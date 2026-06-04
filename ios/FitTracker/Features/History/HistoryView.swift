//
//  HistoryView.swift
//  Slice 8.2: the Progreso tab. A segmented control switches between three
//  sections — Calendario (month grid + selected-day sessions), Análisis
//  (volume trends + muscle distribution charts), and Records (sortable PRs).
//  A toolbar Export button hands a CSV of the visible history to the system
//  Share Sheet.
//
//  All data comes from `HistoryService` (protocol-injected via the service
//  container), which aggregates the local SwiftData store — no network on
//  this screen, so it stays responsive offline and on every re-render.
//

import SwiftUI

struct HistoryView: View {
    @Environment(\.appTheme) private var theme
    @Environment(MockServiceContainer.self) private var services

    @State private var section: HistorySection = .calendar
    @State private var sessions: [WorkoutSession] = []
    @State private var weeklyVolume: [WeeklyVolumePoint] = []
    @State private var muscleVolume: [MuscleVolumePoint] = []
    @State private var prs: [ExercisePR] = []
    @State private var exerciseNames: [UUID: String] = [:]
    @State private var isLoading = true
    @State private var exportURL: URL?

    /// How far back the screen looks. 52 weeks ≈ a year of history.
    private let lookbackWeeks = 52

    var body: some View {
        ZStack {
            ThemedBackdrop()
            content
        }
        .navigationTitle(Text("history.title"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                exportButton
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            Picker("history.section", selection: $section) {
                ForEach(HistorySection.allCases, id: \.self) { s in
                    Text(s.titleKey).tag(s)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)

            if isLoading && sessions.isEmpty {
                loadingState
            } else {
                ScrollView {
                    VStack(spacing: 14) {
                        summaryRow
                        switch section {
                        case .calendar:
                            HistoryCalendarView(sessions: sessions, exerciseNames: exerciseNames)
                        case .analytics:
                            VolumeTrendChartView(points: weeklyVolume)
                            MuscleDistributionChartView(points: muscleVolume)
                        case .records:
                            PRListView(prs: prs)
                        }
                        Spacer(minLength: 60)
                    }
                    .padding(16)
                }
                .scrollContentBackground(.hidden)
            }
        }
    }

    private var loadingState: some View {
        VStack {
            Spacer()
            ProgressView()
                .controlSize(.large)
                .tint(theme.accent)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel(Text("common.loading"))
    }

    // MARK: - Summary

    private var summaryRow: some View {
        HStack(spacing: 12) {
            statTile(value: "\(sessions.count)", labelKey: "history.stat.sessions", color: theme.accent)
            statTile(value: compactVolume, labelKey: "history.stat.volume", color: theme.accentSecondary)
            statTile(value: "\(prs.count)", labelKey: "history.stat.prs", color: theme.positive)
        }
    }

    private var totalVolume: Double { sessions.reduce(0) { $0 + $1.totalVolume } }

    /// "12.3k" style compact volume in kilograms.
    private var compactVolume: String {
        let v = totalVolume
        if v >= 1000 {
            return String(format: "%.1fk", v / 1000)
        }
        return String(Int(v))
    }

    private func statTile(value: String, labelKey: LocalizedStringKey, color: Color) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(theme.font.heroNumeral)
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(labelKey)
                .font(theme.font.caption)
                .foregroundStyle(theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Export

    @ViewBuilder
    private var exportButton: some View {
        if let url = exportURL, !sessions.isEmpty {
            ShareLink(item: url) {
                Label("history.export", systemImage: "square.and.arrow.up")
            }
        } else {
            // Disabled placeholder keeps the toolbar slot stable while data loads.
            Label("history.export", systemImage: "square.and.arrow.up")
                .labelStyle(.iconOnly)
                .foregroundStyle(theme.textTertiary)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Data loading

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        let interval = DateInterval(
            start: Date(timeIntervalSinceNow: -Double(lookbackWeeks) * 7 * 86_400),
            end: Date()
        )
        async let s = services.history.sessions(in: interval)
        async let wv = services.history.volumeByWeek(weeks: 12)
        async let mv = services.history.volumeByMuscle(weeks: lookbackWeeks)
        async let p = services.history.prs()

        sessions = (try? await s) ?? []
        weeklyVolume = (try? await wv) ?? []
        muscleVolume = (try? await mv) ?? []
        prs = (try? await p) ?? []

        // Resolve exercise names from the PR list + any exercise the sessions touch.
        var names: [UUID: String] = [:]
        for pr in prs { names[pr.exerciseId] = pr.exerciseName }
        for ex in MockData.exercises where names[ex.id] == nil { names[ex.id] = ex.name }
        exerciseNames = names

        // Pre-build the CSV so ShareLink has a ready file URL.
        exportURL = try? WorkoutCSVExporter.writeCSV(sessions: sessions, exerciseNames: names)
    }
}

/// The three sections of the Progreso tab.
enum HistorySection: String, CaseIterable, Hashable {
    case calendar
    case analytics
    case records

    var titleKey: LocalizedStringKey {
        switch self {
        case .calendar:  "history.section.calendar"
        case .analytics: "history.section.analytics"
        case .records:   "history.section.records"
        }
    }
}

#Preview("History — Liquid Glass") {
    NavigationStack { HistoryView() }
        .environment(\.appTheme, LiquidGlassTheme())
        .environment(MockServiceContainer())
        .preferredColorScheme(.dark)
}

#Preview("History — Health Cards") {
    NavigationStack { HistoryView() }
        .environment(\.appTheme, HealthCardsTheme())
        .environment(MockServiceContainer())
}
