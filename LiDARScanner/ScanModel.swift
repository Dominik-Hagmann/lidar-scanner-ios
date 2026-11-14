import ARKit
import AVFoundation
import Combine
import SwiftUI
import simd

/// UI state and ARSession delegate are main-queue confined. All point-cloud,
/// metadata counters and file operations are confined to `worker`.
/// The single-flight gate retains at most one ARFrame for processing.
final class ScanModel: NSObject, ObservableObject, ARSessionDelegate {
    let session = ARSession()
    @Published var settings = ScanSettings() {
        didSet { LocationService.shared.isEnabled = settings.recordLocation }
    }
    @Published var scanTitle = ""
    @Published var exportFormat: ExportFormat = .binaryPLY
    @Published var meshExportFormat: MeshExportFormat = .obj
    @Published private(set) var pointCount = 0
    @Published private(set) var activeSeconds: Double = 0
    @Published private(set) var processedFrames = 0
    @Published private(set) var acceptedSamples: UInt64 = 0
    @Published private(set) var depthWidth = 0
    @Published private(set) var depthHeight = 0
    @Published private(set) var savedScanDetail: SavedScan?
    @Published private(set) var isRecording = false
    @Published private(set) var isBusy = false
    @Published private(set) var ready = false
    @Published private(set) var trackingNormal = false
    @Published private(set) var sessionClosed = false
    @Published private(set) var trackingText = LanguageManager.string("Preparing camera…")
    @Published private(set) var notice = LanguageManager.string("Move slowly and capture surfaces from multiple angles.")
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
    private var trackingPhrase = L10nPhrase("Preparing camera…")
    private var noticePhrase = L10nPhrase("Move slowly and capture surfaces from multiple angles.")
    private var closedReasonPhrase: L10nPhrase?
    private var cancellables: Set<AnyCancellable> = []
    private var meshAnchors: [UUID: ARMeshAnchor] = [:]
    private var meshChunkVersions: [UUID: Int] = [:]
    private var meshReconstructionActive = false
    @Published private(set) var meshVersion = 0
    private var lastMeshPublishTime: TimeInterval = 0
    var hasMesh: Bool { !meshAnchors.isEmpty }
    @Published var activeGroundControlPoints: [GroundControlPoint] = []
    @Published var activeAnnotations: [CloudAnnotation] = []
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
        LanguageManager.shared.$selection
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshLocalizedText()
            }
            .store(in: &cancellables)
        refreshArchive()
    }

    private func setTracking(_ key: String) {
        trackingPhrase = L10nPhrase(key)
        trackingText = trackingPhrase.localized
    }

    private func setNotice(_ key: String, _ args: String...) {
        noticePhrase = L10nPhrase(key, args)
        notice = noticePhrase.localized
    }

    private func refreshLocalizedText() {
        trackingText = trackingPhrase.localized
        if let closedReasonPhrase {
            localizedClosedReason = closedReasonPhrase.localized
            if noticePhrase.key == "Scan saved on this device. %@" {
                noticePhrase = L10nPhrase("Scan saved on this device. %@", [closedReasonPhrase.localized])
            } else {
                noticePhrase = closedReasonPhrase
            }
        }
        notice = noticePhrase.localized
        objectWillChange.send()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        session.pause()
        TorchService.shared.turnOff()
        if let cloud { pc_destroy(cloud) }
    }

    func prepare() {
        guard !sessionStarted else { return }
        guard cloud != nil else { errorMessage = LanguageManager.string("Could not allocate point-cloud memory."); return }
        guard supported else {
            setTracking("LiDAR required")
            setNotice("Scanning requires an iPhone or iPad with a LiDAR sensor. The Simulator cannot capture a scene.")
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
        setTracking("Camera access required")
        setNotice("Please allow camera access in the device settings.")
    }

    private func makeConfiguration(meshReconstruction: Bool) -> ARWorldTrackingConfiguration {
        let configuration = ARWorldTrackingConfiguration()
        configuration.frameSemantics = [.sceneDepth]
        if meshReconstruction, ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            configuration.sceneReconstruction = .mesh
        }
        configuration.worldAlignment = .gravity
        configuration.isLightEstimationEnabled = false
        return configuration
    }

    private func startSession(reset: Bool) {
        guard foreground, supported, AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return }
        if reset {
            meshAnchors.removeAll()
            meshChunkVersions.removeAll()
            meshReconstructionActive = false
            meshVersion += 1
        }
        let configuration = makeConfiguration(meshReconstruction: meshReconstructionActive)
        session.run(configuration, options: reset ? [.resetTracking, .removeExistingAnchors] : [])
        sessionStarted = true
        cameraDenied = false
        ready = true
        trackingNormal = false
        setTracking("Detecting surroundings…")
    }

    func toggleRecording() {
        if isRecording { pauseAndSave(); return }
        guard ready, trackingNormal, !sessionClosed, !isBusy, let cloud else { return }
        if activeSettings.maxPoints > 0 && pointCount >= activeSettings.maxPoints && pointCount > 0 {
            setNotice("Point limit reached. Please export or start a new scan.")
            return
        }
        guard os_proc_available_memory() >= Self.captureMemoryReserve else {
            setNotice("Not enough free memory for additional points. Please export the current scan.")
            return
        }
        if pointCount == 0 {
            activeSettings = settings
            let configuration = activeSettings.core
            worker.async { pc_reset(cloud, configuration) }
            startedAt = Date()
            if activeSettings.recordLocation {
                LocationService.shared.isEnabled = true
                LocationService.shared.startUpdating()
            } else {
                LocationService.shared.isEnabled = false
            }
        }
        worker.async { self.workerLastTimestamp = nil }
        lastScheduledTime = -1
        isRecording = true
        if !meshReconstructionActive && ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            meshReconstructionActive = true
            session.run(makeConfiguration(meshReconstruction: true), options: [])
        }
        UIApplication.shared.isIdleTimerDisabled = true
        setNotice("Scanning. Move the camera slowly and steadily.")
    }

    func pauseAndSave() {
        isRecording = false
        LocationService.shared.stopUpdating()
        UIApplication.shared.isIdleTimerDisabled = false
        setNotice("Paused. Camera tracking remains active.")
        saveCurrent(share: false)
    }

    func newScan() {
        guard !isBusy, let cloud else { return }
        TorchService.shared.turnOff()
        isRecording = false
        LocationService.shared.stopUpdating()
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
                self.meshAnchors.removeAll()
                self.meshChunkVersions.removeAll()
                self.meshReconstructionActive = false
                self.meshVersion += 1
                self.activeGroundControlPoints = []
                self.activeAnnotations = []
                self.pointCount = 0; self.activeSeconds = 0
                self.processedFrames = 0; self.acceptedSamples = 0
                self.depthWidth = 0; self.depthHeight = 0
                self.savedScanDetail = nil
                self.preview = []; self.previewVersion += 1
                self.scanTitle = ""; self.sessionClosed = !self.foreground
                self.closedReason = nil
                self.localizedClosedReason = nil
                self.closedReasonPhrase = nil
                self.ready = false
                if !self.foreground { self.sessionStarted = false }
                self.lastScheduledTime = -1; self.lastPreviewTime = -1
                self.isBusy = false
                self.setNotice("New scan. Wait for stable tracking, then start capture.")
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
            else if sessionClosed { setNotice("Scan complete. Export or start a new scan.") }
        }
    }

    private func closeSession(reason: String, reasonPhrase: L10nPhrase? = nil) {
        guard !sessionClosed else { return }
        TorchService.shared.turnOff()
        isRecording = false; sessionClosed = true; trackingNormal = false
        LocationService.shared.stopUpdating()
        UIApplication.shared.isIdleTimerDisabled = false
        session.pause()
        setTracking("Scan complete")
        closedReason = reason
        let phrase = reasonPhrase ?? L10nPhrase(reason)
        closedReasonPhrase = phrase
        let message = phrase.localized
        localizedClosedReason = message
        noticePhrase = phrase
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
                let frames = self.workerFrames
                let samples = result.stats.acceptedSamples
                let width = result.width
                let height = result.height
                DispatchQueue.main.async {
                    self.processingFrame = false
                    guard thisGeneration == self.generation else { return }
                    self.pointCount = Int(result.stats.pointCount)
                    self.activeSeconds = seconds
                    self.processedFrames = frames
                    self.acceptedSamples = samples
                    self.depthWidth = width
                    self.depthHeight = height
                    if let points = result.preview { self.preview = points; self.previewVersion += 1 }
                    if self.isRecording && os_proc_available_memory() < Self.captureMemoryReserve {
                        self.closeSession(reason: "Die Erfassung wurde wegen knappen Arbeitsspeichers beendet. Für weitere Aufnahmen bitte einen neuen Scan beginnen.")
                    } else if result.stats.atCapacity != 0 && self.isRecording {
                        self.pauseAndSave()
                        self.setNotice("Point limit reached. Saving the scan; all captured points are retained.")
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.processingFrame = false
                    guard thisGeneration == self.generation else { return }
                    self.setNotice(error.localizedDescription)
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
        case .normal: trackingNormal = true; setTracking("Tracking stable")
        case .notAvailable: trackingNormal = false; setTracking("Tracking unavailable")
        case .limited(let reason):
            trackingNormal = false
            switch reason {
            case .initializing: setTracking("Detecting surroundings…")
            case .excessiveMotion: setTracking("Please move more slowly")
            case .insufficientFeatures: setTracking("More texture or light required")
            case .relocalizing:
                // Previously accumulated points cannot be retrospectively corrected.
                closeSession(reason: "Tracking musste neu lokalisiert werden. Für weitere Aufnahmen bitte einen neuen Scan beginnen.")
            @unknown default: setTracking("Tracking limited")
            }
        }
    }

    func sessionWasInterrupted(_ session: ARSession) {
        closeSession(reason: "Die Kamera wurde unterbrochen. Für weitere Aufnahmen bitte einen neuen Scan beginnen.")
    }
    func session(_ session: ARSession, didFailWithError error: Error) {
        closeSession(reason: "Kamera beendet: " + error.localizedDescription,
                     reasonPhrase: L10nPhrase("Camera stopped: %@", [error.localizedDescription]))
    }
    func sessionShouldAttemptRelocalization(_ session: ARSession) -> Bool { false }

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        guard isRecording, !isBusy, !sessionClosed else { return }
        var addedMesh = false
        for anchor in anchors {
            if let mesh = anchor as? ARMeshAnchor {
                meshAnchors[mesh.identifier] = mesh
                meshChunkVersions[mesh.identifier, default: 0] += 1
                addedMesh = true
            }
        }
        if addedMesh { meshVersion += 1 }
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        guard isRecording, !isBusy, !sessionClosed else { return }
        var updatedMesh = false
        for anchor in anchors {
            if let mesh = anchor as? ARMeshAnchor {
                meshAnchors[mesh.identifier] = mesh
                meshChunkVersions[mesh.identifier, default: 0] += 1
                updatedMesh = true
            }
        }
        if updatedMesh {
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastMeshPublishTime >= 0.4 {
                lastMeshPublishTime = now
                meshVersion += 1
            }
        }
    }

    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        guard isRecording, !isBusy, !sessionClosed else { return }
        var removedMesh = false
        for anchor in anchors {
            if let mesh = anchor as? ARMeshAnchor {
                meshAnchors.removeValue(forKey: mesh.identifier)
                meshChunkVersions.removeValue(forKey: mesh.identifier)
                removedMesh = true
            }
        }
        if removedMesh { meshVersion += 1 }
    }

    func meshAnchorEntries() -> [(id: UUID, anchor: ARMeshAnchor, version: Int)] {
        meshAnchors.map { (id: $0.key, anchor: $0.value, version: meshChunkVersions[$0.key] ?? 0) }
    }

    func currentMeshPreviewData() -> MeshPreviewData? {
        guard !meshAnchors.isEmpty else { return nil }
        let data = MeshPreviewData.fromAnchors(Array(meshAnchors.values))
        return data.isEmpty ? nil : data
    }

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
            setNotice("Move slowly and capture surfaces from multiple angles.")
        } else if !sessionClosed {
            startSession(reset: false)
        } else {
            setNotice("Scan complete. Export or start a new scan.")
        }
    }

    func exportReport(format: ReportFormat = .pdf) {
        saveCurrent(share: false, reportFormat: format)
    }

    func saveCurrent(share: Bool, reportFormat: ReportFormat? = nil, shareMesh: Bool = false, meshFormat: MeshExportFormat? = nil) {
        guard !isBusy, let cloud else { return }
        isRecording = false
        LocationService.shared.stopUpdating()
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
        let resolvedMeshFormat = meshFormat ?? meshExportFormat
        let recordedLocation = config.recordLocation ? LocationService.shared.currentLocation : nil
        let currentMeshAnchors = Array(meshAnchors.values)
        let currentGCPs = activeGroundControlPoints
        let currentAnnotations = activeAnnotations
        worker.async {
            do {
                let stats = pc_stats(cloud)
                guard stats.pointCount > 0 else {
                    DispatchQueue.main.async { self.isBusy = false; self.endBackgroundTask() }
                    return
                }
                let previousSavedSamples = self.savedSamples
                var saved: SavedScan
                if let cached = self.cachedScan, self.savedSamples == stats.acceptedSamples,
                   self.savedTitle == title, cached.metadata.sessionNote == note, FileManager.default.fileExists(atPath: cached.directory.path) {
                    saved = cached
                    if !FileManager.default.fileExists(atPath: saved.url(for: format).path) {
                        try ScanStorage.writeCloud(cloud, to: saved.url(for: format), format: format)
                    }
                    if (saved.metadata.groundControlPoints ?? []) != currentGCPs {
                        saved = try ScanStorage.updateGroundControlPoints(for: saved, points: currentGCPs)
                        self.cachedScan = saved
                    }
                    if (saved.metadata.annotations ?? []) != currentAnnotations {
                        saved = try ScanStorage.updateAnnotations(for: saved, annotations: currentAnnotations)
                        self.cachedScan = saved
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
                        sessionNote: note,
                        location: recordedLocation,
                        groundControlPoints: currentGCPs.isEmpty ? nil : currentGCPs,
                        annotations: currentAnnotations.isEmpty ? nil : currentAnnotations)
                    saved = try ScanStorage.save(cloud, metadata: metadata, format: format, meshAnchors: currentMeshAnchors)
                    self.cachedScan = saved; self.savedSamples = stats.acceptedSamples; self.savedTitle = title
                }
                if !currentMeshAnchors.isEmpty && (!FileManager.default.fileExists(atPath: saved.meshURL.path) || previousSavedSamples != stats.acceptedSamples) {
                    try? MeshExporter.writeOBJ(anchors: currentMeshAnchors, to: saved.meshURL)
                }
                let meshExportURL = saved.meshURL(for: resolvedMeshFormat)
                if shareMesh {
                    if !FileManager.default.fileExists(atPath: meshExportURL.path) || previousSavedSamples != stats.acceptedSamples {
                        if !currentMeshAnchors.isEmpty {
                            try MeshExporter.write(anchors: currentMeshAnchors, format: resolvedMeshFormat, to: meshExportURL)
                        } else if FileManager.default.fileExists(atPath: saved.meshURL.path),
                                  let loaded = MeshPreviewData.fromOBJ(url: saved.meshURL) {
                            try MeshExporter.write(loaded, format: resolvedMeshFormat, to: meshExportURL)
                        }
                    }
                }
                var snapshot = [PCPoint](repeating: PCPoint(), count: min(40_000, Int(stats.pointCount)))
                _ = snapshot.withUnsafeMutableBufferPointer { pc_copy_preview(cloud, $0.baseAddress, $0.count) }
                let archive = try ScanStorage.list()
                let reportURL = try reportFormat.map { try ScanReport.pointCloud(saved, format: $0) }
                DispatchQueue.main.async {
                    self.pointCount = Int(stats.pointCount)
                    self.acceptedSamples = stats.acceptedSamples
                    self.savedScanDetail = saved
                    self.preview = snapshot; self.previewVersion += 1
                    self.savedScans = archive; self.isBusy = false
                    if self.sessionClosed {
                        self.setNotice("Scan saved on this device. %@", self.localizedClosedReason ?? "")
                    } else {
                        self.setNotice("Scan saved on this device.")
                    }
                    if share {
                        var urls = [saved.url(for: format), saved.metadataURL]
                        if FileManager.default.fileExists(atPath: saved.gcpCSVURL.path) {
                            urls.append(saved.gcpCSVURL)
                        }
                        if FileManager.default.fileExists(atPath: saved.annotationsGeoJSONURL.path) {
                            urls.append(saved.annotationsGeoJSONURL)
                        }
                        self.sharedFiles = SharedFiles(urls: urls)
                    }
                    if let reportURL { self.sharedFiles = SharedFiles(urls: [reportURL]) }
                    if shareMesh && FileManager.default.fileExists(atPath: meshExportURL.path) {
                        self.sharedFiles = SharedFiles(urls: [meshExportURL])
                    }
                    self.endBackgroundTask()
                }
            } catch {
                DispatchQueue.main.async {
                    self.isBusy = false
                    self.errorMessage = LanguageManager.format("Saving failed: %@", error.localizedDescription)
                    self.setNotice("The points remain in memory. Please try saving again.")
                    self.endBackgroundTask()
                }
            }
        }
    }

    var effectiveSettings: ScanSettings {
        pointCount == 0 && !isRecording ? settings : activeSettings
    }

    var detailStatusTitle: String {
        if isRecording { return LanguageManager.string("Recording") }
        if sessionClosed { return LanguageManager.string("Completed") }
        if savedScanDetail != nil { return LanguageManager.string("Saved") }
        return LanguageManager.string("Paused")
    }

    var currentClosedReasonText: String? {
        localizedClosedReason ?? closedReason
    }

    var currentLocationSnapshot: GeoLocation? {
        savedScanDetail?.metadata.location ?? (effectiveSettings.recordLocation ? LocationService.shared.currentLocation : nil)
    }

    func shareActiveGCPs() {
        let gcps = activeGroundControlPoints
        guard !gcps.isEmpty else { return }
        worker.async {
            do {
                let data = ScanStorage.gcpCSVData(for: gcps)
                let url: URL
                if let cached = self.cachedScan, FileManager.default.fileExists(atPath: cached.directory.path) {
                    url = cached.gcpCSVURL
                } else {
                    url = FileManager.default.temporaryDirectory.appendingPathComponent("gcps.csv")
                }
                try data.write(to: url, options: .atomic)
                DispatchQueue.main.async {
                    self.sharedFiles = SharedFiles(urls: [url])
                }
            } catch {
                DispatchQueue.main.async { self.errorMessage = error.localizedDescription }
            }
        }
    }

    func shareActiveAnnotations(_ kind: AnnotationExportKind) {
        let annotations = activeAnnotations
        guard !annotations.isEmpty else { return }
        worker.async {
            do {
                let cached = self.cachedScan.flatMap { FileManager.default.fileExists(atPath: $0.directory.path) ? $0 : nil }
                let metadata = cached?.metadata
                let data: Data
                let url: URL
                switch kind {
                case .geojson:
                    data = try AnnotationExporter.geoJSONData(for: annotations, metadata: metadata)
                    url = cached?.annotationsGeoJSONURL ?? FileManager.default.temporaryDirectory.appendingPathComponent(kind.fileName)
                case .csv:
                    data = AnnotationExporter.csvData(for: annotations)
                    url = cached?.annotationsCSVURL ?? FileManager.default.temporaryDirectory.appendingPathComponent(kind.fileName)
                case .dxf:
                    data = AnnotationExporter.dxfData(for: annotations)
                    url = cached?.annotationsDXFURL ?? FileManager.default.temporaryDirectory.appendingPathComponent(kind.fileName)
                case .json:
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    encoder.dateEncodingStrategy = .iso8601
                    data = try encoder.encode(annotations)
                    url = FileManager.default.temporaryDirectory.appendingPathComponent(kind.fileName)
                }
                try data.write(to: url, options: .atomic)
                DispatchQueue.main.async {
                    self.sharedFiles = SharedFiles(urls: [url])
                }
            } catch {
                DispatchQueue.main.async { self.errorMessage = error.localizedDescription }
            }
        }
    }

    func shareMesh(_ scan: SavedScan, format: MeshExportFormat = .obj, completion: ((URL) -> Void)? = nil) {
        guard scan.hasMesh else { return }
        let targetURL = scan.meshURL(for: format)
        if format == .obj || FileManager.default.fileExists(atPath: targetURL.path) {
            if let completion { completion(targetURL) }
            else { sharedFiles = SharedFiles(urls: [targetURL]) }
            return
        }
        worker.async {
            do {
                guard let loaded = MeshPreviewData.fromOBJ(url: scan.meshURL) else {
                    throw ScanFailure.message(L("Could not read saved mesh."))
                }
                try MeshExporter.write(loaded, format: format, to: targetURL)
                DispatchQueue.main.async {
                    if let completion { completion(targetURL) }
                    else { self.sharedFiles = SharedFiles(urls: [targetURL]) }
                }
            } catch {
                DispatchQueue.main.async { self.errorMessage = error.localizedDescription }
            }
        }
    }

    func shareGCPs(_ scan: SavedScan) {
        guard let gcps = scan.metadata.groundControlPoints, !gcps.isEmpty else { return }
        do {
            if !FileManager.default.fileExists(atPath: scan.gcpCSVURL.path) {
                try ScanStorage.gcpCSVData(for: gcps).write(to: scan.gcpCSVURL, options: .atomic)
            }
            sharedFiles = SharedFiles(urls: [scan.gcpCSVURL])
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateGroundControlPoints(for scan: SavedScan?, points: [GroundControlPoint]) {
        if scan == nil {
            activeGroundControlPoints = points
        }
        persistSavedScanUpdate(for: scan) { target in
            try ScanStorage.updateGroundControlPoints(for: target, points: points)
        } onMainUpdate: { isCachedMatch in
            if isCachedMatch { self.activeGroundControlPoints = points }
        }
    }

    func updateAnnotations(for scan: SavedScan?, annotations: [CloudAnnotation]) {
        if scan == nil {
            activeAnnotations = annotations
        }
        persistSavedScanUpdate(for: scan) { target in
            try ScanStorage.updateAnnotations(for: target, annotations: annotations)
        } onMainUpdate: { isCachedMatch in
            if isCachedMatch { self.activeAnnotations = annotations }
        }
    }

    private func persistSavedScanUpdate(
        for scan: SavedScan?,
        transform: @escaping (SavedScan) throws -> SavedScan,
        onMainUpdate: @escaping (Bool) -> Void
    ) {
        worker.async {
            let targetScan = scan ?? self.cachedScan
            guard let targetScan else { return }
            do {
                let updated = try transform(targetScan)
                let matchesCached = self.cachedScan?.id == updated.id
                if matchesCached {
                    self.cachedScan = updated
                }
                let scans = try ScanStorage.list()
                DispatchQueue.main.async {
                    if matchesCached {
                        self.savedScanDetail = updated
                    }
                    self.savedScans = scans
                    onMainUpdate(matchesCached || scan == nil)
                }
            } catch {
                DispatchQueue.main.async { self.errorMessage = error.localizedDescription }
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
        setNotice("Imported scan: %@", scan.metadata.title)
    }

    func loadPreview(for scan: SavedScan) async -> [PCPoint] {
        await Task.detached(priority: .userInitiated) {
            ScanStorage.readPreview(for: scan)
        }.value
    }

    func loadMesh(for scan: SavedScan) async -> MeshPreviewData? {
        guard scan.hasMesh else { return nil }
        let url = scan.meshURL
        return await Task.detached(priority: .userInitiated) {
            MeshPreviewData.fromOBJ(url: url)
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
