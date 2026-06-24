//
//  RestTimerTests.swift
//  Slice 7.4: the rest timer is timestamp-based so it survives
//  backgrounding (ADR-0006). The pure math and the controller state
//  machine are unit-tested here; the Live Activity / notification / audio
//  side effects are verified on a real device per the manual QA checklist.
//

import Foundation
import Testing
@testable import FitTracker

@Suite("RestTimer")
struct RestTimerTests {

    // MARK: - Pure remaining() math

    @Test("remaining computes from the start timestamp")
    func restTimer_computesRemainingFromTimestamp() {
        let started = Date().addingTimeInterval(-30) // started 30s ago
        let r = RestTimer.remaining(startedAt: started, duration: 90, now: Date())
        #expect(abs(r - 60) < 0.01)
    }

    @Test("remaining clamps at zero and never goes negative")
    func restTimer_clampsAtZero() {
        let started = Date().addingTimeInterval(-200) // long past the duration
        let r = RestTimer.remaining(startedAt: started, duration: 90, now: Date())
        #expect(r == 0)
    }

    @Test("remaining at the exact start equals the full duration")
    func restTimer_atStartIsFullDuration() {
        let now = Date()
        let r = RestTimer.remaining(startedAt: now, duration: 120, now: now)
        #expect(r == 120)
    }

    @Test("progress goes 0 -> 1 across the interval")
    func restTimer_progress() {
        let started = Date(timeIntervalSince1970: 1000)
        // Half-way through a 60s rest.
        let mid = Date(timeIntervalSince1970: 1030)
        let p = RestTimer.progress(startedAt: started, duration: 60, now: mid)
        #expect(abs(p - 0.5) < 0.01)
        // Before start clamps to 0, after end clamps to 1.
        #expect(RestTimer.progress(startedAt: started, duration: 60, now: started) == 0)
        #expect(RestTimer.progress(startedAt: started, duration: 60,
                                   now: started.addingTimeInterval(120)) == 1)
    }

    @Test("isFinished reflects whether the fire date has passed")
    func restTimer_isFinished() {
        let started = Date().addingTimeInterval(-100)
        #expect(RestTimer.isFinished(startedAt: started, duration: 90, now: Date()))
        let fresh = Date()
        #expect(!RestTimer.isFinished(startedAt: fresh, duration: 90, now: fresh))
    }

    // MARK: - Controller state machine

    @MainActor
    @Test("start sets startedAt/duration and schedules effects exactly once")
    func controller_startSchedulesEffects() {
        let spy = SpyTimerEffects()
        let c = RestTimerController(effects: spy)

        #expect(!c.isRunning)
        c.start(duration: 90, exerciseName: "Press de banca")

        #expect(c.isRunning)
        #expect(c.duration == 90)
        #expect(c.exerciseName == "Press de banca")
        #expect(spy.scheduleCount == 1, "completion effects scheduled up front, once")
        #expect(spy.lastScheduledDuration == 90)
    }

    @MainActor
    @Test("remaining on the controller derives from its own startedAt")
    func controller_remainingDerivesFromStart() {
        let spy = SpyTimerEffects()
        let c = RestTimerController(effects: spy)
        c.start(duration: 60, exerciseName: "X")
        // Force a known start in the past to assert the computed remaining.
        c.startedAt = Date().addingTimeInterval(-15)
        #expect(abs(c.remaining - 45) < 0.5)
    }

    @MainActor
    @Test("skip stops the timer and cancels pending effects")
    func controller_skipCancels() {
        let spy = SpyTimerEffects()
        let c = RestTimerController(effects: spy)
        c.start(duration: 90, exerciseName: "X")
        c.skip()
        #expect(!c.isRunning)
        #expect(spy.cancelCount == 1)
    }

    @MainActor
    @Test("addTime extends duration and reschedules effects")
    func controller_addTimeReschedules() {
        let spy = SpyTimerEffects()
        let c = RestTimerController(effects: spy)
        c.start(duration: 60, exerciseName: "X")
        c.addTime(30)
        #expect(c.duration == 90)
        // One cancel + one reschedule on top of the initial schedule.
        #expect(spy.scheduleCount == 2)
        #expect(spy.cancelCount == 1)
        // Reschedule is relative to *now* using remaining time, so the new
        // fire date stays correct. Immediately after addTime, remaining is
        // ~90s (a few ms of test execution shaved off).
        let scheduled = spy.lastScheduledDuration ?? 0
        #expect(abs(scheduled - 90) < 1.0)
    }

    @MainActor
    @Test("completeIfElapsed fires the in-app alert once after the timer ends")
    func controller_completeIfElapsedFiresOnce() {
        let spy = SpyTimerEffects()
        let c = RestTimerController(effects: spy)
        c.start(duration: 60, exerciseName: "X")
        // Simulate the timer having elapsed while backgrounded.
        c.startedAt = Date().addingTimeInterval(-120)

        c.completeIfElapsed()
        #expect(spy.alertCount == 1, "in-app haptic+beep fires once on completion")
        #expect(!c.isRunning, "an elapsed timer transitions out of running")

        // Calling again must NOT double-alert (de-duplicated).
        c.completeIfElapsed()
        #expect(spy.alertCount == 1)
    }

    @MainActor
    @Test("completeIfElapsed does nothing while the timer is still running")
    func controller_completeIfElapsedNoopWhenRunning() {
        let spy = SpyTimerEffects()
        let c = RestTimerController(effects: spy)
        c.start(duration: 90, exerciseName: "X")
        c.completeIfElapsed()
        #expect(spy.alertCount == 0)
        #expect(c.isRunning)
    }
}

// MARK: - Spy

/// Records calls so we can assert the controller's effect orchestration
/// without touching CoreHaptics / AVAudio / UNUserNotificationCenter.
@MainActor
private final class SpyTimerEffects: RestTimerEffects {
    var scheduleCount = 0
    var cancelCount = 0
    var alertCount = 0
    var lastScheduledDuration: TimeInterval?

    func scheduleCompletion(after duration: TimeInterval, exerciseName: String) {
        scheduleCount += 1
        lastScheduledDuration = duration
    }
    func cancelScheduledCompletion() {
        cancelCount += 1
    }
    func fireCompletionAlert() {
        alertCount += 1
    }
}
