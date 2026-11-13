import Foundation
import UIKit
import simd

struct ReportFigure {
    let id: String
    let title: String
    let caption: String
    let pngData: Data
    let pixelWidth: Int
    let pixelHeight: Int
}

enum ReportPreviewRenderer {
    private static let renderSize = CGSize(width: 1080, height: 640)
    private static let keyframeSize = CGSize(width: 1080, height: 340)

    static func pointCloudFigures(for scan: SavedScan) -> [ReportFigure] {
        let points = ScanStorage.readPreview(for: scan, maxPoints: 35_000)
        let gcps = scan.metadata.groundControlPoints ?? []
        let annotations = scan.metadata.annotations ?? []
        guard !points.isEmpty || !gcps.isEmpty || !annotations.isEmpty else { return [] }

        var figures: [ReportFigure] = []
        if let img3D = renderPerspective(
            points: points,
            gcps: gcps,
            annotations: annotations,
            title: loc("3D Perspective View", "3D-Perspektivansicht")
        ), let data3D = img3D.pngData() {
            figures.append(ReportFigure(
                id: "pc-3d",
                title: loc("3D Perspective Preview", "3D-Perspektivvorschau"),
                caption: loc(
                    "Oblique 3D point-cloud preview showing sampled color points, ground control points, and annotations.",
                    "Schräge 3D-Punktwolkenvorschau mit abgetasteten Farbpunkten, Passpunkten und Annotationen."
                ),
                pngData: data3D,
                pixelWidth: Int(renderSize.width),
                pixelHeight: Int(renderSize.height)
            ))
        }

        if let imgPlan = renderTopDown(
            points: points,
            gcps: gcps,
            annotations: annotations,
            title: loc("Top-Down Plan View (Z↑)", "Grundrissansicht / Draufsicht (Z↑)"),
            verticalAxisLabel: "+Y"
        ), let dataPlan = imgPlan.pngData() {
            figures.append(ReportFigure(
                id: "pc-plan",
                title: loc("Planimetric Overview (Local XY)", "Grundrissübersicht (lokal XY)"),
                caption: loc(
                    "Orthographic top-down projection in local metric coordinates (Z pointing up) with approximate scale bar.",
                    "Orthografische Draufsicht in lokalen Meterkoordinaten (Z nach oben) mit Maßstabsleiste."
                ),
                pngData: dataPlan,
                pixelWidth: Int(renderSize.width),
                pixelHeight: Int(renderSize.height)
            ))
        }
        return figures
    }

    static func gaussianFigures(for project: GaussianProject) -> [ReportFigure] {
        var figures: [ReportFigure] = []

        var splatPoints: [PCPoint] = []
        if project.hasResult {
            splatPoints = readGaussianPLYPoints(from: project.resultURL, maxPoints: 35_000)
        }
        if splatPoints.isEmpty, let seedName = project.seedFile {
            let seedURL = project.directory.appendingPathComponent(seedName)
            if FileManager.default.fileExists(atPath: seedURL.path) {
                splatPoints = readGaussianPLYPoints(from: seedURL, maxPoints: 35_000)
            }
        }

        let annotations = project.annotations ?? []
        if !splatPoints.isEmpty || !annotations.isEmpty {
            if let img3D = renderPerspective(
                points: splatPoints,
                gcps: [],
                annotations: annotations,
                title: loc("3D Gaussian Splat Preview", "3D-Gaussian-Splat-Vorschau")
            ), let data3D = img3D.pngData() {
                figures.append(ReportFigure(
                    id: "gs-3d",
                    title: loc("3D Scene Preview", "3D-Szenenvorschau"),
                    caption: loc(
                        "Oblique 3D projection of reconstructed Gaussian centers with overlaid 3D annotations.",
                        "Schräge 3D-Projektion der rekonstruierten Gaussian-Zentren mit überlagerten 3D-Annotationen."
                    ),
                    pngData: data3D,
                    pixelWidth: Int(renderSize.width),
                    pixelHeight: Int(renderSize.height)
                ))
            }

            if let imgPlan = renderTopDown(
                points: splatPoints,
                gcps: [],
                annotations: annotations,
                title: loc("Top-Down Plan View (Y↑)", "Grundrissansicht / Draufsicht (Y↑)"),
                verticalAxisLabel: "-Z"
            ), let dataPlan = imgPlan.pngData() {
                figures.append(ReportFigure(
                    id: "gs-plan",
                    title: loc("Planimetric Overview (Local XZ)", "Grundrissübersicht (lokal XZ)"),
                    caption: loc(
                        "Orthographic top-down projection in ARKit coordinates (Y pointing up) with approximate scale bar.",
                        "Orthografische Draufsicht im ARKit-Koordinatensystem (Y nach oben) mit Maßstabsleiste."
                    ),
                    pngData: dataPlan,
                    pixelWidth: Int(renderSize.width),
                    pixelHeight: Int(renderSize.height)
                ))
            }
        }

        if let keyframesImage = renderKeyframeStrip(for: project),
           let keyframePNG = keyframesImage.pngData() {
            let total = project.frames.count
            figures.append(ReportFigure(
                id: "gs-frames",
                title: loc("Sampled Capture Views", "Ausgewählte Aufnahmeperspektiven"),
                caption: loc(
                    "Representative RGB input frames selected from \(total) saved views.",
                    "Repräsentative RGB-Eingabebilder aus insgesamt \(total) gespeicherten Ansichten."
                ),
                pngData: keyframePNG,
                pixelWidth: Int(keyframeSize.width),
                pixelHeight: Int(keyframeSize.height)
            ))
        }

        return figures
    }

    // MARK: - Scene Bounds & Projection

    private struct Bounds {
        var min: SIMD3<Float>
        var max: SIMD3<Float>
        var center: SIMD3<Float> { (min + max) * 0.5 }
        var extent: SIMD3<Float> { simd_max(max - min, SIMD3<Float>(repeating: 0.1)) }
        var maxDimension: Float { Swift.max(extent.x, Swift.max(extent.y, extent.z)) }
    }

    private static func computeBounds(points: [PCPoint], gcps: [GroundControlPoint], annotations: [CloudAnnotation]) -> Bounds? {
        var low = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var high = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        var any = false

        for p in points {
            let v = SIMD3<Float>(p.x, p.y, p.z)
            if v.x.isFinite && v.y.isFinite && v.z.isFinite {
                low = simd_min(low, v)
                high = simd_max(high, v)
                any = true
            }
        }
        for gcp in gcps {
            let v = gcp.arkitPosition
            low = simd_min(low, v); high = simd_max(high, v); any = true
        }
        for ann in annotations {
            for v in ann.vertices {
                let p = v.arkitPosition
                low = simd_min(low, p); high = simd_max(high, p); any = true
            }
        }
        return any ? Bounds(min: low, max: high) : nil
    }

    private static func renderPerspective(
        points: [PCPoint],
        gcps: [GroundControlPoint],
        annotations: [CloudAnnotation],
        title: String
    ) -> UIImage? {
        guard let bounds = computeBounds(points: points, gcps: gcps, annotations: annotations) else { return nil }
        let center = bounds.center
        let radius = Swift.max(0.25, bounds.maxDimension * 0.5)
        let yaw: Float = 0.62
        let pitch: Float = 0.44
        let cy = cos(yaw), sy = sin(yaw)
        let cp = cos(pitch), sp = sin(pitch)

        func rotate(_ p: SIMD3<Float>) -> SIMD3<Float> {
            let rel = p - center
            let x1 = rel.x * cy - rel.z * sy
            let z1 = rel.x * sy + rel.z * cy
            let y2 = rel.y * cp - z1 * sp
            let z2 = rel.y * sp + z1 * cp
            return SIMD3<Float>(x1, y2, z2)
        }

        let drawRect = CGRect(x: 42, y: 54, width: renderSize.width - 84, height: renderSize.height - 86)
        let camDist = radius * 3.1
        let focal = Float(Swift.min(drawRect.width, drawRect.height)) * 0.92

        func project(_ world: SIMD3<Float>) -> (point: CGPoint, depth: Float)? {
            let r = rotate(world)
            let depth = camDist - r.z
            guard depth > 0.05 else { return nil }
            let scale = (focal / radius) * (camDist / depth) * 0.56
            let x = drawRect.midX + CGFloat(r.x * scale)
            let y = drawRect.midY - CGFloat(r.y * scale)
            return (CGPoint(x: x, y: y), depth)
        }

        struct ProjectedPoint {
            let x: CGFloat
            let y: CGFloat
            let depth: Float
            let r: CGFloat
            let g: CGFloat
            let b: CGFloat
        }

        var projected: [ProjectedPoint] = []
        projected.reserveCapacity(points.count)
        for pt in points {
            let w = SIMD3<Float>(pt.x, pt.y, pt.z)
            if let p = project(w) {
                projected.append(ProjectedPoint(
                    x: p.point.x, y: p.point.y, depth: p.depth,
                    r: CGFloat(pt.r) / 255.0, g: CGFloat(pt.g) / 255.0, b: CGFloat(pt.b) / 255.0
                ))
            }
        }
        projected.sort { $0.depth > $1.depth }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: renderSize, format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            drawCanvasChrome(in: cg, size: renderSize, title: title)

            cg.saveGState()
            cg.clip(to: CGRect(x: 16, y: 42, width: renderSize.width - 32, height: renderSize.height - 56))
            let dotSize: CGFloat = projected.count > 18_000 ? 2.4 : 3.2
            for p in projected {
                cg.setFillColor(red: p.r, green: p.g, blue: p.b, alpha: 0.95)
                cg.fillEllipse(in: CGRect(x: p.x - dotSize * 0.5, y: p.y - dotSize * 0.5, width: dotSize, height: dotSize))
            }

            drawOverlays(
                in: cg,
                gcps: gcps,
                annotations: annotations,
                projector: { project($0)?.point }
            )
            cg.restoreGState()

            // Mini 3D axis gizmo bottom-left
            drawAxisGizmo(in: cg, origin: CGPoint(x: 48, y: renderSize.height - 38), rotate: rotate)
        }
    }

    private static func renderTopDown(
        points: [PCPoint],
        gcps: [GroundControlPoint],
        annotations: [CloudAnnotation],
        title: String,
        verticalAxisLabel: String
    ) -> UIImage? {
        guard let bounds = computeBounds(points: points, gcps: gcps, annotations: annotations) else { return nil }
        let drawRect = CGRect(x: 46, y: 56, width: renderSize.width - 92, height: renderSize.height - 102)
        // ARKit ground plane: horizontal = X, vertical = -Z (north/forward up)
        let spanX = Swift.max(0.25, bounds.max.x - bounds.min.x)
        let spanZ = Swift.max(0.25, bounds.max.z - bounds.min.z)
        let cx = (bounds.min.x + bounds.max.x) * 0.5
        let cz = (bounds.min.z + bounds.max.z) * 0.5
        let pixelsPerMeter = Swift.min(drawRect.width / CGFloat(spanX), drawRect.height / CGFloat(spanZ)) * 0.92

        func project(_ world: SIMD3<Float>) -> CGPoint {
            let px = drawRect.midX + CGFloat(world.x - cx) * pixelsPerMeter
            let py = drawRect.midY + CGFloat(world.z - cz) * pixelsPerMeter
            return CGPoint(x: px, y: py)
        }

        // Sort points bottom-to-top by elevation (world.y) so top surfaces paint cleanly over floor
        let sorted = points.sorted { $0.y < $1.y }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: renderSize, format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            drawCanvasChrome(in: cg, size: renderSize, title: title)

            cg.saveGState()
            cg.clip(to: CGRect(x: 16, y: 42, width: renderSize.width - 32, height: renderSize.height - 56))
            let dotSize: CGFloat = sorted.count > 18_000 ? 2.4 : 3.2
            for pt in sorted {
                let p = project(SIMD3<Float>(pt.x, pt.y, pt.z))
                cg.setFillColor(
                    red: CGFloat(pt.r) / 255.0,
                    green: CGFloat(pt.g) / 255.0,
                    blue: CGFloat(pt.b) / 255.0,
                    alpha: 0.95
                )
                cg.fillEllipse(in: CGRect(x: p.x - dotSize * 0.5, y: p.y - dotSize * 0.5, width: dotSize, height: dotSize))
            }

            drawOverlays(
                in: cg,
                gcps: gcps,
                annotations: annotations,
                projector: { project($0) }
            )
            cg.restoreGState()

            drawScaleBar(in: cg, pixelsPerMeter: pixelsPerMeter, bottomRight: CGPoint(x: renderSize.width - 34, y: renderSize.height - 32))
            drawPlanCompass(in: cg, origin: CGPoint(x: 42, y: renderSize.height - 34), verticalLabel: verticalAxisLabel)
        }
    }

    private static func renderKeyframeStrip(for project: GaussianProject) -> UIImage? {
        guard !project.frames.isEmpty else { return nil }
        let candidateIndices: [Int]
        if project.frames.count <= 3 {
            candidateIndices = Array(project.frames.indices)
        } else {
            candidateIndices = [0, project.frames.count / 2, project.frames.count - 1]
        }

        var loaded: [(index: Int, image: UIImage)] = []
        for idx in candidateIndices {
            let url = project.directory.appendingPathComponent(project.frames[idx].file_path)
            if let img = UIImage(contentsOfFile: url.path) {
                loaded.append((idx + 1, img))
            }
        }
        guard !loaded.isEmpty else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: keyframeSize, format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            drawCanvasChrome(
                in: cg,
                size: keyframeSize,
                title: loc("Captured Input Keyframes", "Erfasste Eingabe-Ansichten")
            )

            let pad: CGFloat = 22
            let gap: CGFloat = 14
            let count = CGFloat(loaded.count)
            let slotWidth = (keyframeSize.width - pad * 2 - gap * (count - 1)) / count
            let slotTop: CGFloat = 52
            let slotHeight = keyframeSize.height - slotTop - 22

            for (i, item) in loaded.enumerated() {
                let rect = CGRect(
                    x: pad + CGFloat(i) * (slotWidth + gap),
                    y: slotTop,
                    width: slotWidth,
                    height: slotHeight
                )
                let clip = UIBezierPath(roundedRect: rect, cornerRadius: 10)
                cg.saveGState()
                clip.addClip()
                let imgSize = item.image.size
                let scale = max(rect.width / max(1, imgSize.width), rect.height / max(1, imgSize.height))
                let drawSize = CGSize(width: imgSize.width * scale, height: imgSize.height * scale)
                let drawRect = CGRect(
                    x: rect.midX - drawSize.width * 0.5,
                    y: rect.midY - drawSize.height * 0.5,
                    width: drawSize.width,
                    height: drawSize.height
                )
                item.image.draw(in: drawRect)
                cg.restoreGState()

                cg.setStrokeColor(UIColor.white.withAlphaComponent(0.24).cgColor)
                cg.setLineWidth(1)
                clip.stroke()

                let badgeText = loc("View #%d", "Ansicht #%d", item.index) as NSString
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont(name: "HelveticaNeue-Bold", size: 12) ?? UIFont.systemFont(ofSize: 12, weight: .bold),
                    .foregroundColor: UIColor.white
                ]
                let textSize = badgeText.size(withAttributes: attrs)
                let pillRect = CGRect(x: rect.minX + 10, y: rect.maxY - textSize.height - 16, width: textSize.width + 14, height: textSize.height + 6)
                cg.setFillColor(UIColor.black.withAlphaComponent(0.68).cgColor)
                UIBezierPath(roundedRect: pillRect, cornerRadius: 6).fill()
                badgeText.draw(at: CGPoint(x: pillRect.minX + 7, y: pillRect.minY + 3), withAttributes: attrs)
            }
        }
    }

    // MARK: - Canvas Helpers

    private static func drawCanvasChrome(in cg: CGContext, size: CGSize, title: String) {
        let bg = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 14)
        cg.setFillColor(UIColor(red: 0.055, green: 0.082, blue: 0.106, alpha: 1.0).cgColor)
        bg.fill()

        // Subtle grid
        cg.setStrokeColor(UIColor.white.withAlphaComponent(0.05).cgColor)
        cg.setLineWidth(1)
        var x: CGFloat = 60
        while x < size.width {
            cg.move(to: CGPoint(x: x, y: 42))
            cg.addLine(to: CGPoint(x: x, y: size.height - 16))
            x += 60
        }
        var y: CGFloat = 90
        while y < size.height - 16 {
            cg.move(to: CGPoint(x: 16, y: y))
            cg.addLine(to: CGPoint(x: size.width - 16, y: y))
            y += 60
        }
        cg.strokePath()

        let titleFont = UIFont(name: "HelveticaNeue-Medium", size: 15) ?? UIFont.systemFont(ofSize: 15, weight: .medium)
        (title as NSString).draw(at: CGPoint(x: 20, y: 14), withAttributes: [
            .font: titleFont,
            .foregroundColor: UIColor(white: 0.92, alpha: 1.0)
        ])
    }

    private static func drawOverlays(
        in cg: CGContext,
        gcps: [GroundControlPoint],
        annotations: [CloudAnnotation],
        projector: (SIMD3<Float>) -> CGPoint?
    ) {
        let labelFont = UIFont(name: "HelveticaNeue-Bold", size: 12) ?? UIFont.systemFont(ofSize: 12, weight: .bold)

        // Annotations
        for ann in annotations where !ann.vertices.isEmpty {
            let color = ann.color.uiColor
            let pts = ann.vertices.compactMap { projector($0.arkitPosition) }
            guard !pts.isEmpty else { continue }

            if ann.type == .polygon, pts.count >= 2 {
                let path = UIBezierPath()
                path.move(to: pts[0])
                for p in pts.dropFirst() { path.addLine(to: p) }
                if pts.count >= 3 {
                    path.close()
                    cg.setFillColor(color.withAlphaComponent(0.24).cgColor)
                    path.fill()
                }
                cg.setStrokeColor(color.cgColor)
                cg.setLineWidth(2.5)
                path.stroke()
            }

            for p in pts {
                let r: CGFloat = ann.type == .point ? 6.5 : 4.0
                cg.setFillColor(color.cgColor)
                cg.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                cg.setStrokeColor(UIColor.white.cgColor)
                cg.setLineWidth(1.5)
                cg.strokeEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            }

            if let c = projector(ann.centroid.arkitPosition) {
                drawTagPill(text: ann.title, accent: color, at: CGPoint(x: c.x, y: c.y - 14), font: labelFont, in: cg)
            }
        }

        // GCPs
        let orange = UIColor.systemOrange
        for gcp in gcps {
            guard let p = projector(gcp.arkitPosition) else { continue }
            let tri = UIBezierPath()
            tri.move(to: CGPoint(x: p.x, y: p.y - 8))
            tri.addLine(to: CGPoint(x: p.x - 7, y: p.y + 6))
            tri.addLine(to: CGPoint(x: p.x + 7, y: p.y + 6))
            tri.close()
            cg.setFillColor(orange.cgColor)
            tri.fill()
            cg.setStrokeColor(UIColor.white.cgColor)
            cg.setLineWidth(1.5)
            tri.stroke()
            drawTagPill(text: gcp.label, accent: orange, at: CGPoint(x: p.x, y: p.y - 16), font: labelFont, in: cg)
        }
    }

    private static func drawTagPill(text: String, accent: UIColor, at center: CGPoint, font: UIFont, in cg: CGContext) {
        let ns = text as NSString
        let size = ns.size(withAttributes: [.font: font])
        let rect = CGRect(
            x: center.x - size.width * 0.5 - 8,
            y: center.y - size.height - 6,
            width: size.width + 16,
            height: size.height + 6
        )
        let pill = UIBezierPath(roundedRect: rect, cornerRadius: 7)
        cg.setFillColor(UIColor.black.withAlphaComponent(0.75).cgColor)
        pill.fill()
        cg.setStrokeColor(accent.cgColor)
        cg.setLineWidth(1.4)
        pill.stroke()
        ns.draw(at: CGPoint(x: rect.minX + 8, y: rect.minY + 3), withAttributes: [
            .font: font,
            .foregroundColor: UIColor.white
        ])
    }

    private static func drawScaleBar(in cg: CGContext, pixelsPerMeter: CGFloat, bottomRight: CGPoint) {
        guard pixelsPerMeter.isFinite, pixelsPerMeter > 2 else { return }
        let candidates: [CGFloat] = [0.1, 0.25, 0.5, 1, 2, 5, 10, 20]
        let chosenMeters = candidates.first(where: { $0 * pixelsPerMeter >= 90 }) ?? 1.0
        let barWidth = Swift.min(240, Swift.max(60, chosenMeters * pixelsPerMeter))
        let labelStr = chosenMeters < 1
            ? String(format: "%.2g m", Double(chosenMeters))
            : String(format: "%.0f m", Double(chosenMeters))

        let startX = bottomRight.x - barWidth
        let y = bottomRight.y
        cg.setStrokeColor(UIColor.white.cgColor)
        cg.setLineWidth(2.2)
        cg.move(to: CGPoint(x: startX, y: y - 6))
        cg.addLine(to: CGPoint(x: startX, y: y))
        cg.addLine(to: CGPoint(x: bottomRight.x, y: y))
        cg.addLine(to: CGPoint(x: bottomRight.x, y: y - 6))
        cg.strokePath()

        let font = UIFont(name: "HelveticaNeue-Medium", size: 12) ?? UIFont.systemFont(ofSize: 12, weight: .medium)
        let ns = labelStr as NSString
        let size = ns.size(withAttributes: [.font: font])
        ns.draw(at: CGPoint(x: startX + (barWidth - size.width) * 0.5, y: y - size.height - 6), withAttributes: [
            .font: font,
            .foregroundColor: UIColor.white
        ])
    }

    private static func drawPlanCompass(in cg: CGContext, origin: CGPoint, verticalLabel: String) {
        let len: CGFloat = 24
        let font = UIFont(name: "HelveticaNeue-Bold", size: 11) ?? UIFont.systemFont(ofSize: 11, weight: .bold)
        cg.setLineWidth(2)
        cg.setStrokeColor(UIColor.systemRed.cgColor)
        cg.move(to: origin); cg.addLine(to: CGPoint(x: origin.x + len, y: origin.y)); cg.strokePath()
        ("+X" as NSString).draw(at: CGPoint(x: origin.x + len + 4, y: origin.y - 7), withAttributes: [.font: font, .foregroundColor: UIColor.systemRed])

        cg.setStrokeColor(UIColor.systemGreen.cgColor)
        cg.move(to: origin); cg.addLine(to: CGPoint(x: origin.x, y: origin.y - len)); cg.strokePath()
        (verticalLabel as NSString).draw(at: CGPoint(x: origin.x - 8, y: origin.y - len - 15), withAttributes: [.font: font, .foregroundColor: UIColor.systemGreen])
    }

    private static func drawAxisGizmo(in cg: CGContext, origin: CGPoint, rotate: (SIMD3<Float>) -> SIMD3<Float>) {
        let font = UIFont(name: "HelveticaNeue-Bold", size: 10) ?? UIFont.systemFont(ofSize: 10, weight: .bold)
        let axes: [(SIMD3<Float>, UIColor, String)] = [
            (SIMD3<Float>(1, 0, 0), .systemRed, "X"),
            (SIMD3<Float>(0, 1, 0), .systemGreen, "Y"),
            (SIMD3<Float>(0, 0, 1), .systemCyan, "Z")
        ]
        cg.setLineWidth(2)
        for (dir, color, name) in axes {
            let r = rotate(dir) - rotate(.zero)
            let end = CGPoint(x: origin.x + CGFloat(r.x) * 24, y: origin.y - CGFloat(r.y) * 24)
            cg.setStrokeColor(color.cgColor)
            cg.move(to: origin); cg.addLine(to: end); cg.strokePath()
            (name as NSString).draw(at: CGPoint(x: end.x + 3, y: end.y - 6), withAttributes: [.font: font, .foregroundColor: color])
        }
    }

    // MARK: - Synchronous Gaussian / Seed PLY Point Reader

    private static func readGaussianPLYPoints(from url: URL, maxPoints: Int) -> [PCPoint] {
        guard let file = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? file.close() }
        guard let headData = try? file.read(upToCount: 32_768), !headData.isEmpty else { return [] }

        let marker = Data("end_header\n".utf8)
        let markerCRLF = Data("end_header\r\n".utf8)
        let headerRange: Range<Data.Index>
        let bodyOffset: Int
        if let r = headData.range(of: marker) {
            headerRange = headData.startIndex..<r.lowerBound
            bodyOffset = r.upperBound
        } else if let r = headData.range(of: markerCRLF) {
            headerRange = headData.startIndex..<r.lowerBound
            bodyOffset = r.upperBound
        } else {
            return []
        }

        guard let headerText = String(data: headData.subdata(in: headerRange), encoding: .utf8) else { return [] }
        var isBinaryLE = false
        var vertexCount = 0
        var inVertex = false
        var offset = 0
        var props: [String: (type: String, offset: Int)] = [:]

        for rawLine in headerText.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("format ") {
                if line.contains("binary_little_endian") { isBinaryLE = true }
                else if !line.contains("ascii") { return [] }
            } else if line.hasPrefix("element ") {
                let parts = line.split(separator: " ")
                if parts.count >= 3 && parts[1] == "vertex", let cnt = Int(parts[2]) {
                    vertexCount = cnt
                    inVertex = true
                } else {
                    inVertex = false
                }
            } else if inVertex && line.hasPrefix("property ") {
                let parts = line.split(separator: " ").map(String.init)
                guard parts.count >= 3, parts[1] != "list" else { continue }
                let type = parts[1]
                let name = parts[2]
                let size = plyTypeSize(type)
                guard size > 0 else { return [] }
                props[name] = (type, offset)
                offset += size
            }
        }

        guard vertexCount > 0,
              let px = props["x"], let py = props["y"], let pz = props["z"] else { return [] }

        if !isBinaryLE {
            return []
        }
        let recordSize = offset
        guard recordSize > 0 else { return [] }
        do { try file.seek(toOffset: UInt64(bodyOffset)) } catch { return [] }

        let targetCount = min(maxPoints, vertexCount)
        var result: [PCPoint] = []
        result.reserveCapacity(targetCount)

        let chunkSize = max(recordSize, (65_536 / recordSize) * recordSize)
        var remainder = Data()
        var vertexIndex = 0
        var sampled = 0
        var nextSampleIndex = 0

        let shCoeff: Float = 0.28209479177387814
        let fdc0 = props["f_dc_0"]
        let fdc1 = props["f_dc_1"]
        let fdc2 = props["f_dc_2"]
        let redProp = props["red"]
        let greenProp = props["green"]
        let blueProp = props["blue"]

        while vertexIndex < vertexCount && result.count < targetCount {
            guard let chunk = try? file.read(upToCount: chunkSize), !chunk.isEmpty else { break }
            var buffer = remainder
            buffer.append(chunk)
            let usable = (buffer.count / recordSize) * recordSize
            let countInBuffer = min(usable / recordSize, vertexCount - vertexIndex)
            remainder = usable < buffer.count ? buffer.subdata(in: usable..<buffer.count) : Data()

            buffer.withUnsafeBytes { raw in
                for i in 0..<countInBuffer {
                    let globalIdx = vertexIndex + i
                    guard globalIdx == nextSampleIndex else { continue }
                    let base = i * recordSize
                    let x = readPLYFloat(raw, type: px.type, offset: base + px.offset)
                    let y = readPLYFloat(raw, type: py.type, offset: base + py.offset)
                    let z = readPLYFloat(raw, type: pz.type, offset: base + pz.offset)
                    let r, g, b: UInt8
                    if let c0 = fdc0, let c1 = fdc1, let c2 = fdc2 {
                        let fr = 0.5 + shCoeff * readPLYFloat(raw, type: c0.type, offset: base + c0.offset)
                        let fg = 0.5 + shCoeff * readPLYFloat(raw, type: c1.type, offset: base + c1.offset)
                        let fb = 0.5 + shCoeff * readPLYFloat(raw, type: c2.type, offset: base + c2.offset)
                        r = UInt8(clamping: Int((max(0, min(1, fr)) * 255.0).rounded()))
                        g = UInt8(clamping: Int((max(0, min(1, fg)) * 255.0).rounded()))
                        b = UInt8(clamping: Int((max(0, min(1, fb)) * 255.0).rounded()))
                    } else if let rp = redProp, let gp = greenProp, let bp = blueProp {
                        r = readPLYByte(raw, type: rp.type, offset: base + rp.offset)
                        g = readPLYByte(raw, type: gp.type, offset: base + gp.offset)
                        b = readPLYByte(raw, type: bp.type, offset: base + bp.offset)
                    } else {
                        r = 200; g = 210; b = 220
                    }
                    result.append(PCPoint(x: x, y: y, z: z, r: r, g: g, b: b, confidence: 2))
                    sampled += 1
                    if sampled >= targetCount { break }
                    nextSampleIndex = (targetCount == vertexCount) ? sampled : (sampled * vertexCount / targetCount)
                }
            }
            vertexIndex += countInBuffer
        }
        return result
    }

    private static func plyTypeSize(_ type: String) -> Int {
        switch type {
        case "char", "int8", "uchar", "uint8": return 1
        case "short", "int16", "ushort", "uint16": return 2
        case "int", "int32", "uint", "uint32", "float", "float32": return 4
        case "double", "float64": return 8
        default: return 0
        }
    }

    private static func readPLYFloat(_ raw: UnsafeRawBufferPointer, type: String, offset: Int) -> Float {
        switch type {
        case "float", "float32":
            var bits: UInt32 = 0
            memcpy(&bits, raw.baseAddress!.advanced(by: offset), 4)
            return Float(bitPattern: UInt32(littleEndian: bits))
        case "double", "float64":
            var bits: UInt64 = 0
            memcpy(&bits, raw.baseAddress!.advanced(by: offset), 8)
            return Float(Double(bitPattern: UInt64(littleEndian: bits)))
        default:
            return 0
        }
    }

    private static func readPLYByte(_ raw: UnsafeRawBufferPointer, type: String, offset: Int) -> UInt8 {
        switch type {
        case "uchar", "uint8":
            return raw.load(fromByteOffset: offset, as: UInt8.self)
        case "float", "float32":
            let v = readPLYFloat(raw, type: type, offset: offset)
            return UInt8(clamping: Int((max(0, min(1, v)) * 255.0).rounded()))
        default:
            return 200
        }
    }

    private static func loc(_ en: String, _ de: String, _ arg: Int? = nil) -> String {
        let template = LanguageManager.isGerman ? de : en
        if let arg {
            return String(format: template, arg)
        }
        return template
    }
}
