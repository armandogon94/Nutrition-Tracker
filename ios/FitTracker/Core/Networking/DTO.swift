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

// MARK: - Products (Slice 3)

/// Mirrors `app/schemas/product.py:ProductResponse`. Keys match the backend
/// JSON exactly: the backend emits `calories` (per serving) and has no
/// food-category column — so there is no `calories_per_serving` or
/// `category` here. The backend's `source`, `image_url`, and `created_at`
/// are intentionally omitted: the domain `Product` doesn't use them and
/// Codable ignores extra keys.
struct ProductDTO: Codable, Sendable, Hashable {
    let id: String
    let barcode: String?
    let name: String
    let brand: String?
    let serving_size_g: Double
    let calories: Double
    let protein_g: Double
    let carbs_g: Double
    let fat_g: Double
    let fiber_g: Double
}

struct ProductSearchResponse: Codable, Sendable {
    let results: [ProductDTO]
}

// MARK: - Meals (Slice 3)

/// Mirrors `app/schemas/meal.py:MealItemResponse`. Backend always returns
/// the snapshot fields (calories/macros) so we can reconstruct the row
/// even if the underlying product is later deleted.
struct MealItemDTO: Codable, Sendable, Hashable {
    let id: String
    let product_id: String?
    let product_name: String
    let brand: String?
    let servings: Double
    let calories: Double
    let protein_g: Double
    let carbs_g: Double
    let fat_g: Double
}

struct MealDTO: Codable, Sendable, Hashable {
    let id: String
    let user_id: String
    let meal_type: String
    let meal_date: Date
    let items: [MealItemDTO]
}

struct MealsListResponse: Codable, Sendable {
    let meals: [MealDTO]
}

/// POST /api/v1/meals/log — single line item logged into (or creating)
/// today's meal of the given type. Backend creates the parent Meal row
/// implicitly if one does not already exist for `meal_type` on
/// `meal_date` for the authenticated user.
struct LogMealItemRequest: Codable, Sendable {
    let meal_type: String
    let meal_date: Date
    let product_id: String?
    let product_name: String
    let brand: String?
    let servings: Double
    let calories: Double
    let protein_g: Double
    let carbs_g: Double
    let fat_g: Double
    /// Optional client-generated identifier so the backend can dedupe
    /// retried writes from the offline queue.
    let client_item_id: String?
}

// MARK: - Vision (Slice 3.5)

/// Response from POST /api/v1/nutrition/recognize. Backend wraps the
/// Claude Vision call so we never expose the Anthropic API key on
/// device. Confidence is a free-form string ("high"/"medium"/"low") to
/// stay loose with model outputs.
struct VisionRecognitionResponse: Codable, Sendable, Hashable {
    let food: String
    let grams: Double
    let confidence: String
    let calories: Double?
    let protein_g: Double?
    let carbs_g: Double?
    let fat_g: Double?
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
