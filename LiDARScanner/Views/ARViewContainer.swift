import RealityKit
import SwiftUI

struct ARViewContainer: UIViewRepresentable {
    let scanner: LiDARScanner

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero)
        view.automaticallyConfigureSession = false
        scanner.attach(session: view.session)
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}
