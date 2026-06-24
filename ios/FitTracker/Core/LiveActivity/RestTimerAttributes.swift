//
//  RestTimerAttributes.swift
//  Slice 7.5: the ActivityKit attributes shared by the app target (which
//  starts/updates/ends the activity) and the widget extension (which
//  renders it on the Lock Screen + Dynamic Island).
//
//  Per ADR-0006 the content state carries `startedAt` + `endsAt` so the
//  system can interpolate the countdown ON ITS OWN CLOCK via
//  `Text(timerInterval:)` / `ProgressView(timerInterval:)` — the widget
//  never computes time itself and no app process is required while the
//  phone is locked.
//
//  This file is compiled into BOTH the FitTracker app target and the
//  FitTrackerRestTimer widget-extension target (see project.yml).
//

import Foundation
import ActivityKit

struct RestTimerAttributes: ActivityAttributes {
    /// Dynamic state pushed on start / +30s. `Codable & Hashable` per
    /// ActivityKit requirements.
    public struct ContentState: Codable, Hashable {
        /// When the current rest began.
        var startedAt: Date
        /// When the current rest will hit zero.
        var endsAt: Date

        /// Convenience range for SwiftUI's timer-interval initializers.
        var interval: ClosedRange<Date> { startedAt...endsAt }
    }

    /// Static data set once at start.
    var exerciseName: String
}
