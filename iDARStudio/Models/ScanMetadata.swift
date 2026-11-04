import Foundation

nonisolated enum ScanKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case object
    case room
    case environment

    var id: String { rawValue }

    var title: String {
        switch self {
        case .object: "Object"
        case .room: "Room"
        case .environment: "Environment"
        }
    }

    var systemImage: String {
        switch self {
        case .object: "cube.transparent"
        case .room: "square.split.bottomrightquarter"
        case .environment: "mountain.2"
        }
    }
}

nonisolated struct ScanMetadata: Codable, Equatable, Identifiable, Sendable {
    static let currentSchemaVersion = 3

    let id: UUID
    var name: String
    let kind: ScanKind
    let createdAt: Date
    var updatedAt: Date
    var relativeModelPath: String?
    var relativeCapturePath: String?
    var previewImagePath: String?
    var fileSizeBytes: Int64?
    var photoCount: Int?
    var isFavorite: Bool
    let schemaVersion: Int

    init(
        id: UUID = UUID(),
        name: String,
        kind: ScanKind,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        relativeModelPath: String? = nil,
        relativeCapturePath: String? = nil,
        previewImagePath: String? = nil,
        fileSizeBytes: Int64? = nil,
        photoCount: Int? = nil,
        isFavorite: Bool = false,
        schemaVersion: Int = currentSchemaVersion
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.relativeModelPath = relativeModelPath
        self.relativeCapturePath = relativeCapturePath
        self.previewImagePath = previewImagePath
        self.fileSizeBytes = fileSizeBytes
        self.photoCount = photoCount
        self.isFavorite = isFavorite
        self.schemaVersion = schemaVersion
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, kind, createdAt, updatedAt, relativeModelPath, relativeCapturePath
        case previewImagePath, fileSizeBytes, photoCount, isFavorite, schemaVersion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        kind = try container.decode(ScanKind.self, forKey: .kind)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        relativeModelPath = try container.decodeIfPresent(String.self, forKey: .relativeModelPath)
        relativeCapturePath = try container.decodeIfPresent(String.self, forKey: .relativeCapturePath)
        previewImagePath = try container.decodeIfPresent(String.self, forKey: .previewImagePath)
        fileSizeBytes = try container.decodeIfPresent(Int64.self, forKey: .fileSizeBytes)
        photoCount = try container.decodeIfPresent(Int.self, forKey: .photoCount)
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
    }
}

nonisolated enum ScanSortOrder: String, CaseIterable, Identifiable, Sendable {
    case newest
    case oldest
    case name

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newest: "Newest first"
        case .oldest: "Oldest first"
        case .name: "Name"
        }
    }
}

nonisolated enum ScanQuery {
    static func results(
        from scans: [ScanMetadata],
        searchText: String,
        sortOrder: ScanSortOrder,
        favoritesOnly: Bool = false
    ) -> [ScanMetadata] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = scans.filter { scan in
            (!favoritesOnly || scan.isFavorite)
                && (query.isEmpty || scan.name.localizedCaseInsensitiveContains(query))
        }

        return filtered.sorted { lhs, rhs in
            switch sortOrder {
            case .newest:
                lhs.updatedAt == rhs.updatedAt
                    ? lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                    : lhs.updatedAt > rhs.updatedAt
            case .oldest:
                lhs.updatedAt == rhs.updatedAt
                    ? lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                    : lhs.updatedAt < rhs.updatedAt
            case .name:
                lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
        }
    }
}
