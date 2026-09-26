import Foundation

enum GaussianPhase: String, Codable {
    case captured, preparing, training, paused, completed, failed, capturing
    var title: String {
        switch self {
        case .captured: return String(localized: "Capture saved")
        case .preparing: return String(localized: "Preparing 3D scene…")
        case .training: return String(localized: "Creating 3D scene…")
        case .paused: return String(localized: "Processing paused")
        case .completed: return String(localized: "3D scene ready")
        case .failed: return String(localized: "Processing needs attention")
        case .capturing: return String(localized: "Capturing views…")
        }
    }
}

struct GaussianFrame: Codable {
    let file_path: String
    let w: Int
    let h: Int
    let fl_x: Float
    let fl_y: Float
    let cx: Float
    let cy: Float
    let transform_matrix: [[Float]]
    let timestamp: Double
    let capturedAt: Date
    let sha256: String
}

struct GaussianDatasetManifest: Codable {
    var camera_model = "OPENCV"
    var k1: Float = 0, k2: Float = 0, p1: Float = 0, p2: Float = 0
    let ply_file_path: String?
    let frames: [GaussianFrame]
}

struct GaussianProfile: Codable, Equatable {
    let name: String
    let iterations: Int
    let downscaleFactor: Float
    var shDegree = 2
    var shDegreeInterval = 500
    var ssimWeight: Float = 0.2
    var numDownscales = 1
    let resolutionSchedule: Int
    var refineEvery = 100
    var warmupLength = 100
    var resetAlphaEvery = 30
    var densifyGradThresh: Float = 0.0002
    var densifySizeThresh: Float = 0.01
    var stopScreenSizeAt = 4000
    let stopDensifyAt: Int
    var splitScreenSize: Float = 0.05
    var keepCrs = true
    var background: [Float] = [0, 0, 0]
    var imageCacheMB = 512

    static func automatic(frames: [GaussianFrame]) -> GaussianProfile {
        let steps = max(1500, min(6000, frames.count * 35))
        let edge = frames.map { max($0.w, $0.h) }.max() ?? 1920
        return GaussianProfile(name: "automatic-v1", iterations: steps,
            downscaleFactor: Float(max(1, Int(ceil(Double(edge) / 1024)))),
            resolutionSchedule: max(1, steps / 3), stopDensifyAt: steps / 2)
    }
}

struct GaussianProject: Codable, Identifiable {
    static let pinnedEngineRevision = "e8611098583059b82e0b7d35259fb4e9c42df248"
    static let pinnedViewerRevision = "464eb37c55d90d7362a79120fdf8b50d4ae03296"
    var schemaVersion = 1
    let id: UUID
    let startedAt: Date
    var updatedAt: Date
    let appVersion: String
    let appBuild: String
    let device: String
    let operatingSystem: String
    var phase: GaussianPhase = .capturing
    var frames: [GaussianFrame] = []
    var decisions: [String: Int] = [:]
    var seedCount = 0
    var seedFile: String?
    var seedHash: String?
    var profile: GaussianProfile?
    var iteration = 0
    var checkpointIteration = 0
    var checkpointSplatCount = 0
    var checkpointHash: String?
    var splatCount = 0
    var processingSeconds: Double = 0
    var resultHash: String?
    var lastIssue: String?
    var recoveryNote: String?
    var auditHead = ""
    var engine = "msplat-ios"
    var engineRevision = GaussianProject.pinnedEngineRevision
    var enginePatch = "scanner-io-audit-5"
    var viewerRevision = GaussianProject.pinnedViewerRevision
    var coordinateSystem = "ARKit world; right-handed; metres; Y up; camera-to-world OpenGL (-Z forward, +Y up); no CRS/EPSG or north alignment"
    var capturePolicy: [String: String] = [
        "minimumIntervalSeconds": "0.5", "minimumTranslationMetres": "0.025",
        "minimumRotationDegrees": "3", "trackingRequired": "normal",
        "maximumInFlightFrames": "1", "jpegQuality": "0.95",
        "imageOrientation": "native sensor; no rotation or crop; per-image intrinsics",
        "seedVoxelMetres": "0.03", "seedMinimumDepthMetres": "0.2", "seedMaximumDepthMetres": "5",
        "seedPixelStep": "4", "seedMinimumConfidence": "1", "seedMaximumPoints": "100000",
        "seedSelection": "one observation per voxel; first retained unless higher confidence arrives",
        "lowMemoryPauseBytes": "402653184", "minimumDiskBytes": "536870912",
        "minimumTrainingViews": "12", "checkpointEverySteps": "100"
    ]
    var directory: URL { GaussianStore.root.appendingPathComponent(id.uuidString, isDirectory: true) }
    var resultURL: URL { directory.appendingPathComponent("scene.ply") }
    var title: String { startedAt.formatted(date: .abbreviated, time: .shortened) }
    var receivedFrames: Int { decisions.values.reduce(0, +) }
    var hasResult: Bool { resultHash != nil && FileManager.default.fileExists(atPath: resultURL.path) }
}

enum GaussianError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
