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
    static let currentSchemaVersion = 1

    let id: UUID
    var name: String
    let kind: ScanKind
    let createdAt: Date
    var updatedAt: Date
    var relativeModelPath: String?
    var previewImagePath: String?
    var fileSizeBytes: Int64?
    let schemaVersion: Int

    init(
        id: UUID = UUID(),
        name: String,
        kind: ScanKind,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        relativeModelPath: String? = nil,
        previewImagePath: String? = nil,
        fileSizeBytes: Int64? = nil,
        schemaVersion: Int = currentSchemaVersion
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.relativeModelPath = relativeModelPath
        self.previewImagePath = previewImagePath
        self.fileSizeBytes = fileSizeBytes
        self.schemaVersion = schemaVersion
    }
}
