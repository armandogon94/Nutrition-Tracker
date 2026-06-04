//
//  HistoryCalendarModel.swift
//  Slice 8.2 / 8.5: pure value types backing the calendar grid and PR
//  sorting. No SwiftUI here so they're trivially unit-testable and cheap.
//

import Foundation

// MARK: - Calendar month

/// One month's worth of calendar layout for `HistoryCalendarView`. Computes
/// the leading blank cells (so day 1 lands under the right weekday) and
/// which days carry a logged workout, given a calendar and the set of
/// session dates. Immutable; `previousMonth()`/`nextMonth()` return new
/// instances so the view can drive navigation with a single `@State`.
struct CalendarMonth: Equatable {
    let firstOfMonth: Date
    let dayCount: Int
    /// 0...6 — blank cells before day 1, honoring `calendar.firstWeekday`.
    let leadingBlankCount: Int
    /// Day-of-month numbers (1-based) that have at least one session.
    private let sessionDays: Set<Int>
    private let calendar: Calendar

    init(monthContaining date: Date, calendar: Calendar, daysWithSessions: [Date]) {
        self.calendar = calendar
        let comps = calendar.dateComponents([.year, .month], from: date)
        let first = calendar.date(from: comps) ?? calendar.startOfDay(for: date)
        self.firstOfMonth = first
        self.dayCount = calendar.range(of: .day, in: .month, for: first)?.count ?? 30

        // Leading blanks: weekday of the 1st, normalised to firstWeekday.
        let weekday = calendar.component(.weekday, from: first) // 1...7
        self.leadingBlankCount = (weekday - calendar.firstWeekday + 7) % 7

        // Which days (within THIS month) have sessions.
        var marked = Set<Int>()
        for d in daysWithSessions where calendar.isDate(d, equalTo: first, toGranularity: .month) {
            marked.insert(calendar.component(.day, from: d))
        }
        self.sessionDays = marked
    }

    func hasSession(day: Int) -> Bool { sessionDays.contains(day) }

    /// The concrete `Date` for a given day-of-month in this month.
    func date(forDay day: Int) -> Date? {
        calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth)
    }

    func previousMonth() -> CalendarMonth {
        let prev = calendar.date(byAdding: .month, value: -1, to: firstOfMonth) ?? firstOfMonth
        return CalendarMonth(monthContaining: prev, calendar: calendar,
                             daysWithSessions: sessionDates())
    }

    func nextMonth() -> CalendarMonth {
        let next = calendar.date(byAdding: .month, value: 1, to: firstOfMonth) ?? firstOfMonth
        return CalendarMonth(monthContaining: next, calendar: calendar,
                             daysWithSessions: sessionDates())
    }

    /// Localized "June 2026"-style title.
    func title(locale: Locale) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return f.string(from: firstOfMonth).capitalized(with: locale)
    }

    /// Re-expand the marked day numbers back into Dates so month-navigation
    /// preserves the same session set (it's re-filtered to the new month).
    private func sessionDates() -> [Date] {
        sessionDays.compactMap { date(forDay: $0) }
    }

    static func == (lhs: CalendarMonth, rhs: CalendarMonth) -> Bool {
        lhs.firstOfMonth == rhs.firstOfMonth && lhs.sessionDays == rhs.sessionDays
    }
}

// MARK: - PR sort

/// Sort orders offered by `PRListView`'s segmented toggle.
enum PRSort: String, CaseIterable, Hashable {
    case byWeight
    case byDate
    case byName

    /// Localization key for the segment label.
    var labelKey: String {
        switch self {
        case .byWeight: "history.pr.sort.weight"
        case .byDate:   "history.pr.sort.date"
        case .byName:   "history.pr.sort.name"
        }
    }

    func apply(_ prs: [ExercisePR]) -> [ExercisePR] {
        switch self {
        case .byWeight:
            return prs.sorted { $0.weightKg > $1.weightKg }
        case .byDate:
            return prs.sorted { $0.achievedAt > $1.achievedAt }
        case .byName:
            return prs.sorted {
                $0.exerciseName.localizedCaseInsensitiveCompare($1.exerciseName) == .orderedAscending
            }
        }
    }
}
