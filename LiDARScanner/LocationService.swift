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
        return String(format: "%.6f° %@, %.6f° %@", abs(latitude), latDir, abs(longitude), lonDir)
    }
}

final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationService()

    private let manager = CLLocationManager()
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
        guard CLLocationManager.locationServicesEnabled() else { return }
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() {
            manager.startUpdatingHeading()
        }
    }

    func stopUpdating() {
        manager.stopUpdatingLocation()
        if CLLocationManager.headingAvailable() {
            manager.stopUpdatingHeading()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            self.authorizationStatus = manager.authorizationStatus
            if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
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
        // Location updates fail silently if GPS signal is unavailable indoors.
    }
}
