//
//  Models.swift
//  Domain models used by mock services in Slice 0.5 and (later) the
//  real backend-backed services. These are plain Sendable structs —
//  SwiftData @Model classes land in Slice 2.
//

import Foundation
import SwiftUI

// MARK: - User / Profile

struct MockUser: Identifiable, Hashable, Sendable {
    let id: UUID
    let email: String
    let displayName: String
    let createdAt: Date
}

enum Sex: String, Hashable, CaseIterable, Sendable {
    case male, female, other

    var label: String {
        switch self {
        case .male: "Masculino"
        case .female: "Femenino"
        case .other: "Otro"
        }
    }
}

enum ActivityLevel: String, Hashable, CaseIterable, Sendable {
    case sedentary, light, moderate, active, veryActive

    var label: String {
        switch self {
        case .sedentary: "Sedentario"
        case .light: "Ligero"
        case .moderate: "Moderado"
        case .active: "Activo"
        case .veryActive: "Muy activo"
        }
    }

    var multiplier: Double {
        switch self {
        case .sedentary: 1.2
        case .light: 1.375
        case .moderate: 1.55
        case .active: 1.725
        case .veryActive: 1.9
        }
    }
}

struct UserProfile: Hashable, Sendable {
    var weightKg: Double
    var heightCm: Double
    var age: Int
    var sex: Sex
    var activity: ActivityLevel
}

struct NutritionGoal: Hashable, Sendable {
    var dailyCalories: Int
    var proteinG: Int
    var carbsG: Int
    var fatG: Int
    var fiberG: Int
}

// MARK: - Nutrition

enum MealType: String, Hashable, CaseIterable, Sendable {
    case breakfast, lunch, dinner, snack

    var label: String {
        switch self {
        case .breakfast: "Desayuno"
        case .lunch: "Almuerzo"
        case .dinner: "Cena"
        case .snack: "Snack"
        }
    }

    var icon: String {
        switch self {
        case .breakfast: "sun.horizon"
        case .lunch: "sun.max"
        case .dinner: "moon.stars"
        case .snack: "leaf"
        }
    }
}

struct Product: Identifiable, Hashable, Sendable {
    let id: UUID
    let barcode: String?
    let name: String
    let brand: String?
    let servingSizeG: Double
    let caloriesPerServing: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let fiberG: Double
    let category: String
}

struct MealItem: Identifiable, Hashable, Sendable {
    let id: UUID
    let productId: UUID
    let productName: String
    let brand: String?
    let servings: Double
    let calories: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
}

struct Meal: Identifiable, Hashable, Sendable {
    let id: UUID
    let mealType: MealType
    let mealDate: Date
    let items: [MealItem]

    var totalCalories: Double { items.reduce(0) { $0 + $1.calories } }
    var totalProtein: Double { items.reduce(0) { $0 + $1.proteinG } }
    var totalCarbs: Double { items.reduce(0) { $0 + $1.carbsG } }
    var totalFat: Double { items.reduce(0) { $0 + $1.fatG } }
}

struct DailyNutrition: Hashable, Sendable {
    let date: Date
    let calories: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let fiberG: Double
}

// MARK: - Meal Plan

struct MealPlanItem: Identifiable, Hashable, Sendable {
    let id: UUID
    let dayIndex: Int          // 0..6 (Mon..Sun)
    let mealType: MealType
    let productName: String
    let servings: Double
}

struct MealPlan: Identifiable, Hashable, Sendable {
    let id: UUID
    let weekStartDate: Date
    let items: [MealPlanItem]
}

enum ShoppingCategory: String, Hashable, CaseIterable, Sendable {
    case produce, dairy, proteins, grains, pantry, frozen, beverages, other

    var label: String {
        switch self {
        case .produce: "Frutas y verduras"
        case .dairy: "Lácteos"
        case .proteins: "Proteínas"
        case .grains: "Granos"
        case .pantry: "Despensa"
        case .frozen: "Congelados"
        case .beverages: "Bebidas"
        case .other: "Otros"
        }
    }
}

struct ShoppingItem: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let quantity: String
    let category: ShoppingCategory
    var checked: Bool
}

// MARK: - Workouts

enum MuscleGroup: String, Hashable, CaseIterable, Sendable {
    case chest, back, legs, shoulders, arms, core

    var label: String {
        switch self {
        case .chest: "Pecho"
        case .back: "Espalda"
        case .legs: "Piernas"
        case .shoulders: "Hombros"
        case .arms: "Brazos"
        case .core: "Core"
        }
    }
}

enum Equipment: String, Hashable, CaseIterable, Sendable {
    case barbell, dumbbell, machine, bodyweight, cable

    var label: String {
        switch self {
        case .barbell: "Barra"
        case .dumbbell: "Mancuerna"
        case .machine: "Máquina"
        case .bodyweight: "Peso corporal"
        case .cable: "Cable"
        }
    }
}

enum Difficulty: String, Hashable, CaseIterable, Sendable {
    case beginner, intermediate, advanced

    var label: String {
        switch self {
        case .beginner: "Principiante"
        case .intermediate: "Intermedio"
        case .advanced: "Avanzado"
        }
    }
}

struct Exercise: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let primaryMuscle: MuscleGroup
    let secondaryMuscles: [MuscleGroup]
    let equipment: Equipment
    let difficulty: Difficulty
    let videoURL: URL?
}

struct WorkoutProgramExerciseSpec: Identifiable, Hashable, Sendable {
    let id: UUID
    let exerciseId: UUID
    let exerciseName: String
    let sets: Int
    let repsLow: Int
    let repsHigh: Int
    let restSeconds: Int
}

struct WorkoutProgramDay: Identifiable, Hashable, Sendable {
    let id: UUID
    let dayName: String        // "Push", "Pull", "Legs", "Day 1", etc.
    let exercises: [WorkoutProgramExerciseSpec]
}

struct WorkoutProgram: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let summary: String
    let daysPerWeek: Int
    let difficulty: Difficulty
    let days: [WorkoutProgramDay]
}

struct WorkoutSet: Identifiable, Hashable, Sendable {
    let id: UUID
    let exerciseId: UUID
    let setNumber: Int
    let weightKg: Double
    let reps: Int
    let isPR: Bool
}

struct WorkoutSession: Identifiable, Hashable, Sendable {
    let id: UUID
    let startedAt: Date
    let completedAt: Date?
    let programName: String
    let dayName: String
    let sets: [WorkoutSet]

    var durationMinutes: Int? {
        guard let completedAt else { return nil }
        return Int(completedAt.timeIntervalSince(startedAt) / 60)
    }
    var totalVolume: Double {
        sets.reduce(0) { $0 + ($1.weightKg * Double($1.reps)) }
    }
}

struct PersonalRecord: Identifiable, Hashable, Sendable {
    let id: UUID
    let exerciseId: UUID
    let exerciseName: String
    let weightKg: Double
    let reps: Int
    let achievedAt: Date
}
