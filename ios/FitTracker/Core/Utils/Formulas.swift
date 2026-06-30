//
//  Formulas.swift
//  Shared strength-training math, kept in ONE place so the on-device
//  computation can never drift from itself or from the backend.
//
//  `estimate1RM` previously lived verbatim in both HistoryService and
//  WorkoutService (review Flash F2). It now lives here; those services call
//  through so their public `estimate1RM(weightKg:reps:)` surface (used by
//  MockServices, views, and tests) is preserved.
//

import Foundation

enum Formulas {

    /// Estimated one-rep max = the average of the Brzycki and Epley formulas.
    /// Accurate in the 2–10 rep range (per CLAUDE.md). MUST stay identical to
    /// `backend/app/services/workout_service.py` so the on-device PR list and a
    /// server-computed list agree.
    ///
    /// - `reps <= 0` or `weightKg <= 0` → 0 (not a valid lift to compare).
    /// - `reps == 1` → the weight itself (a true 1RM).
    /// - `reps >= 37` is capped to 36 to avoid Brzycki's divide-by-zero at 37.
    /// - Result is rounded to 1 decimal with banker's rounding (half-to-even)
    ///   to match Python's `round()` exactly.
    static func estimate1RM(weightKg: Double, reps: Int) -> Double {
        guard weightKg > 0, reps > 0 else { return 0 }
        if reps == 1 { return weightKg }
        let r = Double(min(reps, 36))
        let brzycki = weightKg * (36.0 / (37.0 - r))
        let epley = weightKg * (1.0 + r / 30.0)
        return ((brzycki + epley) / 2 * 10).rounded(.toNearestOrEven) / 10
    }
}
