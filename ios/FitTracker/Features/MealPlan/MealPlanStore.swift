//
//  MealPlanStore.swift
//  Slice 4.2/4.3: @Observable view model that owns the weekly-planner
//  state and brokers every mutation through MealPlanService. Holding the
//  plan here (rather than in each cell) keeps drag/drop re-renders scoped:
//  cells read their slice via `items(forDay:mealType:)` and only the moved
//  chips' cells recompute.
//
//  The store is constructed by MealPlanWeekView from the SwiftData
//  modelContext + a live APIClient. In previews/tests with the mock
//  container it falls back to MockData so the grid is never blank.
//

import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class MealPlanStore {

    private let service: any MealPlanningServiceProtocol
    private let userId: UUID

    /// The week currently shown (Monday 00:00 UTC).
    private(set) var weekStart: Date
    /// The active plan for the shown week, if one exists.
    private(set) var plan: MealPlan?
    /// True while a network mutation is in flight (drives subtle UI).
    private(set) var isBusy = false
    /// Last user-facing error message, if any.
    var errorMessage: String?

    init(service: any MealPlanningServiceProtocol,
         userId: UUID,
         weekStart: Date = MealPlanWeek.weekStart(for: .now)) {
        self.service = service
        self.userId = userId
        self.weekStart = weekStart
    }

    /// Convenience builder used by views: wires the real MealPlanService to
    /// the live SwiftData context. `userId` falls back to a stable mock id
    /// when no session is available (previews / Slice 0.5 tap-through).
    static func live(context: ModelContext,
                     userId: UUID = MockData.user.id) -> MealPlanStore {
        let service = MealPlanService(api: APIClient(), context: context)
        return MealPlanStore(service: service, userId: userId)
    }

    var headerLabel: String { MealPlanWeek.headerLabel(for: weekStart) }

    /// Items for one grid cell (day × meal slot).
    func items(forDay index: Int, mealType: MealType) -> [MealPlanItem] {
        guard let plan else { return [] }
        return MealPlanWeek.items(forDay: index, mealType: mealType, in: plan)
    }

    // MARK: - Loading

    /// Load the cached plan for the current week. Read-through: SwiftData
    /// first; a fresh launch with no plan yields nil (UI shows the create
    /// affordance).
    func load() async {
        do {
            plan = try await service.currentPlan()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func goToPreviousWeek() async {
        weekStart = MealPlanWeek.previous(weekStart)
        await load()
    }

    func goToNextWeek() async {
        weekStart = MealPlanWeek.next(weekStart)
        await load()
    }

    // MARK: - Mutations

    func createPlanForCurrentWeek() async {
        isBusy = true
        defer { isBusy = false }
        do {
            plan = try await service.createPlan(
                weekStartDate: weekStart,
                userId: userId,
                name: MealPlanWeek.headerLabel(for: weekStart)
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addItem(product: Product, servings: Double, day: Int, mealType: MealType) async {
        guard let planId = plan?.id else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            _ = try await service.addItem(toPlan: planId, dayIndex: day,
                                          mealType: mealType, product: product,
                                          servings: servings)
            await load()
        } catch {
            // The optimistic row persists locally; surface a soft notice.
            await load()
            errorMessage = error.localizedDescription
        }
    }

    func move(itemId: UUID, toDay day: Int, mealType: MealType) async {
        guard let planId = plan?.id else { return }
        do {
            try await service.moveItem(itemId, toDay: day, mealType: mealType, inPlan: planId)
            await load()
        } catch {
            await load()
            errorMessage = error.localizedDescription
        }
    }

    func remove(itemId: UUID) async {
        guard let planId = plan?.id else { return }
        do {
            try await service.removeItem(itemId, fromPlan: planId)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Generate the shopping list for the active plan and return the items
    /// (so the caller can navigate straight into the list). Returns nil if
    /// there is no plan.
    @discardableResult
    func generateShoppingList() async -> [ShoppingItem]? {
        guard let planId = plan?.id else { return nil }
        isBusy = true
        defer { isBusy = false }
        do {
            return try await service.generateShoppingList(forPlan: planId, userId: userId)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}
