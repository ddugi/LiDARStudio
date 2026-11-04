import ARKit
import Combine
import Foundation
import OSLog
import UIKit

@MainActor
final class RGBDRecordingCoordinator: NSObject, ObservableObject, ARSessionDelegate {
    @Published private(set) var isPreparing = false
    @Published private(set) var isRecording = false
    @Published private(set) var isFinalizing = false
    @Published private(set) var statusText = "Ready to record"
    @Published private(set) var trackingState = "Waiting for ARKit"
    @Published private(set) var snapshot = RGBDFrameSink.Snapshot(
        sessionCallbacks: 0,
        framesAccepted: 0,
        framesWritten: 0,
        depthFramesWritten: 0,
        confidenceFramesWritten: 0,
        droppedFrames: 0,
        pendingWrites: 0,
        reachedFrameLimit: false,
        datasetURL: nil
    )
    @Published private(set) var completedDatasetURL: URL?
    @Published private(set) var validationReport: RGBDDatasetValidationReport?
    @Published private(set) var errorMessage: String?

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "LiDARStudio",
        category: "RGBDRecording"
    )
    private let delegateQueue = DispatchQueue(
        label: "se.dugiselmanaj.lidarstudio2.rgbd-session",
        qos: .userInitiated
    )
    private let screenAwakeManager: ScreenAwakeManager
    private let frameForwarder = RGBDFrameForwarder()
    private let trackingThrottle = RGBDTrackingThrottle()
    private var session: ARSession?
    private var sink: RGBDFrameSink?
    private var awakeSession: ScreenAwakeManager.Session?
    private var stopTask: Task<Void, Never>?

    init(screenAwakeManager: ScreenAwakeManager? = nil) {
        self.screenAwakeManager = screenAwakeManager ?? .shared
        super.init()
    }

    var isActive: Bool { isPreparing || isRecording || isFinalizing }

    func start() async {
        guard !isActive, session == nil, sink == nil else {
            logger.error("RGBD_START_REJECTED reason=duplicate")
            return
        }
        guard ARWorldTrackingConfiguration.isSupported else {
            failBeforeStart("AR world tracking is unavailable on this device.")
            return
        }
        guard ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) else {
            failBeforeStart("Live scene depth is unavailable on this device.")
            return
        }

        isPreparing = true
        statusText = "Preparing camera"
        errorMessage = nil
        completedDatasetURL = nil
        validationReport = nil

        var permission = CameraPermission.current
        if permission == .notDetermined { permission = await CameraPermission.request() }
        guard permission == .authorized else {
            isPreparing = false
            failBeforeStart("Camera access is required to record RGB-D data.")
            return
        }

        do {
            let root = try Self.datasetRootDirectory()
            let frameSink = RGBDFrameSink()
            frameSink.onSnapshot = { [weak self] snapshot in
                Task { @MainActor [weak self] in self?.receive(snapshot) }
            }
            frameSink.onFatalError = { [weak self] message in
                Task { @MainActor [weak self] in
                    guard let self, self.isRecording else { return }
                    self.errorMessage = message
                    self.stop(reason: .failed, manifestStatus: "failed")
                }
            }
            let datasetURL = try frameSink.begin(
                rootDirectory: root,
                device: RGBDDeviceInfo(
                    model: UIDevice.current.model,
                    systemName: UIDevice.current.systemName,
                    systemVersion: UIDevice.current.systemVersion
                ),
                worldTrackingSupported: true,
                sceneDepthSupported: true
            )

            let newSession = ARSession()
            newSession.delegateQueue = delegateQueue
            newSession.delegate = self
            let configuration = ARWorldTrackingConfiguration()
            configuration.frameSemantics.insert(.sceneDepth)

            sink = frameSink
            frameForwarder.setSink(frameSink)
            session = newSession
            snapshot = frameSink.currentSnapshot()
            awakeSession = screenAwakeManager.begin(.environment)
            isPreparing = false
            isRecording = true
            statusText = "Recording genuine RGB-D frames"
            logger.notice("RGBD_SESSION_RUN_BEGIN dataset=\(datasetURL.lastPathComponent, privacy: .public)")
            newSession.run(configuration, options: [.resetTracking, .removeExistingAnchors])
            logger.notice("RGBD_SESSION_RUN_RETURNED")
        } catch {
            isPreparing = false
            releaseResources(reason: .failed)
            failBeforeStart(error.localizedDescription)
        }
    }

    func stop(
        reason: ScreenAwakeManager.EndReason = .stopped,
        manifestStatus: String = "completed"
    ) {
        guard isRecording, !isFinalizing else { return }
        isRecording = false
        isFinalizing = true
        statusText = "Finalizing local dataset"
        logger.notice("RGBD_SESSION_STOP_BEGIN status=\(manifestStatus, privacy: .public)")

        session?.pause()
        session?.delegate = nil
        session = nil
        frameForwarder.setSink(nil)
        if let awakeSession {
            screenAwakeManager.end(awakeSession, reason: reason)
            self.awakeSession = nil
        }

        guard let sink else {
            isFinalizing = false
            statusText = "Recording stopped"
            return
        }
        self.sink = nil
        stopTask = Task { [weak self] in
            do {
                let completion = try await sink.finish(status: manifestStatus)
                guard let self else { return }
                self.completedDatasetURL = completion.datasetURL
                self.validationReport = completion.validation
                self.snapshot = sink.currentSnapshot()
                self.statusText = completion.validation.isValid
                    ? "Dataset saved and validated"
                    : "Dataset saved with validation errors"
                if !completion.validation.isValid {
                    self.errorMessage = completion.validation.errors.joined(separator: " ")
                }
                self.logger.notice("RGBD_SESSION_FINISHED frames=\(completion.manifest.counts.framesWritten, privacy: .public) valid=\(completion.validation.isValid, privacy: .public)")
            } catch {
                self?.errorMessage = error.localizedDescription
                self?.statusText = "Dataset finalization failed"
                self?.logger.error("RGBD_FINALIZE_FAILED error=\(error.localizedDescription, privacy: .public)")
            }
            self?.isFinalizing = false
            self?.stopTask = nil
        }
    }

    func stopForBackground() {
        if isRecording {
            stop(reason: .backgrounded, manifestStatus: "interrupted")
        } else if isPreparing {
            isPreparing = false
            releaseResources(reason: .backgrounded)
        }
    }

    func validateCompletedDataset() {
        guard let completedDatasetURL else { return }
        validationReport = RGBDDatasetValidator.validate(datasetURL: completedDatasetURL)
    }

    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        frameForwarder.offer(frame)
        guard trackingThrottle.shouldPublish(timestamp: frame.timestamp) else { return }
        let tracking = Self.trackingDescription(frame.camera.trackingState)
        Task { @MainActor [weak self] in
            guard let self, self.isRecording else { return }
            self.trackingState = tracking
        }
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        let nsError = error as NSError
        Task { @MainActor [weak self] in
            guard let self, self.isRecording else { return }
            self.logger.error("RGBD_SESSION_FAILED domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public)")
            self.errorMessage = error.localizedDescription
            self.stop(reason: .failed, manifestStatus: "failed")
        }
    }

    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        Task { @MainActor [weak self] in
            guard let self, self.isRecording else { return }
            self.trackingState = "Session interrupted"
            self.stop(reason: .backgrounded, manifestStatus: "interrupted")
        }
    }

    private func receive(_ snapshot: RGBDFrameSink.Snapshot) {
        self.snapshot = snapshot
        if snapshot.reachedFrameLimit, snapshot.pendingWrites == 0, isRecording {
            statusText = "Frame limit reached"
            stop(reason: .completed, manifestStatus: "completed")
        }
    }

    private func releaseResources(reason: ScreenAwakeManager.EndReason) {
        session?.pause()
        session?.delegate = nil
        session = nil
        frameForwarder.setSink(nil)
        sink = nil
        if let awakeSession {
            screenAwakeManager.end(awakeSession, reason: reason)
            self.awakeSession = nil
        }
    }

    private func failBeforeStart(_ message: String) {
        errorMessage = message
        statusText = "Recording unavailable"
        logger.error("RGBD_START_FAILED error=\(message, privacy: .public)")
    }

    private static func datasetRootDirectory() throws -> URL {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = applicationSupport.appendingPathComponent("RGBDDatasets", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableRoot = root
        try? mutableRoot.setResourceValues(values)
        return root
    }

    nonisolated private static func trackingDescription(_ state: ARCamera.TrackingState) -> String {
        switch state {
        case .normal: "Tracking normal"
        case .notAvailable: "Tracking unavailable"
        case .limited(let reason):
            switch reason {
            case .initializing: "Tracking initializing"
            case .excessiveMotion: "Tracking limited: move slower"
            case .insufficientFeatures: "Tracking limited: point at textured surfaces"
            case .relocalizing: "Tracking relocalizing"
            @unknown default: "Tracking limited"
            }
        }
    }
}

nonisolated private final class RGBDTrackingThrottle: @unchecked Sendable {
    private let lock = NSLock()
    private var lastPublication = 0.0

    func shouldPublish(timestamp: TimeInterval) -> Bool {
        lock.withLock {
            guard timestamp - lastPublication >= 0.2 else { return false }
            lastPublication = timestamp
            return true
        }
    }
}

nonisolated private final class RGBDFrameForwarder: @unchecked Sendable {
    private let lock = NSLock()
    private var sink: RGBDFrameSink?

    func setSink(_ sink: RGBDFrameSink?) {
        lock.withLock { self.sink = sink }
    }

    func offer(_ frame: ARFrame) {
        lock.withLock { sink }?.offer(frame: frame)
    }
}
