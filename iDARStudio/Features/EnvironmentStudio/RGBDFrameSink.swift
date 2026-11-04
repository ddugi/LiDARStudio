import ARKit
import CoreImage
import Foundation
import ImageIO

nonisolated final class RGBDFrameSink: @unchecked Sendable {
    struct Snapshot: Equatable, Sendable {
        let sessionCallbacks: Int
        let framesAccepted: Int
        let framesWritten: Int
        let depthFramesWritten: Int
        let confidenceFramesWritten: Int
        let droppedFrames: Int
        let pendingWrites: Int
        let reachedFrameLimit: Bool
        let datasetURL: URL?
    }

    struct Completion: Sendable {
        let datasetURL: URL
        let manifest: RGBDDatasetManifest
        let validation: RGBDDatasetValidationReport
    }

    enum SinkError: LocalizedError {
        case alreadyRecording
        case notRecording
        case cannotCreatePixelData
        case cannotEncodeColor
        case cannotWriteManifest

        var errorDescription: String? {
            switch self {
            case .alreadyRecording: "An RGB-D recording is already active."
            case .notRecording: "No RGB-D recording is active."
            case .cannotCreatePixelData: "A sensor pixel buffer could not be read."
            case .cannotEncodeColor: "An RGB camera frame could not be encoded."
            case .cannotWriteManifest: "The RGB-D dataset manifest could not be written."
            }
        }
    }

    private struct PendingFrame: @unchecked Sendable {
        let sequence: Int
        let timestamp: TimeInterval
        let trackingState: String
        let cameraIntrinsics: [Float]
        let cameraTransform: [Float]
        let colorBuffer: CVPixelBuffer
        let depthBuffer: CVPixelBuffer
        let confidenceBuffer: CVPixelBuffer?
        let depthSource: String
    }

    private struct State {
        var isRecording = false
        var isFinishing = false
        var datasetURL: URL?
        var manifest: RGBDDatasetManifest?
        var lastAcceptedTimestamp: TimeInterval?
        var pendingWrites = 0
        var lastSnapshotPublication = 0.0
    }

    private let configuration = RGBDRecordingConfiguration(
        requestedDepthSource: "sceneDepth",
        sampleIntervalSeconds: 0.5,
        maximumFrames: 180,
        maximumPendingWrites: 2,
        colorCodec: "JPEG quality 0.92"
    )
    private let lock = NSLock()
    private let writerQueue = DispatchQueue(
        label: "se.dugiselmanaj.lidarstudio2.rgbd-writer",
        qos: .utility
    )
    private let imageContext = CIContext(options: [.cacheIntermediates: false])
    private var state = State()

    var onSnapshot: (@Sendable (Snapshot) -> Void)?
    var onFatalError: (@Sendable (String) -> Void)?

    func begin(
        rootDirectory: URL,
        device: RGBDDeviceInfo,
        worldTrackingSupported: Bool,
        sceneDepthSupported: Bool
    ) throws -> URL {
        let datasetID = UUID()
        let datasetURL = rootDirectory.appendingPathComponent(datasetID.uuidString, isDirectory: true)
        let framesURL = datasetURL.appendingPathComponent("frames", isDirectory: true)

        try lock.withLock {
            guard !state.isRecording, !state.isFinishing else { throw SinkError.alreadyRecording }
            try FileManager.default.createDirectory(at: framesURL, withIntermediateDirectories: true)
            let manifest = RGBDDatasetManifest(
                datasetID: datasetID,
                createdAt: Date(),
                device: device,
                configuration: configuration,
                sensorAvailability: RGBDSensorAvailability(
                    worldTrackingSupported: worldTrackingSupported,
                    sceneDepthSupported: sceneDepthSupported,
                    rgbObserved: false,
                    depthObserved: false,
                    confidenceObserved: false
                )
            )
            try writeManifest(manifest, to: datasetURL)
            state = State(
                isRecording: true,
                isFinishing: false,
                datasetURL: datasetURL,
                manifest: manifest,
                lastAcceptedTimestamp: nil,
                pendingWrites: 0,
                lastSnapshotPublication: 0
            )
        }
        publishSnapshot(force: true)
        return datasetURL
    }

    func offer(frame: ARFrame) {
        let depthData = frame.sceneDepth ?? frame.smoothedSceneDepth
        guard let depthData else {
            lock.withLock {
                guard state.isRecording else { return }
                state.manifest?.counts.sessionCallbacks += 1
                state.manifest?.counts.droppedNoDepth += 1
            }
            publishSnapshot()
            return
        }

        let pending: PendingFrame? = lock.withLock {
            guard state.isRecording, var manifest = state.manifest else { return nil }
            manifest.counts.sessionCallbacks += 1

            if manifest.counts.framesAccepted >= configuration.maximumFrames {
                manifest.counts.droppedAtFrameLimit += 1
                state.manifest = manifest
                return nil
            }
            if let last = state.lastAcceptedTimestamp,
               frame.timestamp - last < configuration.sampleIntervalSeconds {
                manifest.counts.droppedRateLimited += 1
                state.manifest = manifest
                return nil
            }
            if state.pendingWrites >= configuration.maximumPendingWrites {
                manifest.counts.droppedQueueFull += 1
                state.manifest = manifest
                return nil
            }

            let sequence = manifest.counts.framesAccepted
            manifest.counts.framesAccepted += 1
            manifest.sensorAvailability.rgbObserved = true
            manifest.sensorAvailability.depthObserved = true
            let tracking = Self.trackingDescription(frame.camera.trackingState)
            manifest.trackingStateCounts[tracking, default: 0] += 1
            state.manifest = manifest
            state.lastAcceptedTimestamp = frame.timestamp
            state.pendingWrites += 1

            return PendingFrame(
                sequence: sequence,
                timestamp: frame.timestamp,
                trackingState: tracking,
                cameraIntrinsics: Self.flatten(frame.camera.intrinsics),
                cameraTransform: Self.flatten(frame.camera.transform),
                colorBuffer: frame.capturedImage,
                depthBuffer: depthData.depthMap,
                confidenceBuffer: depthData.confidenceMap,
                depthSource: frame.sceneDepth != nil ? "sceneDepth" : "smoothedSceneDepth"
            )
        }

        guard let pending else {
            publishSnapshot()
            return
        }
        publishSnapshot(force: true)
        writerQueue.async { [weak self] in self?.write(pending) }
    }

    func finish(status: String = "completed") async throws -> Completion {
        let canFinish = lock.withLock {
            guard state.isRecording, !state.isFinishing else { return false }
            state.isRecording = false
            state.isFinishing = true
            return true
        }
        guard canFinish else { throw SinkError.notRecording }

        return try await withCheckedThrowingContinuation { continuation in
            writerQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: SinkError.notRecording)
                    return
                }
                do {
                    let result = try self.finalize(status: status)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func currentSnapshot() -> Snapshot { snapshot() }

    private func write(_ pending: PendingFrame) {
        do {
            guard let datasetURL = lock.withLock({ state.datasetURL }) else {
                throw SinkError.notRecording
            }
            let frameMetadata = try writeFrame(pending, datasetURL: datasetURL)
            lock.withLock {
                guard var manifest = state.manifest else { return }
                manifest.counts.framesWritten += 1
                manifest.counts.rgbFramesWritten += 1
                manifest.counts.depthFramesWritten += 1
                if frameMetadata.confidence != nil {
                    manifest.counts.confidenceFramesWritten += 1
                    manifest.sensorAvailability.confidenceObserved = true
                }
                if !manifest.colorResolutions.contains(frameMetadata.color.resolution) {
                    manifest.colorResolutions.append(frameMetadata.color.resolution)
                }
                if !manifest.depthResolutions.contains(frameMetadata.depth.resolution) {
                    manifest.depthResolutions.append(frameMetadata.depth.resolution)
                }
                manifest.frameMetadataFiles.append("frames/\(Self.stem(pending.sequence)).json")
                state.manifest = manifest
                state.pendingWrites = max(0, state.pendingWrites - 1)
                if manifest.counts.framesWritten.isMultiple(of: 10) {
                    try? writeManifest(manifest, to: datasetURL)
                }
            }
        } catch {
            lock.withLock {
                state.manifest?.counts.writeFailures += 1
                state.pendingWrites = max(0, state.pendingWrites - 1)
            }
            onFatalError?(error.localizedDescription)
        }
        publishSnapshot(force: true)
    }

    private func writeFrame(_ pending: PendingFrame, datasetURL: URL) throws -> RGBDFrameMetadata {
        let framesURL = datasetURL.appendingPathComponent("frames", isDirectory: true)
        let stem = Self.stem(pending.sequence)
        let colorRelative = "frames/\(stem).color.jpg"
        let depthRelative = "frames/\(stem).depth.f32"
        let confidenceRelative = "frames/\(stem).confidence.u8"

        let colorURL = datasetURL.appendingPathComponent(colorRelative)
        let colorImage = CIImage(cvPixelBuffer: pending.colorBuffer)
        guard !colorImage.extent.isEmpty else { throw SinkError.cannotEncodeColor }
        try imageContext.writeJPEGRepresentation(
            of: colorImage,
            to: colorURL,
            colorSpace: CGColorSpaceCreateDeviceRGB(),
            options: [
                CIImageRepresentationOption(
                    rawValue: kCGImageDestinationLossyCompressionQuality as String
                ): 0.92
            ]
        )

        let colorResolution = RGBDResolution(
            width: CVPixelBufferGetWidth(pending.colorBuffer),
            height: CVPixelBufferGetHeight(pending.colorBuffer)
        )
        let depthResolution = RGBDResolution(
            width: CVPixelBufferGetWidth(pending.depthBuffer),
            height: CVPixelBufferGetHeight(pending.depthBuffer)
        )
        let depthRowBytes = depthResolution.width * MemoryLayout<Float32>.size
        let depthData = try packedData(from: pending.depthBuffer, bytesPerPixel: MemoryLayout<Float32>.size)
        try depthData.write(to: datasetURL.appendingPathComponent(depthRelative), options: .atomic)

        var confidenceMetadata: RGBDConfidenceFile?
        if let confidenceBuffer = pending.confidenceBuffer {
            let resolution = RGBDResolution(
                width: CVPixelBufferGetWidth(confidenceBuffer),
                height: CVPixelBufferGetHeight(confidenceBuffer)
            )
            if let confidenceData = try? packedData(from: confidenceBuffer, bytesPerPixel: 1) {
                try? confidenceData.write(
                    to: datasetURL.appendingPathComponent(confidenceRelative),
                    options: .atomic
                )
                if FileManager.default.fileExists(atPath: datasetURL.appendingPathComponent(confidenceRelative).path) {
                    confidenceMetadata = RGBDConfidenceFile(
                        filename: confidenceRelative,
                        resolution: resolution,
                        sourcePixelFormat: CVPixelBufferGetPixelFormatType(confidenceBuffer),
                        sourceBytesPerRow: CVPixelBufferGetBytesPerRow(confidenceBuffer),
                        storedBytesPerRow: resolution.width
                    )
                }
            }
        }

        let metadata = RGBDFrameMetadata(
            schemaVersion: 1,
            sequence: pending.sequence,
            timestamp: pending.timestamp,
            trackingState: pending.trackingState,
            cameraIntrinsics: pending.cameraIntrinsics,
            cameraTransform: pending.cameraTransform,
            color: RGBDColorFile(
                filename: colorRelative,
                codec: configuration.colorCodec,
                resolution: colorResolution,
                sourcePixelFormat: CVPixelBufferGetPixelFormatType(pending.colorBuffer)
            ),
            depth: RGBDDepthFile(
                filename: depthRelative,
                source: pending.depthSource,
                resolution: depthResolution,
                sourcePixelFormat: CVPixelBufferGetPixelFormatType(pending.depthBuffer),
                sourceBytesPerRow: CVPixelBufferGetBytesPerRow(pending.depthBuffer),
                storedBytesPerRow: depthRowBytes
            ),
            confidence: confidenceMetadata
        )
        try Self.encoder().encode(metadata).write(
            to: framesURL.appendingPathComponent("\(stem).json"),
            options: .atomic
        )
        return metadata
    }

    private func packedData(from buffer: CVPixelBuffer, bytesPerPixel: Int) throws -> Data {
        guard CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else {
            throw SinkError.cannotCreatePixelData
        }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            throw SinkError.cannotCreatePixelData
        }

        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let sourceBytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let packedBytesPerRow = width * bytesPerPixel
        guard sourceBytesPerRow >= packedBytesPerRow else { throw SinkError.cannotCreatePixelData }
        var data = Data(capacity: packedBytesPerRow * height)
        for row in 0..<height {
            let rowStart = baseAddress.advanced(by: row * sourceBytesPerRow)
                .assumingMemoryBound(to: UInt8.self)
            data.append(rowStart, count: packedBytesPerRow)
        }
        return data
    }

    private func finalize(status: String) throws -> Completion {
        let values: (URL, RGBDDatasetManifest) = try lock.withLock {
            guard let datasetURL = state.datasetURL, var manifest = state.manifest else {
                throw SinkError.notRecording
            }
            manifest.status = status
            manifest.completedAt = Date()
            state.manifest = manifest
            return (datasetURL, manifest)
        }
        try writeManifest(values.1, to: values.0)
        let validation = RGBDDatasetValidator.validate(datasetURL: values.0)
        lock.withLock {
            state.isFinishing = false
            state.datasetURL = values.0
            state.manifest = values.1
        }
        publishSnapshot()
        return Completion(datasetURL: values.0, manifest: values.1, validation: validation)
    }

    private func snapshot() -> Snapshot {
        lock.withLock {
            let counts = state.manifest?.counts ?? RGBDRecordingCounts()
            return Snapshot(
                sessionCallbacks: counts.sessionCallbacks,
                framesAccepted: counts.framesAccepted,
                framesWritten: counts.framesWritten,
                depthFramesWritten: counts.depthFramesWritten,
                confidenceFramesWritten: counts.confidenceFramesWritten,
                droppedFrames: counts.totalDropped,
                pendingWrites: state.pendingWrites,
                reachedFrameLimit: counts.framesAccepted >= configuration.maximumFrames,
                datasetURL: state.datasetURL
            )
        }
    }

    private func publishSnapshot(force: Bool = false) {
        let now = ProcessInfo.processInfo.systemUptime
        let value: Snapshot? = lock.withLock {
            guard force || now - state.lastSnapshotPublication >= 0.2 else { return nil }
            state.lastSnapshotPublication = now
            let counts = state.manifest?.counts ?? RGBDRecordingCounts()
            return Snapshot(
                sessionCallbacks: counts.sessionCallbacks,
                framesAccepted: counts.framesAccepted,
                framesWritten: counts.framesWritten,
                depthFramesWritten: counts.depthFramesWritten,
                confidenceFramesWritten: counts.confidenceFramesWritten,
                droppedFrames: counts.totalDropped,
                pendingWrites: state.pendingWrites,
                reachedFrameLimit: counts.framesAccepted >= configuration.maximumFrames,
                datasetURL: state.datasetURL
            )
        }
        if let value { onSnapshot?(value) }
    }

    private func writeManifest(_ manifest: RGBDDatasetManifest, to datasetURL: URL) throws {
        do {
            try Self.encoder().encode(manifest).write(
                to: datasetURL.appendingPathComponent("manifest.json"),
                options: .atomic
            )
        } catch {
            throw SinkError.cannotWriteManifest
        }
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static func stem(_ sequence: Int) -> String {
        String(format: "%06d", sequence)
    }

    private static func flatten(_ matrix: simd_float3x3) -> [Float] {
        [
            matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z,
            matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z,
            matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z
        ]
    }

    private static func flatten(_ matrix: simd_float4x4) -> [Float] {
        [
            matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z, matrix.columns.0.w,
            matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z, matrix.columns.1.w,
            matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z, matrix.columns.2.w,
            matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z, matrix.columns.3.w
        ]
    }

    private static func trackingDescription(_ state: ARCamera.TrackingState) -> String {
        switch state {
        case .normal: "normal"
        case .notAvailable: "notAvailable"
        case .limited(let reason):
            switch reason {
            case .initializing: "limited.initializing"
            case .excessiveMotion: "limited.excessiveMotion"
            case .insufficientFeatures: "limited.insufficientFeatures"
            case .relocalizing: "limited.relocalizing"
            @unknown default: "limited.unknown"
            }
        }
    }
}
