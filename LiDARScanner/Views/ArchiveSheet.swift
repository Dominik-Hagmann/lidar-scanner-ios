import SwiftUI

struct ArchiveSheet: View {
    private enum ViewMode: String, CaseIterable, Identifiable {
        case list, map
        var id: String { rawValue }
    }

    @ObservedObject var model: ScanModel
    @ObservedObject private var language = LanguageManager.shared
    @ObservedObject private var collectionStore = ProjectCollectionStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var toDelete: SavedScan?
    @State private var sharing: SharedFiles?
    @State private var showImporter = false
    @State private var viewMode: ViewMode = .list
    @State private var previewScan: SavedScan?
    @State private var previewPoints: [PCPoint] = []
    @State private var previewMesh: MeshPreviewData?
    @State private var previewFullScreen = false
    @State private var searchText = ""
    @State private var selectedCollectionID: UUID?
    @State private var selectedTag: String?
    @State private var editingScan: SavedScan?
    @State private var showingCollectionsManager = false
    @State private var editingSelectedCollection: ProjectCollection?

    private var filteredScans: [SavedScan] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let activeTagLower = selectedTag?.lowercased()
        return model.savedScans.filter { scan in
            if let selectedCollectionID,
               !(scan.metadata.collectionIDs?.contains(selectedCollectionID) ?? false) {
                return false
            }
            if let activeTagLower,
               !(scan.metadata.tags?.contains { $0.lowercased() == activeTagLower } ?? false) {
                return false
            }
            if !query.isEmpty {
                let inTitle = scan.metadata.title.lowercased().contains(query)
                let inDesc = scan.metadata.projectDescription?.lowercased().contains(query) ?? false
                let inTags = scan.metadata.tags?.contains { $0.lowercased().contains(query) } ?? false
                let inCollection = collectionStore.collections(for: scan.metadata.collectionIDs)
                    .contains { $0.title.lowercased().contains(query) || $0.summary.lowercased().contains(query) }
                if !(inTitle || inDesc || inTags || inCollection) {
                    return false
                }
            }
            return true
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                let scansToDisplay = filteredScans
                let mapItems = ArchiveMapItem.loadAllGeoreferenced(pointClouds: scansToDisplay)
                if !model.savedScans.isEmpty || !mapItems.isEmpty {
                    Picker(L("Map"), selection: $viewMode) {
                        Label(L("List"), systemImage: "list.bullet").tag(ViewMode.list)
                        Label(L("Map"), systemImage: "map").tag(ViewMode.map)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }

                if viewMode == .map {
                    ArchiveScansMapView(
                        items: mapItems,
                        onSelectPointCloud: { scan in
                            Task {
                                async let ptsTask = model.loadPreview(for: scan)
                                async let meshTask = model.loadMesh(for: scan)
                                let (pts, loadedMesh) = await (ptsTask, meshTask)
                                await MainActor.run {
                                    previewPoints = pts
                                    previewMesh = loadedMesh
                                    previewScan = scan
                                }
                            }
                        }
                    )
                } else {
                    if !model.savedScans.isEmpty {
                        ArchiveFilterBar(
                            collectionStore: collectionStore,
                            searchText: $searchText,
                            selectedCollectionID: $selectedCollectionID,
                            selectedTag: $selectedTag,
                            availableTags: collectionStore.allUsedTags(pointClouds: model.savedScans),
                            totalCount: model.savedScans.count,
                            countForCollection: { cid in
                                model.savedScans.filter { $0.metadata.collectionIDs?.contains(cid) == true }.count
                            },
                            onManageCollections: { showingCollectionsManager = true }
                        )
                        if let selectedCollectionID,
                           let activeCollection = collectionStore.collection(for: selectedCollectionID) {
                            CollectionHeaderCard(
                                collection: activeCollection,
                                matchingPointClouds: scansToDisplay,
                                matchingGaussians: [],
                                onEdit: { editingSelectedCollection = activeCollection }
                            )
                        }
                    }

                    List {
                        if model.savedScans.isEmpty {
                            ContentUnavailableView(L("No Scans Yet"), systemImage: "square.stack.3d.up",
                                description: Text(L("Scans appear here when you pause capture or export.")))
                        } else if scansToDisplay.isEmpty {
                            ContentUnavailableView(L("No Matching Scans"), systemImage: "magnifyingglass",
                                description: Text(L("Adjust the active collection, tag, or search filter.")))
                        }
                        ForEach(scansToDisplay) { scan in
                            scanRow(scan)
                        }
                    }
                }
            }
            .navigationTitle(L("My Scans"))
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button {
                        showImporter = true
                    } label: {
                        Label(L("Import"), systemImage: "square.and.arrow.down")
                    }
                    .accessibilityLabel(L("Import Scan"))
                    Button {
                        showingCollectionsManager = true
                    } label: {
                        Label(L("Collections"), systemImage: "folder")
                    }
                    .accessibilityLabel(L("Collections"))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Done")) { dismiss() }
                }
            }
            .sheet(item: $sharing) { ShareSheet(urls: $0.urls) }
            .sheet(item: $editingScan) { scan in
                ProjectOrganizationEditorSheet(
                    scan: scan,
                    existingTags: collectionStore.allUsedTags(pointClouds: model.savedScans)
                ) { title, desc, tags, collectionIDs in
                    model.updateProjectOrganization(
                        for: scan,
                        title: title,
                        projectDescription: desc,
                        tags: tags,
                        collectionIDs: collectionIDs
                    )
                }
            }
            .sheet(isPresented: $showingCollectionsManager) {
                CollectionsManagerSheet(pointClouds: model.savedScans)
            }
            .sheet(item: $editingSelectedCollection) { collection in
                CollectionEditorSheet(
                    collection: collection,
                    existingTags: collectionStore.allUsedTags(pointClouds: model.savedScans)
                ) { updated in
                    collectionStore.save(updated)
                }
            }
            .sheet(item: Binding(
                get: { previewFullScreen ? nil : previewScan },
                set: { if $0 == nil && !previewFullScreen { previewScan = nil } }
            )) { scan in
                CloudPreviewSheet(
                    points: previewPoints,
                    total: scan.metadata.pointCount,
                    mesh: previewMesh,
                    scanMetadata: scan.metadata,
                    groundControlPoints: scan.metadata.groundControlPoints ?? [],
                    onSaveGCPs: { model.updateGroundControlPoints(for: scan, points: $0) },
                    annotations: scan.metadata.annotations ?? [],
                    onSaveAnnotations: { model.updateAnnotations(for: scan, annotations: $0) },
                    isFullScreen: $previewFullScreen,
                    onClose: { previewScan = nil; previewMesh = nil; previewFullScreen = false }
                )
            }
            .fullScreenCover(item: Binding(
                get: { previewFullScreen ? previewScan : nil },
                set: { if $0 == nil { previewFullScreen = false } }
            )) { scan in
                CloudPreviewSheet(
                    points: previewPoints,
                    total: scan.metadata.pointCount,
                    mesh: previewMesh,
                    scanMetadata: scan.metadata,
                    groundControlPoints: scan.metadata.groundControlPoints ?? [],
                    onSaveGCPs: { model.updateGroundControlPoints(for: scan, points: $0) },
                    annotations: scan.metadata.annotations ?? [],
                    onSaveAnnotations: { model.updateAnnotations(for: scan, annotations: $0) },
                    isFullScreen: $previewFullScreen,
                    onClose: { previewScan = nil; previewMesh = nil; previewFullScreen = false }
                )
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
            .alert(L("Delete Scan?"), isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } })) {
                Button(L("Cancel"), role: .cancel) { toDelete = nil }
                Button(L("Delete"), role: .destructive) { if let scan = toDelete { model.delete(scan) }; toDelete = nil }
            } message: { Text(L("The saved scan and its export files will be removed from this device.")) }
            .alert(L("LiDAR Scanner"), isPresented: Binding(get: { model.errorMessage != nil && toDelete == nil },
                set: { if !$0 { model.errorMessage = nil } })) {
                    Button(L("OK")) { model.errorMessage = nil }
                } message: { Text(model.errorMessage ?? "") }
        }
    }

    @ViewBuilder
    private func scanRow(_ scan: SavedScan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                ProjectThumbnailView(scan: scan, width: 88, height: 64)
                    .onTapGesture {
                        editingScan = scan
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(scan.metadata.title).font(.headline)
                    if let desc = scan.metadata.projectDescription, !desc.isEmpty {
                        Text(desc)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    HStack(spacing: 8) {
                        Text(scan.metadata.savedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(.secondary)
                        if let loc = scan.metadata.location {
                            Label(loc.formattedCoordinates, systemImage: "location.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    ProjectOrganizationBadges(
                        collectionIDs: scan.metadata.collectionIDs,
                        tags: scan.metadata.tags
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                badgesRow(for: scan)
                Spacer()
                Button {
                    editingScan = scan
                } label: {
                    Image(systemName: "tag")
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel(L("Project Details"))

                Button {
                    Task {
                        async let ptsTask = model.loadPreview(for: scan)
                        async let meshTask = model.loadMesh(for: scan)
                        let (pts, loadedMesh) = await (ptsTask, meshTask)
                        await MainActor.run {
                            previewPoints = pts
                            previewMesh = loadedMesh
                            previewScan = scan
                        }
                    }
                } label: {
                    Image(systemName: "cube.transparent").frame(width: 40, height: 36)
                }
                .accessibilityLabel(L("View in 3D"))

                shareMenu(for: scan)
            }
        }
        .padding(.vertical, 6)
        .swipeActions(edge: .trailing) {
            Button(L("Delete"), role: .destructive) { toDelete = scan }
            Button {
                editingScan = scan
            } label: {
                Label(L("Tags"), systemImage: "tag")
            }
            .tint(.indigo)
        }
    }

    @ViewBuilder
    private func badgesRow(for scan: SavedScan) -> some View {
        HStack(spacing: 6) {
            Text(L("Points: %@ · m · Z↑", scan.metadata.pointCount.formatted())).font(.subheadline)
            if let gcpCount = scan.metadata.groundControlPoints?.count, gcpCount > 0 {
                Text("GCP \(gcpCount)")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.orange.opacity(0.2), in: Capsule())
                    .foregroundStyle(.orange)
            }
            if let annCount = scan.metadata.annotations?.count, annCount > 0 {
                Text(L("Tags %@", annCount.formatted()))
                    .font(.caption2.bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.cyan.opacity(0.2), in: Capsule())
                    .foregroundStyle(.cyan)
            }
            if scan.hasMesh {
                Text("OBJ")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.teal.opacity(0.2), in: Capsule())
                    .foregroundStyle(.teal)
            }
            if scan.hasImages {
                Text(L("Photos %@", scan.imageCount.formatted()))
                    .font(.caption2.bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.purple.opacity(0.2), in: Capsule())
                    .foregroundStyle(.purple)
            }
        }
    }

    @ViewBuilder
    private func shareMenu(for scan: SavedScan) -> some View {
        Menu {
            Section {
                Menu {
                    ForEach(scan.existingFormats) { format in
                        Button {
                            var urls = [scan.url(for: format), scan.metadataURL]
                            if FileManager.default.fileExists(atPath: scan.gcpCSVURL.path) {
                                urls.append(scan.gcpCSVURL)
                            }
                            if FileManager.default.fileExists(atPath: scan.gcpGeoJSONURL.path) {
                                urls.append(scan.gcpGeoJSONURL)
                            }
                            if FileManager.default.fileExists(atPath: scan.annotationsGeoJSONURL.path) {
                                urls.append(scan.annotationsGeoJSONURL)
                            }
                            sharing = SharedFiles(urls: urls)
                        } label: {
                            Label(format.title, systemImage: "cube.transparent")
                        }
                    }
                } label: {
                    Label(L("Export 3D Point Cloud"), systemImage: "cube.transparent")
                }
                if scan.hasMesh {
                    MeshExportMenu { meshFormat in
                        model.shareMesh(scan, format: meshFormat) { url in
                            sharing = SharedFiles(urls: [url])
                        }
                    }
                }
                if scan.hasImages {
                    Button {
                        model.shareImages(scan) { url in
                            sharing = SharedFiles(urls: [url])
                        }
                    } label: {
                        Label(L("Export Images (ZIP)"), systemImage: "photo.on.rectangle.angled")
                    }
                }
            }
            let hasGCPs = !(scan.metadata.groundControlPoints?.isEmpty ?? true)
            let hasAnnotations = !(scan.metadata.annotations?.isEmpty ?? true)
            if hasGCPs || hasAnnotations {
                Section {
                    if let gcps = scan.metadata.groundControlPoints, !gcps.isEmpty {
                        GCPExportMenu { kind in
                            model.shareGCPs(scan, kind: kind) { url in
                                sharing = SharedFiles(urls: [url])
                            }
                        }
                    }
                    if let annotations = scan.metadata.annotations, !annotations.isEmpty {
                        AnnotationExportMenu { kind in
                            switch kind {
                            case .geojson:
                                if !FileManager.default.fileExists(atPath: scan.annotationsGeoJSONURL.path),
                                   let data = try? AnnotationExporter.geoJSONData(for: annotations, metadata: scan.metadata) {
                                    try? data.write(to: scan.annotationsGeoJSONURL, options: .atomic)
                                }
                                sharing = SharedFiles(urls: [scan.annotationsGeoJSONURL])
                            case .csv:
                                try? AnnotationExporter.csvData(for: annotations).write(to: scan.annotationsCSVURL, options: .atomic)
                                sharing = SharedFiles(urls: [scan.annotationsCSVURL])
                            case .dxf:
                                try? AnnotationExporter.dxfData(for: annotations).write(to: scan.annotationsDXFURL, options: .atomic)
                                sharing = SharedFiles(urls: [scan.annotationsDXFURL])
                            case .json:
                                break
                            }
                        }
                    }
                }
            }
            Section {
                ReportExportMenu { format in
                    DispatchQueue.global(qos: .userInitiated).async {
                        do {
                            let url = try ScanReport.pointCloud(scan, format: format)
                            DispatchQueue.main.async { sharing = SharedFiles(urls: [url]) }
                        } catch { DispatchQueue.main.async { model.errorMessage = error.localizedDescription } }
                    }
                }
            }
        } label: {
            Image(systemName: "square.and.arrow.up").frame(width: 44, height: 36)
        }
        .accessibilityLabel(L("Share Scan"))
    }
}
