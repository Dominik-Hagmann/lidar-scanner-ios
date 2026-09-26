import ARKit
import AVFoundation
import Combine
import SwiftUI

/// ARSession and published state live on the main queue. File I/O, seed-cloud
/// access and the native engine share one serial worker; no two trainers coexist.
final class GaussianModel: NSObject, ObservableObject, ARSessionDelegate {
    let session = ARSession()
    @Published private(set) var current: GaussianProject?
    @Published private(set) var archive: [GaussianProject] = []
    @Published private(set) var isRecording = false
    @Published private(set) var isBusy = false
    @Published private(set) var cameraReady = false
    @Published private(set) var trackingNormal = false
    @Published private(set) var cameraDenied = false
    @Published private(set) var status = String(localized: "Move slowly around your subject.")
    @Published var errorMessage: String?
    @Published var sharing: SharedFiles?
    let supported = ARWorldTrackingConfiguration.isSupported && ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)

    private let worker = DispatchQueue(label: "LiDARScanner.gaussian", qos: .userInitiated)
    private let stop = GaussianStopSignal()
    private var store: GaussianStore?
    private var seed: OpaquePointer?
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var frameInFlight = false
    private var lastTime: Double = -Double.infinity
    private var lastPose: simd_float4x4?
    private var foreground = true
    private var memoryObserver: NSObjectProtocol?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    override init() {
        super.init()
        session.delegate = self; session.delegateQueue = .main
        memoryObserver = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                if self.isRecording { self.finish(reason: "memory_warning", process: false) }
                else if self.isBusy { self.stop.set("memory_warning") }
            }
        refreshArchive()
    }
    deinit {
        if let memoryObserver { NotificationCenter.default.removeObserver(memoryObserver) }
        session.pause()
        if let seed { pc_destroy(seed) }
    }

    func prepare() {
        guard foreground, current == nil, !cameraReady else { return }
        guard supported else {
            status = String(localized: "Scanning requires an iPhone or iPad with a LiDAR sensor. The Simulator cannot capture a scene.")
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: startCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
                DispatchQueue.main.async {
                    if allowed { self?.startCamera() } else { self?.cameraDenied = true }
                }
            }
        default: cameraDenied = true; status = String(localized: "Please allow camera access in the device settings.")
        }
    }
    private func startCamera() {
        guard foreground, current == nil else { return }
        let configuration = ARWorldTrackingConfiguration()
        configuration.frameSemantics = [.sceneDepth]; configuration.worldAlignment = .gravity
        configuration.isLightEstimationEnabled = false
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        cameraReady = true; cameraDenied = false
    }

    func begin() {
        guard !isBusy, !isRecording, current == nil, cameraReady, trackingNormal else { return }
        isBusy = true; lastPose = nil; lastTime = -Double.infinity
        let now = Date()
        let project = GaussianProject(id: UUID(), startedAt: now, updatedAt: now,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            device: Self.deviceIdentifier(), operatingSystem: UIDevice.current.systemVersion)
        worker.async {
            do {
                if let seed = self.seed { pc_destroy(seed) }
                self.seed = pc_create(GaussianCapture.seedConfiguration())
                guard self.seed != nil else { throw GaussianError.message(String(localized: "Could not allocate point-cloud memory.")) }
                self.store = try GaussianStore(project: project)
                DispatchQueue.main.async {
                    self.current = project; self.isBusy = false
                    if self.foreground {
                        self.isRecording = true; UIApplication.shared.isIdleTimerDisabled = true
                        self.status = String(localized: "Move slowly around your subject. Tap Finish when you have covered it.")
                    } else {
                        self.finish(reason: "app_background", process: false)
                    }
                }
            } catch { self.fail(error) }
        }
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        if case .normal = frame.camera.trackingState { trackingNormal = true } else { trackingNormal = false }
        guard isRecording else { return }
        let reason: String?
        if !trackingNormal { reason = "tracking_limited" }
        else if frameInFlight { reason = "writer_busy" }
        else if frame.timestamp - lastTime < GaussianCapture.interval { reason = "interval" }
        else if !GaussianCapture.needsView(frame.camera.transform, after: lastPose) { reason = "similar_view" }
        else { reason = nil }
        if let reason {
            let timestamp = frame.timestamp
            worker.async {
                do { try self.store?.decision(reason, timestamp: timestamp) }
                catch { self.fail(error) }
            }
            if !trackingNormal { status = String(localized: "Move more slowly and aim at a well-lit, textured surface.") }
            return
        }
        guard os_proc_available_memory() >= 256 * 1024 * 1024 else {
            finish(reason: "capture_memory_reserve", process: false); return
        }
        frameInFlight = true; lastTime = frame.timestamp; lastPose = frame.camera.transform
        worker.async {
            do {
                guard let store = self.store, let seed = self.seed else { return }
                let volume = try store.directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
                guard (volume.volumeAvailableCapacityForImportantUsage ?? 0) > 512 * 1024 * 1024 else {
                    throw GaussianError.message(String(localized: "Storage is nearly full. The captured images have been saved."))
                }
                try autoreleasepool { try GaussianCapture.write(frame, store: store, context: self.context, cloud: seed) }
                let snapshot = store.project
                DispatchQueue.main.async {
                    self.frameInFlight = false; self.current = snapshot
                    if self.isRecording { self.status = String(localized: "Move slowly around your subject. Tap Finish when you have covered it.") }
                }
            } catch {
                do {
                    self.store?.project.lastIssue = error.localizedDescription
                    try self.store?.event("capture_frame_failed", ["arTimestamp": "\(frame.timestamp)", "error": error.localizedDescription])
                    try self.store?.save()
                } catch { self.fail(error); return }
                DispatchQueue.main.async {
                    self.frameInFlight = false; self.finish(reason: "capture_error", process: false)
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func finish(reason: String = "user_finished", process: Bool = true) {
        guard isRecording || (!isBusy && current?.phase == .capturing) else { return }
        if process && (current?.frames.count ?? 0) < 12 {
            status = String(localized: "Capture a few more views before finishing. Move around the subject.")
            return
        }
        isRecording = false; isBusy = true; cameraReady = false; session.pause()
        status = String(localized: "Saving your capture…")
        stop.reset()
        if !process { stop.set(reason) }
        worker.async {
            do {
                guard let store = self.store else { return }
                store.project.phase = .captured
                try store.event("capture_finished", ["reason": reason, "savedViews": "\(store.project.frames.count)"])
                try store.saveDataset()
                if let seed = self.seed { pc_destroy(seed); self.seed = nil }
                self.publish(store.project)
                if process { try self.process(store) }
                else { self.finished(store.project) }
            } catch { self.fail(error) }
        }
    }

    func resume() {
        guard !isBusy, !isRecording, let project = current, project.phase != .completed else { return }
        isBusy = true; stop.reset(); UIApplication.shared.isIdleTimerDisabled = true
        worker.async {
            do {
                guard let store = self.store else { return }
                try self.process(store)
            } catch { self.fail(error) }
        }
    }
    private func process(_ store: GaussianStore) throws {
        DispatchQueue.main.async { UIApplication.shared.isIdleTimerDisabled = true }
        try GaussianProcessor.run(store: store, stop: stop) { self.publish($0) }
        finished(store.project)
    }
    func pause() {
        stop.set("user_paused")
        status = String(localized: "Saving progress…")
    }
    func newCapture() {
        guard !isBusy, !isRecording else { return }
        current = nil; trackingNormal = false; cameraReady = false
        worker.async { self.store = nil }
        status = String(localized: "Move slowly around your subject.")
        prepare()
    }
    func leaveMode() {
        guard !isBusy, !isRecording else { return }
        session.pause(); cameraReady = false; trackingNormal = false; foreground = false
    }
    func enterMode() { foreground = true; prepare(); refreshArchive() }
    func sceneChanged(_ phase: ScenePhase) {
        if phase != .active {
            foreground = false
            if isRecording { beginBackgroundTask(); finish(reason: "app_inactive", process: false) }
            else if isBusy { beginBackgroundTask(); stop.set("app_inactive") }
            session.pause(); cameraReady = false
        } else { foreground = true; prepare() }
    }
    func sessionWasInterrupted(_ session: ARSession) {
        if isRecording { finish(reason: "camera_interrupted", process: false) }
    }
    func session(_ session: ARSession, didFailWithError error: Error) {
        if isRecording { finish(reason: "camera_failed", process: false) }
        errorMessage = error.localizedDescription
    }
    func sessionShouldAttemptRelocalization(_ session: ARSession) -> Bool { false }

    func refreshArchive() {
        worker.async {
            do { let scans = try GaussianStore.list(); DispatchQueue.main.async { self.archive = scans } }
            catch { DispatchQueue.main.async { self.errorMessage = error.localizedDescription } }
        }
    }
    func open(_ project: GaussianProject) {
        guard !isBusy, !isRecording else { return }
        isBusy = true; session.pause(); cameraReady = false
        worker.async {
            do {
                self.store = try GaussianStore(project: project, opening: true)
                if let store = self.store { self.finished(store.project) }
            } catch { self.fail(error) }
        }
    }
    func delete(_ project: GaussianProject) {
        guard !isBusy, !isRecording else { return }
        isBusy = true
        worker.async {
            do {
                if self.store?.project.id == project.id { self.store = nil }
                try FileManager.default.removeItem(at: project.directory)
                let scans = try GaussianStore.list()
                DispatchQueue.main.async {
                    self.archive = scans; self.isBusy = false
                    if self.current?.id == project.id { self.newCapture() }
                }
            } catch { self.fail(error) }
        }
    }
    enum ShareKind { case scene, capture, report, log }
    func share(_ kind: ShareKind) {
        guard !isBusy, !isRecording, current != nil else { return }
        isBusy = true
        worker.async {
            do {
                guard let store = self.store else { return }
                try store.event("export_requested", ["kind": "\(kind)"])
                try store.save()
                let urls: [URL]
                switch kind {
                case .scene:
                    guard store.project.hasResult else { throw GaussianError.message(String(localized: "The 3D scene is not ready yet.")) }
                    urls = [store.project.resultURL, store.directory.appendingPathComponent("scan.json")]
                case .capture: urls = [try store.exportInputs()]
                case .log: urls = [store.directory.appendingPathComponent("scan.json"), store.directory.appendingPathComponent("events.jsonl")]
                case .report: urls = [try ScanReport.gaussian(store.project)]
                }
                let snapshot = store.project
                DispatchQueue.main.async { self.current = snapshot; self.isBusy = false; self.sharing = SharedFiles(urls: urls) }
            } catch { self.fail(error) }
        }
    }
    private func publish(_ project: GaussianProject) {
        DispatchQueue.main.async { self.current = project; self.status = project.phase.title }
    }
    private func finished(_ project: GaussianProject) {
        let scans = (try? GaussianStore.list()) ?? []
        DispatchQueue.main.async {
            self.current = project; self.archive = scans; self.isBusy = false
            self.status = project.phase.title; UIApplication.shared.isIdleTimerDisabled = false
            self.endBackgroundTask()
        }
    }
    private func fail(_ error: Error) {
        // Call on the worker. Do not convert a share/report failure into a failed reconstruction.
        if let store, [.capturing, .preparing, .training].contains(store.project.phase) {
            store.project.phase = .failed; store.project.lastIssue = error.localizedDescription
            do { try store.event("failure", ["error": error.localizedDescription]); try store.save() }
            catch { DispatchQueue.main.async { self.status = String(localized: "The scan log could not be saved. Check available storage.") } }
        }
        let snapshot = store?.project
        DispatchQueue.main.async {
            self.current = snapshot; self.isBusy = false; self.isRecording = false
            self.errorMessage = snapshot?.phase == .failed
                ? String(localized: "Could not complete processing. Your saved capture is available in the archive. See Details for the recorded error.")
                : error.localizedDescription
            UIApplication.shared.isIdleTimerDisabled = false; self.endBackgroundTask()
        }
    }
    private func beginBackgroundTask() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Save Gaussian progress") { [weak self] in
            self?.stop.set("background_time_expired"); self?.endBackgroundTask()
        }
    }
    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask); backgroundTask = .invalid
    }
    private static func deviceIdentifier() -> String {
        var size = 0; sysctlbyname("hw.machine", nil, &size, nil, 0)
        var bytes = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &bytes, &size, nil, 0)
        return size > 0 ? String(cString: bytes) : UIDevice.current.model
    }
}
