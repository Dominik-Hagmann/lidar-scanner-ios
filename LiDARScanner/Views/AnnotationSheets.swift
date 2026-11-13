import SwiftUI

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
    let metadata: ScanMetadata?
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
                         ? L("No 3D annotations yet. Switch to Annotate mode in the 3D preview to place points, polygons, or rectangles.")
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
                        Menu {
                            Button {
                                export(.geojson)
                            } label: {
                                Label(L("GeoJSON (3D · QGIS / GIS)"), systemImage: "globe")
                            }
                            Button {
                                export(.csv)
                            } label: {
                                Label(L("CSV + WKT (Excel / QGIS)"), systemImage: "tablecells")
                            }
                            Button {
                                export(.dxf)
                            } label: {
                                Label(L("DXF (CAD · Layers by Tag)"), systemImage: "square.on.square.dashed")
                            }
                            Button {
                                export(.json)
                            } label: {
                                Label(L("JSON (Native)"), systemImage: "curlybraces")
                            }
                        } label: {
                            Label(L("Export"), systemImage: "square.and.arrow.up")
                        }
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
                data = try AnnotationExporter.geoJSONData(for: items, metadata: metadata)
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

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var color: AnnotationColor
    @State private var tags: [String]
    @State private var newTagText = ""
    @State private var note: String

    init(
        initial: CloudAnnotation,
        isNew: Bool,
        existingTags: [String],
        onSave: @escaping (CloudAnnotation) -> Void,
        onDelete: (() -> Void)?
    ) {
        self.initial = initial
        self.isNew = isNew
        self.existingTags = existingTags
        self.onSave = onSave
        self.onDelete = onDelete
        _title = State(initialValue: initial.title)
        _color = State(initialValue: initial.color)
        _tags = State(initialValue: initial.tags)
        _note = State(initialValue: initial.note)
    }

    private var availableSuggestedTags: [String] {
        var combined = existingTags
        for key in CloudAnnotation.suggestedTagKeys {
            combined.append(LanguageManager.string(key))
        }
        return CloudAnnotation.normalizedTags(combined)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L("Annotation")) {
                    TextField(L("Title (e.g. Wall 12)"), text: $title)
                        .textInputAutocapitalization(.sentences)
                    LabeledContent(L("Geometry"), value: initial.type.title)
                    if initial.type == .point, let p = initial.vertices.first {
                        LabeledContent(L("Coordinates"), value: String(format: "%.3f, %.3f, %.3f m",
                                                                         locale: Locale(identifier: "en_US_POSIX"), p.x, p.y, p.z))
                    } else {
                        LabeledContent(L("Vertices"), value: initial.vertices.count.formatted())
                        LabeledContent(L("Perimeter"), value: String(format: "%.2f m",
                                                                       locale: Locale(identifier: "en_US_POSIX"), initial.perimeterMeters))
                        LabeledContent(L("Area"), value: String(format: "%.3f m²",
                                                                  locale: Locale(identifier: "en_US_POSIX"), initial.areaSquareMeters))
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
                        var updated = initial
                        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.title = trimmed.isEmpty ? initial.title : trimmed
                        updated.color = color
                        updated.tags = CloudAnnotation.normalizedTags(tags)
                        updated.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(updated)
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
