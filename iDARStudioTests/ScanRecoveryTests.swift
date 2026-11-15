import Foundation
import Testing
@testable import iDARStudio

struct ScanRecoveryTests {
    @Test func inventorySeparatesIndexedModelDraftAndManifestOnlyCandidates() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = LocalScanRepository(rootDirectory: root)
        try repository.prepareDirectories()

        let indexedID = UUID()
        let orphanID = UUID()
        let draftID = UUID()
        let manifestOnlyID = UUID()
        try validUSDZ().write(to: repository.modelsDirectory.appending(path: "\(indexedID.uuidString).usdz"))
        try validUSDZ().write(to: repository.modelsDirectory.appending(path: "\(orphanID.uuidString).usdz"))
        try makeCapture(id: indexedID, imageCount: 1, validManifest: true, repository: repository)
        try makeCapture(id: draftID, imageCount: 2, validManifest: false, repository: repository)
        try makeCapture(id: manifestOnlyID, imageCount: 0, validManifest: true, repository: repository)

        let scan = ScanMetadata(
            id: indexedID,
            name: "Indexed",
            kind: .object,
            relativeModelPath: "\(indexedID.uuidString).usdz",
            relativeCapturePath: indexedID.uuidString
        )
        try repository.save([scan])

        let inventory = try ScanRecoveryInventoryService(repository: repository).inventory()
        #expect(inventory.count(for: .indexedScan) == 1)
        #expect(inventory.count(for: .validUnindexedModel) == 1)
        #expect(inventory.count(for: .captureDraftWithImages) == 1)
        #expect(inventory.count(for: .manifestOnlyDraft) == 1)
        #expect(inventory.candidates.count == 4)
        #expect(inventory.candidates.first { $0.classification == .captureDraftWithImages }?.originalImageCount == 2)
    }

    @Test func invalidUSDZAndPartialCaptureRemainUnknown() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = LocalScanRepository(rootDirectory: root)
        try repository.prepareDirectories()
        let candidateID = UUID()
        try Data(repeating: 0, count: 80).write(
            to: repository.modelsDirectory.appending(path: "\(candidateID.uuidString).usdz")
        )
        let capture = repository.capturesDirectory.appending(path: candidateID.uuidString, directoryHint: .isDirectory)
        let reconstruction = capture.appending(path: "ReconstructionCheckpoints", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: reconstruction, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 40).write(to: reconstruction.appending(path: "partial.bin"))

        let inventory = try ScanRecoveryInventoryService(repository: repository).inventory()
        let candidate = try #require(inventory.candidates.first)
        #expect(candidate.classification == .incompleteOrUnknown)
        #expect(candidate.hasValidModel == false)
        #expect(candidate.validatedModelURL == nil)
        #expect(candidate.reconstructionIntermediateCount == 1)
    }

    @Test func matchingModelAndCaptureProduceOneStableCandidate() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = LocalScanRepository(rootDirectory: root)
        try repository.prepareDirectories()
        let id = UUID()
        try validUSDZ().write(to: repository.modelsDirectory.appending(path: "\(id.uuidString).usdz"))
        try makeCapture(id: id, imageCount: 3, validManifest: true, repository: repository)

        let first = try ScanRecoveryInventoryService(repository: repository).inventory()
        let second = try ScanRecoveryInventoryService(repository: repository).inventory()
        #expect(first.candidates.count == 1)
        #expect(first.candidates.map(\.id) == second.candidates.map(\.id))
        #expect(Set(first.candidates.map(\.id)).count == first.candidates.count)
        #expect(first.candidates[0].classification == .validUnindexedModel)
        #expect(first.candidates[0].originalImageCount == 3)
    }

    @Test func symlinksAreVisibleButNeverFollowedOrEligible() throws {
        let root = temporaryRoot()
        let external = temporaryRoot()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: external)
        }
        let repository = LocalScanRepository(rootDirectory: root)
        try repository.prepareDirectories()
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        let externalModel = external.appending(path: "private.usdz")
        try validUSDZ().write(to: externalModel)
        try FileManager.default.createSymbolicLink(
            at: repository.modelsDirectory.appending(path: "linked.usdz"),
            withDestinationURL: externalModel
        )

        let inventory = try ScanRecoveryInventoryService(repository: repository).inventory()
        let candidate = try #require(inventory.candidates.first)
        #expect(candidate.classification == .incompleteOrUnknown)
        #expect(candidate.validatedModelURL == nil)
        #expect(candidate.sizeBytes == 0)
        #expect(candidate.reason.localizedCaseInsensitiveContains("symbolic link"))
    }

    @Test func inventoryIsReadOnlyAndPreservesMetadataAndSourceFiles() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = LocalScanRepository(rootDirectory: root)
        try repository.prepareDirectories()
        let id = UUID()
        try validUSDZ().write(to: repository.modelsDirectory.appending(path: "\(id.uuidString).usdz"))
        try makeCapture(id: id, imageCount: 1, validManifest: true, repository: repository)
        try repository.save([ScanMetadata(name: "Preserve", kind: .object)])
        let metadataURL = root.appending(path: "scans.json")
        let metadataBefore = try Data(contentsOf: metadataURL)
        let filesBefore = try allRelativeFiles(in: root)

        _ = try ScanRecoveryInventoryService(repository: repository).inventory()

        #expect(try Data(contentsOf: metadataURL) == metadataBefore)
        #expect(try allRelativeFiles(in: root) == filesBefore)
    }

    @Test func unsafeIndexedReferencesDoNotEscapeApprovedRoots() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = LocalScanRepository(rootDirectory: root)
        try repository.prepareDirectories()
        let unsafe = ScanMetadata(
            name: "Unsafe",
            kind: .object,
            relativeModelPath: "../outside.usdz",
            relativeCapturePath: "../outside"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode([unsafe]).write(to: root.appending(path: "scans.json"))

        let inventory = try ScanRecoveryInventoryService(repository: repository).inventory()
        let candidate = try #require(inventory.candidates.first)
        #expect(candidate.classification == .indexedScan)
        #expect(candidate.hasValidModel == false)
        #expect(candidate.validatedModelURL == nil)
        #expect(candidate.reason.localizedCaseInsensitiveContains("unsafe"))
    }

    private func makeCapture(
        id: UUID,
        imageCount: Int,
        validManifest: Bool,
        repository: LocalScanRepository
    ) throws {
        let capture = repository.capturesDirectory.appending(path: id.uuidString, directoryHint: .isDirectory)
        let images = capture.appending(path: "Images", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        for index in 0..<imageCount {
            try Data(repeating: UInt8(index), count: 12).write(to: images.appending(path: "image-\(index).jpg"))
        }
        let manifestURL = capture.appending(path: "capture.json")
        if validManifest {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(ObjectCaptureDraft(id: id, photoCount: imageCount)).write(to: manifestURL)
        } else {
            try Data("not-json".utf8).write(to: manifestURL)
        }
    }

    private func validUSDZ() -> Data {
        Data([0x50, 0x4B, 0x03, 0x04]) + Data(repeating: 0, count: 76)
    }

    private func allRelativeFiles(in root: URL) throws -> [String] {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
        return enumerator.compactMap { item in
            guard let url = item as? URL else { return nil }
            return String(url.path.dropFirst(root.path.count))
        }.sorted()
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    }
}
