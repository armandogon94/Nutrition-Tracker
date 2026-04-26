//
//  ManualEntrySheet.swift
//  Slice 3.4: search-as-you-type product picker. Debounces the user's
//  query at 300ms, shares an in-flight Task so we never have two
//  network calls outstanding for stale text, and surfaces the offline
//  cache automatically when the network search fails.
//
//  This intentionally does NOT use Combine — the rest of the app uses
//  Swift Concurrency, and a tiny Task-based debouncer composes better
//  with @Observable view models than a Combine subject.
//

import SwiftUI

struct ManualEntrySheet: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    /// Resolved product chosen by the user. Parent presents
    /// ProductLookupSheet against this and dismisses ManualEntrySheet.
    let onSelect: (Product) -> Void
    /// Source for live search results.
    let productsService: any ProductsServiceProtocol

    @State private var query: String = ""
    @State private var results: [Product] = []
    @State private var isSearching = false
    @State private var debouncer: SearchDebouncer = SearchDebouncer()

    var body: some View {
        NavigationStack {
            ZStack {
                ThemedBackdrop()
                content
            }
            .searchable(text: $query, prompt: Text("manual_entry_prompt"))
            .onChange(of: query) { _, newValue in
                debouncer.scheduleSearch(query: newValue) { q in
                    await runSearch(q)
                }
            }
            .navigationTitle(Text("manual_entry_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Text("common_close")
                            .foregroundStyle(theme.accent)
                    }
                }
            }
            .task {
                // Initial population so the empty state isn't completely
                // bare on open. We seed with the first /products/search?q=
                // call against an empty-ish hint, but only when the user
                // hasn't typed yet.
                await runSearch("")
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isSearching && results.isEmpty {
            ProgressView().controlSize(.large).tint(theme.accent)
        } else if results.isEmpty {
            emptyState
        } else {
            resultsList
        }
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

    private var resultsList: some View {
        List {
            ForEach(results) { product in
                Button {
                    onSelect(product)
                    dismiss()
                } label: {
                    productRow(product)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func productRow(_ product: Product) -> some View {
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
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(theme.accent)
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
            // Network down or transient — keep whatever we had on screen.
            // (When backend search returns no results, search() returns
            // an empty array, not throws — so we don't clobber the list
            // with []. That's intentional: keeping the previous result
            // avoids flicker as the user types.)
        }
    }
}

/// Tiny task-based debouncer used by `searchable`. Cancels the in-flight
/// task on every keystroke so only the most recent query reaches the
/// network. 300ms matches the SPEC §4 acceptance criterion.
@MainActor
@Observable
final class SearchDebouncer {
    private var task: Task<Void, Never>?
    var debounceMillis: UInt64 = 300

    func scheduleSearch(query: String,
                        action: @escaping @MainActor @Sendable (String) async -> Void) {
        task?.cancel()
        task = Task { @MainActor [debounceMillis] in
            try? await Task.sleep(nanoseconds: debounceMillis * 1_000_000)
            if Task.isCancelled { return }
            await action(query)
        }
    }

    func cancel() {
        task?.cancel()
    }
}

#Preview("ManualEntrySheet") {
    ManualEntrySheet(
        onSelect: { _ in },
        productsService: MockProductsService()
    )
    .environment(\.appTheme, LiquidGlassTheme())
    .preferredColorScheme(.dark)
}
