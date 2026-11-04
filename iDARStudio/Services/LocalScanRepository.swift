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
        case invalidCapturePath
        case invalidPreviewPath
        case invalidScanName

        var errorDescription: String? {
            switch self {
            case .invalidModelPath: "A scan referenced a file outside the local scan library."
            case .invalidCapturePath: "A scan referenced a capture outside the local scan library."
            case .invalidPreviewPath: "A scan referenced a preview outside the local scan library."
            case .invalidScanName: "Enter a scan name containing at least one visible character."
            }
        }
    }

    let rootDirectory: URL

    init(rootDirectory: URL? = nil) {
        if let rootDirectory {
            self.rootDirectory = rootDirectory.standardizedFileURL.resolvingSymlinksInPath()
        } else {
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            self.rootDirectory = documents
                .appending(path: "LiDARStudio", directoryHint: .isDirectory)
                .standardizedFileURL
                .resolvingSymlinksInPath()
        }
    }

    var modelsDirectory: URL {
        rootDirectory.appending(path: "Models", directoryHint: .isDirectory)
    }

    var capturesDirectory: URL {
        rootDirectory.appending(path: "Captures", directoryHint: .isDirectory)
    }

    var previewsDirectory: URL {
        rootDirectory.appending(path: "Previews", directoryHint: .isDirectory)
    }

    private var metadataFile: URL {
        rootDirectory.appending(path: "scans.json")
    }

    func prepareDirectories() throws {
        try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: capturesDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: previewsDirectory, withIntermediateDirectories: true)
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
        return modelsDirectory.resolvingSymlinksInPath()
            .appending(path: "\(id.uuidString).usdz")
    }

    func modelURL(for scan: ScanMetadata) throws -> URL? {
        guard let relativePath = scan.relativeModelPath else { return nil }
        guard !relativePath.isEmpty,
              relativePath == URL(fileURLWithPath: relativePath).lastPathComponent,
              !relativePath.contains("/") && !relativePath.contains("\\") else {
            throw RepositoryError.invalidModelPath
        }
        let canonicalDirectory = modelsDirectory.resolvingSymlinksInPath()
        let resolved = canonicalDirectory.appending(path: relativePath).standardizedFileURL
        guard resolved.deletingLastPathComponent() == canonicalDirectory else {
            throw RepositoryError.invalidModelPath
        }
        return resolved
    }

    func existingModelURL(for scan: ScanMetadata) throws -> URL? {
        guard let resolved = try modelURL(for: scan),
              resolved.pathExtension.lowercased() == "usdz",
              FileManager.default.fileExists(atPath: resolved.path) else {
            return nil
        }
        let values = try resolved.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true,
              values.isSymbolicLink != true,
              (values.fileSize ?? 0) >= 64,
              try hasUSDZContainerSignature(at: resolved) else {
            return nil
        }
        return resolved
    }

    func existingPreviewURL(for scan: ScanMetadata) throws -> URL? {
        guard let relativePath = scan.previewImagePath else { return nil }
        let resolved = try secureFileURL(relativePath: relativePath, inside: previewsDirectory, error: .invalidPreviewPath)
        guard FileManager.default.fileExists(atPath: resolved.path) else { return nil }
        let values = try resolved.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { return nil }
        return resolved
    }

    func storageUsageBytes() throws -> Int64 {
        try prepareDirectories()
        guard let enumerator = FileManager.default.enumerator(
            at: rootDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return 0 }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
            if values.isRegularFile == true, values.isSymbolicLink != true {
                total += Int64(values.fileSize ?? 0)
            }
        }
        return total
    }

    func delete(_ scan: ScanMetadata, keeping remainingScans: [ScanMetadata]) throws {
        let modelURL = try modelURL(for: scan)
        let previewURL = try existingPreviewURL(for: scan)
        let captureURL = try captureDirectory(for: scan)

        try save(remainingScans)

        for url in [modelURL, previewURL, captureURL].compactMap({ $0 }) {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
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
            guard !scan.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw RepositoryError.invalidScanName
            }
            _ = try modelURL(for: scan)
            if let preview = scan.previewImagePath {
                _ = try secureFileURL(relativePath: preview, inside: previewsDirectory, error: .invalidPreviewPath)
            }
            _ = try captureDirectory(for: scan)
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

    private func hasUSDZContainerSignature(at url: URL) throws -> Bool {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return try handle.read(upToCount: 4) == Data([0x50, 0x4B, 0x03, 0x04])
    }

    private func captureDirectory(for scan: ScanMetadata) throws -> URL? {
        guard let relativePath = scan.relativeCapturePath else { return nil }
        return try secureFileURL(relativePath: relativePath, inside: capturesDirectory, error: .invalidCapturePath)
    }

    private func secureFileURL(
        relativePath: String,
        inside directory: URL,
        error: RepositoryError
    ) throws -> URL {
        guard !relativePath.isEmpty,
              relativePath == URL(fileURLWithPath: relativePath).lastPathComponent,
              !relativePath.contains("/"),
              !relativePath.contains("\\") else {
            throw error
        }
        let canonicalDirectory = directory.resolvingSymlinksInPath()
        let resolved = canonicalDirectory.appending(path: relativePath).standardizedFileURL
        guard resolved.deletingLastPathComponent() == canonicalDirectory else { throw error }
        return resolved
    }
}
