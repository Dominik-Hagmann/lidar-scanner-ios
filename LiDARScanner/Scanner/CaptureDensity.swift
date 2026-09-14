import Foundation

enum CaptureDensity: String, CaseIterable, Identifiable {
    case low
    case standard
    case high

    var id: String { rawValue }

    var title: String {
        switch self {
        case .low: "Low"
        case .standard: "Standard"
        case .high: "High"
        }
    }

    var frameInterval: TimeInterval {
        switch self {
        case .low: 0.20
        case .standard: 0.15
        case .high: 0.12
        }
    }

    var depthStride: Int {
        switch self {
        case .low: 3
        case .standard: 2
        case .high: 1
        }
    }
}
