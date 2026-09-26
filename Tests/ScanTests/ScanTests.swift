import XCTest
import PDFKit
import simd
@testable import LiDARScanner

final class ScanTests: XCTestCase {
    private func project() -> GaussianProject {
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        return GaussianProject(id: UUID(), startedAt: date, updatedAt: date, appVersion: "1.2.0", appBuild: "4",
                               device: "test-device", operatingSystem: "18.0")
    }
    private func frame() -> GaussianFrame {
        GaussianFrame(file_path: "images/frame_000000.jpg", w: 1920, h: 1440,
            fl_x: 1000, fl_y: 1001, cx: 960, cy: 720,
            transform_matrix: [[1,0,0,1], [0,1,0,2], [0,0,1,3], [0,0,0,1]],
            timestamp: 12.5, savedAt: Date(timeIntervalSince1970: 1_790_000_000), sha256: "fixture")
    }

    func testFrameSelectionKeepsFirstAndDistinctPoses() {
        let identity = matrix_identity_float4x4
        XCTAssertTrue(GaussianCapture.needsView(identity, after: nil))
        XCTAssertFalse(GaussianCapture.needsView(identity, after: identity))
        var moved = identity; moved.columns.3.x = 0.03
        XCTAssertTrue(GaussianCapture.needsView(moved, after: identity))
        let rotated = simd_float4x4(simd_quatf(angle: 0.1, axis: SIMD3(0, 1, 0)))
        XCTAssertTrue(GaussianCapture.needsView(rotated, after: identity))
    }

    func testDatasetPreservesSensorIntrinsicsAndRowMajorPose() throws {
        let manifest = GaussianDatasetManifest(ply_file_path: "points3D.ply", frames: [frame()])
        let data = try GaussianStore.encoder.encode(manifest)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let frames = try XCTUnwrap(json["frames"] as? [[String: Any]])
        XCTAssertEqual(json["camera_model"] as? String, "OPENCV")
        XCTAssertEqual(frames[0]["fl_x"] as? Double, 1000)
        XCTAssertEqual(frames[0]["transform_matrix"] as? [[Double]], [[1,0,0,1], [0,1,0,2], [0,0,1,3], [0,0,0,1]])
    }

    func testRecordedProfileSurvivesRoundTripWithoutReplacingDefaults() throws {
        var profile = GaussianProfile.automatic(frames: [frame()])
        profile.imageCacheMB = 256; profile.shDegree = 1
        let decoded = try GaussianStore.decoder.decode(GaussianProfile.self, from: GaussianStore.encoder.encode(profile))
        XCTAssertEqual(decoded, profile)
        XCTAssertEqual(GaussianProcessor.configuration(decoded).shDegree, 1)
        XCTAssertEqual(decoded.downscaleFactor, 2)
        XCTAssertGreaterThan(decoded.iterations, decoded.stopDensifyAt)
    }

    func testRecoveryUsesLastDurableCheckpointAndMaintainsAuditChain() throws {
        let p = project(); defer { try? FileManager.default.removeItem(at: p.directory) }
        var store: GaussianStore? = try GaussianStore(project: p)
        store?.project.phase = .training; store?.project.iteration = 145; store?.project.checkpointIteration = 100
        try store?.event("fixture_checkpoint", ["iteration": "100"]); try store?.save()
        let saved = try XCTUnwrap(store?.project); store = nil
        let recovered = try GaussianStore(project: saved, opening: true)
        XCTAssertEqual(recovered.project.phase, .paused)
        XCTAssertEqual(recovered.project.iteration, 100)
        XCTAssertNotNil(recovered.project.recoveryNote)
        let data = try Data(contentsOf: p.directory.appendingPathComponent("events.jsonl"))
        let last = try XCTUnwrap(data.split(separator: 10).last)
        let record = try GaussianStore.decoder.decode(GaussianStore.Record.self, from: Data(last))
        XCTAssertEqual(record.event.kind, "recovered")
        XCTAssertEqual(record.sha256, recovered.project.auditHead)
    }

    func testIncompleteFinalJournalLineIsReportedAndEarlierCorruptionRejected() throws {
        let p = project(); defer { try? FileManager.default.removeItem(at: p.directory) }
        var store: GaussianStore? = try GaussianStore(project: p)
        store?.project.phase = .captured; try store?.save()
        let saved = try XCTUnwrap(store?.project); store = nil
        let url = p.directory.appendingPathComponent("events.jsonl")
        let file = try FileHandle(forWritingTo: url); try file.seekToEnd(); try file.write(contentsOf: Data("{partial".utf8)); try file.close()
        var reopened: GaussianStore? = try GaussianStore(project: saved, opening: true)
        XCTAssertTrue(reopened?.project.recoveryNote?.contains("8 bytes") == true)
        reopened = nil
        var text = try String(contentsOf: url, encoding: .utf8)
        text = text.replacingOccurrences(of: "capture_created", with: "capture_changed")
        try text.write(to: url, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try GaussianStore(project: saved, opening: true))
    }

    func testChangedInputIsRejectedBeforeTraining() throws {
        var p = project(); defer { try? FileManager.default.removeItem(at: p.directory) }
        p.frames = [frame()]
        let store = try GaussianStore(project: p)
        try Data("changed-image".utf8).write(to: p.directory.appendingPathComponent(frame().file_path))
        XCTAssertThrowsError(try store.validateInputs())
    }

    func testPLYTruncationIsRejected() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ply")
        defer { try? FileManager.default.removeItem(at: url) }
        var data = Data("ply\nformat binary_little_endian 1.0\nelement vertex 2\nproperty float x\nend_header\n".utf8)
        data.append(Data(repeating: 0, count: 8)); try data.write(to: url)
        XCTAssertNoThrow(try GaussianProcessor.validatePLY(url, expected: 2))
        data.removeLast(); try data.write(to: url)
        XCTAssertThrowsError(try GaussianProcessor.validatePLY(url, expected: 2))
    }

    func testReportReflectsPartialStateAndPDFContainsFinalPage() throws {
        var p = project(); p.phase = .paused; p.frames = [frame()]; p.profile = .automatic(frames: p.frames)
        p.iteration = 100; p.checkpointIteration = 100; p.decisions = ["saved": 1, "interval": 20]
        let paragraphs = ScanReport.gaussianParagraphs(p)
        let body = paragraphs.joined(separator: "\n")
        XCTAssertTrue(body.contains(p.id.uuidString)); XCTAssertTrue(body.contains("100")); XCTAssertTrue(body.contains("paused"))
        let url = try ScanReport.pdf(paragraphs: paragraphs + ["FINAL-RECORD-TEST"], name: "Test")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let document = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertGreaterThan(document.pageCount, 1)
        XCTAssertTrue(document.string?.contains("FINAL-RECORD-TEST") == true)
        XCTAssertTrue(document.string?.contains(p.id.uuidString) == true)
    }

    func testCaptureExportProducesZIP() throws {
        let p = project(); defer { try? FileManager.default.removeItem(at: p.directory) }
        let store = try GaussianStore(project: p); try store.saveDataset()
        let zip = try store.exportInputs(); defer { try? FileManager.default.removeItem(at: zip.deletingLastPathComponent()) }
        let bytes = try Data(contentsOf: zip)
        XCTAssertEqual(Array(bytes.prefix(4)), [0x50, 0x4b, 0x03, 0x04])
    }
}
