//
//  SyncManagerTests.swift
//  Slice 2.2 verification: enqueue under offline, drain on reconnect,
//  immediate flush when online.
//

import Foundation
import Testing
@testable import FitTracker

@Suite("OfflineQueue", .serialized)
struct OfflineQueueTests {

    private func makeQueue() -> OfflineQueue {
        let suiteName = "test.fittracker.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return OfflineQueue(storageKey: "queue", defaults: defaults)
    }

    @Test("enqueue + peekAll round-trip")
    func enqueue_peek() async {
        let q = makeQueue()
        let mut = PendingMutation.deleteMealItem(.init(id: UUID(), mealId: UUID()))
        await q.enqueue(mut)
        let all = await q.peekAll()
        #expect(all.count == 1)
        #expect(all.first?.id == mut.id)
    }

    @Test("remove(id:) only removes the matching mutation")
    func remove_byId() async {
        let q = makeQueue()
        let a = PendingMutation.deleteMealItem(.init(id: UUID(), mealId: UUID()))
        let b = PendingMutation.deleteMealItem(.init(id: UUID(), mealId: UUID()))
        await q.enqueue(a)
        await q.enqueue(b)
        await q.remove(id: a.id)
        let remaining = await q.peekAll()
        #expect(remaining.count == 1)
        #expect(remaining.first?.id == b.id)
    }

    @Test("drain stops on first failure, preserves order")
    func drain_stopsOnFailure() async {
        let q = makeQueue()
        let a = PendingMutation.deleteMealItem(.init(id: UUID(), mealId: UUID()))
        let b = PendingMutation.deleteMealItem(.init(id: UUID(), mealId: UUID()))
        let c = PendingMutation.deleteMealItem(.init(id: UUID(), mealId: UUID()))
        await q.enqueue(a)
        await q.enqueue(b)
        await q.enqueue(c)

        let counter = AtomicCounter()
        let drained = await q.drain { mutation in
            counter.increment()
            if mutation.id == b.id { throw APIError.offline }
        }

        #expect(drained == 1, "only `a` succeeded")
        #expect(counter.value == 2, "tried a, then b — stopped after b failed")
        let remaining = await q.peekAll()
        #expect(remaining.count == 2, "b and c still queued")
        #expect(remaining.first?.id == b.id, "order preserved (b first)")
    }

    @Test("removeAll clears the queue")
    func removeAll() async {
        let q = makeQueue()
        await q.enqueue(.deleteMealItem(.init(id: UUID(), mealId: UUID())))
        await q.removeAll()
        #expect(await q.peekAll().isEmpty)
    }
}

@Suite("Reachability", .serialized)
struct ReachabilityTests {

    @MainActor
    @Test("setStatus flips state and notifies listeners")
    func status_listener() async {
        let r = Reachability(autoStart: false)
        let counter = AtomicCounter()
        r.onChange { _ in counter.increment() }

        r.setStatus(.online)
        r.setStatus(.online)   // duplicate flip — no callback
        r.setStatus(.offline)

        #expect(counter.value == 2)
        #expect(r.status == .offline)
    }
}

@Suite("SyncManager", .serialized)
struct SyncManagerTests {

    init() { MockURLProtocol.reset() }

    @MainActor
    @Test("enqueue while online flushes immediately")
    func onlineEnqueue_flushes() async {
        let session = MockURLProtocol.makeSession()
        let api = APIClient(baseURL: URL(string: "http://test.local")!, session: session)
        let suite = "test.sync.\(UUID().uuidString)"
        let queue = OfflineQueue(storageKey: "q", defaults: UserDefaults(suiteName: suite)!)
        let reachability = Reachability(autoStart: false)
        reachability.setStatus(.online)
        let sut = SyncManager(api: api, queue: queue, reachability: reachability)

        let counter = AtomicCounter()
        MockURLProtocol.handler = { req in
            counter.increment()
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "1.1", headerFields: nil)!
            return (resp, Data(#"{"id":"00000000-0000-0000-0000-000000000001"}"#.utf8))
        }

        await sut.enqueue(.createMeal(.init(
            localId: UUID(),
            userId: UUID(),
            mealType: "breakfast",
            mealDate: Date(),
            items: []
        )))

        #expect(counter.value == 1)
        #expect(await sut.pendingCount() == 0)
    }

    @MainActor
    @Test("enqueue while offline keeps the mutation queued")
    func offlineEnqueue_queues() async {
        let session = MockURLProtocol.makeSession()
        let api = APIClient(baseURL: URL(string: "http://test.local")!, session: session)
        let suite = "test.sync.\(UUID().uuidString)"
        let queue = OfflineQueue(storageKey: "q", defaults: UserDefaults(suiteName: suite)!)
        let reachability = Reachability(autoStart: false)
        reachability.setStatus(.offline)
        let sut = SyncManager(api: api, queue: queue, reachability: reachability)

        let counter = AtomicCounter()
        MockURLProtocol.handler = { _ in
            counter.increment()
            return (HTTPURLResponse(url: URL(string: "http://test.local/x")!, statusCode: 500, httpVersion: nil, headerFields: nil)!, Data())
        }

        await sut.enqueue(.deleteMealItem(.init(id: UUID(), mealId: UUID())))

        #expect(counter.value == 0, "offline enqueue must not hit the network")
        #expect(await sut.pendingCount() == 1)
    }

    @MainActor
    @Test("reconnect drains queued mutations")
    func reconnect_drains() async {
        let session = MockURLProtocol.makeSession()
        let api = APIClient(baseURL: URL(string: "http://test.local")!, session: session)
        let suite = "test.sync.\(UUID().uuidString)"
        let queue = OfflineQueue(storageKey: "q", defaults: UserDefaults(suiteName: suite)!)
        let reachability = Reachability(autoStart: false)
        reachability.setStatus(.offline)
        let sut = SyncManager(api: api, queue: queue, reachability: reachability)
        sut.startObservingConnectivity()

        // Enqueue 2 deletions while offline
        await sut.enqueue(.deleteMealItem(.init(id: UUID(), mealId: UUID())))
        await sut.enqueue(.deleteMealItem(.init(id: UUID(), mealId: UUID())))
        #expect(await sut.pendingCount() == 2)

        let counter = AtomicCounter()
        MockURLProtocol.handler = { req in
            counter.increment()
            return (HTTPURLResponse(url: req.url!, statusCode: 204, httpVersion: "1.1", headerFields: nil)!, Data())
        }

        // Flip online — listener should drain
        reachability.setStatus(.online)

        // Give the Task spawned by the listener a moment to complete
        try? await Task.sleep(nanoseconds: 100_000_000)

        #expect(counter.value == 2)
        #expect(await sut.pendingCount() == 0)
    }
}
