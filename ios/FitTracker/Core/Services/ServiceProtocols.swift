//
//  ServiceProtocols.swift
//  Slice 0.5: defines the protocol surface for every domain service.
//  MockData stubs satisfy these now; concrete actor implementations
//  land per slice (1 = Auth, 2 = Nutrition, 3 = Meals + Products,
//  4 = MealPlan, 5 = Profile, 6 = Programs + Exercises, 7 = Workouts,
//  8 = History).
//
//  Methods are intentionally minimal. Slices may extend protocols
//  via additive extensions or revise once with an ADR.
//

import Foundation

// MARK: - Auth

@MainActor
protocol AuthServiceProtocol: AnyObject {
    var isAuthenticated: Bool { get }
    var currentUser: MockUser? { get }
    func login(email: String, password: String) async throws
    func register(email: String, password: String, displayName: String) async throws
    func signInWithApple(identityToken: String, userIdentifier: String, email: String?, fullName: PersonNameComponents?) async throws
    func signOut() async
    func restoreSession() async
}

import Foundation

// MARK: - Nutrition

@MainActor
protocol NutritionServiceProtocol: AnyObject {
    func dailyNutrition(for date: Date) async throws -> DailyNutrition
    func meals(for date: Date) async throws -> [Meal]
    func currentGoal() async throws -> NutritionGoal
}

// MARK: - Products

protocol ProductsServiceProtocol: AnyObject, Sendable {
    func search(query: String) async throws -> [Product]
    func lookup(barcode: String) async throws -> Product?
}

// MARK: - Meals (CRUD; Slice 3)

protocol MealsServiceProtocol: AnyObject, Sendable {
    func mealsToday() async throws -> [Meal]
    func deleteItem(_ itemId: UUID, fromMeal mealId: UUID) async throws
}

/// Slice 3: extends MealsServiceProtocol with optimistic logging and a
/// SwiftData-backed cache reader. Kept as a separate protocol so the
/// Slice 0.5 mock surface stays minimal and ProductsServiceProtocol can
/// be substituted in previews without dragging in SwiftData.
protocol MealLoggingServiceProtocol: MealsServiceProtocol {
    /// Optimistically inserts a MealItem locally (pendingSync=true) and
    /// fires the backend POST in the background. Returns the freshly
    /// inserted MealItem — view code uses it to update UI immediately,
    /// long before the network round-trip resolves.
    @MainActor
    func logItem(product: Product,
                 servings: Double,
                 mealType: MealType,
                 mealDate: Date,
                 userId: UUID) async throws -> MealItem

    /// Pulls today's meals from the local SwiftData cache. Always returns
    /// quickly; does not hit the network.
    @MainActor
    func recentMeals(for date: Date, userId: UUID) async throws -> [Meal]
}

// MARK: - Meal Plan + Shopping List

@MainActor
protocol MealPlanServiceProtocol: AnyObject {
    func currentPlan() async throws -> MealPlan?
    func shoppingList() async throws -> [ShoppingItem]
    func toggleChecked(_ itemId: UUID) async throws
}

/// Slice 4: extends the minimal Slice-0.5 surface with the full meal-plan
/// CRUD + shopping-list generation backed by the FastAPI backend and the
/// SwiftData cache. Kept as a separate protocol so the Slice-0.5 mock can
/// keep satisfying `MealPlanServiceProtocol` without growing the network
/// surface, mirroring the `MealLoggingServiceProtocol` split.
@MainActor
protocol MealPlanningServiceProtocol: MealPlanServiceProtocol {
    /// Create (and locally cache) a weekly plan for the given week start.
    func createPlan(weekStartDate: Date, userId: UUID, name: String) async throws -> MealPlan

    /// Add a product to a plan cell (day × meal slot). Optimistically
    /// caches the item; throws if the backend POST fails (the optimistic
    /// row is left in place with pendingSync=true for retry).
    func addItem(toPlan planId: UUID,
                 dayIndex: Int,
                 mealType: MealType,
                 product: Product,
                 servings: Double) async throws -> MealPlanItem

    /// Move an item to a different day/slot. The backend has no item-PATCH,
    /// so this deletes the old item and recreates it; the local cache is
    /// updated optimistically first so the UI moves the chip immediately.
    func moveItem(_ itemId: UUID,
                  toDay dayIndex: Int,
                  mealType: MealType,
                  inPlan planId: UUID) async throws

    /// Remove an item from a plan (cache + backend).
    func removeItem(_ itemId: UUID, fromPlan planId: UUID) async throws

    /// Generate (or regenerate) the shopping list for a plan. Caches the
    /// list + items and returns them grouped-ready as domain structs.
    func generateShoppingList(forPlan planId: UUID, userId: UUID) async throws -> [ShoppingItem]

    /// Set the checked state of a shopping item (cache + backend PATCH).
    func setChecked(_ itemId: UUID, checked: Bool, listId: UUID) async throws

    /// The id of the most recently generated shopping list in the cache,
    /// if any. Views need it to address the check PATCH endpoint.
    func currentShoppingListId() async throws -> UUID?
}

// MARK: - Profile + Goals

@MainActor
protocol ProfileServiceProtocol: AnyObject {
    func profile() async throws -> UserProfile
    func updateProfile(_ profile: UserProfile) async throws
    func goal() async throws -> NutritionGoal
    func updateGoal(_ goal: NutritionGoal) async throws
}

// MARK: - Programs + Exercises

protocol ProgramsServiceProtocol: AnyObject, Sendable {
    func allPrograms() async throws -> [WorkoutProgram]
    func program(id: UUID) async throws -> WorkoutProgram?
}

protocol ExercisesServiceProtocol: AnyObject, Sendable {
    func allExercises() async throws -> [Exercise]
    func search(query: String, muscle: MuscleGroup?, equipment: Equipment?) async throws -> [Exercise]
}

// MARK: - Workouts

protocol WorkoutServiceProtocol: AnyObject, Sendable {
    func currentSession() async throws -> WorkoutSession?
    func completedSessions(in: DateInterval) async throws -> [WorkoutSession]
    func personalRecords() async throws -> [PersonalRecord]
}
