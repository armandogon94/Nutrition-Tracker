//
//  PendingMutation.swift
//  Codable, append-only record of a backend write that must be flushed.
//  Stored in UserDefaults (small, atomic) rather than SwiftData so that
//  Schema.swift stays locked during Phase C parallel slices (per
//  ADR-0004 §8). When the queue grows large enough to matter we'll
//  migrate it to its own @Model in a v2 schema.
//
//  Slice (offline-sync): the payloads here mirror the REAL FastAPI
//  endpoints so a queued write replays byte-for-byte what the optimistic
//  online write would have sent. In particular `.logMealItem` carries
//  `client_item_id` so the backend can dedupe a re-sent log
//  (`POST /api/v1/meals/log` is idempotent on `(meal, client_item_id)`),
//  and `.deleteMealItem` targets the by-id delete route
//  (`DELETE /api/v1/meals/items/{id}`), which is itself idempotent.
//
//  Slice (offline-queue-userscope): EVERY payload also carries `ownerId`
//  — the id of the user who created the write. The queue is app-global
//  `UserDefaults` and the backend derives ownership from the bearer token,
//  so without this stamp a write enqueued by user A could replay under
//  user B's token after an account switch and land in B's account (Codex
//  review #4 P0). `SyncManager` compares `ownerId` to the signed-in user
//  before replaying and skips/quarantines anything that isn't theirs.
//

import Foundation

/// One-of-many enum so the queue is a single Codable type. Each variant
/// carries everything `SyncManager.execute` needs to replay the write
/// against the live backend.
enum PendingMutation: Codable, Sendable, Identifiable, Equatable {
    /// `POST /api/v1/meals/log` — the combined "create meal + add item"
    /// write MealService performs optimistically. Replayed verbatim on
    /// reconnect; idempotent on `client_item_id`.
    case logMealItem(LogMealItemPayload)
    /// `DELETE /api/v1/meals/items/{id}` — remove a meal item by id.
    case deleteMealItem(DeleteMealItemPayload)
    // Slices 4 (meal plan), 7 (workout) extend this enum additively.

    /// Stable identity used by the queue for dedup + targeted removal.
    /// For a meal-item log this is the `client_item_id` (the local
    /// MealItem id), so enqueuing the same item twice never produces two
    /// queue entries — and the backend dedupes the same id on its side.
    var id: UUID {
        switch self {
        case .logMealItem(let p): return p.clientItemId
        case .deleteMealItem(let p): return p.id
        }
    }

    /// The id of the user who created this write. `SyncManager` compares it
    /// to the signed-in user before replaying so a write enqueued by one
    /// account never flushes under another's bearer token (Codex review #4
    /// P0). Distinct from `id`, which is the per-mutation dedup key.
    var ownerId: UUID {
        switch self {
        case .logMealItem(let p): return p.ownerId
        case .deleteMealItem(let p): return p.ownerId
        }
    }

    /// The backend path this mutation flushes to. Kept here (rather than in
    /// SyncManager) so the queue record is self-describing for logging.
    var endpoint: String {
        switch self {
        case .logMealItem: return "/api/v1/meals/log"
        case .deleteMealItem(let p): return "/api/v1/meals/items/\(p.id)"
        }
    }
}

/// Mirrors `LogMealItemRequest` (DTO.swift) / backend `MealLogRequest`.
/// `mealDate` is stored as a date-only "yyyy-MM-dd" string because the
/// backend `meal_date` is a Pydantic `date` that 422s on a datetime with a
/// non-zero time component — the same reason MealService pre-formats it.
struct LogMealItemPayload: Codable, Sendable, Equatable {
    let ownerId: UUID             // user who logged this item (replay owner-guard)
    let clientItemId: UUID        // local MealItem id → backend client_item_id
    let mealType: String
    let mealDate: String          // "yyyy-MM-dd"
    let productId: UUID?
    let productName: String
    let brand: String?
    let servings: Double
    let calories: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double

    /// Builds the on-the-wire request body for `POST /api/v1/meals/log`.
    /// Centralised here so the queued replay and any future call site
    /// share one mapping to the backend contract.
    func asRequest() -> LogMealItemRequest {
        LogMealItemRequest(
            meal_type: mealType,
            meal_date: mealDate,
            product_id: productId?.uuidString,
            product_name: productName,
            brand: brand,
            servings: servings,
            calories: calories,
            protein_g: proteinG,
            carbs_g: carbsG,
            fat_g: fatG,
            client_item_id: clientItemId.uuidString
        )
    }
}

struct DeleteMealItemPayload: Codable, Sendable, Equatable {
    let ownerId: UUID             // user who deleted this item (replay owner-guard)
    let id: UUID
}
