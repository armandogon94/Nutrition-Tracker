//
//  MealPlanService.swift
//  Slice 4.1: backend-backed + SwiftData-cached meal-plan service.
//
//  Mirrors the `MealService` shape: @MainActor (every ModelContext op runs
//  on the actor that owns the context), APIClient for the network, and an
//  optimistic-write contract — local cache updates land first so the
//  weekly grid reflects a drag/add within one frame, with the backend
//  call following. On backend failure we keep the local row (pendingSync
//  semantics) rather than rolling back; losing user input is worse than a
//  stale flag (ADR-0004 §4).
//
//  Backend contract (app/api/v1/meal_plans.py, prefix /api/v1/meal-plans):
//    POST   /                                        -> MealPlanDTO
//    GET    /{planId}                                -> MealPlanDTO
//    GET    /                                        -> [MealPlanDTO]
//    DELETE /{planId}                                -> 204
//    POST   /{planId}/items                          -> MealPlanItemDTO
//    DELETE /{planId}/items/{itemId}                 -> 204
//    GET    /{planId}/shopping-list                  -> ShoppingListDTO
//    PATCH  /shopping-lists/{listId}/items/{itemId}/check -> {id,is_checked}
//
//  Notes on two contract gaps the backend forces us to work around:
//    1. There is no "move item" or item-PATCH endpoint. A move is a
//       DELETE of the old item + POST of a recreated one. The local cache
//       is the source of truth for offline correctness.
//    2. `MealPlanItemEntity` (Schema.swift, owned by main) does not store
//       `product_id`. The backend's item-POST requires one, so we keep a
//       small in-memory itemId -> productId map populated whenever items
//       arrive from the server (their DTOs carry product_id). If the id is
//       unknown (e.g. a cold launch reading only cached rows), the move
//       still succeeds locally and is left pendingSync=true — we do NOT
//       issue the DELETE, because deleting without recreating would lose
//       the item server-side permanently. `currentPlan()` repopulates the
//       map from a best-effort server GET so a subsequent move can replay.
//       Persisting product_id needs a schema bump (reported back to main).
//

import Foundation
import SwiftData

@MainActor
final class MealPlanService: MealPlanningServiceProtocol {

    private let api: APIClient
    private let context: ModelContext

    /// itemId -> productId, recovered from server DTOs. Lets `moveItem`
    /// recreate an item server-side without a schema change. See header.
    private var productIdByItem: [UUID: UUID] = [:]

    init(api: APIClient, context: ModelContext) {
        self.api = api
        self.context = context
    }

    // MARK: - Date encoding

    /// The backend's `week_start_date` is a date-only field. APIClient's
    /// JSON encoder emits full ISO8601 datetimes, which the Pydantic
    /// `date` validator rejects — so we pre-format the date ourselves.
    private static let dateOnly: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // MARK: - Plan CRUD

    func createPlan(weekStartDate: Date, userId: UUID, name: String) async throws -> MealPlan {
        let body = MealPlanCreateRequest(
            name: name,
            week_start_date: Self.dateOnly.string(from: weekStartDate),
            notes: nil,
            is_template: false
        )
        let dto: MealPlanDTO = try await api.post("/api/v1/meal-plans", body: body)

        // Cache the new (empty) plan so currentPlan() reads it back offline.
        let entity = MealPlanMapper.makeEntity(from: dto, userId: userId,
                                               pendingSync: false, lastSyncedAt: .now)
        context.insert(entity)
        try context.save()
        cacheProductIds(from: dto)
        return MealPlan(from: dto)
    }

    /// Fetch a plan from the backend and upsert it into the cache. Used by
    /// the week view to refresh after a remote change.
    @discardableResult
    func refreshPlan(_ planId: UUID, userId: UUID) async throws -> MealPlan {
        let dto: MealPlanDTO = try await api.get("/api/v1/meal-plans/\(planId.uuidString)")
        try upsertPlan(dto, userId: userId)
        return MealPlan(from: dto)
    }

    // MARK: - Item CRUD

    func addItem(toPlan planId: UUID,
                 dayIndex: Int,
                 mealType: MealType,
                 product: Product,
                 servings: Double) async throws -> MealPlanItem {
        // Optimistic insert: build a local row first so the grid updates
        // immediately. We use a client UUID; the server may return its own,
        // so we reconcile the id after the POST resolves.
        guard let plan = try fetchPlanEntity(planId) else {
            throw APIError.notFound
        }
        let localId = UUID()
        let optimistic = MealPlanItemEntity(
            id: localId, dayIndex: dayIndex, mealType: mealType.rawValue,
            productName: product.name, servings: servings, pendingSync: true
        )
        optimistic.plan = plan
        plan.items.append(optimistic)
        try context.save()
        productIdByItem[localId] = product.id

        let body = MealPlanItemCreateRequest(
            product_id: product.id.uuidString,
            day_of_week: dayIndex,
            meal_type: mealType.rawValue,
            quantity_servings: servings,
            quantity_grams: nil
        )
        do {
            let dto: MealPlanItemDTO = try await api.post(
                "/api/v1/meal-plans/\(planId.uuidString)/items", body: body
            )
            // Reconcile the local row to the server's canonical id.
            let serverId = UUID(uuidString: dto.id) ?? localId
            if serverId != localId {
                optimistic.id = serverId
                productIdByItem[serverId] = product.id
                productIdByItem[localId] = nil
            }
            optimistic.pendingSync = false
            try context.save()
            return MealPlanItem(from: optimistic)
        } catch {
            // Keep the optimistic row (pendingSync=true) for retry.
            throw error
        }
    }

    func moveItem(_ itemId: UUID,
                  toDay dayIndex: Int,
                  mealType: MealType,
                  inPlan planId: UUID) async throws {
        guard let item = try fetchItemEntity(itemId) else { return }

        // Optimistic local move first — the chip relocates immediately.
        let previousDay = item.dayIndex
        let previousType = item.mealType
        item.dayIndex = dayIndex
        item.mealType = mealType.rawValue
        item.pendingSync = true
        try context.save()

        // No item-PATCH server-side: DELETE the old, POST the new. If we
        // never learned the product_id we cannot recreate it remotely.
        guard let productId = productIdByItem[itemId] else {
            // We can't recreate the item server-side without its product_id,
            // so we must NOT delete the server row — doing so would
            // permanently lose the item (the DELETE succeeds online, but the
            // recreate never happens). Keep the optimistic local move with
            // pendingSync=true so a later sync — once the product_id is known
            // (e.g. after currentPlan() repopulates the map from the server) —
            // can replay the move. Losing user input is worse than a stale
            // server row (ADR-0004 §4). The map is repopulated on the next
            // currentPlan() load; see `reconcileProductIdsFromServer`.
            item.pendingSync = true
            try context.save()
            return
        }

        do {
            try await api.delete("/api/v1/meal-plans/\(planId.uuidString)/items/\(itemId.uuidString)")
            let body = MealPlanItemCreateRequest(
                product_id: productId.uuidString,
                day_of_week: dayIndex,
                meal_type: mealType.rawValue,
                quantity_servings: item.servings,
                quantity_grams: nil
            )
            let dto: MealPlanItemDTO = try await api.post(
                "/api/v1/meal-plans/\(planId.uuidString)/items", body: body
            )
            // Rebind the local row to the recreated server id.
            let serverId = UUID(uuidString: dto.id) ?? itemId
            if serverId != itemId {
                item.id = serverId
                productIdByItem[serverId] = productId
                productIdByItem[itemId] = nil
            }
            item.pendingSync = false
            try context.save()
        } catch {
            // Reconciliation failed: keep the optimistic local move but
            // leave pendingSync=true so a retry can replay it. We do NOT
            // revert to (previousDay, previousType) — preserving the
            // user's intent matters more than server agreement here.
            _ = previousDay; _ = previousType
            throw error
        }
    }

    func removeItem(_ itemId: UUID, fromPlan planId: UUID) async throws {
        if let item = try fetchItemEntity(itemId) {
            context.delete(item)
            try context.save()
        }
        productIdByItem[itemId] = nil
        _ = try? await api.delete("/api/v1/meal-plans/\(planId.uuidString)/items/\(itemId.uuidString)")
    }

    // MARK: - Shopping list

    func generateShoppingList(forPlan planId: UUID, userId: UUID) async throws -> [ShoppingItem] {
        let dto: ShoppingListDTO = try await api.get(
            "/api/v1/meal-plans/\(planId.uuidString)/shopping-list"
        )

        // Replace any previously cached list for this plan so regenerating
        // doesn't pile up stale rows.
        let planMealId = UUID(uuidString: dto.meal_plan_id ?? "") ?? planId
        let existing = try context.fetch(FetchDescriptor<ShoppingListEntity>(
            predicate: #Predicate { $0.mealPlanId == planMealId }
        ))
        for old in existing { context.delete(old) }

        let listEntity = ShoppingListEntity(
            id: UUID(uuidString: dto.id) ?? UUID(),
            mealPlanId: planMealId,
            generatedAt: dto.generated_at,
            lastSyncedAt: .now
        )
        listEntity.items = dto.items.map(ShoppingListItemMapper.makeEntity(from:))
        context.insert(listEntity)
        try context.save()

        return dto.items.map(ShoppingItem.init(from:))
    }

    func setChecked(_ itemId: UUID, checked: Bool, listId: UUID) async throws {
        // Optimistic local toggle first.
        if let item = try fetchShoppingItemEntity(itemId) {
            item.checked = checked
            item.pendingSync = true
            try context.save()
        }

        let body = ShoppingItemCheckRequest(is_checked: checked)
        do {
            let _: ShoppingItemCheckResponse = try await api.patch(
                "/api/v1/meal-plans/shopping-lists/\(listId.uuidString)/items/\(itemId.uuidString)/check",
                body: body
            )
            if let item = try fetchShoppingItemEntity(itemId) {
                item.pendingSync = false
                try context.save()
            }
        } catch {
            // Leave the optimistic toggle in place (pendingSync=true).
            throw error
        }
    }

    func currentShoppingListId() async throws -> UUID? {
        var descriptor = FetchDescriptor<ShoppingListEntity>(
            sortBy: [SortDescriptor(\.generatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first?.id
    }

    // MARK: - MealPlanServiceProtocol (read surface)

    func currentPlan() async throws -> MealPlan? {
        var descriptor = FetchDescriptor<MealPlanEntity>(
            sortBy: [SortDescriptor(\.weekStartDate, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        guard let entity = try context.fetch(descriptor).first else { return nil }

        // Repopulate the itemId -> productId map from the server. After a cold
        // launch the map is empty (it lives in memory only — see header note
        // 2), so a move would otherwise hit the "unknown product_id" branch
        // and stay forever-pending. A best-effort GET reconciles it so online
        // moves recreate the item server-side. Failures (offline) are
        // ignored — the cached plan is still returned.
        if productIdByItem.isEmpty {
            await reconcileProductIdsFromServer(planId: entity.id)
        }

        return MealPlan(from: entity)
    }

    /// Best-effort: fetch the plan from the backend purely to recover each
    /// item's `product_id` into the in-memory map. Used by `currentPlan()`
    /// after a cold launch so moves of server-sourced items can replay
    /// server-side. Never throws — a failure just leaves the map empty.
    private func reconcileProductIdsFromServer(planId: UUID) async {
        guard let dto: MealPlanDTO = try? await api.get(
            "/api/v1/meal-plans/\(planId.uuidString)"
        ) else { return }
        cacheProductIds(from: dto)
    }

    func shoppingList() async throws -> [ShoppingItem] {
        var descriptor = FetchDescriptor<ShoppingListEntity>(
            sortBy: [SortDescriptor(\.generatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        guard let list = try context.fetch(descriptor).first else { return [] }
        return list.items
            .sorted { ($0.category, $0.name) < ($1.category, $1.name) }
            .map(ShoppingItem.init(from:))
    }

    func toggleChecked(_ itemId: UUID) async throws {
        guard let item = try fetchShoppingItemEntity(itemId) else { return }
        let listId = item.list?.id
        let newValue = !item.checked
        if let listId {
            try await setChecked(itemId, checked: newValue, listId: listId)
        } else {
            // Orphaned item (no parent list cached): toggle locally only.
            item.checked = newValue
            try context.save()
        }
    }

    // MARK: - Cache helpers

    private func upsertPlan(_ dto: MealPlanDTO, userId: UUID) throws {
        let planId = UUID(uuidString: dto.id) ?? UUID()
        let existing = try context.fetch(FetchDescriptor<MealPlanEntity>(
            predicate: #Predicate { $0.id == planId }
        ))
        for old in existing { context.delete(old) }
        let entity = MealPlanMapper.makeEntity(from: dto, userId: userId,
                                               pendingSync: false, lastSyncedAt: .now)
        context.insert(entity)
        try context.save()
        cacheProductIds(from: dto)
    }

    private func cacheProductIds(from dto: MealPlanDTO) {
        for item in dto.items {
            if let itemId = UUID(uuidString: item.id),
               let productId = UUID(uuidString: item.product_id) {
                productIdByItem[itemId] = productId
            }
        }
    }

    private func fetchPlanEntity(_ id: UUID) throws -> MealPlanEntity? {
        try context.fetch(FetchDescriptor<MealPlanEntity>(
            predicate: #Predicate { $0.id == id }
        )).first
    }

    private func fetchItemEntity(_ id: UUID) throws -> MealPlanItemEntity? {
        try context.fetch(FetchDescriptor<MealPlanItemEntity>(
            predicate: #Predicate { $0.id == id }
        )).first
    }

    private func fetchShoppingItemEntity(_ id: UUID) throws -> ShoppingListItemEntity? {
        try context.fetch(FetchDescriptor<ShoppingListItemEntity>(
            predicate: #Predicate { $0.id == id }
        )).first
    }
}
