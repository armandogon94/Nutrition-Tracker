//
//  ThemedBackdrop.swift
//  Full-screen backdrop that switches per theme — deep gradient + luminous
//  highlights for Liquid Glass, flat surface for Health Cards.
//

import SwiftUI

struct ThemedBackdrop: View {
    @Environment(\.appTheme) private var theme

    var body: some View {
        switch theme.id {
        case .liquidGlass:
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.04, green: 0.06, blue: 0.16),
                        Color(red: 0.11, green: 0.08, blue: 0.26),
                        Color(red: 0.03, green: 0.04, blue: 0.10)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                RadialGradient(
                    colors: [Color(red: 0.55, green: 0.75, blue: 1.0).opacity(0.22), .clear],
                    center: .topLeading, startRadius: 30, endRadius: 420
                )
                RadialGradient(
                    colors: [Color(red: 0.78, green: 0.55, blue: 1.0).opacity(0.18), .clear],
                    center: .bottomTrailing, startRadius: 40, endRadius: 460
                )
            }
            .ignoresSafeArea()

        case .healthCards:
            theme.background.ignoresSafeArea()
        }
    }
}
