//
//  WeekPicker.swift
//  Slice 4.2: the "‹ Semana del 20 abr ›" header above the weekly grid.
//  Pure presentation — navigation callbacks are owned by MealPlanStore.
//

import SwiftUI

struct WeekPicker: View {
    @Environment(\.appTheme) private var theme

    let label: String
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack {
            Button(action: onPrevious) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .foregroundStyle(theme.accent)

            Spacer()

            Text(label)
                .font(theme.font.titleCompact)
                .foregroundStyle(theme.textPrimary)

            Spacer()

            Button(action: onNext) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .foregroundStyle(theme.accent)
        }
    }
}
