import Foundation

nonisolated struct RoomCaptureLifecycle: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case idle, ready, starting, capturing, stopping, processing
        case review, saving, saved, failed, cancelled

        var title: String {
            switch self {
            case .idle, .ready: "Ready to scan"
            case .starting: "Preparing camera"
            case .capturing: "Scanning room"
            case .stopping: "Finishing capture"
            case .processing: "Processing room"
            case .review: "Review room"
            case .saving: "Saving room"
            case .saved: "Room saved"
            case .failed: "Room scan failed"
            case .cancelled: "Room scan cancelled"
            }
        }
    }

    private(set) var phase: Phase = .idle

    var isCaptureActive: Bool {
        [.starting, .capturing, .stopping].contains(phase)
    }

    var keepsCaptureViewMounted: Bool {
        isCaptureActive || phase == .processing
    }

    mutating func attach() {
        if phase == .idle || phase == .cancelled { phase = .ready }
    }

    mutating func requestStart() -> Bool {
        guard phase == .ready else { return false }
        phase = .starting
        return true
    }

    mutating func confirmStarted() {
        guard phase == .starting else { return }
        phase = .capturing
    }

    mutating func requestFinish() -> Bool {
        guard phase == .capturing else { return false }
        phase = .stopping
        return true
    }

    mutating func beginProcessing() {
        guard phase == .stopping else { return }
        phase = .processing
    }

    mutating func presentReview() {
        guard phase == .processing else { return }
        phase = .review
    }

    mutating func requestSave() -> Bool {
        guard phase == .review else { return false }
        phase = .saving
        return true
    }

    mutating func confirmSaved() {
        guard phase == .saving else { return }
        phase = .saved
    }

    mutating func fail() { phase = .failed }

    mutating func cancel() {
        guard phase != .saved && phase != .failed else { return }
        phase = .cancelled
    }

    mutating func reset() { phase = .idle }
}
