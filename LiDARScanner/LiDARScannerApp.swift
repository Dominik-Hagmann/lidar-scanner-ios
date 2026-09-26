import SwiftUI

@main
struct LiDARScannerApp: App {
    @StateObject private var model = ScanModel()
    var body: some Scene {
        WindowGroup {
            ScanModeView(pointCloud: model)
                .preferredColorScheme(.dark)
                .tint(Color(red: 0.38, green: 0.93, blue: 0.76))
        }
    }
}
