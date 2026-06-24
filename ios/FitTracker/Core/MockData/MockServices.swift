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

    /// Mirrors the real service's preset path: recompute macros locally from
    /// the stored profile's TDEE + preset adjustment so the preview reflects
    /// the selection without a backend.
    func updatePreset(_ preset: GoalPreset) async throws {
        let bmr = TDEECalculator.bmr(
            weightKg: _profile.weightKg, heightCm: _profile.heightCm,
            age: _profile.age, sex: _profile.sex
        )
        let tdee = TDEECalculator.tdee(bmr: bmr, activity: _profile.activity)
        _goal = TDEECalculator.macros(tdee: tdee, goal: preset, weightKg: _profile.weightKg)
    }
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

// MARK: - History + Analytics (Slice 8)

/// Aggregates `MockData.recentSessions` in-memory so the History screen and
/// SwiftUI previews render real-looking charts without a SwiftData store.
/// Uses the same 1RM/week math as the production `HistoryService`.
final class MockHistoryService: HistoryServiceProtocol, @unchecked Sendable {
    private var sessions: [WorkoutSession] { MockData.recentSessions }

    func sessions(in interval: DateInterval) async throws -> [WorkoutSession] {
        sessions.filter { interval.contains($0.startedAt) }
            .sorted { $0.startedAt > $1.startedAt }
    }

    func volumeByWeek(weeks: Int) async throws -> [WeeklyVolumePoint] {
        let count = max(weeks, 1)
        let thisWeek = HistoryService.weekStart(for: Date())
        var buckets: [Date: (Double, Int)] = [:]
        var order: [Date] = []
        for offset in stride(from: count - 1, through: 0, by: -1) {
            guard let ws = HistoryService.calendar.date(byAdding: .weekOfYear,
                                                        value: -offset, to: thisWeek) else { continue }
            buckets[ws] = (0, 0); order.append(ws)
        }
        for session in sessions {
            let ws = HistoryService.weekStart(for: session.startedAt)
            guard buckets[ws] != nil else { continue }
            for set in session.sets {
                buckets[ws]?.0 += set.weightKg * Double(set.reps)
                buckets[ws]?.1 += 1
            }
        }
        return order.map { WeeklyVolumePoint(weekStart: $0, totalVolume: buckets[$0]?.0 ?? 0,
                                             totalSets: buckets[$0]?.1 ?? 0) }
    }

    func volumeByMuscle(weeks: Int) async throws -> [MuscleVolumePoint] {
        // Map mock exercise ids → muscle via the seeded exercise catalog.
        var muscleByExercise: [UUID: MuscleGroup] = [:]
        for ex in MockData.exercises { muscleByExercise[ex.id] = ex.primaryMuscle }
        var totals: [MuscleGroup: (Double, Int)] = [:]
        for session in sessions {
            for set in session.sets {
                let m = muscleByExercise[set.exerciseId] ?? .core
                var e = totals[m] ?? (0, 0)
                e.0 += set.weightKg * Double(set.reps); e.1 += 1
                totals[m] = e
            }
        }
        return totals.map { MuscleVolumePoint(muscle: $0.key, totalVolume: $0.value.0,
                                              totalSets: $0.value.1) }
            .sorted { $0.totalVolume > $1.totalVolume }
    }

    func prs() async throws -> [ExercisePR] {
        MockData.personalRecords.map {
            ExercisePR(exerciseId: $0.exerciseId, exerciseName: $0.exerciseName,
                       weightKg: $0.weightKg, reps: $0.reps,
                       estimated1RM: HistoryService.estimate1RM(weightKg: $0.weightKg, reps: $0.reps),
                       achievedAt: $0.achievedAt)
        }
        .sorted { $0.estimated1RM > $1.estimated1RM }
    }

    func exerciseProgression(exerciseId: UUID) async throws -> [ProgressionPoint] {
        sessions.compactMap { session -> ProgressionPoint? in
            let relevant = session.sets.filter { $0.exerciseId == exerciseId && $0.weightKg > 0 }
            guard let best = relevant.max(by: {
                HistoryService.estimate1RM(weightKg: $0.weightKg, reps: $0.reps)
                    < HistoryService.estimate1RM(weightKg: $1.weightKg, reps: $1.reps)
            }) else { return nil }
            return ProgressionPoint(
                date: session.startedAt,
                estimated1RM: HistoryService.estimate1RM(weightKg: best.weightKg, reps: best.reps),
                topWeightKg: best.weightKg, reps: best.reps)
        }
        .sorted { $0.date < $1.date }
    }
}

// MARK: - Service container (DI)

@Observable
@MainActor
final class MockServiceContainer {
    /// Auth is protocol-typed so production can inject the real
    /// AuthService while previews + Slice 0.5 tap-through keep using
    /// MockAuthService. Slices 2–8 follow the same pattern as each
    /// domain's concrete service lands.
    let auth: any AuthServiceProtocol
    /// Slice 2.4b: nutrition is now protocol-typed too. Production injects
    /// the real `NutritionService` (SwiftData-backed stale-while-revalidate
    /// cache); previews + tap-through keep `MockNutritionService`.
    let nutrition: any NutritionServiceProtocol
    let products = MockProductsService()
    let meals = MockMealsService()
    let mealPlan = MockMealPlanService()
    /// Slice 5.2: profile is protocol-typed so production injects the real
    /// `ProfileService` (backend profile + TDEE + goals). ProfileView /
    /// TDEECalculatorView / GoalsView / SettingsView consume it through
    /// `any ProfileServiceProtocol` unchanged; previews keep the mock.
    let profile: any ProfileServiceProtocol
    let programs = MockProgramsService()
    let exercises = MockExercisesService()
    let workouts = MockWorkoutService()
    /// History/analytics aggregation. Protocol-typed so production can inject
    /// the SwiftData-backed `HistoryService` (Slice 8) while previews +
    /// tap-through keep the in-memory mock.
    let history: any HistoryServiceProtocol

    init(auth: (any AuthServiceProtocol)? = nil,
         nutrition: (any NutritionServiceProtocol)? = nil,
         profile: (any ProfileServiceProtocol)? = nil,
         history: (any HistoryServiceProtocol)? = nil) {
        let resolvedAuth = auth ?? MockAuthService()
        self.auth = resolvedAuth
        self.nutrition = nutrition ?? MockNutritionService()
        self.profile = profile ?? MockProfileService()
        self.history = history ?? MockHistoryService()

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

    /// Production wiring: real AuthService + real NutritionService backed
    /// by the live SwiftData store. The real NutritionService reads the
    /// authenticated user's id from AuthService so its cache predicates and
    /// `/api/v1/nutrition/daily/<date>` fetches scope to the right account.
    ///
    /// `FitTrackerApp.makeServiceContainer()` calls this on launch (except
    /// when `-useMockAuth` forces the all-mock path for design review).
    /// Kept as a factory rather than a flag inside `init` so the default
    /// initializer stays pure-mock for previews and unit tests.
    static func production() -> MockServiceContainer {
        let auth = AuthService()
        let api = APIClient(tokenProvider: KeychainTokenStore.shared)
        let nutrition = NutritionService(
            api: api,
            context: PersistenceController.live.container.mainContext,
            userId: { [weak auth] in auth?.currentUser?.id }
        )
        let profile = ProfileService(api: api)
        // Slice 8 B1 fix: inject the REAL HistoryService so the Progreso tab
        // aggregates the live SwiftData store instead of MockData. It reads the
        // authenticated user's id at query time from the SAME auth instance
        // used for nutrition, so its session/PR queries scope to the right
        // account once the user logs in.
        let history = HistoryService(
            container: PersistenceController.live.container,
            userId: { [weak auth] in auth?.currentUser?.id }
        )
        return MockServiceContainer(auth: auth, nutrition: nutrition,
                                    profile: profile, history: history)
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
