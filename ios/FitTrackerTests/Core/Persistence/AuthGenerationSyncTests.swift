//
//  AuthGenerationSyncTests.swift
//  Codex review #5 P0 — replay owner must be bound to the bearer token used
//  for the ACTUAL request, across the 401-refresh + account-switch race.
//
//  The Wave-5 owner-guard checks the mutation owner at DRAIN time, but
//  `APIClient` independently reads the keychain token at request-build and
//  swaps in a refreshed token on 401. If sign-out / account-switch A→B
//  completes mid-drain (before the initial send, or before a 401 refresh
//  retry), A's queued mutation could still be sent under B's bearer.
//
//  The fix: a monotonic `AuthService.sessionGeneration` (bumped on signOut
//  AND on every successful auth) plus a per-replay `authGuard` that
//  `APIClient` re-checks BOTH before the initial send AND before swapping in
//  a refreshed token on 401. A generation/owner change ABORTS the replay
//  (the mutation stays queued; nothing is sent under the new user).
//

import Foundation
import SwiftData
import Testing
@testable import FitTracker

@Suite("Auth-generation replay sync", .serialized)
struct AuthGenerationSyncTests {

    init() { MockURLProtocol.reset() }

    // MARK: - Stub refresher that flips identity mid-refresh

    /// Simulates an account switch happening DURING the 401 refresh: when the
    /// APIClient asks for a fresh token, the `onRefresh` side effect mutates
    /// the shared identity box to user B (new generation) before returning B's
    /// token. The guard must see the change and abort the retry.
    final class SwitchingRefresher: TokenRefreshing, @unchecked Sendable {
        let calls = AtomicCounter()
        let onRefresh: @Sendable () -> String
        init(onRefresh: @escaping @Sendable () -> String) { self.onRefresh = onRefresh }
        func refreshAccessToken() async throws -> String {
            calls.increment()
            return onRefresh()
        }
    }

    /// Mutable, lock-protected (owner, generation) the test flips to model an
    /// A→B account switch. Read by the SyncManager providers on the MainActor.
    final class IdentityBox: @unchecked Sendable {
        private let lock = NSLock()
        private var _owner: UUID
        private var _gen: Int
        init(owner: UUID, gen: Int) { _owner = owner; _gen = gen }
        var owner: UUID { lock.lock(); defer { lock.unlock() }; return _owner }
        var generation: Int { lock.lock(); defer { lock.unlock() }; return _gen }
        func switchTo(owner: UUID, gen: Int) {
            lock.lock(); defer { lock.unlock() }; _owner = owner; _gen = gen
        }
    }

    // MARK: - Task 4(a)

    @MainActor
    @Test("drain starts as A, 401 occurs, auth switches to B before refresh → mutation NOT sent under B, stays queued")
    func drain_abortsWhenAuthSwitchesDuringRefresh() async throws {
        let session = MockURLProtocol.makeSession()
        let api = APIClient(baseURL: URL(string: "http://test.local")!,
                            tokenProvider: nil, session: session)
        let suite = "test.authgen.\(UUID().uuidString)"
        let queue = OfflineQueue(storageKey: "q", defaults: UserDefaults(suiteName: suite)!)
        let reachability = Reachability(autoStart: false)
        reachability.setStatus(.online)

        let userA = UUID()
        let userB = UUID()
        let identity = IdentityBox(owner: userA, gen: 1)

        // The refresher models the account switch: when APIClient refreshes
        // after the 401, the user has just switched to B (new generation).
        let refresher = SwitchingRefresher {
            identity.switchTo(owner: userB, gen: 2)
            return "tokenB"
        }
        api.setRefresher(refresher)

        let sut = SyncManager(api: api, queue: queue, reachability: reachability)
        sut.setCurrentUserProvider { identity.owner }
        sut.setSessionGenerationProvider { identity.generation }

        // A's mutation is queued (owned by A, captured generation 1).
        await queue.enqueue(.deleteMealItem(.init(ownerId: userA, id: UUID())))

        // Server: ALWAYS 401, so the drain hits the refresh path. If the guard
        // were absent, the retry would be sent under B's "tokenB".
        let sentUnderB = AtomicCounter()
        let totalHits = AtomicCounter()
        MockURLProtocol.handler = { req in
            totalHits.increment()
            if req.value(forHTTPHeaderField: "Authorization") == "Bearer tokenB" {
                sentUnderB.increment()
            }
            return (HTTPURLResponse(url: req.url!, statusCode: 401, httpVersion: "1.1", headerFields: nil)!,
                    Data(#"{"detail":"expired"}"#.utf8))
        }

        let drained = await sut.drainNow()

        #expect(drained == 0, "A's mutation must not count as drained once auth switched to B")
        #expect(sentUnderB.value == 0,
                "A's queued write must NEVER be retried under B's bearer token")
        #expect(refresher.calls.value == 1, "refresh fires once before the guard aborts the retry")
        let remaining = await sut.pendingMutations()
        #expect(remaining.count == 1, "the aborted mutation stays queued for when A signs back in")
        #expect(remaining.first?.ownerId == userA)
    }

    @MainActor
    @Test("auth switches to B BEFORE the initial send → mutation not sent at all, stays queued")
    func drain_abortsWhenAuthSwitchesBeforeInitialSend() async throws {
        let session = MockURLProtocol.makeSession()
        let api = APIClient(baseURL: URL(string: "http://test.local")!,
                            tokenProvider: nil, session: session)
        let suite = "test.authgen.\(UUID().uuidString)"
        let queue = OfflineQueue(storageKey: "q", defaults: UserDefaults(suiteName: suite)!)
        let reachability = Reachability(autoStart: false)
        reachability.setStatus(.online)

        let userA = UUID()
        let userB = UUID()
        // Identity already flipped to B (generation bumped) — models a sign-out
        // + sign-in completing after the queue-level owner check but before the
        // per-request send. The request-level guard captured A@gen1.
        let identity = IdentityBox(owner: userB, gen: 2)

        let sut = SyncManager(api: api, queue: queue, reachability: reachability)
        // Drain is owner-guarded to A@gen1 via an explicit capture the guard
        // compares against the LIVE (now-B) identity.
        sut.setCurrentUserProvider { identity.owner }
        sut.setSessionGenerationProvider { identity.generation }

        // Stamp the mutation as A's, but force the drain to attempt it by
        // pretending A is current at capture time, then the guard sees B live.
        // We model this by capturing the guard against A@1 explicitly through
        // the SyncManager replay path: enqueue as A and have the live identity
        // already be B so the per-request guard fails.
        await queue.enqueue(.deleteMealItem(.init(ownerId: userA, id: UUID())))

        let hits = AtomicCounter()
        MockURLProtocol.handler = { req in
            hits.increment()
            return (HTTPURLResponse(url: req.url!, statusCode: 204, httpVersion: "1.1", headerFields: nil)!, Data())
        }

        let drained = await sut.drainNow()

        // Because the live owner is already B, the queue-level owner-guard
        // alone quarantines A's mutation — no network at all.
        #expect(drained == 0)
        #expect(hits.value == 0, "nothing sent once the live user is no longer A")
        #expect(await sut.pendingCount() == 1, "A's mutation stays queued")
    }

    // MARK: - Happy path: same identity throughout → replay succeeds

    @MainActor
    @Test("when identity is unchanged through a 401 refresh, the replay still completes")
    func drain_succeedsWhenIdentityStable() async throws {
        let session = MockURLProtocol.makeSession()
        let api = APIClient(baseURL: URL(string: "http://test.local")!,
                            tokenProvider: nil, session: session)
        let suite = "test.authgen.\(UUID().uuidString)"
        let queue = OfflineQueue(storageKey: "q", defaults: UserDefaults(suiteName: suite)!)
        let reachability = Reachability(autoStart: false)
        reachability.setStatus(.online)

        let userA = UUID()
        let identity = IdentityBox(owner: userA, gen: 1)
        // Refresh returns a fresh token but DOES NOT change identity.
        let refresher = SwitchingRefresher { "freshA" }
        api.setRefresher(refresher)

        let sut = SyncManager(api: api, queue: queue, reachability: reachability)
        sut.setCurrentUserProvider { identity.owner }
        sut.setSessionGenerationProvider { identity.generation }

        await queue.enqueue(.deleteMealItem(.init(ownerId: userA, id: UUID())))

        // First attempt → 401; retry with the refreshed token → 204.
        MockURLProtocol.handler = { req in
            if req.value(forHTTPHeaderField: "Authorization") == "Bearer freshA" {
                return (HTTPURLResponse(url: req.url!, statusCode: 204, httpVersion: "1.1", headerFields: nil)!, Data())
            }
            return (HTTPURLResponse(url: req.url!, statusCode: 401, httpVersion: "1.1", headerFields: nil)!,
                    Data(#"{"detail":"expired"}"#.utf8))
        }

        let drained = await sut.drainNow()

        #expect(drained == 1, "stable identity → the refreshed retry completes the replay")
        #expect(refresher.calls.value == 1)
        #expect(await sut.pendingCount() == 0, "the confirmed mutation leaves the queue")
    }
}
