//
//  Schema.swift
//  SwiftData entities for the iOS client. Single source of truth for
//  on-device persistence. Slice 2.1.
//
//  Ownership: this file is edited ONLY by the agent owning Slice 2 during
//  Phase C parallel execution. Other slices (3, 5, 6) request additions
//  via task-log notes; the main agent applies them and the subagent
//  rebases. See ADR-0004 and plans/000-OVERVIEW.md §4.
//
//  Two-shape model:
//    - Models/Models.swift   : Sendable structs (DTOs, mocks, view binding)
//    - Core/Persistence/...  : @Model classes (this file)
//  Conversions live in Core/Persistence/Mappers.swift.
//

import Foundation
import SwiftData

// MARK: - Versioned Schema

/// V1 = Phase C baseline. Every @Model in this enum is registered with the
/// ModelContainer. New versions append a `FitTrackerSchemaV2` etc. and a
/// SchemaMigrationPlan stage.
enum FitTrackerSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [
            UserEntity.self,
            UserProfileEntity.self,
            NutritionGoalEntity.self,
            ProductEntity.self,
            MealEntity.self,
            MealItemEntity.self,
            DailyNutritionEntity.self,
            MealPlanEntity.self,
            MealPlanItemEntity.self,
            ShoppingListEntity.self,
            ShoppingListItemEntity.self,
            ExerciseEntity.self,
            WorkoutProgramEntity.self,
            WorkoutProgramDayEntity.self,
            WorkoutProgramExerciseSpecEntity.self,
            WorkoutSessionEntity.self,
            WorkoutSetEntity.self,
            PersonalRecordEntity.self
        ]
    }
}

/// Migration plan. Today: V1 only. Subsequent slices append a new stage
/// with a custom migration block.
enum FitTrackerMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [FitTrackerSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

// MARK: - User

@Model
final class UserEntity {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var email: String
    var displayName: String
    var role: String                            // "user" | "admin"
    var appleUserId: String?
    var createdAt: Date

    // Sync flags — see ADR-0004 §4
    var pendingSync: Bool
    var lastSyncedAt: Date?

    init(id: UUID, email: String, displayName: String,
         role: String = "user", appleUserId: String? = nil,
         createdAt: Date, pendingSync: Bool = false, lastSyncedAt: Date? = nil) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.role = role
        self.appleUserId = appleUserId
        self.createdAt = createdAt
        self.pendingSync = pendingSync
        self.lastSyncedAt = lastSyncedAt
    }
}

// MARK: - Profile + Goals (1-to-1 with user, scoped by userId)

@Model
final class UserProfileEntity {
    @Attribute(.unique) var userId: UUID
    var weightKg: Double
    var heightCm: Double
    var age: Int
    var sex: String                              // raw value of `Sex` enum
    var activity: String                         // raw value of `ActivityLevel` enum

    var pendingSync: Bool
    var lastSyncedAt: Date?

    init(userId: UUID, weightKg: Double, heightCm: Double, age: Int,
         sex: String, activity: String,
         pendingSync: Bool = false, lastSyncedAt: Date? = nil) {
        self.userId = userId
        self.weightKg = weightKg
        self.heightCm = heightCm
        self.age = age
        self.sex = sex
        self.activity = activity
        self.pendingSync = pendingSync
        self.lastSyncedAt = lastSyncedAt
    }
}

@Model
final class NutritionGoalEntity {
    @Attribute(.unique) var userId: UUID
    var dailyCalories: Int
    var proteinG: Int
    var carbsG: Int
    var fatG: Int
    var fiberG: Int

    var pendingSync: Bool
    var lastSyncedAt: Date?

    init(userId: UUID, dailyCalories: Int, proteinG: Int, carbsG: Int,
         fatG: Int, fiberG: Int,
         pendingSync: Bool = false, lastSyncedAt: Date? = nil) {
        self.userId = userId
        self.dailyCalories = dailyCalories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.fiberG = fiberG
        self.pendingSync = pendingSync
        self.lastSyncedAt = lastSyncedAt
    }
}

// MARK: - Product (shared catalog; nullify on delete from MealItem)

@Model
final class ProductEntity {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var barcode: String?
    var name: String
    var brand: String?
    var servingSizeG: Double
    var caloriesPerServing: Double
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    var fiberG: Double
    var category: String

    var pendingSync: Bool
    var lastSyncedAt: Date?

    init(id: UUID, barcode: String?, name: String, brand: String?,
         servingSizeG: Double, caloriesPerServing: Double,
         proteinG: Double, carbsG: Double, fatG: Double, fiberG: Double,
         category: String,
         pendingSync: Bool = false, lastSyncedAt: Date? = nil) {
        self.id = id
        self.barcode = barcode
        self.name = name
        self.brand = brand
        self.servingSizeG = servingSizeG
        self.caloriesPerServing = caloriesPerServing
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.fiberG = fiberG
        self.category = category
        self.pendingSync = pendingSync
        self.lastSyncedAt = lastSyncedAt
    }
}

// MARK: - Meals

@Model
final class MealEntity {
    @Attribute(.unique) var id: UUID
    var userId: UUID
    var mealType: String                         // raw value of `MealType`
    var mealDate: Date

    @Relationship(deleteRule: .cascade, inverse: \MealItemEntity.meal)
    var items: [MealItemEntity] = []

    var pendingSync: Bool
    var lastSyncedAt: Date?

    init(id: UUID, userId: UUID, mealType: String, mealDate: Date,
         pendingSync: Bool = false, lastSyncedAt: Date? = nil) {
        self.id = id
        self.userId = userId
        self.mealType = mealType
        self.mealDate = mealDate
        self.pendingSync = pendingSync
        self.lastSyncedAt = lastSyncedAt
    }
}

@Model
final class MealItemEntity {
    @Attribute(.unique) var id: UUID
    /// Frozen snapshot of the source product at log time — see ADR-0004 §6.
    var productId: UUID?
    var productName: String
    var brand: String?
    var servings: Double
    var calories: Double
    var proteinG: Double
    var carbsG: Double
    var fatG: Double

    /// Inverse of MealEntity.items. Cascade delete from parent meal.
    @Relationship(deleteRule: .nullify) var meal: MealEntity?
    /// Nullify if the underlying product is deleted (catalog entry).
    @Relationship(deleteRule: .nullify) var product: ProductEntity?

    var pendingSync: Bool
    var lastSyncedAt: Date?

    init(id: UUID, productId: UUID?, productName: String, brand: String?,
         servings: Double, calories: Double,
         proteinG: Double, carbsG: Double, fatG: Double,
         pendingSync: Bool = false, lastSyncedAt: Date? = nil) {
        self.id = id
        self.productId = productId
        self.productName = productName
        self.brand = brand
        self.servings = servings
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.pendingSync = pendingSync
        self.lastSyncedAt = lastSyncedAt
    }
}

// MARK: - Daily nutrition (denormalized snapshot for fast home rendering)

@Model
final class DailyNutritionEntity {
    /// Composite key: userId + date (truncated to day). Stored as a single
    /// derived string for unique constraint. Use `Self.makeKey(userId:date:)`.
    @Attribute(.unique) var dayKey: String
    var userId: UUID
    var date: Date
    var calories: Double
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    var fiberG: Double

    var lastSyncedAt: Date?

    init(userId: UUID, date: Date, calories: Double, proteinG: Double,
         carbsG: Double, fatG: Double, fiberG: Double,
         lastSyncedAt: Date? = nil) {
        self.dayKey = Self.makeKey(userId: userId, date: date)
        self.userId = userId
        self.date = date
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.fiberG = fiberG
        self.lastSyncedAt = lastSyncedAt
    }

    static func makeKey(userId: UUID, date: Date) -> String {
        let day = Calendar(identifier: .iso8601).startOfDay(for: date)
        return "\(userId.uuidString):\(Int(day.timeIntervalSince1970))"
    }
}

// MARK: - Meal plan + Shopping list

@Model
final class MealPlanEntity {
    @Attribute(.unique) var id: UUID
    var userId: UUID
    var weekStartDate: Date

    @Relationship(deleteRule: .cascade, inverse: \MealPlanItemEntity.plan)
    var items: [MealPlanItemEntity] = []

    var pendingSync: Bool
    var lastSyncedAt: Date?

    init(id: UUID, userId: UUID, weekStartDate: Date,
         pendingSync: Bool = false, lastSyncedAt: Date? = nil) {
        self.id = id
        self.userId = userId
        self.weekStartDate = weekStartDate
        self.pendingSync = pendingSync
        self.lastSyncedAt = lastSyncedAt
    }
}

@Model
final class MealPlanItemEntity {
    @Attribute(.unique) var id: UUID
    var dayIndex: Int                            // 0..6 (Mon..Sun)
    var mealType: String                         // raw value of `MealType`
    var productName: String
    var servings: Double

    @Relationship(deleteRule: .nullify) var plan: MealPlanEntity?

    var pendingSync: Bool

    init(id: UUID, dayIndex: Int, mealType: String,
         productName: String, servings: Double,
         pendingSync: Bool = false) {
        self.id = id
        self.dayIndex = dayIndex
        self.mealType = mealType
        self.productName = productName
        self.servings = servings
        self.pendingSync = pendingSync
    }
}

@Model
final class ShoppingListEntity {
    @Attribute(.unique) var id: UUID
    var mealPlanId: UUID
    var generatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \ShoppingListItemEntity.list)
    var items: [ShoppingListItemEntity] = []

    var lastSyncedAt: Date?

    init(id: UUID, mealPlanId: UUID, generatedAt: Date, lastSyncedAt: Date? = nil) {
        self.id = id
        self.mealPlanId = mealPlanId
        self.generatedAt = generatedAt
        self.lastSyncedAt = lastSyncedAt
    }
}

@Model
final class ShoppingListItemEntity {
    @Attribute(.unique) var id: UUID
    var name: String
    var quantity: String
    var category: String                         // raw value of `ShoppingCategory`
    var checked: Bool

    @Relationship(deleteRule: .nullify) var list: ShoppingListEntity?

    var pendingSync: Bool

    init(id: UUID, name: String, quantity: String, category: String,
         checked: Bool = false, pendingSync: Bool = false) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.category = category
        self.checked = checked
        self.pendingSync = pendingSync
    }
}

// MARK: - Exercises + Programs

@Model
final class ExerciseEntity {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var name: String
    var primaryMuscle: String                    // raw value of `MuscleGroup`
    /// Comma-joined raw values; structured filtering happens in service code.
    var secondaryMusclesRaw: String
    var equipment: String                        // raw value of `Equipment`
    var difficulty: String                       // raw value of `Difficulty`
    var videoURLString: String?

    var lastSyncedAt: Date?

    init(id: UUID, name: String, primaryMuscle: String,
         secondaryMusclesRaw: String, equipment: String,
         difficulty: String, videoURLString: String? = nil,
         lastSyncedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.primaryMuscle = primaryMuscle
        self.secondaryMusclesRaw = secondaryMusclesRaw
        self.equipment = equipment
        self.difficulty = difficulty
        self.videoURLString = videoURLString
        self.lastSyncedAt = lastSyncedAt
    }
}

@Model
final class WorkoutProgramEntity {
    @Attribute(.unique) var id: UUID
    var name: String
    var summary: String
    var daysPerWeek: Int
    var difficulty: String

    @Relationship(deleteRule: .cascade, inverse: \WorkoutProgramDayEntity.program)
    var days: [WorkoutProgramDayEntity] = []

    var lastSyncedAt: Date?

    init(id: UUID, name: String, summary: String,
         daysPerWeek: Int, difficulty: String,
         lastSyncedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.summary = summary
        self.daysPerWeek = daysPerWeek
        self.difficulty = difficulty
        self.lastSyncedAt = lastSyncedAt
    }
}

@Model
final class WorkoutProgramDayEntity {
    @Attribute(.unique) var id: UUID
    var dayName: String

    @Relationship(deleteRule: .nullify) var program: WorkoutProgramEntity?
    @Relationship(deleteRule: .cascade, inverse: \WorkoutProgramExerciseSpecEntity.day)
    var exercises: [WorkoutProgramExerciseSpecEntity] = []

    init(id: UUID, dayName: String) {
        self.id = id
        self.dayName = dayName
    }
}

@Model
final class WorkoutProgramExerciseSpecEntity {
    @Attribute(.unique) var id: UUID
    var exerciseId: UUID
    var exerciseName: String
    var sets: Int
    var repsLow: Int
    var repsHigh: Int
    var restSeconds: Int

    @Relationship(deleteRule: .nullify) var day: WorkoutProgramDayEntity?

    init(id: UUID, exerciseId: UUID, exerciseName: String,
         sets: Int, repsLow: Int, repsHigh: Int, restSeconds: Int) {
        self.id = id
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.sets = sets
        self.repsLow = repsLow
        self.repsHigh = repsHigh
        self.restSeconds = restSeconds
    }
}

// MARK: - Workout sessions + sets + PRs

@Model
final class WorkoutSessionEntity {
    @Attribute(.unique) var id: UUID
    var userId: UUID
    var startedAt: Date
    var completedAt: Date?
    var programName: String
    var dayName: String

    @Relationship(deleteRule: .cascade, inverse: \WorkoutSetEntity.session)
    var sets: [WorkoutSetEntity] = []

    var pendingSync: Bool
    var lastSyncedAt: Date?

    init(id: UUID, userId: UUID, startedAt: Date, completedAt: Date?,
         programName: String, dayName: String,
         pendingSync: Bool = false, lastSyncedAt: Date? = nil) {
        self.id = id
        self.userId = userId
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.programName = programName
        self.dayName = dayName
        self.pendingSync = pendingSync
        self.lastSyncedAt = lastSyncedAt
    }
}

@Model
final class WorkoutSetEntity {
    @Attribute(.unique) var id: UUID
    var exerciseId: UUID
    var setNumber: Int
    var weightKg: Double
    var reps: Int
    var isPR: Bool

    @Relationship(deleteRule: .nullify) var session: WorkoutSessionEntity?
    /// Nullify if catalog exercise is deleted — keeps historical numbers
    /// (per ADR-0004 §5).
    @Relationship(deleteRule: .nullify) var exercise: ExerciseEntity?

    var pendingSync: Bool

    init(id: UUID, exerciseId: UUID, setNumber: Int,
         weightKg: Double, reps: Int, isPR: Bool = false,
         pendingSync: Bool = false) {
        self.id = id
        self.exerciseId = exerciseId
        self.setNumber = setNumber
        self.weightKg = weightKg
        self.reps = reps
        self.isPR = isPR
        self.pendingSync = pendingSync
    }
}

@Model
final class PersonalRecordEntity {
    @Attribute(.unique) var id: UUID
    var userId: UUID
    var exerciseId: UUID
    var exerciseName: String
    var weightKg: Double
    var reps: Int
    var achievedAt: Date

    var lastSyncedAt: Date?

    init(id: UUID, userId: UUID, exerciseId: UUID, exerciseName: String,
         weightKg: Double, reps: Int, achievedAt: Date,
         lastSyncedAt: Date? = nil) {
        self.id = id
        self.userId = userId
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.weightKg = weightKg
        self.reps = reps
        self.achievedAt = achievedAt
        self.lastSyncedAt = lastSyncedAt
    }
}
