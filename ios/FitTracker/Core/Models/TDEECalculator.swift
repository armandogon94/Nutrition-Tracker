//
//  TDEECalculator.swift
//  Pure-Swift mirror of `backend/app/services/tdee_calculator.py`. Used by
//  the profile form to render BMR/TDEE/macros live as the user adjusts
//  fields — no network round-trip in the preview path. Backend is the
//  source of truth on save: server recalculates and returns its numbers,
//  iOS rehydrates from that response.
//
//  Parity is enforced by `TDEECalculatorTests.backendFixtureParity`: a
//  JSON fixture exported by the backend is loaded at test time and every
//  case must round-trip iOS → match backend within 0.5 kcal.
//
//  If the backend formula changes, run:
//      cd backend && PYTHONPATH=. uv run python scripts/export_tdee_fixtures.py
//  …then update the iOS implementation until tests go green.
//

import Foundation

// MARK: - Goal preset (mirrors backend GoalPreset enum)

enum GoalPreset: String, CaseIterable, Hashable, Sendable {
    case fatLoss      // -500
    case maintenance  //  0
    case leanBulk     // +250
    case muscleGain   // +500

    /// Calorie adjustment in kcal applied on top of TDEE.
    var calorieAdjustment: Int {
        switch self {
        case .fatLoss:     return -500
        case .maintenance: return 0
        case .leanBulk:    return 250
        case .muscleGain:  return 500
        }
    }

    /// Human-readable label key (resolved against Localizable.xcstrings).
    var labelKey: String.LocalizationValue {
        switch self {
        case .fatLoss:     return "goal.preset.fatLoss"
        case .maintenance: return "goal.preset.maintenance"
        case .leanBulk:    return "goal.preset.leanBulk"
        case .muscleGain:  return "goal.preset.muscleGain"
        }
    }

    /// Hint label key — e.g. "−500 kcal", "+250 kcal".
    var hintKey: String.LocalizationValue {
        switch self {
        case .fatLoss:     return "goal.preset.hint.fatLoss"
        case .maintenance: return "goal.preset.hint.maintenance"
        case .leanBulk:    return "goal.preset.hint.leanBulk"
        case .muscleGain:  return "goal.preset.hint.muscleGain"
        }
    }

    /// Wire format for the backend (snake_case enum value).
    var wireValue: String {
        switch self {
        case .fatLoss:     return "fat_loss"
        case .maintenance: return "maintenance"
        case .leanBulk:    return "lean_bulk"
        case .muscleGain:  return "muscle_gain"
        }
    }

    /// Reverse map from a backend wire value, falling back to .maintenance
    /// for unknown strings (forward-compatible with future backend presets).
    static func from(backendValue: String) -> GoalPreset {
        switch backendValue {
        case "fat_loss":     return .fatLoss
        case "maintenance":  return .maintenance
        case "lean_bulk":    return .leanBulk
        case "muscle_gain":  return .muscleGain
        default:             return .maintenance
        }
    }
}

// MARK: - ActivityLevel wire mapping

extension ActivityLevel {
    /// The backend uses snake_case enum values: `very_active` instead of
    /// `veryActive`. Centralizing the conversion keeps both directions
    /// honest.
    var wireValue: String {
        switch self {
        case .sedentary:  return "sedentary"
        case .light:      return "light"
        case .moderate:   return "moderate"
        case .active:     return "active"
        case .veryActive: return "very_active"
        }
    }

    static func from(backendValue: String) -> ActivityLevel {
        switch backendValue {
        case "sedentary":   return .sedentary
        case "light":       return .light
        case "moderate":    return .moderate
        case "active":      return .active
        case "very_active": return .veryActive
        default:            return .moderate
        }
    }
}

// MARK: - Sex wire mapping

extension Sex {
    /// Backend accepts only "male" or "female" (Pydantic regex). `.other`
    /// follows the female (-161) Mifflin-St Jeor branch and is sent as
    /// "female" to the server, matching the calculator's non-male path.
    var wireValue: String {
        switch self {
        case .male:        return "male"
        case .female:      return "female"
        case .other:       return "female"
        }
    }
}

// MARK: - TDEECalculator

enum TDEECalculator {

    /// Activity multipliers — keep in lock-step with backend
    /// `ACTIVITY_MULTIPLIERS`. Unit-tested in `tdee_allMultipliers`.
    static let activityMultiplier: [ActivityLevel: Double] = [
        .sedentary:  1.2,
        .light:      1.375,
        .moderate:   1.55,
        .active:     1.725,
        .veryActive: 1.9,
    ]

    /// Macro split: protein 2g/kg bodyweight, fat 25% of calories,
    /// carbs the remainder. Same formula as backend `calculate_macros`.
    static let proteinPerKg: Double = 2.0
    static let fatCalorieFraction: Double = 0.25
    static let calorieFloor: Int = 1200

    // MARK: BMR

    /// Mifflin-St Jeor BMR. Mirrors `calculate_bmr` exactly:
    ///     BMR = 10·kg + 6.25·cm − 5·age + (5 if male else −161)
    static func bmr(weightKg: Double, heightCm: Double, age: Int, sex: Sex) -> Double {
        let sexFactor: Double = (sex == .male) ? 5.0 : -161.0
        return (10 * weightKg) + (6.25 * heightCm) - (5 * Double(age)) + sexFactor
    }

    // MARK: TDEE

    /// BMR × activity multiplier.
    static func tdee(bmr: Double, activity: ActivityLevel) -> Double {
        bmr * (activityMultiplier[activity] ?? 1.55)
    }

    // MARK: Macros

    /// Daily macro targets given a TDEE, goal preset, and bodyweight.
    /// Matches backend `calculate_macros`:
    ///   - target = max(tdee + adjustment, 1200 floor)
    ///   - protein = weight·2 grams (always — even if calories were clamped)
    ///   - fat     = (target·0.25)/9 grams
    ///   - carbs   = (target − protein·4 − fat·9)/4 grams (non-negative)
    /// All three macro grams are floored to integers (matches Python `int()`,
    /// which truncates toward zero for positive values).
    static func macros(tdee: Double, goal: GoalPreset, weightKg: Double) -> NutritionGoal {
        let targetForMacroMath = max(tdee + Double(goal.calorieAdjustment),
                                     Double(calorieFloor))

        // Keep protein and fat as Double through the carbs subtraction so
        // we match the backend's order of operations exactly. The backend
        // casts to int only at the response boundary; truncating earlier
        // produces a 1–2g carbs drift on non-integer weights/calories.
        let proteinRaw = weightKg * proteinPerKg
        let fatRaw = targetForMacroMath * fatCalorieFraction / 9.0
        let carbsRaw = (targetForMacroMath
                        - proteinRaw * 4.0
                        - fatRaw * 9.0) / 4.0

        return NutritionGoal(
            dailyCalories: Int(targetForMacroMath),
            proteinG: Int(proteinRaw),
            carbsG: Int(max(carbsRaw, 0)),
            fatG: Int(fatRaw),
            fiberG: 0
        )
    }

    // MARK: - Validation (mirrors backend Pydantic Field constraints)

    /// Mirrors backend `ProfileCreate` constraints. We use 30-250 kg / 100-230
    /// cm / 13-120 yr per the slice plan; backend's wider Pydantic bounds
    /// (20-300 / 100-250 / 13-120) accept anything iOS accepts. Tighter iOS
    /// limits give a friendlier UX and surface bad input before a server
    /// round-trip.
    static let weightRange: ClosedRange<Double> = 30...250
    static let heightRange: ClosedRange<Double> = 100...230
    static let ageRange:    ClosedRange<Int>    = 13...120

    static func validate(_ profile: UserProfile) -> ProfileError? {
        if !weightRange.contains(profile.weightKg) { return .weightOutOfRange }
        if !heightRange.contains(profile.heightCm) { return .heightOutOfRange }
        if !ageRange.contains(profile.age)         { return .ageOutOfRange }
        return nil
    }
}
