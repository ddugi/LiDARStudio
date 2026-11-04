import ARKit
import AVFoundation
import RoomPlan
import RealityKit
import SwiftUI

nonisolated struct DeviceCapabilities: Equatable, Sendable {
    let hasCamera: Bool
    let supportsWorldTracking: Bool
    let supportsSceneDepth: Bool
    let supportsLiDARMesh: Bool
    let supportsRoomPlan: Bool
    let supportsObjectCapture: Bool
    let supportsOnDevicePhotogrammetry: Bool
}

enum DeviceCapabilityService {
    static func current() -> DeviceCapabilities {
        let hasCamera = AVCaptureDevice.default(for: .video) != nil
        return DeviceCapabilities(
            hasCamera: hasCamera,
            supportsWorldTracking: ARWorldTrackingConfiguration.isSupported,
            supportsSceneDepth: ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth),
            supportsLiDARMesh: ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh),
            supportsRoomPlan: RoomCaptureSession.isSupported,
            supportsObjectCapture: ObjectCaptureSession.isSupported,
            supportsOnDevicePhotogrammetry: PhotogrammetrySession.isSupported
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

    var title: String {
        switch self {
        case .authorized: "Allowed"
        case .notDetermined: "Not requested"
        case .denied: "Not allowed"
        }
    }
}
