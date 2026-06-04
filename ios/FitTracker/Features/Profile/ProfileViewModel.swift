//
//  ProfileViewModel.swift
//  Slice 5.3 — the live TDEE preview value for ProfileView /
//  TDEECalculatorView. Computes BMR/TDEE/macros through the shared
//  `TDEECalculator` so the on-screen preview is byte-for-byte the
//  backend-parity formula (no second, drift-prone inline copy).
//
//  Pure value type: constructed from a `UserProfile`, recomputed by SwiftUI
//  whenever the form state changes. Macros are shown at the `.maintenance`
//  preset (the neutral baseline); the goal-specific deltas live in GoalsView.
//

import Foundation

struct TDEEPreview: Hashable, Sendable {
    let bmr: Double
    let tdee: Double
    let proteinG: Int
    let carbsG: Int
    let fatG: Int

    init(profile: UserProfile) {
        let bmr = TDEECalculator.bmr(
            weightKg: profile.weightKg,
            heightCm: profile.heightCm,
            age: profile.age,
            sex: profile.sex
        )
        let tdee = TDEECalculator.tdee(bmr: bmr, activity: profile.activity)
        let macros = TDEECalculator.macros(
            tdee: tdee, goal: .maintenance, weightKg: profile.weightKg
        )
        self.bmr = bmr
        self.tdee = tdee
        self.proteinG = macros.proteinG
        self.carbsG = macros.carbsG
        self.fatG = macros.fatG
    }
}
