import SwiftUI
import UIKit

struct ScanLibraryView: View {
    @EnvironmentObject private var library: ScanLibrary
    @State private var searchText = ""
    @State private var sortOrder: ScanSortOrder = .newest
    @State private var favoritesOnly = false
    @AppStorage("scanLibraryPresentation") private var presentation = ScanLibraryPresentation.grid
    @State private var scanToRename: ScanMetadata?
    @State private var proposedName = ""

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
        .alert("Rename Scan", isPresented: renameBinding) {
            TextField("Scan name", text: $proposedName)
            Button("Cancel", role: .cancel) { scanToRename = nil }
            Button("Rename") {
                if let scanToRename {
                    _ = library.rename(scanToRename, to: proposedName)
                }
                scanToRename = nil
            }
        } message: {
            Text("Choose a name stored in this scan's local metadata.")
        }
        .alert("Library action failed", isPresented: errorBinding) {
            Button("OK") { library.clearOperationError() }
        } message: {
            Text(library.operationError ?? "Unknown library error")
        }
    }

    @ToolbarContentBuilder
    private var libraryToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            NavigationLink {
                ScanRecoveryCenterView()
            } label: {
                Image(systemName: "archivebox")
            }
            .accessibilityLabel("Open Scan Recovery Center")
            .accessibilityHint("Inspects unindexed models and capture drafts without changing them")
        }
        if case .failed = library.state {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Retry", systemImage: "arrow.clockwise", action: library.reload)
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Layout", selection: $presentation) {
                        ForEach(ScanLibraryPresentation.allCases) { option in
                            Label(option.title, systemImage: option.systemImage).tag(option)
                        }
                    }
                    Divider()
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
                Group {
                    if presentation == .grid {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 156), spacing: 12)], spacing: 12) {
                            ForEach(visibleScans) { scan in scanLink(scan, style: .grid) }
                        }
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(visibleScans) { scan in scanLink(scan, style: .list) }
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

    private var renameBinding: Binding<Bool> {
        Binding(
            get: { scanToRename != nil },
            set: { if !$0 { scanToRename = nil } }
        )
    }

    @ViewBuilder
    private func scanLink(_ scan: ScanMetadata, style: ScanCardStyle) -> some View {
        let modelURL = library.modelURL(for: scan)
        NavigationLink { ScanDetailView(scanID: scan.id) } label: {
            if style == .grid {
                ScanCard(
                    scan: scan,
                    previewURL: library.previewURL(for: scan),
                    modelURL: modelURL
                )
            } else {
                ScanListRow(
                    scan: scan,
                    previewURL: library.previewURL(for: scan),
                    modelURL: modelURL
                )
            }
        }
        .contextMenu {
            Button {
                library.toggleFavorite(scan)
            } label: {
                Label(
                    scan.isFavorite ? "Remove Favorite" : "Favorite",
                    systemImage: scan.isFavorite ? "star.slash" : "star"
                )
            }
            Button {
                proposedName = scan.name
                scanToRename = scan
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            if let modelURL {
                ShareLink(item: modelURL) {
                    Label("Share / Export", systemImage: "square.and.arrow.up")
                }
            }
        }
    }
}

nonisolated enum ScanLibraryPresentation: String, CaseIterable, Identifiable, Sendable {
    case grid
    case list

    var id: String { rawValue }
    var title: String { self == .grid ? "Grid" : "List" }
    var systemImage: String { self == .grid ? "square.grid.2x2" : "list.bullet" }
}

private enum ScanCardStyle { case grid, list }

private struct ScanCard: View {
    let scan: ScanMetadata
    let previewURL: URL?
    let modelURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ModelThumbnailView(
                scanID: scan.id,
                previewURL: previewURL,
                modelURL: modelURL,
                kind: scan.kind
            )
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
            Label(modelURL != nil ? "USDZ available" : "Model unavailable", systemImage: modelURL != nil ? "checkmark.circle.fill" : "exclamationmark.circle")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(modelURL != nil ? StudioTheme.accent : StudioTheme.warning)
                .lineLimit(1)
        }
        .padding(12)
        .background(StudioTheme.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).stroke(StudioTheme.border) }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens scan details")
    }
}

private struct ScanListRow: View {
    let scan: ScanMetadata
    let previewURL: URL?
    let modelURL: URL?

    var body: some View {
        HStack(spacing: 14) {
            ModelThumbnailView(
                scanID: scan.id,
                previewURL: previewURL,
                modelURL: modelURL,
                kind: scan.kind,
                maximumPixelSize: 240
            )
            .frame(width: 92, height: 92)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(scan.name).font(.headline).lineLimit(1)
                    if scan.isFavorite {
                        Image(systemName: "star.fill").foregroundStyle(StudioTheme.accent)
                    }
                }
                Text(scan.kind.title + " · " + scan.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(StudioTheme.secondaryText)
                Label(
                    modelURL != nil ? "USDZ available" : "Model unavailable",
                    systemImage: modelURL != nil ? "checkmark.circle.fill" : "exclamationmark.circle"
                )
                .font(.caption2.weight(.semibold))
                .foregroundStyle(modelURL != nil ? StudioTheme.accent : StudioTheme.warning)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").foregroundStyle(StudioTheme.secondaryText)
        }
        .foregroundStyle(.white)
        .padding(12)
        .background(StudioTheme.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).stroke(StudioTheme.border) }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens scan details")
    }
}
