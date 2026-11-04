import SwiftUI

struct OnboardingView: View {
    let completion: () -> Void
    @State private var page = 0

    private let pages: [OnboardingPage] = [
        .init(title: "Scan with purpose", message: "Object, room, and environment tools are kept separate so only one camera session runs at a time.", symbol: "viewfinder", accent: StudioTheme.accent),
        .init(title: "Your work stays local", message: "Scans, photographs, and metadata remain on this iPhone unless you explicitly share or save them elsewhere.", symbol: "lock.shield.fill", accent: .cyan),
        .init(title: "Camera access, when needed", message: "LiDARStudio explains why camera access is required before requesting permission. Hardware availability is never simulated.", symbol: "camera.fill", accent: .mint)
    ]

    var body: some View {
        ZStack {
            StudioBackground()
            VStack(spacing: 28) {
                Spacer()
                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, item in
                        VStack(spacing: 24) {
                            Image(systemName: item.symbol)
                                .font(.system(size: 58, weight: .light))
                                .foregroundStyle(item.accent)
                                .frame(width: 112, height: 112)
                                .background(item.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 30))
                                .accessibilityHidden(true)
                            Text(item.title).font(.largeTitle.bold()).multilineTextAlignment(.center)
                            Text(item.message)
                                .font(.title3)
                                .foregroundStyle(StudioTheme.secondaryText)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 28)
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                Button {
                    if page == pages.count - 1 { completion() } else { page += 1 }
                } label: {
                    Text(page == pages.count - 1 ? "Get Started" : "Continue")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(StudioTheme.accent)
                .foregroundStyle(.black)
                .padding(.horizontal, 24)
                Spacer().frame(height: 8)
            }
        }
        .interactiveDismissDisabled()
    }
}

private struct OnboardingPage {
    let title: String
    let message: String
    let symbol: String
    let accent: Color
}
