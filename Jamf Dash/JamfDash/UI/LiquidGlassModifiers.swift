import SwiftUI

extension View {
    @ViewBuilder
    func liquidGlassToolbar() -> some View {
        if #available(macOS 26, *) {
            self.toolbarBackgroundVisibility(.visible, for: .windowToolbar)
        } else {
            self
        }
    }

    @ViewBuilder
    func glassCard(cornerRadius: CGFloat = 14) -> some View {
        if #available(macOS 26, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}
