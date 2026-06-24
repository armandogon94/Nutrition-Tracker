//
//  ProfileViewModelTests.swift
//  Slice 5.3 — the TDEE preview panel must compute BMR/TDEE/macros through
//  the shared `TDEECalculator` (the backend-parity source of truth) rather
//  than the inline arithmetic the Slice 0.5 mock used. This removes a
//  second, drift-prone copy of the formula.
//
//  We test the pure preview value (`TDEEPreview`) directly: given a profile
//  it must equal what TDEECalculator produces, field for field.
//

import Foundation
import Testing
@testable import FitTracker

@Suite("TDEEPreview (Slice 5.3)")
struct ProfileViewModelTests {

    @Test("Preview BMR/TDEE come straight from TDEECalculator")
    func preview_matchesCalculatorBMRandTDEE() {
        let profile = UserProfile(
            weightKg: 80, heightCm: 180, age: 30, sex: .male, activity: .moderate
        )
        let preview = TDEEPreview(profile: profile)

        let expectedBMR = TDEECalculator.bmr(
            weightKg: 80, heightCm: 180, age: 30, sex: .male
        )
        let expectedTDEE = TDEECalculator.tdee(bmr: expectedBMR, activity: .moderate)

        #expect(abs(preview.bmr - expectedBMR) < 0.001)
        #expect(abs(preview.tdee - expectedTDEE) < 0.001)
        // Known value: BMR 1780, TDEE 1780 × 1.55 = 2759.
        #expect(Int(preview.bmr) == 1780)
        #expect(Int(preview.tdee) == 2759)
    }

    @Test("Preview macros come from TDEECalculator.macros at maintenance")
    func preview_macrosMatchCalculator() {
        let profile = UserProfile(
            weightKg: 80, heightCm: 180, age: 30, sex: .male, activity: .moderate
        )
        let preview = TDEEPreview(profile: profile)
        let expected = TDEECalculator.macros(
            tdee: preview.tdee, goal: .maintenance, weightKg: 80
        )
        #expect(preview.proteinG == expected.proteinG)
        #expect(preview.carbsG == expected.carbsG)
        #expect(preview.fatG == expected.fatG)
        // Protein at 2 g/kg → 160 g for an 80 kg user.
        #expect(preview.proteinG == 160)
    }

    @Test("Preview updates when the profile weight changes")
    func preview_reactsToWeight() {
        let lighter = TDEEPreview(profile: UserProfile(
            weightKg: 70, heightCm: 180, age: 30, sex: .male, activity: .moderate))
        let heavier = TDEEPreview(profile: UserProfile(
            weightKg: 90, heightCm: 180, age: 30, sex: .male, activity: .moderate))
        #expect(heavier.tdee > lighter.tdee)
        #expect(heavier.proteinG > lighter.proteinG)
    }

    @Test("Female branch subtracts 161 in the BMR (vs +5 male)")
    func preview_sexBranch() {
        let male = TDEEPreview(profile: UserProfile(
            weightKg: 70, heightCm: 170, age: 30, sex: .male, activity: .sedentary))
        let female = TDEEPreview(profile: UserProfile(
            weightKg: 70, heightCm: 170, age: 30, sex: .female, activity: .sedentary))
        // Male BMR is 166 higher than female (+5 vs −161).
        #expect(abs((male.bmr - female.bmr) - 166) < 0.001)
    }
}
