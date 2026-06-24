//
//  MealPlanWeekView.swift
//  Slice 4.2-4.4: weekly meal planner. Days run as horizontal columns
//  (more mobile-native than a vertical table per the slice plan); each
//  column holds four meal-slot cells. Cells are native SwiftUI drop
//  targets and item chips are `.draggable`, so a meal can be dragged from
//  one day/slot to another. Tapping "+" opens the product-search add flow.
//
//  State lives in a single `MealPlanStore` (@Observable) constructed from
//  the live SwiftData context. Cells read only their own slice, so a drag
//  re-renders just the source + destination cells, not the whole grid.
//

import SwiftUI
import SwiftData

struct MealPlanWeekView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.modelContext) private var modelContext
    @Environment(MockServiceContainer.self) private var services

    @State private var store: MealPlanStore?
    /// The cell the user tapped "+" on, presented as an add sheet.
    @State private var addTarget: PlanCellTarget?
    @State private var pendingShoppingItems: [ShoppingItem]?
    @State private var navigateToShopping = false

    var body: some View {
        ZStack {
            ThemedBackdrop()
            if let store {
                content(store)
            } else {
                ProgressView().tint(theme.accent)
            }
        }
        .navigationTitle(Text("mealplan.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if store == nil {
                let s = makeStore()
                store = s
                await s.load()
            }
        }
        .sheet(item: $addTarget) { target in
            if let store {
                AddPlanItemSheet(
                    productsService: services.products,
                    dayLabel: MealPlanWeek.fullLabel(forDay: target.day),
                    mealType: target.mealType
                ) { product, servings in
                    Task { await store.addItem(product: product, servings: servings,
                                               day: target.day, mealType: target.mealType) }
                }
            }
        }
        .navigationDestination(isPresented: $navigateToShopping) {
            ShoppingListView(initialItems: pendingShoppingItems)
        }
    }

    private func makeStore() -> MealPlanStore {
        let userId = services.auth.currentUser?.id ?? MockData.user.id
        return MealPlanStore.live(context: modelContext, userId: userId)
    }

    @ViewBuilder
    private func content(_ store: MealPlanStore) -> some View {
        VStack(spacing: 0) {
            WeekPicker(
                label: store.headerLabel,
                onPrevious: { Task { await store.goToPreviousWeek() } },
                onNext: { Task { await store.goToNextWeek() } }
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            if store.plan == nil {
                emptyState(store)
            } else {
                grid(store)
                shoppingBar(store)
            }
        }
    }

    // MARK: - Grid

    private func grid(_ store: MealPlanStore) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(0..<7, id: \.self) { day in
                    dayColumn(store, day: day)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private func dayColumn(_ store: MealPlanStore, day: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(MealPlanWeek.shortLabel(forDay: day))
                    .font(theme.font.captionMedium)
                    .tracking(1.2)
                    .foregroundStyle(theme.textTertiary)
                Text(dayNumber(forDay: day, store: store))
                    .font(theme.font.titleCompact)
                    .foregroundStyle(theme.textPrimary)
            }
            .padding(.leading, 4)

            ForEach(MealType.allCases, id: \.self) { type in
                MealPlanCell(
                    day: day,
                    mealType: type,
                    items: store.items(forDay: day, mealType: type),
                    onAdd: { addTarget = PlanCellTarget(day: day, mealType: type) },
                    onDropItem: { itemId in
                        Task { await store.move(itemId: itemId, toDay: day, mealType: type) }
                    },
                    onRemove: { itemId in
                        Task { await store.remove(itemId: itemId) }
                    }
                )
            }
        }
        .frame(width: 168)
    }

    private func dayNumber(forDay day: Int, store: MealPlanStore) -> String {
        let date = MealPlanWeek.date(forDay: day, in: store.weekStart)
        let f = DateFormatter()
        f.calendar = MealPlanWeek.calendar
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "d"
        return f.string(from: date)
    }

    // MARK: - Shopping bar + empty state

    private func shoppingBar(_ store: MealPlanStore) -> some View {
        Button {
            Task {
                let items = await store.generateShoppingList()
                pendingShoppingItems = items
                navigateToShopping = true
            }
        } label: {
            HStack {
                Image(systemName: "cart.fill")
                Text("mealplan.generateList")
                    .font(theme.font.bodyMedium)
                Spacer()
                if store.isBusy {
                    ProgressView().tint(theme.accent)
                } else {
                    Image(systemName: "chevron.right").font(.system(size: 12))
                }
            }
            .padding(16)
            .themedCard()
            .foregroundStyle(theme.accent)
        }
        .buttonStyle(.plain)
        .padding(16)
    }

    private func emptyState(_ store: MealPlanStore) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(theme.textTertiary)
            Text("mealplan.emptyState.title")
                .font(theme.font.titleCompact)
                .foregroundStyle(theme.textPrimary)
            Text("mealplan.emptyState.message")
                .font(theme.font.body)
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button {
                Task { await store.createPlanForCurrentWeek() }
            } label: {
                HStack {
                    if store.isBusy { ProgressView().tint(.white) }
                    Text("mealplan.createPlan").font(theme.font.bodyMedium)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(theme.accent, in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 32)
            .padding(.top, 8)
            Spacer()
            Spacer()
        }
    }
}

/// Identifies which grid cell the user is acting on (add / drop target).
struct PlanCellTarget: Identifiable, Hashable {
    let day: Int
    let mealType: MealType
    var id: String { "\(day)-\(mealType.rawValue)" }
}

#Preview("MealPlanWeek — Liquid Glass") {
    NavigationStack { MealPlanWeekView() }
        .environment(\.appTheme, LiquidGlassTheme())
        .environment(MockServiceContainer())
        .modelContainer(try! PersistenceController.makeInMemory().container)
        .preferredColorScheme(.dark)
}
