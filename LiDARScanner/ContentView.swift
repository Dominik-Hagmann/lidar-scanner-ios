import ARKit
import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            Group {
                if LiDARScanner.isLiDARSupported {
                    ScannerScreen()
                } else {
                    ContentUnavailableView(
                        "LiDAR unavailable",
                        systemImage: "viewfinder",
                        description: Text("This device does not expose ARKit scene depth. Run the app on a LiDAR-equipped iPhone or iPad.")
                    )
                }
            }
            .navigationTitle("LiDAR Scanner")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
