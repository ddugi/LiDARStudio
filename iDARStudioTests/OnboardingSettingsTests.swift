import Foundation
import Testing
@testable import iDARStudio

struct OnboardingSettingsTests {
    @Test func firstLaunchCompletionAndReopenPersistLocally() throws {
        let suiteName = "OnboardingSettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(!OnboardingPreference.isComplete(in: defaults))
        OnboardingPreference.setComplete(true, in: defaults)
        #expect(OnboardingPreference.isComplete(in: defaults))

        OnboardingPreference.setComplete(false, in: defaults)
        #expect(!OnboardingPreference.isComplete(in: defaults))
    }

    @Test func onboardingLabelsUnverifiedStudiosHonestly() throws {
        let features = Dictionary(uniqueKeysWithValues: OnboardingContent.features.map { ($0.id, $0) })

        #expect(features["object"]?.capabilityLevel == .implemented)
        #expect(features["room"]?.capabilityLevel == .capabilityOnly)
        #expect(features["environment"]?.capabilityLevel == .diagnostic)
        #expect(features["library"]?.capabilityLevel == .localLibrary)
        #expect(features["room"]?.summary.localizedCaseInsensitiveContains("not yet physically verified") == true)
        #expect(features["environment"]?.summary.localizedCaseInsensitiveContains("not a finished environment scanner") == true)
    }

    @Test func objectPreparationCoversRequestedGuidanceWithoutScores() {
        let items = ObjectScanPreparationGuide.items
        let ids = Set(items.map(\.id))
        let allText = items.map { "\($0.title) \($0.detail)" }.joined(separator: " ").lowercased()

        #expect(ids == ["lighting", "surface", "overview", "slow", "overlap", "detail", "center", "materials"])
        #expect(allText.contains("diffuse"))
        #expect(allText.contains("matte"))
        #expect(allText.contains("whole object"))
        #expect(allText.contains("move slowly"))
        #expect(allText.contains("overlapping"))
        #expect(allText.contains("focus"))
        #expect(allText.contains("center"))
        #expect(allText.contains("reflective"))
        #expect(!allText.contains("percent"))
        #expect(!allText.contains("score"))
    }

    @Test func preferredPhotoTargetSettingUsesExistingCapturePreference() throws {
        let suiteName = "PhotoTargetSettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        PhotoTargetPreference.write(75, to: defaults)
        #expect(PhotoTargetPreference.read(from: defaults) == 75)

        PhotoTargetPreference.write(nil, to: defaults)
        #expect(PhotoTargetPreference.read(from: defaults) == nil)
    }

    @Test func storageBreakdownCountsRealCategoriesAndExcludesSymlinks() throws {
        let root = temporaryRoot()
        let diagnostics = temporaryRoot()
        let external = temporaryRoot()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: diagnostics)
            try? FileManager.default.removeItem(at: external)
        }

        let models = root.appending(path: "Models", directoryHint: .isDirectory)
        let captures = root.appending(path: "Captures/scan/Images", directoryHint: .isDirectory)
        let captureRoot = root.appending(path: "Captures/scan", directoryHint: .isDirectory)
        let captureCheckpoints = captureRoot.appending(path: "CaptureCheckpoints", directoryHint: .isDirectory)
        let reconstruction = captureRoot.appending(path: "ReconstructionCheckpoints", directoryHint: .isDirectory)
        let previews = root.appending(path: "Previews", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: models, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: captures, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: captureCheckpoints, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: reconstruction, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: previews, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: diagnostics, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)

        try Data(repeating: 0x01, count: 100).write(to: models.appending(path: "model.usdz"))
        try Data(repeating: 0x02, count: 200).write(to: captures.appending(path: "photo.jpg"))
        try Data(repeating: 0x03, count: 30).write(to: captureRoot.appending(path: "capture.json"))
        try Data(repeating: 0x08, count: 31).write(to: captureCheckpoints.appending(path: "capture.bin"))
        try Data(repeating: 0x09, count: 41).write(to: reconstruction.appending(path: "mesh.bin"))
        try Data(repeating: 0x0A, count: 7).write(to: captureRoot.appending(path: "unknown.bin"))
        try Data(repeating: 0x04, count: 40).write(to: previews.appending(path: "preview.jpg"))
        try Data(repeating: 0x05, count: 50).write(to: root.appending(path: "scans.json"))
        try Data(repeating: 0x06, count: 300).write(to: diagnostics.appending(path: "frame.bin"))

        let externalFile = external.appending(path: "private.bin")
        try Data(repeating: 0x07, count: 500).write(to: externalFile)
        try FileManager.default.createSymbolicLink(
            at: models.appending(path: "external.usdz"),
            withDestinationURL: externalFile
        )

        let breakdown = try LocalStorageUsageCalculator().calculate(
            scanRoot: root,
            diagnosticRoot: diagnostics
        )

        #expect(breakdown.modelsBytes == 100)
        #expect(breakdown.capturePhotographsBytes == 200)
        #expect(breakdown.captureCheckpointsBytes == 31)
        #expect(breakdown.reconstructionIntermediatesBytes == 41)
        #expect(breakdown.previewsBytes == 40)
        #expect(breakdown.metadataBytes == 80)
        #expect(breakdown.diagnosticDatasetsBytes == 300)
        #expect(breakdown.otherManagedDataBytes == 7)
        #expect(breakdown.totalBytes == 799)
    }

    @Test func emptyStorageRootsReportZeroWithoutCreatingUserData() throws {
        let root = temporaryRoot()
        let diagnostics = temporaryRoot()

        let breakdown = try LocalStorageUsageCalculator().calculate(
            scanRoot: root,
            diagnosticRoot: diagnostics
        )

        #expect(breakdown == LocalStorageBreakdown(
            modelsBytes: 0,
            capturePhotographsBytes: 0,
            captureCheckpointsBytes: 0,
            reconstructionIntermediatesBytes: 0,
            previewsBytes: 0,
            metadataBytes: 0,
            diagnosticDatasetsBytes: 0,
            otherManagedDataBytes: 0
        ))
        #expect(!FileManager.default.fileExists(atPath: root.path))
        #expect(!FileManager.default.fileExists(atPath: diagnostics.path))
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    }
}
