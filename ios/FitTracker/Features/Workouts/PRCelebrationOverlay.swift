//
//  PRCelebrationOverlay.swift
//  Slice 7.8: the personal-record celebration. A brief full-screen overlay
//  with a confetti burst (SwiftUI Canvas particle sim) + the new record.
//  The haptic `.success` and sound sting are fired by SessionView when the
//  PR is detected; this view is purely visual and auto-dismisses.
//
//  Skills: everything-claude-code:swiftui-patterns,
//  everything-claude-code:liquid-glass-design.
//

import SwiftUI

struct PRCelebrationOverlay: View {
    @Environment(\.appTheme) private var theme

    let record: PersonalRecord
    var onDismiss: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            // Dim the logger behind the celebration; tap to dismiss early.
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            ConfettiView()
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 14) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(theme.accent)
                    .symbolEffect(.bounce, value: appeared)

                Text(String(localized: "workout.pr.title"))
                    .font(theme.font.largeTitle)
                    .foregroundStyle(theme.textPrimary)

                Text(localizedSubtitle)
                    .font(theme.font.bodyMedium)
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)

                Text("\(record.weightKg, specifier: "%.1f") kg × \(record.reps)")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(theme.accent)
                    .padding(.top, 2)
            }
            .padding(28)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radii.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: theme.radii.card, style: .continuous)
                    .stroke(theme.accent.opacity(0.4), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
            .scaleEffect(appeared ? 1 : 0.85)
            .opacity(appeared ? 1 : 0)
            .padding(40)
        }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { appeared = true }
            // Auto-dismiss after a beat so it never blocks the next set.
            Task {
                try? await Task.sleep(nanoseconds: 2_600_000_000)
                onDismiss()
            }
        }
        // Trap VoiceOver inside the celebration (review Flash D3): without
        // `.isModal` a swipe could move focus to the active session underneath
        // while the overlay is still up.
        .accessibilityAddTraits(.isModal)
    }

    private var localizedSubtitle: String {
        String(localized: "workout.pr.subtitle")
            .replacingOccurrences(of: "%@", with: record.exerciseName)
    }
}

// MARK: - Confetti

/// A lightweight confetti burst rendered with a single `Canvas` +
/// `TimelineView`, so it costs one redraw pass per frame (no per-particle
/// views). Particles fall under gravity with a little horizontal drift and
/// spin, fading near the end.
private struct ConfettiView: View {
    private let particles: [Particle]
    private let start = Date()
    private let duration: TimeInterval = 2.6

    init(count: Int = 120) {
        var rng = SystemRandomNumberGenerator()
        particles = (0..<count).map { _ in Particle(rng: &rng) }
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSince(start)
                guard t < duration else { return }
                for p in particles {
                    draw(p, at: t, in: size, ctx: &ctx)
                }
            }
        }
    }

    private func draw(_ p: Particle, at t: TimeInterval, in size: CGSize, ctx: inout GraphicsContext) {
        let progress = t / duration
        // Position: launched from the top, gravity pulls down, drift sideways.
        let gravity = 900.0
        let x = p.originX * size.width + p.driftX * t * 60
        let y = (p.originY * -0.2 * size.height) + p.velocityY * t + 0.5 * gravity * t * t
        guard y < size.height + 40 else { return }

        let angle = Angle.degrees(p.spin * t * 360)
        let fade = progress > 0.7 ? max(0, 1 - (progress - 0.7) / 0.3) : 1

        // Draw each confetto in its own translated/rotated context so we
        // pay no per-particle view cost — just one Canvas pass.
        var inner = ctx
        inner.translateBy(x: x, y: y)
        inner.rotate(by: angle)
        inner.opacity = fade
        inner.fill(
            Path(roundedRect: CGRect(x: -p.size / 2, y: -p.size / 4,
                                     width: p.size, height: p.size * 0.5),
                 cornerRadius: 1.5),
            with: .color(p.color)
        )
    }

    struct Particle {
        let originX: Double      // 0...1 fraction of width
        let originY: Double      // start band near top
        let driftX: Double
        let velocityY: Double
        let size: CGFloat
        let spin: Double
        let color: Color

        init(rng: inout SystemRandomNumberGenerator) {
            originX = Double.random(in: 0...1, using: &rng)
            originY = Double.random(in: 0...0.1, using: &rng)
            driftX = Double.random(in: -1.2...1.2, using: &rng)
            velocityY = Double.random(in: 40...160, using: &rng)
            size = CGFloat.random(in: 6...12, using: &rng)
            spin = Double.random(in: -1.5...1.5, using: &rng)
            let palette: [Color] = [.yellow, .orange, .pink, .green, .blue, .purple, .red]
            color = palette.randomElement(using: &rng) ?? .yellow
        }
    }
}

#Preview("PR Celebration — Liquid Glass") {
    ZStack {
        LiquidGlassTheme().background.ignoresSafeArea()
        PRCelebrationOverlay(
            record: PersonalRecord(id: UUID(), exerciseId: UUID(),
                                   exerciseName: "Press de banca",
                                   weightKg: 100, reps: 5, achievedAt: .now),
            onDismiss: {}
        )
        .environment(\.appTheme, LiquidGlassTheme())
    }
    .preferredColorScheme(.dark)
}
