//
//  SyncManagerTests.swift
//  Slice 2.2 verification: enqueue under offline, drain on reconnect,
//  immediate flush when online.
//

import Foundation
import SwiftData
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
        let mut = PendingMutation.deleteMealItem(.init(id: UUID()))
        await q.enqueue(mut)
        let all = await q.peekAll()
        #expect(all.count == 1)
        #expect(all.first?.id == mut.id)
    }

    @Test("remove(id:) only removes the matching mutation")
    func remove_byId() async {
        let q = makeQueue()
        let a = PendingMutation.deleteMealItem(.init(id: UUID()))
        let b = PendingMutation.deleteMealItem(.init(id: UUID()))
        await q.enqueue(a)
        await q.enqueue(b)
        await q.remove(id: a.id)
        let remaining = await q.peekAll()
        #expect(remaining.count == 1)
        #expect(remaining.first?.id == b.id)
    }

    @Test("enqueue is idempotent by id — re-enqueuing replaces in place, no dup")
    func enqueue_dedupesById() async {
        let q = makeQueue()
        let itemId = UUID()
        // Same client_item_id logged twice (e.g. failed write re-enqueued).
        let first = PendingMutation.logMealItem(.init(
            clientItemId: itemId, mealType: "lunch", mealDate: "2025-01-01",
            productId: UUID(), productName: "Arroz", brand: nil,
            servings: 1, calories: 200, proteinG: 4, carbsG: 44, fatG: 1))
        let second = PendingMutation.logMealItem(.init(
            clientItemId: itemId, mealType: "lunch", mealDate: "2025-01-01",
            productId: UUID(), productName: "Arroz", brand: nil,
            servings: 2, calories: 400, proteinG: 8, carbsG: 88, fatG: 2))
        await q.enqueue(first)
        await q.enqueue(second)
        let all = await q.peekAll()
        #expect(all.count == 1, "same id must not create two queue entries")
        // The newer payload wins (servings 2).
        if case .logMealItem(let p) = all.first { #expect(p.servings == 2) }
        else { Issue.record("expected a logMealItem") }
    }

    @Test("drain stops on first failure, preserves order")
    func drain_stopsOnFailure() async {
        let q = makeQueue()
        let a = PendingMutation.deleteMealItem(.init(id: UUID()))
        let b = PendingMutation.deleteMealItem(.init(id: UUID()))
        let c = PendingMutation.deleteMealItem(.init(id: UUID()))
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
        await q.enqueue(.deleteMealItem(.init(id: UUID())))
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
        // Replay is owner-guarded: register the default test owner so the
        // defaulted-owner mutation below counts as the current user's.
        sut.setCurrentUserProvider { PendingMutationTestOwner.shared }

        let counter = AtomicCounter()
        MockURLProtocol.handler = { req in
            counter.increment()
            let resp = HTTPURLResponse(url: req.url!, statusCode: 201, httpVersion: "1.1",
                                       headerFields: ["Content-Type": "application/json"])!
            return (resp, Data(Self.mealLogResponseJSON.utf8))
        }

        await sut.enqueue(.logMealItem(.init(
            clientItemId: UUID(),
            mealType: "breakfast",
            mealDate: "2025-01-01",
            productId: UUID(),
            productName: "Avena",
            brand: "Quaker",
            servings: 1,
            calories: 150, proteinG: 5, carbsG: 27, fatG: 3
        )))

        #expect(counter.value == 1)
        #expect(await sut.pendingCount() == 0)
    }

    @MainActor
    @Test("logMealItem replays POST /api/v1/meals/log with client_item_id")
    func logMealItem_postsRealEndpointWithClientId() async {
        let session = MockURLProtocol.makeSession()
        let api = APIClient(baseURL: URL(string: "http://test.local")!, session: session)
        let suite = "test.sync.\(UUID().uuidString)"
        let queue = OfflineQueue(storageKey: "q", defaults: UserDefaults(suiteName: suite)!)
        let reachability = Reachability(autoStart: false)
        reachability.setStatus(.online)
        let sut = SyncManager(api: api, queue: queue, reachability: reachability)
        sut.setCurrentUserProvider { PendingMutationTestOwner.shared }

        let clientItemId = UUID()
        nonisolated(unsafe) var capturedPath: String?
        nonisolated(unsafe) var capturedBody: Data?
        MockURLProtocol.handler = { req in
            capturedPath = req.url?.path
            capturedBody = req.bodyData()
            let resp = HTTPURLResponse(url: req.url!, statusCode: 201, httpVersion: "1.1",
                                       headerFields: ["Content-Type": "application/json"])!
            return (resp, Data(Self.mealLogResponseJSON.utf8))
        }

        await sut.enqueue(.logMealItem(.init(
            clientItemId: clientItemId,
            mealType: "lunch",
            mealDate: "2025-01-01",
            productId: UUID(),
            productName: "Arroz",
            brand: nil,
            servings: 1.5,
            calories: 300, proteinG: 6, carbsG: 66, fatG: 1
        )))

        #expect(capturedPath == "/api/v1/meals/log",
                "queued log must replay the real /meals/log route")
        let body = capturedBody ?? Data()
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        #expect(json?["client_item_id"] as? String == clientItemId.uuidString,
                "replay must carry client_item_id so the backend dedupes the retry")
        #expect(json?["meal_date"] as? String == "2025-01-01",
                "meal_date must stay a date-only string the backend `date` accepts")
        #expect(await sut.pendingCount() == 0)
    }

    @MainActor
    @Test("startObservingConnectivity drains a queue left over from a prior launch")
    func launchDrain_replaysLeftoverQueue() async {
        let session = MockURLProtocol.makeSession()
        let api = APIClient(baseURL: URL(string: "http://test.local")!, session: session)
        let suite = "test.sync.\(UUID().uuidString)"
        // Simulate a queue persisted by a PREVIOUS app session. Both queues
        // are built from the same suite NAME (a Sendable String) rather than
        // sharing one UserDefaults instance across actor hops.
        let preQueue = OfflineQueue(storageKey: "q", defaults: UserDefaults(suiteName: suite)!)
        await preQueue.enqueue(.deleteMealItem(.init(id: UUID())))
        #expect(await preQueue.peekAll().count == 1)

        let counter = AtomicCounter()
        MockURLProtocol.handler = { req in
            counter.increment()
            return (HTTPURLResponse(url: req.url!, statusCode: 204, httpVersion: "1.1", headerFields: nil)!, Data())
        }

        // New launch: online from the start, a SyncManager over the SAME store.
        let reachability = Reachability(autoStart: false)
        reachability.setStatus(.online)
        let freshQueue = OfflineQueue(storageKey: "q", defaults: UserDefaults(suiteName: suite)!)
        let sut = SyncManager(api: api, queue: freshQueue, reachability: reachability)
        sut.setCurrentUserProvider { PendingMutationTestOwner.shared }

        sut.startObservingConnectivity()   // must kick an immediate drain

        // Poll to quiescence rather than a fixed sleep: this both avoids
        // flakiness AND guarantees the fire-and-forget launch-drain Task has
        // finished before the test returns — so it can't leak a stray request
        // into the shared MockURLProtocol handler used by a later suite.
        await waitUntilDrained(sut)

        #expect(counter.value == 1, "leftover queue must be replayed at launch, not only on next reconnect")
        #expect(await sut.pendingCount() == 0)
    }

    /// Spin (bounded) until the manager's queue is empty. Used by tests whose
    /// drain is triggered by a fire-and-forget Task so we never assert against
    /// a half-finished drain or let it outlive the test.
    @MainActor
    private func waitUntilDrained(_ sut: SyncManager, maxTries: Int = 100) async {
        for _ in 0..<maxTries {
            if await sut.pendingCount() == 0 { return }
            try? await Task.sleep(nanoseconds: 10_000_000)   // 10ms
        }
    }

    @MainActor
    @Test("a confirmed background replay clears the local pendingSync flag")
    func drain_clearsLocalPendingSyncOnConfirm() async throws {
        let session = MockURLProtocol.makeSession()
        let api = APIClient(baseURL: URL(string: "http://test.local")!, session: session)
        let suite = "test.sync.\(UUID().uuidString)"
        let queue = OfflineQueue(storageKey: "q", defaults: UserDefaults(suiteName: suite)!)
        let reachability = Reachability(autoStart: false)
        reachability.setStatus(.offline)   // start offline so the enqueue stays queued
        let container = try PersistenceController.makeInMemory().container
        let ctx = ModelContext(container)
        let sut = SyncManager(api: api, queue: queue, reachability: reachability, context: ctx)
        sut.setCurrentUserProvider { PendingMutationTestOwner.shared }

        // Seed a local meal + item flagged pendingSync, matching a queued log.
        let itemId = UUID()
        let meal = MealEntity(id: UUID(), userId: UUID(),
                              mealType: MealType.breakfast.rawValue, mealDate: .now,
                              pendingSync: true, lastSyncedAt: nil)
        let item = MealItemEntity(id: itemId, productId: UUID(), productName: "Avena",
                                  brand: nil, servings: 1, calories: 150,
                                  proteinG: 5, carbsG: 27, fatG: 3,
                                  pendingSync: true, lastSyncedAt: nil)
        meal.items = [item]
        ctx.insert(meal)
        try ctx.save()

        await sut.enqueue(.logMealItem(.init(
            clientItemId: itemId, mealType: "breakfast", mealDate: "2025-01-01",
            productId: item.productId, productName: "Avena", brand: nil,
            servings: 1, calories: 150, proteinG: 5, carbsG: 27, fatG: 3)))
        #expect(await sut.pendingCount() == 1, "queued while offline")

        MockURLProtocol.handler = { req in
            (HTTPURLResponse(url: req.url!, statusCode: 201, httpVersion: "1.1",
                             headerFields: ["Content-Type": "application/json"])!,
             Data(Self.mealLogResponseJSON.utf8))
        }

        // Reconnect → drain → reconcile.
        reachability.setStatus(.online)
        await sut.drainNow()

        #expect(await sut.pendingCount() == 0)
        let storedItem = try ctx.fetch(FetchDescriptor<MealItemEntity>()).first
        #expect(storedItem?.pendingSync == false,
                "a confirmed background replay must clear the local item's pendingSync")
        let storedMeal = try ctx.fetch(FetchDescriptor<MealEntity>()).first
        #expect(storedMeal?.pendingSync == false,
                "parent meal flag clears once all its items are synced")
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

        await sut.enqueue(.deleteMealItem(.init(id: UUID())))

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
        sut.setCurrentUserProvider { PendingMutationTestOwner.shared }
        sut.startObservingConnectivity()

        // Enqueue 2 deletions while offline
        await sut.enqueue(.deleteMealItem(.init(id: UUID())))
        await sut.enqueue(.deleteMealItem(.init(id: UUID())))
        #expect(await sut.pendingCount() == 2)

        let counter = AtomicCounter()
        MockURLProtocol.handler = { req in
            counter.increment()
            return (HTTPURLResponse(url: req.url!, statusCode: 204, httpVersion: "1.1", headerFields: nil)!, Data())
        }

        // Flip online — listener should drain
        reachability.setStatus(.online)

        // Wait for the listener's fire-and-forget drain to finish (and not
        // outlive the test, which could leak a request into a later suite's
        // shared MockURLProtocol handler).
        await waitUntilDrained(sut)

        #expect(counter.value == 2)
        #expect(await sut.pendingCount() == 0)
    }

    /// The REAL backend `MealLogResponse` shape (app/schemas/meal.py) so the
    /// `MealDTO` decode in `SyncManager.execute` exercises the true contract.
    static let mealLogResponseJSON = #"""
    {
      "id": "00000000-0000-0000-0000-00000000ABCD",
      "user_id": "00000000-0000-0000-0000-000000000001",
      "meal_type": "breakfast",
      "meal_date": "2025-01-01",
      "items": []
    }
    """#
}

// MARK: - URLRequest body extraction (shared with MealServiceTests)

private extension URLRequest {
    /// Pulls the body bytes whether set as `httpBody` or `httpBodyStream`.
    /// URLProtocol mocking flips between the two depending on size.
    func bodyData() -> Data? {
        if let body = httpBody { return body }
        guard let stream = httpBodyStream else { return nil }
        var data = Data()
        let size = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        defer { buffer.deallocate() }
        stream.open(); defer { stream.close() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: size)
            if read > 0 { data.append(buffer, count: read) }
            if read <= 0 { break }
        }
        return data
    }
}
