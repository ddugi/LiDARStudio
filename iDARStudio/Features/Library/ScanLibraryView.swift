import SwiftUI

struct ScanLibraryView: View {
    @EnvironmentObject private var library: ScanLibrary

    var body: some View {
        ZStack {
            StudioBackground()
            content
        }
        .navigationTitle("My Scans")
        .toolbar {
            if case .failed = library.state {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Retry", systemImage: "arrow.clockwise", action: library.reload)
                }
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
            ContentUnavailableView(
                "Library unavailable",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
        case .loaded where library.scans.isEmpty:
            ContentUnavailableView {
                Label("No scans yet", systemImage: "cube.transparent")
            } description: {
                Text("Completed scans will appear here and remain local by default.")
            }
        case .loaded:
            List {
                ForEach(library.scans) { scan in
                    ScanRow(scan: scan)
                        .listRowBackground(StudioTheme.surface)
                }
                .onDelete(perform: library.delete)
            }
            .scrollContentBackground(.hidden)
        }
    }
}

private struct ScanRow: View {
    let scan: ScanMetadata

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: scan.kind.systemImage)
                .font(.title2)
                .foregroundStyle(StudioTheme.accent)
                .frame(width: 48, height: 48)
                .background(StudioTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text(scan.name).font(.headline)
                Text("\(scan.kind.title) · \(scan.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(StudioTheme.secondaryText)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}
