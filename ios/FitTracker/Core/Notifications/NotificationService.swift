//
//  NotificationService.swift
//  Slice 7.7: local "rest is over" notification.
//
//  Design (source-driven-development + security-and-hardening):
//    - Authorization is requested at the point of use — the first time a
//      workout starts — NOT at app launch (Apple HIG, SPEC §15). We request
//      [.alert, .sound] only.
//    - The notification is scheduled the instant the rest timer starts,
//      with `UNTimeIntervalNotificationTrigger(timeInterval: duration)`, so
//      it fires even if the app is suspended or force-quit (ADR-0006 §3).
//      We do NOT fire it from a tick — a backgrounded app can't tick.
//    - A stable request identifier (`RestTimer`) lets us cancel the pending
//      notification on Skip / Set Complete so a stale alert never arrives
//      for an abandoned rest.
//
//  Testing strategy: UNUserNotificationCenter is a system singleton we
//  can't drive headlessly, so the pure request builder
//  (`makeRestCompleteRequest`) is extracted and unit-tested for its
//  identifier, trigger interval, and content; the thin add/remove glue is
//  verified on a real device per the manual QA checklist.
//

import Foundation
import UserNotifications

@MainActor
final class NotificationService {

    static let shared = NotificationService()

    /// Stable id so we can cancel/replace the single in-flight rest timer
    /// notification. We only ever have one rest timer at a time.
    /// `nonisolated` so the pure request builder can reference it.
    nonisolated static let restTimerRequestID = "rest-timer-complete"

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    // MARK: - Authorization

    /// Request alert + sound authorization. Safe to call repeatedly — the
    /// system no-ops once the user has decided. Returns whether we're
    /// authorized; callers fall back to in-app haptic/sound on denial.
    @discardableResult
    func requestAuthorizationIfNeeded() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    // MARK: - Scheduling

    /// Schedule the "rest is over" notification `duration` seconds from now.
    /// Replaces any existing pending rest notification (same identifier).
    func scheduleRestComplete(after duration: TimeInterval, exerciseName: String) {
        guard duration > 0 else { return }
        let request = Self.makeRestCompleteRequest(after: duration, exerciseName: exerciseName)
        cancelRestComplete() // replace any in-flight one
        center.add(request)
    }

    /// Cancel a pending rest-timer notification (Skip / Set Complete).
    func cancelRestComplete() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.restTimerRequestID])
    }

    // MARK: - Pure builder (testable)

    /// Builds the `UNNotificationRequest` for the rest-over alert. Pure so
    /// tests can assert the trigger interval, repeat flag, identifier, and
    /// localized content without touching the notification center.
    nonisolated static func makeRestCompleteRequest(
        after duration: TimeInterval, exerciseName: String
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "workout.restOver.title")
        // Body names the next exercise when we have it.
        if exerciseName.isEmpty {
            content.body = String(localized: "workout.restOver.body")
        } else {
            content.body = String(localized: "workout.restOver.bodyNamed")
                .replacingOccurrences(of: "%@", with: exerciseName)
        }
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, duration), repeats: false
        )
        return UNNotificationRequest(
            identifier: restTimerRequestID, content: content, trigger: trigger
        )
    }
}
