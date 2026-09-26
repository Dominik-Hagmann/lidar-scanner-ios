import Foundation
import UIKit
import CoreText

/// Reports use factual templates, generated entirely on device. No language
/// model, network request or inferred accuracy claim is involved.
enum ScanReport {
    static func text(_ english: String, _ german: String) -> String {
        Bundle.main.preferredLocalizations.first?.hasPrefix("de") == true ? german : english
    }
    static func number(_ value: Double) -> String {
        String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
    static func date(_ value: Date) -> String { ISO8601DateFormatter().string(from: value) }

    static func gaussianParagraphs(_ p: GaussianProject) -> [String] {
        var paragraphs = [
            text("Gaussian Splatting — processing report", "Gaussian Splatting – Verarbeitungsbericht"),
            text("This report describes scan \(p.id.uuidString), started at \(date(p.startedAt)). It uses the saved processing record as of \(date(p.updatedAt)). The scan was recorded with LiDAR-Scanner \(p.appVersion), build \(p.appBuild), on \(p.device) running iOS \(p.operatingSystem).",
                 "Dieser Bericht beschreibt den Scan \(p.id.uuidString), begonnen am \(date(p.startedAt)). Grundlage ist der gespeicherte Verarbeitungsstand vom \(date(p.updatedAt)). Die Aufnahme erfolgte mit LiDAR-Scanner \(p.appVersion), Build \(p.appBuild), auf \(p.device) mit iOS \(p.operatingSystem)."),
            text("Capture", "Aufnahme"),
            text("The saved record contains \(p.receivedFrames) camera-frame decisions and \(p.frames.count) saved images. Images were selected only while ARKit tracking was normal, at least 0.5 seconds after the preceding selected view, and after at least 0.025 metres of camera movement or 3 degrees of rotation. Only one image was written at a time. No blur score or independent image-quality assessment was calculated.",
                 "Der gespeicherte Stand enthält \(p.receivedFrames) Entscheidungen zu Kamerabildern und \(p.frames.count) gespeicherte Bilder. Bilder wurden bei normalem ARKit-Tracking ausgewählt, frühestens 0,5 Sekunden nach der vorigen ausgewählten Ansicht und nach mindestens 0,025 Metern Kamerabewegung oder 3 Grad Drehung. Es wurde jeweils ein Bild gleichzeitig geschrieben. Ein Unschärfewert oder eine unabhängige Bewertung der Bildqualität wurde nicht berechnet."),
            text("The images were saved as JPEG at quality 0.95, in the camera sensor's original orientation and resolution. The dataset records each image's resolution, focal lengths, principal point, camera-to-world matrix, timestamp and SHA-256 checksum. Images were not cropped or rotated for training. Lens-distortion coefficients were set to zero; no separate lens calibration was performed.",
                 "Die Bilder wurden als JPEG mit Qualität 0,95 in ursprünglicher Sensorausrichtung und Auflösung gespeichert. Der Datensatz enthält für jedes Bild Auflösung, Brennweitenparameter, Hauptpunkt, Kamera-zu-Welt-Matrix, Zeitstempel und SHA-256-Prüfsumme. Für die Berechnung wurden die Bilder weder zugeschnitten noch gedreht. Die Verzeichnungskoeffizienten wurden auf null gesetzt; eine separate Objektivkalibrierung erfolgte nicht."),
            text("The initial scene contains \(p.seedCount) depth-derived points. ARKit sceneDepth supplied the depth; this is Apple's combined LiDAR/camera depth, not raw laser measurements. Sampling used a 0.03 metre voxel grid, depth between 0.2 and 5 metres, every fourth depth pixel and confidence of at least 1. The seed was limited to 100,000 points. The first sample per voxel was retained unless a higher-confidence sample arrived.",
                 "Die Ausgangsszene enthält \(p.seedCount) aus Tiefendaten abgeleitete Punkte. Die Tiefe stammt aus ARKit sceneDepth, also Apples kombinierter LiDAR-/Kameratiefe, nicht aus rohen Lasermessungen. Verwendet wurden ein Voxelraster von 0,03 Metern, Tiefen zwischen 0,2 und 5 Metern, jeder vierte Tiefenbildpixel und eine Konfidenz von mindestens 1. Die Ausgangspunktwolke wurde auf 100.000 Punkte begrenzt. Pro Voxel wurde die erste Beobachtung beibehalten, sofern später keine Beobachtung mit höherer Konfidenz eintraf.")
        ]
        let reasonNames = [
            "saved": text("saved", "gespeichert"), "interval": text("sampling interval", "Auswahlintervall"),
            "similar_view": text("similar camera pose", "ähnliche Kameraposition"),
            "writer_busy": text("previous frame still being saved", "voriges Bild noch in Speicherung"),
            "tracking_limited": text("tracking not normal", "Tracking nicht normal")
        ]
        let reasons = p.decisions.keys.sorted().map { "\(reasonNames[$0] ?? $0): \(p.decisions[$0] ?? 0)" }.joined(separator: "; ")
        paragraphs.append(text("Recorded frame decisions: \(reasons).", "Protokollierte Bildentscheidungen: \(reasons)."))
        if let recovery = p.recoveryNote {
            paragraphs.append(text("The scan was recovered after an interruption. The report refers to the last durable saved state. Recovery note: \(recovery)",
                "Der Scan wurde nach einer Unterbrechung wiederhergestellt. Der Bericht bezieht sich auf den letzten dauerhaft gespeicherten Stand. Wiederherstellungsvermerk: \(recovery)"))
        }
        paragraphs.append(text("Processing and result", "Verarbeitung und Ergebnis"))
        if let profile = p.profile {
            paragraphs.append(text("The app chose profile \(profile.name) automatically from the number and resolution of the saved images. The target was \(profile.iterations) optimization steps; the recorded completed step is \(p.iteration), and the durable checkpoint is step \(p.checkpointIteration). All saved images were eligible for random camera sampling. Training downscaled images by a factor of \(profile.downscaleFactor); an additional coarse-to-fine stage used \(profile.numDownscales) downscale level(s), changing every \(profile.resolutionSchedule) steps. The original saved JPEGs remain at their capture resolution.",
                "Die App wählte das Profil \(profile.name) anhand von Anzahl und Auflösung der gespeicherten Bilder automatisch aus. Vorgesehen waren \(profile.iterations) Optimierungsschritte; protokolliert abgeschlossen ist Schritt \(p.iteration), dauerhaft als Zwischenstand gespeichert ist Schritt \(p.checkpointIteration). Alle gespeicherten Bilder standen für die zufällige Kameraauswahl zur Verfügung. Für die Berechnung wurden die Bilder um den Faktor \(profile.downscaleFactor) verkleinert; zusätzlich kam eine Grob-zu-fein-Stufe mit \(profile.numDownscales) Verkleinerungsstufe(n) und einem Wechsel nach jeweils \(profile.resolutionSchedule) Schritten zum Einsatz. Die ursprünglichen JPEGs behalten ihre Aufnahmeauflösung."))
            paragraphs.append(text("The engine was \(p.engine), revision \(p.engineRevision), integration patch \(p.enginePatch). Its Metal implementation optimized Gaussian positions, sizes, rotations, opacity and spherical-harmonic color coefficients locally on the device. The maximum spherical-harmonic degree was \(profile.shDegree). It used Adam optimization and an L1/SSIM image loss with SSIM weight \(profile.ssimWeight). Topology growth stopped at step \(profile.stopDensifyAt). A black background was used. No held-out quality evaluation was run.",
                "Verwendet wurde \(p.engine), Revision \(p.engineRevision), Integrationspatch \(p.enginePatch). Die Metal-Implementierung optimierte Positionen, Größen, Drehungen, Deckkraft und sphärische Farbkoeffizienten der Gaussians lokal auf dem Gerät. Der maximale Grad der sphärischen Harmonischen betrug \(profile.shDegree). Zum Einsatz kamen Adam-Optimierung und eine L1-/SSIM-Bildverlustfunktion mit SSIM-Gewicht \(profile.ssimWeight). Die Erweiterung der Gaussian-Struktur endete bei Schritt \(profile.stopDensifyAt). Als Hintergrund wurde Schwarz verwendet. Eine Qualitätsprüfung mit zurückgehaltenen Ansichten wurde nicht durchgeführt."))
        } else {
            paragraphs.append(text("No training profile has been applied. The capture is saved, but a processed Gaussian scene has not yet been created.",
                "Es wurde noch kein Berechnungsprofil angewendet. Die Aufnahme ist gespeichert; eine berechnete Gaussian-Szene wurde noch nicht erstellt."))
        }
        paragraphs.append(text("Recorded status: \(p.phase.rawValue). The latest recorded model contains \(p.splatCount) Gaussians. Recorded processing time after engine initialization totals \(number(p.processingSeconds)) seconds, including intermediate checkpoint/export work. The scene export is \(p.hasResult ? "available" : "not available").",
            "Protokollierter Status: \(p.phase.rawValue). Das zuletzt protokollierte Modell enthält \(p.splatCount) Gaussians. Die erfasste Verarbeitungszeit nach Initialisierung der Engine beträgt insgesamt \(number(p.processingSeconds)) Sekunden einschließlich zwischenzeitlicher Sicherungs-/Exportarbeit. Der Szenenexport ist \(p.hasResult ? "vorhanden" : "nicht vorhanden")."))
        if let issue = p.lastIssue { paragraphs.append(text("Last recorded issue or pause reason: \(issue).", "Zuletzt protokollierter Fehler oder Pausengrund: \(issue).")) }
        paragraphs.append(text("Coordinates and limits", "Koordinaten und Grenzen"))
        paragraphs.append(text("Capture and Gaussian PLY use the local ARKit coordinate frame in metres, with Y pointing up and no map reference, EPSG code or north alignment. Camera matrices use the OpenGL convention. The engine centres/scales data internally and restores the original coordinate frame on export (keepCrs=true). This differs from the separate point-cloud mode's Z-up export. Camera poses were taken from ARKit without a separate bundle adjustment or subsequent drift correction. Gaussian optimization may move centres away from measured depth points. No independent metric accuracy, complete coverage or survey suitability was established.",
            "Aufnahme und Gaussian-PLY verwenden das lokale ARKit-Koordinatensystem in Metern mit Y nach oben, ohne Kartenbezug, EPSG-Code oder Nordausrichtung. Die Kameramatrizen folgen der OpenGL-Konvention. Die Engine zentriert/skaliert intern und stellt beim Export das ursprüngliche Koordinatensystem wieder her (keepCrs=true). Dies unterscheidet sich vom Z-oben-Export des separaten Punktwolkenmodus. Kameraposen wurden aus ARKit übernommen, ohne separate Bündelausgleichung oder nachträgliche Driftkorrektur. Die Optimierung kann Gaussian-Zentren gegenüber gemessenen Tiefenpunkten verschieben. Unabhängige metrische Genauigkeit, vollständige Abdeckung oder Vermessungseignung wurden nicht nachgewiesen."))
        paragraphs.append(text("All capture, processing and report generation took place on the device. The app made no upload for these operations. Sharing is initiated separately by the user through the system share sheet. The images and transforms.json can be exported for processing in other software. scan.json stores the full parameters; events.jsonl stores chronological decisions, steps and errors. SHA-256 checksums identify file contents; the linked event hashes are not a digital signature. GPU floating-point accumulation and random camera sampling mean rerunning training need not produce a bit-identical result.",
            "Aufnahme, Verarbeitung und Berichtserstellung erfolgten auf dem Gerät. Die App führte dafür keinen Upload aus. Eine Weitergabe erfolgt separat auf Initiative des Nutzers über den Systemdialog. Bilder und transforms.json können zur Verarbeitung in anderer Software exportiert werden. scan.json enthält die vollständigen Parameter; events.jsonl enthält zeitlich geordnete Entscheidungen, Schritte und Fehler. SHA-256-Prüfsummen identifizieren Dateiinhalte; die verketteten Ereignisprüfsummen sind keine digitale Signatur. GPU-Gleitkommaoperationen und zufällige Kameraauswahl können bei wiederholter Berechnung zu nicht bitidentischen Ergebnissen führen."))
        paragraphs.append(text("Technical record", "Technischer Datensatz"))
        paragraphs.append("Engine: \(p.engineRevision)\nViewer: \(p.viewerRevision)\nPLY SHA-256: \(p.resultHash ?? "—")\nSeed SHA-256: \(p.seedHash ?? "—")\nCheckpoint SHA-256: \(p.checkpointHash ?? "—")\nAudit head: \(p.auditHead)")
        if let profile = p.profile, let data = try? GaussianStore.encoder.encode(profile), let json = String(data: data, encoding: .utf8) {
            paragraphs.append(json)
        }
        return paragraphs
    }

    static func gaussian(_ project: GaussianProject) throws -> URL {
        try pdf(paragraphs: gaussianParagraphs(project), name: "Scan-report-\(project.id.uuidString.prefix(8))")
    }

    static func pointCloud(_ scan: SavedScan) throws -> URL {
        let p = scan.metadata
        let paragraphs = [
            text("Point cloud — processing report", "Punktwolke – Verarbeitungsbericht"),
            text("Scan “\(p.title)” (\(p.scanID.uuidString)) started at \(date(p.startedAt)) and was saved at \(date(p.savedAt)). The recorded app version is \(p.appVersion), build \(p.appBuild ?? "unknown"), on \(p.deviceModel), iOS \(p.systemVersion).",
                "Der Scan „\(p.title)“ (\(p.scanID.uuidString)) wurde am \(date(p.startedAt)) begonnen und am \(date(p.savedAt)) gespeichert. Protokolliert sind App-Version \(p.appVersion), Build \(p.appBuild ?? "unbekannt"), Gerät \(p.deviceModel) und iOS \(p.systemVersion)."),
            text("The recorded capture contains \(p.pointCount) retained points from \(p.processedFrames) processed depth frames and \(p.acceptedSamples) accepted sample updates. Recorded active capture time is \(number(p.activeSeconds)) seconds. The depth-image resolution was \(p.depthWidth) × \(p.depthHeight) pixels. Depth came from ARKit sceneDepth, Apple's combined LiDAR/camera estimate.",
                "Protokolliert sind \(p.pointCount) beibehaltene Punkte aus \(p.processedFrames) verarbeiteten Tiefenbildern und \(p.acceptedSamples) akzeptierten Messpunktaktualisierungen. Die erfasste aktive Aufnahmezeit beträgt \(number(p.activeSeconds)) Sekunden. Die Tiefenbildauflösung war \(p.depthWidth) × \(p.depthHeight) Pixel. Die Tiefe stammt aus ARKit sceneDepth, Apples kombinierter LiDAR-/Kameraschätzung."),
            text("Sampling used a voxel size of \(p.settings.voxelCentimeters) centimetres, a minimum depth of 0.2 metres, a maximum depth of \(p.settings.maxDepth) metres, pixel step \(p.settings.pixelStep) and minimum confidence \(p.settings.minConfidence). The point limit was \(p.settings.maxPoints) (zero means automatic memory monitoring). One observation was retained per voxel; a later observation replaced it only if it had higher confidence. There was no averaging or surface reconstruction.",
                "Die Auswahl verwendete eine Voxelgröße von \(p.settings.voxelCentimeters) Zentimetern, eine Mindesttiefe von 0,2 Metern, eine Höchsttiefe von \(p.settings.maxDepth) Metern, einen Pixelabstand von \(p.settings.pixelStep) und eine Mindestkonfidenz von \(p.settings.minConfidence). Das Punktlimit betrug \(p.settings.maxPoints) (null bedeutet automatische Speicherüberwachung). Pro Voxel wurde eine Beobachtung beibehalten; eine spätere Beobachtung ersetzte diese nur bei höherer Konfidenz. Es erfolgten weder Mittelwertbildung noch Oberflächenrekonstruktion."),
            text("Export coordinates are local and right-handed, in metres with Z pointing up. The transformation from ARKit is (x, y, z) → (x, −z, y). There is no map reference, EPSG code or north alignment. Binary and text PLY preserve RGB color and categorical confidence; XYZ contains coordinates only. Color came from the camera image and was not radiometrically calibrated.",
                "Exportkoordinaten sind lokal und rechtshändig, in Metern mit Z nach oben. Die Transformation aus ARKit lautet (x, y, z) → (x, −z, y). Es bestehen weder Kartenbezug noch EPSG-Code oder Nordausrichtung. Binär- und Text-PLY enthalten RGB-Farbe und kategoriale Konfidenz; XYZ enthält nur Koordinaten. Die Farbe stammt aus dem Kamerabild und wurde nicht radiometrisch kalibriert."),
            text("Recorded session note: \(p.sessionNote)", "Protokollierter Sitzungsvermerk: \(p.sessionNote)"),
            text("This report uses the metadata saved with the point cloud. This mode does not save RGB keyframes, camera poses or individual frame-selection decisions. These cannot be reconstructed from the export. No independent metric accuracy or complete coverage was measured. The scan was processed locally; sharing takes place only when requested by the user.",
                "Dieser Bericht verwendet die mit der Punktwolke gespeicherten Metadaten. Dieser Modus speichert keine RGB-Einzelbilder, Kameraposen oder einzelnen Bildauswahlentscheidungen. Diese lassen sich aus dem Export nicht rekonstruieren. Unabhängige metrische Genauigkeit oder vollständige Abdeckung wurden nicht gemessen. Der Scan wurde lokal verarbeitet; eine Weitergabe erfolgt auf Wunsch des Nutzers."),
            "metadata.json:\n" + (String(data: try GaussianStore.encoder.encode(p), encoding: .utf8) ?? "")
        ]
        return try pdf(paragraphs: paragraphs, name: "Point-cloud-report-\(p.scanID.uuidString.prefix(8))")
    }

    static func pdf(paragraphs: [String], name: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name + ".pdf")
        let paragraphStyle = NSMutableParagraphStyle(); paragraphStyle.lineSpacing = 4; paragraphStyle.paragraphSpacing = 12
        let content = NSMutableAttributedString(string: paragraphs.joined(separator: "\n\n"), attributes: [
            .font: UIFont.systemFont(ofSize: 11), .foregroundColor: UIColor.black, .paragraphStyle: paragraphStyle
        ])
        if let title = paragraphs.first { content.addAttribute(.font, value: UIFont.boldSystemFont(ofSize: 19), range: NSRange(location: 0, length: (title as NSString).length)) }
        let setter = CTFramesetterCreateWithAttributedString(content)
        let bounds = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        try renderer.writePDF(to: url) { output in
            var offset = 0; var page = 0
            while offset < content.length {
                output.beginPage(); page += 1
                let cg = output.cgContext
                cg.saveGState(); cg.translateBy(x: 0, y: bounds.height); cg.scaleBy(x: 1, y: -1)
                let path = CGPath(rect: CGRect(x: 44, y: 52, width: 507, height: 744), transform: nil)
                let frame = CTFramesetterCreateFrame(setter, CFRange(location: offset, length: 0), path, nil)
                CTFrameDraw(frame, cg); let visible = CTFrameGetVisibleStringRange(frame)
                cg.restoreGState()
                let footer = "LiDAR-Scanner · \(page)"
                (footer as NSString).draw(at: CGPoint(x: 44, y: 810), withAttributes: [.font: UIFont.systemFont(ofSize: 9), .foregroundColor: UIColor.darkGray])
                guard visible.length > 0 else { break }
                offset += visible.length
            }
        }
        return url
    }
}
