import ARKit
import Combine
import Foundation
import OSLog
import RoomPlan

@MainActor
final class RoomCaptureCoordinator: NSObject, ObservableObject {
    struct Summary: Equatable, Sendable {
        let walls: Int
        let doors: Int
        let windows: Int
        let objects: Int
    }

    @Published private(set) var lifecycle = RoomCaptureLifecycle()
    @Published private(set) var instructionText = "Move slowly and include every wall and corner."
    @Published private(set) var trackingStatusText = "Waiting for ARKit tracking"
    @Published private(set) var isGeometryOverlayEnabled = true
    @Published private(set) var liveSummary: Summary?
    @Published private(set) var roomSummary: Summary?
    @Published private(set) var errorMessage: String?
    @Published private(set) var savedScanID: UUID?

    private static let logger = Logger(subsystem: "se.dugiselmanaj.lidarstudio2", category: "RoomCapture")
    private let repository: LocalScanRepository
    private weak var captureView: RoomCaptureView?
    private var capturedRoom: CapturedRoom?
    private var awakeSession: ScreenAwakeManager.Session?
    private var shouldStartWhenAttached = false
    private var saveTask: Task<Void, Never>?

    init(repository: LocalScanRepository = LocalScanRepository()) {
        self.repository = repository
    }

    required init?(coder: NSCoder) {
        repository = LocalScanRepository()
        super.init()
    }

    nonisolated func encode(with coder: NSCoder) {
        // RoomCaptureView declares NSCoding for its weak delegate. The
        // coordinator itself has no serializable state and is never archived.
    }

    func attach(_ view: RoomCaptureView) {
        guard captureView !== view else { return }
        captureView = view
        view.delegate = self
        view.captureSession.delegate = self
        view.isModelEnabled = isGeometryOverlayEnabled
        lifecycle.attach()
        Self.logger.info("ROOM_VIEW_ATTACHED")

        if shouldStartWhenAttached {
            shouldStartWhenAttached = false
            startAttachedSession()
        }
    }

    func cameraPermissionDidChange(_ permission: CameraPermission) {
        if permission != .authorized { fail("Camera access is required for RoomPlan.") }
    }

    func startTapped() {
        Self.logger.info("ROOM_START_TAPPED")
        lifecycle.attach()
        if CameraPermission.current == .authorized {
            prepareToStart()
            return
        }

        Task { [weak self] in
            await self?.requestPermissionAndStart()
        }
    }

    private func requestPermissionAndStart() async {
        let permission = await CameraPermission.request()
        cameraPermissionDidChange(permission)
        guard permission == .authorized else { return }
        prepareToStart()
    }

    func prepareToStart() {
        guard CameraPermission.current == .authorized else {
            fail("Camera access is required for RoomPlan.")
            return
        }
        guard RoomCaptureSession.isSupported else {
            fail("RoomPlan is unavailable on this device.")
            return
        }
        guard lifecycle.requestStart() else { return }
        errorMessage = nil
        trackingStatusText = "Waiting for ARKit tracking"
        liveSummary = nil
        roomSummary = nil
        capturedRoom = nil
        savedScanID = nil
        acquireAwakeSession()
        Self.logger.info("ROOM_START_REQUESTED")

        if captureView == nil {
            shouldStartWhenAttached = true
        } else {
            startAttachedSession()
        }
    }

    func finishCapture() {
        guard lifecycle.requestFinish(), let captureView else { return }
        instructionText = "Hold still while RoomPlan finishes the capture."
        Self.logger.info("ROOM_STOP_REQUESTED")
        captureView.captureSession.stop()
    }

    func setGeometryOverlayEnabled(_ isEnabled: Bool) {
        guard isGeometryOverlayEnabled != isEnabled else { return }
        isGeometryOverlayEnabled = isEnabled
        captureView?.isModelEnabled = isEnabled
        Self.logger.info("ROOM_GEOMETRY_OVERLAY enabled=\(isEnabled)")
    }

    func cancel() {
        guard lifecycle.isCaptureActive || lifecycle.phase == .processing else { return }
        let session = captureView?.captureSession
        lifecycle.cancel()
        shouldStartWhenAttached = false
        releaseAwakeSession(reason: .cancelled)
        Self.logger.info("ROOM_CANCELLED")
        session?.stop()
    }

    func reset() {
        cancel()
        saveTask?.cancel()
        saveTask = nil
        errorMessage = nil
        trackingStatusText = "Waiting for ARKit tracking"
        liveSummary = nil
        roomSummary = nil
        capturedRoom = nil
        savedScanID = nil
        lifecycle.reset()
        lifecycle.attach()
    }

    func saveToLibrary() {
        guard lifecycle.requestSave(), let room = capturedRoom else { return }
        let repository = repository
        saveTask = Task { [weak self] in
            do {
                let scan = try await Task.detached(priority: .userInitiated) {
                    try Self.export(room: room, repository: repository)
                }.value
                guard !Task.isCancelled else { return }
                self?.savedScanID = scan.id
                self?.lifecycle.confirmSaved()
                Self.logger.info("ROOM_SAVE_SUCCEEDED id=\(scan.id.uuidString, privacy: .public)")
            } catch {
                guard !Task.isCancelled else { return }
                self?.fail("The room model could not be saved: \(error.localizedDescription)")
            }
        }
    }

    private func startAttachedSession() {
        guard lifecycle.phase == .starting, let captureView else { return }
        var configuration = RoomCaptureSession.Configuration()
        configuration.isCoachingEnabled = true
        instructionText = "Preparing RoomPlan guidance…"
        captureView.captureSession.run(configuration: configuration)
        Self.logger.info("ROOM_SESSION_RUN")
    }

    private func acquireAwakeSession() {
        guard awakeSession == nil else { return }
        awakeSession = ScreenAwakeManager.shared.begin(.room)
    }

    private func releaseAwakeSession(reason: ScreenAwakeManager.EndReason) {
        guard let awakeSession else { return }
        ScreenAwakeManager.shared.end(awakeSession, reason: reason)
        self.awakeSession = nil
    }

    private func fail(_ message: String) {
        errorMessage = message
        lifecycle.fail()
        releaseAwakeSession(reason: .failed)
        Self.logger.error("ROOM_FAILED \(message, privacy: .public)")
    }

    nonisolated private static func export(
        room: CapturedRoom,
        repository: LocalScanRepository
    ) throws -> ScanMetadata {
        let id = UUID()
        let destination = try repository.modelFileURL(id: id)
        try room.export(to: destination, exportOptions: .mesh)

        let values = try destination.resourceValues(forKeys: [.fileSizeKey])
        let scan = ScanMetadata(
            id: id,
            name: "Room Scan \(Date.now.formatted(date: .abbreviated, time: .shortened))",
            kind: .room,
            relativeModelPath: destination.lastPathComponent,
            fileSizeBytes: Int64(values.fileSize ?? 0)
        )
        guard try repository.existingModelURL(for: scan) != nil else {
            throw CocoaError(.fileReadCorruptFile)
        }

        var scans = try repository.load()
        guard !scans.contains(where: { $0.id == id }) else {
            throw CocoaError(.fileWriteFileExists)
        }
        scans.append(scan)
        try repository.save(scans)
        return scan
    }
}

extension RoomCaptureCoordinator: RoomCaptureSessionDelegate {
    nonisolated func captureSession(
        _ session: RoomCaptureSession,
        didStartWith configuration: RoomCaptureSession.Configuration
    ) {
        Task { @MainActor [weak self] in
            guard let self, self.captureView?.captureSession === session else { return }
            self.lifecycle.confirmStarted()
            self.instructionText = "Move slowly and include every wall and corner."
            self.updateTrackingStatus(for: session)
            Self.logger.info("ROOM_SESSION_STARTED")
        }
    }

    nonisolated func captureSession(
        _ session: RoomCaptureSession,
        didProvide instruction: RoomCaptureSession.Instruction
    ) {
        Task { @MainActor [weak self] in
            guard let self, self.captureView?.captureSession === session,
                  self.lifecycle.phase == .capturing else { return }
            self.instructionText = instruction.userFacingText
            self.updateTrackingStatus(for: session)
        }
    }

    nonisolated func captureSession(
        _ session: RoomCaptureSession,
        didUpdate room: CapturedRoom
    ) {
        let summary = Summary(
            walls: room.walls.count,
            doors: room.doors.count,
            windows: room.windows.count,
            objects: room.objects.count
        )
        Task { @MainActor [weak self] in
            guard let self, self.captureView?.captureSession === session,
                  self.lifecycle.phase == .capturing,
                  self.liveSummary != summary else { return }
            self.updateTrackingStatus(for: session)
            self.liveSummary = summary
            Self.logger.info(
                "ROOM_GEOMETRY_UPDATED walls=\(summary.walls) doors=\(summary.doors) windows=\(summary.windows) objects=\(summary.objects)"
            )
        }
    }

    nonisolated func captureSession(
        _ session: RoomCaptureSession,
        didEndWith data: CapturedRoomData,
        error: (any Error)?
    ) {
        Task { @MainActor [weak self] in
            guard let self, self.captureView?.captureSession === session,
                  self.lifecycle.phase != .cancelled else { return }
            self.releaseAwakeSession(reason: error == nil ? .completed : .failed)
            if let error {
                self.fail(error.localizedDescription)
            } else {
                self.lifecycle.beginProcessing()
                Self.logger.info("ROOM_SESSION_ENDED")
            }
        }
    }

    private func updateTrackingStatus(for session: RoomCaptureSession) {
        let status = session.arSession.currentFrame?.camera.trackingState.userFacingText
            ?? "Waiting for the first ARKit frame"
        guard trackingStatusText != status else { return }
        trackingStatusText = status
        Self.logger.info("ROOM_TRACKING_STATUS \(status, privacy: .public)")
    }
}

extension RoomCaptureCoordinator: RoomCaptureViewDelegate {
    nonisolated func captureView(
        shouldPresent roomDataForProcessing: CapturedRoomData,
        error: (any Error)?
    ) -> Bool {
        error == nil
    }

    nonisolated func captureView(
        didPresent processedResult: CapturedRoom,
        error: (any Error)?
    ) {
        Task { @MainActor [weak self] in
            guard let self, self.lifecycle.phase == .processing else { return }
            if let error {
                self.fail(error.localizedDescription)
                return
            }
            self.capturedRoom = processedResult
            self.roomSummary = Summary(
                walls: processedResult.walls.count,
                doors: processedResult.doors.count,
                windows: processedResult.windows.count,
                objects: processedResult.objects.count
            )
            self.lifecycle.presentReview()
            Self.logger.info("ROOM_REVIEW_READY")
        }
    }
}

private extension RoomCaptureSession.Instruction {
    var userFacingText: String {
        switch self {
        case .moveCloseToWall: "Move closer to the wall."
        case .moveAwayFromWall: "Move farther from the wall."
        case .slowDown: "Move more slowly."
        case .turnOnLight: "More light is needed."
        case .normal: "Continue around the room and include every corner."
        case .lowTexture: "Point toward textured surfaces and visible edges."
        @unknown default: "Follow RoomPlan guidance and move slowly."
        }
    }
}

private extension ARCamera.TrackingState {
    var userFacingText: String {
        switch self {
        case .normal:
            "Tracking ready"
        case .notAvailable:
            "Tracking unavailable"
        case .limited(let reason):
            switch reason {
            case .initializing: "Tracking initializing · move the phone slowly"
            case .relocalizing: "Tracking relocalizing · revisit the scanned area"
            case .excessiveMotion: "Tracking limited · move more slowly"
            case .insufficientFeatures: "Tracking limited · point at textured walls and corners"
            @unknown default: "Tracking limited"
            }
        }
    }
}
