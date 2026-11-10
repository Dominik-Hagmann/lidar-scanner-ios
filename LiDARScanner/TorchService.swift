import AVFoundation
import Combine

/// Controls the device's rear-facing LED torch/flashlight for illuminating
/// dark niches, trenches, tombs, and indoor scenes during 3D LiDAR and Gaussian capture.
final class TorchService: ObservableObject {
    static let shared = TorchService()

    @Published var isOn: Bool = false
    @Published var level: Float = 1.0

    var isAvailable: Bool {
        guard let device = backCamera else { return false }
        return device.hasTorch
    }

    private var backCamera: AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(for: .video)
    }

    private init() {}

    func setTorch(on: Bool, level: Float? = nil) {
        guard let device = backCamera, device.hasTorch else {
            if isOn { isOn = false }
            return
        }

        let targetLevel = max(0.01, min(1.0, level ?? self.level))
        do {
            try device.lockForConfiguration()
            if on {
                try device.setTorchModeOn(level: targetLevel)
                isOn = true
                self.level = targetLevel
            } else {
                device.torchMode = .off
                isOn = false
            }
            device.unlockForConfiguration()
        } catch {
            isOn = false
        }
    }

    func toggle() {
        setTorch(on: !isOn)
    }

    func turnOff() {
        if isOn {
            setTorch(on: false)
        }
    }
}
