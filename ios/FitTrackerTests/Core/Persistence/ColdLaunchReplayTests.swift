//
//  ColdLaunchReplayTests.swift
//  Codex review #5 P1 — cold-launch replay must run AFTER auth restore.
//
//  At launch, FitTrackerApp's `.task` starts sync while AuthGate restores the
//  persisted session later. With the nil-safe owner-guard, the launch drain
//  returns 0 (currentUser still nil) and nothing re-triggers it — so a queue
//  persisted from a prior session sits forever even though we're online.
//
//  The fix: `SyncManager.replayAfterAuthChange()` is invoked after a
//  successful restore/login/register/Apple sign-in; it drains when reachability
//  is not offline. These tests pin: (1) a drain with no current user is a
//  no-op that PRESERVES the queue, and (2) once the user is known and online,
//  replayAfterAuthChange flushes the leftover queue.
//

import Foundation
import SwiftData
import Testing
@testable import FitTracker

@Suite("Cold-launch replay after auth restore", .serialized)
struct ColdLaunchReplayTests {

    init() { MockURLProtocol.reset() }

    @MainActor
    @Test("a launch drain with a nil current user is a no-op that preserves the queue")
    func launchDrain_nilUser_preservesQueue() async {
        let session = MockURLProtocol.makeSession()
        let api = APIClient(baseURL: URL(string: "http://test.local")!, session: session)
        let suite = "test.cold.\(UUID().uuidString)"
        let queue = OfflineQueue(storageKey: "q", defaults: UserDefaults(suiteName: suite)!)
        let reachability = Reachability(autoStart: false)
        reachability.setStatus(.online)
        let sut = SyncManager(api: api, queue: queue, reachability: reachability)

        // Cold launch: AuthGate hasn't restored yet, so the user is unknown.
        nonisolated(unsafe) var currentUser: UUID? = nil
        sut.setCurrentUserProvider { currentUser }

        await queue.enqueue(.deleteMealItem(.init(ownerId: UUID(), id: UUID())))

        let hits = AtomicCounter()
        MockURLProtocol.handler = { req in
            hits.increment()
            return (HTTPURLResponse(url: req.url!, statusCode: 204, httpVersion: "1.1", headerFields: nil)!, Data())
        }

        let drained = await sut.drainNow()

        #expect(drained == 0, "no user yet → nothing replays")
        #expect(hits.value == 0, "the leftover write must NOT be sent under an unknown identity")
        #expect(await sut.pendingCount() == 1, "the queue is preserved for after auth restores")
    }

    @MainActor
    @Test("replayAfterAuthChange drains the leftover queue once the user is known and online")
    func replayAfterAuthChange_drainsLeftoverQueue() async {
        let session = MockURLProtocol.makeSession()
        let api = APIClient(baseURL: URL(string: "http://test.local")!, session: session)
        let suite = "test.cold.\(UUID().uuidString)"
        // Simulate a queue persisted by a PREVIOUS session, owned by the user
        // who will be restored.
        let owner = UUID()
        let preQueue = OfflineQueue(storageKey: "q", defaults: UserDefaults(suiteName: suite)!)
        await preQueue.enqueue(.deleteMealItem(.init(ownerId: owner, id: UUID())))

        let reachability = Reachability(autoStart: false)
        reachability.setStatus(.online)
        let freshQueue = OfflineQueue(storageKey: "q", defaults: UserDefaults(suiteName: suite)!)
        let sut = SyncManager(api: api, queue: freshQueue, reachability: reachability)

        // Model AuthGate restoring the session: the user is nil at launch,
        // then becomes known.
        nonisolated(unsafe) var currentUser: UUID? = nil
        sut.setCurrentUserProvider { currentUser }

        let hits = AtomicCounter()
        MockURLProtocol.handler = { req in
            hits.increment()
            return (HTTPURLResponse(url: req.url!, statusCode: 204, httpVersion: "1.1", headerFields: nil)!, Data())
        }

        // Launch drain (nil user) flushes nothing.
        let launchDrained = await sut.drainNow()
        #expect(launchDrained == 0)
        #expect(await sut.pendingCount() == 1, "still queued before restore")

        // restoreSession() completes → user known. The app calls
        // replayAfterAuthChange().
        currentUser = owner
        await sut.replayAfterAuthChange()

        #expect(hits.value == 1, "the leftover write must replay once auth is restored")
        #expect(await sut.pendingCount() == 0, "the queue drains after auth restore + online")
    }

    @MainActor
    @Test("replayAfterAuthChange while offline does not send (drains on later reconnect)")
    func replayAfterAuthChange_offline_isNoOp() async {
        let session = MockURLProtocol.makeSession()
        let api = APIClient(baseURL: URL(string: "http://test.local")!, session: session)
        let suite = "test.cold.\(UUID().uuidString)"
        let queue = OfflineQueue(storageKey: "q", defaults: UserDefaults(suiteName: suite)!)
        let reachability = Reachability(autoStart: false)
        reachability.setStatus(.offline)
        let sut = SyncManager(api: api, queue: queue, reachability: reachability)

        let owner = UUID()
        sut.setCurrentUserProvider { owner }
        await queue.enqueue(.deleteMealItem(.init(ownerId: owner, id: UUID())))

        let hits = AtomicCounter()
        MockURLProtocol.handler = { req in
            hits.increment()
            return (HTTPURLResponse(url: req.url!, statusCode: 204, httpVersion: "1.1", headerFields: nil)!, Data())
        }

        await sut.replayAfterAuthChange()

        #expect(hits.value == 0, "offline → replay deferred to the next reconnect, never sent now")
        #expect(await sut.pendingCount() == 1)
    }
}
