//
//  MealPlanServiceTests.swift
//  Slice 4.1: validates the backend-backed + SwiftData-cached MealPlanService.
//  Each test runs against an in-memory SwiftData container plus a
//  MockURLProtocol-backed APIClient — no network, no shared state.
//
//  Backend contract mirrored here (app/api/v1/meal_plans.py, prefix
//  /api/v1/meal-plans):
//    POST   /api/v1/meal-plans                                  -> MealPlanResponse
//    GET    /api/v1/meal-plans/{planId}                         -> MealPlanResponse
//    POST   /api/v1/meal-plans/{planId}/items                   -> MealPlanItemResponse
//    DELETE /api/v1/meal-plans/{planId}/items/{itemId}          -> 204
//    GET    /api/v1/meal-plans/{planId}/shopping-list           -> ShoppingListResponse
//    PATCH  /api/v1/meal-plans/shopping-lists/{listId}/items/{itemId}/check -> {id, is_checked}
//

import Foundation
import SwiftData
import Testing
@testable import FitTracker

@Suite("MealPlanService", .serialized)
struct MealPlanServiceTests {

    init() { MockURLProtocol.reset() }

    @MainActor
    private func makeSUT() throws -> (MealPlanService, ModelContext) {
        let session = MockURLProtocol.makeSession()
        let api = APIClient(baseURL: URL(string: "http://test.local")!,
                            tokenProvider: nil,
                            session: session)
        let container = try PersistenceController.makeInMemory().container
        let context = ModelContext(container)
        let service = MealPlanService(api: api, context: context)
        return (service, context)
    }

    private static let planId = "00000000-0000-0000-0000-0000000000A1"
    private static let userId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    /// MealPlanResponse JSON with one breakfast item (Monday).
    private static func planJSON(items: String = "") -> String {
        #"""
        {
          "id": "\#(planId)",
          "user_id": "00000000-0000-0000-0000-000000000001",
          "name": "Semana del 20 abr",
          "week_start_date": "2026-04-20",
          "notes": null,
          "is_template": false,
          "items": [\#(items)],
          "created_at": "2026-04-20T08:00:00Z"
        }
        """#
    }

    private static func itemJSON(id: String,
                                 day: Int,
                                 mealType: String,
                                 productName: String,
                                 servings: Double = 1.0) -> String {
        #"""
        {
          "id": "\#(id)",
          "product_id": "00000000-0000-0000-0000-000000000010",
          "day_of_week": \#(day),
          "meal_type": "\#(mealType)",
          "quantity_servings": \#(servings),
          "quantity_grams": null,
          "product": {
            "id": "00000000-0000-0000-0000-000000000010",
            "barcode": "0001",
            "name": "\#(productName)",
            "brand": "Quaker",
            "serving_size_g": 40.0,
            "calories": 150.0,
            "protein_g": 5.0,
            "carbs_g": 27.0,
            "fat_g": 3.0,
            "fiber_g": 4.0,
            "source": "seed",
            "image_url": null,
            "created_at": "2026-04-20T08:00:00Z"
          },
          "created_at": "2026-04-20T08:00:00Z"
        }
        """#
    }

    // MARK: - Task 4.1 RED tests

    @MainActor
    @Test("createPlan POSTs to backend and caches the MealPlan in SwiftData")
    func mealPlan_createsWeeklyPlan() async throws {
        let (sut, ctx) = try makeSUT()

        MockURLProtocol.handler = { req in
            #expect(req.httpMethod == "POST")
            #expect(req.url?.path == "/api/v1/meal-plans")
            let resp = HTTPURLResponse(url: req.url!, statusCode: 201,
                                       httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
            return (resp, Data(Self.planJSON().utf8))
        }

        let weekStart = ISO8601DateFormatter().date(from: "2026-04-20T00:00:00Z")!
        let plan = try await sut.createPlan(weekStartDate: weekStart,
                                            userId: Self.userId,
                                            name: "Semana del 20 abr")

        #expect(plan.id == UUID(uuidString: Self.planId))

        // Cached locally so currentPlan() can read it back offline.
        let stored = try ctx.fetch(FetchDescriptor<MealPlanEntity>())
        #expect(stored.count == 1)
        #expect(stored.first?.id == UUID(uuidString: Self.planId))
    }

    @MainActor
    @Test("addItem POSTs the item and appends it to the cached plan")
    func mealPlan_addItemAppendsToPlan() async throws {
        let (sut, ctx) = try makeSUT()

        // Seed a cached plan so addItem has a parent to attach to.
        let planUUID = UUID(uuidString: Self.planId)!
        let planEntity = MealPlanEntity(id: planUUID, userId: Self.userId,
                                        weekStartDate: .now,
                                        pendingSync: false, lastSyncedAt: .now)
        ctx.insert(planEntity)
        try ctx.save()

        let serverItemId = "00000000-0000-0000-0000-0000000000B1"
        MockURLProtocol.handler = { req in
            #expect(req.httpMethod == "POST")
            #expect(req.url?.path == "/api/v1/meal-plans/\(Self.planId)/items")
            let resp = HTTPURLResponse(url: req.url!, statusCode: 201,
                                       httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
            let body = Self.itemJSON(id: serverItemId, day: 0,
                                     mealType: "breakfast",
                                     productName: "Avena tradicional")
            return (resp, Data(body.utf8))
        }

        let product = MockData.products.first!
        let item = try await sut.addItem(toPlan: planUUID,
                                         dayIndex: 0,
                                         mealType: .breakfast,
                                         product: product,
                                         servings: 1.0)

        #expect(item.dayIndex == 0)
        #expect(item.mealType == .breakfast)

        let storedItems = try ctx.fetch(FetchDescriptor<MealPlanItemEntity>())
        #expect(storedItems.count == 1)
        #expect(storedItems.first?.dayIndex == 0)
        #expect(storedItems.first?.plan?.id == planUUID)
    }

    @MainActor
    @Test("moveItem updates the cached item's day/slot and re-issues to backend")
    func mealPlan_moveItemBetweenDaysUpdatesBackend() async throws {
        let (sut, ctx) = try makeSUT()

        let planUUID = UUID(uuidString: Self.planId)!
        let planEntity = MealPlanEntity(id: planUUID, userId: Self.userId,
                                        weekStartDate: .now,
                                        pendingSync: false, lastSyncedAt: .now)
        let itemUUID = UUID(uuidString: "00000000-0000-0000-0000-0000000000C1")!
        let itemEntity = MealPlanItemEntity(id: itemUUID, dayIndex: 0,
                                            mealType: MealType.breakfast.rawValue,
                                            productName: "Avena tradicional",
                                            servings: 1.0, pendingSync: false)
        itemEntity.plan = planEntity
        planEntity.items = [itemEntity]
        ctx.insert(planEntity)
        try ctx.save()

        // Backend: DELETE old item (204) then POST recreated item (201).
        // moveItem needs a known product_id to recreate server-side; the
        // service learns it when a plan's items arrive from the server, so
        // we prime that path by adding the item through the service first.
        let primeItemId = "00000000-0000-0000-0000-0000000000C1"
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 201,
                                       httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
            let body = Self.itemJSON(id: primeItemId, day: 0,
                                     mealType: "breakfast",
                                     productName: "Avena tradicional")
            return (resp, Data(body.utf8))
        }
        // Replace the pre-seeded item with one created via the service so
        // its product_id is tracked. (Remove the seeded duplicate first.)
        ctx.delete(itemEntity)
        try ctx.save()
        let added = try await sut.addItem(toPlan: planUUID, dayIndex: 0,
                                          mealType: .breakfast,
                                          product: MockData.products.first!,
                                          servings: 1.0)

        let sawDelete = Counter()
        let newServerId = "00000000-0000-0000-0000-0000000000C2"
        MockURLProtocol.handler = { req in
            if req.httpMethod == "DELETE" {
                sawDelete.increment()
                let resp = HTTPURLResponse(url: req.url!, statusCode: 204,
                                           httpVersion: "HTTP/1.1", headerFields: nil)!
                return (resp, Data())
            }
            // POST recreate on the new day (Wednesday=2) / dinner.
            #expect(req.httpMethod == "POST")
            let resp = HTTPURLResponse(url: req.url!, statusCode: 201,
                                       httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
            let body = Self.itemJSON(id: newServerId, day: 2,
                                     mealType: "dinner",
                                     productName: "Avena tradicional")
            return (resp, Data(body.utf8))
        }

        try await sut.moveItem(added.id, toDay: 2, mealType: .dinner, inPlan: planUUID)

        #expect(sawDelete.value >= 1, "move must delete the old item server-side")

        // The cache now reflects the new day/slot (single item, not duplicated).
        let storedItems = try ctx.fetch(FetchDescriptor<MealPlanItemEntity>())
        #expect(storedItems.count == 1, "move must not leave a duplicate item")
        #expect(storedItems.first?.dayIndex == 2)
        #expect(storedItems.first?.mealType == MealType.dinner.rawValue)
    }

    @MainActor
    @Test("generateShoppingList groups items by category and caches them")
    func shoppingList_generatedFromMealPlanGroupsByCategory() async throws {
        let (sut, ctx) = try makeSUT()
        let planUUID = UUID(uuidString: Self.planId)!

        let listId = "00000000-0000-0000-0000-0000000000D1"
        let shoppingJSON = #"""
        {
          "id": "\#(listId)",
          "name": "Lista - Semana",
          "meal_plan_id": "\#(Self.planId)",
          "generated_at": "2026-04-20T09:00:00Z",
          "items": [
            { "id": "00000000-0000-0000-0000-0000000000E1", "ingredient_name": "Pechuga de pollo", "quantity": 500.0, "unit": "g", "category": "Carnes y Aves", "is_checked": false },
            { "id": "00000000-0000-0000-0000-0000000000E2", "ingredient_name": "Leche entera", "quantity": 1000.0, "unit": "g", "category": "Lácteos y Huevos", "is_checked": false },
            { "id": "00000000-0000-0000-0000-0000000000E3", "ingredient_name": "Avena", "quantity": 200.0, "unit": "g", "category": "Granos y Cereales", "is_checked": false }
          ]
        }
        """#

        MockURLProtocol.handler = { req in
            #expect(req.httpMethod == "GET")
            #expect(req.url?.path == "/api/v1/meal-plans/\(Self.planId)/shopping-list")
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200,
                                       httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
            return (resp, Data(shoppingJSON.utf8))
        }

        let items = try await sut.generateShoppingList(forPlan: planUUID, userId: Self.userId)
        #expect(items.count == 3)

        // Backend Spanish category strings map onto the iOS ShoppingCategory enum.
        let categories = Set(items.map(\.category))
        #expect(categories.contains(.proteins))
        #expect(categories.contains(.dairy))
        #expect(categories.contains(.grains))

        // Quantity formatted into the display string (number + unit).
        let pollo = items.first { $0.name == "Pechuga de pollo" }
        #expect(pollo?.quantity.contains("500") == true)

        // Cached so ShoppingListView can read offline.
        let storedLists = try ctx.fetch(FetchDescriptor<ShoppingListEntity>())
        #expect(storedLists.count == 1)
        let storedItems = try ctx.fetch(FetchDescriptor<ShoppingListItemEntity>())
        #expect(storedItems.count == 3)
    }

    @MainActor
    @Test("setChecked persists check state to SwiftData and PATCHes the backend")
    func shoppingList_checkStatePersists() async throws {
        let (sut, ctx) = try makeSUT()

        // Seed a cached list + item.
        let listUUID = UUID(uuidString: "00000000-0000-0000-0000-0000000000D1")!
        let itemUUID = UUID(uuidString: "00000000-0000-0000-0000-0000000000E1")!
        let listEntity = ShoppingListEntity(id: listUUID,
                                            mealPlanId: UUID(uuidString: Self.planId)!,
                                            generatedAt: .now)
        let itemEntity = ShoppingListItemEntity(id: itemUUID, name: "Pechuga de pollo",
                                                quantity: "500 g",
                                                category: ShoppingCategory.proteins.rawValue,
                                                checked: false)
        itemEntity.list = listEntity
        listEntity.items = [itemEntity]
        ctx.insert(listEntity)
        try ctx.save()

        MockURLProtocol.handler = { req in
            #expect(req.httpMethod == "PATCH")
            #expect(req.url?.path == "/api/v1/meal-plans/shopping-lists/\(listUUID.uuidString)/items/\(itemUUID.uuidString)/check")
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200,
                                       httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
            let body = #"{ "id": "\#(itemUUID.uuidString)", "is_checked": true }"#
            return (resp, Data(body.utf8))
        }

        try await sut.setChecked(itemUUID, checked: true, listId: listUUID)

        let stored = try ctx.fetch(FetchDescriptor<ShoppingListItemEntity>())
        #expect(stored.first?.checked == true, "check state must persist to SwiftData")
    }

    // MARK: - Slice 4 B1 regression — no server-side data loss on cold-launch move

    @MainActor
    @Test("moving a server-sourced item without a known product_id never DELETEs it (no data loss)")
    func mealPlan_moveColdCacheItemDoesNotDeleteOrLose() async throws {
        let (sut, ctx) = try makeSUT()

        // Simulate the post-relaunch state: a plan + item read straight from
        // the SwiftData cache. Crucially there was NO prior addItem(), so the
        // in-memory productIdByItem map has no entry for this item — exactly
        // the cold-cache branch in moveItem. The bug: the old code DELETEd the
        // server row and cleared pendingSync, recreating nothing → the item
        // was lost server-side forever, even online.
        let planUUID = UUID(uuidString: Self.planId)!
        let planEntity = MealPlanEntity(id: planUUID, userId: Self.userId,
                                        weekStartDate: .now,
                                        pendingSync: false, lastSyncedAt: .now)
        let itemUUID = UUID(uuidString: "00000000-0000-0000-0000-0000000000CA")!
        let itemEntity = MealPlanItemEntity(id: itemUUID, dayIndex: 0,
                                            mealType: MealType.breakfast.rawValue,
                                            productName: "Avena tradicional",
                                            servings: 1.0, pendingSync: false)
        itemEntity.plan = planEntity
        planEntity.items = [itemEntity]
        ctx.insert(planEntity)
        try ctx.save()

        // The backend is fully online and would happily 204 a DELETE — so if
        // the service issues one, this records it and the test fails.
        let sawDelete = Counter()
        MockURLProtocol.handler = { req in
            if req.httpMethod == "DELETE" {
                sawDelete.increment()
            }
            let resp = HTTPURLResponse(url: req.url!, statusCode: 204,
                                       httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, Data())
        }

        // Move the item. With no known product_id the service can't recreate
        // it server-side, so it must keep the optimistic local move pending
        // and NOT delete the server row.
        try await sut.moveItem(itemUUID, toDay: 3, mealType: .lunch, inPlan: planUUID)

        #expect(sawDelete.value == 0,
                "must not DELETE a server item it cannot recreate (would lose it)")

        // The item still exists locally, moved, and flagged for later sync.
        let stored = try ctx.fetch(FetchDescriptor<MealPlanItemEntity>())
        #expect(stored.count == 1, "item must not be lost")
        #expect(stored.first?.dayIndex == 3)
        #expect(stored.first?.mealType == MealType.lunch.rawValue)
        #expect(stored.first?.pendingSync == true,
                "pending flag stays set so the move can replay once product_id is known")
    }

    @MainActor
    @Test("currentPlan repopulates product ids from the server so a later move recreates server-side")
    func mealPlan_currentPlanReconcilesProductIdsForMove() async throws {
        let (sut, ctx) = try makeSUT()

        // Post-relaunch cache: plan + one item, empty in-memory product map.
        let planUUID = UUID(uuidString: Self.planId)!
        let itemUUID = UUID(uuidString: "00000000-0000-0000-0000-0000000000C1")!
        let planEntity = MealPlanEntity(id: planUUID, userId: Self.userId,
                                        weekStartDate: .now,
                                        pendingSync: false, lastSyncedAt: .now)
        let itemEntity = MealPlanItemEntity(id: itemUUID, dayIndex: 0,
                                            mealType: MealType.breakfast.rawValue,
                                            productName: "Avena tradicional",
                                            servings: 1.0, pendingSync: false)
        itemEntity.plan = planEntity
        planEntity.items = [itemEntity]
        ctx.insert(planEntity)
        try ctx.save()

        // currentPlan() should GET the plan to recover each item's product_id.
        // The server item id matches the cached row so the map keys line up.
        MockURLProtocol.handler = { req in
            #expect(req.httpMethod == "GET")
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200,
                                       httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
            let item = Self.itemJSON(id: itemUUID.uuidString, day: 0,
                                     mealType: "breakfast",
                                     productName: "Avena tradicional")
            return (resp, Data(Self.planJSON(items: item).utf8))
        }
        _ = try await sut.currentPlan()

        // Now a move HAS a product_id, so it deletes the old + recreates it.
        let sawDelete = Counter()
        let sawPost = Counter()
        let newServerId = "00000000-0000-0000-0000-0000000000C2"
        MockURLProtocol.handler = { req in
            if req.httpMethod == "DELETE" {
                sawDelete.increment()
                let resp = HTTPURLResponse(url: req.url!, statusCode: 204,
                                           httpVersion: "HTTP/1.1", headerFields: nil)!
                return (resp, Data())
            }
            sawPost.increment()
            let resp = HTTPURLResponse(url: req.url!, statusCode: 201,
                                       httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
            let body = Self.itemJSON(id: newServerId, day: 2, mealType: "dinner",
                                     productName: "Avena tradicional")
            return (resp, Data(body.utf8))
        }
        try await sut.moveItem(itemUUID, toDay: 2, mealType: .dinner, inPlan: planUUID)

        #expect(sawDelete.value >= 1, "reconciled product_id lets the move delete server-side")
        #expect(sawPost.value >= 1, "and recreate the item on the new day")
        let stored = try ctx.fetch(FetchDescriptor<MealPlanItemEntity>())
        #expect(stored.count == 1, "no duplicate after recreate")
        #expect(stored.first?.dayIndex == 2)
        #expect(stored.first?.pendingSync == false, "synced after successful recreate")
    }

    // MARK: - Task 4.6 RED tests — offline correctness

    @MainActor
    @Test("move persists the new day locally even when the backend is unreachable")
    func mealPlan_moveSurvivesOfflineBackend() async throws {
        let (sut, ctx) = try makeSUT()

        let planUUID = UUID(uuidString: Self.planId)!
        let planEntity = MealPlanEntity(id: planUUID, userId: Self.userId,
                                        weekStartDate: .now,
                                        pendingSync: false, lastSyncedAt: .now)
        ctx.insert(planEntity)
        try ctx.save()

        // Add an item so its product_id is tracked, then knock the network
        // out for the subsequent move.
        let primeItemId = "00000000-0000-0000-0000-0000000000F1"
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 201,
                                       httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
            return (resp, Data(Self.itemJSON(id: primeItemId, day: 1,
                                             mealType: "lunch",
                                             productName: "Arroz").utf8))
        }
        let added = try await sut.addItem(toPlan: planUUID, dayIndex: 1,
                                          mealType: .lunch,
                                          product: MockData.products.first!,
                                          servings: 1.0)

        // Simulate offline: every request fails.
        MockURLProtocol.handler = { _ in throw APIError.offline }

        // The move throws (backend unreachable) but the local cache must
        // already reflect the new day/slot — losing the user's drag is
        // unacceptable (offline-first, ADR-0004 §4).
        await #expect(throws: (any Error).self) {
            try await sut.moveItem(added.id, toDay: 4, mealType: .dinner, inPlan: planUUID)
        }

        let stored = try ctx.fetch(FetchDescriptor<MealPlanItemEntity>())
        #expect(stored.count == 1)
        #expect(stored.first?.dayIndex == 4, "optimistic move persists offline")
        #expect(stored.first?.mealType == MealType.dinner.rawValue)
        #expect(stored.first?.pendingSync == true, "pending flag set for later retry")
    }

    @MainActor
    @Test("check state persists locally even when the PATCH fails")
    func shoppingList_checkSurvivesOfflineBackend() async throws {
        let (sut, ctx) = try makeSUT()

        let listUUID = UUID(uuidString: "00000000-0000-0000-0000-0000000000D9")!
        let itemUUID = UUID(uuidString: "00000000-0000-0000-0000-0000000000E9")!
        let listEntity = ShoppingListEntity(id: listUUID,
                                            mealPlanId: UUID(uuidString: Self.planId)!,
                                            generatedAt: .now)
        let itemEntity = ShoppingListItemEntity(id: itemUUID, name: "Huevos",
                                                quantity: "12 pzas",
                                                category: ShoppingCategory.dairy.rawValue,
                                                checked: false)
        itemEntity.list = listEntity
        listEntity.items = [itemEntity]
        ctx.insert(listEntity)
        try ctx.save()

        MockURLProtocol.handler = { _ in throw APIError.offline }

        await #expect(throws: (any Error).self) {
            try await sut.setChecked(itemUUID, checked: true, listId: listUUID)
        }

        let stored = try ctx.fetch(FetchDescriptor<ShoppingListItemEntity>())
        #expect(stored.first?.checked == true, "check persists locally while offline")
        #expect(stored.first?.pendingSync == true, "pending flag set for later retry")
    }

    @MainActor
    @Test("currentPlan reads the most recent plan from the SwiftData cache")
    func mealPlan_currentPlanReadsCache() async throws {
        let (sut, ctx) = try makeSUT()

        let older = MealPlanEntity(id: UUID(), userId: Self.userId,
                                   weekStartDate: Date(timeIntervalSince1970: 1_000_000),
                                   pendingSync: false, lastSyncedAt: .now)
        let newer = MealPlanEntity(id: UUID(), userId: Self.userId,
                                   weekStartDate: Date(timeIntervalSince1970: 2_000_000),
                                   pendingSync: false, lastSyncedAt: .now)
        ctx.insert(older)
        ctx.insert(newer)
        try ctx.save()

        let plan = try await sut.currentPlan()
        #expect(plan?.id == newer.id, "currentPlan returns the latest week")
    }
}

/// Lock-guarded counter so a `@Sendable` MockURLProtocol handler can record
/// how many times it was hit without tripping Swift 6 data-race checks.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return _value }
    func increment() { lock.lock(); _value += 1; lock.unlock() }
}
