import Foundation

nonisolated enum ScanProgressStatus: String, Equatable, Sendable {
    case preparingCamera = "Preparing camera"
    case readyToScan = "Ready to scan"
    case detectingObject = "Detecting object"
    case capturing = "Capturing"
    case processingModel = "Processing model"
    case savingModel = "Saving model"
    case scanCompleted = "Scan completed"
    case scanFailed = "Scan failed"
}

nonisolated enum ObjectCaptureGuideStage: Int, CaseIterable, Equatable, Sendable {
    case overview
    case detail
    case extraAngles
    case review
    case process

    var title: String {
        switch self {
        case .overview: "Overview"
        case .detail: "Detail"
        case .extraAngles: "Extra Angles"
        case .review: "Review"
        case .process: "Process"
        }
    }

    var guidance: String {
        switch self {
        case .overview: "Keep the whole object visible and maintain image overlap."
        case .detail: "Move closer for detail. Move back if the object loses focus."
        case .extraAngles: "Capture higher, lower, and oblique views. Move slowly."
        case .review: "Review the actual captured photos before processing."
        case .process: "Create the model from the preserved original photos."
        }
    }
}

nonisolated struct ObjectCaptureGuideWorkflow: Equatable, Sendable {
    enum AdvanceAction: Equatable, Sendable {
        case beginNewScanPass
        case finishCapture
        case none
    }

    private(set) var stage: ObjectCaptureGuideStage = .overview
    private(set) var currentPassCompleted = false

    mutating func startCapturing() {
        stage = .overview
        currentPassCompleted = false
    }

    mutating func sessionReportedPassCompleted(_ completed: Bool) {
        guard stage == .overview || stage == .detail || stage == .extraAngles else { return }
        currentPassCompleted = completed
    }

    mutating func advance(reachedImageLimit: Bool = false) -> AdvanceAction {
        guard currentPassCompleted || reachedImageLimit else { return .none }
        if reachedImageLimit {
            stage = .review
            currentPassCompleted = false
            return .finishCapture
        }

        switch stage {
        case .overview:
            stage = .detail
            currentPassCompleted = false
            return .beginNewScanPass
        case .detail:
            stage = .extraAngles
            currentPassCompleted = false
            return .beginNewScanPass
        case .extraAngles:
            stage = .review
            currentPassCompleted = false
            return .finishCapture
        case .review, .process:
            return .none
        }
    }

    mutating func beginReview() {
        stage = .review
        currentPassCompleted = false
    }

    mutating func beginProcessing() {
        guard stage == .review else { return }
        stage = .process
    }
}

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

    func progressStatus(isSavingModel: Bool = false) -> ScanProgressStatus? {
        switch self {
        case .preparing:
            .preparingCamera
        case .readyForDetection:
            .readyToScan
        case .detecting:
            .detectingObject
        case .capturing, .finishing:
            .capturing
        case .reconstructing:
            isSavingModel ? .savingModel : .processingModel
        case .completed:
            .scanCompleted
        case .failed:
            .scanFailed
        default:
            nil
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
             (.reconstructing, .reviewing),
             (.reconstructing, .completed):
            return true
        default:
            return false
        }
    }
}

nonisolated struct ObjectDetectionLifecycle: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case idle
        case ready
        case invokingDetection
        case awaitingDetectionState
        case detecting
        case capturing
        case cancelled
    }

    private(set) var state: State = .idle
    private(set) var automaticRequestAttempted = false

    var isOperationPending: Bool {
        state == .invokingDetection || state == .awaitingDetectionState
    }

    mutating func prepareNewSession() {
        state = .idle
        automaticRequestAttempted = false
    }

    mutating func sessionBecameReady() -> Bool {
        switch state {
        case .awaitingDetectionState, .capturing, .cancelled:
            return false
        default:
            state = .ready
        }

        guard !automaticRequestAttempted else { return false }
        automaticRequestAttempted = true
        state = .invokingDetection
        return true
    }

    mutating func beginRetry(frameworkStateIsReady: Bool) -> Bool {
        guard frameworkStateIsReady, state == .ready else { return false }
        state = .invokingDetection
        return true
    }

    mutating func detectionRequestReturned(started: Bool) {
        guard state == .invokingDetection else { return }
        state = started ? .awaitingDetectionState : .ready
    }

    mutating func prepareForRedetection() {
        guard state == .detecting else { return }
        state = .idle
        automaticRequestAttempted = false
    }

    mutating func sessionBecameDetecting() {
        guard state != .cancelled, state != .capturing else { return }
        state = .detecting
    }

    mutating func beginFreeformCapture(frameworkStateIsReady: Bool) -> Bool {
        guard frameworkStateIsReady, state == .ready else { return false }
        state = .capturing
        return true
    }

    mutating func sessionBecameCapturing() {
        guard state != .cancelled else { return }
        state = .capturing
    }

    mutating func cancel() {
        state = .cancelled
    }
}
