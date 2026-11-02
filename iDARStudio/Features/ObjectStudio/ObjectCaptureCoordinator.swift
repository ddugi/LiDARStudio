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
    @Published private(set) var reviewPhotoURLs: [URL] = []
    @Published private(set) var captureDraft: ObjectCaptureDraft?
    @Published private(set) var reconstructionProgress = 0.0
    @Published private(set) var reconstructionStage = "Preparing photographs"
    @Published private(set) var estimatedRemainingTime: TimeInterval?
    @Published private(set) var invalidPhotoCount = 0
    @Published private(set) var modelURL: URL?
    @Published private(set) var completedScan: ScanMetadata?

    let objectCaptureSupported: Bool
    let photogrammetrySupported: Bool

    private let repository: LocalScanRepository
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "LiDARStudio", category: "ObjectCapture")
    private var sessionTasks: [Task<Void, Never>] = []
    private var captureIdentifier: UUID?
    private var didRequestDetection = false
    private var cleanupPerformed = true
    private var photogrammetrySession: PhotogrammetrySession?
    private var reconstructionTask: Task<Void, Never>?

    init(repository: LocalScanRepository = LocalScanRepository()) {
        self.repository = repository
        objectCaptureSupported = ObjectCaptureSession.isSupported
        photogrammetrySupported = PhotogrammetrySession.isSupported
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
            configuration.isOverCaptureEnabled = true

            captureIdentifier = identifier
            let draft = ObjectCaptureDraft(id: identifier)
            try repository.saveObjectCaptureDraft(draft)
            captureDraft = draft
            cleanupPerformed = false
            didRequestDetection = false
            photoCount = 0
            maximumPhotoCount = newSession.maximumNumberOfInputImages
            canTakePhoto = false
            feedbackMessage = nil
            reviewPhotoURLs = []
            session = newSession
            observe(newSession)
            logger.info("Starting object capture session for local workspace \(identifier.uuidString, privacy: .public)")
            newSession.start(imagesDirectory: workspace.imagesDirectory, configuration: configuration)
        } catch {
            logger.error("Unable to prepare capture workspace: \(error.localizedDescription, privacy: .public)")
            cleanupSession(cancelFramework: true)
            transition(to: .failed(error.localizedDescription))
        }
    }

    func confirmBoundingBox() {
        guard phase == .detecting, let session else { return }
        logger.info("User confirmed the Object Capture bounding box")
        session.startCapturing()
        transition(to: .capturing)
    }

    func resetBoundingBox() {
        guard phase == .detecting, let session else { return }
        if session.resetDetection() {
            didRequestDetection = session.startDetecting()
            logger.info("Object detection reset")
        }
    }

    func takePhoto() {
        guard phase == .capturing, canTakePhoto, let session else { return }
        session.requestImageCapture()
    }

    func finishCapture() {
        guard phase == .capturing, let session else { return }
        transition(to: .finishing)
        logger.info("Finishing object capture with \(self.photoCount, privacy: .public) photos")
        session.finish()
    }

    func cancel() {
        guard phase.isCaptureSessionActive else { return }
        logger.info("Cancelling active object capture session")
        cleanupSession(cancelFramework: true)
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
        cleanupSession(cancelFramework: true)
        cleanupReconstruction(cancelFramework: true)
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
            estimatedRemainingTime = nil
            invalidPhotoCount = 0
            modelURL = nil
            completedScan = nil
            updateDraft(status: .reconstructing)
            transition(to: .reconstructing)
            logger.info("Starting supported on-device photogrammetry for \(self.reviewPhotoURLs.count, privacy: .public) images")
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
        cleanupReconstruction(cancelFramework: true)
        updateDraft(status: .readyForReconstruction)
        transition(to: .cancelled)
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
                    self?.photoCount = count
                }
            },
            Task { [weak self, weak observedSession] in
                guard let observedSession else { return }
                for await canCapture in observedSession.canRequestImageCaptureUpdates {
                    guard !Task.isCancelled else { return }
                    self?.canTakePhoto = canCapture
                }
            },
            Task { [weak self, weak observedSession] in
                guard let observedSession else { return }
                for await feedback in observedSession.feedbackUpdates {
                    guard !Task.isCancelled else { return }
                    self?.feedbackMessage = Self.message(for: feedback)
                }
            }
        ]
    }

    private func handle(_ state: ObjectCaptureSession.CaptureState, from observedSession: ObjectCaptureSession) {
        guard session === observedSession else { return }
        switch state {
        case .initializing:
            break
        case .ready:
            guard !didRequestDetection else { return }
            didRequestDetection = observedSession.startDetecting()
            if !didRequestDetection {
                cleanupSession(cancelFramework: true)
                transition(to: .failed("Object detection could not be started."))
            }
        case .detecting:
            transition(to: .detecting)
        case .capturing:
            transition(to: .capturing)
        case .finishing:
            transition(to: .finishing)
        case .completed:
            cleanupSession(cancelFramework: false)
            prepareReview()
            transition(to: .reviewing)
        case .failed(let error):
            logger.error("Object capture failed: \(error.localizedDescription, privacy: .public)")
            cleanupSession(cancelFramework: false)
            transition(to: .failed(error.localizedDescription))
        @unknown default:
            logger.error("Object Capture reported an unknown state")
        }
    }

    private func cleanupSession(cancelFramework: Bool) {
        guard !cleanupPerformed else { return }
        cleanupPerformed = true
        sessionTasks.forEach { $0.cancel() }
        sessionTasks.removeAll()
        if cancelFramework {
            session?.cancel()
        }
        session = nil
        canTakePhoto = false
        feedbackMessage = nil
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
            cleanupReconstruction(cancelFramework: false)
            transition(to: .completed)
        case .processingCancelled:
            cleanupReconstruction(cancelFramework: false)
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
        cleanupReconstruction(cancelFramework: true)
        transition(to: .failed(error.localizedDescription))
    }

    private func cleanupReconstruction(cancelFramework: Bool) {
        reconstructionTask?.cancel()
        reconstructionTask = nil
        if cancelFramework { photogrammetrySession?.cancel() }
        photogrammetrySession = nil
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
            reviewPhotoURLs = try repository.capturedImageURLs(id: captureIdentifier)
            photoCount = reviewPhotoURLs.count
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
