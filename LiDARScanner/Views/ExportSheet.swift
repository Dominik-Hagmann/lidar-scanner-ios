import SwiftUI

struct ExportSheet: View {
    @ObservedObject var model: ScanModel
    @ObservedObject private var language = LanguageManager.shared
    @ObservedObject private var collectionStore = ProjectCollectionStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showingNewCollection = false
    @State private var newCollectionTitle = ""
    @State private var newCollectionSummary = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(L("Scan")) {
                    TextField(L("Title, e.g. Context 104"), text: $model.scanTitle)
                        .textInputAutocapitalization(.sentences).disabled(model.isBusy)
                    TextField(L("Short description, e.g. North profile wall"), text: $model.scanDescription, axis: .vertical)
                        .lineLimit(2...4)
                        .textInputAutocapitalization(.sentences)
                        .disabled(model.isBusy)
                    LabeledContent(L("Points"), value: model.pointCount.formatted())
                    if model.savedImageCount > 0 {
                        LabeledContent(L("Saved Images"), value: model.savedImageCount.formatted())
                    }
                    if !model.activeGroundControlPoints.isEmpty {
                        LabeledContent(L("Ground Control Points"), value: model.activeGroundControlPoints.count.formatted())
                    }
                    LabeledContent(L("Coordinates"), value: L("Local · Meters · Z Up"))
                }
                Section(L("Tags & Collections")) {
                    ProjectTagsEditorSection(
                        tags: $model.activeProjectTags,
                        existingCatalogTags: collectionStore.allUsedTags(pointClouds: model.savedScans)
                    )
                    .disabled(model.isBusy)

                    ForEach(collectionStore.collections) { collection in
                        let isAssigned = model.activeCollectionIDs.contains(collection.id)
                        Button {
                            if isAssigned {
                                model.activeCollectionIDs.removeAll { $0 == collection.id }
                            } else {
                                model.activeCollectionIDs.append(collection.id)
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: isAssigned ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(isAssigned ? Color.indigo : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(collection.title)
                                        .foregroundStyle(.primary)
                                    if !collection.summary.isEmpty {
                                        Text(collection.summary)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(model.isBusy)
                    }

                    if showingNewCollection {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField(L("Collection Title"), text: $newCollectionTitle)
                                .textInputAutocapitalization(.sentences)
                            TextField(L("Short description alongside title"), text: $newCollectionSummary, axis: .vertical)
                                .lineLimit(2...3)
                                .textInputAutocapitalization(.sentences)
                            HStack {
                                Button(L("Cancel"), role: .cancel) {
                                    newCollectionTitle = ""
                                    newCollectionSummary = ""
                                    showingNewCollection = false
                                }
                                Spacer()
                                Button(L("Create & Assign")) {
                                    let created = collectionStore.save(ProjectCollection(
                                        title: newCollectionTitle,
                                        summary: newCollectionSummary,
                                        tags: []
                                    ))
                                    if !model.activeCollectionIDs.contains(created.id) {
                                        model.activeCollectionIDs.append(created.id)
                                    }
                                    newCollectionTitle = ""
                                    newCollectionSummary = ""
                                    showingNewCollection = false
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(newCollectionTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                    } else {
                        Button {
                            showingNewCollection = true
                        } label: {
                            Label(L("New Collection…"), systemImage: "folder.badge.plus")
                        }
                        .disabled(model.isBusy)
                    }
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
                        MeshExportMenu(selectedFormat: model.meshExportFormat) { meshFormat in
                            model.meshExportFormat = meshFormat
                            model.saveCurrent(share: false, shareMesh: true, meshFormat: meshFormat)
                        }
                        .disabled(model.isBusy || model.pointCount == 0)
                    }
                    if model.savedImageCount > 0 || model.savedScanDetail?.hasImages == true {
                        Button {
                            model.saveCurrent(share: false, shareImages: true)
                        } label: {
                            Label(L("Export Images (ZIP)"), systemImage: "photo.on.rectangle.angled")
                        }
                        .disabled(model.isBusy || model.pointCount == 0)
                    }
                    ReportExportMenu { format in
                        model.saveCurrent(share: false, reportFormat: format)
                    }
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
