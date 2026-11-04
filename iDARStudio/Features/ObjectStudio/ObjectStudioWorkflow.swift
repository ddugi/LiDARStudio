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

nonisolated enum ObjectCaptureMode: Equatable, Sendable {
    case objectCentric
    case freeform
}

nonisolated struct ObjectCaptureGuideWorkflow: Equatable, Sendable {
    enum AdvanceAction: Equatable, Sendable {
        case beginNewScanPass
        case advanceGuidanceOnly
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

    mutating func advance(mode: ObjectCaptureMode) -> AdvanceAction {
        guard stage == .overview || stage == .detail else { return .none }
        if mode == .objectCentric, !currentPassCompleted { return .none }
        let action: AdvanceAction = mode == .objectCentric ? .beginNewScanPass : .advanceGuidanceOnly
        switch stage {
        case .overview:
            stage = .detail
            currentPassCompleted = false
            return action
        case .detail:
            stage = .extraAngles
            currentPassCompleted = false
            return action
        case .extraAngles, .review, .process:
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

nonisolated struct ObjectCaptureControlLifecycle: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case inactive
        case capturing
        case pausePending
        case paused
        case resumePending
        case resumeToFinishPending
        case finishing
    }

    enum Action: Equatable, Sendable {
        case none
        case pause
        case resume
        case finish
    }

    private(set) var state: State = .inactive
    private(set) var isAutoCaptureEnabled = true

    var isPaused: Bool { state == .paused || state == .resumeToFinishPending }
    var isTransitionPending: Bool {
        state == .pausePending || state == .resumePending || state == .resumeToFinishPending
    }
    var isFinishPending: Bool { state == .resumeToFinishPending || state == .finishing }

    mutating func beginCapture(isPaused: Bool, isAutoCaptureEnabled: Bool) {
        state = isPaused ? .paused : .capturing
        self.isAutoCaptureEnabled = isAutoCaptureEnabled
    }

    mutating func requestPause(frameworkStateIsCapturing: Bool) -> Action {
        guard frameworkStateIsCapturing, state == .capturing else { return .none }
        state = .pausePending
        return .pause
    }

    mutating func requestResume(frameworkStateIsCapturing: Bool) -> Action {
        guard frameworkStateIsCapturing, state == .paused else { return .none }
        state = .resumePending
        return .resume
    }

    mutating func requestFinish(frameworkStateIsCapturing: Bool) -> Action {
        guard frameworkStateIsCapturing else { return .none }
        switch state {
        case .capturing:
            state = .finishing
            return .finish
        case .paused:
            state = .resumeToFinishPending
            return .resume
        default:
            return .none
        }
    }

    mutating func sessionReportedPaused(_ paused: Bool) -> Action {
        if paused {
            guard state == .pausePending || state == .capturing else { return .none }
            state = .paused
            return .none
        }

        switch state {
        case .resumePending, .paused:
            state = .capturing
            return .none
        case .pausePending:
            return .none
        case .resumeToFinishPending:
            state = .finishing
            return .finish
        default:
            return .none
        }
    }

    mutating func setAutoCaptureEnabled(_ enabled: Bool, frameworkStateIsCapturing: Bool) -> Bool {
        guard frameworkStateIsCapturing,
              state == .capturing || state == .paused else { return false }
        isAutoCaptureEnabled = enabled
        return true
    }

    mutating func sessionBeganFinishing() {
        state = .finishing
    }

    func canRequestManualPhoto(frameworkAllowsCapture: Bool, reachedMaximum: Bool) -> Bool {
        state == .capturing && frameworkAllowsCapture && !reachedMaximum
    }

    mutating func reset() {
        state = .inactive
    }
}

nonisolated enum PhotoTargetPreference {
    static let key = "objectCapturePreferredPhotoTarget"

    static func read(from defaults: UserDefaults) -> Int? {
        let value = defaults.integer(forKey: key)
        return value > 0 ? value : nil
    }

    static func write(_ value: Int?, to defaults: UserDefaults) {
        defaults.set(max(0, value ?? 0), forKey: key)
    }
}

nonisolated enum CaptureOverlayInteractionPolicy {
    static let framingGuideAllowsHitTesting = false
    static let controlsAllowHitTesting = true
}

nonisolated struct ObjectCapturePhotoProgress: Equatable, Sendable {
    let captured: Int
    let maximum: Int
    let preferredTarget: Int?

    var reachedMaximum: Bool { maximum > 0 && captured >= maximum }
    var isBelowPreferredTarget: Bool {
        guard let preferredTarget else { return false }
        return captured < preferredTarget
    }
    var shouldWarnBeforeFinish: Bool { captured == 0 || isBelowPreferredTarget }
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
