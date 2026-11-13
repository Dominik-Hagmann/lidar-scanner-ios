import SwiftUI

struct ExportSheet: View {
    @ObservedObject var model: ScanModel
    @ObservedObject private var language = LanguageManager.shared
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section(L("Scan")) {
                    TextField(L("Title, e.g. Context 104"), text: $model.scanTitle)
                        .textInputAutocapitalization(.sentences).disabled(model.isBusy)
                    LabeledContent(L("Points"), value: model.pointCount.formatted())
                    if !model.activeGroundControlPoints.isEmpty {
                        LabeledContent(L("Ground Control Points"), value: model.activeGroundControlPoints.count.formatted())
                    }
                    LabeledContent(L("Coordinates"), value: L("Local · Meters · Z Up"))
                }
                Section(L("File Format")) {
                    Picker(L("Format"), selection: $model.exportFormat) {
                        ForEach(ExportFormat.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.inline).labelsHidden().disabled(model.isBusy)
                    Text(L("PLY, CSV, LAS, LAZ, and ASTM E57 preserve colors and confidence; XYZ contains only X, Y, and Z. Metadata JSON (and GCPs when set) are shared alongside."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Button { model.saveCurrent(share: true) } label: {
                        HStack {
                            if model.isBusy { ProgressView() }
                            Label(L(model.isBusy ? "Saving…" : "Save and Share"), systemImage: "square.and.arrow.up")
                        }
                    }.disabled(model.isBusy || model.pointCount == 0)
                    if model.hasMesh {
                        Button { model.saveCurrent(share: false, shareMesh: true) } label: {
                            Label(L("Export 3D Mesh (OBJ)"), systemImage: "cube")
                        }.disabled(model.isBusy || model.pointCount == 0)
                    }
                    Button(L("Export Report"), systemImage: "doc.richtext") { model.saveCurrent(share: false, report: true) }
                        .disabled(model.isBusy || model.pointCount == 0)
                    Text(L("In the next step, choose “Save to Files” or AirDrop. A binary PLY copy remains in the scan archive on this device."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(L("Export Point Cloud")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("Done")) { dismiss() }.disabled(model.isBusy) } }
            .interactiveDismissDisabled(model.isBusy)
            .sheet(item: $model.sharedFiles) { ShareSheet(urls: $0.urls) }
            .alert(L("Export Failed"), isPresented: Binding(get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } })) {
                    Button(L("OK")) { model.errorMessage = nil }
                } message: { Text(model.errorMessage ?? "") }
        }
    }
}
