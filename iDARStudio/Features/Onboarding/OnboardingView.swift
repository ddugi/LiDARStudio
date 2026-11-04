import SwiftUI

struct OnboardingView: View {
    let completion: () -> Void
    @State private var page = 0

    private let pageCount = 4

    var body: some View {
        ZStack {
            StudioBackground()
            VStack(spacing: 14) {
                header
                TabView(selection: $page) {
                    welcomePage.tag(0)
                    studiosPage.tag(1)
                    localFirstPage.tag(2)
                    requirementsPage.tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))

                controls
            }
            .padding(.top, 12)
            .padding(.bottom, 12)
        }
        .interactiveDismissDisabled()
    }

    private var header: some View {
        HStack {
            Text("LiDARStudio")
                .font(.headline)
            Spacer()
            Button("Skip", action: completion)
                .font(.subheadline.weight(.semibold))
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityHint("Closes onboarding. You can reopen it from Settings.")
        }
        .padding(.horizontal, 22)
    }

    private var welcomePage: some View {
        onboardingScroll {
            onboardingSymbol("viewfinder", accent: StudioTheme.accent)
            Text("Precision scanning, with honest status")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text("LiDARStudio keeps each Apple scanning framework isolated and shows only capabilities backed by real application or device state.")
                .font(.title3)
                .foregroundStyle(StudioTheme.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var studiosPage: some View {
        onboardingScroll(alignment: .leading) {
            Text("Four focused workspaces")
                .font(.largeTitle.bold())
            Text("Implemented, diagnostic and capability-only features are labeled separately.")
                .font(.subheadline)
                .foregroundStyle(StudioTheme.secondaryText)
            ForEach(OnboardingContent.features) { feature in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: feature.systemImage)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(accent(for: feature.capabilityLevel))
                        .frame(width: 30)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(feature.title).font(.headline)
                            Spacer(minLength: 8)
                            Text(feature.capabilityLevel.rawValue)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(accent(for: feature.capabilityLevel))
                        }
                        Text(feature.summary)
                            .font(.caption)
                            .foregroundStyle(StudioTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .studioCard()
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var localFirstPage: some View {
        onboardingScroll {
            onboardingSymbol("lock.shield.fill", accent: .cyan)
            Text("Local first, user controlled")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text("Models, original photographs, previews, metadata and diagnostic datasets stay on this iPhone by default.")
                .font(.title3)
                .foregroundStyle(StudioTheme.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Label("Sharing and export require an explicit action", systemImage: "square.and.arrow.up")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .studioCard()
        }
    }

    private var requirementsPage: some View {
        onboardingScroll(alignment: .leading) {
            Text("Before your first scan")
                .font(.largeTitle.bold())
            Label("Camera access is requested only when a camera workflow starts.", systemImage: "camera.fill")
                .studioCard()
            Label("LiDAR, RoomPlan and Object Capture availability depends on this device and Apple's public APIs.", systemImage: "sensor.tag.radiowaves.forward")
                .studioCard()
            VStack(alignment: .leading, spacing: 10) {
                Text("Object capture essentials").font(.headline)
                ForEach(ObjectScanPreparationGuide.items.prefix(5)) { item in
                    Label(item.title, systemImage: item.systemImage)
                        .font(.subheadline)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .studioCard()
            Text("The complete preparation checklist is available in Settings and Object Studio.")
                .font(.footnote)
                .foregroundStyle(StudioTheme.secondaryText)
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            if page > 0 {
                Button("Back") { page -= 1 }
                    .buttonStyle(.bordered)
                    .frame(width: 92, height: 50)
                    .accessibilityHint("Returns to the previous onboarding page.")
            }
            Button {
                if page == pageCount - 1 {
                    completion()
                } else {
                    page += 1
                }
            } label: {
                Text(page == pageCount - 1 ? "Get Started" : "Continue")
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(StudioTheme.accent)
            .foregroundStyle(.black)
            .accessibilityHint(
                page == pageCount - 1
                    ? "Completes onboarding and opens LiDARStudio."
                    : "Advances to the next onboarding page."
            )
        }
        .padding(.horizontal, 22)
    }

    private func onboardingScroll(
        alignment: HorizontalAlignment = .center,
        @ViewBuilder content: () -> some View
    ) -> some View {
        ScrollView {
            VStack(alignment: alignment, spacing: 18, content: content)
                .frame(maxWidth: .infinity, minHeight: 470, alignment: .center)
                .padding(.horizontal, 22)
                .padding(.vertical, 22)
        }
    }

    private func onboardingSymbol(_ symbol: String, accent: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 54, weight: .light))
            .foregroundStyle(accent)
            .frame(width: 104, height: 104)
            .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 28))
            .accessibilityHidden(true)
    }

    private func accent(for level: OnboardingCapabilityLevel) -> Color {
        switch level {
        case .implemented, .localLibrary: StudioTheme.accent
        case .capabilityOnly: StudioTheme.warning
        case .diagnostic: .mint
        }
    }
}
