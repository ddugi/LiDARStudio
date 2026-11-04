import AVFoundation
import Combine
import Foundation
import OSLog
import RealityKit
import SwiftUI

@MainActor
final class ObjectCaptureCoordinator: ObservableObject {
    @Published private(set) var phase: ObjectStudioPhase = .idle
    @Published private(set) var session: ObjectCaptureSession?
    @Published private(set) var photoCount = 0
    @Published private(set) var maximumPhotoCount = 0
    @Published private(set) var canTakePhoto = false
    @Published private(set) var feedbackMessage: String?
    @Published private(set) var detectionRecoveryMessage: String?
    @Published private(set) var isDetectionOperationPending = false
    @Published private(set) var reviewPhotoURLs: [URL] = []
    @Published private(set) var captureDraft: ObjectCaptureDraft?
    @Published private(set) var reconstructionProgress = 0.0
    @Published private(set) var reconstructionStage = "Preparing photographs"
    @Published private(set) var reconstructionErrorMessage: String?
    @Published private(set) var estimatedRemainingTime: TimeInterval?
    @Published private(set) var invalidPhotoCount = 0
    @Published private(set) var modelURL: URL?
    @Published private(set) var completedScan: ScanMetadata?
    @Published private(set) var isSavingModel = false
    @Published private(set) var captureGuideStage: ObjectCaptureGuideStage = .overview
    @Published private(set) var currentPassCompleted = false
    @Published private(set) var captureMode: ObjectCaptureMode = .objectCentric
    @Published private(set) var isCapturePaused = false
    @Published private(set) var isCaptureControlPending = false
    @Published private(set) var isFinishOperationPending = false
    @Published private(set) var isAutoCaptureEnabled = true
    @Published private(set) var preferredPhotoTarget: Int?

    let objectCaptureSupported: Bool
    let photogrammetrySupported: Bool

    private let repository: LocalScanRepository
    private let screenAwakeManager: ScreenAwakeManager
    private let userDefaults: UserDefaults
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "LiDARStudio", category: "ObjectCapture")
    private var sessionTasks: [Task<Void, Never>] = []
    private var captureIdentifier: UUID?
    private var detectionLifecycle = ObjectDetectionLifecycle()
    private var detectionRequestSequence = 0
    private var captureGuideWorkflow = ObjectCaptureGuideWorkflow()
    private var captureControlLifecycle = ObjectCaptureControlLifecycle()
    private var cleanupPerformed = true
    private var photogrammetrySession: PhotogrammetrySession?
    private var reconstructionTask: Task<Void, Never>?
    private var captureAwakeSession: ScreenAwakeManager.Session?
    private var reconstructionAwakeSession: ScreenAwakeManager.Session?
    private var frameworkCanTakePhoto = false

    init(
        repository: LocalScanRepository = LocalScanRepository(),
        screenAwakeManager: ScreenAwakeManager? = nil,
        userDefaults: UserDefaults = .standard
    ) {
        self.repository = repository
        self.screenAwakeManager = screenAwakeManager ?? .shared
        self.userDefaults = userDefaults
        preferredPhotoTarget = PhotoTargetPreference.read(from: userDefaults)
        objectCaptureSupported = ObjectCaptureSession.isSupported
        photogrammetrySupported = PhotogrammetrySession.isSupported
    }

    var progressStatus: ScanProgressStatus? {
        phase.progressStatus(isSavingModel: isSavingModel)
    }

    var reachedInputImageLimit: Bool {
        photoProgress.reachedMaximum
    }

    var photoProgress: ObjectCapturePhotoProgress {
        ObjectCapturePhotoProgress(
            captured: photoCount,
            maximum: maximumPhotoCount,
            preferredTarget: preferredPhotoTarget
        )
    }

    var canAdvanceCaptureGuide: Bool {
        guard phase == .capturing,
              session?.state == .capturing,
              !isCapturePaused,
              !isCaptureControlPending,
              !isFinishOperationPending,
              captureGuideStage == .overview || captureGuideStage == .detail else { return false }
        return captureMode == .freeform || currentPassCompleted
    }

    var captureGuideActionTitle: String {
        return switch captureGuideStage {
        case .overview: "Start Detail Pass"
        case .detail: "Extra Angles"
        case .extraAngles: "Finish & Review"
        case .review, .process: "Continue"
        }
    }

    var canPauseCapture: Bool {
        phase == .capturing && session?.state == .capturing && !isCapturePaused && !isCaptureControlPending && !isFinishOperationPending
    }

    var canResumeCapture: Bool {
        phase == .capturing && session?.state == .capturing && isCapturePaused && !isCaptureControlPending && !isFinishOperationPending
    }

    var canFinishCapture: Bool {
        phase == .capturing && session?.state == .capturing && !isCaptureControlPending && !isFinishOperationPending
    }

    var canChangeAutoCapture: Bool {
        phase == .capturing && session?.state == .capturing && !isCaptureControlPending && !isFinishOperationPending
    }

    deinit {
        sessionTasks.forEach { $0.cancel() }
        reconstructionTask?.cancel()
    }

    func start() async {
        guard !phase.isCaptureSessionActive else {
            logger.notice("Ignored duplicate capture start request")
            return
        }

        transition(to: .preparing)
        guard objectCaptureSupported else {
            transition(to: .unsupported("Object Capture is not supported on this device."))
            return
        }
        guard AVCaptureDevice.default(for: .video) != nil else {
            transition(to: .unsupported("A camera is required for Object Studio."))
            return
        }

        var permission = CameraPermission.current
        if permission == .notDetermined {
            permission = await CameraPermission.request()
        }
        guard permission == .authorized else {
            transition(to: .permissionRequired)
            return
        }

        do {
            let identifier = UUID()
            let workspace = try repository.createObjectCaptureWorkspace(id: identifier)
            let newSession = ObjectCaptureSession()
            var configuration = ObjectCaptureSession.Configuration()
            configuration.checkpointDirectory = workspace.checkpointsDirectory
            configuration.isOverCaptureEnabled = false

            captureIdentifier = identifier
            let draft = ObjectCaptureDraft(id: identifier)
            try repository.saveObjectCaptureDraft(draft)
            captureDraft = draft
            cleanupPerformed = false
            detectionLifecycle.prepareNewSession()
            detectionRequestSequence = 0
            captureGuideWorkflow = ObjectCaptureGuideWorkflow()
            captureControlLifecycle.reset()
            captureMode = .objectCentric
            updateCaptureGuideState()
            updateCaptureControlState()
            updateDetectionOperationState()
            photoCount = newSession.numberOfShotsTaken
            maximumPhotoCount = newSession.maximumNumberOfInputImages
            if let preferredPhotoTarget {
                setPreferredPhotoTarget(preferredPhotoTarget)
            }
            isAutoCaptureEnabled = newSession.isAutoCaptureEnabled
            canTakePhoto = false
            feedbackMessage = nil
            detectionRecoveryMessage = nil
            reviewPhotoURLs = []
            session = newSession
            observe(newSession)
            captureAwakeSession = screenAwakeManager.begin(.object)
            logger.info("Starting object capture session for local workspace \(identifier.uuidString, privacy: .public)")
            newSession.start(imagesDirectory: workspace.imagesDirectory, configuration: configuration)
        } catch {
            logger.error("Unable to prepare capture workspace: \(error.localizedDescription, privacy: .public)")
            cleanupSession(cancelFramework: true, reason: .failed)
            transition(to: .failed(error.localizedDescription))
        }
    }

    func confirmBoundingBox() {
        guard phase == .detecting, let session else { return }
        logger.info("User confirmed the Object Capture bounding box")
        captureMode = .objectCentric
        captureGuideWorkflow.startCapturing()
        updateCaptureGuideState()
        captureControlLifecycle.beginCapture(
            isPaused: session.isPaused,
            isAutoCaptureEnabled: session.isAutoCaptureEnabled
        )
        updateCaptureControlState()
        session.startCapturing()
        transition(to: .capturing)
    }

    func retryDetection() {
        guard phase == .readyForDetection, let session else { return }
        guard detectionLifecycle.beginRetry(frameworkStateIsReady: session.state == .ready) else {
            logger.notice("Ignored retry because detection is pending or the framework session is no longer ready")
            return
        }
        updateDetectionOperationState()
        performDetectionRequest(on: session, reason: "user retry")
    }

    func startFreeformCapture() {
        guard phase == .readyForDetection,
              let session,
              detectionLifecycle.beginFreeformCapture(
                  frameworkStateIsReady: session.state == .ready
              ) else {
            logger.notice("Ignored freeform capture because detection is pending or the session is not ready")
            return
        }
        updateDetectionOperationState()
        detectionRecoveryMessage = nil
        logger.info("Starting supported freeform capture from Object Capture ready state")
        captureMode = .freeform
        captureGuideWorkflow.startCapturing()
        updateCaptureGuideState()
        captureControlLifecycle.beginCapture(
            isPaused: session.isPaused,
            isAutoCaptureEnabled: session.isAutoCaptureEnabled
        )
        updateCaptureControlState()
        session.startCapturing()
        transition(to: .capturing)
    }

    func resetBoundingBox() {
        guard phase == .detecting, let session else { return }
        if session.resetDetection() {
            detectionLifecycle.prepareForRedetection()
            updateDetectionOperationState()
            detectionRecoveryMessage = nil
            logger.info("Object detection reset; waiting for ready state")
        }
    }

    func takePhoto() {
        guard phase == .capturing,
              let session,
              captureControlLifecycle.canRequestManualPhoto(
                  frameworkAllowsCapture: session.canRequestImageCapture,
                  reachedMaximum: reachedInputImageLimit
              ) else { return }
        logger.info("Requesting one manual Object Capture image")
        session.requestImageCapture()
    }

    func advanceCaptureGuide() {
        guard phase == .capturing, let session, session.state == .capturing else { return }
        let action = captureGuideWorkflow.advance(mode: captureMode)
        updateCaptureGuideState()
        switch action {
        case .beginNewScanPass:
            logger.info("Beginning guided Object Capture pass \(self.captureGuideStage.title, privacy: .public)")
            session.beginNewScanPass()
        case .advanceGuidanceOnly:
            logger.info("Advanced freeform guidance to \(self.captureGuideStage.title, privacy: .public) without starting a framework scan pass")
        case .none:
            break
        }
    }

    func pauseCapture() {
        guard let session,
              captureControlLifecycle.requestPause(
                  frameworkStateIsCapturing: session.state == .capturing
              ) == .pause else { return }
        updateCaptureControlState()
        logger.info("Requesting Object Capture pause")
        session.pause()
    }

    func resumeCapture() {
        guard let session,
              captureControlLifecycle.requestResume(
                  frameworkStateIsCapturing: session.state == .capturing
              ) == .resume else { return }
        updateCaptureControlState()
        logger.info("Requesting Object Capture resume")
        session.resume()
    }

    func requestFinishCapture() {
        guard let session else { return }
        let action = captureControlLifecycle.requestFinish(
            frameworkStateIsCapturing: session.state == .capturing
        )
        updateCaptureControlState()
        performCaptureControlAction(action, on: session)
    }

    func setAutoCaptureEnabled(_ enabled: Bool) {
        guard let session,
              captureControlLifecycle.setAutoCaptureEnabled(
                  enabled,
                  frameworkStateIsCapturing: session.state == .capturing
              ) else { return }
        session.isAutoCaptureEnabled = enabled
        isAutoCaptureEnabled = session.isAutoCaptureEnabled
        logger.info("Automatic Object Capture changed to \(self.isAutoCaptureEnabled, privacy: .public)")
    }

    func setPreferredPhotoTarget(_ target: Int?) {
        let normalized: Int?
        if let target {
            normalized = min(max(1, target), max(1, maximumPhotoCount))
        } else {
            normalized = nil
        }
        preferredPhotoTarget = normalized
        PhotoTargetPreference.write(normalized, to: userDefaults)
    }

    func cancel() {
        guard phase.isCaptureSessionActive else { return }
        logger.info("Cancelling active object capture session")
        detectionLifecycle.cancel()
        updateDetectionOperationState()
        cleanupSession(cancelFramework: true, reason: .cancelled)
        updateDraft(status: .cancelled)
        transition(to: .cancelled)
    }

    func handleBackgrounding() {
        if phase.isCaptureSessionActive {
            logger.notice("Application backgrounded during capture; cancelling camera resources safely")
            cancel()
        } else if phase == .reconstructing {
            logger.notice("Application backgrounded during reconstruction; cancelling processing safely")
            cancelReconstruction()
        }
    }

    func handleViewDisappearance() {
        if phase.isCaptureSessionActive {
            cancel()
        } else if phase == .reconstructing {
            cancelReconstruction()
        }
    }

    func reset() {
        cleanupSession(cancelFramework: true, reason: .stopped)
        cleanupReconstruction(cancelFramework: true, reason: .stopped)
        captureGuideWorkflow = ObjectCaptureGuideWorkflow()
        captureControlLifecycle.reset()
        updateCaptureGuideState()
        updateCaptureControlState()
        reconstructionErrorMessage = nil
        transition(to: .idle)
    }

    func startReconstruction(name: String) {
        guard phase == .reviewing, let captureIdentifier else { return }
        guard photogrammetrySupported else {
            transition(to: .failed("On-device photogrammetry is not supported on this device."))
            return
        }
        guard !reviewPhotoURLs.isEmpty else {
            transition(to: .failed("No captured photographs are available for reconstruction."))
            return
        }

        do {
            captureGuideWorkflow.beginProcessing()
            updateCaptureGuideState()
            reconstructionErrorMessage = nil
            let workspace = repository.objectCaptureWorkspace(id: captureIdentifier)
            let outputURL = try repository.modelFileURL(id: captureIdentifier)
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try FileManager.default.removeItem(at: outputURL)
            }
            var configuration = PhotogrammetrySession.Configuration()
            configuration.sampleOrdering = .sequential
            configuration.featureSensitivity = .high
            configuration.isObjectMaskingEnabled = true
            configuration.checkpointDirectory = try repository.reconstructionCheckpointDirectory(id: captureIdentifier)

            let processingSession = try PhotogrammetrySession(
                input: workspace.imagesDirectory,
                configuration: configuration
            )
            let request = PhotogrammetrySession.Request.modelFile(url: outputURL, detail: .reduced)
            photogrammetrySession = processingSession
            reconstructionProgress = 0
            reconstructionStage = "Preparing photographs"
            isSavingModel = false
            estimatedRemainingTime = nil
            invalidPhotoCount = 0
            modelURL = nil
            completedScan = nil
            updateDraft(status: .reconstructing)
            transition(to: .reconstructing)
            logger.info("Starting supported on-device photogrammetry for \(self.reviewPhotoURLs.count, privacy: .public) images")
            reconstructionAwakeSession = screenAwakeManager.begin(.object)
            try processingSession.process(requests: [request])
            reconstructionTask = Task { [weak self, weak processingSession] in
                guard let self, let processingSession else { return }
                do {
                    for try await output in processingSession.outputs {
                        guard !Task.isCancelled else { return }
                        await self.handlePhotogrammetryOutput(output, expectedURL: outputURL, scanName: name)
                    }
                } catch {
                    guard !Task.isCancelled else { return }
                    self.reconstructionFailed(error)
                }
            }
        } catch {
            reconstructionFailed(error)
        }
    }

    func cancelReconstruction() {
        guard phase == .reconstructing else { return }
        cleanupReconstruction(cancelFramework: true, reason: .cancelled)
        captureGuideWorkflow.beginReview()
        updateCaptureGuideState()
        updateDraft(status: .readyForReconstruction)
        reconstructionErrorMessage = "3D model creation was cancelled. Your original photos remain available."
        transition(to: .reviewing)
    }

    private func observe(_ observedSession: ObjectCaptureSession) {
        sessionTasks.forEach { $0.cancel() }
        sessionTasks = [
            Task { [weak self, weak observedSession] in
                guard let observedSession else { return }
                for await state in observedSession.stateUpdates {
                    guard !Task.isCancelled else { return }
                    self?.handle(state, from: observedSession)
                }
            },
            Task { [weak self, weak observedSession] in
                guard let observedSession else { return }
                for await count in observedSession.numberOfShotsTakenUpdates {
                    guard !Task.isCancelled else { return }
                    self?.handlePhotoCount(count, from: observedSession)
                }
            },
            Task { [weak self, weak observedSession] in
                guard let observedSession else { return }
                for await canCapture in observedSession.canRequestImageCaptureUpdates {
                    guard !Task.isCancelled else { return }
                    self?.handleManualCaptureAvailability(canCapture, from: observedSession)
                }
            },
            Task { [weak self, weak observedSession] in
                guard let observedSession else { return }
                for await paused in observedSession.isPausedUpdates {
                    guard !Task.isCancelled else { return }
                    self?.handlePausedState(paused, from: observedSession)
                }
            },
            Task { [weak self, weak observedSession] in
                guard let observedSession else { return }
                for await feedback in observedSession.feedbackUpdates {
                    guard !Task.isCancelled else { return }
                    self?.feedbackMessage = Self.message(for: feedback)
                }
            },
            Task { [weak self, weak observedSession] in
                guard let observedSession else { return }
                for await tracking in observedSession.cameraTrackingUpdates {
                    guard !Task.isCancelled else { return }
                    self?.logCameraTracking(tracking, from: observedSession)
                }
            },
            Task { [weak self, weak observedSession] in
                guard let observedSession else { return }
                for await completed in observedSession.userCompletedScanPassUpdates {
                    guard !Task.isCancelled else { return }
                    self?.handleScanPassCompletion(completed, from: observedSession)
                }
            }
        ]
    }

    private func handle(_ state: ObjectCaptureSession.CaptureState, from observedSession: ObjectCaptureSession) {
        guard session === observedSession else { return }
        logger.info("Object Capture state changed to \(String(describing: state), privacy: .public)")
        switch state {
        case .initializing:
            break
        case .ready:
            transition(to: .readyForDetection)
            guard detectionLifecycle.sessionBecameReady() else {
                updateDetectionOperationState()
                return
            }
            updateDetectionOperationState()
            performDetectionRequest(on: observedSession, reason: "automatic initial request")
        case .detecting:
            detectionLifecycle.sessionBecameDetecting()
            updateDetectionOperationState()
            detectionRecoveryMessage = nil
            transition(to: .detecting)
        case .capturing:
            guard phase != .finishing else {
                logger.notice("Ignored late capturing callback after finish began")
                return
            }
            if captureControlLifecycle.state == .inactive {
                captureGuideWorkflow.startCapturing()
                updateCaptureGuideState()
                captureControlLifecycle.beginCapture(
                    isPaused: observedSession.isPaused,
                    isAutoCaptureEnabled: observedSession.isAutoCaptureEnabled
                )
                updateCaptureControlState()
            }
            detectionLifecycle.sessionBecameCapturing()
            updateDetectionOperationState()
            detectionRecoveryMessage = nil
            transition(to: .capturing)
        case .finishing:
            captureControlLifecycle.sessionBeganFinishing()
            updateCaptureControlState()
            transition(to: .finishing)
        case .completed:
            cleanupSession(cancelFramework: false, reason: .completed)
            prepareReview()
            transition(to: .reviewing)
        case .failed(let error):
            let frameworkError = error as NSError
            logger.error("Object capture failed: domain=\(frameworkError.domain, privacy: .public) code=\(frameworkError.code, privacy: .public) description=\(error.localizedDescription, privacy: .public)")
            photoCount = observedSession.numberOfShotsTaken
            updateDraft(status: .failed)
            cleanupSession(cancelFramework: false, reason: .failed)
            transition(to: .failed(error.localizedDescription))
        @unknown default:
            logger.error("Object Capture reported an unknown state")
        }
    }

    private func performDetectionRequest(on observedSession: ObjectCaptureSession, reason: String) {
        guard session === observedSession,
              observedSession.state == .ready else {
            detectionLifecycle.detectionRequestReturned(started: false)
            updateDetectionOperationState()
            logger.notice("Aborted object detection invocation because the active session was no longer ready")
            return
        }

        detectionRequestSequence += 1
        let requestID = detectionRequestSequence
        let frameworkState = String(describing: observedSession.state)
        let tracking = String(describing: observedSession.cameraTracking)
        let authorization = String(describing: AVCaptureDevice.authorizationStatus(for: .video))
        logger.info("Invoking object detection requestID=\(requestID, privacy: .public) reason=\(reason, privacy: .public) frameworkState=\(frameworkState, privacy: .public) tracking=\(tracking, privacy: .public) cameraAuthorization=\(authorization, privacy: .public)")

        let started = observedSession.startDetecting()
        detectionLifecycle.detectionRequestReturned(started: started)
        updateDetectionOperationState()
        logger.info("Object detection requestID=\(requestID, privacy: .public) returned \(started, privacy: .public); frameworkState=\(String(describing: observedSession.state), privacy: .public)")
        guard started else {
            detectionRecoveryMessage = "No surface found. Reposition the reticle, then Retry or use Free Scan."
            return
        }
        detectionRecoveryMessage = nil
    }

    private func updateDetectionOperationState() {
        isDetectionOperationPending = detectionLifecycle.isOperationPending
    }

    private func handleScanPassCompletion(_ completed: Bool, from observedSession: ObjectCaptureSession) {
        guard session === observedSession, phase == .capturing, captureMode == .objectCentric else { return }
        captureGuideWorkflow.sessionReportedPassCompleted(completed)
        updateCaptureGuideState()
        if completed {
            logger.info("Object Capture reported completed guided pass \(self.captureGuideStage.title, privacy: .public)")
        }
    }

    private func updateCaptureGuideState() {
        captureGuideStage = captureGuideWorkflow.stage
        currentPassCompleted = captureGuideWorkflow.currentPassCompleted
    }

    private func handlePhotoCount(_ count: Int, from observedSession: ObjectCaptureSession) {
        guard session === observedSession else { return }
        photoCount = count
        refreshManualCaptureAvailability(for: observedSession)
    }

    private func handleManualCaptureAvailability(
        _ canCapture: Bool,
        from observedSession: ObjectCaptureSession
    ) {
        guard session === observedSession else { return }
        frameworkCanTakePhoto = canCapture
        refreshManualCaptureAvailability(for: observedSession)
    }

    private func handlePausedState(_ paused: Bool, from observedSession: ObjectCaptureSession) {
        guard session === observedSession, observedSession.state == .capturing else { return }
        guard paused == observedSession.isPaused else {
            logger.notice("Ignored stale Object Capture pause callback")
            return
        }
        let action = captureControlLifecycle.sessionReportedPaused(paused)
        updateCaptureControlState()
        refreshManualCaptureAvailability(for: observedSession)
        logger.info("Object Capture pause state confirmed as \(paused, privacy: .public)")
        performCaptureControlAction(action, on: observedSession)
    }

    private func performCaptureControlAction(
        _ action: ObjectCaptureControlLifecycle.Action,
        on observedSession: ObjectCaptureSession
    ) {
        guard session === observedSession else { return }
        switch action {
        case .resume:
            logger.info("Resuming paused capture before requested finish")
            observedSession.resume()
        case .finish:
            guard observedSession.state == .capturing, !observedSession.isPaused else {
                logger.notice("Deferred finish because the active session is not in an unpaused capturing state")
                return
            }
            transition(to: .finishing)
            logger.info("Finishing object capture with \(self.photoCount, privacy: .public) photos")
            observedSession.finish()
        case .pause, .none:
            break
        }
    }

    private func updateCaptureControlState() {
        isCapturePaused = captureControlLifecycle.isPaused
        isCaptureControlPending = captureControlLifecycle.isTransitionPending
        isFinishOperationPending = captureControlLifecycle.isFinishPending
        isAutoCaptureEnabled = captureControlLifecycle.isAutoCaptureEnabled
        if let session {
            refreshManualCaptureAvailability(for: session)
        } else {
            canTakePhoto = false
        }
    }

    private func refreshManualCaptureAvailability(for observedSession: ObjectCaptureSession) {
        guard session === observedSession else { return }
        canTakePhoto = captureControlLifecycle.canRequestManualPhoto(
            frameworkAllowsCapture: frameworkCanTakePhoto && observedSession.canRequestImageCapture,
            reachedMaximum: reachedInputImageLimit
        )
    }

    private func logCameraTracking(
        _ tracking: ObjectCaptureSession.Tracking,
        from observedSession: ObjectCaptureSession
    ) {
        guard session === observedSession else { return }
        logger.info("Object Capture camera tracking changed to \(String(describing: tracking), privacy: .public)")
    }

    private func cleanupSession(cancelFramework: Bool, reason: ScreenAwakeManager.EndReason) {
        guard !cleanupPerformed else { return }
        cleanupPerformed = true
        detectionLifecycle.cancel()
        captureControlLifecycle.reset()
        updateDetectionOperationState()
        updateCaptureControlState()
        sessionTasks.forEach { $0.cancel() }
        sessionTasks.removeAll()
        if cancelFramework {
            session?.cancel()
        }
        session = nil
        if let captureAwakeSession {
            screenAwakeManager.end(captureAwakeSession, reason: reason)
            self.captureAwakeSession = nil
        }
        canTakePhoto = false
        frameworkCanTakePhoto = false
        feedbackMessage = nil
        detectionRecoveryMessage = nil
        logger.debug("Object capture resources released")
    }

    private func transition(to next: ObjectStudioPhase) {
        guard ObjectStudioTransitionPolicy.permits(from: phase, to: next) || phase == next else {
            logger.error("Rejected invalid Object Studio state transition")
            return
        }
        phase = next
    }

    private func handlePhotogrammetryOutput(
        _ output: PhotogrammetrySession.Output,
        expectedURL: URL,
        scanName: String
    ) async {
        switch output {
        case .inputComplete:
            reconstructionStage = "Aligning photographs"
        case .requestProgress(_, let fractionComplete):
            reconstructionProgress = min(max(fractionComplete, 0), 1)
        case .requestProgressInfo(_, let info):
            estimatedRemainingTime = info.estimatedRemainingTime
            if let processingStage = info.processingStage {
                reconstructionStage = Self.title(for: processingStage)
            }
        case .invalidSample:
            invalidPhotoCount += 1
        case .skippedSample:
            invalidPhotoCount += 1
        case .automaticDownsampling:
            logger.notice("Photogrammetry automatically downsampled input images")
        case .stitchingIncomplete:
            logger.notice("Photogrammetry reported incomplete stitching")
        case .requestError(_, let error):
            reconstructionFailed(error)
        case .requestComplete(_, let result):
            guard case .modelFile(let producedURL) = result else {
                reconstructionFailed(ObjectStudioError.unexpectedReconstructionResult)
                return
            }
            do {
                try await validateModel(at: producedURL, expectedURL: expectedURL)
                modelURL = producedURL
            } catch {
                reconstructionFailed(error)
            }
        case .processingComplete:
            isSavingModel = true
            guard let modelURL else {
                reconstructionFailed(ObjectStudioError.missingModelFile)
                return
            }
            reconstructionProgress = 1
            updateDraft(status: .completed)
            do {
                let values = try modelURL.resourceValues(forKeys: [.fileSizeKey])
                let cleanedName = scanName.trimmingCharacters(in: .whitespacesAndNewlines)
                completedScan = ScanMetadata(
                    id: captureDraft?.id ?? UUID(),
                    name: cleanedName.isEmpty ? "Object Scan" : cleanedName,
                    kind: .object,
                    createdAt: captureDraft?.createdAt ?? Date(),
                    updatedAt: Date(),
                    relativeModelPath: modelURL.lastPathComponent,
                    relativeCapturePath: captureDraft?.id.uuidString,
                    fileSizeBytes: Int64(values.fileSize ?? 0),
                    photoCount: photoCount
                )
            } catch {
                reconstructionFailed(error)
                return
            }
            cleanupReconstruction(cancelFramework: false, reason: .completed)
            transition(to: .completed)
        case .processingCancelled:
            cleanupReconstruction(cancelFramework: false, reason: .cancelled)
        @unknown default:
            logger.error("Photogrammetry reported an unknown output")
        }
    }

    private func validateModel(at producedURL: URL, expectedURL: URL) async throws {
        guard producedURL.standardizedFileURL == expectedURL.standardizedFileURL,
              producedURL.pathExtension.lowercased() == "usdz",
              FileManager.default.fileExists(atPath: producedURL.path) else {
            throw ObjectStudioError.missingModelFile
        }
        let values = try producedURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, (values.fileSize ?? 0) > 0 else {
            throw ObjectStudioError.invalidModelFile
        }
        _ = try await Entity(contentsOf: producedURL)
        logger.info("Validated reconstructed USDZ with RealityKit")
    }

    private func reconstructionFailed(_ error: Error) {
        logger.error("Photogrammetry failed: \(error.localizedDescription, privacy: .public)")
        updateDraft(status: .failed)
        cleanupReconstruction(cancelFramework: true, reason: .failed)
        captureGuideWorkflow.beginReview()
        updateCaptureGuideState()
        reconstructionErrorMessage = "\(error.localizedDescription) Your original photos remain available; you can try again."
        transition(to: .reviewing)
    }

    private func cleanupReconstruction(cancelFramework: Bool, reason: ScreenAwakeManager.EndReason) {
        reconstructionTask?.cancel()
        reconstructionTask = nil
        if cancelFramework { photogrammetrySession?.cancel() }
        photogrammetrySession = nil
        isSavingModel = false
        if let reconstructionAwakeSession {
            screenAwakeManager.end(reconstructionAwakeSession, reason: reason)
            self.reconstructionAwakeSession = nil
        }
    }

    private static func title(for stage: PhotogrammetrySession.Output.ProcessingStage) -> String {
        switch stage {
        case .preProcessing: "Preparing photographs"
        case .imageAlignment: "Aligning photographs"
        case .pointCloudGeneration: "Building point cloud"
        case .meshGeneration: "Generating mesh"
        case .textureMapping: "Mapping original photo texture"
        case .optimization: "Optimizing USDZ"
        @unknown default: "Processing model"
        }
    }

    private func prepareReview() {
        guard let captureIdentifier else { return }
        do {
            captureGuideWorkflow.beginReview()
            updateCaptureGuideState()
            reviewPhotoURLs = try repository.capturedImageURLs(id: captureIdentifier)
            photoCount = reviewPhotoURLs.count
            reconstructionErrorMessage = nil
            updateDraft(status: .readyForReconstruction)
            logger.info("Prepared local review for \(self.reviewPhotoURLs.count, privacy: .public) captured images")
        } catch {
            logger.error("Unable to load captured photographs for review: \(error.localizedDescription, privacy: .public)")
            transition(to: .failed(error.localizedDescription))
        }
    }

    private func updateDraft(status: ObjectCaptureDraft.Status) {
        guard var draft = captureDraft else { return }
        draft.updatedAt = Date()
        draft.photoCount = photoCount
        draft.status = status
        captureDraft = draft
        do {
            try repository.saveObjectCaptureDraft(draft)
        } catch {
            logger.error("Unable to update capture manifest: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func message(for feedback: Set<ObjectCaptureSession.Feedback>) -> String? {
        if feedback.contains(.environmentTooDark) { return "The scene is too dark. Add steady, diffuse light." }
        if feedback.contains(.environmentLowLight) { return "More even light will improve the photographs." }
        if feedback.contains(.objectTooClose) { return "Move slightly farther from the object." }
        if feedback.contains(.objectTooFar) { return "Move closer to keep the object detailed." }
        if feedback.contains(.movingTooFast) { return "Move more slowly so each photo stays sharp." }
        if feedback.contains(.outOfFieldOfView) { return "Keep the complete object inside the frame." }
        if feedback.contains(.objectNotDetected) { return "Keep the object still and clearly separated from its background." }
        if feedback.contains(.overCapturing) { return "This angle has enough photos. Continue around the object." }
        if feedback.contains(.objectNotFlippable) { return "Continue without flipping this object." }
        return nil
    }
}

nonisolated enum ObjectStudioError: LocalizedError {
    case unexpectedReconstructionResult
    case missingModelFile
    case invalidModelFile

    var errorDescription: String? {
        switch self {
        case .unexpectedReconstructionResult: "Photogrammetry returned an unexpected result."
        case .missingModelFile: "Photogrammetry did not produce the expected USDZ file."
        case .invalidModelFile: "The reconstructed USDZ file is empty or invalid."
        }
    }
}
