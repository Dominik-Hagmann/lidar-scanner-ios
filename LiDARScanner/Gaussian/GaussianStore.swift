import Foundation
import CryptoKit

/// The archive and every mutation of one store are confined to the Gaussian worker.
final class GaussianStore {
    struct Event: Codable {
        let sequence: Int
        let timestamp: Date
        let kind: String
        let values: [String: String]
        let previousHash: String
    }
    struct Record: Codable {
        let event: Event
        let sha256: String
    }

    static var root: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GaussianScans", isDirectory: true)
    }
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
    static var decoder: JSONDecoder {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return decoder
    }
    var project: GaussianProject
    private var journal: FileHandle
    private var sequence = 0
    private var head = ""
    var directory: URL { project.directory }
    var checkpoint: URL { directory.appendingPathComponent("checkpoint-\(project.checkpointIteration).ckpt") }

    init(project: GaussianProject, opening: Bool = false) throws {
        self.project = project
        let fm = FileManager.default
        try fm.createDirectory(at: project.directory.appendingPathComponent("images"), withIntermediateDirectories: true)
        let journalURL = project.directory.appendingPathComponent("events.jsonl")
        if !fm.fileExists(atPath: journalURL.path) { fm.createFile(atPath: journalURL.path, contents: nil) }
        journal = try FileHandle(forUpdating: journalURL)
        if opening {
            let bytes = try Data(contentsOf: journalURL)
            var validBytes = 0
            // A killed process may leave one incomplete final record. Earlier corruption
            // is an error; it is never silently rewritten into a clean history.
            for line in bytes.split(separator: 10, omittingEmptySubsequences: false).dropLast() {
                let record = try Self.decoder.decode(Record.self, from: Data(line))
                guard record.event.sequence == sequence + 1, record.event.previousHash == head,
                      Self.hash(try Self.encoder.encode(record.event)) == record.sha256 else {
                    throw GaussianError.message(String(localized: "The scan log failed its integrity check."))
                }
                sequence = record.event.sequence; head = record.sha256
                validBytes += line.count + 1
            }
            if validBytes < bytes.count {
                try journal.truncate(atOffset: UInt64(validBytes))
                self.project.recoveryNote = "An incomplete final log record was removed after interruption (\(bytes.count - validBytes) bytes)."
            }
        }
        try journal.seekToEnd()
        if opening {
            if [.capturing, .preparing, .training].contains(project.phase) {
                self.project.phase = .paused
                self.project.iteration = project.checkpointIteration
                self.project.splatCount = project.checkpointSplatCount
                self.project.recoveryNote = "Recovered the last saved capture and checkpoint. Work after the last durable checkpoint may need to be repeated."
                try event("recovered", ["checkpointIteration": "\(project.checkpointIteration)"])
            }
            try save()
        } else {
            try event("capture_created", ["mode": "gaussian", "processing": "on-device", "network": "none"])
            try save()
        }
    }

    deinit { try? journal.close() }

    func event(_ kind: String, _ values: [String: String] = [:]) throws {
        let event = Event(sequence: sequence + 1, timestamp: Date(), kind: kind, values: values, previousHash: head)
        let digest = Self.hash(try Self.encoder.encode(event))
        var data = try Self.encoder.encode(Record(event: event, sha256: digest)); data.append(10)
        try journal.write(contentsOf: data)
        sequence += 1; head = digest
    }

    func decision(_ reason: String, timestamp: TimeInterval) throws {
        project.decisions[reason, default: 0] += 1
        try event("frame_decision", ["reason": reason, "arTimestamp": String(timestamp)])
    }

    func save() throws {
        project.updatedAt = Date(); project.auditHead = head
        try journal.synchronize()
        try Self.encoder.encode(project).write(to: directory.appendingPathComponent("scan.json"), options: .atomic)
    }

    func saveDataset() throws {
        let data = GaussianDatasetManifest(ply_file_path: project.seedFile,
                                           frames: project.frames)
        try Self.encoder.encode(data).write(to: directory.appendingPathComponent("transforms.json"), options: .atomic)
        try save()
    }

    /// Recoverable snapshots use rename on the same volume: the last valid file
    /// survives a full disk, cancellation, and process termination during a write.
    static func commit(_ temporary: URL, to destination: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: destination)
        }
    }

    static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func hashFile(_ url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
        var hash = SHA256()
        while let block = try file.read(upToCount: 1 << 20), !block.isEmpty { hash.update(data: block) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func list() throws -> [GaussianProject] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]).compactMap { directory in
                guard let data = try? Data(contentsOf: directory.appendingPathComponent("scan.json")) else { return nil }
                return try? decoder.decode(GaussianProject.self, from: data)
            }.sorted { $0.startedAt > $1.startedAt }
    }

    func validateInputs() throws {
        for frame in project.frames {
            guard try Self.hashFile(directory.appendingPathComponent(frame.file_path)) == frame.sha256 else {
                throw GaussianError.message(String(localized: "A saved image is missing or has changed. The original capture is required."))
            }
        }
        if let seedHash = project.seedHash, let seedFile = project.seedFile {
            guard try Self.hashFile(directory.appendingPathComponent(seedFile)) == seedHash else {
                throw GaussianError.message(String(localized: "The saved depth seed has changed."))
            }
        }
        try saveDataset()
    }

    func exportInputs() throws -> URL {
        let exportRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let capture = exportRoot.appendingPathComponent("Capture", isDirectory: true)
        try FileManager.default.createDirectory(at: capture, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: capture.appendingPathComponent("images"), withIntermediateDirectories: true)
        let names = ["transforms.json", "scan.json", "events.jsonl"] + project.frames.map(\.file_path) + [project.seedFile].compactMap { $0 }
        for name in names {
            let source = directory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: source.path) {
                try FileManager.default.copyItem(at: source, to: capture.appendingPathComponent(name))
            }
        }
        let output = exportRoot.appendingPathComponent("Capture-\(project.id.uuidString.prefix(8)).zip")
        var coordinatorError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: capture, options: .forUploading, error: &coordinatorError) { zipped in
            do { try FileManager.default.copyItem(at: zipped, to: output) } catch { copyError = error }
        }
        if let error = coordinatorError ?? (copyError as NSError?) { throw error }
        try FileManager.default.removeItem(at: capture)
        return output
    }
}
