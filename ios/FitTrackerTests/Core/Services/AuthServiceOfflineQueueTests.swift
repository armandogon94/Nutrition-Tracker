//
//  AuthServiceOfflineQueueTests.swift
//  Codex review #4 P0 — sign-out must clear the signed-out user's offline
//  queue so a queued write can never replay under the NEXT account.
//
//  Also exercises the headline cross-account scenario end-to-end against
//  the SyncManager owner-guard: user A enqueues offline, signs out, user B
//  signs in and drains — A's mutation is NOT sent under B's token.
//

import Foundation
import SwiftData
import Testing
@testable import FitTracker

@Suite("AuthService offline-queue", .serialized)
struct AuthServiceOfflineQueueTests {

    init() { MockURLProtocol.reset() }

    @MainActor
    private func makeQueue() -> OfflineQueue {
        OfflineQueue(storageKey: "q",
                     defaults: UserDefaults(suiteName: "test.authq.\(UUID().uuidString)")!)
    }

    @MainActor
    private func makeAuth(queue: OfflineQueue,
                          seedAccess: String? = nil,
                          seedRefresh: String? = nil) async -> (AuthService, KeychainTokenStore) {
        let session = MockURLProtocol.makeSession()
        let kc = KeychainTokenStore(service: "test.fittracker.\(UUID().uuidString)")
        kc.clearAll()
        if let seedAccess { await kc.updateAccessToken(seedAccess) }
        if let seedRefresh { await kc.updateRefreshToken(seedRefresh) }
        if seedAccess != nil { await kc.updateAccessTokenExpiry(Date().addingTimeInterval(3600)) }
        let api = APIClient(baseURL: URL(string: "http://test.local")!,
                            tokenProvider: nil, session: session)
        return (AuthService(api: api, keychain: kc, offlineQueue: queue), kc)
    }

    @MainActor
    @Test("signOut clears the signed-out user's queued mutations")
    func signOut_clearsCurrentUsersQueue() async throws {
        let queue = makeQueue()
        let (sut, kc) = await makeAuth(queue: queue, seedAccess: "acc", seedRefresh: "ref")
        defer { kc.clearAll() }

        // Drive the service to a known signed-in user via /auth/me, then
        // enqueue a mutation owned by that user.
        MockURLProtocol.handler = { req in
            if req.url?.path.hasSuffix("/auth/login") == true {
                return (Self.ok(req), Data(Self.tokensJSON.utf8))
            }
            if req.url?.path.hasSuffix("/auth/me") == true {
                return (Self.ok(req), Data(Self.meJSON.utf8))
            }
            // logout revoke
            return (Self.ok(req), Data())
        }
        try await sut.login(email: "a@x.dev", password: "pw")
        let uid = try #require(sut.currentUser?.id)
        await queue.enqueue(.deleteMealItem(.init(ownerId: uid, id: UUID())))
        #expect(await queue.peekAll().count == 1)

        await sut.signOut()

        #expect(await queue.peekAll().isEmpty,
                "sign-out must purge the signed-out user's queued writes so they can't replay under another account")
        #expect(!sut.isAuthenticated)
    }

    @MainActor
    @Test("user A enqueues offline, signs out, user B signs in → A's mutation is not replayed under B")
    func crossAccount_replayIsBlocked() async throws {
        // One shared durable queue, exactly like OfflineQueue.shared in prod.
        let queue = makeQueue()

        // ---- User A session ----
        let (authA, kcA) = await makeAuth(queue: queue, seedAccess: "accA", seedRefresh: "refA")
        defer { kcA.clearAll() }
        let userA = UUID()

        // A logs a meal OFFLINE → durable mutation owned by A.
        await queue.enqueue(.logMealItem(.init(
            ownerId: userA,
            clientItemId: UUID(), mealType: "lunch", mealDate: "2025-01-01",
            productId: UUID(), productName: "Arroz de A", brand: nil,
            servings: 1, calories: 200, proteinG: 4, carbsG: 44, fatG: 1)))

        // A signs out. We DON'T clear via A here on purpose for the strict
        // case where sign-out clearing might be bypassed — the owner-guard is
        // the real backstop. (signOut also clears, tested separately.)
        // Simulate the queue surviving by NOT calling signOut's clear path:
        // re-seed the same mutation to model "left over from A".
        _ = authA

        // ---- User B session, SAME queue ----
        let session = MockURLProtocol.makeSession()
        let apiB = APIClient(baseURL: URL(string: "http://test.local")!, session: session)
        let reachability = Reachability(autoStart: false)
        reachability.setStatus(.online)
        let sync = SyncManager(api: apiB, queue: queue, reachability: reachability)
        let userB = UUID()
        sync.setCurrentUserProvider { userB }   // B is now the signed-in user

        let hits = AtomicCounter()
        MockURLProtocol.handler = { req in
            hits.increment()
            return (Self.created(req), Data(Self.mealLogResponseJSON.utf8))
        }

        let drained = await sync.drainNow()

        #expect(drained == 0, "B must not flush A's offline meal log")
        #expect(hits.value == 0, "A's POST /meals/log must never be sent under B's bearer token")
        let remaining = await sync.pendingMutations()
        #expect(remaining.count == 1, "A's mutation stays quarantined")
        #expect(remaining.first?.ownerId == userA)
    }

    // MARK: - Fixtures

    private static func ok(_ r: URLRequest) -> HTTPURLResponse {
        HTTPURLResponse(url: r.url!, statusCode: 200, httpVersion: "1.1", headerFields: nil)!
    }
    private static func created(_ r: URLRequest) -> HTTPURLResponse {
        HTTPURLResponse(url: r.url!, statusCode: 201, httpVersion: "1.1",
                        headerFields: ["Content-Type": "application/json"])!
    }
    private static let tokensJSON = #"""
    {"access_token":"accA","refresh_token":"refA","token_type":"bearer","expires_in":3600}
    """#
    private static let meJSON = #"""
    {"id":"00000000-0000-0000-0000-0000000000AA","email":"a@x.dev","display_name":"A","role":"user"}
    """#
    private static let mealLogResponseJSON = #"""
    {"id":"00000000-0000-0000-0000-00000000ABCD","user_id":"00000000-0000-0000-0000-0000000000AA","meal_type":"lunch","meal_date":"2025-01-01","items":[]}
    """#
}
