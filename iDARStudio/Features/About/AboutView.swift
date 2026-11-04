import SwiftUI
import UIKit

struct AboutView: View {
    var body: some View {
        ZStack {
            StudioBackground()
            ScrollView {
                VStack(spacing: 22) {
                    appIcon
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

    @ViewBuilder
    private var appIcon: some View {
        if let image = Self.loadAppIcon() {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 128, height: 128)
                .clipShape(RoundedRectangle(cornerRadius: 29, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 29, style: .continuous)
                        .stroke(StudioTheme.border, lineWidth: 1)
                }
                .shadow(color: StudioTheme.accent.opacity(0.22), radius: 20)
                .accessibilityLabel("LiDARStudio app icon")
        } else {
            Image(systemName: "viewfinder.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(StudioTheme.accent)
                .accessibilityLabel("LiDARStudio")
        }
    }

    private static func loadAppIcon() -> UIImage? {
        let names = ["AppIcon60x60@3x", "AppIcon60x60@2x", "AppIcon60x60"]
        for name in names {
            if let url = Bundle.main.url(forResource: name, withExtension: "png"),
               let image = UIImage(contentsOfFile: url.path) {
                return image
            }
            if let image = UIImage(named: name) { return image }
        }
        return nil
    }
}
