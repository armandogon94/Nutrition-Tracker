//
//  RestTimerView.swift
//  Slice 7.4: the rest-timer sheet. Timestamp-based per ADR-0006 — it does
//  NOT decrement a counter. A `TimelineView(.animation)` redraws the ring +
//  digits while on screen; every frame reads the pure
//  `RestTimerController.remaining/progress`, which are computed from
//  `startedAt`, so the display is always correct (even right after the app
//  returns from the background).
//
//  Completion effects (haptic + beep + notification) are owned by the
//  controller, scheduled up front at start. This view just renders and
//  offers Skip / +30s.
//

import SwiftUI

struct RestTimerView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    /// Shared controller — owned by SessionView so the timer state survives
    /// the sheet being recomposed and stays consistent with the Live
    /// Activity.
    let controller: RestTimerController
    /// Called when the timer reaches zero (auto-dismiss + advance).
    var onFinished: () -> Void = {}
    /// Called when the user taps Skip.
    var onSkip: () -> Void = {}
    /// Called after +30s so the caller can keep the Live Activity in sync.
    var onAddTime: () -> Void = {}

    var body: some View {
        ZStack {
            ThemedBackdrop()
            // TimelineView drives ~60fps redraws while visible; no Timer.
            TimelineView(.animation) { _ in
                content
            }
        }
    }

    private var content: some View {
        let remaining = controller.remaining
        let progress = controller.progress

        return VStack(spacing: 30) {
            VStack(spacing: 6) {
                Text(String(localized: "workout.rest"))
                    .font(theme.font.titleCompact)
                    .foregroundStyle(theme.textTertiary)
                    .tracking(1.4)
                if !controller.exerciseName.isEmpty {
                    Text(controller.exerciseName)
                        .font(theme.font.body)
                        .foregroundStyle(theme.textSecondary)
                }
            }

            ZStack {
                Circle()
                    .stroke(theme.accent.opacity(0.2), lineWidth: 14)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(theme.accent, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.2), value: progress)
                Text(Self.format(remaining))
                    .font(.system(size: 72, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(theme.textPrimary)
                    .contentTransition(.numericText())
            }
            .frame(width: 220, height: 220)

            HStack(spacing: 16) {
                Button {
                    controller.skip()
                    onSkip()
                    dismiss()
                } label: {
                    Text(String(localized: "workout.skip"))
                        .font(theme.font.bodyMedium)
                        .foregroundStyle(theme.negative)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Capsule().stroke(theme.negative.opacity(0.5), lineWidth: 1))
                }
                Button {
                    controller.addTime(30)
                    onAddTime()
                } label: {
                    Text(String(localized: "workout.addThirty"))
                        .font(theme.font.bodyMedium)
                        .foregroundStyle(theme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Capsule().stroke(theme.accent.opacity(0.5), lineWidth: 1))
                }
            }
            .padding(.horizontal, 8)
        }
        .padding(40)
        .onChange(of: remainingTick(remaining)) { _, _ in
            // When the computed remaining reaches zero, run the controller's
            // de-duplicated completion path and dismiss.
            if controller.isRunning && remaining <= 0 {
                controller.completeIfElapsed()
                onFinished()
                dismiss()
            }
        }
    }

    /// Bucket remaining into whole seconds so `onChange` only fires on a
    /// second boundary, not every animation frame.
    private func remainingTick(_ remaining: TimeInterval) -> Int {
        Int(remaining.rounded(.up))
    }

    /// mm:ss for >= 60s, otherwise a bare seconds count.
    static func format(_ remaining: TimeInterval) -> String {
        let total = Int(remaining.rounded(.up))
        if total >= 60 {
            return String(format: "%d:%02d", total / 60, total % 60)
        }
        return "\(total)"
    }
}

#Preview("RestTimer — Liquid Glass") {
    RestTimerView(controller: {
        let c = RestTimerController(effects: PreviewTimerEffects())
        c.start(duration: 90, exerciseName: "Press de banca")
        return c
    }())
    .environment(\.appTheme, LiquidGlassTheme())
    .preferredColorScheme(.dark)
}

/// No-op effects so previews don't touch haptics/audio/notifications.
@MainActor
private final class PreviewTimerEffects: RestTimerEffects {
    func scheduleCompletion(after duration: TimeInterval, exerciseName: String) {}
    func cancelScheduledCompletion() {}
    func fireCompletionAlert() {}
}
