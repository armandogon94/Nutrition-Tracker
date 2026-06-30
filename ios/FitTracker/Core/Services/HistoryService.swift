//
//  HistoryService.swift
//  Slice 8.1: on-device aggregation for the History + Analytics screens.
//
//  Why local-only: the workout sessions/sets the user logged in Slice 7 are
//  already cached in SwiftData. Charts re-aggregate on every scroll/filter
//  change, so hitting the backend each time would be wasteful and offline-
//  hostile. We run one bounded SwiftData fetch per query and fold it into
//  immutable value structs the chart views read directly (per the Slice 8
//  perf plan: "chart reads from immutable struct").
//
//  PR detection MIRRORS the backend `app/services/workout_service.py`:
//    estimated 1RM = average of Brzycki and Epley, the "best" set per
//    exercise is the one with the highest estimated 1RM, ties broken by
//    recency. Keeping these in lock-step means the on-device PR list and a
//    future server-computed list agree.
//
//  Week bucketing uses an ISO-8601 UTC calendar, matching
//  `DailyNutritionEntity.makeKey` and the backend's calendar-day semantics
//  so a session logged at 23:30 local lands in the same week the backend
//  would assign it.
//
//  Skills invoked:
//   - api-and-interface-design (service surface)
//   - everything-claude-code:swift-actor-persistence (SwiftData reads)
//   - performance-optimization (one fetch per query, struct fold)
//   - test-driven-development
//

import Foundation
import SwiftData

// MARK: - Aggregation value types

/// Total training volume for one ISO week. `weekStart` is the UTC start of
/// that week's Monday — a stable bucket key the chart plots on its X axis.
struct WeeklyVolumePoint: Identifiable, Hashable, Sendable {
    var weekStart: Date
    var totalVolume: Double
    var totalSets: Int
    var id: Date { weekStart }
}

/// Total volume attributed to one muscle group over the analysed window.
/// `muscle` is the exercise's PRIMARY muscle (mirrors backend grouping).
struct MuscleVolumePoint: Identifiable, Hashable, Sendable {
    var muscle: MuscleGroup
    var totalVolume: Double
    var totalSets: Int
    var id: MuscleGroup { muscle }
}

/// One personal record: the best (by estimated 1RM) set ever logged for an
/// exercise. Mirrors `PersonalRecordEntity` but is computed from sets so it
/// stays correct even if the stored PR rows are stale.
struct ExercisePR: Identifiable, Hashable, Sendable {
    var exerciseId: UUID
    var exerciseName: String
    var weightKg: Double
    var reps: Int
    var estimated1RM: Double
    var achievedAt: Date
    var id: UUID { exerciseId }
}

/// One point on an exercise's strength-progression sparkline: the best set
/// of a single session.
struct ProgressionPoint: Identifiable, Hashable, Sendable {
    var date: Date
    var estimated1RM: Double
    var topWeightKg: Double
    var reps: Int
    var id: Date { date }
}

// MARK: - Service

final class HistoryService: HistoryServiceProtocol, @unchecked Sendable {

    private let container: ModelContainer
    /// Resolves the current user's id at query time. A closure (rather than a
    /// captured value) so `production()` can build the service at launch —
    /// before login — and have every query scope to whoever is authenticated
    /// when it actually runs. Mirrors `NutritionService(userId:)`. Returns
    /// nil when no user is signed in, in which case queries yield empty.
    ///
    /// Not `@Sendable`: it's only ever invoked from this service's `@MainActor`
    /// methods (so it reads `AuthService.currentUser` on the main actor), and
    /// the class opts out of Sendable checking via `@unchecked`. This matches
    /// `NutritionService(userId:)`, whose closure is likewise non-Sendable.
    private let userIdProvider: () -> UUID?

    /// Convenience for a fixed user (tests, and any caller that already holds
    /// the id). Wraps the constant in the resolver.
    @MainActor
    convenience init(container: ModelContainer, userId: UUID) {
        self.init(container: container, userId: { userId })
    }

    @MainActor
    init(container: ModelContainer, userId: @escaping () -> UUID?) {
        self.container = container
        self.userIdProvider = userId
    }

    // MARK: - Sessions in a date range

    /// Completed sessions whose `startedAt` falls inside `interval`, newest
    /// first. In-progress sessions (no `completedAt`) are excluded — history
    /// only shows finished workouts.
    @MainActor
    func sessions(in interval: DateInterval) async throws -> [WorkoutSession] {
        let rows = try fetchCompletedSessions(in: interval)
        return rows.map(Self.mapSession).sorted { $0.startedAt > $1.startedAt }
    }

    // MARK: - Volume by week

    /// Last `weeks` ISO weeks (oldest first), each a contiguous bucket so the
    /// bar chart has no gaps. Empty weeks are zero-filled. Volume is
    /// `sum(weight × reps)` over every set in sessions started that week.
    @MainActor
    func volumeByWeek(weeks: Int) async throws -> [WeeklyVolumePoint] {
        let count = max(weeks, 1)
        let thisWeek = Self.weekStart(for: Date())
        // Build contiguous, zero-filled buckets oldest → newest.
        var buckets: [Date: (volume: Double, sets: Int)] = [:]
        var order: [Date] = []
        for offset in stride(from: count - 1, through: 0, by: -1) {
            guard let ws = Self.calendar.date(byAdding: .weekOfYear,
                                              value: -offset, to: thisWeek) else { continue }
            buckets[ws] = (0, 0)
            order.append(ws)
        }
        guard let earliest = order.first else { return [] }
        let interval = DateInterval(start: earliest, end: Date())

        for session in try fetchCompletedSessions(in: interval) {
            let ws = Self.weekStart(for: session.startedAt)
            guard buckets[ws] != nil else { continue }
            for set in session.sets {
                buckets[ws]?.volume += Self.volume(of: set)
                buckets[ws]?.sets += 1
            }
        }
        return order.map { ws in
            let b = buckets[ws] ?? (0, 0)
            return WeeklyVolumePoint(weekStart: ws, totalVolume: b.volume, totalSets: b.sets)
        }
    }

    // MARK: - Volume by muscle

    /// Volume grouped by each exercise's PRIMARY muscle over the last
    /// `weeks` weeks, sorted by volume descending (biggest contributor
    /// first — matches the backend ordering).
    @MainActor
    func volumeByMuscle(weeks: Int) async throws -> [MuscleVolumePoint] {
        let count = max(weeks, 1)
        let start = Self.calendar.date(byAdding: .weekOfYear, value: -(count - 1),
                                       to: Self.weekStart(for: Date())) ?? Date.distantPast
        let interval = DateInterval(start: start, end: Date())

        let muscleByExercise = try exerciseMuscleLookup()
        var totals: [MuscleGroup: (volume: Double, sets: Int)] = [:]

        for session in try fetchCompletedSessions(in: interval) {
            for set in session.sets {
                let muscle = muscleByExercise[set.exerciseId] ?? .core
                var entry = totals[muscle] ?? (0, 0)
                entry.volume += Self.volume(of: set)
                entry.sets += 1
                totals[muscle] = entry
            }
        }
        return totals
            .map { MuscleVolumePoint(muscle: $0.key, totalVolume: $0.value.volume,
                                     totalSets: $0.value.sets) }
            .sorted { lhs, rhs in
                if lhs.totalVolume == rhs.totalVolume { return lhs.muscle.rawValue < rhs.muscle.rawValue }
                return lhs.totalVolume > rhs.totalVolume
            }
    }

    // MARK: - Personal records

    /// One PR per exercise = the set with the highest estimated 1RM ever
    /// logged. Sorted by estimated 1RM descending. Computed from sets so it
    /// reflects the freshest data (rather than trusting stored PR rows).
    @MainActor
    func prs() async throws -> [ExercisePR] {
        guard let userId = userIdProvider() else { return [] }
        let ctx = ModelContext(container)
        // All of the user's completed-session sets, with their session date.
        let sessions = try ctx.fetch(FetchDescriptor<WorkoutSessionEntity>(
            predicate: Self.completedPredicate(userId: userId)
        ))
        let names = try exerciseNameLookup(ctx)

        var best: [UUID: ExercisePR] = [:]
        for session in sessions {
            for set in session.sets where set.weightKg > 0 {
                let e1rm = Self.estimate1RM(weightKg: set.weightKg, reps: set.reps)
                let candidate = ExercisePR(
                    exerciseId: set.exerciseId,
                    exerciseName: names[set.exerciseId] ?? "—",
                    weightKg: set.weightKg, reps: set.reps,
                    estimated1RM: e1rm, achievedAt: session.startedAt
                )
                if let existing = best[set.exerciseId] {
                    // Higher 1RM wins; tie → more recent.
                    if e1rm > existing.estimated1RM ||
                        (e1rm == existing.estimated1RM && session.startedAt > existing.achievedAt) {
                        best[set.exerciseId] = candidate
                    }
                } else {
                    best[set.exerciseId] = candidate
                }
            }
        }
        return best.values.sorted { $0.estimated1RM > $1.estimated1RM }
    }

    // MARK: - Exercise progression

    /// Strength progression for one exercise: the best set of each session
    /// (by estimated 1RM), oldest session first. Drives the sparkline in
    /// the session/exercise detail.
    @MainActor
    func exerciseProgression(exerciseId: UUID) async throws -> [ProgressionPoint] {
        guard let userId = userIdProvider() else { return [] }
        let ctx = ModelContext(container)
        let sessions = try ctx.fetch(FetchDescriptor<WorkoutSessionEntity>(
            predicate: Self.completedPredicate(userId: userId)
        ))
        var points: [ProgressionPoint] = []
        for session in sessions {
            let relevant = session.sets.filter { $0.exerciseId == exerciseId && $0.weightKg > 0 }
            guard !relevant.isEmpty else { continue }
            let bestSet = relevant.max {
                Self.estimate1RM(weightKg: $0.weightKg, reps: $0.reps)
                    < Self.estimate1RM(weightKg: $1.weightKg, reps: $1.reps)
            }!
            points.append(ProgressionPoint(
                date: session.startedAt,
                estimated1RM: Self.estimate1RM(weightKg: bestSet.weightKg, reps: bestSet.reps),
                topWeightKg: bestSet.weightKg,
                reps: bestSet.reps
            ))
        }
        return points.sorted { $0.date < $1.date }
    }

    // MARK: - 1RM (mirror of backend workout_service.estimate_1rm)

    /// Average of Brzycki and Epley formulas. Delegates to the shared
    /// `Formulas.estimate1RM` (review Flash F2) so the on-device PR math lives
    /// in exactly one place and stays in lock-step with the backend; the
    /// signature is preserved for callers and tests.
    static func estimate1RM(weightKg: Double, reps: Int) -> Double {
        Formulas.estimate1RM(weightKg: weightKg, reps: reps)
    }

    // MARK: - Week math

    /// ISO-8601 UTC calendar — stable across device timezones, matching
    /// `DailyNutritionEntity.makeKey` and the backend's day semantics.
    static let calendar: Calendar = {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    /// Start (Monday 00:00 UTC) of the ISO week containing `date`.
    static func weekStart(for date: Date) -> Date {
        let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: comps) ?? calendar.startOfDay(for: date)
    }

    // MARK: - Private fetch helpers

    private static func volume(of set: WorkoutSetEntity) -> Double {
        // weight 0 (bodyweight) contributes 0 volume but still counts as a set.
        set.weightKg * Double(set.reps)
    }

    /// `#Predicate` for the current user's completed sessions. Factored out
    /// so every query shares the same definition of "history".
    private static func completedPredicate(userId: UUID) -> Predicate<WorkoutSessionEntity> {
        #Predicate<WorkoutSessionEntity> { session in
            session.userId == userId && session.completedAt != nil
        }
    }

    @MainActor
    private func fetchCompletedSessions(in interval: DateInterval) throws -> [WorkoutSessionEntity] {
        guard let uid = userIdProvider() else { return [] }
        let ctx = ModelContext(container)
        let start = interval.start
        let end = interval.end
        var descriptor = FetchDescriptor<WorkoutSessionEntity>(
            predicate: #Predicate { session in
                session.userId == uid
                    && session.completedAt != nil
                    && session.startedAt >= start
                    && session.startedAt <= end
            },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.relationshipKeyPathsForPrefetching = [\.sets]
        return try ctx.fetch(descriptor)
    }

    /// Map exerciseId → primary muscle group from the cached exercise catalog.
    @MainActor
    private func exerciseMuscleLookup() throws -> [UUID: MuscleGroup] {
        let ctx = ModelContext(container)
        let rows = try ctx.fetch(FetchDescriptor<ExerciseEntity>())
        var map: [UUID: MuscleGroup] = [:]
        for row in rows {
            map[row.id] = MuscleGroup(rawValue: row.primaryMuscle.lowercased()) ?? .core
        }
        return map
    }

    /// Map exerciseId → display name from the cached exercise catalog.
    /// Public surface (protocol) so views label sessions/sets/CSV from the
    /// real SwiftData catalog instead of `MockData`.
    @MainActor
    func exerciseNameLookup() async throws -> [UUID: String] {
        try exerciseNameLookup(ModelContext(container))
    }

    /// Map exerciseId → display name from the cached exercise catalog.
    @MainActor
    private func exerciseNameLookup(_ ctx: ModelContext) throws -> [UUID: String] {
        let rows = try ctx.fetch(FetchDescriptor<ExerciseEntity>())
        var map: [UUID: String] = [:]
        for row in rows { map[row.id] = row.name }
        return map
    }

    // MARK: - Mapping

    static func mapSession(_ entity: WorkoutSessionEntity) -> WorkoutSession {
        WorkoutSession(
            id: entity.id,
            startedAt: entity.startedAt,
            completedAt: entity.completedAt,
            programName: entity.programName,
            dayName: entity.dayName,
            sets: entity.sets
                .sorted { $0.setNumber < $1.setNumber }
                .map { WorkoutSet(id: $0.id, exerciseId: $0.exerciseId,
                                  setNumber: $0.setNumber, weightKg: $0.weightKg,
                                  reps: $0.reps, isPR: $0.isPR) }
        )
    }
}
