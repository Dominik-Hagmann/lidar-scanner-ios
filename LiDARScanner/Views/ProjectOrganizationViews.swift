import SwiftUI
import UIKit

// MARK: - Project Screenshot Thumbnail

struct ProjectThumbnailView: View {
    enum Source: Equatable {
        case pointCloud(SavedScan)
        case gaussian(GaussianProject)

        static func == (lhs: Source, rhs: Source) -> Bool {
            switch (lhs, rhs) {
            case (.pointCloud(let a), .pointCloud(let b)):
                return a.id == b.id && a.metadata.savedAt == b.metadata.savedAt && a.metadata.pointCount == b.metadata.pointCount
            case (.gaussian(let a), .gaussian(let b)):
                return a.id == b.id && a.updatedAt == b.updatedAt && a.splatCount == b.splatCount && a.frames.count == b.frames.count
            default:
                return false
            }
        }

        var cacheKey: String {
            switch self {
            case .pointCloud(let scan):
                return "pc-\(scan.id)-\(scan.metadata.savedAt.timeIntervalSince1970)-\(scan.metadata.pointCount)"
            case .gaussian(let project):
                return "gs-\(project.id.uuidString)-\(project.updatedAt.timeIntervalSince1970)-\(project.splatCount)-\(project.frames.count)"
            }
        }

        var fallbackSystemImage: String {
            switch self {
            case .pointCloud: return "cube.transparent"
            case .gaussian: return "sparkles"
            }
        }
    }

    let source: Source
    var width: CGFloat? = 88
    var height: CGFloat = 64
    var cornerRadius: CGFloat = 10
    var refreshToken: Int = 0

    @State private var image: UIImage?
    @State private var isLoading = false

    init(scan: SavedScan, width: CGFloat? = 88, height: CGFloat = 64, cornerRadius: CGFloat = 10, refreshToken: Int = 0) {
        self.source = .pointCloud(scan)
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
        self.refreshToken = refreshToken
    }

    init(gaussian: GaussianProject, width: CGFloat? = 88, height: CGFloat = 64, cornerRadius: CGFloat = 10, refreshToken: Int = 0) {
        self.source = .gaussian(gaussian)
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
        self.refreshToken = refreshToken
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(red: 0.055, green: 0.082, blue: 0.106))

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: width ?? .infinity, maxHeight: height)
                    .clipped()
            } else if isLoading {
                ProgressView()
                    .tint(.white.opacity(0.7))
            } else {
                Image(systemName: source.fallbackSystemImage)
                    .font(height > 100 ? .title : .body)
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .frame(width: width, height: height)
        .frame(maxWidth: width == nil ? .infinity : width)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
        )
        .task(id: "\(source.cacheKey)-\(refreshToken)") {
            await loadThumbnail(forceRefresh: refreshToken > 0)
        }
    }

    private func loadThumbnail(forceRefresh: Bool) async {
        isLoading = true
        let src = source
        let loaded: UIImage? = await Task.detached(priority: .utility) {
            switch src {
            case .pointCloud(let scan):
                return ReportPreviewRenderer.pointCloudThumbnailImage(for: scan, forceRefresh: forceRefresh)
            case .gaussian(let project):
                return ReportPreviewRenderer.gaussianThumbnailImage(for: project, forceRefresh: forceRefresh)
            }
        }.value
        await MainActor.run {
            self.image = loaded
            self.isLoading = false
        }
    }
}

// MARK: - Tag & Collection Badges

struct ProjectOrganizationBadges: View {
    let collectionIDs: [UUID]?
    let tags: [String]?
    @ObservedObject private var collectionStore = ProjectCollectionStore.shared

    var body: some View {
        let collections = collectionStore.collections(for: collectionIDs)
        let projectTags = CloudAnnotation.normalizedTags(tags ?? [])
        if !collections.isEmpty || !projectTags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(collections) { collection in
                        Label(collection.title, systemImage: "folder.fill")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.indigo.opacity(0.16), in: Capsule())
                            .foregroundStyle(.indigo)
                            .lineLimit(1)
                    }
                    ForEach(projectTags, id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.secondary.opacity(0.14), in: Capsule())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}

// MARK: - Archive Filter Bar & Collection Summary Card

struct ArchiveFilterBar: View {
    @ObservedObject var collectionStore: ProjectCollectionStore
    @Binding var searchText: String
    @Binding var selectedCollectionID: UUID?
    @Binding var selectedTag: String?
    let availableTags: [String]
    let totalCount: Int
    let countForCollection: (UUID) -> Int
    let onManageCollections: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(L("Search title, description, or #tag"), text: $searchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                Button {
                    onManageCollections()
                } label: {
                    Label(L("Collections"), systemImage: "folder.badge.plus")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(.indigo.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            if !collectionStore.collections.isEmpty || selectedCollectionID != nil {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        filterChip(
                            title: L("All (%lld)", Int64(totalCount)),
                            systemImage: "square.stack",
                            isSelected: selectedCollectionID == nil
                        ) {
                            selectedCollectionID = nil
                        }
                        ForEach(collectionStore.collections) { collection in
                            let count = countForCollection(collection.id)
                            filterChip(
                                title: "\(collection.title) (\(count))",
                                systemImage: "folder.fill",
                                isSelected: selectedCollectionID == collection.id
                            ) {
                                selectedCollectionID = (selectedCollectionID == collection.id) ? nil : collection.id
                            }
                        }
                    }
                }
            }

            if !availableTags.isEmpty || selectedTag != nil {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        if selectedTag != nil {
                            Button {
                                selectedTag = nil
                            } label: {
                                Label(L("All Tags"), systemImage: "xmark.circle")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.secondary.opacity(0.16), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        ForEach(availableTags, id: \.self) { tag in
                            let active = selectedTag?.caseInsensitiveCompare(tag) == .orderedSame
                            Button {
                                selectedTag = active ? nil : tag
                            } label: {
                                Text("#\(tag)")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4)
                                    .background(active ? Color.accentColor : Color.secondary.opacity(0.12), in: Capsule())
                                    .foregroundStyle(active ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func filterChip(title: String, systemImage: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? Color.indigo : Color.secondary.opacity(0.12), in: Capsule())
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

struct CollectionHeaderCard: View {
    let collection: ProjectCollection
    let matchingPointClouds: [SavedScan]
    let matchingGaussians: [GaussianProject]
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Label(collection.title, systemImage: "folder.fill")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.indigo)
                        if !collection.summary.isEmpty {
                            Text("— \(collection.summary)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    if !collection.tags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(collection.tags, id: \.self) { tag in
                                    Text("#\(tag)")
                                        .font(.caption2.weight(.medium))
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 2)
                                        .background(.indigo.opacity(0.12), in: Capsule())
                                        .foregroundStyle(.indigo)
                                }
                            }
                        }
                    }
                }
                Spacer(minLength: 8)
                Button(action: onEdit) {
                    Image(systemName: "pencil.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.indigo)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("Edit Collection"))
            }

            if !matchingPointClouds.isEmpty || !matchingGaussians.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(matchingPointClouds.prefix(6)) { scan in
                            VStack(alignment: .leading, spacing: 2) {
                                ProjectThumbnailView(scan: scan, width: 72, height: 50, cornerRadius: 7)
                                Text(scan.metadata.title)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .frame(width: 72, alignment: .leading)
                            }
                        }
                        ForEach(matchingGaussians.prefix(6)) { project in
                            VStack(alignment: .leading, spacing: 2) {
                                ProjectThumbnailView(gaussian: project, width: 72, height: 50, cornerRadius: 7)
                                Text(project.title)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .frame(width: 72, alignment: .leading)
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(.indigo.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.indigo.opacity(0.22), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

// MARK: - Tag Picker Flow Helper

struct ProjectTagsEditorSection: View {
    @Binding var tags: [String]
    @State private var draftTag = ""
    let existingCatalogTags: [String]

    private var suggestions: [String] {
        let activeLower = Set(tags.map { $0.lowercased() })
        return ProjectTagCatalog.suggestedTags(including: existingCatalogTags)
            .filter { !activeLower.contains($0.lowercased()) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !tags.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 95), spacing: 6)], alignment: .leading, spacing: 6) {
                    ForEach(tags, id: \.self) { tag in
                        HStack(spacing: 4) {
                            Text("#\(tag)")
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                            Button {
                                tags.removeAll { $0.caseInsensitiveCompare(tag) == .orderedSame }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.accentColor.opacity(0.16), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                    }
                }
            }

            HStack(spacing: 8) {
                TextField(L("Add tag (e.g. Trench 4, Find)"), text: $draftTag)
                    .textInputAutocapitalization(.words)
                    .onSubmit { commitDraftTag() }
                Button(L("Add")) {
                    commitDraftTag()
                }
                .disabled(draftTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(suggestions, id: \.self) { tag in
                            Button {
                                tags = CloudAnnotation.normalizedTags(tags + [tag])
                            } label: {
                                Label("#\(tag)", systemImage: "plus")
                                    .font(.caption2.weight(.medium))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(.secondary.opacity(0.12), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func commitDraftTag() {
        let parts = draftTag
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return }
        tags = CloudAnnotation.normalizedTags(tags + parts)
        draftTag = ""
    }
}

// MARK: - Project Organization Editor Sheet

struct ProjectOrganizationEditorSheet: View {
    enum Target {
        case pointCloud(SavedScan)
        case gaussian(GaussianProject)
    }

    let target: Target
    let existingTags: [String]
    let onSave: (_ title: String, _ description: String?, _ tags: [String], _ collectionIDs: [UUID]) -> Void

    @ObservedObject private var collectionStore = ProjectCollectionStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var descriptionText: String
    @State private var tags: [String]
    @State private var selectedCollectionIDs: Set<UUID>
    @State private var thumbnailRefreshToken = 0
    @State private var showingNewCollection = false
    @State private var newCollectionTitle = ""
    @State private var newCollectionSummary = ""

    init(
        scan: SavedScan,
        existingTags: [String] = [],
        onSave: @escaping (_ title: String, _ description: String?, _ tags: [String], _ collectionIDs: [UUID]) -> Void
    ) {
        self.target = .pointCloud(scan)
        self.existingTags = existingTags
        self.onSave = onSave
        _title = State(initialValue: scan.metadata.title)
        _descriptionText = State(initialValue: scan.metadata.projectDescription ?? "")
        _tags = State(initialValue: scan.metadata.tags ?? [])
        _selectedCollectionIDs = State(initialValue: Set(scan.metadata.collectionIDs ?? []))
    }

    init(
        gaussian: GaussianProject,
        existingTags: [String] = [],
        onSave: @escaping (_ title: String, _ description: String?, _ tags: [String], _ collectionIDs: [UUID]) -> Void
    ) {
        self.target = .gaussian(gaussian)
        self.existingTags = existingTags
        self.onSave = onSave
        _title = State(initialValue: gaussian.title)
        _descriptionText = State(initialValue: gaussian.projectDescription ?? "")
        _tags = State(initialValue: gaussian.tags ?? [])
        _selectedCollectionIDs = State(initialValue: Set(gaussian.collectionIDs ?? []))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L("Project Preview")) {
                    VStack(alignment: .trailing, spacing: 8) {
                        switch target {
                        case .pointCloud(let scan):
                            ProjectThumbnailView(
                                scan: scan,
                                width: nil,
                                height: 190,
                                cornerRadius: 12,
                                refreshToken: thumbnailRefreshToken
                            )
                        case .gaussian(let project):
                            ProjectThumbnailView(
                                gaussian: project,
                                width: nil,
                                height: 190,
                                cornerRadius: 12,
                                refreshToken: thumbnailRefreshToken
                            )
                        }
                        Button {
                            thumbnailRefreshToken += 1
                        } label: {
                            Label(L("Refresh Preview"), systemImage: "arrow.clockwise")
                                .font(.caption.weight(.medium))
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
                }

                Section(L("Title & Short Description")) {
                    TextField(L("Project Title"), text: $title)
                        .textInputAutocapitalization(.sentences)
                    TextField(L("Short description, e.g. North profile wall"), text: $descriptionText, axis: .vertical)
                        .lineLimit(2...4)
                        .textInputAutocapitalization(.sentences)
                }

                Section(L("Project Tags")) {
                    ProjectTagsEditorSection(tags: $tags, existingCatalogTags: existingTags)
                }

                Section(L("Collections")) {
                    if collectionStore.collections.isEmpty {
                        Text(L("No collections yet. Create a collection below to group related scans."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(collectionStore.collections) { collection in
                            let isAssigned = selectedCollectionIDs.contains(collection.id)
                            Button {
                                if isAssigned {
                                    selectedCollectionIDs.remove(collection.id)
                                } else {
                                    selectedCollectionIDs.insert(collection.id)
                                }
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: isAssigned ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(isAssigned ? Color.indigo : .secondary)
                                        .font(.title3)
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                                            Text(collection.title)
                                                .font(.body.weight(.medium))
                                                .foregroundStyle(.primary)
                                            if !collection.summary.isEmpty {
                                                Text("— \(collection.summary)")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                            }
                                        }
                                        if !collection.tags.isEmpty {
                                            Text(collection.tags.map { "#\($0)" }.joined(separator: " "))
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                        }
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
                                    selectedCollectionIDs.insert(created.id)
                                    newCollectionTitle = ""
                                    newCollectionSummary = ""
                                    showingNewCollection = false
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(newCollectionTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                        .padding(.vertical, 4)
                    } else {
                        Button {
                            showingNewCollection = true
                        } label: {
                            Label(L("New Collection…"), systemImage: "folder.badge.plus")
                        }
                    }
                }
            }
            .navigationTitle(L("Project Details"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Save")) {
                        let orderedIDs = collectionStore.collections
                            .map(\.id)
                            .filter { selectedCollectionIDs.contains($0) }
                        onSave(
                            title,
                            ProjectTagCatalog.trimmedOrNil(descriptionText),
                            CloudAnnotation.normalizedTags(tags),
                            orderedIDs
                        )
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Collections Manager & Editor Sheets

struct CollectionsManagerSheet: View {
    @ObservedObject private var collectionStore = ProjectCollectionStore.shared
    let pointClouds: [SavedScan]
    let gaussians: [GaussianProject]
    @Environment(\.dismiss) private var dismiss

    @State private var loadedPointClouds: [SavedScan] = []
    @State private var loadedGaussians: [GaussianProject] = []
    @State private var editingCollection: ProjectCollection?
    @State private var creatingNew = false
    @State private var toDelete: ProjectCollection?

    init(pointClouds: [SavedScan] = [], gaussians: [GaussianProject] = []) {
        self.pointClouds = pointClouds
        self.gaussians = gaussians
    }

    private var effectivePointClouds: [SavedScan] {
        pointClouds.isEmpty ? loadedPointClouds : pointClouds
    }

    private var effectiveGaussians: [GaussianProject] {
        gaussians.isEmpty ? loadedGaussians : gaussians
    }

    var body: some View {
        NavigationStack {
            List {
                if collectionStore.collections.isEmpty {
                    ContentUnavailableView(
                        L("No Collections Yet"),
                        systemImage: "folder",
                        description: Text(L("Group related point clouds and Gaussian scenes into collections with a short description and preview thumbnails."))
                    )
                } else {
                    ForEach(collectionStore.collections) { collection in
                        let pcs = effectivePointClouds.filter { $0.metadata.collectionIDs?.contains(collection.id) == true }
                        let gs = effectiveGaussians.filter { $0.collectionIDs?.contains(collection.id) == true }
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Text(collection.title)
                                            .font(.headline)
                                        if !collection.summary.isEmpty {
                                            Text("— \(collection.summary)")
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                        }
                                    }
                                    Text(L("%lld projects", Int64(pcs.count + gs.count)))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if !collection.tags.isEmpty {
                                        HStack(spacing: 6) {
                                            ForEach(collection.tags, id: \.self) { tag in
                                                Text("#\(tag)")
                                                    .font(.caption2.weight(.medium))
                                                    .padding(.horizontal, 7)
                                                    .padding(.vertical, 2)
                                                    .background(.indigo.opacity(0.14), in: Capsule())
                                                    .foregroundStyle(.indigo)
                                            }
                                        }
                                    }
                                }
                                Spacer()
                                Button {
                                    editingCollection = collection
                                } label: {
                                    Image(systemName: "pencil")
                                        .frame(width: 36, height: 36)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel(L("Edit Collection"))
                            }

                            if !pcs.isEmpty || !gs.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(pcs.prefix(5)) { scan in
                                            ProjectThumbnailView(scan: scan, width: 72, height: 50, cornerRadius: 8)
                                        }
                                        ForEach(gs.prefix(5)) { project in
                                            ProjectThumbnailView(gaussian: project, width: 72, height: 50, cornerRadius: 8)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            editingCollection = collection
                        }
                        .swipeActions {
                            Button(L("Delete"), role: .destructive) {
                                toDelete = collection
                            }
                        }
                    }
                }
            }
            .navigationTitle(L("Collections"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        creatingNew = true
                    } label: {
                        Label(L("New Collection"), systemImage: "plus")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Done")) { dismiss() }
                }
            }
            .task {
                await loadMissingProjects()
            }
            .sheet(item: $editingCollection) { collection in
                CollectionEditorSheet(
                    collection: collection,
                    existingTags: collectionStore.allUsedTags(pointClouds: effectivePointClouds, gaussians: effectiveGaussians)
                ) { updated in
                    collectionStore.save(updated)
                }
            }
            .sheet(isPresented: $creatingNew) {
                CollectionEditorSheet(
                    collection: nil,
                    existingTags: collectionStore.allUsedTags(pointClouds: effectivePointClouds, gaussians: effectiveGaussians)
                ) { created in
                    collectionStore.save(created)
                }
            }
            .alert(
                L("Delete Collection?"),
                isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } })
            ) {
                Button(L("Cancel"), role: .cancel) { toDelete = nil }
                Button(L("Delete"), role: .destructive) {
                    if let toDelete {
                        collectionStore.delete(toDelete)
                    }
                    toDelete = nil
                }
            } message: {
                Text(L("Scans inside this collection are kept on your device; only the collection group is removed."))
            }
        }
    }

    private func loadMissingProjects() async {
        let needPC = pointClouds.isEmpty
        let needGS = gaussians.isEmpty
        guard needPC || needGS else { return }
        let (pcs, gs) = await Task.detached(priority: .utility) {
            let loadedPC = needPC ? ((try? ScanStorage.list()) ?? []) : []
            let loadedGS = needGS ? ((try? GaussianStore.list()) ?? []) : []
            return (loadedPC, loadedGS)
        }.value
        await MainActor.run {
            if needPC { self.loadedPointClouds = pcs }
            if needGS { self.loadedGaussians = gs }
        }
    }
}

struct CollectionEditorSheet: View {
    let collection: ProjectCollection?
    let existingTags: [String]
    let onSave: (ProjectCollection) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var summary: String
    @State private var tags: [String]

    init(collection: ProjectCollection?, existingTags: [String] = [], onSave: @escaping (ProjectCollection) -> Void) {
        self.collection = collection
        self.existingTags = existingTags
        self.onSave = onSave
        _title = State(initialValue: collection?.title ?? "")
        _summary = State(initialValue: collection?.summary ?? "")
        _tags = State(initialValue: collection?.tags ?? [])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L("Collection")) {
                    TextField(L("Collection Title"), text: $title)
                        .textInputAutocapitalization(.sentences)
                    TextField(L("Short description alongside title"), text: $summary, axis: .vertical)
                        .lineLimit(2...4)
                        .textInputAutocapitalization(.sentences)
                }
                Section(L("Tags")) {
                    ProjectTagsEditorSection(tags: $tags, existingCatalogTags: existingTags)
                }
            }
            .navigationTitle(collection == nil ? L("New Collection") : L("Edit Collection"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Save")) {
                        let base = collection ?? ProjectCollection(title: title)
                        let updated = ProjectCollection(
                            id: base.id,
                            title: title,
                            summary: summary,
                            tags: tags,
                            createdAt: base.createdAt,
                            updatedAt: Date()
                        )
                        onSave(updated)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
