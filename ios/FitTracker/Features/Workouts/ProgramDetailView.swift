//
//  ProgramDetailView.swift
//  Slice 6.3: detail of a workout program. Lists each day with the
//  exercise prescription. The "Empezar" CTA is stubbed for Slice 7 —
//  it shows a toast instead of pushing into SessionView.
//

import SwiftUI

struct ProgramDetailView: View {
    @Environment(\.appTheme) private var theme
    @Environment(MockServiceContainer.self) private var services

    let program: WorkoutProgram
    var injectedService: (any ProgramsServiceProtocol)?

    /// Resolves the programs service: explicit override first, otherwise the
    /// container's shared-client `ProgramsService` (mirroring ProgramsListView).
    /// Reading the container here is what lets `loadDays()` hydrate days in
    /// normal production navigation — previously `injectedService` was nil in
    /// production, so the detail screen fell back to the list DTO's empty
    /// `days` and showed "no days" (codex-review-4 P1).
    private var service: any ProgramsServiceProtocol {
        injectedService ?? services.programs
    }

    /// Hydrated days from the detail endpoint. The list endpoint returns
    /// programs without nested days, so we re-fetch on appear if empty.
    @State private var days: [WorkoutProgramDay] = []
    @State private var isLoading = false
    @State private var showStartToast = false
    /// Slice 7 wiring: non-nil pushes the active-workout logger for a day.
    @State private var activeConfig: SessionConfig?

    var body: some View {
        ZStack {
            ThemedBackdrop()
            ScrollView {
                LazyVStack(spacing: 14) {
                    summaryCard
                    if isLoading && days.isEmpty {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(theme.accent)
                            .padding(.vertical, 30)
                    } else if days.isEmpty {
                        noDaysCard
                    } else {
                        ForEach(days, id: \.id) { day in
                            DayCard(day: day, onStart: { start(day) })
                        }
                    }
                    Spacer(minLength: 60)
                }
                .padding(16)
            }
            .scrollContentBackground(.hidden)

            if showStartToast {
                VStack {
                    Spacer()
                    StartToast()
                        .padding(.bottom, 30)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showStartToast)
        .navigationTitle(program.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadDays() }
        .navigationDestination(item: $activeConfig) { config in
            SessionView(config: config)
        }
    }

    /// Builds a `SessionConfig` for the tapped day and pushes `SessionView`.
    /// Falls back to the existing toast when there's no signed-in user.
    private func start(_ day: WorkoutProgramDay) {
        guard let userId = services.auth.currentUser?.id else {
            showStartToast = true
            Task {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                showStartToast = false
            }
            return
        }
        activeConfig = SessionConfig(
            programName: program.name,
            dayName: day.dayName,
            programId: program.id,
            programDayId: day.id,
            exercises: day.exercises,
            userId: userId
        )
    }

    // MARK: - Subviews

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !program.summary.isEmpty {
                Text(program.summary)
                    .font(theme.font.body)
                    .foregroundStyle(theme.textPrimary)
            }
            HStack(spacing: 18) {
                Label {
                    Text(String(localized: "programs.daysPerWeek")
                        .replacingOccurrences(of: "%lld", with: "\(program.daysPerWeek)"))
                } icon: {
                    Image(systemName: "calendar")
                }
                Label(program.difficulty.label, systemImage: "flame.fill")
            }
            .font(theme.font.caption)
            .foregroundStyle(theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .themedCard()
    }

    private var noDaysCard: some View {
        Text(String(localized: "programs.noDays"))
            .font(theme.font.body)
            .foregroundStyle(theme.textTertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)
            .themedInnerCard()
    }

    // MARK: - Loading

    private func loadDays() async {
        // If the program already arrived with days populated (e.g. from a
        // detail-only navigation source), trust it.
        if !program.days.isEmpty {
            days = program.days
            return
        }
        // Otherwise hydrate via the resolved service. The list endpoint maps
        // `days: []`, so without this fetch the detail screen would be empty
        // and the user could never start the workout (codex-review-4 P1).
        isLoading = true
        defer { isLoading = false }
        do {
            if let detail = try await service.program(id: program.id) {
                days = detail.days
            }
        } catch {
            // Leave days empty — UI shows "no days" placeholder.
        }
    }
}

// MARK: - DayCard

private struct DayCard: View {
    @Environment(\.appTheme) private var theme
    let day: WorkoutProgramDay
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(day.dayName)
                    .font(theme.font.titleCompact)
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                Button(action: onStart) {
                    Text(String(localized: "programs.startWorkout"))
                        .font(theme.font.captionMedium)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(theme.accent, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            VStack(spacing: 8) {
                ForEach(day.exercises, id: \.id) { spec in
                    HStack {
                        Text(spec.exerciseName)
                            .font(theme.font.body)
                            .foregroundStyle(theme.textSecondary)
                        Spacer()
                        Text("\(spec.sets) × \(spec.repsLow)-\(spec.repsHigh)")
                            .font(theme.font.caption)
                            .foregroundStyle(theme.textTertiary)
                    }
                    if spec.id != day.exercises.last?.id {
                        Divider().opacity(0.18)
                    }
                }
            }
        }
        .padding(16)
        .themedCard()
    }
}

// MARK: - StartToast

private struct StartToast: View {
    @Environment(\.appTheme) private var theme

    var body: some View {
        Text(String(localized: "programs.startWorkoutToast"))
            .font(theme.font.bodyMedium)
            .foregroundStyle(theme.textPrimary)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(theme.surfaceSecondary, in: Capsule())
            .overlay {
                Capsule().stroke(theme.accent.opacity(0.4), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
    }
}

#Preview("ProgramDetail — Liquid Glass") {
    NavigationStack {
        ProgramDetailView(program: MockData.programs[0])
            .environment(\.appTheme, LiquidGlassTheme())
            .environment(MockServiceContainer())
            .preferredColorScheme(.dark)
    }
}

#Preview("ProgramDetail — Health Cards") {
    NavigationStack {
        ProgramDetailView(program: MockData.programs[0])
            .environment(\.appTheme, HealthCardsTheme())
            .environment(MockServiceContainer())
            .preferredColorScheme(.light)
    }
}
