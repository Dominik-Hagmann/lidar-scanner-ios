import ARKit
import SwiftUI

struct GaussianScannerView: View {
    @ObservedObject var model: GaussianModel
    @ObservedObject private var torch = TorchService.shared
    @ObservedObject private var language = LanguageManager.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var details = false
    @State private var archive = false
    @State private var preview = false
    @State private var previewFullScreen = false
    @State private var showCredits = false
    private let mint = Color(red: 0.38, green: 0.93, blue: 0.76)

    var body: some View {
        ZStack {
            Color(red: 0.035, green: 0.055, blue: 0.07).ignoresSafeArea()
            if model.cameraReady {
                GaussianCameraView(session: model.session).ignoresSafeArea()
                LinearGradient(colors: [.black.opacity(0.7), .clear, .black.opacity(0.4)],
                    startPoint: .top, endPoint: .bottom).ignoresSafeArea().allowsHitTesting(false)
            }
            VStack(spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L("Gaussian Splatting")).font(.title3.bold())
                        Text(L("Capture · Create · Share")).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        model.refreshArchive()
                        archive = true
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
                        showCredits = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 18, weight: .medium))
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                            .contentShape(Circle())
                    }
                    .accessibilityLabel(L("Project & Credits"))
                    .disabled(model.isBusy || model.isRecording)
                }
                HStack {
                    Image(systemName: model.isRecording ? "record.circle" : "iphone")
                        .foregroundStyle(model.isRecording ? .red : mint)
                    Text(model.status).font(.subheadline)
                    Spacer(minLength: 0)
                }.padding(12).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                Spacer()
                if !model.cameraReady {
                    if let p = model.current, p.hasResult {
                        Button { preview = true } label: {
                            VStack(spacing: 16) {
                                Image(systemName: "cube.transparent").font(.system(size: 72, weight: .ultraLight))
                                Text(L("View 3D Scene")).font(.headline)
                            }.padding(32)
                        }.disabled(model.isBusy)
                    } else if model.isBusy {
                        ProgressView().controlSize(.large)
                    } else if model.cameraDenied {
                        Button(L("Open Settings")) {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }.buttonStyle(.borderedProminent)
                    } else if model.current == nil {
                        Image(systemName: "viewfinder").font(.system(size: 72, weight: .ultraLight)).foregroundStyle(mint)
                    }
                } else if torch.isAvailable {
                    HStack {
                        Spacer()
                        Button { torch.toggle() } label: {
                            Image(systemName: torch.isOn ? "flashlight.on.fill" : "flashlight.off.fill")
                                .font(.title3)
                                .foregroundStyle(torch.isOn ? .yellow : .white)
                                .frame(width: 48, height: 48)
                                .background(.ultraThinMaterial, in: Circle())
                        }.accessibilityLabel(L(torch.isOn ? "Turn Off Torch" : "Turn On Torch"))
                    }
                }
                Spacer()
            }.padding(20)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { controls }
        .task { model.enterMode() }
        .onChange(of: scenePhase) { _, value in
            model.sceneChanged(value)
            if value != .active { torch.turnOff() }
        }
        .onDisappear { torch.turnOff() }
        .sheet(isPresented: $archive) { GaussianArchiveView(model: model) }
        .sheet(isPresented: $details) { GaussianDetailsView(model: model) }
        .sheet(isPresented: $showCredits) { CreditsSheet() }
        .sheet(isPresented: Binding(
            get: { preview && !previewFullScreen },
            set: { if !$0 && !previewFullScreen { preview = false } }
        )) {
            if let p = model.current {
                GaussianPreviewSheet(
                    url: p.resultURL,
                    exportMetadata: AnnotationExportMetadata(gaussian: p),
                    annotations: p.annotations ?? [],
                    onSaveAnnotations: { model.updateAnnotations(for: p, annotations: $0) },
                    isFullScreen: $previewFullScreen,
                    onClose: { preview = false; previewFullScreen = false }
                )
            }
        }
        .fullScreenCover(isPresented: $previewFullScreen) {
            if let p = model.current {
                GaussianPreviewSheet(
                    url: p.resultURL,
                    exportMetadata: AnnotationExportMetadata(gaussian: p),
                    annotations: p.annotations ?? [],
                    onSaveAnnotations: { model.updateAnnotations(for: p, annotations: $0) },
                    isFullScreen: $previewFullScreen,
                    onClose: { preview = false; previewFullScreen = false }
                )
            }
        }
        .sheet(item: Binding(get: { details ? nil : model.sharing }, set: { model.sharing = $0 })) { ShareSheet(urls: $0.urls) }
        .alert(L("LiDAR Scanner"), isPresented: Binding(get: { model.errorMessage != nil && !details && !archive }, set: { if !$0 { model.errorMessage = nil } })) {
            Button(L("OK")) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    private var controls: some View {
        VStack(spacing: 14) {
            if let p = model.current {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(p.frames.count.formatted()).font(.system(size: 32, weight: .semibold, design: .rounded)).monospacedDigit()
                        Text(L("SAVED VIEWS")).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(L("Details"), systemImage: "info.circle") { details = true }
                }
                if model.isBusy, model.processingActive, let profile = p.profile {
                    VStack(alignment: .leading, spacing: 6) {
                        if p.phase == .preparing {
                            ProgressView(L("Preparing 3D scene…"))
                        } else if p.iteration >= profile.iterations {
                            ProgressView(L("Saving 3D scene…"))
                        } else {
                            ProgressView(value: Double(p.iteration), total: Double(profile.iterations))
                            Text(L("Step %lld of %lld", Int64(p.iteration), Int64(profile.iterations))).font(.caption).monospacedDigit()
                        }
                        Text(L("Keep the app open. Your capture is saved on this iPhone."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                Text(L("Move around your subject and capture it from several angles. Processing starts automatically when you finish."))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if model.isRecording {
                Button { model.finish() } label: {
                    Label(L("Finish and Create"), systemImage: "stop.fill").frame(maxWidth: .infinity, minHeight: 46)
                }.buttonStyle(.borderedProminent).tint(mint).foregroundStyle(.black)
            } else if model.isBusy {
                if model.processingActive {
                    Button(L("Pause Processing"), systemImage: "pause.fill") { model.pause() }
                        .buttonStyle(.bordered)
                }
            } else if model.current == nil {
                let canStart = model.cameraReady && model.trackingNormal
                Button { model.begin() } label: {
                    Label(L("Start Scan"), systemImage: "record.circle").frame(maxWidth: .infinity, minHeight: 46)
                }.buttonStyle(.borderedProminent)
                    .tint(canStart ? mint : Color.white.opacity(0.16))
                    .foregroundStyle(canStart ? Color.black : Color.white.opacity(0.72))
                    .disabled(!canStart)
            } else if let p = model.current {
                if !p.hasResult && p.frames.count >= 12 {
                    Button(L("Continue Processing"), systemImage: "play.fill") { model.resume() }
                        .buttonStyle(.borderedProminent).tint(mint).foregroundStyle(.black)
                }
                if !p.hasResult && p.frames.count < 12 {
                    Text(L("This capture has too few views for local processing. You can export it or start a new scan."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack(alignment: .center) {
                    Button {
                        model.newCapture()
                    } label: {
                        Label(L("New Scan"), systemImage: "plus")
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .contentShape(Capsule())
                    }
                    Spacer()
                    Menu {
                        Section {
                            Button(L("Share 3D Scene"), systemImage: "cube.transparent") { model.share(.scene) }.disabled(!p.hasResult)
                            Button(L("Export Capture"), systemImage: "photo.stack") { model.share(.capture) }
                        }
                        if let annotations = p.annotations, !annotations.isEmpty {
                            Section {
                                AnnotationExportMenu { kind in
                                    switch kind {
                                    case .geojson:
                                        if !FileManager.default.fileExists(atPath: p.annotationsGeoJSONURL.path),
                                           let data = try? AnnotationExporter.geoJSONData(for: annotations, exportMetadata: AnnotationExportMetadata(gaussian: p)) {
                                            try? data.write(to: p.annotationsGeoJSONURL, options: .atomic)
                                        }
                                        model.sharing = SharedFiles(urls: [p.annotationsGeoJSONURL])
                                    case .csv:
                                        try? AnnotationExporter.csvData(for: annotations).write(to: p.annotationsCSVURL, options: .atomic)
                                        model.sharing = SharedFiles(urls: [p.annotationsCSVURL])
                                    case .dxf:
                                        try? AnnotationExporter.dxfData(for: annotations).write(to: p.annotationsDXFURL, options: .atomic)
                                        model.sharing = SharedFiles(urls: [p.annotationsDXFURL])
                                    case .json:
                                        break
                                    }
                                }
                            }
                        }
                        Section {
                            ReportExportMenu { format in
                                model.share(.report(format))
                            }
                            Button(L("Export Processing Log"), systemImage: "list.bullet.rectangle") { model.share(.log) }
                        }
                    } label: {
                        ShareActionButtonLabel(isBusy: false, tint: mint)
                    }
                }
                .padding(.top, 4)
            }
        }.padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 24).frame(maxWidth: 680).frame(maxWidth: .infinity)
            .background(.ultraThinMaterial, in: UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28))
    }
}

private struct GaussianCameraView: UIViewRepresentable {
    let session: ARSession
    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(); view.session = session; view.scene = SCNScene(); view.preferredFramesPerSecond = 30
        view.automaticallyUpdatesLighting = false; return view
    }
    func updateUIView(_ uiView: ARSCNView, context: Context) {}
}

struct GaussianDetailsView: View {
    @ObservedObject var model: GaussianModel
    @ObservedObject private var language = LanguageManager.shared
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                if let p = model.current {
                    Section(L("Current State")) {
                        LabeledContent(L("Status"), value: p.phase.title)
                        LabeledContent(L("Saved Views"), value: "\(p.frames.count)")
                        LabeledContent(L("Recorded Frame Decisions"), value: "\(p.receivedFrames)")
                        LabeledContent(L("Depth Seed Points"), value: "\(p.seedCount)")
                        if let profile = p.profile {
                            LabeledContent(L("Completed Steps"), value: "\(p.iteration) / \(profile.iterations)")
                            LabeledContent(L("Saved Checkpoint"), value: "\(p.checkpointIteration)")
                            LabeledContent(L("Gaussians"), value: "\(p.splatCount)")
                            LabeledContent(L("Recorded Processing Time"), value: "\(Int(p.processingSeconds)) s")
                        }
                    }
                    Section(L("What Happened")) {
                        Text(L("Selected images and camera poses are saved on this device. Processing uses all saved views and LiDAR depth as its starting point."))
                        if let issue = p.issueDescription { Text(issue).textSelection(.enabled) }
                        if p.recoveryNote != nil { Text(L("This scan was recovered after an interruption. The last saved checkpoint is used when processing continues.")) }
                        ForEach(p.decisions.keys.sorted(), id: \.self) { key in
                            LabeledContent(reason(key), value: "\(p.decisions[key] ?? 0)")
                        }
                    }
                    Section {
                        ReportExportMenu { format in
                            model.share(.report(format))
                        }
                        Button(L("Export Processing Log"), systemImage: "list.bullet.rectangle") { model.share(.log) }
                    }.disabled(model.isBusy || model.isRecording)
                    Section(L("Technical Details")) {
                        Text(p.coordinateSystem).font(.caption).textSelection(.enabled)
                        Text(L("Engine: %@", p.engineRevision)).font(.caption).textSelection(.enabled)
                        if let profile = p.profile,
                           let data = try? GaussianStore.encoder.encode(profile),
                           let json = String(data: data, encoding: .utf8) {
                            Text(json).font(.caption.monospaced()).textSelection(.enabled)
                        }
                        Text(L("The report explains the processing in full sentences. The log contains the exact recorded settings, decisions, steps and file checksums."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.navigationTitle(L("Scan Details")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("Done")) { dismiss() } } }
                .sheet(item: $model.sharing) { ShareSheet(urls: $0.urls) }
                .alert(L("LiDAR Scanner"), isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
                    Button(L("OK")) { model.errorMessage = nil }
                } message: { Text(model.errorMessage ?? "") }
        }
    }
    private func reason(_ value: String) -> String {
        switch value {
        case "saved": return LanguageManager.string("Saved")
        case "interval": return LanguageManager.string("Sampling Interval")
        case "similar_view": return LanguageManager.string("Similar View")
        case "writer_busy": return LanguageManager.string("Previous Image Being Saved")
        case "tracking_limited": return LanguageManager.string("Tracking Limited")
        default: return value
        }
    }
}

private struct GaussianArchiveView: View {
    @ObservedObject var model: GaussianModel
    @ObservedObject private var language = LanguageManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var deleting: GaussianProject?
    @State private var showImporter = false
    var body: some View {
        NavigationStack {
            List {
                if model.archive.isEmpty {
                    ContentUnavailableView(L("No Scans Yet"), systemImage: "square.stack.3d.up")
                }
                ForEach(model.archive) { scan in
                    Button {
                        model.open(scan); dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(scan.title).font(.headline)
                            Text(scan.phase.title).font(.subheadline).foregroundStyle(.secondary)
                            HStack(spacing: 6) {
                                Text(L("Saved views: %lld", Int64(scan.frames.count))).font(.caption)
                                if let annCount = scan.annotations?.count, annCount > 0 {
                                    Text(L("Tags %@", annCount.formatted()))
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(.cyan.opacity(0.2), in: Capsule())
                                        .foregroundStyle(.cyan)
                                }
                            }
                        }.padding(.vertical, 6)
                    }.swipeActions { Button(L("Delete"), role: .destructive) { deleting = scan } }
                }
            }.navigationTitle(L("Gaussian Scans"))
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showImporter = true
                        } label: {
                            Label(L("Import"), systemImage: "square.and.arrow.down")
                        }
                        .accessibilityLabel(L("Import Scan"))
                    }
                    ToolbarItem(placement: .confirmationAction) { Button(L("Done")) { dismiss() } }
                }
                .fileImporter(
                    isPresented: $showImporter,
                    allowedContentTypes: [.folder, .zip],
                    allowsMultipleSelection: true
                ) { result in
                    switch result {
                    case .success(let urls):
                        Task {
                            for url in urls {
                                do {
                                    _ = try await model.importProject(from: url)
                                } catch {
                                    await MainActor.run { model.errorMessage = error.localizedDescription }
                                }
                            }
                        }
                    case .failure(let error):
                        model.errorMessage = error.localizedDescription
                    }
                }
                .alert(L("Delete Scan?"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                    Button(L("Cancel"), role: .cancel) { deleting = nil }
                    Button(L("Delete"), role: .destructive) { if let deleting { model.delete(deleting) }; deleting = nil }
                } message: { Text(L("The capture, 3D scene and processing log will be removed from this device.")) }
                .alert(L("LiDAR Scanner"), isPresented: Binding(get: { model.errorMessage != nil && deleting == nil }, set: { if !$0 { model.errorMessage = nil } })) {
                    Button(L("OK")) { model.errorMessage = nil }
                } message: { Text(model.errorMessage ?? "") }
        }
    }
}
