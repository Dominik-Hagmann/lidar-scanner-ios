import Foundation
import UIKit

enum ReportFormat: String, CaseIterable, Identifiable {
    case pdf
    case docx

    var id: String { rawValue }

    var fileExtension: String { rawValue }
}

enum ReportBlock {
    case paragraph(String)
    case keyValues([(label: String, value: String)])
    case table(headers: [String], rows: [[String]], dotHexes: [String?]?)
    case code(title: String, content: String)
}

struct ReportSection {
    let heading: String
    let blocks: [ReportBlock]
}

struct ReportDocument {
    let badge: String
    let title: String
    let subtitle: String
    let generatedAt: String
    let metrics: [(label: String, value: String)]
    let figures: [ReportFigure]
    let sections: [ReportSection]
    let footerText: String
}

/// Reports use factual templates and local visualizations generated entirely on
/// device in the active app language (`LanguageManager.isGerman`). No network
/// request, language model, or unverified accuracy claim is involved.
enum ScanReport {
    private static var isGerman: Bool { LanguageManager.isGerman }

    static func text(_ english: String, _ german: String) -> String {
        isGerman ? german : english
    }

    static func number(_ value: Double, decimals: Int = 3) -> String {
        let formatter = NumberFormatter()
        formatter.locale = LanguageManager.currentLocale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = decimals
        formatter.maximumFractionDigits = decimals
        return formatter.string(from: NSNumber(value: value))
            ?? String(format: "%.\(decimals)f", locale: LanguageManager.currentLocale, value)
    }

    static func integer(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = LanguageManager.currentLocale
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func date(_ value: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = LanguageManager.currentLocale
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: value)
    }

    static func isoDate(_ value: Date) -> String {
        ISO8601DateFormatter().string(from: value)
    }

    // MARK: - Public Export Entry Points

    static func pointCloud(_ scan: SavedScan, format: ReportFormat = .pdf) throws -> URL {
        let doc = buildPointCloudDocument(scan)
        let prefix = text("Point-cloud-report", "Punktwolke-Bericht")
        let baseName = "\(prefix)-\(scan.metadata.scanID.uuidString.prefix(8))"
        return try write(doc, name: baseName, format: format)
    }

    static func gaussian(_ project: GaussianProject, format: ReportFormat = .pdf) throws -> URL {
        let doc = buildGaussianDocument(project)
        let prefix = text("Gaussian-report", "Gaussian-Bericht")
        let baseName = "\(prefix)-\(project.id.uuidString.prefix(8))"
        return try write(doc, name: baseName, format: format)
    }

    private static func write(_ doc: ReportDocument, name: String, format: ReportFormat) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("\(name).\(format.fileExtension)")
        switch format {
        case .pdf:
            try renderPDF(doc, to: url)
        case .docx:
            try DocxReportWriter.write(doc, to: url)
        }
        return url
    }

    // MARK: - Document Builders

    static func buildPointCloudDocument(_ scan: SavedScan) -> ReportDocument {
        let p = scan.metadata
        let posix = Locale(identifier: "en_US_POSIX")
        let figures = ReportPreviewRenderer.pointCloudFigures(for: scan)

        var sections: [ReportSection] = []

        // 1. Capture Summary & Settings
        var capturePairs: [(String, String)] = [
            (text("Scan ID", "Scan-ID"), p.scanID.uuidString),
            (text("Started", "Startzeitpunkt"), "\(date(p.startedAt)) (\(isoDate(p.startedAt)))"),
            (text("Saved", "Speicherzeitpunkt"), "\(date(p.savedAt)) (\(isoDate(p.savedAt)))"),
            (text("Device & OS", "Gerät & System"), "\(p.deviceModel) · iOS \(p.systemVersion)"),
            (text("App Version", "App-Version"), "LiDAR Scanner App for iPhone and iPad \(p.appVersion) (Build \(p.appBuild ?? "unknown"))"),
            (text("Processed Depth Frames", "Verarbeitete Tiefenbilder"), integer(p.processedFrames)),
            (text("Accepted Sample Updates", "Akzeptierte Messpunktaktualisierungen"), integer(Int(p.acceptedSamples))),
            (text("Depth Image Size", "Tiefenbildauflösung"), "\(p.depthWidth) × \(p.depthHeight) px"),
            (text("Voxel Grid Size", "Voxelraster"), "\(number(Double(p.settings.voxelCentimeters), decimals: 1)) cm"),
            (text("Depth Range", "Tiefenbereich"), "0.2 – \(number(Double(p.settings.maxDepth), decimals: 1)) m"),
            (text("Pixel Step / Min Confidence", "Pixelabstand / Min. Konfidenz"), "\(p.settings.pixelStep) / \(p.settings.minConfidence)"),
            (text("Point Limit", "Punktlimit"), p.settings.maxPoints == 0 ? text("Automatic memory monitoring", "Automatische Speicherüberwachung") : integer(p.settings.maxPoints))
        ]
        if scan.hasMesh {
            capturePairs.append((text("Surface Mesh", "Oberflächennetz"), "mesh.obj (\(text("Local Z↑", "Lokal Z↑")))"))
        }

        sections.append(ReportSection(
            heading: text("Capture Overview & Parameters", "Aufnahmeübersicht & Parameter"),
            blocks: [
                .keyValues(capturePairs),
                .paragraph(text(
                    "Depth points come from ARKit sceneDepth (Apple's combined LiDAR and RGB depth estimate, without smoothedSceneDepth temporal smoothing). One observation is retained per voxel; a subsequent observation replaces it only if it carries higher confidence, without averaging or surface smoothing.",
                    "Die Tiefenpunkte stammen aus ARKit sceneDepth (Apples kombinierter LiDAR-/Kameratiefenschätzung, ohne zeitliche Glättung über smoothedSceneDepth). Pro Voxel wird eine Beobachtung beibehalten; eine spätere Beobachtung ersetzt diese nur bei höherer Konfidenz – ohne Mittelwertbildung oder Oberflächenglättung."
                ))
            ]
        ))

        // 2. Coordinates, Formats & Provenance
        var provenanceBlocks: [ReportBlock] = [
            .keyValues([
                (text("Units & Orientation", "Einheit & Ausrichtung"), text("Metres · Local right-handed · Z pointing up", "Meter · Lokal rechtshändig · Z nach oben")),
                (text("ARKit Transform", "ARKit-Transformation"), "(x, y, z) → (x, −z, y)"),
                (text("Reference System", "Referenzsystem"), text("Local frame (no EPSG / no north alignment unless external GCPs applied)", "Lokales System (kein EPSG / keine Nordausrichtung ohne externe Passpunkte)")),
                (text("Supported Formats", "Exportformate"), "Binary/ASCII PLY, CSV, LAS, LAZ, ASTM E57 (RGB + Confidence); XYZ; Mesh: OBJ, STL, PLY, GLB")
            ])
        ]
        if let loc = p.location {
            provenanceBlocks.append(.keyValues(gnssPairs(loc)))
        }
        sections.append(ReportSection(
            heading: text("Coordinates, Georeferencing & Provenance", "Koordinaten, Georeferenzierung & Herkunft"),
            blocks: provenanceBlocks
        ))

        // 3. GCPs (if present)
        if let gcps = p.groundControlPoints, !gcps.isEmpty {
            let headers = [
                text("Label", "Bezeichnung"),
                text("Local (X, Y, Z) m", "Lokal (X, Y, Z) m"),
                text("Target Reference", "Zielreferenz"),
                text("CRS / Note", "CRS / Notiz")
            ]
            let rows: [[String]] = gcps.map { gcp in
                let local = String(format: "%.3f, %.3f, %.3f", locale: posix, gcp.localX, gcp.localY, gcp.localZ)
                let target: String
                if gcp.targetX != nil || gcp.targetY != nil || gcp.targetZ != nil {
                    let tx = gcp.targetX.map { String(format: "%.6f", locale: posix, $0) } ?? "–"
                    let ty = gcp.targetY.map { String(format: "%.6f", locale: posix, $0) } ?? "–"
                    let tz = gcp.targetZ.map { String(format: "%.3f", locale: posix, $0) } ?? "–"
                    target = "\(tx), \(ty), \(tz)"
                } else {
                    target = "–"
                }
                let extra = [gcp.coordinateSystem, gcp.note].filter { !$0.isEmpty }.joined(separator: " · ")
                return [gcp.label, local, target, extra.isEmpty ? "–" : extra]
            }
            sections.append(ReportSection(
                heading: text("Ground Control Points (\(gcps.count))", "Passpunkte / Ground Control Points (\(gcps.count))"),
                blocks: [.table(headers: headers, rows: rows, dotHexes: nil)]
            ))
        }

        // 4. Annotations (if present)
        if let annotations = p.annotations, !annotations.isEmpty {
            sections.append(annotationSection(annotations))
        }

        // 5. Technical Record & Limitations
        var techBlocks: [ReportBlock] = [
            .keyValues([
                (text("Session Note", "Sitzungsvermerk"), p.sessionNote),
                (text("Local Processing", "Lokale Verarbeitung"), text("100% on device · No server uploads · Color not radiometrically calibrated", "100 % lokal auf dem Gerät · Kein Server-Upload · Farbe nicht radiometrisch kalibriert"))
            ]),
            .paragraph(text(
                "This report summarizes metadata saved with the point cloud. Raw RGB keyframes and individual frame-selection decisions are not retained in point-cloud mode. Independent metric accuracy and complete coverage were not measured.",
                "Dieser Bericht fasst die mit der Punktwolke gespeicherten Metadaten zusammen. Einzelne RGB-Bilder und Bildauswahlentscheidungen werden im Punktwolkenmodus nicht gespeichert. Eine unabhängige metrische Genauigkeit oder vollständige Abdeckung wurde nicht gemessen."
            ))
        ]
        if let jsonData = try? GaussianStore.encoder.encode(p),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            techBlocks.append(.code(title: "metadata.json", content: jsonString))
        }
        sections.append(ReportSection(
            heading: text("Technical Record", "Technischer Datensatz"),
            blocks: techBlocks
        ))

        let metrics: [(String, String)] = [
            (text("Retained Points", "Punkte"), integer(p.pointCount)),
            (text("Capture Time", "Aufnahmezeit"), "\(number(p.activeSeconds, decimals: 1)) s"),
            (text("Frames", "Tiefenbilder"), integer(p.processedFrames)),
            (text("Coordinate Frame", "Koordinatensystem"), "m · Z↑")
        ]

        return ReportDocument(
            badge: text("POINT CLOUD · PROCESSING REPORT", "PUNKTWOLKE · VERARBEITUNGSBERICHT"),
            title: p.title,
            subtitle: "LiDAR Scanner App for iPhone and iPad · \(p.appVersion) (\(p.appBuild ?? "–")) · \(p.deviceModel)",
            generatedAt: date(p.savedAt),
            metrics: metrics,
            figures: figures,
            sections: sections,
            footerText: "LiDAR Scanner App for iPhone and iPad"
        )
    }

    static func buildGaussianDocument(_ p: GaussianProject) -> ReportDocument {
        let figures = ReportPreviewRenderer.gaussianFigures(for: p)
        var sections: [ReportSection] = []

        let reasonNames = [
            "saved": text("Saved Views", "Gespeicherte Ansichten"),
            "interval": text("Sampling Interval", "Auswahlintervall"),
            "similar_view": text("Similar Camera Pose", "Ähnliche Kameraposition"),
            "writer_busy": text("Writer Busy", "Speicherung aktiv"),
            "tracking_limited": text("Tracking Not Normal", "Tracking eingeschränkt")
        ]
        let decisionsSummary = p.decisions.keys.sorted()
            .map { "\(reasonNames[$0] ?? $0): \(integer(p.decisions[$0] ?? 0))" }
            .joined(separator: " · ")

        // 1. Capture Overview
        var capturePairs: [(String, String)] = [
            (text("Project ID", "Projekt-ID"), p.id.uuidString),
            (text("Status", "Status"), p.phase.title),
            (text("Started", "Startzeitpunkt"), "\(date(p.startedAt)) (\(isoDate(p.startedAt)))"),
            (text("Updated", "Aktualisiert"), "\(date(p.updatedAt)) (\(isoDate(p.updatedAt)))"),
            (text("Device & OS", "Gerät & System"), "\(p.device) · iOS \(p.operatingSystem)"),
            (text("App Version", "App-Version"), "LiDAR Scanner App for iPhone and iPad \(p.appVersion) (Build \(p.appBuild))"),
            (text("Saved Views / Decisions", "Ansichten / Bildentscheidungen"), "\(integer(p.frames.count)) / \(integer(p.receivedFrames))"),
            (text("Seed Depth Points", "Ausgangs-Tiefenpunkte"), integer(p.seedCount))
        ]
        if let recovery = p.recoveryNote {
            capturePairs.append((text("Recovery Note", "Wiederherstellung"), recovery))
        }
        if let issue = p.lastIssue {
            capturePairs.append((text("Last Issue / Pause", "Letzter Hinweis / Pause"), issue))
        }
        if !decisionsSummary.isEmpty {
            capturePairs.append((text("Frame Decisions", "Bildentscheidungen"), decisionsSummary))
        }

        sections.append(ReportSection(
            heading: text("Capture & Input Data", "Aufnahme & Eingangsdaten"),
            blocks: [
                .keyValues(capturePairs),
                .paragraph(text(
                    "Views were selected automatically when ARKit tracking was normal, at least 0.5 s after the prior keyframe, and after at least 0.025 m translation or 3° rotation. JPEGs were stored at quality 0.95 in native orientation without cropping, paired with camera intrinsics, camera-to-world matrices, and SHA-256 hashes. Initial scene seed geometry uses ARKit sceneDepth on a 0.03 m voxel grid (0.2–5.0 m, pixel step 4, confidence ≥ 1, up to 100,000 points).",
                    "Ansichten wurden bei normalem ARKit-Tracking automatisch ausgewählt (mindestens 0,5 s Abstand sowie 0,025 m Bewegung oder 3° Drehung). Die JPEGs wurden mit Qualität 0,95 in nativer Sensorausrichtung ohne Zuschnitt samt Kameramatrizen, Intrinsics und SHA-256-Prüfsummen gespeichert. Die Ausgangsgeometrie basiert auf ARKit sceneDepth (0,03 m Voxelraster, 0,2–5,0 m, Pixelabstand 4, Konfidenz ≥ 1, max. 100.000 Punkte)."
                ))
            ]
        ))

        // 2. Optimization / Processing
        var procPairs: [(String, String)] = [
            (text("Recorded Status", "Protokollierter Status"), p.phase.title),
            (text("Gaussians (Splats)", "Gaussians (Splats)"), integer(p.splatCount)),
            (text("Processing Time", "Verarbeitungszeit"), "\(number(p.processingSeconds, decimals: 1)) s"),
            (text("Result Export", "Szenenexport"), p.hasResult ? text("Available (scene.ply)", "Vorhanden (scene.ply)") : text("Not available yet", "Noch nicht vorhanden"))
        ]
        if let profile = p.profile {
            procPairs.insert((text("Profile", "Profil"), profile.name), at: 0)
            procPairs.append((text("Completed / Target Steps", "Schritte (abgeschlossen / Ziel)"), "\(integer(p.iteration)) / \(integer(profile.iterations))"))
            procPairs.append((text("Durable Checkpoint", "Gesicherter Zwischenstand"), integer(p.checkpointIteration)))
            procPairs.append((text("Downscale / SH Degree", "Verkleinerung / SH-Grad"), "\(number(Double(profile.downscaleFactor), decimals: 1))× / \(profile.shDegree)"))
            procPairs.append((text("Stop Densify / SSIM Weight", "Densify-Stopp / SSIM"), "\(integer(profile.stopDensifyAt)) / \(number(Double(profile.ssimWeight), decimals: 2))"))
        }
        sections.append(ReportSection(
            heading: text("Processing & Reconstruction", "Verarbeitung & Rekonstruktion"),
            blocks: [
                .keyValues(procPairs),
                .paragraph(text(
                    "Local Metal optimization uses \(p.engine) (revision \(p.engineRevision.prefix(10)), patch \(p.enginePatch)) with Adam optimization and L1/SSIM loss on a black background. All views participate in training; no held-out test split or independent blur evaluation was computed.",
                    "Die lokale Metal-Optimierung nutzt \(p.engine) (Revision \(p.engineRevision.prefix(10)), Patch \(p.enginePatch)) mit Adam und L1-/SSIM-Verlust auf schwarzem Hintergrund. Alle gespeicherten Ansichten wurden verwendet; es wurde keine getrennte Testansicht zurückgehalten."
                ))
            ]
        ))

        // 3. Coordinates & Provenance
        var coordBlocks: [ReportBlock] = [
            .keyValues([
                (text("Coordinate System", "Koordinatensystem"), text("Local ARKit world · Metres · Y pointing up · OpenGL cameras", "Lokales ARKit-System · Meter · Y nach oben · OpenGL-Kameras")),
                (text("Reference Frame", "Referenzrahmen"), text("keepCrs=true · No EPSG / no north alignment (differs from Z-up Point Cloud mode)", "keepCrs=true · Kein EPSG / keine Nordausrichtung (abweichend vom Z-oben-Punktwolkenmodus)")),
                (text("Metric Caveat", "Metrischer Hinweis"), text("ARKit poses without bundle adjustment; Gaussian centers may shift during optimization", "ARKit-Posen ohne Bündelausgleichung; Gaussian-Zentren können sich bei Optimierung verschieben"))
            ])
        ]
        if let loc = p.location {
            coordBlocks.append(.keyValues(gnssPairs(loc)))
        }
        sections.append(ReportSection(
            heading: text("Coordinates & Limits", "Koordinaten & Grenzen"),
            blocks: coordBlocks
        ))

        // 4. Annotations (if present)
        if let annotations = p.annotations, !annotations.isEmpty {
            sections.append(annotationSection(annotations))
        }

        // 5. Technical Record
        var techBlocks: [ReportBlock] = [
            .keyValues([
                ("Engine / Viewer", "\(p.engineRevision.prefix(12)) / \(p.viewerRevision.prefix(12))"),
                ("PLY SHA-256", p.resultHash ?? "–"),
                ("Seed SHA-256", p.seedHash ?? "–"),
                ("Checkpoint SHA-256", p.checkpointHash ?? "–"),
                ("Audit Head", p.auditHead.isEmpty ? "–" : p.auditHead)
            ]),
            .paragraph(text(
                "All capture, optimization, and reporting ran locally on the device without uploads. Images and transforms.json can be exported for external pipelines; scan.json and events.jsonl record parameters and event hashes (not a cryptographic signature).",
                "Aufnahme, Optimierung und Berichtserstellung erfolgten vollständig lokal auf dem Gerät ohne Upload. Bilder und transforms.json lassen sich weitergeben; scan.json und events.jsonl protokollieren Parameter und Ereignis-Hashes (keine digitale Signatur)."
            ))
        ]
        if let profile = p.profile,
           let data = try? GaussianStore.encoder.encode(profile),
           let json = String(data: data, encoding: .utf8) {
            techBlocks.append(.code(title: "profile.json", content: json))
        }
        sections.append(ReportSection(
            heading: text("Technical Record", "Technischer Datensatz"),
            blocks: techBlocks
        ))

        let metrics: [(String, String)] = [
            ("Gaussians", integer(p.splatCount)),
            (text("Saved Views", "Ansichten"), integer(p.frames.count)),
            (text("Processing", "Rechenzeit"), "\(number(p.processingSeconds, decimals: 1)) s"),
            (text("Coordinate Frame", "Koordinatensystem"), "m · Y↑")
        ]

        return ReportDocument(
            badge: text("GAUSSIAN SPLATTING · PROCESSING REPORT", "GAUSSIAN SPLATTING · VERARBEITUNGSBERICHT"),
            title: p.title,
            subtitle: "LiDAR Scanner App for iPhone and iPad · \(p.appVersion) (\(p.appBuild)) · \(p.device)",
            generatedAt: date(p.updatedAt),
            metrics: metrics,
            figures: figures,
            sections: sections,
            footerText: "LiDAR Scanner App for iPhone and iPad"
        )
    }

    private static func gnssPairs(_ loc: GeoLocation) -> [(String, String)] {
        let posix = Locale(identifier: "en_US_POSIX")
        let lat = String(format: "%.6f°", locale: posix, loc.latitude)
        let lon = String(format: "%.6f°", locale: posix, loc.longitude)
        let altStr = loc.altitude.map { String(format: "%.2f m", locale: posix, $0) } ?? "–"
        let hAcc = String(format: "±%.1f m", locale: posix, loc.horizontalAccuracy)
        let vAcc = loc.verticalAccuracy.map { String(format: "±%.1f m", locale: posix, $0) } ?? "–"
        let headingStr = loc.heading.map { String(format: "%.1f°", locale: posix, $0) } ?? "–"
        return [
            (text("GNSS Position (WGS84)", "GNSS-Position (WGS84)"), "\(lat), \(lon)"),
            (text("Altitude / Heading", "Höhe / Ausrichtung"), "\(altStr) · \(headingStr)"),
            (text("GNSS Accuracy (H / V)", "GNSS-Genauigkeit (H / V)"), "\(hAcc) / \(vAcc)")
        ]
    }

    private static func annotationSection(_ annotations: [CloudAnnotation]) -> ReportSection {
        let posix = Locale(identifier: "en_US_POSIX")
        let headers = [
            text("Name", "Name"),
            text("Type & Tags", "Typ & Tags"),
            text("Center (X, Y, Z) m", "Zentrum (X, Y, Z) m"),
            text("Geometry / Note", "Geometrie / Notiz")
        ]
        var rows: [[String]] = []
        var hexes: [String?] = []

        for ann in annotations {
            let c = ann.centroid
            let typeLabel = ann.type == .point ? text("Point", "Punkt") : text("Polygon", "Polygon")
            let tagsText = ann.tags.isEmpty ? typeLabel : "\(typeLabel) · " + ann.tags.joined(separator: ", ")
            let coord = String(format: "%.3f, %.3f, %.3f", locale: posix, c.x, c.y, c.z)
            var geomParts: [String] = []
            if ann.type != .point {
                geomParts.append(String(format: "P=%.2f m · A=%.3f m²", locale: posix, ann.perimeterMeters, ann.areaSquareMeters))
            }
            if !ann.note.isEmpty {
                geomParts.append(ann.note)
            }
            rows.append([ann.title, tagsText, coord, geomParts.isEmpty ? "–" : geomParts.joined(separator: " — ")])
            hexes.append(String(ann.color.hex.dropFirst()))
        }

        return ReportSection(
            heading: text("3D Annotations (\(annotations.count))", "3D-Annotationen (\(annotations.count))"),
            blocks: [.table(headers: headers, rows: rows, dotHexes: hexes)]
        )
    }

    // MARK: - Legacy Compatibility Helpers (used by existing unit tests)

    static func gaussianParagraphs(_ p: GaussianProject) -> [String] {
        var result = [
            text("Gaussian Splatting — processing report", "Gaussian Splatting – Verarbeitungsbericht"),
            "LiDAR Scanner App for iPhone and iPad \(p.appVersion) (\(p.appBuild))",
            "\(p.phase.title) · \(p.splatCount) Gaussians · \(p.frames.count) views"
        ]
        let doc = buildGaussianDocument(p)
        for sec in doc.sections {
            result.append(sec.heading)
            for block in sec.blocks {
                switch block {
                case .paragraph(let txt): result.append(txt)
                case .keyValues(let pairs): result.append(pairs.map { "\($0.label): \($0.value)" }.joined(separator: "\n"))
                case .table(_, let rows, _): result.append(contentsOf: rows.map { $0.joined(separator: " · ") })
                case .code(let title, let content): result.append("\(title)\n\(content)")
                }
            }
        }
        return result
    }

    static func pdf(paragraphs: [String], name: String) throws -> URL {
        let title = paragraphs.first ?? "LiDAR Scanner App for iPhone and iPad"
        let bodyBlocks = paragraphs.dropFirst().map { ReportBlock.paragraph($0) }
        let doc = ReportDocument(
            badge: "REPORT",
            title: title,
            subtitle: "LiDAR Scanner App for iPhone and iPad",
            generatedAt: date(Date()),
            metrics: [],
            figures: [],
            sections: bodyBlocks.isEmpty ? [] : [ReportSection(heading: text("Summary", "Zusammenfassung"), blocks: bodyBlocks)],
            footerText: "LiDAR Scanner App for iPhone and iPad"
        )
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("\(name).pdf")
        try renderPDF(doc, to: url)
        return url
    }

    // MARK: - PDF Renderer (Pure UIKit Top-Down with PDF-Safe Fonts)

    private static func fontRegular(_ size: CGFloat) -> UIFont {
        UIFont(name: "HelveticaNeue", size: size) ?? UIFont.systemFont(ofSize: size)
    }

    private static func fontMedium(_ size: CGFloat) -> UIFont {
        UIFont(name: "HelveticaNeue-Medium", size: size) ?? UIFont.systemFont(ofSize: size, weight: .medium)
    }

    private static func fontBold(_ size: CGFloat) -> UIFont {
        UIFont(name: "HelveticaNeue-Bold", size: size) ?? UIFont.boldSystemFont(ofSize: size)
    }

    private static func fontItalic(_ size: CGFloat) -> UIFont {
        UIFont(name: "HelveticaNeue-Italic", size: size) ?? UIFont.italicSystemFont(ofSize: size)
    }

    private static func fontMono(_ size: CGFloat) -> UIFont {
        UIFont(name: "Menlo-Regular", size: size) ?? UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    private static func renderPDF(_ doc: ReportDocument, to url: URL) throws {
        // A4 in points: 595 x 842
        let pageSize = CGSize(width: 595, height: 842)
        let margin: CGFloat = 40
        let contentWidth = pageSize.width - margin * 2
        let topY: CGFloat = 46
        let bottomLimit: CGFloat = pageSize.height - 46

        let inkDark = UIColor(red: 0.06, green: 0.09, blue: 0.16, alpha: 1.0)
        let inkBody = UIColor(red: 0.15, green: 0.20, blue: 0.26, alpha: 1.0)
        let inkMuted = UIColor(red: 0.36, green: 0.43, blue: 0.50, alpha: 1.0)
        let mintAccent = UIColor(red: 0.08, green: 0.72, blue: 0.65, alpha: 1.0)
        let slateTint = UIColor(red: 0.96, green: 0.97, blue: 0.98, alpha: 1.0)
        let headerTint = UIColor(red: 0.90, green: 0.96, blue: 0.95, alpha: 1.0)
        let borderColor = UIColor(red: 0.84, green: 0.88, blue: 0.92, alpha: 1.0)

        var pages: [[(CGContext) -> Void]] = [[]]
        var y: CGFloat = topY

        func appendDraw(_ block: @escaping (CGContext) -> Void) {
            pages[pages.count - 1].append(block)
        }

        func newPage() {
            pages.append([])
            y = topY
        }

        func ensureSpace(_ heightNeeded: CGFloat) {
            if y + heightNeeded > bottomLimit && y > topY + 20 {
                newPage()
            }
        }

        func measureHeight(_ text: String, width: CGFloat, font: UIFont, lineSpacing: CGFloat = 3) -> CGFloat {
            let pStyle = NSMutableParagraphStyle()
            pStyle.lineSpacing = lineSpacing
            pStyle.lineBreakMode = .byWordWrapping
            let rect = (text as NSString).boundingRect(
                with: CGSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font, .paragraphStyle: pStyle],
                context: nil
            )
            return ceil(rect.height)
        }

        func drawText(_ text: String, in rect: CGRect, font: UIFont, color: UIColor, lineSpacing: CGFloat = 3, align: NSTextAlignment = .left) {
            let pStyle = NSMutableParagraphStyle()
            pStyle.lineSpacing = lineSpacing
            pStyle.alignment = align
            pStyle.lineBreakMode = .byWordWrapping
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: pStyle
            ]
            appendDraw { _ in
                (text as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs, context: nil)
            }
        }

        // 1. Header Banner
        let titleFont = fontBold(18)
        let titleH = measureHeight(doc.title, width: contentWidth - 36, font: titleFont, lineSpacing: 2)
        let subText = "\(doc.subtitle) · \(doc.generatedAt)"
        let subFont = fontRegular(9.5)
        let subH = measureHeight(subText, width: contentWidth - 36, font: subFont, lineSpacing: 2)
        let bannerH = 16 + 14 + 6 + titleH + 6 + subH + 16
        let bannerRect = CGRect(x: margin, y: y, width: contentWidth, height: bannerH)
        appendDraw { cg in
            let bg = UIBezierPath(roundedRect: bannerRect, cornerRadius: 8)
            cg.setFillColor(inkDark.cgColor)
            bg.fill()
            cg.setFillColor(mintAccent.cgColor)
            UIBezierPath(roundedRect: CGRect(x: bannerRect.minX, y: bannerRect.minY, width: 5, height: bannerRect.height), cornerRadius: 2).fill()
        }
        drawText(doc.badge, in: CGRect(x: margin + 18, y: y + 14, width: contentWidth - 36, height: 14), font: fontBold(8.5), color: UIColor(red: 0.38, green: 0.93, blue: 0.83, alpha: 1))
        drawText(doc.title, in: CGRect(x: margin + 18, y: y + 32, width: contentWidth - 36, height: titleH), font: titleFont, color: .white, lineSpacing: 2)
        drawText(subText, in: CGRect(x: margin + 18, y: y + 38 + titleH, width: contentWidth - 36, height: subH), font: subFont, color: UIColor(white: 0.84, alpha: 1), lineSpacing: 2)
        y += bannerH + 14

        // 2. Metrics Cards
        if !doc.metrics.isEmpty {
            let count = CGFloat(doc.metrics.count)
            let gap: CGFloat = 8
            let cardW = (contentWidth - gap * (count - 1)) / count
            let cardH: CGFloat = 48
            ensureSpace(cardH + 10)
            for (idx, m) in doc.metrics.enumerated() {
                let x = margin + CGFloat(idx) * (cardW + gap)
                let rect = CGRect(x: x, y: y, width: cardW, height: cardH)
                appendDraw { cg in
                    let path = UIBezierPath(roundedRect: rect, cornerRadius: 6)
                    cg.setFillColor(slateTint.cgColor); path.fill()
                    cg.setStrokeColor(borderColor.cgColor); cg.setLineWidth(0.75); path.stroke()
                }
                drawText(m.label.uppercased(), in: CGRect(x: x + 9, y: y + 7, width: cardW - 18, height: 12), font: fontBold(7.5), color: inkMuted)
                drawText(m.value, in: CGRect(x: x + 9, y: y + 21, width: cardW - 18, height: 22), font: fontBold(12), color: inkDark)
            }
            y += cardH + 16
        }

        func drawSectionHeading(_ heading: String) {
            let hFont = fontBold(13)
            let hHeight = measureHeight(heading, width: contentWidth, font: hFont, lineSpacing: 2)
            ensureSpace(hHeight + 48)
            y += 6
            drawText(heading, in: CGRect(x: margin, y: y, width: contentWidth, height: hHeight), font: hFont, color: inkDark, lineSpacing: 2)
            let ruleY = y + hHeight + 4
            appendDraw { cg in
                cg.setStrokeColor(mintAccent.cgColor)
                cg.setLineWidth(1.5)
                cg.move(to: CGPoint(x: margin, y: ruleY))
                cg.addLine(to: CGPoint(x: margin + contentWidth, y: ruleY))
                cg.strokePath()
            }
            y = ruleY + 9
        }

        // 3. Visual Result Figures
        if !doc.figures.isEmpty {
            drawSectionHeading(text("Visual Results", "Visuelle Ergebnisse"))
            for fig in doc.figures {
                let aspect = CGFloat(max(1, fig.pixelHeight)) / CGFloat(max(1, fig.pixelWidth))
                let imgH = min(285, contentWidth * aspect)
                let imgW = imgH / aspect
                let capText = "\(fig.title) — \(fig.caption)"
                let capH = measureHeight(capText, width: contentWidth, font: fontItalic(8.5), lineSpacing: 2)
                ensureSpace(imgH + capH + 18)

                if let image = UIImage(data: fig.pngData) {
                    let imgRect = CGRect(x: margin + (contentWidth - imgW) * 0.5, y: y, width: imgW, height: imgH)
                    appendDraw { cg in
                        cg.saveGState()
                        let clip = UIBezierPath(roundedRect: imgRect, cornerRadius: 6)
                        clip.addClip()
                        image.draw(in: imgRect)
                        cg.restoreGState()
                        cg.setStrokeColor(borderColor.cgColor)
                        cg.setLineWidth(0.75)
                        clipStroke(imgRect, radius: 6, in: cg)
                    }
                    y += imgH + 5
                }
                drawText(capText, in: CGRect(x: margin, y: y, width: contentWidth, height: capH), font: fontItalic(8.5), color: inkMuted, lineSpacing: 2)
                y += capH + 12
            }
        }

        // 4. Structured Sections
        for section in doc.sections {
            drawSectionHeading(section.heading)
            for block in section.blocks {
                switch block {
                case .paragraph(let txt):
                    let pFont = fontRegular(9.8)
                    let h = measureHeight(txt, width: contentWidth, font: pFont, lineSpacing: 3.5)
                    ensureSpace(h + 8)
                    drawText(txt, in: CGRect(x: margin, y: y, width: contentWidth, height: h), font: pFont, color: inkBody, lineSpacing: 3.5)
                    y += h + 9

                case .keyValues(let pairs):
                    let labelW: CGFloat = 175
                    let valW = contentWidth - labelW - 22
                    let kFont = fontMedium(9.2)
                    let vFont = fontRegular(9.2)
                    for (idx, pair) in pairs.enumerated() {
                        let lh = measureHeight(pair.label, width: labelW - 12, font: kFont, lineSpacing: 2)
                        let vh = measureHeight(pair.value, width: valW, font: vFont, lineSpacing: 2)
                        let rowH = max(lh, vh) + 10
                        ensureSpace(rowH)
                        let rowRect = CGRect(x: margin, y: y, width: contentWidth, height: rowH)
                        let isEven = idx % 2 == 0
                        appendDraw { cg in
                            if isEven {
                                cg.setFillColor(slateTint.cgColor)
                                cg.fill(rowRect)
                            }
                            cg.setStrokeColor(borderColor.withAlphaComponent(0.75).cgColor)
                            cg.setLineWidth(0.5)
                            cg.move(to: CGPoint(x: rowRect.minX, y: rowRect.maxY))
                            cg.addLine(to: CGPoint(x: rowRect.maxX, y: rowRect.maxY))
                            cg.strokePath()
                        }
                        drawText(pair.label, in: CGRect(x: margin + 8, y: y + 5, width: labelW - 12, height: lh), font: kFont, color: inkDark, lineSpacing: 2)
                        drawText(pair.value, in: CGRect(x: margin + labelW + 6, y: y + 5, width: valW, height: vh), font: vFont, color: inkBody, lineSpacing: 2)
                        y += rowH
                    }
                    y += 10

                case .table(let headers, let rows, let dotHexes):
                    let colCount = max(1, headers.count)
                    let colW = contentWidth / CGFloat(colCount)
                    let hFont = fontBold(8.8)
                    let rFont = fontRegular(8.6)

                    func drawHeaderRow() {
                        let headerH = (headers.map { measureHeight($0, width: colW - 12, font: hFont, lineSpacing: 2) }.max() ?? 12) + 10
                        let rect = CGRect(x: margin, y: y, width: contentWidth, height: headerH)
                        appendDraw { cg in
                            cg.setFillColor(headerTint.cgColor)
                            cg.fill(rect)
                            cg.setStrokeColor(borderColor.cgColor)
                            cg.setLineWidth(0.75)
                            cg.stroke(rect)
                        }
                        for (cIdx, h) in headers.enumerated() {
                            drawText(h, in: CGRect(x: margin + CGFloat(cIdx) * colW + 6, y: y + 5, width: colW - 12, height: headerH - 8), font: hFont, color: inkDark, lineSpacing: 2)
                        }
                        y += headerH
                    }

                    ensureSpace(44)
                    drawHeaderRow()

                    for (rIdx, row) in rows.enumerated() {
                        let heights = (0..<colCount).map { cIdx -> CGFloat in
                            let text = cIdx < row.count ? row[cIdx] : ""
                            let indent: CGFloat = (cIdx == 0 && dotHexes?[safe: rIdx] != nil) ? 12 : 0
                            return measureHeight(text, width: colW - 12 - indent, font: rFont, lineSpacing: 2)
                        }
                        let rowH = (heights.max() ?? 12) + 9
                        if y + rowH > bottomLimit {
                            newPage()
                            drawHeaderRow()
                        }
                        let rect = CGRect(x: margin, y: y, width: contentWidth, height: rowH)
                        let isOdd = rIdx % 2 == 1
                        appendDraw { cg in
                            if isOdd {
                                cg.setFillColor(slateTint.cgColor)
                                cg.fill(rect)
                            }
                            cg.setStrokeColor(borderColor.cgColor)
                            cg.setLineWidth(0.5)
                            cg.move(to: CGPoint(x: rect.minX, y: rect.maxY))
                            cg.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                            cg.strokePath()
                        }
                        for cIdx in 0..<colCount {
                            let text = cIdx < row.count ? row[cIdx] : ""
                            let cellX = margin + CGFloat(cIdx) * colW + 6
                            var textIndent: CGFloat = 0
                            if cIdx == 0, let hex = dotHexes?[safe: rIdx] ?? nil {
                                textIndent = 11
                                let dotColor = uiColor(hex: hex)
                                appendDraw { cg in
                                    cg.setFillColor(dotColor.cgColor)
                                    cg.fillEllipse(in: CGRect(x: cellX, y: rect.minY + 7.5, width: 6.5, height: 6.5))
                                }
                            }
                            drawText(text, in: CGRect(x: cellX + textIndent, y: y + 4.5, width: colW - 12 - textIndent, height: rowH - 8), font: rFont, color: inkBody, lineSpacing: 2)
                        }
                        y += rowH
                    }
                    y += 10

                case .code(let title, let codeText):
                    let mFont = fontMono(7.5)
                    let titleH = measureHeight(title, width: contentWidth, font: fontMedium(8.5), lineSpacing: 2)
                    ensureSpace(titleH + 34)
                    drawText(title, in: CGRect(x: margin, y: y, width: contentWidth, height: titleH), font: fontMedium(8.5), color: inkMuted)
                    y += titleH + 4

                    // Split monospace lines safely into page-fitting chunks
                    let wrappedChunks = wrapMonospaceLines(codeText, maxCharsPerLine: 94)
                    var index = 0
                    while index < wrappedChunks.count {
                        let availableH = max(36, bottomLimit - y - 12)
                        let lineH: CGFloat = 10.5
                        let maxLines = max(3, Int(availableH / lineH))
                        let slice = Array(wrappedChunks[index..<min(wrappedChunks.count, index + maxLines)])
                        let boxText = slice.joined(separator: "\n")
                        let boxTextH = measureHeight(boxText, width: contentWidth - 18, font: mFont, lineSpacing: 1.5)
                        let boxH = boxTextH + 14
                        let boxRect = CGRect(x: margin, y: y, width: contentWidth, height: boxH)
                        appendDraw { cg in
                            cg.setFillColor(slateTint.cgColor)
                            UIBezierPath(roundedRect: boxRect, cornerRadius: 4).fill()
                            cg.setFillColor(UIColor(red: 0.62, green: 0.70, blue: 0.78, alpha: 1).cgColor)
                            cg.fill(CGRect(x: boxRect.minX, y: boxRect.minY, width: 3, height: boxRect.height))
                            cg.setStrokeColor(borderColor.cgColor)
                            cg.setLineWidth(0.5)
                            clipStroke(boxRect, radius: 4, in: cg)
                        }
                        drawText(boxText, in: CGRect(x: margin + 10, y: y + 7, width: contentWidth - 18, height: boxTextH), font: mFont, color: inkBody, lineSpacing: 1.5)
                        y += boxH + 8
                        index += slice.count
                        if index < wrappedChunks.count {
                            newPage()
                        }
                    }
                }
            }
        }

        // Write actual PDF pages using UIGraphicsPDFRenderer
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        let totalPages = pages.count
        try renderer.writePDF(to: url) { output in
            for (idx, drawCommands) in pages.enumerated() {
                output.beginPage()
                let cg = output.cgContext
                for cmd in drawCommands {
                    cmd(cg)
                }
                let pageNumText = text("Page \(idx + 1) of \(totalPages)", "Seite \(idx + 1) von \(totalPages)")
                let footerLeft = doc.footerText
                let fFont = fontRegular(8.5)
                cg.setStrokeColor(borderColor.cgColor)
                cg.setLineWidth(0.5)
                cg.move(to: CGPoint(x: margin, y: pageSize.height - 34))
                cg.addLine(to: CGPoint(x: pageSize.width - margin, y: pageSize.height - 34))
                cg.strokePath()
                (footerLeft as NSString).draw(at: CGPoint(x: margin, y: pageSize.height - 27), withAttributes: [.font: fFont, .foregroundColor: inkMuted])
                let rightSize = (pageNumText as NSString).size(withAttributes: [.font: fFont])
                (pageNumText as NSString).draw(at: CGPoint(x: pageSize.width - margin - rightSize.width, y: pageSize.height - 27), withAttributes: [.font: fFont, .foregroundColor: inkMuted])
            }
        }
    }

    private static func clipStroke(_ rect: CGRect, radius: CGFloat, in cg: CGContext) {
        UIBezierPath(roundedRect: rect, cornerRadius: radius).stroke()
    }

    private static func wrapMonospaceLines(_ text: String, maxCharsPerLine: Int) -> [String] {
        var result: [String] = []
        for line in text.components(separatedBy: .newlines) {
            if line.count <= maxCharsPerLine {
                result.append(line)
            } else {
                var current = ""
                for ch in line {
                    current.append(ch)
                    if current.count >= maxCharsPerLine {
                        result.append(current)
                        current = ""
                    }
                }
                if !current.isEmpty { result.append(current) }
            }
        }
        return result
    }

    private static func uiColor(hex: String) -> UIColor {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        var rgb: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&rgb)
        return UIColor(
            red: CGFloat((rgb >> 16) & 0xFF) / 255.0,
            green: CGFloat((rgb >> 8) & 0xFF) / 255.0,
            blue: CGFloat(rgb & 0xFF) / 255.0,
            alpha: 1.0
        )
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
