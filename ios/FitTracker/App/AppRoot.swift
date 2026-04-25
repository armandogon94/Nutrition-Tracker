//
//  AppRoot.swift
//  Slice 0.5: routes between LoginView (when not authenticated) and
//  MainTabView (when authenticated). Auth state is owned by the
//  injected MockAuthService. Real backend wiring lands in Slice 1.
//

import SwiftUI

struct AppRoot: View {
    @Environment(MockServiceContainer.self) private var services

    var body: some View {
        ZStack {
            ThemedBackdrop()

            if services.auth.isAuthenticated {
                MainTabView()
                    .transition(.opacity)
            } else {
                LoginView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: services.auth.isAuthenticated)
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
