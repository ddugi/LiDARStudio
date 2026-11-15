import Foundation

nonisolated struct LocalStorageBreakdown: Equatable, Sendable {
    let modelsBytes: Int64
    let capturePhotographsBytes: Int64
    let captureCheckpointsBytes: Int64
    let reconstructionIntermediatesBytes: Int64
    let previewsBytes: Int64
    let metadataBytes: Int64
    let diagnosticDatasetsBytes: Int64
    let otherManagedDataBytes: Int64

    var otherScanDataBytes: Int64 {
        captureCheckpointsBytes
            + reconstructionIntermediatesBytes
            + metadataBytes
            + otherManagedDataBytes
    }

    var totalBytes: Int64 {
        modelsBytes
            + capturePhotographsBytes
            + captureCheckpointsBytes
            + reconstructionIntermediatesBytes
            + previewsBytes
            + metadataBytes
            + diagnosticDatasetsBytes
            + otherManagedDataBytes
    }
}

nonisolated struct LocalStorageUsageCalculator: Sendable {
    private static let captureImageExtensions = Set(["heic", "heif", "jpg", "jpeg", "png"])

    func calculate(scanRoot: URL, diagnosticRoot: URL) throws -> LocalStorageBreakdown {
        let canonicalScanRoot = scanRoot.standardizedFileURL.resolvingSymlinksInPath()
        let models = try regularFileBytes(
            in: canonicalScanRoot.appending(path: "Models", directoryHint: .isDirectory)
        )
        let captures = try captureBreakdown(
            in: canonicalScanRoot.appending(path: "Captures", directoryHint: .isDirectory)
        )
        let previews = try regularFileBytes(
            in: canonicalScanRoot.appending(path: "Previews", directoryHint: .isDirectory)
        )
        let metadata = try regularFileBytes(at: canonicalScanRoot.appending(path: "scans.json"))
        let allScanData = try regularFileBytes(in: canonicalScanRoot)
        let classifiedScanData = models + captures.totalBytes + previews + metadata
        let otherManagedData = max(0, allScanData - classifiedScanData)
        let diagnostics = try regularFileBytes(
            in: diagnosticRoot.standardizedFileURL.resolvingSymlinksInPath()
        )

        return LocalStorageBreakdown(
            modelsBytes: models,
            capturePhotographsBytes: captures.photographs,
            captureCheckpointsBytes: captures.captureCheckpoints,
            reconstructionIntermediatesBytes: captures.reconstructionIntermediates,
            previewsBytes: previews,
            metadataBytes: metadata + captures.metadata,
            diagnosticDatasetsBytes: diagnostics,
            otherManagedDataBytes: otherManagedData + captures.other
        )
    }

    private struct CaptureBreakdown {
        var photographs: Int64 = 0
        var captureCheckpoints: Int64 = 0
        var reconstructionIntermediates: Int64 = 0
        var metadata: Int64 = 0
        var other: Int64 = 0

        var totalBytes: Int64 {
            photographs + captureCheckpoints + reconstructionIntermediates + metadata + other
        }
    }

    private func captureBreakdown(in directory: URL) throws -> CaptureBreakdown {
        guard FileManager.default.fileExists(atPath: directory.path) else { return CaptureBreakdown() }
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return CaptureBreakdown() }

        var result = CaptureBreakdown()
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [
                .fileSizeKey, .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey
            ])
            if values.isSymbolicLink == true {
                if values.isDirectory == true { enumerator.skipDescendants() }
                continue
            }
            guard values.isRegularFile == true else { continue }

            let canonicalURL = url.standardizedFileURL.resolvingSymlinksInPath()
            let canonicalDirectory = directory.standardizedFileURL.resolvingSymlinksInPath()
            let relativeComponents = Array(canonicalURL.pathComponents.dropFirst(canonicalDirectory.pathComponents.count))
            guard relativeComponents.count >= 2 else {
                result.other += Int64(values.fileSize ?? 0)
                continue
            }
            let workspaceComponent = relativeComponents[1]
            let bytes = Int64(values.fileSize ?? 0)
            switch workspaceComponent {
            case "Images" where Self.captureImageExtensions.contains(url.pathExtension.lowercased()):
                result.photographs += bytes
            case "CaptureCheckpoints":
                result.captureCheckpoints += bytes
            case "ReconstructionCheckpoints":
                result.reconstructionIntermediates += bytes
            case "capture.json":
                result.metadata += bytes
            default:
                result.other += bytes
            }
        }
        return result
    }

    private func regularFileBytes(at file: URL) throws -> Int64 {
        guard FileManager.default.fileExists(atPath: file.path) else { return 0 }
        let values = try file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { return 0 }
        return Int64(values.fileSize ?? 0)
    }

    static func defaultDiagnosticRoot() throws -> URL {
        try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        .appending(path: "RGBDDatasets", directoryHint: .isDirectory)
    }

    private func regularFileBytes(
        in directory: URL,
        allowedExtensions: Set<String>? = nil
    ) throws -> Int64 {
        guard FileManager.default.fileExists(atPath: directory.path) else { return 0 }
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return 0 }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            if let allowedExtensions,
               !allowedExtensions.contains(url.pathExtension.lowercased()) {
                continue
            }
            let values = try url.resourceValues(forKeys: [
                .fileSizeKey,
                .isRegularFileKey,
                .isSymbolicLinkKey
            ])
            if values.isRegularFile == true, values.isSymbolicLink != true {
                total += Int64(values.fileSize ?? 0)
            }
        }
        return total
    }
}
