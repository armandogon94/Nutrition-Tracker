//
//  ProgramsListView.swift
//  Slice 0.5 mock — list of preset programs.
//

import SwiftUI

struct ProgramsListView: View {
    @Environment(\.appTheme) private var theme
    @Environment(MockServiceContainer.self) private var services
    @State private var programs: [WorkoutProgram] = []

    var body: some View {
        ZStack {
            ThemedBackdrop()
            ScrollView {
                VStack(spacing: 14) {
                    ForEach(programs) { program in
                        NavigationLink {
                            ProgramDetailView(program: program)
                        } label: {
                            programCard(program)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 60)
                }
                .padding(16)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Programas")
        .task { programs = (try? await services.programs.allPrograms()) ?? [] }
    }

    private func programCard(_ program: WorkoutProgram) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(program.name)
                    .font(theme.font.titleCompact)
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                difficultyPill(program.difficulty)
            }
            Text(program.summary)
                .font(theme.font.body)
                .foregroundStyle(theme.textSecondary)
                .lineLimit(2)
            HStack(spacing: 14) {
                Label("\(program.daysPerWeek) días/sem", systemImage: "calendar")
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(theme.textTertiary)
            }
            .font(theme.font.caption)
            .foregroundStyle(theme.textTertiary)
        }
        .padding(16)
        .themedCard()
    }

    private func difficultyPill(_ d: Difficulty) -> some View {
        let color: Color = {
            switch d {
            case .beginner: theme.positive
            case .intermediate: theme.accent
            case .advanced: theme.negative
            }
        }()
        return Text(d.label)
            .font(theme.font.captionMedium)
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.18), in: Capsule())
    }
}

struct ProgramDetailView: View {
    @Environment(\.appTheme) private var theme
    let program: WorkoutProgram

    var body: some View {
        ZStack {
            ThemedBackdrop()
            ScrollView {
                VStack(spacing: 14) {
                    summaryCard
                    if program.days.isEmpty {
                        comingSoonCard
                    } else {
                        ForEach(program.days) { day in
                            dayCard(day)
                        }
                    }
                    Spacer(minLength: 60)
                }
                .padding(16)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(program.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(program.summary)
                .font(theme.font.body)
                .foregroundStyle(theme.textPrimary)
            HStack(spacing: 18) {
                Label("\(program.daysPerWeek) días/sem", systemImage: "calendar")
                Label(program.difficulty.label, systemImage: "flame.fill")
            }
            .font(theme.font.caption)
            .foregroundStyle(theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .themedCard()
    }

    private func dayCard(_ day: WorkoutProgramDay) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(day.dayName)
                    .font(theme.font.titleCompact)
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                NavigationLink {
                    SessionView(programDayName: day.dayName, exercises: day.exercises)
                } label: {
                    Text("Empezar")
                        .font(theme.font.captionMedium)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(theme.accent, in: Capsule())
                }
            }
            VStack(spacing: 8) {
                ForEach(day.exercises) { spec in
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

    private var comingSoonCard: some View {
        Text("Detalles disponibles en Slice 6")
            .font(theme.font.body)
            .foregroundStyle(theme.textTertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)
            .themedInnerCard()
    }
}
