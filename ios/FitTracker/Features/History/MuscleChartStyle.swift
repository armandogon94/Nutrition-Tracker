//
//  MuscleChartStyle.swift
//  Slice 8.4: color-blind-safe color mapping + axis symbols for muscle
//  groups in the analytics charts.
//
//  The default theme `categoryColors` are tuned for macros and re-use
//  similar hues (two greens, two purples) that deuteranopes/protanopes
//  can confuse. For the volume-by-muscle chart we instead anchor on the
//  Okabe-Ito qualitative palette — eight hues explicitly designed to stay
//  distinguishable across the common color-vision deficiencies. We also
//  pair each muscle with a distinct SF Symbol so color is never the ONLY
//  channel carrying meaning (WCAG 1.4.1 — use of color).
//

import SwiftUI

enum MuscleChartStyle {

    /// Okabe-Ito color-blind-safe palette, one stable hue per muscle.
    static func color(for muscle: MuscleGroup) -> Color {
        switch muscle {
        case .chest:     return Color(red: 0.00, green: 0.45, blue: 0.70) // blue
        case .back:      return Color(red: 0.90, green: 0.62, blue: 0.00) // orange
        case .legs:      return Color(red: 0.00, green: 0.62, blue: 0.45) // bluish green
        case .shoulders: return Color(red: 0.80, green: 0.47, blue: 0.65) // reddish purple
        case .arms:      return Color(red: 0.34, green: 0.71, blue: 0.91) // sky blue
        case .core:      return Color(red: 0.84, green: 0.37, blue: 0.00) // vermillion
        }
    }

    /// A glyph that doubles as a redundant (non-color) legend marker so the
    /// chart is legible without color perception.
    static func symbol(for muscle: MuscleGroup) -> String {
        switch muscle {
        case .chest:     return "circle.fill"
        case .back:      return "square.fill"
        case .legs:      return "triangle.fill"
        case .shoulders: return "diamond.fill"
        case .arms:      return "hexagon.fill"
        case .core:      return "star.fill"
        }
    }

    /// Deterministic legend order — biggest, most common muscle groups
    /// first, so the same muscle is always the same swatch across renders.
    static let legendOrder: [MuscleGroup] = [.chest, .back, .legs, .shoulders, .arms, .core]
}
