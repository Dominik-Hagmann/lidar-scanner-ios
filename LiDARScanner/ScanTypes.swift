import Foundation
import UIKit
import ARKit
import CoreImage
import ImageIO

struct ScanSettings: Codable, Equatable {
    var voxelCentimeters: Double = 1
    var maxDepth: Double = 5
    var minConfidence: Int = 1
    var pixelStep: Int = 2
    // Zero selects automatic memory monitoring instead of a fixed point count.
    var maxPoints: Int = 0
    var recordLocation: Bool = true
    var saveImages: Bool = true

    init(voxelCentimeters: Double = 1, maxDepth: Double = 5, minConfidence: Int = 1,
         pixelStep: Int = 2, maxPoints: Int = 0, recordLocation: Bool = true, saveImages: Bool = true) {
        self.voxelCentimeters = voxelCentimeters
        self.maxDepth = maxDepth
        self.minConfidence = minConfidence
        self.pixelStep = pixelStep
        self.maxPoints = maxPoints
        self.recordLocation = recordLocation
        self.saveImages = saveImages
    }

    enum CodingKeys: String, CodingKey {
        case voxelCentimeters, maxDepth, minConfidence, pixelStep, maxPoints, recordLocation, saveImages
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        voxelCentimeters = try c.decodeIfPresent(Double.self, forKey: .voxelCentimeters) ?? 1
        maxDepth = try c.decodeIfPresent(Double.self, forKey: .maxDepth) ?? 5
        minConfidence = try c.decodeIfPresent(Int.self, forKey: .minConfidence) ?? 1
        pixelStep = try c.decodeIfPresent(Int.self, forKey: .pixelStep) ?? 2
        maxPoints = try c.decodeIfPresent(Int.self, forKey: .maxPoints) ?? 0
        recordLocation = try c.decodeIfPresent(Bool.self, forKey: .recordLocation) ?? true
        saveImages = try c.decodeIfPresent(Bool.self, forKey: .saveImages) ?? true
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

    var resolvedCRS: CRSEntry? {
        coordinateSystem.isEmpty ? nil : CRSCatalog.lookup(coordinateSystem)
    }

    var hasTargetCoordinates: Bool {
        targetX != nil && targetY != nil
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
        self.coordinateSystem = CRSCatalog.normalizeCode(coordinateSystem)
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

enum CloudAnnotationGeometryType: String, Codable, CaseIterable, Identifiable {
    case point
    case polygon

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case "point": self = .point
        case "polygon", "rectangle": self = .polygon
        default: self = .polygon
        }
    }

    var title: String {
        switch self {
        case .point: return LanguageManager.string("Point")
        case .polygon: return LanguageManager.string("Polygon")
        }
    }

    var systemImage: String {
        switch self {
        case .point: return "mappin.circle.fill"
        case .polygon: return "pentagon"
        }
    }
}

enum AnnotationColor: String, Codable, CaseIterable, Identifiable {
    case cyan, amber, magenta, lime, gold

    var id: String { rawValue }

    var hex: String {
        switch self {
        case .cyan: return "#38BDF8"
        case .amber: return "#F97316"
        case .magenta: return "#EC4899"
        case .lime: return "#4ADE80"
        case .gold: return "#FACC15"
        }
    }

    var uiColor: UIColor {
        switch self {
        case .cyan: return UIColor(red: 0.22, green: 0.74, blue: 0.97, alpha: 1)
        case .amber: return UIColor(red: 0.98, green: 0.45, blue: 0.09, alpha: 1)
        case .magenta: return UIColor(red: 0.93, green: 0.28, blue: 0.60, alpha: 1)
        case .lime: return UIColor(red: 0.29, green: 0.87, blue: 0.50, alpha: 1)
        case .gold: return UIColor(red: 0.98, green: 0.80, blue: 0.08, alpha: 1)
        }
    }
}

struct AnnotationPoint3D: Codable, Equatable {
    // Local scan coordinates in export frame (meters, Z-up: (x, -z, y) from ARKit).
    var x: Double
    var y: Double
    var z: Double

    var arkitPosition: SIMD3<Float> {
        SIMD3<Float>(Float(x), Float(z), Float(-y))
    }

    static func fromARKit(_ point: SIMD3<Float>) -> AnnotationPoint3D {
        AnnotationPoint3D(x: Double(point.x), y: Double(-point.z), z: Double(point.y))
    }
}

struct CloudAnnotation: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var title: String
    var type: CloudAnnotationGeometryType
    var vertices: [AnnotationPoint3D]
    var tags: [String] = []
    var color: AnnotationColor = .cyan
    var note: String = ""
    var createdAt: Date = Date()

    static let suggestedTagKeys: [String] = [
        "Feature", "Find", "Wall", "Pit", "Section", "Sample", "Damage", "Measure"
    ]

    var centroid: AnnotationPoint3D {
        guard !vertices.isEmpty else { return AnnotationPoint3D(x: 0, y: 0, z: 0) }
        let count = Double(vertices.count)
        let sx = vertices.reduce(0.0) { $0 + $1.x }
        let sy = vertices.reduce(0.0) { $0 + $1.y }
        let sz = vertices.reduce(0.0) { $0 + $1.z }
        return AnnotationPoint3D(x: sx / count, y: sy / count, z: sz / count)
    }

    var perimeterMeters: Double {
        AnnotationGeometryHelper.perimeter(vertices)
    }

    var areaSquareMeters: Double {
        AnnotationGeometryHelper.area(vertices)
    }

    init(id: UUID = UUID(), title: String, type: CloudAnnotationGeometryType,
         vertices: [AnnotationPoint3D], tags: [String] = [],
         color: AnnotationColor = .cyan, note: String = "", createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.type = type
        self.vertices = vertices
        self.tags = Self.normalizedTags(tags)
        self.color = color
        self.note = note
        self.createdAt = createdAt
    }

    static func normalizedTags(_ raw: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        let trimSet = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "#"))
        for entry in raw {
            let trimmed = entry.trimmingCharacters(in: trimSet)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            if seen.insert(key).inserted {
                result.append(trimmed)
            }
        }
        return result
    }
}

struct ScanMetadata: Codable {
    let schemaVersion: Int
    let appVersion: String
    let appBuild: String?
    let scanID: UUID
    var title: String
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
    var georeferencing: ScanGeoreferencing? = nil
    var annotations: [CloudAnnotation]? = nil
    var savedImageCount: Int? = nil
    var projectDescription: String? = nil
    var tags: [String]? = nil
    var collectionIDs: [UUID]? = nil

    init(schemaVersion: Int, appVersion: String, appBuild: String?, scanID: UUID, title: String,
         startedAt: Date, savedAt: Date, pointCount: Int, acceptedSamples: UInt64,
         processedFrames: Int, activeSeconds: Double, settings: ScanSettings,
         deviceModel: String, systemVersion: String, depthWidth: Int, depthHeight: Int,
         unit: String, coordinateSystem: String, arkitToExportRowMajor: [Int],
         depthSource: String, confidenceMeaning: String, pointSelection: String,
         colorSource: String, sessionNote: String,
         location: GeoLocation? = nil, groundControlPoints: [GroundControlPoint]? = nil,
         annotations: [CloudAnnotation]? = nil,
         georeferencing: ScanGeoreferencing? = nil,
         savedImageCount: Int? = nil,
         projectDescription: String? = nil,
         tags: [String]? = nil,
         collectionIDs: [UUID]? = nil) {
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
        self.annotations = annotations
        self.georeferencing = georeferencing ?? GCPRegistration.computeGeoreferencing(for: groundControlPoints ?? [])
        self.savedImageCount = savedImageCount
        self.projectDescription = ProjectTagCatalog.trimmedOrNil(projectDescription)
        self.tags = ProjectTagCatalog.normalizedOrNil(tags ?? [])
        self.collectionIDs = (collectionIDs?.isEmpty == false) ? collectionIDs : nil
    }
}

struct SavedScan: Identifiable {
    let directory: URL
    let metadata: ScanMetadata
    var id: String { directory.lastPathComponent }
    var metadataURL: URL { directory.appendingPathComponent("metadata.json") }
    var previewImageURL: URL { directory.appendingPathComponent("preview.png") }
    var hasPreviewImage: Bool { FileManager.default.fileExists(atPath: previewImageURL.path) }
    var meshURL: URL { directory.appendingPathComponent("mesh.obj") }
    func meshURL(for format: MeshExportFormat) -> URL { directory.appendingPathComponent(format.fileName) }
    var hasMesh: Bool { FileManager.default.fileExists(atPath: meshURL.path) }
    var imagesDirectory: URL { directory.appendingPathComponent("images", isDirectory: true) }
    var imageURLs: [URL] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: imagesDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return urls.filter { ["jpg", "jpeg", "png"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
    var imageCount: Int {
        let diskCount = imageURLs.count
        return diskCount > 0 ? diskCount : (metadata.savedImageCount ?? 0)
    }
    var hasImages: Bool { !imageURLs.isEmpty }
    var gcpCSVURL: URL { directory.appendingPathComponent("gcps.csv") }
    var gcpGeoJSONURL: URL { directory.appendingPathComponent("gcps.geojson") }
    var gcpDXFURL: URL { directory.appendingPathComponent("gcps.dxf") }
    var gcpCloudCompareURL: URL { directory.appendingPathComponent("gcps-cloudcompare.txt") }
    var gcpQGISPointsURL: URL { directory.appendingPathComponent("gcps.points") }
    func gcpURL(for kind: GCPExportKind) -> URL { directory.appendingPathComponent(kind.fileName) }
    var hasGCPs: Bool { !(metadata.groundControlPoints?.isEmpty ?? true) || FileManager.default.fileExists(atPath: gcpCSVURL.path) }
    var annotationsGeoJSONURL: URL { directory.appendingPathComponent("annotations.geojson") }
    var annotationsCSVURL: URL { directory.appendingPathComponent("annotations.csv") }
    var annotationsDXFURL: URL { directory.appendingPathComponent("annotations.dxf") }
    var hasAnnotations: Bool { !(metadata.annotations?.isEmpty ?? true) || FileManager.default.fileExists(atPath: annotationsGeoJSONURL.path) }
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

    static func stagingImagesDirectory(for scanID: UUID) throws -> URL {
        try root().appendingPathComponent(".images-" + scanID.uuidString, isDirectory: true)
    }

    static func cleanupStagingImages(for scanID: UUID? = nil) {
        guard let base = try? root() else { return }
        if let scanID {
            try? FileManager.default.removeItem(at: base.appendingPathComponent(".images-" + scanID.uuidString, isDirectory: true))
        } else if let items = try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil, options: []) {
            for item in items where item.lastPathComponent.hasPrefix(".images-") {
                try? FileManager.default.removeItem(at: item)
            }
        }
    }

    @discardableResult
    static func writeStagingImage(_ pixelBuffer: CVPixelBuffer, index: Int, scanID: UUID, context: CIContext) throws -> Bool {
        let dir = try stagingImagesDirectory(for: scanID)
        let volume = try dir.deletingLastPathComponent().resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let avail = volume.volumeAvailableCapacityForImportantUsage, avail > 0, avail <= 256 * 1024 * 1024 {
            return false
        }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard let bytes = context.jpegRepresentation(
            of: image,
            colorSpace: CGColorSpaceCreateDeviceRGB(),
            options: [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.92]
        ) else {
            return false
        }
        let fileURL = dir.appendingPathComponent(String(format: "frame_%06d.jpg", index))
        try bytes.write(to: fileURL, options: .atomic)
        return true
    }

    static func syncStagingImages(from stagingImagesURL: URL?, to targetImagesDirectory: URL) throws -> Int {
        guard let stagingImagesURL, FileManager.default.fileExists(atPath: stagingImagesURL.path) else { return 0 }
        let files = (try? FileManager.default.contentsOfDirectory(
            at: stagingImagesURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ))?.filter { ["jpg", "jpeg", "png"].contains($0.pathExtension.lowercased()) }
          .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
        guard !files.isEmpty else { return 0 }
        try FileManager.default.createDirectory(at: targetImagesDirectory, withIntermediateDirectories: true)
        for file in files {
            let dest = targetImagesDirectory.appendingPathComponent(file.lastPathComponent)
            if !FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.copyItem(at: file, to: dest)
            }
        }
        return files.count
    }

    static func exportImagesZIP(for scan: SavedScan) throws -> URL {
        let images = scan.imageURLs
        guard !images.isEmpty else {
            throw ScanFailure.message("No captured images available for export.")
        }
        return try ZipArchive.zipFiles(
            images,
            folderName: "images",
            zipFileName: "Images-\(scan.metadata.scanID.uuidString.prefix(8)).zip"
        )
    }

    static func save(_ cloud: OpaquePointer, metadata: ScanMetadata, format: ExportFormat, meshAnchors: [ARMeshAnchor] = [], stagingImagesURL: URL? = nil) throws -> SavedScan {
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
            var savedMetadata = metadata
            let copiedImages = try syncStagingImages(from: stagingImagesURL, to: staging.appendingPathComponent("images", isDirectory: true))
            if copiedImages > 0 && savedMetadata.savedImageCount == nil {
                savedMetadata.savedImageCount = copiedImages
            }
            if let gcps = savedMetadata.groundControlPoints, !gcps.isEmpty {
                savedMetadata.georeferencing = savedMetadata.georeferencing ?? GCPRegistration.computeGeoreferencing(for: gcps)
                try GCPExporter.csvData(for: gcps).write(to: staging.appendingPathComponent("gcps.csv"), options: .atomic)
                try GCPExporter.geoJSONData(for: gcps, metadata: savedMetadata)
                    .write(to: staging.appendingPathComponent("gcps.geojson"), options: .atomic)
            }
            if let annotations = savedMetadata.annotations, !annotations.isEmpty {
                try AnnotationExporter.geoJSONData(for: annotations, metadata: savedMetadata)
                    .write(to: staging.appendingPathComponent("annotations.geojson"), options: .atomic)
            }
            try encodeMetadata(savedMetadata).write(to: staging.appendingPathComponent("metadata.json"), options: .atomic)
            try FileManager.default.moveItem(at: staging, to: final)
            let savedScan = SavedScan(directory: final, metadata: savedMetadata)
            ReportPreviewRenderer.writePointCloudThumbnail(for: savedScan)
            return savedScan
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    static func gcpCSVData(for points: [GroundControlPoint]) -> Data {
        GCPExporter.csvData(for: points)
    }

    private static func encodeMetadata(_ metadata: ScanMetadata) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(metadata)
    }

    static func updateGroundControlPoints(for scan: SavedScan, points: [GroundControlPoint]) throws -> SavedScan {
        var meta = scan.metadata
        meta.groundControlPoints = points.isEmpty ? nil : points
        meta.georeferencing = GCPRegistration.computeGeoreferencing(for: points)
        try encodeMetadata(meta).write(to: scan.metadataURL, options: .atomic)
        if points.isEmpty {
            try? FileManager.default.removeItem(at: scan.gcpCSVURL)
            try? FileManager.default.removeItem(at: scan.gcpGeoJSONURL)
        } else {
            try GCPExporter.csvData(for: points).write(to: scan.gcpCSVURL, options: .atomic)
            try GCPExporter.geoJSONData(for: points, metadata: meta).write(to: scan.gcpGeoJSONURL, options: .atomic)
        }
        return SavedScan(directory: scan.directory, metadata: meta)
    }

    static func updateAnnotations(for scan: SavedScan, annotations: [CloudAnnotation]) throws -> SavedScan {
        var meta = scan.metadata
        meta.annotations = annotations.isEmpty ? nil : annotations
        try encodeMetadata(meta).write(to: scan.metadataURL, options: .atomic)
        if annotations.isEmpty {
            try? FileManager.default.removeItem(at: scan.annotationsGeoJSONURL)
        } else {
            try AnnotationExporter.geoJSONData(for: annotations, metadata: meta)
                .write(to: scan.annotationsGeoJSONURL, options: .atomic)
        }
        return SavedScan(directory: scan.directory, metadata: meta)
    }

    static func updateProjectOrganization(
        for scan: SavedScan,
        title: String,
        projectDescription: String?,
        tags: [String],
        collectionIDs: [UUID]
    ) throws -> SavedScan {
        var meta = scan.metadata
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanTitle.isEmpty {
            meta.title = cleanTitle
        }
        meta.projectDescription = ProjectTagCatalog.trimmedOrNil(projectDescription)
        meta.tags = ProjectTagCatalog.normalizedOrNil(tags)
        var seen = Set<UUID>()
        let dedupedIDs = collectionIDs.filter { seen.insert($0).inserted }
        meta.collectionIDs = dedupedIDs.isEmpty ? nil : dedupedIDs
        try encodeMetadata(meta).write(to: scan.metadataURL, options: .atomic)
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
            let savedScan = SavedScan(directory: final, metadata: metadata)
            ReportPreviewRenderer.writePointCloudThumbnail(for: savedScan)
            return savedScan
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
