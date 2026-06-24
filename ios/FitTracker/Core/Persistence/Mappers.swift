//
//  Mappers.swift
//  Slice 3: convert between domain structs (Models.swift), backend DTOs
//  (DTO.swift), and SwiftData entities (Schema.swift). Living between the
//  three shapes is unavoidable — pinning the conversions here keeps the
//  rest of the app from sprouting ad-hoc copies. See ADR-0004 §2 for the
//  two-shape rationale.
//
//  Conventions:
//    - `make<Entity>(from: <Struct>)` returns a new @Model ready to insert
//    - `<Struct>(from: <Entity>)` reads a SwiftData row back into a
//      Sendable struct safe to pass across actor boundaries
//    - `<Struct>(from: <DTO>)` materializes a server response into the
//      domain struct used by views
//
//  Mappers are non-throwing where possible. Where the DTO uses string
//  ids ("uuid") we accept malformed values silently by minting a fresh
//  UUID and surfacing the issue via a #if DEBUG assertion — the alternative
//  (throwing) propagates noise into every call site for what is almost
//  certainly a backend contract bug, not a client problem.
//

import Foundation

// MARK: - Helpers

/// Best-effort UUID parse. A bad string returns a fresh UUID and asserts
/// in debug builds so we catch backend regressions early without crashing
/// in release. Backend tests are the right place to enforce the format.
@inline(__always)
private func parseUUID(_ raw: String, field: StaticString = #function) -> UUID {
    if let u = UUID(uuidString: raw) { return u }
    #if DEBUG
    assertionFailure("Mappers: malformed UUID '\(raw)' for field \(field)")
    #endif
    return UUID()
}

// MARK: - Product

extension Product {
    init(from dto: ProductDTO) {
        self.init(
            id: parseUUID(dto.id),
            barcode: dto.barcode,
            name: dto.name,
            brand: dto.brand,
            servingSizeG: dto.serving_size_g,
            caloriesPerServing: dto.calories,
            proteinG: dto.protein_g,
            carbsG: dto.carbs_g,
            fatG: dto.fat_g,
            fiberG: dto.fiber_g,
            // The backend has no food-category column; `category` is only
            // populated for mock/manual data, so backend products get "".
            category: ""
        )
    }

    init(from entity: ProductEntity) {
        self.init(
            id: entity.id,
            barcode: entity.barcode,
            name: entity.name,
            brand: entity.brand,
            servingSizeG: entity.servingSizeG,
            caloriesPerServing: entity.caloriesPerServing,
            proteinG: entity.proteinG,
            carbsG: entity.carbsG,
            fatG: entity.fatG,
            fiberG: entity.fiberG,
            category: entity.category
        )
    }
}

enum ProductMapper {
    static func makeEntity(from product: Product,
                           pendingSync: Bool = false,
                           lastSyncedAt: Date? = .now) -> ProductEntity {
        ProductEntity(
            id: product.id,
            barcode: product.barcode,
            name: product.name,
            brand: product.brand,
            servingSizeG: product.servingSizeG,
            caloriesPerServing: product.caloriesPerServing,
            proteinG: product.proteinG,
            carbsG: product.carbsG,
            fatG: product.fatG,
            fiberG: product.fiberG,
            category: product.category,
            pendingSync: pendingSync,
            lastSyncedAt: lastSyncedAt
        )
    }
}

// MARK: - MealItem

extension MealItem {
    init(from dto: MealItemDTO) {
        self.init(
            id: parseUUID(dto.id),
            productId: dto.product_id.flatMap(UUID.init(uuidString:)) ?? UUID(),
            productName: dto.product_name,
            brand: dto.brand,
            servings: dto.servings,
            calories: dto.calories,
            proteinG: dto.protein_g,
            carbsG: dto.carbs_g,
            fatG: dto.fat_g
        )
    }

    init(from entity: MealItemEntity) {
        self.init(
            id: entity.id,
            productId: entity.productId ?? UUID(),
            productName: entity.productName,
            brand: entity.brand,
            servings: entity.servings,
            calories: entity.calories,
            proteinG: entity.proteinG,
            carbsG: entity.carbsG,
            fatG: entity.fatG
        )
    }
}

enum MealItemMapper {
    static func makeEntity(from item: MealItem,
                           pendingSync: Bool = true,
                           lastSyncedAt: Date? = nil) -> MealItemEntity {
        MealItemEntity(
            id: item.id,
            productId: item.productId,
            productName: item.productName,
            brand: item.brand,
            servings: item.servings,
            calories: item.calories,
            proteinG: item.proteinG,
            carbsG: item.carbsG,
            fatG: item.fatG,
            pendingSync: pendingSync,
            lastSyncedAt: lastSyncedAt
        )
    }
}

// MARK: - Meal

extension Meal {
    init(from dto: MealDTO) {
        let mealType = MealType(rawValue: dto.meal_type) ?? .snack
        self.init(
            id: parseUUID(dto.id),
            mealType: mealType,
            mealDate: dto.meal_date,
            items: dto.items.map(MealItem.init(from:))
        )
    }

    init(from entity: MealEntity) {
        self.init(
            id: entity.id,
            mealType: MealType(rawValue: entity.mealType) ?? .snack,
            mealDate: entity.mealDate,
            items: entity.items.map(MealItem.init(from:))
        )
    }
}

enum MealMapper {
    static func makeEntity(from meal: Meal,
                           userId: UUID,
                           pendingSync: Bool = true,
                           lastSyncedAt: Date? = nil) -> MealEntity {
        let entity = MealEntity(
            id: meal.id,
            userId: userId,
            mealType: meal.mealType.rawValue,
            mealDate: meal.mealDate,
            pendingSync: pendingSync,
            lastSyncedAt: lastSyncedAt
        )
        entity.items = meal.items.map { MealItemMapper.makeEntity(from: $0,
                                                                  pendingSync: pendingSync,
                                                                  lastSyncedAt: lastSyncedAt) }
        return entity
    }
}
