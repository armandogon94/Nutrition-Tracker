//
//  ShoppingListView.swift
//  Slice 0.5 mock — items grouped by category with check toggle.
//

import SwiftUI

struct ShoppingListView: View {
    @Environment(\.appTheme) private var theme
    @Environment(MockServiceContainer.self) private var services
    @State private var items: [ShoppingItem] = []

    private var grouped: [(category: ShoppingCategory, items: [ShoppingItem])] {
        let dict = Dictionary(grouping: items, by: \.category)
        return ShoppingCategory.allCases.compactMap { cat in
            guard let xs = dict[cat], !xs.isEmpty else { return nil }
            return (cat, xs)
        }
    }

    var body: some View {
        ZStack {
            ThemedBackdrop()
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(grouped, id: \.category) { group in
                        section(category: group.category, items: group.items)
                    }
                    Spacer(minLength: 60)
                }
                .padding(16)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Lista del super")
        .navigationBarTitleDisplayMode(.inline)
        .task { items = (try? await services.mealPlan.shoppingList()) ?? [] }
    }

    private func section(category: ShoppingCategory, items: [ShoppingItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(category.label.uppercased())
                .font(theme.font.captionMedium)
                .tracking(1.4)
                .foregroundStyle(theme.textTertiary)
            VStack(spacing: 8) {
                ForEach(items) { item in
                    Button {
                        Task {
                            try? await services.mealPlan.toggleChecked(item.id)
                            self.items = (try? await services.mealPlan.shoppingList()) ?? []
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.checked ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22))
                                .foregroundStyle(item.checked ? theme.positive : theme.textTertiary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(theme.font.bodyMedium)
                                    .foregroundStyle(item.checked ? theme.textTertiary : theme.textPrimary)
                                    .strikethrough(item.checked)
                                Text(item.quantity)
                                    .font(theme.font.caption)
                                    .foregroundStyle(theme.textSecondary)
                            }
                            Spacer()
                        }
                        .padding(12)
                        .themedInnerCard()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
