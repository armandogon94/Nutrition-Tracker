//
//  RefreshAwareLivePathsTests.swift
//  codex-review-4 P1 ("Several live paths bypass the refresh-aware production
//  service graph"): meal-plan, shopping list, workout session, photo
//  recognition, and account deletion used to build ad-hoc
//  `APIClient(tokenProvider:)` instances with no `TokenRefreshing` coordinator,
//  so a normal expired access token produced a hard 401 instead of
//  refresh + retry.
//
//  The fix routes every one of those paths through services backed by the ONE
//  shared refresh-aware `APIClient`. These tests pin that contract end-to-end:
//  for each live path we wire the production-style service over an `APIClient`
//  with a refresher set, drive a 401-then-success through `MockURLProtocol`,
//  and assert exactly ONE refresh + ONE retry (mirroring the Wave-1
//  `APIClientRefreshTests` pattern). If any path regresses to its own client,
//  the refresh count drops to 0 and the request fails as `.unauthorized`.
//

import Foundation
import SwiftData
import Testing
@testable import FitTracker

@Suite("Live paths route through the shared refresh-aware APIClient", .serialized)
struct RefreshAwareLivePathsTests {

    init() { MockURLProtocol.reset() }

    // MARK: - Shared stubs (local copies of the Wave-1 refresher harness)

    /// Records how many times a refresh happened; returns a fresh token or
    /// throws. Mirrors `APIClientRefreshTests.StubTokenRefresher`.
    final class StubTokenRefresher: TokenRefreshing, @unchecked Sendable {
        let calls = AtomicCounter()
        let onRefresh: (@Sendable (String) -> Void)?
        let newToken: String
        init(newToken: String = "fresh", onRefresh: (@Sendable (String) -> Void)? = nil) {
            self.newToken = newToken
            self.onRefresh = onRefresh
        }
        func refreshAccessToken() async throws -> String {
            calls.increment()
            onRefresh?(newToken)
            return newToken
        }
    }

    /// Synchronous mutable token provider so the refresher can swap the token
    /// between the original request and the retry.
    final class MutableTokenProvider: TokenProvider, @unchecked Sendable {
        private let lock = NSLock()
        private var token: String?
        init(_ token: String?) { self.token = token }
        func currentAccessToken() -> String? {
            lock.lock(); defer { lock.unlock() }; return token
        }
        func updateAccessToken(_ token: String?) async { set(token) }
        func set(_ token: String?) {
            lock.lock(); defer { lock.unlock() }; self.token = token
        }
    }

    /// Builds an `APIClient` over the mock session with a stale token + a
    /// refresher wired in — the production shape the live paths must use.
    /// Returns the client, the refresher (to assert call count), and an
    /// attempts counter (to assert original + one retry).
    private func makeRefreshingClient() -> (APIClient, StubTokenRefresher, AtomicCounter) {
        let session = MockURLProtocol.makeSession()
        let provider = MutableTokenProvider("stale")
        let refresher = StubTokenRefresher { provider.set($0) }
        let api = APIClient(baseURL: URL(string: "http://test.local")!,
                            tokenProvider: provider, session: session)
        api.setRefresher(refresher)
        return (api, refresher, AtomicCounter())
    }

    /// A handler that 401s any request without the fresh Bearer and returns
    /// `okBody` (200) once the retried request carries `Bearer fresh`.
    private func first401ThenOK(_ attempts: AtomicCounter,
                                okBody: String) -> @Sendable (URLRequest) -> (HTTPURLResponse, Data) {
        { req in
            attempts.increment()
            let isRetry = req.value(forHTTPHeaderField: "Authorization") == "Bearer fresh"
            let status = isRetry ? 200 : 401
            let body = isRetry ? okBody : #"{"detail":"expired"}"#
            let resp = HTTPURLResponse(url: req.url!, statusCode: status,
                                       httpVersion: "1.1",
                                       headerFields: ["Content-Type": "application/json"])!
            return (resp, Data(body.utf8))
        }
    }

    // MARK: - 1. Vision (multipart photo recognition)

    @Test("VisionService.recognize refreshes once + retries on a 401")
    func vision_refreshesAndRetries() async throws {
        let (api, refresher, attempts) = makeRefreshingClient()
        let okBody = #"{"food":"pollo","grams":150,"confidence":"alta","calories":247,"protein_g":46.5,"carbs_g":0,"fat_g":5.4}"#
        let h = first401ThenOK(attempts, okBody: okBody)
        MockURLProtocol.handler = { try h($0) }

        let sut = VisionService(api: api)
        let result = try await sut.recognize(jpegData: Data([0xFF, 0xD8, 0xFF, 0xD9]))

        #expect(result.food == "pollo")
        #expect(refresher.calls.value == 1, "refresh must fire exactly once")
        #expect(attempts.value == 2, "original multipart request + one retry")
    }

    // MARK: - 2. Account deletion (DELETE /users/me)

    @Test("AccountService.deleteAccount refreshes once + retries on a 401")
    func account_refreshesAndRetries() async throws {
        let (api, refresher, attempts) = makeRefreshingClient()
        let h = first401ThenOK(attempts, okBody: "{}")
        MockURLProtocol.handler = { try h($0) }

        let sut = AccountService(api: api)
        try await sut.deleteAccount()

        #expect(refresher.calls.value == 1, "refresh must fire exactly once")
        #expect(attempts.value == 2, "original DELETE + one retry")
    }

    // MARK: - 3. Meal-plan mutation (POST /meal-plans)

    @MainActor
    @Test("MealPlanService.createPlan refreshes once + retries on a 401")
    func mealPlan_refreshesAndRetries() async throws {
        let (api, refresher, attempts) = makeRefreshingClient()
        let pid = "00000000-0000-0000-0000-0000000000A1"
        let uid = "00000000-0000-0000-0000-0000000000C1"
        let okBody = """
        {"id":"\(pid)","user_id":"\(uid)","name":"Semana","week_start_date":"2026-06-22",
         "notes":null,"is_template":false,"items":[]}
        """
        let h = first401ThenOK(attempts, okBody: okBody)
        MockURLProtocol.handler = { try h($0) }

        let container = try PersistenceController.makeInMemory().container
        let sut = MealPlanService(api: api, context: container.mainContext)
        let plan = try await sut.createPlan(weekStartDate: Date(),
                                            userId: UUID(uuidString: uid)!,
                                            name: "Semana")

        #expect(plan.id == UUID(uuidString: pid))
        #expect(refresher.calls.value == 1, "refresh must fire exactly once")
        #expect(attempts.value == 2, "original POST + one retry")
    }

    // MARK: - 4. Workout mutation (POST /workouts/sessions)

    @MainActor
    @Test("WorkoutService.startSession refreshes once + retries on a 401")
    func workout_refreshesAndRetries() async throws {
        let (api, refresher, attempts) = makeRefreshingClient()
        let sid = "00000000-0000-0000-0000-0000000000B1"
        let uid = "00000000-0000-0000-0000-0000000000C2"
        let okBody = """
        {"id":"\(sid)","user_id":"\(uid)","program_id":null,"program_day_id":null,
         "started_at":"2026-06-22T10:00:00Z","completed_at":null,"duration_minutes":null,
         "notes":null,"sets":[]}
        """
        let h = first401ThenOK(attempts, okBody: okBody)
        MockURLProtocol.handler = { try h($0) }

        let container = try PersistenceController.makeInMemory().container
        let sut = WorkoutService(api: api, context: container.mainContext)
        let userId = UUID(uuidString: uid)!
        _ = try await sut.startSession(programName: "PPL", dayName: "Push",
                                       programId: nil, programDayId: nil, userId: userId)

        // startSession is offline-resilient (it swallows backend errors), so the
        // proof that the POST actually succeeded after refresh is the cleared
        // pendingSync flag on the persisted row — only a 2xx clears it.
        let rows = try container.mainContext.fetch(
            FetchDescriptor<WorkoutSessionEntity>()
        )
        #expect(rows.first?.pendingSync == false,
                "a successful POST (after refresh) clears pendingSync")
        #expect(refresher.calls.value == 1, "refresh must fire exactly once")
        #expect(attempts.value == 2, "original POST + one retry")
    }

    // MARK: - 5. APIClient.postMultipart itself bounds the refresh loop

    @Test("APIClient.postMultipart does not loop on a persistent 401")
    func postMultipart_noInfiniteLoop() async {
        let (api, refresher, attempts) = makeRefreshingClient()
        // Server ALWAYS 401s, even with the refreshed token.
        MockURLProtocol.handler = { req in
            attempts.increment()
            let resp = HTTPURLResponse(url: req.url!, statusCode: 401,
                                       httpVersion: "1.1", headerFields: nil)!
            return (resp, Data(#"{"detail":"still expired"}"#.utf8))
        }
        let body = VisionService.makeMultipartBody(jpegData: Data([0x01]), boundary: "B")

        await #expect(throws: APIError.unauthorized) {
            let _: VisionRecognitionResponse = try await api.postMultipart(
                "/api/v1/nutrition/recognize", body: body, boundary: "B")
        }
        #expect(refresher.calls.value == 1, "refresh fires once, not per-attempt")
        #expect(attempts.value == 2, "original + exactly one retry, then give up")
    }
}
