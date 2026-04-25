//
//  MealsListView.swift
//  Slice 0.5 mock — meals grouped by type with totals.
//

import SwiftUI

struct MealsListView: View {
    @Environment(\.appTheme) private var theme
    @Environment(MockServiceContainer.self) private var services

    @State private var meals: [Meal] = []

    var body: some View {
        ZStack {
            ThemedBackdrop()
            ScrollView {
                VStack(spacing: 14) {
                    ForEach(MealType.allCases, id: \.self) { type in
                        if let meal = meals.first(where: { $0.mealType == type }) {
                            mealCard(meal)
                        } else {
                            emptyMealCard(type)
                        }
                    }
                    Spacer(minLength: 60)
                }
                .padding(16)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Comidas")
        .task { meals = (try? await services.meals.mealsToday()) ?? [] }
    }

    private func mealCard(_ meal: Meal) -> some View {
        NavigationLink {
            MealDetailView(meal: meal)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: meal.mealType.icon)
                        .foregroundStyle(theme.accent)
                        .frame(width: 32, height: 32)
                        .background(theme.accent.opacity(0.2), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(meal.mealType.label)
                            .font(theme.font.titleCompact)
                            .foregroundStyle(theme.textPrimary)
                        Text(timeLabel(meal.mealDate))
                            .font(theme.font.caption)
                            .foregroundStyle(theme.textSecondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(Int(meal.totalCalories))")
                            .font(theme.font.titleCompact)
                            .foregroundStyle(theme.textPrimary)
                        Text("kcal")
                            .font(theme.font.caption)
                            .foregroundStyle(theme.textTertiary)
                    }
                }
                Divider().opacity(0.18)
                ForEach(meal.items) { item in
                    HStack {
                        Text(item.productName)
                            .font(theme.font.body)
                            .foregroundStyle(theme.textSecondary)
                        Spacer()
                        Text("\(Int(item.calories)) kcal")
                            .font(theme.font.caption)
                            .foregroundStyle(theme.textTertiary)
                    }
                }
            }
            .padding(16)
            .themedCard()
        }
        .buttonStyle(.plain)
    }

    private func emptyMealCard(_ type: MealType) -> some View {
        HStack {
            Image(systemName: type.icon)
                .foregroundStyle(theme.textTertiary)
                .frame(width: 32, height: 32)
                .background(theme.surfaceSecondary, in: Circle())
            VStack(alignment: .leading) {
                Text(type.label)
                    .font(theme.font.bodyMedium)
                    .foregroundStyle(theme.textSecondary)
                Text("Sin registrar")
                    .font(theme.font.caption)
                    .foregroundStyle(theme.textTertiary)
            }
            Spacer()
            Image(systemName: "plus.circle")
                .foregroundStyle(theme.accent)
        }
        .padding(16)
        .themedInnerCard()
    }

    private func timeLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }
}

struct MealDetailView: View {
    @Environment(\.appTheme) private var theme
    let meal: Meal

    var body: some View {
        ZStack {
            ThemedBackdrop()
            ScrollView {
                VStack(spacing: 14) {
                    summaryCard
                    itemsCard
                    Spacer(minLength: 60)
                }
                .padding(16)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(meal.mealType.label)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var summaryCard: some View {
        VStack(spacing: 8) {
            Text("\(Int(meal.totalCalories))")
                .font(theme.font.heroNumeral)
                .foregroundStyle(theme.textPrimary)
            Text("kcal · \(meal.items.count) elementos")
                .font(theme.font.caption)
                .foregroundStyle(theme.textSecondary)
            HStack(spacing: 18) {
                macroChip("P", value: meal.totalProtein, color: theme.categoryColors[0])
                macroChip("C", value: meal.totalCarbs,   color: theme.categoryColors[1])
                macroChip("G", value: meal.totalFat,     color: theme.categoryColors[2])
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .themedCard()
    }

    private func macroChip(_ label: String, value: Double, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text("\(label) \(Int(value))g")
                .font(theme.font.captionMedium)
                .foregroundStyle(theme.textPrimary)
        }
    }

    private var itemsCard: some View {
        VStack(spacing: 10) {
            ForEach(meal.items) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.productName)
                            .font(theme.font.bodyMedium)
                            .foregroundStyle(theme.textPrimary)
                        Text("\(item.brand ?? "Sin marca") · \(servingsLabel(item.servings))")
                            .font(theme.font.caption)
                            .foregroundStyle(theme.textSecondary)
                    }
                    Spacer()
                    Text("\(Int(item.calories)) kcal")
                        .font(theme.font.bodyMedium)
                        .foregroundStyle(theme.textPrimary)
                }
                if item.id != meal.items.last?.id {
                    Divider().opacity(0.18)
                }
            }
        }
        .padding(16)
        .themedCard()
    }

    private func servingsLabel(_ s: Double) -> String {
        if s == 1 { return "1 porción" }
        return String(format: "%.1f porciones", s)
    }
}
