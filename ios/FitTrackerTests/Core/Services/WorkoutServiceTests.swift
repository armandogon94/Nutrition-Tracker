//
//  WorkoutServiceTests.swift
//  Slice 7.2: backend-backed workout session/set/PR service over SwiftData.
//
//  Coverage:
//    - estimate1RM pure math mirrors backend (avg of Brzycki + Epley)
//    - startSession writes the local row and POSTs to the backend
//    - logSet detects a PR when estimated-1RM beats the prior record
//    - logSet does NOT flag a PR for a weaker set
//    - logSet writes the set to SwiftData even when the backend is offline
//    - completeSession stamps completedAt + derives duration
//
//  All network is mocked via MockURLProtocol; SwiftData is an in-memory
//  container per test so cases never see each other's writes.
//

import Foundation
import SwiftData
import Testing
@testable import FitTracker

@Suite("WorkoutService", .serialized)
@MainActor
struct WorkoutServiceTests {

    init() { MockURLProtocol.reset() }

    // Stable ids reused across cases.
    private let userId = UUID(uuidString: "00000000-0000-0000-0000-000000C00001")!
    private let benchId = UUID(uuidString: "00000000-0000-0000-0000-0000000E0001")!
    private let programId = UUID(uuidString: "00000000-0000-0000-0000-00000000B001")!
    private let dayId = UUID(uuidString: "00000000-0000-0000-0000-00000000D001")!

    private func makeSUT() throws -> (WorkoutService, ModelContainer) {
        let session = MockURLProtocol.makeSession()
        let api = APIClient(baseURL: URL(string: "http://test.local")!,
                            tokenProvider: nil,
                            session: session)
        let container = try PersistenceController.makeInMemory().container
        let ctx = ModelContext(container)
        return (WorkoutService(api: api, context: ctx), container)
    }

    /// Builds an ExerciseDTO JSON fragment for embedding in set/PR responses.
    private func exerciseJSON(id: UUID, name: String) -> String {
        """
        {
          "id": "\(id.uuidString)",
          "name": "\(name)",
          "primary_muscle": "chest",
          "secondary_muscles": "shoulders,arms",
          "equipment": "barbell",
          "difficulty": "intermediate",
          "instructions": null,
          "video_url": null,
          "category": null
        }
        """
    }

    // MARK: - 1RM math

    @Test("estimate1RM mirrors backend: avg of Brzycki + Epley")
    func estimate1RM_matchesBackend() {
        // reps == 1 returns the weight unchanged.
        #expect(WorkoutService.estimate1RM(weightKg: 100, reps: 1) == 100)
        // reps <= 0 or weight <= 0 returns 0.
        #expect(WorkoutService.estimate1RM(weightKg: 100, reps: 0) == 0)
        #expect(WorkoutService.estimate1RM(weightKg: 0, reps: 5) == 0)

        // 100kg × 8 reps:
        //   Brzycki = 100 * 36/(37-8) = 124.137...
        //   Epley   = 100 * (1 + 8/30) = 126.666...
        //   avg     = 125.4 (rounded to 1 dp like backend)
        let e = WorkoutService.estimate1RM(weightKg: 100, reps: 8)
        #expect(abs(e - 125.4) < 0.05)
    }

    // MARK: - startSession

    @Test("startSession writes a local row and POSTs to the backend")
    func startSession_createsBackendAndLocal() async throws {
        let (sut, container) = try makeSUT()

        let serverSessionId = UUID()
        let json = """
        {
          "id": "\(serverSessionId.uuidString)",
          "user_id": "\(userId.uuidString)",
          "program_id": "\(programId.uuidString)",
          "program_day_id": "\(dayId.uuidString)",
          "started_at": "2026-06-04T10:00:00Z",
          "completed_at": null,
          "duration_minutes": null,
          "notes": null,
          "sets": []
        }
        """
        MockURLProtocol.handler = { req in
            #expect(req.url?.path.contains("/workouts/sessions") == true)
            #expect(req.httpMethod == "POST")
            let resp = HTTPURLResponse(url: req.url!, statusCode: 201,
                                       httpVersion: "1.1", headerFields: nil)!
            return (resp, Data(json.utf8))
        }

        let session = try await sut.startSession(
            programName: "PPL", dayName: "Push",
            programId: programId, programDayId: dayId, userId: userId
        )

        #expect(session.programName == "PPL")
        #expect(session.dayName == "Push")
        #expect(session.completedAt == nil)

        // A WorkoutSessionEntity must exist locally and be marked synced
        // after the successful POST.
        let ctx = ModelContext(container)
        let sid = session.id
        let rows = try ctx.fetch(FetchDescriptor<WorkoutSessionEntity>(
            predicate: #Predicate { $0.id == sid }
        ))
        #expect(rows.count == 1)
        #expect(rows.first?.pendingSync == false)
        #expect(rows.first?.userId == userId)
    }

    @Test("startSession keeps the local row pending when the backend is offline")
    func startSession_offlineLeavesPending() async throws {
        let (sut, container) = try makeSUT()
        MockURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }

        let session = try await sut.startSession(
            programName: "PPL", dayName: "Pull",
            programId: nil, programDayId: nil, userId: userId
        )

        let ctx = ModelContext(container)
        let sid = session.id
        let rows = try ctx.fetch(FetchDescriptor<WorkoutSessionEntity>(
            predicate: #Predicate { $0.id == sid }
        ))
        #expect(rows.count == 1)
        #expect(rows.first?.pendingSync == true, "offline session must survive locally for later sync")
    }

    // MARK: - logSet + PR detection

    @Test("logSet flags a PR and creates a record when there is no prior PR")
    func logSet_detectsPRWhenNoPriorRecord() async throws {
        let (sut, container) = try makeSUT()

        // Seed an active session locally so logSet has a parent.
        let sessionId = try seedActiveSession(container)

        let setId = UUID()
        let setJSON = """
        {
          "id": "\(setId.uuidString)",
          "exercise_id": "\(benchId.uuidString)",
          "exercise": \(exerciseJSON(id: benchId, name: "Press de banca")),
          "set_number": 1,
          "reps": 8,
          "weight_kg": 80.0,
          "rpe": null,
          "is_pr": true,
          "completed_at": "2026-06-04T10:05:00Z"
        }
        """
        MockURLProtocol.handler = { req in
            #expect(req.httpMethod == "POST")
            let resp = HTTPURLResponse(url: req.url!, statusCode: 201,
                                       httpVersion: "1.1", headerFields: nil)!
            return (resp, Data(setJSON.utf8))
        }

        let outcome = try await sut.logSet(
            sessionId: sessionId, exerciseId: benchId,
            exerciseName: "Press de banca", setNumber: 1,
            weightKg: 80, reps: 8, userId: userId
        )

        #expect(outcome.isPR, "first ever set for an exercise is always a PR")
        #expect(outcome.newPR?.exerciseName == "Press de banca")
        #expect(outcome.set.weightKg == 80)
        #expect(outcome.set.reps == 8)

        // The set + PR must be persisted locally.
        let ctx = ModelContext(container)
        let bench = benchId
        let prRows = try ctx.fetch(FetchDescriptor<PersonalRecordEntity>(
            predicate: #Predicate { $0.exerciseId == bench }
        ))
        #expect(prRows.count == 1)
        let setRows = try ctx.fetch(FetchDescriptor<WorkoutSetEntity>())
        #expect(setRows.contains { $0.isPR })
    }

    @Test("logSet flags a PR when estimated-1RM beats the prior record")
    func logSet_detectsPRWhenAboveMax() async throws {
        let (sut, container) = try makeSUT()
        let sessionId = try seedActiveSession(container)

        // Prior PR: 80kg × 8 -> est1RM ~100.3. New: 90kg × 8 -> ~112.9 > prior.
        let ctx = ModelContext(container)
        ctx.insert(PersonalRecordEntity(
            id: UUID(), userId: userId, exerciseId: benchId,
            exerciseName: "Press de banca",
            weightKg: 80, reps: 8, achievedAt: Date(timeIntervalSince1970: 1_700_000_000)
        ))
        try ctx.save()

        let setJSON = setResponseJSON(reps: 8, weight: 90, isPR: true)
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 201, httpVersion: "1.1", headerFields: nil)!
            return (resp, Data(setJSON.utf8))
        }

        let outcome = try await sut.logSet(
            sessionId: sessionId, exerciseId: benchId,
            exerciseName: "Press de banca", setNumber: 2,
            weightKg: 90, reps: 8, userId: userId
        )
        #expect(outcome.isPR)
        #expect(outcome.newPR?.weightKg == 90)

        // The existing PR row should now reflect the heavier lift.
        let ctx2 = ModelContext(container)
        let bench = benchId
        let prRows = try ctx2.fetch(FetchDescriptor<PersonalRecordEntity>(
            predicate: #Predicate { $0.exerciseId == bench }
        ))
        #expect(prRows.count == 1, "PR is updated in place, not duplicated")
        #expect(prRows.first?.weightKg == 90)
    }

    @Test("logSet does NOT flag a PR for a weaker set")
    func logSet_noPRWhenBelowMax() async throws {
        let (sut, container) = try makeSUT()
        let sessionId = try seedActiveSession(container)

        // Prior PR: 100kg × 5 -> est1RM ~112.9. New: 60kg × 8 -> ~75.2 < prior.
        let ctx = ModelContext(container)
        ctx.insert(PersonalRecordEntity(
            id: UUID(), userId: userId, exerciseId: benchId,
            exerciseName: "Press de banca",
            weightKg: 100, reps: 5, achievedAt: Date(timeIntervalSince1970: 1_700_000_000)
        ))
        try ctx.save()

        let setJSON = setResponseJSON(reps: 8, weight: 60, isPR: false)
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 201, httpVersion: "1.1", headerFields: nil)!
            return (resp, Data(setJSON.utf8))
        }

        let outcome = try await sut.logSet(
            sessionId: sessionId, exerciseId: benchId,
            exerciseName: "Press de banca", setNumber: 1,
            weightKg: 60, reps: 8, userId: userId
        )
        #expect(!outcome.isPR)
        #expect(outcome.newPR == nil)

        let ctx2 = ModelContext(container)
        let bench = benchId
        let prRows = try ctx2.fetch(FetchDescriptor<PersonalRecordEntity>(
            predicate: #Predicate { $0.exerciseId == bench }
        ))
        #expect(prRows.first?.weightKg == 100, "weaker set must not overwrite the PR")
    }

    @Test("logSet writes the set locally even when the backend is offline")
    func logSet_offlineStillPersistsSet() async throws {
        let (sut, container) = try makeSUT()
        let sessionId = try seedActiveSession(container)
        MockURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }

        // The local write + PR detection must succeed; the network failure
        // is swallowed so the lifter never loses a set mid-workout.
        let outcome = try await sut.logSet(
            sessionId: sessionId, exerciseId: benchId,
            exerciseName: "Press de banca", setNumber: 1,
            weightKg: 70, reps: 10, userId: userId
        )
        #expect(outcome.isPR, "local PR detection works without the network")

        let ctx = ModelContext(container)
        let setRows = try ctx.fetch(FetchDescriptor<WorkoutSetEntity>())
        #expect(setRows.count == 1)
        #expect(setRows.first?.pendingSync == true)
    }

    // MARK: - completeSession

    @Test("completeSession stamps completedAt and derives duration")
    func completeSession_writesDurationAndFlushes() async throws {
        let (sut, container) = try makeSUT()

        // Seed a session that started 30 minutes ago.
        let started = Date().addingTimeInterval(-1800)
        let ctx = ModelContext(container)
        let sessionId = UUID()
        ctx.insert(WorkoutSessionEntity(
            id: sessionId, userId: userId, startedAt: started, completedAt: nil,
            programName: "PPL", dayName: "Push", pendingSync: false, lastSyncedAt: .now
        ))
        try ctx.save()

        let completedJSON = """
        {
          "id": "\(sessionId.uuidString)",
          "user_id": "\(userId.uuidString)",
          "program_id": null,
          "program_day_id": null,
          "started_at": "\(ISO8601DateFormatter().string(from: started))",
          "completed_at": "\(ISO8601DateFormatter().string(from: Date()))",
          "duration_minutes": 30,
          "notes": null,
          "sets": []
        }
        """
        MockURLProtocol.handler = { req in
            #expect(req.httpMethod == "PATCH")
            #expect(req.url?.path.contains("/complete") == true)
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "1.1", headerFields: nil)!
            return (resp, Data(completedJSON.utf8))
        }

        let completed = try await sut.completeSession(sessionId: sessionId)
        #expect(completed.completedAt != nil)
        #expect(completed.durationMinutes == 30)

        let ctx2 = ModelContext(container)
        let rows = try ctx2.fetch(FetchDescriptor<WorkoutSessionEntity>(
            predicate: #Predicate { $0.id == sessionId }
        ))
        #expect(rows.first?.completedAt != nil)
        #expect(rows.first?.pendingSync == false)
    }

    @Test("currentSession returns the most recent incomplete local session")
    func currentSession_returnsActive() async throws {
        let (sut, container) = try makeSUT()
        let ctx = ModelContext(container)
        // One completed, one active.
        ctx.insert(WorkoutSessionEntity(
            id: UUID(), userId: userId,
            startedAt: Date().addingTimeInterval(-7200),
            completedAt: Date().addingTimeInterval(-5400),
            programName: "PPL", dayName: "Legs", pendingSync: false
        ))
        let activeId = UUID()
        ctx.insert(WorkoutSessionEntity(
            id: activeId, userId: userId,
            startedAt: Date().addingTimeInterval(-600),
            completedAt: nil,
            programName: "PPL", dayName: "Push", pendingSync: true
        ))
        try ctx.save()

        let current = try await sut.currentSession()
        #expect(current?.id == activeId)
        #expect(current?.completedAt == nil)
    }

    // MARK: - Helpers

    /// Inserts an active (incomplete) session locally and returns its id.
    private func seedActiveSession(_ container: ModelContainer) throws -> UUID {
        let ctx = ModelContext(container)
        let id = UUID()
        ctx.insert(WorkoutSessionEntity(
            id: id, userId: userId, startedAt: Date(), completedAt: nil,
            programName: "PPL", dayName: "Push", pendingSync: false, lastSyncedAt: .now
        ))
        try ctx.save()
        return id
    }

    private func setResponseJSON(reps: Int, weight: Double, isPR: Bool) -> String {
        """
        {
          "id": "\(UUID().uuidString)",
          "exercise_id": "\(benchId.uuidString)",
          "exercise": \(exerciseJSON(id: benchId, name: "Press de banca")),
          "set_number": 1,
          "reps": \(reps),
          "weight_kg": \(weight),
          "rpe": null,
          "is_pr": \(isPR),
          "completed_at": "2026-06-04T10:05:00Z"
        }
        """
    }
}
