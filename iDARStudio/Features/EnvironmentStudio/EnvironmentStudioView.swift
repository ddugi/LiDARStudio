import SwiftUI

struct EnvironmentStudioView: View {
    private let capabilities = DeviceCapabilityService.current()

    var body: some View {
        ScannerFoundationView(
            title: "Environment Studio",
            description: "Map larger spaces using ARKit LiDAR scene reconstruction.",
            systemImage: "mountain.2",
            hardwareSupported: capabilities.supportsWorldTracking && capabilities.supportsLiDARMesh,
            unavailableMessage: "Scene reconstruction requires a LiDAR-equipped device with AR world tracking."
        )
    }
}
