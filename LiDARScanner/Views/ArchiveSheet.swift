import SwiftUI

struct ArchiveSheet: View {
    @ObservedObject var model: ScanModel
    @Environment(\.dismiss) private var dismiss
    @State private var toDelete: SavedScan?
    @State private var sharing: SharedFiles?
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
                            Menu {
                                ForEach(scan.existingFormats) { format in
                                    Button(format.title) {
                                        sharing = SharedFiles(urls: [scan.url(for: format), scan.metadataURL])
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
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $sharing) { ShareSheet(urls: $0.urls) }
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
