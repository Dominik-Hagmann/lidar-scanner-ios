import SwiftUI

struct ExportSheet: View {
    @ObservedObject var model: ScanModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Scan") {
                    TextField("Bezeichnung, z. B. Befund 104", text: $model.scanTitle)
                        .textInputAutocapitalization(.sentences).disabled(model.isBusy)
                    LabeledContent("Punkte", value: model.pointCount.formatted())
                    LabeledContent("Koordinaten", value: "Lokal · Meter · Z nach oben")
                }
                Section("Dateiformat") {
                    Picker("Format", selection: $model.exportFormat) {
                        ForEach(ExportFormat.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.inline).labelsHidden().disabled(model.isBusy)
                    Text("PLY bewahrt Farben und Konfidenz. Die XYZ-Datei enthält ausschließlich X, Y und Z. Die Metadaten werden jeweils als zusätzliche JSON-Datei geteilt.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Button { model.saveCurrent(share: true) } label: {
                        HStack {
                            if model.isBusy { ProgressView() }
                            Label(model.isBusy ? "Wird gesichert …" : "Sichern und teilen", systemImage: "square.and.arrow.up")
                        }
                    }.disabled(model.isBusy || model.pointCount == 0)
                    Text("Im nächsten Schritt „In Dateien sichern“ oder AirDrop auswählen. Eine binäre PLY-Kopie bleibt im Scan-Archiv auf diesem Gerät.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Punktwolke exportieren").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() }.disabled(model.isBusy) } }
            .interactiveDismissDisabled(model.isBusy)
            .sheet(item: $model.sharedFiles) { ShareSheet(urls: $0.urls) }
            .alert("Export fehlgeschlagen", isPresented: Binding(get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } })) {
                    Button("OK") { model.errorMessage = nil }
                } message: { Text(model.errorMessage ?? "") }
        }
    }
}
