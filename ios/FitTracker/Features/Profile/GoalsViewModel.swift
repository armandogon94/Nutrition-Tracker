//
//  GoalsViewModel.swift
//  Slice 5.4 — pure decision logic for GoalsView: preset → concrete
//  NutritionGoal (via the shared TDEECalculator), and custom-goal warnings
//  (sex-specific calorie floor + 0.8 g/kg protein minimum). Kept free of
//  SwiftUI so it's unit-testable; the view binds to these results.
//

import Foundation

/// Non-blocking advisories shown under the custom-goal editor. They warn but
/// never prevent saving — the backend enforces hard bounds separately.
enum GoalWarning: Hashable, Sendable {
    case lowCalories   // below the sex-specific floor (1200 F / 1500 M)
    case lowProtein    // below 0.8 g per kg bodyweight
    case lowCarbs      // below the 100 g/day floor (CLAUDE.md)
}

enum GoalsViewModel {

    /// Per-sex daily-calorie floor below which we warn. Mirrors CLAUDE.md
    /// ("Warn if calories < 1200/1500") and the Slice 5 plan.
    static func calorieFloor(for sex: Sex) -> Int {
        sex == .male ? 1500 : 1200
    }

    /// Minimum advisable protein: 0.8 g per kg bodyweight (RDA baseline).
    static let proteinPerKgFloor: Double = 0.8

    /// Daily-carb floor below which we warn. Mirrors CLAUDE.md ("Warn if …
    /// carbs < 100g") — very-low-carb targets are flagged, never blocked.
    static let carbFloorGrams = 100

    /// The concrete macro target for a preset, given the user's TDEE and
    /// bodyweight. Delegates entirely to `TDEECalculator.macros` so presets
    /// stay in lock-step with the backend (and with the ProfileView preview).
    static func presetGoal(for preset: GoalPreset, tdee: Double, weightKg: Double) -> NutritionGoal {
        TDEECalculator.macros(tdee: tdee, goal: preset, weightKg: weightKg)
    }

    /// Advisory warnings for a custom (hand-edited) goal. Empty when the goal
    /// looks healthy.
    static func warnings(for goal: NutritionGoal, sex: Sex, weightKg: Double) -> Set<GoalWarning> {
        var result: Set<GoalWarning> = []
        if goal.dailyCalories < calorieFloor(for: sex) {
            result.insert(.lowCalories)
        }
        if Double(goal.proteinG) < weightKg * proteinPerKgFloor {
            result.insert(.lowProtein)
        }
        if goal.carbsG < carbFloorGrams {
            result.insert(.lowCarbs)
        }
        return result
    }
}
