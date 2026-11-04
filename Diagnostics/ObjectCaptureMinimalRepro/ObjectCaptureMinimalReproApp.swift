import AVFoundation
import OSLog
import RealityKit
import SwiftUI

@main
struct ObjectCaptureMinimalReproApp: App {
    var body: some SwiftUI.Scene {
        WindowGroup {
            ReproView()
                .preferredColorScheme(.dark)
        }
    }
}

struct ReproView: View {
    @StateObject private var coordinator = ReproCoordinator()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let session = coordinator.session {
                ObjectCaptureView(session: session)
                    .ignoresSafeArea()
                    .onAppear {
                        coordinator.objectCaptureViewDidAppear(for: session)
                    }
                VStack {
                    statusPanel
                    Spacer()
                    controls
                }
                .padding(12)
            } else {
                VStack(spacing: 20) {
                    Text("Object Capture Minimal Repro")
                        .font(.title2.bold())
                    Text("One ObjectCaptureSession. No ARView, custom renderer, additional ARSession, reconstruction, storage repository, or production state machine.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    Button("Create Session", action: coordinator.createSession)
                        .buttonStyle(.borderedProminent)
                        .disabled(!ObjectCaptureSession.isSupported)
                }
                .padding(24)
            }
        }
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(coordinator.status)
                .font(.headline)
            Text("Framework: \(coordinator.frameworkState)")
                .font(.caption.monospaced())
            Text("Tracking: \(coordinator.trackingState)")
                .font(.caption.monospaced())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
        .allowsHitTesting(false)
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button("Detect", action: coordinator.startDetection)
                .buttonStyle(.borderedProminent)
                .disabled(!coordinator.canStartFromReady)
            Button("Freeform", action: coordinator.startFreeform)
                .buttonStyle(.bordered)
                .disabled(!coordinator.canStartFromReady)
            Button("Cancel", role: .cancel, action: coordinator.cancel)
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
    }
}

@MainActor
final class ReproCoordinator: ObservableObject {
    @Published private(set) var session: ObjectCaptureSession?
    @Published private(set) var status = "Create one session"
    @Published private(set) var frameworkState = "none"
    @Published private(set) var trackingState = "none"
    @Published private(set) var canStartFromReady = false

    private let logger = Logger(subsystem: "se.dugiselmanaj.lidarstudio2.objectcapture-repro", category: "MinimalRepro")
    private var tasks: [Task<Void, Never>] = []
    private var hasStarted = false
    private var operationInFlight = false

    func createSession() {
        guard session == nil else { return }
        logger.notice("REPRO_CREATE_SESSION")
        let newSession = ObjectCaptureSession()
        session = newSession
        observe(newSession)
        status = "View created; waiting for ObjectCaptureView.onAppear"
    }

    func objectCaptureViewDidAppear(for visibleSession: ObjectCaptureSession) {
        guard session === visibleSession, !hasStarted else { return }
        hasStarted = true
        logger.notice("REPRO_VIEW_APPEARED")
        Task { await startAfterAuthorization(visibleSession) }
    }

    func startDetection() {
        guard let session,
              session.state == .ready,
              !operationInFlight else {
            logger.notice("REPRO_DETECT_REJECTED state=\(self.frameworkState, privacy: .public)")
            return
        }
        operationInFlight = true
        canStartFromReady = false
        logger.notice("REPRO_DETECT_BEGIN tracking=\(self.trackingState, privacy: .public)")
        let started = session.startDetecting()
        logger.notice("REPRO_DETECT_RETURNED started=\(started, privacy: .public) state=\(String(describing: session.state), privacy: .public)")
        operationInFlight = started
        if !started {
            operationInFlight = false
            canStartFromReady = session.state == .ready
            status = "Detection returned false; session remains recoverable"
        }
    }

    func startFreeform() {
        guard let session,
              session.state == .ready,
              !operationInFlight else {
            logger.notice("REPRO_FREEFORM_REJECTED state=\(self.frameworkState, privacy: .public)")
            return
        }
        operationInFlight = true
        canStartFromReady = false
        logger.notice("REPRO_FREEFORM_BEGIN")
        session.startCapturing()
    }

    func cancel() {
        guard let session else { return }
        logger.notice("REPRO_CANCEL")
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        session.cancel()
        self.session = nil
        hasStarted = false
        operationInFlight = false
        canStartFromReady = false
        frameworkState = "cancelled"
        trackingState = "none"
        status = "Cancelled"
    }

    private func startAfterAuthorization(_ activeSession: ObjectCaptureSession) async {
        var authorization = AVCaptureDevice.authorizationStatus(for: .video)
        if authorization == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            authorization = granted ? .authorized : .denied
        }
        guard authorization == .authorized, session === activeSession else {
            status = "Camera permission denied"
            return
        }
        do {
            let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("MinimalReproImages", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            logger.notice("REPRO_SESSION_START")
            activeSession.start(imagesDirectory: directory)
            logger.notice("REPRO_SESSION_START_RETURNED")
            status = "Session started; waiting for Ready"
        } catch {
            logger.error("REPRO_START_FAILED \(error.localizedDescription, privacy: .public)")
            status = "Start failed: \(error.localizedDescription)"
        }
    }

    private func observe(_ observedSession: ObjectCaptureSession) {
        tasks = [
            Task { [weak self, weak observedSession] in
                guard let observedSession else { return }
                for await state in observedSession.stateUpdates {
                    guard !Task.isCancelled, self?.session === observedSession else { return }
                    self?.handle(state)
                }
            },
            Task { [weak self, weak observedSession] in
                guard let observedSession else { return }
                for await tracking in observedSession.cameraTrackingUpdates {
                    guard !Task.isCancelled, self?.session === observedSession else { return }
                    let value = String(describing: tracking)
                    self?.trackingState = value
                    self?.logger.notice("REPRO_TRACKING \(value, privacy: .public)")
                }
            }
        ]
    }

    private func handle(_ state: ObjectCaptureSession.CaptureState) {
        let value = String(describing: state)
        frameworkState = value
        logger.notice("REPRO_STATE \(value, privacy: .public)")
        switch state {
        case .ready:
            operationInFlight = false
            canStartFromReady = true
            status = "Ready"
        case .detecting:
            operationInFlight = false
            canStartFromReady = false
            status = "Detecting"
        case .capturing:
            operationInFlight = false
            canStartFromReady = false
            status = "Freeform capture running"
        case .failed(let error):
            operationInFlight = false
            canStartFromReady = false
            status = "Framework failed: \(error.localizedDescription)"
        default:
            break
        }
    }
}
