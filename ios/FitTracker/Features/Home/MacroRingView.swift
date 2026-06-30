//
//  MacroRingView.swift
//  Slice 0.5 mock — three-ring activity-style indicator. Outer ring is
//  total-calorie progress, inner two are the dominant macros. Real
//  implementation in Slice 2.5 with SwiftUI Charts integration.
//

import SwiftUI

struct MacroRingView: View {
    @Environment(\.appTheme) private var theme

    let consumed: Double
    let goal: Double
    let proteinPct: Double
    let carbsPct: Double
    let fatPct: Double

    private var caloriePct: Double { goal == 0 ? 0 : min(1, consumed / goal) }

    var body: some View {
        ZStack {
            ring(progress: caloriePct, color: theme.categoryColors[0], lineWidth: 12, inset: 0)
            ring(progress: carbsPct,    color: theme.categoryColors[1], lineWidth: 10, inset: 16)
            ring(progress: fatPct,      color: theme.categoryColors[2], lineWidth: 8,  inset: 30)

            VStack(spacing: 2) {
                Text("\(Int(caloriePct * 100))%")
                    .font(theme.font.titleCompact)
                    .foregroundStyle(theme.textPrimary)
                    .contentTransition(.numericText())
                Text("meta")
                    .font(theme.font.caption)
                    .foregroundStyle(theme.textTertiary)
            }
        }
        // The concentric rings are decorative individually; VoiceOver used to
        // read just "60% meta" (review Flash D1). Collapse them into one element
        // that announces each macro's progress toward goal.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(
            "dashboard.macros.progress \(Int(caloriePct * 100)) \(Int(carbsPct * 100)) \(Int(fatPct * 100))"
        ))
    }

    private func ring(progress: Double, color: Color, lineWidth: CGFloat, inset: CGFloat) -> some View {
        Circle()
            .trim(from: 0, to: max(0.001, progress))
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .padding(inset)
            .overlay {
                Circle()
                    .stroke(color.opacity(0.18), lineWidth: lineWidth)
                    .padding(inset)
            }
    }
}

#Preview {
    HStack(spacing: 20) {
        MacroRingView(consumed: 1450, goal: 2400, proteinPct: 0.65, carbsPct: 0.4, fatPct: 0.55)
            .frame(width: 130, height: 130)
        MacroRingView(consumed: 800, goal: 2400, proteinPct: 0.3, carbsPct: 0.2, fatPct: 0.4)
            .frame(width: 130, height: 130)
    }
    .padding()
    .background(LiquidGlassBackdropMini())
    .environment(\.appTheme, LiquidGlassTheme())
}

private struct LiquidGlassBackdropMini: View {
    var body: some View {
        LinearGradient(
            colors: [Color(red: 0.04, green: 0.06, blue: 0.16), Color(red: 0.11, green: 0.08, blue: 0.26)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }
}
