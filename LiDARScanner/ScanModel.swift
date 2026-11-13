import ARKit
import AVFoundation
import Combine
import SplatIO
import SwiftUI
import simd

/// UI state and ARSession delegate are main-queue confined. All point-cloud,
/// metadata counters and file operations are confined to `worker`.
/// The single-flight gate retains at most one ARFrame for processing.
final class ScanModel: NSObject, ObservableObject, ARSessionDelegate {
    let session = ARSession()
    @Published var settings = ScanSettings()
    @Published var scanTitle = ""
    @Published var exportFormat: ExportFormat = .binaryPLY
    @Published private(set) var pointCount = 0
    @Published private(set) var activeSeconds: Double = 0
    @Published private(set) var isRecording = false
    @Published private(set) var isBusy = false
    @Published private(set) var ready = false
    @Published private(set) var trackingNormal = false
    @Published private(set) var sessionClosed = false
    @Published private(set) var trackingText = String(localized: "Preparing camera…")
    @Published private(set) var notice = String(localized: "Move slowly and capture surfaces from multiple angles.")
    @Published private(set) var preview: [PCPoint] = []
    @Published private(set) var previewVersion = 0
    @Published private(set) var savedScans: [SavedScan] = []
    @Published var sharedFiles: SharedFiles?
    @Published var errorMessage: String?
    @Published private(set) var cameraDenied = false
    let supported = ARWorldTrackingConfiguration.isSupported &&
        ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)

    private let worker = DispatchQueue(label: "LiDARScanner.cloud", qos: .userInitiated)
    private let cloud: OpaquePointer?
    private var processingFrame = false
    private var lastScheduledTime: TimeInterval = -1
    private var lastPreviewTime: TimeInterval = -1
    private var generation = 0
    private var sessionStarted = false
    private var foreground = true
    private var activeSettings = ScanSettings()
    private var startedAt = Date()
    private var scanID = UUID()
    private var observers: [NSObjectProtocol] = []
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    // Keep room for ARKit, preview creation and a streaming export at scan end.
    private static let captureMemoryReserve = 256 * 1024 * 1024
    // Keep the original reason in metadata; localize only the displayed notice.
    private var closedReason: String?
    private var localizedClosedReason: String?
    // Worker queue only:
    private var workerFrames = 0
    private var workerSeconds: Double = 0
    private var workerLastTimestamp: TimeInterval?
    private var workerWidth = 0
    private var workerHeight = 0
    private var cachedScan: SavedScan?
    private var savedSamples: UInt64 = 0
    private var savedTitle = ""

    override init() {
        cloud = pc_create(ScanSettings().core)
        super.init()
        session.delegate = self
        session.delegateQueue = .main
        observers.append(NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.closeSession(reason: "Die Erfassung wurde wegen einer Speicherwarnung beendet. Für weitere Aufnahmen bitte einen neuen Scan beginnen.")
        })
        refreshArchive()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        session.pause()
        TorchService.shared.turnOff()
        if let cloud { pc_destroy(cloud) }
    }

    func prepare() {
        guard !sessionStarted else { return }
        guard cloud != nil else { errorMessage = String(localized: "Could not allocate point-cloud memory."); return }
        guard supported else {
            trackingText = String(localized: "LiDAR required")
            notice = String(localized: "Scanning requires an iPhone or iPad with a LiDAR sensor. The Simulator cannot capture a scene.")
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: startSession(reset: true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
                DispatchQueue.main.async {
                    if allowed { self?.startSession(reset: true) }
                    else { self?.denyCamera() }
                }
            }
        default: denyCamera()
        }
    }

    private func denyCamera() {
        cameraDenied = true
        trackingText = String(localized: "Camera access required")
        notice = String(localized: "Please allow camera access in the device settings.")
    }

    private func startSession(reset: Bool) {
        guard foreground, supported, AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return }
        let configuration = ARWorldTrackingConfiguration()
        configuration.frameSemantics = [.sceneDepth]
        configuration.worldAlignment = .gravity
        configuration.isLightEstimationEnabled = false
        session.run(configuration, options: reset ? [.resetTracking, .removeExistingAnchors] : [])
        sessionStarted = true
        cameraDenied = false
        ready = true
        trackingNormal = false
        trackingText = String(localized: "Detecting surroundings…")
    }

    func toggleRecording() {
        if isRecording { pauseAndSave(); return }
        guard ready, trackingNormal, !sessionClosed, !isBusy, let cloud else { return }
        if activeSettings.maxPoints > 0 && pointCount >= activeSettings.maxPoints && pointCount > 0 {
            notice = String(localized: "Point limit reached. Please export or start a new scan.")
            return
        }
        guard os_proc_available_memory() >= Self.captureMemoryReserve else {
            notice = String(localized: "Not enough free memory for additional points. Please export the current scan.")
            return
        }
        if pointCount == 0 {
            activeSettings = settings
            let configuration = activeSettings.core
            worker.async { pc_reset(cloud, configuration) }
            startedAt = Date()
        }
        worker.async { self.workerLastTimestamp = nil }
        lastScheduledTime = -1
        isRecording = true
        UIApplication.shared.isIdleTimerDisabled = true
        notice = String(localized: "Scanning. Move the camera slowly and steadily.")
    }

    func pauseAndSave() {
        isRecording = false
        UIApplication.shared.isIdleTimerDisabled = false
        notice = String(localized: "Paused. Camera tracking remains active.")
        saveCurrent(share: false)
    }

    func newScan() {
        guard !isBusy, let cloud else { return }
        TorchService.shared.turnOff()
        isRecording = false
        UIApplication.shared.isIdleTimerDisabled = false
        isBusy = true
        generation += 1
        scanID = UUID(); startedAt = Date(); activeSettings = settings
        let config = settings.core
        worker.async {
            pc_reset(cloud, config)
            self.workerFrames = 0; self.workerSeconds = 0; self.workerLastTimestamp = nil
            self.workerWidth = 0; self.workerHeight = 0
            self.cachedScan = nil; self.savedSamples = 0; self.savedTitle = ""
            DispatchQueue.main.async {
                self.pointCount = 0; self.activeSeconds = 0
                self.preview = []; self.previewVersion += 1
                self.scanTitle = ""; self.sessionClosed = !self.foreground
                self.closedReason = nil
                self.localizedClosedReason = nil
                self.ready = false
                if !self.foreground { self.sessionStarted = false }
                self.lastScheduledTime = -1; self.lastPreviewTime = -1
                self.isBusy = false
                self.notice = String(localized: "New scan. Wait for stable tracking, then start capture.")
                self.startSession(reset: true)
                self.endBackgroundTask()
            }
        }
    }

    func sceneChanged(_ phase: ScenePhase) {
        if phase == .background {
            foreground = false
            closeSession(reason: "Die App war im Hintergrund. Der Scan ist abgeschlossen und bleibt exportierbar.")
        } else if phase == .active {
            foreground = true
            if cameraDenied || !sessionStarted { prepare() }
            else if sessionClosed { notice = String(localized: "Scan complete. Export or start a new scan.") }
        }
    }

    private func closeSession(reason: String, localizedReason: String? = nil) {
        guard !sessionClosed else { return }
        TorchService.shared.turnOff()
        isRecording = false; sessionClosed = true; trackingNormal = false
        UIApplication.shared.isIdleTimerDisabled = false
        session.pause()
        trackingText = String(localized: "Scan complete")
        closedReason = reason
        let message = localizedReason ?? NSLocalizedString(reason, comment: "Capture session closure notice")
        localizedClosedReason = message
        notice = message
        beginBackgroundTask()
        if !isBusy { saveCurrent(share: false) }
        // An already-running save owns completion and ends the background task.
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        updateTracking(frame.camera.trackingState)
        guard isRecording, !isBusy, !processingFrame, !sessionClosed, let cloud else { return }
        guard case .normal = frame.camera.trackingState else { return }
        guard frame.timestamp - lastScheduledTime >= 0.15 else { return }
        guard os_proc_available_memory() >= Self.captureMemoryReserve else {
            closeSession(reason: "Die Erfassung wurde wegen knappen Arbeitsspeichers beendet. Für weitere Aufnahmen bitte einen neuen Scan beginnen.")
            return
        }
        processingFrame = true
        lastScheduledTime = frame.timestamp
        let thisGeneration = generation
        let makePreview = frame.timestamp - lastPreviewTime >= 0.5
        if makePreview { lastPreviewTime = frame.timestamp }
        worker.async {
            do {
                let result = try DepthProcessor.process(frame, cloud: cloud, makePreview: makePreview)
                self.workerFrames += 1
                if let last = self.workerLastTimestamp {
                    self.workerSeconds += min(0.5, max(0, frame.timestamp - last))
                }
                self.workerLastTimestamp = frame.timestamp
                self.workerWidth = result.width; self.workerHeight = result.height
                let seconds = self.workerSeconds
                DispatchQueue.main.async {
                    self.processingFrame = false
                    guard thisGeneration == self.generation else { return }
                    self.pointCount = Int(result.stats.pointCount)
                    self.activeSeconds = seconds
                    if let points = result.preview { self.preview = points; self.previewVersion += 1 }
                    if self.isRecording && os_proc_available_memory() < Self.captureMemoryReserve {
                        self.closeSession(reason: "Die Erfassung wurde wegen knappen Arbeitsspeichers beendet. Für weitere Aufnahmen bitte einen neuen Scan beginnen.")
                    } else if result.stats.atCapacity != 0 && self.isRecording {
                        self.pauseAndSave()
                        self.notice = String(localized: "Point limit reached. Saving the scan; all captured points are retained.")
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.processingFrame = false
                    guard thisGeneration == self.generation else { return }
                    self.notice = error.localizedDescription
                    if frame.sceneDepth != nil {
                        self.isRecording = false
                        UIApplication.shared.isIdleTimerDisabled = false
                        self.saveCurrent(share: false)
                    }
                }
            }
        }
    }

    private func updateTracking(_ state: ARCamera.TrackingState) {
        guard !sessionClosed else { return }
        switch state {
        case .normal: trackingNormal = true; trackingText = String(localized: "Tracking stable")
        case .notAvailable: trackingNormal = false; trackingText = String(localized: "Tracking unavailable")
        case .limited(let reason):
            trackingNormal = false
            switch reason {
            case .initializing: trackingText = String(localized: "Detecting surroundings…")
            case .excessiveMotion: trackingText = String(localized: "Please move more slowly")
            case .insufficientFeatures: trackingText = String(localized: "More texture or light required")
            case .relocalizing:
                // Previously accumulated points cannot be retrospectively corrected.
                closeSession(reason: "Tracking musste neu lokalisiert werden. Für weitere Aufnahmen bitte einen neuen Scan beginnen.")
            @unknown default: trackingText = String(localized: "Tracking limited")
            }
        }
    }

    func sessionWasInterrupted(_ session: ARSession) {
        closeSession(reason: "Die Kamera wurde unterbrochen. Für weitere Aufnahmen bitte einen neuen Scan beginnen.")
    }
    func session(_ session: ARSession, didFailWithError error: Error) {
        closeSession(reason: "Kamera beendet: " + error.localizedDescription,
                     localizedReason: String(localized: "Camera stopped: \(error.localizedDescription)"))
    }
    func sessionShouldAttemptRelocalization(_ session: ARSession) -> Bool { false }

    func leaveMode() {
        guard !isBusy, !isRecording else { return }
        TorchService.shared.turnOff()
        if pointCount > 0 {
            closeSession(reason: "The scan mode was changed. This capture is complete.")
        } else {
            session.pause()
            trackingNormal = false
        }
        foreground = false
    }

    func enterMode() {
        foreground = true
        if !sessionStarted {
            prepare()
        } else if pointCount == 0 {
            sessionClosed = false
            startSession(reset: true)
            notice = String(localized: "Move slowly and capture surfaces from multiple angles.")
        } else if !sessionClosed {
            startSession(reset: false)
        } else {
            notice = String(localized: "Scan complete. Export or start a new scan.")
        }
    }

    func exportReport() {
        saveCurrent(share: false, report: true)
    }

    func exportGaussians() {
        guard !isBusy, let cloud else { return }
        isRecording = false
        UIApplication.shared.isIdleTimerDisabled = false
        isBusy = true
        Task {
            do {
                let plyURL = try await makeGaussianExportURL(cloud: cloud)
                await MainActor.run {
                    self.isBusy = false
                    self.sharedFiles = SharedFiles(urls: [plyURL])
                    self.notice = String(localized: "3D Gaussian Splats exported successfully.")
                }
            } catch {
                await MainActor.run {
                    self.isBusy = false
                    self.errorMessage = String(localized: "Exporting Gaussians failed: \(error.localizedDescription)")
                }
            }
        }
    }

    func makeGaussianExportURL() async throws -> URL {
        guard let cloud else { throw ScanImportError.emptyPointCloud }
        return try await makeGaussianExportURL(cloud: cloud)
    }

    private func makeGaussianExportURL(cloud: OpaquePointer) async throws -> URL {
        let cleanTitle = await MainActor.run { scanTitle.trimmingCharacters(in: .whitespacesAndNewlines) }
        let title = cleanTitle.isEmpty ? "LiDAR-Scan" : cleanTitle
        let points: [PCPoint] = try await withCheckedThrowingContinuation { continuation in
            worker.async {
                let stats = pc_stats(cloud)
                guard stats.pointCount > 0 else {
                    continuation.resume(throwing: ScanImportError.emptyPointCloud)
                    return
                }
                let count = Int(stats.pointCount)
                var copied = [PCPoint](repeating: PCPoint(), count: count)
                let written = copied.withUnsafeMutableBufferPointer { pc_copy_preview(cloud, $0.baseAddress, $0.count) }
                if written < count { copied.removeLast(count - written) }
                continuation.resume(returning: copied)
            }
        }
        return try await Self.writeGaussians(from: points, title: title)
    }

    static func writeGaussians(from points: [PCPoint], title: String) async throws -> URL {
        guard !points.isEmpty else { throw ScanImportError.emptyPointCloud }
        let safeTitle = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
        let fileStem = safeTitle.isEmpty ? "LiDAR-Scan" : safeTitle
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let plyURL = tempDir.appendingPathComponent("\(fileStem)-gaussians.ply")
        let splatPoints = PCPoint.toSplatPoints(points)
        let writer = try SplatPLYSceneWriter(to: .file(plyURL))
        try await writer.start(sphericalHarmonicDegree: 0, binary: true, pointCount: splatPoints.count)
        try await writer.write(splatPoints)
        try await writer.close()
        return plyURL
    }

    func saveCurrent(share: Bool, report: Bool = false) {
        guard !isBusy, let cloud else { return }
        isRecording = false
        UIApplication.shared.isIdleTimerDisabled = false
        isBusy = true
        let cleanTitle = scanTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = cleanTitle.isEmpty ? "LiDAR-Scan" : cleanTitle
        let id = scanID, start = startedAt, config = activeSettings
        let device = UIDevice.current.model, system = UIDevice.current.systemVersion
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let appBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let note = sessionClosed
            ? "Capture session closed; not resumable. " + (closedReason ?? "")
            : "Capture paused; ARSession remained active."
        let format = share ? exportFormat : .binaryPLY
        worker.async {
            do {
                let stats = pc_stats(cloud)
                guard stats.pointCount > 0 else {
                    DispatchQueue.main.async { self.isBusy = false; self.endBackgroundTask() }
                    return
                }
                let saved: SavedScan
                if let cached = self.cachedScan, self.savedSamples == stats.acceptedSamples,
                   self.savedTitle == title, cached.metadata.sessionNote == note, FileManager.default.fileExists(atPath: cached.directory.path) {
                    saved = cached
                    if !FileManager.default.fileExists(atPath: saved.url(for: format).path) {
                        try ScanStorage.writeCloud(cloud, to: saved.url(for: format), format: format)
                    }
                } else {
                    let metadata = ScanMetadata(schemaVersion: 1, appVersion: appVersion, appBuild: appBuild,
                        scanID: id, title: title, startedAt: start, savedAt: Date(), pointCount: Int(stats.pointCount),
                        acceptedSamples: stats.acceptedSamples, processedFrames: self.workerFrames,
                        activeSeconds: self.workerSeconds, settings: config, deviceModel: device,
                        systemVersion: system, depthWidth: self.workerWidth, depthHeight: self.workerHeight,
                        unit: "metre", coordinateSystem: "Local right-handed Cartesian; Z up; no CRS/EPSG; no north alignment",
                        arkitToExportRowMajor: [1,0,0,0, 0,0,-1,0, 0,1,0,0, 0,0,0,1],
                        depthSource: "ARFrame.sceneDepth; Apple-fused LiDAR and RGB depth; not raw laser returns; no smoothedSceneDepth",
                        confidenceMeaning: "ARConfidenceLevel: 0 low, 1 medium, 2 high; categorical, not metric uncertainty",
                        pointSelection: "One observation per world voxel; first sample retained unless higher confidence arrives; no averaging or surface reconstruction",
                        colorSource: "ARFrame.capturedImage; YCbCr to RGB; 601/709 attachment, 601 fallback; full/video range; not radiometrically calibrated",
                        sessionNote: note)
                    saved = try ScanStorage.save(cloud, metadata: metadata, format: format)
                    self.cachedScan = saved; self.savedSamples = stats.acceptedSamples; self.savedTitle = title
                }
                var snapshot = [PCPoint](repeating: PCPoint(), count: min(40_000, Int(stats.pointCount)))
                _ = snapshot.withUnsafeMutableBufferPointer { pc_copy_preview(cloud, $0.baseAddress, $0.count) }
                let archive = try ScanStorage.list()
                let reportURL = report ? try ScanReport.pointCloud(saved) : nil
                DispatchQueue.main.async {
                    self.pointCount = Int(stats.pointCount)
                    self.preview = snapshot; self.previewVersion += 1
                    self.savedScans = archive; self.isBusy = false
                    self.notice = self.sessionClosed
                        ? String(localized: "Scan saved on this device. \(self.localizedClosedReason ?? "")")
                        : String(localized: "Scan saved on this device.")
                    if share { self.sharedFiles = SharedFiles(urls: [saved.url(for: format), saved.metadataURL]) }
                    if let reportURL { self.sharedFiles = SharedFiles(urls: [reportURL]) }
                    self.endBackgroundTask()
                }
            } catch {
                DispatchQueue.main.async {
                    self.isBusy = false
                    self.errorMessage = String(localized: "Saving failed: \(error.localizedDescription)")
                    self.notice = String(localized: "The points remain in memory. Please try saving again.")
                    self.endBackgroundTask()
                }
            }
        }
    }

    func refreshArchive() {
        worker.async {
            do {
                let scans = try ScanStorage.list()
                DispatchQueue.main.async { self.savedScans = scans }
            } catch { DispatchQueue.main.async { self.errorMessage = error.localizedDescription } }
        }
    }

    func delete(_ scan: SavedScan) {
        worker.async {
            do {
                try FileManager.default.removeItem(at: scan.directory)
                if self.cachedScan?.id == scan.id { self.cachedScan = nil }
                let scans = try ScanStorage.list()
                DispatchQueue.main.async { self.savedScans = scans }
            } catch { DispatchQueue.main.async { self.errorMessage = error.localizedDescription } }
        }
    }

    func importScan(from url: URL) async throws -> SavedScan {
        let scan = try await Task.detached(priority: .userInitiated) {
            try ScanImporter.importScan(from: url)
        }.value
        refreshArchive()
        return scan
    }

    func notifyImported(_ scan: SavedScan) {
        notice = String(format: String(localized: "Imported scan: %@"), scan.metadata.title)
    }

    func loadPreview(for scan: SavedScan) async -> [PCPoint] {
        await Task.detached(priority: .userInitiated) {
            ScanStorage.readPreview(for: scan)
        }.value
    }

    private func beginBackgroundTask() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Save point cloud") { [weak self] in
            self?.endBackgroundTask()
        }
    }
    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
}
