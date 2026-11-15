import Foundation
import CoreLocation
import MapKit
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
    private static let thumbnailSize = CGSize(width: 480, height: 320)

    static func pointCloudThumbnailImage(for scan: SavedScan, forceRefresh: Bool = false) -> UIImage? {
        if !forceRefresh,
           FileManager.default.fileExists(atPath: scan.previewImageURL.path),
           let cached = UIImage(contentsOfFile: scan.previewImageURL.path) {
            return cached
        }

        let points = ScanStorage.readPreview(for: scan, maxPoints: 16_000)
        let gcps = scan.metadata.groundControlPoints ?? []
        let annotations = scan.metadata.annotations ?? []

        var rendered: UIImage?
        if !points.isEmpty || !gcps.isEmpty || !annotations.isEmpty {
            rendered = renderPerspective(
                points: points,
                gcps: gcps,
                annotations: annotations,
                title: nil,
                canvasSize: thumbnailSize,
                includeChrome: false
            )
        } else if let firstImageURL = scan.imageURLs.first,
                  let source = UIImage(contentsOfFile: firstImageURL.path) {
            rendered = renderPhotoThumbnail(source, size: thumbnailSize)
        }

        if let rendered,
           let data = rendered.pngData(),
           FileManager.default.fileExists(atPath: scan.directory.path) {
            try? data.write(to: scan.previewImageURL, options: .atomic)
        }
        return rendered
    }

    static func writePointCloudThumbnail(for scan: SavedScan) {
        _ = pointCloudThumbnailImage(for: scan, forceRefresh: true)
    }

    static func gaussianThumbnailImage(for project: GaussianProject, forceRefresh: Bool = false) -> UIImage? {
        if !forceRefresh,
           FileManager.default.fileExists(atPath: project.previewImageURL.path),
           let cached = UIImage(contentsOfFile: project.previewImageURL.path) {
            return cached
        }

        var splatPoints: [PCPoint] = []
        if project.hasResult {
            splatPoints = readGaussianPLYPoints(from: project.resultURL, maxPoints: 16_000)
        }
        if splatPoints.isEmpty, let seedName = project.seedFile {
            let seedURL = project.directory.appendingPathComponent(seedName)
            if FileManager.default.fileExists(atPath: seedURL.path) {
                splatPoints = readGaussianPLYPoints(from: seedURL, maxPoints: 16_000)
            }
        }

        let annotations = project.annotations ?? []
        var rendered: UIImage?
        if !splatPoints.isEmpty || !annotations.isEmpty {
            rendered = renderPerspective(
                points: splatPoints,
                gcps: [],
                annotations: annotations,
                title: nil,
                canvasSize: thumbnailSize,
                includeChrome: false
            )
        } else {
            let candidateFrames: [GaussianFrame]
            if project.frames.isEmpty {
                candidateFrames = []
            } else {
                candidateFrames = [project.frames[project.frames.count / 2], project.frames[0]]
            }
            for frame in candidateFrames {
                let url = project.directory.appendingPathComponent(frame.file_path)
                if let img = UIImage(contentsOfFile: url.path) {
                    rendered = renderPhotoThumbnail(img, size: thumbnailSize)
                    break
                }
            }
        }

        if let rendered,
           let data = rendered.pngData(),
           FileManager.default.fileExists(atPath: project.directory.path) {
            try? data.write(to: project.previewImageURL, options: .atomic)
        }
        return rendered
    }

    static func writeGaussianThumbnail(for project: GaussianProject) {
        _ = gaussianThumbnailImage(for: project, forceRefresh: true)
    }

    static func pointCloudFigures(for scan: SavedScan) -> [ReportFigure] {
        let points = ScanStorage.readPreview(for: scan, maxPoints: 35_000)
        let gcps = scan.metadata.groundControlPoints ?? []
        let annotations = scan.metadata.annotations ?? []
        var figures: [ReportFigure] = []

        if !points.isEmpty || !gcps.isEmpty || !annotations.isEmpty {
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
        }

        if let locData = scan.metadata.location, locData.isValidCoordinate,
           let mapFig = renderLocationMapFigure(for: locData, scanTitle: scan.metadata.title) {
            figures.append(mapFig)
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

        if let locData = project.location, locData.isValidCoordinate,
           let mapFig = renderLocationMapFigure(for: locData, scanTitle: project.title) {
            figures.append(mapFig)
        }

        return figures
    }

    // MARK: - GNSS Location Map Figure

    static func renderLocationMapFigure(
        for location: GeoLocation,
        scanTitle: String,
        allowNetworkSnapshot: Bool = !Thread.isMainThread
    ) -> ReportFigure? {
        guard location.isValidCoordinate else { return nil }

        let mapRect = CGRect(x: 22, y: 48, width: renderSize.width - 44, height: renderSize.height - 114)
        let spanMeters = max(120.0, min(2000.0, location.horizontalAccuracy > 0 ? location.horizontalAccuracy * 8.0 : 200.0))

        var snapshot: MKMapSnapshotter.Snapshot?
        if allowNetworkSnapshot {
            let options = MKMapSnapshotter.Options()
            options.region = MKCoordinateRegion(
                center: location.coordinate,
                latitudinalMeters: spanMeters,
                longitudinalMeters: spanMeters * Double(mapRect.width / mapRect.height)
            )
            options.size = mapRect.size
            options.scale = 1.0
            options.mapType = .standard
            options.showsBuildings = true

            let semaphore = DispatchSemaphore(value: 0)
            let snapshotter = MKMapSnapshotter(options: options)
            snapshotter.start(with: DispatchQueue.global(qos: .userInitiated)) { result, _ in
                snapshot = result
                semaphore.signal()
            }
            if semaphore.wait(timeout: .now() + 2.5) == .timedOut {
                snapshotter.cancel()
            }
        }

        let mintColor = UIColor(red: 0.38, green: 0.93, blue: 0.76, alpha: 1.0)
        let cyanColor = UIColor.systemCyan
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: renderSize, format: format)

        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            drawCanvasChrome(in: cg, size: renderSize, title: loc("GNSS Location Map (WGS84)", "GNSS-Standortkarte (WGS84)"))

            let mapClip = UIBezierPath(roundedRect: mapRect, cornerRadius: 10)
            cg.saveGState()
            mapClip.addClip()

            let centerPoint: CGPoint
            let pixelsPerMeter: CGFloat

            if let snapshot {
                snapshot.image.draw(in: mapRect)
                let rawCenter = snapshot.point(for: location.coordinate)
                centerPoint = CGPoint(x: mapRect.minX + rawCenter.x, y: mapRect.minY + rawCenter.y)
                let eastSample = snapshot.point(for: location.coordinateOffset(northMeters: 0, eastMeters: 50))
                let northSample = snapshot.point(for: location.coordinateOffset(northMeters: 50, eastMeters: 0))
                let pxEast = hypot(eastSample.x - rawCenter.x, eastSample.y - rawCenter.y)
                let pxNorth = hypot(northSample.x - rawCenter.x, northSample.y - rawCenter.y)
                let measuredPpm = ((pxEast + pxNorth) * 0.5) / 50.0
                pixelsPerMeter = (measuredPpm.isFinite && measuredPpm > 0.05) ? measuredPpm : (mapRect.height / CGFloat(spanMeters))
            } else {
                // Offline cartographic coordinate-grid fallback
                cg.setFillColor(UIColor(red: 0.068, green: 0.105, blue: 0.145, alpha: 1.0).cgColor)
                cg.fill(mapRect)

                centerPoint = CGPoint(x: mapRect.midX, y: mapRect.midY)
                pixelsPerMeter = mapRect.height / CGFloat(spanMeters)

                let gridCandidates: [Double] = [5, 10, 25, 50, 100, 250, 500]
                let gridMeters = gridCandidates.first(where: { CGFloat($0) * pixelsPerMeter >= 55 }) ?? 50.0
                let stepPx = CGFloat(gridMeters) * pixelsPerMeter

                cg.setStrokeColor(UIColor.white.withAlphaComponent(0.08).cgColor)
                cg.setLineWidth(1)
                var gx = centerPoint.x
                while gx <= mapRect.maxX {
                    cg.move(to: CGPoint(x: gx, y: mapRect.minY))
                    cg.addLine(to: CGPoint(x: gx, y: mapRect.maxY))
                    gx += stepPx
                }
                gx = centerPoint.x - stepPx
                while gx >= mapRect.minX {
                    cg.move(to: CGPoint(x: gx, y: mapRect.minY))
                    cg.addLine(to: CGPoint(x: gx, y: mapRect.maxY))
                    gx -= stepPx
                }
                var gy = centerPoint.y
                while gy <= mapRect.maxY {
                    cg.move(to: CGPoint(x: mapRect.minX, y: gy))
                    cg.addLine(to: CGPoint(x: mapRect.maxX, y: gy))
                    gy += stepPx
                }
                gy = centerPoint.y - stepPx
                while gy >= mapRect.minY {
                    cg.move(to: CGPoint(x: mapRect.minX, y: gy))
                    cg.addLine(to: CGPoint(x: mapRect.maxX, y: gy))
                    gy -= stepPx
                }
                cg.strokePath()

                // Metric distance rings around center
                let ringFont = UIFont(name: "HelveticaNeue", size: 10) ?? UIFont.systemFont(ofSize: 10)
                for mult in [1, 2, 3] {
                    let ringMeters = gridMeters * Double(mult)
                    let r = CGFloat(ringMeters) * pixelsPerMeter
                    guard r < min(mapRect.width, mapRect.height) * 0.48 else { continue }
                    cg.setStrokeColor(UIColor.white.withAlphaComponent(0.16).cgColor)
                    cg.setLineWidth(1)
                    cg.strokeEllipse(in: CGRect(x: centerPoint.x - r, y: centerPoint.y - r, width: r * 2, height: r * 2))
                    let ringLabel = "\(Int(ringMeters)) m" as NSString
                    ringLabel.draw(
                        at: CGPoint(x: centerPoint.x + 4, y: centerPoint.y - r + 2),
                        withAttributes: [.font: ringFont, .foregroundColor: UIColor(white: 0.72, alpha: 0.85)]
                    )
                }

                // Cardinal N/S/E/W crosshair axes
                cg.setStrokeColor(UIColor.white.withAlphaComponent(0.22).cgColor)
                cg.setLineWidth(1)
                cg.setLineDash(phase: 0, lengths: [4, 4])
                cg.move(to: CGPoint(x: centerPoint.x, y: mapRect.minY + 12))
                cg.addLine(to: CGPoint(x: centerPoint.x, y: mapRect.maxY - 12))
                cg.move(to: CGPoint(x: mapRect.minX + 12, y: centerPoint.y))
                cg.addLine(to: CGPoint(x: mapRect.maxX - 12, y: centerPoint.y))
                cg.strokePath()
                cg.setLineDash(phase: 0, lengths: [])

                let offlineLabel = loc("Offline Coordinate Diagram", "Offline-Koordinatenkarte") as NSString
                let offlineFont = UIFont(name: "HelveticaNeue-Medium", size: 11) ?? UIFont.systemFont(ofSize: 11, weight: .medium)
                let offlineSize = offlineLabel.size(withAttributes: [.font: offlineFont])
                let badgeRect = CGRect(x: mapRect.minX + 12, y: mapRect.minY + 12, width: offlineSize.width + 16, height: offlineSize.height + 8)
                cg.setFillColor(UIColor.black.withAlphaComponent(0.58).cgColor)
                UIBezierPath(roundedRect: badgeRect, cornerRadius: 6).fill()
                offlineLabel.draw(
                    at: CGPoint(x: badgeRect.minX + 8, y: badgeRect.minY + 4),
                    withAttributes: [.font: offlineFont, .foregroundColor: UIColor(white: 0.88, alpha: 1)]
                )
            }

            // Accuracy circle overlay (± horizontalAccuracy)
            var accuracyRadiusPx: CGFloat = 24
            if location.horizontalAccuracy > 0 {
                let rawRadius = CGFloat(location.horizontalAccuracy) * pixelsPerMeter
                accuracyRadiusPx = max(10, min(min(mapRect.width, mapRect.height) * 0.42, rawRadius))
                let circleRect = CGRect(
                    x: centerPoint.x - accuracyRadiusPx,
                    y: centerPoint.y - accuracyRadiusPx,
                    width: accuracyRadiusPx * 2,
                    height: accuracyRadiusPx * 2
                )
                cg.setFillColor(cyanColor.withAlphaComponent(0.20).cgColor)
                cg.fillEllipse(in: circleRect)
                cg.setStrokeColor(cyanColor.withAlphaComponent(0.95).cgColor)
                cg.setLineWidth(2.0)
                cg.setLineDash(phase: 0, lengths: [6, 4])
                cg.strokeEllipse(in: circleRect)
                cg.setLineDash(phase: 0, lengths: [])

                let posix = Locale(identifier: "en_US_POSIX")
                let accLabel = String(format: "±%.1f m", locale: posix, location.horizontalAccuracy) as NSString
                let accFont = UIFont(name: "HelveticaNeue-Bold", size: 11) ?? UIFont.systemFont(ofSize: 11, weight: .bold)
                let accSize = accLabel.size(withAttributes: [.font: accFont])
                let accPill = CGRect(
                    x: centerPoint.x - accSize.width * 0.5 - 6,
                    y: centerPoint.y + accuracyRadiusPx + 6,
                    width: accSize.width + 12,
                    height: accSize.height + 4
                )
                cg.setFillColor(UIColor.black.withAlphaComponent(0.72).cgColor)
                UIBezierPath(roundedRect: accPill, cornerRadius: 5).fill()
                accLabel.draw(
                    at: CGPoint(x: accPill.minX + 6, y: accPill.minY + 2),
                    withAttributes: [.font: accFont, .foregroundColor: cyanColor]
                )
            }

            // Compass heading cone & ray
            if let heading = location.heading, heading.isFinite, heading >= 0 {
                let rad = CGFloat(heading * .pi / 180.0)
                let rayLen = max(56.0, min(140.0, accuracyRadiusPx * 1.55))
                // 0° is north (-Y in UIKit coordinates); clockwise increases angle.
                let cgAngle = rad - (.pi * 0.5)
                let coneSpread = CGFloat(24.0 * .pi / 180.0)
                let cone = UIBezierPath()
                cone.move(to: centerPoint)
                cone.addArc(
                    withCenter: centerPoint,
                    radius: rayLen,
                    startAngle: cgAngle - coneSpread,
                    endAngle: cgAngle + coneSpread,
                    clockwise: true
                )
                cone.close()
                cg.setFillColor(mintColor.withAlphaComponent(0.28).cgColor)
                cone.fill()

                let dx = sin(rad)
                let dy = -cos(rad)
                let tip = CGPoint(x: centerPoint.x + dx * rayLen, y: centerPoint.y + dy * rayLen)
                cg.setStrokeColor(mintColor.cgColor)
                cg.setLineWidth(3.0)
                cg.setLineCap(.round)
                cg.move(to: centerPoint)
                cg.addLine(to: tip)
                cg.strokePath()

                // Arrowhead at tip
                let headLen: CGFloat = 11
                let leftWing = CGPoint(
                    x: tip.x - headLen * cos(cgAngle - 0.45),
                    y: tip.y - headLen * sin(cgAngle - 0.45)
                )
                let rightWing = CGPoint(
                    x: tip.x - headLen * cos(cgAngle + 0.45),
                    y: tip.y - headLen * sin(cgAngle + 0.45)
                )
                let arrowHead = UIBezierPath()
                arrowHead.move(to: tip)
                arrowHead.addLine(to: leftWing)
                arrowHead.addLine(to: rightWing)
                arrowHead.close()
                cg.setFillColor(mintColor.cgColor)
                arrowHead.fill()
            }

            // Central GNSS Pin
            cg.setFillColor(UIColor.white.cgColor)
            cg.fillEllipse(in: CGRect(x: centerPoint.x - 10, y: centerPoint.y - 10, width: 20, height: 20))
            cg.setFillColor(mintColor.cgColor)
            cg.fillEllipse(in: CGRect(x: centerPoint.x - 7.5, y: centerPoint.y - 7.5, width: 15, height: 15))
            cg.setFillColor(UIColor.black.cgColor)
            cg.fillEllipse(in: CGRect(x: centerPoint.x - 2.5, y: centerPoint.y - 2.5, width: 5, height: 5))

            let trimmedTitle = scanTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedTitle.isEmpty {
                let labelFont = UIFont(name: "HelveticaNeue-Bold", size: 12) ?? UIFont.systemFont(ofSize: 12, weight: .bold)
                drawTagPill(text: trimmedTitle, accent: mintColor, at: CGPoint(x: centerPoint.x, y: centerPoint.y - 16), font: labelFont, in: cg)
            }

            // North indicator (top-right inside mapRect)
            let northCenter = CGPoint(x: mapRect.maxX - 30, y: mapRect.minY + 30)
            cg.setFillColor(UIColor.black.withAlphaComponent(0.68).cgColor)
            cg.fillEllipse(in: CGRect(x: northCenter.x - 18, y: northCenter.y - 18, width: 36, height: 36))
            let northPath = UIBezierPath()
            northPath.move(to: CGPoint(x: northCenter.x, y: northCenter.y - 11))
            northPath.addLine(to: CGPoint(x: northCenter.x - 5, y: northCenter.y + 3))
            northPath.addLine(to: CGPoint(x: northCenter.x, y: northCenter.y))
            northPath.addLine(to: CGPoint(x: northCenter.x + 5, y: northCenter.y + 3))
            northPath.close()
            cg.setFillColor(UIColor.white.cgColor)
            northPath.fill()
            let nFont = UIFont(name: "HelveticaNeue-Bold", size: 10) ?? UIFont.systemFont(ofSize: 10, weight: .bold)
            ("N" as NSString).draw(at: CGPoint(x: northCenter.x - 4, y: northCenter.y + 3), withAttributes: [.font: nFont, .foregroundColor: UIColor.white])

            // Scale bar with backing pill (bottom-right inside mapRect)
            drawScaleBar(in: cg, pixelsPerMeter: pixelsPerMeter, bottomRight: CGPoint(x: mapRect.maxX - 24, y: mapRect.maxY - 18), drawBackdrop: true)

            cg.restoreGState()

            // Crisp map frame border
            cg.setStrokeColor(UIColor.white.withAlphaComponent(0.18).cgColor)
            cg.setLineWidth(1)
            mapClip.stroke()

            // Bottom WGS84 metadata bar
            let posix = Locale(identifier: "en_US_POSIX")
            let coordText = "WGS84: \(location.formattedCoordinates)"
            var detailParts: [String] = []
            let hAccStr = String(format: "±%.1f m", locale: posix, location.horizontalAccuracy)
            if let vAcc = location.verticalAccuracy {
                detailParts.append(loc("Accuracy", "Genauigkeit") + ": \(hAccStr) / " + String(format: "±%.1f m", locale: posix, vAcc))
            } else {
                detailParts.append(loc("Accuracy", "Genauigkeit") + ": \(hAccStr)")
            }
            if let alt = location.altitude {
                detailParts.append(loc("Altitude", "Höhe") + ": " + String(format: "%.1f m", locale: posix, alt))
            }
            if let headingStr = location.cardinalHeadingString {
                detailParts.append(loc("Heading", "Ausrichtung") + ": \(headingStr)")
            }

            let metaFont = UIFont(name: "HelveticaNeue-Medium", size: 13) ?? UIFont.systemFont(ofSize: 13, weight: .medium)
            let subMetaFont = UIFont(name: "HelveticaNeue", size: 12) ?? UIFont.systemFont(ofSize: 12)
            let metaY = mapRect.maxY + 14
            (coordText as NSString).draw(at: CGPoint(x: 24, y: metaY), withAttributes: [.font: metaFont, .foregroundColor: UIColor.white])
            let rightSummary = detailParts.joined(separator: "  ·  ") as NSString
            let rightSize = rightSummary.size(withAttributes: [.font: subMetaFont])
            rightSummary.draw(
                at: CGPoint(x: max(24, renderSize.width - 24 - rightSize.width), y: metaY + 22),
                withAttributes: [.font: subMetaFont, .foregroundColor: UIColor(white: 0.78, alpha: 1.0)]
            )
        }

        guard let pngData = image.pngData() else { return nil }
        let modeHint = snapshot != nil
            ? loc("Apple Maps basemap with horizontal accuracy circle and compass heading.", "Apple-Maps-Basiskarte mit horizontalem Genauigkeitskreis und Kompassausrichtung.")
            : loc("Offline coordinate diagram with metric grid, horizontal accuracy circle, and compass heading.", "Offline-Koordinatendiagramm mit Meterraster, horizontalem Genauigkeitskreis und Kompassausrichtung.")
        return ReportFigure(
            id: "gnss-map",
            title: loc("GNSS Location & Orientation (WGS84)", "GNSS-Position & Ausrichtung (WGS84)"),
            caption: modeHint,
            pngData: pngData,
            pixelWidth: Int(renderSize.width),
            pixelHeight: Int(renderSize.height)
        )
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
        title: String?,
        canvasSize: CGSize = renderSize,
        includeChrome: Bool = true
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

        let drawRect = includeChrome
            ? CGRect(x: 42, y: 54, width: canvasSize.width - 84, height: canvasSize.height - 86)
            : CGRect(x: 16, y: 16, width: canvasSize.width - 32, height: canvasSize.height - 32)
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
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            if includeChrome {
                drawCanvasChrome(in: cg, size: canvasSize, title: title ?? "")
            } else {
                cg.setFillColor(UIColor(red: 0.055, green: 0.082, blue: 0.106, alpha: 1.0).cgColor)
                cg.fill(CGRect(origin: .zero, size: canvasSize))
            }

            cg.saveGState()
            if includeChrome {
                cg.clip(to: CGRect(x: 16, y: 42, width: canvasSize.width - 32, height: canvasSize.height - 56))
            } else {
                cg.clip(to: CGRect(origin: .zero, size: canvasSize))
            }
            let dotSize: CGFloat = projected.count > 18_000 ? 2.4 : (includeChrome ? 3.2 : 2.6)
            for p in projected {
                cg.setFillColor(red: p.r, green: p.g, blue: p.b, alpha: 0.95)
                cg.fillEllipse(in: CGRect(x: p.x - dotSize * 0.5, y: p.y - dotSize * 0.5, width: dotSize, height: dotSize))
            }

            if includeChrome {
                drawOverlays(
                    in: cg,
                    gcps: gcps,
                    annotations: annotations,
                    projector: { project($0)?.point }
                )
            }
            cg.restoreGState()

            if includeChrome {
                // Mini 3D axis gizmo bottom-left
                drawAxisGizmo(in: cg, origin: CGPoint(x: 48, y: canvasSize.height - 38), rotate: rotate)
            }
        }
    }

    private static func renderPhotoThumbnail(_ source: UIImage, size: CGSize) -> UIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            cg.setFillColor(UIColor(red: 0.055, green: 0.082, blue: 0.106, alpha: 1.0).cgColor)
            cg.fill(CGRect(origin: .zero, size: size))
            let imgSize = source.size
            let scale = max(size.width / max(1, imgSize.width), size.height / max(1, imgSize.height))
            let drawSize = CGSize(width: imgSize.width * scale, height: imgSize.height * scale)
            let drawRect = CGRect(
                x: (size.width - drawSize.width) * 0.5,
                y: (size.height - drawSize.height) * 0.5,
                width: drawSize.width,
                height: drawSize.height
            )
            source.draw(in: drawRect)
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

    private static func drawScaleBar(in cg: CGContext, pixelsPerMeter: CGFloat, bottomRight: CGPoint, drawBackdrop: Bool = false) {
        guard pixelsPerMeter.isFinite, pixelsPerMeter > 0.05 else { return }
        let candidates: [CGFloat] = [0.1, 0.25, 0.5, 1, 2, 5, 10, 20, 50, 100, 250, 500, 1000]
        let chosenMeters = candidates.first(where: { $0 * pixelsPerMeter >= 80 }) ?? 1.0
        let barWidth = Swift.min(200, Swift.max(60, chosenMeters * pixelsPerMeter))
        let labelStr = chosenMeters < 1
            ? String(format: "%.2g m", Double(chosenMeters))
            : String(format: "%.0f m", Double(chosenMeters))

        let startX = bottomRight.x - barWidth
        let y = bottomRight.y
        if drawBackdrop {
            let backdrop = CGRect(x: startX - 10, y: y - 28, width: barWidth + 20, height: 36)
            cg.setFillColor(UIColor.black.withAlphaComponent(0.66).cgColor)
            UIBezierPath(roundedRect: backdrop, cornerRadius: 7).fill()
        }
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
