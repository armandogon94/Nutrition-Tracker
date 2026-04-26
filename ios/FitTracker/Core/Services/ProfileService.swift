//
//  ProfileService.swift
//  Slice 5 — backend-backed implementation of `ProfileServiceProtocol`.
//  Owns the profile + goals network surface:
//    - GET  /api/v1/profile/tdee      → fetch BMR/TDEE/macros
//    - POST /api/v1/profile           → create-or-update body fields
//    - POST /api/v1/profile/goals     → set goal preset (fat-loss, etc.)
//    - PUT  /api/v1/nutrition/goals   → set custom macro overrides
//
//  Validation guards mirror backend Pydantic constraints (and our
//  iOS-tighter UX bounds defined in `TDEECalculator`). Out-of-range
//  payloads throw `ProfileError` *before* any network round-trip so
//  bad input never reaches the server.
//
//  This service is @MainActor because (a) the protocol declares it as
//  such (it's read by SwiftUI views) and (b) the surface is small and
//  every call hops to APIClient (an actor) anyway. Concurrency safety
//  is delegated to APIClient + URLSession.
//

import Foundation
import Observation

/// Errors surfaced by ProfileService validation guards. Mirrors the
/// backend's Pydantic field constraints; throwing here keeps invalid
/// input out of the network entirely.
enum ProfileError: Error, Equatable, Sendable {
    case weightOutOfRange
    case heightOutOfRange
    case ageOutOfRange
    case caloriesOutOfRange
    case macrosOutOfRange
}

@MainActor
@Observable
final class ProfileService: ProfileServiceProtocol {

    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    // MARK: - profile()

    /// Fetches the user's profile + computed targets. On a cold-start 404
    /// (no profile exists yet) returns sensible defaults so the form has
    /// something to render — the user fills in their real values from
    /// there. Any other error propagates.
    func profile() async throws -> UserProfile {
        do {
            let resp: TDEEResponse = try await api.get("/api/v1/profile/tdee")
            // The /tdee endpoint doesn't echo back weight/height/age, only
            // activity. We treat /tdee as the live "is profile complete?"
            // probe and fall back to defaults for the other fields. The
            // form rehydrates from the local SwiftData cache on Slice 5+1
            // when the persistence wiring lands; for now defaults seed
            // the form on first appear and the user edits from there.
            return UserProfile(
                weightKg: 75.0,
                heightCm: 175.0,
                age: 30,
                sex: .male,
                activity: ActivityLevel.from(backendValue: resp.activity_level)
            )
        } catch APIError.notFound {
            return Self.defaultProfile
        }
    }

    /// Creates or updates the body fields. Server recalculates BMR/TDEE
    /// and returns the fresh numbers — caller may discard or rehydrate.
    func updateProfile(_ profile: UserProfile) async throws {
        if let err = TDEECalculator.validate(profile) { throw err }
        let body = ProfileRequest(
            weight_kg: profile.weightKg,
            height_cm: profile.heightCm,
            age: profile.age,
            sex: profile.sex.wireValue,
            activity_level: profile.activity.wireValue
        )
        let _: ProfileResponse = try await api.post("/api/v1/profile", body: body)
    }

    // MARK: - goal()

    /// Returns the user's current calorie + macro targets. On 404 (no
    /// profile yet) returns the spec's default goal so the home screen
    /// has something to render. The single source-of-truth is the
    /// /profile/tdee endpoint, which already accounts for either a
    /// `goal_preset` selection or a custom override.
    func goal() async throws -> NutritionGoal {
        do {
            let resp: TDEEResponse = try await api.get("/api/v1/profile/tdee")
            return NutritionGoal(
                dailyCalories: resp.daily_calories,
                proteinG: resp.daily_protein_g,
                carbsG: resp.daily_carbs_g,
                fatG: resp.daily_fat_g,
                fiberG: 0   // backend doesn't track fiber on /tdee yet
            )
        } catch APIError.notFound {
            return Self.defaultGoal
        }
    }

    /// Save a preset selection. Backend recalculates macros from current
    /// profile + preset adjustment.
    func updatePreset(_ preset: GoalPreset) async throws {
        let body = GoalPresetRequest(goal_preset: preset.wireValue)
        let _: TDEEResponse = try await api.post("/api/v1/profile/goals", body: body)
    }

    /// Save a fully-custom macro override. Routes through
    /// PUT /api/v1/nutrition/goals (the dedicated nutrition-goals
    /// endpoint, not the profile preset endpoint) so existing profile
    /// preset is preserved on the server.
    func updateGoal(_ goal: NutritionGoal) async throws {
        try Self.validate(goal)
        let body = NutritionGoalRequest(
            daily_calories: goal.dailyCalories,
            daily_protein_g: goal.proteinG,
            daily_carbs_g: goal.carbsG,
            daily_fat_g: goal.fatG
        )
        let _: NutritionGoalResponseDTO = try await api.put(
            "/api/v1/nutrition/goals", body: body
        )
    }

    // MARK: - Validation

    /// Mirrors backend `NutritionGoalUpdate` Pydantic Field constraints:
    /// calories 800-10_000, protein 0-500g, carbs 0-1_000g, fat 0-500g.
    /// Reject *before* the network so the user gets immediate feedback.
    private static func validate(_ goal: NutritionGoal) throws {
        if goal.dailyCalories < 800 || goal.dailyCalories > 10_000 {
            throw ProfileError.caloriesOutOfRange
        }
        if goal.proteinG < 0 || goal.proteinG > 500 { throw ProfileError.macrosOutOfRange }
        if goal.carbsG   < 0 || goal.carbsG   > 1_000 { throw ProfileError.macrosOutOfRange }
        if goal.fatG     < 0 || goal.fatG     > 500 { throw ProfileError.macrosOutOfRange }
    }

    // MARK: - Defaults

    /// Same prefill the backend's `ProfileCreate` form would suggest:
    /// 30 yr, 175 cm, 75 kg, male, moderate activity. Used only when no
    /// profile exists yet — the form replaces these as the user types.
    static let defaultProfile = UserProfile(
        weightKg: 75.0,
        heightCm: 175.0,
        age: 30,
        sex: .male,
        activity: .moderate
    )

    /// Backend's `goals.DEFAULT_GOALS` constant (2000/150/250/65). Returned
    /// when /profile/tdee 404s (no profile created yet) so the home screen
    /// renders something instead of erroring on first launch.
    static let defaultGoal = NutritionGoal(
        dailyCalories: 2000,
        proteinG: 150,
        carbsG: 250,
        fatG: 65,
        fiberG: 25
    )
}
