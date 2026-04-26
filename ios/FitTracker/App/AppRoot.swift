//
//  AppRoot.swift
//  Slice 0.5: routes between LoginView (when not authenticated) and
//  MainTabView (when authenticated). Auth state is owned by the
//  injected MockAuthService. Real backend wiring lands in Slice 1.
//

import SwiftUI

struct AppRoot: View {
    var body: some View {
        AuthGate()
    }
}

#Preview("AppRoot — Liquid Glass — Unauthed") {
    AppRoot()
        .environment(\.appTheme, LiquidGlassTheme())
        .environment(MockServiceContainer())
        .preferredColorScheme(.dark)
}

#Preview("AppRoot — Health Cards — Unauthed") {
    AppRoot()
        .environment(\.appTheme, HealthCardsTheme())
        .environment(MockServiceContainer())
        .preferredColorScheme(.light)
}
