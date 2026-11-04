import Foundation

nonisolated struct RGBDResolution: Codable, Equatable, Hashable, Sendable {
    let width: Int
    let height: Int
}

nonisolated struct RGBDRecordingConfiguration: Codable, Equatable, Sendable {
    let requestedDepthSource: String
    let sampleIntervalSeconds: Double
    let maximumFrames: Int
    let maximumPendingWrites: Int
    let colorCodec: String
}

nonisolated struct RGBDDeviceInfo: Codable, Equatable, Sendable {
    let model: String
    let systemName: String
    let systemVersion: String
}

nonisolated struct RGBDSensorAvailability: Codable, Equatable, Sendable {
    let worldTrackingSupported: Bool
    let sceneDepthSupported: Bool
    var rgbObserved: Bool
    var depthObserved: Bool
    var confidenceObserved: Bool
}

nonisolated struct RGBDRecordingCounts: Codable, Equatable, Sendable {
    var sessionCallbacks = 0
    var framesAccepted = 0
    var framesWritten = 0
    var rgbFramesWritten = 0
    var depthFramesWritten = 0
    var confidenceFramesWritten = 0
    var droppedRateLimited = 0
    var droppedQueueFull = 0
    var droppedNoDepth = 0
    var droppedAtFrameLimit = 0
    var writeFailures = 0

    var totalDropped: Int {
        droppedRateLimited + droppedQueueFull + droppedNoDepth + droppedAtFrameLimit + writeFailures
    }
}

nonisolated struct RGBDDatasetManifest: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let datasetID: UUID
    let createdAt: Date
    var completedAt: Date?
    var status: String
    let coordinateConvention: String
    let matrixStorage: String
    let depthUnit: String
    let colorOrientation: String
    let device: RGBDDeviceInfo
    let configuration: RGBDRecordingConfiguration
    var sensorAvailability: RGBDSensorAvailability
    var counts: RGBDRecordingCounts
    var colorResolutions: [RGBDResolution]
    var depthResolutions: [RGBDResolution]
    var trackingStateCounts: [String: Int]
    var frameMetadataFiles: [String]
    var sensorLimitations: [String]

    init(
        datasetID: UUID,
        createdAt: Date,
        device: RGBDDeviceInfo,
        configuration: RGBDRecordingConfiguration,
        sensorAvailability: RGBDSensorAvailability
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.datasetID = datasetID
        self.createdAt = createdAt
        self.completedAt = nil
        self.status = "recording"
        self.coordinateConvention = "ARKit right-handed world; camera transform is T_world_camera"
        self.matrixStorage = "column-major arrays"
        self.depthUnit = "meters as Float32 little-endian packed rows"
        self.colorOrientation = "ARKit capturedImage native pixel-buffer orientation; no rotation applied"
        self.device = device
        self.configuration = configuration
        self.sensorAvailability = sensorAvailability
        self.counts = RGBDRecordingCounts()
        self.colorResolutions = []
        self.depthResolutions = []
        self.trackingStateCounts = [:]
        self.frameMetadataFiles = []
        self.sensorLimitations = [
            "ARKit controls camera exposure, focus, sensor fusion, depth filtering, and calibration.",
            "sceneDepth is LiDAR-derived scene depth, not raw time-of-flight returns or per-ray measurements.",
            "RGB and depth resolutions differ; consumers must use the recorded intrinsics and dimensions.",
            "Frames are intentionally sampled and may be dropped when the bounded writer queue is full.",
            "Camera poses are ARKit visual-inertial estimates and are not external ground truth."
        ]
    }
}

nonisolated struct RGBDColorFile: Codable, Equatable, Sendable {
    let filename: String
    let codec: String
    let resolution: RGBDResolution
    let sourcePixelFormat: UInt32
}

nonisolated struct RGBDDepthFile: Codable, Equatable, Sendable {
    let filename: String
    let source: String
    let resolution: RGBDResolution
    let sourcePixelFormat: UInt32
    let sourceBytesPerRow: Int
    let storedBytesPerRow: Int
}

nonisolated struct RGBDConfidenceFile: Codable, Equatable, Sendable {
    let filename: String
    let resolution: RGBDResolution
    let sourcePixelFormat: UInt32
    let sourceBytesPerRow: Int
    let storedBytesPerRow: Int
}

nonisolated struct RGBDFrameMetadata: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let sequence: Int
    let timestamp: TimeInterval
    let trackingState: String
    let cameraIntrinsics: [Float]
    let cameraTransform: [Float]
    let color: RGBDColorFile
    let depth: RGBDDepthFile
    let confidence: RGBDConfidenceFile?
}

nonisolated struct RGBDDatasetValidationReport: Codable, Equatable, Sendable {
    let datasetURL: URL
    let framesChecked: Int
    let errors: [String]
    let warnings: [String]

    var isValid: Bool { errors.isEmpty }
}
