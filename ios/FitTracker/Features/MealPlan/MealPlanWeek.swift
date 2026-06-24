//
//  MealPlanWeek.swift
//  Slice 4.2: pure, testable helpers for the weekly planner — week-start
//  math, day navigation, grid-cell lookups, and Spanish weekday labels.
//
//  All date math uses an ISO-8601 calendar pinned to UTC so a plan's
//  `weekStartDate` is stable regardless of the device timezone (mirrors
//  the DailyNutrition composite-key rationale in Schema.swift / ADR-0004).
//  Days run Monday(0)..Sunday(6) to match the backend's `day_of_week`.
//

import Foundation

enum MealPlanWeek {

    /// ISO-8601 calendar in UTC. `.iso8601` already treats Monday as the
    /// first weekday, which is exactly the convention the backend uses.
    static var calendar: Calendar {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    /// The Monday 00:00 UTC that starts the week containing `date`.
    static func weekStart(for date: Date) -> Date {
        let cal = calendar
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return cal.date(from: comps) ?? cal.startOfDay(for: date)
    }

    /// The week start exactly 7 days after `weekStart`.
    static func next(_ weekStart: Date) -> Date {
        calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
    }

    /// The week start exactly 7 days before `weekStart`.
    static func previous(_ weekStart: Date) -> Date {
        calendar.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart
    }

    /// The calendar date of day `index` (0=Mon..6=Sun) within the week.
    static func date(forDay index: Int, in weekStart: Date) -> Date {
        calendar.date(byAdding: .day, value: index, to: weekStart) ?? weekStart
    }

    /// All items assigned to one grid cell (a single day × meal slot).
    static func items(forDay index: Int, mealType: MealType, in plan: MealPlan) -> [MealPlanItem] {
        plan.items.filter { $0.dayIndex == index && $0.mealType == mealType }
    }

    /// Spanish three-letter weekday abbreviation for day `index` (0=Mon).
    static func shortLabel(forDay index: Int) -> String {
        let labels = ["Lun", "Mar", "Mié", "Jue", "Vie", "Sáb", "Dom"]
        guard labels.indices.contains(index) else { return "" }
        return labels[index]
    }

    /// Spanish full weekday name for day `index` (0=Mon).
    static func fullLabel(forDay index: Int) -> String {
        let labels = ["Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado", "Domingo"]
        guard labels.indices.contains(index) else { return "" }
        return labels[index]
    }

    /// Human label for the week header, e.g. "Semana del 20 abr".
    static func headerLabel(for weekStart: Date) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = Locale(identifier: "es")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "d MMM"
        return "Semana del \(f.string(from: weekStart))"
    }
}
