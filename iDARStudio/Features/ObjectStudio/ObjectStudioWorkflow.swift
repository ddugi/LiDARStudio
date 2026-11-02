import Foundation

nonisolated enum ObjectStudioPhase: Equatable, Sendable {
    case idle
    case preparing
    case permissionRequired
    case unsupported(String)
    case readyForDetection
    case detecting
    case capturing
    case finishing
    case reviewing
    case reconstructing
    case completed
    case cancelled
    case failed(String)

    var isCaptureSessionActive: Bool {
        switch self {
        case .preparing, .readyForDetection, .detecting, .capturing, .finishing:
            true
        default:
            false
        }
    }
}

nonisolated enum ObjectStudioTransitionPolicy {
    static func permits(from current: ObjectStudioPhase, to next: ObjectStudioPhase) -> Bool {
        if case .failed = next { return true }
        if next == .idle { return true }
        if next == .cancelled { return current.isCaptureSessionActive || current == .reconstructing }

        switch (current, next) {
        case (.idle, .preparing),
             (.permissionRequired, .preparing),
             (.unsupported, .preparing),
             (.cancelled, .preparing),
             (.failed, .preparing),
             (.completed, .preparing),
             (.preparing, .permissionRequired),
             (.preparing, .unsupported),
             (.preparing, .readyForDetection),
             (.readyForDetection, .detecting),
             (.readyForDetection, .capturing),
             (.preparing, .detecting),
             (.detecting, .readyForDetection),
             (.detecting, .capturing),
             (.capturing, .finishing),
             (.finishing, .reviewing),
             (.reviewing, .reconstructing),
             (.reconstructing, .completed):
            return true
        default:
            return false
        }
    }
}
