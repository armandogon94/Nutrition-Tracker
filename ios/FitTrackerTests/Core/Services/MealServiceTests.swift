//
//  MealServiceTests.swift
//  Slice 3.1: validates the optimistic-write contract for MealService.
//  Each test runs against an in-memory SwiftData container plus a
//  MockURLProtocol-backed APIClient — no network, no shared state.
//

import Foundation
import SwiftData
import Testing
@testable import FitTracker

@Suite("MealService", .serialized)
struct MealServiceTests {

    init() { MockURLProtocol.reset() }

    @MainActor
    private func makeSUT() throws -> (MealService, ModelContext) {
        let session = MockURLProtocol.makeSession()
        let api = APIClient(baseURL: URL(string: "http://test.local")!,
                            tokenProvider: nil,
                            session: session)
        let container = try PersistenceController.makeInMemory().container
        let context = ModelContext(container)
        let service = MealService(api: api, context: context)
        return (service, context)
    }

    // Mirrors the REAL backend `MealLogResponse` (app/schemas/meal.py): the
    // parent meal with snapshot items. `meal_date` is a Pydantic `date`, so it
    // serializes date-only ("yyyy-MM-dd"), NOT a datetime — and each item is a
    // flat snapshot (`MealItemLogResponse`), NOT a nested `product`. Using the
    // true shape here means these tests validate the actual contract.
    private static let serverItemJSON = #"""
    {
      "id": "00000000-0000-0000-0000-00000000ABCD",
      "user_id": "00000000-0000-0000-0000-000000000001",
      "meal_type": "breakfast",
      "meal_date": "2025-01-01",
      "items": [
        {
          "id": "00000000-0000-0000-0000-00000000FFFF",
          "product_id": "00000000-0000-0000-0000-000000000010",
          "product_name": "Avena tradicional",
          "brand": "Quaker",
          "servings": 1.0,
          "calories": 150,
          "protein_g": 5,
          "carbs_g": 27,
          "fat_g": 3
        }
      ]
    }
    """#

    @MainActor
    @Test("logItem inserts immediately (pendingSync=true) and clears the flag on success")
    func logItem_optimisticInsertThenSync() async throws {
        let (sut, ctx) = try makeSUT()

        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200,
                                       httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
            return (resp, Data(Self.serverItemJSON.utf8))
        }

        let userId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let product = MockData.products.first!

        let item = try await sut.logItem(
            product: product,
            servings: 1.0,
            mealType: .breakfast,
            mealDate: Date(timeIntervalSince1970: 1_735_718_400),
            userId: userId
        )
        #expect(item.productName == product.name)

        // After the API succeeds the entity should exist in SwiftData with pendingSync == false.
        let stored = try ctx.fetch(FetchDescriptor<MealItemEntity>())
        #expect(stored.count == 1)
        #expect(stored.first?.pendingSync == false,
                "successful sync must clear pendingSync")
        #expect(stored.first?.calories == product.caloriesPerServing)
    }

    @MainActor
    @Test("logItem sends meal_date as a date-only string the backend `date` field accepts")
    func logItem_sendsDateOnlyMealDate() async throws {
        let (sut, _) = try makeSUT()

        // Capture the outgoing request body so we can inspect what actually
        // goes on the wire. The backend `MealLogRequest.meal_date` is a Pydantic
        // `date`, which REJECTS a full ISO8601 datetime with a non-zero time
        // (422). So the body must carry "2025-01-01", never "2025-01-01T…Z".
        nonisolated(unsafe) var capturedBody: Data?
        MockURLProtocol.handler = { req in
            capturedBody = req.bodyStreamData()
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200,
                                       httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
            return (resp, Data(Self.serverItemJSON.utf8))
        }

        let userId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        // 2025-01-01T08:00:00Z — a deliberately NON-midnight instant so a
        // datetime encoding would carry a time component and fail the backend.
        let mealDate = Date(timeIntervalSince1970: 1_735_718_400)

        _ = try await sut.logItem(
            product: MockData.products.first!,
            servings: 1.0,
            mealType: .breakfast,
            mealDate: mealDate,
            userId: userId
        )

        let body = try #require(capturedBody, "request body should have been captured")
        let json = try #require(
            try JSONSerialization.jsonObject(with: body) as? [String: Any],
            "request body should be a JSON object"
        )
        let mealDateField = try #require(json["meal_date"] as? String,
                                         "meal_date must be present as a string")
        #expect(mealDateField == "2025-01-01",
                "meal_date must be a date-only 'yyyy-MM-dd' string (got \(mealDateField))")
        #expect(!mealDateField.contains("T"),
                "meal_date must not be a datetime — the backend `date` field 422s on a time component")
        // client_item_id must be sent for idempotent offline-queue replay.
        #expect(json["client_item_id"] is String,
                "client_item_id must be sent so the backend can dedupe retried writes")
    }

    @MainActor
    @Test("logItem keeps the row but flags it pendingSync on backend error")
    func logItem_revertsOnApiError() async throws {
        let (sut, ctx) = try makeSUT()

        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 500,
                                       httpVersion: "HTTP/1.1",
                                       headerFields: nil)!
            return (resp, Data())
        }

        let userId = UUID()
        let product = MockData.products.first!

        // The call surfaces an error to the caller, but the optimistic row
        // remains in SwiftData with pendingSync=true so the offline queue
        // can retry later. We do NOT roll back — losing user input is
        // worse than a stale flag.
        await #expect(throws: (any Error).self) {
            _ = try await sut.logItem(
                product: product,
                servings: 1,
                mealType: .lunch,
                mealDate: Date(),
                userId: userId
            )
        }

        let stored = try ctx.fetch(FetchDescriptor<MealItemEntity>())
        #expect(stored.count == 1, "row remains after API failure")
        #expect(stored.first?.pendingSync == true,
                "API failure must leave pendingSync=true so retry queue picks it up")
    }

    @MainActor
    @Test("logItem reuses an existing meal of the same type/date")
    func logItem_reusesExistingMeal() async throws {
        let (sut, ctx) = try makeSUT()
        let userId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

        // Pre-seed a Meal so the second call should attach to it instead
        // of creating a sibling.
        let mealDate = Date(timeIntervalSince1970: 1_735_718_400)
        let existing = MealEntity(id: UUID(), userId: userId,
                                   mealType: MealType.breakfast.rawValue,
                                   mealDate: mealDate,
                                   pendingSync: false,
                                   lastSyncedAt: .now)
        ctx.insert(existing)
        try ctx.save()

        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200,
                                       httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
            return (resp, Data(Self.serverItemJSON.utf8))
        }

        _ = try await sut.logItem(
            product: MockData.products.first!,
            servings: 1,
            mealType: .breakfast,
            mealDate: mealDate,
            userId: userId
        )

        let meals = try ctx.fetch(FetchDescriptor<MealEntity>())
        #expect(meals.count == 1, "logItem must not create a duplicate parent meal")
        #expect(meals.first?.items.count == 1)
    }

    @MainActor
    @Test("recentMeals reads SwiftData and returns Meal structs")
    func recentMeals_readsLocalCache() async throws {
        let (sut, ctx) = try makeSUT()

        let userId = UUID()
        let meal = MealEntity(id: UUID(), userId: userId,
                              mealType: MealType.dinner.rawValue,
                              mealDate: .now,
                              pendingSync: false,
                              lastSyncedAt: .now)
        let item = MealItemEntity(id: UUID(), productId: UUID(),
                                  productName: "Pollo asado", brand: nil,
                                  servings: 1.5, calories: 247.5,
                                  proteinG: 49.5, carbsG: 0, fatG: 5.4)
        meal.items = [item]
        ctx.insert(meal)
        try ctx.save()

        let meals = try await sut.recentMeals(for: .now, userId: userId)
        #expect(meals.count == 1)
        #expect(meals.first?.items.first?.productName == "Pollo asado")
    }
}

// MARK: - URLRequest body extraction

private extension URLRequest {
    /// Pulls the body bytes regardless of whether they were set as
    /// `httpBody` or via `httpBodyStream`. URLProtocol mocking flips between
    /// the two depending on size, so request-body assertions must handle both.
    func bodyStreamData() -> Data? {
        if let body = httpBody { return body }
        guard let stream = httpBodyStream else { return nil }
        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        stream.open()
        defer { stream.close() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read > 0 { data.append(buffer, count: read) }
            if read <= 0 { break }
        }
        return data
    }
}
