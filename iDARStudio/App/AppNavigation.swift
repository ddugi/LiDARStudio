import Foundation
import Combine

nonisolated enum AppDestination: Hashable, Sendable {
    case objectStudio
    case roomStudio
    case environmentStudio
    case library
    case scanModel(UUID)
    case settings
    case about
}

@MainActor
final class AppNavigationState: ObservableObject {
    @Published var path: [AppDestination] = []
    @Published private(set) var externalNavigationError: String?

    func open(_ destination: AppDestination) {
        path.append(destination)
    }

    func openFromExternalRequest(_ destination: AppDestination) {
        guard path.last != destination else { return }
        path = [destination]
    }

    func reportExternalNavigationError(_ message: String) {
        externalNavigationError = message
    }

    func clearExternalNavigationError() {
        externalNavigationError = nil
    }

    func returnHome() {
        path.removeAll()
    }
}
