//
//  HealthKitServiceTests.swift
//  Slice 3.6: validates the testable surface of HealthKitService.
//
//  We can't mock HKHealthStore directly (it's an opaque system class
//  that pops a permission UI), so we focus on the pure helpers:
//    - sample construction (right unit, right value, right metadata)
//    - idempotency metadata (HKMetadataKeyExternalUUID == mealItem.id)
//    - graceful no-op when an item has zero macros
//
//  The thin glue around requestAuthorization / save is exercised
//  manually on a real device.
//

import Foundation
import HealthKit
import Testing
@testable import FitTracker

@MainActor
@Suite("HealthKitService", .serialized)
struct HealthKitServiceTests {

    @Test("makeSamples emits energy + 3 macros with the right units")
    func makeSamples_emitsExpectedTypes() {
        let item = MealItem(
            id: UUID(),
            productId: UUID(),
            productName: "Pollo",
            brand: nil,
            servings: 1.5,
            calories: 247.5,
            proteinG: 46.5,
            carbsG: 0,   // intentionally zero — should be omitted
            fatG: 5.4
        )
        let samples = HealthKitService.makeSamples(for: item, mealDate: .now)
        // Calories + protein + fat = 3. carbs == 0 is dropped.
        #expect(samples.count == 3, "zero-valued macros must not produce samples")
        let identifiers = Set(samples.map { $0.quantityType.identifier })
        #expect(identifiers.contains(HKQuantityTypeIdentifier.dietaryEnergyConsumed.rawValue))
        #expect(identifiers.contains(HKQuantityTypeIdentifier.dietaryProtein.rawValue))
        #expect(identifiers.contains(HKQuantityTypeIdentifier.dietaryFatTotal.rawValue))
        #expect(!identifiers.contains(HKQuantityTypeIdentifier.dietaryCarbohydrates.rawValue))
    }

    @Test("makeSamples encodes calories in kilocalories and macros in grams")
    func makeSamples_usesCorrectUnits() {
        let item = MealItem(
            id: UUID(), productId: UUID(),
            productName: "Avena", brand: nil,
            servings: 1, calories: 150, proteinG: 5, carbsG: 27, fatG: 3
        )
        let samples = HealthKitService.makeSamples(for: item, mealDate: .now)

        let energy = samples.first {
            $0.quantityType.identifier == HKQuantityTypeIdentifier.dietaryEnergyConsumed.rawValue
        }
        #expect(energy != nil)
        #expect(energy?.quantity.doubleValue(for: .kilocalorie()) == 150)

        let protein = samples.first {
            $0.quantityType.identifier == HKQuantityTypeIdentifier.dietaryProtein.rawValue
        }
        #expect(protein?.quantity.doubleValue(for: .gram()) == 5)
    }

    @Test("Every sample carries HKMetadataKeyExternalUUID = mealItem.id (idempotency)")
    func makeSamples_includesExternalUUID() {
        let id = UUID()
        let item = MealItem(
            id: id, productId: UUID(),
            productName: "X", brand: nil,
            servings: 1, calories: 100, proteinG: 10, carbsG: 10, fatG: 1
        )
        let samples = HealthKitService.makeSamples(for: item, mealDate: .now)
        for s in samples {
            #expect(s.metadata?[HKMetadataKeyExternalUUID] as? String == id.uuidString,
                    "Sample missing ExternalUUID — Apple Health will create duplicates on retry")
            #expect(s.metadata?[HKMetadataKeyFoodType] as? String == "meal")
        }
    }

    @Test("Item with all zero values yields no samples")
    func makeSamples_zeroItemYieldsNothing() {
        let item = MealItem(
            id: UUID(), productId: UUID(),
            productName: "Empty", brand: nil,
            servings: 0, calories: 0, proteinG: 0, carbsG: 0, fatG: 0
        )
        let samples = HealthKitService.makeSamples(for: item, mealDate: .now)
        #expect(samples.isEmpty)
    }

    @Test("writeMealEntry on a service without a store throws .unavailable")
    func writeMealEntry_unavailable() async {
        // Force the unavailable code path by passing nil store.
        let service = HealthKitService(store: nil)
        let item = MealItem(
            id: UUID(), productId: UUID(),
            productName: "Avena", brand: nil,
            servings: 1, calories: 150, proteinG: 5, carbsG: 27, fatG: 3
        )
        await #expect(throws: HealthKitError.unavailable) {
            try await service.writeMealEntry(item)
        }
    }
}
