import ARKit
import AVFoundation
import Combine
import Foundation
import OSLog

enum LiDARDiagnosticStage: String, CaseIterable, Identifiable {
    case basic, depth, full
    var id: Self { self }
    var title: String {
        switch self { case .basic: "Basic"; case .depth: "Depth"; case .full: "Mesh" }
    }
    var explanation: String {
        switch self {
        case .basic: "World tracking only. Confirms ordinary ARKit frames."
        case .depth: "World tracking with scene depth."
        case .full: "World tracking with scene depth and mesh reconstruction."
        }
    }
}

@MainActor
final class LiDARDiagnosticCoordinator: NSObject, ObservableObject, ARSessionDelegate {
    @Published private(set) var isPresented = false
    @Published private(set) var isPreparing = false
    @Published private(set) var currentStage: LiDARDiagnosticStage?
    @Published private(set) var isDepthAvailable = false
    @Published private(set) var depthStatus = "Waiting for live depth"
    @Published private(set) var sessionUpdateCallbackCount = 0
    @Published private(set) var frameCount = 0
    @Published private(set) var depthFrameCount = 0
    @Published private(set) var normalTrackingFrameCount = 0
    @Published private(set) var trackingStatus = "Tracking: starting"
    @Published private(set) var meshAnchorCount = 0
    @Published private(set) var meshAnchorsAdded = 0
    @Published private(set) var meshAnchorsUpdated = 0
    @Published private(set) var meshAnchorsRemoved = 0
    @Published private(set) var errorMessage: String?

    let supportsSceneDepth = ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
    let supportsMesh = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "LiDARStudio", category: "LiDARDiagnostic")
    private let screenAwakeManager: ScreenAwakeManager
    private let delegateQueue = DispatchQueue(label: "se.dugiselmanaj.lidarstudio2.lidar-diagnostic", qos: .userInitiated)
    private let metrics = LiDARDiagnosticMetrics()
    private var session: ARSession?
    private var awakeSession: ScreenAwakeManager.Session?

    init(screenAwakeManager: ScreenAwakeManager? = nil) {
        self.screenAwakeManager = screenAwakeManager ?? .shared
        super.init()
    }

    var progressStatus: ScanProgressStatus? {
        if errorMessage != nil, !isPresented { return .scanFailed }
        if isPreparing { return .preparingCamera }
        if isPresented { return frameCount == 0 ? .readyToScan : .capturing }
        return nil
    }

    func logStartTapped(stage: LiDARDiagnosticStage) {
        logger.notice("LIDAR_START_TAPPED stage=\(stage.rawValue, privacy: .public)")
    }

    func prepare(stage: LiDARDiagnosticStage) async {
        guard !isPreparing, session == nil, !isPresented else {
            logger.error("LIDAR_START_REJECTED reason=duplicate")
            return
        }
        guard ARWorldTrackingConfiguration.isSupported else {
            errorMessage = "AR world tracking is unavailable on this device."
            return
        }
        guard stage != .depth || supportsSceneDepth else {
            errorMessage = "Scene depth is unavailable on this device."
            return
        }
        guard stage != .full || (supportsSceneDepth && supportsMesh) else {
            errorMessage = "Scene depth and mesh reconstruction are required for this stage."
            return
        }

        isPreparing = true
        defer { isPreparing = false }
        var permission = CameraPermission.current
        if permission == .notDetermined { permission = await CameraPermission.request() }
        guard permission == .authorized else {
            errorMessage = "Camera access is required for the LiDAR diagnostic."
            return
        }
        reset(stage: stage)
        startSession(stage: stage)
    }

    func stop(reason: ScreenAwakeManager.EndReason = .stopped) {
        guard isPresented || session != nil else { return }
        let snapshot = metrics.snapshot()
        logger.notice("LIDAR_SESSION_STOPPED stage=\(self.currentStage?.rawValue ?? "none", privacy: .public) frames=\(snapshot.frames, privacy: .public) depthFrames=\(snapshot.depthFrames, privacy: .public) activeMeshAnchors=\(snapshot.activeMeshAnchors, privacy: .public)")
        session?.pause()
        session?.delegate = nil
        session = nil
        currentStage = nil
        isPresented = false
        isPreparing = false
        if let awakeSession {
            screenAwakeManager.end(awakeSession, reason: reason)
            self.awakeSession = nil
        }
    }

    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard metrics.record(frame: frame) else { return }
        let snapshot = metrics.snapshot()
        Task { @MainActor [weak self] in self?.publish(snapshot) }
    }

    nonisolated func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        metrics.record(anchors: anchors, event: .added)
    }
    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        metrics.record(anchors: anchors, event: .updated)
    }
    nonisolated func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        metrics.record(anchors: anchors, event: .removed)
    }
    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        let nsError = error as NSError
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.errorMessage = error.localizedDescription
            self.logger.error("LIDAR_SESSION_FAILED domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public)")
            self.stop(reason: .failed)
        }
    }
    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        Task { @MainActor [weak self] in
            self?.trackingStatus = "Tracking: interrupted"
            self?.logger.notice("LIDAR_SESSION_INTERRUPTED")
        }
    }
    nonisolated func sessionInterruptionEnded(_ session: ARSession) {
        Task { @MainActor [weak self] in
            self?.trackingStatus = "Tracking: interruption ended"
            self?.logger.notice("LIDAR_SESSION_INTERRUPTION_ENDED")
        }
    }

    private func startSession(stage: LiDARDiagnosticStage) {
        precondition(session == nil, "Only one diagnostic ARSession may exist")
        let newSession = ARSession()
        let configuration = ARWorldTrackingConfiguration()
        switch stage {
        case .basic: break
        case .depth: configuration.frameSemantics.insert(.sceneDepth)
        case .full:
            configuration.frameSemantics.insert(.sceneDepth)
            configuration.sceneReconstruction = .mesh
        }
        newSession.delegateQueue = delegateQueue
        newSession.delegate = self
        session = newSession
        currentStage = stage
        isPresented = true
        awakeSession = screenAwakeManager.begin(.environment)
        logger.notice("LIDAR_CONFIGURATION_VALIDATED stage=\(stage.rawValue, privacy: .public) depth=\(configuration.frameSemantics.contains(.sceneDepth), privacy: .public) mesh=\(configuration.sceneReconstruction == .mesh, privacy: .public)")
        logger.notice("LIDAR_SESSION_RUN_BEGIN stage=\(stage.rawValue, privacy: .public)")
        let startedAt = ContinuousClock.now
        newSession.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        let elapsed = startedAt.duration(to: .now)
        logger.notice("LIDAR_SESSION_RUN_RETURNED stage=\(stage.rawValue, privacy: .public) duration=\(String(describing: elapsed), privacy: .public)")
    }

    private func publish(_ snapshot: LiDARDiagnosticMetrics.Snapshot) {
        guard isPresented else { return }
        let firstFrame = frameCount == 0 && snapshot.frames > 0
        let firstDepth = depthFrameCount == 0 && snapshot.depthFrames > 0
        let firstMesh = meshAnchorsAdded == 0 && snapshot.meshAnchorsAdded > 0
        sessionUpdateCallbackCount = snapshot.frames
        frameCount = snapshot.frames
        depthFrameCount = snapshot.depthFrames
        normalTrackingFrameCount = snapshot.normalTrackingFrames
        trackingStatus = snapshot.trackingStatus
        meshAnchorCount = snapshot.activeMeshAnchors
        meshAnchorsAdded = snapshot.meshAnchorsAdded
        meshAnchorsUpdated = snapshot.meshAnchorsUpdated
        meshAnchorsRemoved = snapshot.meshAnchorsRemoved
        isDepthAvailable = snapshot.hasDepth
        if snapshot.hasDepth, let width = snapshot.depthWidth, let height = snapshot.depthHeight {
            depthStatus = "Live depth: \(width) × \(height)"
        } else {
            depthStatus = currentStage == .basic ? "Depth not requested" : "Waiting for live depth"
        }
        if firstFrame { logger.notice("LIDAR_FIRST_FRAME tracking=\(snapshot.trackingStatus, privacy: .public)") }
        if firstDepth { logger.notice("LIDAR_DEPTH_RECEIVED width=\(snapshot.depthWidth ?? 0, privacy: .public) height=\(snapshot.depthHeight ?? 0, privacy: .public)") }
        if firstMesh { logger.notice("LIDAR_MESH_ANCHOR_ADDED active=\(snapshot.activeMeshAnchors, privacy: .public)") }
    }

    private func reset(stage: LiDARDiagnosticStage) {
        metrics.reset()
        errorMessage = nil
        currentStage = stage
        isDepthAvailable = false
        depthStatus = stage == .basic ? "Depth not requested" : "Waiting for live depth"
        sessionUpdateCallbackCount = 0
        frameCount = 0
        depthFrameCount = 0
        normalTrackingFrameCount = 0
        trackingStatus = "Tracking: starting"
        meshAnchorCount = 0
        meshAnchorsAdded = 0
        meshAnchorsUpdated = 0
        meshAnchorsRemoved = 0
    }
}

nonisolated private final class LiDARDiagnosticMetrics: @unchecked Sendable {
    struct Snapshot: Sendable {
        let frames, depthFrames, normalTrackingFrames: Int
        let trackingStatus: String
        let hasDepth: Bool
        let depthWidth, depthHeight: Int?
        let activeMeshAnchors, meshAnchorsAdded, meshAnchorsUpdated, meshAnchorsRemoved: Int
    }
    enum AnchorEvent { case added, updated, removed }
    private let lock = NSLock()
    private var frames = 0, depthFrames = 0, normalTrackingFrames = 0
    private var trackingStatus = "Tracking: starting"
    private var hasDepth = false
    private var depthWidth: Int?, depthHeight: Int?
    private var meshIDs: Set<UUID> = []
    private var meshAnchorsAdded = 0, meshAnchorsUpdated = 0, meshAnchorsRemoved = 0
    private var lastPublishTime: TimeInterval = 0

    func record(frame: ARFrame) -> Bool {
        lock.withLock {
            frames += 1
            let depthMap = frame.sceneDepth?.depthMap
            hasDepth = depthMap != nil
            if let depthMap {
                depthFrames += 1
                depthWidth = CVPixelBufferGetWidth(depthMap)
                depthHeight = CVPixelBufferGetHeight(depthMap)
            }
            trackingStatus = Self.trackingDescription(frame.camera.trackingState)
            if case .normal = frame.camera.trackingState { normalTrackingFrames += 1 }
            meshIDs = Set(frame.anchors.compactMap { ($0 as? ARMeshAnchor)?.identifier })
            guard frame.timestamp - lastPublishTime >= 0.2 else { return false }
            lastPublishTime = frame.timestamp
            return true
        }
    }

    func record(anchors: [ARAnchor], event: AnchorEvent) {
        let ids = anchors.compactMap { ($0 as? ARMeshAnchor)?.identifier }
        guard !ids.isEmpty else { return }
        lock.withLock {
            switch event {
            case .added: meshAnchorsAdded += ids.count; meshIDs.formUnion(ids)
            case .updated: meshAnchorsUpdated += ids.count; meshIDs.formUnion(ids)
            case .removed: meshAnchorsRemoved += ids.count; meshIDs.subtract(ids)
            }
        }
    }

    func snapshot() -> Snapshot {
        lock.withLock {
            Snapshot(frames: frames, depthFrames: depthFrames, normalTrackingFrames: normalTrackingFrames, trackingStatus: trackingStatus, hasDepth: hasDepth, depthWidth: depthWidth, depthHeight: depthHeight, activeMeshAnchors: meshIDs.count, meshAnchorsAdded: meshAnchorsAdded, meshAnchorsUpdated: meshAnchorsUpdated, meshAnchorsRemoved: meshAnchorsRemoved)
        }
    }

    func reset() {
        lock.withLock {
            frames = 0; depthFrames = 0; normalTrackingFrames = 0
            trackingStatus = "Tracking: starting"; hasDepth = false
            depthWidth = nil; depthHeight = nil; meshIDs = []
            meshAnchorsAdded = 0; meshAnchorsUpdated = 0; meshAnchorsRemoved = 0
            lastPublishTime = 0
        }
    }

    private static func trackingDescription(_ state: ARCamera.TrackingState) -> String {
        switch state {
        case .normal: "Tracking: normal"
        case .notAvailable: "Tracking: unavailable"
        case .limited(let reason):
            switch reason {
            case .initializing: "Tracking: initializing"
            case .excessiveMotion: "Tracking limited: move slower"
            case .insufficientFeatures: "Tracking limited: scan textured surfaces"
            case .relocalizing: "Tracking: relocalizing"
            @unknown default: "Tracking: limited"
            }
        }
    }
}
