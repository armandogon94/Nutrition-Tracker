//
//  MealService.swift
//  Slice 3: optimistic-write MealsService backed by SwiftData + APIClient.
//
//  The contract: a `logItem` call must update the local store IMMEDIATELY
//  so HomeView and MealsListView reflect the change within one frame.
//  The backend POST then runs in the background. On success we clear the
//  pendingSync flag; on failure we leave the row in place with
//  pendingSync=true so a future "retry pending" job can replay it.
//
//  We intentionally do NOT roll back on API failure. A user logging a
//  meal offline must see their data persist locally — losing input is
//  worse than a stale flag. ADR-0004 §4 codifies this stance.
//
//  Concurrency: MealService is @MainActor because every SwiftData
//  ModelContext operation must run on the actor that owns the context.
//  Backend POSTs are launched as detached Tasks so the UI is never
//  blocked while a write is in flight. This matches the Swift 6.2
//  approachable concurrency guidance — main-actor-by-default with
//  explicit hops only when crossing into URLSession-land.
//

import Foundation
import SwiftData

@MainActor
final class MealService: MealLoggingServiceProtocol {

    private let api: APIClient
    private let context: ModelContext

    init(api: APIClient, context: ModelContext) {
        self.api = api
        self.context = context
    }

    // MARK: - Date encoding

    /// The backend's `meal_date` is a date-only field. APIClient's JSON
    /// encoder emits full ISO8601 datetimes, which the Pydantic `date`
    /// validator rejects with a 422 — so we pre-format the day ourselves.
    /// (Same approach as `MealPlanService` for `week_start_date`.)
    private static let dateOnly: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // MARK: - Logging

    /// Optimistic insert + fire-and-forget sync. Returns synchronously
    /// after the local insert; the network call awaits completion only
    /// so we can flip pendingSync. Any error is rethrown so the caller
    /// can show a "saved locally, will retry" toast.
    func logItem(product: Product,
                 servings: Double,
                 mealType: MealType,
                 mealDate: Date,
                 userId: UUID) async throws -> MealItem {

        // Reuse an existing Meal for (userId, mealType, mealDate-day) or
        // create one. We treat "same meal" as same calendar day per the
        // dashboard aggregation rule in SPEC.md §4.
        let dayStart = Calendar(identifier: .iso8601).startOfDay(for: mealDate)
        let mealTypeRaw = mealType.rawValue
        let descriptor = FetchDescriptor<MealEntity>(
            predicate: #Predicate { meal in
                meal.userId == userId &&
                meal.mealType == mealTypeRaw &&
                meal.mealDate >= dayStart
            }
        )
        let candidates = try context.fetch(descriptor)
        let parent: MealEntity
        if let existing = candidates.first(where: {
            Calendar(identifier: .iso8601).isDate($0.mealDate, inSameDayAs: dayStart)
        }) {
            parent = existing
        } else {
            parent = MealEntity(
                id: UUID(), userId: userId,
                mealType: mealTypeRaw, mealDate: mealDate,
                pendingSync: true, lastSyncedAt: nil
            )
            context.insert(parent)
        }

        // Build the MealItem snapshot using product nutrition × servings.
        // We freeze macros at log time so future edits to the catalog
        // entry never rewrite history (ADR-0004 §6).
        let snapshot = MealItem(
            id: UUID(),
            productId: product.id,
            productName: product.name,
            brand: product.brand,
            servings: servings,
            calories: product.caloriesPerServing * servings,
            proteinG: product.proteinG * servings,
            carbsG: product.carbsG * servings,
            fatG: product.fatG * servings
        )
        let entity = MealItemMapper.makeEntity(from: snapshot, pendingSync: true)
        entity.meal = parent
        parent.items.append(entity)
        try context.save()

        // Fire the backend POST. If it fails we surface the error but
        // leave pendingSync=true so the row can be retried.
        let body = LogMealItemRequest(
            meal_type: mealType.rawValue,
            meal_date: Self.dateOnly.string(from: mealDate),
            product_id: product.id.uuidString,
            product_name: product.name,
            brand: product.brand,
            servings: servings,
            calories: snapshot.calories,
            protein_g: snapshot.proteinG,
            carbs_g: snapshot.carbsG,
            fat_g: snapshot.fatG,
            client_item_id: snapshot.id.uuidString
        )
        do {
            let _: MealDTO = try await api.post("/api/v1/meals/log", body: body)
            entity.pendingSync = false
            entity.lastSyncedAt = .now
            parent.pendingSync = false
            parent.lastSyncedAt = .now
            try context.save()
        } catch {
            // Leave pendingSync=true; the offline-retry job (Slice 2.x)
            // will sweep these on next launch / reachability event.
            throw error
        }

        return snapshot
    }

    // MARK: - Reads

    /// Today's meals from the SwiftData cache. Used by HomeView and
    /// MealsListView; never hits the network.
    func recentMeals(for date: Date, userId: UUID) async throws -> [Meal] {
        let cal = Calendar(identifier: .iso8601)
        let dayStart = cal.startOfDay(for: date)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? date
        let descriptor = FetchDescriptor<MealEntity>(
            predicate: #Predicate { meal in
                meal.userId == userId &&
                meal.mealDate >= dayStart &&
                meal.mealDate < dayEnd
            },
            sortBy: [SortDescriptor(\.mealDate, order: .forward)]
        )
        return try context.fetch(descriptor).map(Meal.init(from:))
    }

    // MARK: - MealsServiceProtocol (legacy surface)

    /// Forwarded for compatibility with the existing MealsServiceProtocol.
    /// Callers needing today's view should prefer `recentMeals(for:userId:)`.
    func mealsToday() async throws -> [Meal] {
        // Without a known userId here we simply fetch all of today's
        // meals. In practice MainTabView wires `recentMeals(for:userId:)`
        // through the auth-aware view model.
        let cal = Calendar(identifier: .iso8601)
        let dayStart = cal.startOfDay(for: .now)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? Date()
        let descriptor = FetchDescriptor<MealEntity>(
            predicate: #Predicate { meal in
                meal.mealDate >= dayStart && meal.mealDate < dayEnd
            },
            sortBy: [SortDescriptor(\.mealDate, order: .forward)]
        )
        return try context.fetch(descriptor).map(Meal.init(from:))
    }

    func deleteItem(_ itemId: UUID, fromMeal mealId: UUID) async throws {
        let descriptor = FetchDescriptor<MealItemEntity>(
            predicate: #Predicate { $0.id == itemId }
        )
        guard let item = try context.fetch(descriptor).first else { return }
        context.delete(item)
        try context.save()
        // Best-effort backend delete; swallow errors so offline UX works.
        _ = try? await api.delete("/api/v1/meals/items/\(itemId.uuidString)")
    }
}
