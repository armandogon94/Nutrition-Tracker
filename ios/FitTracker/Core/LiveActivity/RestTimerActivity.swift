//
//  RestTimerActivity.swift
//  Slice 7.5: thin app-side wrapper around `Activity<RestTimerAttributes>`.
//  SessionView calls start / update / end; the widget extension renders.
//
//  Robustness:
//    - Guarded by `ActivityAuthorizationInfo().areActivitiesEnabled`, so if
//      the user disabled Live Activities (or we're on a build without the
//      widget extension wired) every call is a safe no-op.
//    - The content state carries only `startedAt` + `endsAt`; the system
//      animates the countdown itself (ADR-0006 §4), so we do NOT push
//      per-second updates — just start, optional +30s, and end.
//    - We only ever run ONE rest timer, so start/end operate over the
//      framework's own `Activity.activities` list rather than juggling a
//      stored non-Sendable reference (which Swift 6 won't let us send into
//      a Task). This also self-heals a stale activity left by a prior crash.
//
//  Real-device only: the Simulator does not render Live Activities
//  faithfully, so this path is exercised by the manual QA checklist, not
//  unit tests. The pure timing it relies on (RestTimer math) is unit-tested.
//

import Foundation
import ActivityKit

@MainActor
enum RestTimerActivity {

    /// Singleton-style facade so call sites read `RestTimerActivity.shared.start(...)`.
    static let shared = RestTimerActivity.Facade()

    struct Facade {
        /// Whether the system currently allows Live Activities.
        var isEnabled: Bool {
            ActivityAuthorizationInfo().areActivitiesEnabled
        }

        /// Begin a Live Activity for a rest period. Ends any existing rest
        /// activity first so we never stack them. No-op if disabled.
        func start(exerciseName: String, startedAt: Date, duration: TimeInterval) {
            guard isEnabled else { return }
            endAll() // never stack; also clears a crash-orphaned one

            let attributes = RestTimerAttributes(exerciseName: exerciseName)
            let state = RestTimerAttributes.ContentState(
                startedAt: startedAt,
                endsAt: startedAt.addingTimeInterval(duration)
            )
            let content = ActivityContent(
                state: state,
                staleDate: startedAt.addingTimeInterval(duration + 5)
            )
            do {
                _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
            } catch {
                // Requesting can fail (quota, disabled mid-flight) — stay
                // silent; the in-app timer + notification still alert.
            }
        }

        /// Push a new end date (e.g. after +30s). The system re-interpolates.
        func update(startedAt: Date, duration: TimeInterval) {
            let state = RestTimerAttributes.ContentState(
                startedAt: startedAt,
                endsAt: startedAt.addingTimeInterval(duration)
            )
            let content = ActivityContent(
                state: state,
                staleDate: startedAt.addingTimeInterval(duration + 5)
            )
            // Iterate the framework's list inside the MainActor task so no
            // non-Sendable Activity is captured/sent.
            Task { @MainActor in
                for activity in Activity<RestTimerAttributes>.activities {
                    await activity.update(content)
                }
            }
        }

        /// End the rest Live Activity immediately.
        func end() { endAll() }

        private func endAll() {
            Task { @MainActor in
                for activity in Activity<RestTimerAttributes>.activities {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
            }
        }
    }
}
