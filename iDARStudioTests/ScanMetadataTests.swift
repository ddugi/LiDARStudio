import Foundation
import Testing
@testable import iDARStudio

struct ScanMetadataTests {
    @Test func metadataRoundTripsThroughLocalRepository() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let repository = LocalScanRepository(rootDirectory: root)
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let expected = ScanMetadata(
            name: "Workshop",
            kind: .environment,
            createdAt: timestamp,
            updatedAt: timestamp,
            relativeModelPath: "workshop.usdz",
            fileSizeBytes: 42
        )

        try repository.save([expected])
        let loaded = try repository.load()

        #expect(loaded == [expected])
    }

    @Test func repositoryStartsEmptyAndCreatesLocalFolders() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let repository = LocalScanRepository(rootDirectory: root)

        #expect(try repository.load().isEmpty)
        #expect(FileManager.default.fileExists(atPath: repository.modelsDirectory.path))
    }

    @Test func repositoryRejectsEscapingModelPaths() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = LocalScanRepository(rootDirectory: root)
        let scan = ScanMetadata(name: "Unsafe", kind: .object, relativeModelPath: "../outside.usdz")

        #expect(throws: LocalScanRepository.RepositoryError.self) {
            try repository.save([scan])
        }
    }
}
