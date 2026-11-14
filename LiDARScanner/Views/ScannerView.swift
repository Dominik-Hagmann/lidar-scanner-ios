import SwiftUI

struct ScannerView: View {
    @ObservedObject var model: ScanModel
    @ObservedObject private var torch = TorchService.shared
    @ObservedObject private var language = LanguageManager.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var showPoints = true
    @State private var showMesh = false
    @State private var showSettings = false
    @State private var showArchive = false
    @State private var showDetails = false
    @State private var showExport = false
    @State private var showPreview = false
    @State private var previewMesh: MeshPreviewData?
    @State private var previewFullScreen = false
    @State private var confirmReset = false
    private let mint = Color(red: 0.38, green: 0.93, blue: 0.76)

    var body: some View {
        ZStack {
            Color(red: 0.035, green: 0.055, blue: 0.07).ignoresSafeArea()
            if model.supported && !model.cameraDenied {
                LiveCameraView(model: model, showPoints: showPoints, showMesh: showMesh).ignoresSafeArea()
                LinearGradient(colors: [.black.opacity(0.7), .clear, .black.opacity(0.4)],
                               startPoint: .top, endPoint: .bottom).ignoresSafeArea().allowsHitTesting(false)
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "viewfinder").font(.system(size: 64, weight: .ultraLight)).foregroundStyle(mint)
                    Text(L(model.cameraDenied ? "Allow Camera Access" : "LiDAR Sensor Required"))
                        .font(.title2.bold())
                    Text(model.notice).multilineTextAlignment(.center).foregroundStyle(.secondary)
                    if model.cameraDenied {
                        Button(L("Open Settings")) {
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
                        Text(L("REC")).font(.caption.bold()).monospaced()
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
                                }.accessibilityLabel(L(torch.isOn ? "Turn Off Torch" : "Turn On Torch"))
                            }
                            Button { showPoints.toggle() } label: {
                                Image(systemName: showPoints ? "circle.hexagongrid.fill" : "circle.hexagongrid")
                                    .font(.title3)
                                    .foregroundStyle(showPoints ? mint : .white)
                                    .frame(width: 48, height: 48)
                                    .background(.ultraThinMaterial, in: Circle())
                            }.accessibilityLabel(L(showPoints ? "Hide Points" : "Show Points"))

                            Button { showMesh.toggle() } label: {
                                Image(systemName: showMesh ? "cube.fill" : "cube")
                                    .font(.title3)
                                    .foregroundStyle(showMesh ? mint : .white)
                                    .frame(width: 48, height: 48)
                                    .background(.ultraThinMaterial, in: Circle())
                            }.accessibilityLabel(L(showMesh ? "Hide Mesh" : "Show Mesh"))
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
        .sheet(isPresented: $showDetails) { PointCloudDetailsView(model: model) }
        .sheet(isPresented: $showExport) { ExportSheet(model: model) }
        .sheet(isPresented: Binding(
            get: { showPreview && !previewFullScreen },
            set: { if !$0 && !previewFullScreen { showPreview = false } }
        )) {
            CloudPreviewSheet(
                points: model.preview,
                total: model.pointCount,
                mesh: previewMesh,
                groundControlPoints: model.activeGroundControlPoints,
                onSaveGCPs: { model.updateGroundControlPoints(for: nil, points: $0) },
                annotations: model.activeAnnotations,
                onSaveAnnotations: { model.updateAnnotations(for: nil, annotations: $0) },
                isFullScreen: $previewFullScreen,
                onClose: { showPreview = false; previewFullScreen = false; previewMesh = nil }
            )
        }
        .fullScreenCover(isPresented: $previewFullScreen) {
            CloudPreviewSheet(
                points: model.preview,
                total: model.pointCount,
                mesh: previewMesh,
                groundControlPoints: model.activeGroundControlPoints,
                onSaveGCPs: { model.updateGroundControlPoints(for: nil, points: $0) },
                annotations: model.activeAnnotations,
                onSaveAnnotations: { model.updateAnnotations(for: nil, annotations: $0) },
                isFullScreen: $previewFullScreen,
                onClose: { showPreview = false; previewFullScreen = false; previewMesh = nil }
            )
        }
        .sheet(item: $model.sharedFiles) { ShareSheet(urls: $0.urls) }
        .alert(L("Start a New Scan?"), isPresented: $confirmReset) {
            Button(L("Cancel"), role: .cancel) {}
            Button(L("New Scan"), role: .destructive) { model.newScan() }
        } message: {
            Text(L("The current point cloud will be cleared from memory. Previously saved scans will be kept. If saving failed, export the scan again first."))
        }
        .alert(L("LiDAR Scanner"), isPresented: Binding(get: { model.errorMessage != nil && !showArchive && !showExport && !showDetails },
                                                  set: { if !$0 { model.errorMessage = nil } })) {
            Button(L("OK")) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(L("LiDAR Scanner")).font(.system(size: 20, weight: .bold, design: .rounded))
                    .lineLimit(1).minimumScaleFactor(0.75)
                Text(L("LiDAR · Scene to Point Cloud")).font(.caption).foregroundStyle(.secondary)
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
            .accessibilityLabel(L("Saved Scans"))
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
            .accessibilityLabel(L("Scan Settings"))
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
                    Label(L("Start Scan"), systemImage: "record.circle")
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
                        Text(L("POINTS")).font(.caption2.weight(.semibold)).tracking(1.5).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(String(format: "%02d:%02d", Int(model.activeSeconds)/60, Int(model.activeSeconds)%60))
                            .font(.title3.monospacedDigit())
                        Text(L("CAPTURE TIME")).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(model.notice).font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                    Button(L("Details"), systemImage: "info.circle") { showDetails = true }
                        .font(.subheadline.weight(.medium))
                        .fixedSize()
                }

                if model.isRecording {
                    Button { model.toggleRecording() } label: {
                        Label(L("Pause"), systemImage: "pause.fill")
                            .font(.headline).frame(maxWidth: .infinity, minHeight: 46)
                    }
                    .buttonStyle(.borderedProminent).tint(.orange)
                    .foregroundStyle(.black)
                } else {
                    HStack(spacing: 12) {
                        Button { model.toggleRecording() } label: {
                            Label(L("Resume"), systemImage: "record.circle")
                                .font(.headline).frame(maxWidth: .infinity, minHeight: 46)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(canCapture ? mint : Color.white.opacity(0.16))
                        .foregroundStyle(canCapture ? Color.black : Color.white.opacity(0.72))
                        .disabled(!canCapture)

                        Button {
                            previewMesh = model.currentMeshPreviewData()
                            showPreview = true
                        } label: {
                            Label(L("3D View"), systemImage: "cube.transparent")
                                .font(.headline).frame(maxWidth: .infinity, minHeight: 46)
                        }
                        .buttonStyle(.bordered)
                        .disabled((model.preview.isEmpty && !model.hasMesh) || model.isBusy)
                        .accessibilityLabel(L("View Point Cloud in 3D"))
                    }
                    HStack {
                        Button(L("New Scan"), systemImage: "plus") {
                            confirmReset = true
                        }
                        .disabled(model.isBusy || !model.supported || model.cameraDenied)

                        Spacer()

                        Menu {
                            Section {
                                Button {
                                    model.saveCurrent(share: true)
                                } label: {
                                    Label(L("Share Point Cloud"), systemImage: "cube.transparent")
                                }

                                Menu {
                                    ForEach(ExportFormat.allCases) { format in
                                        Button {
                                            model.exportFormat = format
                                            model.saveCurrent(share: true)
                                        } label: {
                                            if format == model.exportFormat {
                                                Label(format.title, systemImage: "checkmark")
                                            } else {
                                                Text(format.title)
                                            }
                                        }
                                    }
                                } label: {
                                    Label(L("Export Formats"), systemImage: "arrow.triangle.branch")
                                }

                                Button {
                                    showExport = true
                                } label: {
                                    Label(L("Export Point Cloud…"), systemImage: "doc.badge.gearshape")
                                }

                                if model.hasMesh {
                                    Button {
                                        model.saveCurrent(share: false, shareMesh: true)
                                    } label: {
                                        Label(L("Export 3D Mesh (OBJ)"), systemImage: "cube")
                                    }
                                }
                            }

                            if !model.activeGroundControlPoints.isEmpty || !model.activeAnnotations.isEmpty {
                                Section {
                                    if !model.activeGroundControlPoints.isEmpty {
                                        Button {
                                            model.shareActiveGCPs()
                                        } label: {
                                            Label(L("Export Ground Control Points (CSV)"), systemImage: "scope")
                                        }
                                    }
                                    if !model.activeAnnotations.isEmpty {
                                        AnnotationExportMenu { kind in
                                            model.shareActiveAnnotations(kind)
                                        }
                                    }
                                }
                            }

                            Section {
                                ReportExportMenu { format in
                                    model.exportReport(format: format)
                                }
                            }
                        } label: {
                            if model.isBusy { ProgressView().padding(.trailing, 4) }
                            Label(L(model.isBusy ? "Saving…" : "Share"), systemImage: "square.and.arrow.up")
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

struct PointCloudDetailsView: View {
    @ObservedObject var model: ScanModel
    @ObservedObject private var language = LanguageManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let cfg = model.effectiveSettings
        NavigationStack {
            List {
                Section(L("Current State")) {
                    LabeledContent(L("Status"), value: model.detailStatusTitle)
                    LabeledContent(L("Points"), value: model.pointCount.formatted())
                    LabeledContent(
                        L("Capture Time"),
                        value: String(format: "%02d:%02d", Int(model.activeSeconds) / 60, Int(model.activeSeconds) % 60)
                    )
                    LabeledContent(L("Processed Frames"), value: model.processedFrames.formatted())
                    LabeledContent(L("Accepted Samples"), value: model.acceptedSamples.formatted())
                    if model.depthWidth > 0 && model.depthHeight > 0 {
                        LabeledContent(L("Depth Resolution"), value: "\(model.depthWidth) × \(model.depthHeight)")
                    }
                    if model.hasMesh {
                        LabeledContent(L("Surface Mesh (OBJ)"), value: L("Captured"))
                    }
                    if !model.activeGroundControlPoints.isEmpty {
                        LabeledContent(L("Ground Control Points"), value: model.activeGroundControlPoints.count.formatted())
                    }
                    if !model.activeAnnotations.isEmpty {
                        LabeledContent(L("3D Annotations"), value: model.activeAnnotations.count.formatted())
                    }
                }
                Section(L("What Happened")) {
                    Text(L("Depth points from ARKit sceneDepth and camera colors are accumulated on this device into a local voxel grid without averaging or server uploads."))
                    if let reason = model.currentClosedReasonText {
                        Text(reason).textSelection(.enabled)
                    }
                    if let loc = model.currentLocationSnapshot {
                        LabeledContent(L("GNSS Location"), value: loc.formattedCoordinates)
                    }
                }
                Section {
                    ReportExportMenu { format in
                        model.exportReport(format: format)
                    }
                }.disabled(model.isBusy || model.isRecording || model.pointCount == 0)
                Section(L("Technical Details")) {
                    Text(L("Local right-handed Cartesian; Z up; no CRS/EPSG; no north alignment"))
                        .font(.caption).textSelection(.enabled)
                    LabeledContent(L("Voxel Size"), value: "\(cfg.voxelCentimeters) cm")
                    LabeledContent(L("Max Depth"), value: String(format: "%.1f m", cfg.maxDepth))
                    LabeledContent(L("Pixel Step"), value: "\(cfg.pixelStep)")
                    LabeledContent(L("Min Confidence"), value: "\(cfg.minConfidence)")
                    LabeledContent(L("Point Limit"), value: cfg.maxPoints == 0 ? L("Automatic") : cfg.maxPoints.formatted())
                    if let saved = model.savedScanDetail,
                       let data = try? GaussianStore.encoder.encode(saved.metadata),
                       let json = String(data: data, encoding: .utf8) {
                        Text(json).font(.caption.monospaced()).textSelection(.enabled)
                    }
                    Text(L("The report explains the capture in full sentences. Exported scans include metadata.json with the full parameters."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(L("Scan Details"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Done")) { dismiss() }
                }
            }
            .sheet(item: $model.sharedFiles) { ShareSheet(urls: $0.urls) }
            .alert(L("LiDAR Scanner"), isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
                Button(L("OK")) { model.errorMessage = nil }
            } message: { Text(model.errorMessage ?? "") }
        }
    }
}
