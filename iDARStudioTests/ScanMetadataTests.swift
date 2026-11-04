import Foundation
import Testing
@testable import iDARStudio

struct ScanMetadataTests {
    @Test @MainActor func screenAwakeLifecycleRestoresIdleTimerForEveryTerminalReason() {
        let reasons: [ScreenAwakeManager.EndReason] = [.stopped, .cancelled, .completed, .failed]

        for reason in reasons {
            var appliedValues: [Bool] = []
            let manager = ScreenAwakeManager { appliedValues.append($0) }
            let session = manager.begin(.object)

            #expect(manager.isKeepingScreenAwake)
            #expect(appliedValues == [true])

            manager.end(session, reason: reason)

            #expect(!manager.isKeepingScreenAwake)
            #expect(appliedValues == [true, false])
        }
    }

    @Test @MainActor func overlappingScanningSessionsCannotResetIdleTimerEarly() {
        var appliedValues: [Bool] = []
        let manager = ScreenAwakeManager { appliedValues.append($0) }
        let objectSession = manager.begin(.object)
        let roomSession = manager.begin(.room)
        let environmentSession = manager.begin(.environment)

        manager.end(objectSession, reason: .completed)
        manager.end(roomSession, reason: .cancelled)

        #expect(manager.isKeepingScreenAwake)
        #expect(manager.activeSessionCount == 1)
        #expect(appliedValues == [true])

        manager.end(environmentSession, reason: .stopped)

        #expect(!manager.isKeepingScreenAwake)
        #expect(appliedValues == [true, false])
    }

    @Test @MainActor func backgroundingRestoresIdleTimerAndLateCleanupIsIdempotent() {
        var appliedValues: [Bool] = []
        let manager = ScreenAwakeManager { appliedValues.append($0) }
        let session = manager.begin(.environment)

        manager.applicationDidEnterBackground()
        manager.end(session, reason: .backgrounded)

        #expect(!manager.isKeepingScreenAwake)
        #expect(manager.activeSessionCount == 0)
        #expect(appliedValues == [true, false])
    }

    @Test func objectProgressLabelsReflectRealWorkflowPhases() {
        #expect(ObjectStudioPhase.preparing.progressStatus() == .preparingCamera)
        #expect(ObjectStudioPhase.readyForDetection.progressStatus() == .readyToScan)
        #expect(ObjectStudioPhase.detecting.progressStatus() == .detectingObject)
        #expect(ObjectStudioPhase.capturing.progressStatus() == .capturing)
        #expect(ObjectStudioPhase.reconstructing.progressStatus() == .processingModel)
        #expect(ObjectStudioPhase.reconstructing.progressStatus(isSavingModel: true) == .savingModel)
        #expect(ObjectStudioPhase.completed.progressStatus() == .scanCompleted)
        #expect(ObjectStudioPhase.failed("framework").progressStatus() == .scanFailed)
        #expect(ObjectStudioPhase.reviewing.progressStatus() == nil)
    }

    @Test func multiDistanceGuideRequiresRealPassCompletionBeforeAdvancing() {
        var workflow = ObjectCaptureGuideWorkflow()
        workflow.startCapturing()

        #expect(workflow.stage == .overview)
        #expect(workflow.advance(mode: .objectCentric) == .none)

        workflow.sessionReportedPassCompleted(true)
        #expect(workflow.advance(mode: .objectCentric) == .beginNewScanPass)
        #expect(workflow.stage == .detail)
        #expect(!workflow.currentPassCompleted)

        workflow.sessionReportedPassCompleted(true)
        #expect(workflow.advance(mode: .objectCentric) == .beginNewScanPass)
        #expect(workflow.stage == .extraAngles)

        workflow.sessionReportedPassCompleted(true)
        #expect(workflow.advance(mode: .objectCentric) == .none)
        #expect(workflow.stage == .extraAngles)

        workflow.beginReview()
        workflow.beginProcessing()
        #expect(workflow.stage == .process)
    }

    @Test func freeformGuidanceNeverStartsAFrameworkScanPassOrFinishesAutomatically() {
        var workflow = ObjectCaptureGuideWorkflow()
        workflow.startCapturing()

        #expect(workflow.advance(mode: .freeform) == .advanceGuidanceOnly)
        #expect(workflow.stage == .detail)
        #expect(workflow.advance(mode: .freeform) == .advanceGuidanceOnly)
        #expect(workflow.stage == .extraAngles)
        #expect(workflow.advance(mode: .freeform) == .none)
    }

    @Test func captureControlPauseResumeWaitsForFrameworkConfirmation() {
        var lifecycle = ObjectCaptureControlLifecycle()
        lifecycle.beginCapture(isPaused: false, isAutoCaptureEnabled: true)

        #expect(lifecycle.requestPause(frameworkStateIsCapturing: true) == .pause)
        #expect(lifecycle.state == .pausePending)
        #expect(!lifecycle.isPaused)
        #expect(lifecycle.requestPause(frameworkStateIsCapturing: true) == .none)
        #expect(lifecycle.sessionReportedPaused(false) == .none)
        #expect(lifecycle.state == .pausePending)

        #expect(lifecycle.sessionReportedPaused(true) == .none)
        #expect(lifecycle.state == .paused)
        #expect(lifecycle.isPaused)
        #expect(lifecycle.requestResume(frameworkStateIsCapturing: true) == .resume)
        #expect(lifecycle.state == .resumePending)
        #expect(lifecycle.sessionReportedPaused(false) == .none)
        #expect(lifecycle.state == .capturing)
    }

    @Test func earlyFinishIsExplicitAndDuplicateFinishIsRejected() {
        var lifecycle = ObjectCaptureControlLifecycle()
        lifecycle.beginCapture(isPaused: false, isAutoCaptureEnabled: true)

        #expect(lifecycle.requestFinish(frameworkStateIsCapturing: true) == .finish)
        #expect(lifecycle.state == .finishing)
        #expect(lifecycle.requestFinish(frameworkStateIsCapturing: true) == .none)
    }

    @Test func finishingWhilePausedResumesBeforeFinishing() {
        var lifecycle = ObjectCaptureControlLifecycle()
        lifecycle.beginCapture(isPaused: true, isAutoCaptureEnabled: false)

        #expect(lifecycle.requestFinish(frameworkStateIsCapturing: true) == .resume)
        #expect(lifecycle.state == .resumeToFinishPending)
        #expect(lifecycle.sessionReportedPaused(false) == .finish)
        #expect(lifecycle.state == .finishing)
    }

    @Test func automaticAndManualCaptureRespectActualControlState() {
        var lifecycle = ObjectCaptureControlLifecycle()
        lifecycle.beginCapture(isPaused: false, isAutoCaptureEnabled: true)

        let automaticModeChanged = lifecycle.setAutoCaptureEnabled(
            false,
            frameworkStateIsCapturing: true
        )
        #expect(automaticModeChanged)
        #expect(!lifecycle.isAutoCaptureEnabled)
        #expect(lifecycle.canRequestManualPhoto(frameworkAllowsCapture: true, reachedMaximum: false))
        #expect(!lifecycle.canRequestManualPhoto(frameworkAllowsCapture: false, reachedMaximum: false))
        #expect(!lifecycle.canRequestManualPhoto(frameworkAllowsCapture: true, reachedMaximum: true))

        #expect(lifecycle.requestPause(frameworkStateIsCapturing: true) == .pause)
        #expect(!lifecycle.canRequestManualPhoto(frameworkAllowsCapture: true, reachedMaximum: false))
    }

    @Test func realPhotoProgressUsesFrameworkMaximumAndUserTargetOnlyAsGuidance() {
        let belowTarget = ObjectCapturePhotoProgress(captured: 12, maximum: 250, preferredTarget: 40)
        #expect(!belowTarget.reachedMaximum)
        #expect(belowTarget.isBelowPreferredTarget)
        #expect(belowTarget.shouldWarnBeforeFinish)

        let reachedTarget = ObjectCapturePhotoProgress(captured: 40, maximum: 250, preferredTarget: 40)
        #expect(!reachedTarget.reachedMaximum)
        #expect(!reachedTarget.shouldWarnBeforeFinish)

        let maximum = ObjectCapturePhotoProgress(captured: 250, maximum: 250, preferredTarget: nil)
        #expect(maximum.reachedMaximum)
        #expect(!maximum.shouldWarnBeforeFinish)
    }

    @Test func preferredPhotoTargetPersistsAndCanBeDisabled() throws {
        let suiteName = "PhotoTargetPreferenceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        PhotoTargetPreference.write(85, to: defaults)
        #expect(PhotoTargetPreference.read(from: defaults) == 85)
        PhotoTargetPreference.write(nil, to: defaults)
        #expect(PhotoTargetPreference.read(from: defaults) == nil)
    }

    @Test func framingGuideCannotInterceptTouchesButControlsCan() {
        #expect(!CaptureOverlayInteractionPolicy.framingGuideAllowsHitTesting)
        #expect(CaptureOverlayInteractionPolicy.controlsAllowHitTesting)
    }

    @Test func objectStudioWorkflowRejectsOutOfOrderTransitions() {
        #expect(ObjectStudioTransitionPolicy.permits(from: .idle, to: .preparing))
        #expect(ObjectStudioTransitionPolicy.permits(from: .preparing, to: .readyForDetection))
        #expect(ObjectStudioTransitionPolicy.permits(from: .readyForDetection, to: .detecting))
        #expect(ObjectStudioTransitionPolicy.permits(from: .readyForDetection, to: .capturing))
        #expect(ObjectStudioTransitionPolicy.permits(from: .preparing, to: .detecting))
        #expect(ObjectStudioTransitionPolicy.permits(from: .detecting, to: .capturing))
        #expect(ObjectStudioTransitionPolicy.permits(from: .detecting, to: .readyForDetection))
        #expect(ObjectStudioTransitionPolicy.permits(from: .reconstructing, to: .reviewing))
        #expect(!ObjectStudioTransitionPolicy.permits(from: .idle, to: .capturing))
        #expect(!ObjectStudioTransitionPolicy.permits(from: .capturing, to: .reconstructing))
    }

    @Test func detectionReturningFalseReturnsToRecoverableReadyState() {
        var lifecycle = ObjectDetectionLifecycle()
        lifecycle.prepareNewSession()

        let shouldStartAutomatically = lifecycle.sessionBecameReady()
        #expect(shouldStartAutomatically)
        lifecycle.detectionRequestReturned(started: false)

        #expect(lifecycle.state == .ready)
        #expect(!lifecycle.isOperationPending)
    }

    @Test func repeatedRetryIsAllowedAfterACompletedFalseResult() {
        var lifecycle = readyDetectionLifecycle()

        let firstRetryStarted = lifecycle.beginRetry(frameworkStateIsReady: true)
        #expect(firstRetryStarted)
        lifecycle.detectionRequestReturned(started: false)
        let secondRetryStarted = lifecycle.beginRetry(frameworkStateIsReady: true)
        #expect(secondRetryStarted)
    }

    @Test func detectionDoubleTapIsRejectedWhileInvocationIsPending() {
        var lifecycle = readyDetectionLifecycle()

        let firstTapStarted = lifecycle.beginRetry(frameworkStateIsReady: true)
        let secondTapStarted = lifecycle.beginRetry(frameworkStateIsReady: true)
        #expect(firstTapStarted)
        #expect(!secondTapStarted)
        #expect(lifecycle.isOperationPending)
    }

    @Test func retryAndFreeformRemainBlockedWhileFrameworkStateUpdateIsPending() {
        var lifecycle = readyDetectionLifecycle()
        let retryStarted = lifecycle.beginRetry(frameworkStateIsReady: true)
        #expect(retryStarted)
        lifecycle.detectionRequestReturned(started: true)

        let duplicateRetryStarted = lifecycle.beginRetry(frameworkStateIsReady: true)
        let freeformStarted = lifecycle.beginFreeformCapture(frameworkStateIsReady: true)
        let automaticRetryStarted = lifecycle.sessionBecameReady()
        #expect(lifecycle.state == .awaitingDetectionState)
        #expect(!duplicateRetryStarted)
        #expect(!freeformStarted)
        #expect(!automaticRetryStarted)
    }

    @Test func cancellationWhileReadyIsTerminalForLateSessionEvents() {
        var lifecycle = readyDetectionLifecycle()

        lifecycle.cancel()
        lifecycle.sessionBecameDetecting()

        #expect(lifecycle.state == .cancelled)
        let retryStarted = lifecycle.beginRetry(frameworkStateIsReady: true)
        #expect(!retryStarted)
    }

    @Test func cancellationClearsPendingDetectionState() {
        var lifecycle = readyDetectionLifecycle()
        let retryStarted = lifecycle.beginRetry(frameworkStateIsReady: true)
        #expect(retryStarted)
        lifecycle.detectionRequestReturned(started: true)
        #expect(lifecycle.isOperationPending)

        lifecycle.cancel()

        #expect(lifecycle.state == .cancelled)
        #expect(!lifecycle.isOperationPending)
    }

    @Test func staleCaptureEventCannotReviveCancelledLifecycle() {
        var lifecycle = readyDetectionLifecycle()

        lifecycle.cancel()
        lifecycle.sessionBecameCapturing()

        #expect(lifecycle.state == .cancelled)
    }

    @Test func navigationDismissalCancellationBlocksFurtherDetection() {
        var lifecycle = readyDetectionLifecycle()

        lifecycle.cancel()

        let retryStarted = lifecycle.beginRetry(frameworkStateIsReady: true)
        let freeformStarted = lifecycle.beginFreeformCapture(frameworkStateIsReady: true)
        #expect(!retryStarted)
        #expect(!freeformStarted)
    }

    @Test func freeformCaptureStartsOnlyFromCurrentReadyState() {
        var lifecycle = readyDetectionLifecycle()

        let invalidFreeformStarted = lifecycle.beginFreeformCapture(frameworkStateIsReady: false)
        let validFreeformStarted = lifecycle.beginFreeformCapture(frameworkStateIsReady: true)
        #expect(!invalidFreeformStarted)
        #expect(validFreeformStarted)
        #expect(lifecycle.state == .capturing)
        let retryStarted = lifecycle.beginRetry(frameworkStateIsReady: true)
        #expect(!retryStarted)
    }

    private func readyDetectionLifecycle() -> ObjectDetectionLifecycle {
        var lifecycle = ObjectDetectionLifecycle()
        lifecycle.prepareNewSession()
        let shouldStartAutomatically = lifecycle.sessionBecameReady()
        #expect(shouldStartAutomatically)
        lifecycle.detectionRequestReturned(started: false)
        return lifecycle
    }

    @Test func objectCaptureWorkspaceUsesSeparatedLocalDirectories() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = LocalScanRepository(rootDirectory: root)

        let workspace = try repository.createObjectCaptureWorkspace(id: UUID())

        #expect(FileManager.default.fileExists(atPath: workspace.imagesDirectory.path))
        #expect(FileManager.default.fileExists(atPath: workspace.checkpointsDirectory.path))
        #expect(workspace.imagesDirectory.path.hasPrefix(repository.capturesDirectory.path))
    }

    @Test func objectCaptureDraftPersistsForLaterProcessing() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = LocalScanRepository(rootDirectory: root)
        let draft = ObjectCaptureDraft(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_010),
            photoCount: 42,
            status: .readyForReconstruction
        )

        try repository.saveObjectCaptureDraft(draft)

        #expect(try repository.loadObjectCaptureDraft(id: draft.id) == draft)
    }

    @Test func failedCaptureManifestPreservesOriginalImages() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = LocalScanRepository(rootDirectory: root)
        let id = UUID()
        let workspace = try repository.createObjectCaptureWorkspace(id: id)
        let image = workspace.imagesDirectory.appending(path: "IMG_0001.heic")
        try Data(repeating: 0x2A, count: 128).write(to: image)
        let failedDraft = ObjectCaptureDraft(id: id, photoCount: 1, status: .failed)

        try repository.saveObjectCaptureDraft(failedDraft)

        let reloadedDraft = try repository.loadObjectCaptureDraft(id: id)
        #expect(reloadedDraft.id == id)
        #expect(reloadedDraft.status == .failed)
        #expect(reloadedDraft.photoCount == 1)
        #expect(FileManager.default.fileExists(atPath: image.path))
        #expect(try repository.capturedImageURLs(id: id) == [image])
    }

    @Test func modelOutputStaysInsideLocalModelsDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = LocalScanRepository(rootDirectory: root)

        let output = try repository.modelFileURL(id: UUID())

        #expect(output.pathExtension == "usdz")
        #expect(output.deletingLastPathComponent().standardizedFileURL == repository.modelsDirectory.standardizedFileURL)
    }

    @Test func libraryOnlyOpensAnExistingNonemptyUSDZ() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = LocalScanRepository(rootDirectory: root)
        let id = UUID()
        let modelURL = try repository.modelFileURL(id: id)
        let scan = ScanMetadata(
            id: id,
            name: "Object",
            kind: .object,
            relativeModelPath: modelURL.lastPathComponent
        )

        #expect(try repository.existingModelURL(for: scan) == nil)
        try structurallyValidUSDZData().write(to: modelURL)
        #expect(try repository.existingModelURL(for: scan) == modelURL)
    }

    @Test func libraryRejectsEmptyMalformedAndSymbolicLinkUSDZFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = LocalScanRepository(rootDirectory: root)

        let emptyID = UUID()
        let emptyURL = try repository.modelFileURL(id: emptyID)
        try Data().write(to: emptyURL)
        let emptyScan = ScanMetadata(id: emptyID, name: "Empty", kind: .object, relativeModelPath: emptyURL.lastPathComponent)
        #expect(try repository.existingModelURL(for: emptyScan) == nil)

        let malformedID = UUID()
        let malformedURL = try repository.modelFileURL(id: malformedID)
        try Data(repeating: 0x00, count: 128).write(to: malformedURL)
        let malformedScan = ScanMetadata(id: malformedID, name: "Malformed", kind: .object, relativeModelPath: malformedURL.lastPathComponent)
        #expect(try repository.existingModelURL(for: malformedScan) == nil)

        let outsideURL = root.appending(path: "outside.usdz")
        try structurallyValidUSDZData().write(to: outsideURL)
        let linkID = UUID()
        let linkURL = try repository.modelFileURL(id: linkID)
        try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: outsideURL)
        let linkScan = ScanMetadata(id: linkID, name: "Link", kind: .object, relativeModelPath: linkURL.lastPathComponent)
        #expect(try repository.existingModelURL(for: linkScan) == nil)
    }

    @Test @MainActor func libraryMetadataSurvivesAppStyleReload() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = LocalScanRepository(rootDirectory: root)
        let id = UUID()
        let modelURL = try repository.modelFileURL(id: id)
        try structurallyValidUSDZData().write(to: modelURL)
        let scan = ScanMetadata(
            id: id,
            name: "Restart Test",
            kind: .object,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            relativeModelPath: modelURL.lastPathComponent,
            fileSizeBytes: Int64(structurallyValidUSDZData().count)
        )

        let firstLaunch = ScanLibrary(repository: repository, autoLoad: false)
        firstLaunch.upsert(scan)
        let restartedLibrary = ScanLibrary(repository: repository)

        #expect(firstLaunch.state == .loaded)
        #expect(restartedLibrary.scans == [scan])
        #expect(restartedLibrary.modelURL(for: scan) == modelURL)
    }

    @Test func metadataRoundTripsThroughLocalRepository() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let repository = LocalScanRepository(rootDirectory: root)
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let expected = ScanMetadata(
            name: "Workshop",
            kind: .environment,
            createdAt: timestamp,
            updatedAt: timestamp,
            relativeModelPath: "workshop.usdz",
            relativeCapturePath: UUID().uuidString,
            fileSizeBytes: 42,
            photoCount: 75
        )

        try repository.save([expected])
        let loaded = try repository.load()

        #expect(loaded == [expected])
    }

    @Test func legacySprintOneMetadataStillDecodes() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "name": "Legacy Object",
          "kind": "object",
          "createdAt": "2026-01-01T00:00:00Z",
          "updatedAt": "2026-01-01T00:00:00Z",
          "relativeModelPath": "legacy.usdz",
          "schemaVersion": 1
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let scan = try decoder.decode(ScanMetadata.self, from: json)

        #expect(scan.name == "Legacy Object")
        #expect(scan.relativeCapturePath == nil)
        #expect(scan.photoCount == nil)
    }

    @Test func repositoryStartsEmptyAndCreatesLocalFolders() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let repository = LocalScanRepository(rootDirectory: root)

        #expect(try repository.load().isEmpty)
        #expect(FileManager.default.fileExists(atPath: repository.modelsDirectory.path))
    }

    @Test func repositoryRejectsEscapingModelPaths() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = LocalScanRepository(rootDirectory: root)
        let scan = ScanMetadata(name: "Unsafe", kind: .object, relativeModelPath: "../outside.usdz")

        #expect(throws: LocalScanRepository.RepositoryError.self) {
            try repository.save([scan])
        }
    }

    private func structurallyValidUSDZData() -> Data {
        var data = Data([0x50, 0x4B, 0x03, 0x04])
        data.append(Data(repeating: 0x00, count: 124))
        return data
    }
}
