//
//  NutritionServiceTests.swift
//  Slice 2.3 — verifies stale-while-revalidate, cache writes, no
//  duplicate fetch when cache is warm.
//

import Foundation
import SwiftData
import Testing
@testable import FitTracker

@Suite("NutritionService", .serialized)
struct NutritionServiceTests {

    init() { MockURLProtocol.reset() }

    @MainActor
    private func makeSUT() throws -> (NutritionService, ModelContext, UUID) {
        let container = try PersistenceController.makeInMemory().container
        let ctx = ModelContext(container)
        let uid = UUID()
        let api = APIClient(baseURL: URL(string: "http://test.local")!,
                            session: MockURLProtocol.makeSession())
        let sut = NutritionService(api: api, context: ctx, userId: { uid })
        return (sut, ctx, uid)
    }

    @MainActor
    @Test("Cold cache: fetches from network and writes to SwiftData")
    func cold_fetchesAndCaches() async throws {
        let (sut, ctx, _) = try makeSUT()

        let counter = AtomicCounter()
        MockURLProtocol.handler = { req in
            counter.increment()
            let json = #"""
            {"nutrition_date":"2026-04-25","total_calories":2100,"total_protein_g":150,"total_carbs_g":210,"total_fat_g":70,"total_fiber_g":30,"meals_count":3}
            """#
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "1.1", headerFields: nil)!, Data(json.utf8))
        }

        let result = try await sut.dailyNutrition(for: Date())
        #expect(result.calories == 2100)
        #expect(counter.value == 1)

        // SwiftData should now have one DailyNutritionEntity
        let stored = try ctx.fetch(FetchDescriptor<DailyNutritionEntity>())
        #expect(stored.count == 1)
        #expect(stored.first?.calories == 2100)
    }

    @MainActor
    @Test("Warm cache: returns cached immediately, refreshes in background")
    func warm_returnsCachedImmediately() async throws {
        let (sut, ctx, uid) = try makeSUT()
        // The request date is April 25 NOON LOCAL, so its local nutrition day is
        // April 25 in any timezone (review B10). The cache key is derived from
        // the local day via `LocalDay.cacheKeyDate`, which matches both the seed
        // below and the backend's "2026-04-25" (decoded as UTC-midnight) — so
        // the warm read hits regardless of test-runner timezone.
        let date = LocalDay.calendar()
            .date(from: DateComponents(year: 2026, month: 4, day: 25, hour: 12)) ?? Date()

        ctx.insert(DailyNutritionEntity(
            userId: uid, date: LocalDay.cacheKeyDate(for: date),
            calories: 1500, proteinG: 100, carbsG: 150, fatG: 50, fiberG: 20
        ))
        try ctx.save()

        let counter = AtomicCounter()
        MockURLProtocol.handler = { req in
            counter.increment()
            let json = #"""
            {"nutrition_date":"2026-04-25","total_calories":1900,"total_protein_g":140,"total_carbs_g":190,"total_fat_g":60,"total_fiber_g":25,"meals_count":2}
            """#
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "1.1", headerFields: nil)!, Data(json.utf8))
        }

        let firstResult = try await sut.dailyNutrition(for: date)
        #expect(firstResult.calories == 1500, "must return cached immediately")

        // Background refresh; give it time to upsert.
        try? await Task.sleep(nanoseconds: 300_000_000)
        #expect(counter.value == 1, "background refresh fired exactly once")

        let stored = try ctx.fetch(FetchDescriptor<DailyNutritionEntity>())
        #expect(stored.count == 1, "still one row — upsert, not insert")
        #expect(stored.first?.calories == 1900, "refreshed value persisted")
    }

    @MainActor
    @Test("Warm cache + offline: cached value still returned, no error propagated")
    func warm_offline_returnsCachedSilently() async throws {
        let (sut, ctx, uid) = try makeSUT()

        ctx.insert(DailyNutritionEntity(
            userId: uid, date: Date(),
            calories: 1500, proteinG: 100, carbsG: 150, fatG: 50, fiberG: 20
        ))
        try ctx.save()

        MockURLProtocol.handler = { req in
            // Simulate offline-style failure
            return (HTTPURLResponse(url: req.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!, Data())
        }

        // Caller gets the cached value despite the failed background refresh
        let result = try await sut.dailyNutrition(for: Date())
        #expect(result.calories == 1500)
    }

    @MainActor
    @Test("currentGoal upserts: second refresh updates the same row, doesn't duplicate")
    func goal_upserts() async throws {
        let (sut, ctx, _) = try makeSUT()

        let calls = AtomicCounter()
        MockURLProtocol.handler = { req in
            calls.increment()
            let json: String = (calls.value == 1)
                ? #"{"daily_calories":2400,"daily_protein_g":180,"daily_carbs_g":270,"daily_fat_g":70}"#
                : #"{"daily_calories":2200,"daily_protein_g":170,"daily_carbs_g":250,"daily_fat_g":65}"#
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
        }

        let first = try await sut.refreshGoal()
        #expect(first.dailyCalories == 2400)

        let second = try await sut.refreshGoal()
        #expect(second.dailyCalories == 2200)

        let stored = try ctx.fetch(FetchDescriptor<NutritionGoalEntity>())
        #expect(stored.count == 1, "upsert, not insert")
        #expect(stored.first?.dailyCalories == 2200)
    }
}
