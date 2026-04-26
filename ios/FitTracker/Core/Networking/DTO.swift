//
//  DTO.swift
//  Append-only file for Codable request/response types mirroring the
//  FastAPI backend contract. Each slice adds its DTOs here.
//
//  Naming:
//    - *Request suffix for request bodies
//    - *Response suffix (or plain noun) for response shapes
//    - Dates use `Date` — decoding handled in APIClient
//    - snake_case API keys map via explicit CodingKeys below
//

import Foundation

// MARK: - Health (Slice 0.8 ping)

struct HealthResponse: Codable, Sendable {
    let status: String
}

// MARK: - Auth (Slice 1)

struct LoginRequest: Codable, Sendable {
    let email: String
    let password: String
}

struct RegisterRequest: Codable, Sendable {
    let email: String
    let password: String
    let display_name: String
}

struct AppleSignInRequest: Codable, Sendable {
    let identity_token: String
    let user_identifier: String
    let email: String?
    let full_name: AppleFullName?

    struct AppleFullName: Codable, Sendable {
        let firstName: String?
        let lastName: String?
    }
}

struct RefreshRequest: Codable, Sendable {
    let refresh_token: String
}

struct AuthTokens: Codable, Sendable {
    let access_token: String
    let refresh_token: String
    let token_type: String
    let expires_in: Int          // seconds; backend honors this for access lifetime
}

struct AuthMeResponse: Codable, Sendable {
    let id: String
    let email: String
    let display_name: String
    let role: String?
}

// MARK: - Profile + Goals (Slice 5)

/// POST /api/v1/profile request body. Mirrors backend `ProfileCreate`.
struct ProfileRequest: Codable, Sendable {
    let weight_kg: Double
    let height_cm: Double
    let age: Int
    let sex: String              // "male" | "female"
    let activity_level: String   // ActivityLevel wire value (snake_case)
}

/// GET /api/v1/profile/tdee response shape. Mirrors backend `TDEEResponse`.
/// Used for both the initial profile fetch (client falls back to defaults
/// on 404) and any post-save refresh.
struct TDEEResponse: Codable, Sendable {
    let bmr: Double
    let tdee: Double
    let activity_level: String
    let goal_preset: String?
    let daily_calories: Int
    let daily_protein_g: Int
    let daily_fat_g: Int
    let daily_carbs_g: Int
}

/// POST /api/v1/profile response shape. Mirrors backend `ProfileResponse`.
/// All fields except the user-entered five are nullable because they are
/// only filled once a goal preset has been set.
struct ProfileResponse: Codable, Sendable {
    let weight_kg: Double
    let height_cm: Double
    let age: Int
    let sex: String
    let activity_level: String
    let bmr: Double?
    let tdee: Double?
    let goal_preset: String?
    let daily_calories: Int?
    let daily_protein_g: Int?
    let daily_carbs_g: Int?
    let daily_fat_g: Int?
}

/// POST /api/v1/profile/goals request body. Mirrors backend `GoalPresetUpdate`.
struct GoalPresetRequest: Codable, Sendable {
    let goal_preset: String      // GoalPreset wire value (snake_case)
}

/// PUT /api/v1/nutrition/goals request body. Mirrors backend
/// `NutritionGoalUpdate`. Used for the "Custom" tab where the user
/// overrides each macro directly. Backend validates 800 ≤ cal ≤ 10_000.
struct NutritionGoalRequest: Codable, Sendable {
    let daily_calories: Int
    let daily_protein_g: Int
    let daily_carbs_g: Int
    let daily_fat_g: Int
}

/// GET /api/v1/nutrition/goals response. Mirrors backend `NutritionGoalResponse`.
struct NutritionGoalResponseDTO: Codable, Sendable {
    let daily_calories: Int
    let daily_protein_g: Int
    let daily_carbs_g: Int
    let daily_fat_g: Int
}

// MARK: - Exercises (Slice 6)

struct ExerciseDTO: Codable, Sendable {
    let id: String
    let name: String
    let primary_muscle: String
    let secondary_muscles: String?
    let equipment: String?
    let difficulty: String?
    let instructions: String?
    let video_url: String?
    let category: String?
}

struct ExerciseListDTO: Codable, Sendable {
    let exercises: [ExerciseDTO]
    let total: Int
}

// MARK: - Programs (Slice 6)

struct WorkoutProgramExerciseDTO: Codable, Sendable {
    let id: String
    let exercise: ExerciseDTO
    let set_count: Int
    let rep_min: Int?
    let rep_max: Int?
    let rest_seconds: Int?
    let exercise_order: Int
    let notes: String?
}

struct WorkoutProgramDayDTO: Codable, Sendable {
    let id: String
    let day_number: Int
    let day_name: String?
    let focus: String?
    let description: String?
    let exercises: [WorkoutProgramExerciseDTO]
}

struct WorkoutProgramListDTO: Codable, Sendable {
    let id: String
    let name: String
    let description: String?
    let program_type: String?
    let days_per_week: Int
    let difficulty: String?
    let is_preset: Bool
}

struct WorkoutProgramDTO: Codable, Sendable {
    let id: String
    let name: String
    let description: String?
    let program_type: String?
    let days_per_week: Int
    let difficulty: String?
    let is_preset: Bool
    let days: [WorkoutProgramDayDTO]
}
