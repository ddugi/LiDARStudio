import RoomPlan
import SwiftUI

struct RoomCaptureContainer: UIViewRepresentable {
    @ObservedObject var coordinator: RoomCaptureCoordinator

    func makeUIView(context: Context) -> RoomCaptureView {
        let view = RoomCaptureView(frame: .zero)
        coordinator.attach(view)
        return view
    }

    func updateUIView(_ uiView: RoomCaptureView, context: Context) {
        coordinator.attach(uiView)
    }

    static func dismantleUIView(_ uiView: RoomCaptureView, coordinator: Void) {
        uiView.captureSession.stop()
    }
}
