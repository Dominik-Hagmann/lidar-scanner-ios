import Foundation
import simd

struct AnnotationExportMetadata: Equatable {
    let scanID: UUID
    let title: String
    let unit: String
    let coordinateSystem: String

    init(scanID: UUID, title: String, unit: String = "metre", coordinateSystem: String) {
        self.scanID = scanID
        self.title = title
        self.unit = unit
        self.coordinateSystem = coordinateSystem
    }

    init(scan: ScanMetadata) {
        self.init(scanID: scan.scanID, title: scan.title, unit: scan.unit, coordinateSystem: scan.coordinateSystem)
    }

    init(gaussian: GaussianProject) {
        self.init(
            scanID: gaussian.id,
            title: gaussian.title,
            unit: "metre",
            coordinateSystem: "Local right-handed Cartesian; Z up (metres; converted via (x, -z, y) from ARKit splat space)"
        )
    }
}

enum AnnotationGeometryHelper {
    /// Computes perimeter in metres of a closed vertex loop (0 for single point).
    static func perimeter(_ vertices: [AnnotationPoint3D]) -> Double {
        guard vertices.count >= 2 else { return 0 }
        var total = 0.0
        for i in 0..<vertices.count {
            let a = vertices[i]
            let b = vertices[(i + 1) % vertices.count]
            let dx = b.x - a.x, dy = b.y - a.y, dz = b.z - a.z
            total += sqrt(dx * dx + dy * dy + dz * dz)
        }
        return total
    }

    /// Computes 3D planar surface area in m² for 3+ ordered vertices using vector-summed triangle cross products.
    static func area(_ vertices: [AnnotationPoint3D]) -> Double {
        guard vertices.count >= 3 else { return 0 }
        let origin = SIMD3<Double>(vertices[0].x, vertices[0].y, vertices[0].z)
        var areaVec = SIMD3<Double>(repeating: 0)
        for i in 1..<(vertices.count - 1) {
            let a = SIMD3<Double>(vertices[i].x, vertices[i].y, vertices[i].z) - origin
            let b = SIMD3<Double>(vertices[i + 1].x, vertices[i + 1].y, vertices[i + 1].z) - origin
            areaVec += simd_cross(a, b)
        }
        return 0.5 * simd_length(areaVec)
    }
}

enum AnnotationExporter {
    private static let posix = Locale(identifier: "en_US_POSIX")

    /// RFC 7946 GeoJSON FeatureCollection preserving 3D Z-up local coordinates (metres), tags, and computed metrics.
    static func geoJSONData(for annotations: [CloudAnnotation], metadata: ScanMetadata? = nil) throws -> Data {
        try geoJSONData(for: annotations, exportMetadata: metadata.map(AnnotationExportMetadata.init(scan:)))
    }

    static func geoJSONData(for annotations: [CloudAnnotation], exportMetadata: AnnotationExportMetadata?) throws -> Data {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let features: [[String: Any]] = annotations.compactMap { ann in
            guard !ann.vertices.isEmpty else { return nil }
            let geometry: [String: Any]
            if ann.type == .point || ann.vertices.count == 1 {
                let p = ann.vertices[0]
                geometry = [
                    "type": "Point",
                    "coordinates": [p.x, p.y, p.z]
                ]
            } else {
                var ring = ann.vertices.map { [$0.x, $0.y, $0.z] }
                if let first = ring.first { ring.append(first) }
                geometry = [
                    "type": "Polygon",
                    "coordinates": [ring]
                ]
            }

            var props: [String: Any] = [
                "title": ann.title,
                "geometryType": ann.type.rawValue,
                "tags": ann.tags,
                "color": ann.color.rawValue,
                "colorHex": ann.color.hex,
                "note": ann.note,
                "vertexCount": ann.vertices.count,
                "perimeterMeters": (ann.perimeterMeters * 10_000).rounded() / 10_000,
                "areaSquareMeters": (ann.areaSquareMeters * 10_000).rounded() / 10_000,
                "createdAt": iso.string(from: ann.createdAt),
                "coordinateUnit": exportMetadata?.unit ?? "metre",
                "coordinateSystem": exportMetadata?.coordinateSystem ?? "Local right-handed Cartesian; Z up"
            ]
            if let exportMetadata {
                props["scanID"] = exportMetadata.scanID.uuidString
                props["scanTitle"] = exportMetadata.title
            }
            return [
                "type": "Feature",
                "id": ann.id.uuidString,
                "geometry": geometry,
                "properties": props
            ]
        }

        var root: [String: Any] = [
            "type": "FeatureCollection",
            "features": features
        ]
        if let exportMetadata {
            root["metadata"] = [
                "scanID": exportMetadata.scanID.uuidString,
                "title": exportMetadata.title,
                "unit": exportMetadata.unit,
                "coordinateSystem": exportMetadata.coordinateSystem
            ]
        }
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    /// Table export (CSV with 3D WKT geometry) compatible with QGIS Delimited Text, Excel, and R.
    static func csvData(for annotations: [CloudAnnotation]) -> Data {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var lines = ["id,title,type,tags,color,centroid_x_m,centroid_y_m,centroid_z_m,perimeter_m,area_m2,vertex_count,wkt_z,note,created_at"]
        for ann in annotations where !ann.vertices.isEmpty {
            let c = ann.centroid
            let fields = [
                csvEscape(ann.id.uuidString),
                csvEscape(ann.title),
                csvEscape(ann.type.rawValue),
                csvEscape(ann.tags.joined(separator: "; ")),
                csvEscape(ann.color.rawValue),
                fmt(c.x, 6),
                fmt(c.y, 6),
                fmt(c.z, 6),
                fmt(ann.perimeterMeters, 4),
                fmt(ann.areaSquareMeters, 4),
                "\(ann.vertices.count)",
                csvEscape(wkt(for: ann)),
                csvEscape(ann.note),
                csvEscape(iso.string(from: ann.createdAt))
            ]
            lines.append(fields.joined(separator: ","))
        }
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }

    /// ASCII AutoCAD DXF (ENTITIES section) grouping 3D Points and closed 3D Polylines onto layers by primary tag.
    static func dxfData(for annotations: [CloudAnnotation]) -> Data {
        var out: [String] = [
            "0", "SECTION",
            "2", "HEADER",
            "9", "$INSUNITS",
            "70", "6", // metres
            "0", "ENDSEC",
            "0", "SECTION",
            "2", "ENTITIES"
        ]

        for ann in annotations where !ann.vertices.isEmpty {
            let layer = sanitizeDXFLayer(ann.tags.first ?? "ANNOTATIONS")
            if ann.type == .point || ann.vertices.count == 1 {
                let p = ann.vertices[0]
                out.append(contentsOf: [
                    "0", "POINT",
                    "8", layer,
                    "10", fmt(p.x, 6),
                    "20", fmt(p.y, 6),
                    "30", fmt(p.z, 6)
                ])
            } else {
                out.append(contentsOf: [
                    "0", "POLYLINE",
                    "8", layer,
                    "66", "1",
                    "10", "0.0",
                    "20", "0.0",
                    "30", "0.0",
                    "70", "9" // closed (1) + 3D polyline (8)
                ])
                for p in ann.vertices {
                    out.append(contentsOf: [
                        "0", "VERTEX",
                        "8", layer,
                        "10", fmt(p.x, 6),
                        "20", fmt(p.y, 6),
                        "30", fmt(p.z, 6),
                        "70", "32" // 3D polyline vertex
                    ])
                }
                out.append(contentsOf: ["0", "SEQEND", "8", layer])
            }
        }

        out.append(contentsOf: ["0", "ENDSEC", "0", "EOF"])
        return Data((out.joined(separator: "\n") + "\n").utf8)
    }

    private static func wkt(for ann: CloudAnnotation) -> String {
        if ann.type == .point || ann.vertices.count == 1 {
            let p = ann.vertices[0]
            return "POINT Z (\(fmt(p.x, 6)) \(fmt(p.y, 6)) \(fmt(p.z, 6)))"
        }
        var ring = ann.vertices
        if let first = ring.first { ring.append(first) }
        let coords = ring.map { "\(fmt($0.x, 6)) \(fmt($0.y, 6)) \(fmt($0.z, 6))" }.joined(separator: ", ")
        return "POLYGON Z ((\(coords)))"
    }

    private static func fmt(_ v: Double, _ decimals: Int) -> String {
        String(format: "%.\(decimals)f", locale: posix, v)
    }

    private static func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    private static func sanitizeDXFLayer(_ raw: String) -> String {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "_")
            .filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
        return cleaned.isEmpty ? "ANNOTATIONS" : String(cleaned.prefix(64))
    }
}
