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
            caloriesPerServing: dto.calories_per_serving,
            proteinG: dto.protein_g,
            carbsG: dto.carbs_g,
            fatG: dto.fat_g,
            fiberG: dto.fiber_g,
            category: dto.category
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

// MARK: - Shopping category (Slice 4)

extension ShoppingCategory {
    /// Map a backend category string onto the iOS enum. The backend stores
    /// localized Spanish section names (see services/shopping_list.py:
    /// CATEGORY_MAP + _categorize_product). We fold both the Spanish
    /// section labels and the raw English category keys onto our enum, so
    /// the mapping is robust whether the backend sends "Lácteos y Huevos"
    /// or a future "dairy". Unknown values fall back to `.other`.
    init(fromBackend raw: String?) {
        guard let raw, !raw.isEmpty else { self = .other; return }
        let v = raw.lowercased()
        switch v {
        // Spanish section labels emitted by shopping_list.py
        case "frutas y verduras":      self = .produce
        case "carnes y aves",
             "pescados y mariscos":    self = .proteins
        case "lácteos y huevos",
             "lacteos y huevos":       self = .dairy
        case "panadería", "panaderia",
             "granos y cereales":      self = .grains
        case "bebidas":                self = .beverages
        case "congelados":             self = .frozen
        case "enlatados y conservas",
             "condimentos y especias",
             "aceites y vinagres",
             "botanas y snacks":       self = .pantry
        default:
            // Tolerate raw English keys too (forward-compat).
            switch v {
            case "produce":                       self = .produce
            case "dairy":                         self = .dairy
            case "proteins", "meat", "seafood":   self = .proteins
            case "grains", "bakery":              self = .grains
            case "beverages":                     self = .beverages
            case "frozen":                        self = .frozen
            case "pantry", "canned",
                 "condiments", "oils", "snacks":  self = .pantry
            default:                              self = .other
            }
        }
    }
}

// MARK: - ShoppingItem (Slice 4)

extension ShoppingItem {
    init(from dto: ShoppingListItemDTO) {
        self.init(
            id: parseUUID(dto.id),
            name: dto.ingredient_name,
            quantity: Self.formatQuantity(dto.quantity, unit: dto.unit),
            category: ShoppingCategory(fromBackend: dto.category),
            checked: dto.is_checked
        )
    }

    init(from entity: ShoppingListItemEntity) {
        self.init(
            id: entity.id,
            name: entity.name,
            quantity: entity.quantity,
            category: ShoppingCategory(rawValue: entity.category) ?? .other,
            checked: entity.checked
        )
    }

    /// Render a numeric quantity + unit into a compact display string:
    /// "500 g", "1.5 kg", "2 pzas". Drops a trailing ".0" so integral
    /// amounts read cleanly.
    static func formatQuantity(_ quantity: Double, unit: String?) -> String {
        let qStr: String
        if quantity == quantity.rounded() {
            qStr = String(Int(quantity))
        } else {
            qStr = String(format: "%.1f", quantity)
        }
        if let unit, !unit.isEmpty {
            return "\(qStr) \(unit)"
        }
        return qStr
    }
}

enum ShoppingListItemMapper {
    static func makeEntity(from dto: ShoppingListItemDTO) -> ShoppingListItemEntity {
        ShoppingListItemEntity(
            id: parseUUID(dto.id),
            name: dto.ingredient_name,
            quantity: ShoppingItem.formatQuantity(dto.quantity, unit: dto.unit),
            category: ShoppingCategory(fromBackend: dto.category).rawValue,
            checked: dto.is_checked,
            pendingSync: false
        )
    }
}

// MARK: - MealPlanItem (Slice 4)

extension MealPlanItem {
    init(from dto: MealPlanItemDTO) {
        self.init(
            id: parseUUID(dto.id),
            dayIndex: dto.day_of_week,
            mealType: MealType(rawValue: dto.meal_type) ?? .snack,
            productName: dto.product.name,
            servings: dto.quantity_servings
        )
    }

    init(from entity: MealPlanItemEntity) {
        self.init(
            id: entity.id,
            dayIndex: entity.dayIndex,
            mealType: MealType(rawValue: entity.mealType) ?? .snack,
            productName: entity.productName,
            servings: entity.servings
        )
    }
}

enum MealPlanItemMapper {
    static func makeEntity(from item: MealPlanItem,
                           pendingSync: Bool = false) -> MealPlanItemEntity {
        MealPlanItemEntity(
            id: item.id,
            dayIndex: item.dayIndex,
            mealType: item.mealType.rawValue,
            productName: item.productName,
            servings: item.servings,
            pendingSync: pendingSync
        )
    }

    static func makeEntity(from dto: MealPlanItemDTO,
                           pendingSync: Bool = false) -> MealPlanItemEntity {
        MealPlanItemEntity(
            id: parseUUID(dto.id),
            dayIndex: dto.day_of_week,
            mealType: dto.meal_type,
            productName: dto.product.name,
            servings: dto.quantity_servings,
            pendingSync: pendingSync
        )
    }
}

// MARK: - MealPlan (Slice 4)

extension MealPlan {
    init(from dto: MealPlanDTO) {
        self.init(
            id: parseUUID(dto.id),
            weekStartDate: dto.week_start_date,
            items: dto.items.map(MealPlanItem.init(from:))
        )
    }

    init(from entity: MealPlanEntity) {
        self.init(
            id: entity.id,
            weekStartDate: entity.weekStartDate,
            items: entity.items
                .sorted { ($0.dayIndex, $0.mealType) < ($1.dayIndex, $1.mealType) }
                .map(MealPlanItem.init(from:))
        )
    }
}

enum MealPlanMapper {
    static func makeEntity(from dto: MealPlanDTO,
                           userId: UUID,
                           pendingSync: Bool = false,
                           lastSyncedAt: Date? = .now) -> MealPlanEntity {
        let entity = MealPlanEntity(
            id: parseUUID(dto.id),
            userId: userId,
            weekStartDate: dto.week_start_date,
            pendingSync: pendingSync,
            lastSyncedAt: lastSyncedAt
        )
        entity.items = dto.items.map { MealPlanItemMapper.makeEntity(from: $0, pendingSync: pendingSync) }
        return entity
    }
}
