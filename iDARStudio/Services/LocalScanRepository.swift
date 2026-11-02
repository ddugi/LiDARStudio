import Foundation

nonisolated struct LocalScanRepository: Sendable {
    struct ObjectCaptureWorkspace: Equatable, Sendable {
        let id: UUID
        let directory: URL
        let imagesDirectory: URL
        let checkpointsDirectory: URL
    }

    enum RepositoryError: LocalizedError {
        case invalidModelPath

        var errorDescription: String? {
            switch self {
            case .invalidModelPath: "A scan referenced a file outside the local scan library."
            }
        }
    }

    let rootDirectory: URL

    init(rootDirectory: URL? = nil) {
        if let rootDirectory {
            self.rootDirectory = rootDirectory.standardizedFileURL
        } else {
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            self.rootDirectory = documents.appending(path: "LiDARStudio", directoryHint: .isDirectory)
        }
    }

    var modelsDirectory: URL {
        rootDirectory.appending(path: "Models", directoryHint: .isDirectory)
    }

    var capturesDirectory: URL {
        rootDirectory.appending(path: "Captures", directoryHint: .isDirectory)
    }

    private var metadataFile: URL {
        rootDirectory.appending(path: "scans.json")
    }

    func prepareDirectories() throws {
        try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: capturesDirectory, withIntermediateDirectories: true)
    }

    func createObjectCaptureWorkspace(id: UUID) throws -> ObjectCaptureWorkspace {
        try prepareDirectories()
        let directory = capturesDirectory.appending(path: id.uuidString, directoryHint: .isDirectory)
        let images = directory.appending(path: "Images", directoryHint: .isDirectory)
        let checkpoints = directory.appending(path: "CaptureCheckpoints", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: checkpoints, withIntermediateDirectories: true)
        return ObjectCaptureWorkspace(
            id: id,
            directory: directory,
            imagesDirectory: images,
            checkpointsDirectory: checkpoints
        )
    }

    func objectCaptureWorkspace(id: UUID) -> ObjectCaptureWorkspace {
        let directory = capturesDirectory.appending(path: id.uuidString, directoryHint: .isDirectory)
        return ObjectCaptureWorkspace(
            id: id,
            directory: directory,
            imagesDirectory: directory.appending(path: "Images", directoryHint: .isDirectory),
            checkpointsDirectory: directory.appending(path: "CaptureCheckpoints", directoryHint: .isDirectory)
        )
    }

    func saveObjectCaptureDraft(_ draft: ObjectCaptureDraft) throws {
        let workspace = try createObjectCaptureWorkspace(id: draft.id)
        let data = try Self.encoder.encode(draft)
        try data.write(to: workspace.directory.appending(path: "capture.json"), options: .atomic)
    }

    func loadObjectCaptureDraft(id: UUID) throws -> ObjectCaptureDraft {
        let file = objectCaptureWorkspace(id: id).directory.appending(path: "capture.json")
        return try Self.decoder.decode(ObjectCaptureDraft.self, from: Data(contentsOf: file))
    }

    func capturedImageURLs(id: UUID) throws -> [URL] {
        let imagesDirectory = objectCaptureWorkspace(id: id).imagesDirectory
        let allowedExtensions = Set(["heic", "heif", "jpg", "jpeg", "png"])
        return try FileManager.default.contentsOfDirectory(
            at: imagesDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        )
        .filter { allowedExtensions.contains($0.pathExtension.lowercased()) }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    func reconstructionCheckpointDirectory(id: UUID) throws -> URL {
        let directory = objectCaptureWorkspace(id: id).directory
            .appending(path: "ReconstructionCheckpoints", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func modelFileURL(id: UUID) throws -> URL {
        try prepareDirectories()
        return modelsDirectory.appending(path: "\(id.uuidString).usdz")
    }

    func modelURL(for scan: ScanMetadata) throws -> URL? {
        guard let relativePath = scan.relativeModelPath else { return nil }
        let resolved = modelsDirectory.appending(path: relativePath).standardizedFileURL
        guard resolved.path.hasPrefix(modelsDirectory.standardizedFileURL.path + "/") else {
            throw RepositoryError.invalidModelPath
        }
        return resolved
    }

    func load() throws -> [ScanMetadata] {
        try prepareDirectories()
        guard FileManager.default.fileExists(atPath: metadataFile.path) else { return [] }
        let data = try Data(contentsOf: metadataFile)
        return try Self.decoder.decode([ScanMetadata].self, from: data)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func save(_ scans: [ScanMetadata]) throws {
        try prepareDirectories()
        for scan in scans {
            _ = try modelURL(for: scan)
        }
        let data = try Self.encoder.encode(scans)
        try data.write(to: metadataFile, options: .atomic)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
