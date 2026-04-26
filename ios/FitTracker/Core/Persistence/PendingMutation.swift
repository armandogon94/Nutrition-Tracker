//
//  PendingMutation.swift
//  Codable, append-only record of a backend write that must be flushed.
//  Stored in UserDefaults (small, atomic) rather than SwiftData so that
//  Schema.swift stays locked during Phase C parallel slices (per
//  ADR-0004 §8). When the queue grows large enough to matter we'll
//  migrate it to its own @Model in a v2 schema.
//

import Foundation

/// One-of-many enum so the queue is a single Codable type. Each variant
/// carries everything `execute(on:)` needs to replay the write.
enum PendingMutation: Codable, Sendable, Identifiable, Equatable {
    case createMeal(CreateMealPayload)
    case deleteMealItem(DeleteMealItemPayload)
    // Slices 4 (meal plan), 7 (workout) extend this enum additively.

    var id: UUID {
        switch self {
        case .createMeal(let p): return p.localId
        case .deleteMealItem(let p): return p.id
        }
    }

    var endpoint: String {
        switch self {
        case .createMeal: return "/api/v1/meals"
        case .deleteMealItem(let p): return "/api/v1/meals/\(p.mealId)/items/\(p.id)"
        }
    }
}

struct CreateMealPayload: Codable, Sendable, Equatable {
    let localId: UUID                 // local temp ID; backend may return a different one
    let userId: UUID
    let mealType: String
    let mealDate: Date
    let items: [Item]

    struct Item: Codable, Sendable, Equatable {
        let productId: UUID?
        let productName: String
        let servings: Double
    }
}

struct DeleteMealItemPayload: Codable, Sendable, Equatable {
    let id: UUID
    let mealId: UUID
}
