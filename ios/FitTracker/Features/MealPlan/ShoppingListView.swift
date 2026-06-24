//
//  ShoppingListView.swift
//  Slice 4.5: categorized shopping list with persistent check state.
//  Items are grouped by ShoppingCategory (Produce, Dairy, Proteins,
//  Grains, Pantry, Frozen, Beverages, Other). Tapping a row toggles its
//  checked state — optimistically in SwiftData, then PATCHed to the
//  backend so it round-trips and survives relaunch. Toolbar offers
//  "Clear checked" and "Regenerate list".
//
//  The view constructs a real MealPlanService from the live SwiftData
//  context (matching MealsListView's pattern). It can be seeded with
//  `initialItems` from the generate flow so navigating straight in shows
//  the freshly built list without a second round-trip.
//

import SwiftUI
import SwiftData

struct ShoppingListView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.modelContext) private var modelContext
    @Environment(MockServiceContainer.self) private var services

    /// Optional pre-generated items (from "Generate shopping list").
    let initialItems: [ShoppingItem]?

    @State private var service: MealPlanService?
    @State private var items: [ShoppingItem] = []
    @State private var listId: UUID?
    @State private var isWorking = false

    init(initialItems: [ShoppingItem]? = nil) {
        self.initialItems = initialItems
    }

    private var grouped: [(category: ShoppingCategory, items: [ShoppingItem])] {
        let dict = Dictionary(grouping: items, by: \.category)
        return ShoppingCategory.allCases.compactMap { cat in
            guard let xs = dict[cat], !xs.isEmpty else { return nil }
            return (cat, xs.sorted { $0.name < $1.name })
        }
    }

    private var remaining: Int { items.filter { !$0.checked }.count }

    var body: some View {
        ZStack {
            ThemedBackdrop()
            if items.isEmpty {
                emptyState
            } else {
                listContent
            }
        }
        .navigationTitle(Text("shopping.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .task { await bootstrap() }
    }

    // MARK: - Content

    private var listContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                progressHeader
                ForEach(grouped, id: \.category) { group in
                    section(category: group.category, items: group.items)
                }
                Spacer(minLength: 60)
            }
            .padding(16)
        }
        .scrollContentBackground(.hidden)
    }

    private var progressHeader: some View {
        HStack {
            Text("\(remaining)/\(items.count)")
                .font(theme.font.titleCompact)
                .foregroundStyle(theme.textPrimary)
            Spacer()
            ProgressView(value: Double(items.count - remaining), total: Double(max(items.count, 1)))
                .tint(theme.positive)
                .frame(width: 120)
        }
        .padding(.horizontal, 4)
        // VoiceOver reads "N de M pendientes" instead of "N slash M".
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            String(localized: "shopping.itemsRemaining \(remaining) \(items.count)")
        )
    }

    private func section(category: ShoppingCategory, items: [ShoppingItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(category.label.uppercased())
                .font(theme.font.captionMedium)
                .tracking(1.4)
                .foregroundStyle(theme.textTertiary)
            VStack(spacing: 8) {
                ForEach(items) { item in
                    row(item)
                }
            }
        }
    }

    private func row(_ item: ShoppingItem) -> some View {
        Button {
            Task { await toggle(item) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.checked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(item.checked ? theme.positive : theme.textTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: item.name)
                        .font(theme.font.bodyMedium)
                        .foregroundStyle(item.checked ? theme.textTertiary : theme.textPrimary)
                        .strikethrough(item.checked)
                    Text(verbatim: item.quantity)
                        .font(theme.font.caption)
                        .foregroundStyle(theme.textSecondary)
                }
                Spacer()
            }
            .padding(12)
            .themedInnerCard()
        }
        .buttonStyle(.plain)
        // Swipe-to-check via a leading swipe action on each row.
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                Task { await toggle(item) }
            } label: {
                Label(item.checked ? "mealplan.empty" : "shopping.title",
                      systemImage: item.checked ? "arrow.uturn.left" : "checkmark")
            }
            .tint(item.checked ? theme.textTertiary : theme.positive)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "cart")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(theme.textTertiary)
            Text("shopping.empty.title")
                .font(theme.font.titleCompact)
                .foregroundStyle(theme.textPrimary)
            Text("shopping.empty.message")
                .font(theme.font.body)
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    Task { await clearChecked() }
                } label: {
                    Label("shopping.clearChecked", systemImage: "checklist.unchecked")
                }
                .disabled(items.allSatisfy { !$0.checked })

                Button {
                    Task { await regenerate() }
                } label: {
                    Label("shopping.regenerate", systemImage: "arrow.clockwise")
                }
            } label: {
                if isWorking {
                    ProgressView().tint(theme.accent)
                } else {
                    Image(systemName: "ellipsis.circle").foregroundStyle(theme.accent)
                }
            }
        }
    }

    // MARK: - Actions

    private func bootstrap() async {
        let svc = service ?? MealPlanService(api: APIClient(), context: modelContext)
        service = svc

        if let initialItems, !initialItems.isEmpty {
            items = sortForDisplay(initialItems)
        } else {
            items = sortForDisplay((try? await svc.shoppingList()) ?? [])
        }
        listId = try? await svc.currentShoppingListId()
    }

    private func toggle(_ item: ShoppingItem) async {
        // Optimistic UI flip first.
        let newValue = !item.checked
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx].checked = newValue
        }
        PlanHaptics.selection()
        guard let service, let listId else { return }
        do {
            try await service.setChecked(item.id, checked: newValue, listId: listId)
        } catch {
            // Local cache already updated optimistically (offline-first);
            // refresh from cache so the UI matches what persisted.
            items = sortForDisplay((try? await service.shoppingList()) ?? items)
        }
    }

    private func clearChecked() async {
        guard let service, let listId else { return }
        isWorking = true
        defer { isWorking = false }
        for item in items where item.checked {
            try? await service.setChecked(item.id, checked: false, listId: listId)
        }
        items = sortForDisplay((try? await service.shoppingList()) ?? items)
    }

    private func regenerate() async {
        guard let service, let listId else { return }
        isWorking = true
        defer { isWorking = false }
        // Find the plan this list was generated from via the cache, then
        // re-run generation. currentPlan() gives the latest plan, which is
        // the one the list belongs to in the common single-plan case.
        _ = listId
        let userId = services.auth.currentUser?.id ?? MockData.user.id
        if let plan = try? await service.currentPlan() {
            let fresh = (try? await service.generateShoppingList(forPlan: plan.id, userId: userId)) ?? []
            items = sortForDisplay(fresh)
            self.listId = try? await service.currentShoppingListId()
        }
    }

    private func sortForDisplay(_ xs: [ShoppingItem]) -> [ShoppingItem] {
        xs.sorted {
            if $0.category != $1.category {
                return categoryOrder($0.category) < categoryOrder($1.category)
            }
            return $0.name < $1.name
        }
    }

    private func categoryOrder(_ c: ShoppingCategory) -> Int {
        ShoppingCategory.allCases.firstIndex(of: c) ?? .max
    }
}

#Preview("ShoppingList — Liquid Glass") {
    NavigationStack {
        ShoppingListView(initialItems: MockData.shoppingList)
    }
    .environment(\.appTheme, LiquidGlassTheme())
    .environment(MockServiceContainer())
    .modelContainer(try! PersistenceController.makeInMemory().container)
    .preferredColorScheme(.dark)
}
