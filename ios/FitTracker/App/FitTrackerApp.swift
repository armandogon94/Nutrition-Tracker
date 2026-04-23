//
//  FitTrackerApp.swift
//  @main entry. Resolves the active theme via ThemeStore and injects it
//  into the environment. A debug-only toggle in AppRoot flips themes at
//  runtime during Slice 0 / 0.5 design validation. Replaced in Slice 11
//  with a proper Settings picker.
//

import SwiftUI

@main
struct FitTrackerApp: App {
    @Environment(\.colorScheme) private var systemScheme
    @State private var themeStore = ThemeStore()

    var body: some Scene {
        WindowGroup {
            let activeTheme = themeStore.theme(forColorScheme: systemScheme)
            AppRoot()
                .environment(\.appTheme, activeTheme)
                .environment(themeStore)
                .preferredColorScheme(activeTheme.preferredColorScheme)
        }
    }
}
