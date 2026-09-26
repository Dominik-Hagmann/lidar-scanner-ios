import SwiftUI
import MetalKit
import MetalSplatter
import SplatIO
import simd

struct GaussianPreviewSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    @State private var loading = true
    var body: some View {
        NavigationStack {
            GaussianMetalView(url: url, loading: $loading, error: $error)
                .ignoresSafeArea(edges: .bottom)
                .overlay {
                    if loading { ProgressView("Loading 3D scene…").padding().background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16)) }
                    if let error { Text(error).padding().background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16)) }
                }
                .overlay(alignment: .bottom) {
                    Text("Drag to Rotate · Pinch to Zoom").font(.caption).padding()
                        .background(.ultraThinMaterial, in: Capsule()).padding(.bottom, 24)
                }
                .navigationTitle("3D Scene").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

private struct GaussianMetalView: UIViewRepresentable {
    let url: URL
    @Binding var loading: Bool
    @Binding var error: String?
    func makeCoordinator() -> Renderer { Renderer() }
    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.colorPixelFormat = .bgra8Unorm_srgb; view.depthStencilPixelFormat = .invalid
        view.preferredFramesPerSecond = 30; view.backgroundColor = .black
        let renderer = context.coordinator
        renderer.view = view; view.delegate = renderer
        view.addGestureRecognizer(UIPanGestureRecognizer(target: renderer, action: #selector(Renderer.pan(_:))))
        view.addGestureRecognizer(UIPinchGestureRecognizer(target: renderer, action: #selector(Renderer.pinch(_:))))
        renderer.onFailure = { error = $0; loading = false }
        renderer.task = Task { @MainActor in
            do { try await renderer.load(url); if !Task.isCancelled { loading = false } }
            catch { if !Task.isCancelled { renderer.onFailure?(error.localizedDescription) } }
        }
        return view
    }
    func updateUIView(_ view: MTKView, context: Context) {}
    static func dismantleUIView(_ view: MTKView, coordinator: Renderer) {
        view.isPaused = true; view.delegate = nil; coordinator.task?.cancel()
    }

    @MainActor final class Renderer: NSObject, MTKViewDelegate {
        weak var view: MTKView?
        var task: Task<Void, Never>?
        var onFailure: ((String) -> Void)?
        var splats: SplatRenderer?
        var queue: MTLCommandQueue?
        var center = SIMD3<Float>(repeating: 0)
        var radius: Float = 1
        var yaw: Float = 0, pitch: Float = 0.15, zoom: Float = 1
        let semaphore = DispatchSemaphore(value: 2)

        func load(_ url: URL) async throws {
            #if arch(x86_64)
            throw GaussianError.message(String(localized: "The 3D viewer requires an Apple Silicon device."))
            #else
            guard let view, let device = view.device, let queue = device.makeCommandQueue() else {
                throw GaussianError.message(String(localized: "Metal graphics are unavailable."))
            }
            self.queue = queue
            let reader = try AutodetectSceneReader(url)
            let points = try await reader.readAll()
            try Task.checkCancellation()
            guard !points.isEmpty else { throw GaussianError.message(String(localized: "The scene contains no Gaussians.")) }
            var low = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
            var high = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
            for point in points where point.position.x.isFinite && point.position.y.isFinite && point.position.z.isFinite {
                low = simd_min(low, point.position); high = simd_max(high, point.position)
            }
            center = (low + high) / 2; radius = max(0.1, simd_length(high - low) / 2)
            guard radius.isFinite else { throw GaussianError.message(String(localized: "The scene contains invalid coordinates.")) }
            let renderer = try SplatRenderer(device: device, colorFormat: view.colorPixelFormat,
                depthFormat: .invalid, sampleCount: 1, maxViewCount: 1, maxSimultaneousRenders: 2, highQualityDepth: false,
                clearColor: MTLClearColor(red: 0.035, green: 0.055, blue: 0.07, alpha: 1))
            let chunk = try SplatChunk(device: device, from: points)
            await renderer.addChunk(chunk)
            try Task.checkCancellation(); splats = renderer
            #endif
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
