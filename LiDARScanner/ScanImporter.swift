import Foundation
import UniformTypeIdentifiers

enum ScanImportError: LocalizedError {
    case unsupportedFormat
    case invalidFile
    case readingFailed(String)
    case emptyPointCloud

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return String(localized: "Unsupported file format. Please select a .ply, .xyz, .zip file or scan folder.")
        case .invalidFile:
            return String(localized: "The selected file could not be read or does not exist.")
        case .readingFailed(let reason):
            return String(format: String(localized: "Import failed: %@"), reason)
        case .emptyPointCloud:
            return String(localized: "The point cloud file contains no valid points.")
        }
    }
}

enum ScanImporter {
    static let supportedContentTypes: [UTType] = [
        UTType(filenameExtension: "ply") ?? .data,
        UTType(filenameExtension: "xyz") ?? .plainText,
        .zip,
        .folder,
        .item
    ]

    /// Parses a PLY file header to determine the vertex count and whether it is binary or ASCII.
    static func parsePLYHeader(from url: URL) -> (vertexCount: Int, isBinary: Bool, hasColor: Bool)? {
        guard let file = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? file.close() }

        guard let initialData = try? file.read(upToCount: 8192),
              let headerString = String(data: initialData, encoding: .utf8) ?? String(data: initialData, encoding: .ascii),
              headerString.hasPrefix("ply") else {
            return nil
        }

        let isBinary = headerString.contains("format binary_little_endian")
        let hasColor = headerString.contains("red") && headerString.contains("green") && headerString.contains("blue")
        var vertexCount = 0

        let lines = headerString.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("element vertex ") {
                let parts = trimmed.components(separatedBy: " ")
                if parts.count >= 3, let count = Int(parts[2]) {
                    vertexCount = count
                    break
                }
            }
            if trimmed == "end_header" { break }
        }

        return (vertexCount: vertexCount, isBinary: isBinary, hasColor: hasColor)
    }

    /// Reads up to `maxPoints` from a PLY or XYZ file for 3D preview in the app.
    static func readPreviewPoints(from url: URL, maxPoints: Int = 40_000) -> [PCPoint] {
        if url.pathExtension.lowercased() == "xyz" {
            return readXYZPreviewPoints(from: url, maxPoints: maxPoints)
        }

        guard let file = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? file.close() }

        guard let initialData = try? file.read(upToCount: 8192),
              let headerString = String(data: initialData, encoding: .utf8) ?? String(data: initialData, encoding: .ascii),
              let endHeaderRange = headerString.range(of: "end_header\n") ?? headerString.range(of: "end_header\r\n") else {
            return []
        }

        let isBinary = headerString.contains("format binary_little_endian")
        var vertexCount = 0
        let lines = headerString.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("element vertex ") {
                let parts = trimmed.components(separatedBy: " ")
                if parts.count >= 3, let count = Int(parts[2]) {
                    vertexCount = count
                    break
                }
            }
        }

        guard vertexCount > 0 else { return [] }
        let headerLength = headerString[..<endHeaderRange.upperBound].utf8.count
        try? file.seek(toOffset: UInt64(headerLength))

        var points: [PCPoint] = []
        points.reserveCapacity(min(maxPoints, vertexCount))
        let step = max(1, vertexCount / maxPoints)

        if isBinary {
            let hasColors = headerString.contains("property uchar red") || headerString.contains("property uint8 red")
            let recordSize = hasColors ? 16 : 12
            let bufferSize = 65536
            var remainingVertices = vertexCount
            var vertexIndex = 0

            while remainingVertices > 0 {
                guard let chunk = try? file.read(upToCount: min(bufferSize, remainingVertices * recordSize)),
                      chunk.count >= recordSize else { break }
                let countInChunk = chunk.count / recordSize

                chunk.withUnsafeBytes { raw in
                    for i in 0..<countInChunk {
                        let globalIndex = vertexIndex + i
                        if globalIndex % step == 0 {
                            let offset = i * recordSize
                            let x = raw.load(fromByteOffset: offset, as: Float.self)
                            let y = raw.load(fromByteOffset: offset + 4, as: Float.self)
                            let z = raw.load(fromByteOffset: offset + 8, as: Float.self)

                            var r: UInt8 = 200, g: UInt8 = 200, b: UInt8 = 200, conf: UInt8 = 2
                            if recordSize >= 16 {
                                r = raw.load(fromByteOffset: offset + 12, as: UInt8.self)
                                g = raw.load(fromByteOffset: offset + 13, as: UInt8.self)
                                b = raw.load(fromByteOffset: offset + 14, as: UInt8.self)
                                conf = raw.load(fromByteOffset: offset + 15, as: UInt8.self)
                            }
                            // Convert PLY (X, -Z, Y) to ARKit preview orientation (X, Y_arkit, Z_arkit)
                            points.append(PCPoint(x: x, y: z, z: -y, r: r, g: g, b: b, confidence: conf))
                            if points.count >= maxPoints { return }
                        }
                    }
                }
                if points.count >= maxPoints { break }
                vertexIndex += countInChunk
                remainingVertices -= countInChunk
            }
        } else {
            guard let restData = try? file.readToEnd(),
                  let restString = String(data: restData, encoding: .utf8) ?? String(data: restData, encoding: .ascii) else {
                return []
            }
            var i = 0
            restString.enumerateLines { line, stop in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return }
                if i % step == 0 {
                    let parts = trimmed.components(separatedBy: .whitespaces)
                    if parts.count >= 3,
                       let x = Float(parts[0]),
                       let y = Float(parts[1]),
                       let z = Float(parts[2]) {
                        var r: UInt8 = 200, g: UInt8 = 200, b: UInt8 = 200
                        if parts.count >= 6,
                           let red = UInt8(parts[3]),
                           let green = UInt8(parts[4]),
                           let blue = UInt8(parts[5]) {
                            r = red; g = green; b = blue
                        }
                        points.append(PCPoint(x: x, y: z, z: -y, r: r, g: g, b: b, confidence: 2))
                        if points.count >= maxPoints { stop = true }
                    }
                }
                i += 1
            }
        }

        return points
    }

    private static func readXYZPreviewPoints(from url: URL, maxPoints: Int) -> [PCPoint] {
        guard let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
            return []
        }
        var points: [PCPoint] = []
        var totalLines = 0
        content.enumerateLines { _, _ in totalLines += 1 }
        let step = max(1, totalLines / maxPoints)
        var i = 0
        content.enumerateLines { line, stop in
            if i % step == 0 {
                let parts = line.trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces)
                if parts.count >= 3,
                   let x = Float(parts[0]),
                   let y = Float(parts[1]),
                   let z = Float(parts[2]) {
                    points.append(PCPoint(x: x, y: z, z: -y, r: 200, g: 200, b: 200, confidence: 2))
                    if points.count >= maxPoints { stop = true }
                }
            }
            i += 1
        }
        return points
    }

    /// Imports an external file or directory into the app's Scans archive.
    static func importScan(from sourceURL: URL) throws -> SavedScan {
        let isAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: sourceURL.path, isDirectory: &isDir) else {
            throw ScanImportError.invalidFile
        }

        if isDir.boolValue {
            return try importDirectory(sourceURL)
        }

        let ext = sourceURL.pathExtension.lowercased()
        switch ext {
        case "ply":
            return try importPLYFile(sourceURL)
        case "xyz":
            return try importXYZFile(sourceURL)
        case "zip":
            return try importZIPArchive(sourceURL)
        default:
            throw ScanImportError.unsupportedFormat
        }
    }

    private static func importPLYFile(_ fileURL: URL) throws -> SavedScan {
        guard let header = parsePLYHeader(from: fileURL), header.vertexCount > 0 else {
            throw ScanImportError.emptyPointCloud
        }

        let baseTitle = fileURL.deletingPathExtension().lastPathComponent
        let metadata = makeMetadata(title: baseTitle, pointCount: header.vertexCount, formatNote: header.isBinary ? "Binary PLY" : "ASCII PLY")
        return try ScanStorage.saveImported(sourceURL: fileURL, metadata: metadata, format: header.isBinary ? .binaryPLY : .asciiPLY)
    }

    private static func importXYZFile(_ fileURL: URL) throws -> SavedScan {
        guard let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
            throw ScanImportError.invalidFile
        }

        var lineCount = 0
        text.enumerateLines { line, _ in
            if !line.trimmingCharacters(in: .whitespaces).isEmpty { lineCount += 1 }
        }
        guard lineCount > 0 else { throw ScanImportError.emptyPointCloud }

        let baseTitle = fileURL.deletingPathExtension().lastPathComponent
        let metadata = makeMetadata(title: baseTitle, pointCount: lineCount, formatNote: "XYZ text coordinates")
        return try ScanStorage.saveImported(sourceURL: fileURL, metadata: metadata, format: .xyz)
    }

    private static func importDirectory(_ dirURL: URL) throws -> SavedScan {
        let metadataURL = dirURL.appendingPathComponent("metadata.json")
        let pointsPlyURL = dirURL.appendingPathComponent("points.ply")

        if FileManager.default.fileExists(atPath: metadataURL.path),
           FileManager.default.fileExists(atPath: pointsPlyURL.path) {
            // Already a full scan directory: copy it into Scans/
            let base = try ScanStorage.root()
            let id = UUID().uuidString
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let target = base.appendingPathComponent(formatter.string(from: Date()) + "_" + String(id.prefix(8)) + "_" + dirURL.lastPathComponent)
            try FileManager.default.copyItem(at: dirURL, to: target)

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let data = try Data(contentsOf: target.appendingPathComponent("metadata.json"))
            let metadata = try decoder.decode(ScanMetadata.self, from: data)
            return SavedScan(directory: target, metadata: metadata)
        }

        // Look for any .ply file inside the folder
        let files = try FileManager.default.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil)
        if let plyFile = files.first(where: { $0.pathExtension.lowercased() == "ply" }) {
            return try importPLYFile(plyFile)
        }
        if let xyzFile = files.first(where: { $0.pathExtension.lowercased() == "xyz" }) {
            return try importXYZFile(xyzFile)
        }

        throw ScanImportError.unsupportedFormat
    }

    private static func importZIPArchive(_ zipURL: URL) throws -> SavedScan {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("import-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Use iOS FileManager unzip or folder discovery
        // Unzip via system or find files
        let coordinator = NSFileCoordinator()
        var coordinatedError: NSError?
        var importedScan: SavedScan?

        coordinator.coordinate(readingItemAt: zipURL, options: [], error: &coordinatedError) { readURL in
            // Look inside the uncompressed folder if system mounted or unpack
            // In iOS, FileManager can unpack if zipped or read as container
            do {
                let items = try FileManager.default.contentsOfDirectory(at: readURL, includingPropertiesForKeys: nil)
                if let scanDir = items.first(where: { (try? FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil))?.contains(where: { $0.lastPathComponent == "points.ply" }) == true }) {
                    importedScan = try? importDirectory(scanDir)
                } else if let ply = items.first(where: { $0.pathExtension.lowercased() == "ply" }) {
                    importedScan = try? importPLYFile(ply)
                }
            } catch {}
        }

        if let importedScan {
            return importedScan
        }
        throw ScanImportError.unsupportedFormat
    }

    private static func makeMetadata(title: String, pointCount: Int, formatNote: String) -> ScanMetadata {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.2.0"
        let appBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "4"

        return ScanMetadata(
            schemaVersion: 1,
            appVersion: appVersion,
            appBuild: appBuild,
            scanID: UUID(),
            title: title,
            startedAt: Date(),
            savedAt: Date(),
            pointCount: pointCount,
            acceptedSamples: UInt64(pointCount),
            processedFrames: 0,
            activeSeconds: 0,
            settings: ScanSettings(),
            deviceModel: "External File",
            systemVersion: "Imported",
            depthWidth: 0,
            depthHeight: 0,
            unit: "metre",
            coordinateSystem: "Imported Cartesian; Z up",
            arkitToExportRowMajor: [1, 0, 0, 0, 0, 0, -1, 0, 0, 1, 0, 0, 0, 0, 0, 1],
            depthSource: "Imported via Files (\(formatNote))",
            confidenceMeaning: "Imported; external source",
            pointSelection: "External source",
            colorSource: "Imported; external source",
            sessionNote: "Imported into LiDAR-Scanner archive"
        )
    }
}
