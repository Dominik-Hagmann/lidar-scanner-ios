import ARKit
import Combine
import CoreVideo
import Foundation
import simd

final class LiDARScanner: NSObject, ObservableObject, ARSessionDelegate {
    static var isLiDARSupported: Bool {
        ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
        || ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth)
    }

    @Published private(set) var isScanning = false
    @Published private(set) var isFinalizing = false
    @Published private(set) var pointCount: Int64 = 0
    @Published private(set) var rawByteCount: Int64 = 0
    @Published private(set) var exportedURL: URL?
    @Published private(set) var statusText = "Ready"
    @Published var density: CaptureDensity = .standard

    private weak var session: ARSession?
    private let processingQueue = DispatchQueue(label: "at.dominikhagmann.lidarscanner.processing", qos: .userInitiated)
    private var writer: PointCloudWriter?
    private var lastAcceptedFrameTimestamp: TimeInterval = 0

    func attach(session: ARSession) {
        self.session = session
        session.delegate = self
        session.delegateQueue = .main
    }

    func startNewScan() {
        guard !isScanning, !isFinalizing, let session else { return }

        do {
            writer = try processingQueue.sync { try PointCloudWriter() }
        } catch {
            statusText = "Could not create scan file: \(error.localizedDescription)"
            return
        }

        pointCount = 0
        rawByteCount = 0
        exportedURL = nil
        lastAcceptedFrameTimestamp = 0

        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity

        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            configuration.frameSemantics.insert(.smoothedSceneDepth)
        } else if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
        }

        isScanning = true
        statusText = "Scanning"
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    func stopScan() {
        guard isScanning else { return }
        isScanning = false
        isFinalizing = true
        statusText = "Finalizing scan"
        session?.pause()

        processingQueue.async { [weak self] in
            guard let self else { return }
            do {
                try self.writer?.finish()
                DispatchQueue.main.async {
                    self.isFinalizing = false
                    self.statusText = self.pointCount > 0 ? "Scan ready to export" : "No points captured"
                }
            } catch {
                DispatchQueue.main.async {
                    self.isFinalizing = false
                    self.statusText = "Could not finalize scan: \(error.localizedDescription)"
                }
            }
        }
    }

    func exportPLY() {
        guard !isScanning, !isFinalizing, writer != nil else { return }
        isFinalizing = true
        statusText = "Exporting PLY"

        processingQueue.async { [weak self] in
            guard let self, let writer = self.writer else { return }
            do {
                let url = try writer.exportPLY()
                DispatchQueue.main.async {
                    self.exportedURL = url
                    self.isFinalizing = false
                    self.statusText = "PLY ready"
                }
            } catch {
                DispatchQueue.main.async {
                    self.isFinalizing = false
                    self.statusText = "Export failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard isScanning else { return }

        let interval = density.frameInterval
        guard frame.timestamp - lastAcceptedFrameTimestamp >= interval else { return }
        lastAcceptedFrameTimestamp = frame.timestamp
        let stride = density.depthStride

        processingQueue.async { [weak self] in
            self?.process(frame: frame, stride: stride)
        }
    }

    private func process(frame: ARFrame, stride: Int) {
        guard let writer else { return }

        let depthData = frame.smoothedSceneDepth ?? frame.sceneDepth
        guard let depthData else { return }

        let depthMap = depthData.depthMap
        let confidenceMap = depthData.confidenceMap
        let image = frame.capturedImage

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        if let confidenceMap {
            CVPixelBufferLockBaseAddress(confidenceMap, .readOnly)
        }
        CVPixelBufferLockBaseAddress(image, .readOnly)

        defer {
            CVPixelBufferUnlockBaseAddress(image, .readOnly)
            if let confidenceMap {
                CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly)
            }
            CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
        }

        guard let depthBaseAddress = CVPixelBufferGetBaseAddress(depthMap) else { return }

        let depthWidth = CVPixelBufferGetWidth(depthMap)
        let depthHeight = CVPixelBufferGetHeight(depthMap)
        let depthBytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        let depthStrideFloats = depthBytesPerRow / MemoryLayout<Float32>.size
        let depthPointer = depthBaseAddress.assumingMemoryBound(to: Float32.self)

        let confidencePointer = confidenceMap
            .flatMap { CVPixelBufferGetBaseAddress($0)?.assumingMemoryBound(to: UInt8.self) }
        let confidenceBytesPerRow = confidenceMap.map(CVPixelBufferGetBytesPerRow) ?? 0

        let imageWidth = CVPixelBufferGetWidth(image)
        let imageHeight = CVPixelBufferGetHeight(image)
        let scaleX = Float(imageWidth) / Float(depthWidth)
        let scaleY = Float(imageHeight) / Float(depthHeight)

        let intrinsics = frame.camera.intrinsics
        let fx = intrinsics.columns.0.x
        let fy = intrinsics.columns.1.y
        let cx = intrinsics.columns.2.x
        let cy = intrinsics.columns.2.y
        let cameraTransform = frame.camera.transform

        var points: [PointSample] = []
        let estimatedCount = max(1, (depthWidth / stride) * (depthHeight / stride))
        points.reserveCapacity(estimatedCount)

        for y in Swift.stride(from: 0, to: depthHeight, by: stride) {
            for x in Swift.stride(from: 0, to: depthWidth, by: stride) {
                let depth = depthPointer[y * depthStrideFloats + x]
                guard depth.isFinite, depth > 0.05, depth < 10.0 else { continue }

                if let confidencePointer {
                    let confidence = confidencePointer[y * confidenceBytesPerRow + x]
                    guard confidence >= 1 else { continue }
                }

                let imageX = min(imageWidth - 1, max(0, Int(Float(x) * scaleX)))
                let imageY = min(imageHeight - 1, max(0, Int(Float(y) * scaleY)))

                let u = Float(imageX)
                let v = Float(imageY)
                let cameraX = (u - cx) / fx * depth
                let cameraY = -(v - cy) / fy * depth
                let cameraPoint = SIMD4<Float>(cameraX, cameraY, -depth, 1.0)
                let worldPoint = cameraTransform * cameraPoint

                let rgb = sampleRGB(from: image, x: imageX, y: imageY)
                points.append(
                    PointSample(
                        position: SIMD3(worldPoint.x, worldPoint.y, worldPoint.z),
                        red: rgb.0,
                        green: rgb.1,
                        blue: rgb.2
                    )
                )
            }
        }

        do {
            try writer.append(points)
            let count = writer.pointCount
            let bytes = writer.rawByteCount
            DispatchQueue.main.async { [weak self] in
                self?.pointCount = count
                self?.rawByteCount = bytes
            }
        } catch {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isScanning = false
                self.statusText = "Scan write failed: \(error.localizedDescription)"
                self.session?.pause()
            }
        }
    }

    private func sampleRGB(from pixelBuffer: CVPixelBuffer, x: Int, y: Int) -> (UInt8, UInt8, UInt8) {
        guard CVPixelBufferGetPlaneCount(pixelBuffer) >= 2,
              let yBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0)?.assumingMemoryBound(to: UInt8.self),
              let uvBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1)?.assumingMemoryBound(to: UInt8.self)
        else {
            return (255, 255, 255)
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let clampedX = min(max(x, 0), width - 1)
        let clampedY = min(max(y, 0), height - 1)

        let yBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let uvBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)

        let yValue = Float(yBase[clampedY * yBytesPerRow + clampedX])
        let uvOffset = (clampedY / 2) * uvBytesPerRow + (clampedX / 2) * 2
        let cb = Float(uvBase[uvOffset]) - 128.0
        let cr = Float(uvBase[uvOffset + 1]) - 128.0

        let r = yValue + 1.402 * cr
        let g = yValue - 0.344136 * cb - 0.714136 * cr
        let b = yValue + 1.772 * cb

        return (clampByte(r), clampByte(g), clampByte(b))
    }

    private func clampByte(_ value: Float) -> UInt8 {
        UInt8(max(0, min(255, Int(value.rounded()))))
    }
}
