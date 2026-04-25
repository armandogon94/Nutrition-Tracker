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
    func signOut() async
}

// MARK: - Nutrition

protocol NutritionServiceProtocol: AnyObject, Sendable {
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

// MARK: - Meal Plan + Shopping List

@MainActor
protocol MealPlanServiceProtocol: AnyObject {
    func currentPlan() async throws -> MealPlan?
    func shoppingList() async throws -> [ShoppingItem]
    func toggleChecked(_ itemId: UUID) async throws
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
