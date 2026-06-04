//
//  AddPlanItemSheet.swift
//  Slice 4.4: the "+" add flow for a planner cell. Two steps in one sheet:
//    1. search-as-you-type product picker (300ms debounce, offline cache
//       fallback — same contract as Scan's ManualEntrySheet)
//    2. a servings stepper to confirm quantity for the chosen product
//  On confirm it hands (product, servings) back to the caller, which routes
//  it through MealPlanStore.addItem.
//

import SwiftUI

struct AddPlanItemSheet: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    let productsService: any ProductsServiceProtocol
    let dayLabel: String
    let mealType: MealType
    let onConfirm: (Product, Double) -> Void

    @State private var selected: Product?

    var body: some View {
        NavigationStack {
            ZStack {
                ThemedBackdrop()
                if let selected {
                    QuantityStep(
                        product: selected,
                        dayLabel: dayLabel,
                        mealType: mealType,
                        onBack: { self.selected = nil },
                        onConfirm: { servings in
                            onConfirm(selected, servings)
                            PlanHaptics.success()
                            dismiss()
                        }
                    )
                } else {
                    ProductSearchStep(productsService: productsService) { product in
                        selected = product
                    }
                }
            }
            .navigationTitle(Text(selected == nil ? "mealplan.searchFood" : "mealplan.quantity"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Text("common_cancel").foregroundStyle(theme.accent)
                    }
                }
            }
        }
    }
}

// MARK: - Step 1: product search

private struct ProductSearchStep: View {
    @Environment(\.appTheme) private var theme

    let productsService: any ProductsServiceProtocol
    let onSelect: (Product) -> Void

    @State private var query = ""
    @State private var results: [Product] = []
    @State private var isSearching = false
    @State private var debouncer = SearchDebouncer()

    var body: some View {
        Group {
            if isSearching && results.isEmpty {
                ProgressView().controlSize(.large).tint(theme.accent)
            } else if results.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .searchable(text: $query, prompt: Text("mealplan.searchFood"))
        .onChange(of: query) { _, newValue in
            debouncer.scheduleSearch(query: newValue) { q in await runSearch(q) }
        }
        .task { await runSearch("") }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(theme.textTertiary)
            Text("manual_entry_no_results")
                .font(theme.font.body)
                .foregroundStyle(theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private var list: some View {
        List {
            ForEach(results) { product in
                Button { onSelect(product) } label: { row(product) }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func row(_ product: Product) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "shippingbox.fill")
                .foregroundStyle(theme.accent)
                .frame(width: 38, height: 38)
                .background(theme.accent.opacity(0.18), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: product.name)
                    .font(theme.font.bodyMedium)
                    .foregroundStyle(theme.textPrimary)
                Text(verbatim: "\(product.brand ?? "—") · \(Int(product.caloriesPerServing)) kcal / \(Int(product.servingSizeG))g")
                    .font(theme.font.caption)
                    .foregroundStyle(theme.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundStyle(theme.textTertiary)
        }
        .padding(12)
        .themedInnerCard()
    }

    @MainActor
    private func runSearch(_ q: String) async {
        isSearching = true
        defer { isSearching = false }
        do {
            results = try await productsService.search(query: q)
        } catch {
            // Keep previous results on transient failure (no flicker).
        }
    }
}

// MARK: - Step 2: quantity

private struct QuantityStep: View {
    @Environment(\.appTheme) private var theme

    let product: Product
    let dayLabel: String
    let mealType: MealType
    let onBack: () -> Void
    let onConfirm: (Double) -> Void

    @State private var servings: Double = 1.0

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                summaryCard
                stepperCard
                confirmButton
                Spacer(minLength: 40)
            }
            .padding(16)
        }
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .top) {
            HStack {
                Button(action: onBack) {
                    Label("common_close", systemImage: "chevron.left")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(theme.accent)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
        }
    }

    private var summaryCard: some View {
        VStack(spacing: 6) {
            Text(verbatim: product.name)
                .font(theme.font.titleCompact)
                .foregroundStyle(theme.textPrimary)
                .multilineTextAlignment(.center)
            Text(verbatim: "\(dayLabel) · \(mealType.label)")
                .font(theme.font.caption)
                .foregroundStyle(theme.textSecondary)
            Text(verbatim: "\(Int(product.caloriesPerServing * servings)) kcal")
                .font(theme.font.heroNumeral)
                .foregroundStyle(theme.accent)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .themedCard()
    }

    private var stepperCard: some View {
        HStack {
            Text("mealplan.servings")
                .font(theme.font.bodyMedium)
                .foregroundStyle(theme.textPrimary)
            Spacer()
            Button { servings = max(0.5, servings - 0.5) } label: {
                Image(systemName: "minus.circle.fill").font(.system(size: 28))
            }
            .foregroundStyle(theme.accent)
            Text(servingsLabel)
                .font(theme.font.titleCompact)
                .foregroundStyle(theme.textPrimary)
                .frame(minWidth: 48)
            Button { servings = min(20, servings + 0.5) } label: {
                Image(systemName: "plus.circle.fill").font(.system(size: 28))
            }
            .foregroundStyle(theme.accent)
        }
        .padding(16)
        .themedCard()
    }

    private var confirmButton: some View {
        Button { onConfirm(servings) } label: {
            Text("mealplan.add")
                .font(theme.font.bodyMedium)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(theme.accent, in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    private var servingsLabel: String {
        if servings == servings.rounded() { return "\(Int(servings))" }
        return String(format: "%.1f", servings)
    }
}

#Preview("AddPlanItemSheet") {
    AddPlanItemSheet(
        productsService: MockProductsService(),
        dayLabel: "Lunes",
        mealType: .breakfast
    ) { _, _ in }
    .environment(\.appTheme, LiquidGlassTheme())
    .preferredColorScheme(.dark)
}
