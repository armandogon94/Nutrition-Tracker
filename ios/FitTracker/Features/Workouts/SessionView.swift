//
//  SessionView.swift
//  Slice 7.3 / 7.5 / 7.8: the live active-workout logger.
//
//  Flow: opened from a program day -> starts a WorkoutSession (backend +
//  SwiftData) -> the lifter logs sets (weight kg + reps) -> "Set complete"
//  persists the set, detects a PR, and starts the timestamp-based rest
//  timer (Live Activity + Dynamic Island on a real device) -> the lifter
//  advances through exercises -> "Finish" completes the session and writes
//  it to Apple Health.
//
//  Wiring note (Slice 6 ownership): ProgramDetailView's "Empezar" button is
//  owned by Slice 6 and currently shows a toast. This view is built to be
//  pushed from there with a single NavigationLink/navigationDestination —
//  see the slice report's "merge note". SessionView is otherwise fully
//  self-contained: it resolves its service from the injected value or the
//  environment container (mirroring ProgramsListView), so previews and the
//  eventual production wiring both work.
//
//  Skills: everything-claude-code:swiftui-patterns, ux-design:ios-hig-design,
//  everything-claude-code:liquid-glass-design, performance-optimization.
//

import SwiftUI
import SwiftData

// MARK: - Config

/// Everything SessionView needs to run a workout. Built by the caller
/// (ProgramDetailView, once wired) from the chosen program day.
struct SessionConfig: Hashable, Sendable {
    let programName: String
    let dayName: String
    let programId: UUID?
    let programDayId: UUID?
    let exercises: [WorkoutProgramExerciseSpec]
    let userId: UUID
}

// MARK: - View

struct SessionView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(MockServiceContainer.self) private var services

    let config: SessionConfig
    /// Optional service override for previews/tests. When nil (production), the
    /// view uses the container's `workouts` service — the real `WorkoutService`
    /// over the ONE shared refresh-aware `APIClient` — instead of building its
    /// own client that would bypass 401 → refresh → retry (codex-review-4 P1).
    var injectedService: (any WorkoutLoggingServiceProtocol)?

    @State private var model: SessionViewModel?
    @State private var restController = RestTimerController()
    @State private var showRestTimer = false
    @State private var showEndConfirm = false

    /// Resolves the logging service: explicit override first, otherwise the
    /// container's shared-client `WorkoutService`. The production `workouts`
    /// slot is a `WorkoutService` (conforms to `WorkoutLoggingServiceProtocol`);
    /// the `as?` only fails for a read-only mock with no override, where we fall
    /// back to a context-backed instance so previews still function.
    private var service: any WorkoutLoggingServiceProtocol {
        if let injectedService { return injectedService }
        if let logging = services.workouts as? any WorkoutLoggingServiceProtocol {
            return logging
        }
        return WorkoutService(
            api: APIClient(tokenProvider: KeychainTokenStore.shared),
            context: modelContext
        )
    }

    var body: some View {
        ZStack {
            ThemedBackdrop()
            if let model {
                logger(model)
            } else {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(theme.accent)
            }

            // PR celebration overlay.
            if let model, let pr = model.celebratingPR {
                PRCelebrationOverlay(record: pr) {
                    model.dismissCelebration()
                }
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model?.celebratingPR)
        .navigationTitle(config.dayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    showEndConfirm = true
                } label: {
                    Text(String(localized: "workout.endWorkout"))
                        .foregroundStyle(theme.negative)
                }
                .disabled(model == nil)
            }
        }
        .confirmationDialog(
            String(localized: "workout.endWorkout.confirm.title"),
            isPresented: $showEndConfirm,
            titleVisibility: .visible
        ) {
            Button(String(localized: "workout.endWorkout"), role: .destructive) {
                Task { await endWorkout() }
            }
            Button(String(localized: "common_cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "workout.endWorkout.confirm.message"))
        }
        .sheet(isPresented: $showRestTimer) {
            RestTimerView(
                controller: restController,
                onFinished: { showRestTimer = false },
                onSkip: { RestTimerActivity.shared.end() },
                onAddTime: {
                    // Keep the Live Activity end date in lockstep with +30s.
                    RestTimerActivity.shared.update(
                        startedAt: restController.startedAt,
                        duration: restController.duration
                    )
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .onDisappear { RestTimerActivity.shared.end() }
        }
        .task { await startIfNeeded() }
        .onChange(of: scenePhase) { _, newPhase in
            // Returning to the foreground: recompute the timer from its
            // timestamp and fire the (de-duplicated) completion if it
            // elapsed while we were away. No drift — nothing was counting.
            if newPhase == .active, restController.isRunning {
                restController.completeIfElapsed()
                if !restController.isRunning { showRestTimer = false }
            }
        }
    }

    // MARK: - Logger UI

    @ViewBuilder
    private func logger(_ model: SessionViewModel) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                if let ex = model.currentExercise {
                    exerciseHeader(model, ex)
                    setLogger(model, ex)
                    loggedSetsCard(model)
                    if model.hasNextExercise {
                        nextExerciseButton(model)
                    } else {
                        finishHintCard
                    }
                } else {
                    sessionCompleteCard
                }
                Spacer(minLength: 60)
            }
            .padding(16)
        }
        .scrollContentBackground(.hidden)
    }

    private func exerciseHeader(_ model: SessionViewModel, _ ex: WorkoutProgramExerciseSpec) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(localizedFormat("workout.exerciseProgress",
                                 model.currentExerciseIndex + 1, model.exercises.count))
                .font(theme.font.captionMedium).tracking(1.4)
                .foregroundStyle(theme.textTertiary)
            Text(ex.exerciseName)
                .font(theme.font.title)
                .foregroundStyle(theme.textPrimary)
            Text(localizedFormat("workout.setOfTarget", model.currentSetNumber, ex.sets)
                 + " · \(ex.repsLow)-\(ex.repsHigh) reps · \(ex.restSeconds)s")
                .font(theme.font.caption)
                .foregroundStyle(theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .themedCard()
    }

    private func setLogger(_ model: SessionViewModel, _ ex: WorkoutProgramExerciseSpec) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 16) {
                numericStepper(label: String(localized: "workout.weightKg"),
                               value: Binding(get: { model.weight }, set: { model.weight = $0 }),
                               step: 2.5, format: "%.1f")
                numericStepper(label: String(localized: "workout.reps"),
                               value: Binding(get: { Double(model.reps) }, set: { model.reps = Int($0) }),
                               step: 1, format: "%.0f")
            }
            Button {
                Task { await logCurrentSet(model, restSeconds: ex.restSeconds) }
            } label: {
                Text(String(localized: "workout.setComplete"))
                    .font(theme.font.bodyMedium)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(theme.accent, in: Capsule())
            }
            .disabled(model.isLogging)
        }
        .padding(16)
        .themedCard()
    }

    private func numericStepper(label: String, value: Binding<Double>, step: Double, format: String) -> some View {
        VStack(spacing: 4) {
            Text(label).font(theme.font.caption).foregroundStyle(theme.textTertiary)
            HStack {
                Button { value.wrappedValue = max(0, value.wrappedValue - step) } label: {
                    Image(systemName: "minus.circle.fill").font(.system(size: 28))
                }
                .foregroundStyle(theme.accent)
                .buttonRepeatBehavior(.enabled)

                Text(String(format: format, value.wrappedValue))
                    .font(theme.font.title)
                    .monospacedDigit()
                    .foregroundStyle(theme.textPrimary)
                    .frame(minWidth: 64)
                    .contentTransition(.numericText())

                Button { value.wrappedValue += step } label: {
                    Image(systemName: "plus.circle.fill").font(.system(size: 28))
                }
                .foregroundStyle(theme.accent)
                .buttonRepeatBehavior(.enabled)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func loggedSetsCard(_ model: SessionViewModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "workout.loggedSets"))
                .font(theme.font.captionMedium).tracking(1.4)
                .foregroundStyle(theme.textTertiary)
            if model.currentExerciseSets.isEmpty {
                Text(String(localized: "workout.noSetsYet"))
                    .font(theme.font.body)
                    .foregroundStyle(theme.textTertiary)
            } else {
                ForEach(Array(model.currentExerciseSets.enumerated()), id: \.element.id) { idx, s in
                    HStack {
                        Text(localizedFormat("workout.setLabel", idx + 1))
                            .foregroundStyle(theme.textSecondary)
                        if s.isPR {
                            Image(systemName: "trophy.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(theme.accent)
                        }
                        Spacer()
                        Text("\(s.weightKg, specifier: "%.1f") kg × \(s.reps)")
                            .font(theme.font.bodyMedium)
                            .monospacedDigit()
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

    private func nextExerciseButton(_ model: SessionViewModel) -> some View {
        Button {
            model.advanceExercise()
        } label: {
            Text(String(localized: "workout.nextExercise"))
                .font(theme.font.bodyMedium)
                .foregroundStyle(theme.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Capsule().stroke(theme.accent, lineWidth: 1))
        }
    }

    private var finishHintCard: some View {
        Text(String(localized: "workout.endWorkout.confirm.message"))
            .font(theme.font.caption)
            .foregroundStyle(theme.textTertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
    }

    private var sessionCompleteCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44))
                .foregroundStyle(theme.positive)
            Text(String(localized: "workout.sessionComplete"))
                .font(theme.font.title)
                .foregroundStyle(theme.textPrimary)
        }
        .padding(40)
    }

    // MARK: - Actions

    private func startIfNeeded() async {
        guard model == nil else { return }
        let service = self.service
        let vm = SessionViewModel(config: config)
        do {
            let session = try await service.startSession(
                programName: config.programName,
                dayName: config.dayName,
                programId: config.programId,
                programDayId: config.programDayId,
                userId: config.userId
            )
            vm.sessionId = session.id
        } catch {
            // Even if the (already offline-resilient) start throws, keep a
            // local id so the lifter can still log; the service persisted
            // the session locally regardless.
            vm.sessionId = vm.sessionId ?? UUID()
        }
        model = vm
    }

    private func logCurrentSet(_ model: SessionViewModel, restSeconds: Int) async {
        guard let ex = model.currentExercise, let sessionId = model.sessionId else { return }
        model.isLogging = true
        defer { model.isLogging = false }

        HapticsService.shared.medium()
        do {
            let outcome = try await service.logSet(
                sessionId: sessionId,
                exerciseId: ex.exerciseId,
                exerciseName: ex.exerciseName,
                setNumber: model.currentSetNumber,
                weightKg: model.weight,
                reps: model.reps,
                userId: config.userId
            )
            model.appendSet(outcome.set)

            if let pr = outcome.newPR {
                HapticsService.shared.success()
                model.celebrate(pr)
            }

            // Start the rest timer after every logged set. The lifter then
            // either does the next set, advances to the next exercise, or
            // taps Finish (all of which dismiss/cancel the timer). We don't
            // suppress it on the "last" set because lifters routinely add
            // extra sets, and resting before tapping Finish is harmless.
            startRest(restSeconds: restSeconds, exerciseName: ex.exerciseName)
        } catch {
            // logSet is offline-resilient; a thrown error here is unexpected
            // (e.g. session-not-found). Surface nothing destructive — the
            // lifter can retry the set.
        }
    }

    private func startRest(restSeconds: Int, exerciseName: String) {
        restController.start(duration: TimeInterval(restSeconds), exerciseName: exerciseName)
        RestTimerActivity.shared.start(
            exerciseName: exerciseName,
            startedAt: restController.startedAt,
            duration: restController.duration
        )
        showRestTimer = true
    }

    private func endWorkout() async {
        guard let model, let sessionId = model.sessionId else { dismiss(); return }
        let service = self.service
        restController.skip()
        RestTimerActivity.shared.end()
        NotificationService.shared.cancelRestComplete()
        do {
            let completed = try await service.completeSession(sessionId: sessionId)
            // Best-effort Apple Health write. Never blocks ending the workout.
            try? await HealthKitService.shared.writeWorkout(completed)
        } catch {
            // Completion is offline-resilient; ignore and leave the view.
        }
        dismiss()
    }

    // MARK: - Localization helpers

    /// `String(format:)` against a localized template, e.g. "EXERCISE %1$lld / %2$lld".
    private func localizedFormat(_ key: String.LocalizationValue, _ args: CVarArg...) -> String {
        String(format: String(localized: key), arguments: args)
    }
}

// MARK: - ViewModel

/// Holds the mutable logging state. `@Observable` so SwiftUI tracks the
/// per-field changes without a pile of `@State` in the view.
@Observable
@MainActor
final class SessionViewModel {
    let config: SessionConfig
    var sessionId: UUID?

    var currentExerciseIndex = 0
    var weight: Double = 60
    var reps: Int = 8
    var isLogging = false

    /// All logged sets, in order. Filtered per-exercise for the UI.
    private(set) var loggedSets: [WorkoutSet] = []
    /// The PR currently being celebrated (drives the overlay).
    private(set) var celebratingPR: PersonalRecord?

    init(config: SessionConfig) {
        self.config = config
    }

    var exercises: [WorkoutProgramExerciseSpec] { config.exercises }

    var currentExercise: WorkoutProgramExerciseSpec? {
        exercises.indices.contains(currentExerciseIndex) ? exercises[currentExerciseIndex] : nil
    }

    var hasNextExercise: Bool {
        currentExerciseIndex < exercises.count - 1
    }

    /// Sets logged so far for the current exercise.
    var currentExerciseSets: [WorkoutSet] {
        guard let ex = currentExercise else { return [] }
        return loggedSets.filter { $0.exerciseId == ex.exerciseId }
    }

    /// 1-based number of the set about to be logged for the current exercise.
    var currentSetNumber: Int {
        currentExerciseSets.count + 1
    }

    func appendSet(_ set: WorkoutSet) {
        loggedSets.append(set)
    }

    func advanceExercise() {
        guard hasNextExercise else { return }
        currentExerciseIndex += 1
    }

    func celebrate(_ pr: PersonalRecord) {
        celebratingPR = pr
    }

    func dismissCelebration() {
        celebratingPR = nil
    }
}

// MARK: - Previews

#Preview("Session — Liquid Glass") {
    NavigationStack {
        SessionView(
            config: SessionConfig(
                programName: "PPL",
                dayName: "Push",
                programId: MockData.programs.first?.id,
                programDayId: nil,
                exercises: MockData.programs.first?.days.first?.exercises ?? [],
                userId: MockData.user.id
            ),
            injectedService: PreviewWorkoutService()
        )
        .environment(\.appTheme, LiquidGlassTheme())
        .environment(MockServiceContainer())
        .preferredColorScheme(.dark)
    }
}

#Preview("Session — Health Cards") {
    NavigationStack {
        SessionView(
            config: SessionConfig(
                programName: "PPL",
                dayName: "Push",
                programId: MockData.programs.first?.id,
                programDayId: nil,
                exercises: MockData.programs.first?.days.first?.exercises ?? [],
                userId: MockData.user.id
            ),
            injectedService: PreviewWorkoutService()
        )
        .environment(\.appTheme, HealthCardsTheme())
        .environment(MockServiceContainer())
        .preferredColorScheme(.light)
    }
}

/// Lightweight in-memory logging service so previews don't need a backend.
/// Flags every 2nd set a "PR" so the celebration overlay is previewable.
@MainActor
private final class PreviewWorkoutService: WorkoutLoggingServiceProtocol {
    private var count = 0

    func startSession(programName: String, dayName: String, programId: UUID?,
                      programDayId: UUID?, userId: UUID) async throws -> WorkoutSession {
        WorkoutSession(id: UUID(), startedAt: .now, completedAt: nil,
                       programName: programName, dayName: dayName, sets: [])
    }
    func logSet(sessionId: UUID, exerciseId: UUID, exerciseName: String, setNumber: Int,
                weightKg: Double, reps: Int, userId: UUID) async throws -> LogSetOutcome {
        count += 1
        let set = WorkoutSet(id: UUID(), exerciseId: exerciseId, setNumber: setNumber,
                             weightKg: weightKg, reps: reps, isPR: count.isMultiple(of: 2))
        let pr = count.isMultiple(of: 2)
            ? PersonalRecord(id: UUID(), exerciseId: exerciseId, exerciseName: exerciseName,
                             weightKg: weightKg, reps: reps, achievedAt: .now)
            : nil
        return LogSetOutcome(set: set, newPR: pr)
    }
    func completeSession(sessionId: UUID) async throws -> WorkoutSession {
        WorkoutSession(id: sessionId, startedAt: .now.addingTimeInterval(-1800),
                       completedAt: .now, programName: "PPL", dayName: "Push", sets: [])
    }
    func currentSession() async throws -> WorkoutSession? { nil }
    func completedSessions(in interval: DateInterval) async throws -> [WorkoutSession] { [] }
    func personalRecords() async throws -> [PersonalRecord] { [] }
}
