//
//  FitTrackerApp.swift
//  @main entry. Resolves the active theme via ThemeStore and injects it
//  into the environment. A debug-only toggle in AppRoot flips themes at
//  runtime during Slice 0 / 0.5 design validation. Replaced in Slice 11
//  with a proper Settings picker.
//

import SwiftUI
import SwiftData

@main
struct FitTrackerApp: App {
    @State private var themeStore = ThemeStore()
    @State private var services = FitTrackerApp.makeServiceContainer()

    var body: some Scene {
        WindowGroup {
            ThemedRootView()
                .environment(themeStore)
                .environment(services)
                // Slice 3.7: install the SwiftData container so any view
                // using @Query / @Environment(\.modelContext) works.
                .modelContainer(PersistenceController.live.container)
        }
    }

    /// Production wiring: real AuthService against APIClient + Keychain.
    /// Pass `-useMockAuth` at launch to fall back to the mock (used by
    /// Slice 0.5 design-review screenshots and preview-driven testing).
    @MainActor
    private static func makeServiceContainer() -> MockServiceContainer {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-useMockAuth") {
            return MockServiceContainer()  // mock auth path
        }
        #endif
        return MockServiceContainer(auth: AuthService())
    }
}

/// Bridges the system color scheme into our theme protocol. `@Environment
/// (\.colorScheme)` is reliable inside Views but not at the App / Scene
/// level — a launch-time read in FitTrackerApp.body does not refresh when
/// system appearance changes. Resolving here means theme + system stay
/// in sync across appearance toggles and explicit user selections.
private struct ThemedRootView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(ThemeStore.self) private var themeStore

    var body: some View {
        let active = themeStore.theme(forColorScheme: colorScheme)
        // Only override system appearance when the user has explicitly
        // picked a theme. In automatic mode we let the system drive so
        // the colorScheme environment can flip and re-render the theme.
        let preferred: ColorScheme? = themeStore.selectedID == nil
            ? nil
            : active.preferredColorScheme
        AppRoot()
            .environment(\.appTheme, active)
            .preferredColorScheme(preferred)
    }
}
