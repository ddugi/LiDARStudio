import Foundation
import Testing
@testable import iDARStudio

struct ScanModelRecoveryTests {
    @Test func successfulRestorePreservesModelAndPersistsMetadata() async throws {
        let context = try makeContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        let before = try Data(contentsOf: context.modelURL)

        let scan = try await ScanModelRecoveryService(repository: context.repository)
            .restore(candidateID: context.candidateID, proposedName: "Recovered Bust")

        #expect(scan.id == context.id)
        #expect(scan.relativeModelPath == context.modelURL.lastPathComponent)
        #expect(scan.relativeCapturePath == context.id.uuidString)
        #expect(scan.photoCount == 2)
        #expect(try Data(contentsOf: context.modelURL) == before)
        let persisted = try #require(context.repository.load().first)
        #expect(persisted.id == scan.id)
        #expect(persisted.name == scan.name)
        #expect(persisted.relativeModelPath == scan.relativeModelPath)
        #expect(persisted.relativeCapturePath == scan.relativeCapturePath)
        #expect(persisted.photoCount == scan.photoCount)
    }

    @Test func duplicateRestoreIsRejectedWithoutAddingMetadata() async throws {
        let context = try makeContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        let service = ScanModelRecoveryService(repository: context.repository)
        _ = try await service.restore(candidateID: context.candidateID, proposedName: "First")
        await #expect(throws: ScanModelRecoveryService.RecoveryError.duplicate) {
            try await service.restore(candidateID: context.candidateID, proposedName: "Second")
        }
        #expect(try context.repository.load().count == 1)
    }

    @Test func concurrentRestoreCreatesExactlyOneEntry() async throws {
        let context = try makeContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        let service = ScanModelRecoveryService(repository: context.repository)
        let outcomes = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
            for name in ["One", "Two"] {
                group.addTask { (try? await service.restore(candidateID: context.candidateID, proposedName: name)) != nil }
            }
            var values: [Bool] = []
            for await value in group { values.append(value) }
            return values
        }
        #expect(outcomes.filter { $0 }.count == 1)
        #expect(try context.repository.load().count == 1)
    }

    @Test func missingOrInvalidModelCannotBeRestored() async throws {
        let missing = try makeContext()
        defer { try? FileManager.default.removeItem(at: missing.root) }
        try FileManager.default.removeItem(at: missing.modelURL)
        await #expect(throws: ScanModelRecoveryService.RecoveryError.notEligible) {
            try await ScanModelRecoveryService(repository: missing.repository)
                .restore(candidateID: missing.candidateID, proposedName: "Missing")
        }

        let invalid = try makeContext(validModel: false)
        defer { try? FileManager.default.removeItem(at: invalid.root) }
        await #expect(throws: ScanModelRecoveryService.RecoveryError.notEligible) {
            try await ScanModelRecoveryService(repository: invalid.repository)
                .restore(candidateID: invalid.candidateID, proposedName: "Invalid")
        }
    }

    @Test func symlinkAndUnsafePathsAreNeverRecoveryEligible() async throws {
        let root = temporaryRoot()
        let external = temporaryRoot()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: external)
        }
        let repository = LocalScanRepository(rootDirectory: root)
        try repository.prepareDirectories()
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        let externalModel = external.appending(path: "outside.usdz")
        try validUSDZ().write(to: externalModel)
        try FileManager.default.createSymbolicLink(
            at: repository.modelsDirectory.appending(path: "linked.usdz"),
            withDestinationURL: externalModel
        )
        let candidate = try #require(ScanRecoveryInventoryService(repository: repository).inventory().candidates.first)
        #expect(candidate.canRestoreToLibrary == false)
        await #expect(throws: ScanModelRecoveryService.RecoveryError.notEligible) {
            try await ScanModelRecoveryService(repository: repository)
                .restore(candidateID: candidate.id, proposedName: "Unsafe")
        }
    }

    @Test func existingIdentifierCollisionIsRejected() async throws {
        let context = try makeContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        let otherURL = context.repository.modelsDirectory.appending(path: "other.usdz")
        try validUSDZ().write(to: otherURL)
        try context.repository.save([ScanMetadata(
            id: context.id,
            name: "Existing",
            kind: .object,
            relativeModelPath: otherURL.lastPathComponent
        )])
        await #expect(throws: ScanModelRecoveryService.RecoveryError.identifierCollision) {
            try await ScanModelRecoveryService(repository: context.repository)
                .restore(candidateID: context.candidateID, proposedName: "Collision")
        }
        #expect(try context.repository.load().count == 1)
    }

    @Test func interruptedRestoreLeavesMetadataAndOriginalFilesUntouched() async throws {
        enum SimulatedInterruption: Error { case stop }
        let context = try makeContext()
        defer { try? FileManager.default.removeItem(at: context.root) }
        let before = try Data(contentsOf: context.modelURL)
        let service = ScanModelRecoveryService(repository: context.repository) { throw SimulatedInterruption.stop }
        await #expect(throws: SimulatedInterruption.stop) {
            try await service.restore(candidateID: context.candidateID, proposedName: "Interrupted")
        }
        #expect(try context.repository.load().isEmpty)
        #expect(try Data(contentsOf: context.modelURL) == before)
    }

    private struct Context {
        let root: URL
        let repository: LocalScanRepository
        let id: UUID
        let modelURL: URL
        var candidateID: String { "candidate:\(id.uuidString)" }
    }

    private func makeContext(validModel: Bool = true) throws -> Context {
        let root = temporaryRoot()
        let repository = LocalScanRepository(rootDirectory: root)
        try repository.prepareDirectories()
        let id = UUID()
        let modelURL = repository.modelsDirectory.appending(path: "\(id.uuidString).usdz")
        try (validModel ? validUSDZ() : Data(repeating: 0, count: 80)).write(to: modelURL)
        let capture = repository.capturesDirectory.appending(path: id.uuidString, directoryHint: .isDirectory)
        let images = capture.appending(path: "Images", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 12).write(to: images.appending(path: "one.jpg"))
        try Data(repeating: 2, count: 12).write(to: images.appending(path: "two.jpg"))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(ObjectCaptureDraft(id: id, photoCount: 2)).write(to: capture.appending(path: "capture.json"))
        return Context(root: root, repository: repository, id: id, modelURL: modelURL)
    }

    private func validUSDZ() -> Data {
        Data([0x50, 0x4B, 0x03, 0x04]) + Data(repeating: 0, count: 76)
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    }
}
