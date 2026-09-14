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
                    ContentUnavailableView("Noch keine Scans", systemImage: "square.stack.3d.up",
                        description: Text("Beim Pausieren oder Exportieren wird ein Scan hier abgelegt."))
                }
                ForEach(model.savedScans) { scan in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(scan.metadata.title).font(.headline)
                        Text(scan.metadata.savedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Text("\(scan.metadata.pointCount.formatted()) Punkte · m · Z↑").font(.subheadline)
                            Spacer()
                            Menu {
                                ForEach(scan.existingFormats) { format in
                                    Button(format.title) {
                                        sharing = SharedFiles(urls: [scan.url(for: format), scan.metadataURL])
                                    }
                                }
                            } label: { Image(systemName: "square.and.arrow.up").frame(width: 44, height: 36) }
                            .accessibilityLabel("Scan teilen")
                        }
                    }.padding(.vertical, 6)
                        .swipeActions { Button("Löschen", role: .destructive) { toDelete = scan } }
                }
            }
            .navigationTitle("Meine Scans")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
            .sheet(item: $sharing) { ShareSheet(urls: $0.urls) }
            .alert("Scan löschen?", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } })) {
                Button("Abbrechen", role: .cancel) { toDelete = nil }
                Button("Löschen", role: .destructive) { if let scan = toDelete { model.delete(scan) }; toDelete = nil }
            } message: { Text("Der gespeicherte Scan und seine Exportdateien werden von diesem Gerät entfernt.") }
            .alert("LiDAR-Scanner", isPresented: Binding(get: { model.errorMessage != nil && toDelete == nil },
                set: { if !$0 { model.errorMessage = nil } })) {
                    Button("OK") { model.errorMessage = nil }
                } message: { Text(model.errorMessage ?? "") }
        }
    }
}
