import ARKit
import MetalKit
import MetalSplatter
import SceneKit
import SplatIO
import SwiftUI
import simd

extension PCPoint {
    static func toSplatPoints(_ points: [PCPoint]) -> [SplatPoint] {
        guard !points.isEmpty else { return [] }
        var low = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var high = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        for p in points where p.x.isFinite && p.y.isFinite && p.z.isFinite {
            let pos = SIMD3<Float>(p.x, p.y, p.z)
            low = simd_min(low, pos)
            high = simd_max(high, pos)
        }
        let extent = high - low
        let surfaceEstimate = 2 * (extent.x * extent.y + extent.y * extent.z + extent.z * extent.x)
        let estimatedSpacing = sqrt(max(0.0001, surfaceEstimate) / Float(max(1, points.count)))
        let splatRadius: Float = max(0.006, min(0.035, estimatedSpacing * 0.95))
        let rotation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        let scale = SplatPoint.Scale.linearFloat(SIMD3<Float>(repeating: splatRadius))
        let opacity = SplatPoint.Opacity.linearFloat(0.92)

        return points.compactMap { p -> SplatPoint? in
            guard p.x.isFinite && p.y.isFinite && p.z.isFinite else { return nil }
            return SplatPoint(
                position: SIMD3<Float>(p.x, p.y, p.z),
                color: .sRGBUInt8(SIMD3<UInt8>(p.r, p.g, p.b)),
                opacity: opacity,
                scale: scale,
                rotation: rotation
            )
        }
    }
}

enum PointGeometry {
    static func make(_ points: [PCPoint]) -> SCNGeometry? {
        guard !points.isEmpty else { return nil }
        var vertices = [Float](); var colors = [Float]()
        vertices.reserveCapacity(points.count * 3); colors.reserveCapacity(points.count * 4)
        for p in points {
            vertices.append(contentsOf: [p.x, p.y, p.z])
            colors.append(contentsOf: [Float(p.r)/255, Float(p.g)/255, Float(p.b)/255, 1])
        }
        let vertexData = vertices.withUnsafeBytes { Data($0) }
        let colorData = colors.withUnsafeBytes { Data($0) }
        let vertexSource = SCNGeometrySource(data: vertexData, semantic: .vertex, vectorCount: points.count,
            usesFloatComponents: true, componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: 12)
        let colorSource = SCNGeometrySource(data: colorData, semantic: .color, vectorCount: points.count,
            usesFloatComponents: true, componentsPerVector: 4, bytesPerComponent: 4, dataOffset: 0, dataStride: 16)
        let indices = (0..<points.count).map { UInt32($0) }
        let element = SCNGeometryElement(data: indices.withUnsafeBytes { Data($0) }, primitiveType: .point,
            primitiveCount: points.count, bytesPerIndex: 4)
        element.pointSize = 4
        element.minimumPointScreenSpaceRadius = 1
        element.maximumPointScreenSpaceRadius = 5
        let result = SCNGeometry(sources: [vertexSource, colorSource], elements: [element])
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = UIColor.white
        material.isDoubleSided = true
        result.materials = [material]
        return result
    }
}

struct LiveCameraView: UIViewRepresentable {
    @ObservedObject var model: ScanModel
    let showPoints: Bool
    final class Coordinator {
        let node = SCNNode()
        var version = -1
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.session = model.session
        view.scene = SCNScene()
        view.scene.rootNode.addChildNode(context.coordinator.node)
        view.automaticallyUpdatesLighting = false
        view.preferredFramesPerSecond = 30
        return view
    }
    func updateUIView(_ view: ARSCNView, context: Context) {
        context.coordinator.node.isHidden = !showPoints
        if model.previewVersion != context.coordinator.version {
            context.coordinator.node.geometry = PointGeometry.make(model.preview)
            context.coordinator.version = model.previewVersion
        }
    }
}

struct OrbitCloudView: UIViewRepresentable {
    let points: [PCPoint]
    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = UIColor(red: 0.035, green: 0.055, blue: 0.07, alpha: 1)
        let scene = SCNScene()
        scene.rootNode.addChildNode(SCNNode(geometry: PointGeometry.make(points)))
        var low = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var high = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        for p in points {
            low = simd_min(low, SIMD3(p.x, p.y, p.z))
            high = simd_max(high, SIMD3(p.x, p.y, p.z))
        }
        let center = points.isEmpty ? SIMD3<Float>(repeating: 0) : (low + high) * 0.5
        let radius = points.isEmpty ? Float(1) : max(0.25, simd_length(high - low) * 0.65)
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.zNear = 0.01
        camera.camera?.zFar = Double(max(100, radius * 10))
        camera.simdPosition = center + SIMD3<Float>(0.7, 0.5, 1.5) * radius
        camera.look(at: SCNVector3(center.x, center.y, center.z))
        scene.rootNode.addChildNode(camera)
        view.scene = scene
        view.pointOfView = camera
        view.allowsCameraControl = true
        view.defaultCameraController.target = SCNVector3(center.x, center.y, center.z)
        view.defaultCameraController.interactionMode = .orbitTurntable
        view.antialiasingMode = .multisampling4X
        return view
    }
    func updateUIView(_ uiView: SCNView, context: Context) {}
}

enum RenderMode: String, CaseIterable, Identifiable {
    case points = "Points"
    case gaussians = "Gaussians"
    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self {
        case .points: return "Point Cloud"
        case .gaussians: return "Gaussians"
        }
    }
}

struct CloudPreviewSheet: View {
    let points: [PCPoint]
    let total: Int
    @Binding var isFullScreen: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var renderMode: RenderMode = .points
    @State private var gaussianLoading = true
    @State private var gaussianError: String?
    @State private var sharing: SharedFiles?

    init(points: [PCPoint], total: Int, isFullScreen: Binding<Bool> = .constant(false)) {
        self.points = points
        self.total = total
        self._isFullScreen = isFullScreen
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.035, green: 0.055, blue: 0.07).ignoresSafeArea()
                if renderMode == .points {
                    OrbitCloudView(points: points).ignoresSafeArea(edges: .bottom)
                } else {
                    GaussianMetalView(source: .points(points), loading: $gaussianLoading, error: $gaussianError)
                        .ignoresSafeArea(edges: .bottom)
                        .overlay {
                            if gaussianLoading {
                                ProgressView("Generating 3D Gaussians…")
                                    .padding()
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                            }
                            if let gaussianError {
                                Text(gaussianError)
                                    .padding()
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                            }
                        }
                }
            }
            .overlay(alignment: .bottom) {
                if !isFullScreen {
                    VStack(spacing: 4) {
                        Text(LocalizedStringKey(renderMode == .points ? "Rotate with One Finger · Pinch to Zoom" : "Drag to Rotate · Pinch to Zoom"))
                            .font(.caption.bold())
                        Text(renderMode == .points
                            ? String.localizedStringWithFormat(NSLocalizedString("Preview points: %@ of %@. The export contains all points.", comment: ""), points.count.formatted(), total.formatted())
                            : String.localizedStringWithFormat(NSLocalizedString("%@ 3D Gaussian Splats · Real-time Metal Rendering", comment: ""), points.count.formatted()))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal)
                    .padding(.bottom, 16)
                } else {
                    Text(renderMode == .points
                        ? String.localizedStringWithFormat(NSLocalizedString("%@ / %@ points", comment: ""), points.count.formatted(), total.formatted())
                        : String.localizedStringWithFormat(NSLocalizedString("%@ Gaussians", comment: ""), points.count.formatted()))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 16)
                }
            }
            .navigationTitle(LocalizedStringKey(renderMode == .points ? "Point Cloud" : "3D Gaussians"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isFullScreen.toggle()
                        }
                    } label: {
                        Image(systemName: isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    }
                    .accessibilityLabel(LocalizedStringKey(isFullScreen ? "Minimize" : "Maximize"))
                }
                ToolbarItem(placement: .principal) {
                    Picker("Mode", selection: $renderMode) {
                        Text(RenderMode.points.title).tag(RenderMode.points)
                        Text(RenderMode.gaussians.title).tag(RenderMode.gaussians)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 220)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            exportGaussians()
                        } label: {
                            Label("Export 3D Gaussian Splats", systemImage: "aqi.medium")
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Export Options")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        isFullScreen = false
                        dismiss()
                    }
                }
            }
            .sheet(item: $sharing) { ShareSheet(urls: $0.urls) }
        }
        .interactiveDismissDisabled(true)
    }

    private func exportGaussians() {
        Task {
            do {
                let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                let plyURL = tempDir.appendingPathComponent("pointcloud-gaussians.ply")
                let splats = PCPoint.toSplatPoints(points)
                let writer = try SplatPLYSceneWriter(to: .file(plyURL))
                try await writer.start(sphericalHarmonicDegree: 0, binary: true, pointCount: splats.count)
                try await writer.write(splats)
                try await writer.close()
                await MainActor.run {
                    sharing = SharedFiles(urls: [plyURL])
                }
            } catch {
                await MainActor.run {
                    gaussianError = error.localizedDescription
                }
            }
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let urls: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: urls, applicationActivities: nil)
        if UIDevice.current.userInterfaceIdiom == .pad,
           let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows }).first(where: { $0.isKeyWindow }) {
            controller.modalPresentationStyle = .popover
            controller.popoverPresentationController?.sourceView = window
            controller.popoverPresentationController?.sourceRect = CGRect(
                x: window.bounds.midX, y: window.bounds.midY, width: 1, height: 1)
            controller.popoverPresentationController?.permittedArrowDirections = []
        }
        return controller
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
