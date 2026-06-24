//
//  HapticsService.swift
//  Slice 7.6: haptic feedback for the workout logger.
//
//  Design (source-driven-development):
//    - The three semantic calls the slice needs map cleanly onto UIKit's
//      feedback generators, which are the Apple-recommended path for
//      discrete UI feedback and Just Work on every supported device:
//        medium()    -> UIImpactFeedbackGenerator(.medium)   (set complete)
//        success()   -> UINotificationFeedbackGenerator .success (PR!)
//        lightTick() -> UIImpactFeedbackGenerator(.light)    (timer zero tick)
//    - For the rest-timer completion we ALSO play a short custom CoreHaptics
//      pattern (two ascending transients) for a more "alarm-like" feel when
//      the engine is available; we fall back to the notification generator
//      otherwise. CoreHaptics requires a real Taptic Engine, so on the
//      Simulator the engine simply never starts and we use the fallback.
//
//  Concurrency: @MainActor — UIFeedbackGenerator must be used from the main
//  thread, and CHHapticEngine setup is cheap and one-shot.
//
//  iOS vibration alone is unreliable for "your rest is over" (silent mode,
//  pocket), so RestTimerController always pairs this with an audible beep
//  (Core/Audio/TimerBeep) and a local notification (ADR-0006 §3).
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif
import CoreHaptics

@MainActor
final class HapticsService {

    static let shared = HapticsService()

    private var engine: CHHapticEngine?
    private let supportsHaptics: Bool

    init() {
        supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
        prepareEngine()
    }

    // MARK: - Semantic feedback

    /// Medium impact — used when a set is logged.
    func medium() {
        #if canImport(UIKit)
        let gen = UIImpactFeedbackGenerator(style: .medium)
        gen.prepare()
        gen.impactOccurred()
        #endif
    }

    /// Success notification — used when a new PR is set.
    func success() {
        #if canImport(UIKit)
        let gen = UINotificationFeedbackGenerator()
        gen.prepare()
        gen.notificationOccurred(.success)
        #endif
    }

    /// Light tick — used as the timer crosses zero, alongside the beep.
    func lightTick() {
        #if canImport(UIKit)
        let gen = UIImpactFeedbackGenerator(style: .light)
        gen.prepare()
        gen.impactOccurred()
        #endif
    }

    /// Rest-timer completion: a stronger, alarm-like double buzz. Uses a
    /// custom CoreHaptics pattern when the engine is live; otherwise falls
    /// back to the success notification so the user still feels something.
    func restComplete() {
        guard supportsHaptics, let engine else {
            success()
            return
        }
        do {
            let events = [
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
                    ],
                    relativeTime: 0
                ),
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.9)
                    ],
                    relativeTime: 0.18
                )
            ]
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try engine.start()
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            // Engine hiccup — fall back to the simple notification haptic.
            success()
        }
    }

    // MARK: - Engine lifecycle

    private func prepareEngine() {
        guard supportsHaptics else { return }
        do {
            let engine = try CHHapticEngine()
            // Restart transparently if the engine is reset/stopped by the OS.
            engine.resetHandler = { [weak engine] in
                try? engine?.start()
            }
            engine.stoppedHandler = { _ in }
            try engine.start()
            self.engine = engine
        } catch {
            // No engine — semantic calls fall back to UIKit generators.
            self.engine = nil
        }
    }
}
