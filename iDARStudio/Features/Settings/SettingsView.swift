import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var library: ScanLibrary
    @Environment(\.openURL) private var openURL
    @AppStorage(OnboardingPreference.key) private var hasCompletedOnboarding = true
    @AppStorage(PhotoTargetPreference.key) private var preferredPhotoTarget = 0
    @State private var storageBreakdown: LocalStorageBreakdown?
    private let capabilities = DeviceCapabilityService.current()

    private let photoTargets = [0, 50, 75, 100, 150, 200]

    var body: some View {
        ZStack {
            StudioBackground()
            List {
                capturePreferences
                storage
                access
                hardwareAndPermissions
                privacyAndOwnership
                application
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Settings")
        .task { refreshStorage() }
        .refreshable { refreshStorage() }
    }

    private var capturePreferences: some View {
        Section("Object Capture") {
            Picker("Preferred photo target", selection: $preferredPhotoTarget) {
                Text("Off").tag(0)
                ForEach(photoTargets.dropFirst(), id: \.self) { target in
                    Text("\(target) photos").tag(target)
                }
            }
            .accessibilityHint("A personal guidance target. It does not automatically finish capture.")

            LabeledContent("Capture mode", value: "Choose while capturing")
            Text("The photo target is optional guidance, not an Apple-defined minimum. Automatic and manual capture can only be changed while the active Object Capture session reports that the control is available.")
                .font(.caption)
                .foregroundStyle(StudioTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var storage: some View {
        Section("Local Storage") {
            LabeledContent("Total managed data", value: formatted(storageBreakdown?.totalBytes))
            storageRow("Models", bytes: storageBreakdown?.modelsBytes, symbol: "cube.transparent")
            storageRow("Original photographs", bytes: storageBreakdown?.capturePhotographsBytes, symbol: "photo.stack")
            storageRow("Capture checkpoints", bytes: storageBreakdown?.captureCheckpointsBytes, symbol: "camera.metering.matrix")
            storageRow("Reconstruction intermediates", bytes: storageBreakdown?.reconstructionIntermediatesBytes, symbol: "square.3.layers.3d")
            storageRow("Previews", bytes: storageBreakdown?.previewsBytes, symbol: "photo")
            storageRow("Metadata", bytes: storageBreakdown?.metadataBytes, symbol: "doc.text")
            storageRow("Diagnostic datasets", bytes: storageBreakdown?.diagnosticDatasetsBytes, symbol: "waveform.path.ecg")
            if let other = storageBreakdown?.otherManagedDataBytes, other > 0 {
                storageRow("Other managed data", bytes: other, symbol: "questionmark.folder")
            }
            Text("Counts regular local files only. Symbolic links are excluded, and private filesystem paths are never displayed.")
                .font(.caption)
                .foregroundStyle(StudioTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var access: some View {
        Section("App Access") {
            NavigationLink(value: AppDestination.library) {
                Label("Scan Library", systemImage: "square.stack.3d.up")
            }
            NavigationLink {
                ObjectScanPreparationView()
            } label: {
                Label("Object Scan Preparation", systemImage: "checklist")
            }
            NavigationLink(value: AppDestination.environmentStudio) {
                Label("ARKit & RGB-D Diagnostics", systemImage: "waveform.path.ecg")
            }
            Text("Environment tools expose real diagnostic state. Known ARKit tracking and depth blockers remain open.")
                .font(.caption)
                .foregroundStyle(StudioTheme.secondaryText)
        }
    }

    private var hardwareAndPermissions: some View {
        Section("Hardware & Permissions") {
            statusRow("Camera", value: CameraPermission.current.title, available: CameraPermission.current == .authorized)
            statusRow("Object Capture", supported: capabilities.supportsObjectCapture)
            statusRow("On-device reconstruction", supported: capabilities.supportsOnDevicePhotogrammetry)
            statusRow("RoomPlan", supported: capabilities.supportsRoomPlan)
            statusRow("AR world tracking", supported: capabilities.supportsWorldTracking)
            statusRow("Scene depth", supported: capabilities.supportsSceneDepth)
            statusRow("LiDAR mesh", supported: capabilities.supportsLiDARMesh)
            if CameraPermission.current == .denied {
                Button("Open iOS Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                .accessibilityHint("Opens the system settings page for LiDARStudio.")
            }
            Text("Supported means the public API reports hardware capability. It does not mean every workflow has completed physical validation.")
                .font(.caption)
                .foregroundStyle(StudioTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var privacyAndOwnership: some View {
        Section("Privacy & Ownership") {
            Label("Local by default", systemImage: "lock.shield")
            Text("LiDARStudio does not upload scans automatically. Sharing and export occur only after an explicit user action.")
                .font(.caption)
                .foregroundStyle(StudioTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            LabeledContent("Product owner", value: "Dugi Selmanaj")
            Text("© 2026 Dugi Selmanaj. All rights reserved.")
                .font(.caption)
        }
    }

    private var application: some View {
        Section("Application") {
            LabeledContent("Version", value: appVersion)
            LabeledContent("Build", value: buildNumber)
            NavigationLink("About LiDARStudio", value: AppDestination.about)
            Button {
                hasCompletedOnboarding = false
            } label: {
                Label("Show Onboarding Again", systemImage: "sparkles.rectangle.stack")
                    .frame(minHeight: 44)
            }
            .accessibilityHint("Opens the introductory pages without deleting settings or scans.")
        }
    }

    private func storageRow(_ title: String, bytes: Int64?, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(StudioTheme.accent)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(title)
            Spacer(minLength: 8)
            Text(formatted(bytes))
                .foregroundStyle(StudioTheme.secondaryText)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private func formatted(_ bytes: Int64?) -> String {
        guard let bytes else { return "Unavailable" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
    }

    private func statusRow(_ title: String, supported: Bool) -> some View {
        statusRow(title, value: supported ? "Supported" : "Unavailable", available: supported)
    }

    private func statusRow(_ title: String, value: String, available: Bool) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 8)
            Text(value)
                .foregroundStyle(available ? StudioTheme.accent : StudioTheme.warning)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private func refreshStorage() {
        storageBreakdown = library.storageBreakdown()
    }
}
