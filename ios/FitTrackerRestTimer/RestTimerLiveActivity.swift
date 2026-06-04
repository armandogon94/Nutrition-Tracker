//
//  RestTimerLiveActivity.swift
//  Slice 7.5: the rest-timer Live Activity UI rendered by the
//  FitTrackerRestTimer widget extension on the Lock Screen and in the
//  Dynamic Island.
//
//  This target is intentionally SELF-CONTAINED: it shares only
//  `RestTimerAttributes` with the app and otherwise uses plain SwiftUI +
//  system styling (it cannot see the app's AppTheme). The countdown is
//  rendered with SwiftUI's `Text(timerInterval:)` /
//  `ProgressView(timerInterval:)`, which the system animates on its OWN
//  clock — no app process runs while the phone is locked (ADR-0006 §4).
//

import WidgetKit
import SwiftUI
import ActivityKit

// Brand accent kept local so the extension has no app-target dependency.
private let kAccent = Color(red: 0.0, green: 0.78, blue: 0.66)

struct RestTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestTimerAttributes.self) { context in
            // Lock Screen / banner presentation.
            LockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.25))
                .activitySystemActionForegroundColor(kAccent)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded presentation.
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(context.attributes.exerciseName)
                            .font(.caption)
                            .lineLimit(1)
                    } icon: {
                        Image(systemName: "dumbbell.fill").foregroundStyle(kAccent)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: context.state.interval, countsDown: true)
                        .font(.system(.title2, design: .rounded).monospacedDigit())
                        .foregroundStyle(kAccent)
                        .frame(maxWidth: 64)
                        .multilineTextAlignment(.trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(timerInterval: context.state.interval, countsDown: true) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    }
                    .tint(kAccent)
                    .labelsHidden()
                }
            } compactLeading: {
                Image(systemName: "timer").foregroundStyle(kAccent)
            } compactTrailing: {
                Text(timerInterval: context.state.interval, countsDown: true)
                    .font(.system(.caption, design: .rounded).monospacedDigit())
                    .foregroundStyle(kAccent)
                    .frame(maxWidth: 44)
                    .multilineTextAlignment(.trailing)
            } minimal: {
                Image(systemName: "timer").foregroundStyle(kAccent)
            }
            .keylineTint(kAccent)
        }
    }
}

// MARK: - Lock Screen

private struct LockScreenView: View {
    let context: ActivityViewContext<RestTimerAttributes>

    var body: some View {
        HStack(spacing: 16) {
            // Circular countdown ring with the remaining time inside.
            ZStack {
                ProgressView(timerInterval: context.state.interval, countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    Text(timerInterval: context.state.interval, countsDown: true)
                        .font(.system(.headline, design: .rounded).monospacedDigit())
                        .multilineTextAlignment(.center)
                }
                .progressViewStyle(.circular)
                .tint(kAccent)
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 2) {
                Text("DESCANSO")
                    .font(.caption2.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                Text(context.attributes.exerciseName)
                    .font(.headline)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "dumbbell.fill")
                .font(.title3)
                .foregroundStyle(kAccent)
        }
        .padding()
    }
}
