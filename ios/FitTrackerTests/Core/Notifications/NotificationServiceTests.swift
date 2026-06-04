//
//  NotificationServiceTests.swift
//  Slice 7.7: the rest-complete notification is built by a pure function so
//  we can assert its trigger interval, identifier, and content without
//  driving UNUserNotificationCenter (verified on device).
//

import Foundation
import UserNotifications
import Testing
@testable import FitTracker

@Suite("NotificationService")
struct NotificationServiceTests {

    @Test("rest-complete request uses a non-repeating time-interval trigger")
    func request_usesTimeIntervalTrigger() {
        let req = NotificationService.makeRestCompleteRequest(after: 90, exerciseName: "Press de banca")
        let trigger = req.trigger as? UNTimeIntervalNotificationTrigger
        #expect(trigger != nil)
        #expect(trigger?.timeInterval == 90)
        #expect(trigger?.repeats == false)
    }

    @Test("rest-complete request uses the stable cancellable identifier")
    func request_usesStableIdentifier() {
        let req = NotificationService.makeRestCompleteRequest(after: 60, exerciseName: "X")
        #expect(req.identifier == NotificationService.restTimerRequestID)
    }

    @Test("interval is clamped to at least 1 second")
    func request_clampsTinyInterval() {
        let req = NotificationService.makeRestCompleteRequest(after: 0, exerciseName: "X")
        let trigger = req.trigger as? UNTimeIntervalNotificationTrigger
        #expect((trigger?.timeInterval ?? 0) >= 1)
    }

    @Test("content carries a title, body, and time-sensitive interruption")
    func request_hasContent() {
        let req = NotificationService.makeRestCompleteRequest(after: 30, exerciseName: "Sentadilla")
        #expect(!req.content.title.isEmpty)
        #expect(!req.content.body.isEmpty)
        #expect(req.content.interruptionLevel == .timeSensitive)
        // Named body should include the exercise name.
        #expect(req.content.body.contains("Sentadilla"))
    }
}
