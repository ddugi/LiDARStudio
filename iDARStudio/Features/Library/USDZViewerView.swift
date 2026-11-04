import QuickLook
import SwiftUI

nonisolated struct ModelFileInfo: Equatable, Sendable {
    let fileName: String
    let sizeBytes: Int64
    let modifiedAt: Date?

    static func inspect(_ url: URL) throws -> ModelFileInfo {
        guard url.pathExtension.lowercased() == "usdz",
              FileManager.default.fileExists(atPath: url.path) else {
            throw ModelFileError.missing
        }
        let values = try url.resourceValues(forKeys: [
            .fileSizeKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .contentModificationDateKey
        ])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw ModelFileError.invalid }
        let size = Int64(values.fileSize ?? 0)
        guard size >= 64 else { throw ModelFileError.invalid }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard try handle.read(upToCount: 4) == Data([0x50, 0x4B, 0x03, 0x04]) else { throw ModelFileError.invalid }
        return ModelFileInfo(
            fileName: url.lastPathComponent,
            sizeBytes: size,
            modifiedAt: values.contentModificationDate
        )
    }
}

nonisolated enum ModelFileError: LocalizedError, Equatable {
    case missing
    case invalid

    var errorDescription: String? {
        switch self {
        case .missing: "The USDZ model file is missing."
        case .invalid: "The model is empty, invalid, or not a regular USDZ file."
        }
    }
}

struct USDZViewerView: View {
    let modelURL: URL
    let title: String
    @State private var result: Result<ModelFileInfo, Error>?

    var body: some View {
        ZStack {
            StudioBackground()
            switch result {
            case .success(let info): viewer(info)
            case .failure(let error):
                ContentUnavailableView("Unable to Open Model", systemImage: "cube.transparent.fill", description: Text(error.localizedDescription))
            case nil:
                ProgressView("Validating model…").tint(StudioTheme.accent)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if case .some(.success) = result {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: modelURL) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share or export model")
                }
            }
        }
        .task(id: modelURL) {
            result = nil
            result = await Task.detached(priority: .utility) {
                Result { try ModelFileInfo.inspect(modelURL) }
            }.value
        }
    }

    private func viewer(_ info: ModelFileInfo) -> some View {
        ZStack(alignment: .bottom) {
            QuickLookModelPreview(url: modelURL).ignoresSafeArea(edges: .bottom)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(info.fileName).font(.caption.weight(.semibold)).lineLimit(1)
                    Text("USDZ · \(ByteCountFormatter.string(fromByteCount: info.sizeBytes, countStyle: .file)) · Local")
                        .font(.caption2).foregroundStyle(StudioTheme.secondaryText)
                }
                Spacer()
                ShareLink(item: modelURL) {
                    Image(systemName: "square.and.arrow.up").frame(width: 44, height: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(StudioTheme.accent)
                .foregroundStyle(.black)
                .accessibilityLabel("Share or save model to Files")
            }
            .padding(12)
            .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 18))
            .padding(14)
        }
    }
}

private struct QuickLookModelPreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

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
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { url as NSURL }
    }
}
