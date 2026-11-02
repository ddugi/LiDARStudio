import SwiftUI

struct RoomStudioView: View {
    private let capabilities = DeviceCapabilityService.current()

    var body: some View {
        ScannerFoundationView(
            title: "Room Studio",
            description: "Create structured architectural captures with Apple RoomPlan.",
            systemImage: "square.split.bottomrightquarter",
            hardwareSupported: capabilities.supportsRoomPlan,
            unavailableMessage: "RoomPlan requires a LiDAR-equipped supported iPhone or iPad."
        )
    }
}
