import SwiftUI

struct ScannerView: View {
    @ObservedObject var model: ScanModel
    @ObservedObject private var torch = TorchService.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var showPoints = true
    @State private var showSettings = false
    @State private var showArchive = false
    @State private var showExport = false
    @State private var showPreview = false
    @State private var previewFullScreen = false
    @State private var confirmReset = false
    private let mint = Color(red: 0.38, green: 0.93, blue: 0.76)

    var body: some View {
        ZStack {
            Color(red: 0.035, green: 0.055, blue: 0.07).ignoresSafeArea()
            if model.supported && !model.cameraDenied {
                LiveCameraView(model: model, showPoints: showPoints).ignoresSafeArea()
                LinearGradient(colors: [.black.opacity(0.7), .clear, .black.opacity(0.4)],
                               startPoint: .top, endPoint: .bottom).ignoresSafeArea().allowsHitTesting(false)
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "viewfinder").font(.system(size: 64, weight: .ultraLight)).foregroundStyle(mint)
                    Text(LocalizedStringKey(model.cameraDenied ? "Allow Camera Access" : "LiDAR Sensor Required"))
                        .font(.title2.bold())
                    Text(model.notice).multilineTextAlignment(.center).foregroundStyle(.secondary)
                    if model.cameraDenied {
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }.buttonStyle(.borderedProminent)
                    }
                }.padding(32)
            }
            VStack(spacing: 16) {
                header
                HStack(spacing: 8) {
                    Circle().fill(model.trackingNormal ? mint : .orange).frame(width: 7, height: 7)
                    Text(model.trackingText).font(.subheadline.weight(.medium))
                    Spacer()
                    if model.isRecording {
                        Circle().fill(.red).frame(width: 7, height: 7)
                        Text("REC").font(.caption.bold()).monospaced()
                    }
                }.padding(12).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                Spacer()
                if model.supported && !model.cameraDenied {
                    HStack {
                        Spacer()
                        VStack(spacing: 12) {
                            if torch.isAvailable {
                                Button { torch.toggle() } label: {
                                    Image(systemName: torch.isOn ? "flashlight.on.fill" : "flashlight.off.fill")
                                        .font(.title3)
                                        .foregroundStyle(torch.isOn ? .yellow : .white)
                                        .frame(width: 48, height: 48)
                                        .background(.ultraThinMaterial, in: Circle())
                                }.accessibilityLabel(LocalizedStringKey(torch.isOn ? "Turn Off Torch" : "Turn On Torch"))
                            }
                            Button { showPoints.toggle() } label: {
                                Image(systemName: showPoints ? "circle.hexagongrid.fill" : "circle.hexagongrid")
                                    .font(.title3).frame(width: 48, height: 48)
                                    .background(.ultraThinMaterial, in: Circle())
                            }.accessibilityLabel(LocalizedStringKey(showPoints ? "Hide Points" : "Show Points"))
                        }
                    }
                }
            }.padding(20)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { controls }
        .task { model.enterMode() }
        .onChange(of: scenePhase) { _, phase in
            model.sceneChanged(phase)
            if phase != .active { torch.turnOff() }
        }
        .onDisappear { torch.turnOff() }
        .sheet(isPresented: $showSettings) { SettingsSheet(model: model) }
        .sheet(isPresented: $showArchive) { ArchiveSheet(model: model) }
        .sheet(isPresented: $showExport) { ExportSheet(model: model) }
        .sheet(isPresented: Binding(
            get: { showPreview && !previewFullScreen },
            set: { if !$0 && !previewFullScreen { showPreview = false } }
        )) {
            CloudPreviewSheet(
                points: model.preview,
                total: model.pointCount,
                isFullScreen: $previewFullScreen,
                exportFullGaussians: { try await model.makeGaussianExportURL() },
                onClose: { showPreview = false; previewFullScreen = false }
            )
        }
        .fullScreenCover(isPresented: $previewFullScreen) {
            CloudPreviewSheet(
                points: model.preview,
                total: model.pointCount,
                isFullScreen: $previewFullScreen,
                exportFullGaussians: { try await model.makeGaussianExportURL() },
                onClose: { showPreview = false; previewFullScreen = false }
            )
        }
        .sheet(item: $model.sharedFiles) { ShareSheet(urls: $0.urls) }
        .alert("Start a New Scan?", isPresented: $confirmReset) {
            Button("Cancel", role: .cancel) {}
            Button("New Scan", role: .destructive) { model.newScan() }
        } message: {
            Text("The current point cloud will be cleared from memory. Previously saved scans will be kept. If saving failed, export the scan again first.")
        }
        .alert("LiDAR-Scanner", isPresented: Binding(get: { model.errorMessage != nil && !showArchive && !showExport },
                                                  set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("LiDAR-Scanner").font(.system(size: 20, weight: .bold, design: .rounded))
                    .lineLimit(1).minimumScaleFactor(0.75)
                Text("LiDAR · Scene to Point Cloud").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                model.refreshArchive()
                showArchive = true
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
                    .contentShape(Circle())
            }
            .accessibilityLabel("Saved Scans")
            .disabled(model.isBusy || model.isRecording)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showSettings = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
                    .contentShape(Circle())
            }
            .accessibilityLabel("Scan Settings")
            .disabled(model.isBusy || model.isRecording)
        }.foregroundStyle(.white)
    }

    private var controls: some View {
        let canCapture = !model.isBusy && !model.sessionClosed && model.ready && model.trackingNormal
        return VStack(spacing: 14) {
            if model.pointCount == 0 && !model.isRecording {
                if model.supported && !model.cameraDenied {
                    Text(model.notice)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button {
                    model.toggleRecording()
                } label: {
                    Label("Start Scan", systemImage: "record.circle")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 46)
                }
                .buttonStyle(.borderedProminent)
                .tint(canCapture ? mint : Color.white.opacity(0.16))
                .foregroundStyle(canCapture ? Color.black : Color.white.opacity(0.72))
                .disabled(!canCapture)
            } else {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.pointCount.formatted()).font(.system(size: 32, weight: .semibold, design: .rounded))
                            .monospacedDigit().contentTransition(.numericText())
                        Text("POINTS").font(.caption2.weight(.semibold)).tracking(1.5).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(String(format: "%02d:%02d", Int(model.activeSeconds)/60, Int(model.activeSeconds)%60))
                            .font(.title3.monospacedDigit())
                        Text("CAPTURE TIME").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Text(model.notice).font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)

                if model.isRecording {
                    Button { model.toggleRecording() } label: {
                        Label("Pause", systemImage: "pause.fill")
                            .font(.headline).frame(maxWidth: .infinity, minHeight: 46)
                    }
                    .buttonStyle(.borderedProminent).tint(.orange)
                    .foregroundStyle(.black)
                } else {
                    HStack(spacing: 12) {
                        Button { model.toggleRecording() } label: {
                            Label("Resume", systemImage: "record.circle")
                                .font(.headline).frame(maxWidth: .infinity, minHeight: 46)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(canCapture ? mint : Color.white.opacity(0.16))
                        .foregroundStyle(canCapture ? Color.black : Color.white.opacity(0.72))
                        .disabled(!canCapture)

                        Button { showPreview = true } label: {
                            Label("3D View", systemImage: "cube.transparent")
                                .font(.headline).frame(maxWidth: .infinity, minHeight: 46)
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.preview.isEmpty || model.isBusy)
                        .accessibilityLabel("View Point Cloud in 3D")
                    }
                    HStack {
                        Button("New Scan", systemImage: "plus") {
                            confirmReset = true
                        }
                        .disabled(model.isBusy || !model.supported || model.cameraDenied)

                        Spacer()

                        Menu {
                            Button {
                                showExport = true
                            } label: {
                                Label("Export Point Cloud", systemImage: "doc.badge.gearshape")
                            }

                            Button {
                                model.saveCurrent(share: true, report: false)
                            } label: {
                                Label("Share Point Cloud", systemImage: "cube.transparent")
                            }

                            Button {
                                model.exportGaussians()
                            } label: {
                                Label("Export 3D Gaussian Splats", systemImage: "aqi.medium")
                            }

                            Menu {
                                ForEach(ExportFormat.allCases) { format in
                                    Button(format.title) {
                                        model.exportFormat = format
                                        model.saveCurrent(share: true, report: false)
                                    }
                                }
                            } label: {
                                Label("Export Formats", systemImage: "arrow.triangle.branch")
                            }

                            Button {
                                model.exportReport()
                            } label: {
                                Label("Export Report", systemImage: "doc.richtext")
                            }
                        } label: {
                            if model.isBusy { ProgressView().padding(.trailing, 4) }
                            Label(LocalizedStringKey(model.isBusy ? "Saving…" : "Share"), systemImage: "square.and.arrow.up")
                        }
                        .disabled(model.isBusy)
                    }.font(.subheadline.weight(.medium))
                }
            }
        }
        .padding(20).frame(maxWidth: 680).frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28))
    }
}
