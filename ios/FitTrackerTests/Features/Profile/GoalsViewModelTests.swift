//
//  GoalsViewModelTests.swift
//  Slice 5.4 — GoalsView preset + custom logic, promoted off the Slice 0.5
//  hardcoded arrays onto the real `GoalPreset` + `TDEECalculator`. Pure
//  decision logic lives in `GoalsViewModel` so it's testable without SwiftUI.
//
//  Covered:
//    - preset goal = TDEECalculator.macros(tdee, preset, weight)
//    - preset calorie deltas (fat loss −500, maintenance 0, etc.)
//    - custom-goal warnings: low calories (sex-specific floor), low protein
//

import Foundation
import Testing
@testable import FitTracker

@Suite("GoalsViewModel (Slice 5.4)")
struct GoalsViewModelTests {

    // MARK: - Presets

    @Test("Preset goal equals TDEECalculator.macros for that preset")
    func presetGoal_matchesCalculator() {
        let tdee = 2759.0
        let goal = GoalsViewModel.presetGoal(for: .fatLoss, tdee: tdee, weightKg: 80)
        let expected = TDEECalculator.macros(tdee: tdee, goal: .fatLoss, weightKg: 80)
        #expect(goal == expected)
    }

    @Test("Maintenance preset keeps calories at TDEE; fat loss subtracts 500")
    func presetGoal_calorieDeltas() {
        let tdee = 2500.0
        let maintenance = GoalsViewModel.presetGoal(for: .maintenance, tdee: tdee, weightKg: 80)
        let fatLoss = GoalsViewModel.presetGoal(for: .fatLoss, tdee: tdee, weightKg: 80)
        let leanBulk = GoalsViewModel.presetGoal(for: .leanBulk, tdee: tdee, weightKg: 80)
        #expect(maintenance.dailyCalories == 2500)
        #expect(fatLoss.dailyCalories == 2000)   // −500
        #expect(leanBulk.dailyCalories == 2750)  // +250
    }

    @Test("Calorie floor (1200) is enforced even with an aggressive deficit")
    func presetGoal_respectsFloor() {
        // TDEE 1500 − 500 = 1000, clamped up to the 1200 floor.
        let goal = GoalsViewModel.presetGoal(for: .fatLoss, tdee: 1500, weightKg: 60)
        #expect(goal.dailyCalories == 1200)
    }

    // MARK: - Custom-goal warnings

    @Test("Low calories warn below the female floor (1200)")
    func warnings_lowCaloriesFemale() {
        let goal = NutritionGoal(dailyCalories: 1100, proteinG: 120, carbsG: 100, fatG: 40, fiberG: 0)
        let warnings = GoalsViewModel.warnings(for: goal, sex: .female, weightKg: 60)
        #expect(warnings.contains(.lowCalories))
    }

    @Test("1300 kcal is fine for a female (>1200) but low for a male (<1500)")
    func warnings_calorieFloorIsSexSpecific() {
        let goal = NutritionGoal(dailyCalories: 1300, proteinG: 130, carbsG: 120, fatG: 40, fiberG: 0)
        let female = GoalsViewModel.warnings(for: goal, sex: .female, weightKg: 60)
        let male = GoalsViewModel.warnings(for: goal, sex: .male, weightKg: 70)
        #expect(!female.contains(.lowCalories), "1300 ≥ 1200 female floor")
        #expect(male.contains(.lowCalories), "1300 < 1500 male floor")
    }

    @Test("Low protein warns below 0.8 g/kg bodyweight")
    func warnings_lowProtein() {
        // 80 kg × 0.8 = 64 g minimum. 50 g is too low.
        let goal = NutritionGoal(dailyCalories: 2200, proteinG: 50, carbsG: 250, fatG: 70, fiberG: 0)
        let warnings = GoalsViewModel.warnings(for: goal, sex: .male, weightKg: 80)
        #expect(warnings.contains(.lowProtein))
    }

    @Test("A balanced custom goal produces no warnings")
    func warnings_none() {
        let goal = NutritionGoal(dailyCalories: 2200, proteinG: 170, carbsG: 230, fatG: 70, fiberG: 25)
        let warnings = GoalsViewModel.warnings(for: goal, sex: .male, weightKg: 80)
        #expect(warnings.isEmpty)
    }
}
