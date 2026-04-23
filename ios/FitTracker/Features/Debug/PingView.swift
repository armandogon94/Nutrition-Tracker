//
//  PingView.swift
//  Debug-only view. Slice 0.3: placeholder surface that verifies theme
//  tokens apply to themed cards. Slice 0.8 wires it to an actual backend
//  /health request via APIClient.
//

import SwiftUI

#if DEBUG
struct PingView: View {
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(spacing: 12) {
            Text("DEBUG PING")
                .font(theme.font.captionMedium)
                .tracking(1.5)
                .foregroundStyle(theme.textTertiary)
            Text("Backend call lands in Slice 0.8")
                .font(theme.font.body)
                .foregroundStyle(theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .themedCard()
    }
}

#Preview("PingView — Liquid Glass") {
    ZStack {
        ThemedBackdrop()
        PingView()
            .padding()
    }
    .environment(\.appTheme, LiquidGlassTheme())
    .preferredColorScheme(.dark)
}

#Preview("PingView — Health Cards") {
    ZStack {
        ThemedBackdrop()
        PingView()
            .padding()
    }
    .environment(\.appTheme, HealthCardsTheme())
    .preferredColorScheme(.light)
}
#endif
