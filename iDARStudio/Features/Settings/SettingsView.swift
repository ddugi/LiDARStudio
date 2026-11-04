import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var library: ScanLibrary
    @Environment(\.openURL) private var openURL
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = true
    @State private var storageBytes: Int64?
    private let capabilities = DeviceCapabilityService.current()

    var body: some View {
        ZStack {
            StudioBackground()
            List {
                Section("Storage") {
                    LabeledContent("Local scans", value: "\(library.scans.count)")
                    LabeledContent("Scan library data", value: storageDescription)
                    Text("Includes local scan metadata, models, capture photographs, and previews. Separate RGB-D diagnostic datasets are not included in this value.")
                        .font(.caption).foregroundStyle(StudioTheme.secondaryText)
                }
                Section("Hardware & Permissions") {
                    statusRow("Camera", value: CameraPermission.current.title, available: CameraPermission.current == .authorized)
                    statusRow("Object Capture", supported: capabilities.supportsObjectCapture)
                    statusRow("RoomPlan", supported: capabilities.supportsRoomPlan)
                    statusRow("Scene depth", supported: capabilities.supportsSceneDepth)
                    statusRow("LiDAR mesh", supported: capabilities.supportsLiDARMesh)
                    if CameraPermission.current == .denied {
                        Button("Open iOS Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                    }
                }
                Section("Diagnostics") {
                    NavigationLink(value: AppDestination.environmentStudio) {
                        Label("ARKit & RGB-D Diagnostics", systemImage: "waveform.path.ecg")
                    }
                    Text("Diagnostics use real public ARKit readings. Known tracking and depth blockers remain documented.")
                        .font(.caption).foregroundStyle(StudioTheme.secondaryText)
                }
                Section("Privacy & Ownership") {
                    Label("Local by default", systemImage: "lock.shield")
                    Text("Sharing and export occur only after an explicit action. LiDARStudio does not upload scans automatically.")
                        .font(.caption).foregroundStyle(StudioTheme.secondaryText)
                    Text("© 2026 Dugi Selmanaj. All rights reserved.").font(.caption)
                }
                Section("Application") {
                    LabeledContent("Version", value: appVersion)
                    LabeledContent("Build", value: buildNumber)
                    NavigationLink("About LiDARStudio", value: AppDestination.about)
                    Button("Show Onboarding Again") { hasCompletedOnboarding = false }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Settings")
        .task { storageBytes = library.storageUsageBytes() }
    }

    private var storageDescription: String {
        guard let storageBytes else { return "Unavailable" }
        return ByteCountFormatter.string(fromByteCount: storageBytes, countStyle: .file)
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
            Spacer()
            Text(value).foregroundStyle(available ? StudioTheme.accent : StudioTheme.warning)
        }
        .accessibilityElement(children: .combine)
    }
}
