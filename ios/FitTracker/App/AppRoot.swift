//
//  AppRoot.swift
//  Root view. Slice 0: shows a splash with theme-aware backdrop and
//  a Debug `PingView` (wired in Slice 0.8). Replaced in Slice 1 by
//  AuthGate which swaps between LoginView and MainTabView.
//

import SwiftUI

struct AppRoot: View {
    @Environment(\.appTheme) private var theme

    var body: some View {
        ZStack {
            ThemedBackdrop()

            VStack(spacing: 20) {
                Text("FitTracker")
                    .font(theme.font.largeTitle)
                    .foregroundStyle(theme.textPrimary)

                Text(theme.displayName)
                    .font(theme.font.caption)
                    .foregroundStyle(theme.textTertiary)
                    .tracking(1.5)

                #if DEBUG
                PingView()
                    .padding(.top, 24)
                #endif
            }
            .padding(24)
        }
    }
}

#Preview("AppRoot — Liquid Glass") {
    AppRoot()
        .environment(\.appTheme, LiquidGlassTheme())
        .preferredColorScheme(.dark)
}

#Preview("AppRoot — Health Cards") {
    AppRoot()
        .environment(\.appTheme, HealthCardsTheme())
        .preferredColorScheme(.light)
}
