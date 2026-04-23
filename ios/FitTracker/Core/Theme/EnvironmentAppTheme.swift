//
//  EnvironmentAppTheme.swift
//  SwiftUI environment key so every view can read the active theme.
//

import SwiftUI

private struct AppThemeEnvironmentKey: EnvironmentKey {
    static let defaultValue: any AppTheme = LiquidGlassTheme()
}

extension EnvironmentValues {
    var appTheme: any AppTheme {
        get { self[AppThemeEnvironmentKey.self] }
        set { self[AppThemeEnvironmentKey.self] = newValue }
    }
}
