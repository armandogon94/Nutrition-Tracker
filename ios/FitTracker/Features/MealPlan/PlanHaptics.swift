//
//  PlanHaptics.swift
//  Slice 4.3: thin haptics wrapper scoped to the meal-plan feature. A
//  shared Core/Haptics helper does not exist yet; rather than reach across
//  feature boundaries (this slice owns only Features/MealPlan/*), we keep a
//  small local shim. When a Core haptics service lands, callers swap to it.
//
//  No-ops cleanly off the main actor / on platforms without Taptic Engine.
//

import UIKit

enum PlanHaptics {
    @MainActor
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let gen = UIImpactFeedbackGenerator(style: style)
        gen.prepare()
        gen.impactOccurred()
    }

    @MainActor
    static func selection() {
        let gen = UISelectionFeedbackGenerator()
        gen.selectionChanged()
    }

    @MainActor
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
