import SwiftUI

@main
struct LiDARScannerApp: App {
    @StateObject private var model = ScanModel()
    @ObservedObject private var language = LanguageManager.shared
    var body: some Scene {
        WindowGroup {
            ScanModeView(pointCloud: model)
                .environment(\.locale, language.locale)
                .preferredColorScheme(.dark)
                .tint(Color(red: 0.38, green: 0.93, blue: 0.76))
                .onOpenURL { url in
                    Task {
                        do {
                            let imported = try await model.importScan(from: url)
                            await MainActor.run {
                                model.notifyImported(imported)
                            }
                        } catch {
                            await MainActor.run {
                                model.errorMessage = error.localizedDescription
                            }
                        }
                    }
                }
        }
    }
}
