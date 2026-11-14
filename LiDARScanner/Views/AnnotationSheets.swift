import SwiftUI
import simd

struct ProjectedAnnotationLabel: Identifiable, Equatable {
    let id: UUID
    let title: String
    let primaryTag: String?
    let color: AnnotationColor
    let type: CloudAnnotationGeometryType
    let screenPoint: CGPoint
    let isSelected: Bool
}

struct ProjectedAnnotationShape: Identifiable, Equatable {
    let id: UUID
    let color: AnnotationColor
    let isPolygon: Bool
    let isSelected: Bool
    let points: [CGPoint]
}

@MainActor
final class AnnotationOverlayProjectionModel: ObservableObject {
    @Published var labels: [ProjectedAnnotationLabel] = []
    @Published var shapes: [ProjectedAnnotationShape] = []
    @Published var draftScreenPoints: [CGPoint] = []

    func update(
        labels newLabels: [ProjectedAnnotationLabel],
        shapes newShapes: [ProjectedAnnotationShape] = [],
        draftPoints newDraft: [CGPoint] = []
    ) {
        if !approxEqualLabels(labels, newLabels) {
            labels = newLabels
        }
        if !approxEqualShapes(shapes, newShapes) {
            shapes = newShapes
        }
        if !approxEqualPoints(draftScreenPoints, newDraft) {
            draftScreenPoints = newDraft
        }
    }

    private func approxEqualLabels(_ a: [ProjectedAnnotationLabel], _ b: [ProjectedAnnotationLabel]) -> Bool {
        guard a.count == b.count else { return false }
        for (l, r) in zip(a, b) {
            if l.id != r.id || l.title != r.title || l.primaryTag != r.primaryTag ||
                l.color != r.color || l.isSelected != r.isSelected {
                return false
            }
            if abs(l.screenPoint.x - r.screenPoint.x) > 0.6 || abs(l.screenPoint.y - r.screenPoint.y) > 0.6 {
                return false
            }
        }
        return true
    }

    private func approxEqualShapes(_ a: [ProjectedAnnotationShape], _ b: [ProjectedAnnotationShape]) -> Bool {
        guard a.count == b.count else { return false }
        for (l, r) in zip(a, b) {
            if l.id != r.id || l.color != r.color || l.isPolygon != r.isPolygon || l.isSelected != r.isSelected {
                return false
            }
            if !approxEqualPoints(l.points, r.points) { return false }
        }
        return true
    }

    private func approxEqualPoints(_ a: [CGPoint], _ b: [CGPoint]) -> Bool {
        guard a.count == b.count else { return false }
        for (l, r) in zip(a, b) {
            if abs(l.x - r.x) > 0.6 || abs(l.y - r.y) > 0.6 { return false }
        }
        return true
    }
}

struct AnnotationShapesCanvasOverlay: View {
    @ObservedObject var projection: AnnotationOverlayProjectionModel
    let isEditingDraft: Bool

    var body: some View {
        Canvas { context, _ in
            for shape in projection.shapes where !shape.points.isEmpty {
                let uiColor = shape.color.uiColor
                let swiftColor = Color(uiColor: uiColor)
                if shape.isPolygon && shape.points.count >= 3 {
                    var path = Path()
                    path.addLines(shape.points)
                    path.closeSubpath()
                    context.fill(path, with: .color(swiftColor.opacity(shape.isSelected ? 0.34 : 0.22)))
                    context.stroke(path, with: .color(swiftColor), lineWidth: shape.isSelected ? 3.0 : 2.0)
                }
                for pt in shape.points {
                    let r: CGFloat = shape.isPolygon ? (shape.isSelected ? 5 : 4) : (shape.isSelected ? 7 : 5.5)
                    let rect = CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(swiftColor))
                    context.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.85)), lineWidth: 1)
                }
            }

            let draft = projection.draftScreenPoints
            if !draft.isEmpty {
                let draftColor = Color.cyan
                if draft.count >= 2 {
                    var path = Path()
                    path.addLines(draft)
                    if draft.count >= 3 {
                        path.closeSubpath()
                        context.fill(path, with: .color(draftColor.opacity(0.24)))
                    }
                    context.stroke(
                        path,
                        with: .color(draftColor),
                        style: StrokeStyle(lineWidth: isEditingDraft ? 2.8 : 2.2, dash: isEditingDraft ? [6, 4] : [])
                    )
                }
                for pt in draft {
                    let r: CGFloat = 5.5
                    let rect = CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(draftColor))
                    context.stroke(Path(ellipseIn: rect), with: .color(.white), lineWidth: 1.5)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct AnnotationLabelsOverlayView: View {
    @ObservedObject var projection: AnnotationOverlayProjectionModel
    let onTapLabel: (UUID) -> Void

    var body: some View {
        GeometryReader { geo in
            ForEach(projection.labels) { label in
                let clampedX = min(max(label.screenPoint.x, 48), max(48, geo.size.width - 48))
                let clampedY = min(max(label.screenPoint.y - 24, 24), max(24, geo.size.height - 90))
                Button {
                    onTapLabel(label.id)
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color(uiColor: label.color.uiColor))
                            .frame(width: 7, height: 7)
                        Text(label.title)
                            .font(.caption2.weight(.bold))
                            .lineLimit(1)
                        if let tag = label.primaryTag {
                            Text("#\(tag)")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color(uiColor: label.color.uiColor))
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                Color(uiColor: label.color.uiColor).opacity(label.isSelected ? 0.95 : 0.55),
                                lineWidth: label.isSelected ? 1.8 : 1.0
                            )
                    )
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                }
                .foregroundStyle(.white)
                .buttonStyle(.plain)
                .position(x: clampedX, y: clampedY)
            }
        }
    }
}

struct AnnotationToolHUDCard: View {
    @Binding var annotations: [CloudAnnotation]
    @Binding var selectedAnnotationID: UUID?
    @Binding var activeTagFilter: String?
    @Binding var annotationShape: CloudAnnotationGeometryType
    @Binding var draftPoints: [SIMD3<Float>]
    @Binding var editingAnnotation: CloudAnnotation?
    let onFinishNewDraft: () -> Void
    let onCommitGeometryEdit: () -> Void
    let onCancelGeometryEdit: () -> Void
    let onOpenList: () -> Void
    let onEditAnnotation: (CloudAnnotation) -> Void

    var body: some View {
        VStack(spacing: 8) {
            if let editing = editingAnnotation {
                HStack(spacing: 8) {
                    Image(systemName: "pencil.and.outline")
                        .foregroundStyle(.cyan)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Editing: %@", editing.title))
                            .font(.caption.weight(.bold))
                            .lineLimit(1)
                        Text(editing.type == .point
                             ? L("Tap scene to move point")
                             : L("Tap scene to add corners (%@)", draftPoints.count.formatted()))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(L("Cancel")) {
                        onCancelGeometryEdit()
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)

                    if editing.type == .polygon && !draftPoints.isEmpty {
                        Button {
                            draftPoints.removeLast()
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                        .accessibilityLabel(L("Undo"))
                    }

                    Button(L("Save")) {
                        onCommitGeometryEdit()
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)
                    .foregroundStyle(.black)
                    .disabled(editing.type == .point ? draftPoints.isEmpty : draftPoints.count < 3)
                }
            } else {
                HStack(spacing: 6) {
                    ForEach(CloudAnnotationGeometryType.allCases) { shape in
                        Button {
                            annotationShape = shape
                            draftPoints = []
                        } label: {
                            Label(shape.title, systemImage: shape.systemImage)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(annotationShape == shape ? Color.cyan.opacity(0.28) : Color.secondary.opacity(0.14), in: Capsule())
                        }
                        .foregroundStyle(annotationShape == shape ? .cyan : .primary)
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    if !annotations.isEmpty {
                        Button(L("List (%@)", annotations.count.formatted())) {
                            onOpenList()
                        }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.bordered)
                        .tint(.cyan)
                    }
                }

                HStack(spacing: 8) {
                    Circle().fill(Color.cyan).frame(width: 8, height: 8)
                    Text(annotationShape == .point
                         ? L("Tap a point to add annotation")
                         : L("Polygon: %@ vertices (min 3)", draftPoints.count.formatted()))
                        .font(.caption.weight(.medium))
                    Spacer()
                    if !draftPoints.isEmpty {
                        Button {
                            draftPoints.removeLast()
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                        .accessibilityLabel(L("Undo"))

                        if annotationShape == .polygon && draftPoints.count >= 3 {
                            Button(L("Finish")) {
                                onFinishNewDraft()
                            }
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.borderedProminent)
                            .tint(.cyan)
                            .foregroundStyle(.black)
                        }
                    }
                }

                if let activeTagFilter {
                    HStack(spacing: 6) {
                        Text(L("Filter: #%@", activeTagFilter == "__untagged__" ? L("Untagged") : activeTagFilter))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.cyan)
                        Spacer()
                        Button(L("Clear")) {
                            self.activeTagFilter = nil
                        }
                        .font(.caption2)
                    }
                } else if !annotations.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(annotations) { ann in
                                Button {
                                    selectedAnnotationID = ann.id
                                    onEditAnnotation(ann)
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: ann.type.systemImage)
                                        Text(ann.title)
                                        Image(systemName: "pencil")
                                            .font(.caption2)
                                            .opacity(0.75)
                                    }
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color(uiColor: ann.color.uiColor).opacity(selectedAnnotationID == ann.id ? 0.35 : 0.18), in: Capsule())
                                }
                                .foregroundStyle(.primary)
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

enum AnnotationExportKind {
    case geojson
    case csv
    case dxf
    case json

    var fileName: String {
        switch self {
        case .geojson: return "annotations.geojson"
        case .csv: return "annotations.csv"
        case .dxf: return "annotations.dxf"
        case .json: return "annotations.json"
        }
    }
}

struct AnnotationExportMenu: View {
    var titleKey: String = "Export Annotations"
    var systemImage: String = "mappin.and.ellipse"
    var includeJSON: Bool = false
    let onSelect: (AnnotationExportKind) -> Void

    var body: some View {
        Menu {
            Button {
                onSelect(.geojson)
            } label: {
                Label(L("GeoJSON (3D · QGIS / GIS)"), systemImage: "globe")
            }
            Button {
                onSelect(.csv)
            } label: {
                Label(L("CSV + WKT (Excel / QGIS)"), systemImage: "tablecells")
            }
            Button {
                onSelect(.dxf)
            } label: {
                Label(L("DXF (CAD · Layers by Tag)"), systemImage: "square.on.square.dashed")
            }
            if includeJSON {
                Divider()
                Button {
                    onSelect(.json)
                } label: {
                    Label(L("JSON (Native)"), systemImage: "curlybraces")
                }
            }
        } label: {
            Label(L(titleKey), systemImage: systemImage)
        }
    }
}

struct ReportExportMenu: View {
    let onSelect: (ReportFormat) -> Void

    var body: some View {
        Menu {
            Button {
                onSelect(.pdf)
            } label: {
                Label(L("PDF Report"), systemImage: "doc.richtext")
            }
            Button {
                onSelect(.docx)
            } label: {
                Label(L("Word Document (.docx)"), systemImage: "doc.text")
            }
        } label: {
            Label(L("Export Report"), systemImage: "doc.richtext")
        }
    }
}

struct MeshExportMenu: View {
    var selectedFormat: MeshExportFormat? = nil
    let onSelect: (MeshExportFormat) -> Void

    var body: some View {
        Menu {
            ForEach(MeshExportFormat.allCases) { format in
                Button {
                    onSelect(format)
                } label: {
                    if format == selectedFormat {
                        Label(format.title, systemImage: "checkmark")
                    } else {
                        Text(format.title)
                    }
                }
            }
        } label: {
            Label(L("Export 3D Mesh"), systemImage: "cube")
        }
    }
}

struct ShareActionButtonLabel: View {
    let isBusy: Bool
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            if isBusy { ProgressView() }
            Label(L(isBusy ? "Saving…" : "Share"), systemImage: "square.and.arrow.up")
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(tint.opacity(0.20), in: Capsule())
        .overlay(Capsule().stroke(tint.opacity(0.45), lineWidth: 1))
        .contentShape(Capsule())
    }
}

struct AnnotationEditorState: Identifiable {
    let id = UUID()
    let existing: CloudAnnotation?
    let initial: CloudAnnotation
}

private enum AnnotationOrganization: String, CaseIterable {
    case groupedByTag
    case chronological
}

struct AnnotationListSheet: View {
    @Binding var annotations: [CloudAnnotation]
    @Binding var selectedAnnotationID: UUID?
    @Binding var activeTagFilter: String?
    let exportMetadata: AnnotationExportMetadata?
    let onChanged: ([CloudAnnotation]) -> Void
    let onEdit: (CloudAnnotation) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var organization: AnnotationOrganization = .groupedByTag
    @State private var searchText = ""
    @State private var shareFile: SharedFiles?

    private var allTags: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for ann in annotations {
            for tag in ann.tags {
                let key = tag.lowercased()
                if seen.insert(key).inserted {
                    result.append(tag)
                }
            }
        }
        return result.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var hasUntagged: Bool {
        annotations.contains { $0.tags.isEmpty }
    }

    private var filteredAnnotations: [CloudAnnotation] {
        annotations.filter { ann in
            let matchesTag: Bool
            if let activeTagFilter {
                if activeTagFilter == "__untagged__" {
                    matchesTag = ann.tags.isEmpty
                } else {
                    matchesTag = ann.tags.contains { $0.caseInsensitiveCompare(activeTagFilter) == .orderedSame }
                }
            } else {
                matchesTag = true
            }
            guard matchesTag else { return false }
            let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !q.isEmpty else { return true }
            return ann.title.localizedCaseInsensitiveContains(q)
                || ann.note.localizedCaseInsensitiveContains(q)
                || ann.tags.contains { $0.localizedCaseInsensitiveContains(q) }
        }
    }

    private var tagSections: [(header: String, items: [CloudAnnotation])] {
        var sections: [(String, [CloudAnnotation])] = []
        for tag in allTags {
            let matching = filteredAnnotations.filter {
                $0.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
            }
            if !matching.isEmpty {
                sections.append((tag, matching))
            }
        }
        let untagged = filteredAnnotations.filter { $0.tags.isEmpty }
        if !untagged.isEmpty {
            sections.append((L("Untagged"), untagged))
        }
        return sections
    }

    var body: some View {
        NavigationStack {
            List {
                if !annotations.isEmpty {
                    Section {
                        Picker(L("Organization"), selection: $organization) {
                            Text(L("By Tag")).tag(AnnotationOrganization.groupedByTag)
                            Text(L("Newest")).tag(AnnotationOrganization.chronological)
                        }
                        .pickerStyle(.segmented)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                tagFilterChip(label: L("All (%@)", annotations.count.formatted()), tagValue: nil)
                                ForEach(allTags, id: \.self) { tag in
                                    let count = annotations.filter {
                                        $0.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
                                    }.count
                                    tagFilterChip(label: "\(tag) (\(count))", tagValue: tag)
                                }
                                if hasUntagged {
                                    let count = annotations.filter { $0.tags.isEmpty }.count
                                    tagFilterChip(label: "\(L("Untagged")) (\(count))", tagValue: "__untagged__")
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                if filteredAnnotations.isEmpty {
                    Text(annotations.isEmpty
                         ? L("No 3D annotations yet. Switch to Annotate mode in the 3D preview to place points or polygons.")
                         : L("No annotations match the active filter."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if organization == .groupedByTag {
                    ForEach(tagSections, id: \.header) { section in
                        Section(section.header) {
                            ForEach(section.items) { ann in
                                annotationRow(ann)
                            }
                            .onDelete { offsets in
                                deleteFrom(items: section.items, offsets: offsets)
                            }
                        }
                    }
                } else {
                    let ordered = filteredAnnotations.sorted { $0.createdAt > $1.createdAt }
                    ForEach(ordered) { ann in
                        annotationRow(ann)
                    }
                    .onDelete { offsets in
                        deleteFrom(items: ordered, offsets: offsets)
                    }
                }
            }
            .searchable(text: $searchText, prompt: L("Search title, tag, note"))
            .navigationTitle(L("3D Annotations"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !filteredAnnotations.isEmpty {
                        AnnotationExportMenu(
                            titleKey: "Export",
                            systemImage: "square.and.arrow.up",
                            includeJSON: true,
                            onSelect: export
                        )
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Done")) { dismiss() }
                }
            }
            .sheet(item: $shareFile) { item in
                ShareSheet(urls: item.urls)
            }
        }
    }

    private func tagFilterChip(label: String, tagValue: String?) -> some View {
        let isSelected = activeTagFilter == tagValue
        return Button {
            activeTagFilter = (isSelected && tagValue != nil) ? nil : tagValue
        } label: {
            Text(label)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.14), in: Capsule())
        }
        .foregroundStyle(isSelected ? Color.accentColor : .primary)
        .buttonStyle(.plain)
    }

    private func annotationRow(_ ann: CloudAnnotation) -> some View {
        Button {
            selectedAnnotationID = ann.id
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                onEdit(ann)
            }
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Image(systemName: ann.type.systemImage)
                        .foregroundStyle(Color(uiColor: ann.color.uiColor))
                    Text(ann.title).font(.headline)
                    Spacer()
                    Text(ann.type.title)
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                }

                let c = ann.centroid
                if ann.type == .point {
                    Text(String(format: "%.3f, %.3f, %.3f m", locale: Locale(identifier: "en_US_POSIX"), c.x, c.y, c.z))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    Text(String(format: "%.2f m · %.3f m² · (%@ pts)",
                                locale: Locale(identifier: "en_US_POSIX"),
                                ann.perimeterMeters, ann.areaSquareMeters, "\(ann.vertices.count)"))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                if !ann.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(ann.tags, id: \.self) { tag in
                                Text("#\(tag)")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 7).padding(.vertical, 2)
                                    .background(Color(uiColor: ann.color.uiColor).opacity(0.18), in: Capsule())
                                    .foregroundStyle(Color(uiColor: ann.color.uiColor))
                            }
                        }
                    }
                }

                if !ann.note.isEmpty {
                    Text(ann.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .foregroundStyle(.primary)
    }

    private func deleteFrom(items: [CloudAnnotation], offsets: IndexSet) {
        let idsToRemove = Set(offsets.map { items[$0].id })
        annotations.removeAll { idsToRemove.contains($0.id) }
        if let selectedAnnotationID, idsToRemove.contains(selectedAnnotationID) {
            self.selectedAnnotationID = nil
        }
        onChanged(annotations)
    }

    private func export(_ kind: AnnotationExportKind) {
        let items = filteredAnnotations
        guard !items.isEmpty else { return }
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(kind.fileName)
        do {
            let data: Data
            switch kind {
            case .geojson:
                data = try AnnotationExporter.geoJSONData(for: items, exportMetadata: exportMetadata)
            case .csv:
                data = AnnotationExporter.csvData(for: items)
            case .dxf:
                data = AnnotationExporter.dxfData(for: items)
            case .json:
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                data = try encoder.encode(items)
            }
            try data.write(to: tempURL, options: .atomic)
            shareFile = SharedFiles(urls: [tempURL])
        } catch {}
    }
}

struct AnnotationEditorSheet: View {
    let initial: CloudAnnotation
    let isNew: Bool
    let existingTags: [String]
    let onSave: (CloudAnnotation) -> Void
    let onDelete: (() -> Void)?
    let onEditGeometry: ((CloudAnnotation) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var color: AnnotationColor
    @State private var tags: [String]
    @State private var newTagText = ""
    @State private var note: String
    @State private var vertices: [AnnotationPoint3D]

    init(
        initial: CloudAnnotation,
        isNew: Bool,
        existingTags: [String],
        onSave: @escaping (CloudAnnotation) -> Void,
        onDelete: (() -> Void)?,
        onEditGeometry: ((CloudAnnotation) -> Void)? = nil
    ) {
        self.initial = initial
        self.isNew = isNew
        self.existingTags = existingTags
        self.onSave = onSave
        self.onDelete = onDelete
        self.onEditGeometry = onEditGeometry
        _title = State(initialValue: initial.title)
        _color = State(initialValue: initial.color)
        _tags = State(initialValue: initial.tags)
        _note = State(initialValue: initial.note)
        _vertices = State(initialValue: initial.vertices)
    }

    private var availableSuggestedTags: [String] {
        var combined = existingTags
        for key in CloudAnnotation.suggestedTagKeys {
            combined.append(LanguageManager.string(key))
        }
        return CloudAnnotation.normalizedTags(combined)
    }

    private func draftAnnotation() -> CloudAnnotation {
        var updated = initial
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.title = trimmed.isEmpty ? initial.title : trimmed
        updated.color = color
        updated.tags = CloudAnnotation.normalizedTags(tags)
        updated.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.vertices = vertices
        return updated
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L("Annotation")) {
                    TextField(L("Title (e.g. Wall 12)"), text: $title)
                        .textInputAutocapitalization(.sentences)
                    LabeledContent(L("Geometry"), value: initial.type.title)
                    if initial.type == .point, let p = vertices.first {
                        LabeledContent(L("Coordinates"), value: String(format: "%.3f, %.3f, %.3f m",
                                                                         locale: Locale(identifier: "en_US_POSIX"), p.x, p.y, p.z))
                    } else {
                        LabeledContent(L("Vertices"), value: vertices.count.formatted())
                        LabeledContent(L("Perimeter"), value: String(format: "%.2f m",
                                                                       locale: Locale(identifier: "en_US_POSIX"), AnnotationGeometryHelper.perimeter(vertices)))
                        LabeledContent(L("Area"), value: String(format: "%.3f m²",
                                                                  locale: Locale(identifier: "en_US_POSIX"), AnnotationGeometryHelper.area(vertices)))
                    }
                    if !isNew, let onEditGeometry {
                        Button {
                            commitTagInput()
                            let updated = draftAnnotation()
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                onEditGeometry(updated)
                            }
                        } label: {
                            Label(initial.type == .point ? L("Move Point in 3D") : L("Edit Points in 3D"),
                                  systemImage: "viewfinder")
                        }
                    }
                }

                if !isNew && initial.type == .polygon && vertices.count > 3 {
                    Section(L("Vertices")) {
                        ForEach(Array(vertices.enumerated()), id: \.offset) { index, pt in
                            HStack {
                                Text(String(format: "#%d · %.3f, %.3f, %.3f m",
                                            index + 1, pt.x, pt.y, pt.z))
                                    .font(.caption.monospacedDigit())
                                Spacer()
                                Button(role: .destructive) {
                                    if vertices.count > 3 {
                                        vertices.remove(at: index)
                                    }
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }

                Section(L("Color")) {
                    HStack(spacing: 14) {
                        ForEach(AnnotationColor.allCases) { option in
                            Button {
                                color = option
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(Color(uiColor: option.uiColor))
                                        .frame(width: 28, height: 28)
                                    if color == option {
                                        Circle()
                                            .strokeBorder(.primary, lineWidth: 2.5)
                                            .frame(width: 34, height: 34)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section(L("Tags")) {
                    HStack {
                        TextField(L("Add tag (e.g. Trench A)"), text: $newTagText)
                            .textInputAutocapitalization(.words)
                            .onSubmit { commitTagInput() }
                        Button(L("Add")) {
                            commitTagInput()
                        }
                        .disabled(newTagText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    if !tags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(tags, id: \.self) { tag in
                                    Button {
                                        tags.removeAll { $0.caseInsensitiveCompare(tag) == .orderedSame }
                                    } label: {
                                        HStack(spacing: 4) {
                                            Text("#\(tag)")
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.caption2)
                                        }
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 10).padding(.vertical, 5)
                                        .background(Color(uiColor: color.uiColor).opacity(0.2), in: Capsule())
                                    }
                                    .foregroundStyle(.primary)
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(availableSuggestedTags, id: \.self) { suggestion in
                                let active = tags.contains { $0.caseInsensitiveCompare(suggestion) == .orderedSame }
                                Button {
                                    toggleTag(suggestion)
                                } label: {
                                    Text(active ? "✓ \(suggestion)" : "+ \(suggestion)")
                                        .font(.caption)
                                        .padding(.horizontal, 9).padding(.vertical, 4)
                                        .background(active ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.12), in: Capsule())
                                }
                                .foregroundStyle(active ? Color.accentColor : .secondary)
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                Section(L("Notes")) {
                    TextField(L("Description, stratigraphy, condition…"), text: $note, axis: .vertical)
                        .lineLimit(2...5)
                }

                if let onDelete {
                    Section {
                        Button(L("Delete Annotation"), role: .destructive) {
                            onDelete()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isNew ? L("New Annotation") : L("Edit Annotation"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Save")) {
                        commitTagInput()
                        onSave(draftAnnotation())
                        dismiss()
                    }
                }
            }
        }
    }

    private func toggleTag(_ tag: String) {
        if let idx = tags.firstIndex(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
            tags.remove(at: idx)
        } else {
            tags.append(tag)
        }
    }

    private func commitTagInput() {
        let parts = newTagText.split(separator: ",").map { String($0) }
        if !parts.isEmpty {
            tags = CloudAnnotation.normalizedTags(tags + parts)
        }
        newTagText = ""
    }
}
