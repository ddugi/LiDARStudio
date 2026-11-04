import AppIntents
import Foundation

struct OpenScanLibraryIntent: TargetContentProvidingIntent {
    static let title: LocalizedStringResource = "Open Scan Library"
    static let description = IntentDescription("Opens the local LiDARStudio scan library.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    static let supportedModes: IntentModes = .foreground(.immediate)
    static let allowedExecutionTargets: IntentExecutionTargets = .main

    var contentIdentifier: String { "lidarstudio.library" }
}

struct FindSavedScansIntent: AppIntent {
    static let title: LocalizedStringResource = "Find Saved Scans"
    static let description = IntentDescription("Finds scans by name using local metadata only.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    static let supportedModes: IntentModes = .background
    static let allowedExecutionTargets: IntentExecutionTargets = .main

    @Parameter(title: "Name", description: "Part or all of a saved scan name")
    var name: String?

    init() {}

    init(name: String?) {
        self.name = name
    }

    func perform() async throws -> some IntentResult & ReturnsValue<[ScanEntity]> & ProvidesDialog {
        let query = ScanEntityQuery()
        let scans: [ScanEntity]
        if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            scans = try await query.entities(matching: name)
        } else {
            scans = try await query.allEntities()
        }
        return .result(
            value: scans,
            dialog: "Found \(scans.count) saved scans in the local library."
        )
    }
}

struct OpenSavedModelIntent: TargetContentProvidingIntent {
    static let title: LocalizedStringResource = "Open Saved 3D Model"
    static let description = IntentDescription("Opens a verified local USDZ model without sharing it.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    static let supportedModes: IntentModes = .foreground(.immediate)
    static let allowedExecutionTargets: IntentExecutionTargets = .main

    @Parameter(title: "Scan", description: "A saved scan with a valid local 3D model")
    var scan: ScanEntity

    init() {}

    init(scan: ScanEntity) {
        self.scan = scan
    }

    var contentIdentifier: String { "lidarstudio.model.\(scan.id.uuidString)" }
}

struct ViewScanMetadataIntent: AppIntent {
    static let title: LocalizedStringResource = "View Scan Metadata"
    static let description = IntentDescription("Shows approved local metadata without exposing files or sensor data.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    static let supportedModes: IntentModes = .background
    static let allowedExecutionTargets: IntentExecutionTargets = .main

    @Parameter(title: "Scan")
    var scan: ScanEntity

    init() {}

    init(scan: ScanEntity) {
        self.scan = scan
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let metadata = try ScanIntentAccess.approvedMetadata(for: scan.id)
        return .result(value: metadata.spokenSummary, dialog: "\(metadata.spokenSummary)")
    }
}

struct PrepareObjectStudioIntent: TargetContentProvidingIntent {
    static let title: LocalizedStringResource = "Prepare Object Studio"
    static let description = IntentDescription("Opens Object Studio preparation. It never starts the camera or capture.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    static let supportedModes: IntentModes = .foreground(.immediate)
    static let allowedExecutionTargets: IntentExecutionTargets = .main

    var contentIdentifier: String { "lidarstudio.object-studio.prepare" }
}

struct LiDARStudioShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenScanLibraryIntent(),
            phrases: ["Open my scans in \(.applicationName)"],
            shortTitle: "Open My Scans",
            systemImageName: "square.stack.3d.up"
        )
        AppShortcut(
            intent: FindSavedScansIntent(),
            phrases: ["Find scans in \(.applicationName)"],
            shortTitle: "Find Scans",
            systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent: OpenSavedModelIntent(),
            phrases: ["Open a model in \(.applicationName)"],
            shortTitle: "Open 3D Model",
            systemImageName: "cube.transparent"
        )
        AppShortcut(
            intent: ViewScanMetadataIntent(),
            phrases: ["View scan details in \(.applicationName)"],
            shortTitle: "Scan Details",
            systemImageName: "info.circle"
        )
        AppShortcut(
            intent: PrepareObjectStudioIntent(),
            phrases: ["Prepare Object Studio in \(.applicationName)"],
            shortTitle: "Prepare Object Studio",
            systemImageName: "viewfinder"
        )
    }

    static let shortcutTileColor: ShortcutTileColor = .lime
}
