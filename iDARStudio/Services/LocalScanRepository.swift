import Foundation

nonisolated struct LocalScanRepository: Sendable {
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

    private var metadataFile: URL {
        rootDirectory.appending(path: "scans.json")
    }

    func prepareDirectories() throws {
        try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
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
            guard let relativePath = scan.relativeModelPath else { continue }
            let resolvedPath = modelsDirectory.appending(path: relativePath).standardizedFileURL.path
            guard resolvedPath.hasPrefix(modelsDirectory.standardizedFileURL.path + "/") else {
                throw RepositoryError.invalidModelPath
            }
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
