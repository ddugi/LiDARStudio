import Foundation

nonisolated enum RecoveryClassification: String, CaseIterable, Sendable {
    case indexedScan
    case validUnindexedModel
    case captureDraftWithImages
    case manifestOnlyDraft
    case incompleteOrUnknown

    var title: String {
        switch self {
        case .indexedScan: "Indexed scan"
        case .validUnindexedModel: "Valid unindexed USDZ"
        case .captureDraftWithImages: "Capture draft with usable images"
        case .manifestOnlyDraft: "Manifest-only draft"
        case .incompleteOrUnknown: "Incomplete or unknown data"
        }
    }
}

nonisolated enum RecoveryEligibility: String, Sendable {
    case alreadyIndexed
    case metadataPreview
    case reconstructionAssessment
    case inspectionOnly

    var title: String {
        switch self {
        case .alreadyIndexed: "Already available in My Scans"
        case .metadataPreview: "Eligible for a future metadata recovery"
        case .reconstructionAssessment: "Source images can be assessed for reconstruction"
        case .inspectionOnly: "Inspection only"
        }
    }
}

nonisolated struct RecoveryCandidate: Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let safeIdentifier: String
    let classification: RecoveryClassification
    let eligibility: RecoveryEligibility
    let reason: String
    let modifiedAt: Date?
    let sizeBytes: Int64
    let originalImageCount: Int
    let captureCheckpointCount: Int
    let reconstructionIntermediateCount: Int
    let hasValidManifest: Bool
    let hasValidModel: Bool
    let validatedModelURL: URL?
}

nonisolated struct RecoveryInventory: Equatable, Sendable {
    let candidates: [RecoveryCandidate]

    func count(for classification: RecoveryClassification) -> Int {
        candidates.count { $0.classification == classification }
    }
}

nonisolated struct ScanRecoveryInventoryService: Sendable {
    enum InventoryError: LocalizedError {
        case unsafeRepositoryRoot

        var errorDescription: String? {
            switch self {
            case .unsafeRepositoryRoot: "The local scan repository could not be validated safely."
            }
        }
    }

    private struct ModelRecord: Sendable {
        let fileName: String
        let stem: String
        let url: URL
        let sizeBytes: Int64
        let modifiedAt: Date?
        let isValidUSDZ: Bool
        let limitation: String?
    }

    private struct CaptureRecord: Sendable {
        let directoryName: String
        let sizeBytes: Int64
        let modifiedAt: Date?
        let originalImageCount: Int
        let captureCheckpointCount: Int
        let reconstructionIntermediateCount: Int
        let manifestIsValid: Bool
        let manifestExists: Bool
        let limitation: String?
    }

    private let repository: LocalScanRepository
    private static let imageExtensions = Set(["heic", "heif", "jpg", "jpeg", "png"])
    private static let maximumManifestBytes = 1_048_576

    private var fileManager: FileManager { .default }

    init(repository: LocalScanRepository = LocalScanRepository()) {
        self.repository = repository
    }

    func inventory() throws -> RecoveryInventory {
        let root = repository.rootDirectory.standardizedFileURL.resolvingSymlinksInPath()
        guard root.isFileURL else { throw InventoryError.unsafeRepositoryRoot }

        let indexedScans = try loadIndexedScansReadOnly(from: root.appending(path: "scans.json"))
        var models = try modelRecords(in: repository.modelsDirectory)
        var captures = try captureRecords(in: repository.capturesDirectory)
        var candidates: [RecoveryCandidate] = []

        for scan in indexedScans {
            let modelName = safeChildName(scan.relativeModelPath)
            let captureName = safeChildName(scan.relativeCapturePath)
            let model = modelName.flatMap { models.removeValue(forKey: $0) }
            let capture = captureName.flatMap { captures.removeValue(forKey: $0) }

            var limitations: [String] = []
            if scan.relativeModelPath != nil, modelName == nil { limitations.append("The indexed model reference is unsafe.") }
            if scan.relativeCapturePath != nil, captureName == nil { limitations.append("The indexed capture reference is unsafe.") }
            if scan.relativeModelPath != nil, model == nil { limitations.append("The indexed model file is missing.") }
            if let model, !model.isValidUSDZ { limitations.append(model.limitation ?? "The indexed model is not a valid USDZ file.") }
            if scan.relativeCapturePath != nil, capture == nil { limitations.append("The indexed capture directory is missing.") }
            if let limitation = capture?.limitation { limitations.append(limitation) }

            candidates.append(RecoveryCandidate(
                id: "indexed:\(scan.id.uuidString)",
                displayName: scan.name,
                safeIdentifier: abbreviated(scan.id.uuidString),
                classification: .indexedScan,
                eligibility: .alreadyIndexed,
                reason: limitations.isEmpty ? "This scan is already represented by current library metadata." : limitations.joined(separator: " "),
                modifiedAt: latest(scan.updatedAt, model?.modifiedAt, capture?.modifiedAt),
                sizeBytes: (model?.sizeBytes ?? 0) + (capture?.sizeBytes ?? 0),
                originalImageCount: capture?.originalImageCount ?? 0,
                captureCheckpointCount: capture?.captureCheckpointCount ?? 0,
                reconstructionIntermediateCount: capture?.reconstructionIntermediateCount ?? 0,
                hasValidManifest: capture?.manifestIsValid ?? false,
                hasValidModel: model?.isValidUSDZ ?? false,
                validatedModelURL: model?.isValidUSDZ == true ? model?.url : nil
            ))
        }

        var remainingKeys = Set(captures.keys)
        for model in models.values { remainingKeys.insert(model.stem) }

        for key in remainingKeys.sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }) {
            let capture = captures[key]
            let model = models.values.first(where: { $0.stem == key })
            let classification: RecoveryClassification
            let eligibility: RecoveryEligibility
            let reason: String

            if model?.isValidUSDZ == true {
                classification = .validUnindexedModel
                eligibility = .metadataPreview
                reason = "The USDZ container is valid but no current scan metadata references it. Recovery would require a name, scan type, dates, and validated model reference."
            } else if let capture, capture.originalImageCount > 0 {
                classification = .captureDraftWithImages
                eligibility = .reconstructionAssessment
                reason = capture.manifestIsValid
                    ? "Original source images and a valid draft manifest are present. Reconstruction feasibility still requires explicit review."
                    : "Original source images are present, but the draft manifest is missing or invalid. Reconstruction feasibility is not established."
            } else if let capture,
                      capture.manifestIsValid,
                      capture.originalImageCount == 0,
                      capture.captureCheckpointCount == 0,
                      capture.reconstructionIntermediateCount == 0 {
                classification = .manifestOnlyDraft
                eligibility = .inspectionOnly
                reason = "A valid draft manifest exists, but no source images or processing checkpoints were verified."
            } else {
                classification = .incompleteOrUnknown
                eligibility = .inspectionOnly
                reason = model?.limitation
                    ?? capture?.limitation
                    ?? "The available files do not establish a valid model or a recoverable image-based draft."
            }

            let identifier = safeIdentifier(for: key)
            candidates.append(RecoveryCandidate(
                id: "candidate:\(key)",
                displayName: "Local project \(identifier)",
                safeIdentifier: identifier,
                classification: classification,
                eligibility: eligibility,
                reason: reason,
                modifiedAt: latest(model?.modifiedAt, capture?.modifiedAt),
                sizeBytes: (model?.sizeBytes ?? 0) + (capture?.sizeBytes ?? 0),
                originalImageCount: capture?.originalImageCount ?? 0,
                captureCheckpointCount: capture?.captureCheckpointCount ?? 0,
                reconstructionIntermediateCount: capture?.reconstructionIntermediateCount ?? 0,
                hasValidManifest: capture?.manifestIsValid ?? false,
                hasValidModel: model?.isValidUSDZ ?? false,
                validatedModelURL: model?.isValidUSDZ == true ? model?.url : nil
            ))
        }

        return RecoveryInventory(candidates: candidates.sorted {
            if $0.classification != $1.classification {
                return $0.classification.rawValue < $1.classification.rawValue
            }
            return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        })
    }

    private func loadIndexedScansReadOnly(from metadataFile: URL) throws -> [ScanMetadata] {
        guard fileManager.fileExists(atPath: metadataFile.path) else { return [] }
        let values = try metadataFile.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([ScanMetadata].self, from: Data(contentsOf: metadataFile))
    }

    private func modelRecords(in directory: URL) throws -> [String: ModelRecord] {
        guard fileManager.fileExists(atPath: directory.path) else { return [:] }
        let canonicalDirectory = directory.standardizedFileURL.resolvingSymlinksInPath()
        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        var result: [String: ModelRecord] = [:]
        for url in urls {
            guard url.standardizedFileURL.deletingLastPathComponent() == directory.standardizedFileURL else { continue }
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey])
            let isSymlink = values.isSymbolicLink == true
            let isRegular = values.isRegularFile == true && !isSymlink
            let resolvesInside = url.resolvingSymlinksInPath().deletingLastPathComponent() == canonicalDirectory
            let isUSDZ = url.pathExtension.lowercased() == "usdz"
            let canValidate = isRegular && resolvesInside && isUSDZ && (values.fileSize ?? 0) >= 64
            let valid = canValidate ? try hasUSDZSignature(at: url) : false
            let limitation: String? = valid ? nil : (isSymlink
                ? "A symbolic link was excluded from recovery inspection."
                : "The model candidate is missing, too small, outside the approved folder, or does not have a valid USDZ container signature.")
            result[url.lastPathComponent] = ModelRecord(
                fileName: url.lastPathComponent,
                stem: url.deletingPathExtension().lastPathComponent,
                url: url,
                sizeBytes: isRegular ? Int64(values.fileSize ?? 0) : 0,
                modifiedAt: values.contentModificationDate,
                isValidUSDZ: valid,
                limitation: limitation
            )
        }
        return result
    }

    private func captureRecords(in directory: URL) throws -> [String: CaptureRecord] {
        guard fileManager.fileExists(atPath: directory.path) else { return [:] }
        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        var result: [String: CaptureRecord] = [:]
        for url in urls {
            guard url.standardizedFileURL.deletingLastPathComponent() == directory.standardizedFileURL else { continue }
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else {
                result[url.lastPathComponent] = CaptureRecord(
                    directoryName: url.lastPathComponent,
                    sizeBytes: 0,
                    modifiedAt: values.contentModificationDate,
                    originalImageCount: 0,
                    captureCheckpointCount: 0,
                    reconstructionIntermediateCount: 0,
                    manifestIsValid: false,
                    manifestExists: false,
                    limitation: "A non-directory or symbolic link was excluded from recovery inspection."
                )
                continue
            }
            result[url.lastPathComponent] = try inspectCaptureDirectory(url, initialDate: values.contentModificationDate)
        }
        return result
    }

    private func inspectCaptureDirectory(_ directory: URL, initialDate: Date?) throws -> CaptureRecord {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return CaptureRecord(directoryName: directory.lastPathComponent, sizeBytes: 0, modifiedAt: initialDate, originalImageCount: 0, captureCheckpointCount: 0, reconstructionIntermediateCount: 0, manifestIsValid: false, manifestExists: false, limitation: "The capture directory could not be enumerated.")
        }

        var bytes: Int64 = 0
        var imageCount = 0
        var captureCheckpointCount = 0
        var reconstructionCount = 0
        var modifiedAt = initialDate
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey])
            if values.isSymbolicLink == true {
                if values.isDirectory == true { enumerator.skipDescendants() }
                continue
            }
            guard values.isRegularFile == true else { continue }
            bytes += Int64(values.fileSize ?? 0)
            modifiedAt = latest(modifiedAt, values.contentModificationDate)
            let relative = Array(url.pathComponents.dropFirst(directory.pathComponents.count))
            guard let first = relative.first else { continue }
            if first == "Images", Self.imageExtensions.contains(url.pathExtension.lowercased()) {
                imageCount += 1
            } else if first == "CaptureCheckpoints" {
                captureCheckpointCount += 1
            } else if first == "ReconstructionCheckpoints" {
                reconstructionCount += 1
            }
        }

        let manifestURL = directory.appending(path: "capture.json")
        let manifest = try validateManifest(at: manifestURL)
        return CaptureRecord(
            directoryName: directory.lastPathComponent,
            sizeBytes: bytes,
            modifiedAt: modifiedAt,
            originalImageCount: imageCount,
            captureCheckpointCount: captureCheckpointCount,
            reconstructionIntermediateCount: reconstructionCount,
            manifestIsValid: manifest.valid,
            manifestExists: manifest.exists,
            limitation: manifest.limitation
        )
    }

    private func validateManifest(at url: URL) throws -> (exists: Bool, valid: Bool, limitation: String?) {
        guard fileManager.fileExists(atPath: url.path) else { return (false, false, "The draft manifest is missing.") }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true,
              values.isSymbolicLink != true,
              let size = values.fileSize,
              size > 0,
              size <= Self.maximumManifestBytes else {
            return (true, false, "The draft manifest is unsafe or outside the supported size limit.")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            _ = try decoder.decode(ObjectCaptureDraft.self, from: Data(contentsOf: url))
            return (true, true, nil)
        } catch {
            return (true, false, "The draft manifest could not be validated.")
        }
    }

    private func hasUSDZSignature(at url: URL) throws -> Bool {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return try handle.read(upToCount: 4) == Data([0x50, 0x4B, 0x03, 0x04])
    }

    private func safeChildName(_ value: String?) -> String? {
        guard let value,
              !value.isEmpty,
              value == URL(fileURLWithPath: value).lastPathComponent,
              !value.contains("/"),
              !value.contains("\\") else { return nil }
        return value
    }

    private func safeIdentifier(for value: String) -> String {
        UUID(uuidString: value).map { abbreviated($0.uuidString) } ?? String(value.prefix(20))
    }

    private func abbreviated(_ value: String) -> String {
        String(value.prefix(8)).uppercased()
    }

    private func latest(_ dates: Date?...) -> Date? {
        dates.compactMap { $0 }.max()
    }
}
