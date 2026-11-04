import Foundation
import Testing
import UIKit
@testable import iDARStudio

struct RGBDDatasetTests {
    @Test @MainActor func validSynchronizedDatasetPassesStructuralValidation() throws {
        let dataset = try makeDataset(timestamps: [1.0, 1.5])
        defer { try? FileManager.default.removeItem(at: dataset) }

        let report = RGBDDatasetValidator.validate(datasetURL: dataset)

        #expect(report.isValid)
        #expect(report.framesChecked == 2)
    }

    @Test @MainActor func nonIncreasingTimestampsAreRejected() throws {
        let dataset = try makeDataset(timestamps: [2.0, 2.0])
        defer { try? FileManager.default.removeItem(at: dataset) }

        let report = RGBDDatasetValidator.validate(datasetURL: dataset)

        #expect(!report.isValid)
        #expect(report.errors.contains { $0.contains("strictly increasing") })
    }

    @Test @MainActor func missingDepthPayloadIsRejectedWithoutDeletingDataset() throws {
        let dataset = try makeDataset(timestamps: [1.0])
        defer { try? FileManager.default.removeItem(at: dataset) }
        let depthURL = dataset.appendingPathComponent("frames/000000.depth.f32")
        try FileManager.default.removeItem(at: depthURL)

        let report = RGBDDatasetValidator.validate(datasetURL: dataset)

        #expect(!report.isValid)
        #expect(FileManager.default.fileExists(atPath: dataset.path))
        #expect(report.errors.contains { $0.contains("depth file") })
    }

    @Test @MainActor func malformedCameraPoseIsRejected() throws {
        let dataset = try makeDataset(timestamps: [1.0], invalidPose: true)
        defer { try? FileManager.default.removeItem(at: dataset) }

        let report = RGBDDatasetValidator.validate(datasetURL: dataset)

        #expect(!report.isValid)
        #expect(report.errors.contains { $0.contains("homogeneous pose") })
    }

    @MainActor
    private func makeDataset(
        timestamps: [TimeInterval],
        invalidPose: Bool = false
    ) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rgbd-test-\(UUID().uuidString)", isDirectory: true)
        let frames = root.appendingPathComponent("frames", isDirectory: true)
        try FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2), format: format)
        let jpeg = renderer.jpegData(withCompressionQuality: 0.9, actions: { context in
            UIColor.systemGreen.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        })

        var metadataFiles: [String] = []
        for (sequence, timestamp) in timestamps.enumerated() {
            let stem = String(format: "%06d", sequence)
            let colorName = "frames/\(stem).color.jpg"
            let depthName = "frames/\(stem).depth.f32"
            let confidenceName = "frames/\(stem).confidence.u8"
            try jpeg.write(to: root.appendingPathComponent(colorName))
            try Data(count: 2 * 2 * MemoryLayout<Float32>.size)
                .write(to: root.appendingPathComponent(depthName))
            try Data([2, 2, 2, 2]).write(to: root.appendingPathComponent(confidenceName))

            var transform: [Float] = [
                1, 0, 0, 0,
                0, 1, 0, 0,
                0, 0, 1, 0,
                0, 0, 0, 1
            ]
            if invalidPose { transform[15] = 0 }
            let metadata = RGBDFrameMetadata(
                schemaVersion: 1,
                sequence: sequence,
                timestamp: timestamp,
                trackingState: "normal",
                cameraIntrinsics: [100, 0, 0, 0, 100, 0, 1, 1, 1],
                cameraTransform: transform,
                color: RGBDColorFile(
                    filename: colorName,
                    codec: "JPEG fixture",
                    resolution: RGBDResolution(width: 2, height: 2),
                    sourcePixelFormat: 0
                ),
                depth: RGBDDepthFile(
                    filename: depthName,
                    source: "test fixture",
                    resolution: RGBDResolution(width: 2, height: 2),
                    sourcePixelFormat: 0,
                    sourceBytesPerRow: 8,
                    storedBytesPerRow: 8
                ),
                confidence: RGBDConfidenceFile(
                    filename: confidenceName,
                    resolution: RGBDResolution(width: 2, height: 2),
                    sourcePixelFormat: 0,
                    sourceBytesPerRow: 2,
                    storedBytesPerRow: 2
                )
            )
            let metadataName = "frames/\(stem).json"
            try encoder().encode(metadata).write(to: root.appendingPathComponent(metadataName))
            metadataFiles.append(metadataName)
        }

        var manifest = RGBDDatasetManifest(
            datasetID: UUID(),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            device: RGBDDeviceInfo(model: "Test", systemName: "iOS", systemVersion: "Test"),
            configuration: RGBDRecordingConfiguration(
                requestedDepthSource: "sceneDepth",
                sampleIntervalSeconds: 0.5,
                maximumFrames: 180,
                maximumPendingWrites: 2,
                colorCodec: "JPEG fixture"
            ),
            sensorAvailability: RGBDSensorAvailability(
                worldTrackingSupported: true,
                sceneDepthSupported: true,
                rgbObserved: true,
                depthObserved: true,
                confidenceObserved: true
            )
        )
        manifest.status = "completed"
        manifest.completedAt = Date(timeIntervalSince1970: 1_700_000_100)
        manifest.counts.framesAccepted = timestamps.count
        manifest.counts.framesWritten = timestamps.count
        manifest.counts.rgbFramesWritten = timestamps.count
        manifest.counts.depthFramesWritten = timestamps.count
        manifest.counts.confidenceFramesWritten = timestamps.count
        manifest.frameMetadataFiles = metadataFiles
        manifest.colorResolutions = [RGBDResolution(width: 2, height: 2)]
        manifest.depthResolutions = [RGBDResolution(width: 2, height: 2)]
        try encoder().encode(manifest).write(to: root.appendingPathComponent("manifest.json"))
        return root
    }

    private func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
