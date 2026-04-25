//
//  HealthCardsTheme.swift
//  Apple Health vibe — bright cards, soft shadows, rose / indigo accents,
//  SF Rounded bold numerals. See ADR-0002.
//

import SwiftUI

struct HealthCardsTheme: AppTheme {
    let id: ThemeID = .healthCards
    let displayName = "Health Cards"
    let summary = "Apple Health vibe — bright cards, soft shadows, gradient glows"
    let preferredColorScheme: ColorScheme? = .light

    var background: Color { Color(red: 0.965, green: 0.965, blue: 0.975) }
    var surface: Color { .white }
    var surfaceSecondary: Color { Color(red: 0.95, green: 0.95, blue: 0.97) }

    var textPrimary: Color { Color(red: 0.08, green: 0.09, blue: 0.12) }
    var textSecondary: Color { Color(red: 0.42, green: 0.44, blue: 0.50) }
    var textTertiary: Color { Color(red: 0.65, green: 0.68, blue: 0.72) }

    var accent: Color { Color(red: 0.96, green: 0.35, blue: 0.45) }
    var accentSecondary: Color { Color(red: 0.38, green: 0.48, blue: 0.98) }
    var positive: Color { Color(red: 0.18, green: 0.70, blue: 0.45) }
    var negative: Color { Color(red: 0.96, green: 0.35, blue: 0.45) }

    var categoryColors: [Color] {
        [
            Color(red: 0.38, green: 0.52, blue: 0.98), // Protein
            Color(red: 0.22, green: 0.78, blue: 0.52), // Carbs
            Color(red: 1.00, green: 0.68, blue: 0.22), // Fat
            Color(red: 0.58, green: 0.42, blue: 0.98), // Fiber
            Color(red: 0.98, green: 0.45, blue: 0.45), // Legs
            Color(red: 0.95, green: 0.42, blue: 0.78), // Chest
            Color(red: 0.22, green: 0.72, blue: 0.88), // Back
            Color(red: 0.98, green: 0.55, blue: 0.28), // Shoulders
            Color(red: 0.62, green: 0.62, blue: 0.68), // Arms / Other
        ]
    }

    var font: ThemeFont {
        ThemeFont(
            largeTitle: .system(size: 34, weight: .bold, design: .default),
            title: .system(size: 22, weight: .bold, design: .default),
            titleCompact: .system(size: 17, weight: .semibold, design: .default),
            heroNumeral: .system(size: 44, weight: .bold, design: .rounded),
            bodyMedium: .system(size: 15, weight: .medium, design: .default),
            body: .system(size: 15, weight: .regular, design: .default),
            caption: .system(size: 12, weight: .regular, design: .default),
            captionMedium: .system(size: 12, weight: .semibold, design: .default),
            monoNumeral: .system(size: 15, weight: .medium, design: .rounded)
        )
    }

    var radii: ThemeRadii { ThemeRadii(card: 20, button: 14, pill: 999, sheet: 28) }
    var spacing: ThemeSpacing { ThemeSpacing() }

    func heroGradient() -> AnyShapeStyle { AnyShapeStyle(background) }
    func cardBackground() -> AnyShapeStyle { AnyShapeStyle(surface) }
}
