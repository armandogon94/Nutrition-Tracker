//
//  WorkoutService.swift
//  Slice 7.2: active-workout session/set/PR service backed by SwiftData +
//  APIClient. Mirrors the optimistic-write contract established by
//  `MealService` (Slice 3):
//
//    - Every mutation writes the local SwiftData store FIRST, so a
//      mid-workout crash or an offline gym never loses a set.
//    - The backend round-trip runs afterwards and only flips `pendingSync`
//      on success. A network failure is swallowed for sets (input is
//      sacred) and surfaced-but-survived for session create/complete.
//
//  PR detection mirrors `backend/app/services/workout_service.py`
//  exactly: the comparison key is the estimated 1RM (the average of the
//  Brzycki and Epley formulas), NOT raw weight. This keeps the on-device
//  celebration consistent with what the backend records as `is_pr`, and
//  means a heavier-for-fewer-reps set can still be a PR.
//
//  Concurrency: @MainActor because every ModelContext call must run on the
//  actor that owns the context. The APIClient is an actor, so the awaited
//  network hops are explicit and the UI is never blocked on I/O.
//
//  Skills invoked:
//   - api-and-interface-design (protocol surface in ServiceProtocols.swift)
//   - everything-claude-code:swift-actor-persistence (SwiftData on MainActor)
//   - everything-claude-code:swift-concurrency-6-2 (MainActor + actor hops)
//   - test-driven-development (WorkoutServiceTests written RED-first)
//

import Foundation
import SwiftData

@MainActor
final class WorkoutService: WorkoutLoggingServiceProtocol {

    private let api: APIClient
    private let context: ModelContext

    init(api: APIClient, context: ModelContext) {
        self.api = api
        self.context = context
    }

    // MARK: - 1RM (pure, mirrors backend estimate_1rm)

    /// Average of the Brzycki and Epley one-rep-max estimates. Mirrors the
    /// backend so on-device PR detection agrees with the server's `is_pr`.
    /// Delegates to the shared `Formulas.estimate1RM` (review Flash F2) so the
    /// math lives in exactly one place; the signature is preserved for callers
    /// and tests.
    nonisolated static func estimate1RM(weightKg: Double, reps: Int) -> Double {
        Formulas.estimate1RM(weightKg: weightKg, reps: reps)
    }

    // MARK: - Start session

    func startSession(programName: String,
                      dayName: String,
                      programId: UUID?,
                      programDayId: UUID?,
                      userId: UUID) async throws -> WorkoutSession {
        let id = UUID()
        let startedAt = Date()

        // 1. Local-first: persist the session so the logger UI can open
        //    immediately and a crash before the POST resolves still leaves
        //    a recoverable session.
        let entity = WorkoutSessionEntity(
            id: id, userId: userId, startedAt: startedAt, completedAt: nil,
            programName: programName, dayName: dayName,
            pendingSync: true, lastSyncedAt: nil
        )
        context.insert(entity)
        try context.save()

        // 2. Backend POST. We send the local id as the client-supplied
        //    session id so the server persists the row under it — making
        //    logSet / completeSession (which address /sessions/{localId}/...)
        //    resolve to the SAME session end-to-end (Codex finding #1). The
        //    POST is idempotent server-side, so the offline-retry sweep can
        //    replay it. A failure leaves pendingSync=true.
        let body = SessionCreateRequest(
            id: id.uuidString,
            program_id: programId?.uuidString,
            program_day_id: programDayId?.uuidString,
            started_at: startedAt
        )
        do {
            let _: WorkoutSessionDTO = try await api.post("/api/v1/workouts/sessions", body: body)
            entity.pendingSync = false
            entity.lastSyncedAt = .now
            try context.save()
        } catch {
            // Swallow: an offline gym must still start a workout. The
            // offline-sync sweep (Slice 2.x) replays pending sessions.
        }

        return WorkoutSession(from: entity)
    }

    // MARK: - Log set

    func logSet(sessionId: UUID,
                exerciseId: UUID,
                exerciseName: String,
                setNumber: Int,
                weightKg: Double,
                reps: Int,
                userId: UUID) async throws -> LogSetOutcome {

        // 1. Resolve the parent session.
        let sessionRows = try context.fetch(FetchDescriptor<WorkoutSessionEntity>(
            predicate: #Predicate { $0.id == sessionId }
        ))
        guard let parent = sessionRows.first else {
            throw WorkoutServiceError.sessionNotFound
        }

        // 2. PR detection BEFORE persisting the set, so the set's isPR flag
        //    and the PR row are written together. Compare estimated-1RM
        //    against the existing PR for this (user, exercise).
        let newE1RM = Self.estimate1RM(weightKg: weightKg, reps: reps)
        let prRows = try context.fetch(FetchDescriptor<PersonalRecordEntity>(
            predicate: #Predicate { $0.userId == userId && $0.exerciseId == exerciseId }
        ))
        let existingPR = prRows.first

        var isPR = false
        var prResult: PersonalRecord?
        if newE1RM > 0 {
            let priorE1RM = existingPR.map { Self.estimate1RM(weightKg: $0.weightKg, reps: $0.reps) } ?? 0
            if existingPR == nil || newE1RM > priorE1RM {
                isPR = true
                if let existingPR {
                    existingPR.weightKg = weightKg
                    existingPR.reps = reps
                    existingPR.achievedAt = Date()
                    existingPR.lastSyncedAt = nil
                    prResult = PersonalRecord(from: existingPR)
                } else {
                    let pr = PersonalRecordEntity(
                        id: UUID(), userId: userId, exerciseId: exerciseId,
                        exerciseName: exerciseName, weightKg: weightKg, reps: reps,
                        achievedAt: Date(), lastSyncedAt: nil
                    )
                    context.insert(pr)
                    prResult = PersonalRecord(from: pr)
                }
            }
        }

        // 3. Persist the set locally (pendingSync=true). Crash-safety: the
        //    set is durable the instant the user taps "Set complete".
        let setEntity = WorkoutSetEntity(
            id: UUID(), exerciseId: exerciseId, setNumber: setNumber,
            weightKg: weightKg, reps: reps, isPR: isPR, pendingSync: true
        )
        setEntity.session = parent
        parent.sets.append(setEntity)
        try context.save()

        // 4. Fire the backend POST. We TRUST the local PR decision for the
        //    UI; the server independently recomputes is_pr. A failure is
        //    swallowed — losing a logged set is worse than a stale flag.
        let body = SetCreateRequest(
            exercise_id: exerciseId.uuidString,
            set_number: setNumber,
            reps: reps,
            weight_kg: weightKg,
            rpe: nil
        )
        do {
            let _: WorkoutSetDTO = try await api.post(
                "/api/v1/workouts/sessions/\(sessionId.uuidString)/sets", body: body
            )
            setEntity.pendingSync = false
            try context.save()
        } catch {
            // Leave pendingSync=true for the offline-retry sweep.
        }

        return LogSetOutcome(set: WorkoutSet(from: setEntity), newPR: prResult)
    }

    // MARK: - Complete session

    func completeSession(sessionId: UUID) async throws -> WorkoutSession {
        let rows = try context.fetch(FetchDescriptor<WorkoutSessionEntity>(
            predicate: #Predicate { $0.id == sessionId }
        ))
        guard let entity = rows.first else {
            throw WorkoutServiceError.sessionNotFound
        }

        // Local-first: stamp completion so the summary screen + HealthKit
        // write have a finished session even if the PATCH fails.
        entity.completedAt = Date()
        entity.pendingSync = true
        try context.save()

        let body = SessionCompleteRequest(notes: nil)
        do {
            let _: WorkoutSessionDTO = try await api.patch(
                "/api/v1/workouts/sessions/\(sessionId.uuidString)/complete", body: body
            )
            entity.pendingSync = false
            entity.lastSyncedAt = .now
            try context.save()
        } catch {
            // Swallow; the offline sweep replays the completion.
        }

        return WorkoutSession(from: entity)
    }

    // MARK: - WorkoutServiceProtocol (reads)

    /// The most recent session with no `completedAt`. Used on relaunch to
    /// resume an interrupted workout.
    func currentSession() async throws -> WorkoutSession? {
        let rows = try context.fetch(FetchDescriptor<WorkoutSessionEntity>(
            predicate: #Predicate { $0.completedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        ))
        return rows.first.map(WorkoutSession.init(from:))
    }

    func completedSessions(in interval: DateInterval) async throws -> [WorkoutSession] {
        let start = interval.start
        let end = interval.end
        let rows = try context.fetch(FetchDescriptor<WorkoutSessionEntity>(
            predicate: #Predicate { session in
                session.completedAt != nil &&
                session.startedAt >= start &&
                session.startedAt <= end
            },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        ))
        return rows.map(WorkoutSession.init(from:))
    }

    func personalRecords() async throws -> [PersonalRecord] {
        let rows = try context.fetch(FetchDescriptor<PersonalRecordEntity>(
            sortBy: [SortDescriptor(\.achievedAt, order: .reverse)]
        ))
        return rows.map(PersonalRecord.init(from:))
    }
}

// MARK: - Errors

enum WorkoutServiceError: Error, Sendable, Equatable {
    /// Logging a set / completing referenced a session id with no local row.
    case sessionNotFound
}

// MARK: - Entity -> Domain mappers (Slice 7)
//
// Workout-domain readbacks live here (not in Core/Persistence/Mappers.swift,
// which Slice 3 owns) to keep slice ownership clean. They follow the same
// `<Struct>(from: <Entity>)` convention documented in Mappers.swift: read a
// SwiftData row into a Sendable struct safe to hand to SwiftUI.

extension WorkoutSet {
    init(from entity: WorkoutSetEntity) {
        self.init(
            id: entity.id,
            exerciseId: entity.exerciseId,
            setNumber: entity.setNumber,
            weightKg: entity.weightKg,
            reps: entity.reps,
            isPR: entity.isPR
        )
    }
}

extension WorkoutSession {
    init(from entity: WorkoutSessionEntity) {
        self.init(
            id: entity.id,
            startedAt: entity.startedAt,
            completedAt: entity.completedAt,
            programName: entity.programName,
            dayName: entity.dayName,
            sets: entity.sets
                .sorted { $0.setNumber < $1.setNumber }
                .map(WorkoutSet.init(from:))
        )
    }
}

extension PersonalRecord {
    init(from entity: PersonalRecordEntity) {
        self.init(
            id: entity.id,
            exerciseId: entity.exerciseId,
            exerciseName: entity.exerciseName,
            weightKg: entity.weightKg,
            reps: entity.reps,
            achievedAt: entity.achievedAt
        )
    }
}
