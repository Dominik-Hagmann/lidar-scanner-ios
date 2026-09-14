import ARKit
import SceneKit
import SwiftUI
import simd

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

struct CloudPreviewSheet: View {
    let points: [PCPoint]
    let total: Int
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            OrbitCloudView(points: points).ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .bottom) {
                    Text("Drehen mit einem Finger · Aufziehen zum Zoomen\nVorschau: \(points.count.formatted()) von \(total.formatted()) Punkten. Export enthält alle Punkte.")
                        .font(.caption).multilineTextAlignment(.center).foregroundStyle(.secondary)
                        .padding().background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal).padding(.bottom, 24)
                }
                .navigationTitle("Punktwolke").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
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
