import SwiftUI

struct ScanModeView: View {
    @ObservedObject var pointCloud: ScanModel
    @StateObject private var gaussian = GaussianModel()
    @State private var mode = 0
    var body: some View {
        Group {
            if mode == 0 { ScannerView(model: pointCloud) }
            else { GaussianScannerView(model: gaussian) }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            Picker("Scan Mode", selection: $mode) {
                Text("Point Cloud").tag(0)
                Text("Gaussian Splatting").tag(1)
            }.pickerStyle(.segmented).padding(.horizontal, 20).padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .disabled(pointCloud.isRecording || pointCloud.isBusy || gaussian.isRecording || gaussian.isBusy)
        }
        .onChange(of: mode) { _, value in
            if value == 1 { pointCloud.leaveMode(); gaussian.enterMode() }
            else { gaussian.leaveMode(); pointCloud.enterMode() }
        }
    }
}
