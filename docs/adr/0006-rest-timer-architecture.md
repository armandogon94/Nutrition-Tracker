# ADR-0006: Rest Timer Architecture (timestamp-based, background-safe)

- **Status:** Accepted
- **Date:** 2026-06-04
- **Slice:** 7 (Workout Session + Rest Timer + Live Activity + HealthKit write)
- **Supersedes / relates to:** ADR-0004 (SwiftData schema), ADR-0001 (three-client architecture)

## Context

The active-workout rest timer must keep accurate time while the app is
backgrounded, the screen is locked, or the app is force-quit. iOS gives a
backgrounded app essentially no CPU: a foreground `Timer.scheduledTimer`
stops firing the instant the app is suspended, and `Task.sleep` loops are
likewise frozen. A naïve "decrement a counter every second" timer drifts
badly (or stops entirely) the moment the user locks the phone between
sets — which is exactly when a lifter is resting and looking at the Lock
Screen, not the app.

We have three surfaces that must agree on "how much rest is left":

1. The in-app `RestTimerView` (progress ring + numeric readout).
2. The Lock Screen / Dynamic Island Live Activity.
3. The local notification that fires at zero (even if the app is dead).

If each surface ran its own ticking clock they would diverge. We need one
source of truth that all three derive from without any of them needing to
"run" while suspended.

## Decision

### 1. Timestamp math, never a live countdown variable

The single source of truth is a pair of values captured the instant the
timer starts:

```
startedAt : Date          // wall-clock instant the rest began
duration  : TimeInterval  // total rest seconds for this set
```

Remaining time is *always computed*, never stored or decremented:

```
remaining(at now: Date) = max(0, duration - now.timeIntervalSince(startedAt))
```

`RestTimer.remaining(startedAt:duration:now:)` is a pure, static, fully
unit-tested function. Because it is a pure function of wall-clock time, it
is correct after any amount of backgrounding: when the app foregrounds we
re-read `Date.now` and recompute — there is no accumulated drift to
correct because nothing was counting.

### 2. `TimelineView(.animation)` drives the redraw, not a Timer

The ring and the digits are redrawn by SwiftUI's `TimelineView(.animation)`
(or `.periodic`), which only fires while the view is actually on screen and
the app is foreground. Each tick calls the same pure `remaining(...)`
function. We never schedule our own repeating `Timer`. This means:

- No retained timer to leak.
- No background ticks attempted (and throttled / dropped by the OS).
- Redraw cost is bounded to visible-and-foreground frames.

### 3. Completion side effects are scheduled up front, at start

The haptic + audio beep + local notification are **scheduled at the instant
the timer starts**, keyed off `startedAt + duration`, NOT fired from a tick:

- The **local notification** uses
  `UNTimeIntervalNotificationTrigger(timeInterval: duration)`. The system
  delivers it even if the app is suspended or force-quit. This is the only
  reliable "your rest is over" signal when the phone is in a pocket.
- The **in-app haptic + beep** fire from a foreground completion check
  (`scenePhase` / TimelineView crossing zero) *and* are de-duplicated so we
  never double-alert when both the notification and the in-app path land.
- On manual **Skip** or **Set Complete -> next set**, the pending
  notification is cancelled by its stable request identifier so a stale
  "rest over" alert never arrives for an abandoned rest.

### 4. Live Activity reads the same two values

The ActivityKit Live Activity content state carries `startedAt` and an
end-`Date`, and renders with SwiftUI's native `Text(timerInterval:)` /
`ProgressView(timerInterval:)`, which the system animates **on its own
clock** on the Lock Screen and in the Dynamic Island — no app process
required. The app's only jobs are `start`, optional `update` (e.g. +30 s),
and `end`. The widget extension never computes time itself; it interpolates
between the two endpoints the system already knows.

### 5. `scenePhase` observer recomputes on foreground

`SessionView` observes `@Environment(\.scenePhase)`. On the
`.background -> .active` transition it forces a recompute (and, if the
timer already elapsed while away, runs the de-duplicated completion path
so the UI catches up). Nothing is "resumed" because nothing was paused —
we simply re-read the clock.

## Consequences

**Positive**

- Zero drift by construction: remaining time is a pure function of
  wall-clock time, independent of how long the app was suspended.
- Survives lock, background, and force-quit (notification still fires).
- One source of truth (`startedAt` + `duration`) shared by app UI, Live
  Activity, and notification — they cannot disagree.
- The core math is trivially unit-testable without any timer, simulator
  clock, or async waiting (see `RestTimerTests`).
- No retained `Timer`, so no leak and no zombie ticks.

**Negative / trade-offs**

- The Live Activity and the on-device notification can only be verified on
  a **real device** — the Simulator does not render Live Activities
  faithfully and notification delivery under suspension differs. Unit tests
  cover the pure math and the controller state machine; the OS-integration
  surfaces are covered by a documented manual QA checklist (see
  `plans/slice-07-workout-session.md` "Verification before merge").
- `+30 s` mid-rest must update three things in lockstep (controller
  `duration`, the rescheduled notification, the Live Activity content
  state). The controller centralizes this so callers issue a single
  `addTime(30)` and all three stay consistent.

## Alternatives considered

- **`Timer.scheduledTimer` + background-decremented counter** — rejected:
  stops firing when suspended; the headline failure mode we must avoid.
- **`BGProcessingTask` / background execution to keep ticking** — rejected:
  the OS does not guarantee wakeups at second granularity; wrong tool for a
  sub-2-minute foreground-ish timer, and wasteful.
- **Audio keep-alive (silent background audio) to keep the app running** —
  rejected: abuses the background-audio entitlement, hurts battery, and is
  App-Store-risky for a use case the notification API already solves.
