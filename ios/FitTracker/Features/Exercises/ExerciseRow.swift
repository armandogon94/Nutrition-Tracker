//
//  ExerciseRow.swift
//  Slice 6.4: row used by `ExercisesBrowserView`. Stable identity comes
//  from the underlying `Exercise.id` (UUID); the row itself stays cheap
//  and snapshot-friendly. AsyncImage's `.task` cancellation is wired
//  via `id:` so SwiftUI tears down the request when the row scrolls
//  off-screen.
//

import SwiftUI

struct ExerciseRow: View {
    @Environment(\.appTheme) private var theme
    let exercise: Exercise

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name)
                    .font(theme.font.bodyMedium)
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                Text("\(exercise.primaryMuscle.label) · \(exercise.equipment.label)")
                    .font(theme.font.caption)
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            difficultyDot
            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundStyle(theme.textTertiary)
        }
        .padding(10)
        .themedInnerCard()
    }

    @ViewBuilder
    private var thumbnail: some View {
        // The seed exercises don't ship with thumbnails — the YouTube
        // links don't expose easily-fetchable images without an API key.
        // We render a muscle-icon fallback. Once the backend provides a
        // dedicated thumbnail URL we can swap in AsyncImage here without
        // changing the row contract.
        ZStack {
            Circle().fill(theme.accent.opacity(0.18))
            Image(systemName: muscleIcon)
                .foregroundStyle(theme.accent)
                .font(.system(size: 18, weight: .semibold))
        }
    }

    private var muscleIcon: String {
        switch exercise.primaryMuscle {
        case .chest: "figure.strengthtraining.traditional"
        case .back: "figure.cooldown"
        case .legs: "figure.run"
        case .shoulders: "figure.boxing"
        case .arms: "dumbbell.fill"
        case .core: "figure.core.training"
        }
    }

    private var difficultyDot: some View {
        let color: Color = {
            switch exercise.difficulty {
            case .beginner: theme.positive
            case .intermediate: theme.accent
            case .advanced: theme.negative
            }
        }()
        return Circle()
            .fill(color)
            .frame(width: 6, height: 6)
    }
}
