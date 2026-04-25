//
//  AppTheme.swift
//  Design-system protocol. Every screen reads its colors, fonts, radii,
//  and surface materials through this so we can swap between Liquid Glass
//  and Health Cards at runtime. See ADR-0002.
//

import SwiftUI

// MARK: - Protocol

protocol AppTheme: Sendable {
    var id: ThemeID { get }
    var displayName: String { get }
    var summary: String { get }
    var preferredColorScheme: ColorScheme? { get }

    // Surface colors
    var background: Color { get }
    var surface: Color { get }
    var surfaceSecondary: Color { get }

    // Semantic text colors
    var textPrimary: Color { get }
    var textSecondary: Color { get }
    var textTertiary: Color { get }

    // Accents
    var accent: Color { get }
    var accentSecondary: Color { get }
    var positive: Color { get }
    var negative: Color { get }

    // Category / macro swatches (protein, carbs, fat, fiber, …)
    var categoryColors: [Color] { get }

    // Layout tokens
    var font: ThemeFont { get }
    var radii: ThemeRadii { get }
    var spacing: ThemeSpacing { get }

    // Hero gradient used behind headers / big totals
    func heroGradient() -> AnyShapeStyle
    // Card background style — materials for Liquid Glass, solid for Health Cards
    func cardBackground() -> AnyShapeStyle
}

enum ThemeID: String, CaseIterable, Hashable, Sendable {
    case liquidGlass
    case healthCards

    var label: String {
        switch self {
        case .liquidGlass: "Liquid Glass"
        case .healthCards: "Health Cards"
        }
    }
}

// MARK: - Supporting token types

struct ThemeFont: Sendable {
    var largeTitle: Font
    var title: Font
    var titleCompact: Font
    var heroNumeral: Font
    var bodyMedium: Font
    var body: Font
    var caption: Font
    var captionMedium: Font
    var monoNumeral: Font

    static let systemDefault = ThemeFont(
        largeTitle: .system(size: 34, weight: .bold, design: .default),
        title: .system(size: 22, weight: .semibold, design: .default),
        titleCompact: .system(size: 17, weight: .semibold, design: .default),
        heroNumeral: .system(size: 40, weight: .semibold, design: .rounded),
        bodyMedium: .system(size: 15, weight: .medium, design: .default),
        body: .system(size: 15, weight: .regular, design: .default),
        caption: .system(size: 12, weight: .regular, design: .default),
        captionMedium: .system(size: 12, weight: .semibold, design: .default),
        monoNumeral: .system(size: 15, weight: .medium, design: .monospaced)
    )
}

struct ThemeRadii: Sendable {
    var card: CGFloat = 22
    var button: CGFloat = 14
    var pill: CGFloat = 999
    var sheet: CGFloat = 30
}

struct ThemeSpacing: Sendable {
    var xs: CGFloat = 4
    var sm: CGFloat = 8
    var md: CGFloat = 12
    var lg: CGFloat = 16
    var xl: CGFloat = 20
    var xxl: CGFloat = 28
}
