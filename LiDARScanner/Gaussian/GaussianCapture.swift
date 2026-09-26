import ARKit
import CoreImage
import ImageIO
import simd

enum GaussianCapture {
    static let interval: Double = 0.5
    static let translation: Float = 0.025
    static let angle: Float = 3 * .pi / 180

    static func needsView(_ pose: simd_float4x4, after last: simd_float4x4?) -> Bool {
        guard let last else { return true }
        let distance = simd_distance(pose.columns.3, last.columns.3)
        let a = simd_quatf(pose), b = simd_quatf(last)
        let rotation = 2 * acos(min(1, abs(simd_dot(a.vector, b.vector))))
        return distance >= translation || rotation >= angle
    }

    static func seedConfiguration() -> PCConfig {
        PCConfig(voxelMeters: 0.03, minDepth: 0.2, maxDepth: 5, maxPoints: 100_000,
                 pixelStep: 4, minConfidence: 1)
    }

    static func write(_ frame: ARFrame, store: GaussianStore, context: CIContext, cloud: OpaquePointer) throws {
        let image = CIImage(cvPixelBuffer: frame.capturedImage)
        guard let bytes = context.jpegRepresentation(of: image, colorSpace: CGColorSpaceCreateDeviceRGB(),
            options: [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.95]) else {
            throw GaussianError.message(String(localized: "Could not save the camera image."))
        }
        let relative = String(format: "images/frame_%06d.jpg", store.project.frames.count)
        try bytes.write(to: store.directory.appendingPathComponent(relative), options: .atomic)
        let k = frame.camera.intrinsics, m = frame.camera.transform
        let width = CVPixelBufferGetWidth(frame.capturedImage), height = CVPixelBufferGetHeight(frame.capturedImage)
        let sx = Float(width) / Float(frame.camera.imageResolution.width)
        let sy = Float(height) / Float(frame.camera.imageResolution.height)
        let saved = GaussianFrame(file_path: relative, w: width, h: height,
            fl_x: k.columns.0.x * sx, fl_y: k.columns.1.y * sy, cx: k.columns.2.x * sx, cy: k.columns.2.y * sy,
            transform_matrix: (0..<4).map { row in (0..<4).map { column in m[column][row] } },
            timestamp: frame.timestamp, savedAt: Date(), sha256: GaussianStore.hash(bytes))
        // The image is committed first. A failed depth update must not lose it.
        store.project.frames.append(saved)
        try store.decision("saved", timestamp: frame.timestamp)
        let previousSeed = store.project.seedFile
        if frame.sceneDepth != nil {
            do {
                _ = try DepthProcessor.process(frame, cloud: cloud, makePreview: false)
                try saveSeed(cloud, store: store)
            } catch {
                try store.event("seed_update_failed", ["image": relative, "error": error.localizedDescription])
            }
        } else {
            try store.event("depth_unavailable", ["image": relative])
        }
        try store.event("image_saved", ["path": relative, "sha256": saved.sha256,
            "width": "\(width)", "height": "\(height)", "seedPoints": "\(store.project.seedCount)"])
        try store.saveDataset()
        if let previousSeed, previousSeed != store.project.seedFile {
            try? FileManager.default.removeItem(at: store.directory.appendingPathComponent(previousSeed))
        }
    }

    static func saveSeed(_ cloud: OpaquePointer, store: GaussianStore) throws {
        let count = Int(pc_stats(cloud).pointCount)
        guard count > 0 else { return }
        var points = [PCPoint](repeating: PCPoint(), count: count)
        let written = points.withUnsafeMutableBufferPointer { pc_copy_preview(cloud, $0.baseAddress, $0.count) }
        // The Gaussian dataset stays in ARKit Y-up coordinates. The existing point
        // cloud export has a separate Z-up transform and is intentionally not used.
        var data = Data("ply\nformat binary_little_endian 1.0\ncomment ARKit world metres Y up\nelement vertex \(written)\nproperty float x\nproperty float y\nproperty float z\nproperty uchar red\nproperty uchar green\nproperty uchar blue\nend_header\n".utf8)
        for p in points.prefix(written) {
            for value in [p.x, p.y, p.z] {
                var bits = value.bitPattern.littleEndian
                withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
            }
            data.append(contentsOf: [p.r, p.g, p.b])
        }
        let seedFile = "seed-\(store.project.frames.count).ply"
        try data.write(to: store.directory.appendingPathComponent(seedFile), options: .atomic)
        store.project.seedFile = seedFile
        store.project.seedCount = written; store.project.seedHash = GaussianStore.hash(data)
    }
}
