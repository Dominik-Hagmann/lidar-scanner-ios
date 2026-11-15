import Foundation
import simd

enum CRSUnitKind: String, Codable, Equatable {
    case meters = "metre"
    case degrees = "degree"

    var shortLabel: String {
        switch self {
        case .meters: return "m"
        case .degrees: return "°"
        }
    }
}

enum CRSCategory: String, CaseIterable, Identifiable, Codable {
    case austria
    case croatiaBalkans
    case germanySwitzerlandItaly
    case europeETRS89
    case globalWGS84
    case otherNational
    case local

    var id: String { rawValue }

    var title: String {
        switch self {
        case .austria: return LanguageManager.string("Austria (MGI / ETRS89)")
        case .croatiaBalkans: return LanguageManager.string("Croatia & SE Europe")
        case .germanySwitzerlandItaly: return LanguageManager.string("Germany, Switzerland & Italy")
        case .europeETRS89: return LanguageManager.string("Europe (ETRS89 / UTM)")
        case .globalWGS84: return LanguageManager.string("Global (WGS 84 / UTM)")
        case .otherNational: return LanguageManager.string("Other National Grids")
        case .local: return LanguageManager.string("Local Grid")
        }
    }
}

struct CRSEntry: Identifiable, Equatable, Codable {
    var id: String { code }
    let code: String
    let epsgNumber: Int?
    let name: String
    let region: String
    let category: CRSCategory
    let unitKind: CRSUnitKind

    var ogcURN: String? {
        epsgNumber.map { "urn:ogc:def:crs:EPSG::\($0)" }
    }
}

enum CRSCatalog {
    static let quickPickCodes: [String] = [
        "EPSG:31256",
        "EPSG:31255",
        "EPSG:31254",
        "EPSG:25833",
        "EPSG:25832",
        "EPSG:3765",
        "EPSG:4326",
        "LOCAL"
    ]

    static let allEntries: [CRSEntry] = {
        var list: [CRSEntry] = []

        // Austria (BEV / MGI & ETRS89)
        list.append(contentsOf: [
            CRSEntry(code: "EPSG:31254", epsgNumber: 31254, name: "MGI / Austria GK West", region: "Austria (Vorarlberg, Tyrol)", category: .austria, unitKind: .meters),
            CRSEntry(code: "EPSG:31255", epsgNumber: 31255, name: "MGI / Austria GK Central", region: "Austria (Salzburg, Carinthia, Upper Austria)", category: .austria, unitKind: .meters),
            CRSEntry(code: "EPSG:31256", epsgNumber: 31256, name: "MGI / Austria GK East", region: "Austria (Vienna, Lower Austria, Styria, Burgenland)", category: .austria, unitKind: .meters),
            CRSEntry(code: "EPSG:31257", epsgNumber: 31257, name: "MGI / Austria GK M28", region: "Austria (Meridian M28, +150 km)", category: .austria, unitKind: .meters),
            CRSEntry(code: "EPSG:31258", epsgNumber: 31258, name: "MGI / Austria GK M31", region: "Austria (Meridian M31, +450 km)", category: .austria, unitKind: .meters),
            CRSEntry(code: "EPSG:31259", epsgNumber: 31259, name: "MGI / Austria GK M34", region: "Austria (Meridian M34, +750 km)", category: .austria, unitKind: .meters),
            CRSEntry(code: "EPSG:31287", epsgNumber: 31287, name: "MGI / Austria Lambert", region: "Austria (National Lambert)", category: .austria, unitKind: .meters),
            CRSEntry(code: "EPSG:3416", epsgNumber: 3416, name: "ETRS89 / Austria Lambert", region: "Austria (ETRS89 Lambert)", category: .austria, unitKind: .meters),
            CRSEntry(code: "EPSG:4312", epsgNumber: 4312, name: "MGI Geographic 2D", region: "Austria (Geographic deg)", category: .austria, unitKind: .degrees)
        ])

        // Croatia & SE Europe / Balkans
        list.append(contentsOf: [
            CRSEntry(code: "EPSG:3765", epsgNumber: 3765, name: "HTRS96 / Croatia TM", region: "Croatia (National TM)", category: .croatiaBalkans, unitKind: .meters),
            CRSEntry(code: "EPSG:3766", epsgNumber: 3766, name: "HTRS96 / Croatia LCC", region: "Croatia (Lambert Conformal)", category: .croatiaBalkans, unitKind: .meters),
            CRSEntry(code: "EPSG:4761", epsgNumber: 4761, name: "HTRS96 Geographic 2D", region: "Croatia (Geographic deg)", category: .croatiaBalkans, unitKind: .degrees),
            CRSEntry(code: "EPSG:3908", epsgNumber: 3908, name: "MGI 1901 / Balkans zone 6", region: "Croatia, Bosnia, Serbia (Historical GK 6)", category: .croatiaBalkans, unitKind: .meters),
            CRSEntry(code: "EPSG:3909", epsgNumber: 3909, name: "MGI 1901 / Balkans zone 7", region: "Serbia, Montenegro, North Macedonia (GK 7)", category: .croatiaBalkans, unitKind: .meters),
            CRSEntry(code: "EPSG:3794", epsgNumber: 3794, name: "Slovenia 1996 / Slovene National Grid (D96/TM)", region: "Slovenia", category: .croatiaBalkans, unitKind: .meters),
            CRSEntry(code: "EPSG:23700", epsgNumber: 23700, name: "HD72 / EOV", region: "Hungary", category: .croatiaBalkans, unitKind: .meters),
            CRSEntry(code: "EPSG:8687", epsgNumber: 8687, name: "SRB_ETRS89 / UTM zone 34N", region: "Serbia", category: .croatiaBalkans, unitKind: .meters),
            CRSEntry(code: "EPSG:3844", epsgNumber: 3844, name: "Pulkovo 1942(58) / Stereo70", region: "Romania", category: .croatiaBalkans, unitKind: .meters),
            CRSEntry(code: "EPSG:2100", epsgNumber: 2100, name: "GGRS87 / Greek Grid", region: "Greece", category: .croatiaBalkans, unitKind: .meters)
        ])

        // Germany, Switzerland & Italy
        list.append(contentsOf: [
            CRSEntry(code: "EPSG:31466", epsgNumber: 31466, name: "DHDN / 3-degree Gauss-Kruger zone 2", region: "Germany (West, 6°E)", category: .germanySwitzerlandItaly, unitKind: .meters),
            CRSEntry(code: "EPSG:31467", epsgNumber: 31467, name: "DHDN / 3-degree Gauss-Kruger zone 3", region: "Germany (Central, 9°E)", category: .germanySwitzerlandItaly, unitKind: .meters),
            CRSEntry(code: "EPSG:31468", epsgNumber: 31468, name: "DHDN / 3-degree Gauss-Kruger zone 4", region: "Germany (East/Bavaria, 12°E)", category: .germanySwitzerlandItaly, unitKind: .meters),
            CRSEntry(code: "EPSG:31469", epsgNumber: 31469, name: "DHDN / 3-degree Gauss-Kruger zone 5", region: "Germany (Far East, 15°E)", category: .germanySwitzerlandItaly, unitKind: .meters),
            CRSEntry(code: "EPSG:4647", epsgNumber: 4647, name: "ETRS89 / UTM zone 32N (zE-N)", region: "Germany (with zone prefix)", category: .germanySwitzerlandItaly, unitKind: .meters),
            CRSEntry(code: "EPSG:5650", epsgNumber: 5650, name: "ETRS89 / UTM zone 33N (zE-N)", region: "Germany (with zone prefix)", category: .germanySwitzerlandItaly, unitKind: .meters),
            CRSEntry(code: "EPSG:2056", epsgNumber: 2056, name: "CH1903+ / LV95", region: "Switzerland & Liechtenstein", category: .germanySwitzerlandItaly, unitKind: .meters),
            CRSEntry(code: "EPSG:21781", epsgNumber: 21781, name: "CH1903 / LV03", region: "Switzerland (Legacy)", category: .germanySwitzerlandItaly, unitKind: .meters),
            CRSEntry(code: "EPSG:3003", epsgNumber: 3003, name: "Monte Mario / Italy zone 1", region: "Italy (West)", category: .germanySwitzerlandItaly, unitKind: .meters),
            CRSEntry(code: "EPSG:3004", epsgNumber: 3004, name: "Monte Mario / Italy zone 2", region: "Italy (East)", category: .germanySwitzerlandItaly, unitKind: .meters),
            CRSEntry(code: "EPSG:6706", epsgNumber: 6706, name: "RDN2008 Geographic 2D", region: "Italy (Geographic deg)", category: .germanySwitzerlandItaly, unitKind: .degrees),
            CRSEntry(code: "EPSG:7791", epsgNumber: 7791, name: "RDN2008 / UTM zone 32N", region: "Italy (West)", category: .germanySwitzerlandItaly, unitKind: .meters),
            CRSEntry(code: "EPSG:7792", epsgNumber: 7792, name: "RDN2008 / UTM zone 33N", region: "Italy (Central/South)", category: .germanySwitzerlandItaly, unitKind: .meters),
            CRSEntry(code: "EPSG:7793", epsgNumber: 7793, name: "RDN2008 / UTM zone 34N", region: "Italy (Far East)", category: .germanySwitzerlandItaly, unitKind: .meters)
        ])

        // Europe (ETRS89)
        list.append(contentsOf: [
            CRSEntry(code: "EPSG:4258", epsgNumber: 4258, name: "ETRS89 Geographic 2D", region: "Europe (Geographic deg)", category: .europeETRS89, unitKind: .degrees),
            CRSEntry(code: "EPSG:4937", epsgNumber: 4937, name: "ETRS89 Geographic 3D", region: "Europe (3D Lon/Lat/Ellipsoid h)", category: .europeETRS89, unitKind: .degrees),
            CRSEntry(code: "EPSG:3034", epsgNumber: 3034, name: "ETRS89-extended / LCC Europe", region: "Europe (Pan-European LCC)", category: .europeETRS89, unitKind: .meters),
            CRSEntry(code: "EPSG:3035", epsgNumber: 3035, name: "ETRS89-extended / LAEA Europe", region: "Europe (Equal Area)", category: .europeETRS89, unitKind: .meters)
        ])
        for zone in 28...38 {
            let epsg = 25800 + zone
            list.append(CRSEntry(
                code: "EPSG:\(epsg)",
                epsgNumber: epsg,
                name: "ETRS89 / UTM zone \(zone)N",
                region: "Europe (Zone \(zone)N)",
                category: .europeETRS89,
                unitKind: .meters
            ))
        }

        // Global (WGS 84) + all 120 UTM zones
        list.append(contentsOf: [
            CRSEntry(code: "EPSG:4326", epsgNumber: 4326, name: "WGS 84 Geographic 2D", region: "Global (GNSS Lon/Lat deg)", category: .globalWGS84, unitKind: .degrees),
            CRSEntry(code: "EPSG:4979", epsgNumber: 4979, name: "WGS 84 Geographic 3D", region: "Global (GNSS 3D deg + m)", category: .globalWGS84, unitKind: .degrees),
            CRSEntry(code: "EPSG:3857", epsgNumber: 3857, name: "WGS 84 / Pseudo-Mercator", region: "Global (Web Mercator)", category: .globalWGS84, unitKind: .meters)
        ])
        for zone in 1...60 {
            let epsg = 32600 + zone
            list.append(CRSEntry(
                code: "EPSG:\(epsg)",
                epsgNumber: epsg,
                name: "WGS 84 / UTM zone \(zone)N",
                region: "Northern Hemisphere (Zone \(zone)N)",
                category: .globalWGS84,
                unitKind: .meters
            ))
        }
        for zone in 1...60 {
            let epsg = 32700 + zone
            list.append(CRSEntry(
                code: "EPSG:\(epsg)",
                epsgNumber: epsg,
                name: "WGS 84 / UTM zone \(zone)S",
                region: "Southern Hemisphere (Zone \(zone)S)",
                category: .globalWGS84,
                unitKind: .meters
            ))
        }

        // Other National Grids
        list.append(contentsOf: [
            CRSEntry(code: "EPSG:2154", epsgNumber: 2154, name: "RGF93 v1 / Lambert-93", region: "France", category: .otherNational, unitKind: .meters),
            CRSEntry(code: "EPSG:27700", epsgNumber: 27700, name: "OSGB36 / British National Grid", region: "United Kingdom", category: .otherNational, unitKind: .meters),
            CRSEntry(code: "EPSG:28992", epsgNumber: 28992, name: "Amersfoort / RD New", region: "Netherlands", category: .otherNational, unitKind: .meters),
            CRSEntry(code: "EPSG:31370", epsgNumber: 31370, name: "Belge 1972 / Belgian Lambert 72", region: "Belgium", category: .otherNational, unitKind: .meters),
            CRSEntry(code: "EPSG:5514", epsgNumber: 5514, name: "S-JTSK / Krovak East North", region: "Czechia & Slovakia", category: .otherNational, unitKind: .meters),
            CRSEntry(code: "EPSG:2180", epsgNumber: 2180, name: "ETRF2000-PL / CS92", region: "Poland", category: .otherNational, unitKind: .meters),
            CRSEntry(code: "EPSG:2039", epsgNumber: 2039, name: "Israel 1993 / Israeli TM Grid", region: "Israel", category: .otherNational, unitKind: .meters),
            CRSEntry(code: "EPSG:4269", epsgNumber: 4269, name: "NAD83 Geographic 2D", region: "North America (Geographic deg)", category: .otherNational, unitKind: .degrees),
            CRSEntry(code: "EPSG:6318", epsgNumber: 6318, name: "NAD83(2011) Geographic 2D", region: "North America (Geographic deg)", category: .otherNational, unitKind: .degrees)
        ])
        for zone in 10...19 {
            let epsg = 26900 + zone
            list.append(CRSEntry(
                code: "EPSG:\(epsg)",
                epsgNumber: epsg,
                name: "NAD83 / UTM zone \(zone)N",
                region: "North America (Zone \(zone)N)",
                category: .otherNational,
                unitKind: .meters
            ))
        }

        // Local Grid
        list.append(CRSEntry(
            code: "LOCAL",
            epsgNumber: nil,
            name: "Local Excavation / Survey Grid",
            region: "Local Cartesian (m)",
            category: .local,
            unitKind: .meters
        ))

        return list
    }()

    private static let entriesByCode: [String: CRSEntry] = {
        Dictionary(allEntries.map { ($0.code.uppercased(), $0) }, uniquingKeysWith: { first, _ in first })
    }()

    static func normalizeCode(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.caseInsensitiveCompare("local") == .orderedSame {
            return "LOCAL"
        }
        if trimmed.allSatisfy(\.isNumber) {
            return "EPSG:\(trimmed)"
        }
        let upper = trimmed.uppercased()
        if upper.hasPrefix("EPSG") {
            let remainder = upper.dropFirst(4)
                .trimmingCharacters(in: CharacterSet(charactersIn: ": ").union(.whitespaces))
            if !remainder.isEmpty && remainder.allSatisfy(\.isNumber) {
                return "EPSG:\(remainder)"
            }
        }
        return trimmed
    }

    static func lookup(_ raw: String) -> CRSEntry? {
        let normalized = normalizeCode(raw)
        guard !normalized.isEmpty else { return nil }
        if let found = entriesByCode[normalized.uppercased()] {
            return found
        }
        if let num = parsedEPSGNumber(from: normalized) {
            return CRSEntry(
                code: "EPSG:\(num)",
                epsgNumber: num,
                name: "EPSG:\(num)",
                region: "Custom EPSG",
                category: .otherNational,
                unitKind: .meters
            )
        }
        return nil
    }

    static func search(_ query: String) -> [CRSEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return allEntries }

        let tokens = trimmed.split(whereSeparator: \.isWhitespace).map { String($0).lowercased() }
        var matches = allEntries.filter { entry in
            let haystack = "\(entry.code) \(entry.name) \(entry.region) \(entry.category.title)".lowercased()
            return tokens.allSatisfy { haystack.contains($0) }
        }

        if let num = parsedEPSGNumber(from: normalizeCode(trimmed)),
           !matches.contains(where: { $0.epsgNumber == num }) {
            matches.append(CRSEntry(
                code: "EPSG:\(num)",
                epsgNumber: num,
                name: "EPSG:\(num)",
                region: "Custom EPSG",
                category: .otherNational,
                unitKind: .meters
            ))
        }

        return matches
    }

    private static func parsedEPSGNumber(from normalized: String) -> Int? {
        guard normalized.uppercased().hasPrefix("EPSG:") else { return nil }
        let suffix = normalized.dropFirst(5)
        guard !suffix.isEmpty, suffix.allSatisfy(\.isNumber), let num = Int(suffix), num > 0 else {
            return nil
        }
        return num
    }
}

struct GCPResidual: Codable, Equatable {
    let label: String
    let dx: Double
    let dy: Double
    let dz: Double
    let error3DMeters: Double
}

struct ScanGeoreferencing: Codable, Equatable {
    let targetCRS: String
    let targetCRSName: String?
    let ogcURN: String?
    let unit: String
    let controlPointCount: Int
    let referencePointCount: Int
    let localToTargetRowMajor: [Double]?
    let rmseMeters: Double?
    let residuals: [GCPResidual]?
}

enum GCPRegistration {
    static func computeGeoreferencing(for points: [GroundControlPoint]) -> ScanGeoreferencing? {
        guard !points.isEmpty else { return nil }

        let primaryCRS = points
            .map { CRSCatalog.normalizeCode($0.coordinateSystem) }
            .first(where: { !$0.isEmpty }) ?? "LOCAL"
        let crsEntry = CRSCatalog.lookup(primaryCRS)
        let resolvedUnit = crsEntry?.unitKind.rawValue ?? "metre"

        let referencePoints = points.filter { $0.targetX != nil && $0.targetY != nil }

        var matrix: [Double]? = nil
        var rmseMeters: Double? = nil
        var residuals: [GCPResidual]? = nil

        if referencePoints.count >= 3, crsEntry?.unitKind != .degrees {
            let localVectors = referencePoints.map { SIMD3<Double>($0.localX, $0.localY, $0.localZ) }
            let targetVectors = referencePoints.map { SIMD3<Double>($0.targetX ?? 0, $0.targetY ?? 0, $0.targetZ ?? 0) }
            if let transform = rigidTransformHorn(local: localVectors, target: targetVectors) {
                matrix = rowMajor4x4(rotation: transform.rotation, translation: transform.translation)
                var computedResiduals: [GCPResidual] = []
                computedResiduals.reserveCapacity(referencePoints.count)
                var sumSq = 0.0
                for (idx, gcp) in referencePoints.enumerated() {
                    let predicted = transform.rotation * localVectors[idx] + transform.translation
                    let actual = targetVectors[idx]
                    let delta = predicted - actual
                    let err = simd_length(delta)
                    sumSq += err * err
                    computedResiduals.append(GCPResidual(
                        label: gcp.label,
                        dx: rounded(delta.x, decimals: 6),
                        dy: rounded(delta.y, decimals: 6),
                        dz: rounded(delta.z, decimals: 6),
                        error3DMeters: rounded(err, decimals: 6)
                    ))
                }
                residuals = computedResiduals
                rmseMeters = rounded(sqrt(sumSq / Double(referencePoints.count)), decimals: 6)
            }
        }

        return ScanGeoreferencing(
            targetCRS: primaryCRS,
            targetCRSName: crsEntry?.name,
            ogcURN: crsEntry?.ogcURN,
            unit: resolvedUnit,
            controlPointCount: points.count,
            referencePointCount: referencePoints.count,
            localToTargetRowMajor: matrix,
            rmseMeters: rmseMeters,
            residuals: residuals
        )
    }

    private static func rigidTransformHorn(
        local: [SIMD3<Double>],
        target: [SIMD3<Double>]
    ) -> (rotation: simd_double3x3, translation: SIMD3<Double>)? {
        let count = local.count
        guard count >= 3, count == target.count else { return nil }

        let invN = 1.0 / Double(count)
        let localMean = local.reduce(SIMD3<Double>.zero, +) * invN
        let targetMean = target.reduce(SIMD3<Double>.zero, +) * invN

        let pCentered = local.map { $0 - localMean }
        let qCentered = target.map { $0 - targetMean }

        let totalSpread = pCentered.reduce(0.0) { $0 + simd_length_squared($1) }
        guard totalSpread > 1e-10 else { return nil }

        // Ensure points are non-collinear so roll around the line axis is well-defined.
        var maxCrossSq = 0.0
        for i in 0..<count {
            for j in (i + 1)..<count {
                let c = simd_cross(pCentered[i], pCentered[j])
                maxCrossSq = max(maxCrossSq, simd_length_squared(c))
            }
        }
        guard maxCrossSq > 1e-8 else { return nil }

        // Cross-covariance S = sum(p_i * q_i^T)
        var sxx = 0.0, sxy = 0.0, sxz = 0.0
        var syx = 0.0, syy = 0.0, syz = 0.0
        var szx = 0.0, szy = 0.0, szz = 0.0
        for i in 0..<count {
            let p = pCentered[i]
            let q = qCentered[i]
            sxx += p.x * q.x; sxy += p.x * q.y; sxz += p.x * q.z
            syx += p.y * q.x; syy += p.y * q.y; syz += p.y * q.z
            szx += p.z * q.x; szy += p.z * q.y; szz += p.z * q.z
        }

        // Horn 4x4 symmetric matrix N for quaternion ordering (w, x, y, z)
        var nMat: [[Double]] = [
            [sxx + syy + szz, syz - szy, szx - sxz, sxy - syx],
            [syz - szy, sxx - syy - szz, sxy + syx, szx + sxz],
            [szx - sxz, sxy + syx, -sxx + syy - szz, syz + szy],
            [sxy - syx, szx + sxz, syz + szy, -sxx - syy + szz]
        ]

        let (_, vectors) = jacobiEigen4x4(&nMat)
        let nDiag = [nMat[0][0], nMat[1][1], nMat[2][2], nMat[3][3]]
        guard let maxIdx = nDiag.indices.max(by: { nDiag[$0] < nDiag[$1] }) else { return nil }

        let qw = vectors[0][maxIdx]
        let qx = vectors[1][maxIdx]
        let qy = vectors[2][maxIdx]
        let qz = vectors[3][maxIdx]
        let qNorm = sqrt(qw * qw + qx * qx + qy * qy + qz * qz)
        guard qNorm > 1e-12 else { return nil }

        let quat = simd_quatd(ix: qx / qNorm, iy: qy / qNorm, iz: qz / qNorm, r: qw / qNorm)
        let rotation = simd_double3x3(quat)
        let translation = targetMean - rotation * localMean
        return (rotation, translation)
    }

    private static func jacobiEigen4x4(_ a: inout [[Double]]) -> ([Double], [[Double]]) {
        var v = [
            [1.0, 0.0, 0.0, 0.0],
            [0.0, 1.0, 0.0, 0.0],
            [0.0, 0.0, 1.0, 0.0],
            [0.0, 0.0, 0.0, 1.0]
        ]
        for _ in 0..<50 {
            var maxVal = 0.0
            var p = 0
            var q = 1
            for i in 0..<4 {
                for j in (i + 1)..<4 {
                    let val = abs(a[i][j])
                    if val > maxVal {
                        maxVal = val
                        p = i
                        q = j
                    }
                }
            }
            if maxVal < 1e-15 { break }

            let app = a[p][p]
            let aqq = a[q][q]
            let apq = a[p][q]
            let tau = (aqq - app) / (2.0 * apq)
            let t = tau >= 0 ? (1.0 / (tau + sqrt(1.0 + tau * tau))) : (-1.0 / (-tau + sqrt(1.0 + tau * tau)))
            let c = 1.0 / sqrt(1.0 + t * t)
            let s = t * c

            a[p][p] = app - t * apq
            a[q][q] = aqq + t * apq
            a[p][q] = 0.0
            a[q][p] = 0.0

            for r in 0..<4 where r != p && r != q {
                let arp = a[r][p]
                let arq = a[r][q]
                a[r][p] = c * arp - s * arq
                a[p][r] = a[r][p]
                a[r][q] = s * arp + c * arq
                a[q][r] = a[r][q]
            }

            for r in 0..<4 {
                let vrp = v[r][p]
                let vrq = v[r][q]
                v[r][p] = c * vrp - s * vrq
                v[r][q] = s * vrp + c * vrq
            }
        }
        return ([a[0][0], a[1][1], a[2][2], a[3][3]], v)
    }

    private static func rowMajor4x4(rotation r: simd_double3x3, translation t: SIMD3<Double>) -> [Double] {
        [
            rounded(r.columns.0.x, decimals: 9), rounded(r.columns.1.x, decimals: 9), rounded(r.columns.2.x, decimals: 9), rounded(t.x, decimals: 6),
            rounded(r.columns.0.y, decimals: 9), rounded(r.columns.1.y, decimals: 9), rounded(r.columns.2.y, decimals: 9), rounded(t.y, decimals: 6),
            rounded(r.columns.0.z, decimals: 9), rounded(r.columns.1.z, decimals: 9), rounded(r.columns.2.z, decimals: 9), rounded(t.z, decimals: 6),
            0.0, 0.0, 0.0, 1.0
        ]
    }

    private static func rounded(_ value: Double, decimals: Int) -> Double {
        let factor = pow(10.0, Double(decimals))
        return (value * factor).rounded() / factor
    }
}

enum GCPExportKind: String, CaseIterable, Identifiable {
    case csv
    case geojson
    case dxf
    case cloudCompare
    case qgisPoints

    var id: String { rawValue }

    var fileName: String {
        switch self {
        case .csv: return "gcps.csv"
        case .geojson: return "gcps.geojson"
        case .dxf: return "gcps.dxf"
        case .cloudCompare: return "gcps-cloudcompare.txt"
        case .qgisPoints: return "gcps.points"
        }
    }
}

enum GCPExporter {
    private static let posix = Locale(identifier: "en_US_POSIX")

    static func data(for points: [GroundControlPoint], kind: GCPExportKind, metadata: ScanMetadata? = nil) throws -> Data {
        switch kind {
        case .csv:
            return csvData(for: points)
        case .geojson:
            return try geoJSONData(for: points, metadata: metadata)
        case .dxf:
            return dxfData(for: points)
        case .cloudCompare:
            return cloudCompareData(for: points)
        case .qgisPoints:
            return qgisPointsData(for: points)
        }
    }

    static func csvData(for points: [GroundControlPoint]) -> Data {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let geo = GCPRegistration.computeGeoreferencing(for: points)
        let residualMap = Dictionary((geo?.residuals ?? []).map { ($0.label, $0.error3DMeters) }, uniquingKeysWith: { a, _ in a })

        var lines = ["label,local_x_m,local_y_m,local_z_m,target_x,target_y,target_z,crs,note,created_at,crs_name,wkt_local,wkt_target,residual_m"]
        for p in points {
            let normalizedCRS = CRSCatalog.normalizeCode(p.coordinateSystem)
            let resolved = normalizedCRS.isEmpty ? nil : CRSCatalog.lookup(normalizedCRS)
            let localWKT = "POINT Z (\(fmt(p.localX, 6)) \(fmt(p.localY, 6)) \(fmt(p.localZ, 6)))"
            let targetWKT: String
            if let tx = p.targetX, let ty = p.targetY {
                targetWKT = "POINT Z (\(fmt(tx, 8)) \(fmt(ty, 8)) \(fmt(p.targetZ ?? 0, 4)))"
            } else {
                targetWKT = ""
            }
            let residual = residualMap[p.label].map { fmt($0, 6) } ?? ""
            let fields = [
                csvEscape(p.label),
                fmt(p.localX, 6),
                fmt(p.localY, 6),
                fmt(p.localZ, 6),
                p.targetX.map { fmt($0, 8) } ?? "",
                p.targetY.map { fmt($0, 8) } ?? "",
                p.targetZ.map { fmt($0, 4) } ?? "",
                csvEscape(normalizedCRS),
                csvEscape(p.note),
                csvEscape(iso.string(from: p.createdAt)),
                csvEscape(resolved?.name ?? ""),
                csvEscape(localWKT),
                csvEscape(targetWKT),
                residual
            ]
            lines.append(fields.joined(separator: ","))
        }
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }

    static func geoJSONData(for points: [GroundControlPoint], metadata: ScanMetadata? = nil) throws -> Data {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let geo = metadata?.georeferencing ?? GCPRegistration.computeGeoreferencing(for: points)
        let residualMap = Dictionary((geo?.residuals ?? []).map { ($0.label, $0.error3DMeters) }, uniquingKeysWith: { a, _ in a })

        let features: [[String: Any]] = points.map { p in
            let normalizedCRS = CRSCatalog.normalizeCode(p.coordinateSystem)
            let resolved = normalizedCRS.isEmpty ? nil : CRSCatalog.lookup(normalizedCRS)
            let hasTarget = p.targetX != nil && p.targetY != nil
            let coords: [Double] = hasTarget
                ? [p.targetX ?? 0, p.targetY ?? 0, p.targetZ ?? 0]
                : [p.localX, p.localY, p.localZ]

            var props: [String: Any] = [
                "label": p.label,
                "localX": p.localX,
                "localY": p.localY,
                "localZ": p.localZ,
                "crs": normalizedCRS,
                "hasTargetCoordinates": hasTarget,
                "note": p.note,
                "createdAt": iso.string(from: p.createdAt)
            ]
            if let tx = p.targetX { props["targetX"] = tx }
            if let ty = p.targetY { props["targetY"] = ty }
            if let tz = p.targetZ { props["targetZ"] = tz }
            if let crsName = resolved?.name { props["crsName"] = crsName }
            if let res = residualMap[p.label] { props["residualMeters"] = res }
            if let metadata {
                props["scanID"] = metadata.scanID.uuidString
                props["scanTitle"] = metadata.title
            }

            return [
                "type": "Feature",
                "id": p.id.uuidString,
                "geometry": [
                    "type": "Point",
                    "coordinates": coords
                ],
                "properties": props
            ]
        }

        var root: [String: Any] = [
            "type": "FeatureCollection",
            "features": features
        ]

        if let urn = geo?.ogcURN {
            root["crs"] = [
                "type": "name",
                "properties": ["name": urn]
            ]
        }

        if let geo {
            var geoDict: [String: Any] = [
                "targetCRS": geo.targetCRS,
                "unit": geo.unit,
                "controlPointCount": geo.controlPointCount,
                "referencePointCount": geo.referencePointCount
            ]
            if let name = geo.targetCRSName { geoDict["targetCRSName"] = name }
            if let urn = geo.ogcURN { geoDict["ogcURN"] = urn }
            if let rmse = geo.rmseMeters { geoDict["rmseMeters"] = rmse }
            if let mat = geo.localToTargetRowMajor { geoDict["localToTargetRowMajor"] = mat }
            root["georeferencing"] = geoDict
        }

        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    static func dxfData(for points: [GroundControlPoint]) -> Data {
        var out: [String] = [
            "0", "SECTION",
            "2", "HEADER",
            "9", "$INSUNITS",
            "70", "6",
            "0", "ENDSEC",
            "0", "SECTION",
            "2", "ENTITIES"
        ]

        for p in points {
            out.append(contentsOf: [
                "0", "POINT",
                "8", "GCP_LOCAL",
                "10", fmt(p.localX, 6),
                "20", fmt(p.localY, 6),
                "30", fmt(p.localZ, 6)
            ])
            if let tx = p.targetX, let ty = p.targetY {
                out.append(contentsOf: [
                    "0", "POINT",
                    "8", "GCP_TARGET",
                    "10", fmt(tx, 6),
                    "20", fmt(ty, 6),
                    "30", fmt(p.targetZ ?? 0, 6)
                ])
            }
        }

        out.append(contentsOf: ["0", "ENDSEC", "0", "EOF"])
        return Data((out.joined(separator: "\n") + "\n").utf8)
    }

    static func cloudCompareData(for points: [GroundControlPoint]) -> Data {
        let geo = GCPRegistration.computeGeoreferencing(for: points)
        let crsCode = geo?.targetCRS ?? "LOCAL"
        let crsName = geo?.targetCRSName ?? ""
        let crsHeader = crsName.isEmpty ? crsCode : "\(crsCode) (\(crsName))"

        var lines: [String] = [
            "# LiDAR Scanner GCP Export (CloudCompare / Metashape compatible)",
            "# CoordinateSystem: \(crsHeader)"
        ]
        if let rmse = geo?.rmseMeters {
            lines.append("# RMSE_3D_m: \(fmt(rmse, 6))")
        }
        if let mat = geo?.localToTargetRowMajor, mat.count == 16 {
            lines.append("# Local_to_Target_Matrix_4x4 (row-major):")
            for row in 0..<4 {
                let start = row * 4
                let rowStr = (start..<(start + 4)).map { fmt(mat[$0], 9) }.joined(separator: " ")
                lines.append("# \(rowStr)")
            }
        }

        let targetPoints = points.filter { $0.targetX != nil && $0.targetY != nil }
        if !targetPoints.isEmpty {
            lines.append("# Target_Reference_Points (label, X, Y, Z)")
            for p in targetPoints {
                let row = [
                    p.label,
                    fmt(p.targetX ?? 0, 8),
                    fmt(p.targetY ?? 0, 8),
                    fmt(p.targetZ ?? 0, 4)
                ].joined(separator: ", ")
                lines.append(row)
            }
        }

        lines.append("# Local_Scan_Points (label, local_x_m, local_y_m, local_z_m)")
        for p in points {
            let row = [
                p.label,
                fmt(p.localX, 6),
                fmt(p.localY, 6),
                fmt(p.localZ, 6)
            ].joined(separator: ", ")
            lines.append(row)
        }

        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }

    static func qgisPointsData(for points: [GroundControlPoint]) -> Data {
        let geo = GCPRegistration.computeGeoreferencing(for: points)
        let crsCode = geo?.targetCRS ?? "LOCAL"
        let residualMap = Dictionary((geo?.residuals ?? []).map { ($0.label, $0) }, uniquingKeysWith: { a, _ in a })

        var lines: [String] = [
            "#CRS: \(crsCode)",
            "mapX,mapY,sourceX,sourceY,enable,dX,dY,residual"
        ]

        for p in points {
            guard let tx = p.targetX, let ty = p.targetY else { continue }
            let res = residualMap[p.label]
            let dx = res.map { fmt($0.dx, 6) } ?? "0"
            let dy = res.map { fmt($0.dy, 6) } ?? "0"
            let err = res.map { fmt($0.error3DMeters, 6) } ?? "0"
            lines.append([
                fmt(tx, 8),
                fmt(ty, 8),
                fmt(p.localX, 6),
                fmt(p.localY, 6),
                "1",
                dx,
                dy,
                err
            ].joined(separator: ","))
        }

        return Data((lines.joined(separator: "\n") + "\n").utf8)
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
}
