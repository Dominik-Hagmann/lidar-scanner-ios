import SwiftUI
import MetalKit
import MetalSplatter
import SplatIO
import simd

struct GaussianPreviewSheet: View {
    let url: URL
    let exportMetadata: AnnotationExportMetadata?
    let onSaveAnnotations: (([CloudAnnotation]) -> Void)?
    @Binding var isFullScreen: Bool
    let onClose: (() -> Void)?

    @ObservedObject private var language = LanguageManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    @State private var loading = true

    @State private var isAnnotateMode = false
    @State private var annotations: [CloudAnnotation]
    @State private var annotationShape: CloudAnnotationGeometryType = .point
    @State private var draftAnnotationPoints: [SIMD3<Float>] = []
    @State private var editingGeometryAnnotation: CloudAnnotation?
    @State private var selectedAnnotationID: UUID?
    @State private var activeTagFilter: String?
    @State private var annotationEditorState: AnnotationEditorState?
    @State private var showAnnotationList = false
    @StateObject private var projectionModel = AnnotationOverlayProjectionModel()

    init(
        url: URL,
        exportMetadata: AnnotationExportMetadata? = nil,
        annotations: [CloudAnnotation] = [],
        onSaveAnnotations: (([CloudAnnotation]) -> Void)? = nil,
        isFullScreen: Binding<Bool> = .constant(false),
        onClose: (() -> Void)? = nil
    ) {
        self.url = url
        self.exportMetadata = exportMetadata
        self._annotations = State(initialValue: annotations)
        self.onSaveAnnotations = onSaveAnnotations
        self._isFullScreen = isFullScreen
        self.onClose = onClose
    }

    private var allAnnotationTags: [String] {
        CloudAnnotation.normalizedTags(annotations.flatMap(\.tags))
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                GaussianMetalView(
                    url: url,
                    isAnnotateMode: isAnnotateMode,
                    annotations: annotations,
                    selectedAnnotationID: selectedAnnotationID,
                    activeTagFilter: activeTagFilter,
                    editingAnnotationID: editingGeometryAnnotation?.id,
                    draftAnnotationPoints: draftAnnotationPoints,
                    projectionModel: projectionModel,
                    onPickAnnotationPoint: handleAnnotationTap(at:),
                    loading: $loading,
                    error: $error
                )
                .ignoresSafeArea(edges: .bottom)

                AnnotationShapesCanvasOverlay(
                    projection: projectionModel,
                    isEditingDraft: editingGeometryAnnotation != nil
                )
                .ignoresSafeArea(edges: .bottom)

                AnnotationLabelsOverlayView(projection: projectionModel) { tappedID in
                    guard editingGeometryAnnotation == nil,
                          let ann = annotations.first(where: { $0.id == tappedID }) else { return }
                    selectedAnnotationID = ann.id
                    annotationEditorState = AnnotationEditorState(existing: ann, initial: ann)
                }

                if isAnnotateMode {
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
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                } else if !isFullScreen {
                    Text(L("Drag to Rotate · Pinch to Zoom"))
                        .font(.caption)
                        .padding(10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 20)
                }
            }
            .overlay {
                if loading {
                    ProgressView(L("Loading 3D scene…"))
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
                if let error {
                    Text(error)
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .navigationTitle(L("3D Scene")).navigationBarTitleDisplayMode(.inline)
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
                        isAnnotateMode.toggle()
                        if !isAnnotateMode {
                            draftAnnotationPoints = []
                            editingGeometryAnnotation = nil
                            selectedAnnotationID = nil
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: isAnnotateMode ? "highlighter" : "tag")
                            if !annotations.isEmpty {
                                Text("\(annotations.count)")
                                    .font(.caption2.bold().monospacedDigit())
                            }
                        }
                    }
                    .tint(isAnnotateMode ? .cyan : .primary)
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
                        isAnnotateMode = true
                    }
                )
            }
            .sheet(isPresented: $showAnnotationList) {
                AnnotationListSheet(
                    annotations: $annotations,
                    selectedAnnotationID: $selectedAnnotationID,
                    activeTagFilter: $activeTagFilter,
                    exportMetadata: exportMetadata,
                    onChanged: { updated in
                        onSaveAnnotations?(updated)
                    },
                    onEdit: { ann in
                        annotationEditorState = AnnotationEditorState(existing: ann, initial: ann)
                    }
                )
            }
        }
        .interactiveDismissDisabled(true)
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
}

struct GaussianMetalView: UIViewRepresentable {
    let url: URL
    let isAnnotateMode: Bool
    let annotations: [CloudAnnotation]
    let selectedAnnotationID: UUID?
    let activeTagFilter: String?
    let editingAnnotationID: UUID?
    let draftAnnotationPoints: [SIMD3<Float>]
    let projectionModel: AnnotationOverlayProjectionModel
    let onPickAnnotationPoint: (SIMD3<Float>) -> Void
    @Binding var loading: Bool
    @Binding var error: String?

    func makeCoordinator() -> Renderer { Renderer(self) }
    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.colorPixelFormat = .bgra8Unorm_srgb; view.depthStencilPixelFormat = .invalid
        view.preferredFramesPerSecond = 30; view.backgroundColor = .black
        let renderer = context.coordinator
        renderer.view = view; view.delegate = renderer
        let pan = UIPanGestureRecognizer(target: renderer, action: #selector(Renderer.pan(_:)))
        let pinch = UIPinchGestureRecognizer(target: renderer, action: #selector(Renderer.pinch(_:)))
        let tap = UITapGestureRecognizer(target: renderer, action: #selector(Renderer.handleTap(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = renderer
        view.addGestureRecognizer(pan)
        view.addGestureRecognizer(pinch)
        view.addGestureRecognizer(tap)
        renderer.onFailure = { error = $0; loading = false }
        renderer.task = Task { @MainActor in
            do { try await renderer.load(url); if !Task.isCancelled { loading = false } }
            catch { if !Task.isCancelled { renderer.onFailure?(error.localizedDescription) } }
        }
        return view
    }
    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.parent = self
    }
    static func dismantleUIView(_ view: MTKView, coordinator: Renderer) {
        view.isPaused = true; view.delegate = nil; coordinator.task?.cancel()
    }

    @MainActor final class Renderer: NSObject, MTKViewDelegate, UIGestureRecognizerDelegate {
        var parent: GaussianMetalView
        weak var view: MTKView?
        var task: Task<Void, Never>?
        var onFailure: ((String) -> Void)?
        var splats: SplatRenderer?
        var splatPositions: [SIMD3<Float>] = []
        var queue: MTLCommandQueue?
        var center = SIMD3<Float>(repeating: 0)
        var radius: Float = 1
        var yaw: Float = 0, pitch: Float = 0.15, zoom: Float = 1
        var lastViewMatrix = matrix_identity_float4x4
        var lastProjectionMatrix = matrix_identity_float4x4
        let semaphore = DispatchSemaphore(value: 2)

        init(_ parent: GaussianMetalView) {
            self.parent = parent
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        func load(_ url: URL) async throws {
            #if arch(x86_64)
            throw GaussianError.message(LanguageManager.string("The 3D viewer requires an Apple Silicon device."))
            #else
            guard let view, let device = view.device, let queue = device.makeCommandQueue() else {
                throw GaussianError.message(LanguageManager.string("Metal graphics are unavailable."))
            }
            self.queue = queue
            let reader = try AutodetectSceneReader(url)
            let points = try await reader.readAll()
            try Task.checkCancellation()
            guard !points.isEmpty else { throw GaussianError.message(LanguageManager.string("The scene contains no Gaussians.")) }
            var low = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
            var high = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
            var sampled: [SIMD3<Float>] = []
            let maxSamples = 60_000
            let strideStep = max(1, points.count / maxSamples)
            sampled.reserveCapacity(min(points.count, maxSamples))
            for (idx, point) in points.enumerated() where point.position.x.isFinite && point.position.y.isFinite && point.position.z.isFinite {
                low = simd_min(low, point.position); high = simd_max(high, point.position)
                if idx % strideStep == 0 {
                    sampled.append(point.position)
                }
            }
            splatPositions = sampled
            center = (low + high) / 2; radius = max(0.1, simd_length(high - low) / 2)
            guard radius.isFinite else { throw GaussianError.message(LanguageManager.string("The scene contains invalid coordinates.")) }
            let renderer = try SplatRenderer(device: device, colorFormat: view.colorPixelFormat,
                depthFormat: .invalid, sampleCount: 1, maxViewCount: 1, maxSimultaneousRenders: 2, highQualityDepth: false,
                clearColor: MTLClearColor(red: 0.035, green: 0.055, blue: 0.07, alpha: 1))
            let chunk = try SplatChunk(device: device, from: points)
            await renderer.addChunk(chunk)
            try Task.checkCancellation(); splats = renderer
            #endif
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard parent.isAnnotateMode, let view, !splatPositions.isEmpty else { return }
            let location = gesture.location(in: view)
            let size = view.bounds.size
            guard size.width > 0, size.height > 0 else { return }

            let maxScreenDistance: Float = 44.0
            var closestDistance = maxScreenDistance
            var closestZ: Float = .greatestFiniteMagnitude
            var bestPoint: SIMD3<Float>?
            let vp = lastProjectionMatrix * lastViewMatrix

            for p in splatPositions {
                guard let proj = Self.project(p, viewProj: vp, viewSize: size) else { continue }
                let dx = Float(proj.point.x) - Float(location.x)
                let dy = Float(proj.point.y) - Float(location.y)
                let dist = hypot(dx, dy)
                if dist < closestDistance || (abs(dist - closestDistance) < 5.0 && proj.depth < closestZ) {
                    closestDistance = dist
                    closestZ = proj.depth
                    bestPoint = p
                }
            }
            if let bestPoint {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                parent.onPickAnnotationPoint(bestPoint)
            }
        }

        @objc func pan(_ gesture: UIPanGestureRecognizer) {
            let offset = gesture.translation(in: view); gesture.setTranslation(.zero, in: view)
            yaw -= Float(offset.x) * 0.006
            pitch = min(1.45, max(-1.45, pitch + Float(offset.y) * 0.006))
        }
        @objc func pinch(_ gesture: UIPinchGestureRecognizer) {
            zoom = min(10, max(0.15, zoom / Float(gesture.scale))); gesture.scale = 1
        }
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        private static func project(_ pos: SIMD3<Float>, viewProj: simd_float4x4, viewSize: CGSize) -> (point: CGPoint, depth: Float)? {
            let clip = viewProj * SIMD4<Float>(pos, 1)
            guard clip.w > 0.0001 else { return nil }
            let ndc = SIMD3<Float>(clip.x, clip.y, clip.z) / clip.w
            guard ndc.z >= 0 && ndc.z <= 1, ndc.x.isFinite && ndc.y.isFinite else { return nil }
            let x = CGFloat(ndc.x * 0.5 + 0.5) * viewSize.width
            let y = CGFloat(0.5 - ndc.y * 0.5) * viewSize.height
            return (CGPoint(x: x, y: y), ndc.z)
        }

        private func updateProjectedOverlays(viewProj: simd_float4x4, viewSize: CGSize) {
            guard viewSize.width > 0, viewSize.height > 0 else { return }
            let visible = parent.annotations.filter { ann in
                guard let filter = parent.activeTagFilter else { return true }
                if filter == "__untagged__" { return ann.tags.isEmpty }
                return ann.tags.contains { $0.caseInsensitiveCompare(filter) == .orderedSame }
            }
            let selectedID = parent.selectedAnnotationID
            let editingID = parent.editingAnnotationID
            let marginBounds = CGRect(origin: .zero, size: viewSize).insetBy(dx: -80, dy: -80)

            var labels: [ProjectedAnnotationLabel] = []
            var shapes: [ProjectedAnnotationShape] = []
            for ann in visible where !ann.vertices.isEmpty {
                let centroid = ann.centroid.arkitPosition
                if let cProj = Self.project(centroid, viewProj: viewProj, viewSize: viewSize),
                   marginBounds.contains(cProj.point) {
                    labels.append(ProjectedAnnotationLabel(
                        id: ann.id,
                        title: ann.title,
                        primaryTag: ann.tags.first,
                        color: ann.color,
                        type: ann.type,
                        screenPoint: cProj.point,
                        isSelected: ann.id == selectedID
                    ))
                }
                if ann.id != editingID {
                    let screenPts = ann.vertices.compactMap { v -> CGPoint? in
                        Self.project(v.arkitPosition, viewProj: viewProj, viewSize: viewSize)?.point
                    }
                    if screenPts.count == ann.vertices.count {
                        shapes.append(ProjectedAnnotationShape(
                            id: ann.id,
                            color: ann.color,
                            isPolygon: ann.type != .point && screenPts.count >= 2,
                            isSelected: ann.id == selectedID,
                            points: screenPts
                        ))
                    }
                }
            }

            let draftPts: [CGPoint] = parent.isAnnotateMode
                ? parent.draftAnnotationPoints.compactMap { Self.project($0, viewProj: viewProj, viewSize: viewSize)?.point }
                : []
            let model = parent.projectionModel
            DispatchQueue.main.async {
                model.update(labels: labels, shapes: shapes, draftPoints: draftPts)
            }
        }

        func draw(in view: MTKView) {
            guard let splats, splats.isReadyToRender, let queue,
                  view.drawableSize.width > 0, view.drawableSize.height > 0,
                  semaphore.wait(timeout: .now()) == .success else { return }
            guard let buffer = queue.makeCommandBuffer(), let drawable = view.currentDrawable else { semaphore.signal(); return }
            let semaphore = semaphore
            buffer.addCompletedHandler { _ in semaphore.signal() }
            let eye = center + radius * 3 * zoom * SIMD3<Float>(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
            let z = simd_normalize(eye - center), x = simd_normalize(simd_cross(SIMD3<Float>(0, 1, 0), z)), y = simd_cross(z, x)
            let matrix = simd_float4x4(columns: (
                SIMD4(x.x, y.x, z.x, 0), SIMD4(x.y, y.y, z.y, 0), SIMD4(x.z, y.z, z.z, 0),
                SIMD4(-simd_dot(x, eye), -simd_dot(y, eye), -simd_dot(z, eye), 1)))
            let near: Float = max(0.001, radius / 1000), far: Float = max(100, radius * 100)
            let sy: Float = 1 / tan(.pi / 6), sx = sy / Float(view.drawableSize.width / view.drawableSize.height)
            let projection = simd_float4x4(columns: (
                SIMD4(sx, 0, 0, 0), SIMD4(0, sy, 0, 0), SIMD4(0, 0, far / (near - far), -1),
                SIMD4(0, 0, near * far / (near - far), 0)))
            lastViewMatrix = matrix
            lastProjectionMatrix = projection
            updateProjectedOverlays(viewProj: projection * matrix, viewSize: view.bounds.size)
            let viewport = SplatRenderer.ViewportDescriptor(viewport: MTLViewport(originX: 0, originY: 0,
                width: view.drawableSize.width, height: view.drawableSize.height, znear: 0, zfar: 1),
                projectionMatrix: projection, viewMatrix: matrix,
                screenSize: SIMD2(Int(view.drawableSize.width), Int(view.drawableSize.height)))
            do {
                if try splats.render(viewports: [viewport], colorTexture: drawable.texture, colorStoreAction: .store,
                    depthTexture: nil, rasterizationRateMap: nil, renderTargetArrayLength: 0, to: buffer) { buffer.present(drawable) }
            } catch { view.isPaused = true; onFailure?(error.localizedDescription) }
            buffer.commit()
        }
    }
}
