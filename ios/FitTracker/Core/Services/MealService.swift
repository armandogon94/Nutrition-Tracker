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

/// Whether a logged item made it all the way to the backend or is sitting
/// durably in the offline queue waiting for connectivity. Drives honest UX
/// copy ("saved" vs "saved locally — pending sync") instead of a blanket
/// success banner.
enum MealSyncState: Sendable, Equatable {
    case synced        // backend confirmed the write
    case pendingSync   // saved locally + durably enqueued; will replay on reconnect
}

/// Result of an optimistic log: the inserted item plus its sync state. A
/// THROW from `logItemReturningOutcome` means the LOCAL write failed (true
/// "failed to save"); a `.pendingSync` outcome is a success from the user's
/// standpoint because the mutation is durable.
struct MealLogOutcome: Sendable, Equatable {
    let item: MealItem
    let state: MealSyncState
}

@MainActor
final class MealService: MealLoggingServiceProtocol {

    private let api: APIClient
    private let context: ModelContext
    /// Shared durable queue (the SAME instance SyncManager drains). When a
    /// backend round-trip fails, the write is enqueued here so it survives an
    /// app kill and replays on reconnect. Defaults to `OfflineQueue.shared`
    /// so the shipped app (wired via `MockServiceContainer.production()`)
    /// enqueues without extra plumbing; tests inject an isolated queue. Pass
    /// `nil` to opt out entirely (a failed write then only stays
    /// `pendingSync` locally).
    private let offlineQueue: OfflineQueue?

    /// Test-only seam for forcing a local persist failure. Production passes
    /// `nil`, so every save goes straight through `context.save()`. Tests inject
    /// a throwing hook to exercise the delete-path rollback (Codex review #5
    /// P2) without needing to corrupt the SwiftData store.
    private let saveHook: (@MainActor (ModelContext) throws -> Void)?

    init(api: APIClient,
         context: ModelContext,
         offlineQueue: OfflineQueue? = .shared,
         saveHook: (@MainActor (ModelContext) throws -> Void)? = nil) {
        self.api = api
        self.context = context
        self.offlineQueue = offlineQueue
        self.saveHook = saveHook
    }

    /// Persist pending changes, routing through the injected `saveHook` when
    /// present (tests) and otherwise calling `context.save()` directly.
    private func persist() throws {
        if let saveHook {
            try saveHook(context)
        } else {
            try context.save()
        }
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

    /// Protocol entry point. Optimistically inserts locally, then tries the
    /// backend. Returns the inserted item. Throws ONLY when the local write
    /// fails (genuine "failed to save"); a backend failure is NOT an error
    /// here because the write is durably enqueued and will replay — callers
    /// wanting to distinguish synced-vs-pending should use
    /// `logItemReturningOutcome`.
    func logItem(product: Product,
                 servings: Double,
                 mealType: MealType,
                 mealDate: Date,
                 userId: UUID) async throws -> MealItem {
        try await logItemReturningOutcome(
            product: product, servings: servings, mealType: mealType,
            mealDate: mealDate, userId: userId
        ).item
    }

    /// Optimistic insert + sync, surfacing whether the item synced or is
    /// pending. The LOCAL insert happens first and any failure there throws
    /// (the user genuinely lost the write). The backend POST then runs; on
    /// failure we enqueue a durable `PendingMutation` and report
    /// `.pendingSync` instead of throwing, so the UI can be honest rather
    /// than claiming a blanket success.
    func logItemReturningOutcome(product: Product,
                                 servings: Double,
                                 mealType: MealType,
                                 mealDate: Date,
                                 userId: UUID) async throws -> MealLogOutcome {

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
        // A failure HERE is a true "failed to save" — the optimistic local
        // write didn't even persist — so it propagates to the caller.
        try persist()

        // Build the durable mutation and ENQUEUE IT BEFORE the network call.
        // The `client_item_id` (the snapshot's local id) makes the write
        // idempotent: a queued retry sends the same id and the backend returns
        // the existing row instead of duplicating. `ownerId` lets SyncManager
        // owner-guard the replay so it never flushes under another account.
        //
        // Ordering matters (Codex review #4 P2 "lost-write window"): if we
        // only enqueued inside the catch, an app kill between the local save
        // and the catch would leave a `pendingSync` row with NO queue entry —
        // a silently lost write. Enqueuing first, then removing on confirmed
        // success, closes that window. The enqueue is idempotent by id, so the
        // pre-write + a later replay never produce two entries.
        let dateOnly = Self.dateOnly.string(from: mealDate)
        let payload = LogMealItemPayload(
            ownerId: userId,
            clientItemId: snapshot.id,
            mealType: mealType.rawValue,
            mealDate: dateOnly,
            productId: product.id,
            productName: product.name,
            brand: product.brand,
            servings: servings,
            calories: snapshot.calories,
            proteinG: snapshot.proteinG,
            carbsG: snapshot.carbsG,
            fatG: snapshot.fatG
        )
        await offlineQueue?.enqueue(.logMealItem(payload))

        do {
            let _: MealDTO = try await api.post("/api/v1/meals/log", body: payload.asRequest())
            // Confirmed by the server: drop the durable entry (no leak) and
            // clear the local pending flag.
            await offlineQueue?.remove(id: snapshot.id)
            entity.pendingSync = false
            entity.lastSyncedAt = .now
            // Only clear the parent's flag if every sibling item is synced;
            // otherwise an earlier pending item would be wrongly marked done.
            if parent.items.allSatisfy({ !$0.pendingSync }) {
                parent.pendingSync = false
                parent.lastSyncedAt = .now
            }
            try? persist()
            return MealLogOutcome(item: snapshot, state: .synced)
        } catch {
            // Backend unreachable / rejected. The durable mutation is ALREADY
            // queued (above), so the write is NOT lost — it replays on
            // reconnect / next launch. Reporting `.pendingSync` (not throwing)
            // is what lets the UI say "saved locally" honestly.
            return MealLogOutcome(item: snapshot, state: .pendingSync)
        }
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

        // Attribute the tombstone to the meal's owner so SyncManager can
        // owner-guard the replayed delete. Derive it BEFORE deleting (after
        // delete the relationship is gone). Fall back to a direct meal lookup
        // if the inverse relationship is somehow nil.
        let ownerId = item.meal?.userId ?? Self.ownerId(ofMeal: mealId, in: context)

        // Queue a durable tombstone BEFORE the optimistic local delete (Codex
        // review #4 P2 "lost-write window"): a kill after the local delete but
        // before enqueue would otherwise lose the deletion entirely, and the
        // row would silently reappear on the next server read. The by-id
        // delete route is idempotent, so replaying it is safe even if the row
        // is already gone server-side. We can only enqueue when we know the
        // owner; without one we'd risk a replay the guard can never run.
        if let ownerId {
            await offlineQueue?.enqueue(.deleteMealItem(DeleteMealItemPayload(ownerId: ownerId, id: itemId)))
        }

        // Optimistic local delete. If the SAVE fails, the tombstone we just
        // queued would otherwise survive and a later replay could delete the
        // SERVER row while the local row is still present — a silent divergence
        // (Codex review #5 P2). So on failure we remove the tombstone before
        // rethrowing, leaving local + queue consistent (nothing deleted yet).
        context.delete(item)
        do {
            try persist()
        } catch {
            if ownerId != nil {
                await offlineQueue?.remove(id: itemId)
            }
            throw error
        }

        do {
            try await api.delete("/api/v1/meals/items/\(itemId.uuidString)")
            // Confirmed: drop the durable tombstone (no leak).
            await offlineQueue?.remove(id: itemId)
        } catch {
            // Backend unreachable / rejected. The tombstone is ALREADY queued
            // (above), so the deletion replays on reconnect rather than being
            // silently lost.
        }
    }

    /// Best-effort lookup of the owning user for a meal id, used as a fallback
    /// when a meal item's inverse relationship to its parent is nil.
    private static func ownerId(ofMeal mealId: UUID, in context: ModelContext) -> UUID? {
        let descriptor = FetchDescriptor<MealEntity>(
            predicate: #Predicate { $0.id == mealId }
        )
        return (try? context.fetch(descriptor).first)?.userId
    }
}
