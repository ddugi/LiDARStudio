import SwiftUI

struct AboutView: View {
    var body: some View {
        ZStack {
            StudioBackground()
            ScrollView {
                VStack(spacing: 22) {
                    Image(systemName: "viewfinder.circle.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(StudioTheme.accent)
                        .accessibilityHidden(true)
                    VStack(spacing: 6) {
                        Text("LiDARStudio").font(.largeTitle.bold())
                        Text("Version 0.1.0")
                            .font(.headline)
                            .foregroundStyle(StudioTheme.secondaryText)
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Local by default", systemImage: "lock.shield")
                        Label("Native Apple frameworks", systemImage: "apple.logo")
                        Label("Designed for iPhone Pro", systemImage: "iphone.gen3")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .studioCard()
                    Text("© 2026 Dugi Selmanaj. All rights reserved.")
                        .font(.footnote)
                        .foregroundStyle(StudioTheme.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}
