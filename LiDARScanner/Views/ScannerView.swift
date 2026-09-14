import SwiftUI

struct ScannerView: View {
    @ObservedObject var model: ScanModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var showPoints = true
    @State private var showSettings = false
    @State private var showArchive = false
    @State private var showPreview = false
    @State private var showExport = false
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
                    Text(model.cameraDenied ? "Kamera freigeben" : "LiDAR-Scanner erforderlich")
                        .font(.title2.bold())
                    Text(model.notice).multilineTextAlignment(.center).foregroundStyle(.secondary)
                    if model.cameraDenied {
                        Button("Einstellungen öffnen") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }.buttonStyle(.borderedProminent)
                    }
                }.padding(32)
            }
            VStack {
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
                        Button { showPoints.toggle() } label: {
                            Image(systemName: showPoints ? "circle.hexagongrid.fill" : "circle.hexagongrid")
                                .font(.title3).frame(width: 48, height: 48)
                                .background(.ultraThinMaterial, in: Circle())
                        }.accessibilityLabel(showPoints ? "Punkte ausblenden" : "Punkte einblenden")
                    }
                }
            }.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 12)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { controls }
        .task { model.prepare() }
        .onChange(of: scenePhase) { _, phase in model.sceneChanged(phase) }
        .sheet(isPresented: $showSettings) { SettingsSheet(model: model) }
        .sheet(isPresented: $showArchive) { ArchiveSheet(model: model) }
        .sheet(isPresented: $showPreview) { CloudPreviewSheet(points: model.preview, total: model.pointCount) }
        .sheet(isPresented: $showExport) { ExportSheet(model: model) }
        .alert("Neuen Scan beginnen?", isPresented: $confirmReset) {
            Button("Abbrechen", role: .cancel) {}
            Button("Neuer Scan", role: .destructive) { model.newScan() }
        } message: {
            Text("Die aktuelle Punktwolke im Arbeitsspeicher wird geleert. Bereits gesicherte Scans bleiben erhalten. Falls das Sichern fehlgeschlagen ist, zuerst erneut exportieren.")
        }
        .alert("LiDAR-Scanner", isPresented: Binding(get: { model.errorMessage != nil && !showExport && !showArchive },
                                                  set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("LiDAR-Scanner").font(.system(size: 20, weight: .bold, design: .rounded))
                    .lineLimit(1).minimumScaleFactor(0.75)
                Text("LiDAR · Szene als Punktwolke").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { model.refreshArchive(); showArchive = true } label: {
                Image(systemName: "folder").frame(width: 44, height: 44)
            }.accessibilityLabel("Gespeicherte Scans").disabled(model.isBusy || model.isRecording)
            Button { showSettings = true } label: {
                Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44)
            }.accessibilityLabel("Scan-Einstellungen").disabled(model.isBusy || model.isRecording || model.pointCount > 0)
        }.foregroundStyle(.white)
    }

    private var controls: some View {
        VStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.pointCount.formatted()).font(.system(size: 32, weight: .semibold, design: .rounded))
                        .monospacedDigit().contentTransition(.numericText())
                    Text("PUNKTE").font(.caption2.weight(.semibold)).tracking(1.5).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(String(format: "%02d:%02d", Int(model.activeSeconds)/60, Int(model.activeSeconds)%60))
                        .font(.title3.monospacedDigit())
                    Text("ERFASSUNGSZEIT").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Text(model.notice).font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button { model.toggleRecording() } label: {
                    Label(model.isRecording ? "Pausieren" : (model.pointCount > 0 ? "Fortsetzen" : "Scan starten"),
                          systemImage: model.isRecording ? "pause.fill" : "record.circle")
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 46)
                }.buttonStyle(.borderedProminent).tint(model.isRecording ? .orange : mint)
                    .foregroundStyle(.black)
                    .disabled(model.isBusy || model.sessionClosed || !model.ready || (!model.trackingNormal && !model.isRecording))
                Button { showPreview = true } label: {
                    Image(systemName: "cube.transparent").font(.title3).frame(width: 48, height: 46)
                }.buttonStyle(.bordered).disabled(model.preview.isEmpty || model.isRecording || model.isBusy)
                    .accessibilityLabel("Punktwolke in 3D ansehen")
            }
            HStack {
                Button("Neuer Scan", systemImage: "plus") {
                    if model.pointCount > 0 { confirmReset = true } else { model.newScan() }
                }.disabled(model.isRecording || model.isBusy || !model.supported || model.cameraDenied)
                Spacer()
                Button {
                    if model.isRecording { model.pauseAndSave() }
                    showExport = true
                } label: {
                    if model.isBusy { ProgressView().padding(.trailing, 4) }
                    Label(model.isBusy ? "Sichern …" : "Exportieren", systemImage: "square.and.arrow.up")
                }.disabled(model.pointCount == 0 || model.isBusy)
            }.font(.subheadline.weight(.medium))
        }
        .padding(20).frame(maxWidth: 680).frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28))
    }
}
