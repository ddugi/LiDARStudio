import Foundation
import Testing
@testable import iDARStudio

struct ScanMetadataTests {
    @Test func objectStudioWorkflowRejectsOutOfOrderTransitions() {
        #expect(ObjectStudioTransitionPolicy.permits(from: .idle, to: .preparing))
        #expect(ObjectStudioTransitionPolicy.permits(from: .preparing, to: .readyForDetection))
        #expect(ObjectStudioTransitionPolicy.permits(from: .readyForDetection, to: .detecting))
        #expect(ObjectStudioTransitionPolicy.permits(from: .readyForDetection, to: .capturing))
        #expect(ObjectStudioTransitionPolicy.permits(from: .preparing, to: .detecting))
        #expect(ObjectStudioTransitionPolicy.permits(from: .detecting, to: .capturing))
        #expect(ObjectStudioTransitionPolicy.permits(from: .detecting, to: .readyForDetection))
        #expect(!ObjectStudioTransitionPolicy.permits(from: .idle, to: .capturing))
        #expect(!ObjectStudioTransitionPolicy.permits(from: .capturing, to: .reconstructing))
    }

    @Test func objectCaptureWorkspaceUsesSeparatedLocalDirectories() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = LocalScanRepository(rootDirectory: root)

        let workspace = try repository.createObjectCaptureWorkspace(id: UUID())

        #expect(FileManager.default.fileExists(atPath: workspace.imagesDirectory.path))
        #expect(FileManager.default.fileExists(atPath: workspace.checkpointsDirectory.path))
        #expect(workspace.imagesDirectory.path.hasPrefix(repository.capturesDirectory.path))
    }

    @Test func objectCaptureDraftPersistsForLaterProcessing() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = LocalScanRepository(rootDirectory: root)
        let draft = ObjectCaptureDraft(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_010),
            photoCount: 42,
            status: .readyForReconstruction
        )

        try repository.saveObjectCaptureDraft(draft)

        #expect(try repository.loadObjectCaptureDraft(id: draft.id) == draft)
    }

    @Test func modelOutputStaysInsideLocalModelsDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = LocalScanRepository(rootDirectory: root)

        let output = try repository.modelFileURL(id: UUID())

        #expect(output.pathExtension == "usdz")
        #expect(output.deletingLastPathComponent().standardizedFileURL == repository.modelsDirectory.standardizedFileURL)
    }

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
            relativeCapturePath: UUID().uuidString,
            fileSizeBytes: 42,
            photoCount: 75
        )

        try repository.save([expected])
        let loaded = try repository.load()

        #expect(loaded == [expected])
    }

    @Test func legacySprintOneMetadataStillDecodes() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "name": "Legacy Object",
          "kind": "object",
          "createdAt": "2026-01-01T00:00:00Z",
          "updatedAt": "2026-01-01T00:00:00Z",
          "relativeModelPath": "legacy.usdz",
          "schemaVersion": 1
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let scan = try decoder.decode(ScanMetadata.self, from: json)

        #expect(scan.name == "Legacy Object")
        #expect(scan.relativeCapturePath == nil)
        #expect(scan.photoCount == nil)
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
