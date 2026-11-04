import SwiftUI
import RealityKit
import OSLog

struct ObjectStudioView: View {
    @EnvironmentObject private var library: ScanLibrary
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var coordinator = ObjectCaptureCoordinator()
    @State private var showsHelp = false
    @State private var showsCaptureSettings = false
    @State private var showsFinishConfirmation = false
    @State private var framingGuideScale = 0.68
    @State private var scanName = "Object Scan"
    private let uiLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "LiDARStudio",
        category: "ObjectStudioUI"
    )

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
        .confirmationDialog(
            "Finish capture?",
            isPresented: $showsFinishConfirmation,
            titleVisibility: .visible
        ) {
            Button("Finish & Review") { coordinator.requestFinishCapture() }
            Button("Continue Capturing", role: .cancel) {}
        } message: {
            Text(finishConfirmationMessage)
        }
        .sheet(isPresented: $showsCaptureSettings) {
            captureSettings
        }
    }

    private func captureView(session: ObjectCaptureSession) -> some View {
        ZStack {
            ObjectCaptureView(session: session)
                .ignoresSafeArea()

            if coordinator.phase == .capturing {
                captureFramingGuide
                    .zIndex(0.5)
            }

            VStack(spacing: 12) {
                captureHeader
                Spacer()
                if let feedback = coordinator.detectionRecoveryMessage ?? coordinator.feedbackMessage {
                    Text(feedback)
                        .font(.footnote.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.64), in: RoundedRectangle(cornerRadius: 14))
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
                captureControls
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .zIndex(1)
        }
    }

    private var captureHeader: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(coordinator.progressStatus?.rawValue ?? "Object Studio")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(captureInstruction)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(2)
                if coordinator.phase == .capturing {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(coordinator.captureGuideStage.title)
                            if coordinator.currentPassCompleted {
                                Label("Pass complete", systemImage: "checkmark.circle.fill")
                            }
                        }
                        HStack(spacing: 8) {
                            Text("Captured \(coordinator.photoCount)")
                            if let target = coordinator.preferredPhotoTarget {
                                Text("Target \(target)")
                            }
                            Text("Maximum \(coordinator.maximumPhotoCount)")
                        }
                        .monospacedDigit()
                        if coordinator.currentPassCompleted {
                            Text("Apple reported this pass complete")
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(StudioTheme.accent)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                }
            }
            Spacer()
            Button("Help", systemImage: "questionmark.circle") {
                uiLogger.notice("UI_HELP_TAPPED")
                showsHelp.toggle()
            }
                .labelStyle(.iconOnly)
                .buttonStyle(.bordered)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityLabel("Capture help")
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background(.black.opacity(0.64), in: RoundedRectangle(cornerRadius: 16))
        .popover(isPresented: $showsHelp) {
            captureHelp
                .presentationCompactAdaptation(.sheet)
        }
    }

    private var captureControls: some View {
        captureControlContent
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.black.opacity(0.64))
        }
        .allowsHitTesting(CaptureOverlayInteractionPolicy.controlsAllowHitTesting)
    }

    @ViewBuilder
    private var captureControlContent: some View {
        if coordinator.phase == .readyForDetection {
            detectionReadyControls
        } else if coordinator.phase == .detecting {
            boundingBoxControls
        } else if coordinator.phase == .capturing {
            activeCaptureControls
        } else {
            HStack(spacing: 8) {
                cancelCaptureButton
                ProgressView().tint(StudioTheme.accent)
                Text("Saving photos…").font(.subheadline.weight(.semibold))
            }
        }
    }

    private var detectionReadyControls: some View {
        HStack(spacing: 8) {
            cancelCaptureButton
            Button {
                uiLogger.notice("UI_RETRY_TAPPED")
                coordinator.retryDetection()
            } label: {
                compactControlLabel("Retry", systemImage: "viewfinder")
            }
            .buttonStyle(.borderedProminent)
            .tint(StudioTheme.accent)
            .foregroundStyle(.black)
            .frame(minHeight: 44)
            .disabled(coordinator.isDetectionOperationPending)

            Button {
                uiLogger.notice("UI_SKIP_TAPPED")
                coordinator.startFreeformCapture()
            } label: {
                compactControlLabel("Free Scan", systemImage: "arrow.right")
            }
            .buttonStyle(.bordered)
            .frame(minHeight: 44)
            .disabled(coordinator.isDetectionOperationPending)
            .accessibilityHint("Starts Apple's freeform object capture without a selection box")
        }
    }

    private var boundingBoxControls: some View {
        HStack(spacing: 8) {
            cancelCaptureButton
            Button("Reset", systemImage: "arrow.counterclockwise", action: coordinator.resetBoundingBox)
                .buttonStyle(.bordered)
                .frame(minHeight: 44)
            Button("Use Box", systemImage: "checkmark", action: coordinator.confirmBoundingBox)
                .buttonStyle(.borderedProminent)
                .tint(StudioTheme.accent)
                .foregroundStyle(.black)
                .frame(minHeight: 44)
        }
    }

    private var activeCaptureControls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Toggle("Auto", isOn: Binding(
                    get: { coordinator.isAutoCaptureEnabled },
                    set: { coordinator.setAutoCaptureEnabled($0) }
                ))
                .toggleStyle(.button)
                .buttonStyle(.bordered)
                .disabled(!coordinator.canChangeAutoCapture)

                Button(action: coordinator.takePhoto) {
                    compactControlLabel("Manual Photo", systemImage: "camera.shutter.button")
                }
                .buttonStyle(.borderedProminent)
                .tint(StudioTheme.accent)
                .foregroundStyle(.black)
                .frame(minHeight: 44)
                .disabled(!coordinator.canTakePhoto)

                if coordinator.captureGuideStage != .extraAngles {
                    Button(action: coordinator.advanceCaptureGuide) {
                        compactControlLabel(
                            LocalizedStringKey(coordinator.captureGuideStage == .overview ? "Detail" : "Angles"),
                            systemImage: "arrow.right"
                        )
                    }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
                    .disabled(!coordinator.canAdvanceCaptureGuide)
                    .accessibilityLabel(coordinator.captureGuideActionTitle)
                }

                Button { showsCaptureSettings = true } label: {
                    Image(systemName: "slider.horizontal.3")
                        .frame(minWidth: 28, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Capture settings")
            }
            captureNavigationControls
        }
    }

    private var captureNavigationControls: some View {
        HStack(spacing: 8) {
            cancelCaptureButton
            Button {
                if coordinator.isCapturePaused {
                    coordinator.resumeCapture()
                } else {
                    coordinator.pauseCapture()
                }
            } label: {
                compactControlLabel(
                    LocalizedStringKey(coordinator.isCapturePaused ? "Resume" : "Pause"),
                    systemImage: coordinator.isCapturePaused ? "play.fill" : "pause.fill"
                )
            }
            .buttonStyle(.bordered)
            .frame(minHeight: 44)
            .disabled(coordinator.isCapturePaused ? !coordinator.canResumeCapture : !coordinator.canPauseCapture)

            Button { showsFinishConfirmation = true } label: {
                compactControlLabel("Finish & Review", systemImage: "checkmark")
            }
            .buttonStyle(.borderedProminent)
            .tint(StudioTheme.accent)
            .foregroundStyle(.black)
            .frame(minHeight: 44)
            .disabled(!coordinator.canFinishCapture)
        }
    }

    private var cancelCaptureButton: some View {
        Button(role: .cancel) {
            uiLogger.notice("UI_CANCEL_TAPPED")
            coordinator.cancel()
        } label: {
            compactControlLabel("Cancel", systemImage: "xmark")
        }
        .buttonStyle(.bordered)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityLabel("Cancel capture")
    }

    private func compactControlLabel(_ title: LocalizedStringKey, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var captureFramingGuide: some View {
        GeometryReader { proxy in
            let guideWidth = proxy.size.width * framingGuideScale
            let guideHeight = min(proxy.size.height * 0.48, guideWidth * 1.18)
            ZStack {
                RoundedRectangle(cornerRadius: 26)
                    .stroke(
                        StudioTheme.accent.opacity(0.82),
                        style: StrokeStyle(lineWidth: 1.5, dash: [10, 7])
                    )
                    .frame(width: guideWidth, height: guideHeight)
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(.white.opacity(0.9))
                Text("Visual framing guide")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.55), in: Capsule())
                    .offset(y: guideHeight / 2 + 18)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, proxy.safeAreaInsets.top + 72)
            .padding(.bottom, proxy.safeAreaInsets.bottom + 128)
        }
        .allowsHitTesting(CaptureOverlayInteractionPolicy.framingGuideAllowsHitTesting)
        .accessibilityHidden(true)
    }

    private var captureSettings: some View {
        NavigationStack {
            Form {
                Section("Photo guidance") {
                    Toggle("Preferred photo target", isOn: Binding(
                        get: { coordinator.preferredPhotoTarget != nil },
                        set: { enabled in
                            coordinator.setPreferredPhotoTarget(enabled ? min(100, targetMaximum) : nil)
                        }
                    ))
                    if let target = coordinator.preferredPhotoTarget {
                        Stepper(
                            "Target: \(target)",
                            value: Binding(
                                get: { target },
                                set: { coordinator.setPreferredPhotoTarget($0) }
                            ),
                            in: 1...targetMaximum,
                            step: min(5, targetMaximum)
                        )
                    }
                    LabeledContent("Captured", value: "\(coordinator.photoCount)")
                    LabeledContent("Framework maximum", value: "\(coordinator.maximumPhotoCount)")
                    Text("The preferred target is guidance only. Reaching it does not finish capture, and it is not an Apple-defined minimum.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("Framing guide") {
                    Slider(value: $framingGuideScale, in: 0.45...0.9) {
                        Text("Guide size")
                    }
                    Text("This overlay is only a visual aid. It is not a detected bounding box and does not measure depth or coverage.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Capture Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showsCaptureSettings = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var targetMaximum: Int {
        max(1, coordinator.maximumPhotoCount)
    }

    private var finishConfirmationMessage: String {
        if coordinator.photoCount == 0 {
            return "No captured images have been reported. You can finish, but processing will remain unavailable unless valid images are saved."
        }
        if let target = coordinator.preferredPhotoTarget,
           coordinator.photoCount < target {
            return "Captured \(coordinator.photoCount) of your preferred \(target) photos. Finishing now may produce an incomplete reconstruction. This target is guidance, not an Apple-defined minimum."
        }
        return "Finish with \(coordinator.photoCount) captured photos? Apple Object Capture will save the available images before Review opens."
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
                    Text("Review Photos")
                        .font(.title2.bold())
                    Text("Capture is complete. Review the original local photos, name the scan, then create the 3D model.")
                        .font(.subheadline)
                        .foregroundStyle(StudioTheme.secondaryText)
                }

                if let message = coordinator.reconstructionErrorMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(StudioTheme.warning)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .studioCard()
                }

                HStack {
                    Label("\(coordinator.reviewPhotoURLs.count) photos", systemImage: "photo.stack")
                    Spacer()
                    Label("Stored locally", systemImage: "lock.shield")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(StudioTheme.accent)
                .studioCard()

                captureStageSummary

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
                    Label("Create 3D Model", systemImage: "cube.fill")
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
                Text(coordinator.progressStatus?.rawValue ?? ScanProgressStatus.processingModel.rawValue)
                    .font(.title2.bold())
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
                Text(ScanProgressStatus.scanCompleted.rawValue)
                    .font(.title2.bold())
                Text("3D Model Saved")
                    .font(.headline)
                    .foregroundStyle(StudioTheme.accent)
                Text("The USDZ and original photographs are stored locally and will remain available after restart.")
                    .font(.subheadline)
                    .foregroundStyle(StudioTheme.secondaryText)
                    .multilineTextAlignment(.center)
            }

            modelFileCard(modelURL: modelURL)

            NavigationLink {
                USDZViewerView(modelURL: modelURL, title: coordinator.completedScan?.name ?? scanName)
            } label: {
                Label("View in 3D", systemImage: "cube.transparent")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(StudioTheme.accent)
            .foregroundStyle(.black)

            ShareLink(item: modelURL) {
                Label("Share / Save to Files", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            NavigationLink {
                ScanLibraryView()
            } label: {
                Label("Open My Scans", systemImage: "square.stack.3d.up")
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

    private func modelFileCard(modelURL: URL) -> some View {
        let scan = coordinator.completedScan
        let size = scan?.fileSizeBytes.map {
            ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
        } ?? "Unknown size"

        return VStack(alignment: .leading, spacing: 8) {
            Label(modelURL.lastPathComponent, systemImage: "doc.fill")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            HStack {
                Text("USDZ")
                Spacer()
                Text(size)
            }
            .font(.caption)
            .foregroundStyle(StudioTheme.secondaryText)
            Label("Stored locally on this iPhone", systemImage: "iphone.gen3")
                .font(.caption.weight(.semibold))
                .foregroundStyle(StudioTheme.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .studioCard()
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
        case .preparing:
            HStack { ProgressView(); Text(ScanProgressStatus.preparingCamera.rawValue) }
                .frame(maxWidth: .infinity, alignment: .leading)
                .studioCard()
        case .finishing:
            HStack { ProgressView(); Text(ScanProgressStatus.capturing.rawValue) }
                .frame(maxWidth: .infinity, alignment: .leading)
                .studioCard()
        case .permissionRequired:
            Label("Camera access is required. Enable it in Settings, then try again.", systemImage: "camera.fill")
                .foregroundStyle(StudioTheme.warning)
                .studioCard()
        case .unsupported(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(StudioTheme.warning)
                .studioCard()
        case .failed(let message):
            VStack(alignment: .leading, spacing: 6) {
                Label(ScanProgressStatus.scanFailed.rawValue, systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                Text(message).font(.subheadline)
            }
            .foregroundStyle(StudioTheme.warning)
            .frame(maxWidth: .infinity, alignment: .leading)
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
        case .readyForDetection: "Aim at the surface beneath the object"
        case .detecting: "Adjust the box around the object"
        case .capturing:
            coordinator.isCapturePaused ? "Capture paused" : coordinator.captureGuideStage.guidance
        case .finishing: "Saving photos…"
        default: "Object Capture"
        }
    }

    private var captureStageSummary: some View {
        HStack(spacing: 8) {
            ForEach([ObjectCaptureGuideStage.overview, .detail, .extraAngles, .review], id: \.rawValue) { stage in
                Text(stage.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(stage.rawValue <= coordinator.captureGuideStage.rawValue ? .black : StudioTheme.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        stage.rawValue <= coordinator.captureGuideStage.rawValue
                            ? StudioTheme.accent
                            : StudioTheme.elevatedSurface,
                        in: Capsule()
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Capture stages: Overview, Detail, Extra Angles, Review")
    }

    private var captureHelp: some View {
        NavigationStack {
            List {
                Label("Keep the object still throughout capture.", systemImage: "hand.raised")
                Label("Use soft, even light and avoid reflections.", systemImage: "light.max")
                Label("Move slowly through low, middle, and high angles.", systemImage: "arrow.triangle.2.circlepath")
                Label("Only the framework photo count is shown; coverage is not estimated.", systemImage: "checkmark.shield")
                Label("Pause and resume keep the same capture session and saved-photo folder.", systemImage: "pause.circle")
                Label("Finish & Review is always your explicit choice.", systemImage: "checkmark.circle")
            }
            .navigationTitle("Capture Help")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}
