import AppIntents
import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var navigation: AppNavigationState
    @EnvironmentObject private var library: ScanLibrary
    @AppStorage(OnboardingPreference.key) private var hasCompletedOnboarding = false

    var body: some View {
        NavigationStack(path: $navigation.path) {
            HomeView()
                .navigationDestination(for: AppDestination.self) { destination in
                    destinationView(destination)
                }
        }
        .environmentObject(navigation)
        .onAppIntentExecution(OpenScanLibraryIntent.self) { _ in
            navigation.openFromExternalRequest(.library)
        }
        .onAppIntentExecution(OpenSavedModelIntent.self) { intent in
            openModelRequestedByIntent(intent.scan.id)
        }
        .onAppIntentExecution(PrepareObjectStudioIntent.self) { _ in
            navigation.openFromExternalRequest(.objectStudio)
        }
        .alert("Unable to Open Scan", isPresented: externalNavigationErrorBinding) {
            Button("OK") { navigation.clearExternalNavigationError() }
        } message: {
            Text(navigation.externalNavigationError ?? "The requested scan is unavailable.")
        }
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
        case .scanModel(let scanID): AppIntentModelDestinationView(scanID: scanID)
        case .settings: SettingsView()
        case .about: AboutView()
        }
    }

    private func openModelRequestedByIntent(_ scanID: UUID) {
        library.reload()
        guard let scan = library.scans.first(where: { $0.id == scanID }),
              library.modelURL(for: scan) != nil else {
            navigation.reportExternalNavigationError(
                "The selected scan no longer has a valid local USDZ model. No file was opened or shared."
            )
            return
        }
        navigation.openFromExternalRequest(.scanModel(scanID))
    }

    private var externalNavigationErrorBinding: Binding<Bool> {
        Binding(
            get: { navigation.externalNavigationError != nil },
            set: { if !$0 { navigation.clearExternalNavigationError() } }
        )
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(ScanLibrary.preview)
            .environmentObject(AppNavigationState())
            .preferredColorScheme(.dark)
    }
}
