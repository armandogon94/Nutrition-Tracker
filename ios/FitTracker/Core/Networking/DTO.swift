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

// MARK: - Products (Slice 3)

/// Mirrors `app/schemas/product.py:ProductResponse`. Snake_case keys map
/// directly to the Pydantic schema; we keep the shape flat (no nested
/// "nutrition" object) because the backend already flattened macros for
/// the iOS contract during Slice 9.
struct ProductDTO: Codable, Sendable, Hashable {
    let id: String
    let barcode: String?
    let name: String
    let brand: String?
    let serving_size_g: Double
    let calories_per_serving: Double
    let protein_g: Double
    let carbs_g: Double
    let fat_g: Double
    let fiber_g: Double
    let category: String
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
