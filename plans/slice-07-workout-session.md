# Slice 7 — Workout Session + Rest Timer (Live Activity + HealthKit Write)

**Branch:** `slice/07-workout-session`
**Estimate:** 22h realistic (14h optimistic, 30h if ActivityKit or HealthKit write edge cases appear)
**Owner:** Opus subagent during Phase D (concurrent with Slice 4)

---

## Dependencies

- **Slice 6 merged** (programs + exercises available)
- **Slice 2 merged** (SwiftData schema has `WorkoutSession`, `WorkoutSet`, `PersonalRecord`)

## Parallelizable peers

- **Slice 4** (meal plan) — zero overlap, runs concurrently in main worktree
- **Slice 9 Phase C** (rate limits) — backend worktree

## Objective

Deliver the real-time workout logging experience: user picks a program day → logs sets with weight and reps → rest timer counts down between sets (surviving app backgrounding via Live Activity + Dynamic Island) → PRs detected and celebrated → workout completes and writes to HealthKit.

This is the single most feature-heavy slice and the biggest iOS-native flex.

## Acceptance criteria

- [ ] "Start workout" from ProgramDetailView creates session on backend + SwiftData, navigates to `SessionView`
- [ ] Set logger: weight (kg) + reps inputs; "Set complete" advances to next set and starts rest timer
- [ ] Rest timer runs via timestamp-based calc; survives backgrounding; accurate when returning from background
- [ ] Live Activity shows timer on Lock Screen; Dynamic Island shows compact countdown
- [ ] Timer completion: haptic + sound beep (AVAudioPlayer) + local notification
- [ ] PR detected and badged on-screen when user lifts heavier than previous max for that exercise
- [ ] "End workout" → session marked complete → HealthKit workout sample written
- [ ] Haptics work: medium on set complete, success on PR, light on timer zero
- [ ] All 15 new Swift tests pass (including a timer-backgrounding simulation)
- [ ] Works on real device (required — Simulator limited for Live Activity)

## Skills to invoke

1. `source-driven-development` — ActivityKit (Live Activity, Dynamic Island), CoreHaptics, UNUserNotificationCenter, AVAudioPlayer, HealthKit workout API. Every one of these needs doc-grounded implementation; use Context7 MCP for current Apple docs.
2. `security-and-hardening` — notification permissions, HealthKit authorization at point-of-use
3. `everything-claude-code:healthcare-phi-compliance` — HealthKit workout write rules
4. `api-and-interface-design` — `WorkoutService` protocol
5. `everything-claude-code:swift-concurrency-6-2` — timer state, background tasks
6. `test-driven-development`
7. `everything-claude-code:swiftui-patterns` — SessionView layout, timer ring
8. `performance-optimization` — timer must not leak or drift
9. `everything-claude-code:liquid-glass-design` + `ux-design:ios-hig-design`
10. `code-review-and-quality`
11. `documentation-and-adrs` — ADR-0005 on timer architecture

---

## Tasks

### Task 7.1 — ADR + `WorkoutService` protocol

**Skills:** `documentation-and-adrs`, `api-and-interface-design`

**Files:**
- `docs/adr/0005-timer-architecture.md` — decisions:
  - Timestamp-based countdown (not `Timer.scheduledTimer`) so backgrounding stays accurate
  - Live Activity is the source of truth display; app UI just reads the same started-at + duration
  - Notifications scheduled at the instant timer starts (not at tick), so they fire even if app is killed
- `Core/Services/WorkoutService.swift` protocol + actor

**Est:** 1h

---

### Task 7.2 — `WorkoutService` CRUD for sessions + sets

**Skills:** `api-and-interface-design`, `everything-claude-code:swift-actor-persistence`, `test-driven-development`

**RED tests:**
```swift
@Test func startSession_createsBackendAndLocal() async throws { ... }
@Test func logSet_detectsPRWhenWeightAboveMax() async throws { ... }
@Test func completeSession_writesDurationAndFlushes() async throws { ... }
```

**Files:**
- `Core/Services/WorkoutService.swift` — `startSession`, `logSet`, `completeSession`, `currentSession() async -> WorkoutSession?`

**Est:** 2.5h

---

### Task 7.3 — `SessionView` — logger UI

**Skills:** `everything-claude-code:swiftui-patterns`, `ux-design:ios-hig-design`

**Files:**
- `Features/Workouts/SessionView.swift` — top: current exercise name + set N of M; middle: weight + reps input + "Set Complete" button; bottom: prior sets for this exercise; "End Workout" in toolbar
- `Features/Workouts/SetInputRow.swift` — numeric input with ± buttons and keyboard decimal pad

**Keyboard:** `.keyboardType(.decimalPad)` for both fields; `.submitLabel(.next)` to move between them.

**Est:** 3h

---

### Task 7.4 — `RestTimerView` (timestamp-based, backgrounding-safe)

**Skills:** `source-driven-development`, `everything-claude-code:swift-concurrency-6-2`, `performance-optimization`, `test-driven-development`

**RED tests:**
```swift
@Test func restTimer_computesRemainingFromTimestamp() {
    let started = Date().addingTimeInterval(-30)  // started 30s ago
    #expect(RestTimer.remaining(startedAt: started, duration: 90) == 60)
}
@Test func restTimer_clampsAtZero() { ... }
@Test func restTimer_resumingAfterBackgroundRecomputes() async throws {
    // Start timer → simulate 30s elapsed → assert UI shows correct remaining
}
```

**Files:**
- `Features/Workouts/RestTimerView.swift` — progress ring + big numeric readout + Skip button
- `Core/Services/RestTimerController.swift` — `@Observable`; holds `startedAt: Date`, `duration: TimeInterval`; exposes `remaining` as computed property; fires scheduled beep + haptic at zero
- `scenePhase` observer — on return to foreground, recalculates remaining from `startedAt` (no drift)

**Important:** NEVER use `Timer.scheduledTimer(withTimeInterval:)` — backgrounded timers don't fire. Use only timestamp math + a `TimelineView(.animation)` for UI redraw.

**Est:** 3h

---

### Task 7.5 — Live Activity + Dynamic Island

**Skills:** `source-driven-development` (ActivityKit docs, Context7 MCP), `everything-claude-code:swiftui-patterns`

**Files:**
- New Widget Extension target in `project.yml`: `FitTrackerRestTimer` with `ActivityConfiguration`
- `ios/FitTrackerRestTimer/RestTimerLiveActivity.swift` — `Widget` conforming to `Widget` protocol, registers ActivityAttributes
- `Core/LiveActivity/RestTimerActivity.swift` (in main target) — wrapper around `Activity<RestTimerAttributes>` — start/update/end

**Entitlement:** `com.apple.developer.activitykit` added to `project.yml`.

**Info.plist:** `NSSupportsLiveActivities = YES`.

**States:**
- Lock Screen: circular progress + remaining + exercise name + "Skip" button (deep link back to app)
- Dynamic Island compact: remaining seconds + ring
- Dynamic Island expanded: full timer + Skip / +30s buttons

**Acceptance (real device only):** Start workout → timer visible on Lock Screen; lock phone → timer still counts down accurately.

**Est:** 5h

---

### Task 7.6 — CoreHaptics engine + AVAudioPlayer beep

**Skills:** `source-driven-development`, `everything-claude-code:swift-concurrency-6-2`

**Files:**
- `Core/Haptics/HapticsService.swift` — manages `CHHapticEngine`, provides `medium()`, `success()`, `lightTick()` static calls
- `Core/Audio/TimerBeep.swift` — embed tiny 500ms WAV asset; play via `AVAudioPlayer`; respect `AVAudioSession.Category.ambient` (mix with music)

**Info.plist:** no new keys needed (no background audio playback for this).

**Acceptance:** Haptic + beep at timer zero even if muted? Keep beep tied to ringer switch (don't override silent mode).

**Est:** 2h

---

### Task 7.7 — Local notification scheduling

**Skills:** `source-driven-development`, `security-and-hardening`

**Files:**
- `Core/Notifications/NotificationService.swift` — request authorization on first workout start; schedule `UNNotificationRequest` at timer start with `UNTimeIntervalNotificationTrigger(timeInterval: duration)`
- Cancel on manual Skip / Set Complete

**Acceptance:** Kill the app mid-rest-timer → notification still fires at expected time.

**Est:** 1.5h

---

### Task 7.8 — PR detection + celebration

**Skills:** `everything-claude-code:swiftui-patterns`, `everything-claude-code:liquid-glass-design`

**Files:**
- `WorkoutService.logSet(...)` — compare weight+reps against `PersonalRecord` for this exercise. If new max weight OR max reps at current weight, update PR.
- `SessionView` — on PR, present a brief `.overlay` sheet with confetti-style (SwiftUI Canvas particle animation) + haptic `.success` + sound sting

**Est:** 2h

---

### Task 7.9 — HealthKit workout write

**Skills:** `source-driven-development`, `everything-claude-code:healthcare-phi-compliance`, `security-and-hardening`

**RED tests:**
```swift
@Test func healthKit_writesWorkoutWithCorrectDuration() async throws { ... }
@Test func healthKit_idempotentViaMetadataUUID() async throws { ... }
```

**Files:**
- `Core/Health/HealthKitService.swift` — add `writeWorkout(session: WorkoutSession, sets: [WorkoutSet])` method
- Uses `HKWorkoutBuilder` (deprecated in iOS 17+) or new `HKWorkout.init(...)` — verify current API
- Workout type: `HKWorkoutActivityType.functionalStrengthTraining`
- Metadata: `HKMetadataKeyExternalUUID = session.id.uuidString` for idempotency

**Acceptance (real device):** Complete workout → open Health → Workouts → see entry with correct duration.

**Est:** 2h

---

## Parallelization strategy

Dispatched as Opus subagent during Phase D alongside Slice 4.

```
Agent(
  description: "Slice 7 — Workout Session + Rest Timer + Live Activity + HealthKit",
  subagent_type: "general-purpose",
  isolation: "worktree",
  model: "opus",
  prompt: """
    Read plans/slice-07-workout-session.md and execute Tasks 7.1 through 7.9.
    Base: main just after Slice 6 merge.
    Branch: slice/07-workout-session

    CRITICAL:
    - Add a NEW target FitTrackerRestTimer (Widget Extension) in project.yml
    - TDD RED-first for service + timer math (UI LiveActivity not unit testable, manual QA on device)
    - Invoke skills per task header (especially source-driven-development for ActivityKit/CoreHaptics/HealthKit)
    - Touch: Features/Workouts/SessionView.swift, RestTimerView.swift, Core/Services/WorkoutService.swift, RestTimerController.swift, Core/LiveActivity/*, Core/Haptics/*, Core/Audio/*, Core/Notifications/*, Core/Health/HealthKitService.swift (ADD method), FitTrackerRestTimer/ (new target), ios/project.yml (add target + entitlements)
    - Do NOT touch Features/MealPlan/* (Slice 4 is concurrent)
    - Run xcodebuild test after each task
    - For LiveActivity/HealthKit: document manual test plan in task log; Simulator can't verify them fully

    When done, push + report task log.
  """,
  run_in_background: true
)
```

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| Live Activity test on Simulator limited | Note in ADR; all final QA on real device; feature-flag if blocked |
| Timer drift under aggressive OS throttling | Timestamp-based math eliminates drift by design |
| Notification permission denied → timer silent | Fall back to in-app haptic + sound; surface "Enable in Settings" hint |
| HealthKit API shifts across iOS versions | Use `#available(iOS 26, *)` gate; pin to iOS 26 min target per SPEC |
| AVAudioSession conflicts with music playback | Use `.ambient` category so music keeps playing |
| PR detection false positives from prior session's bad data | Edge case: only compare against verified sessions (not pending-sync ghosts) |
| ActivityKit quota (4 concurrent) | We only have 1 rest timer at a time; never an issue |
| Set data lost on mid-workout app crash | Write each set to SwiftData immediately; session recovers on relaunch |

## Verification before merge

```bash
cd ios && xcodebuild -scheme FitTracker test
# Real-device QA (required):
# 1. Start PPL day 1 → log bench 60kg × 8 → set complete → rest timer starts
# 2. Lock phone → timer shows on Lock Screen + Dynamic Island
# 3. Wait for zero → phone buzzes + beeps + notification arrives
# 4. Log heavier weight → PR celebration
# 5. End workout → open Health → see workout entry
# 6. Kill app during rest timer → notification still fires
```

Screenshots:
- [ ] SessionView both themes mid-set
- [ ] RestTimerView both themes with ring animation
- [ ] Dynamic Island compact + expanded
- [ ] Lock Screen Live Activity
- [ ] PR celebration overlay
- [ ] Apple Health workout entry

## Post-merge

Tag `slice-07-complete`. Slice 8 can now start.
