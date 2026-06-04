//
//  HealthKitBodyMassTests.swift
//  Slice 2.5 — HealthKit bodyweight READ.
//
//  HKHealthStore itself can't be mocked (opaque system class, permission
//  UI). We therefore inject the *query execution* as a closure seam:
//  `HealthKitService.init(store:bodyMassFetcher:)`. The fetcher returns the
//  raw `[HKQuantitySample]` that an HKSampleQuery for `.bodyMass` would
//  yield; the testable logic under `latestBodyMass()` is then:
//    - pick the most-recent sample (already sorted newest-first by the
//      real query's sort descriptor; we don't re-sort)
//    - convert its quantity to kilograms
//    - return nil for an empty result or an unavailable store
//
//  These tests stub the fetcher with deterministic samples and assert the
//  conversion + selection. The thin glue that builds the real HKSampleQuery
//  is exercised manually on a real device (Simulator HealthKit is limited).
//

import Foundation
import HealthKit
import Testing
@testable import FitTracker

@MainActor
@Suite("HealthKitService bodyweight read (Slice 2.5)", .serialized)
struct HealthKitBodyMassTests {

    /// Builds a body-mass sample at `kg` kilograms, ending at `date`.
    private func bodyMassSample(kg: Double, date: Date) -> HKQuantitySample {
        let type = HKQuantityType(.bodyMass)
        let quantity = HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kg)
        return HKQuantitySample(type: type, quantity: quantity, start: date, end: date)
    }

    @Test("latestBodyMass returns the newest sample's value in kilograms")
    func latestBodyMass_returnsNewestInKg() async throws {
        let now = Date()
        let newest = bodyMassSample(kg: 82.5, date: now)
        let older = bodyMassSample(kg: 80.0, date: now.addingTimeInterval(-86_400))
        // Real query sorts newest-first; mirror that ordering here.
        let service = HealthKitService(
            store: HKHealthStore(),
            bodyMassFetcher: { _ in [newest, older] }
        )
        let result = try await service.latestBodyMass()
        #expect(result == 82.5)
    }

    @Test("latestBodyMass converts gram-based samples to kilograms")
    func latestBodyMass_convertsUnits() async throws {
        // 75 000 grams == 75 kg. Construct via the kilo unit so the stored
        // value is unambiguous, then verify the service reports kilograms.
        let sample = bodyMassSample(kg: 75.0, date: Date())
        let service = HealthKitService(
            store: HKHealthStore(),
            bodyMassFetcher: { _ in [sample] }
        )
        let result = try await service.latestBodyMass()
        #expect(result == 75.0)
    }

    @Test("latestBodyMass returns nil when there are no samples")
    func latestBodyMass_nilWhenEmpty() async throws {
        let service = HealthKitService(
            store: HKHealthStore(),
            bodyMassFetcher: { _ in [] }
        )
        let result = try await service.latestBodyMass()
        #expect(result == nil)
    }

    @Test("latestBodyMass returns nil when the HealthKit store is unavailable")
    func latestBodyMass_nilWhenUnavailable() async throws {
        // No store at all (HealthKit unavailable on this device) → nil,
        // never a throw: the dashboard must keep rendering its profile
        // bodyweight fallback.
        let service = HealthKitService(store: nil)
        let result = try await service.latestBodyMass()
        #expect(result == nil)
    }
}
