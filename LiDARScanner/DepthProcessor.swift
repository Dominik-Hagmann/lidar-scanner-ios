import ARKit
import CoreVideo
import simd

enum DepthProcessor {
    struct Result {
        let stats: PCStats
        let width: Int
        let height: Int
        let preview: [PCPoint]?
    }

    static func process(_ frame: ARFrame, cloud: OpaquePointer, makePreview: Bool) throws -> Result {
        guard let data = frame.sceneDepth, let confidence = data.confidenceMap else {
            throw ScanFailure.message("Noch keine LiDAR-Tiefendaten. Kamera langsam auf eine strukturierte Fläche richten.")
        }
        let depth = data.depthMap
        let image = frame.capturedImage
        let w = CVPixelBufferGetWidth(depth), h = CVPixelBufferGetHeight(depth)
        let pixelFormat = CVPixelBufferGetPixelFormatType(image)
        guard CVPixelBufferGetPixelFormatType(depth) == kCVPixelFormatType_DepthFloat32,
              CVPixelBufferGetPixelFormatType(confidence) == kCVPixelFormatType_OneComponent8,
              CVPixelBufferGetWidth(confidence) == w, CVPixelBufferGetHeight(confidence) == h,
              CVPixelBufferGetPlaneCount(image) == 2,
              pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange ||
              pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange else {
            throw ScanFailure.message("Das gelieferte Tiefen- oder Kamerabildformat wird nicht unterstützt.")
        }
        guard CVPixelBufferLockBaseAddress(depth, .readOnly) == kCVReturnSuccess else {
            throw ScanFailure.message("Tiefenbild konnte nicht gelesen werden.")
        }
        defer { CVPixelBufferUnlockBaseAddress(depth, .readOnly) }
        guard CVPixelBufferLockBaseAddress(confidence, .readOnly) == kCVReturnSuccess else {
            throw ScanFailure.message("Konfidenzbild konnte nicht gelesen werden.")
        }
        defer { CVPixelBufferUnlockBaseAddress(confidence, .readOnly) }
        guard CVPixelBufferLockBaseAddress(image, .readOnly) == kCVReturnSuccess else {
            throw ScanFailure.message("Kamerabild konnte nicht gelesen werden.")
        }
        defer { CVPixelBufferUnlockBaseAddress(image, .readOnly) }

        let resolution = frame.camera.imageResolution
        let scaleX = Float(w) / Float(resolution.width)
        let scaleY = Float(h) / Float(resolution.height)
        let k = frame.camera.intrinsics
        let matrix = CVBufferCopyAttachment(image, kCVImageBufferYCbCrMatrixKey, nil) as? String
        var transform = frame.camera.transform
        var input = PCFrame()
        input.depth = CVPixelBufferGetBaseAddress(depth).map { UnsafeRawPointer($0) }
        input.depthRowBytes = CVPixelBufferGetBytesPerRow(depth)
        input.width = Int32(w); input.height = Int32(h)
        input.confidence = CVPixelBufferGetBaseAddress(confidence).map { UnsafePointer($0.assumingMemoryBound(to: UInt8.self)) }
        input.confidenceRowBytes = CVPixelBufferGetBytesPerRow(confidence)
        input.luma = CVPixelBufferGetBaseAddressOfPlane(image, 0).map { UnsafePointer($0.assumingMemoryBound(to: UInt8.self)) }
        input.chroma = CVPixelBufferGetBaseAddressOfPlane(image, 1).map { UnsafePointer($0.assumingMemoryBound(to: UInt8.self)) }
        input.lumaRowBytes = CVPixelBufferGetBytesPerRowOfPlane(image, 0)
        input.chromaRowBytes = CVPixelBufferGetBytesPerRowOfPlane(image, 1)
        input.imageWidth = Int32(CVPixelBufferGetWidthOfPlane(image, 0))
        input.imageHeight = Int32(CVPixelBufferGetHeightOfPlane(image, 0))
        input.chromaWidth = Int32(CVPixelBufferGetWidthOfPlane(image, 1))
        input.chromaHeight = Int32(CVPixelBufferGetHeightOfPlane(image, 1))
        input.videoRange = pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange ? 1 : 0
        input.matrix709 = matrix == (kCVImageBufferYCbCrMatrix_ITU_R_709_2 as String) ? 1 : 0
        input.fx = k.columns.0.x * scaleX; input.fy = k.columns.1.y * scaleY
        input.cx = k.columns.2.x * scaleX; input.cy = k.columns.2.y * scaleY
        let accepted = withUnsafeBytes(of: &transform) { bytes -> Int32 in
            input.cameraToWorld = bytes.bindMemory(to: Float.self).baseAddress
            return pc_ingest(cloud, input)
        }
        if accepted == -1 { throw ScanFailure.message("Ungültige Kalibrierung oder Bilddaten.") }
        if accepted == -2 { throw ScanFailure.message("Speichergrenze erreicht. Bitte den bisherigen Scan sichern.") }
        let stats = pc_stats(cloud)
        var points: [PCPoint]?
        if makePreview {
            var buffer = [PCPoint](repeating: PCPoint(), count: min(40_000, Int(stats.pointCount)))
            let written = buffer.withUnsafeMutableBufferPointer { pc_copy_preview(cloud, $0.baseAddress, $0.count) }
            buffer.removeLast(buffer.count - written)
            points = buffer
        }
        return Result(stats: stats, width: w, height: h, preview: points)
    }
}
