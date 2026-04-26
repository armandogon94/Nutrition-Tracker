//
//  ExercisesBrowserView.swift
//  Slice 6.4: searchable exercise browser with muscle/equipment filter
//  chips. Search debounced 300ms via DebouncedSearcher. Backed by
//  ExercisesService (cache-aside; offline still works after one online
//  sync). LazyVStack with stable IDs for 60fps scrolling at 100+ rows.
//
//  Skills invoked:
//   - everything-claude-code:swiftui-patterns
//   - performance-optimization (LazyVStack stable id, AsyncImage with
//     .task cancellation on scroll-off)
//

import SwiftUI

struct ExercisesBrowserView: View {
    @Environment(\.appTheme) private var theme
    @Environment(MockServiceContainer.self) private var container

    /// Optional override for previews / tests.
    var injectedService: (any ExercisesServiceProtocol)?

    @State private var query: String = ""
    @State private var muscle: MuscleGroup?
    @State private var equipment: Equipment?
    @State private var results: [Exercise] = []
    @State private var isLoading = false
    @State private var debouncer: DebouncedSearcher?

    private var service: any ExercisesServiceProtocol {
        injectedService ?? container.exercises
    }

    var body: some View {
        ZStack {
            ThemedBackdrop()
            VStack(spacing: 0) {
                filtersBar
                if isLoading && results.isEmpty {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(theme.accent)
                    Spacer()
                } else if results.isEmpty {
                    Spacer()
                    Text(String(localized: "exercises.empty"))
                        .font(theme.font.body)
                        .foregroundStyle(theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(results, id: \.id) { exercise in
                                NavigationLink {
                                    ExerciseDetailView(exercise: exercise)
                                } label: {
                                    ExerciseRow(exercise: exercise)
                                }
                                .buttonStyle(.plain)
                            }
                            Spacer(minLength: 30)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    }
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .searchable(text: $query, prompt: Text(String(localized: "exercises.searchPrompt")))
        .navigationTitle(Text(String(localized: "exercises.title")))
        .onChange(of: query) { _, newValue in
            debouncer?.fire(query: newValue)
        }
        .onChange(of: muscle) { _, _ in Task { await reload() } }
        .onChange(of: equipment) { _, _ in Task { await reload() } }
        .task {
            if debouncer == nil {
                debouncer = makeDebouncer()
            }
            await reload()
        }
    }

    // MARK: - Filters

    private var filtersBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(
                    label: String(localized: "exercises.filter.muscle"),
                    selected: muscle?.label
                ) {
                    muscle = nextMuscle()
                }
                chip(
                    label: String(localized: "exercises.filter.equipment"),
                    selected: equipment?.label
                ) {
                    equipment = nextEquipment()
                }
                if muscle != nil || equipment != nil {
                    Button {
                        muscle = nil
                        equipment = nil
                    } label: {
                        Label(
                            String(localized: "exercises.filter.clear"),
                            systemImage: "xmark.circle.fill"
                        )
                        .font(theme.font.caption)
                        .foregroundStyle(theme.negative)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 8)
    }

    private func chip(label: String,
                      selected: String?,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(selected ?? label)
                    .font(theme.font.captionMedium)
                Image(systemName: "chevron.down").font(.system(size: 10))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(selected == nil
                               ? theme.surfaceSecondary
                               : theme.accent.opacity(0.2))
            )
            .foregroundStyle(selected == nil ? theme.textSecondary : theme.accent)
        }
    }

    // MARK: - Chip cycling

    private func nextMuscle() -> MuscleGroup? {
        let order: [MuscleGroup?] = [nil] + MuscleGroup.allCases.map { Optional($0) }
        let i = order.firstIndex(of: muscle) ?? 0
        return order[(i + 1) % order.count]
    }

    private func nextEquipment() -> Equipment? {
        let order: [Equipment?] = [nil] + Equipment.allCases.map { Optional($0) }
        let i = order.firstIndex(of: equipment) ?? 0
        return order[(i + 1) % order.count]
    }

    // MARK: - Loading

    private func makeDebouncer() -> DebouncedSearcher {
        DebouncedSearcher(intervalMillis: 300) { @Sendable [self] _ in
            await reload()
        }
    }

    @MainActor
    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            results = try await service.search(query: query,
                                                muscle: muscle,
                                                equipment: equipment)
        } catch {
            // Keep previous results on error; future polish: surface a banner.
        }
    }
}

#Preview("ExercisesBrowser — Liquid Glass") {
    NavigationStack {
        ExercisesBrowserView()
            .environment(\.appTheme, LiquidGlassTheme())
            .environment(MockServiceContainer())
            .preferredColorScheme(.dark)
    }
}

#Preview("ExercisesBrowser — Health Cards") {
    NavigationStack {
        ExercisesBrowserView()
            .environment(\.appTheme, HealthCardsTheme())
            .environment(MockServiceContainer())
            .preferredColorScheme(.light)
    }
}
