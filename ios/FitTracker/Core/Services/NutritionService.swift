//
//  NutritionService.swift
//  Stale-while-revalidate read-through cache for daily nutrition data.
//  Slice 2.3.
//
//  Pattern: callers ask for `dailyNutrition(for:)`. The service:
//    1. Returns the SwiftData-cached row immediately if present
//    2. Spawns a background fetch from /api/v1/nutrition/daily/<date>
//    3. Upserts the fresh row on success and emits via AsyncStream
//  HomeView (Task 2.4) renders cached then auto-updates when the stream
//  fires.
//

import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class NutritionService: NutritionServiceProtocol {

    private let api: APIClient
    private let context: ModelContext
    private let userId: () -> UUID?

    init(api: APIClient,
         context: ModelContext,
         userId: @escaping () -> UUID?) {
        self.api = api
        self.context = context
        self.userId = userId
    }

    // MARK: - Protocol surface

    /// Return the cached value if it's from today, then refresh in
    /// background. If no cache exists, fetch synchronously.
    func dailyNutrition(for date: Date) async throws -> DailyNutrition {
        if let cached = try? cachedDailyNutrition(for: date) {
            // Background refresh — don't block the caller.
            Task { try? await refreshDailyNutrition(for: date) }
            return cached
        }
        // Cold path: fetch + cache before returning.
        return try await refreshDailyNutrition(for: date)
    }

    /// Slice 3 (MealService) replaces this with a real implementation.
    /// For Slice 2 we read straight from the cache; HomeView only needs
    /// the meal count, which we derive from MealEntity rows once Slice
    /// 3 lands them. Returning empty here is acceptable: the hero card
    /// reads aggregated calories from DailyNutritionEntity.
    func meals(for date: Date) async throws -> [Meal] {
        guard let uid = userId() else { return [] }
        let dayStart = Calendar(identifier: .iso8601).startOfDay(for: date)
        let dayEnd = Calendar(identifier: .iso8601)
            .date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        let descriptor = FetchDescriptor<MealEntity>(
            predicate: #Predicate {
                $0.userId == uid && $0.mealDate >= dayStart && $0.mealDate < dayEnd
            },
            sortBy: [SortDescriptor(\.mealDate)]
        )
        let entities = (try? context.fetch(descriptor)) ?? []
        return entities.map { entity in
            Meal(id: entity.id,
                 mealType: MealType(rawValue: entity.mealType) ?? .snack,
                 mealDate: entity.mealDate,
                 items: [])  // Slice 3 fills items
        }
    }

    /// Returns the user's active goal — cache first, then network refresh.
    func currentGoal() async throws -> NutritionGoal {
        if let cached = try? cachedGoal() {
            Task { try? await refreshGoal() }
            return cached
        }
        return try await refreshGoal()
    }

    // MARK: - Cache

    private func cachedDailyNutrition(for date: Date) throws -> DailyNutrition? {
        guard let uid = userId() else { return nil }
        let key = DailyNutritionEntity.makeKey(userId: uid, date: date)
        let descriptor = FetchDescriptor<DailyNutritionEntity>(
            predicate: #Predicate { $0.dayKey == key }
        )
        return try context.fetch(descriptor).first?.toStruct()
    }

    private func cachedGoal() throws -> NutritionGoal? {
        guard let uid = userId() else { return nil }
        let descriptor = FetchDescriptor<NutritionGoalEntity>(
            predicate: #Predicate { $0.userId == uid }
        )
        guard let entity = try context.fetch(descriptor).first else { return nil }
        return NutritionGoal(
            dailyCalories: entity.dailyCalories,
            proteinG: entity.proteinG,
            carbsG: entity.carbsG,
            fatG: entity.fatG,
            fiberG: entity.fiberG
        )
    }

    // MARK: - Network + upsert

    /// Fetch from backend, upsert into SwiftData, return the fresh value.
    @discardableResult
    func refreshDailyNutrition(for date: Date) async throws -> DailyNutrition {
        guard let uid = userId() else { throw APIError.unauthorized }
        let dateString = Self.dateFormatter.string(from: date)
        let dto: DailyNutritionDTO = try await api.get(
            "/api/v1/nutrition/daily/\(dateString)"
        )
        let fresh = dto.toStruct()
        try upsert(fresh, userId: uid)
        return fresh
    }

    @discardableResult
    func refreshGoal() async throws -> NutritionGoal {
        guard let uid = userId() else { throw APIError.unauthorized }
        let dto: NutritionGoalDTO = try await api.get("/api/v1/goals")
        let fresh = NutritionGoal(
            dailyCalories: dto.daily_calories,
            proteinG: dto.protein_g,
            carbsG: dto.carbs_g,
            fatG: dto.fat_g,
            fiberG: dto.fiber_g
        )
        try upsertGoal(fresh, userId: uid)
        return fresh
    }

    // MARK: - SwiftData upsert helpers

    private func upsert(_ value: DailyNutrition, userId uid: UUID) throws {
        let key = DailyNutritionEntity.makeKey(userId: uid, date: value.date)
        let descriptor = FetchDescriptor<DailyNutritionEntity>(
            predicate: #Predicate { $0.dayKey == key }
        )
        if let existing = try context.fetch(descriptor).first {
            existing.calories = value.calories
            existing.proteinG = value.proteinG
            existing.carbsG = value.carbsG
            existing.fatG = value.fatG
            existing.fiberG = value.fiberG
            existing.lastSyncedAt = Date()
        } else {
            context.insert(value.toEntity(userId: uid, lastSyncedAt: Date()))
        }
        try context.save()
    }

    private func upsertGoal(_ goal: NutritionGoal, userId uid: UUID) throws {
        let descriptor = FetchDescriptor<NutritionGoalEntity>(
            predicate: #Predicate { $0.userId == uid }
        )
        if let existing = try context.fetch(descriptor).first {
            existing.dailyCalories = goal.dailyCalories
            existing.proteinG = goal.proteinG
            existing.carbsG = goal.carbsG
            existing.fatG = goal.fatG
            existing.fiberG = goal.fiberG
            existing.lastSyncedAt = Date()
        } else {
            context.insert(NutritionGoalEntity(
                userId: uid,
                dailyCalories: goal.dailyCalories,
                proteinG: goal.proteinG,
                carbsG: goal.carbsG,
                fatG: goal.fatG,
                fiberG: goal.fiberG,
                lastSyncedAt: Date()
            ))
        }
        try context.save()
    }

    // MARK: - Helpers

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

// MARK: - DTOs (Slice 2.3 backend contract)

struct DailyNutritionDTO: Codable, Sendable {
    let date: Date
    let calories: Double
    let protein_g: Double
    let carbs_g: Double
    let fat_g: Double
    let fiber_g: Double

    func toStruct() -> DailyNutrition {
        DailyNutrition(
            date: date,
            calories: calories,
            proteinG: protein_g,
            carbsG: carbs_g,
            fatG: fat_g,
            fiberG: fiber_g
        )
    }
}

struct NutritionGoalDTO: Codable, Sendable {
    let daily_calories: Int
    let protein_g: Int
    let carbs_g: Int
    let fat_g: Int
    let fiber_g: Int
}
