import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var navigation = AppNavigationState()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        NavigationStack(path: $navigation.path) {
            HomeView()
                .navigationDestination(for: AppDestination.self) { destination in
                    destinationView(destination)
                }
        }
        .environmentObject(navigation)
        .fullScreenCover(isPresented: Binding(
            get: { !hasCompletedOnboarding },
            set: { if !$0 { hasCompletedOnboarding = true } }
        )) {
            OnboardingView { hasCompletedOnboarding = true }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                ScreenAwakeManager.shared.applicationDidEnterBackground()
            }
        }
    }

    @ViewBuilder
    private func destinationView(_ destination: AppDestination) -> some View {
        switch destination {
        case .objectStudio: ObjectStudioView()
        case .roomStudio: RoomStudioView()
        case .environmentStudio: EnvironmentStudioView()
        case .library: ScanLibraryView()
        case .settings: SettingsView()
        case .about: AboutView()
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(ScanLibrary.preview)
            .preferredColorScheme(.dark)
    }
}
