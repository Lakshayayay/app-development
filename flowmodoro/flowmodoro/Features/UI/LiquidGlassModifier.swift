import SwiftUI

struct LiquidGlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(.white.opacity(0.2), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

extension View {
    func liquidGlassStyle() -> some View {
        self.modifier(LiquidGlassModifier())
    }
}
