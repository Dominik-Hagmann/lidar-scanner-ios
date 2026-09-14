import SwiftUI

struct SettingsSheet: View {
    @ObservedObject var model: ScanModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Punktdichte") {
                    Picker("Rasterweite", selection: $model.settings.voxelCentimeters) {
                        Text("0,5 cm").tag(0.5)
                        Text("1 cm").tag(1.0)
                        Text("2 cm").tag(2.0)
                        Text("5 cm").tag(5.0)
                    }
                    Picker("Tiefenpixel", selection: $model.settings.pixelStep) {
                        Text("Jeder Pixel").tag(1)
                        Text("Jeder zweite je Achse").tag(2)
                        Text("Jeder vierte je Achse").tag(4)
                    }
                    Text("Pro Rasterzelle bleibt ein Punkt erhalten. Die Rasterweite bestimmt die Ausdünnung, nicht die Messgenauigkeit.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Messbereich und Filter") {
                    Picker("Maximale Tiefe", selection: $model.settings.maxDepth) {
                        Text("2 m").tag(2.0); Text("3 m").tag(3.0); Text("5 m").tag(5.0)
                    }
                    Picker("Konfidenz", selection: $model.settings.minConfidence) {
                        Text("Nur hoch").tag(2)
                        Text("Mittel und hoch").tag(1)
                        Text("Alle").tag(0)
                    }
                    Picker("Punktlimit", selection: $model.settings.maxPoints) {
                        Text("Automatisch · keine feste Punktzahl").tag(0)
                        Text("500.000").tag(500_000)
                        Text("1 Million").tag(1_000_000)
                        Text("2 Millionen").tag(2_000_000)
                        Text("5 Millionen").tag(5_000_000)
                        Text("10 Millionen").tag(10_000_000)
                    }
                    Text("Im automatischen Modus bestimmt der verfügbare Arbeitsspeicher die erreichbare Punktzahl. Wenn der Arbeitsspeicher knapp wird, beendet die App die Erfassung und sichert den Scan. Die Speicherüberwachung gilt auch bei fest gewählten Punktlimits.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Tiefen unter 0,2 m werden verworfen. Bei eingeschränktem Tracking werden keine Punkte hinzugefügt.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Export") {
                    Picker("Format", selection: $model.exportFormat) {
                        ForEach(ExportFormat.allCases) { Text($0.title).tag($0) }
                    }
                    Text("PLY enthält XYZ, RGB und Konfidenz; XYZ enthält drei Koordinatenspalten. Alle Koordinaten sind lokal, in Metern und mit Z nach oben. Zu jedem Scan gehört eine JSON-Datei mit Metadaten.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Speicherung") {
                    Text("Beim Pausieren wird der Scan automatisch auf diesem Gerät gesichert. Du findest ihn in „Dateien“ unter „Auf meinem iPhone“ bzw. „Auf meinem iPad“ → „LiDAR-Scanner“ → „Scans“ und im Scan-Archiv der App.")
                    Text("Nach einer Kameraunterbrechung oder einem Wechsel in den Hintergrund bleibt der Scan exportierbar. Weitere Punkte werden in einem neuen Scan erfasst.")
                }.font(.footnote)
            }
            .navigationTitle("Einstellungen").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
        }
    }
}
