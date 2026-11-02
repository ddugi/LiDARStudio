import ARKit
import AVFoundation
import RoomPlan

nonisolated struct DeviceCapabilities: Equatable, Sendable {
    let hasCamera: Bool
    let supportsWorldTracking: Bool
    let supportsLiDARMesh: Bool
    let supportsRoomPlan: Bool

    var supportsObjectCapture: Bool { hasCamera }
}

enum DeviceCapabilityService {
    static func current() -> DeviceCapabilities {
        let hasCamera = AVCaptureDevice.default(for: .video) != nil
        return DeviceCapabilities(
            hasCamera: hasCamera,
            supportsWorldTracking: ARWorldTrackingConfiguration.isSupported,
            supportsLiDARMesh: ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh),
            supportsRoomPlan: RoomCaptureSession.isSupported
        )
    }
}

enum CameraPermission {
    case authorized
    case notDetermined
    case denied

    static var current: CameraPermission {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: .authorized
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    static func request() async -> CameraPermission {
        guard current == .notDetermined else { return current }
        return await AVCaptureDevice.requestAccess(for: .video) ? .authorized : .denied
    }
}
