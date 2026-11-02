import SwiftUI
import RealityKit

struct ObjectStudioView: View {
    @EnvironmentObject private var library: ScanLibrary
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var coordinator = ObjectCaptureCoordinator()
    @State private var showsHelp = false
    @State private var scanName = "Object Scan"

    var body: some View {
        ZStack {
            StudioBackground()
            if let session = coordinator.session, coordinator.phase.isCaptureSessionActive {
                captureView(session: session)
            } else if coordinator.phase == .reviewing {
                reviewView
            } else if coordinator.phase == .reconstructing {
                reconstructionView
            } else if coordinator.phase == .completed, let modelURL = coordinator.modelURL {
                completedView(modelURL: modelURL)
            } else {
                landingView
            }
        }
        .navigationTitle("Object Studio")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active { coordinator.handleBackgrounding() }
        }
        .onDisappear { coordinator.handleViewDisappearance() }
        .onChange(of: coordinator.completedScan) { _, scan in
            guard let scan else { return }
            library.upsert(scan)
        }
    }

    private func captureView(session: ObjectCaptureSession) -> some View {
        ObjectCaptureView(session: session) {
            VStack(spacing: 12) {
                captureHeader
                Spacer()
                if let feedback = coordinator.feedbackMessage {
                    Text(feedback)
                        .font(.subheadline.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.72), in: Capsule())
                        .transition(.opacity)
                }
                captureControls
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
        .ignoresSafeArea()
    }

    private var captureHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(captureInstruction)
                    .font(.headline)
                if coordinator.phase == .capturing {
                    Text("\(coordinator.photoCount) photos")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(StudioTheme.accent)
                }
            }
            Spacer()
            Button("Help", systemImage: "questionmark.circle") { showsHelp.toggle() }
                .labelStyle(.iconOnly)
                .buttonStyle(.bordered)
                .accessibilityLabel("Capture help")
        }
        .padding(14)
        .background(.black.opacity(0.70), in: RoundedRectangle(cornerRadius: 18))
        .padding(.top, 54)
        .popover(isPresented: $showsHelp) {
            captureHelp
                .presentationCompactAdaptation(.sheet)
        }
    }

    @ViewBuilder
    private var captureControls: some View {
        HStack(spacing: 18) {
            Button(role: .cancel, action: coordinator.cancel) {
                Image(systemName: "xmark")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Cancel capture")

            if coordinator.phase == .detecting {
                Button("Reset", systemImage: "arrow.counterclockwise", action: coordinator.resetBoundingBox)
                    .buttonStyle(.bordered)
                Button("Use Box", systemImage: "checkmark", action: coordinator.confirmBoundingBox)
                    .buttonStyle(.borderedProminent)
                    .tint(StudioTheme.accent)
                    .foregroundStyle(.black)
            } else if coordinator.phase == .capturing {
                Button(action: coordinator.takePhoto) {
                    ZStack {
                        Circle().stroke(.white.opacity(0.9), lineWidth: 3)
                        Circle().fill(StudioTheme.accent).padding(6)
                    }
                    .frame(width: 62, height: 62)
                }
                .disabled(!coordinator.canTakePhoto)
                .accessibilityLabel("Take photo")
                .accessibilityHint(coordinator.canTakePhoto ? "Captures the current angle" : "Wait until the camera is ready")

                Button("Finish", systemImage: "checkmark", action: coordinator.finishCapture)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.bordered)
                    .disabled(coordinator.photoCount == 0)
                    .accessibilityLabel("Finish photography")
            } else {
                ProgressView().tint(StudioTheme.accent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.black.opacity(0.72), in: Capsule())
    }

    private var landingView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "cube.transparent")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(StudioTheme.accent)
                    .accessibilityHidden(true)
                Text("High-detail photography guided by Apple Object Capture.")
                    .font(.title2.bold())
                capabilityCard
                statusCard
                if canStart {
                    Button {
                        Task { await coordinator.start() }
                    } label: {
                        Label("Start Object Capture", systemImage: "camera.viewfinder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(StudioTheme.accent)
                    .foregroundStyle(.black)
                    .controlSize(.large)
                }
                Text("Use a stationary object with diffuse, even light. Photographs remain on this device by default.")
                    .font(.footnote)
                    .foregroundStyle(StudioTheme.secondaryText)
                    .studioCard()
            }
            .padding(20)
        }
    }

    private var reviewView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Review photographs")
                        .font(.title2.bold())
                    Text("These are the original local files Object Capture produced. Remove glare or blurred angles by starting a new capture before reconstruction.")
                        .font(.subheadline)
                        .foregroundStyle(StudioTheme.secondaryText)
                }

                HStack {
                    Label("\(coordinator.reviewPhotoURLs.count) photos", systemImage: "photo.stack")
                    Spacer()
                    Label("Stored locally", systemImage: "lock.shield")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(StudioTheme.accent)
                .studioCard()

                TextField("Scan name", text: $scanName)
                    .textInputAutocapitalization(.words)
                    .padding(14)
                    .background(StudioTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityLabel("Scan name")

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                    ForEach(coordinator.reviewPhotoURLs, id: \.self) { url in
                        LocalPhotoThumbnail(url: url)
                        .frame(minHeight: 112)
                        .background(StudioTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .accessibilityLabel("Captured photograph \(url.deletingPathExtension().lastPathComponent)")
                    }
                }

                Button {
                    coordinator.reset()
                    Task { await coordinator.start() }
                } label: {
                    Label("Capture Again", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button { coordinator.startReconstruction(name: scanName) } label: {
                    Label("Reconstruct Textured Model", systemImage: "cube.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(StudioTheme.accent)
                .foregroundStyle(.black)
                .disabled(!coordinator.photogrammetrySupported || coordinator.reviewPhotoURLs.isEmpty)
                .accessibilityHint("Uses Apple's supported on-device photogrammetry")
            }
            .padding(20)
        }
    }

    private var reconstructionView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "cube.fill")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(StudioTheme.accent)
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text(coordinator.reconstructionStage)
                    .font(.title3.bold())
                Text("\(Int(coordinator.reconstructionProgress * 100))%")
                    .font(.title.monospacedDigit().bold())
                    .foregroundStyle(StudioTheme.accent)
                if let remaining = coordinator.estimatedRemainingTime {
                    Text("About \(Duration.seconds(remaining).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))) remaining")
                        .font(.subheadline)
                        .foregroundStyle(StudioTheme.secondaryText)
                }
            }
            ProgressView(value: coordinator.reconstructionProgress)
                .tint(StudioTheme.accent)
                .accessibilityLabel(coordinator.reconstructionStage)
                .accessibilityValue("\(Int(coordinator.reconstructionProgress * 100)) percent")
            if coordinator.invalidPhotoCount > 0 {
                Text("Apple Photogrammetry skipped \(coordinator.invalidPhotoCount) unusable photographs.")
                    .font(.footnote)
                    .foregroundStyle(StudioTheme.warning)
            }
            Button("Cancel Reconstruction", role: .cancel, action: coordinator.cancelReconstruction)
                .buttonStyle(.bordered)
            Spacer()
        }
        .padding(28)
    }

    private func completedView(modelURL: URL) -> some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(StudioTheme.accent)
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text("Textured model saved")
                    .font(.title2.bold())
                Text("The USDZ and original photographs are stored locally and will remain available after restart.")
                    .font(.subheadline)
                    .foregroundStyle(StudioTheme.secondaryText)
                    .multilineTextAlignment(.center)
            }
            NavigationLink {
                USDZViewerView(modelURL: modelURL, title: coordinator.completedScan?.name ?? scanName)
            } label: {
                Label("Open 3D Model", systemImage: "cube.transparent")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(StudioTheme.accent)
            .foregroundStyle(.black)

            ShareLink(item: modelURL) {
                Label("Share USDZ", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button("Scan Another Object") { coordinator.reset() }
                .buttonStyle(.plain)
                .foregroundStyle(StudioTheme.secondaryText)
            Spacer()
        }
        .padding(24)
    }

    private var capabilityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(coordinator.objectCaptureSupported ? "Guided capture supported" : "Guided capture unavailable",
                  systemImage: coordinator.objectCaptureSupported ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            Label(coordinator.photogrammetrySupported ? "On-device reconstruction supported" : "On-device reconstruction unavailable",
                  systemImage: coordinator.photogrammetrySupported ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
        }
        .foregroundStyle(coordinator.objectCaptureSupported ? StudioTheme.accent : StudioTheme.warning)
        .frame(maxWidth: .infinity, alignment: .leading)
        .studioCard()
    }

    @ViewBuilder
    private var statusCard: some View {
        switch coordinator.phase {
        case .preparing, .finishing:
            HStack { ProgressView(); Text("Preparing Object Capture…") }
                .frame(maxWidth: .infinity, alignment: .leading)
                .studioCard()
        case .permissionRequired:
            Label("Camera access is required. Enable it in Settings, then try again.", systemImage: "camera.fill")
                .foregroundStyle(StudioTheme.warning)
                .studioCard()
        case .unsupported(let message), .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(StudioTheme.warning)
                .studioCard()
        case .cancelled:
            Label("Capture cancelled. Camera resources were released; saved photos remain local.", systemImage: "xmark.circle")
                .studioCard()
        case .reviewing:
            EmptyView()
        default:
            EmptyView()
        }
    }

    private var canStart: Bool {
        coordinator.objectCaptureSupported && !coordinator.phase.isCaptureSessionActive
    }

    private var captureInstruction: String {
        switch coordinator.phase {
        case .preparing: "Preparing camera…"
        case .detecting: "Adjust the box to fit only the object, then confirm."
        case .capturing: "Move slowly around the object and photograph new angles."
        case .finishing: "Saving photographs…"
        default: "Object Capture"
        }
    }

    private var captureHelp: some View {
        NavigationStack {
            List {
                Label("Keep the object still throughout capture.", systemImage: "hand.raised")
                Label("Use soft, even light and avoid reflections.", systemImage: "light.max")
                Label("Move slowly through low, middle, and high angles.", systemImage: "arrow.triangle.2.circlepath")
                Label("Only the framework photo count is shown; coverage is not estimated.", systemImage: "checkmark.shield")
            }
            .navigationTitle("Capture Help")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}
