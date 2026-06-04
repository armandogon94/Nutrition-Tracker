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
