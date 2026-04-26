//
//  ExerciseDetailView.swift
//  Slice 6.5: details for a single exercise — form video + meta.
//  Video routing follows ADR-0005:
//    - YouTube URL → "Ver en YouTube" button (UIApplication.shared.open)
//    - Other URL  → inline AVKit VideoPlayer
//    - No URL     → placeholder
//

import SwiftUI
import UIKit

struct ExerciseDetailView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.openURL) private var openURL

    let exercise: Exercise

    var body: some View {
        ZStack {
            ThemedBackdrop()
            ScrollView {
                VStack(spacing: 14) {
                    videoArea
                    metaCard
                    Spacer(minLength: 60)
                }
                .padding(16)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Video

    @ViewBuilder
    private var videoArea: some View {
        switch ExerciseVideoSource.classify(exercise.videoURL) {
        case .inline(let url):
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "exercises.detail.videoCaption"))
                    .font(theme.font.captionMedium)
                    .tracking(1.2)
                    .foregroundStyle(theme.textTertiary)
                ExerciseVideoPlayer(url: url)
            }
        case .external(let url):
            externalVideoCard(url: url)
        case .none:
            noVideoCard
        }
    }

    private func externalVideoCard(url: URL) -> some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: theme.radii.card, style: .continuous)
                    .fill(LinearGradient(
                        colors: [theme.accent.opacity(0.5), .black.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                VStack(spacing: 10) {
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(.white)
                    Text(String(localized: "exercises.detail.videoCaption"))
                        .font(theme.font.captionMedium)
                        .foregroundStyle(.white.opacity(0.85))
                        .tracking(1.2)
                }
            }
            .frame(height: 180)

            Button {
                openURL(url)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.right.square.fill")
                    Text(String(localized: "exercises.detail.openYouTube"))
                }
                .font(theme.font.bodyMedium)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(theme.accent, in: Capsule())
            }
            .accessibilityLabel(Text(String(localized: "exercises.detail.openYouTube")))
        }
    }

    private var noVideoCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: theme.radii.card, style: .continuous)
                .fill(theme.surfaceSecondary)
            VStack(spacing: 8) {
                Image(systemName: "film")
                    .font(.system(size: 36))
                    .foregroundStyle(theme.textTertiary)
                Text(String(localized: "exercises.detail.noVideo"))
                    .font(theme.font.body)
                    .foregroundStyle(theme.textTertiary)
            }
        }
        .frame(height: 160)
    }

    // MARK: - Meta

    private var metaCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            row(String(localized: "exercises.detail.primaryMuscle"),
                value: exercise.primaryMuscle.label)
            if !exercise.secondaryMuscles.isEmpty {
                row(String(localized: "exercises.detail.secondaryMuscles"),
                    value: exercise.secondaryMuscles.map(\.label).joined(separator: ", "))
            }
            row(String(localized: "exercises.detail.equipment"),
                value: exercise.equipment.label)
            row(String(localized: "exercises.detail.difficulty"),
                value: exercise.difficulty.label)
        }
        .padding(16)
        .themedCard()
    }

    private func row(_ label: String, value: String) -> some View {
        HStack {
            Text(label).font(theme.font.body).foregroundStyle(theme.textSecondary)
            Spacer()
            Text(value).font(theme.font.bodyMedium).foregroundStyle(theme.textPrimary)
        }
    }
}

#Preview("ExerciseDetail (YouTube) — Liquid Glass") {
    NavigationStack {
        ExerciseDetailView(exercise: Exercise(
            id: UUID(),
            name: "Press de banca",
            primaryMuscle: .chest,
            secondaryMuscles: [.shoulders, .arms],
            equipment: .barbell,
            difficulty: .intermediate,
            videoURL: URL(string: "https://www.youtube.com/watch?v=abc")
        ))
        .environment(\.appTheme, LiquidGlassTheme())
        .preferredColorScheme(.dark)
    }
}

#Preview("ExerciseDetail (No Video) — Health Cards") {
    NavigationStack {
        ExerciseDetailView(exercise: Exercise(
            id: UUID(),
            name: "Plancha",
            primaryMuscle: .core,
            secondaryMuscles: [.shoulders],
            equipment: .bodyweight,
            difficulty: .beginner,
            videoURL: nil
        ))
        .environment(\.appTheme, HealthCardsTheme())
        .preferredColorScheme(.light)
    }
}
