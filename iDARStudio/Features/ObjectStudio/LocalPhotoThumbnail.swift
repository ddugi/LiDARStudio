import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct LocalPhotoThumbnail: View {
    let url: URL

    @State private var image: Image?

    var body: some View {
        Group {
            if let image {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                ProgressView().tint(StudioTheme.accent)
            }
        }
        .task(id: url) {
            let thumbnailData = await Task.detached(priority: .utility) {
                LocalImageThumbnailer.makeJPEGData(for: url, maximumPixelSize: 360)
            }.value
            guard !Task.isCancelled,
                  let thumbnailData,
                  let platformImage = UIImage(data: thumbnailData) else { return }
            image = Image(uiImage: platformImage)
        }
    }
}

nonisolated enum LocalImageThumbnailer {
    static func makeJPEGData(for url: URL, maximumPixelSize: Int) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, thumbnail, [kCGImageDestinationLossyCompressionQuality: 0.78] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
