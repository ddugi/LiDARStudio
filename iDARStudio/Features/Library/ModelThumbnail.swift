import Combine
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

nonisolated struct ModelThumbnailCache: Sendable {
    let directory: URL

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory.standardizedFileURL
        } else {
            let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            self.directory = caches
                .appending(path: "LiDARStudio", directoryHint: .isDirectory)
                .appending(path: "ModelThumbnails", directoryHint: .isDirectory)
        }
    }

    func cachedURL(scanID: UUID, maximumPixelSize: Int) -> URL {
        directory.appending(path: "\(scanID.uuidString)-\(maximumPixelSize).png")
    }

    func validCachedData(for modelURL: URL, scanID: UUID, maximumPixelSize: Int) -> Data? {
        let cachedURL = cachedURL(scanID: scanID, maximumPixelSize: maximumPixelSize)
        guard FileManager.default.fileExists(atPath: cachedURL.path),
              let modelAttributes = try? FileManager.default.attributesOfItem(atPath: modelURL.path),
              let cacheAttributes = try? FileManager.default.attributesOfItem(atPath: cachedURL.path),
              let cacheValues = try? cachedURL.resourceValues(
                forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
              ),
              cacheValues.isRegularFile == true,
              cacheValues.isSymbolicLink != true,
              (cacheValues.fileSize ?? 0) > 0,
              let modelModifiedAt = modelAttributes[.modificationDate] as? Date,
              let cacheModifiedAt = cacheAttributes[.modificationDate] as? Date,
              cacheModifiedAt >= modelModifiedAt else {
            return nil
        }
        return try? Data(contentsOf: cachedURL, options: [.mappedIfSafe])
    }

    func store(_ data: Data, scanID: UUID, maximumPixelSize: Int) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(
            to: cachedURL(scanID: scanID, maximumPixelSize: maximumPixelSize),
            options: .atomic
        )
    }
}

@MainActor
final class ModelThumbnailLoader: ObservableObject {
    @Published private(set) var image: UIImage?
    @Published private(set) var didFail = false

    private let cache: ModelThumbnailCache

    init(cache: ModelThumbnailCache = ModelThumbnailCache()) {
        self.cache = cache
    }

    func load(
        scanID: UUID,
        previewURL: URL?,
        modelURL: URL?,
        maximumPixelSize: Int
    ) async {
        image = nil
        didFail = false

        if let previewURL,
           let data = await Task.detached(priority: .utility, operation: {
               LocalImageThumbnailer.makeJPEGData(
                   for: previewURL,
                   maximumPixelSize: maximumPixelSize
               )
           }).value,
           !Task.isCancelled {
            image = UIImage(data: data)
            return
        }

        guard let modelURL else {
            didFail = true
            return
        }

        if let cachedData = await Task.detached(priority: .utility, operation: { [cache] in
            cache.validCachedData(
                for: modelURL,
                scanID: scanID,
                maximumPixelSize: maximumPixelSize
            )
        }).value,
           !Task.isCancelled,
           let cachedImage = UIImage(data: cachedData) {
            image = cachedImage
            return
        }

        guard let generatedData = await Self.generateThumbnailData(
            for: modelURL,
            maximumPixelSize: maximumPixelSize
        ), !Task.isCancelled else {
            didFail = true
            return
        }

        image = UIImage(data: generatedData)
        await Task.detached(priority: .utility, operation: { [cache] in
            try? cache.store(
                generatedData,
                scanID: scanID,
                maximumPixelSize: maximumPixelSize
            )
        }).value
    }

    private static func generateThumbnailData(
        for modelURL: URL,
        maximumPixelSize: Int
    ) async -> Data? {
        let size = CGSize(width: maximumPixelSize, height: maximumPixelSize)
        let request = QLThumbnailGenerator.Request(
            fileAt: modelURL,
            size: size,
            scale: 1,
            representationTypes: .thumbnail
        )
        request.contentType = .usdz

        return await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                continuation.resume(returning: representation?.uiImage.pngData())
            }
        }
    }
}

struct ModelThumbnailView: View {
    let scanID: UUID
    let previewURL: URL?
    let modelURL: URL?
    let kind: ScanKind
    var maximumPixelSize = 480

    @StateObject private var loader = ModelThumbnailLoader()

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [StudioTheme.elevatedSurface, StudioTheme.surface],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else {
                Image(systemName: kind.systemImage)
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(loader.didFail ? StudioTheme.secondaryText : StudioTheme.accent)
            }
        }
        .clipped()
        .accessibilityHidden(true)
        .task(id: thumbnailIdentity) {
            await loader.load(
                scanID: scanID,
                previewURL: previewURL,
                modelURL: modelURL,
                maximumPixelSize: maximumPixelSize
            )
        }
    }

    private var thumbnailIdentity: String {
        "\(scanID.uuidString)|\(previewURL?.path ?? "")|\(modelURL?.path ?? "")|\(maximumPixelSize)"
    }
}
