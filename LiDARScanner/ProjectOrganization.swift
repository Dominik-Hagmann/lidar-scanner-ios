import Foundation
import Combine

struct ProjectCollection: Codable, Equatable, Identifiable {
    var id: UUID
    var title: String
    var summary: String
    var tags: [String]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        summary: String = "",
        tags: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        self.tags = CloudAnnotation.normalizedTags(tags)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, title, summary, tags, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decode(String.self, forKey: .title)
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        tags = CloudAnnotation.normalizedTags(try c.decodeIfPresent([String].self, forKey: .tags) ?? [])
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }
}

enum ProjectTagCatalog {
    static let suggestedTagKeys: [String] = [
        "Excavation", "Trench", "Feature", "Find", "Architecture", "Profile", "Survey", "Archive"
    ]

    static func suggestedTags(including existing: [String] = []) -> [String] {
        var combined = existing
        for key in suggestedTagKeys {
            combined.append(LanguageManager.string(key))
        }
        return CloudAnnotation.normalizedTags(combined)
    }

    static func normalizedOrNil(_ raw: [String]) -> [String]? {
        let clean = CloudAnnotation.normalizedTags(raw)
        return clean.isEmpty ? nil : clean
    }

    static func trimmedOrNil(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

final class ProjectCollectionStore: ObservableObject {
    static let shared = ProjectCollectionStore()

    @Published private(set) var collections: [ProjectCollection] = []

    private let fileURL: URL
    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    init(storageURL: URL? = nil) {
        self.fileURL = storageURL ?? Self.defaultFileURL()
        reload()
    }

    static func defaultFileURL() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return docs
            .appendingPathComponent("Collections", isDirectory: true)
            .appendingPathComponent("collections.json")
    }

    func reload() {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let decoded = try? Self.decoder.decode([ProjectCollection].self, from: data) else {
            collections = []
            return
        }
        collections = decoded.sorted { $0.updatedAt > $1.updatedAt }
    }

    @discardableResult
    func save(_ collection: ProjectCollection) -> ProjectCollection {
        var normalized = collection
        let trimmedTitle = normalized.title.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.title = trimmedTitle.isEmpty ? LanguageManager.string("Untitled Collection") : trimmedTitle
        normalized.summary = normalized.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.tags = CloudAnnotation.normalizedTags(normalized.tags)
        normalized.updatedAt = Date()

        var list = collections
        if let idx = list.firstIndex(where: { $0.id == normalized.id }) {
            normalized.createdAt = list[idx].createdAt
            list[idx] = normalized
        } else {
            list.insert(normalized, at: 0)
        }
        list.sort { $0.updatedAt > $1.updatedAt }
        collections = list
        persist()
        return normalized
    }

    func delete(_ collection: ProjectCollection) {
        collections.removeAll { $0.id == collection.id }
        persist()
    }

    func collection(for id: UUID) -> ProjectCollection? {
        collections.first { $0.id == id }
    }

    func collections(for ids: [UUID]?) -> [ProjectCollection] {
        guard let ids, !ids.isEmpty else { return [] }
        let idSet = Set(ids)
        return collections.filter { idSet.contains($0.id) }
    }

    func allUsedTags(pointClouds: [SavedScan] = [], gaussians: [GaussianProject] = []) -> [String] {
        var collected: [String] = []
        for c in collections { collected.append(contentsOf: c.tags) }
        for s in pointClouds { collected.append(contentsOf: s.metadata.tags ?? []) }
        for g in gaussians { collected.append(contentsOf: g.tags ?? []) }
        return CloudAnnotation.normalizedTags(collected)
    }

    private func persist() {
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? Self.encoder.encode(collections) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
