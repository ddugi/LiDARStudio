import SwiftUI

@main
struct LiDARStudioApp: App {
    @StateObject private var library = ScanLibrary()

    var body: some Scene {
        WindowGroup {
            LiDARStudioSceneRoot()
                .environmentObject(library)
                .preferredColorScheme(.dark)
                .tint(StudioTheme.accent)
        }
    }
}

private struct LiDARStudioSceneRoot: View {
    @StateObject private var navigation = AppNavigationState()

    var body: some View {
        ContentView()
            .environmentObject(navigation)
    }
}
