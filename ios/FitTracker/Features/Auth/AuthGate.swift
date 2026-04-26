//
//  AuthGate.swift
//  Slice 1.6: governs the unauthenticated → authenticated transition.
//  On first appear it asks AuthService to validate any persisted
//  Keychain session; while restoration is in flight it shows a loading
//  state to avoid flashing LoginView before the refresh completes.
//

import SwiftUI

struct AuthGate: View {
    @Environment(\.appTheme) private var theme
    @Environment(MockServiceContainer.self) private var services

    @State private var hasRestored = false

    var body: some View {
        ZStack {
            ThemedBackdrop()
            if !hasRestored {
                ProgressView()
                    .tint(theme.accent)
                    .scaleEffect(1.4)
            } else if services.auth.isAuthenticated {
                MainTabView()
                    .transition(.opacity)
            } else {
                LoginView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: services.auth.isAuthenticated)
        .animation(.easeInOut(duration: 0.2), value: hasRestored)
        .task {
            if !hasRestored {
                await services.auth.restoreSession()
                hasRestored = true
            }
        }
    }
}

#Preview("AuthGate — restored unauthed (LG)") {
    AuthGate()
        .environment(\.appTheme, LiquidGlassTheme())
        .environment(MockServiceContainer())
        .preferredColorScheme(.dark)
}
