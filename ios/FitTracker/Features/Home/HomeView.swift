//
//  HomeView.swift
//  Slice 0.5 mock — hero calories card with macro rings, today's meals.
//

import SwiftUI

struct HomeView: View {
    @Environment(\.appTheme) private var theme
    @Environment(MockServiceContainer.self) private var services

    @State private var nutrition: DailyNutrition?
    @State private var goal: NutritionGoal?
    @State private var meals: [Meal] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                heroCard
                statRow
                recentMealsCard
                Spacer(minLength: 60)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .scrollContentBackground(.hidden)
        .background(ThemedBackdrop())
        .navigationTitle("Hola, \(services.auth.currentUser?.displayName ?? "")")
        .toolbarBackground(.hidden, for: .navigationBar)
        .task {
            nutrition = try? await services.nutrition.dailyNutrition(for: Date())
            goal = try? await services.nutrition.currentGoal()
            meals = (try? await services.meals.mealsToday()) ?? []
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("CALORÍAS HOY")
                .font(theme.font.captionMedium)
                .tracking(1.5)
                .foregroundStyle(theme.textTertiary)

            HStack(alignment: .center, spacing: 18) {
                MacroRingView(
                    consumed: nutrition?.calories ?? 0,
                    goal: Double(goal?.dailyCalories ?? 2400),
                    proteinPct: macroPct(\.proteinG, goalKey: \.proteinG),
                    carbsPct: macroPct(\.carbsG, goalKey: \.carbsG),
                    fatPct: macroPct(\.fatG, goalKey: \.fatG)
                )
                .frame(width: 120, height: 120)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(Int(nutrition?.calories ?? 0))")
                            .font(theme.font.heroNumeral)
                            .foregroundStyle(theme.textPrimary)
                            .contentTransition(.numericText())
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text("/ \(goal?.dailyCalories ?? 2400)")
                            .font(theme.font.body)
                            .foregroundStyle(theme.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    Text("kcal")
                        .font(theme.font.caption)
                        .foregroundStyle(theme.textTertiary)
                    Spacer().frame(height: 4)
                    macroLine("Proteína", value: nutrition?.proteinG ?? 0, goal: Double(goal?.proteinG ?? 0), color: theme.categoryColors[0])
                    macroLine("Carbos", value: nutrition?.carbsG ?? 0, goal: Double(goal?.carbsG ?? 0), color: theme.categoryColors[1])
                    macroLine("Grasa", value: nutrition?.fatG ?? 0, goal: Double(goal?.fatG ?? 0), color: theme.categoryColors[2])
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .themedCard()
    }

    private func macroLine(_ label: String, value: Double, goal: Double, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text("\(label) \(Int(value))/\(Int(goal))g")
                .font(theme.font.caption)
                .foregroundStyle(theme.textSecondary)
        }
    }

    private var statRow: some View {
        HStack(spacing: 12) {
            statCard(label: "Comidas", value: "\(meals.count)", icon: "fork.knife", tint: theme.accent)
            statCard(label: "Fibra", value: "\(Int(nutrition?.fiberG ?? 0))g", icon: "leaf.fill", tint: theme.positive)
            statCard(label: "Agua", value: "1.8L", icon: "drop.fill", tint: theme.accentSecondary)
        }
    }

    private func statCard(label: String, value: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.18), in: Circle())
            Text(label)
                .font(theme.font.caption)
                .foregroundStyle(theme.textSecondary)
            Text(value)
                .font(theme.font.titleCompact)
                .foregroundStyle(theme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .themedCard(radius: theme.radii.card - 4)
    }

    private var recentMealsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Comidas de hoy")
                    .font(theme.font.titleCompact)
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                NavigationLink("Ver todas") { MealsListView() }
                    .font(theme.font.caption)
                    .foregroundStyle(theme.accent)
            }
            VStack(spacing: 8) {
                ForEach(meals) { meal in
                    HomeMealRow(meal: meal)
                    if meal.id != meals.last?.id {
                        Divider().opacity(0.2)
                    }
                }
            }
        }
        .padding(18)
        .themedCard()
    }

    // MARK: - Helpers

    private func macroPct<G>(_ key: KeyPath<DailyNutrition, Double>,
                              goalKey: KeyPath<NutritionGoal, G>) -> Double where G: BinaryInteger {
        guard let nutrition, let goal else { return 0 }
        let g = Double(goal[keyPath: goalKey])
        return g == 0 ? 0 : min(1, nutrition[keyPath: key] / g)
    }
}

private struct HomeMealRow: View {
    @Environment(\.appTheme) private var theme
    let meal: Meal

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: meal.mealType.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.accent)
                .frame(width: 32, height: 32)
                .background(theme.accent.opacity(0.18), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(meal.mealType.label)
                    .font(theme.font.bodyMedium)
                    .foregroundStyle(theme.textPrimary)
                Text("\(meal.items.count) elementos")
                    .font(theme.font.caption)
                    .foregroundStyle(theme.textSecondary)
            }
            Spacer()
            Text("\(Int(meal.totalCalories)) kcal")
                .font(theme.font.bodyMedium)
                .foregroundStyle(theme.textPrimary)
        }
    }
}

#Preview("Home — Liquid Glass") {
    NavigationStack { HomeView() }
        .environment(\.appTheme, LiquidGlassTheme())
        .environment({
            let s = MockServiceContainer()
            (s.auth as? MockAuthService)?.quickLogin(as: MockData.user)
            return s
        }())
        .preferredColorScheme(.dark)
}
