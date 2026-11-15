import Foundation
import CoreLocation
import Combine

struct GeoLocation: Codable, Equatable {
    let latitude: Double
    let longitude: Double
    let altitude: Double?
    let horizontalAccuracy: Double
    let verticalAccuracy: Double?
    let heading: Double?
    let timestamp: Date

    var formattedCoordinates: String {
        let latDir = latitude >= 0 ? "N" : "S"
        let lonDir = longitude >= 0 ? "E" : "W"
        return String(
            format: "%.6f° %@, %.6f° %@",
            locale: Locale(identifier: "en_US_POSIX"),
            abs(latitude), latDir, abs(longitude), lonDir
        )
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var isValidCoordinate: Bool {
        latitude.isFinite && longitude.isFinite && abs(latitude) <= 90 && abs(longitude) <= 180
    }

    /// Returns a coordinate displaced by north/east offsets in meters on the WGS84 sphere.
    func coordinateOffset(northMeters: Double, eastMeters: Double) -> CLLocationCoordinate2D {
        let earthRadius = 6_378_137.0
        let latRad = latitude * .pi / 180.0
        let dLat = (northMeters / earthRadius) * (180.0 / .pi)
        let cosLat = max(1e-6, abs(cos(latRad)))
        let dLon = (eastMeters / (earthRadius * cosLat)) * (180.0 / .pi)
        let clampedLat = min(90.0, max(-90.0, latitude + dLat))
        var wrappedLon = longitude + dLon
        while wrappedLon > 180.0 { wrappedLon -= 360.0 }
        while wrappedLon < -180.0 { wrappedLon += 360.0 }
        return CLLocationCoordinate2D(latitude: clampedLat, longitude: wrappedLon)
    }

    /// Returns the endpoint of a compass heading ray at the given distance in meters, if heading is available.
    func headingRayEndCoordinate(distanceMeters: Double) -> CLLocationCoordinate2D? {
        guard let heading, heading.isFinite, heading >= 0, distanceMeters > 0 else { return nil }
        let rad = heading * .pi / 180.0
        let northMeters = distanceMeters * cos(rad)
        let eastMeters = distanceMeters * sin(rad)
        return coordinateOffset(northMeters: northMeters, eastMeters: eastMeters)
    }

    /// Formats the heading in degrees together with its 8-point cardinal direction (e.g. "92.5° (E)").
    var cardinalHeadingString: String? {
        guard let heading, heading.isFinite, heading >= 0 else { return nil }
        let normalized = ((heading.truncatingRemainder(dividingBy: 360.0)) + 360.0)
            .truncatingRemainder(dividingBy: 360.0)
        let cardinals = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let idx = Int(((normalized + 22.5) / 45.0).rounded(.down)) % 8
        return String(
            format: "%.1f° (%@)",
            locale: Locale(identifier: "en_US_POSIX"),
            normalized,
            cardinals[idx]
        )
    }
}

final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationService()

    private let manager = CLLocationManager()
    private var wantsUpdating = false
    var isEnabled: Bool = true {
        didSet {
            if !isEnabled {
                stopUpdating()
                currentLocation = nil
            }
        }
    }
    @Published private(set) var currentLocation: GeoLocation?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
    }

    func requestAuthorization() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    func startUpdating() {
        guard isEnabled else { return }
        wantsUpdating = true
        let status = manager.authorizationStatus
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.startUpdatingLocation()
            if CLLocationManager.headingAvailable() {
                manager.startUpdatingHeading()
            }
        }
    }

    func stopUpdating() {
        wantsUpdating = false
        manager.stopUpdatingLocation()
        if CLLocationManager.headingAvailable() {
            manager.stopUpdatingHeading()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            self.authorizationStatus = manager.authorizationStatus
            if self.wantsUpdating && self.isEnabled &&
                (manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways) {
                manager.startUpdatingLocation()
                if CLLocationManager.headingAvailable() {
                    manager.startUpdatingHeading()
                }
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        DispatchQueue.main.async {
            let heading = self.currentLocation?.heading
            let alt: Double? = location.verticalAccuracy >= 0 ? location.altitude : nil
            let vAcc: Double? = location.verticalAccuracy >= 0 ? location.verticalAccuracy : nil
            self.currentLocation = GeoLocation(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                altitude: alt,
                horizontalAccuracy: location.horizontalAccuracy,
                verticalAccuracy: vAcc,
                heading: heading,
                timestamp: location.timestamp
            )
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0 else { return }
        DispatchQueue.main.async {
            let headingValue = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
            if let loc = self.currentLocation {
                self.currentLocation = GeoLocation(
                    latitude: loc.latitude,
                    longitude: loc.longitude,
                    altitude: loc.altitude,
                    horizontalAccuracy: loc.horizontalAccuracy,
                    verticalAccuracy: loc.verticalAccuracy,
                    heading: headingValue,
                    timestamp: loc.timestamp
                )
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Location updates fail silently when GNSS signal is unavailable indoors.
    }
}
