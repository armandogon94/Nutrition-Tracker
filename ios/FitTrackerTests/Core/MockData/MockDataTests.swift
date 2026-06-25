//
//  MockDataTests.swift
//  Verifies seed fixtures are complete and self-consistent. Slice 0.5
//  views depend on these always being non-empty.
//

import Foundation
import Testing
@testable import FitTracker

@Test("MockData has all required collections populated")
func mockData_collectionsNonEmpty() {
    #expect(MockData.testAccounts.count == 3)
    #expect(MockData.products.count >= 10)
    #expect(MockData.meals.count >= 3)
    #expect(MockData.exercises.count >= 10)
    #expect(MockData.programs.count >= 4)
    #expect(MockData.shoppingList.count >= 8)
    #expect(MockData.recentSessions.count >= 5)
    #expect(MockData.personalRecords.count >= 4)
}

@Test("MockData daily nutrition aggregates from meals")
func mockData_dailyNutrition_aggregates() {
    let totalFromMeals = MockData.meals.reduce(0) { $0 + $1.totalCalories }
    #expect(MockData.dailyNutrition.calories == totalFromMeals)
}

@Test("MockData meal plan covers a full 7-day week")
func mockData_mealPlan_fullWeek() {
    let days = Set(MockData.mealPlan.items.map(\.dayIndex))
    #expect(days.count == 7)
}

@MainActor
@Test("MockAuthService quickLogin authenticates")
func mockAuth_quickLogin() {
    let sut = MockAuthService()
    #expect(!sut.isAuthenticated)
    sut.quickLogin(as: MockData.user)
    #expect(sut.isAuthenticated)
    #expect(sut.currentUser?.email == MockData.user.email)
}

@MainActor
@Test("MockMealPlanService toggleChecked persists in-session")
func mockMealPlan_toggleChecked() async throws {
    let sut = MockMealPlanService()
    let planId = UUID()
    let initial = try await sut.shoppingList(forPlan: planId)
    let firstUnchecked = try #require(initial.first { !$0.checked })
    try await sut.toggleChecked(firstUnchecked.id)
    let after = try await sut.shoppingList(forPlan: planId)
    #expect(after.first { $0.id == firstUnchecked.id }?.checked == true)
}
