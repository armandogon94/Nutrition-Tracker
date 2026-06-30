//
//  LocalDay.swift
//  Single source of truth for "the user's nutrition day" (review B10 / Flash
//  G4). Meal logging and the dashboard's daily nutrition must roll over at the
//  user's LOCAL midnight, not UTC midnight — otherwise a late-evening log in a
//  negative-UTC-offset zone (e.g. Mexico City logging dinner at 20:30) lands on
//  tomorrow's date.
//
//  Everything here derives from the user's CURRENT calendar / timezone:
//    - `dateString(for:)`  → the "yyyy-MM-dd" we send to the backend as the
//      date-only meal_date / nutrition date.
//    - `startOfDay(for:)`  → the local start-of-day Date used for grouping and
//      "today/tomorrow" boundaries.
//    - `cacheKeyDate(for:)` → a Date pinned to UTC-midnight of the LOCAL
//      calendar day. This is what we feed `DailyNutritionEntity.makeKey`
//      (which itself applies UTC-startOfDay and cannot be changed — it lives in
//      the SwiftData schema). The backend returns the date-only nutrition date,
//      which the APIClient decodes as UTC-midnight; pinning the cache key to the
//      same UTC-midnight-of-the-local-day keeps reads and writes on ONE key so
//      the cache actually hits for evening LATAM users.
//

import Foundation

enum LocalDay {

    /// Resolver for the active calendar. Defaults to the user's current
    /// calendar+timezone. A parameter (rather than a hard `Calendar.current`)
    /// so tests can pin a specific timezone deterministically.
    static func calendar(_ timeZone: TimeZone = .current) -> Calendar {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = timeZone
        return cal
    }

    /// "yyyy-MM-dd" for `date` in the user's local calendar — the date-only
    /// value sent to the backend for meal_date / nutrition date.
    static func dateString(for date: Date, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// Local start-of-day for `date` (used for grouping + day boundaries).
    static func startOfDay(for date: Date, timeZone: TimeZone = .current) -> Date {
        calendar(timeZone).startOfDay(for: date)
    }

    /// Local end-of-day exclusive boundary (next local midnight).
    static func nextDay(after date: Date, timeZone: TimeZone = .current) -> Date {
        let cal = calendar(timeZone)
        let start = cal.startOfDay(for: date)
        return cal.date(byAdding: .day, value: 1, to: start) ?? date
    }

    /// A Date pinned to UTC-midnight of the LOCAL calendar day containing
    /// `date`. Feed this to `DailyNutritionEntity.makeKey` so the cache key
    /// matches the backend's date-only round-trip (decoded as UTC-midnight).
    ///
    /// We rebuild the instant from the LOCAL y/m/d components in a UTC calendar,
    /// which is correct regardless of the timezone offset's sign (no fragile
    /// offset arithmetic).
    static func cacheKeyDate(for date: Date, timeZone: TimeZone = .current) -> Date {
        let localComps = calendar(timeZone).dateComponents([.year, .month, .day], from: date)
        var utcCal = Calendar(identifier: .iso8601)
        utcCal.timeZone = TimeZone(identifier: "UTC")!
        var utcComps = DateComponents()
        utcComps.year = localComps.year
        utcComps.month = localComps.month
        utcComps.day = localComps.day
        return utcCal.date(from: utcComps) ?? date
    }
}
