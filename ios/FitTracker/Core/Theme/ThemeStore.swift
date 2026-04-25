//
//  ThemeStore.swift
//  Persists the user's theme choice and resolves `any AppTheme` at runtime.
//  Default: follow system (dark → Liquid Glass, light → Health Cards).
//

import SwiftUI

@MainActor
@Observable
final class ThemeStore {
    @ObservationIgnored
    @AppStorage("selected_theme") private var storedID: String = ""

    var selectedID: ThemeID? {
        get { ThemeID(rawValue: storedID) }
        set { storedID = newValue?.rawValue ?? "" }
    }

    /// Resolve to a concrete theme, falling back to a system-aware default
    /// when the user hasn't chosen one.
    func theme(forColorScheme scheme: ColorScheme) -> any AppTheme {
        switch selectedID {
        case .liquidGlass:
            return LiquidGlassTheme()
        case .healthCards:
            return HealthCardsTheme()
        case .none:
            return scheme == .dark ? LiquidGlassTheme() : HealthCardsTheme()
        }
    }
}
