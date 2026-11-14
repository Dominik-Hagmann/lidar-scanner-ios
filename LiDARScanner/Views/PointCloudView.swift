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
    let showMesh: Bool

    final class Coordinator {
        let node = SCNNode()
        let meshRootNode = SCNNode()
        var version = -1
        var renderedMeshVersion = -1
        private var chunkNodes: [UUID: (node: SCNNode, version: Int)] = [:]

        func syncMeshes(showMesh: Bool, model: ScanModel) {
            meshRootNode.isHidden = !showMesh
            guard showMesh else { return }
            let currentVersion = model.meshVersion
            guard currentVersion != renderedMeshVersion else { return }
            renderedMeshVersion = currentVersion

            let entries = model.meshAnchorEntries()
            let activeIDs = Set(entries.map(\.id))
            for (id, entry) in chunkNodes where !activeIDs.contains(id) {
                entry.node.removeFromParentNode()
                chunkNodes.removeValue(forKey: id)
            }

            for item in entries {
                if let existing = chunkNodes[item.id] {
                    if existing.version != item.version {
                        existing.node.simdTransform = item.anchor.transform
                        existing.node.geometry = MeshGeometry.makeWireframeGeometry(from: item.anchor)
                        chunkNodes[item.id] = (existing.node, item.version)
                    }
                } else {
                    let chunkNode = SCNNode()
                    chunkNode.simdTransform = item.anchor.transform
                    chunkNode.geometry = MeshGeometry.makeWireframeGeometry(from: item.anchor)
                    meshRootNode.addChildNode(chunkNode)
                    chunkNodes[item.id] = (chunkNode, item.version)
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.session = model.session
        view.scene = SCNScene()
        view.scene.rootNode.addChildNode(context.coordinator.node)
        view.scene.rootNode.addChildNode(context.coordinator.meshRootNode)
        view.automaticallyUpdatesLighting = false
        view.preferredFramesPerSecond = 30
        context.coordinator.syncMeshes(showMesh: showMesh, model: model)
        return view
    }

    func updateUIView(_ view: ARSCNView, context: Context) {
        context.coordinator.node.isHidden = !showPoints
        if model.previewVersion != context.coordinator.version {
            context.coordinator.node.geometry = PointGeometry.make(model.preview)
            context.coordinator.version = model.previewVersion
        }
        context.coordinator.syncMeshes(showMesh: showMesh, model: model)
    }
}

enum PreviewToolMode: Equatable {
    case view
    case measure
    case gcp
    case annotate
}

enum PreviewVisuals {
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
        if abs(dot - 1.0) >= 0.0001 {
            if abs(dot + 1.0) < 0.0001 {
                node.simdOrientation = simd_quatf(angle: .pi, axis: SIMD3<Float>(1, 0, 0))
            } else {
                let axis = simd_normalize(simd_cross(yAxis, dir))
                let angle = acos(max(-1.0, min(1.0, dot)))
                node.simdOrientation = simd_quatf(angle: angle, axis: axis)
            }
        }
        return node
    }

    static func makePolygonSurface(vertices: [SIMD3<Float>], color: UIColor) -> SCNNode? {
        guard vertices.count >= 3 else { return nil }
        var coords: [Float] = []
        coords.reserveCapacity(vertices.count * 3)
        for v in vertices {
            coords.append(contentsOf: [v.x, v.y, v.z])
        }
        var indices: [UInt32] = []
        indices.reserveCapacity((vertices.count - 2) * 3)
        for i in 1..<(vertices.count - 1) {
            indices.append(contentsOf: [0, UInt32(i), UInt32(i + 1)])
        }
        let vertexData = coords.withUnsafeBytes { Data($0) }
        let vertexSource = SCNGeometrySource(
            data: vertexData,
            semantic: .vertex,
            vectorCount: vertices.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: 4,
            dataOffset: 0,
            dataStride: 12
        )
        let element = SCNGeometryElement(
            data: indices.withUnsafeBytes { Data($0) },
            primitiveType: .triangles,
            primitiveCount: vertices.count - 2,
            bytesPerIndex: 4
        )
        let geometry = SCNGeometry(sources: [vertexSource], elements: [element])
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = color.withAlphaComponent(0.28)
        material.isDoubleSided = true
        material.writesToDepthBuffer = false
        geometry.materials = [material]
        return SCNNode(geometry: geometry)
    }

    static func addShape(
        vertices: [SIMD3<Float>],
        closed: Bool,
        fill: Bool,
        markerRadius: CGFloat,
        lineRadius: CGFloat,
        color: UIColor,
        into parentNode: SCNNode
    ) {
        for v in vertices {
            parentNode.addChildNode(makeMarker(at: v, radius: markerRadius, color: color))
        }
        if vertices.count >= 2 {
            let edgeCount = closed ? vertices.count : vertices.count - 1
            for i in 0..<edgeCount {
                let a = vertices[i]
                let b = vertices[(i + 1) % vertices.count]
                parentNode.addChildNode(makeLine(from: a, to: b, radius: lineRadius, color: color))
            }
        }
        if fill, let surface = makePolygonSurface(vertices: vertices, color: color) {
            parentNode.addChildNode(surface)
        }
    }
}

struct OrbitCloudView: UIViewRepresentable {
    let points: [PCPoint]
    let mesh: MeshPreviewData?
    let showPoints: Bool
    let showMesh: Bool
    let toolMode: PreviewToolMode
    @Binding var selectedA: SIMD3<Float>?
    @Binding var selectedB: SIMD3<Float>?
    let groundControlPoints: [GroundControlPoint]
    let selectedGCPID: UUID?
    let onPickGCPPoint: (SIMD3<Float>) -> Void
    let annotations: [CloudAnnotation]
    let selectedAnnotationID: UUID?
    let activeTagFilter: String?
    let editingAnnotationID: UUID?
    let draftAnnotationPoints: [SIMD3<Float>]
    let projectionModel: AnnotationOverlayProjectionModel
    let onPickAnnotationPoint: (SIMD3<Float>) -> Void

    final class Coordinator: NSObject, UIGestureRecognizerDelegate, SCNSceneRendererDelegate {
        var parent: OrbitCloudView
        let pointsNode = SCNNode()
        let meshWireNode = SCNNode()
        let meshSurfaceNode = SCNNode()
        var meshBuilt = false
        let overlayNode = SCNNode()
        weak var scnView: SCNView?
        var boundsRadius: Float = 1.0

        init(_ parent: OrbitCloudView) {
            self.parent = parent
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard parent.toolMode != .view, let scnView else { return }
            let location = gesture.location(in: scnView)
            guard let hitPoint = findNearestPoint(to: location, in: scnView) else { return }

            UIImpactFeedbackGenerator(style: .medium).impactOccurred()

            switch parent.toolMode {
            case .view:
                break
            case .measure:
                if parent.selectedA == nil || parent.selectedB != nil {
                    parent.selectedA = hitPoint
                    parent.selectedB = nil
                } else {
                    parent.selectedB = hitPoint
                }
            case .gcp:
                parent.onPickGCPPoint(hitPoint)
            case .annotate:
                parent.onPickAnnotationPoint(hitPoint)
            }
        }

        private func findNearestPoint(to location: CGPoint, in view: SCNView) -> SIMD3<Float>? {
            let maxScreenDistance: Float = 44.0
            var closestDistance = maxScreenDistance
            var closestZ: Float = .greatestFiniteMagnitude
            var bestPoint: SIMD3<Float>?

            for p in parent.points {
                let screenPos = view.projectPoint(SCNVector3(p.x, p.y, p.z))
                guard screenPos.z > 0 && screenPos.z < 1 else { continue }
                let dx = Float(screenPos.x) - Float(location.x)
                let dy = Float(screenPos.y) - Float(location.y)
                let dist = hypot(dx, dy)
                if dist < closestDistance || (abs(dist - closestDistance) < 5.0 && screenPos.z < closestZ) {
                    closestDistance = dist
                    closestZ = screenPos.z
                    bestPoint = SIMD3<Float>(p.x, p.y, p.z)
                }
            }
            return bestPoint
        }

        private var filteredAnnotations: [CloudAnnotation] {
            parent.annotations.filter { ann in
                guard let filter = parent.activeTagFilter else { return true }
                if filter == "__untagged__" { return ann.tags.isEmpty }
                return ann.tags.contains { $0.caseInsensitiveCompare(filter) == .orderedSame }
            }
        }

        func renderer(_ renderer: SCNSceneRenderer, didRenderScene scene: SCNScene, atTime time: TimeInterval) {
            guard let scnView else { return }
            let bounds = scnView.bounds
            guard bounds.width > 0, bounds.height > 0 else { return }
            let snapshot = filteredAnnotations
            let selectedID = parent.selectedAnnotationID
            let model = parent.projectionModel
            var labels: [ProjectedAnnotationLabel] = []
            labels.reserveCapacity(snapshot.count)

            for ann in snapshot where !ann.vertices.isEmpty {
                let c = ann.centroid.arkitPosition
                let projected = renderer.projectPoint(SCNVector3(c.x, c.y, c.z))
                guard projected.z > 0 && projected.z < 1,
                      projected.x.isFinite && projected.y.isFinite else { continue }
                let pt = CGPoint(x: CGFloat(projected.x), y: CGFloat(projected.y))
                guard pt.x >= -60, pt.x <= bounds.width + 60,
                      pt.y >= -60, pt.y <= bounds.height + 60 else { continue }
                labels.append(ProjectedAnnotationLabel(
                    id: ann.id,
                    title: ann.title,
                    primaryTag: ann.tags.first,
                    color: ann.color,
                    type: ann.type,
                    screenPoint: pt,
                    isSelected: ann.id == selectedID
                ))
            }

            DispatchQueue.main.async {
                model.update(labels: labels)
            }
        }

        func updateVisuals() {
            overlayNode.childNodes.forEach { $0.removeFromParentNode() }
            pointsNode.isHidden = !parent.showPoints
            if parent.showMesh, let mesh = parent.mesh, !mesh.isEmpty {
                if !meshBuilt {
                    meshWireNode.geometry = MeshGeometry.makeSCNGeometry(from: mesh, wireframe: true, color: MeshGeometry.previewWireframeColor)
                    meshSurfaceNode.geometry = MeshGeometry.makeSCNGeometry(from: mesh, wireframe: false, color: MeshGeometry.previewSurfaceColor)
                    meshBuilt = true
                }
                meshWireNode.isHidden = !parent.showPoints
                meshSurfaceNode.isHidden = parent.showPoints
            } else {
                meshWireNode.isHidden = true
                meshSurfaceNode.isHidden = true
            }
            let markerRadius = CGFloat(max(0.005, boundsRadius * 0.014))
            let lineRadius = CGFloat(max(0.002, boundsRadius * 0.0045))

            for gcp in parent.groundControlPoints {
                let isSelected = gcp.id == parent.selectedGCPID
                let color: UIColor = isSelected
                    ? UIColor(red: 1.0, green: 0.27, blue: 0.23, alpha: 1)
                    : UIColor(red: 1.0, green: 0.62, blue: 0.04, alpha: 1)
                let scale: CGFloat = isSelected ? 1.55 : 1.15
                overlayNode.addChildNode(PreviewVisuals.makeMarker(at: gcp.arkitPosition, radius: markerRadius * scale, color: color))
            }

            for ann in filteredAnnotations {
                if ann.id == parent.editingAnnotationID { continue }
                let isSelected = ann.id == parent.selectedAnnotationID
                let scale: CGFloat = isSelected ? 1.45 : 1.0
                let verts = ann.vertices.map(\.arkitPosition)
                if ann.type == .point || verts.count == 1, let pos = verts.first {
                    overlayNode.addChildNode(PreviewVisuals.makeMarker(
                        at: pos,
                        radius: markerRadius * scale,
                        color: ann.color.uiColor
                    ))
                } else {
                    PreviewVisuals.addShape(
                        vertices: verts,
                        closed: true,
                        fill: true,
                        markerRadius: markerRadius * 0.85 * scale,
                        lineRadius: lineRadius * (isSelected ? 1.5 : 1.0),
                        color: ann.color.uiColor,
                        into: overlayNode
                    )
                }
            }

            if parent.toolMode == .annotate && !parent.draftAnnotationPoints.isEmpty {
                let draftColor = UIColor(red: 0.22, green: 0.74, blue: 0.97, alpha: 1)
                PreviewVisuals.addShape(
                    vertices: parent.draftAnnotationPoints,
                    closed: parent.draftAnnotationPoints.count >= 3,
                    fill: parent.draftAnnotationPoints.count >= 3,
                    markerRadius: markerRadius * 0.95,
                    lineRadius: lineRadius * 1.2,
                    color: draftColor,
                    into: overlayNode
                )
            }

            guard parent.toolMode == .measure else { return }
            let mintColor = UIColor(red: 0.38, green: 0.93, blue: 0.76, alpha: 1)
            if let a = parent.selectedA {
                overlayNode.addChildNode(PreviewVisuals.makeMarker(at: a, radius: markerRadius, color: mintColor))
            }
            if let b = parent.selectedB {
                overlayNode.addChildNode(PreviewVisuals.makeMarker(at: b, radius: markerRadius, color: mintColor))
            }
            if let a = parent.selectedA, let b = parent.selectedB {
                overlayNode.addChildNode(PreviewVisuals.makeLine(from: a, to: b, radius: lineRadius, color: mintColor))
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = UIColor(red: 0.035, green: 0.055, blue: 0.07, alpha: 1)
        let scene = SCNScene()
        context.coordinator.pointsNode.geometry = PointGeometry.make(points)
        context.coordinator.meshWireNode.isHidden = true
        context.coordinator.meshSurfaceNode.isHidden = true
        scene.rootNode.addChildNode(context.coordinator.pointsNode)
        scene.rootNode.addChildNode(context.coordinator.meshSurfaceNode)
        scene.rootNode.addChildNode(context.coordinator.meshWireNode)
        scene.rootNode.addChildNode(context.coordinator.overlayNode)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 550
        scene.rootNode.addChildNode(ambient)

        let keyLight = SCNNode()
        keyLight.light = SCNLight()
        keyLight.light?.type = .directional
        keyLight.light?.intensity = 850
        keyLight.eulerAngles = SCNVector3(-Float.pi / 3, Float.pi / 4, 0)
        scene.rootNode.addChildNode(keyLight)

        let fillLight = SCNNode()
        fillLight.light = SCNLight()
        fillLight.light?.type = .directional
        fillLight.light?.intensity = 400
        fillLight.eulerAngles = SCNVector3(Float.pi / 4, -3 * Float.pi / 4, 0)
        scene.rootNode.addChildNode(fillLight)

        var low = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var high = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        for p in points {
            low = simd_min(low, SIMD3(p.x, p.y, p.z))
            high = simd_max(high, SIMD3(p.x, p.y, p.z))
        }
        if points.isEmpty, let meshVerts = mesh?.vertices {
            for v in meshVerts {
                low = simd_min(low, v)
                high = simd_max(high, v)
            }
        }
        let hasBounds = !points.isEmpty || !(mesh?.vertices.isEmpty ?? true)
        let center = hasBounds ? (low + high) * 0.5 : SIMD3<Float>(repeating: 0)
        let radius = hasBounds ? max(0.25, simd_length(high - low) * 0.65) : Float(1)
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
        view.delegate = context.coordinator

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)
        context.coordinator.scnView = view
        context.coordinator.updateVisuals()
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.updateVisuals()
    }
}

private struct GCPEditorState: Identifiable {
    let id = UUID()
    let existing: GroundControlPoint?
    let initialPoint: GroundControlPoint
}

struct CloudPreviewSheet: View {
    let points: [PCPoint]
    let total: Int
    let mesh: MeshPreviewData?
    let scanMetadata: ScanMetadata?
    @Binding var isFullScreen: Bool
    let onClose: (() -> Void)?
    let onSaveGCPs: (([GroundControlPoint]) -> Void)?
    let onSaveAnnotations: (([CloudAnnotation]) -> Void)?

    @State private var showPoints = true
    @State private var showMesh = false
    @State private var toolMode: PreviewToolMode = .view
    @State private var selectedA: SIMD3<Float>?
    @State private var selectedB: SIMD3<Float>?
    @State private var gcps: [GroundControlPoint]
    @State private var selectedGCPID: UUID?
    @State private var editorState: GCPEditorState?
    @State private var showGCPList = false
    @State private var sharedGCPFile: SharedFiles?

    @State private var annotations: [CloudAnnotation]
    @State private var annotationShape: CloudAnnotationGeometryType = .point
    @State private var draftAnnotationPoints: [SIMD3<Float>] = []
    @State private var editingGeometryAnnotation: CloudAnnotation?
    @State private var selectedAnnotationID: UUID?
    @State private var activeTagFilter: String?
    @State private var annotationEditorState: AnnotationEditorState?
    @State private var showAnnotationList = false
    @StateObject private var projectionModel = AnnotationOverlayProjectionModel()

    @ObservedObject private var language = LanguageManager.shared
    @Environment(\.dismiss) private var dismiss

    private var measurementDistance: Float? {
        guard let a = selectedA, let b = selectedB else { return nil }
        return simd_distance(a, b)
    }

    init(
        points: [PCPoint],
        total: Int,
        mesh: MeshPreviewData? = nil,
        scanMetadata: ScanMetadata? = nil,
        groundControlPoints: [GroundControlPoint] = [],
        onSaveGCPs: (([GroundControlPoint]) -> Void)? = nil,
        annotations: [CloudAnnotation] = [],
        onSaveAnnotations: (([CloudAnnotation]) -> Void)? = nil,
        isFullScreen: Binding<Bool> = .constant(false),
        onClose: (() -> Void)? = nil
    ) {
        self.points = points
        self.total = total
        self.mesh = mesh
        self.scanMetadata = scanMetadata
        self._gcps = State(initialValue: groundControlPoints)
        self.onSaveGCPs = onSaveGCPs
        self._annotations = State(initialValue: annotations)
        self.onSaveAnnotations = onSaveAnnotations
        self._isFullScreen = isFullScreen
        self.onClose = onClose
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                OrbitCloudView(
                    points: points,
                    mesh: mesh,
                    showPoints: showPoints,
                    showMesh: showMesh,
                    toolMode: toolMode,
                    selectedA: $selectedA,
                    selectedB: $selectedB,
                    groundControlPoints: gcps,
                    selectedGCPID: selectedGCPID,
                    onPickGCPPoint: openNewGCP(at:),
                    annotations: annotations,
                    selectedAnnotationID: selectedAnnotationID,
                    activeTagFilter: activeTagFilter,
                    editingAnnotationID: editingGeometryAnnotation?.id,
                    draftAnnotationPoints: draftAnnotationPoints,
                    projectionModel: projectionModel,
                    onPickAnnotationPoint: handleAnnotationTap(at:)
                )
                .ignoresSafeArea(edges: .bottom)

                AnnotationLabelsOverlayView(projection: projectionModel) { tappedID in
                    guard editingGeometryAnnotation == nil,
                          let ann = annotations.first(where: { $0.id == tappedID }) else { return }
                    selectedAnnotationID = ann.id
                    annotationEditorState = AnnotationEditorState(existing: ann, initial: ann)
                }

                VStack(spacing: 10) {
                    if toolMode == .measure {
                        measurementCard
                    } else if toolMode == .gcp {
                        gcpCard
                    } else if toolMode == .annotate {
                        AnnotationToolHUDCard(
                            annotations: $annotations,
                            selectedAnnotationID: $selectedAnnotationID,
                            activeTagFilter: $activeTagFilter,
                            annotationShape: $annotationShape,
                            draftPoints: $draftAnnotationPoints,
                            editingAnnotation: $editingGeometryAnnotation,
                            onFinishNewDraft: finishDraftAnnotation,
                            onCommitGeometryEdit: commitGeometryEdit,
                            onCancelGeometryEdit: cancelGeometryEdit,
                            onOpenList: { showAnnotationList = true },
                            onEditAnnotation: { ann in
                                annotationEditorState = AnnotationEditorState(existing: ann, initial: ann)
                            }
                        )
                    } else if !isFullScreen {
                        infoCard
                    } else {
                        Text(L("%@ / %@ points", points.count.formatted(), total.formatted()))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .overlay(alignment: .topTrailing) {
                if let mesh, !mesh.isEmpty {
                    VStack(spacing: 10) {
                        Button { showPoints.toggle() } label: {
                            Image(systemName: showPoints ? "circle.hexagongrid.fill" : "circle.hexagongrid")
                                .font(.title3)
                                .foregroundStyle(showPoints ? Color(red: 0.38, green: 0.93, blue: 0.76) : .white)
                                .frame(width: 44, height: 44)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .accessibilityLabel(L(showPoints ? "Hide Points" : "Show Points"))

                        Button { showMesh.toggle() } label: {
                            Image(systemName: showMesh ? "cube.fill" : "cube")
                                .font(.title3)
                                .foregroundStyle(showMesh ? Color(red: 0.38, green: 0.93, blue: 0.76) : .white)
                                .frame(width: 44, height: 44)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .accessibilityLabel(L(showMesh ? "Hide Mesh" : "Show Mesh"))
                    }
                    .padding(16)
                }
            }
            .navigationTitle(L("Point Cloud"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isFullScreen.toggle()
                        }
                    } label: {
                        Image(systemName: isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    }
                    .accessibilityLabel(L(isFullScreen ? "Minimize" : "Maximize"))

                    Button {
                        toggleTool(.measure)
                    } label: {
                        Image(systemName: toolMode == .measure ? "ruler.fill" : "ruler")
                    }
                    .tint(toolMode == .measure ? Color(red: 0.38, green: 0.93, blue: 0.76) : .primary)
                    .accessibilityLabel(L("Measure"))

                    Button {
                        toggleTool(.gcp)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: toolMode == .gcp ? "scope" : "mappin.and.ellipse")
                            if !gcps.isEmpty {
                                Text("\(gcps.count)")
                                    .font(.caption2.bold().monospacedDigit())
                            }
                        }
                    }
                    .tint(toolMode == .gcp ? .orange : .primary)
                    .accessibilityLabel(L("Ground Control Points"))

                    Button {
                        toggleTool(.annotate)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: toolMode == .annotate ? "highlighter" : "tag")
                            if !annotations.isEmpty {
                                Text("\(annotations.count)")
                                    .font(.caption2.bold().monospacedDigit())
                            }
                        }
                    }
                    .tint(toolMode == .annotate ? .cyan : .primary)
                    .accessibilityLabel(L("3D Annotations"))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Done")) {
                        isFullScreen = false
                        if let onClose {
                            onClose()
                        } else {
                            dismiss()
                        }
                    }
                }
            }
            .sheet(item: $editorState) { state in
                GCPEditorSheet(
                    initial: state.initialPoint,
                    isNew: state.existing == nil,
                    onSave: { saved in
                        saveGCP(saved, isNew: state.existing == nil)
                    },
                    onDelete: state.existing == nil ? nil : {
                        deleteGCP(state.initialPoint)
                    }
                )
            }
            .sheet(isPresented: $showGCPList) {
                gcpListSheet
            }
            .sheet(item: $annotationEditorState) { state in
                AnnotationEditorSheet(
                    initial: state.initial,
                    isNew: state.existing == nil,
                    existingTags: allAnnotationTags,
                    onSave: { saved in
                        saveAnnotation(saved, isNew: state.existing == nil)
                    },
                    onDelete: state.existing == nil ? nil : {
                        deleteAnnotation(state.initial)
                    },
                    onEditGeometry: state.existing == nil ? nil : { updatedDraft in
                        editingGeometryAnnotation = updatedDraft
                        selectedAnnotationID = updatedDraft.id
                        annotationShape = updatedDraft.type
                        draftAnnotationPoints = updatedDraft.vertices.map(\.arkitPosition)
                        toolMode = .annotate
                    }
                )
            }
            .sheet(isPresented: $showAnnotationList) {
                AnnotationListSheet(
                    annotations: $annotations,
                    selectedAnnotationID: $selectedAnnotationID,
                    activeTagFilter: $activeTagFilter,
                    exportMetadata: scanMetadata.map(AnnotationExportMetadata.init(scan:)),
                    onChanged: { updated in
                        onSaveAnnotations?(updated)
                    },
                    onEdit: { ann in
                        annotationEditorState = AnnotationEditorState(existing: ann, initial: ann)
                    }
                )
            }
            .sheet(item: $sharedGCPFile) { item in
                ShareSheet(urls: item.urls)
            }
        }
        .interactiveDismissDisabled(true)
    }

    private func toggleTool(_ target: PreviewToolMode) {
        if toolMode == target {
            toolMode = .view
            selectedA = nil
            selectedB = nil
            selectedGCPID = nil
            selectedAnnotationID = nil
            draftAnnotationPoints = []
            editingGeometryAnnotation = nil
        } else {
            if target != .measure {
                selectedA = nil
                selectedB = nil
            }
            if target != .annotate {
                draftAnnotationPoints = []
                editingGeometryAnnotation = nil
            }
            toolMode = target
        }
    }

    private var infoCard: some View {
        VStack(spacing: 4) {
            Text(L("Rotate with One Finger · Pinch to Zoom"))
                .font(.caption.bold())
            Text(L("Preview points: %@ of %@. The export contains all points.", points.count.formatted(), total.formatted()))
                .font(.caption2)
                .foregroundStyle(.secondary)
            if !gcps.isEmpty || !annotations.isEmpty {
                HStack(spacing: 12) {
                    if !gcps.isEmpty {
                        Button {
                            showGCPList = true
                        } label: {
                            Label(L("%@ Ground Control Points", gcps.count.formatted()), systemImage: "mappin.and.ellipse")
                                .font(.caption2.weight(.semibold))
                        }
                        .foregroundStyle(.orange)
                    }
                    if !annotations.isEmpty {
                        Button {
                            showAnnotationList = true
                        } label: {
                            Label(L("%@ Annotations", annotations.count.formatted()), systemImage: "tag.fill")
                                .font(.caption2.weight(.semibold))
                        }
                        .foregroundStyle(.cyan)
                    }
                }
                .padding(.top, 2)
            }
        }
        .multilineTextAlignment(.center)
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var measurementCard: some View {
        VStack(spacing: 8) {
            if let dist = measurementDistance {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Distance")).font(.caption.bold()).foregroundStyle(.secondary)
                        Text(String(format: "%.1f cm", dist * 100))
                            .font(.title2.bold())
                            .foregroundStyle(Color(red: 0.38, green: 0.93, blue: 0.76))
                        Text(String(format: "(%.3f m)", dist))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(L("Reset")) {
                        selectedA = nil
                        selectedB = nil
                    }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.bordered)
                }
            } else if selectedA != nil {
                HStack(spacing: 8) {
                    Circle().fill(Color.yellow).frame(width: 8, height: 8)
                    Text(L("Tap second point to measure distance"))
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Button(L("Cancel")) { selectedA = nil }
                        .font(.caption).buttonStyle(.bordered)
                }
            } else {
                HStack(spacing: 8) {
                    Circle().fill(Color(red: 0.38, green: 0.93, blue: 0.76)).frame(width: 8, height: 8)
                    Text(L("Tap first point in the scene"))
                        .font(.subheadline.weight(.medium))
                    Spacer()
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var gcpCard: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(Color.orange).frame(width: 8, height: 8)
                Text(L("Tap a point in the scene to add a GCP"))
                    .font(.subheadline.weight(.medium))
                Spacer()
                if !gcps.isEmpty {
                    Button(L("List (%@)", gcps.count.formatted())) {
                        showGCPList = true
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .tint(.orange)
                }
            }
            if !gcps.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(gcps) { gcp in
                            Button {
                                selectedGCPID = gcp.id
                                editorState = GCPEditorState(existing: gcp, initialPoint: gcp)
                            } label: {
                                Text(gcp.label)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(selectedGCPID == gcp.id ? Color.red.opacity(0.25) : Color.orange.opacity(0.2), in: Capsule())
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var gcpListSheet: some View {
        NavigationStack {
            List {
                if gcps.isEmpty {
                    Text(L("No ground control points recorded yet. Switch to GCP mode in the 3D preview and tap a point."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(gcps) { gcp in
                        Button {
                            showGCPList = false
                            selectedGCPID = gcp.id
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                editorState = GCPEditorState(existing: gcp, initialPoint: gcp)
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(gcp.label).font(.headline)
                                    Spacer()
                                    if !gcp.coordinateSystem.isEmpty {
                                        Text(gcp.coordinateSystem)
                                            .font(.caption2.monospaced())
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(.orange.opacity(0.18), in: Capsule())
                                    }
                                }
                                Text(String(format: "Local: %.3f, %.3f, %.3f m", gcp.localX, gcp.localY, gcp.localZ))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                if gcp.targetX != nil || gcp.targetY != nil || gcp.targetZ != nil {
                                    let tx = gcp.targetX.map { String(format: "%.4f", $0) } ?? "–"
                                    let ty = gcp.targetY.map { String(format: "%.4f", $0) } ?? "–"
                                    let tz = gcp.targetZ.map { String(format: "%.3f", $0) } ?? "–"
                                    Text(L("Ref: %@, %@, %@", tx, ty, tz))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.orange)
                                }
                                if !gcp.note.isEmpty {
                                    Text(gcp.note).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .onDelete { offsets in
                        gcps.remove(atOffsets: offsets)
                        selectedGCPID = nil
                        onSaveGCPs?(gcps)
                    }
                }
            }
            .navigationTitle(L("Ground Control Points"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !gcps.isEmpty {
                        Button {
                            exportGCPCSV()
                        } label: {
                            Label(L("Export CSV"), systemImage: "square.and.arrow.up")
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Done")) { showGCPList = false }
                }
            }
        }
    }

    private func openNewGCP(at point: SIMD3<Float>) {
        let nextIndex = gcps.count + 1
        let defaultCRS = gcps.last(where: { !$0.coordinateSystem.isEmpty })?.coordinateSystem ?? ""
        let gcp = GroundControlPoint.fromARKit(point, label: "GCP-\(nextIndex)", coordinateSystem: defaultCRS)
        selectedGCPID = gcp.id
        editorState = GCPEditorState(existing: nil, initialPoint: gcp)
    }

    private func saveGCP(_ point: GroundControlPoint, isNew: Bool) {
        if isNew {
            gcps.append(point)
        } else if let idx = gcps.firstIndex(where: { $0.id == point.id }) {
            gcps[idx] = point
        }
        selectedGCPID = point.id
        onSaveGCPs?(gcps)
    }

    private func deleteGCP(_ point: GroundControlPoint) {
        gcps.removeAll { $0.id == point.id }
        if selectedGCPID == point.id { selectedGCPID = nil }
        onSaveGCPs?(gcps)
    }

    private var allAnnotationTags: [String] {
        CloudAnnotation.normalizedTags(annotations.flatMap(\.tags))
    }

    private func handleAnnotationTap(at point: SIMD3<Float>) {
        if let editing = editingGeometryAnnotation {
            if editing.type == .point {
                draftAnnotationPoints = [point]
            } else {
                draftAnnotationPoints.append(point)
            }
            return
        }
        switch annotationShape {
        case .point:
            openNewAnnotation(type: .point, arkitVertices: [point])
        case .polygon:
            draftAnnotationPoints.append(point)
        }
    }

    private func finishDraftAnnotation() {
        guard annotationShape == .polygon, draftAnnotationPoints.count >= 3 else { return }
        let pts = draftAnnotationPoints
        draftAnnotationPoints = []
        openNewAnnotation(type: .polygon, arkitVertices: pts)
    }

    private func commitGeometryEdit() {
        guard var updated = editingGeometryAnnotation else { return }
        let minCount = updated.type == .point ? 1 : 3
        guard draftAnnotationPoints.count >= minCount else { return }
        updated.vertices = draftAnnotationPoints.map(AnnotationPoint3D.fromARKit)
        editingGeometryAnnotation = nil
        draftAnnotationPoints = []
        saveAnnotation(updated, isNew: false)
    }

    private func cancelGeometryEdit() {
        editingGeometryAnnotation = nil
        draftAnnotationPoints = []
    }

    private func openNewAnnotation(type: CloudAnnotationGeometryType, arkitVertices: [SIMD3<Float>]) {
        let nextIndex = annotations.count + 1
        let defaultColor = AnnotationColor.allCases[(nextIndex - 1) % AnnotationColor.allCases.count]
        let defaultTags: [String]
        if let activeTagFilter, activeTagFilter != "__untagged__" {
            defaultTags = [activeTagFilter]
        } else {
            defaultTags = []
        }
        let ann = CloudAnnotation(
            title: "A-\(nextIndex)",
            type: type,
            vertices: arkitVertices.map(AnnotationPoint3D.fromARKit),
            tags: defaultTags,
            color: defaultColor
        )
        selectedAnnotationID = ann.id
        annotationEditorState = AnnotationEditorState(existing: nil, initial: ann)
    }

    private func saveAnnotation(_ ann: CloudAnnotation, isNew: Bool) {
        if isNew {
            annotations.append(ann)
        } else if let idx = annotations.firstIndex(where: { $0.id == ann.id }) {
            annotations[idx] = ann
        }
        selectedAnnotationID = ann.id
        onSaveAnnotations?(annotations)
    }

    private func deleteAnnotation(_ ann: CloudAnnotation) {
        annotations.removeAll { $0.id == ann.id }
        if selectedAnnotationID == ann.id { selectedAnnotationID = nil }
        onSaveAnnotations?(annotations)
    }

    private func exportGCPCSV() {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("gcps.csv")
        do {
            try ScanStorage.gcpCSVData(for: gcps).write(to: tempURL, options: .atomic)
            showGCPList = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                sharedGCPFile = SharedFiles(urls: [tempURL])
            }
        } catch {}
    }
}

private struct GCPEditorSheet: View {
    let initial: GroundControlPoint
    let isNew: Bool
    let onSave: (GroundControlPoint) -> Void
    let onDelete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var label: String
    @State private var targetX: String
    @State private var targetY: String
    @State private var targetZ: String
    @State private var crs: String
    @State private var note: String

    init(initial: GroundControlPoint, isNew: Bool, onSave: @escaping (GroundControlPoint) -> Void, onDelete: (() -> Void)?) {
        self.initial = initial
        self.isNew = isNew
        self.onSave = onSave
        self.onDelete = onDelete
        _label = State(initialValue: initial.label)
        _targetX = State(initialValue: initial.targetX.map { String($0) } ?? "")
        _targetY = State(initialValue: initial.targetY.map { String($0) } ?? "")
        _targetZ = State(initialValue: initial.targetZ.map { String($0) } ?? "")
        _crs = State(initialValue: initial.coordinateSystem)
        _note = State(initialValue: initial.note)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L("Point Identifier")) {
                    TextField(L("Label (e.g. GCP-1)"), text: $label)
                    HStack {
                        Text(L("Local (X, Y, Z)"))
                        Spacer()
                        Text(String(format: "%.3f, %.3f, %.3f m", initial.localX, initial.localY, initial.localZ))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                Section(L("Reference Coordinates (Optional)")) {
                    TextField(L("Target X / Easting / Lon"), text: $targetX)
                        .keyboardType(.numbersAndPunctuation)
                    TextField(L("Target Y / Northing / Lat"), text: $targetY)
                        .keyboardType(.numbersAndPunctuation)
                    TextField(L("Target Z / Elevation (m)"), text: $targetZ)
                        .keyboardType(.numbersAndPunctuation)
                    TextField(L("CRS (e.g. EPSG:31256 or EPSG:4326)"), text: $crs)
                        .textInputAutocapitalization(.characters)
                }
                Section(L("Notes")) {
                    TextField(L("Target / Nail / Trench note"), text: $note)
                }
                if let onDelete {
                    Section {
                        Button(L("Delete GCP"), role: .destructive) {
                            onDelete()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isNew ? L("New GCP") : L("Edit GCP"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Save")) {
                        var updated = initial
                        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.label = trimmedLabel.isEmpty ? initial.label : trimmedLabel
                        updated.targetX = parseDouble(targetX)
                        updated.targetY = parseDouble(targetY)
                        updated.targetZ = parseDouble(targetZ)
                        updated.coordinateSystem = crs.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(updated)
                        dismiss()
                    }
                }
            }
        }
    }

    private func parseDouble(_ text: String) -> Double? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        return normalized.isEmpty ? nil : Double(normalized)
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
