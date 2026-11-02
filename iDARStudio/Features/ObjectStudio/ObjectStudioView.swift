import SwiftUI

struct ObjectStudioView: View {
    private let capabilities = DeviceCapabilityService.current()

    var body: some View {
        ScannerFoundationView(
            title: "Object Studio",
            description: "Capture a detailed image set for Apple Object Capture photogrammetry.",
            systemImage: "cube.transparent",
            hardwareSupported: capabilities.supportsObjectCapture,
            unavailableMessage: "Object capture requires a supported iPhone camera."
        )
    }
}
