import Foundation

nonisolated struct LocalStorageBreakdown: Equatable, Sendable {
    let modelsBytes: Int64
    let capturePhotographsBytes: Int64
    let previewsBytes: Int64
    let diagnosticDatasetsBytes: Int64
    let otherScanDataBytes: Int64

    var totalBytes: Int64 {
        modelsBytes
            + capturePhotographsBytes
            + previewsBytes
            + diagnosticDatasetsBytes
            + otherScanDataBytes
    }
}

nonisolated struct LocalStorageUsageCalculator: Sendable {
    private static let captureImageExtensions = Set(["heic", "heif", "jpg", "jpeg", "png"])

    func calculate(scanRoot: URL, diagnosticRoot: URL) throws -> LocalStorageBreakdown {
        let canonicalScanRoot = scanRoot.standardizedFileURL.resolvingSymlinksInPath()
        let models = try regularFileBytes(
            in: canonicalScanRoot.appending(path: "Models", directoryHint: .isDirectory)
        )
        let capturePhotos = try regularFileBytes(
            in: canonicalScanRoot.appending(path: "Captures", directoryHint: .isDirectory),
            allowedExtensions: Self.captureImageExtensions
        )
        let previews = try regularFileBytes(
            in: canonicalScanRoot.appending(path: "Previews", directoryHint: .isDirectory)
        )
        let allScanData = try regularFileBytes(in: canonicalScanRoot)
        let classifiedScanData = models + capturePhotos + previews
        let otherScanData = max(0, allScanData - classifiedScanData)
        let diagnostics = try regularFileBytes(
            in: diagnosticRoot.standardizedFileURL.resolvingSymlinksInPath()
        )

        return LocalStorageBreakdown(
            modelsBytes: models,
            capturePhotographsBytes: capturePhotos,
            previewsBytes: previews,
            diagnosticDatasetsBytes: diagnostics,
            otherScanDataBytes: otherScanData
        )
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
