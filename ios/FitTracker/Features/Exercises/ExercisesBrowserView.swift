//
//  ExercisesBrowserView.swift
//  Slice 0.5 mock — searchable exercise list with muscle/equipment chips.
//

import SwiftUI

struct ExercisesBrowserView: View {
    @Environment(\.appTheme) private var theme
    @Environment(MockServiceContainer.self) private var services

    @State private var query = ""
    @State private var muscle: MuscleGroup?
    @State private var equipment: Equipment?
    @State private var results: [Exercise] = MockData.exercises

    var body: some View {
        ZStack {
            ThemedBackdrop()
            VStack(spacing: 0) {
                filtersBar
                List(results) { ex in
                    NavigationLink {
                        ExerciseDetailView(exercise: ex)
                    } label: {
                        exerciseRow(ex)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .searchable(text: $query, prompt: "Buscar ejercicio")
        .navigationTitle("Ejercicios")
        .onChange(of: query) { _, _ in updateResults() }
    }

    private var filtersBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(label: "Músculo", selected: muscle?.label) {
                    muscle = nextMuscle()
                    updateResults()
                }
                chip(label: "Equipo", selected: equipment?.label) {
                    equipment = nextEquipment()
                    updateResults()
                }
                if muscle != nil || equipment != nil {
                    Button {
                        muscle = nil; equipment = nil; updateResults()
                    } label: {
                        Label("Limpiar", systemImage: "xmark.circle.fill")
                            .font(theme.font.caption)
                            .foregroundStyle(theme.negative)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 8)
    }

    private func chip(label: String, selected: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(selected ?? label)
                    .font(theme.font.captionMedium)
                Image(systemName: "chevron.down").font(.system(size: 10))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(selected == nil ? theme.surfaceSecondary : theme.accent.opacity(0.2))
            )
            .foregroundStyle(selected == nil ? theme.textSecondary : theme.accent)
        }
    }

    private func exerciseRow(_ ex: Exercise) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(theme.accent.opacity(0.18))
                Image(systemName: "dumbbell.fill")
                    .foregroundStyle(theme.accent)
            }
            .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(ex.name)
                    .font(theme.font.bodyMedium)
                    .foregroundStyle(theme.textPrimary)
                Text("\(ex.primaryMuscle.label) · \(ex.equipment.label)")
                    .font(theme.font.caption)
                    .foregroundStyle(theme.textSecondary)
            }
        }
        .padding(10)
        .themedInnerCard()
    }

    private func updateResults() {
        Task {
            results = (try? await services.exercises.search(query: query, muscle: muscle, equipment: equipment)) ?? []
        }
    }

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
}

struct ExerciseDetailView: View {
    @Environment(\.appTheme) private var theme
    let exercise: Exercise

    var body: some View {
        ZStack {
            ThemedBackdrop()
            ScrollView {
                VStack(spacing: 14) {
                    videoPlaceholder
                    metaCard
                    Spacer(minLength: 60)
                }
                .padding(16)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var videoPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.black)
            Image(systemName: "play.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(height: 220)
    }

    private var metaCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            row("Músculo principal", value: exercise.primaryMuscle.label)
            if !exercise.secondaryMuscles.isEmpty {
                row("Secundarios", value: exercise.secondaryMuscles.map(\.label).joined(separator: ", "))
            }
            row("Equipo", value: exercise.equipment.label)
            row("Dificultad", value: exercise.difficulty.label)
        }
        .padding(16)
        .themedCard()
    }

    private func row(_ label: String, value: String) -> some View {
        HStack {
            Text(label).font(theme.font.body).foregroundStyle(theme.textSecondary)
            Spacer()
            Text(value).font(theme.font.bodyMedium).foregroundStyle(theme.textPrimary)
        }
    }
}
