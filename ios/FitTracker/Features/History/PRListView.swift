//
//  PRListView.swift
//  Slice 8.5: sortable list of personal records. Each row shows the
//  exercise, the PR weight × reps, estimated 1RM, and the date achieved.
//  A segmented toggle re-sorts by weight / date / name (logic lives in the
//  unit-tested `PRSort`).
//

import SwiftUI

struct PRListView: View {
    @Environment(\.appTheme) private var theme
    let prs: [ExercisePR]

    @State private var sort: PRSort = .byWeight

    private var sorted: [ExercisePR] { sort.apply(prs) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("history.pr.title")
                    .font(theme.font.captionMedium).tracking(1.4)
                    .foregroundStyle(theme.textTertiary)
                Spacer()
            }

            if prs.isEmpty {
                emptyState
            } else {
                Picker("history.pr.sort", selection: $sort) {
                    ForEach(PRSort.allCases, id: \.self) { s in
                        Text(LocalizedStringKey(s.labelKey)).tag(s)
                    }
                }
                .pickerStyle(.segmented)

                ForEach(sorted) { pr in
                    row(pr)
                    if pr.id != sorted.last?.id {
                        Divider().opacity(0.18)
                    }
                }
            }
        }
        .padding(16)
        .themedCard()
    }

    private func row(_ pr: ExercisePR) -> some View {
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
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(WorkoutCSVExporter.formatWeight(pr.weightKg)) kg × \(pr.reps)")
                    .font(theme.font.titleCompact)
                    .foregroundStyle(theme.textPrimary)
                Text("1RM ~\(Int(pr.estimated1RM)) kg")
                    .font(theme.font.caption)
                    .foregroundStyle(theme.textTertiary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibility(pr))
    }

    private func accessibility(_ pr: ExercisePR) -> Text {
        Text(pr.exerciseName)
            + Text(": \(WorkoutCSVExporter.formatWeight(pr.weightKg)) ")
            + Text("history.unit.kg")
            + Text(" × \(pr.reps) ")
            + Text("history.session.repsSuffix")
            + Text(", 1RM \(Int(pr.estimated1RM)) ")
            + Text("history.unit.kg")
    }

    private var emptyState: some View {
        Text("history.pr.empty")
            .font(theme.font.body)
            .foregroundStyle(theme.textTertiary)
            .frame(maxWidth: .infinity, minHeight: 80)
    }

    private func dateLabel(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "es_419")))
    }
}
