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

enum PreviewToolMode: Equatable {
    case view
    case measure
    case gcp
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
}

struct OrbitCloudView: UIViewRepresentable {
    let points: [PCPoint]
    let toolMode: PreviewToolMode
    @Binding var selectedA: SIMD3<Float>?
    @Binding var selectedB: SIMD3<Float>?
    let groundControlPoints: [GroundControlPoint]
    let selectedGCPID: UUID?
    let onPickGCPPoint: (SIMD3<Float>) -> Void

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: OrbitCloudView
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

        func updateVisuals() {
            overlayNode.childNodes.forEach { $0.removeFromParentNode() }
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
        scene.rootNode.addChildNode(SCNNode(geometry: PointGeometry.make(points)))
        scene.rootNode.addChildNode(context.coordinator.overlayNode)

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
    @Binding var isFullScreen: Bool
    let onClose: (() -> Void)?
    let onSaveGCPs: (([GroundControlPoint]) -> Void)?

    @State private var toolMode: PreviewToolMode = .view
    @State private var selectedA: SIMD3<Float>?
    @State private var selectedB: SIMD3<Float>?
    @State private var gcps: [GroundControlPoint]
    @State private var selectedGCPID: UUID?
    @State private var editorState: GCPEditorState?
    @State private var showGCPList = false
    @State private var sharedGCPFile: SharedFiles?
    @ObservedObject private var language = LanguageManager.shared
    @Environment(\.dismiss) private var dismiss

    private var measurementDistance: Float? {
        guard let a = selectedA, let b = selectedB else { return nil }
        return simd_distance(a, b)
    }

    init(
        points: [PCPoint],
        total: Int,
        groundControlPoints: [GroundControlPoint] = [],
        onSaveGCPs: (([GroundControlPoint]) -> Void)? = nil,
        isFullScreen: Binding<Bool> = .constant(false),
        onClose: (() -> Void)? = nil
    ) {
        self.points = points
        self.total = total
        self._gcps = State(initialValue: groundControlPoints)
        self.onSaveGCPs = onSaveGCPs
        self._isFullScreen = isFullScreen
        self.onClose = onClose
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                OrbitCloudView(
                    points: points,
                    toolMode: toolMode,
                    selectedA: $selectedA,
                    selectedB: $selectedB,
                    groundControlPoints: gcps,
                    selectedGCPID: selectedGCPID,
                    onPickGCPPoint: openNewGCP(at:)
                )
                .ignoresSafeArea(edges: .bottom)

                VStack(spacing: 10) {
                    if toolMode == .measure {
                        measurementCard
                    } else if toolMode == .gcp {
                        gcpCard
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
        } else {
            if target != .measure {
                selectedA = nil
                selectedB = nil
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
            if !gcps.isEmpty {
                Button {
                    showGCPList = true
                } label: {
                    Label(L("%@ Ground Control Points", gcps.count.formatted()), systemImage: "mappin.and.ellipse")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(.orange)
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
