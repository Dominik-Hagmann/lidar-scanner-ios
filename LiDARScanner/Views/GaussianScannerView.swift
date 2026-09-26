import ARKit
import SwiftUI

struct GaussianScannerView: View {
    @ObservedObject var model: GaussianModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var details = false
    @State private var archive = false
    @State private var preview = false
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
                        Text("Gaussian Splatting").font(.title3.bold())
                        Text("Capture · Create · Share").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { model.refreshArchive(); archive = true } label: {
                        Image(systemName: "folder").frame(width: 44, height: 44)
                    }.accessibilityLabel("Saved Scans").disabled(model.isBusy || model.isRecording)
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
                                Text("View 3D Scene").font(.headline)
                            }.padding(32)
                        }.disabled(model.isBusy)
                    } else if model.isBusy {
                        ProgressView().controlSize(.large)
                    } else if model.cameraDenied {
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }.buttonStyle(.borderedProminent)
                    } else if model.current == nil {
                        Image(systemName: "viewfinder").font(.system(size: 72, weight: .ultraLight)).foregroundStyle(mint)
                    }
                }
                Spacer()
            }.padding(20)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { controls }
        .task { model.enterMode() }
        .onChange(of: scenePhase) { _, value in model.sceneChanged(value) }
        .sheet(isPresented: $archive) { GaussianArchiveView(model: model) }
        .sheet(isPresented: $details) { GaussianDetailsView(model: model) }
        .sheet(isPresented: $preview) {
            if let p = model.current { GaussianPreviewSheet(url: p.resultURL) }
        }
        .sheet(item: Binding(get: { details ? nil : model.sharing }, set: { model.sharing = $0 })) { ShareSheet(urls: $0.urls) }
        .alert("LiDAR-Scanner", isPresented: Binding(get: { model.errorMessage != nil && !details }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    private var controls: some View {
        VStack(spacing: 14) {
            if let p = model.current {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(p.frames.count.formatted()).font(.system(size: 32, weight: .semibold, design: .rounded)).monospacedDigit()
                        Text("SAVED VIEWS").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Details", systemImage: "info.circle") { details = true }
                }
                if model.isBusy, model.processingActive, let profile = p.profile {
                    VStack(alignment: .leading, spacing: 6) {
                        if p.phase == .preparing {
                            ProgressView("Preparing 3D scene…")
                        } else if p.iteration >= profile.iterations {
                            ProgressView("Saving 3D scene…")
                        } else {
                            ProgressView(value: Double(p.iteration), total: Double(profile.iterations))
                            Text("Step \(p.iteration) of \(profile.iterations)").font(.caption).monospacedDigit()
                        }
                        Text("Keep the app open. Your capture is saved on this iPhone.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Move around your subject and capture it from several angles. Processing starts automatically when you finish.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if model.isRecording {
                Button { model.finish() } label: {
                    Label("Finish and Create", systemImage: "stop.fill").frame(maxWidth: .infinity, minHeight: 46)
                }.buttonStyle(.borderedProminent).tint(mint).foregroundStyle(.black)
            } else if model.isBusy {
                if model.processingActive {
                    Button("Pause Processing", systemImage: "pause.fill") { model.pause() }
                        .buttonStyle(.bordered)
                }
            } else if model.current == nil {
                Button { model.begin() } label: {
                    Label("Start Scan", systemImage: "record.circle").frame(maxWidth: .infinity, minHeight: 46)
                }.buttonStyle(.borderedProminent).tint(mint).foregroundStyle(.black)
                    .disabled(!model.cameraReady || !model.trackingNormal)
            } else if let p = model.current {
                if !p.hasResult && p.frames.count >= 12 {
                    Button("Continue Processing", systemImage: "play.fill") { model.resume() }
                        .buttonStyle(.borderedProminent).tint(mint).foregroundStyle(.black)
                }
                if !p.hasResult && p.frames.count < 12 {
                    Text("This capture has too few views for local processing. You can export it or start a new scan.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button("New Scan", systemImage: "plus") { model.newCapture() }
                    Spacer()
                    Menu {
                        Button("Share 3D Scene", systemImage: "cube.transparent") { model.share(.scene) }.disabled(!p.hasResult)
                        Button("Export Capture", systemImage: "photo.stack") { model.share(.capture) }
                        Button("Export Report", systemImage: "doc.richtext") { model.share(.report) }
                        Button("Export Processing Log", systemImage: "list.bullet.rectangle") { model.share(.log) }
                    } label: { Label("Share", systemImage: "square.and.arrow.up") }
                }
            }
        }.padding(20).frame(maxWidth: 680).frame(maxWidth: .infinity)
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
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                if let p = model.current {
                    Section("Current State") {
                        LabeledContent("Status", value: p.phase.title)
                        LabeledContent("Saved Views", value: "\(p.frames.count)")
                        LabeledContent("Recorded Frame Decisions", value: "\(p.receivedFrames)")
                        LabeledContent("Depth Seed Points", value: "\(p.seedCount)")
                        if let profile = p.profile {
                            LabeledContent("Completed Steps", value: "\(p.iteration) / \(profile.iterations)")
                            LabeledContent("Saved Checkpoint", value: "\(p.checkpointIteration)")
                            LabeledContent("Gaussians", value: "\(p.splatCount)")
                            LabeledContent("Recorded Processing Time", value: "\(Int(p.processingSeconds)) s")
                        }
                    }
                    Section("What Happened") {
                        Text("Selected images and camera poses are saved on this device. Processing uses all saved views and LiDAR depth as its starting point.")
                        if let issue = p.issueDescription { Text(issue).textSelection(.enabled) }
                        if p.recoveryNote != nil { Text("This scan was recovered after an interruption. The last saved checkpoint is used when processing continues.") }
                        ForEach(p.decisions.keys.sorted(), id: \.self) { key in
                            LabeledContent(reason(key), value: "\(p.decisions[key] ?? 0)")
                        }
                    }
                    Section {
                        Button("Export Report", systemImage: "doc.richtext") { model.share(.report) }
                        Button("Export Processing Log", systemImage: "list.bullet.rectangle") { model.share(.log) }
                    }.disabled(model.isBusy || model.isRecording)
                    Section("Technical Details") {
                        Text(p.coordinateSystem).font(.caption).textSelection(.enabled)
                        Text("Engine: \(p.engineRevision)").font(.caption).textSelection(.enabled)
                        if let data = try? GaussianStore.encoder.encode(p.profile), let json = String(data: data, encoding: .utf8) {
                            Text(json).font(.caption.monospaced()).textSelection(.enabled)
                        }
                        Text("The report explains the processing in full sentences. The log contains the exact recorded settings, decisions, steps and file checksums.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.navigationTitle("Scan Details").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .sheet(item: $model.sharing) { ShareSheet(urls: $0.urls) }
                .alert("LiDAR-Scanner", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
                    Button("OK") { model.errorMessage = nil }
                } message: { Text(model.errorMessage ?? "") }
        }
    }
    private func reason(_ value: String) -> String {
        switch value {
        case "saved": return String(localized: "Saved")
        case "interval": return String(localized: "Sampling Interval")
        case "similar_view": return String(localized: "Similar View")
        case "writer_busy": return String(localized: "Previous Image Being Saved")
        case "tracking_limited": return String(localized: "Tracking Limited")
        default: return value
        }
    }
}

private struct GaussianArchiveView: View {
    @ObservedObject var model: GaussianModel
    @Environment(\.dismiss) private var dismiss
    @State private var deleting: GaussianProject?
    var body: some View {
        NavigationStack {
            List {
                if model.archive.isEmpty {
                    ContentUnavailableView("No Scans Yet", systemImage: "square.stack.3d.up")
                }
                ForEach(model.archive) { scan in
                    Button {
                        model.open(scan); dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(scan.title).font(.headline)
                            Text(scan.phase.title).font(.subheadline).foregroundStyle(.secondary)
                            Text("Saved views: \(scan.frames.count)").font(.caption)
                        }.padding(.vertical, 6)
                    }.swipeActions { Button("Delete", role: .destructive) { deleting = scan } }
                }
            }.navigationTitle("Gaussian Scans")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .alert("Delete Scan?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                    Button("Cancel", role: .cancel) { deleting = nil }
                    Button("Delete", role: .destructive) { if let deleting { model.delete(deleting) }; deleting = nil }
                } message: { Text("The capture, 3D scene and processing log will be removed from this device.") }
        }
    }
}
