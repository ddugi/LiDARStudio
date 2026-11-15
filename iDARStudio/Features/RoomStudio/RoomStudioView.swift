import RoomPlan
import SwiftUI

struct RoomStudioView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var library: ScanLibrary
    @StateObject private var coordinator = RoomCaptureCoordinator()

    private let capabilities = DeviceCapabilityService.current()

    var body: some View {
        ZStack {
            StudioBackground()

            switch coordinator.lifecycle.phase {
            case .idle, .ready, .cancelled:
                preparationView
            case .starting, .capturing, .stopping, .processing:
                activeRoomView
            case .saving:
                progressView
            case .review, .saved:
                reviewView
            case .failed:
                failureView
            }
        }
        .navigationTitle(coordinator.lifecycle.keepsCaptureViewMounted ? "" : "Room Studio")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(coordinator.lifecycle.keepsCaptureViewMounted ? .hidden : .visible, for: .navigationBar)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { coordinator.cancel() }
        }
        .onDisappear { coordinator.cancel() }
        .onChange(of: coordinator.savedScanID) { _, scanID in
            if scanID != nil { library.reload() }
        }
    }

    private var preparationView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "square.split.bottomrightquarter")
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(StudioTheme.accent)
                    .accessibilityHidden(true)

                Text("Scan walls, doors, windows and recognized furniture with Apple's RoomPlan guidance.")
                    .font(.title3)
                    .foregroundStyle(StudioTheme.secondaryText)

                readinessCard

                VStack(alignment: .leading, spacing: 12) {
                    Label("Walk slowly around the room", systemImage: "figure.walk")
                    Label("Point at every wall and corner", systemImage: "viewfinder")
                    Label("Keep doorways and furniture visible", systemImage: "door.left.hand.open")
                    Label("Use even lighting", systemImage: "lightbulb")
                }
                .font(.subheadline)
                .studioCard()

                Button {
                    coordinator.startTapped()
                } label: {
                    Label(startButtonTitle, systemImage: "camera.viewfinder")
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(StudioTheme.accent)
                .foregroundStyle(.black)
                .disabled(!capabilities.supportsRoomPlan || CameraPermission.current == .denied)
                .accessibilityHint("Starts one RoomPlan camera session.")
            }
            .padding(20)
        }
    }

    private var activeRoomView: some View {
        ZStack {
            RoomCaptureContainer(coordinator: coordinator)
                .ignoresSafeArea()

            if coordinator.lifecycle.phase == .processing {
                Color.black.opacity(0.72).ignoresSafeArea()
                VStack(spacing: 18) {
                    ProgressView().controlSize(.large).tint(StudioTheme.accent)
                    Text("Processing room").font(.title2.bold())
                    Text("RoomPlan is preparing the captured geometry for review.")
                        .foregroundStyle(.white.opacity(0.82))
                        .multilineTextAlignment(.center)
                }
                .padding(28)
            } else {
                captureControls
            }
        }
    }

    private var captureControls: some View {
        VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(coordinator.lifecycle.phase.title)
                            .font(.headline)
                        Text(coordinator.instructionText)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.82))
                    }
                    Spacer(minLength: 12)
                }
                .padding(14)
                .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 18))

                Spacer()

                HStack(spacing: 12) {
                    Button(role: .cancel) { coordinator.cancel() } label: {
                        Label("Cancel", systemImage: "xmark").frame(minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)

                    Button { coordinator.finishCapture() } label: {
                        Label("Stop & Review", systemImage: "checkmark")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(StudioTheme.accent)
                    .foregroundStyle(.black)
                    .disabled(coordinator.lifecycle.phase != .capturing)
                }
                .padding(14)
                .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 22))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var progressView: some View {
        VStack(spacing: 18) {
            ProgressView().controlSize(.large).tint(StudioTheme.accent)
            Text(coordinator.lifecycle.phase.title).font(.title2.bold())
            Text(coordinator.lifecycle.phase == .saving
                 ? "The validated RoomPlan model is being saved locally."
                 : "RoomPlan is processing the captured room geometry.")
                .foregroundStyle(StudioTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .studioCard()
        .padding(20)
    }

    private var reviewView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(coordinator.lifecycle.phase == .saved ? "Room Saved" : "Review Room")
                    .font(.largeTitle.bold())

                if let summary = coordinator.roomSummary {
                    VStack(spacing: 12) {
                        summaryRow("Walls", value: summary.walls)
                        summaryRow("Doors", value: summary.doors)
                        summaryRow("Windows", value: summary.windows)
                        summaryRow("Objects", value: summary.objects)
                    }
                    .studioCard()
                }

                Text(coordinator.lifecycle.phase == .saved
                     ? "The USDZ was validated and added to My Scans."
                     : "These counts come directly from RoomPlan. Save only if the room looks complete.")
                    .font(.subheadline)
                    .foregroundStyle(StudioTheme.secondaryText)

                if coordinator.lifecycle.phase == .review {
                    Button { coordinator.saveToLibrary() } label: {
                        Label("Save Room to My Scans", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(StudioTheme.accent)
                    .foregroundStyle(.black)
                }

                Button { coordinator.reset() } label: {
                    Text("Scan Another Room").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
            .padding(20)
        }
    }

    private var failureView: some View {
        ContentUnavailableView {
            Label("Room Scan Failed", systemImage: "exclamationmark.triangle")
        } description: {
            Text(coordinator.errorMessage ?? "RoomPlan could not complete this scan.")
        } actions: {
            Button("Try Again") { coordinator.reset() }
                .buttonStyle(.borderedProminent)
                .tint(StudioTheme.accent)
        }
    }

    private var readinessCard: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: readinessIcon)
                .font(.title2)
                .foregroundStyle(capabilities.supportsRoomPlan ? StudioTheme.accent : StudioTheme.warning)
            VStack(alignment: .leading, spacing: 5) {
                Text(capabilities.supportsRoomPlan ? "RoomPlan available" : "RoomPlan unavailable")
                    .font(.headline)
                Text(readinessMessage)
                    .font(.subheadline)
                    .foregroundStyle(StudioTheme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .studioCard()
    }

    private var startButtonTitle: String {
        CameraPermission.current == .notDetermined ? "Allow Camera & Start" : "Start Room Scan"
    }

    private var readinessIcon: String {
        capabilities.supportsRoomPlan ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }

    private var readinessMessage: String {
        guard capabilities.supportsRoomPlan else {
            return "RoomPlan requires a supported LiDAR-equipped iPhone or iPad."
        }
        switch CameraPermission.current {
        case .authorized: return "Ready to start a real RoomPlan capture."
        case .notDetermined: return "Camera access is requested only when you start."
        case .denied: return "Enable camera access in Settings before scanning."
        }
    }

    private func summaryRow(_ label: String, value: Int) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value.formatted()).foregroundStyle(StudioTheme.accent)
        }
        .font(.headline)
    }
}
