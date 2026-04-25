//
//  MockServices.swift
//  Slice 0.5: protocol-conforming mock services that return MockData
//  fixtures. Slices 1–8 swap these out for real-backend implementations
//  one at a time without touching views.
//

import Foundation
import Observation

// MARK: - Auth

@Observable
@MainActor
final class MockAuthService: AuthServiceProtocol {
    var isAuthenticated: Bool = false
    var currentUser: MockUser?

    func login(email: String, password: String) async throws {
        try await Task.sleep(nanoseconds: 200_000_000) // simulate latency
        currentUser = MockData.testAccounts.first { $0.email == email } ?? MockData.user
        isAuthenticated = true
    }

    func register(email: String, password: String, displayName: String) async throws {
        try await Task.sleep(nanoseconds: 200_000_000)
        currentUser = MockUser(id: UUID(), email: email, displayName: displayName, createdAt: Date())
        isAuthenticated = true
    }

    func signOut() async {
        currentUser = nil
        isAuthenticated = false
    }

    /// Test convenience: skip the form, drop straight in.
    func quickLogin(as user: MockUser) {
        currentUser = user
        isAuthenticated = true
    }
}

// MARK: - Nutrition

final class MockNutritionService: NutritionServiceProtocol, @unchecked Sendable {
    func dailyNutrition(for date: Date) async throws -> DailyNutrition { MockData.dailyNutrition }
    func meals(for date: Date) async throws -> [Meal] { MockData.meals }
    func currentGoal() async throws -> NutritionGoal { MockData.goal }
}

// MARK: - Products

final class MockProductsService: ProductsServiceProtocol, @unchecked Sendable {
    func search(query: String) async throws -> [Product] {
        guard !query.isEmpty else { return MockData.products }
        let q = query.lowercased()
        return MockData.products.filter { $0.name.lowercased().contains(q) || ($0.brand?.lowercased().contains(q) ?? false) }
    }
    func lookup(barcode: String) async throws -> Product? {
        MockData.products.first { $0.barcode == barcode }
    }
}

// MARK: - Meals

final class MockMealsService: MealsServiceProtocol, @unchecked Sendable {
    func mealsToday() async throws -> [Meal] { MockData.meals }
    func deleteItem(_ itemId: UUID, fromMeal mealId: UUID) async throws { /* no-op in mock */ }
}

// MARK: - Meal plan

@Observable
@MainActor
final class MockMealPlanService: MealPlanServiceProtocol {
    private var checkedIDs: Set<UUID> = Set(MockData.shoppingList.filter(\.checked).map(\.id))

    func currentPlan() async throws -> MealPlan? { MockData.mealPlan }

    func shoppingList() async throws -> [ShoppingItem] {
        MockData.shoppingList.map { item in
            var copy = item
            copy.checked = checkedIDs.contains(item.id)
            return copy
        }
    }

    func toggleChecked(_ itemId: UUID) async throws {
        if checkedIDs.contains(itemId) {
            checkedIDs.remove(itemId)
        } else {
            checkedIDs.insert(itemId)
        }
    }
}

// MARK: - Profile

@Observable
@MainActor
final class MockProfileService: ProfileServiceProtocol {
    private var _profile: UserProfile = MockData.profile
    private var _goal: NutritionGoal = MockData.goal

    func profile() async throws -> UserProfile { _profile }
    func updateProfile(_ profile: UserProfile) async throws { _profile = profile }
    func goal() async throws -> NutritionGoal { _goal }
    func updateGoal(_ goal: NutritionGoal) async throws { _goal = goal }
}

// MARK: - Programs

final class MockProgramsService: ProgramsServiceProtocol, @unchecked Sendable {
    func allPrograms() async throws -> [WorkoutProgram] { MockData.programs }
    func program(id: UUID) async throws -> WorkoutProgram? { MockData.programs.first { $0.id == id } }
}

// MARK: - Exercises

final class MockExercisesService: ExercisesServiceProtocol, @unchecked Sendable {
    func allExercises() async throws -> [Exercise] { MockData.exercises }

    func search(query: String, muscle: MuscleGroup?, equipment: Equipment?) async throws -> [Exercise] {
        let q = query.lowercased()
        return MockData.exercises.filter { ex in
            (q.isEmpty || ex.name.lowercased().contains(q)) &&
            (muscle == nil || ex.primaryMuscle == muscle || ex.secondaryMuscles.contains(muscle!)) &&
            (equipment == nil || ex.equipment == equipment)
        }
    }
}

// MARK: - Workouts

final class MockWorkoutService: WorkoutServiceProtocol, @unchecked Sendable {
    func currentSession() async throws -> WorkoutSession? { nil }
    func completedSessions(in interval: DateInterval) async throws -> [WorkoutSession] {
        MockData.recentSessions.filter { interval.contains($0.startedAt) }
    }
    func personalRecords() async throws -> [PersonalRecord] { MockData.personalRecords }
}

// MARK: - Service container (DI)

@Observable
@MainActor
final class MockServiceContainer {
    let auth = MockAuthService()
    let nutrition = MockNutritionService()
    let products = MockProductsService()
    let meals = MockMealsService()
    let mealPlan = MockMealPlanService()
    let profile = MockProfileService()
    let programs = MockProgramsService()
    let exercises = MockExercisesService()
    let workouts = MockWorkoutService()

    init() {
        #if DEBUG
        // Auto-login when the app is launched with `-uiAutoLogin carlos`.
        // Used by Slice 0.5 simulator capture scripts to skip past the
        // login screen for screenshotting deeper screens.
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-uiAutoLogin"), i + 1 < args.count {
            let handle = args[i + 1]
            if let user = MockData.testAccounts.first(where: { $0.email.hasPrefix(handle) || $0.displayName.lowercased() == handle.lowercased() }) {
                auth.quickLogin(as: user)
            }
        }
        #endif
    }
}
