//
//  MealsListView.swift
//  Slice 3.7: today's meals grouped by type. Reads MealEntity straight
//  out of SwiftData via @Query, sorted by mealDate. When the store is
//  empty (typically: fresh install before first scan) we fall back to
//  the Slice 0.5 mock data so previews and TestFlight reviewers don't
//  see a stark empty state.
//

import SwiftUI
import SwiftData

struct MealsListView: View {
    @Environment(\.appTheme) private var theme
    @Environment(MockServiceContainer.self) private var services
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \MealEntity.mealDate, order: .forward)
    private var entities: [MealEntity]

    /// Snapshot of struct-shaped meals for rendering. Computed from
    /// either the @Query results (real data) or the Slice 0.5 mock.
    private var meals: [Meal] {
        let today = Calendar(identifier: .iso8601).startOfDay(for: .now)
        let tomorrow = Calendar(identifier: .iso8601).date(byAdding: .day, value: 1, to: today) ?? Date()
        let local = entities
            .filter { $0.mealDate >= today && $0.mealDate < tomorrow }
            .map(Meal.init(from:))
        return local.isEmpty ? MockData.meals : local
    }

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
        .navigationTitle(Text("meals_title"))
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
                Text("meals_unregistered")
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
