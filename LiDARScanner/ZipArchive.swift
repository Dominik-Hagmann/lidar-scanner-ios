import Foundation
import zlib

enum ZipArchiveError: LocalizedError {
    case invalidArchive
    case encryptedArchive
    case unsupportedCompression(UInt16)
    case unsafePath(String)
    case corruptedEntry(String)
    case sizeLimitExceeded

    var errorDescription: String? {
        switch self {
        case .invalidArchive:
            return LanguageManager.string("The ZIP archive is invalid or damaged.")
        case .encryptedArchive:
            return LanguageManager.string("Encrypted ZIP archives are not supported.")
        case .unsupportedCompression(let method):
            return LanguageManager.format("Unsupported ZIP compression method (%d).", Int(method))
        case .unsafePath(let path):
            return LanguageManager.format("ZIP archive contains an unsafe path: %@", path)
        case .corruptedEntry(let name):
            return LanguageManager.format("ZIP entry could not be extracted: %@", name)
        case .sizeLimitExceeded:
            return LanguageManager.string("ZIP archive exceeds the allowed extraction limit.")
        }
    }
}

enum ZipArchive {
    private static let eocdSignature: UInt32 = 0x0605_4b50
    private static let centralHeaderSignature: UInt32 = 0x0201_4b50
    private static let localHeaderSignature: UInt32 = 0x0403_4b50
    private static let maxEntries = 20_000
    private static let maxTotalUncompressedBytes: UInt64 = 2_000_000_000
    private static let maxArchiveBytes = 1_500_000_000

    /// Extracts all regular entries from a `.zip` file into `destinationURL` using zlib.
    static func extract(from zipURL: URL, to destinationURL: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: zipURL.path)
        if let fileSize = attributes[.size] as? NSNumber, fileSize.intValue > maxArchiveBytes {
            throw ZipArchiveError.sizeLimitExceeded
        }

        let data = try Data(contentsOf: zipURL, options: .mappedIfSafe)
        let eocdOffset = try findEOCDOffset(in: data)

        let diskNumber: UInt16 = readLE(data, at: eocdOffset + 4)
        let cdDisk: UInt16 = readLE(data, at: eocdOffset + 6)
        guard diskNumber == 0, cdDisk == 0 else {
            throw ZipArchiveError.invalidArchive
        }

        let entryCount = Int(readLE(data, at: eocdOffset + 10) as UInt16)
        let cdSize = Int(readLE(data, at: eocdOffset + 12) as UInt32)
        let cdOffset = Int(readLE(data, at: eocdOffset + 16) as UInt32)

        guard entryCount != Int(UInt16.max), cdOffset != Int(UInt32.max), cdSize != Int(UInt32.max) else {
            throw ZipArchiveError.sizeLimitExceeded
        }
        guard entryCount <= maxEntries,
              cdOffset >= 0, cdSize >= 0,
              cdOffset + cdSize <= data.count else {
            throw ZipArchiveError.invalidArchive
        }

        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        let resolvedDestRoot = destinationURL.standardizedFileURL.path

        var cursor = cdOffset
        let cdEnd = cdOffset + cdSize
        var totalExtractedBytes: UInt64 = 0

        for _ in 0..<entryCount {
            guard cursor + 46 <= cdEnd,
                  readLE(data, at: cursor) as UInt32 == centralHeaderSignature else {
                throw ZipArchiveError.invalidArchive
            }

            let flags: UInt16 = readLE(data, at: cursor + 8)
            let method: UInt16 = readLE(data, at: cursor + 10)
            let expectedCRC: UInt32 = readLE(data, at: cursor + 16)
            let compressedSize = Int(readLE(data, at: cursor + 20) as UInt32)
            let uncompressedSize = Int(readLE(data, at: cursor + 24) as UInt32)
            let nameLen = Int(readLE(data, at: cursor + 28) as UInt16)
            let extraLen = Int(readLE(data, at: cursor + 30) as UInt16)
            let commentLen = Int(readLE(data, at: cursor + 32) as UInt16)
            let externalAttrs: UInt32 = readLE(data, at: cursor + 38)
            let localOffset = Int(readLE(data, at: cursor + 42) as UInt32)

            let nameStart = cursor + 46
            let nextCursor = nameStart + nameLen + extraLen + commentLen
            guard nextCursor <= cdEnd else { throw ZipArchiveError.invalidArchive }
            cursor = nextCursor

            guard (flags & 0x0001) == 0 else {
                throw ZipArchiveError.encryptedArchive
            }

            let nameData = data.subdata(in: nameStart..<(nameStart + nameLen))
            let rawName = String(data: nameData, encoding: .utf8) ?? String(data: nameData, encoding: .isoLatin1) ?? ""
            let normalizedName = rawName.replacingOccurrences(of: "\\", with: "/")

            if shouldSkipMetadataEntry(normalizedName) {
                continue
            }

            let sanitizedPath = try sanitizeRelativePath(normalizedName)
            guard !sanitizedPath.isEmpty else { continue }

            let targetURL = destinationURL.appendingPathComponent(sanitizedPath).standardizedFileURL
            let rootPrefix = resolvedDestRoot.hasSuffix("/") ? resolvedDestRoot : resolvedDestRoot + "/"
            guard targetURL.path == resolvedDestRoot || targetURL.path.hasPrefix(rootPrefix) else {
                throw ZipArchiveError.unsafePath(normalizedName)
            }

            let isDirectory = normalizedName.hasSuffix("/") || ((externalAttrs & 0x10) != 0 && uncompressedSize == 0)
            if isDirectory {
                try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: true)
                continue
            }

            let nextTotal = totalExtractedBytes + UInt64(max(0, uncompressedSize))
            guard nextTotal <= maxTotalUncompressedBytes else {
                throw ZipArchiveError.sizeLimitExceeded
            }
            totalExtractedBytes = nextTotal

            guard localOffset + 30 <= data.count,
                  readLE(data, at: localOffset) as UInt32 == localHeaderSignature else {
                throw ZipArchiveError.corruptedEntry(sanitizedPath)
            }
            let localNameLen = Int(readLE(data, at: localOffset + 26) as UInt16)
            let localExtraLen = Int(readLE(data, at: localOffset + 28) as UInt16)
            let payloadStart = localOffset + 30 + localNameLen + localExtraLen
            let payloadEnd = payloadStart + compressedSize
            guard payloadStart >= 0, payloadEnd <= data.count else {
                throw ZipArchiveError.corruptedEntry(sanitizedPath)
            }

            let compressedSlice = data.subdata(in: payloadStart..<payloadEnd)
            let output = try decompress(compressedSlice, method: method, expectedSize: uncompressedSize,
                                          expectedCRC: expectedCRC, entryName: sanitizedPath)
            try FileManager.default.createDirectory(at: targetURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try output.write(to: targetURL, options: .atomic)
        }
    }

    private static func findEOCDOffset(in data: Data) throws -> Int {
        guard data.count >= 22 else { throw ZipArchiveError.invalidArchive }
        let searchMin = max(0, data.count - (65_535 + 22))
        var pos = data.count - 22
        while pos >= searchMin {
            if readLE(data, at: pos) as UInt32 == eocdSignature {
                let commentLen = Int(readLE(data, at: pos + 20) as UInt16)
                if pos + 22 + commentLen == data.count {
                    return pos
                }
            }
            pos -= 1
        }
        throw ZipArchiveError.invalidArchive
    }

    private static func shouldSkipMetadataEntry(_ path: String) -> Bool {
        let components = path.split(separator: "/")
        guard !components.isEmpty else { return true }
        if components.first == "__MACOSX" { return true }
        if let last = components.last, last.hasPrefix("._") || last == ".DS_Store" {
            return true
        }
        return false
    }

    private static func sanitizeRelativePath(_ path: String) throws -> String {
        if path.hasPrefix("/") || path.hasPrefix("~") {
            throw ZipArchiveError.unsafePath(path)
        }
        var kept: [String] = []
        for part in path.split(separator: "/") {
            let segment = String(part)
            if segment == "." || segment.isEmpty { continue }
            if segment == ".." || segment.contains(":") {
                throw ZipArchiveError.unsafePath(path)
            }
            kept.append(segment)
        }
        return kept.joined(separator: "/")
    }

    private static func decompress(_ input: Data, method: UInt16, expectedSize: Int,
                                   expectedCRC: UInt32, entryName: String) throws -> Data {
        let output: Data
        switch method {
        case 0:
            guard input.count == expectedSize else {
                throw ZipArchiveError.corruptedEntry(entryName)
            }
            output = input
        case 8:
            if expectedSize == 0, input.isEmpty {
                output = Data()
            } else {
                output = try inflateRawDeflate(input, expectedSize: expectedSize, entryName: entryName)
            }
        default:
            throw ZipArchiveError.unsupportedCompression(method)
        }

        let actualCRC = output.withUnsafeBytes { raw -> UInt32 in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: Bytef.self) else { return 0 }
            return UInt32(zlib.crc32(0, base, uInt(raw.count)))
        }
        guard actualCRC == expectedCRC else {
            throw ZipArchiveError.corruptedEntry(entryName)
        }
        return output
    }

    private static func inflateRawDeflate(_ input: Data, expectedSize: Int, entryName: String) throws -> Data {
        var stream = z_stream()
        let initStatus = inflateInit2_(&stream, -MAX_WBITS, zlibVersion(), Int32(MemoryLayout<z_stream>.size))
        guard initStatus == Z_OK else {
            throw ZipArchiveError.corruptedEntry(entryName)
        }
        defer { inflateEnd(&stream) }

        var output = Data(count: max(expectedSize, 4096))
        var status: Int32 = Z_OK
        try input.withUnsafeBytes { rawInput in
            guard let inputPtr = rawInput.baseAddress?.assumingMemoryBound(to: Bytef.self) else { return }
            stream.next_in = UnsafeMutablePointer(mutating: inputPtr)
            stream.avail_in = uInt(rawInput.count)

            while true {
                let totalOut = Int(stream.total_out)
                if totalOut >= output.count {
                    output.count += max(65_536, output.count / 2)
                }
                let availableOut = output.count - totalOut
                output.withUnsafeMutableBytes { rawOutput in
                    guard let outBase = rawOutput.baseAddress?.assumingMemoryBound(to: Bytef.self) else { return }
                    stream.next_out = outBase.advanced(by: totalOut)
                    stream.avail_out = uInt(availableOut)
                    status = zlib.inflate(&stream, Z_NO_FLUSH)
                }
                if status == Z_STREAM_END { break }
                if status != Z_OK { throw ZipArchiveError.corruptedEntry(entryName) }
                if stream.avail_in == 0 && stream.avail_out > 0 { break }
            }
        }

        guard status == Z_STREAM_END else {
            throw ZipArchiveError.corruptedEntry(entryName)
        }
        output.count = Int(stream.total_out)
        if expectedSize > 0 && output.count != expectedSize {
            throw ZipArchiveError.corruptedEntry(entryName)
        }
        return output
    }

    static func createArchive(entries: [(path: String, data: Data)], to destinationURL: URL) throws {
        var archiveData = Data()
        var centralDirectory = Data()
        let (dosTime, dosDate) = currentDOSDateTime()
        let utf8Flag: UInt16 = 0x0800

        for entry in entries {
            let nameData = Data(entry.path.utf8)
            let rawData = entry.data
            let crc = computeCRC32(rawData)
            let deflated = compressRawDeflate(rawData)
            let useDeflate = deflated != nil && (deflated?.count ?? Int.max) < rawData.count
            let method: UInt16 = useDeflate ? 8 : 0
            let payload = useDeflate ? (deflated ?? rawData) : rawData
            let localHeaderOffset = UInt32(archiveData.count)

            // Local file header
            appendLE(&archiveData, localHeaderSignature)
            appendLE(&archiveData, UInt16(20)) // version needed
            appendLE(&archiveData, utf8Flag)
            appendLE(&archiveData, method)
            appendLE(&archiveData, dosTime)
            appendLE(&archiveData, dosDate)
            appendLE(&archiveData, crc)
            appendLE(&archiveData, UInt32(payload.count))
            appendLE(&archiveData, UInt32(rawData.count))
            appendLE(&archiveData, UInt16(nameData.count))
            appendLE(&archiveData, UInt16(0)) // extra length
            archiveData.append(nameData)
            archiveData.append(payload)

            // Central directory header
            appendLE(&centralDirectory, centralHeaderSignature)
            appendLE(&centralDirectory, UInt16(20)) // version made by
            appendLE(&centralDirectory, UInt16(20)) // version needed
            appendLE(&centralDirectory, utf8Flag)
            appendLE(&centralDirectory, method)
            appendLE(&centralDirectory, dosTime)
            appendLE(&centralDirectory, dosDate)
            appendLE(&centralDirectory, crc)
            appendLE(&centralDirectory, UInt32(payload.count))
            appendLE(&centralDirectory, UInt32(rawData.count))
            appendLE(&centralDirectory, UInt16(nameData.count))
            appendLE(&centralDirectory, UInt16(0)) // extra length
            appendLE(&centralDirectory, UInt16(0)) // comment length
            appendLE(&centralDirectory, UInt16(0)) // disk number start
            appendLE(&centralDirectory, UInt16(0)) // internal attrs
            appendLE(&centralDirectory, UInt32(0)) // external attrs
            appendLE(&centralDirectory, localHeaderOffset)
            centralDirectory.append(nameData)
        }

        let cdOffset = UInt32(archiveData.count)
        archiveData.append(centralDirectory)

        // End of central directory record
        appendLE(&archiveData, eocdSignature)
        appendLE(&archiveData, UInt16(0))
        appendLE(&archiveData, UInt16(0))
        appendLE(&archiveData, UInt16(entries.count))
        appendLE(&archiveData, UInt16(entries.count))
        appendLE(&archiveData, UInt32(centralDirectory.count))
        appendLE(&archiveData, cdOffset)
        appendLE(&archiveData, UInt16(0))

        try archiveData.write(to: destinationURL, options: .atomic)
    }

    private static func computeCRC32(_ data: Data) -> UInt32 {
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: Bytef.self) else { return 0 }
            return UInt32(zlib.crc32(0, base, uInt(raw.count)))
        }
    }

    private static func compressRawDeflate(_ input: Data) -> Data? {
        guard !input.isEmpty else { return Data() }
        var stream = z_stream()
        let status = deflateInit2_(
            &stream,
            Z_DEFAULT_COMPRESSION,
            Z_DEFLATED,
            -MAX_WBITS,
            8,
            Z_DEFAULT_STRATEGY,
            zlibVersion(),
            Int32(MemoryLayout<z_stream>.size)
        )
        guard status == Z_OK else { return nil }
        defer { deflateEnd(&stream) }

        var output = Data(count: max(64, Int(deflateBound(&stream, uLong(input.count)))))
        var finishStatus: Int32 = Z_OK
        input.withUnsafeBytes { rawInput in
            guard let inBase = rawInput.baseAddress?.assumingMemoryBound(to: Bytef.self) else { return }
            stream.next_in = UnsafeMutablePointer(mutating: inBase)
            stream.avail_in = uInt(rawInput.count)
            output.withUnsafeMutableBytes { rawOutput in
                guard let outBase = rawOutput.baseAddress?.assumingMemoryBound(to: Bytef.self) else { return }
                stream.next_out = outBase
                stream.avail_out = uInt(rawOutput.count)
                finishStatus = zlib.deflate(&stream, Z_FINISH)
            }
        }
        guard finishStatus == Z_STREAM_END else { return nil }
        output.count = Int(stream.total_out)
        return output
    }

    private static func currentDOSDateTime() -> (UInt16, UInt16) {
        let cal = Calendar(identifier: .gregorian)
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date())
        let year = max(1980, c.year ?? 2026) - 1980
        let month = c.month ?? 1
        let day = c.day ?? 1
        let hour = c.hour ?? 0
        let minute = c.minute ?? 0
        let second = (c.second ?? 0) / 2
        let dosTime = UInt16((hour << 11) | (minute << 5) | second)
        let dosDate = UInt16((year << 9) | (month << 5) | day)
        return (dosTime, dosDate)
    }

    private static func appendLE<T: FixedWidthInteger>(_ data: inout Data, _ value: T) {
        var le = value.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }

    private static func readLE<T: FixedWidthInteger>(_ data: Data, at offset: Int) -> T {
        var value: T = 0
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress, offset + MemoryLayout<T>.size <= raw.count else { return }
            memcpy(&value, base.advanced(by: offset), MemoryLayout<T>.size)
        }
        return T(littleEndian: value)
    }
}
