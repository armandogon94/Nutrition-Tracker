//
//  HomeView.swift
//  Slice 3.7: hero calories card + today's meals from SwiftData (with a
//  Slice 0.5 mock fallback for fresh installs / previews). Adds the
//  "Registrar comida" FAB that routes into ScanView.
//

import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.appTheme) private var theme
    @Environment(MockServiceContainer.self) private var services

    @State private var nutrition: DailyNutrition?
    @State private var goal: NutritionGoal?
    @State private var refinedTDEE: RefinedTDEE?
    @State private var showScan = false
    @State private var isRefreshing = false

    @Query(sort: \MealEntity.mealDate, order: .forward)
    private var entities: [MealEntity]

    /// Today's meals — pulled from SwiftData when there are any rows
    /// for this calendar day, otherwise the Slice 0.5 mock so the home
    /// screen never looks empty during onboarding.
    private var meals: [Meal] {
        let today = Calendar(identifier: .iso8601).startOfDay(for: .now)
        let tomorrow = Calendar(identifier: .iso8601).date(byAdding: .day, value: 1, to: today) ?? Date()
        let local = entities
            .filter { $0.mealDate >= today && $0.mealDate < tomorrow }
            .map(Meal.init(from:))
        return local.isEmpty ? MockData.meals : local
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
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
            logMealFAB
        }
        .navigationTitle(navTitle)
        .toolbarBackground(.hidden, for: .navigationBar)
        .refreshable { await load() }
        .task { await load() }
        .sheet(isPresented: $showScan) {
            NavigationStack { ScanView() }
        }
    }

    private var navTitle: String {
        let name = services.auth.currentUser?.displayName.components(separatedBy: " ").first ?? ""
        return name.isEmpty ? "Inicio" : "Hola, \(name)"
    }

    @MainActor
    private func load() async {
        isRefreshing = true
        defer { isRefreshing = false }
        // Meals come from @Query so we don't refetch via the service.
        //
        // Both calls are @MainActor (NutritionServiceProtocol is main-actor
        // isolated as of Slice 2.4b, where `nutrition` became a protocol
        // existential so production can inject the real service). They hit
        // the same MainActor-bound SwiftData context, so awaiting them in
        // sequence keeps the existential on the main actor — `async let`
        // would force a non-Sendable existential across an isolation
        // boundary and fail strict concurrency. Each method is cache-first
        // (stale-while-revalidate) so this stays fast.
        nutrition = try? await services.nutrition.dailyNutrition(for: Date())
        goal = try? await services.nutrition.currentGoal()
        await refineTDEE()
    }

    /// Slice 2.6: refine the displayed daily-burn estimate from a FRESH
    /// HealthKit bodyweight sample when one exists, else fall back to the
    /// profile weight. Quietly no-ops when there's no profile / no Health
    /// access — the hero card just omits the burn chip.
    @MainActor
    private func refineTDEE() async {
        guard let profile = try? await services.profile.profile() else {
            refinedTDEE = nil
            return
        }
        let sample = try? await HealthKitService.shared.latestBodyMassReading()
        refinedTDEE = HomeViewModel.refineTDEE(profile: profile, healthKit: sample)
    }

    private var logMealFAB: some View {
        Button {
            showScan = true
        } label: {
            Label {
                Text("meals_log_meal_fab")
                    .font(theme.font.bodyMedium)
            } icon: {
                Image(systemName: "barcode.viewfinder")
            }
            .padding(.horizontal, 18).padding(.vertical, 12)
            .background(theme.accent, in: Capsule())
            .foregroundStyle(.white)
        }
        .padding(20)
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

            if let refinedTDEE {
                tdeeChip(refinedTDEE)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .themedCard()
    }

    /// Slice 2.6: estimated daily energy burn (TDEE). When it was refined
    /// from a recent Apple Health bodyweight sample, an inline hint with the
    /// Health glyph tells the user where the number came from.
    private func tdeeChip(_ refined: RefinedTDEE) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "flame.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.accentSecondary)
            Text("\(Text("home.tdee.label")) · \(Int(refined.tdee)) kcal")
                .font(theme.font.caption)
                .foregroundStyle(theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if refined.usedHealthKit {
                Spacer(minLength: 6)
                HStack(spacing: 3) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text("home.tdee.fromHealth")
                        .font(theme.font.caption)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .foregroundStyle(theme.positive)
            }
        }
        .padding(.top, 4)
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
