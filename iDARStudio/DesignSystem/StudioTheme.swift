import SwiftUI

enum StudioTheme {
    static let background = Color(red: 0.025, green: 0.028, blue: 0.032)
    static let surface = Color(red: 0.075, green: 0.082, blue: 0.09)
    static let elevatedSurface = Color(red: 0.105, green: 0.115, blue: 0.125)
    static let border = Color.white.opacity(0.10)
    static let secondaryText = Color.white.opacity(0.64)
    static let accent = Color(red: 0.70, green: 1.0, blue: 0.16)
    static let warning = Color(red: 1.0, green: 0.70, blue: 0.20)
    static let cornerRadius: CGFloat = 22
}

struct StudioBackground: View {
    var body: some View {
        LinearGradient(
            colors: [StudioTheme.background, Color(red: 0.045, green: 0.052, blue: 0.047)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

struct StudioCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(20)
            .background(StudioTheme.surface, in: RoundedRectangle(cornerRadius: StudioTheme.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: StudioTheme.cornerRadius)
                    .stroke(StudioTheme.border, lineWidth: 1)
            }
    }
}

extension View {
    func studioCard() -> some View {
        modifier(StudioCardModifier())
    }
}
