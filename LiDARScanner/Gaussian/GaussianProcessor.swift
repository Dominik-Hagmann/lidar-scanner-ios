import Foundation

/// Cancellation is the only state shared by the UI and the native worker.
final class GaussianStopSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var reason: String?
    func set(_ reason: String) { lock.lock(); self.reason = reason; lock.unlock() }
    func reset() { lock.lock(); reason = nil; lock.unlock() }
    var value: String? { lock.lock(); defer { lock.unlock() }; return reason }
}

enum GaussianProcessor {
    static func configuration(_ p: GaussianProfile) -> MsplatConfig {
        var c = msplat_default_config()
        c.iterations = Int32(p.iterations); c.shDegree = Int32(p.shDegree)
        c.shDegreeInterval = Int32(p.shDegreeInterval); c.ssimWeight = p.ssimWeight
        c.numDownscales = Int32(p.numDownscales); c.resolutionSchedule = Int32(p.resolutionSchedule)
        c.refineEvery = Int32(p.refineEvery); c.warmupLength = Int32(p.warmupLength)
        c.resetAlphaEvery = Int32(p.resetAlphaEvery); c.densifyGradThresh = p.densifyGradThresh
        c.densifySizeThresh = p.densifySizeThresh; c.stopScreenSizeAt = Int32(p.stopScreenSizeAt)
        c.stopDensifyAt = Int32(p.stopDensifyAt); c.splitScreenSize = p.splitScreenSize
        c.keepCrs = p.keepCrs; c.downscaleFactor = p.downscaleFactor
        c.bgColor = (p.background[0], p.background[1], p.background[2])
        return c
    }

    static func run(store: GaussianStore, stop: GaussianStopSignal, publish: (GaussianProject) -> Void) throws {
        guard store.project.frames.count >= 12 else {
            throw GaussianError.message(String(localized: "At least 12 saved views are needed. Capture the subject from more angles."))
        }
        guard store.project.seedCount > 0 else {
            throw GaussianError.message(String(localized: "No usable LiDAR depth was saved. The images remain available for export."))
        }
        try store.validateInputs()
        if store.project.profile == nil { store.project.profile = .automatic(frames: store.project.frames) }
        guard let profile = store.project.profile else { return }
        store.project.phase = .preparing; store.project.lastIssue = nil
        try store.event("processing_started", ["profile": String(data: try GaussianStore.encoder.encode(profile), encoding: .utf8)!,
            "engineRevision": GaussianProject.pinnedEngineRevision, "resumeCheckpoint": "\(store.project.checkpointIteration)",
            "imageSelection": "all saved views; random camera sampling during training", "evaluation": "not performed"])
        try store.save(); publish(store.project)
        #if targetEnvironment(simulator)
        let shaderName = "default-iossimulator"
        #else
        let shaderName = "default-ios"
        #endif
        guard let shader = Bundle.main.path(forResource: shaderName, ofType: "metallib") else {
            throw GaussianError.message(String(localized: "The processing engine is missing from this app build."))
        }
        guard os_proc_available_memory() > 512 * 1024 * 1024 else {
            throw GaussianError.message(String(localized: "Processing needs more free memory. Your capture is saved; try again later."))
        }
        // Set the engine's documented image-cache budget once, on its serial worker.
        setenv("MSPLAT_IMAGE_CACHE_MB", "\(profile.imageCacheMB)", 1)
        var message = [CChar](repeating: 0, count: 2048)
        guard let engine = gs_open(store.directory.path, shader, configuration(profile), &message, message.count) else {
            throw GaussianError.message(String(cString: message))
        }
        defer { gs_close(engine) }
        let start = Date()
        let previousSeconds = store.project.processingSeconds
        if store.project.checkpointIteration > 0 {
            guard try GaussianStore.hashFile(store.checkpoint) == store.project.checkpointHash else {
                throw GaussianError.message(String(localized: "The processing checkpoint is incomplete or has changed."))
            }
            var restored: Int32 = 0
            try check(gs_restore(engine, store.checkpoint.path, &restored, &message, message.count), message)
            store.project.iteration = Int(restored)
            store.project.splatCount = store.project.checkpointSplatCount
            try store.event("checkpoint_restored", ["iteration": "\(restored)"])
        } else { store.project.iteration = 0 }
        store.project.phase = .training
        try store.save(); publish(store.project)

        while store.project.iteration < profile.iterations {
            let pauseReason = stop.value ?? resourcePauseReason()
            if let reason = pauseReason {
                if store.project.iteration > 0 { try checkpoint(engine, store: store) }
                store.project.processingSeconds = previousSeconds + Date().timeIntervalSince(start)
                store.project.phase = .paused; store.project.lastIssue = reason
                try store.event("processing_paused", ["reason": reason, "iteration": "\(store.project.iteration)"])
                try store.save(); publish(store.project)
                return
            }
            try autoreleasepool {
                var stats = MsplatStats()
                try check(gs_step(engine, &stats, &message, message.count), message)
                guard stats.iteration > store.project.iteration, stats.splatCount > 0, stats.cameraIndex >= 0, Int(stats.cameraIndex) < store.project.frames.count else {
                    throw GaussianError.message(String(localized: "Processing stopped without producing a valid scene."))
                }
                store.project.iteration = Int(stats.iteration); store.project.splatCount = Int(stats.splatCount)
                store.project.processingSeconds = previousSeconds + Date().timeIntervalSince(start)
                try store.event("training_step", ["iteration": "\(stats.iteration)", "gaussians": "\(stats.splatCount)",
                    "cameraIndex": "\(stats.cameraIndex)", "image": store.project.frames[Int(stats.cameraIndex)].file_path,
                    "effectiveImageWidth": "\(stats.imageWidth)", "effectiveImageHeight": "\(stats.imageHeight)",
                    "engineStepMilliseconds": "\(stats.msPerStep)", "availableMemoryBytes": "\(os_proc_available_memory())",
                    "thermalState": "\(ProcessInfo.processInfo.thermalState.rawValue)"])
                if store.project.iteration % 100 == 0 { try checkpoint(engine, store: store) }
                if store.project.iteration % 5 == 0 { publish(store.project) }
            }
        }
        try checkpoint(engine, store: store)
        let temporary = store.directory.appendingPathComponent("scene.pending.ply")
        try store.event("export_started", ["format": "Gaussian PLY", "coordinateSystem": store.project.coordinateSystem])
        try check(gs_export(engine, temporary.path, &message, message.count), message)
        try validatePLY(temporary, expected: store.project.splatCount)
        try GaussianStore.commit(temporary, to: store.project.resultURL)
        store.project.resultHash = try GaussianStore.hashFile(store.project.resultURL)
        store.project.phase = .completed; store.project.lastIssue = nil
        store.project.processingSeconds = previousSeconds + Date().timeIntervalSince(start)
        try store.event("processing_completed", ["iteration": "\(store.project.iteration)",
            "gaussians": "\(store.project.splatCount)", "resultSHA256": store.project.resultHash!,
            "elapsedSecondsThisRun": "\(Date().timeIntervalSince(start))"])
        try store.save(); publish(store.project)
    }

    private static func check(_ result: Int32, _ error: [CChar]) throws {
        guard result != 0 else { throw GaussianError.message(String(cString: error)) }
    }
    private static func resourcePauseReason() -> String? {
        if ProcessInfo.processInfo.thermalState == .critical { return "thermal_critical" }
        if os_proc_available_memory() < 384 * 1024 * 1024 { return "memory_reserve" }
        return nil
    }
    private static func checkpoint(_ engine: OpaquePointer, store: GaussianStore) throws {
        var error = [CChar](repeating: 0, count: 2048)
        let temporary = store.directory.appendingPathComponent("training.pending.ckpt")
        try check(gs_checkpoint(engine, temporary.path, &error, error.count), error)
        let hash = try GaussianStore.hashFile(temporary)
        let destination = store.directory.appendingPathComponent("checkpoint-\(store.project.iteration).ckpt")
        let oldCheckpoint = store.checkpoint
        try GaussianStore.commit(temporary, to: destination)
        store.project.checkpointIteration = store.project.iteration; store.project.checkpointHash = hash
        store.project.checkpointSplatCount = store.project.splatCount
        try store.event("checkpoint_saved", ["iteration": "\(store.project.iteration)", "sha256": hash])
        try store.save()
        if oldCheckpoint != destination { try? FileManager.default.removeItem(at: oldCheckpoint) }
    }
    static func validatePLY(_ url: URL, expected: Int) throws {
        let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
        let data = try file.read(upToCount: 16384) ?? Data()
        let marker = Data("end_header\n".utf8)
        guard let range = data.range(of: marker), let header = String(data: data[..<range.lowerBound], encoding: .utf8),
              header.hasPrefix("ply\nformat binary_little_endian 1.0\n"),
              header.contains("element vertex \(expected)\n"), expected > 0 else {
            throw GaussianError.message(String(localized: "The scene export could not be verified."))
        }
        let properties = header.components(separatedBy: "\n").filter { $0.hasPrefix("property float ") }.count
        let size = try file.seekToEnd()
        guard size == UInt64(range.upperBound + expected * properties * 4) else {
            throw GaussianError.message(String(localized: "The scene export is incomplete. Your capture is still saved."))
        }
    }
}
