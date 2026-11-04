import SwiftUI

nonisolated enum OnboardingPreference {
    static let key = "hasCompletedOnboarding"

    static func isComplete(in defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: key)
    }

    static func setComplete(_ complete: Bool, in defaults: UserDefaults) {
        defaults.set(complete, forKey: key)
    }
}

nonisolated enum OnboardingCapabilityLevel: String, Equatable, Sendable {
    case implemented = "Implemented"
    case capabilityOnly = "Capability check"
    case diagnostic = "Diagnostic"
    case localLibrary = "Local library"
}

nonisolated struct OnboardingFeature: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let summary: String
    let systemImage: String
    let capabilityLevel: OnboardingCapabilityLevel
}

nonisolated enum OnboardingContent {
    static let features: [OnboardingFeature] = [
        OnboardingFeature(
            id: "object",
            title: "Object Studio",
            summary: "Guided photography and on-device reconstruction are implemented on supported hardware. A known RealityKit/Metal stability issue remains under investigation.",
            systemImage: "cube.transparent",
            capabilityLevel: .implemented
        ),
        OnboardingFeature(
            id: "room",
            title: "Room Studio",
            summary: "Checks RoomPlan and camera availability. Finished room capture and export are not yet physically verified.",
            systemImage: "square.split.bottomrightquarter",
            capabilityLevel: .capabilityOnly
        ),
        OnboardingFeature(
            id: "environment",
            title: "Environment Studio",
            summary: "Provides isolated ARKit and RGB-D diagnostics. It is research tooling, not a finished environment scanner.",
            systemImage: "sensor.tag.radiowaves.forward",
            capabilityLevel: .diagnostic
        ),
        OnboardingFeature(
            id: "library",
            title: "Scan Library",
            summary: "Keeps valid local USDZ models, metadata, favorites, thumbnails, viewing and explicit export in one place.",
            systemImage: "square.stack.3d.up",
            capabilityLevel: .localLibrary
        )
    ]
}

nonisolated struct ScanPreparationItem: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let detail: String
    let systemImage: String
}

nonisolated enum ObjectScanPreparationGuide {
    static let items: [ScanPreparationItem] = [
        .init(id: "lighting", title: "Use diffuse, even lighting", detail: "Avoid hard moving shadows while walking around the object.", systemImage: "sun.max"),
        .init(id: "surface", title: "Prefer textured, matte objects", detail: "Reflective and transparent surfaces are difficult to reconstruct reliably.", systemImage: "circle.hexagongrid"),
        .init(id: "overview", title: "Keep the whole object visible", detail: "Maintain full-object framing throughout the overview pass.", systemImage: "viewfinder"),
        .init(id: "slow", title: "Move slowly", detail: "Use steady motion and avoid sudden viewpoint changes.", systemImage: "figure.walk.motion"),
        .init(id: "overlap", title: "Capture overlapping viewpoints", detail: "Keep recognizable surface detail visible between neighboring views.", systemImage: "square.on.square"),
        .init(id: "detail", title: "Move closer carefully for detail", detail: "Maintain focus and move back if the surface becomes soft or cropped.", systemImage: "plus.magnifyingglass"),
        .init(id: "center", title: "Keep the object near center", detail: "Use the framing guide as a visual aid; it is not a measured bounding box.", systemImage: "scope"),
        .init(id: "materials", title: "Avoid difficult materials", detail: "Use reflective or transparent objects only with realistic expectations.", systemImage: "exclamationmark.triangle")
    ]
}

struct ObjectScanPreparationView: View {
    var body: some View {
        ZStack {
            StudioBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    Text("A calm, consistent capture gives Apple Object Capture stronger photographic input. These are practical guidelines, not a quality score or guarantee.")
                        .font(.subheadline)
                        .foregroundStyle(StudioTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .studioCard()

                    ForEach(ObjectScanPreparationGuide.items) { item in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: item.systemImage)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(StudioTheme.accent)
                                .frame(width: 32, height: 32)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title).font(.headline)
                                Text(item.detail)
                                    .font(.subheadline)
                                    .foregroundStyle(StudioTheme.secondaryText)
                            }
                            .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .studioCard()
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(18)
            }
        }
        .navigationTitle("Prepare an Object")
        .navigationBarTitleDisplayMode(.inline)
    }
}
