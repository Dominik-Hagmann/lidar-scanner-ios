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
            let isLocked = pointCloud.isRecording || pointCloud.isBusy || gaussian.isRecording || gaussian.isBusy
            ZStack {
                Picker("Scan Mode", selection: $mode) {
                    Text("Point Cloud").tag(0)
                    Text("Gaussian Splatting").tag(1)
                }
                .pickerStyle(.segmented)
                .controlSize(.large)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)

                if !isLocked {
                    HStack(spacing: 0) {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if mode != 0 {
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    mode = 0
                                }
                            }
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if mode != 1 {
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    mode = 1
                                }
                            }
                    }
                }
            }
            .background(.ultraThinMaterial)
            .disabled(isLocked)
        }
        .onChange(of: mode) { _, value in
            if value == 1 { pointCloud.leaveMode(); gaussian.enterMode() }
            else { gaussian.leaveMode(); pointCloud.enterMode() }
        }
    }
}
