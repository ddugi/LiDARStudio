import AppIntents
import Foundation
import Testing
@testable import iDARStudio

struct AppIntentsTests {
    @Test func entityUUIDResolutionAndDeletionUseCurrentRepositoryState() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = LocalScanRepository(rootDirectory: root)
        let scan = ScanMetadata(name: "Current Bust", kind: .object)
        try repository.save([scan])
        let query = ScanEntityQuery(repository: repository)

        let resolved = try await query.entities(for: [scan.id])
        #expect(resolved.map(\.id) == [scan.id])
        #expect(resolved.first?.displayName == "Current Bust")

        try repository.save([])
        #expect(try await query.entities(for: [scan.id]).isEmpty)
    }

    @Test func nameSearchIsCaseInsensitiveAndReturnsOnlyCurrentScans() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = LocalScanRepository(rootDirectory: root)
        let bust = ScanMetadata(name: "Silver Bust", kind: .object)
        let room = ScanMetadata(name: "Workshop Room", kind: .room)
        try repository.save([bust, room])

        let results = try await ScanEntityQuery(repository: repository).entities(matching: "BUST")

        #expect(results.map(\.id) == [bust.id])
    }

    @Test func invalidUSDZIsNeverReportedAsAnAvailableModel() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = LocalScanRepository(rootDirectory: root)
        let id = UUID()
        let modelURL = try repository.modelFileURL(id: id)
        try Data(repeating: 0, count: 128).write(to: modelURL)
        let scan = ScanMetadata(
            id: id,
            name: "Invalid Model",
            kind: .object,
            relativeModelPath: modelURL.lastPathComponent
        )
        try repository.save([scan])

        let entity = try #require(await ScanEntityQuery(repository: repository).entities(for: [id]).first)

        #expect(!entity.hasValidModel)
        #expect(try ScanIntentAccess.approvedMetadata(for: id, repository: repository).hasValidModel == false)
    }

    @Test func approvedMetadataContainsNoPrivatePathsOrSensorFields() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = LocalScanRepository(rootDirectory: root)
        let scan = ScanMetadata(
            name: "Private Capture",
            kind: .environment,
            relativeModelPath: "private.usdz",
            relativeCapturePath: "private-capture",
            previewImagePath: "private.jpg",
            photoCount: 99
        )
        try repository.save([scan])

        let approved = try ScanIntentAccess.approvedMetadata(for: scan.id, repository: repository)
        let labels = Set(Mirror(reflecting: approved).children.compactMap(\.label))
        let summary = approved.spokenSummary.lowercased()

        #expect(labels == ["id", "displayName", "scanType", "creationDate", "isFavorite", "hasValidModel"])
        #expect(!summary.contains("private.usdz"))
        #expect(!summary.contains("private-capture"))
        #expect(!summary.contains("private.jpg"))
        #expect(!summary.contains("intrinsic"))
        #expect(!summary.contains("depth"))
        #expect(!summary.contains("99"))
    }

    @Test func entityQueriesDoNotModifyPersistedMetadata() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = LocalScanRepository(rootDirectory: root)
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
        let scan = ScanMetadata(
            name: "Read Only",
            kind: .object,
            createdAt: timestamp,
            updatedAt: timestamp,
            isFavorite: true
        )
        try repository.save([scan])
        let metadataURL = root.appending(path: "scans.json")
        let before = try Data(contentsOf: metadataURL)

        let query = ScanEntityQuery(repository: repository)
        _ = try await query.entities(matching: "Read")
        _ = try await query.entities(for: [scan.id])
        _ = try ScanIntentAccess.approvedMetadata(for: scan.id, repository: repository)

        #expect(try Data(contentsOf: metadataURL) == before)
        #expect(try repository.load() == [scan])
    }

    @Test func missingScanFailsWithoutReturningStaleMetadata() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = LocalScanRepository(rootDirectory: root)

        #expect(throws: ScanIntentError.scanUnavailable) {
            try ScanIntentAccess.approvedMetadata(for: UUID(), repository: repository)
        }
    }

    @Test func intentAuthenticationPoliciesMatchPrivacyRequirements() {
        #expect(OpenScanLibraryIntent.authenticationPolicy == .requiresAuthentication)
        #expect(FindSavedScansIntent.authenticationPolicy == .requiresLocalDeviceAuthentication)
        #expect(OpenSavedModelIntent.authenticationPolicy == .requiresLocalDeviceAuthentication)
        #expect(ViewScanMetadataIntent.authenticationPolicy == .requiresLocalDeviceAuthentication)
        #expect(PrepareObjectStudioIntent.authenticationPolicy == .requiresAuthentication)
    }

    @Test @MainActor func externalNavigationHandlesColdLaunchRunningAppAndDuplicates() {
        let navigation = AppNavigationState()

        navigation.openFromExternalRequest(.library)
        #expect(navigation.path == [.library])

        navigation.open(.settings)
        navigation.openFromExternalRequest(.objectStudio)
        #expect(navigation.path == [.objectStudio])

        navigation.openFromExternalRequest(.objectStudio)
        #expect(navigation.path == [.objectStudio])
    }

    @Test @MainActor func navigationStateDoesNotLeakBetweenScenes() {
        let firstScene = AppNavigationState()
        let secondScene = AppNavigationState()

        firstScene.openFromExternalRequest(.library)

        #expect(firstScene.path == [.library])
        #expect(secondScene.path.isEmpty)
    }

    @Test @MainActor func prepareObjectStudioRoutingDoesNotAcquireScanningResources() {
        var idleTimerChanges: [Bool] = []
        let awakeManager = ScreenAwakeManager { idleTimerChanges.append($0) }
        let navigation = AppNavigationState()

        navigation.openFromExternalRequest(.objectStudio)

        #expect(navigation.path == [.objectStudio])
        #expect(awakeManager.activeSessionCount == 0)
        #expect(idleTimerChanges.isEmpty)
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    }
}
