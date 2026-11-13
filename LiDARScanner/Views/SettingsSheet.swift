import SwiftUI

struct SettingsSheet: View {
    @ObservedObject var model: ScanModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Point Density") {
                    Picker("Voxel Size", selection: $model.settings.voxelCentimeters) {
                        Text("0.5 cm").tag(0.5)
                        Text("1 cm").tag(1.0)
                        Text("2 cm").tag(2.0)
                        Text("5 cm").tag(5.0)
                    }.disabled(model.pointCount > 0)
                    Picker("Depth Pixels", selection: $model.settings.pixelStep) {
                        Text("Every Pixel").tag(1)
                        Text("Every Second Pixel per Axis").tag(2)
                        Text("Every Fourth Pixel per Axis").tag(4)
                    }.disabled(model.pointCount > 0)
                    if model.pointCount > 0 {
                        Text("Point density settings cannot be changed during an active scan and will apply to the next new scan.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("One point is retained per voxel. Voxel size determines subsampling, not measurement accuracy.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Depth Range and Filters") {
                    Picker("Maximum Depth", selection: $model.settings.maxDepth) {
                        Text("2 m").tag(2.0); Text("3 m").tag(3.0); Text("5 m").tag(5.0)
                    }
                    Picker("Confidence", selection: $model.settings.minConfidence) {
                        Text("High Only").tag(2)
                        Text("Medium and High").tag(1)
                        Text("All").tag(0)
                    }
                    Picker("Point Limit", selection: $model.settings.maxPoints) {
                        Text("Automatic · No Fixed Point Count").tag(0)
                        Text("500,000").tag(500_000)
                        Text("1 Million").tag(1_000_000)
                        Text("2 Million").tag(2_000_000)
                        Text("5 Million").tag(5_000_000)
                        Text("10 Million").tag(10_000_000)
                    }
                    Text("In automatic mode, available memory determines the number of points that can be captured. When memory runs low, the app stops capture and saves the scan. Memory monitoring also applies when a fixed point limit is selected.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Depths below 0.2 m are discarded. No points are added while tracking is limited.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Export") {
                    Picker("Format", selection: $model.exportFormat) {
                        ForEach(ExportFormat.allCases) { Text($0.title).tag($0) }
                    }
                    Text("PLY contains XYZ, RGB, and confidence; XYZ contains three coordinate columns. All coordinates are local, in meters, with Z pointing up. Each scan includes a JSON metadata file.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if TorchService.shared.isAvailable {
                    Section("Illumination") {
                        Toggle("Torch", isOn: Binding(
                            get: { TorchService.shared.isOn },
                            set: { TorchService.shared.setTorch(on: $0) }
                        ))
                        if TorchService.shared.isOn {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Brightness")
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
                        Text("Illuminates dark surfaces, niches, trenches, and interiors during capture.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Storage") {
                    Text("Pausing automatically saves the scan on this device. You can find it in Files under “On My iPhone” or “On My iPad” → “LiDAR-Scanner” → “Scans” and in the app’s scan archive.")
                    Text("After a camera interruption or a switch to the background, the scan can still be exported. Additional points are captured in a new scan.")
                }.font(.footnote)
                Section("About & Credits") {
                    NavigationLink {
                        CreditsView()
                    } label: {
                        Label("Project & Credits", systemImage: "info.circle")
                    }
                }
            }
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
