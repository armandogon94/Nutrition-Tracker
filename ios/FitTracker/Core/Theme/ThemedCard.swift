//
//  ThemedCard.swift
//  One API (.themedCard() / ThemedBackdrop) that every screen calls.
//  The modifier dispatches per-theme so Liquid Glass gets glass materials
//  and Health Cards gets solid surfaces with soft elevation.
//

import SwiftUI

// MARK: - Per-theme card modifier

extension View {
    /// Apply the active theme's card surface (fill + border + shadow).
    /// - Parameter radius: optional override; defaults to `theme.radii.card`.
    func themedCard(radius: CGFloat? = nil) -> some View {
        modifier(ThemedCardModifier(radius: radius))
    }

    /// Variant with reduced visual weight — used for nested/inner cards.
    func themedInnerCard(radius: CGFloat? = nil) -> some View {
        modifier(ThemedCardModifier(radius: radius, inner: true))
    }
}

struct ThemedCardModifier: ViewModifier {
    @Environment(\.appTheme) private var theme
    var radius: CGFloat?
    var inner: Bool = false

    func body(content: Content) -> some View {
        let r = radius ?? theme.radii.card
        switch theme.id {

        // Liquid Glass — materials, luminous border, layered shadow
        case .liquidGlass:
            content
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: r, style: .continuous)
                            .fill(inner ? AnyShapeStyle(Color.white.opacity(0.05))
                                        : AnyShapeStyle(.ultraThinMaterial))
                        RoundedRectangle(cornerRadius: r, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color.white.opacity(inner ? 0.18 : 0.32),
                                             Color.white.opacity(0.04)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
                )
                .shadow(color: .black.opacity(inner ? 0.10 : 0.30),
                        radius: inner ? 8 : 18, y: inner ? 4 : 10)

        // Health Cards — clean rounded surface with soft elevation
        case .healthCards:
            content
                .background(
                    RoundedRectangle(cornerRadius: r, style: .continuous)
                        .fill(inner ? theme.surfaceSecondary : theme.surface)
                )
                .shadow(
                    color: .black.opacity(inner ? 0.04 : 0.08),
                    radius: inner ? 6 : 14, y: inner ? 2 : 6
                )
        }
    }
}
