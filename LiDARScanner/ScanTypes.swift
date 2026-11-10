import Foundation
import UIKit

struct ScanSettings: Codable, Equatable {
    var voxelCentimeters: Double = 1
    var maxDepth: Double = 5
    var minConfidence: Int = 1
    var pixelStep: Int = 2
    // Zero selects automatic memory monitoring instead of a fixed point count.
    var maxPoints: Int = 0
    var recordLocation: Bool = true

    var core: PCConfig {
        PCConfig(voxelMeters: Float(voxelCentimeters / 100), minDepth: 0.2,
                 maxDepth: Float(maxDepth), maxPoints: UInt32(maxPoints),
                 pixelStep: Int32(pixelStep), minConfidence: UInt8(minConfidence))
    }

    enum CodingKeys: String, CodingKey {
        case voxelCentimeters, maxDepth, minConfidence, pixelStep, maxPoints, recordLocation
    }

    init(voxelCentimeters: Double = 1, maxDepth: Double = 5, minConfidence: Int = 1, pixelStep: Int = 2, maxPoints: Int = 0, recordLocation: Bool = true) {
        self.voxelCentimeters = voxelCentimeters
        self.maxDepth = maxDepth
        self.minConfidence = minConfidence
        self.pixelStep = pixelStep
        self.maxPoints = maxPoints
        self.recordLocation = recordLocation
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        voxelCentimeters = try container.decodeIfPresent(Double.self, forKey: .voxelCentimeters) ?? 1
        maxDepth = try container.decodeIfPresent(Double.self, forKey: .maxDepth) ?? 5
        minConfidence = try container.decodeIfPresent(Int.self, forKey: .minConfidence) ?? 1
        pixelStep = try container.decodeIfPresent(Int.self, forKey: .pixelStep) ?? 2
        maxPoints = try container.decodeIfPresent(Int.self, forKey: .maxPoints) ?? 0
        recordLocation = try container.decodeIfPresent(Bool.self, forKey: .recordLocation) ?? true
    }
}

enum ExportFormat: Int32, CaseIterable, Identifiable {
    case binaryPLY = 0, asciiPLY = 1, xyz = 2
    var id: Int32 { rawValue }
    var title: String {
        switch self {
        case .binaryPLY: return String(localized: "PLY · Binary, Color")
        case .asciiPLY: return String(localized: "PLY · Text, Color")
        case .xyz: return String(localized: "XYZ · Coordinates Only")
        }
    }
    var fileName: String {
        switch self {
        case .binaryPLY: return "points.ply"
        case .asciiPLY: return "points-ascii.ply"
        case .xyz: return "points.xyz"
        }
    }
}

struct ScanMetadata: Codable {
    let schemaVersion: Int
    let appVersion: String
    let appBuild: String?
    let scanID: UUID
    let title: String
    let startedAt: Date
    let savedAt: Date
    let pointCount: Int
    let acceptedSamples: UInt64
    let processedFrames: Int
    let activeSeconds: Double
    let settings: ScanSettings
    let deviceModel: String
    let systemVersion: String
    let depthWidth: Int
    let depthHeight: Int
    let unit: String
    let coordinateSystem: String
    let arkitToExportRowMajor: [Int]
    let depthSource: String
    let confidenceMeaning: String
    let pointSelection: String
    let colorSource: String
    let sessionNote: String
    let location: GeoLocation?

    init(schemaVersion: Int, appVersion: String, appBuild: String?, scanID: UUID, title: String,
         startedAt: Date, savedAt: Date, pointCount: Int, acceptedSamples: UInt64,
         processedFrames: Int, activeSeconds: Double, settings: ScanSettings, deviceModel: String,
         systemVersion: String, depthWidth: Int, depthHeight: Int, unit: String,
         coordinateSystem: String, arkitToExportRowMajor: [Int], depthSource: String,
         confidenceMeaning: String, pointSelection: String, colorSource: String,
         sessionNote: String, location: GeoLocation? = nil) {
        self.schemaVersion = schemaVersion
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.scanID = scanID
        self.title = title
        self.startedAt = startedAt
        self.savedAt = savedAt
        self.pointCount = pointCount
        self.acceptedSamples = acceptedSamples
        self.processedFrames = processedFrames
        self.activeSeconds = activeSeconds
        self.settings = settings
        self.deviceModel = deviceModel
        self.systemVersion = systemVersion
        self.depthWidth = depthWidth
        self.depthHeight = depthHeight
        self.unit = unit
        self.coordinateSystem = coordinateSystem
        self.arkitToExportRowMajor = arkitToExportRowMajor
        self.depthSource = depthSource
        self.confidenceMeaning = confidenceMeaning
        self.pointSelection = pointSelection
        self.colorSource = colorSource
        self.sessionNote = sessionNote
        self.location = location
    }
}

struct SavedScan: Identifiable {
    let directory: URL
    let metadata: ScanMetadata
    var id: String { directory.lastPathComponent }
    var metadataURL: URL { directory.appendingPathComponent("metadata.json") }
    func url(for format: ExportFormat) -> URL { directory.appendingPathComponent(format.fileName) }
    var existingFormats: [ExportFormat] {
        ExportFormat.allCases.filter { FileManager.default.fileExists(atPath: url(for: $0).path) }
    }
}

struct SharedFiles: Identifiable {
    let id = UUID()
    let urls: [URL]
}

enum ScanFailure: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self {
        case .message(let text):
            // Preserve raw acquisition/export errors; translate when displayed.
            return NSLocalizedString(text, comment: "Scan or export error")
        }
    }
}

enum ScanStorage {
    static func root() throws -> URL {
        let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                    appropriateFor: nil, create: true)
        let result = documents.appendingPathComponent("Scans", isDirectory: true)
        try FileManager.default.createDirectory(at: result, withIntermediateDirectories: true)
        return result
    }

    static func list() throws -> [SavedScan] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try FileManager.default.contentsOfDirectory(at: root(), includingPropertiesForKeys: nil,
                                                           options: [.skipsHiddenFiles]).compactMap { url in
            guard let data = try? Data(contentsOf: url.appendingPathComponent("metadata.json")),
                  let metadata = try? decoder.decode(ScanMetadata.self, from: data),
                  FileManager.default.fileExists(atPath: url.appendingPathComponent("points.ply").path)
            else { return nil }
            return SavedScan(directory: url, metadata: metadata)
        }.sorted { $0.metadata.savedAt > $1.metadata.savedAt }
    }

    static func writeCloud(_ cloud: OpaquePointer, to url: URL, format: ExportFormat) throws {
        var error = [CChar](repeating: 0, count: 512)
        let ok = url.path.withCString { path in
            error.withUnsafeMutableBufferPointer { buffer in
                pc_export(cloud, path, format.rawValue, buffer.baseAddress, buffer.count)
            }
        }
        if ok == 0 { throw ScanFailure.message(String(cString: error)) }
    }

    static func save(_ cloud: OpaquePointer, metadata: ScanMetadata, format: ExportFormat) throws -> SavedScan {
        let base = try root()
        let id = UUID().uuidString
        let staging = base.appendingPathComponent(".pending-" + id, isDirectory: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let final = base.appendingPathComponent(formatter.string(from: metadata.savedAt) + "_" + String(id.prefix(8)),
                                                isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            try writeCloud(cloud, to: staging.appendingPathComponent(ExportFormat.binaryPLY.fileName), format: .binaryPLY)
            if format != .binaryPLY {
                try writeCloud(cloud, to: staging.appendingPathComponent(format.fileName), format: format)
            }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(metadata).write(to: staging.appendingPathComponent("metadata.json"), options: .atomic)
            try FileManager.default.moveItem(at: staging, to: final)
            return SavedScan(directory: final, metadata: metadata)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }
}
