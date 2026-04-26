//
//  NutritionMappers.swift
//  Struct ↔ @Model converters for the nutrition domain (DailyNutrition).
//  Slice 2.3.
//
//  Per ADR-0004 we keep one mapper file per domain so Phase C parallel
//  slices don't contend on a single Mappers.swift. Slices 3 / 5 / 6
//  ship their own NutritionMappers / ProfileMappers / ProgramMappers.
//

import Foundation

extension DailyNutritionEntity {
    /// Project to the Sendable struct used by views and services.
    func toStruct() -> DailyNutrition {
        DailyNutrition(
            date: date,
            calories: calories,
            proteinG: proteinG,
            carbsG: carbsG,
            fatG: fatG,
            fiberG: fiberG
        )
    }
}

extension DailyNutrition {
    /// Materialize the struct as a @Model instance for SwiftData inserts.
    func toEntity(userId: UUID, lastSyncedAt: Date? = nil) -> DailyNutritionEntity {
        DailyNutritionEntity(
            userId: userId,
            date: date,
            calories: calories,
            proteinG: proteinG,
            carbsG: carbsG,
            fatG: fatG,
            fiberG: fiberG,
            lastSyncedAt: lastSyncedAt
        )
    }
}
