//
//  HistoryServiceTests.swift
//  Slice 8.1: date-range aggregation queries over SwiftData for the
//  History + Analytics experience. All aggregation is on-device (no
//  network) so charts can recompute cheaply. PR detection mirrors the
//  backend `workout_service.py` (1RM = avg of Brzycki + Epley).
//

import Foundation
import SwiftData
import Testing
@testable import FitTracker

@Suite("HistoryService", .serialized)
@MainActor
struct HistoryServiceTests {

    // Stable hex UUIDs (project convention: UUID(uuidString:) is hex-only).
    private let userId = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
    private let benchId = UUID(uuidString: "00000000-0000-0000-0000-0000000B0001")!
    private let squatId = UUID(uuidString: "00000000-0000-0000-0000-0000000B0002")!

    /// Builds a service over a fresh in-memory store and returns the
    /// container so tests can seed entities directly.
    private func makeSUT() throws -> (HistoryService, ModelContainer) {
        let container = try PersistenceController.makeInMemory().container
        let sut = HistoryService(container: container, userId: userId)
        return (sut, container)
    }

    /// Inserts a completed session with the given sets at a fixed start date.
    @discardableResult
    private func seedSession(
        _ ctx: ModelContext,
        startedAt: Date,
        program: String = "PPL",
        day: String = "Push",
        sets: [(exerciseId: UUID, set: Int, weight: Double, reps: Int)]
    ) -> WorkoutSessionEntity {
        let session = WorkoutSessionEntity(
            id: UUID(), userId: userId, startedAt: startedAt,
            completedAt: startedAt.addingTimeInterval(60 * 60),
            programName: program, dayName: day
        )
        ctx.insert(session)
        for s in sets {
            let setEntity = WorkoutSetEntity(
                id: UUID(), exerciseId: s.exerciseId, setNumber: s.set,
                weightKg: s.weight, reps: s.reps
            )
            setEntity.session = session
            ctx.insert(setEntity)
        }
        return session
    }

    private func seedExercise(_ ctx: ModelContext, id: UUID, name: String, muscle: MuscleGroup) {
        ctx.insert(ExerciseEntity(
            id: id, name: name, primaryMuscle: muscle.rawValue,
            secondaryMusclesRaw: "", equipment: Equipment.barbell.rawValue,
            difficulty: Difficulty.intermediate.rawValue
        ))
    }

    // MARK: - sessions(in:)

    @Test("sessions(in:) returns only completed sessions inside the interval, newest first")
    func sessions_filtersByIntervalAndCompletion() async throws {
        let (sut, container) = try makeSUT()
        let ctx = ModelContext(container)
        let now = Date(timeIntervalSince1970: 1_700_000_000) // fixed

        // Inside interval
        seedSession(ctx, startedAt: now.addingTimeInterval(-86400 * 2),
                    sets: [(benchId, 1, 80, 8)])
        seedSession(ctx, startedAt: now.addingTimeInterval(-86400 * 5),
                    sets: [(benchId, 1, 82, 6)])
        // Outside interval (too old)
        seedSession(ctx, startedAt: now.addingTimeInterval(-86400 * 40),
                    sets: [(benchId, 1, 70, 8)])
        // In-progress (completedAt nil) inside interval — must be excluded
        let inProgress = WorkoutSessionEntity(
            id: UUID(), userId: userId, startedAt: now.addingTimeInterval(-3600),
            completedAt: nil, programName: "PPL", dayName: "Pull"
        )
        ctx.insert(inProgress)
        try ctx.save()

        let interval = DateInterval(start: now.addingTimeInterval(-86400 * 30), end: now)
        let sessions = try await sut.sessions(in: interval)

        #expect(sessions.count == 2)
        // Newest first
        #expect(sessions.first!.startedAt > sessions.last!.startedAt)
        #expect(sessions.allSatisfy { $0.completedAt != nil })
    }

    @Test("sessions(in:) scopes to the service's user only")
    func sessions_scopedToUser() async throws {
        let (sut, container) = try makeSUT()
        let ctx = ModelContext(container)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        seedSession(ctx, startedAt: now.addingTimeInterval(-86400),
                    sets: [(benchId, 1, 80, 8)])
        // Another user's session inside the interval
        let other = WorkoutSessionEntity(
            id: UUID(), userId: UUID(uuidString: "00000000-0000-0000-0000-0000000000F9")!,
            startedAt: now.addingTimeInterval(-86400), completedAt: now,
            programName: "PPL", dayName: "Push"
        )
        ctx.insert(other)
        try ctx.save()

        let interval = DateInterval(start: now.addingTimeInterval(-86400 * 7), end: now)
        let sessions = try await sut.sessions(in: interval)
        #expect(sessions.count == 1)
    }

    // MARK: - volumeByWeek

    @Test("volumeByWeek aggregates total volume across sessions within a week")
    func volumeByWeek_aggregatesAcrossSessions() async throws {
        let (sut, container) = try makeSUT()
        let ctx = ModelContext(container)

        // Anchor on the CURRENT ISO week so the sessions fall inside the
        // 12-week window. Monday + Wednesday land in the same bucket.
        let monday = HistoryService.weekStart(for: Date())
        let wednesday = HistoryService.calendar.date(byAdding: .day, value: 2, to: monday)!

        // Session A: 80*8 + 80*7 = 1200
        seedSession(ctx, startedAt: monday, sets: [(benchId, 1, 80, 8), (benchId, 2, 80, 7)])
        // Session B: 100*5 = 500
        seedSession(ctx, startedAt: wednesday, sets: [(squatId, 1, 100, 5)])
        try ctx.save()

        let points = try await sut.volumeByWeek(weeks: 12)
        // The two sessions share this week's bucket → 1700 total.
        let bucket = points.first { $0.weekStart == monday }
        #expect(bucket != nil)
        #expect(bucket?.totalVolume == 1700)
    }

    @Test("volumeByWeek returns exactly `weeks` contiguous buckets, oldest first, zero-filled")
    func volumeByWeek_contiguousZeroFilled() async throws {
        let (sut, container) = try makeSUT()
        let ctx = ModelContext(container)
        seedSession(ctx, startedAt: Date(), sets: [(benchId, 1, 50, 10)])
        try ctx.save()

        let points = try await sut.volumeByWeek(weeks: 12)
        #expect(points.count == 12)
        // Oldest first → strictly increasing week starts.
        for i in 1..<points.count {
            #expect(points[i].weekStart > points[i - 1].weekStart)
        }
        // Most recent bucket holds the seeded session.
        #expect(points.last!.totalVolume == 500)
    }

    // MARK: - volumeByMuscle

    @Test("volumeByMuscle groups by the exercise's PRIMARY muscle only")
    func volumeByMuscle_primaryOnly() async throws {
        let (sut, container) = try makeSUT()
        let ctx = ModelContext(container)
        seedExercise(ctx, id: benchId, name: "Bench Press", muscle: .chest)
        seedExercise(ctx, id: squatId, name: "Squat", muscle: .legs)

        // chest: 80*8 = 640 ; legs: 100*5 + 100*5 = 1000
        seedSession(ctx, startedAt: Date(), sets: [
            (benchId, 1, 80, 8),
            (squatId, 1, 100, 5),
            (squatId, 2, 100, 5)
        ])
        try ctx.save()

        let points = try await sut.volumeByMuscle(weeks: 12)
        let chest = points.first { $0.muscle == .chest }
        let legs = points.first { $0.muscle == .legs }
        #expect(chest?.totalVolume == 640)
        #expect(legs?.totalVolume == 1000)
        // Sorted descending by volume → legs before chest.
        #expect(points.first?.muscle == .legs)
    }

    @Test("volumeByMuscle treats bodyweight sets (weight 0) as zero volume but counts the set")
    func volumeByMuscle_bodyweightZeroVolume() async throws {
        let (sut, container) = try makeSUT()
        let ctx = ModelContext(container)
        seedExercise(ctx, id: benchId, name: "Push-up", muscle: .chest)
        seedSession(ctx, startedAt: Date(), sets: [(benchId, 1, 0, 20)])
        try ctx.save()

        let points = try await sut.volumeByMuscle(weeks: 12)
        let chest = points.first { $0.muscle == .chest }
        #expect(chest?.totalVolume == 0)
        #expect(chest?.totalSets == 1)
    }

    // MARK: - PRs

    @Test("prs() returns the latest max-1RM record per exercise")
    func prsByExercise_returnsLatestMaxPerExercise() async throws {
        let (sut, container) = try makeSUT()
        let ctx = ModelContext(container)
        seedExercise(ctx, id: benchId, name: "Bench Press", muscle: .chest)

        let early = Date(timeIntervalSince1970: 1_600_000_000)
        let late = Date(timeIntervalSince1970: 1_700_000_000)

        // Early heavier-by-1RM set: 100kg x 5 → e1RM ~112.6
        seedSession(ctx, startedAt: early, sets: [(benchId, 1, 100, 5)])
        // Later lighter set: 90kg x 5 → e1RM ~101.3 (NOT a PR over the earlier one)
        seedSession(ctx, startedAt: late, sets: [(benchId, 1, 90, 5)])
        try ctx.save()

        let prs = try await sut.prs()
        #expect(prs.count == 1)
        let pr = prs.first!
        #expect(pr.exerciseId == benchId)
        // The 100x5 set wins on estimated 1RM.
        #expect(pr.weightKg == 100)
        #expect(pr.reps == 5)
        #expect(pr.exerciseName == "Bench Press")
    }

    @Test("prs() picks the higher estimated-1RM even when raw weight is lower")
    func prs_usesEstimated1RMNotRawWeight() async throws {
        let (sut, container) = try makeSUT()
        let ctx = ModelContext(container)
        seedExercise(ctx, id: benchId, name: "Bench Press", muscle: .chest)

        // 100kg x 1 → e1RM 100. 95kg x 5 → e1RM ~106.8 → wins despite lower weight.
        seedSession(ctx, startedAt: Date(), sets: [
            (benchId, 1, 100, 1),
            (benchId, 2, 95, 5)
        ])
        try ctx.save()

        let prs = try await sut.prs()
        #expect(prs.count == 1)
        #expect(prs.first?.weightKg == 95)
        #expect(prs.first?.reps == 5)
    }

    @Test("estimate1RM matches backend: avg of Brzycki + Epley, 1 rep is identity")
    func estimate1RM_matchesBackend() {
        // reps == 1 → identity
        #expect(HistoryService.estimate1RM(weightKg: 100, reps: 1) == 100)
        // 100kg x 5: Brzycki = 100*36/32 = 112.5 ; Epley = 100*(1+5/30)=116.667
        // avg = 114.583 → rounded to 1 decimal = 114.6
        #expect(HistoryService.estimate1RM(weightKg: 100, reps: 5) == 114.6)
        // Non-positive → 0
        #expect(HistoryService.estimate1RM(weightKg: 0, reps: 5) == 0)
        #expect(HistoryService.estimate1RM(weightKg: 100, reps: 0) == 0)
    }

    // MARK: - exerciseProgression

    @Test("exerciseProgression returns one point per session with best 1RM, oldest first")
    func exerciseProgression_bestPerSession() async throws {
        let (sut, container) = try makeSUT()
        let ctx = ModelContext(container)
        seedExercise(ctx, id: benchId, name: "Bench Press", muscle: .chest)

        let d1 = Date(timeIntervalSince1970: 1_600_000_000)
        let d2 = Date(timeIntervalSince1970: 1_700_000_000)
        seedSession(ctx, startedAt: d1, sets: [(benchId, 1, 80, 8), (benchId, 2, 85, 5)])
        seedSession(ctx, startedAt: d2, sets: [(benchId, 1, 90, 5)])
        try ctx.save()

        let points = try await sut.exerciseProgression(exerciseId: benchId)
        #expect(points.count == 2)
        // Oldest first
        #expect(points.first!.date < points.last!.date)
        // First session has two sets; the point reports the one with the
        // highest estimated 1RM. 80x8 (≈100.3) beats 85x5 (≈97.4), so the
        // best set's weight is 80, not the heaviest weight on the bar.
        let oneRM80x8 = HistoryService.estimate1RM(weightKg: 80, reps: 8)
        let oneRM85x5 = HistoryService.estimate1RM(weightKg: 85, reps: 5)
        #expect(oneRM80x8 > oneRM85x5)
        #expect(points.first?.estimated1RM == oneRM80x8)
        #expect(points.first?.topWeightKg == 80)
        // Last session reflects progression to 90x5.
        #expect(points.last?.topWeightKg == 90)
    }
}
