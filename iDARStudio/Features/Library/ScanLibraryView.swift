import SwiftUI
import UIKit

struct ScanLibraryView: View {
    @EnvironmentObject private var library: ScanLibrary
    @State private var searchText = ""
    @State private var sortOrder: ScanSortOrder = .newest
    @State private var favoritesOnly = false

    private var visibleScans: [ScanMetadata] {
        ScanQuery.results(
            from: library.scans,
            searchText: searchText,
            sortOrder: sortOrder,
            favoritesOnly: favoritesOnly
        )
    }

    var body: some View {
        ZStack {
            StudioBackground()
            content
        }
        .navigationTitle("My Scans")
        .searchable(text: $searchText, prompt: "Search scans")
        .toolbar { libraryToolbar }
        .alert("Library action failed", isPresented: errorBinding) {
            Button("OK") { library.clearOperationError() }
        } message: {
            Text(library.operationError ?? "Unknown library error")
        }
    }

    @ToolbarContentBuilder
    private var libraryToolbar: some ToolbarContent {
        if case .failed = library.state {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Retry", systemImage: "arrow.clockwise", action: library.reload)
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort", selection: $sortOrder) {
                        ForEach(ScanSortOrder.allCases) { order in Text(order.title).tag(order) }
                    }
                    Divider()
                    Toggle("Favorites Only", isOn: $favoritesOnly)
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel("Filter and sort scans")
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch library.state {
        case .loading:
            ContentUnavailableView {
                Label("Loading scans", systemImage: "square.stack.3d.up")
            } description: {
                ProgressView().tint(StudioTheme.accent)
            }
            .accessibilityLabel("Loading scans")
        case .failed(let message):
            ContentUnavailableView("Library unavailable", systemImage: "exclamationmark.triangle", description: Text(message))
        case .loaded where library.scans.isEmpty:
            ContentUnavailableView {
                Label("No scans yet", systemImage: "cube.transparent")
            } description: {
                Text("Completed scans will appear here and remain local by default.")
            } actions: {
                NavigationLink("Open Object Studio", value: AppDestination.objectStudio)
                    .buttonStyle(.borderedProminent)
                    .tint(StudioTheme.accent)
                    .foregroundStyle(.black)
            }
        case .loaded where visibleScans.isEmpty:
            ContentUnavailableView.search(text: searchText.isEmpty ? "Favorites" : searchText)
        case .loaded:
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 156), spacing: 12)], spacing: 12) {
                    ForEach(visibleScans) { scan in
                        NavigationLink { ScanDetailView(scanID: scan.id) } label: {
                            ScanCard(
                                scan: scan,
                                previewURL: library.previewURL(for: scan),
                                modelAvailable: library.modelURL(for: scan) != nil
                            )
                        }
                        .contextMenu {
                            Button {
                                library.toggleFavorite(scan)
                            } label: {
                                Label(scan.isFavorite ? "Remove Favorite" : "Favorite", systemImage: scan.isFavorite ? "star.slash" : "star")
                            }
                        }
                    }
                }
                .padding(16)
            }
            .refreshable { library.reload() }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { library.operationError != nil }, set: { if !$0 { library.clearOperationError() } })
    }
}

struct ScanThumbnail: View {
    let url: URL?
    let kind: ScanKind

    var body: some View {
        Group {
            if let url, let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    LinearGradient(colors: [StudioTheme.elevatedSurface, StudioTheme.surface], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: kind.systemImage)
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(StudioTheme.accent)
                }
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

private struct ScanCard: View {
    let scan: ScanMetadata
    let previewURL: URL?
    let modelAvailable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScanThumbnail(url: previewURL, kind: scan.kind)
                .frame(height: 118)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(alignment: .topTrailing) {
                    if scan.isFavorite {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.black)
                            .padding(8)
                            .background(StudioTheme.accent, in: Circle())
                            .padding(8)
                    }
                }
            Text(scan.name).font(.headline).foregroundStyle(.white).lineLimit(1)
            Text(scan.updatedAt.formatted(date: .abbreviated, time: .omitted))
                .font(.caption).foregroundStyle(StudioTheme.secondaryText)
            Label(modelAvailable ? "USDZ available" : "Model unavailable", systemImage: modelAvailable ? "checkmark.circle.fill" : "exclamationmark.circle")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(modelAvailable ? StudioTheme.accent : StudioTheme.warning)
                .lineLimit(1)
        }
        .padding(12)
        .background(StudioTheme.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).stroke(StudioTheme.border) }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens scan details")
    }
}
