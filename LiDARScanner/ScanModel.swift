import ARKit
import AVFoundation
import Combine
import SwiftUI

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
    @Published private(set) var trackingText = "Kamera wird vorbereitet …"
    @Published private(set) var notice = "Langsam bewegen und Flächen aus mehreren Blickwinkeln erfassen."
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
    private var closedReason: String?
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
        if let cloud { pc_destroy(cloud) }
    }

    func prepare() {
        guard !sessionStarted else { return }
        guard cloud != nil else { errorMessage = "Punktspeicher konnte nicht angelegt werden."; return }
        guard supported else {
            trackingText = "LiDAR erforderlich"
            notice = "Scannen benötigt ein iPhone oder iPad mit LiDAR-Sensor. Der Simulator kann keine Szene erfassen."
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
        trackingText = "Kamerazugriff fehlt"
        notice = "Bitte den Kamerazugriff in den Geräteeinstellungen erlauben."
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
        trackingText = "Umgebung wird erkannt …"
    }

    func toggleRecording() {
        if isRecording { pauseAndSave(); return }
        guard ready, trackingNormal, !sessionClosed, !isBusy, let cloud else { return }
        if activeSettings.maxPoints > 0 && pointCount >= activeSettings.maxPoints && pointCount > 0 {
            notice = "Punktlimit erreicht. Bitte exportieren oder einen neuen Scan beginnen."
            return
        }
        guard os_proc_available_memory() >= Self.captureMemoryReserve else {
            notice = "Zu wenig freier Arbeitsspeicher für weitere Punkte. Bitte vorhandenen Scan exportieren."
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
        notice = "Scan läuft. Kamera langsam und gleichmäßig bewegen."
    }

    func pauseAndSave() {
        isRecording = false
        UIApplication.shared.isIdleTimerDisabled = false
        notice = "Pausiert. Die Kameraposition wird weiter verfolgt."
        saveCurrent(share: false)
    }

    func newScan() {
        guard !isBusy, let cloud else { return }
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
                self.ready = false
                if !self.foreground { self.sessionStarted = false }
                self.lastScheduledTime = -1; self.lastPreviewTime = -1
                self.isBusy = false
                self.notice = "Neuer Scan. Auf stabiles Tracking warten und Aufnahme starten."
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
            else if sessionClosed { notice = "Scan abgeschlossen. Exportieren oder einen neuen Scan beginnen." }
        }
    }

    private func closeSession(reason: String) {
        guard !sessionClosed else { return }
        isRecording = false; sessionClosed = true; trackingNormal = false
        UIApplication.shared.isIdleTimerDisabled = false
        session.pause()
        trackingText = "Scan abgeschlossen"
        closedReason = reason
        notice = reason
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
                        self.notice = "Punktlimit erreicht. Der Scan wird gesichert; alle erfassten Punkte bleiben erhalten."
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
        case .normal: trackingNormal = true; trackingText = "Tracking stabil"
        case .notAvailable: trackingNormal = false; trackingText = "Tracking nicht verfügbar"
        case .limited(let reason):
            trackingNormal = false
            switch reason {
            case .initializing: trackingText = "Umgebung wird erkannt …"
            case .excessiveMotion: trackingText = "Bitte langsamer bewegen"
            case .insufficientFeatures: trackingText = "Mehr Struktur oder Licht erforderlich"
            case .relocalizing:
                // Previously accumulated points cannot be retrospectively corrected.
                closeSession(reason: "Tracking musste neu lokalisiert werden. Für weitere Aufnahmen bitte einen neuen Scan beginnen.")
            @unknown default: trackingText = "Tracking eingeschränkt"
            }
        }
    }

    func sessionWasInterrupted(_ session: ARSession) {
        closeSession(reason: "Die Kamera wurde unterbrochen. Für weitere Aufnahmen bitte einen neuen Scan beginnen.")
    }
    func session(_ session: ARSession, didFailWithError error: Error) {
        closeSession(reason: "Kamera beendet: " + error.localizedDescription)
    }
    func sessionShouldAttemptRelocalization(_ session: ARSession) -> Bool { false }

    func saveCurrent(share: Bool) {
        guard !isBusy, let cloud else { return }
        isRecording = false
        UIApplication.shared.isIdleTimerDisabled = false
        isBusy = true
        let cleanTitle = scanTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = cleanTitle.isEmpty ? "LiDAR-Scan" : cleanTitle
        let id = scanID, start = startedAt, config = activeSettings
        let device = UIDevice.current.model, system = UIDevice.current.systemVersion
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
                   self.savedTitle == title, FileManager.default.fileExists(atPath: cached.directory.path) {
                    saved = cached
                    if !FileManager.default.fileExists(atPath: saved.url(for: format).path) {
                        try ScanStorage.writeCloud(cloud, to: saved.url(for: format), format: format)
                    }
                } else {
                    let metadata = ScanMetadata(schemaVersion: 1, appVersion: "1.0.0", scanID: id, title: title,
                        startedAt: start, savedAt: Date(), pointCount: Int(stats.pointCount),
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
                DispatchQueue.main.async {
                    self.pointCount = Int(stats.pointCount)
                    self.preview = snapshot; self.previewVersion += 1
                    self.savedScans = archive; self.isBusy = false
                    self.notice = self.sessionClosed
                        ? "Scan auf diesem Gerät gesichert. " + (self.closedReason ?? "")
                        : "Scan auf diesem Gerät gesichert."
                    if share { self.sharedFiles = SharedFiles(urls: [saved.url(for: format), saved.metadataURL]) }
                    self.endBackgroundTask()
                }
            } catch {
                DispatchQueue.main.async {
                    self.isBusy = false
                    self.errorMessage = "Speichern fehlgeschlagen: " + error.localizedDescription
                    self.notice = "Die Punkte bleiben im Arbeitsspeicher. Bitte erneut sichern."
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

    private func beginBackgroundTask() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Scan sichern") { [weak self] in
            self?.endBackgroundTask()
        }
    }
    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
}
