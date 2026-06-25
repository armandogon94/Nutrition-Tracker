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


// MARK: - History + Analytics (Slice 8)

/// On-device aggregation surface for the History + Analytics screens.
/// All methods read the local SwiftData store (no network) so charts can
/// re-aggregate cheaply on every scroll/filter change. PR + 1RM logic
/// mirrors the backend `workout_service.py`. See `HistoryService`.
protocol HistoryServiceProtocol: AnyObject, Sendable {
    /// Completed sessions whose `startedAt` falls inside `interval`,
    /// newest first.
    func sessions(in interval: DateInterval) async throws -> [WorkoutSession]
    /// Contiguous, zero-filled weekly volume buckets (oldest first).
    func volumeByWeek(weeks: Int) async throws -> [WeeklyVolumePoint]
    /// Volume grouped by each exercise's primary muscle, descending.
    func volumeByMuscle(weeks: Int) async throws -> [MuscleVolumePoint]
    /// One PR (best estimated 1RM) per exercise, descending.
    func prs() async throws -> [ExercisePR]
    /// Per-session best-set progression for one exercise, oldest first.
    func exerciseProgression(exerciseId: UUID) async throws -> [ProgressionPoint]
    /// Map of exerciseId -> display name from the exercise catalog. Views use
    /// it to label sessions/sets/CSV by name. The real service reads the
    /// SwiftData `ExerciseEntity` catalog (so real, non-mock exercises
    /// resolve); the mock returns the seeded `MockData.exercises`.
    func exerciseNameLookup() async throws -> [UUID: String]
}
