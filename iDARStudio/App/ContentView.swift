import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            HomeView()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                ScreenAwakeManager.shared.applicationDidEnterBackground()
            }
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
