//
//  ProductLookupSheet.swift
//  Slice 3.3: bottom sheet shown after a barcode scan or a manual-entry
//  selection. Confirms the resolved product, lets the user adjust
//  servings + meal type, and fires the optimistic log.
//
//  Visual states (in this order):
//    1. .loading — spinner + "Buscando producto…"
//    2. .found(Product) — product card + serving stepper + "Registrar" CTA
//    3. .notFound — empty state with "Crear alimento personalizado" link
//    4. .failed(error) — retry affordance
//

import SwiftUI

/// Resolution state of the product lookup. Drives the sheet's body.
enum ProductLookupState: Equatable {
    case loading
    case found(Product)
    case notFound
    case failed(String)
}

struct ProductLookupSheet: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    /// What we resolved. Owned by the parent so the parent can drive
    /// re-renders if it picks a different product mid-flow.
    let state: ProductLookupState
    /// Default meal type. The user can switch via the picker.
    let defaultMealType: MealType
    /// Closure invoked when the user taps "Registrar". Parent owns the
    /// MealService call + dismiss; this view stays presentation-only.
    let onLog: @MainActor (Product, Double, MealType) async -> Void
    /// Optional escape hatch for "Producto no encontrado" → manual flow.
    let onCreateCustom: (() -> Void)?

    @State private var servings: Double = 1.0
    @State private var mealType: MealType
    @State private var isLogging = false
    @State private var errorMessage: String?

    init(state: ProductLookupState,
         defaultMealType: MealType = .snack,
         onLog: @escaping @MainActor (Product, Double, MealType) async -> Void,
         onCreateCustom: (() -> Void)? = nil) {
        self.state = state
        self.defaultMealType = defaultMealType
        self.onLog = onLog
        self.onCreateCustom = onCreateCustom
        _mealType = State(initialValue: defaultMealType)
    }

    var body: some View {
        ZStack {
            ThemedBackdrop()
            VStack(spacing: 18) {
                topBar
                content
                Spacer(minLength: 0)
            }
            .padding(20)
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.ultraThinMaterial)
    }

    private var topBar: some View {
        HStack {
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(theme.textTertiary)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            loadingState
        case .found(let product):
            foundState(product)
        case .notFound:
            notFoundState
        case .failed(let message):
            failedState(message)
        }
    }

    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large).tint(theme.accent)
            Text("product_lookup_loading")
                .font(theme.font.body)
                .foregroundStyle(theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private func foundState(_ product: Product) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            productHeader(product)
            macrosStrip(product)
            servingsRow
            mealTypeRow
            logButton(product)
            if let errorMessage {
                Text(errorMessage)
                    .font(theme.font.caption)
                    .foregroundStyle(theme.negative)
            }
        }
    }

    private func productHeader(_ product: Product) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(theme.accent)
                .frame(width: 56, height: 56)
                .background(theme.accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 4) {
                Text(product.name)
                    .font(theme.font.titleCompact)
                    .foregroundStyle(theme.textPrimary)
                if let brand = product.brand {
                    Text(brand)
                        .font(theme.font.caption)
                        .foregroundStyle(theme.textSecondary)
                }
                Text(verbatim: "\(Int(product.caloriesPerServing)) kcal · \(Int(product.servingSizeG))g")
                    .font(theme.font.caption)
                    .foregroundStyle(theme.textTertiary)
            }
            Spacer()
        }
    }

    private func macrosStrip(_ product: Product) -> some View {
        HStack(spacing: 12) {
            macroPill(label: "P", value: product.proteinG * servings, color: theme.categoryColors[0])
            macroPill(label: "C", value: product.carbsG * servings, color: theme.categoryColors[1])
            macroPill(label: "G", value: product.fatG * servings, color: theme.categoryColors[2])
        }
    }

    private func macroPill(label: String, value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: label)
                .font(theme.font.caption)
                .foregroundStyle(theme.textTertiary)
            Text(verbatim: "\(Int(value))g")
                .font(theme.font.bodyMedium)
                .foregroundStyle(theme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: 12))
    }

    private var servingsRow: some View {
        HStack {
            Text("product_lookup_serving_label")
                .font(theme.font.bodyMedium)
                .foregroundStyle(theme.textPrimary)
            Spacer()
            Stepper(value: $servings, in: 0.25...10, step: 0.25) {
                Text(verbatim: String(format: "%.2f", servings))
                    .font(theme.font.body)
                    .foregroundStyle(theme.textSecondary)
            }
            .labelsHidden()
            Text(verbatim: String(format: "%.2f", servings))
                .font(theme.font.bodyMedium)
                .foregroundStyle(theme.textPrimary)
                .frame(minWidth: 40, alignment: .trailing)
        }
        .padding(.vertical, 8)
    }

    private var mealTypeRow: some View {
        HStack {
            Text("product_lookup_meal_type")
                .font(theme.font.bodyMedium)
                .foregroundStyle(theme.textPrimary)
            Spacer()
            Picker(selection: $mealType) {
                ForEach(MealType.allCases, id: \.self) { type in
                    Text(verbatim: type.label).tag(type)
                }
            } label: {
                Text(verbatim: mealType.label)
            }
            .pickerStyle(.menu)
            .tint(theme.accent)
        }
        .padding(.vertical, 8)
    }

    private func logButton(_ product: Product) -> some View {
        Button {
            Task { @MainActor in
                isLogging = true
                errorMessage = nil
                await onLog(product, servings, mealType)
                isLogging = false
                dismiss()
            }
        } label: {
            HStack {
                if isLogging {
                    ProgressView().tint(.white)
                }
                Text("product_lookup_log_button")
                    .font(theme.font.bodyMedium)
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(theme.accent, in: RoundedRectangle(cornerRadius: 14))
        }
        .disabled(isLogging)
    }

    private var notFoundState: some View {
        VStack(spacing: 14) {
            Image(systemName: "questionmark.diamond")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(theme.textSecondary)
            Text("product_lookup_not_found_title")
                .font(theme.font.titleCompact)
                .foregroundStyle(theme.textPrimary)
            Text("product_lookup_not_found_body")
                .font(theme.font.body)
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
            if let onCreateCustom {
                Button {
                    onCreateCustom()
                } label: {
                    Text("manual_entry_create_custom")
                        .font(theme.font.bodyMedium)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(theme.accent, in: RoundedRectangle(cornerRadius: 14))
                }
                .padding(.top, 8)
            }
        }
        .padding(.vertical, 30)
    }

    private func failedState(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(theme.negative)
            Text(verbatim: message)
                .font(theme.font.body)
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 30)
    }
}

#Preview("ProductLookupSheet — found") {
    ProductLookupSheet(
        state: .found(MockData.products.first!),
        defaultMealType: .breakfast,
        onLog: { _, _, _ in },
        onCreateCustom: nil
    )
    .environment(\.appTheme, LiquidGlassTheme())
    .preferredColorScheme(.dark)
}
