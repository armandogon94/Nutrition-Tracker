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

// MARK: - Profile + Goals

@MainActor
protocol ProfileServiceProtocol: AnyObject {
    func profile() async throws -> UserProfile
    func updateProfile(_ profile: UserProfile) async throws
    func goal() async throws -> NutritionGoal
    func updateGoal(_ goal: NutritionGoal) async throws
    /// Slice 5.4: persist a goal *preset* selection. Backend recalculates
    /// macros from the current profile + preset adjustment and returns the
    /// fresh targets. Added to the protocol so GoalsView can save presets
    /// through `any ProfileServiceProtocol` (production = real ProfileService,
    /// preview = MockProfileService).
    func updatePreset(_ preset: GoalPreset) async throws
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

/// Outcome of logging a single set. Returns the freshly inserted
/// `WorkoutSet` (so the UI can append it immediately) plus an optional
/// `PersonalRecord` that is non-nil exactly when this set set a new PR for
/// its exercise — the view uses it to drive the celebration overlay.
struct LogSetOutcome: Sendable, Equatable {
    let set: WorkoutSet
    /// Non-nil iff this set beat the prior estimated-1RM for the exercise.
    let newPR: PersonalRecord?
    var isPR: Bool { newPR != nil }
}

/// Slice 7: extends `WorkoutServiceProtocol` with the active-workout
/// mutations. Kept as a separate protocol — mirroring
/// `MealLoggingServiceProtocol` — so the Slice 0.5 read-only mock surface
/// stays minimal and previews can inject a lightweight read-only stub.
///
/// All three mutators are `@MainActor` because each one touches a SwiftData
/// `ModelContext`; the backend round-trip is launched from inside the
/// actor and awaited only so we can flip `pendingSync`.
@MainActor
protocol WorkoutLoggingServiceProtocol: WorkoutServiceProtocol {
    /// Creates a session locally (pendingSync=true) and on the backend.
    /// Returns the local `WorkoutSession` immediately so the logger UI can
    /// navigate without waiting on the network. A backend failure leaves
    /// the row pending for later sync rather than blocking the workout.
    func startSession(programName: String,
                      dayName: String,
                      programId: UUID?,
                      programDayId: UUID?,
                      userId: UUID) async throws -> WorkoutSession

    /// Logs one set against an active session. Writes the set to SwiftData
    /// first (so a mid-workout crash never loses input), detects a PR by
    /// comparing estimated-1RM against the local `PersonalRecord` for the
    /// exercise (mirroring `backend/app/services/workout_service.py`),
    /// updates/creates that PR locally, then fires the backend POST.
    func logSet(sessionId: UUID,
                exerciseId: UUID,
                exerciseName: String,
                setNumber: Int,
                weightKg: Double,
                reps: Int,
                userId: UUID) async throws -> LogSetOutcome

    /// Marks a session complete: stamps `completedAt`, persists locally,
    /// and PATCHes the backend. Returns the completed `WorkoutSession`
    /// (with duration derived) for the summary screen + HealthKit write.
    func completeSession(sessionId: UUID) async throws -> WorkoutSession
}
