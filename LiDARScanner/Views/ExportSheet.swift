import SwiftUI

struct ExportSheet: View {
    @ObservedObject var model: ScanModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Scan") {
                    TextField("Title, e.g. Context 104", text: $model.scanTitle)
                        .textInputAutocapitalization(.sentences).disabled(model.isBusy)
                    LabeledContent("Points", value: model.pointCount.formatted())
                    LabeledContent("Coordinates", value: String(localized: "Local · Meters · Z Up"))
                }
                Section("File Format") {
                    Picker("Format", selection: $model.exportFormat) {
                        ForEach(ExportFormat.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.inline).labelsHidden().disabled(model.isBusy)
                    Text("PLY preserves colors and confidence. The XYZ file contains only X, Y, and Z. Metadata is shared as an additional JSON file with either format.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Button { model.saveCurrent(share: true) } label: {
                        HStack {
                            if model.isBusy { ProgressView() }
                            Label(LocalizedStringKey(model.isBusy ? "Saving…" : "Save and Share"), systemImage: "square.and.arrow.up")
                        }
                    }.disabled(model.isBusy || model.pointCount == 0)
                    Text("In the next step, choose “Save to Files” or AirDrop. A binary PLY copy remains in the scan archive on this device.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Export Point Cloud").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.disabled(model.isBusy) } }
            .interactiveDismissDisabled(model.isBusy)
            .sheet(item: $model.sharedFiles) { ShareSheet(urls: $0.urls) }
            .alert("Export Failed", isPresented: Binding(get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } })) {
                    Button("OK") { model.errorMessage = nil }
                } message: { Text(model.errorMessage ?? "") }
        }
    }
}
