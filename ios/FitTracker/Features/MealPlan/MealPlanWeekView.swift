//
//  MealPlanWeekView.swift
//  Slice 0.5 mock — 7-day grid of meal slots. Drag-and-drop affordance
//  visible but inert (real DnD lands in Slice 4).
//

import SwiftUI

struct MealPlanWeekView: View {
    @Environment(\.appTheme) private var theme
    @Environment(MockServiceContainer.self) private var services

    @State private var plan: MealPlan?

    private let days = ["Lun", "Mar", "Mié", "Jue", "Vie", "Sáb", "Dom"]

    var body: some View {
        ZStack {
            ThemedBackdrop()
            ScrollView {
                VStack(spacing: 14) {
                    weekHeader
                    ForEach(0..<7, id: \.self) { day in
                        dayCard(day: day)
                    }
                    NavigationLink {
                        ShoppingListView()
                    } label: {
                        HStack {
                            Image(systemName: "cart.fill")
                            Text("Lista del super")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                        }
                        .padding(16)
                        .themedCard()
                        .foregroundStyle(theme.accent)
                    }
                    Spacer(minLength: 60)
                }
                .padding(16)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Plan semanal")
        .task { plan = try? await services.mealPlan.currentPlan() }
    }

    private var weekHeader: some View {
        HStack {
            Button { } label: { Image(systemName: "chevron.left") }
                .foregroundStyle(theme.textTertiary)
            Spacer()
            Text("Semana del 21 de abr.")
                .font(theme.font.titleCompact)
                .foregroundStyle(theme.textPrimary)
            Spacer()
            Button { } label: { Image(systemName: "chevron.right") }
                .foregroundStyle(theme.textTertiary)
        }
        .padding(.horizontal, 4)
    }

    private func dayCard(day: Int) -> some View {
        let items = plan?.items.filter { $0.dayIndex == day } ?? []
        return VStack(alignment: .leading, spacing: 8) {
            Text(days[day])
                .font(theme.font.captionMedium)
                .tracking(1.4)
                .foregroundStyle(theme.textTertiary)
            ForEach(MealType.allCases, id: \.self) { type in
                let item = items.first { $0.mealType == type }
                HStack(spacing: 10) {
                    Image(systemName: type.icon)
                        .foregroundStyle(item == nil ? theme.textTertiary : theme.accent)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(type.label)
                            .font(theme.font.caption)
                            .foregroundStyle(theme.textTertiary)
                        Text(item?.productName ?? "—")
                            .font(theme.font.bodyMedium)
                            .foregroundStyle(item == nil ? theme.textTertiary : theme.textPrimary)
                    }
                    Spacer()
                    if item != nil {
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(theme.textTertiary.opacity(0.6))
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(16)
        .themedCard()
    }
}
