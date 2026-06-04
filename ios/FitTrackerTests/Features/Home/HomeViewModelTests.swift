//
//  HomeViewModelTests.swift
//  Slice 2.6 — the dashboard refines its TDEE estimate when HealthKit has a
//  FRESH bodyweight sample, otherwise it uses the weight saved on the
//  profile. The decision is a pure function (`HomeViewModel.refineTDEE`) so
//  it's testable without HealthKit or SwiftUI.
//
//  Cases:
//    - fresh HK sample (within the freshness window) → TDEE uses HK weight
//    - stale HK sample (older than the window)       → TDEE uses profile weight
//    - no HK sample at all                            → TDEE uses profile weight
//    - parity: the chosen TDEE equals TDEECalculator on the chosen weight
//

import Foundation
import Testing
@testable import FitTracker

@Suite("HomeViewModel TDEE refinement (Slice 2.6)")
struct HomeViewModelTests {

    private let profile = UserProfile(
        weightKg: 80, heightCm: 180, age: 30, sex: .male, activity: .moderate
    )

    /// Expected TDEE for a given weight, computed straight from the shared
    /// calculator — the helper must not diverge from it.
    private func expectedTDEE(weightKg: Double) -> Double {
        let bmr = TDEECalculator.bmr(
            weightKg: weightKg, heightCm: 180, age: 30, sex: .male
        )
        return TDEECalculator.tdee(bmr: bmr, activity: .moderate)
    }

    @Test("Fresh HealthKit sample refines TDEE using the HealthKit weight")
    func fresh_usesHealthKitWeight() {
        let now = Date()
        let sample = BodyMassReading(weightKg: 85, date: now.addingTimeInterval(-3_600)) // 1h old
        let result = HomeViewModel.refineTDEE(
            profile: profile,
            healthKit: sample,
            now: now,
            freshnessWindow: 7 * 86_400
        )
        #expect(result.usedHealthKit == true)
        #expect(result.effectiveWeightKg == 85)
        #expect(abs(result.tdee - expectedTDEE(weightKg: 85)) < 0.001)
        // And it must differ from the profile-weight TDEE (85 ≠ 80).
        #expect(result.tdee != expectedTDEE(weightKg: 80))
    }

    @Test("Stale HealthKit sample falls back to the profile weight")
    func stale_usesProfileWeight() {
        let now = Date()
        let sample = BodyMassReading(weightKg: 85, date: now.addingTimeInterval(-30 * 86_400)) // 30d old
        let result = HomeViewModel.refineTDEE(
            profile: profile,
            healthKit: sample,
            now: now,
            freshnessWindow: 7 * 86_400
        )
        #expect(result.usedHealthKit == false)
        #expect(result.effectiveWeightKg == 80)
        #expect(abs(result.tdee - expectedTDEE(weightKg: 80)) < 0.001)
    }

    @Test("No HealthKit sample uses the profile weight")
    func none_usesProfileWeight() {
        let result = HomeViewModel.refineTDEE(
            profile: profile,
            healthKit: nil,
            now: Date(),
            freshnessWindow: 7 * 86_400
        )
        #expect(result.usedHealthKit == false)
        #expect(result.effectiveWeightKg == 80)
        #expect(abs(result.tdee - expectedTDEE(weightKg: 80)) < 0.001)
    }

    @Test("A sample exactly at the freshness boundary still counts as fresh")
    func boundary_isFresh() {
        let now = Date()
        let window: TimeInterval = 7 * 86_400
        let sample = BodyMassReading(weightKg: 78, date: now.addingTimeInterval(-window)) // exactly window old
        let result = HomeViewModel.refineTDEE(
            profile: profile,
            healthKit: sample,
            now: now,
            freshnessWindow: window
        )
        #expect(result.usedHealthKit == true)
        #expect(result.effectiveWeightKg == 78)
    }

    @Test("A future-dated sample is treated as fresh (clock skew tolerance)")
    func futureDated_isFresh() {
        let now = Date()
        let sample = BodyMassReading(weightKg: 79, date: now.addingTimeInterval(3_600)) // 1h in the future
        let result = HomeViewModel.refineTDEE(
            profile: profile,
            healthKit: sample,
            now: now,
            freshnessWindow: 7 * 86_400
        )
        #expect(result.usedHealthKit == true)
        #expect(result.effectiveWeightKg == 79)
    }
}
