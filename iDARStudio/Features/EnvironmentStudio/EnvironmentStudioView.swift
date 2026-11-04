import SwiftUI

struct EnvironmentStudioView: View {
    private let capabilities = DeviceCapabilityService.current()
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var diagnostic = LiDARDiagnosticCoordinator()
    @StateObject private var recorder = RGBDRecordingCoordinator()
    @State private var selectedStage: LiDARDiagnosticStage = .basic

    var body: some View {
        ZStack {
            StudioBackground()
            if recorder.isActive {
                liveRecording
            } else if diagnostic.isPresented {
                liveDiagnostic
            } else {
                diagnosticLanding
            }
        }
        .navigationTitle(recorder.isActive ? "RGB-D Recording" : "LiDAR Diagnostic")
        .navigationBarTitleDisplayMode(diagnostic.isPresented || recorder.isActive ? .inline : .large)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                diagnostic.stop(reason: .backgrounded)
                recorder.stopForBackground()
            }
        }
        .onDisappear {
            diagnostic.stop(reason: .cancelled)
            recorder.stopForBackground()
        }
    }

    private var diagnosticLanding: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "sensor.tag.radiowaves.forward")
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(StudioTheme.accent)
                    .accessibilityHidden(true)
                Text("Isolate ordinary ARKit frames, scene depth, and scene mesh without saving camera data.")
                    .font(.title3)
                    .foregroundStyle(StudioTheme.secondaryText)
                VStack(alignment: .leading, spacing: 12) {
                    Label("RGB-D Recording Proof of Concept", systemImage: "record.circle")
                        .font(.headline)
                        .foregroundStyle(StudioTheme.accent)
                    Text("Records genuine ARKit camera frames, scene depth, confidence, intrinsics, poses, and timestamps to a separate local dataset.")
                        .font(.subheadline)
                        .foregroundStyle(StudioTheme.secondaryText)
                    Text("Bounded to 180 samples at up to 2 fps. No mesh and no competing camera session.")
                        .font(.footnote)
                        .foregroundStyle(StudioTheme.secondaryText)
                    Button {
                        Task { await recorder.start() }
                    } label: {
                        Label("Start RGB-D Recording", systemImage: "record.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(StudioTheme.accent)
                    .foregroundStyle(.black)
                    .controlSize(.large)
                    .disabled(!capabilities.supportsSceneDepth || diagnostic.isPresented)
                }
                .studioCard()
                VStack(alignment: .leading, spacing: 12) {
                    capabilityRow("AR world tracking", supported: capabilities.supportsWorldTracking)
                    capabilityRow("Scene depth semantics", supported: capabilities.supportsSceneDepth)
                    capabilityRow("Mesh reconstruction", supported: capabilities.supportsLiDARMesh)
                }.studioCard()
                VStack(alignment: .leading, spacing: 12) {
                    Text("Diagnostic stage").font(.headline)
                    Picker("Diagnostic stage", selection: $selectedStage) {
                        ForEach(LiDARDiagnosticStage.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented)
                    Text(selectedStage.explanation)
                        .font(.footnote)
                        .foregroundStyle(StudioTheme.secondaryText)
                }.studioCard()
                if let message = diagnostic.errorMessage {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(ScanProgressStatus.scanFailed.rawValue, systemImage: "exclamationmark.triangle.fill")
                            .font(.headline)
                        Text(message).font(.subheadline)
                    }
                        .foregroundStyle(StudioTheme.warning)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .studioCard()
                }
                if let message = recorder.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(StudioTheme.warning)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .studioCard()
                }
                if let url = recorder.completedDatasetURL {
                    completedDataset(url)
                }
                Button {
                    diagnostic.logStartTapped(stage: selectedStage)
                    Task { await diagnostic.prepare(stage: selectedStage) }
                } label: {
                    Label("Start \(selectedStage.title) Diagnostic", systemImage: "viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(StudioTheme.accent)
                .foregroundStyle(.black)
                .controlSize(.large)
                .disabled(!canStartSelectedStage || diagnostic.isPreparing)
                Text("Run Basic first, then stop it before starting Depth or Mesh. Only one ARSession is retained at a time.")
                    .font(.footnote)
                    .foregroundStyle(StudioTheme.secondaryText)
                    .studioCard()
            }.padding(20)
        }
    }

    private var liveRecording: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label(recorder.statusText, systemImage: recorder.isFinalizing ? "externaldrive.badge.timemachine" : "waveform.path.ecg")
                    .font(.headline)
                    .foregroundStyle(StudioTheme.accent)
                VStack(alignment: .leading, spacing: 10) {
                    Text(recorder.trackingState)
                    metricRow("ARKit callbacks", recorder.snapshot.sessionCallbacks)
                    metricRow("Samples accepted", recorder.snapshot.framesAccepted)
                    metricRow("RGB frames written", recorder.snapshot.framesWritten)
                    metricRow("Depth frames written", recorder.snapshot.depthFramesWritten)
                    metricRow("Confidence maps", recorder.snapshot.confidenceFramesWritten)
                    metricRow("Dropped / intentionally skipped", recorder.snapshot.droppedFrames)
                    metricRow("Pending writes", recorder.snapshot.pendingWrites)
                }
                .font(.subheadline.weight(.semibold))
                .studioCard()

                Text("Keep the phone moving slowly. Counts are real ARKit callbacks and files; no progress or sensor readings are simulated.")
                    .font(.footnote)
                    .foregroundStyle(StudioTheme.secondaryText)
                    .studioCard()

                if let message = recorder.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(StudioTheme.warning)
                        .studioCard()
                }

                Button(role: .cancel) {
                    recorder.stop()
                } label: {
                    Label(recorder.isFinalizing ? "Finalizing…" : "Stop and Validate", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(.black.opacity(0.72))
                .disabled(!recorder.isRecording)
            }
            .padding(20)
        }
    }

    private func completedDataset(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Local RGB-D dataset", systemImage: "externaldrive.fill.badge.checkmark")
                .font(.headline)
                .foregroundStyle(StudioTheme.accent)
            Text(url.lastPathComponent)
                .font(.caption.monospaced())
                .textSelection(.enabled)
            if let validation = recorder.validationReport {
                Text(validation.isValid
                     ? "Validated: \(validation.framesChecked) synchronized frame sets"
                     : "Validation failed: \(validation.errors.count) issue(s)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(validation.isValid ? StudioTheme.accent : StudioTheme.warning)
            }
            HStack {
                Button("Validate Again") { recorder.validateCompletedDataset() }
                    .buttonStyle(.bordered)
                ShareLink(item: url) {
                    Label("Export Dataset", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
                .tint(StudioTheme.accent)
                .foregroundStyle(.black)
            }
        }
        .studioCard()
    }

    private func metricRow(_ label: String, _ value: Int) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value, format: .number).monospacedDigit()
        }
    }

    private var canStartSelectedStage: Bool {
        guard capabilities.supportsWorldTracking else { return false }
        switch selectedStage {
        case .basic: return true
        case .depth: return capabilities.supportsSceneDepth
        case .full: return capabilities.supportsSceneDepth && capabilities.supportsLiDARMesh
        }
    }

    private var liveDiagnostic: some View {
        VStack(spacing: 16) {
            liveMetrics
            Text("The Metal camera preview is disabled for this isolation run. ARKit sensor callbacks continue on a dedicated queue.")
                .font(.footnote)
                .foregroundStyle(StudioTheme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .studioCard()
            Spacer()
            Button(role: .cancel) {
                diagnostic.stop()
            } label: {
                Label("Stop Diagnostic", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity).frame(minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(.black.opacity(0.72))
        }.padding(20)
    }

    private var liveMetrics: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let status = diagnostic.progressStatus {
                Label(status.rawValue, systemImage: "wave.3.right.circle.fill")
                    .foregroundStyle(StudioTheme.accent)
            }
            Text(diagnostic.currentStage?.title ?? "Diagnostic").font(.headline)
            Label(diagnostic.depthStatus, systemImage: diagnostic.isDepthAvailable ? "checkmark.circle.fill" : "clock")
            Text("Session callbacks: \(diagnostic.sessionUpdateCallbackCount)")
            Text("Frames: \(diagnostic.frameCount) · Depth: \(diagnostic.depthFrameCount)")
            Text("Normal tracking frames: \(diagnostic.normalTrackingFrameCount)")
            Label(diagnostic.trackingStatus, systemImage: "location.viewfinder")
            Label("Mesh anchors: \(diagnostic.meshAnchorCount)", systemImage: "square.3.layers.3d")
            Text("Mesh events +\(diagnostic.meshAnchorsAdded)  ↻\(diagnostic.meshAnchorsUpdated)  −\(diagnostic.meshAnchorsRemoved)")
            if let message = diagnostic.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(StudioTheme.warning)
            }
        }
        .font(.subheadline.weight(.semibold))
        .frame(maxWidth: .infinity, alignment: .leading)
        .studioCard()
    }

    private func capabilityRow(_ title: String, supported: Bool) -> some View {
        Label(supported ? "\(title): supported" : "\(title): unavailable", systemImage: supported ? "checkmark.circle.fill" : "xmark.circle.fill")
            .foregroundStyle(supported ? StudioTheme.accent : StudioTheme.warning)
    }
}
