import SwiftUI

struct HomeView: View {
    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        ZStack {
            StudioBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    LazyVGrid(columns: columns, spacing: 14) {
                        NavigationLink { ObjectStudioView() } label: {
                            StudioSectionCard(
                                title: "Object Studio",
                                subtitle: "High-detail photogrammetry",
                                systemImage: "cube.transparent",
                                accent: StudioTheme.accent
                            )
                        }
                        NavigationLink { RoomStudioView() } label: {
                            StudioSectionCard(
                                title: "Room Studio",
                                subtitle: "Architectural capture",
                                systemImage: "square.split.bottomrightquarter",
                                accent: .cyan
                            )
                        }
                        NavigationLink { EnvironmentStudioView() } label: {
                            StudioSectionCard(
                                title: "Environment Studio",
                                subtitle: "LiDAR scene mesh",
                                systemImage: "mountain.2",
                                accent: .mint
                            )
                        }
                        NavigationLink { ScanLibraryView() } label: {
                            StudioSectionCard(
                                title: "My Scans",
                                subtitle: "Private, on-device library",
                                systemImage: "square.stack.3d.up",
                                accent: .purple
                            )
                        }
                    }
                    privacyNote
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            }
        }
        .navigationTitle("LiDARStudio")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { AboutView() } label: {
                    Image(systemName: "info.circle")
                }
                .accessibilityLabel("About LiDARStudio")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CAPTURE THE PHYSICAL WORLD")
                .font(.caption.weight(.semibold))
                .tracking(1.6)
                .foregroundStyle(StudioTheme.accent)
            Text("Precision 3D scanning,\nbuilt for iPhone Pro.")
                .font(.largeTitle.bold())
                .minimumScaleFactor(0.8)
            Text("Choose a studio to begin. Hardware support is verified before any capture session starts.")
                .font(.body)
                .foregroundStyle(StudioTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var privacyNote: some View {
        Label {
            Text("Scans stay on this device by default.")
                .font(.subheadline.weight(.medium))
        } icon: {
            Image(systemName: "lock.shield")
                .foregroundStyle(StudioTheme.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .studioCard()
    }
}

private struct StudioSectionCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: systemImage)
                .font(.title2.weight(.medium))
                .foregroundStyle(accent)
                .frame(width: 46, height: 46)
                .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            Spacer(minLength: 10)
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(StudioTheme.secondaryText)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 178, alignment: .leading)
        .studioCard()
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
