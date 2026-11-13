import XCTest
import PDFKit
import SplatIO
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

    func testTorchServiceInitializationAndSafeFallback() {
        let torch = TorchService.shared
        XCTAssertFalse(torch.isOn)
        torch.setTorch(on: true, level: 0.8)
        if !torch.isAvailable {
            XCTAssertFalse(torch.isOn)
        }
        torch.toggle()
        torch.turnOff()
        XCTAssertFalse(torch.isOn)
    }

    func testParsePLYHeaderAndPreviewPoints() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let plyContent = """
        ply
        format ascii 1.0
        element vertex 3
        property float x
        property float y
        property float z
        property uchar red
        property uchar green
        property uchar blue
        end_header
        1.0 2.0 3.0 255 0 0
        4.0 5.0 6.0 0 255 0
        7.0 8.0 9.0 0 0 255
        """
        let plyURL = tempDir.appendingPathComponent("test.ply")
        try plyContent.write(to: plyURL, atomically: true, encoding: .utf8)

        let parsed = try XCTUnwrap(ScanImporter.parsePLYHeader(from: plyURL))
        XCTAssertEqual(parsed.vertexCount, 3)
        XCTAssertFalse(parsed.isBinary)
        XCTAssertTrue(parsed.hasColor)

        let points = ScanImporter.readPreviewPoints(from: plyURL, maxPoints: 10)
        XCTAssertEqual(points.count, 3)
        XCTAssertEqual(points[0].x, 1.0)
        XCTAssertEqual(points[0].r, 255)
    }

    func testImportScanPLYCreatesCompliantSavedScan() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let plyContent = """
        ply
        format ascii 1.0
        element vertex 2
        property float x
        property float y
        property float z
        end_header
        0.5 1.0 1.5
        2.0 2.5 3.0
        """
        let sourceURL = tempDir.appendingPathComponent("imported_cloud.ply")
        try plyContent.write(to: sourceURL, atomically: true, encoding: .utf8)

        let saved = try ScanImporter.importScan(from: sourceURL)
        defer { try? FileManager.default.removeItem(at: saved.directory) }

        XCTAssertTrue(FileManager.default.fileExists(atPath: saved.url(for: .asciiPLY).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: saved.url(for: .binaryPLY).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: saved.metadataURL.path))
        XCTAssertEqual(saved.metadata.pointCount, 2)
        XCTAssertEqual(saved.metadata.title, "imported_cloud")
        XCTAssertTrue(try ScanStorage.list().contains(where: { $0.id == saved.id }))
        XCTAssertEqual(ScanStorage.readPreview(for: saved).count, 2)
    }

    func testBinaryPLYWithNegativeCoordinatesAndPackedRGBParsesCorrectly() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // 15-byte packed stride (float x,y,z + uchar r,g,b) with negative coordinates producing bytes >= 0x80
        var data = Data("""
        ply\r
        format binary_little_endian 1.0\r
        element vertex 2\r
        property float x\r
        property float y\r
        property float z\r
        property uchar red\r
        property uchar green\r
        property uchar blue\r
        end_header\r\n
        """.utf8)
        func appendLE(_ value: Float) {
            var bits = value.bitPattern.littleEndian
            withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
        }
        appendLE(-1.2345); appendLE(-2.5); appendLE(3.25)
        data.append(contentsOf: [10, 20, 30])
        appendLE(4.5); appendLE(5.5); appendLE(-6.75)
        data.append(contentsOf: [200, 100, 50])

        let plyURL = tempDir.appendingPathComponent("packed_negative.ply")
        try data.write(to: plyURL)

        let header = try XCTUnwrap(ScanImporter.parsePLYHeader(from: plyURL))
        XCTAssertEqual(header.vertexCount, 2)
        XCTAssertTrue(header.isBinary)
        XCTAssertTrue(header.hasColor)

        let pts = ScanImporter.readPreviewPoints(from: plyURL, maxPoints: 10)
        XCTAssertEqual(pts.count, 2)
        XCTAssertEqual(pts[0].x, -1.2345, accuracy: 0.0001)
        XCTAssertEqual(pts[0].y, 3.25, accuracy: 0.0001)
        XCTAssertEqual(pts[0].z, 2.5, accuracy: 0.0001)
        XCTAssertEqual(pts[0].r, 10)
        XCTAssertEqual(pts[1].x, 4.5, accuracy: 0.0001)
        XCTAssertEqual(pts[1].g, 100)
    }

    func testASCIIPLYAndXYZMultipleWhitespaceParsing() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let plyURL = tempDir.appendingPathComponent("spaced.ply")
        try """
        ply
        format ascii 1.0
        element vertex 2
        property float x
        property float y
        property float z
        property uchar red
        property uchar green
        property uchar blue
        end_header
          1.0   2.0\t3.0  12 34 56
        -1.0  0.5  -2.5  255 128 0
        """.write(to: plyURL, atomically: true, encoding: .utf8)

        let plyPoints = ScanImporter.readPoints(from: plyURL, maxPoints: nil)
        XCTAssertEqual(plyPoints.count, 2)
        XCTAssertEqual(plyPoints[0].r, 12)
        XCTAssertEqual(plyPoints[1].x, -1.0)

        let xyzURL = tempDir.appendingPathComponent("spaced.xyz")
        try """
        # Header comment
        1.5   -2.5   3.5
          4.0\t5.0  -6.0
        """.write(to: xyzURL, atomically: true, encoding: .utf8)

        let savedXYZ = try ScanImporter.importScan(from: xyzURL)
        defer { try? FileManager.default.removeItem(at: savedXYZ.directory) }
        XCTAssertEqual(savedXYZ.existingFormats, [.xyz])
        XCTAssertTrue(try ScanStorage.list().contains(where: { $0.id == savedXYZ.id }))
        let loaded = ScanStorage.readAllPoints(for: savedXYZ)
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[0].x, 1.5, accuracy: 0.001)
    }

    func testImportZIPArchivePointCloudAndGaussianProject() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = tempDir.appendingPathComponent("BundleFolder", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let plyURL = folder.appendingPathComponent("zipped.ply")
        try """
        ply
        format ascii 1.0
        element vertex 2
        property float x
        property float y
        property float z
        end_header
        1 2 3
        4 5 6
        """.write(to: plyURL, atomically: true, encoding: .utf8)

        let zipURL = tempDir.appendingPathComponent("Bundle.zip")
        var coordError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: .forUploading, error: &coordError) { producedZip in
            do { try FileManager.default.copyItem(at: producedZip, to: zipURL) } catch { copyError = error }
        }
        if let err = coordError ?? (copyError as NSError?) { throw err }

        let importedCloud = try ScanImporter.importScan(from: zipURL)
        defer { try? FileManager.default.removeItem(at: importedCloud.directory) }
        XCTAssertEqual(importedCloud.metadata.title, "zipped")
        XCTAssertEqual(ScanStorage.readAllPoints(for: importedCloud).count, 2)

        // Also test Gaussian capture ZIP export -> delete original -> re-import into GaussianStore
        let p = project()
        let store = try GaussianStore(project: p)
        try store.saveDataset()
        let captureZIP = try store.exportInputs()
        defer { try? FileManager.default.removeItem(at: captureZIP.deletingLastPathComponent()) }
        try? FileManager.default.removeItem(at: GaussianStore.root)

        let reimported = try GaussianStore.importProject(from: captureZIP)
        defer { try? FileManager.default.removeItem(at: reimported.directory) }
        XCTAssertEqual(reimported.id, p.id)
        XCTAssertTrue(try GaussianStore.list().contains(where: { $0.id == p.id }))
    }

    func testZipPathTraversalIsRejected() throws {
        let name = Data("../evil.ply".utf8)
        var local = Data()
        func appendLE16(_ d: inout Data, _ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        func appendLE32(_ d: inout Data, _ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }

        appendLE32(&local, 0x0403_4b50)
        appendLE16(&local, 20); appendLE16(&local, 0); appendLE16(&local, 0)
        appendLE16(&local, 0); appendLE16(&local, 0)
        appendLE32(&local, 0); appendLE32(&local, 0); appendLE32(&local, 0)
        appendLE16(&local, UInt16(name.count)); appendLE16(&local, 0)
        local.append(name)

        let cdOffset = UInt32(local.count)
        var cd = Data()
        appendLE32(&cd, 0x0201_4b50)
        appendLE16(&cd, 20); appendLE16(&cd, 20); appendLE16(&cd, 0); appendLE16(&cd, 0)
        appendLE16(&cd, 0); appendLE16(&cd, 0)
        appendLE32(&cd, 0); appendLE32(&cd, 0); appendLE32(&cd, 0)
        appendLE16(&cd, UInt16(name.count)); appendLE16(&cd, 0); appendLE16(&cd, 0)
        appendLE16(&cd, 0); appendLE16(&cd, 0); appendLE32(&cd, 0); appendLE32(&cd, 0)
        cd.append(name)

        var eocd = Data()
        appendLE32(&eocd, 0x0605_4b50)
        appendLE16(&eocd, 0); appendLE16(&eocd, 0)
        appendLE16(&eocd, 1); appendLE16(&eocd, 1)
        appendLE32(&eocd, UInt32(cd.count)); appendLE32(&eocd, cdOffset); appendLE16(&eocd, 0)

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let zipURL = tempDir.appendingPathComponent("traversal.zip")
        try (local + cd + eocd).write(to: zipURL)

        XCTAssertThrowsError(try ZipArchive.extract(from: zipURL, to: tempDir.appendingPathComponent("out")))
    }

    func testScanModelModeSwitchingPreservesSessionWhenNoPoints() {
        let model = ScanModel()
        XCTAssertFalse(model.sessionClosed)
        XCTAssertEqual(model.pointCount, 0)
        model.leaveMode()
        XCTAssertFalse(model.sessionClosed)
        model.enterMode()
        XCTAssertFalse(model.sessionClosed)
        XCTAssertFalse(model.isBusy)
        XCTAssertFalse(model.isRecording)
    }

    func testGaussianModelResilienceWhenStoreNil() {
        let model = GaussianModel()
        XCTAssertFalse(model.isBusy)
        XCTAssertFalse(model.processingActive)
        model.resume()
        XCTAssertFalse(model.isBusy)
        XCTAssertFalse(model.processingActive)
        model.share(.scene)
        XCTAssertFalse(model.isBusy)
        model.leaveMode()
        XCTAssertFalse(model.cameraReady)
        model.enterMode()
        XCTAssertFalse(model.isBusy)
    }

    func testSettingsRemainConfigurable() {
        let model = ScanModel()
        model.settings.voxelCentimeters = 2.0
        XCTAssertEqual(model.settings.voxelCentimeters, 2.0)
        model.exportFormat = .asciiPLY
        XCTAssertEqual(model.exportFormat, .asciiPLY)
        XCTAssertFalse(model.isBusy)
        XCTAssertFalse(model.isRecording)
    }

    func testPointCloudReportGeneration() throws {
        let metadata = ScanMetadata(
            schemaVersion: 1, appVersion: "1.2.0", appBuild: "4", scanID: UUID(),
            title: "Test Scan", startedAt: Date(), savedAt: Date(), pointCount: 1500,
            acceptedSamples: 1500, processedFrames: 30, activeSeconds: 12.5,
            settings: ScanSettings(), deviceModel: "iPhone", systemVersion: "18.0",
            depthWidth: 256, depthHeight: 192, unit: "metre",
            coordinateSystem: "Local", arkitToExportRowMajor: [1,0,0,0, 0,0,-1,0, 0,1,0,0, 0,0,0,1],
            depthSource: "ARFrame.sceneDepth", confidenceMeaning: "0,1,2",
            pointSelection: "voxel", colorSource: "camera", sessionNote: "Test note"
        )
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let saved = SavedScan(directory: dir, metadata: metadata)
        let url = try ScanReport.pointCloud(saved)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let doc = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertGreaterThan(doc.pageCount, 0)
        XCTAssertTrue(doc.string?.contains("Test Scan") == true)
    }

    func testPCPointToSplatPointsConversion() {
        let p1 = PCPoint(x: 1.0, y: 2.0, z: 3.0, r: 255, g: 128, b: 64, confidence: 2)
        let p2 = PCPoint(x: 1.1, y: 2.1, z: 3.1, r: 0, g: 255, b: 128, confidence: 1)
        let splats = PCPoint.toSplatPoints([p1, p2])
        XCTAssertEqual(splats.count, 2)
        XCTAssertEqual(splats[0].position.x, 1.0, accuracy: 0.001)
        XCTAssertEqual(splats[0].position.y, 2.0, accuracy: 0.001)
        XCTAssertEqual(splats[0].position.z, 3.0, accuracy: 0.001)
        XCTAssertEqual(splats[0].color.asSRGBUInt8.x, 255)
        XCTAssertEqual(splats[0].color.asSRGBUInt8.y, 128)
        XCTAssertEqual(splats[0].color.asSRGBUInt8.z, 64)
        XCTAssertGreaterThan(splats[0].scale.asLinearFloat.x, 0.005)
        XCTAssertLessThan(splats[0].scale.asLinearFloat.x, 0.05)
    }

    func testGaussianPLYExportAndReadBack() async throws {
        let points = [
            PCPoint(x: 0.0, y: 0.0, z: 1.0, r: 255, g: 0, b: 0, confidence: 2),
            PCPoint(x: 0.1, y: 0.2, z: 1.1, r: 0, g: 255, b: 0, confidence: 2),
            PCPoint(x: -0.1, y: 0.1, z: 1.2, r: 0, g: 0, b: 255, confidence: 2)
        ]
        let splats = PCPoint.toSplatPoints(points)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ply")
        defer { try? FileManager.default.removeItem(at: url) }

        let writer = try SplatPLYSceneWriter(to: .file(url))
        try await writer.start(sphericalHarmonicDegree: 0, binary: true, pointCount: splats.count)
        try await writer.write(splats)
        try await writer.close()

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let reader = try AutodetectSceneReader(url)
        let readPoints = try await reader.readAll()
        XCTAssertEqual(readPoints.count, 3)
        XCTAssertEqual(readPoints[0].position.x, 0.0, accuracy: 0.001)
        XCTAssertEqual(readPoints[0].position.y, 0.0, accuracy: 0.001)
        XCTAssertEqual(readPoints[0].position.z, 1.0, accuracy: 0.001)
    }

    func testEnglishAndGermanLocalizationsAreCompleteAndLoadable() throws {
        let bundle = Bundle.main
        XCTAssertTrue(bundle.localizations.contains("en"), "Missing en localization in app bundle")
        XCTAssertTrue(bundle.localizations.contains("de"), "Missing de localization in app bundle")

        let enPath = try XCTUnwrap(bundle.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: "en"))
        let dePath = try XCTUnwrap(bundle.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: "de"))
        let enDict = try XCTUnwrap(NSDictionary(contentsOfFile: enPath) as? [String: String])
        let deDict = try XCTUnwrap(NSDictionary(contentsOfFile: dePath) as? [String: String])

        XCTAssertFalse(enDict.isEmpty)
        XCTAssertEqual(Set(enDict.keys), Set(deDict.keys))

        XCTAssertEqual(deDict["%@ / %@ points"], "%@ / %@ Punkte")
        XCTAssertEqual(deDict["Mode"], "Modus")
        XCTAssertEqual(deDict["Export Options"], "Exportoptionen")
        XCTAssertEqual(deDict["Rotate with One Finger · Pinch to Zoom"], "Drehen mit einem Finger · Aufziehen zum Zoomen")
        XCTAssertEqual(deDict["Preview points: %@ of %@. The export contains all points."], "Punkte in der Vorschau: %@ von %@. Export enthält alle Punkte.")
        XCTAssertEqual(deDict["About & Credits"], "Über & Danksagung")
    }
}
