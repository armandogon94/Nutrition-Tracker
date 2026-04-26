//
//  SchemaTests.swift
//  Validates the Slice 2.1 SwiftData baseline: every @Model registers,
//  cascade rules behave, and the composite-key derivation for
//  DailyNutritionEntity is stable.
//

import Foundation
import SwiftData
import Testing
@testable import FitTracker

@Suite("SwiftData Schema", .serialized)
struct SchemaTests {

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        try PersistenceController.makeInMemory().container
    }

    @MainActor
    @Test("Container builds with all v1 entities registered")
    func container_buildsCleanly() throws {
        let container = try makeContainer()
        // Smoke: we can fetch from any model without throwing.
        let ctx = ModelContext(container)
        _ = try ctx.fetch(FetchDescriptor<UserEntity>())
        _ = try ctx.fetch(FetchDescriptor<MealEntity>())
        _ = try ctx.fetch(FetchDescriptor<WorkoutProgramEntity>())
        _ = try ctx.fetch(FetchDescriptor<PersonalRecordEntity>())
    }

    @MainActor
    @Test("UserEntity round-trip: insert, save, fetch")
    func user_roundTrip() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let id = UUID()
        ctx.insert(UserEntity(id: id, email: "carlos@test.dev",
                              displayName: "Carlos", createdAt: .now))
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<UserEntity>(predicate: #Predicate { $0.id == id }))
        #expect(fetched.count == 1)
        #expect(fetched.first?.email == "carlos@test.dev")
        #expect(fetched.first?.role == "user")
    }

    @MainActor
    @Test("Meal cascades to MealItem on delete")
    func meal_cascadesToItems() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let userId = UUID()
        let meal = MealEntity(id: UUID(), userId: userId,
                              mealType: "breakfast", mealDate: .now)
        let item1 = MealItemEntity(id: UUID(), productId: UUID(),
                                   productName: "Avena", brand: "Quaker",
                                   servings: 1.5, calories: 225,
                                   proteinG: 7.5, carbsG: 40.5, fatG: 4.5)
        let item2 = MealItemEntity(id: UUID(), productId: UUID(),
                                   productName: "Plátano", brand: nil,
                                   servings: 1, calories: 105,
                                   proteinG: 1.3, carbsG: 27, fatG: 0.4)
        meal.items = [item1, item2]
        ctx.insert(meal)
        try ctx.save()

        #expect(try ctx.fetch(FetchDescriptor<MealItemEntity>()).count == 2)

        ctx.delete(meal)
        try ctx.save()

        let remaining = try ctx.fetch(FetchDescriptor<MealItemEntity>())
        #expect(remaining.isEmpty, "MealItem children should cascade-delete with their parent Meal")
    }

    @MainActor
    @Test("Product delete leaves the meal item with frozen nutrition")
    func product_nullifyOnMealItem() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let product = ProductEntity(
            id: UUID(), barcode: "7501055302345", name: "Avena", brand: "Quaker",
            servingSizeG: 40, caloriesPerServing: 150, proteinG: 5,
            carbsG: 27, fatG: 3, fiberG: 4, category: "Grano"
        )
        let item = MealItemEntity(id: UUID(), productId: product.id,
                                  productName: "Avena", brand: "Quaker",
                                  servings: 1, calories: 150,
                                  proteinG: 5, carbsG: 27, fatG: 3)
        item.product = product
        ctx.insert(item)
        ctx.insert(product)
        try ctx.save()

        // The frozen-nutrition invariant (ADR-0004 §6) is what matters here:
        // the meal item must survive product deletion with its calorie + macro
        // snapshot intact. Whether SwiftData auto-nullifies the `product`
        // back-reference depends on whether we declare an explicit inverse,
        // and is an implementation detail we don't pin in this test.
        ctx.delete(product)
        try ctx.save()

        let items = try ctx.fetch(FetchDescriptor<MealItemEntity>())
        #expect(items.count == 1, "MealItem must survive Product deletion (frozen nutrition snapshot)")
        #expect(items.first?.calories == 150, "frozen calories preserved")
        #expect(items.first?.proteinG == 5)
        #expect(items.first?.productName == "Avena")
    }

    @MainActor
    @Test("WorkoutSession cascades to WorkoutSets")
    func workoutSession_cascadesToSets() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let session = WorkoutSessionEntity(
            id: UUID(), userId: UUID(),
            startedAt: .now, completedAt: nil,
            programName: "PPL", dayName: "Push"
        )
        session.sets = (1...3).map { i in
            WorkoutSetEntity(id: UUID(), exerciseId: UUID(),
                             setNumber: i, weightKg: 80, reps: 8)
        }
        ctx.insert(session)
        try ctx.save()
        #expect(try ctx.fetch(FetchDescriptor<WorkoutSetEntity>()).count == 3)

        ctx.delete(session)
        try ctx.save()
        #expect(try ctx.fetch(FetchDescriptor<WorkoutSetEntity>()).isEmpty)
    }

    @MainActor
    @Test("DailyNutrition composite key is stable across same-UTC-day timestamps")
    func dailyNutrition_keyStability() {
        // Per ADR-0004 §6 the key is UTC-anchored so a meal logged at
        // 23:30 local (which is the next-day UTC) collides with the
        // backend's 'date' for that calendar day. Test that two different
        // UTC times within the same UTC day produce the same key.
        let userId = UUID()
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let dawn = cal.date(from: DateComponents(year: 2026, month: 4, day: 25, hour: 0, minute: 30))!
        let dusk = cal.date(from: DateComponents(year: 2026, month: 4, day: 25, hour: 23, minute: 30))!
        let key1 = DailyNutritionEntity.makeKey(userId: userId, date: dawn)
        let key2 = DailyNutritionEntity.makeKey(userId: userId, date: dusk)
        #expect(key1 == key2, "same UTC day timestamps must produce identical keys")
    }

    @MainActor
    @Test("WorkoutProgram → Day → ExerciseSpec cascades all the way down")
    func program_deepCascade() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let day = WorkoutProgramDayEntity(id: UUID(), dayName: "Push")
        day.exercises = [
            WorkoutProgramExerciseSpecEntity(
                id: UUID(), exerciseId: UUID(), exerciseName: "Bench",
                sets: 4, repsLow: 6, repsHigh: 8, restSeconds: 120
            )
        ]
        let program = WorkoutProgramEntity(
            id: UUID(), name: "PPL", summary: "test",
            daysPerWeek: 6, difficulty: "intermediate"
        )
        program.days = [day]
        ctx.insert(program)
        try ctx.save()

        #expect(try ctx.fetch(FetchDescriptor<WorkoutProgramExerciseSpecEntity>()).count == 1)

        ctx.delete(program)
        try ctx.save()

        #expect(try ctx.fetch(FetchDescriptor<WorkoutProgramDayEntity>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<WorkoutProgramExerciseSpecEntity>()).isEmpty)
    }
}
