import SwiftUI

struct ArchiveSheet: View {
    @ObservedObject var model: ScanModel
    @Environment(\.dismiss) private var dismiss
    @State private var toDelete: SavedScan?
    @State private var sharing: SharedFiles?
    @State private var showImporter = false
    @State private var previewScan: SavedScan?
    @State private var previewPoints: [PCPoint] = []
    var body: some View {
        NavigationStack {
            List {
                if model.savedScans.isEmpty {
                    ContentUnavailableView("No Scans Yet", systemImage: "square.stack.3d.up",
                        description: Text("Scans appear here when you pause capture or export."))
                }
                ForEach(model.savedScans) { scan in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(scan.metadata.title).font(.headline)
                        Text(scan.metadata.savedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Text("Points: \(scan.metadata.pointCount.formatted()) · m · Z↑").font(.subheadline)
                            Spacer()
                            Button {
                                Task {
                                    let pts = await model.loadPreview(for: scan)
                                    await MainActor.run {
                                        previewPoints = pts
                                        previewScan = scan
                                    }
                                }
                            } label: {
                                Image(systemName: "cube.transparent").frame(width: 44, height: 36)
                            }
                            .accessibilityLabel("View in 3D")

                            Menu {
                                ForEach(scan.existingFormats) { format in
                                    Button(format.title) {
                                        sharing = SharedFiles(urls: [scan.url(for: format), scan.metadataURL])
                                    }
                                }
                                Button("Export Report") {
                                    DispatchQueue.global(qos: .userInitiated).async {
                                        do {
                                            let url = try ScanReport.pointCloud(scan)
                                            DispatchQueue.main.async { sharing = SharedFiles(urls: [url]) }
                                        } catch { DispatchQueue.main.async { model.errorMessage = error.localizedDescription } }
                                    }
                                }
                            } label: { Image(systemName: "square.and.arrow.up").frame(width: 44, height: 36) }
                            .accessibilityLabel("Share Scan")
                        }
                    }.padding(.vertical, 6)
                        .swipeActions { Button("Delete", role: .destructive) { toDelete = scan } }
                }
            }
            .navigationTitle("My Scans")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showImporter = true
                    } label: {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                    .accessibilityLabel("Import Scan")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $sharing) { ShareSheet(urls: $0.urls) }
            .sheet(item: $previewScan) { scan in
                CloudPreviewSheet(points: previewPoints, total: scan.metadata.pointCount)
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: ScanImporter.supportedContentTypes,
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    Task {
                        for url in urls {
                            do {
                                _ = try await model.importScan(from: url)
                            } catch {
                                await MainActor.run { model.errorMessage = error.localizedDescription }
                            }
                        }
                    }
                case .failure(let error):
                    model.errorMessage = error.localizedDescription
                }
            }
            .alert("Delete Scan?", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } })) {
                Button("Cancel", role: .cancel) { toDelete = nil }
                Button("Delete", role: .destructive) { if let scan = toDelete { model.delete(scan) }; toDelete = nil }
            } message: { Text("The saved scan and its export files will be removed from this device.") }
            .alert("LiDAR-Scanner", isPresented: Binding(get: { model.errorMessage != nil && toDelete == nil },
                set: { if !$0 { model.errorMessage = nil } })) {
                    Button("OK") { model.errorMessage = nil }
                } message: { Text(model.errorMessage ?? "") }
        }
    }
}
