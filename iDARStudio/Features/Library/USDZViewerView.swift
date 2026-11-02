import QuickLook
import SwiftUI

struct USDZViewerView: View {
    let modelURL: URL
    let title: String

    var body: some View {
        ZStack(alignment: .bottom) {
            StudioBackground()
            QuickLookModelPreview(url: modelURL)
                .ignoresSafeArea(edges: .bottom)
            ShareLink(item: modelURL) {
                Label("Share USDZ", systemImage: "square.and.arrow.up")
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(StudioTheme.accent)
            .foregroundStyle(.black)
            .padding(.bottom, 18)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct QuickLookModelPreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        if context.coordinator.url != url {
            context.coordinator.url = url
            controller.reloadData()
        }
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}
