//
//  SessionDetailView.swift
//  Slice 8.3: detail of a single completed workout. Sets are grouped by
//  exercise; each group shows a sets table and an inline weight-progression
//  sparkline of that exercise across all the user's past sessions (pulled
//  on demand from `HistoryService.exerciseProgression`).
//

import SwiftUI
import Charts

struct SessionDetailView: View {
    @Environment(\.appTheme) private var theme

    let session: WorkoutSession
    let exerciseNames: [UUID: String]

    var body: some View {
        ZStack {
            ThemedBackdrop()
            ScrollView {
                VStack(spacing: 14) {
                    headerCard
                    ForEach(groupedExercises, id: \.exerciseId) { group in
                        ExerciseSetsCard(
                            exerciseId: group.exerciseId,
                            name: exerciseNames[group.exerciseId] ?? String(localized: "history.exercise.unknown"),
                            sets: group.sets
                        )
                    }
                    Spacer(minLength: 40)
                }
                .padding(16)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("\(session.programName) · \(session.dayName)")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headerCard: some View {
        HStack(spacing: 12) {
            metric(value: dateLabel, labelKey: "history.session.date")
            metric(value: durationLabel, labelKey: "history.session.duration")
            metric(value: "\(Int(session.totalVolume))", labelKey: "history.stat.volume")
        }
        .padding(16)
        .themedCard()
    }

    private func metric(value: String, labelKey: LocalizedStringKey) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(theme.font.bodyMedium)
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(labelKey)
                .font(theme.font.caption)
                .foregroundStyle(theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var dateLabel: String {
        session.startedAt.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "es_419")))
    }

    private var durationLabel: String {
        guard let m = session.durationMinutes else { return "—" }
        return "\(m) min"
    }

    /// Sets grouped by exercise, preserving first-seen order.
    private var groupedExercises: [(exerciseId: UUID, sets: [WorkoutSet])] {
        var order: [UUID] = []
        var byExercise: [UUID: [WorkoutSet]] = [:]
        for set in session.sets.sorted(by: { $0.setNumber < $1.setNumber }) {
            if byExercise[set.exerciseId] == nil { order.append(set.exerciseId) }
            byExercise[set.exerciseId, default: []].append(set)
        }
        return order.map { ($0, byExercise[$0] ?? []) }
    }
}

// MARK: - Per-exercise card

private struct ExerciseSetsCard: View {
    @Environment(\.appTheme) private var theme
    @Environment(MockServiceContainer.self) private var services

    let exerciseId: UUID
    let name: String
    let sets: [WorkoutSet]

    @State private var progression: [ProgressionPoint] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(name)
                    .font(theme.font.titleCompact)
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                if sets.contains(where: \.isPR) {
                    Label("history.pr.badge", systemImage: "trophy.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(theme.positive)
                        .accessibilityLabel(Text("history.pr.badge"))
                }
            }

            // Sets table
            VStack(spacing: 6) {
                ForEach(sets) { set in
                    HStack {
                        Text("\(set.setNumber)")
                            .font(theme.font.caption)
                            .foregroundStyle(theme.textTertiary)
                            .frame(width: 24, alignment: .leading)
                        Text(weightLabel(set.weightKg))
                            .font(theme.font.bodyMedium)
                            .foregroundStyle(theme.textPrimary)
                        Text("× \(set.reps)")
                            .font(theme.font.body)
                            .foregroundStyle(theme.textSecondary)
                        Spacer()
                        if set.isPR {
                            Image(systemName: "trophy.fill")
                                .font(.caption2)
                                .foregroundStyle(theme.positive)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(setAccessibility(set))
                }
            }

            if progression.count >= 2 {
                progressionSparkline
            }
        }
        .padding(16)
        .themedCard()
        .task(id: exerciseId) {
            progression = (try? await services.history.exerciseProgression(exerciseId: exerciseId)) ?? []
        }
    }

    private var progressionSparkline: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("history.progression.title")
                .font(theme.font.captionMedium).tracking(1.0)
                .foregroundStyle(theme.textTertiary)
            Chart(progression) { point in
                LineMark(
                    x: .value(String(localized: "history.progression.axis.date"), point.date),
                    y: .value(String(localized: "history.progression.axis.oneRM"), point.estimated1RM)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(theme.accent)
                PointMark(
                    x: .value(String(localized: "history.progression.axis.date"), point.date),
                    y: .value(String(localized: "history.progression.axis.oneRM"), point.estimated1RM)
                )
                .foregroundStyle(theme.accent)
                .symbolSize(20)
            }
            .frame(height: 90)
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisValueLabel().foregroundStyle(theme.textTertiary)
                }
            }
            .accessibilityLabel(Text("history.progression.axisLabel \(name)"))
            .accessibilityValue(Text("history.progression.value \(Int(progression.last?.estimated1RM ?? 0))"))
        }
        .padding(.top, 4)
    }

    private func weightLabel(_ kg: Double) -> String {
        kg == 0 ? String(localized: "history.weight.bodyweight") : WorkoutCSVExporter.formatWeight(kg) + " kg"
    }

    private func setAccessibility(_ set: WorkoutSet) -> Text {
        let weight = set.weightKg == 0
            ? Text("history.weight.bodyweight")
            : Text("\(WorkoutCSVExporter.formatWeight(set.weightKg)) kg")
        let base = Text("history.set.number \(set.setNumber)") + Text(", ") + weight + Text(", \(set.reps) ") + Text("history.session.repsSuffix")
        return set.isPR ? base + Text(", ") + Text("history.pr.badge") : base
    }
}
