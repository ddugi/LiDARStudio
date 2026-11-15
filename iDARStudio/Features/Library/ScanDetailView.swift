import SwiftUI

struct ScanDetailView: View {
    @EnvironmentObject private var library: ScanLibrary
    @Environment(\.dismiss) private var dismiss
    let scanID: UUID
    @State private var showsRename = false
    @State private var showsDeleteConfirmation = false
    @State private var proposedName = ""
    @State private var modelInfo: ModelFileInfo?

    private var scan: ScanMetadata? { library.scans.first { $0.id == scanID } }

    var body: some View {
        ZStack {
            StudioBackground()
            if let scan {
                details(scan)
            } else {
                ContentUnavailableView("Scan unavailable", systemImage: "questionmark.folder", description: Text("This scan is no longer present in the local library."))
            }
        }
        .navigationTitle(scan?.name ?? "Scan Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let scan {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        library.toggleFavorite(scan)
                    } label: {
                        Image(systemName: scan.isFavorite ? "star.fill" : "star")
                    }
                    .accessibilityLabel(scan.isFavorite ? "Remove from favorites" : "Add to favorites")
                }
            }
        }
        .alert("Rename Scan", isPresented: $showsRename) {
            TextField("Scan name", text: $proposedName)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                if let scan { _ = library.rename(scan, to: proposedName) }
            }
        } message: {
            Text("Choose a name stored in this scan's local metadata.")
        }
        .confirmationDialog("Delete this scan?", isPresented: $showsDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete Scan and Local Files", role: .destructive) {
                if let scan, library.delete(scan) { dismiss() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the model, preview, captured photographs, and metadata from this iPhone. This cannot be undone.")
        }
        .alert("Library action failed", isPresented: errorBinding) {
            Button("OK") { library.clearOperationError() }
        } message: {
            Text(library.operationError ?? "Unknown library error")
        }
    }

    private func details(_ scan: ScanMetadata) -> some View {
        let modelURL = library.modelURL(for: scan)
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ModelThumbnailView(
                    scanID: scan.id,
                    previewURL: library.previewURL(for: scan),
                    modelURL: modelURL,
                    kind: scan.kind,
                    maximumPixelSize: 800
                )
                    .frame(height: 230)
                    .clipShape(RoundedRectangle(cornerRadius: 22))

                VStack(alignment: .leading, spacing: 12) {
                    detailRow("Type", value: scan.kind.title)
                    detailRow("Created", value: scan.createdAt.formatted(date: .long, time: .shortened))
                    detailRow("Updated", value: scan.updatedAt.formatted(date: .long, time: .shortened))
                    if let count = scan.photoCount { detailRow("Original photos", value: "\(count)") }
                    detailRow("Format", value: scan.relativeModelPath == nil ? "No model" : "USDZ")
                    detailRow("File name", value: modelInfo?.fileName ?? scan.relativeModelPath ?? "Unavailable")
                    detailRow("File size", value: modelInfo.map { ByteCountFormatter.string(fromByteCount: $0.sizeBytes, countStyle: .file) } ?? "Unknown")
                    if let modifiedAt = modelInfo?.modifiedAt {
                        detailRow("File modified", value: modifiedAt.formatted(date: .long, time: .shortened))
                    }
                    detailRow("Storage", value: "Local on this iPhone")
                }
                .studioCard()

                if let modelURL {
                    NavigationLink {
                        USDZViewerView(modelURL: modelURL, title: scan.name)
                    } label: {
                        Label("View in 3D", systemImage: "cube.transparent").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(StudioTheme.accent)
                    .foregroundStyle(.black)

                    ShareLink(item: modelURL) {
                        Label("Share / Save to Files", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Label("The model file is missing, empty, invalid, or outside the protected local Models folder.", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline).foregroundStyle(StudioTheme.warning).studioCard()
                }

                Button {
                    proposedName = scan.name
                    showsRename = true
                } label: {
                    Label("Rename", systemImage: "pencil").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)

                Button(role: .destructive) {
                    showsDeleteConfirmation = true
                } label: {
                    Label("Delete Scan", systemImage: "trash").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
            .padding(18)
        }
        .task(id: modelURL) {
            guard let modelURL else {
                modelInfo = nil
                return
            }
            modelInfo = try? await Task.detached(priority: .utility) {
                try ModelFileInfo.inspect(modelURL)
            }.value
        }
    }

    private func detailRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(StudioTheme.secondaryText)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { library.operationError != nil }, set: { if !$0 { library.clearOperationError() } })
    }
}
