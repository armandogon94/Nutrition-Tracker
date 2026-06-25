//
//  MockMealPlanningServiceTests.swift
//  Slice 4: smoke-tests the in-memory planning mock so previews/tests that
//  depend on it stay honest as the protocol evolves.
//

import Foundation
import Testing
@testable import FitTracker

@Suite("MockMealPlanningService", .serialized)
struct MockMealPlanningServiceTests {

    @MainActor
    @Test("addItem then moveItem mutate the in-session plan")
    func addThenMove() async throws {
        let sut = MockMealPlanningService()
        let week = Date.now
        let userId = UUID()
        let plan = try await sut.createPlan(weekStartDate: week, userId: userId, name: "Test")

        let product = MockData.products.first!
        let item = try await sut.addItem(toPlan: plan.id, dayIndex: 0,
                                         mealType: .breakfast, product: product, servings: 2)
        let afterAdd = try await sut.currentPlan(forWeek: week, userId: userId)
        #expect(afterAdd?.items.contains(where: { $0.id == item.id }) == true)

        try await sut.moveItem(item.id, toDay: 3, mealType: .dinner, inPlan: plan.id)
        let afterMove = try await sut.currentPlan(forWeek: week, userId: userId)
        let moved = afterMove?.items.first { $0.id == item.id }
        #expect(moved?.dayIndex == 3)
        #expect(moved?.mealType == .dinner)

        try await sut.removeItem(item.id, fromPlan: plan.id)
        let afterRemove = try await sut.currentPlan(forWeek: week, userId: userId)
        #expect(afterRemove?.items.contains(where: { $0.id == item.id }) == false)
    }

    @MainActor
    @Test("setChecked flips a shopping item and survives a re-read")
    func checkRoundTrips() async throws {
        let sut = MockMealPlanningService()
        let planId = UUID()
        let list = try await sut.shoppingList(forPlan: planId)
        let target = list.first!
        #expect(target.checked == false || target.checked == true)  // baseline

        try await sut.setChecked(target.id, checked: true, listId: UUID())
        let after = try await sut.shoppingList(forPlan: planId)
        #expect(after.first { $0.id == target.id }?.checked == true)
    }
}
