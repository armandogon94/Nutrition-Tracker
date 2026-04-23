//
//  ThemeTests.swift
//  Verifies the AppTheme protocol and both concrete themes. Also covers
//  ThemeStore persistence + system-aware fallback.
//

import SwiftUI
import Testing
@testable import FitTracker

@Test("LiquidGlassTheme identifies as .liquidGlass")
func liquidGlass_identity() {
    let sut = LiquidGlassTheme()
    #expect(sut.id == .liquidGlass)
    #expect(sut.displayName == "Liquid Glass")
    #expect(sut.preferredColorScheme == .dark)
}

@Test("HealthCardsTheme identifies as .healthCards")
func healthCards_identity() {
    let sut = HealthCardsTheme()
    #expect(sut.id == .healthCards)
    #expect(sut.displayName == "Health Cards")
    #expect(sut.preferredColorScheme == .light)
}

@Test("ThemeID iterates both cases")
func themeID_allCases() {
    #expect(ThemeID.allCases.count == 2)
    #expect(ThemeID.allCases.contains(.liquidGlass))
    #expect(ThemeID.allCases.contains(.healthCards))
}

@Test("Categorical palettes have one color per displayed category")
func categoryColors_count() {
    #expect(LiquidGlassTheme().categoryColors.count >= 4)
    #expect(HealthCardsTheme().categoryColors.count >= 4)
}

@MainActor
@Test("ThemeStore defaults to system scheme when nothing selected")
func themeStore_systemDefault() {
    // Reset storage
    UserDefaults.standard.removeObject(forKey: "selected_theme")

    let sut = ThemeStore()
    let darkTheme = sut.theme(forColorScheme: .dark)
    let lightTheme = sut.theme(forColorScheme: .light)

    #expect(darkTheme.id == .liquidGlass)
    #expect(lightTheme.id == .healthCards)
}

@MainActor
@Test("ThemeStore honors explicit selection regardless of system scheme")
func themeStore_explicitOverridesSystem() {
    UserDefaults.standard.removeObject(forKey: "selected_theme")

    let sut = ThemeStore()
    sut.selectedID = .healthCards

    #expect(sut.theme(forColorScheme: .dark).id == .healthCards)
    #expect(sut.theme(forColorScheme: .light).id == .healthCards)

    // Cleanup
    UserDefaults.standard.removeObject(forKey: "selected_theme")
}
