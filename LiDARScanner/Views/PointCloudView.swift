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

enum MeasureVisuals {
    static func makeMarker(at position: SIMD3<Float>, radius: CGFloat, color: UIColor) -> SCNNode {
        let sphere = SCNSphere(radius: radius)
        sphere.firstMaterial?.diffuse.contents = color
        sphere.firstMaterial?.lightingModel = .constant
        let node = SCNNode(geometry: sphere)
        node.simdPosition = position
        return node
    }

    static func makeLine(from start: SIMD3<Float>, to end: SIMD3<Float>, radius: CGFloat, color: UIColor) -> SCNNode {
        let distance = simd_distance(start, end)
        guard distance > 0.0001 else { return SCNNode() }
        let cylinder = SCNCylinder(radius: radius, height: CGFloat(distance))
        cylinder.firstMaterial?.diffuse.contents = color
        cylinder.firstMaterial?.lightingModel = .constant

        let node = SCNNode(geometry: cylinder)
        node.simdPosition = (start + end) * 0.5

        let dir = simd_normalize(end - start)
        let yAxis = SIMD3<Float>(0, 1, 0)
        let dot = simd_dot(yAxis, dir)
        if abs(dot - 1.0) < 0.0001 {
            // aligned with Y
        } else if abs(dot + 1.0) < 0.0001 {
            // inverted Y
            node.simdOrientation = simd_quatf(angle: .pi, axis: SIMD3<Float>(1, 0, 0))
        } else {
            let axis = simd_normalize(simd_cross(yAxis, dir))
            let angle = acos(max(-1.0, min(1.0, dot)))
            node.simdOrientation = simd_quatf(angle: angle, axis: axis)
        }
        return node
    }
}

struct OrbitCloudView: UIViewRepresentable {
    let points: [PCPoint]
    let measureMode: Bool
    @Binding var selectedA: SIMD3<Float>?
    @Binding var selectedB: SIMD3<Float>?

    final class Coordinator: NSObject {
        var parent: OrbitCloudView
        let measureNode = SCNNode()
        weak var scnView: SCNView?
        var boundsRadius: Float = 1.0

        init(_ parent: OrbitCloudView) {
            self.parent = parent
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard parent.measureMode, let scnView = self.scnView else { return }
            let location = gesture.location(in: scnView)
            guard let hitPoint = findNearestPoint(to: location, in: scnView) else { return }

            UIImpactFeedbackGenerator(style: .medium).impactOccurred()

            if parent.selectedA == nil || parent.selectedB != nil {
                parent.selectedA = hitPoint
                parent.selectedB = nil
            } else {
                parent.selectedB = hitPoint
            }
        }

        private func findNearestPoint(to location: CGPoint, in view: SCNView) -> SIMD3<Float>? {
            let maxScreenDistance: Float = 44.0
            var closestDistance: Float = maxScreenDistance
            var closestZ: Float = .greatestFiniteMagnitude
            var bestPoint: SIMD3<Float>?

            for p in parent.points {
                let worldPos = SCNVector3(p.x, p.y, p.z)
                let screenPos = view.projectPoint(worldPos)
                guard screenPos.z > 0 && screenPos.z < 1 else { continue }

                let dx = Float(screenPos.x) - Float(location.x)
                let dy = Float(screenPos.y) - Float(location.y)
                let dist = sqrt(dx * dx + dy * dy)

                if dist < closestDistance || (abs(dist - closestDistance) < 5.0 && screenPos.z < closestZ) {
                    closestDistance = dist
                    closestZ = screenPos.z
                    bestPoint = SIMD3<Float>(p.x, p.y, p.z)
                }
            }
            return bestPoint
        }

        func updateVisuals() {
            measureNode.childNodes.forEach { $0.removeFromParentNode() }
            guard parent.measureMode else { return }
            let markerRadius = CGFloat(max(0.005, boundsRadius * 0.015))
            let lineRadius = CGFloat(max(0.002, boundsRadius * 0.005))
            let mintColor = UIColor(red: 0.38, green: 0.93, blue: 0.76, alpha: 1)

            if let a = parent.selectedA {
                measureNode.addChildNode(MeasureVisuals.makeMarker(at: a, radius: markerRadius, color: mintColor))
            }
            if let b = parent.selectedB {
                measureNode.addChildNode(MeasureVisuals.makeMarker(at: b, radius: markerRadius, color: .systemYellow))
            }
            if let a = parent.selectedA, let b = parent.selectedB {
                measureNode.addChildNode(MeasureVisuals.makeLine(from: a, to: b, radius: lineRadius, color: .systemYellow))
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = UIColor(red: 0.035, green: 0.055, blue: 0.07, alpha: 1)
        let scene = SCNScene()
        scene.rootNode.addChildNode(SCNNode(geometry: PointGeometry.make(points)))
        scene.rootNode.addChildNode(context.coordinator.measureNode)

        var low = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var high = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        for p in points {
            low = simd_min(low, SIMD3(p.x, p.y, p.z))
            high = simd_max(high, SIMD3(p.x, p.y, p.z))
        }
        let center = points.isEmpty ? SIMD3<Float>(repeating: 0) : (low + high) * 0.5
        let radius = points.isEmpty ? Float(1) : max(0.25, simd_length(high - low) * 0.65)
        context.coordinator.boundsRadius = radius

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

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tap)
        context.coordinator.scnView = view

        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.updateVisuals()
    }
}

struct CloudPreviewSheet: View {
    let points: [PCPoint]
    let total: Int
    @Environment(\.dismiss) private var dismiss
    @State private var measureMode = false
    @State private var selectedA: SIMD3<Float>?
    @State private var selectedB: SIMD3<Float>?

    private var measurementDistance: Float? {
        guard let a = selectedA, let b = selectedB else { return nil }
        return simd_distance(a, b)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                OrbitCloudView(points: points, measureMode: measureMode,
                               selectedA: $selectedA, selectedB: $selectedB)
                    .ignoresSafeArea(edges: .bottom)

                VStack(spacing: 12) {
                    if measureMode {
                        measurementCard
                    } else {
                        infoCard
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .navigationTitle("Point Cloud")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        measureMode.toggle()
                        if !measureMode {
                            selectedA = nil
                            selectedB = nil
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: measureMode ? "ruler.fill" : "ruler")
                            Text("Measure")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(measureMode ? Color(red: 0.38, green: 0.93, blue: 0.76) : Color.secondary.opacity(0.3))
                    .foregroundStyle(measureMode ? .black : .primary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var infoCard: some View {
        Text("Rotate with One Finger · Pinch to Zoom\nPreview points: \(points.count.formatted()) of \(total.formatted()). The export contains all points.")
            .font(.caption).multilineTextAlignment(.center).foregroundStyle(.secondary)
            .padding().frame(maxWidth: .infinity)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var measurementCard: some View {
        VStack(spacing: 8) {
            if let dist = measurementDistance {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Distance").font(.caption.bold()).foregroundStyle(.secondary)
                        Text(String(format: "%.1f cm", dist * 100))
                            .font(.title2.bold())
                            .foregroundStyle(Color(red: 0.38, green: 0.93, blue: 0.76))
                        Text(String(format: "(%.3f m)", dist))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Reset") {
                        selectedA = nil
                        selectedB = nil
                    }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.bordered)
                }
            } else if selectedA != nil {
                HStack(spacing: 8) {
                    Circle().fill(Color.yellow).frame(width: 8, height: 8)
                    Text("Tap second point to measure distance")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Button("Cancel") { selectedA = nil }
                        .font(.caption).buttonStyle(.bordered)
                }
            } else {
                HStack(spacing: 8) {
                    Circle().fill(Color(red: 0.38, green: 0.93, blue: 0.76)).frame(width: 8, height: 8)
                    Text("Tap first point in the scene")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
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
