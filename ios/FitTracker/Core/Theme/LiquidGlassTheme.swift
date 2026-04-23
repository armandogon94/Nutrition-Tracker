//
//  LiquidGlassTheme.swift
//  iOS 26 native aesthetic: deep layered gradient backgrounds, translucent
//  cards on ultraThinMaterial, big rounded numerals, luminous accents.
//  See ADR-0002.
//

import SwiftUI

struct LiquidGlassTheme: AppTheme {
    let id: ThemeID = .liquidGlass
    let displayName = "Liquid Glass"
    let summary = "iOS 26 native — translucent depth, glass cards, big numerals"
    let preferredColorScheme: ColorScheme? = .dark

    var background: Color { Color(red: 0.04, green: 0.05, blue: 0.10) }
    var surface: Color { Color.white.opacity(0.08) }
    var surfaceSecondary: Color { Color.white.opacity(0.05) }

    var textPrimary: Color { Color.white }
    var textSecondary: Color { Color.white.opacity(0.70) }
    var textTertiary: Color { Color.white.opacity(0.45) }

    var accent: Color { Color(red: 0.62, green: 0.78, blue: 1.0) }
    var accentSecondary: Color { Color(red: 0.78, green: 0.69, blue: 1.0) }
    var positive: Color { Color(red: 0.45, green: 0.92, blue: 0.69) }
    var negative: Color { Color(red: 1.0, green: 0.48, blue: 0.55) }

    // Macro / category palette tuned for fitness context
    var categoryColors: [Color] {
        [
            Color(red: 0.55, green: 0.70, blue: 1.00), // Protein
            Color(red: 0.45, green: 0.92, blue: 0.69), // Carbs
            Color(red: 1.00, green: 0.78, blue: 0.35), // Fat
            Color(red: 0.78, green: 0.69, blue: 1.00), // Fiber
            Color(red: 0.98, green: 0.56, blue: 0.42), // Legs
            Color(red: 0.95, green: 0.55, blue: 0.83), // Chest
            Color(red: 0.45, green: 0.78, blue: 0.95), // Back
            Color(red: 1.00, green: 0.65, blue: 0.40), // Shoulders
            Color(red: 0.65, green: 0.68, blue: 0.75), // Arms / Other
        ]
    }

    var font: ThemeFont {
        ThemeFont(
            largeTitle: .system(size: 36, weight: .bold, design: .rounded),
            title: .system(size: 24, weight: .semibold, design: .rounded),
            titleCompact: .system(size: 18, weight: .semibold, design: .rounded),
            heroNumeral: .system(size: 48, weight: .semibold, design: .rounded),
            bodyMedium: .system(size: 15, weight: .medium, design: .default),
            body: .system(size: 15, weight: .regular, design: .default),
            caption: .system(size: 12, weight: .regular, design: .default),
            captionMedium: .system(size: 12, weight: .semibold, design: .default),
            monoNumeral: .system(size: 15, weight: .medium, design: .rounded)
        )
    }

    var radii: ThemeRadii { ThemeRadii(card: 26, button: 16, pill: 999, sheet: 34) }
    var spacing: ThemeSpacing { ThemeSpacing() }

    func heroGradient() -> AnyShapeStyle {
        AnyShapeStyle(
            LinearGradient(
                colors: [
                    Color(red: 0.09, green: 0.12, blue: 0.28),
                    Color(red: 0.32, green: 0.15, blue: 0.45),
                    Color(red: 0.05, green: 0.07, blue: 0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    func cardBackground() -> AnyShapeStyle {
        AnyShapeStyle(.ultraThinMaterial)
    }
}
