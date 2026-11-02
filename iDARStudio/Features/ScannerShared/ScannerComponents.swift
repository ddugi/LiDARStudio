import SwiftUI

enum ScannerReadiness: Equatable {
    case ready(String)
    case unavailable(String)
    case permissionRequired(String)

    var title: String {
        switch self {
        case .ready: "Ready for capture"
        case .unavailable: "Hardware unavailable"
        case .permissionRequired: "Camera access required"
        }
    }

    var message: String {
        switch self {
        case .ready(let message), .unavailable(let message), .permissionRequired(let message): message
        }
    }

    var icon: String {
        switch self {
        case .ready: "checkmark.circle.fill"
        case .unavailable: "exclamationmark.triangle.fill"
        case .permissionRequired: "camera.fill"
        }
    }

    var color: Color {
        switch self {
        case .ready: StudioTheme.accent
        case .unavailable: StudioTheme.warning
        case .permissionRequired: .cyan
        }
    }
}

struct ScannerFoundationView: View {
    let title: String
    let description: String
    let systemImage: String
    let hardwareSupported: Bool
    let unavailableMessage: String

    @State private var permission = CameraPermission.current

    private var readiness: ScannerReadiness {
        guard hardwareSupported else { return .unavailable(unavailableMessage) }
        switch permission {
        case .authorized:
            return .ready("This studio is supported. Capture integration will be delivered and device-verified in a later sprint.")
        case .notDetermined:
            return .permissionRequired("Allow camera access before starting a scan.")
        case .denied:
            return .permissionRequired("Camera access is disabled. Enable it in Settings to use this studio.")
        }
    }

    var body: some View {
        ZStack {
            StudioBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: systemImage)
                        .font(.system(size: 42, weight: .light))
                        .foregroundStyle(StudioTheme.accent)
                        .accessibilityHidden(true)
                    Text(description)
                        .font(.title3)
                        .foregroundStyle(StudioTheme.secondaryText)
                    readinessCard
                    ScanControlBar(isEnabled: false)
                    Text("Sprint 1 provides capability checks, permissions, navigation, controls, and local storage. It does not start a camera or scanning session.")
                        .font(.footnote)
                        .foregroundStyle(StudioTheme.secondaryText)
                        .studioCard()
                }
                .padding(20)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .task { permission = CameraPermission.current }
    }

    private var readinessCard: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: readiness.icon)
                .font(.title2)
                .foregroundStyle(readiness.color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(readiness.title).font(.headline)
                Text(readiness.message)
                    .font(.subheadline)
                    .foregroundStyle(StudioTheme.secondaryText)
                if hardwareSupported && permission == .notDetermined {
                    Button("Allow Camera") {
                        Task { permission = await CameraPermission.request() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(StudioTheme.accent)
                    .foregroundStyle(.black)
                    .padding(.top, 8)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .studioCard()
    }
}

struct ScanControlBar: View {
    let isEnabled: Bool

    var body: some View {
        HStack(spacing: 18) {
            Button(action: {}) {
                Label("Cancel", systemImage: "xmark")
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.bordered)

            Button(action: {}) {
                ZStack {
                    Circle().stroke(.white.opacity(0.8), lineWidth: 3)
                    Circle().fill(StudioTheme.accent).padding(6)
                }
                .frame(width: 66, height: 66)
            }
            .accessibilityLabel("Start scan")
            .disabled(!isEnabled)

            Button(action: {}) {
                Label("Finish", systemImage: "checkmark")
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(StudioTheme.elevatedSurface, in: Capsule())
        .opacity(isEnabled ? 1 : 0.55)
        .accessibilityElement(children: .contain)
        .accessibilityHint(isEnabled ? "Scanning controls" : "Scanning controls are unavailable in Sprint 1")
    }
}
