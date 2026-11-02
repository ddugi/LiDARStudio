import Foundation

nonisolated struct ObjectCaptureDraft: Codable, Equatable, Identifiable, Sendable {
    enum Status: String, Codable, Sendable {
        case capturing
        case cancelled
        case readyForReconstruction
        case reconstructing
        case completed
        case failed
    }

    let id: UUID
    let createdAt: Date
    var updatedAt: Date
    var photoCount: Int
    var status: Status

    init(
        id: UUID,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        photoCount: Int = 0,
        status: Status = .capturing
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.photoCount = photoCount
        self.status = status
    }
}
