import Foundation

actor ScanModelRecoveryService {
    private actor CommitCoordinator {
        func perform<T: Sendable>(_ operation: @Sendable () throws -> T) rethrows -> T {
            try operation()
        }
    }

    private static let commitCoordinator = CommitCoordinator()
    enum RecoveryError: LocalizedError, Equatable {
        case candidateUnavailable
        case notEligible
        case invalidName
        case invalidModel
        case duplicate
        case identifierCollision

        var errorDescription: String? {
            switch self {
            case .candidateUnavailable: "The recovery candidate is no longer available. Refresh and try again."
            case .notEligible: "This project is not eligible for model recovery."
            case .invalidName: "Enter a name containing at least one visible character."
            case .invalidModel: "The USDZ could not be validated safely at restore time."
            case .duplicate: "This model is already present in My Scans."
            case .identifierCollision: "The recovered identifier is already used by another scan."
            }
        }
    }

    private let repository: LocalScanRepository
    private let beforeCommit: @Sendable () throws -> Void

    init(
        repository: LocalScanRepository = LocalScanRepository(),
        beforeCommit: @escaping @Sendable () throws -> Void = {}
    ) {
        self.repository = repository
        self.beforeCommit = beforeCommit
    }

    func restore(candidateID: String, proposedName: String) async throws -> ScanMetadata {
        let name = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw RecoveryError.invalidName }
        let repository = repository
        let beforeCommit = beforeCommit
        return try await Self.commitCoordinator.perform {
            try Self.restoreSynchronously(
                repository: repository,
                beforeCommit: beforeCommit,
                candidateID: candidateID,
                name: name
            )
        }
    }

    private nonisolated static func restoreSynchronously(
        repository: LocalScanRepository,
        beforeCommit: @Sendable () throws -> Void,
        candidateID: String,
        name: String
    ) throws -> ScanMetadata {
        let inventory = try ScanRecoveryInventoryService(repository: repository).inventory()
        guard let candidate = inventory.candidates.first(where: { $0.id == candidateID }) else {
            if let rawID = candidateID.removingPrefix("candidate:"),
               let scanID = UUID(uuidString: rawID),
               try repository.load().contains(where: { $0.id == scanID || $0.relativeModelPath == "\(scanID.uuidString).usdz" }) {
                throw RecoveryError.duplicate
            }
            throw RecoveryError.candidateUnavailable
        }
        guard candidate.canRestoreToLibrary,
              let scanID = candidate.stableScanID,
              let modelFileName = candidate.modelFileName,
              let expectedURL = candidate.validatedModelURL else {
            throw RecoveryError.notEligible
        }

        let probe = ScanMetadata(
            id: scanID,
            name: name,
            kind: .object,
            relativeModelPath: modelFileName,
            relativeCapturePath: candidate.captureDirectoryName
        )
        guard let validatedURL = try repository.existingModelURL(for: probe),
              validatedURL.standardizedFileURL == expectedURL.standardizedFileURL else {
            throw RecoveryError.invalidModel
        }

        var scans = try repository.load()
        if scans.contains(where: { $0.relativeModelPath == modelFileName }) {
            throw RecoveryError.duplicate
        }
        if scans.contains(where: { $0.id == scanID }) {
            throw RecoveryError.identifierCollision
        }

        let createdAt = candidate.captureCreatedAt ?? candidate.modifiedAt ?? Date()
        let scan = ScanMetadata(
            id: scanID,
            name: name,
            kind: .object,
            createdAt: createdAt,
            updatedAt: Date(),
            relativeModelPath: modelFileName,
            relativeCapturePath: candidate.captureDirectoryName,
            fileSizeBytes: candidate.validatedModelURL.flatMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }.map(Int64.init),
            photoCount: candidate.originalImageCount > 0 ? candidate.originalImageCount : nil
        )
        scans.append(scan)
        try beforeCommit()
        try repository.save(scans)
        return scan
    }
}

private extension String {
    nonisolated func removingPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count))
    }
}
