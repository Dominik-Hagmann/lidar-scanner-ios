import SwiftUI

struct ArchiveSheet: View {
    @ObservedObject var model: ScanModel
    @ObservedObject private var language = LanguageManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var toDelete: SavedScan?
    @State private var sharing: SharedFiles?
    @State private var showImporter = false
    @State private var previewScan: SavedScan?
    @State private var previewPoints: [PCPoint] = []
    @State private var previewFullScreen = false
    var body: some View {
        NavigationStack {
            List {
                if model.savedScans.isEmpty {
                    ContentUnavailableView(L("No Scans Yet"), systemImage: "square.stack.3d.up",
                        description: Text(L("Scans appear here when you pause capture or export.")))
                }
                ForEach(model.savedScans) { scan in
                    scanRow(scan)
                }
            }
            .navigationTitle(L("My Scans"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showImporter = true
                    } label: {
                        Label(L("Import"), systemImage: "square.and.arrow.down")
                    }
                    .accessibilityLabel(L("Import Scan"))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Done")) { dismiss() }
                }
            }
            .sheet(item: $sharing) { ShareSheet(urls: $0.urls) }
            .sheet(item: Binding(
                get: { previewFullScreen ? nil : previewScan },
                set: { if $0 == nil && !previewFullScreen { previewScan = nil } }
            )) { scan in
                CloudPreviewSheet(
                    points: previewPoints,
                    total: scan.metadata.pointCount,
                    scanMetadata: scan.metadata,
                    groundControlPoints: scan.metadata.groundControlPoints ?? [],
                    onSaveGCPs: { model.updateGroundControlPoints(for: scan, points: $0) },
                    annotations: scan.metadata.annotations ?? [],
                    onSaveAnnotations: { model.updateAnnotations(for: scan, annotations: $0) },
                    isFullScreen: $previewFullScreen,
                    onClose: { previewScan = nil; previewFullScreen = false }
                )
            }
            .fullScreenCover(item: Binding(
                get: { previewFullScreen ? previewScan : nil },
                set: { if $0 == nil { previewFullScreen = false } }
            )) { scan in
                CloudPreviewSheet(
                    points: previewPoints,
                    total: scan.metadata.pointCount,
                    scanMetadata: scan.metadata,
                    groundControlPoints: scan.metadata.groundControlPoints ?? [],
                    onSaveGCPs: { model.updateGroundControlPoints(for: scan, points: $0) },
                    annotations: scan.metadata.annotations ?? [],
                    onSaveAnnotations: { model.updateAnnotations(for: scan, annotations: $0) },
                    isFullScreen: $previewFullScreen,
                    onClose: { previewScan = nil; previewFullScreen = false }
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
            Text(scan.metadata.title).font(.headline)
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
            HStack {
                badgesRow(for: scan)
                Spacer()
                Button {
                    Task {
                        let pts = await model.loadPreview(for: scan)
                        await MainActor.run {
                            previewPoints = pts
                            previewScan = scan
                        }
                    }
                } label: {
                    Image(systemName: "cube.transparent").frame(width: 44, height: 36)
                }
                .accessibilityLabel(L("View in 3D"))

                shareMenu(for: scan)
            }
        }
        .padding(.vertical, 6)
        .swipeActions { Button(L("Delete"), role: .destructive) { toDelete = scan } }
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
        }
    }

    @ViewBuilder
    private func shareMenu(for scan: SavedScan) -> some View {
        Menu {
            Section {
                ForEach(scan.existingFormats) { format in
                    Button {
                        var urls = [scan.url(for: format), scan.metadataURL]
                        if FileManager.default.fileExists(atPath: scan.gcpCSVURL.path) {
                            urls.append(scan.gcpCSVURL)
                        }
                        if FileManager.default.fileExists(atPath: scan.annotationsGeoJSONURL.path) {
                            urls.append(scan.annotationsGeoJSONURL)
                        }
                        sharing = SharedFiles(urls: urls)
                    } label: {
                        Label(format.title, systemImage: "cube.transparent")
                    }
                }
                if scan.hasMesh {
                    Button {
                        sharing = SharedFiles(urls: [scan.meshURL])
                    } label: {
                        Label(L("Export 3D Mesh (OBJ)"), systemImage: "cube")
                    }
                }
            }
            let hasGCPs = !(scan.metadata.groundControlPoints?.isEmpty ?? true)
            let hasAnnotations = !(scan.metadata.annotations?.isEmpty ?? true)
            if hasGCPs || hasAnnotations {
                Section {
                    if let gcps = scan.metadata.groundControlPoints, !gcps.isEmpty {
                        Button {
                            if !FileManager.default.fileExists(atPath: scan.gcpCSVURL.path) {
                                try? ScanStorage.gcpCSVData(for: gcps).write(to: scan.gcpCSVURL, options: .atomic)
                            }
                            sharing = SharedFiles(urls: [scan.gcpCSVURL])
                        } label: {
                            Label(L("Export Ground Control Points (CSV)"), systemImage: "scope")
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
                Button {
                    DispatchQueue.global(qos: .userInitiated).async {
                        do {
                            let url = try ScanReport.pointCloud(scan)
                            DispatchQueue.main.async { sharing = SharedFiles(urls: [url]) }
                        } catch { DispatchQueue.main.async { model.errorMessage = error.localizedDescription } }
                    }
                } label: {
                    Label(L("Export Report"), systemImage: "doc.richtext")
                }
            }
        } label: {
            Image(systemName: "square.and.arrow.up").frame(width: 44, height: 36)
        }
        .accessibilityLabel(L("Share Scan"))
    }
}
