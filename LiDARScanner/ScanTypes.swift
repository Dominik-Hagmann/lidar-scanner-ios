import Foundation
import UIKit
import ARKit

struct ScanSettings: Codable, Equatable {
    var voxelCentimeters: Double = 1
    var maxDepth: Double = 5
    var minConfidence: Int = 1
    var pixelStep: Int = 2
    // Zero selects automatic memory monitoring instead of a fixed point count.
    var maxPoints: Int = 0
    var recordLocation: Bool = true

    init(voxelCentimeters: Double = 1, maxDepth: Double = 5, minConfidence: Int = 1,
         pixelStep: Int = 2, maxPoints: Int = 0, recordLocation: Bool = true) {
        self.voxelCentimeters = voxelCentimeters
        self.maxDepth = maxDepth
        self.minConfidence = minConfidence
        self.pixelStep = pixelStep
        self.maxPoints = maxPoints
        self.recordLocation = recordLocation
    }

    enum CodingKeys: String, CodingKey {
        case voxelCentimeters, maxDepth, minConfidence, pixelStep, maxPoints, recordLocation
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        voxelCentimeters = try c.decodeIfPresent(Double.self, forKey: .voxelCentimeters) ?? 1
        maxDepth = try c.decodeIfPresent(Double.self, forKey: .maxDepth) ?? 5
        minConfidence = try c.decodeIfPresent(Int.self, forKey: .minConfidence) ?? 1
        pixelStep = try c.decodeIfPresent(Int.self, forKey: .pixelStep) ?? 2
        maxPoints = try c.decodeIfPresent(Int.self, forKey: .maxPoints) ?? 0
        recordLocation = try c.decodeIfPresent(Bool.self, forKey: .recordLocation) ?? true
    }

    var core: PCConfig {
        PCConfig(voxelMeters: Float(voxelCentimeters / 100), minDepth: 0.2,
                 maxDepth: Float(maxDepth), maxPoints: UInt32(maxPoints),
                 pixelStep: Int32(pixelStep), minConfidence: UInt8(minConfidence))
    }
}

enum ExportFormat: Int32, CaseIterable, Identifiable {
    case binaryPLY = 0, asciiPLY = 1, xyz = 2, csv = 5, las = 3, laz = 4, e57 = 6
    var id: Int32 { rawValue }
    var title: String {
        switch self {
        case .binaryPLY: return LanguageManager.string("PLY · Binary, Color")
        case .asciiPLY: return LanguageManager.string("PLY · Text, Color")
        case .xyz: return LanguageManager.string("XYZ · Coordinates Only")
        case .csv: return LanguageManager.string("CSV · Table, Color & Confidence")
        case .las: return LanguageManager.string("LAS · ASPRS Point Cloud")
        case .laz: return LanguageManager.string("LAZ · Compressed ASPRS")
        case .e57: return LanguageManager.string("E57 · ASTM Standard")
        }
    }
    var fileName: String {
        switch self {
        case .binaryPLY: return "points.ply"
        case .asciiPLY: return "points-ascii.ply"
        case .xyz: return "points.xyz"
        case .csv: return "points.csv"
        case .las: return "points.las"
        case .laz: return "points.laz"
        case .e57: return "points.e57"
        }
    }
}

struct GroundControlPoint: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var label: String
    // Local scan coordinates in export frame (meters, Z-up: (x, -z, y) from ARKit).
    var localX: Double
    var localY: Double
    var localZ: Double
    var targetX: Double?
    var targetY: Double?
    var targetZ: Double?
    var coordinateSystem: String = ""
    var note: String = ""
    var createdAt: Date = Date()

    var arkitPosition: SIMD3<Float> {
        SIMD3<Float>(Float(localX), Float(localZ), Float(-localY))
    }

    init(id: UUID = UUID(), label: String, localX: Double, localY: Double, localZ: Double,
         targetX: Double? = nil, targetY: Double? = nil, targetZ: Double? = nil,
         coordinateSystem: String = "", note: String = "", createdAt: Date = Date()) {
        self.id = id
        self.label = label
        self.localX = localX
        self.localY = localY
        self.localZ = localZ
        self.targetX = targetX
        self.targetY = targetY
        self.targetZ = targetZ
        self.coordinateSystem = coordinateSystem
        self.note = note
        self.createdAt = createdAt
    }

    static func fromARKit(_ point: SIMD3<Float>, label: String,
                          targetX: Double? = nil, targetY: Double? = nil, targetZ: Double? = nil,
                          coordinateSystem: String = "", note: String = "") -> GroundControlPoint {
        GroundControlPoint(
            label: label,
            localX: Double(point.x),
            localY: Double(-point.z),
            localZ: Double(point.y),
            targetX: targetX,
            targetY: targetY,
            targetZ: targetZ,
            coordinateSystem: coordinateSystem,
            note: note
        )
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
    var location: GeoLocation? = nil
    var groundControlPoints: [GroundControlPoint]? = nil

    init(schemaVersion: Int, appVersion: String, appBuild: String?, scanID: UUID, title: String,
         startedAt: Date, savedAt: Date, pointCount: Int, acceptedSamples: UInt64,
         processedFrames: Int, activeSeconds: Double, settings: ScanSettings,
         deviceModel: String, systemVersion: String, depthWidth: Int, depthHeight: Int,
         unit: String, coordinateSystem: String, arkitToExportRowMajor: [Int],
         depthSource: String, confidenceMeaning: String, pointSelection: String,
         colorSource: String, sessionNote: String,
         location: GeoLocation? = nil, groundControlPoints: [GroundControlPoint]? = nil) {
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
        self.groundControlPoints = groundControlPoints
    }
}

struct SavedScan: Identifiable {
    let directory: URL
    let metadata: ScanMetadata
    var id: String { directory.lastPathComponent }
    var metadataURL: URL { directory.appendingPathComponent("metadata.json") }
    var meshURL: URL { directory.appendingPathComponent("mesh.obj") }
    var hasMesh: Bool { FileManager.default.fileExists(atPath: meshURL.path) }
    var gcpCSVURL: URL { directory.appendingPathComponent("gcps.csv") }
    var hasGCPs: Bool { !(metadata.groundControlPoints?.isEmpty ?? true) || FileManager.default.fileExists(atPath: gcpCSVURL.path) }
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
            return LanguageManager.string(text)
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
                  let metadata = try? decoder.decode(ScanMetadata.self, from: data)
            else { return nil }
            let scan = SavedScan(directory: url, metadata: metadata)
            guard !scan.existingFormats.isEmpty else { return nil }
            return scan
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

    static func save(_ cloud: OpaquePointer, metadata: ScanMetadata, format: ExportFormat, meshAnchors: [ARMeshAnchor] = []) throws -> SavedScan {
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
            if !meshAnchors.isEmpty {
                try MeshExporter.writeOBJ(anchors: meshAnchors, to: staging.appendingPathComponent("mesh.obj"))
            }
            if let gcps = metadata.groundControlPoints, !gcps.isEmpty {
                try gcpCSVData(for: gcps).write(to: staging.appendingPathComponent("gcps.csv"), options: .atomic)
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

    static func gcpCSVData(for points: [GroundControlPoint]) -> Data {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var lines = ["label,local_x_m,local_y_m,local_z_m,target_x,target_y,target_z,crs,note,created_at"]
        for p in points {
            let fields = [
                csvEscape(p.label),
                String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), p.localX),
                String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), p.localY),
                String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), p.localZ),
                p.targetX.map { String(format: "%.8f", locale: Locale(identifier: "en_US_POSIX"), $0) } ?? "",
                p.targetY.map { String(format: "%.8f", locale: Locale(identifier: "en_US_POSIX"), $0) } ?? "",
                p.targetZ.map { String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), $0) } ?? "",
                csvEscape(p.coordinateSystem),
                csvEscape(p.note),
                csvEscape(iso.string(from: p.createdAt))
            ]
            lines.append(fields.joined(separator: ","))
        }
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }

    private static func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    static func updateGroundControlPoints(for scan: SavedScan, points: [GroundControlPoint]) throws -> SavedScan {
        var meta = scan.metadata
        meta.groundControlPoints = points.isEmpty ? nil : points
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(meta).write(to: scan.metadataURL, options: .atomic)
        if points.isEmpty {
            try? FileManager.default.removeItem(at: scan.gcpCSVURL)
        } else {
            try gcpCSVData(for: points).write(to: scan.gcpCSVURL, options: .atomic)
        }
        return SavedScan(directory: scan.directory, metadata: meta)
    }

    static func saveImported(sourceURL: URL, metadata: ScanMetadata, format: ExportFormat = .binaryPLY) throws -> SavedScan {
        let base = try root()
        let id = UUID().uuidString
        let staging = base.appendingPathComponent(".pending-" + id, isDirectory: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let cleanTitle = metadata.title.replacingOccurrences(of: "/", with: "-")
        let final = base.appendingPathComponent(formatter.string(from: metadata.savedAt) + "_" + String(id.prefix(8)) + "_" + cleanTitle,
                                                isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            let targetFile = staging.appendingPathComponent(format.fileName)
            try FileManager.default.copyItem(at: sourceURL, to: targetFile)

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

    static func readPreview(for scan: SavedScan, maxPoints: Int = 40_000) -> [PCPoint] {
        readPoints(for: scan, maxPoints: maxPoints)
    }

    static func readAllPoints(for scan: SavedScan) -> [PCPoint] {
        readPoints(for: scan, maxPoints: nil)
    }

    private static func readPoints(for scan: SavedScan, maxPoints: Int?) -> [PCPoint] {
        for format in [ExportFormat.binaryPLY, .asciiPLY, .xyz, .csv] {
            let fileURL = scan.url(for: format)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                return ScanImporter.readPoints(from: fileURL, formatHint: format, maxPoints: maxPoints)
            }
        }
        return []
    }
}
