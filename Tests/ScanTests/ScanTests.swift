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
        XCTAssertTrue(body.contains(p.id.uuidString)); XCTAssertTrue(body.contains("100")); XCTAssertTrue(body.contains(p.phase.title))
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
        XCTAssertEqual(deDict["Rotate with One Finger · Pinch to Zoom"], "Drehen mit einem Finger · Aufziehen zum Zoomen")
        XCTAssertEqual(deDict["Preview points: %@ of %@. The export contains all points."], "Punkte in der Vorschau: %@ von %@. Export enthält alle Punkte.")
        XCTAssertEqual(deDict["About & Credits"], "Über & Danksagung")
        XCTAssertEqual(deDict["Language"], "Sprache")
    }

    func testLanguageManagerSwitchesBetweenGermanAndEnglish() {
        let manager = LanguageManager.shared
        let previous = manager.selection
        defer { manager.selection = previous }

        manager.selection = .german
        XCTAssertEqual(LanguageManager.string("Settings"), "Einstellungen")
        XCTAssertEqual(LanguageManager.string("Language"), "Sprache")
        XCTAssertEqual(L10nPhrase("Imported scan: %@", ["Test"]).localized, "Scan importiert: Test")

        manager.selection = .english
        XCTAssertEqual(LanguageManager.string("Settings"), "Settings")
        XCTAssertEqual(LanguageManager.string("Language"), "Language")
        XCTAssertEqual(L10nPhrase("Imported scan: %@", ["Test"]).localized, "Imported scan: Test")
    }

    func testScanSettingsBackwardCompatibleDecoding() throws {
        let legacyJSON = #"{"voxelCentimeters":2,"maxDepth":3,"minConfidence":2,"pixelStep":4,"maxPoints":500000}"#
        let decoded = try JSONDecoder().decode(ScanSettings.self, from: Data(legacyJSON.utf8))
        XCTAssertEqual(decoded.voxelCentimeters, 2)
        XCTAssertEqual(decoded.maxDepth, 3)
        XCTAssertEqual(decoded.minConfidence, 2)
        XCTAssertEqual(decoded.pixelStep, 4)
        XCTAssertEqual(decoded.maxPoints, 500_000)
        XCTAssertTrue(decoded.recordLocation)

        var custom = ScanSettings()
        custom.recordLocation = false
        let roundtrip = try JSONDecoder().decode(ScanSettings.self, from: JSONEncoder().encode(custom))
        XCTAssertFalse(roundtrip.recordLocation)
    }

    func testAllExportFormatsHaveDistinctIDsAndFileNames() {
        XCTAssertEqual(ExportFormat.allCases.count, 7)
        XCTAssertEqual(Set(ExportFormat.allCases.map(\.rawValue)).count, 7)
        XCTAssertEqual(Set(ExportFormat.allCases.map(\.fileName)).count, 7)
        XCTAssertEqual(ExportFormat.csv.fileName, "points.csv")
        XCTAssertEqual(ExportFormat.las.fileName, "points.las")
        XCTAssertEqual(ExportFormat.laz.fileName, "points.laz")
        XCTAssertEqual(ExportFormat.e57.fileName, "points.e57")
    }

    func testCSVReadAndGroundControlPointsPersistenceAndReport() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let csvURL = tempDir.appendingPathComponent("points.csv")
        let csvContent = "x,y,z,red,green,blue,confidence\n1.500,-2.000,0.750,255,128,64,2\n-0.250,3.000,1.250,10,20,30,1\n"
        try csvContent.write(to: csvURL, atomically: true, encoding: .utf8)

        let points = ScanImporter.readPoints(from: csvURL, formatHint: .csv, maxPoints: nil)
        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points[0].x, 1.5, accuracy: 0.001)
        XCTAssertEqual(points[0].y, 0.75, accuracy: 0.001)
        XCTAssertEqual(points[0].z, 2.0, accuracy: 0.001)
        XCTAssertEqual(points[0].r, 255)
        XCTAssertEqual(points[0].confidence, 2)

        let gcp = GroundControlPoint.fromARKit(
            SIMD3<Float>(points[0].x, points[0].y, points[0].z),
            label: "GCP-1",
            targetX: 602_500.125,
            targetY: 5_340_120.5,
            targetZ: 172.4,
            coordinateSystem: "EPSG:31256",
            note: "Trench NW"
        )
        XCTAssertEqual(gcp.localX, 1.5, accuracy: 0.001)
        XCTAssertEqual(gcp.localY, -2.0, accuracy: 0.001)
        XCTAssertEqual(gcp.localZ, 0.75, accuracy: 0.001)
        XCTAssertEqual(gcp.arkitPosition.x, points[0].x, accuracy: 0.001)
        XCTAssertEqual(gcp.arkitPosition.y, points[0].y, accuracy: 0.001)
        XCTAssertEqual(gcp.arkitPosition.z, points[0].z, accuracy: 0.001)

        let loc = GeoLocation(latitude: 48.210033, longitude: 16.363449, altitude: 171.2,
                              horizontalAccuracy: 3.5, verticalAccuracy: 4.0, heading: 92.5,
                              timestamp: Date(timeIntervalSince1970: 1_790_000_000))
        XCTAssertTrue(loc.formattedCoordinates.contains("48.210033"))

        let meta = ScanMetadata(
            schemaVersion: 1, appVersion: "1.2.0", appBuild: "4", scanID: UUID(),
            title: "Trench A", startedAt: Date(), savedAt: Date(), pointCount: 2,
            acceptedSamples: 2, processedFrames: 1, activeSeconds: 1.0,
            settings: ScanSettings(), deviceModel: "iPad", systemVersion: "18.0",
            depthWidth: 256, depthHeight: 192, unit: "metre",
            coordinateSystem: "Local", arkitToExportRowMajor: [1,0,0,0, 0,0,-1,0, 0,1,0,0, 0,0,0,1],
            depthSource: "ARFrame.sceneDepth", confidenceMeaning: "0,1,2",
            pointSelection: "voxel", colorSource: "camera", sessionNote: "Field test",
            location: loc
        )
        let saved = SavedScan(directory: tempDir, metadata: meta)
        let updated = try ScanStorage.updateGroundControlPoints(for: saved, points: [gcp])
        XCTAssertTrue(updated.hasGCPs)
        XCTAssertTrue(FileManager.default.fileExists(atPath: updated.gcpCSVURL.path))
        let gcpCSVText = try String(contentsOf: updated.gcpCSVURL, encoding: .utf8)
        XCTAssertTrue(gcpCSVText.contains("GCP-1,1.500000,-2.000000,0.750000"))
        XCTAssertTrue(gcpCSVText.contains("EPSG:31256"))

        let reportURL = try ScanReport.pointCloud(updated)
        defer { try? FileManager.default.removeItem(at: reportURL.deletingLastPathComponent()) }
        let doc = try XCTUnwrap(PDFDocument(url: reportURL))
        let pdfText = doc.string ?? ""
        XCTAssertTrue(pdfText.contains("48.210033"))
        XCTAssertTrue(pdfText.contains("GCP-1"))
    }

    func testAnnotationsGeometryTagsExportPersistenceAndReport() throws {
        // Horizontal and tilted 3D polygons (4 x 2 m -> 12 m perimeter, 8 m²; 3 x 2 m -> 10 m, 6 m²)
        let flatVerts = [
            SIMD3<Float>(0, 1.0, 0),
            SIMD3<Float>(4.0, 1.0, 0),
            SIMD3<Float>(4.0, 1.0, -2.0),
            SIMD3<Float>(0, 1.0, -2.0)
        ].map { AnnotationPoint3D.fromARKit($0) }
        XCTAssertEqual(AnnotationGeometryHelper.perimeter(flatVerts), 12.0, accuracy: 0.001)
        XCTAssertEqual(AnnotationGeometryHelper.area(flatVerts), 8.0, accuracy: 0.001)

        let wallVerts = [
            SIMD3<Float>(0, 0, 0),
            SIMD3<Float>(3.0, 0, 0),
            SIMD3<Float>(3.0, 2.0, 0),
            SIMD3<Float>(0, 2.0, 0)
        ].map { AnnotationPoint3D.fromARKit($0) }
        XCTAssertEqual(AnnotationGeometryHelper.perimeter(wallVerts), 10.0, accuracy: 0.001)
        XCTAssertEqual(AnnotationGeometryHelper.area(wallVerts), 6.0, accuracy: 0.001)

        // Normalized tags deduplicate case-insensitively and trim hashes/whitespace
        let cleanTags = CloudAnnotation.normalizedTags([" #Wall ", "wall", "Trench A", ""])
        XCTAssertEqual(cleanTags, ["Wall", "Trench A"])

        // Legacy "rectangle" JSON decodes cleanly as .polygon
        let legacyDecoded = try JSONDecoder().decode(CloudAnnotationGeometryType.self, from: Data(#""rectangle""#.utf8))
        XCTAssertEqual(legacyDecoded, .polygon)

        let pointAnn = CloudAnnotation(
            title: "Coin Find",
            type: .point,
            vertices: [AnnotationPoint3D(x: 1.25, y: 2.5, z: -0.3)],
            tags: ["Find", "Trench A"],
            color: .gold,
            note: "Bronze follis"
        )
        let polyAnn = CloudAnnotation(
            title: "Pit 4",
            type: .polygon,
            vertices: [
                AnnotationPoint3D(x: 0, y: 0, z: 0),
                AnnotationPoint3D(x: 2, y: 0, z: 0),
                AnnotationPoint3D(x: 2, y: 2, z: 0),
                AnnotationPoint3D(x: 0, y: 2, z: 0)
            ],
            tags: ["Pit"],
            color: .amber,
            note: "Dark fill"
        )
        let wallPolyAnn = CloudAnnotation(
            title: "Wall Section",
            type: .polygon,
            vertices: wallVerts,
            tags: cleanTags,
            color: .cyan
        )

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("ScanAnnotations-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let meta = ScanMetadata(
            schemaVersion: 1, appVersion: "1.3.0", appBuild: "5", scanID: UUID(),
            title: "Annotation Test", startedAt: Date(), savedAt: Date(), pointCount: 100,
            acceptedSamples: 100, processedFrames: 1, activeSeconds: 1.0,
            settings: ScanSettings(), deviceModel: "iPad", systemVersion: "18.0",
            depthWidth: 256, depthHeight: 192, unit: "metre",
            coordinateSystem: "Local", arkitToExportRowMajor: [1,0,0,0, 0,0,-1,0, 0,1,0,0, 0,0,0,1],
            depthSource: "ARFrame.sceneDepth", confidenceMeaning: "0,1,2",
            pointSelection: "voxel", colorSource: "camera", sessionNote: ""
        )
        let saved = SavedScan(directory: tempDir, metadata: meta)
        let updated = try ScanStorage.updateAnnotations(for: saved, annotations: [pointAnn, polyAnn, wallPolyAnn])
        XCTAssertTrue(updated.hasAnnotations)
        XCTAssertTrue(FileManager.default.fileExists(atPath: updated.annotationsGeoJSONURL.path))

        // GeoJSON export contains 3D features and metadata tags
        let geoText = try String(contentsOf: updated.annotationsGeoJSONURL, encoding: .utf8)
        XCTAssertTrue(geoText.contains("\"FeatureCollection\""))
        XCTAssertTrue(geoText.contains("\"Coin Find\""))
        XCTAssertTrue(geoText.contains("\"Pit 4\""))
        XCTAssertTrue(geoText.contains("\"Wall Section\""))

        // CSV export contains 3D WKT POINT Z and POLYGON Z geometries
        let csvText = String(decoding: AnnotationExporter.csvData(for: [pointAnn, polyAnn, wallPolyAnn]), as: UTF8.self)
        XCTAssertTrue(csvText.contains("POINT Z ("))
        XCTAssertTrue(csvText.contains("POLYGON Z (("))
        XCTAssertTrue(csvText.contains("Find; Trench A"))

        // DXF export assigns tag layers and creates 3D POLYLINE + POINT entities
        let dxfText = String(decoding: AnnotationExporter.dxfData(for: [pointAnn, polyAnn, wallPolyAnn]), as: UTF8.self)
        XCTAssertTrue(dxfText.contains("ENTITIES"))
        XCTAssertTrue(dxfText.contains("POLYLINE"))
        XCTAssertTrue(dxfText.contains("\nFind\n"))
        XCTAssertTrue(dxfText.contains("EOF"))

        // PDF report summarizes annotations
        let reportURL = try ScanReport.pointCloud(updated)
        defer { try? FileManager.default.removeItem(at: reportURL.deletingLastPathComponent()) }
        let doc = try XCTUnwrap(PDFDocument(url: reportURL))
        let pdfText = doc.string ?? ""
        XCTAssertTrue(pdfText.contains("Coin Find"))
        XCTAssertTrue(pdfText.contains("Pit 4"))

        // Gaussian project annotation persistence, GeoJSON export & PDF report
        let project = GaussianProject(
            id: UUID(),
            startedAt: Date(),
            updatedAt: Date(),
            appVersion: "1.3.0",
            appBuild: "5",
            device: "iPad16,6",
            operatingSystem: "18.0",
            annotations: [pointAnn, polyAnn]
        )
        let gaussianGeoJSON = String(
            decoding: try AnnotationExporter.geoJSONData(for: [pointAnn, polyAnn], exportMetadata: AnnotationExportMetadata(gaussian: project)),
            as: UTF8.self
        )
        XCTAssertTrue(gaussianGeoJSON.contains("\"FeatureCollection\""))
        XCTAssertTrue(gaussianGeoJSON.contains("\"Coin Find\""))

        let gaussianReportURL = try ScanReport.gaussian(project)
        defer { try? FileManager.default.removeItem(at: gaussianReportURL.deletingLastPathComponent()) }
        let gDoc = try XCTUnwrap(PDFDocument(url: gaussianReportURL))
        let gPdfText = gDoc.string ?? ""
        XCTAssertTrue(gPdfText.contains("Coin Find"))
        XCTAssertTrue(gPdfText.contains("LiDAR Scanner App for iPhone and iPad"))
    }

    func testReportPDFAndDOCXFormattingImagesAndLanguage() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // Save a small real PLY so preview images are rendered inside both PDF and DOCX
        let ply = """
        ply
        format ascii 1.0
        element vertex 4
        property float x
        property float y
        property float z
        property uchar red
        property uchar green
        property uchar blue
        end_header
        0.0 0.0 0.0 255 80 60
        1.0 0.0 0.2 80 255 80
        1.0 1.0 0.5 60 120 255
        0.0 1.0 0.1 240 220 40
        """
        try ply.write(to: dir.appendingPathComponent("points.ply"), atomically: true, encoding: .utf8)

        let ann = CloudAnnotation(
            title: "Fundstelle ÄÖÜ",
            type: .point,
            vertices: [AnnotationPoint3D(x: 0.5, y: 0.5, z: 0.2)],
            tags: ["Keramik"],
            color: .lime,
            note: "Randscherbe"
        )
        let meta = ScanMetadata(
            schemaVersion: 1, appVersion: "1.3.0", appBuild: "5", scanID: UUID(), title: "Schnitt 1 · Östliche Mauer",
            startedAt: Date(), savedAt: Date(), pointCount: 4, acceptedSamples: 4, processedFrames: 2,
            activeSeconds: 3.4, settings: ScanSettings(), deviceModel: "iPad16,6", systemVersion: "18.0",
            depthWidth: 256, depthHeight: 192, unit: "metre",
            coordinateSystem: "Local right-handed Cartesian; Z up",
            arkitToExportRowMajor: [1,0,0,0, 0,0,-1,0, 0,1,0,0, 0,0,0,1],
            depthSource: "ARFrame.sceneDepth", confidenceMeaning: "0/1/2",
            pointSelection: "voxel", colorSource: "RGB", sessionNote: "Pause",
            groundControlPoints: [GroundControlPoint(label: "GCP-1", localX: 0, localY: 0, localZ: 0)],
            annotations: [ann]
        )
        try GaussianStore.encoder.encode(meta).write(to: dir.appendingPathComponent("metadata.json"))
        let scan = SavedScan(directory: dir, metadata: meta)

        let previousLang = LanguageManager.shared.selection
        defer { LanguageManager.shared.selection = previousLang }

        // Test German report (PDF + DOCX)
        LanguageManager.shared.selection = .german
        let pdfURL = try ScanReport.pointCloud(scan, format: .pdf)
        defer { try? FileManager.default.removeItem(at: pdfURL.deletingLastPathComponent()) }
        let pdfDoc = try XCTUnwrap(PDFDocument(url: pdfURL))
        XCTAssertGreaterThanOrEqual(pdfDoc.pageCount, 1)
        let pdfText = pdfDoc.string ?? ""
        XCTAssertTrue(pdfText.contains("Fundstelle ÄÖÜ"))
        XCTAssertTrue(pdfText.contains("Visuelle Ergebnisse"))
        XCTAssertTrue(pdfText.contains("LiDAR Scanner App for iPhone and iPad"))

        let docxURL = try ScanReport.pointCloud(scan, format: .docx)
        defer { try? FileManager.default.removeItem(at: docxURL.deletingLastPathComponent()) }
        XCTAssertEqual(docxURL.pathExtension, "docx")

        let extractedDir = dir.appendingPathComponent("docx_unzipped", isDirectory: true)
        try ZipArchive.extract(from: docxURL, to: extractedDir)
        let docXML = try String(contentsOf: extractedDir.appendingPathComponent("word/document.xml"), encoding: .utf8)
        XCTAssertTrue(docXML.contains("Fundstelle ÄÖÜ"))
        XCTAssertTrue(docXML.contains("PUNKTWOLKE"))
        XCTAssertTrue(docXML.contains("Visuelle Ergebnisse"))
        XCTAssertTrue(docXML.contains("Schnitt 1 · Östliche Mauer"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: extractedDir.appendingPathComponent("word/styles.xml").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: extractedDir.appendingPathComponent("word/media/figure_1.png").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: extractedDir.appendingPathComponent("word/media/figure_2.png").path))

        // Test English report (DOCX)
        LanguageManager.shared.selection = .english
        let enDocxURL = try ScanReport.pointCloud(scan, format: .docx)
        defer { try? FileManager.default.removeItem(at: enDocxURL.deletingLastPathComponent()) }
        let enExtractedDir = dir.appendingPathComponent("docx_en_unzipped", isDirectory: true)
        try ZipArchive.extract(from: enDocxURL, to: enExtractedDir)
        let enDocXML = try String(contentsOf: enExtractedDir.appendingPathComponent("word/document.xml"), encoding: .utf8)
        XCTAssertTrue(enDocXML.contains("POINT CLOUD"))
        XCTAssertTrue(enDocXML.contains("Visual Results"))
    }
}
