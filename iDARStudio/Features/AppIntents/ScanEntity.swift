import AppIntents
import Foundation

nonisolated struct ScanEntity: AppEntity, Equatable, Sendable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Saved Scan",
        numericFormat: "\(placeholder: .int) saved scans"
    )
    static let defaultQuery = ScanEntityQuery()

    let id: UUID
    let displayName: String
    let scanType: String
    let creationDate: Date
    let isFavorite: Bool
    let hasValidModel: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(displayName)",
            subtitle: "\(scanType) · \(creationDate.formatted(date: .abbreviated, time: .omitted))",
            image: .init(systemName: hasValidModel ? "cube.transparent" : "questionmark.folder")
        )
    }

    init(metadata: ScanMetadata, hasValidModel: Bool) {
        id = metadata.id
        displayName = metadata.name
        scanType = metadata.kind.title
        creationDate = metadata.createdAt
        isFavorite = metadata.isFavorite
        self.hasValidModel = hasValidModel
    }
}

nonisolated struct ScanEntityQuery: EntityStringQuery, EnumerableEntityQuery, Sendable {
    private let repository: LocalScanRepository

    init() {
        repository = LocalScanRepository()
    }

    init(repository: LocalScanRepository) {
        self.repository = repository
    }

    func entities(for identifiers: [UUID]) async throws -> [ScanEntity] {
        let requested = Set(identifiers)
        return try currentEntities().filter { requested.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [ScanEntity] {
        let query = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let entities = try currentEntities()
        guard !query.isEmpty else { return entities }
        return entities.filter { $0.displayName.localizedCaseInsensitiveContains(query) }
    }

    func allEntities() async throws -> [ScanEntity] {
        try currentEntities()
    }

    func suggestedEntities() async throws -> [ScanEntity] {
        try currentEntities()
    }

    private func currentEntities() throws -> [ScanEntity] {
        try repository.load().map { metadata in
            ScanEntity(
                metadata: metadata,
                hasValidModel: (try? repository.existingModelURL(for: metadata)) != nil
            )
        }
    }
}

nonisolated struct ApprovedScanMetadata: Equatable, Sendable {
    let id: UUID
    let displayName: String
    let scanType: String
    let creationDate: Date
    let isFavorite: Bool
    let hasValidModel: Bool

    var spokenSummary: String {
        let favorite = isFavorite ? "Favorite. " : ""
        let model = hasValidModel ? "A valid local 3D model is available." : "No valid local 3D model is available."
        return "\(displayName). \(scanType) scan, created \(creationDate.formatted(date: .long, time: .omitted)). \(favorite)\(model)"
    }
}

nonisolated enum ScanIntentAccess {
    static func approvedMetadata(
        for id: UUID,
        repository: LocalScanRepository = LocalScanRepository()
    ) throws -> ApprovedScanMetadata {
        guard let metadata = try repository.load().first(where: { $0.id == id }) else {
            throw ScanIntentError.scanUnavailable
        }
        return ApprovedScanMetadata(
            id: metadata.id,
            displayName: metadata.name,
            scanType: metadata.kind.title,
            creationDate: metadata.createdAt,
            isFavorite: metadata.isFavorite,
            hasValidModel: (try? repository.existingModelURL(for: metadata)) != nil
        )
    }
}

nonisolated enum ScanIntentError: LocalizedError, Equatable {
    case scanUnavailable

    var errorDescription: String? {
        switch self {
        case .scanUnavailable:
            "The selected scan is no longer available in the local library."
        }
    }
}
