//
//  HistoryViewLogicTests.swift
//  Slice 8.2 / 8.5: pure view-logic helpers — calendar month grid and PR
//  sorting. Kept free of SwiftUI so they run fast and headless.
//

import Foundation
import Testing
@testable import FitTracker

@Suite("HistoryViewLogic")
struct HistoryViewLogicTests {

    // MARK: - Calendar month grid

    @Test("CalendarMonth lays out leading blanks so day 1 sits under its weekday")
    func calendarMonth_leadingBlanks() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        cal.firstWeekday = 2 // Monday-first (es_419 convention)
        // June 2026: June 1 is a Monday → zero leading blanks with Monday-first.
        let anchor = cal.date(from: DateComponents(year: 2026, month: 6, day: 15))!
        let month = CalendarMonth(monthContaining: anchor, calendar: cal, daysWithSessions: [])
        #expect(month.leadingBlankCount == 0)
        #expect(month.dayCount == 30)
    }

    @Test("CalendarMonth flags days that have sessions")
    func calendarMonth_marksSessionDays() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        cal.firstWeekday = 2
        let anchor = cal.date(from: DateComponents(year: 2026, month: 6, day: 1))!
        let day10 = cal.date(from: DateComponents(year: 2026, month: 6, day: 10))!
        let month = CalendarMonth(monthContaining: anchor, calendar: cal,
                                  daysWithSessions: [day10])
        #expect(month.hasSession(day: 10))
        #expect(!month.hasSession(day: 11))
    }

    @Test("CalendarMonth previous/next shift the visible month")
    func calendarMonth_navigation() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        cal.firstWeekday = 2
        let anchor = cal.date(from: DateComponents(year: 2026, month: 6, day: 15))!
        let month = CalendarMonth(monthContaining: anchor, calendar: cal, daysWithSessions: [])
        let prev = month.previousMonth()
        let next = month.nextMonth()
        #expect(cal.component(.month, from: prev.firstOfMonth) == 5)
        #expect(cal.component(.month, from: next.firstOfMonth) == 7)
    }

    // MARK: - PR sorting

    private func pr(_ name: String, weight: Double, reps: Int, daysAgo: Int) -> ExercisePR {
        ExercisePR(exerciseId: UUID(), exerciseName: name, weightKg: weight, reps: reps,
                   estimated1RM: HistoryService.estimate1RM(weightKg: weight, reps: reps),
                   achievedAt: Date(timeIntervalSinceNow: -Double(daysAgo) * 86400))
    }

    @Test("PRSort.byWeight orders heaviest first")
    func prSort_byWeight() {
        let prs = [pr("A", weight: 80, reps: 5, daysAgo: 1),
                   pr("B", weight: 120, reps: 3, daysAgo: 2),
                   pr("C", weight: 100, reps: 5, daysAgo: 3)]
        let sorted = PRSort.byWeight.apply(prs)
        #expect(sorted.map(\.weightKg) == [120, 100, 80])
    }

    @Test("PRSort.byDate orders most recent first")
    func prSort_byDate() {
        let prs = [pr("A", weight: 80, reps: 5, daysAgo: 10),
                   pr("B", weight: 120, reps: 3, daysAgo: 1),
                   pr("C", weight: 100, reps: 5, daysAgo: 5)]
        let sorted = PRSort.byDate.apply(prs)
        #expect(sorted.map(\.exerciseName) == ["B", "C", "A"])
    }

    @Test("PRSort.byName orders alphabetically, locale-aware")
    func prSort_byName() {
        let prs = [pr("Sentadilla", weight: 120, reps: 5, daysAgo: 1),
                   pr("Press banca", weight: 100, reps: 5, daysAgo: 2),
                   pr("Dominadas", weight: 20, reps: 8, daysAgo: 3)]
        let sorted = PRSort.byName.apply(prs)
        #expect(sorted.map(\.exerciseName) == ["Dominadas", "Press banca", "Sentadilla"])
    }
}
