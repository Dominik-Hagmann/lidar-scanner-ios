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
            return LanguageManager.string("Unsupported file format. Please select a .ply, .xyz, .zip file or scan folder.")
        case .invalidFile:
            return LanguageManager.string("The selected file could not be read or does not exist.")
        case .readingFailed(let reason):
            return LanguageManager.format("Import failed: %@", reason)
        case .emptyPointCloud:
            return LanguageManager.string("The point cloud file contains no valid points.")
        }
    }
}

private enum PLYFormat {
    case ascii
    case binaryLittleEndian
    case binaryBigEndian

    var isBinary: Bool {
        self != .ascii
    }
}

private enum PLYScalarType {
    case int8, uint8, int16, uint16, int32, uint32, float32, float64

    var byteSize: Int {
        switch self {
        case .int8, .uint8: return 1
        case .int16, .uint16: return 2
        case .int32, .uint32, .float32: return 4
        case .float64: return 8
        }
    }

    init?(plyToken: String) {
        switch plyToken.lowercased() {
        case "char", "int8": self = .int8
        case "uchar", "uint8": self = .uint8
        case "short", "int16": self = .int16
        case "ushort", "uint16": self = .uint16
        case "int", "int32": self = .int32
        case "uint", "uint32": self = .uint32
        case "float", "float32": self = .float32
        case "double", "float64": self = .float64
        default: return nil
        }
    }

    func readFloat(from raw: UnsafeRawBufferPointer, offset: Int, bigEndian: Bool) -> Float {
        switch self {
        case .int8: return Float(loadUnaligned(raw, offset: offset, as: Int8.self))
        case .uint8: return Float(loadUnaligned(raw, offset: offset, as: UInt8.self))
        case .int16:
            let v = loadUnaligned(raw, offset: offset, as: Int16.self)
            return Float(bigEndian ? Int16(bigEndian: v) : Int16(littleEndian: v))
        case .uint16:
            let v = loadUnaligned(raw, offset: offset, as: UInt16.self)
            return Float(bigEndian ? UInt16(bigEndian: v) : UInt16(littleEndian: v))
        case .int32:
            let v = loadUnaligned(raw, offset: offset, as: Int32.self)
            return Float(bigEndian ? Int32(bigEndian: v) : Int32(littleEndian: v))
        case .uint32:
            let v = loadUnaligned(raw, offset: offset, as: UInt32.self)
            return Float(bigEndian ? UInt32(bigEndian: v) : UInt32(littleEndian: v))
        case .float32:
            let bits = loadUnaligned(raw, offset: offset, as: UInt32.self)
            return Float(bitPattern: bigEndian ? UInt32(bigEndian: bits) : UInt32(littleEndian: bits))
        case .float64:
            let bits = loadUnaligned(raw, offset: offset, as: UInt64.self)
            return Float(Double(bitPattern: bigEndian ? UInt64(bigEndian: bits) : UInt64(littleEndian: bits)))
        }
    }

    func readByteColor(from raw: UnsafeRawBufferPointer, offset: Int, bigEndian: Bool) -> UInt8 {
        switch self {
        case .uint8:
            return loadUnaligned(raw, offset: offset, as: UInt8.self)
        case .int8:
            return UInt8(max(0, Int(loadUnaligned(raw, offset: offset, as: Int8.self))))
        case .float32, .float64:
            let val = readFloat(from: raw, offset: offset, bigEndian: bigEndian)
            let scaled = (val >= 0 && val <= 1.0) ? val * 255.0 : val
            return UInt8(clamping: Int(scaled.rounded()))
        default:
            return UInt8(clamping: Int(readFloat(from: raw, offset: offset, bigEndian: bigEndian).rounded()))
        }
    }

    private func loadUnaligned<T>(_ raw: UnsafeRawBufferPointer, offset: Int, as type: T.Type) -> T {
        precondition(offset >= 0 && offset + MemoryLayout<T>.size <= raw.count)
        return withUnsafeTemporaryAllocation(byteCount: MemoryLayout<T>.size, alignment: MemoryLayout<T>.alignment) { temp in
            memcpy(temp.baseAddress!, raw.baseAddress!.advanced(by: offset), MemoryLayout<T>.size)
            return temp.baseAddress!.assumingMemoryBound(to: T.self).pointee
        }
    }
}

private struct PLYProperty {
    let type: PLYScalarType
    let byteOffset: Int
    let columnIndex: Int
}

private struct PLYHeader {
    let format: PLYFormat
    let vertexCount: Int
    let headerByteLength: Int
    let recordSize: Int
    let x: PLYProperty
    let y: PLYProperty
    let z: PLYProperty
    let red: PLYProperty?
    let green: PLYProperty?
    let blue: PLYProperty?
    let confidence: PLYProperty?

    var isBinary: Bool { format.isBinary }
    var hasColor: Bool { red != nil && green != nil && blue != nil }

    static func parse(from url: URL) -> PLYHeader? {
        guard let file = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? file.close() }

        let maxHeaderBytes = 65_536
        var headerData = Data()
        while headerData.count < maxHeaderBytes {
            guard let chunk = try? file.read(upToCount: 8192), !chunk.isEmpty else { break }
            headerData.append(chunk)
            if locateEndHeader(in: headerData) != nil { break }
        }

        guard let endRange = locateEndHeader(in: headerData) else { return nil }
        let asciiHeaderData = headerData.subdata(in: 0..<endRange.upperBound)
        guard let headerString = String(data: asciiHeaderData, encoding: .utf8) ?? String(data: asciiHeaderData, encoding: .isoLatin1) else {
            return nil
        }

        let lines = headerString.split(whereSeparator: \.isNewline)
        guard let firstLine = lines.first?.trimmingCharacters(in: .whitespaces), firstLine == "ply" else {
            return nil
        }

        var format: PLYFormat?
        var vertexCount = -1
        var inVertexElement = false
        var properties: [String: PLYProperty] = [:]
        var byteOffset = 0
        var columnIndex = 0

        for rawLine in lines.dropFirst() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("comment ") || line.hasPrefix("obj_info ") { continue }
            if line == "end_header" { break }

            let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard let keyword = parts.first else { continue }

            switch keyword {
            case "format":
                guard parts.count >= 2 else { return nil }
                switch parts[1] {
                case "ascii": format = .ascii
                case "binary_little_endian": format = .binaryLittleEndian
                case "binary_big_endian": format = .binaryBigEndian
                default: return nil
                }
            case "element":
                guard parts.count >= 3 else { continue }
                if parts[1] == "vertex" {
                    guard let count = Int(parts[2]), count >= 0 else { return nil }
                    vertexCount = count
                    inVertexElement = true
                } else {
                    inVertexElement = false
                }
            case "property":
                guard inVertexElement else { continue }
                if parts.count >= 2 && parts[1] == "list" {
                    if format?.isBinary == true { return nil }
                    columnIndex += 1
                    continue
                }
                guard parts.count >= 3, let scalar = PLYScalarType(plyToken: parts[1]) else { continue }
                let prop = PLYProperty(type: scalar, byteOffset: byteOffset, columnIndex: columnIndex)
                properties[parts[2].lowercased()] = prop
                byteOffset += scalar.byteSize
                columnIndex += 1
            default:
                continue
            }
        }

        guard let resolvedFormat = format, vertexCount >= 0,
              let x = properties["x"], let y = properties["y"], let z = properties["z"] else {
            return nil
        }

        let red = properties["red"] ?? properties["r"]
        let green = properties["green"] ?? properties["g"]
        let blue = properties["blue"] ?? properties["b"]
        let conf = properties["confidence"] ?? properties["conf"]

        return PLYHeader(
            format: resolvedFormat,
            vertexCount: vertexCount,
            headerByteLength: endRange.upperBound,
            recordSize: byteOffset,
            x: x, y: y, z: z,
            red: red, green: green, blue: blue,
            confidence: conf
        )
    }

    private static func locateEndHeader(in data: Data) -> Range<Int>? {
        let lfMarker = Data("end_header\n".utf8)
        let crlfMarker = Data("end_header\r\n".utf8)
        let lfRange = data.range(of: lfMarker)
        let crlfRange = data.range(of: crlfMarker)

        switch (lfRange, crlfRange) {
        case (.some(let a), .some(let b)):
            return a.lowerBound < b.lowerBound ? a : b
        case (.some(let a), .none):
            return a
        case (.none, .some(let b)):
            return b
        case (.none, .none):
            let eofMarker = Data("end_header".utf8)
            if let r = data.range(of: eofMarker), r.upperBound == data.count {
                return r
            }
            return nil
        }
    }
}

enum ScanImporter {
    static let supportedContentTypes: [UTType] = [
        UTType(filenameExtension: "ply") ?? .data,
        UTType(filenameExtension: "xyz") ?? .plainText,
        .commaSeparatedText,
        .zip,
        .folder,
        .item
    ]

    /// Parses a PLY file header to determine the vertex count and whether it is binary or ASCII.
    static func parsePLYHeader(from url: URL) -> (vertexCount: Int, isBinary: Bool, hasColor: Bool)? {
        guard let header = PLYHeader.parse(from: url) else { return nil }
        return (vertexCount: header.vertexCount, isBinary: header.isBinary, hasColor: header.hasColor)
    }

    /// Reads up to `maxPoints` evenly sampled points from a PLY, XYZ, or CSV file for 3D preview.
    static func readPreviewPoints(from url: URL, maxPoints: Int = 40_000) -> [PCPoint] {
        readPoints(from: url, formatHint: nil, maxPoints: maxPoints)
    }

    /// Reads points from a PLY, XYZ, or CSV file. Pass `nil` for `maxPoints` to load every point.
    static func readPoints(from url: URL, formatHint: ExportFormat? = nil, maxPoints: Int? = 40_000) -> [PCPoint] {
        let ext = url.pathExtension.lowercased()
        if formatHint == .csv || (formatHint == nil && ext == "csv") {
            return readTextPoints(from: url, maxPoints: maxPoints, parser: parseCSVLine)
        }
        if formatHint == .xyz || (formatHint == nil && ext == "xyz") {
            return readTextPoints(from: url, maxPoints: maxPoints, parser: parseXYZLine)
        }
        return readPLYPoints(from: url, maxPoints: maxPoints)
    }

    private static func readPLYPoints(from url: URL, maxPoints: Int?) -> [PCPoint] {
        guard let header = PLYHeader.parse(from: url), header.vertexCount > 0 else { return [] }
        if let maxPoints, maxPoints <= 0 { return [] }

        guard let file = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? file.close() }
        do {
            try file.seek(toOffset: UInt64(header.headerByteLength))
        } catch {
            return []
        }

        let targetCount = maxPoints.map { min($0, header.vertexCount) } ?? header.vertexCount
        var points: [PCPoint] = []
        points.reserveCapacity(targetCount)

        if header.isBinary {
            guard header.recordSize > 0 else { return [] }
            let recordSize = header.recordSize
            let bigEndian = header.format == .binaryBigEndian
            let readSize = max(recordSize, (65_536 / recordSize) * recordSize)

            var remainder = Data()
            var vertexIndex = 0
            var sampled = 0
            var nextSampleIndex = 0

            while vertexIndex < header.vertexCount && points.count < targetCount {
                guard let chunk = try? file.read(upToCount: readSize), !chunk.isEmpty else { break }
                var buffer = remainder
                buffer.append(chunk)

                let usableBytes = (buffer.count / recordSize) * recordSize
                let countInBuffer = min(usableBytes / recordSize, header.vertexCount - vertexIndex)
                if usableBytes < buffer.count {
                    remainder = buffer.subdata(in: usableBytes..<buffer.count)
                } else {
                    remainder.removeAll(keepingCapacity: true)
                }

                buffer.withUnsafeBytes { raw in
                    for i in 0..<countInBuffer {
                        let globalIndex = vertexIndex + i
                        guard globalIndex == nextSampleIndex else { continue }

                        let base = i * recordSize
                        let x = header.x.type.readFloat(from: raw, offset: base + header.x.byteOffset, bigEndian: bigEndian)
                        let y = header.y.type.readFloat(from: raw, offset: base + header.y.byteOffset, bigEndian: bigEndian)
                        let z = header.z.type.readFloat(from: raw, offset: base + header.z.byteOffset, bigEndian: bigEndian)

                        let r = header.red.map { $0.type.readByteColor(from: raw, offset: base + $0.byteOffset, bigEndian: bigEndian) } ?? 200
                        let g = header.green.map { $0.type.readByteColor(from: raw, offset: base + $0.byteOffset, bigEndian: bigEndian) } ?? 200
                        let b = header.blue.map { $0.type.readByteColor(from: raw, offset: base + $0.byteOffset, bigEndian: bigEndian) } ?? 200
                        let conf = header.confidence.map { $0.type.readByteColor(from: raw, offset: base + $0.byteOffset, bigEndian: bigEndian) } ?? 2

                        // Convert PLY (X, -Z, Y) back to ARKit preview orientation (X, Y_arkit, Z_arkit)
                        points.append(PCPoint(x: x, y: z, z: -y, r: r, g: g, b: b, confidence: conf))
                        sampled += 1
                        if sampled >= targetCount { break }
                        nextSampleIndex = (targetCount == header.vertexCount) ? sampled : (sampled * header.vertexCount / targetCount)
                    }
                }
                vertexIndex += countInBuffer
            }
        } else {
            guard let restData = try? file.readToEnd(),
                  let restString = String(data: restData, encoding: .utf8) ?? String(data: restData, encoding: .isoLatin1) else {
                return []
            }

            var vertexIndex = 0
            var sampled = 0
            var nextSampleIndex = 0

            restString.enumerateLines { line, stop in
                if vertexIndex >= header.vertexCount || sampled >= targetCount {
                    stop = true
                    return
                }
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return }

                defer { vertexIndex += 1 }
                guard vertexIndex == nextSampleIndex else { return }

                let parts = trimmed.split(whereSeparator: \.isWhitespace)
                let needed = max(header.x.columnIndex, header.y.columnIndex, header.z.columnIndex)
                guard parts.count > needed,
                      let x = Float(parts[header.x.columnIndex]),
                      let y = Float(parts[header.y.columnIndex]),
                      let z = Float(parts[header.z.columnIndex]) else {
                    return
                }

                let r = header.red.flatMap { parts.indices.contains($0.columnIndex) ? parseASCIIColor(parts[$0.columnIndex]) : nil } ?? 200
                let g = header.green.flatMap { parts.indices.contains($0.columnIndex) ? parseASCIIColor(parts[$0.columnIndex]) : nil } ?? 200
                let b = header.blue.flatMap { parts.indices.contains($0.columnIndex) ? parseASCIIColor(parts[$0.columnIndex]) : nil } ?? 200
                let conf = header.confidence.flatMap { parts.indices.contains($0.columnIndex) ? UInt8(parts[$0.columnIndex]) : nil } ?? 2

                points.append(PCPoint(x: x, y: z, z: -y, r: r, g: g, b: b, confidence: conf))
                sampled += 1
                nextSampleIndex = (targetCount == header.vertexCount) ? sampled : (sampled * header.vertexCount / targetCount)
                if sampled >= targetCount { stop = true }
            }
        }

        return points
    }

    private static func readTextPoints(from url: URL, maxPoints: Int?, parser: @escaping (String) -> PCPoint?) -> [PCPoint] {
        if let maxPoints, maxPoints <= 0 { return [] }
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let content = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            return []
        }

        var points: [PCPoint] = []
        guard let maxPoints else {
            content.enumerateLines { line, _ in
                if let point = parser(line) {
                    points.append(point)
                }
            }
            return points
        }

        var validLines = 0
        content.enumerateLines { line, _ in
            if parser(line) != nil { validLines += 1 }
        }
        guard validLines > 0 else { return [] }

        let targetCount = min(maxPoints, validLines)
        points.reserveCapacity(targetCount)
        var validIndex = 0
        var sampled = 0
        var nextSampleIndex = 0

        content.enumerateLines { line, stop in
            guard let point = parser(line) else { return }
            if validIndex == nextSampleIndex {
                points.append(point)
                sampled += 1
                if sampled >= targetCount {
                    stop = true
                    return
                }
                nextSampleIndex = (targetCount == validLines) ? sampled : (sampled * validLines / targetCount)
            }
            validIndex += 1
        }
        return points
    }

    private static func parseXYZLine(_ line: String) -> PCPoint? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), !trimmed.hasPrefix("//") else { return nil }
        return buildTextPoint(from: trimmed.split(whereSeparator: \.isWhitespace))
    }

    private static func parseCSVLine(_ line: String) -> PCPoint? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), !trimmed.hasPrefix("//") else { return nil }
        let separator: Character = trimmed.contains(";") ? ";" : ","
        let rawParts = trimmed.split(separator: separator, omittingEmptySubsequences: false)
            .map { Substring($0.trimmingCharacters(in: .whitespaces)) }
        return buildTextPoint(from: rawParts)
    }

    private static func buildTextPoint(from parts: [Substring]) -> PCPoint? {
        guard parts.count >= 3,
              let x = Float(parts[0]),
              let y = Float(parts[1]),
              let z = Float(parts[2]) else {
            return nil
        }
        var r: UInt8 = 200, g: UInt8 = 200, b: UInt8 = 200
        if parts.count >= 6,
           let red = parseASCIIColor(parts[3]),
           let green = parseASCIIColor(parts[4]),
           let blue = parseASCIIColor(parts[5]) {
            r = red; g = green; b = blue
        }
        var confidence: UInt8 = 2
        if parts.count >= 7, let c = UInt8(parts[6]) {
            confidence = c
        }
        return PCPoint(x: x, y: z, z: -y, r: r, g: g, b: b, confidence: confidence)
    }

    private static func parseASCIIColor(_ token: Substring) -> UInt8? {
        if let byte = UInt8(token) { return byte }
        guard let floatVal = Float(token) else { return nil }
        let scaled = (floatVal >= 0 && floatVal <= 1.0) ? floatVal * 255.0 : floatVal
        return UInt8(clamping: Int(scaled.rounded()))
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
            return try importDirectory(sourceURL, depth: 0)
        }

        switch sourceURL.pathExtension.lowercased() {
        case "ply":
            return try importPLYFile(sourceURL)
        case "xyz":
            return try importDelimitedTextFile(sourceURL, format: .xyz, formatNote: "XYZ text coordinates", parser: parseXYZLine)
        case "csv":
            return try importDelimitedTextFile(sourceURL, format: .csv, formatNote: "CSV table coordinates", parser: parseCSVLine)
        case "zip":
            return try importZIPArchive(sourceURL)
        default:
            throw ScanImportError.unsupportedFormat
        }
    }

    private static func importPLYFile(_ fileURL: URL) throws -> SavedScan {
        guard let header = PLYHeader.parse(from: fileURL), header.vertexCount > 0 else {
            throw ScanImportError.emptyPointCloud
        }

        let baseTitle = fileURL.deletingPathExtension().lastPathComponent
        let format: ExportFormat = header.isBinary ? .binaryPLY : .asciiPLY
        let note = header.isBinary ? "Binary PLY" : "ASCII PLY"
        let metadata = makeMetadata(title: baseTitle, pointCount: header.vertexCount, formatNote: note)
        return try ScanStorage.saveImported(sourceURL: fileURL, metadata: metadata, format: format)
    }

    private static func importDelimitedTextFile(_ fileURL: URL, format: ExportFormat,
                                                formatNote: String, parser: @escaping (String) -> PCPoint?) throws -> SavedScan {
        guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe),
              let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw ScanImportError.invalidFile
        }

        var pointCount = 0
        text.enumerateLines { line, _ in
            if parser(line) != nil { pointCount += 1 }
        }
        guard pointCount > 0 else { throw ScanImportError.emptyPointCloud }

        let baseTitle = fileURL.deletingPathExtension().lastPathComponent
        let metadata = makeMetadata(title: baseTitle, pointCount: pointCount, formatNote: formatNote)
        return try ScanStorage.saveImported(sourceURL: fileURL, metadata: metadata, format: format)
    }

    private static func importDirectory(_ dirURL: URL, depth: Int) throws -> SavedScan {
        if let saved = try tryImportScanContainer(dirURL) {
            return saved
        }

        let children = try FileManager.default.contentsOfDirectory(
            at: dirURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).filter { $0.lastPathComponent != "__MACOSX" }

        if let plyFile = children.first(where: { $0.pathExtension.lowercased() == "ply" }) {
            return try importPLYFile(plyFile)
        }
        if let xyzFile = children.first(where: { $0.pathExtension.lowercased() == "xyz" }) {
            return try importDelimitedTextFile(xyzFile, format: .xyz, formatNote: "XYZ text coordinates", parser: parseXYZLine)
        }
        if let csvFile = children.first(where: { $0.pathExtension.lowercased() == "csv" && $0.lastPathComponent.lowercased() != "gcps.csv" }) {
            return try importDelimitedTextFile(csvFile, format: .csv, formatNote: "CSV table coordinates", parser: parseCSVLine)
        }

        if depth < 2 {
            var lastError: Error?
            for child in children {
                let isDir = (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if isDir {
                    do {
                        return try importDirectory(child, depth: depth + 1)
                    } catch {
                        lastError = error
                    }
                }
            }
            if let lastError, !(lastError is ScanImportError) {
                throw lastError
            }
            if case .emptyPointCloud? = lastError as? ScanImportError {
                throw ScanImportError.emptyPointCloud
            }
        }

        throw ScanImportError.unsupportedFormat
    }

    private static func tryImportScanContainer(_ dirURL: URL) throws -> SavedScan? {
        let metadataURL = dirURL.appendingPathComponent("metadata.json")
        guard FileManager.default.fileExists(atPath: metadataURL.path) else { return nil }

        let hasPointFile = ExportFormat.allCases.contains {
            FileManager.default.fileExists(atPath: dirURL.appendingPathComponent($0.fileName).path)
        }
        guard hasPointFile else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try Data(contentsOf: metadataURL)
        let metadata = try decoder.decode(ScanMetadata.self, from: data)

        let base = try ScanStorage.root()
        let id = UUID().uuidString
        let staging = base.appendingPathComponent(".pending-" + id, isDirectory: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let cleanTitle = metadata.title.replacingOccurrences(of: "/", with: "-")
        let final = base.appendingPathComponent(formatter.string(from: Date()) + "_" + String(id.prefix(8)) + "_" + cleanTitle,
                                                isDirectory: true)
        do {
            try FileManager.default.copyItem(at: dirURL, to: staging)
            try FileManager.default.moveItem(at: staging, to: final)
            return SavedScan(directory: final, metadata: metadata)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    private static func importZIPArchive(_ zipURL: URL) throws -> SavedScan {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("import-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try ZipArchive.extract(from: zipURL, to: tempDir)
        return try importDirectory(tempDir, depth: 0)
    }

    private static func makeMetadata(title: String, pointCount: Int, formatNote: String) -> ScanMetadata {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.3.0"
        let appBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "5"

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
