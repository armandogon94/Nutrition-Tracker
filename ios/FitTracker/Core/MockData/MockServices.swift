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

    func signInWithApple(identityToken: String, userIdentifier: String, email: String?, fullName: PersonNameComponents?) async throws {
        try await Task.sleep(nanoseconds: 200_000_000)
        currentUser = MockUser(
            id: UUID(),
            email: email ?? "apple_\(userIdentifier)@fittracker.local",
            displayName: fullName?.givenName ?? "Apple User",
            createdAt: Date()
        )
        isAuthenticated = true
    }

    func signOut() async {
        currentUser = nil
        isAuthenticated = false
    }

    func restoreSession() async {
        // No persisted state in mock — already in correct state from init/quickLogin
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
    /// Auth is protocol-typed so production can inject the real
    /// AuthService while previews + Slice 0.5 tap-through keep using
    /// MockAuthService. Slices 2–8 will follow the same pattern as
    /// each domain's concrete service lands.
    let auth: any AuthServiceProtocol
    let nutrition = MockNutritionService()
    let products = MockProductsService()
    let meals = MockMealsService()
    let mealPlan = MockMealPlanService()
    let profile = MockProfileService()
    let programs = MockProgramsService()
    let exercises = MockExercisesService()
    let workouts = MockWorkoutService()

    init(auth: (any AuthServiceProtocol)? = nil) {
        let resolvedAuth = auth ?? MockAuthService()
        self.auth = resolvedAuth

        #if DEBUG
        // Auto-login when the app is launched with `-uiAutoLogin carlos`.
        // Used by simulator capture scripts to skip past the login screen.
        // Only meaningful with MockAuthService (real auth needs a backend).
        let args = ProcessInfo.processInfo.arguments
        if let mock = resolvedAuth as? MockAuthService,
           let i = args.firstIndex(of: "-uiAutoLogin"), i + 1 < args.count {
            let handle = args[i + 1]
            if let user = MockData.testAccounts.first(where: {
                $0.email.hasPrefix(handle) || $0.displayName.lowercased() == handle.lowercased()
            }) {
                mock.quickLogin(as: user)
            }
        }
        #endif
    }
}

// MARK: - Meal plan (full planning surface — Slice 4)

/// In-memory mock for the extended `MealPlanningServiceProtocol`. Backs
/// previews and tests that exercise the planner/shopping flows without a
/// SwiftData context or network. Mutations are kept in plain arrays so the
/// weekly grid and shopping list reflect changes within the session.
@Observable
@MainActor
final class MockMealPlanningService: MealPlanningServiceProtocol {
    private var _plan: MealPlan? = MockData.mealPlan
    private var _shopping: [ShoppingItem] = MockData.shoppingList
    private let _listId = UUID()

    func currentPlan() async throws -> MealPlan? { _plan }

    func shoppingList() async throws -> [ShoppingItem] { _shopping }

    func toggleChecked(_ itemId: UUID) async throws {
        guard let i = _shopping.firstIndex(where: { $0.id == itemId }) else { return }
        _shopping[i].checked.toggle()
    }

    func createPlan(weekStartDate: Date, userId: UUID, name: String) async throws -> MealPlan {
        let plan = MealPlan(id: UUID(), weekStartDate: weekStartDate, items: [])
        _plan = plan
        return plan
    }

    func addItem(toPlan planId: UUID, dayIndex: Int, mealType: MealType,
                 product: Product, servings: Double) async throws -> MealPlanItem {
        let item = MealPlanItem(id: UUID(), dayIndex: dayIndex, mealType: mealType,
                                productName: product.name, servings: servings)
        if let plan = _plan {
            _plan = MealPlan(id: plan.id, weekStartDate: plan.weekStartDate,
                             items: plan.items + [item])
        }
        return item
    }

    func moveItem(_ itemId: UUID, toDay dayIndex: Int,
                  mealType: MealType, inPlan planId: UUID) async throws {
        guard let plan = _plan else { return }
        let items = plan.items.map { item -> MealPlanItem in
            guard item.id == itemId else { return item }
            return MealPlanItem(id: item.id, dayIndex: dayIndex, mealType: mealType,
                                productName: item.productName, servings: item.servings)
        }
        _plan = MealPlan(id: plan.id, weekStartDate: plan.weekStartDate, items: items)
    }

    func removeItem(_ itemId: UUID, fromPlan planId: UUID) async throws {
        guard let plan = _plan else { return }
        _plan = MealPlan(id: plan.id, weekStartDate: plan.weekStartDate,
                         items: plan.items.filter { $0.id != itemId })
    }

    func generateShoppingList(forPlan planId: UUID, userId: UUID) async throws -> [ShoppingItem] {
        _shopping = MockData.shoppingList
        return _shopping
    }

    func setChecked(_ itemId: UUID, checked: Bool, listId: UUID) async throws {
        guard let i = _shopping.firstIndex(where: { $0.id == itemId }) else { return }
        _shopping[i].checked = checked
    }

    func currentShoppingListId() async throws -> UUID? { _listId }
}
