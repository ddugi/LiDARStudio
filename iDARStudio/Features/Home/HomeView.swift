import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var library: ScanLibrary
    private let capabilities = DeviceCapabilityService.current()
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ZStack {
            StudioBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    header
                    summary
                    studios
                    recentProjects
                    privacyNote
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            }
            .refreshable { library.reload() }
        }
        .navigationTitle("LiDARStudio")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                NavigationLink(value: AppDestination.settings) { Image(systemName: "gearshape") }
                    .accessibilityLabel("Settings")
                NavigationLink(value: AppDestination.about) { Image(systemName: "info.circle") }
                    .accessibilityLabel("About LiDARStudio")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CAPTURE THE PHYSICAL WORLD")
                .font(.caption.weight(.semibold))
                .tracking(1.5)
                .foregroundStyle(StudioTheme.accent)
            Text("Precision 3D scanning,\nbuilt for iPhone Pro.")
                .font(.largeTitle.bold())
                .minimumScaleFactor(0.78)
            Text("Choose a workflow. Availability is checked from public Apple APIs on this device.")
                .font(.body)
                .foregroundStyle(StudioTheme.secondaryText)
        }
    }

    private var summary: some View {
        NavigationLink(value: AppDestination.library) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("MY SCANS").font(.caption2.weight(.bold)).tracking(1.2)
                    switch library.state {
                    case .loading: Text("Loading…").font(.title2.bold())
                    case .failed: Text("Unavailable").font(.title2.bold())
                    case .loaded: Text("\(library.scans.count)").font(.title.bold()).monospacedDigit()
                    }
                }
                Spacer()
                Image(systemName: "square.stack.3d.up.fill").font(.title2).foregroundStyle(StudioTheme.accent)
                Image(systemName: "chevron.right").foregroundStyle(StudioTheme.secondaryText)
            }
            .foregroundStyle(.white)
            .studioCard()
        }
        .accessibilityHint("Opens the local scan library")
    }

    private var studios: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Studios").font(.title2.bold())
            LazyVGrid(columns: columns, spacing: 12) {
                StudioSectionCard(
                    destination: .objectStudio,
                    title: "Object Studio",
                    subtitle: "Photogrammetry",
                    systemImage: "cube.transparent",
                    accent: StudioTheme.accent,
                    status: objectStudioAvailable ? "API supported" : "Unavailable",
                    available: objectStudioAvailable
                )
                StudioSectionCard(
                    destination: .roomStudio,
                    title: "Room Studio",
                    subtitle: "RoomPlan",
                    systemImage: "square.split.bottomrightquarter",
                    accent: .cyan,
                    status: capabilities.supportsRoomPlan ? "API supported" : "Unavailable",
                    available: capabilities.supportsRoomPlan
                )
                StudioSectionCard(
                    destination: .environmentStudio,
                    title: "Environment",
                    subtitle: "LiDAR diagnostics",
                    systemImage: "sensor.tag.radiowaves.forward",
                    accent: .mint,
                    status: capabilities.supportsWorldTracking ? "Diagnostic only" : "Unavailable",
                    available: capabilities.supportsWorldTracking
                )
                StudioSectionCard(
                    destination: .library,
                    title: "My Scans",
                    subtitle: "Local library",
                    systemImage: "square.stack.3d.up",
                    accent: .purple,
                    status: "On device",
                    available: true
                )
            }
        }
    }

    @ViewBuilder
    private var recentProjects: some View {
        if case .loaded = library.state, !library.scans.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Recent Projects").font(.title2.bold())
                    Spacer()
                    NavigationLink("See All", value: AppDestination.library)
                        .font(.subheadline.weight(.semibold))
                }
                ForEach(library.scans.prefix(3)) { scan in
                    NavigationLink { ScanDetailView(scanID: scan.id) } label: {
                        RecentScanRow(scan: scan, modelAvailable: library.modelURL(for: scan) != nil)
                    }
                }
            }
        }
    }

    private var privacyNote: some View {
        Label("Scans stay on this device unless you explicitly share them.", systemImage: "lock.shield")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .studioCard()
    }

    private var objectStudioAvailable: Bool {
        capabilities.supportsObjectCapture && capabilities.supportsOnDevicePhotogrammetry
    }
}

private struct StudioSectionCard: View {
    let destination: AppDestination
    let title: String
    let subtitle: String
    let systemImage: String
    let accent: Color
    let status: String
    let available: Bool

    var body: some View {
        NavigationLink(value: destination) {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    Image(systemName: systemImage).font(.title2.weight(.medium)).foregroundStyle(accent)
                    Spacer()
                    Circle().fill(available ? accent : StudioTheme.warning).frame(width: 7, height: 7)
                }
                Spacer(minLength: 6)
                Text(title).font(.headline).lineLimit(2)
                Text(subtitle).font(.caption).foregroundStyle(StudioTheme.secondaryText).lineLimit(1)
                Text(status)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(available ? accent : StudioTheme.warning)
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 142, alignment: .leading)
            .studioCard()
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens \(title)")
    }
}

private struct RecentScanRow: View {
    let scan: ScanMetadata
    let modelAvailable: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: scan.kind.systemImage)
                .font(.title3)
                .foregroundStyle(StudioTheme.accent)
                .frame(width: 44, height: 44)
                .background(StudioTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(scan.name).font(.headline).lineLimit(1)
                    if scan.isFavorite {
                        Image(systemName: "star.fill").font(.caption).foregroundStyle(StudioTheme.accent)
                    }
                }
                Text(scan.updatedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption).foregroundStyle(StudioTheme.secondaryText)
            }
            Spacer()
            Image(systemName: modelAvailable ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(modelAvailable ? StudioTheme.accent : StudioTheme.warning)
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(StudioTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}
