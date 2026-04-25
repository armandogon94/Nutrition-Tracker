//
//  HistoryView.swift
//  Slice 0.5 mock — calendar of recent sessions, volume chart, PR list.
//

import SwiftUI
import Charts

struct HistoryView: View {
    @Environment(\.appTheme) private var theme
    @Environment(MockServiceContainer.self) private var services
    @State private var sessions: [WorkoutSession] = []
    @State private var prs: [PersonalRecord] = []

    var body: some View {
        ZStack {
            ThemedBackdrop()
            ScrollView {
                VStack(spacing: 14) {
                    summaryRow
                    VolumeChartView(sessions: sessions)
                    PRListView(prs: prs)
                    Spacer(minLength: 60)
                }
                .padding(16)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Progreso")
        .task {
            let interval = DateInterval(start: Date(timeIntervalSinceNow: -86400 * 60), end: Date())
            sessions = (try? await services.workouts.completedSessions(in: interval)) ?? []
            prs = (try? await services.workouts.personalRecords()) ?? []
        }
    }

    private var summaryRow: some View {
        HStack(spacing: 12) {
            statTile(value: "\(sessions.count)", label: "Sesiones", color: theme.accent)
            statTile(value: "\(Int(totalVolume / 1000))k", label: "Volumen kg", color: theme.accentSecondary)
            statTile(value: "\(prs.count)", label: "PRs", color: theme.positive)
        }
    }

    private var totalVolume: Double { sessions.reduce(0) { $0 + $1.totalVolume } }

    private func statTile(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(theme.font.heroNumeral)
                .foregroundStyle(theme.textPrimary)
                .minimumScaleFactor(0.5)
            Text(label)
                .font(theme.font.caption)
                .foregroundStyle(theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct VolumeChartView: View {
    @Environment(\.appTheme) private var theme
    let sessions: [WorkoutSession]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("VOLUMEN POR SESIÓN")
                .font(theme.font.captionMedium).tracking(1.4)
                .foregroundStyle(theme.textTertiary)
            if sessions.isEmpty {
                Text("Sin datos aún")
                    .font(theme.font.body).foregroundStyle(theme.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                Chart {
                    ForEach(sessions) { session in
                        BarMark(
                            x: .value("Día", session.startedAt, unit: .day),
                            y: .value("Volumen", session.totalVolume)
                        )
                        .foregroundStyle(theme.accent.gradient)
                    }
                }
                .frame(height: 180)
                .chartYAxis {
                    AxisMarks { _ in
                        AxisGridLine().foregroundStyle(theme.textTertiary.opacity(0.2))
                        AxisValueLabel().foregroundStyle(theme.textTertiary)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 4)) { _ in
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                            .foregroundStyle(theme.textTertiary)
                    }
                }
            }
        }
        .padding(16)
        .themedCard()
    }
}

struct PRListView: View {
    @Environment(\.appTheme) private var theme
    let prs: [PersonalRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PRs PERSONALES")
                .font(theme.font.captionMedium).tracking(1.4)
                .foregroundStyle(theme.textTertiary)
            ForEach(prs) { pr in
                HStack(spacing: 12) {
                    Image(systemName: "trophy.fill")
                        .foregroundStyle(theme.positive)
                        .frame(width: 32, height: 32)
                        .background(theme.positive.opacity(0.18), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pr.exerciseName)
                            .font(theme.font.bodyMedium)
                            .foregroundStyle(theme.textPrimary)
                        Text(dateLabel(pr.achievedAt))
                            .font(theme.font.caption)
                            .foregroundStyle(theme.textTertiary)
                    }
                    Spacer()
                    Text("\(pr.weightKg, specifier: "%.0f") × \(pr.reps)")
                        .font(theme.font.titleCompact)
                        .foregroundStyle(theme.textPrimary)
                }
                if pr.id != prs.last?.id {
                    Divider().opacity(0.18)
                }
            }
        }
        .padding(16)
        .themedCard()
    }

    private func dateLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy"
        f.locale = Locale(identifier: "es_419")
        return f.string(from: date)
    }
}
