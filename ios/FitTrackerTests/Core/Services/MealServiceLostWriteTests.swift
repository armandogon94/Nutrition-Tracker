//
//  MealServiceLostWriteTests.swift
//  Codex review #4 P2 — "lost-write window before enqueue".
//
//  The durable PendingMutation must be written BEFORE the network call is
//  attempted (and removed only on confirmed success), so a kill between the
//  local save and the network catch cannot lose the mutation. For deletes,
//  the tombstone must be queued BEFORE the local row is deleted.
//
//  Strategy: a backend FAILURE must leave the durable mutation queued
//  (proving it was written before, not inside, the now-failed catch path),
//  and a SUCCESS must leave nothing queued (proving the confirmed entry is
//  removed — no leak).
//

import Foundation
import SwiftData
import Testing
@testable import FitTracker

@Suite("MealService lost-write window", .serialized)
struct MealServiceLostWriteTests {

    init() { MockURLProtocol.reset() }

    @MainActor
    private func makeSUT() throws -> (MealService, ModelContext, OfflineQueue) {
        let session = MockURLProtocol.makeSession()
        let api = APIClient(baseURL: URL(string: "http://test.local")!,
                            tokenProvider: nil, session: session)
        let container = try PersistenceController.makeInMemory().container
        let context = ModelContext(container)
        let queue = OfflineQueue(storageKey: "q",
                                 defaults: UserDefaults(suiteName: "test.lostwrite.\(UUID().uuidString)")!)
        return (MealService(api: api, context: context, offlineQueue: queue), context, queue)
    }

    @MainActor
    @Test("log on success leaves nothing queued (durable entry removed after confirm)")
    func log_successLeavesNothingQueued() async throws {
        let (sut, _, queue) = try makeSUT()
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 201, httpVersion: "1.1",
                                       headerFields: ["Content-Type": "application/json"])!
            return (resp, Data(Self.mealLogResponseJSON.utf8))
        }

        let outcome = try await sut.logItemReturningOutcome(
            product: MockData.products.first!, servings: 1, mealType: .lunch,
            mealDate: Date(timeIntervalSince1970: 1_735_718_400), userId: UUID())

        #expect(outcome.state == .synced, "a 201 confirms the write")
        #expect(await queue.peekAll().isEmpty,
                "the durable entry written before the POST must be removed on confirm — no leak")
    }

    @MainActor
    @Test("log: a failure keeps the durable mutation (enqueue-before-network => no lost write)")
    func log_failureKeepsDurableMutation() async throws {
        let (sut, ctx, queue) = try makeSUT()
        MockURLProtocol.handler = { req in
            (HTTPURLResponse(url: req.url!, statusCode: 500, httpVersion: "1.1", headerFields: nil)!, Data())
        }
        let userId = UUID()
        let outcome = try await sut.logItemReturningOutcome(
            product: MockData.products.first!, servings: 1, mealType: .lunch,
            mealDate: Date(), userId: userId)

        #expect(outcome.state == .pendingSync)
        let queued = await queue.peekAll()
        #expect(queued.count == 1, "the write survived the failure because it was enqueued first")
        #expect(queued.first?.ownerId == userId, "queued mutation is stamped with the logging user")
        let stored = try ctx.fetch(FetchDescriptor<MealItemEntity>())
        #expect(stored.first?.pendingSync == true)
    }

    @MainActor
    @Test("delete queues a durable, owner-stamped tombstone before removing the local row")
    func delete_queuesTombstoneBeforeLocalDelete() async throws {
        let (sut, ctx, queue) = try makeSUT()
        let userId = UUID()
        let meal = MealEntity(id: UUID(), userId: userId,
                              mealType: MealType.lunch.rawValue, mealDate: .now,
                              pendingSync: false, lastSyncedAt: .now)
        let itemId = UUID()
        let item = MealItemEntity(id: itemId, productId: UUID(), productName: "Pan",
                                  brand: nil, servings: 1, calories: 80,
                                  proteinG: 3, carbsG: 15, fatG: 1)
        meal.items = [item]
        ctx.insert(meal)
        try ctx.save()

        // Backend DELETE fails so the tombstone must remain queued.
        MockURLProtocol.handler = { req in
            (HTTPURLResponse(url: req.url!, statusCode: 500, httpVersion: "1.1", headerFields: nil)!, Data())
        }

        try await sut.deleteItem(itemId, fromMeal: meal.id)

        #expect(try ctx.fetch(FetchDescriptor<MealItemEntity>()).isEmpty,
                "optimistic local delete still happens")
        let queued = await queue.peekAll()
        #expect(queued.count == 1, "a durable delete tombstone must survive the failure")
        #expect(queued.first?.id == itemId)
        #expect(queued.first?.ownerId == userId, "tombstone is stamped with the deleting user")
        if case .deleteMealItem = queued.first {} else {
            Issue.record("expected a .deleteMealItem tombstone")
        }
    }

    @MainActor
    @Test("delete: a failed local save removes the queued tombstone before rethrowing")
    func delete_localSaveFailure_removesTombstoneAndRethrows() async throws {
        // Codex review #5 P2: if the optimistic local delete's save() throws,
        // the tombstone queued just before it must NOT survive — otherwise a
        // later replay deletes the server item while the local row is still
        // present. The method must remove the tombstone and rethrow.
        let session = MockURLProtocol.makeSession()
        let api = APIClient(baseURL: URL(string: "http://test.local")!,
                            tokenProvider: nil, session: session)
        let container = try PersistenceController.makeInMemory().container
        let ctx = ModelContext(container)
        let queue = OfflineQueue(storageKey: "q",
                                 defaults: UserDefaults(suiteName: "test.lostwrite.\(UUID().uuidString)")!)
        // Inject a save hook that fails ONLY the local delete save.
        struct SaveBlewUp: Error {}
        let sut = MealService(api: api, context: ctx, offlineQueue: queue,
                              saveHook: { _ in throw SaveBlewUp() })

        let userId = UUID()
        let meal = MealEntity(id: UUID(), userId: userId,
                              mealType: MealType.lunch.rawValue, mealDate: .now,
                              pendingSync: false, lastSyncedAt: .now)
        let itemId = UUID()
        let item = MealItemEntity(id: itemId, productId: UUID(), productName: "Pan",
                                  brand: nil, servings: 1, calories: 80,
                                  proteinG: 3, carbsG: 15, fatG: 1)
        meal.items = [item]
        ctx.insert(meal)
        // Seed via the real context (the hook only intercepts MealService saves).
        try ctx.save()

        // The network must NEVER be reached: the local save fails first.
        let hits = AtomicCounter()
        MockURLProtocol.handler = { req in
            hits.increment()
            return (HTTPURLResponse(url: req.url!, statusCode: 204, httpVersion: "1.1", headerFields: nil)!, Data())
        }

        await #expect(throws: (any Error).self) {
            try await sut.deleteItem(itemId, fromMeal: meal.id)
        }

        #expect(await queue.peekAll().isEmpty,
                "a failed local delete must NOT leave a tombstone that could delete the server row later")
        #expect(hits.value == 0, "the backend delete must not run when the local delete failed")
    }

    @MainActor
    @Test("delete on success leaves no tombstone queued")
    func delete_successLeavesNoTombstone() async throws {
        let (sut, ctx, queue) = try makeSUT()
        let userId = UUID()
        let meal = MealEntity(id: UUID(), userId: userId,
                              mealType: MealType.lunch.rawValue, mealDate: .now,
                              pendingSync: false, lastSyncedAt: .now)
        let itemId = UUID()
        let item = MealItemEntity(id: itemId, productId: UUID(), productName: "Pan",
                                  brand: nil, servings: 1, calories: 80,
                                  proteinG: 3, carbsG: 15, fatG: 1)
        meal.items = [item]
        ctx.insert(meal)
        try ctx.save()

        MockURLProtocol.handler = { req in
            (HTTPURLResponse(url: req.url!, statusCode: 204, httpVersion: "1.1", headerFields: nil)!, Data())
        }

        try await sut.deleteItem(itemId, fromMeal: meal.id)

        #expect(try ctx.fetch(FetchDescriptor<MealItemEntity>()).isEmpty)
        #expect(await queue.peekAll().isEmpty,
                "a confirmed delete removes the durable tombstone — no leak")
    }

    private static let mealLogResponseJSON = #"""
    {"id":"00000000-0000-0000-0000-00000000ABCD","user_id":"00000000-0000-0000-0000-000000000001","meal_type":"lunch","meal_date":"2025-01-01","items":[]}
    """#
}
