//
//  TDEECalculatorTests.swift
//  Slice 5 (Task 5.1) — verifies the iOS TDEE calculator produces results
//  identical to the backend's `app.services.tdee_calculator` for every
//  fixture case exported by `backend/scripts/export_tdee_fixtures.py`.
//
//  The fixture JSON is the contract: any drift between iOS and backend
//  fails this suite. Backend is the source of truth — if a case fails,
//  fix the iOS implementation.
//

import Foundation
import Testing
@testable import FitTracker

@Suite("TDEECalculator")
struct TDEECalculatorTests {

    // MARK: - Reference cases

    @Test("BMR — male, 80kg/180cm/30y → 1780 (Mifflin-St Jeor)")
    func bmr_referenceMale() {
        let bmr = TDEECalculator.bmr(
            weightKg: 80, heightCm: 180, age: 30, sex: .male
        )
        #expect(abs(bmr - 1780.0) < 0.001)
    }

    @Test("BMR — female, 80kg/180cm/30y → 1614 (sex offset −161)")
    func bmr_referenceFemale() {
        let bmr = TDEECalculator.bmr(
            weightKg: 80, heightCm: 180, age: 30, sex: .female
        )
        #expect(abs(bmr - 1614.0) < 0.001)
    }

    @Test("BMR — `other` follows the female (-161) branch (matches backend non-male path)")
    func bmr_otherSexFollowsFemaleBranch() {
        let bmrOther = TDEECalculator.bmr(
            weightKg: 80, heightCm: 180, age: 30, sex: .other
        )
        let bmrFemale = TDEECalculator.bmr(
            weightKg: 80, heightCm: 180, age: 30, sex: .female
        )
        #expect(abs(bmrOther - bmrFemale) < 0.001)
    }

    @Test("TDEE — moderate activity multiplies BMR by 1.55")
    func tdee_moderateMultiplier() {
        let tdee = TDEECalculator.tdee(bmr: 1780.0, activity: .moderate)
        #expect(abs(tdee - 2759.0) < 0.001)
    }

    @Test("TDEE — sedentary 1.2 / light 1.375 / active 1.725 / very active 1.9")
    func tdee_allMultipliers() {
        let bmr = 2000.0
        #expect(abs(TDEECalculator.tdee(bmr: bmr, activity: .sedentary) - 2400) < 0.001)
        #expect(abs(TDEECalculator.tdee(bmr: bmr, activity: .light) - 2750) < 0.001)
        #expect(abs(TDEECalculator.tdee(bmr: bmr, activity: .moderate) - 3100) < 0.001)
        #expect(abs(TDEECalculator.tdee(bmr: bmr, activity: .active) - 3450) < 0.001)
        #expect(abs(TDEECalculator.tdee(bmr: bmr, activity: .veryActive) - 3800) < 0.001)
    }

    // MARK: - Macros

    @Test("macros — 2g/kg protein floor honored even on tiny goals")
    func macros_proteinFloor() {
        let m = TDEECalculator.macros(tdee: 2000, goal: .fatLoss, weightKg: 80)
        #expect(m.proteinG == 160)
    }

    @Test("macros — daily_calories floor is 1200 kcal even after −500 fat-loss adjustment")
    func macros_calorieFloor() {
        let m = TDEECalculator.macros(tdee: 1231.8, goal: .fatLoss, weightKg: 40)
        #expect(m.dailyCalories == 1200)
    }

    @Test("macros — Maintenance preserves TDEE-rounded calories (no shift)")
    func macros_maintenanceNoShift() {
        let m = TDEECalculator.macros(tdee: 2759.0, goal: .maintenance, weightKg: 80)
        #expect(m.dailyCalories == 2759)
    }

    @Test("macros — Lean bulk +250, Muscle gain +500")
    func macros_bulkAdjustments() {
        let lean = TDEECalculator.macros(tdee: 2000, goal: .leanBulk, weightKg: 80)
        let mass = TDEECalculator.macros(tdee: 2000, goal: .muscleGain, weightKg: 80)
        #expect(lean.dailyCalories == 2250)
        #expect(mass.dailyCalories == 2500)
    }

    // MARK: - Field bounds (mirrors backend Pydantic constraints)

    @Test("validate — accepts valid bounds")
    func validate_accepts() {
        let p = UserProfile(
            weightKg: 80, heightCm: 180, age: 30, sex: .male, activity: .moderate
        )
        #expect(TDEECalculator.validate(p) == nil)
    }

    @Test("validate — rejects weight 30kg lower bound is allowed; 29kg is not")
    func validate_weightLowerBound() {
        let ok = UserProfile(
            weightKg: 30, heightCm: 180, age: 30, sex: .male, activity: .moderate
        )
        let bad = UserProfile(
            weightKg: 29.9, heightCm: 180, age: 30, sex: .male, activity: .moderate
        )
        #expect(TDEECalculator.validate(ok) == nil)
        #expect(TDEECalculator.validate(bad) == .weightOutOfRange)
    }

    @Test("validate — rejects age 12 or 121")
    func validate_age() {
        let young = UserProfile(
            weightKg: 80, heightCm: 180, age: 12, sex: .male, activity: .moderate
        )
        let old = UserProfile(
            weightKg: 80, heightCm: 180, age: 121, sex: .male, activity: .moderate
        )
        #expect(TDEECalculator.validate(young) == .ageOutOfRange)
        #expect(TDEECalculator.validate(old) == .ageOutOfRange)
    }

    @Test("validate — rejects height 99cm or 231cm")
    func validate_height() {
        let short = UserProfile(
            weightKg: 80, heightCm: 99, age: 30, sex: .male, activity: .moderate
        )
        let tall = UserProfile(
            weightKg: 80, heightCm: 231, age: 30, sex: .male, activity: .moderate
        )
        #expect(TDEECalculator.validate(short) == .heightOutOfRange)
        #expect(TDEECalculator.validate(tall) == .heightOutOfRange)
    }

    // MARK: - Backend parity (fixture-driven)

    @Test("backend parity — every fixture case matches iOS output within 0.5 kcal")
    func backendFixtureParity() throws {
        let fixture = try Self.loadFixture()
        let tolerance = fixture.toleranceKcal

        #expect(fixture.cases.count >= 30, "fixture should cover ≥30 cases")

        for (i, c) in fixture.cases.enumerated() {
            let p = UserProfile(
                weightKg: c.input.weightKg,
                heightCm: c.input.heightCm,
                age: c.input.age,
                sex: Sex(rawValue: c.input.sex == "male" ? "male" : "female") ?? .female,
                activity: ActivityLevel.from(backendValue: c.input.activityLevel)
            )
            let goal = GoalPreset.from(backendValue: c.input.goalPreset)
            let bmr = TDEECalculator.bmr(
                weightKg: p.weightKg, heightCm: p.heightCm, age: p.age, sex: p.sex
            )
            let tdee = TDEECalculator.tdee(bmr: bmr, activity: p.activity)
            let macros = TDEECalculator.macros(
                tdee: tdee, goal: goal, weightKg: p.weightKg
            )

            #expect(
                abs(bmr - c.expected.bmr) < tolerance,
                "case \(i) BMR drift: ios=\(bmr) backend=\(c.expected.bmr) input=\(c.input)"
            )
            #expect(
                abs(tdee - c.expected.tdee) < tolerance,
                "case \(i) TDEE drift: ios=\(tdee) backend=\(c.expected.tdee) input=\(c.input)"
            )
            #expect(
                macros.dailyCalories == c.expected.dailyCalories,
                "case \(i) calories: ios=\(macros.dailyCalories) backend=\(c.expected.dailyCalories) input=\(c.input)"
            )
            #expect(
                macros.proteinG == c.expected.dailyProteinG,
                "case \(i) protein: ios=\(macros.proteinG) backend=\(c.expected.dailyProteinG) input=\(c.input)"
            )
            #expect(
                macros.fatG == c.expected.dailyFatG,
                "case \(i) fat: ios=\(macros.fatG) backend=\(c.expected.dailyFatG) input=\(c.input)"
            )
            #expect(
                macros.carbsG == c.expected.dailyCarbsG,
                "case \(i) carbs: ios=\(macros.carbsG) backend=\(c.expected.dailyCarbsG) input=\(c.input)"
            )
        }
    }

    // MARK: - Fixture loading

    private struct Fixture: Decodable, Sendable {
        let version: Int
        let toleranceKcal: Double
        let caseCount: Int
        let cases: [Case]

        enum CodingKeys: String, CodingKey {
            case version
            case toleranceKcal = "tolerance_kcal"
            case caseCount = "case_count"
            case cases
        }
    }
    private struct Case: Decodable, Sendable {
        let input: Input
        let expected: Expected
    }
    private struct Input: Decodable, Sendable {
        let weightKg: Double
        let heightCm: Double
        let age: Int
        let sex: String
        let activityLevel: String
        let goalPreset: String
        enum CodingKeys: String, CodingKey {
            case weightKg = "weight_kg"
            case heightCm = "height_cm"
            case age, sex
            case activityLevel = "activity_level"
            case goalPreset = "goal_preset"
        }
    }
    private struct Expected: Decodable, Sendable {
        let bmr: Double
        let tdee: Double
        let dailyCalories: Int
        let dailyProteinG: Int
        let dailyFatG: Int
        let dailyCarbsG: Int
        enum CodingKeys: String, CodingKey {
            case bmr, tdee
            case dailyCalories = "daily_calories"
            case dailyProteinG = "daily_protein_g"
            case dailyFatG = "daily_fat_g"
            case dailyCarbsG = "daily_carbs_g"
        }
    }

    private static func loadFixture() throws -> Fixture {
        let bundle = Bundle(for: BundleAnchor.self)
        guard let url = bundle.url(forResource: "tdee_fixtures", withExtension: "json") else {
            throw FixtureError.missingResource
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Fixture.self, from: data)
    }

    private final class BundleAnchor {}
    private enum FixtureError: Error { case missingResource }
}
