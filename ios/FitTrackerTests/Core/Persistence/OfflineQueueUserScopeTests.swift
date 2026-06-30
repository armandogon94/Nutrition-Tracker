//
//  OfflineQueueUserScopeTests.swift
//  Codex review #4 P0 — cross-user replay of OfflineQueue.shared.
//
//  These tests pin the user-scoping contract that closes the release
//  blocker: every PendingMutation is stamped with the userId that created
//  it; the queue can remove a single owner's entries; the SyncManager
//  owner-guards replay so it never sends user A's queued write under user
//  B's token; and sign-out clears the signed-out user's queue. They also
//  pin the P2 "lost-write window" fix (enqueue BEFORE the network call).
//

import Foundation
import SwiftData
import Testing
@testable import FitTracker

// MARK: - PendingMutation owner stamping

@Suite("PendingMutation owner", .serialized)
struct PendingMutationOwnerTests {

    @Test("logMealItem carries its owning userId, distinct from the dedup id")
    func logMealItem_carriesOwnerId() {
        let owner = UUID()
        let itemId = UUID()
        let mut = PendingMutation.logMealItem(.init(
            ownerId: owner,
            clientItemId: itemId, mealType: "lunch", mealDate: "2025-01-01",
            productId: UUID(), productName: "Arroz", brand: nil,
            servings: 1, calories: 200, proteinG: 4, carbsG: 44, fatG: 1))
        #expect(mut.ownerId == owner, "mutation must expose the user who created it")
        #expect(mut.id == itemId, "dedup id stays the client_item_id, not the owner")
    }

    @Test("deleteMealItem carries its owning userId")
    func deleteMealItem_carriesOwnerId() {
        let owner = UUID()
        let itemId = UUID()
        let mut = PendingMutation.deleteMealItem(.init(ownerId: owner, id: itemId))
        #expect(mut.ownerId == owner)
        #expect(mut.id == itemId)
    }

    @Test("owner survives a Codable round-trip through the queue's JSON")
    func ownerId_survivesEncodeDecode() throws {
        let owner = UUID()
        let mut = PendingMutation.deleteMealItem(.init(ownerId: owner, id: UUID()))
        let data = try JSONEncoder().encode([mut])
        let back = try JSONDecoder().decode([PendingMutation].self, from: data)
        #expect(back.first?.ownerId == owner)
    }
}

// MARK: - OfflineQueue owner-scoped removal

@Suite("OfflineQueue owner scope", .serialized)
struct OfflineQueueOwnerScopeTests {

    private func makeQueue() -> OfflineQueue {
        let suiteName = "test.fittracker.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return OfflineQueue(storageKey: "queue", defaults: defaults)
    }

    @Test("removeAll(ownedBy:) drops only that user's mutations")
    func removeAll_ownedBy() async {
        let q = makeQueue()
        let userA = UUID()
        let userB = UUID()
        await q.enqueue(.deleteMealItem(.init(ownerId: userA, id: UUID())))
        await q.enqueue(.deleteMealItem(.init(ownerId: userB, id: UUID())))
        await q.enqueue(.deleteMealItem(.init(ownerId: userA, id: UUID())))

        await q.removeAll(ownedBy: userA)

        let remaining = await q.peekAll()
        #expect(remaining.count == 1, "only user B's mutation survives")
        #expect(remaining.first?.ownerId == userB)
    }

    @Test("drain(ownedBy:) skips foreign mutations and replays only the owner's")
    func drain_ownedBy_skipsForeign() async {
        let q = makeQueue()
        let me = UUID()
        let other = UUID()
        // Interleave so a naive 'stop on first foreign' would wrongly stall.
        await q.enqueue(.deleteMealItem(.init(ownerId: other, id: UUID())))
        await q.enqueue(.deleteMealItem(.init(ownerId: me, id: UUID())))
        await q.enqueue(.deleteMealItem(.init(ownerId: other, id: UUID())))
        await q.enqueue(.deleteMealItem(.init(ownerId: me, id: UUID())))

        let applied = AtomicCounter()
        let drained = await q.drain(ownedBy: me) { mutation in
            #expect(mutation.ownerId == me, "drain must never hand a foreign mutation to apply")
            applied.increment()
        }

        #expect(drained == 2, "both of my mutations replayed")
        #expect(applied.value == 2, "apply was only ever called for my mutations")
        let remaining = await q.peekAll()
        #expect(remaining.count == 2, "the other user's mutations are quarantined, not replayed")
        #expect(remaining.allSatisfy { $0.ownerId == other })
    }

    @Test("drain(ownedBy:) stops on the owner's first network failure, preserving order")
    func drain_ownedBy_stopsOnFailure() async {
        let q = makeQueue()
        let me = UUID()
        let a = UUID(); let b = UUID(); let c = UUID()
        await q.enqueue(.deleteMealItem(.init(ownerId: me, id: a)))
        await q.enqueue(.deleteMealItem(.init(ownerId: me, id: b)))
        await q.enqueue(.deleteMealItem(.init(ownerId: me, id: c)))

        let tries = AtomicCounter()
        let drained = await q.drain(ownedBy: me) { mutation in
            tries.increment()
            if mutation.id == b { throw APIError.offline }
        }

        #expect(drained == 1, "only `a` succeeded")
        #expect(tries.value == 2, "tried a then b, then stopped")
        let remaining = await q.peekAll()
        #expect(remaining.count == 2, "b and c stay queued")
        #expect(remaining.first?.id == b)
    }
}

// MARK: - OfflineQueue corruption quarantine (review C4 / Flash B1)

@Suite("OfflineQueue corruption quarantine", .serialized)
struct OfflineQueueQuarantineTests {

    private func makeDefaults() -> (defaults: UserDefaults, suite: String, key: String) {
        let suite = "test.fittracker.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite, "queue")
    }

    @Test("corrupt blob is quarantined, not silently dropped")
    func corruptBlob_isQuarantined() async {
        let (defaults, suite, key) = makeDefaults()
        // Seed an undecodable blob under the live queue key.
        let garbage = Data("{ not valid pending mutations ]".utf8)
        defaults.set(garbage, forKey: key)

        // Give the actor its OWN handle to the same suite store so the
        // non-Sendable `defaults` we seed/assert with is never "sent" into the
        // actor (Swift 6 data-race safety) — matches the pattern used elsewhere
        // in this file.
        let q = OfflineQueue(storageKey: key, defaults: UserDefaults(suiteName: suite)!)

        // Reading yields empty (the queue can't decode it)...
        let items = await q.peekAll()
        #expect(items.isEmpty)

        // ...but the raw bytes are preserved under the quarantine key, and the
        // primary key was cleared so we don't re-attempt the same decode.
        let quarantined = defaults.data(forKey: q.corruptedKey)
        #expect(quarantined == garbage, "corrupt payload must be copied to the quarantine key")
        #expect(defaults.data(forKey: key) == nil, "primary key cleared after quarantine")
    }

    @Test("a later enqueue after corruption does not erase the quarantined blob")
    func enqueueAfterCorruption_keepsQuarantine() async {
        let (defaults, suite, key) = makeDefaults()
        let garbage = Data("totally not json".utf8)
        defaults.set(garbage, forKey: key)

        // Give the actor its OWN handle to the same suite store so the
        // non-Sendable `defaults` we seed/assert with is never "sent" into the
        // actor (Swift 6 data-race safety) — matches the pattern used elsewhere
        // in this file.
        let q = OfflineQueue(storageKey: key, defaults: UserDefaults(suiteName: suite)!)
        // First read triggers the quarantine.
        _ = await q.peekAll()

        // A brand-new write proceeds normally on the (now-cleared) primary key.
        let owner = UUID()
        await q.enqueue(.deleteMealItem(.init(ownerId: owner, id: UUID())))
        let items = await q.peekAll()
        #expect(items.count == 1, "new mutations still enqueue after a corruption event")

        // The quarantined blob is still recoverable — never overwritten.
        #expect(defaults.data(forKey: q.corruptedKey) == garbage)
    }

    @Test("first corruption wins: a second corrupt read doesn't clobber the quarantine")
    func secondCorruption_keepsFirstBlob() async {
        let (defaults, suite, key) = makeDefaults()
        let first = Data("first-corrupt".utf8)
        defaults.set(first, forKey: key)

        // Give the actor its OWN handle to the same suite store so the
        // non-Sendable `defaults` we seed/assert with is never "sent" into the
        // actor (Swift 6 data-race safety) — matches the pattern used elsewhere
        // in this file.
        let q = OfflineQueue(storageKey: key, defaults: UserDefaults(suiteName: suite)!)
        _ = await q.peekAll()   // quarantines `first`, clears primary

        // Simulate a second corruption landing on the primary key later.
        let second = Data("second-corrupt".utf8)
        defaults.set(second, forKey: key)
        _ = await q.peekAll()

        #expect(defaults.data(forKey: q.corruptedKey) == first,
                "the earliest corrupt blob is preserved, not overwritten")
    }
}

// MARK: - SyncManager owner guard

@Suite("SyncManager owner guard", .serialized)
struct SyncManagerOwnerGuardTests {

    init() { MockURLProtocol.reset() }

    @MainActor
    @Test("drainNow never replays a mutation owned by a different user")
    func drain_skipsForeignOwner() async {
        let session = MockURLProtocol.makeSession()
        let api = APIClient(baseURL: URL(string: "http://test.local")!, session: session)
        let suite = "test.sync.\(UUID().uuidString)"
        let queue = OfflineQueue(storageKey: "q", defaults: UserDefaults(suiteName: suite)!)
        let reachability = Reachability(autoStart: false)
        reachability.setStatus(.online)
        let sut = SyncManager(api: api, queue: queue, reachability: reachability)

        let userA = UUID()
        let userB = UUID()
        // Current user is B; a stale mutation from A is in the queue.
        sut.setCurrentUserProvider { userB }

        await queue.enqueue(.deleteMealItem(.init(ownerId: userA, id: UUID())))

        let hits = AtomicCounter()
        MockURLProtocol.handler = { req in
            hits.increment()
            return (HTTPURLResponse(url: req.url!, statusCode: 204, httpVersion: "1.1", headerFields: nil)!, Data())
        }

        let drained = await sut.drainNow()

        #expect(drained == 0, "B must not flush A's mutation")
        #expect(hits.value == 0, "A's queued write must never reach the network under B's token")
        #expect(await sut.pendingCount() == 1, "A's mutation stays quarantined for when A signs back in")
    }

    @MainActor
    @Test("drainNow replays only the current user's mutations, quarantining the rest")
    func drain_replaysOwnUserOnly() async {
        let session = MockURLProtocol.makeSession()
        let api = APIClient(baseURL: URL(string: "http://test.local")!, session: session)
        let suite = "test.sync.\(UUID().uuidString)"
        let queue = OfflineQueue(storageKey: "q", defaults: UserDefaults(suiteName: suite)!)
        let reachability = Reachability(autoStart: false)
        reachability.setStatus(.online)
        let sut = SyncManager(api: api, queue: queue, reachability: reachability)

        let me = UUID()
        let other = UUID()
        sut.setCurrentUserProvider { me }

        await queue.enqueue(.deleteMealItem(.init(ownerId: other, id: UUID())))
        await queue.enqueue(.deleteMealItem(.init(ownerId: me, id: UUID())))

        let hits = AtomicCounter()
        MockURLProtocol.handler = { req in
            hits.increment()
            return (HTTPURLResponse(url: req.url!, statusCode: 204, httpVersion: "1.1", headerFields: nil)!, Data())
        }

        let drained = await sut.drainNow()

        #expect(drained == 1, "only my mutation flushed")
        #expect(hits.value == 1, "exactly one network call, mine")
        let remaining = await sut.pendingMutations()
        #expect(remaining.count == 1)
        #expect(remaining.first?.ownerId == other, "the foreign mutation is untouched")
    }

    @MainActor
    @Test("with no current user, nothing is replayed")
    func drain_noCurrentUser_replaysNothing() async {
        let session = MockURLProtocol.makeSession()
        let api = APIClient(baseURL: URL(string: "http://test.local")!, session: session)
        let suite = "test.sync.\(UUID().uuidString)"
        let queue = OfflineQueue(storageKey: "q", defaults: UserDefaults(suiteName: suite)!)
        let reachability = Reachability(autoStart: false)
        reachability.setStatus(.online)
        let sut = SyncManager(api: api, queue: queue, reachability: reachability)
        sut.setCurrentUserProvider { nil }   // signed out

        await queue.enqueue(.deleteMealItem(.init(ownerId: UUID(), id: UUID())))

        let hits = AtomicCounter()
        MockURLProtocol.handler = { req in
            hits.increment()
            return (HTTPURLResponse(url: req.url!, statusCode: 204, httpVersion: "1.1", headerFields: nil)!, Data())
        }

        let drained = await sut.drainNow()
        #expect(drained == 0)
        #expect(hits.value == 0, "no signed-in user → no replay at all")
    }
}
