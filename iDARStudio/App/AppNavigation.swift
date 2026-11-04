import Foundation
import Combine

nonisolated enum AppDestination: Hashable, Sendable {
    case objectStudio
    case roomStudio
    case environmentStudio
    case library
    case settings
    case about
}

@MainActor
final class AppNavigationState: ObservableObject {
    @Published var path: [AppDestination] = []

    func open(_ destination: AppDestination) {
        path.append(destination)
    }

    func returnHome() {
        path.removeAll()
    }
}
