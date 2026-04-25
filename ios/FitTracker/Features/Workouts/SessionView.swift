//
//  SessionView.swift
//  Slice 0.5 mock — set logger + visual rest timer (counts but no real
//  background-survival; that lands in Slice 7 with ActivityKit).
//

import SwiftUI

struct SessionView: View {
    @Environment(\.appTheme) private var theme
    let programDayName: String
    let exercises: [WorkoutProgramExerciseSpec]

    @State private var currentExerciseIndex = 0
    @State private var weight: Double = 60
    @State private var reps: Int = 8
    @State private var loggedSets: [(weight: Double, reps: Int)] = []
    @State private var showRestTimer = false

    private var currentExercise: WorkoutProgramExerciseSpec? {
        exercises.indices.contains(currentExerciseIndex) ? exercises[currentExerciseIndex] : nil
    }

    var body: some View {
        ZStack {
            ThemedBackdrop()
            ScrollView {
                VStack(spacing: 14) {
                    if let ex = currentExercise {
                        exerciseHeader(ex)
                        setLogger(ex)
                        loggedSetsCard
                        nextExerciseButton
                    } else {
                        Text("Sesión completa")
                            .font(theme.font.title)
                            .foregroundStyle(theme.textPrimary)
                    }
                    Spacer(minLength: 60)
                }
                .padding(16)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(programDayName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showRestTimer) {
            RestTimerView(seconds: currentExercise?.restSeconds ?? 90)
                .presentationDetents([.medium])
        }
    }

    private func exerciseHeader(_ ex: WorkoutProgramExerciseSpec) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("EJERCICIO \(currentExerciseIndex + 1) / \(exercises.count)")
                .font(theme.font.captionMedium).tracking(1.4)
                .foregroundStyle(theme.textTertiary)
            Text(ex.exerciseName)
                .font(theme.font.title)
                .foregroundStyle(theme.textPrimary)
            Text("\(ex.sets) sets · \(ex.repsLow)-\(ex.repsHigh) reps · \(ex.restSeconds)s descanso")
                .font(theme.font.caption)
                .foregroundStyle(theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .themedCard()
    }

    private func setLogger(_ ex: WorkoutProgramExerciseSpec) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 16) {
                stepperField(label: "Peso (kg)", value: $weight, step: 2.5)
                stepperField(label: "Reps", intValue: $reps, step: 1)
            }
            Button {
                loggedSets.append((weight, reps))
                showRestTimer = true
            } label: {
                Text("Set completo")
                    .font(theme.font.bodyMedium)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(theme.accent, in: Capsule())
            }
        }
        .padding(16)
        .themedCard()
    }

    private func stepperField(label: String, value: Binding<Double>, step: Double) -> some View {
        VStack(spacing: 4) {
            Text(label).font(theme.font.caption).foregroundStyle(theme.textTertiary)
            HStack {
                Button { value.wrappedValue = max(0, value.wrappedValue - step) } label: {
                    Image(systemName: "minus.circle.fill").font(.system(size: 28))
                }
                .foregroundStyle(theme.accent)
                Text("\(value.wrappedValue, specifier: "%.1f")")
                    .font(theme.font.title)
                    .foregroundStyle(theme.textPrimary)
                    .frame(minWidth: 60)
                    .contentTransition(.numericText())
                Button { value.wrappedValue += step } label: {
                    Image(systemName: "plus.circle.fill").font(.system(size: 28))
                }
                .foregroundStyle(theme.accent)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func stepperField(label: String, intValue: Binding<Int>, step: Int) -> some View {
        VStack(spacing: 4) {
            Text(label).font(theme.font.caption).foregroundStyle(theme.textTertiary)
            HStack {
                Button { intValue.wrappedValue = max(0, intValue.wrappedValue - step) } label: {
                    Image(systemName: "minus.circle.fill").font(.system(size: 28))
                }
                .foregroundStyle(theme.accent)
                Text("\(intValue.wrappedValue)")
                    .font(theme.font.title)
                    .foregroundStyle(theme.textPrimary)
                    .frame(minWidth: 60)
                    .contentTransition(.numericText())
                Button { intValue.wrappedValue += step } label: {
                    Image(systemName: "plus.circle.fill").font(.system(size: 28))
                }
                .foregroundStyle(theme.accent)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var loggedSetsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SETS REGISTRADOS")
                .font(theme.font.captionMedium).tracking(1.4)
                .foregroundStyle(theme.textTertiary)
            if loggedSets.isEmpty {
                Text("Aún ninguno")
                    .font(theme.font.body)
                    .foregroundStyle(theme.textTertiary)
            } else {
                ForEach(Array(loggedSets.enumerated()), id: \.offset) { idx, s in
                    HStack {
                        Text("Set \(idx + 1)").foregroundStyle(theme.textSecondary)
                        Spacer()
                        Text("\(s.weight, specifier: "%.1f") kg × \(s.reps)")
                            .font(theme.font.bodyMedium)
                            .foregroundStyle(theme.textPrimary)
                    }
                    .font(theme.font.body)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .themedCard()
    }

    private var nextExerciseButton: some View {
        Button {
            currentExerciseIndex += 1
            loggedSets = []
        } label: {
            Text("Siguiente ejercicio")
                .font(theme.font.bodyMedium)
                .foregroundStyle(theme.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    Capsule().stroke(theme.accent, lineWidth: 1)
                )
        }
    }
}

struct RestTimerView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    let seconds: Int

    @State private var remaining: Int
    @State private var timerTask: Task<Void, Never>?

    init(seconds: Int) {
        self.seconds = seconds
        self._remaining = State(initialValue: seconds)
    }

    private var progress: Double {
        seconds == 0 ? 0 : 1.0 - (Double(remaining) / Double(seconds))
    }

    var body: some View {
        ZStack {
            ThemedBackdrop()
            VStack(spacing: 30) {
                Text("Descanso")
                    .font(theme.font.titleCompact)
                    .foregroundStyle(theme.textTertiary)
                    .tracking(1.4)
                ZStack {
                    Circle()
                        .stroke(theme.accent.opacity(0.2), lineWidth: 14)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(theme.accent, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(remaining)")
                        .font(.system(size: 80, weight: .semibold, design: .rounded))
                        .foregroundStyle(theme.textPrimary)
                        .contentTransition(.numericText())
                }
                .frame(width: 220, height: 220)
                HStack(spacing: 16) {
                    Button("Saltar") { dismiss() }
                        .foregroundStyle(theme.negative)
                    Button("+30s") { remaining += 30 }
                        .foregroundStyle(theme.accent)
                }
                .font(theme.font.bodyMedium)
            }
            .padding(40)
        }
        .onAppear {
            timerTask = Task {
                while remaining > 0 {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    if Task.isCancelled { break }
                    await MainActor.run { remaining -= 1 }
                }
                await MainActor.run { dismiss() }
            }
        }
        .onDisappear { timerTask?.cancel() }
    }
}
