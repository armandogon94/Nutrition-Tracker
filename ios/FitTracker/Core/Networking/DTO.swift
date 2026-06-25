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

// MARK: - Workout Sessions + Sets + PRs (Slice 7)

/// POST /api/v1/workouts/sessions request body. Mirrors backend
/// `SessionCreate`. `program_id` / `program_day_id` are optional so an
/// ad-hoc (program-less) session is representable; today's flow always
/// supplies them from the chosen program day.
struct SessionCreateRequest: Codable, Sendable {
    let program_id: String?
    let program_day_id: String?
    let started_at: Date
}

/// POST /api/v1/workouts/sessions/{id}/sets request body. Mirrors backend
/// `SetCreate`. `weight_kg` is optional (bodyweight movements) and `rpe`
/// is reserved for a later slice; we send it nil for now.
struct SetCreateRequest: Codable, Sendable {
    let exercise_id: String
    let set_number: Int
    let reps: Int
    let weight_kg: Double?
    let rpe: Double?
}

/// PATCH /api/v1/workouts/sessions/{id}/complete request body. Mirrors
/// backend `SessionComplete`.
struct SessionCompleteRequest: Codable, Sendable {
    let notes: String?
}

/// Response shape for a single logged set. Mirrors backend `SetResponse`.
/// The nested `exercise` is the full ExerciseDTO; we only read its id +
/// name for the on-device row, but decode the whole object to stay tolerant
/// of the contract.
struct WorkoutSetDTO: Codable, Sendable {
    let id: String
    let exercise_id: String
    let exercise: ExerciseDTO
    let set_number: Int
    let reps: Int
    let weight_kg: Double?
    let rpe: Double?
    let is_pr: Bool
    let completed_at: Date
}

/// Response shape for a workout session. Mirrors backend `SessionResponse`.
struct WorkoutSessionDTO: Codable, Sendable {
    let id: String
    let user_id: String
    let program_id: String?
    let program_day_id: String?
    let started_at: Date
    let completed_at: Date?
    let duration_minutes: Int?
    let notes: String?
    let sets: [WorkoutSetDTO]
}

/// Response shape for a personal record. Mirrors backend
/// `PersonalRecordResponse`. `estimated_1rm` is the comparison key the
/// backend uses for PR detection (avg of Brzycki + Epley).
struct PersonalRecordDTO: Codable, Sendable {
    let id: String
    let exercise: ExerciseDTO
    let max_weight_kg: Double?
    let max_reps_at_weight: Int?
    let estimated_1rm: Double?
    let achieved_at: Date
}


// MARK: - Meal Plan + Shopping List (Slice 4)

/// Request body for POST /api/v1/meal-plans. Mirrors
/// `app/schemas/meal_plan.py:MealPlanCreate`. `week_start_date` is a
/// date-only string ("yyyy-MM-dd"); we encode it ourselves rather than
/// relying on the ISO8601 default so the backend `Date` field parses.
struct MealPlanCreateRequest: Codable, Sendable {
    let name: String
    let week_start_date: String        // "yyyy-MM-dd"
    let notes: String?
    let is_template: Bool
}

/// Request body for POST /api/v1/meal-plans/{planId}/items. Mirrors
/// `MealPlanItemCreate`. `meal_type` is one of breakfast|lunch|dinner|snack.
struct MealPlanItemCreateRequest: Codable, Sendable {
    let product_id: String
    let day_of_week: Int               // 0..6 (Mon..Sun)
    let meal_type: String
    let quantity_servings: Double
    let quantity_grams: Double?
}

/// Embedded product inside MealPlanItemResponse. This mirrors
/// `app/schemas/product.py:ProductResponse` — NOT the flattened
/// `ProductDTO` used elsewhere (that one carries `calories_per_serving`
/// + `category`, which the meal-plan endpoint does not return). Kept
/// minimal: meal-plan items only need the product name.
struct MealPlanProductDTO: Codable, Sendable, Hashable {
    let id: String
    let name: String
    let brand: String?
}

/// Mirrors `MealPlanItemResponse`. The full product is embedded; the iOS
/// cache only stores `productName` + `servings` (see Schema.swift —
/// MealPlanItemEntity).
struct MealPlanItemDTO: Codable, Sendable, Hashable {
    let id: String
    let product_id: String
    let day_of_week: Int
    let meal_type: String
    let quantity_servings: Double
    let quantity_grams: Double?
    let product: MealPlanProductDTO
}

/// Mirrors `MealPlanResponse`. `week_start_date` decodes via the
/// date-only branch in APIClient's custom date strategy.
struct MealPlanDTO: Codable, Sendable, Hashable {
    let id: String
    let user_id: String
    let name: String
    let week_start_date: Date
    let notes: String?
    let is_template: Bool
    let items: [MealPlanItemDTO]
}

/// Request body for PATCH .../check. Mirrors `ShoppingItemCheck`.
struct ShoppingItemCheckRequest: Codable, Sendable {
    let is_checked: Bool
}

/// Response from the check PATCH endpoint: `{id, is_checked}`.
struct ShoppingItemCheckResponse: Codable, Sendable {
    let id: String
    let is_checked: Bool
}

/// Mirrors `ShoppingListItemResponse`. `quantity` is numeric + a separate
/// `unit`; the iOS `ShoppingItem` flattens these into a display string.
struct ShoppingListItemDTO: Codable, Sendable, Hashable {
    let id: String
    let ingredient_name: String
    let quantity: Double
    let unit: String?
    let category: String?
    let is_checked: Bool
}

/// Mirrors `ShoppingListResponse`.
struct ShoppingListDTO: Codable, Sendable, Hashable {
    let id: String
    let name: String?
    let meal_plan_id: String?
    let items: [ShoppingListItemDTO]
    let generated_at: Date
}
