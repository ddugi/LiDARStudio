import SwiftUI

@main
struct LiDARStudioApp: App {
    @StateObject private var library = ScanLibrary()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(library)
                .preferredColorScheme(.dark)
                .tint(StudioTheme.accent)
        }
    }
}
