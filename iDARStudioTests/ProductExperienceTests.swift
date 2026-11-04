import Foundation
import Testing
@testable import iDARStudio

struct ProductExperienceTests {
    @Test func scanSearchSortAndFavoritesUseRealMetadata() {
        let old = ScanMetadata(
            id: UUID(),
            name: "Alpha Bust",
            kind: .object,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100),
            isFavorite: true
        )
        let new = ScanMetadata(
            id: UUID(),
            name: "Workshop Room",
            kind: .room,
            createdAt: Date(timeIntervalSince1970: 200),
            updatedAt: Date(timeIntervalSince1970: 200)
        )

        #expect(ScanQuery.results(from: [old, new], searchText: "room", sortOrder: .newest) == [new])
        #expect(ScanQuery.results(from: [new, old], searchText: "", sortOrder: .name) == [old, new])
        #expect(ScanQuery.results(from: [old, new], searchText: "", sortOrder: .newest) == [new, old])
        #expect(ScanQuery.results(from: [old, new], searchText: "", sortOrder: .oldest) == [old, new])
        #expect(ScanQuery.results(from: [old, new], searchText: "", sortOrder: .newest, favoritesOnly: true) == [old])
    }

    @Test @MainActor func libraryRenameFavoriteAndRestartPersist() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = LocalScanRepository(rootDirectory: root)
        let original = ScanMetadata(name: "Original", kind: .object)
        let library = ScanLibrary(repository: repository, autoLoad: false)

        library.upsert(original)
        #expect(library.rename(original, to: "  Renamed Scan  "))
        let renamed = try #require(library.scans.first)
        #expect(renamed.name == "Renamed Scan")

        library.toggleFavorite(renamed)
        #expect(library.scans.first?.isFavorite == true)

        let restarted = ScanLibrary(repository: repository)
        #expect(restarted.scans.first?.name == "Renamed Scan")
        #expect(restarted.scans.first?.isFavorite == true)
    }

    @Test @MainActor func blankRenameIsRejectedWithoutChangingMetadata() {
        let repository = LocalScanRepository(rootDirectory: temporaryRoot())
        let library = ScanLibrary(repository: repository, autoLoad: false)
        let scan = ScanMetadata(name: "Keep Me", kind: .object)
        library.upsert(scan)

        #expect(!library.rename(scan, to: " \n "))
        #expect(library.scans.first?.name == "Keep Me")
        #expect(library.operationError != nil)
    }

    @Test @MainActor func confirmedDeleteRemovesOnlySelectedLocalAssets() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = LocalScanRepository(rootDirectory: root)
        try repository.prepareDirectories()
        let id = UUID()
        let workspace = try repository.createObjectCaptureWorkspace(id: id)
        let capturedPhoto = workspace.imagesDirectory.appending(path: "IMG_0001.jpg")
        try Data(repeating: 0x01, count: 128).write(to: capturedPhoto)
        let modelURL = try repository.modelFileURL(id: id)
        try validUSDZData().write(to: modelURL)
        let previewURL = repository.previewsDirectory.appending(path: "\(id.uuidString).jpg")
        try Data(repeating: 0x02, count: 128).write(to: previewURL)
        let scan = ScanMetadata(
            id: id,
            name: "Delete Me",
            kind: .object,
            relativeModelPath: modelURL.lastPathComponent,
            relativeCapturePath: id.uuidString,
            previewImagePath: previewURL.lastPathComponent
        )
        let survivor = ScanMetadata(name: "Keep Me", kind: .room)
        let library = ScanLibrary(repository: repository, autoLoad: false)
        library.upsert(scan)
        library.upsert(survivor)

        #expect(library.delete(scan))
        #expect(library.scans.map(\.id) == [survivor.id])
        #expect(!FileManager.default.fileExists(atPath: modelURL.path))
        #expect(!FileManager.default.fileExists(atPath: workspace.directory.path))
        #expect(!FileManager.default.fileExists(atPath: previewURL.path))
        let persisted = try repository.load()
        #expect(persisted.count == 1)
        #expect(persisted.first?.id == survivor.id)
        #expect(persisted.first?.name == survivor.name)
    }

    @Test func repositoryRejectsEscapingPreviewAndCapturePaths() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = LocalScanRepository(rootDirectory: root)
        let badPreview = ScanMetadata(name: "Preview", kind: .object, previewImagePath: "../private.jpg")
        let badCapture = ScanMetadata(name: "Capture", kind: .object, relativeCapturePath: "../Photos")

        #expect(throws: LocalScanRepository.RepositoryError.self) { try repository.save([badPreview]) }
        #expect(throws: LocalScanRepository.RepositoryError.self) { try repository.save([badCapture]) }
    }

    @Test func modelInspectionAcceptsValidUSDZAndRejectsMissingOrEmptyFiles() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let valid = root.appending(path: "model.usdz")
        try validUSDZData().write(to: valid)
        let info = try ModelFileInfo.inspect(valid)
        #expect(info.fileName == "model.usdz")
        #expect(info.sizeBytes == Int64(validUSDZData().count))

        let empty = root.appending(path: "empty.usdz")
        try Data().write(to: empty)
        #expect(throws: ModelFileError.self) { try ModelFileInfo.inspect(empty) }
        #expect(throws: ModelFileError.self) { try ModelFileInfo.inspect(root.appending(path: "missing.usdz")) }
    }

    @Test @MainActor func navigationStateOpensDestinationsAndReturnsHome() {
        let navigation = AppNavigationState()
        navigation.open(.library)
        navigation.open(.settings)
        #expect(navigation.path == [.library, .settings])
        navigation.returnHome()
        #expect(navigation.path.isEmpty)
    }

    @Test @MainActor func emptyAndCorruptRepositoriesExposeAccurateStates() throws {
        let emptyRoot = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: emptyRoot) }
        let emptyLibrary = ScanLibrary(repository: LocalScanRepository(rootDirectory: emptyRoot))
        #expect(emptyLibrary.state == .loaded)
        #expect(emptyLibrary.scans.isEmpty)

        let corruptRoot = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: corruptRoot) }
        try FileManager.default.createDirectory(at: corruptRoot, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: corruptRoot.appending(path: "scans.json"))
        let corruptLibrary = ScanLibrary(repository: LocalScanRepository(rootDirectory: corruptRoot))
        guard case .failed = corruptLibrary.state else {
            Issue.record("Corrupt metadata must surface an explicit failed state")
            return
        }
    }

    @Test func legacyMetadataDefaultsFavoriteToFalse() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "name": "Legacy",
          "kind": "object",
          "createdAt": "2026-01-01T00:00:00Z",
          "updatedAt": "2026-01-01T00:00:00Z",
          "schemaVersion": 2
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode(ScanMetadata.self, from: json).isFavorite == false)
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    }

    private func validUSDZData() -> Data {
        var data = Data([0x50, 0x4B, 0x03, 0x04])
        data.append(Data(repeating: 0x00, count: 124))
        return data
    }
}
