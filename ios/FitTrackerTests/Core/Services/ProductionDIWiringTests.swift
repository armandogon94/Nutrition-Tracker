//
//  ProductionDIWiringTests.swift
//  Codex P0 ("production DI still mock") — verifies MockServiceContainer
//  .production() vends a REAL concrete service for EVERY domain slot, not
//  just auth/nutrition/profile/history. Products, meals, mealPlan,
//  programs, exercises, and workouts were still mocks (codex-review-1 #5,
//  codex-review-2 #5), so the shipped app ran fake data and never exercised
//  the real backend contracts for those flows.
//
//  Mirrors NutritionServiceWiringTests / HistoryServiceWiringTests: the
//  production factory injects concrete live services backed by ONE shared
//  authenticated APIClient + the live SwiftData store, while the default
//  initializer keeps the all-mock container for previews + unit tests.
//

import Foundation
import SwiftData
import Testing
@testable import FitTracker

@MainActor
@Suite("Production DI wiring — every domain is real in production()", .serialized)
struct ProductionDIWiringTests {

    // MARK: - production() vends real concrete services for every slot

    @Test("production() yields a REAL ProductService, not the mock")
    func production_yieldsRealProducts() {
        let c = MockServiceContainer.production()
        #expect(c.products is ProductService, "production must inject the real ProductService")
        #expect(!(c.products is MockProductsService), "production must NOT keep the products mock")
    }

    @Test("production() yields a REAL MealService, not the mock")
    func production_yieldsRealMeals() {
        let c = MockServiceContainer.production()
        #expect(c.meals is MealService, "production must inject the real MealService")
        #expect(!(c.meals is MockMealsService), "production must NOT keep the meals mock")
    }

    @Test("production() yields a REAL MealPlanService, not the mock")
    func production_yieldsRealMealPlan() {
        let c = MockServiceContainer.production()
        #expect(c.mealPlan is MealPlanService, "production must inject the real MealPlanService")
        #expect(!(c.mealPlan is MockMealPlanService), "production must NOT keep the mealPlan mock")
    }

    @Test("production() yields a REAL ProgramsService, not the mock")
    func production_yieldsRealPrograms() {
        let c = MockServiceContainer.production()
        #expect(c.programs is ProgramsService, "production must inject the real ProgramsService")
        #expect(!(c.programs is MockProgramsService), "production must NOT keep the programs mock")
    }

    @Test("production() yields a REAL ExercisesService, not the mock")
    func production_yieldsRealExercises() {
        let c = MockServiceContainer.production()
        #expect(c.exercises is ExercisesService, "production must inject the real ExercisesService")
        #expect(!(c.exercises is MockExercisesService), "production must NOT keep the exercises mock")
    }

    @Test("production() yields a REAL WorkoutService, not the mock")
    func production_yieldsRealWorkouts() {
        let c = MockServiceContainer.production()
        #expect(c.workouts is WorkoutService, "production must inject the real WorkoutService")
        #expect(!(c.workouts is MockWorkoutService), "production must NOT keep the workouts mock")
    }

    // MARK: - default init keeps the all-mock container (previews/tests)

    @Test("Default init keeps mocks for every newly-promoted slot")
    func defaultInit_keepsMocks() {
        let c = MockServiceContainer()
        #expect(c.products is MockProductsService)
        #expect(c.meals is MockMealsService)
        #expect(c.mealPlan is MockMealPlanService)
        #expect(c.programs is MockProgramsService)
        #expect(c.exercises is MockExercisesService)
        #expect(c.workouts is MockWorkoutService)
        // …and must NOT reach for the real services / backend.
        #expect(!(c.products is ProductService))
        #expect(!(c.meals is MealService))
        #expect(!(c.mealPlan is MealPlanService))
        #expect(!(c.programs is ProgramsService))
        #expect(!(c.exercises is ExercisesService))
        #expect(!(c.workouts is WorkoutService))
    }
}
