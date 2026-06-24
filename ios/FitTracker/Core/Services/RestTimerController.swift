//
//  RestTimerController.swift
//  Slice 7.4: timestamp-based rest timer (ADR-0006).
//
//  The timer NEVER decrements a counter. The single source of truth is
//  `startedAt` + `duration`; remaining time is always computed from the
//  wall clock, so the timer is correct after any amount of backgrounding.
//  The view redraws via `TimelineView(.animation)`; this controller only
//  holds state and orchestrates completion effects (haptic + beep +
//  notification + Live Activity), which are SCHEDULED up front at start.
//
//  Skills invoked:
//   - source-driven-development (UNUserNotificationCenter, ActivityKit)
//   - everything-claude-code:swift-concurrency-6-2 (@Observable + @MainActor)
//   - performance-optimization (no retained Timer -> no leak, no drift)
//   - test-driven-development (RestTimerTests, RED-first)
//

import Foundation
import Observation

// MARK: - Pure math

/// Pure, side-effect-free rest-timer math. Fully unit-tested; this is the
/// one thing every surface (app UI, Live Activity, notification) agrees on.
enum RestTimer {

    /// Seconds left, clamped to [0, duration]. A pure function of the wall
    /// clock — correct regardless of how long the app was suspended.
    static func remaining(startedAt: Date, duration: TimeInterval, now: Date = .now) -> TimeInterval {
        let elapsed = now.timeIntervalSince(startedAt)
        return min(duration, max(0, duration - elapsed))
    }

    /// Fractional progress 0...1 across the interval.
    static func progress(startedAt: Date, duration: TimeInterval, now: Date = .now) -> Double {
        guard duration > 0 else { return 1 }
        let elapsed = now.timeIntervalSince(startedAt)
        return min(1, max(0, elapsed / duration))
    }

    /// True once the fire date (`startedAt + duration`) has passed.
    static func isFinished(startedAt: Date, duration: TimeInterval, now: Date = .now) -> Bool {
        now.timeIntervalSince(startedAt) >= duration
    }

    /// The instant the timer will (or did) hit zero.
    static func fireDate(startedAt: Date, duration: TimeInterval) -> Date {
        startedAt.addingTimeInterval(duration)
    }
}

// MARK: - Effects seam

/// The completion side effects the controller orchestrates. Abstracted so
/// unit tests can inject a spy instead of CoreHaptics / AVAudio /
/// UNUserNotificationCenter / ActivityKit.
@MainActor
protocol RestTimerEffects: AnyObject {
    /// Schedule everything that must fire when the rest ends, keyed off
    /// `startedAt + duration`. Called at start and on `+30s`.
    func scheduleCompletion(after duration: TimeInterval, exerciseName: String)
    /// Cancel anything scheduled (Skip / Set Complete / reschedule).
    func cancelScheduledCompletion()
    /// Fire the immediate in-app alert (haptic + beep) when the timer ends
    /// while the app is foreground.
    func fireCompletionAlert()
}

// MARK: - Controller

@Observable
@MainActor
final class RestTimerController {

    /// Start instant of the current rest. Settable so tests can simulate
    /// elapsed time without sleeping.
    var startedAt: Date = .now
    /// Total rest seconds for the current set.
    private(set) var duration: TimeInterval = 0
    /// Name of the exercise the next set belongs to (for the alert + UI).
    private(set) var exerciseName: String = ""
    /// Whether a rest is currently in progress.
    private(set) var isRunning: Bool = false

    /// Guards against double-firing the in-app completion alert when both
    /// the TimelineView crossing and the scenePhase foreground path notice
    /// the timer has elapsed.
    private var didFireCompletion = false

    private let effects: any RestTimerEffects

    init(effects: any RestTimerEffects) {
        self.effects = effects
    }

    /// Convenience for production: wires the real haptic/audio/notification/
    /// Live-Activity effects.
    convenience init() {
        self.init(effects: DefaultRestTimerEffects())
    }

    // MARK: - Computed

    /// Seconds remaining right now.
    var remaining: TimeInterval {
        RestTimer.remaining(startedAt: startedAt, duration: duration)
    }

    /// Progress 0...1 right now.
    var progress: Double {
        RestTimer.progress(startedAt: startedAt, duration: duration)
    }

    /// The instant this rest hits zero.
    var fireDate: Date {
        RestTimer.fireDate(startedAt: startedAt, duration: duration)
    }

    // MARK: - State transitions

    /// Begin a rest. Captures the timestamp and schedules completion effects
    /// once, up front.
    func start(duration: TimeInterval, exerciseName: String) {
        self.startedAt = .now
        self.duration = duration
        self.exerciseName = exerciseName
        self.isRunning = true
        self.didFireCompletion = false
        effects.scheduleCompletion(after: duration, exerciseName: exerciseName)
    }

    /// User skipped the rest. Stop and cancel pending effects.
    func skip() {
        guard isRunning else { return }
        isRunning = false
        effects.cancelScheduledCompletion()
    }

    /// Add time mid-rest (e.g. +30s). Extends the duration in place (keeping
    /// the same start) and reschedules the completion effects so the
    /// notification + Live Activity stay in lockstep.
    func addTime(_ seconds: TimeInterval) {
        guard isRunning else { return }
        duration += seconds
        didFireCompletion = false
        effects.cancelScheduledCompletion()
        // Reschedule relative to NOW based on the new remaining time, so the
        // notification fires at the correct new fire date.
        effects.scheduleCompletion(after: remaining, exerciseName: exerciseName)
    }

    /// Called from the UI tick and on foreground. If the timer has elapsed
    /// and we haven't already alerted, fire the in-app alert exactly once
    /// and transition out of running.
    func completeIfElapsed() {
        guard isRunning, !didFireCompletion else { return }
        guard RestTimer.isFinished(startedAt: startedAt, duration: duration) else { return }
        didFireCompletion = true
        isRunning = false
        effects.fireCompletionAlert()
    }
}

// MARK: - Default effects (production)

/// Real completion effects: schedules the local notification at start,
/// cancels it on skip/reschedule, and fires haptic + beep + (optionally)
/// updates the Live Activity in-app when the timer ends. The Live Activity
/// start/update/end is owned by RestTimerActivity and driven from
/// SessionView, so this type keeps to the notification + immediate
/// alert responsibilities.
@MainActor
final class DefaultRestTimerEffects: RestTimerEffects {

    func scheduleCompletion(after duration: TimeInterval, exerciseName: String) {
        NotificationService.shared.scheduleRestComplete(after: duration, exerciseName: exerciseName)
    }

    func cancelScheduledCompletion() {
        NotificationService.shared.cancelRestComplete()
    }

    func fireCompletionAlert() {
        HapticsService.shared.restComplete()
        TimerBeep.shared.playRestComplete()
    }
}
