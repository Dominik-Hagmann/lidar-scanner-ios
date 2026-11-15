import CoreLocation
import MapKit
import SwiftUI

struct ArchiveMapItem: Identifiable, Equatable {
    enum Kind: String, Equatable {
        case pointCloud
        case gaussian
    }

    let id: String
    let title: String
    let subtitle: String
    let date: Date
    let kind: Kind
    let location: GeoLocation
    let pointCloudScan: SavedScan?
    let gaussianProject: GaussianProject?

    static func == (lhs: ArchiveMapItem, rhs: ArchiveMapItem) -> Bool {
        lhs.id == rhs.id &&
            lhs.kind == rhs.kind &&
            lhs.title == rhs.title &&
            lhs.subtitle == rhs.subtitle &&
            lhs.date == rhs.date &&
            lhs.location == rhs.location
    }

    static func loadAllGeoreferenced(
        pointClouds: [SavedScan]? = nil,
        gaussians: [GaussianProject]? = nil
    ) -> [ArchiveMapItem] {
        let pcList = pointClouds ?? (try? ScanStorage.list()) ?? []
        let gsList = gaussians ?? (try? GaussianStore.list()) ?? []

        var items: [ArchiveMapItem] = []
        items.reserveCapacity(pcList.count + gsList.count)

        for scan in pcList {
            guard let loc = scan.metadata.location, loc.isValidCoordinate else { continue }
            items.append(ArchiveMapItem(
                id: "pc-\(scan.id)",
                title: scan.metadata.title,
                subtitle: L("Points: %@ · m · Z↑", scan.metadata.pointCount.formatted()),
                date: scan.metadata.savedAt,
                kind: .pointCloud,
                location: loc,
                pointCloudScan: scan,
                gaussianProject: nil
            ))
        }

        for project in gsList {
            guard let loc = project.location, loc.isValidCoordinate else { continue }
            items.append(ArchiveMapItem(
                id: "gs-\(project.id.uuidString)",
                title: project.title,
                subtitle: L("Saved views: %lld", Int64(project.frames.count)),
                date: project.updatedAt,
                kind: .gaussian,
                location: loc,
                pointCloudScan: nil,
                gaussianProject: project
            ))
        }

        return items.sorted { $0.date > $1.date }
    }
}

private enum MapVisualStyle {
    static let mint = Color(red: 0.38, green: 0.93, blue: 0.76)
    static let gaussianAccent = Color.orange

    static func regionPosition(for location: GeoLocation) -> MapCameraPosition {
        let spanMeters = max(100.0, min(1500.0, location.horizontalAccuracy > 0 ? location.horizontalAccuracy * 6.0 : 180.0))
        return .region(MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: spanMeters,
            longitudinalMeters: spanMeters
        ))
    }

    static func fitAllPosition(for items: [ArchiveMapItem]) -> MapCameraPosition {
        guard let first = items.first else { return .automatic }
        if items.count == 1 {
            return regionPosition(for: first.location)
        }

        var minLat = first.location.latitude
        var maxLat = first.location.latitude
        var minLon = first.location.longitude
        var maxLon = first.location.longitude

        for item in items.dropFirst() {
            minLat = min(minLat, item.location.latitude)
            maxLat = max(maxLat, item.location.latitude)
            minLon = min(minLon, item.location.longitude)
            maxLon = max(maxLon, item.location.longitude)
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) * 0.5,
            longitude: (minLon + maxLon) * 0.5
        )
        let latDelta = max(0.0025, (maxLat - minLat) * 1.55)
        let lonDelta = max(0.0025, (maxLon - minLon) * 1.55)
        return .region(MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
        ))
    }

    static func accuracyText(_ location: GeoLocation) -> String {
        let posix = Locale(identifier: "en_US_POSIX")
        let hAcc = String(format: "±%.1f m", locale: posix, location.horizontalAccuracy)
        if let vAcc = location.verticalAccuracy {
            return "\(hAcc) / " + String(format: "±%.1f m", locale: posix, vAcc)
        }
        return hAcc
    }

    static func altitudeText(_ location: GeoLocation) -> String? {
        guard let alt = location.altitude else { return nil }
        return String(format: "%.1f m", locale: Locale(identifier: "en_US_POSIX"), alt)
    }
}

private struct ScanPinBadgeView: View {
    let heading: Double?
    let tint: Color
    var isSelected: Bool = false

    var body: some View {
        ZStack {
            if let heading, heading.isFinite, heading >= 0 {
                HeadingConeShape()
                    .fill(tint.opacity(0.35))
                    .frame(width: 44, height: 44)
                    .rotationEffect(.degrees(heading))
            }

            Circle()
                .fill(tint)
                .frame(width: isSelected ? 26 : 20, height: isSelected ? 26 : 20)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: isSelected ? 2.5 : 2)
                )
                .shadow(color: .black.opacity(0.45), radius: 3, y: 1)

            if let heading, heading.isFinite, heading >= 0 {
                Image(systemName: "location.north.fill")
                    .font(.system(size: isSelected ? 12 : 9, weight: .bold))
                    .foregroundStyle(.black)
                    .rotationEffect(.degrees(heading))
            } else {
                Circle()
                    .fill(.black)
                    .frame(width: isSelected ? 7 : 5, height: isSelected ? 7 : 5)
            }
        }
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }
}

private struct HeadingConeShape: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) * 0.5
        // 0° points straight up (-90° in Core Graphics / SwiftUI unit circle)
        var path = Path()
        path.move(to: center)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(-115),
            endAngle: .degrees(-65),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

struct ScanLocationMapCard: View {
    let location: GeoLocation
    var title: String? = nil
    var height: CGFloat = 210

    @ObservedObject private var language = LanguageManager.shared
    @State private var position: MapCameraPosition
    @State private var useHybrid = false
    @State private var showExpandedSheet = false

    init(location: GeoLocation, title: String? = nil, height: CGFloat = 210) {
        self.location = location
        self.title = title
        self.height = height
        self._position = State(initialValue: MapVisualStyle.regionPosition(for: location))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                Map(position: $position, interactionModes: .all) {
                    if location.horizontalAccuracy > 0 {
                        MapCircle(
                            center: location.coordinate,
                            radius: max(1.0, location.horizontalAccuracy)
                        )
                        .foregroundStyle(.cyan.opacity(0.2))
                        .stroke(.cyan, lineWidth: 1.5)
                    }

                    if let endCoord = location.headingRayEndCoordinate(
                        distanceMeters: max(12.0, location.horizontalAccuracy * 1.8)
                    ) {
                        MapPolyline(coordinates: [location.coordinate, endCoord])
                            .stroke(MapVisualStyle.mint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    }

                    Annotation(title ?? L("GNSS Location"), coordinate: location.coordinate, anchor: .center) {
                        ScanPinBadgeView(heading: location.heading, tint: MapVisualStyle.mint, isSelected: true)
                    }
                }
                .mapStyle(useHybrid ? .hybrid(elevation: .realistic) : .standard(elevation: .realistic))
                .mapControls {
                    MapCompass()
                    MapScaleView()
                }
                .frame(height: height)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )

                HStack(spacing: 6) {
                    Button {
                        useHybrid.toggle()
                    } label: {
                        Image(systemName: useHybrid ? "map" : "globe.americas.fill")
                            .font(.caption.weight(.semibold))
                            .frame(width: 30, height: 30)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L(useHybrid ? "Standard" : "Satellite"))

                    Button {
                        withAnimation {
                            position = MapVisualStyle.regionPosition(for: location)
                        }
                    } label: {
                        Image(systemName: "location.viewfinder")
                            .font(.caption.weight(.semibold))
                            .frame(width: 30, height: 30)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("Recenter"))

                    Button {
                        showExpandedSheet = true
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.caption.weight(.semibold))
                            .frame(width: 30, height: 30)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("Maximize"))
                }
                .padding(8)
            }

            HStack(spacing: 12) {
                Label(MapVisualStyle.accuracyText(location), systemImage: "scope")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                if let alt = MapVisualStyle.altitudeText(location) {
                    Label(alt, systemImage: "arrow.up.and.down")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if let headingStr = location.cardinalHeadingString {
                    Label(headingStr, systemImage: "safari")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .sheet(isPresented: $showExpandedSheet) {
            ScanLocationMapSheet(location: location, title: title)
        }
    }
}

struct ScanLocationMapSheet: View {
    let location: GeoLocation
    var title: String? = nil

    @ObservedObject private var language = LanguageManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var position: MapCameraPosition
    @State private var useHybrid = false

    init(location: GeoLocation, title: String? = nil) {
        self.location = location
        self.title = title
        self._position = State(initialValue: MapVisualStyle.regionPosition(for: location))
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Map(position: $position, interactionModes: .all) {
                    if location.horizontalAccuracy > 0 {
                        MapCircle(
                            center: location.coordinate,
                            radius: max(1.0, location.horizontalAccuracy)
                        )
                        .foregroundStyle(.cyan.opacity(0.2))
                        .stroke(.cyan, lineWidth: 2)
                    }

                    if let endCoord = location.headingRayEndCoordinate(
                        distanceMeters: max(15.0, location.horizontalAccuracy * 2.0)
                    ) {
                        MapPolyline(coordinates: [location.coordinate, endCoord])
                            .stroke(MapVisualStyle.mint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    }

                    Annotation(title ?? L("GNSS Location"), coordinate: location.coordinate, anchor: .center) {
                        ScanPinBadgeView(heading: location.heading, tint: MapVisualStyle.mint, isSelected: true)
                    }
                }
                .mapStyle(useHybrid ? .hybrid(elevation: .realistic) : .standard(elevation: .realistic))
                .mapControls {
                    MapCompass()
                    MapScaleView()
                }
                .ignoresSafeArea(edges: .bottom)

                VStack(alignment: .leading, spacing: 8) {
                    if let title, !title.isEmpty {
                        Text(title)
                            .font(.headline)
                    }
                    HStack {
                        Text(L("GNSS Location"))
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(location.formattedCoordinates)
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .textSelection(.enabled)
                    }
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("Accuracy")).font(.caption2).foregroundStyle(.secondary)
                            Text(MapVisualStyle.accuracyText(location)).font(.caption.monospacedDigit())
                        }
                        if let alt = MapVisualStyle.altitudeText(location) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L("Altitude")).font(.caption2).foregroundStyle(.secondary)
                                Text(alt).font(.caption.monospacedDigit())
                            }
                        }
                        if let headingStr = location.cardinalHeadingString {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L("Heading")).font(.caption2).foregroundStyle(.secondary)
                                Text(headingStr).font(.caption.monospacedDigit())
                            }
                        }
                        Spacer()
                    }
                }
                .padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .navigationTitle(L("GNSS Map"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Picker(L("Map"), selection: $useHybrid) {
                        Text(L("Standard")).tag(false)
                        Text(L("Satellite")).tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 170)

                    Button {
                        withAnimation {
                            position = MapVisualStyle.regionPosition(for: location)
                        }
                    } label: {
                        Image(systemName: "location.viewfinder")
                    }
                    .accessibilityLabel(L("Recenter"))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Done")) { dismiss() }
                }
            }
        }
    }
}

struct ArchiveScansMapView: View {
    let items: [ArchiveMapItem]
    var onSelectPointCloud: ((SavedScan) -> Void)? = nil
    var onSelectGaussian: ((GaussianProject) -> Void)? = nil

    @ObservedObject private var language = LanguageManager.shared
    @State private var position: MapCameraPosition
    @State private var selectedItemID: String?
    @State private var useHybrid = false
    @State private var detailMapItem: ArchiveMapItem?

    init(
        items: [ArchiveMapItem],
        onSelectPointCloud: ((SavedScan) -> Void)? = nil,
        onSelectGaussian: ((GaussianProject) -> Void)? = nil
    ) {
        self.items = items
        self.onSelectPointCloud = onSelectPointCloud
        self.onSelectGaussian = onSelectGaussian
        self._position = State(initialValue: MapVisualStyle.fitAllPosition(for: items))
        self._selectedItemID = State(initialValue: items.first?.id)
    }

    private var selectedItem: ArchiveMapItem? {
        items.first(where: { $0.id == selectedItemID }) ?? items.first
    }

    var body: some View {
        if items.isEmpty {
            ContentUnavailableView(
                L("No Georeferenced Scans"),
                systemImage: "map",
                description: Text(L("Scans recorded with GNSS location enabled will appear on this map."))
            )
        } else {
            ZStack(alignment: .bottom) {
                Map(position: $position, interactionModes: .all) {
                    ForEach(items) { item in
                        let tint = item.kind == .pointCloud ? MapVisualStyle.mint : MapVisualStyle.gaussianAccent
                        if item.location.horizontalAccuracy > 0 {
                            MapCircle(
                                center: item.location.coordinate,
                                radius: max(1.0, item.location.horizontalAccuracy)
                            )
                            .foregroundStyle(tint.opacity(0.16))
                            .stroke(tint.opacity(0.75), lineWidth: 1.2)
                        }

                        if let endCoord = item.location.headingRayEndCoordinate(
                            distanceMeters: max(12.0, item.location.horizontalAccuracy * 1.8)
                        ) {
                            MapPolyline(coordinates: [item.location.coordinate, endCoord])
                                .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        }

                        Annotation(item.title, coordinate: item.location.coordinate, anchor: .center) {
                            Button {
                                withAnimation {
                                    selectedItemID = item.id
                                    position = MapVisualStyle.regionPosition(for: item.location)
                                }
                            } label: {
                                ScanPinBadgeView(
                                    heading: item.location.heading,
                                    tint: tint,
                                    isSelected: selectedItem?.id == item.id
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .mapStyle(useHybrid ? .hybrid(elevation: .realistic) : .standard(elevation: .realistic))
                .mapControls {
                    MapCompass()
                    MapScaleView()
                }
                .ignoresSafeArea(edges: .bottom)
                .onChange(of: items) { _, updated in
                    if let currentID = selectedItemID, !updated.contains(where: { $0.id == currentID }) {
                        selectedItemID = updated.first?.id
                    } else if selectedItemID == nil {
                        selectedItemID = updated.first?.id
                    }
                    position = MapVisualStyle.fitAllPosition(for: updated)
                }

                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        HStack(spacing: 10) {
                            legendPill(color: MapVisualStyle.mint, text: L("Point Cloud"))
                            legendPill(color: MapVisualStyle.gaussianAccent, text: L("Gaussian Splatting"))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())

                        Spacer()

                        Button {
                            withAnimation {
                                position = MapVisualStyle.fitAllPosition(for: items)
                            }
                        } label: {
                            Image(systemName: "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left")
                                .font(.caption.weight(.semibold))
                                .frame(width: 34, height: 34)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L("Fit All"))

                        Button {
                            useHybrid.toggle()
                        } label: {
                            Image(systemName: useHybrid ? "map" : "globe.americas.fill")
                                .font(.caption.weight(.semibold))
                                .frame(width: 34, height: 34)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L(useHybrid ? "Standard" : "Satellite"))
                    }

                    Spacer()

                    if let item = selectedItem {
                        selectionCard(for: item)
                    }
                }
                .padding(14)
            }
            .sheet(item: $detailMapItem) { item in
                ScanLocationMapSheet(location: item.location, title: item.title)
            }
        }
    }

    @ViewBuilder
    private func legendPill(color: Color, text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(.caption2.weight(.medium))
        }
    }

    @ViewBuilder
    private func selectionCard(for item: ArchiveMapItem) -> some View {
        let tint = item.kind == .pointCloud ? MapVisualStyle.mint : MapVisualStyle.gaussianAccent
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(item.kind == .pointCloud ? L("Point Cloud") : L("Gaussian Splatting"))
                            .font(.caption2.bold())
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(tint.opacity(0.22), in: Capsule())
                            .foregroundStyle(tint)
                        Text(item.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(item.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(item.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    detailMapItem = item
                } label: {
                    Image(systemName: "map")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 34, height: 34)
                        .background(.secondary.opacity(0.16), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("GNSS Map"))
            }

            HStack(spacing: 12) {
                Label(item.location.formattedCoordinates, systemImage: "location.fill")
                    .font(.caption2.monospacedDigit())
                    .lineLimit(1)
                Spacer()
                Text(MapVisualStyle.accuracyText(item.location))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if (item.kind == .pointCloud && item.pointCloudScan != nil && onSelectPointCloud != nil) ||
                (item.kind == .gaussian && item.gaussianProject != nil && onSelectGaussian != nil) {
                Button {
                    if let scan = item.pointCloudScan {
                        onSelectPointCloud?(scan)
                    } else if let project = item.gaussianProject {
                        onSelectGaussian?(project)
                    }
                } label: {
                    Label(
                        item.kind == .pointCloud ? L("View in 3D") : L("Open Scan"),
                        systemImage: item.kind == .pointCloud ? "cube.transparent" : "arrow.up.forward.app"
                    )
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(tint)
                .foregroundStyle(.black)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
