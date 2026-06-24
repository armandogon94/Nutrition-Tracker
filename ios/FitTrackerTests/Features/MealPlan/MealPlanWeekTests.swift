//
//  MealPlanWeekTests.swift
//  Slice 4.2: pure week-math + grid-grouping helpers behind the weekly
//  planner. The SwiftUI drag/drop itself is exercised by integration +
//  manual QA (see plan), but the date arithmetic and the day×slot lookup
//  are deterministic and unit-tested here.
//

import Foundation
import Testing
@testable import FitTracker

@Suite("MealPlanWeek")
struct MealPlanWeekTests {

    private func utc(_ s: String) -> Date {
        ISO8601DateFormatter().date(from: s)!
    }

    @Test("weekStart snaps any date back to the Monday 00:00 UTC of its week")
    func weekStart_snapsToMonday() {
        // 2026-04-22 is a Wednesday. Monday of that week is 2026-04-20.
        let wed = utc("2026-04-22T15:30:00Z")
        let start = MealPlanWeek.weekStart(for: wed)
        #expect(start == utc("2026-04-20T00:00:00Z"))

        // A Monday maps to itself (start of day).
        let mon = utc("2026-04-20T09:00:00Z")
        #expect(MealPlanWeek.weekStart(for: mon) == utc("2026-04-20T00:00:00Z"))

        // A Sunday maps back to the prior Monday, not forward.
        let sun = utc("2026-04-26T23:59:00Z")
        #expect(MealPlanWeek.weekStart(for: sun) == utc("2026-04-20T00:00:00Z"))
    }

    @Test("advancing/regressing a week moves exactly 7 days")
    func week_navigation() {
        let start = utc("2026-04-20T00:00:00Z")
        #expect(MealPlanWeek.next(start) == utc("2026-04-27T00:00:00Z"))
        #expect(MealPlanWeek.previous(start) == utc("2026-04-13T00:00:00Z"))
    }

    @Test("date(forDay:in:) returns the Nth day of the week")
    func date_forDay() {
        let start = utc("2026-04-20T00:00:00Z")    // Monday
        #expect(MealPlanWeek.date(forDay: 0, in: start) == utc("2026-04-20T00:00:00Z"))
        #expect(MealPlanWeek.date(forDay: 6, in: start) == utc("2026-04-26T00:00:00Z"))
    }

    @Test("items(forDay:mealType:in:) filters a plan to a single grid cell")
    func grid_cellLookup() {
        let plan = MealPlan(
            id: UUID(),
            weekStartDate: utc("2026-04-20T00:00:00Z"),
            items: [
                MealPlanItem(id: UUID(), dayIndex: 0, mealType: .breakfast, productName: "Avena", servings: 1),
                MealPlanItem(id: UUID(), dayIndex: 0, mealType: .breakfast, productName: "Plátano", servings: 1),
                MealPlanItem(id: UUID(), dayIndex: 2, mealType: .dinner, productName: "Pollo", servings: 1.5)
            ]
        )
        let mondayBreakfast = MealPlanWeek.items(forDay: 0, mealType: .breakfast, in: plan)
        #expect(mondayBreakfast.count == 2)

        let mondayDinner = MealPlanWeek.items(forDay: 0, mealType: .dinner, in: plan)
        #expect(mondayDinner.isEmpty)

        let wedDinner = MealPlanWeek.items(forDay: 2, mealType: .dinner, in: plan)
        #expect(wedDinner.first?.productName == "Pollo")
    }

    @Test("shortLabel(forDay:) yields Spanish weekday abbreviations Mon..Sun")
    func dayLabels() {
        #expect(MealPlanWeek.shortLabel(forDay: 0) == "Lun")
        #expect(MealPlanWeek.shortLabel(forDay: 5) == "Sáb")
        #expect(MealPlanWeek.shortLabel(forDay: 6) == "Dom")
    }
}
