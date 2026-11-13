import SwiftUI

struct SettingsSheet: View {
    @ObservedObject var model: ScanModel
    @ObservedObject private var language = LanguageManager.shared
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section(L("Language")) {
                    Picker(L("App Language"), selection: $language.selection) {
                        Text(L("System")).tag(AppLanguage.system)
                        Text("Deutsch").tag(AppLanguage.german)
                        Text("English").tag(AppLanguage.english)
                    }
                    .pickerStyle(.segmented)
                    Text(L("Switches the app language immediately between German and English, or follows the device language."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section(L("Point Density")) {
                    Picker(L("Voxel Size"), selection: $model.settings.voxelCentimeters) {
                        Text(L("0.5 cm")).tag(0.5)
                        Text(L("1 cm")).tag(1.0)
                        Text(L("2 cm")).tag(2.0)
                        Text(L("5 cm")).tag(5.0)
                    }.disabled(model.pointCount > 0)
                    Picker(L("Depth Pixels"), selection: $model.settings.pixelStep) {
                        Text(L("Every Pixel")).tag(1)
                        Text(L("Every Second Pixel per Axis")).tag(2)
                        Text(L("Every Fourth Pixel per Axis")).tag(4)
                    }.disabled(model.pointCount > 0)
                    if model.pointCount > 0 {
                        Text(L("Point density settings cannot be changed during an active scan and will apply to the next new scan."))
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text(L("One point is retained per voxel. Voxel size determines subsampling, not measurement accuracy."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section(L("Depth Range and Filters")) {
                    Picker(L("Maximum Depth"), selection: $model.settings.maxDepth) {
                        Text(L("2 m")).tag(2.0); Text(L("3 m")).tag(3.0); Text(L("5 m")).tag(5.0)
                    }
                    Picker(L("Confidence"), selection: $model.settings.minConfidence) {
                        Text(L("High Only")).tag(2)
                        Text(L("Medium and High")).tag(1)
                        Text(L("All")).tag(0)
                    }
                    Picker(L("Point Limit"), selection: $model.settings.maxPoints) {
                        Text(L("Automatic · No Fixed Point Count")).tag(0)
                        Text(L("500,000")).tag(500_000)
                        Text(L("1 Million")).tag(1_000_000)
                        Text(L("2 Million")).tag(2_000_000)
                        Text(L("5 Million")).tag(5_000_000)
                        Text(L("10 Million")).tag(10_000_000)
                    }
                    Text(L("In automatic mode, available memory determines the number of points that can be captured. When memory runs low, the app stops capture and saves the scan. Memory monitoring also applies when a fixed point limit is selected."))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(L("Depths below 0.2 m are discarded. No points are added while tracking is limited."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section(L("Export")) {
                    Picker(L("Format"), selection: $model.exportFormat) {
                        ForEach(ExportFormat.allCases) { Text($0.title).tag($0) }
                    }
                    Text(L("PLY, CSV, LAS, LAZ, and ASTM E57 preserve RGB color and confidence; XYZ contains three coordinate columns. All coordinates are local, in meters, with Z pointing up. Each scan includes a JSON metadata file."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section(L("Georeferencing")) {
                    Toggle(L("Record GNSS location"), isOn: $model.settings.recordLocation)
                    Text(L("Stores device GPS coordinates (WGS84), altitude, and compass heading in scan metadata and PDF reports. Works offline without an internet connection."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if TorchService.shared.isAvailable {
                    Section(L("Illumination")) {
                        Toggle(L("Torch"), isOn: Binding(
                            get: { TorchService.shared.isOn },
                            set: { TorchService.shared.setTorch(on: $0) }
                        ))
                        if TorchService.shared.isOn {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(L("Brightness"))
                                    Spacer()
                                    Text("\(Int(TorchService.shared.level * 100))%")
                                        .foregroundStyle(.secondary)
                                }
                                Slider(value: Binding(
                                    get: { TorchService.shared.level },
                                    set: { TorchService.shared.setTorch(on: true, level: $0) }
                                ), in: 0.1...1.0, step: 0.05)
                            }
                        }
                        Text(L("Illuminates dark surfaces, niches, trenches, and interiors during capture."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section(L("Storage")) {
                    Text(L("Pausing automatically saves the scan on this device. You can find it in Files under “On My iPhone” or “On My iPad” → “LiDAR-Scanner” → “Scans” and in the app’s scan archive."))
                    Text(L("After a camera interruption or a switch to the background, the scan can still be exported. Additional points are captured in a new scan."))
                }.font(.footnote)
                Section(L("About & Credits")) {
                    NavigationLink {
                        CreditsView()
                    } label: {
                        Label(L("Project & Credits"), systemImage: "info.circle")
                    }
                }
            }
            .navigationTitle(L("Settings")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("Done")) { dismiss() } } }
        }
    }
}
