# Slice 0.5 — Mockup Tap-Through Prototype

**Branch:** `slice/005-mockup`
**Estimate:** 14h realistic (8h optimistic, 20h if design ping-pongs)
**Owner:** Main agent — **do not parallelize**. This is a design gate.

---

## Dependencies

- **Slice 0 merged** (foundation, both themes present, AppTheme environment wired)

## Parallelizable peers

- **Slice 9 Phase A** (if not already done in Slice 0 parallel dispatch)

## Objective

Produce a tap-through SwiftUI prototype that renders all 14 screens from SPEC §4 using only `MockData` — no network, no persistence, no auth. The prototype's only job is to let Armando validate the look AND feel of both themes in the Simulator before we commit to building real implementations in Slices 1–8.

**Scope boundary:** Buttons that would mutate data just log + dismiss. No backend. No SwiftData. No HealthKit. No timers. Just navigation and visuals.

## Acceptance criteria

- [ ] Launch the app in Simulator, tap-through works: Login → Dashboard → every tab → every detail screen
- [ ] A Settings screen exposes a theme switcher; switching redraws all screens instantly without re-launch
- [ ] All 14 screens render in both Liquid Glass and Health Cards themes without visual breakage
- [ ] Mock data is seeded realistically (5 meals, 3 workouts, 10 exercises, 1 meal plan, 1 shopping list, 1 profile, 3 test users)
- [ ] Scroll performance: 60fps on iPhone 16 Pro simulator (no `LazyVStack` misuse, no gigantic images)
- [ ] Preview gallery: every view file has `#Preview` block showing both themes side-by-side
- [ ] Armando reviews in Simulator and picks "go" / "tweak X" / "redo Y". Output is captured in `plans/design-review-log.md`
- [ ] One screen recording per theme (Simulator → File → Record Screen) committed to `docs/mockups/`

## Skills to invoke (in order)

1. `everything-claude-code:liquid-glass-design` — for every Liquid Glass rendering decision
2. `ux-design:ios-hig-design` — tap targets ≥44pt, safe areas, Dynamic Type support
3. `ux-design:refactoring-ui` — visual hierarchy, spacing, color use across all 14 screens
4. `everything-claude-code:swiftui-patterns` — SwiftUI structural patterns (NavigationStack, sheet presentation, .toolbar, @Environment)
5. `frontend-ui-engineering` — (adapted to SwiftUI) component composition, avoiding god-views
6. `incremental-implementation` — one screen at a time, each committed
7. `code-simplification` — avoid premature abstraction
8. `test-driven-development` — only for MockData service protocol

---

## Tasks

### Task 0.5.1 — MockData service + seed fixtures

**Skills:** `everything-claude-code:swift-protocol-di-testing`, `test-driven-development`

**RED test:**
```swift
@Test func mockData_hasCompleteDashboardFixture() {
    let sut = MockDataService()
    #expect(sut.meals.count >= 5)
    #expect(sut.exercises.count >= 10)
    #expect(sut.user.email == "carlos@fittracker.dev")
}
```

**Files:**
- `ios/FitTracker/Core/MockData/MockData.swift` — static seed (meals, workouts, exercises, meal plan, shopping list, user)
- `ios/FitTracker/Core/MockData/MockServices.swift` — `MockAuthService`, `MockMealService`, `MockWorkoutService`, etc., each conforming to the *service protocols defined in later slices*. We DEFINE the protocols here in stub form so the views can bind against them.
- `ios/FitTracker/Core/Services/ServiceProtocols.swift` — protocols only (implementations in later slices)

**Decision:** the protocol surface is defined NOW so that Slice 1–8 implementations just fill in the concrete types. Prototype views bind to the protocols.

**Acceptance:** All mock services return seed data; no nulls; no crashes.

**Est:** 2h

---

### Task 0.5.2 — Tab bar + navigation skeleton

**Skills:** `everything-claude-code:swiftui-patterns`, `ux-design:ios-hig-design`

**Files:**
- `ios/FitTracker/Features/Root/MainTabView.swift` — 4 tabs: Home, Meals, Workouts, Profile. Each tab hosts a `NavigationStack`.
- Updates `AppRoot.swift` to mount `MainTabView` when "logged in" (mock flag at this stage)

**Acceptance:** Tabs switch without losing scroll position within each stack.

**Est:** 0.5h

---

### Task 0.5.3 — LoginView (mock)

**Skills:** `everything-claude-code:liquid-glass-design`, `ux-design:ios-hig-design`

**Files:**
- `ios/FitTracker/Features/Auth/LoginView.swift`
- Email field, password field, "Sign In" button, "Sign in with Apple" button (visual only — actual SIWA in Slice 1)
- Quick-select buttons for 3 test accounts (carlos/maria/roberto@fittracker.dev)
- Link to "Create account"

**Acceptance:** Renders correctly in both themes. "Sign In" button just navigates to MainTabView.

**Est:** 1h

---

### Task 0.5.4 — RegisterView (mock)

**Files:** `Features/Auth/RegisterView.swift` — email, display name, password, confirm password. Submit dismisses → login.

**Est:** 0.5h

---

### Task 0.5.5 — HomeView (mock)

**Skills:** `everything-claude-code:liquid-glass-design`, `ux-design:ios-hig-design`, `ux-design:refactoring-ui`

**Files:**
- `ios/FitTracker/Features/Home/HomeView.swift` — hero card "Calories Today" with progress ring, macro row (P/C/F), recent meals list, "Log Meal" FAB
- `ios/FitTracker/Features/Home/MacroRingView.swift` — custom SwiftUI `Canvas` rendering three concentric rings (protein blue, carbs green, fat amber), tokens from theme

**Design notes:**
- Liquid Glass version: hero card uses `.ultraThinMaterial`, rings glow with `.accent` opacity
- Health Cards version: hero card is white surface with soft shadow, rings are solid fill

**Acceptance:** Rings render at correct angles for seed data (1450 cal of 2000 goal = 72.5% fill). Numbers legible at 375pt width.

**Est:** 2h

---

### Task 0.5.6 — ScanView (mock)

**Files:** `Features/Scan/ScanView.swift` — fake viewfinder with animated line, "Manual Entry" and "Take Photo" buttons. Tapping "Manual Entry" presents the ManualEntrySheet with a search field and mock product list.

**Acceptance:** Navigation out to ProductDetailSheet from mock search result works.

**Est:** 1h

---

### Task 0.5.7 — MealsListView + MealDetailView (mock)

**Files:**
- `Features/Meals/MealsListView.swift` — sectioned by meal type (breakfast/lunch/dinner/snack)
- `Features/Meals/MealDetailView.swift` — list of items with calories, delete swipe action (mock)

**Est:** 1h

---

### Task 0.5.8 — MealPlanWeekView (mock)

**Skills:** `everything-claude-code:swiftui-patterns`, `ux-design:ios-hig-design`

**Files:**
- `Features/MealPlan/MealPlanWeekView.swift` — 7-column horizontal scroll, each column is a day with breakfast/lunch/dinner/snack cells. Static drag-and-drop affordance only (no real DnD in mockup).

**Est:** 1h

---

### Task 0.5.9 — ShoppingListView (mock)

**Files:** `Features/MealPlan/ShoppingListView.swift` — list grouped by Produce/Dairy/Proteins/etc. with checkboxes. State stays in `@State` only (resets on navigation).

**Est:** 0.5h

---

### Task 0.5.10 — ProfileView + TDEECalculatorView + GoalsView (mock)

**Files:**
- `Features/Profile/ProfileView.swift` — form (weight/height/age/sex/activity)
- `Features/Profile/TDEECalculatorView.swift` — live BMR/TDEE/macros preview; uses a mock calculator that just returns static numbers
- `Features/Profile/GoalsView.swift` — preset picker (Fat Loss / Maintenance / Lean Bulk / Muscle Gain) + custom editor

**Est:** 1.5h

---

### Task 0.5.11 — ProgramsListView + ProgramDetailView (mock)

**Files:**
- `Features/Workouts/ProgramsListView.swift` — card per program, name + days/week + difficulty pill
- `Features/Workouts/ProgramDetailView.swift` — list of days, each day lists exercises

**Est:** 1h

---

### Task 0.5.12 — ExercisesBrowserView + ExerciseDetailView (mock)

**Files:**
- `Features/Exercises/ExercisesBrowserView.swift` — searchable list with muscle-group filter pills
- `Features/Exercises/ExerciseDetailView.swift` — name, muscle groups, equipment, difficulty, placeholder video thumbnail with play button (no actual video in mockup)

**Est:** 1h

---

### Task 0.5.13 — SessionView + RestTimerView (mock)

**Files:**
- `Features/Workouts/SessionView.swift` — current exercise card, set rows (weight + reps input), "Set Complete" button
- `Features/Workouts/RestTimerView.swift` — visual countdown ring. Start/Pause/Skip. No real timer — just counts from 90 to 0 for demo.

**Design note:** This is the big iOS-feel moment. Spend extra time here making the rest timer feel snappy and premium in both themes.

**Est:** 1.5h

---

### Task 0.5.14 — HistoryView + VolumeChartView + PRListView (mock)

**Files:**
- `Features/History/HistoryView.swift` — calendar (SwiftUI `DatePicker` style or custom grid) with dots on workout days
- `Features/History/VolumeChartView.swift` — SwiftUI Charts bar chart, mock 8-week data
- `Features/History/PRListView.swift` — list of PRs with exercise name + weight + date

**Est:** 1h

---

### Task 0.5.15 — SettingsView with theme toggle

**Skills:** `everything-claude-code:swiftui-patterns`, `ux-design:ios-hig-design`

**Files:**
- `Features/Settings/SettingsView.swift` — theme picker (Liquid Glass / Health Cards / System), language toggle (EN/ES), sign-out button, Account → "Delete Account" (mock action)

**Acceptance:** Changing theme picker instantly updates every screen (via `@AppStorage` + environment).

**Est:** 0.5h

---

### Task 0.5.16 — Simulator recordings + design review log

**Skills:** `ux-design:refactoring-ui`

**Files:**
- `docs/mockups/recording-liquid-glass.mov`
- `docs/mockups/recording-health-cards.mov`
- `plans/design-review-log.md` — armando's notes, final verdict

**Acceptance:** Two screen recordings exist; design-review-log has a verdict of "go with Liquid Glass as default", "go with Health Cards as default", or "revise N items".

**Est:** 0.5h (plus Armando's review time, which is outside this task)

---

## Parallelization strategy

**None.** All 14 screens need consistent component patterns; splitting them across agents would produce drift. Main agent does this end-to-end.

**However**, Slice 9 Phase A (started during Slice 0) should now be nearly done. If subagent reports complete, I rebase and merge it immediately — gives us a cleaner backend while I work on mockups.

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| Perfectionism spiral — redesigning while mocking | Timebox each screen to its estimate; defer polish to Slice 11 |
| Mock protocols diverge from what real services need | Keep protocols minimal and method-shaped (e.g. `func fetchMeals(on: Date) async throws -> [Meal]`). Slices 1–8 refine. |
| Theme inconsistency between screens | Audit checklist at end of task 0.5.16: for each screen, verify both themes render and no hardcoded colors exist |
| Design review triggers large rework | That's the POINT of this slice. Budget 20% buffer for one round of revision. If >2 rounds, escalate to scope trim. |

## Verification before merge

```bash
cd ios && xcodegen && xcodebuild -scheme FitTracker -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
# No tests to run beyond Slice 0's smoke + MockData test
```

Checklist:
- [ ] 14 screens + Settings = 15 views with `#Preview` in both themes
- [ ] Screen recordings committed
- [ ] `plans/design-review-log.md` shows Armando's verdict
- [ ] PR description notes: "This slice produces no user value — its purpose is design validation. Next slice (1) begins real implementation."

## Post-merge

Tag `slice-05-complete`. Based on design review:
- If "go": proceed to Slice 1 with theme defaults locked in
- If "revise N items": create `slice/005b-design-revisions` branch, fix, re-review, then Slice 1

Important: the mockup code is NOT thrown away. The protocol stubs and MockData service carry forward. The views are rewritten in Slices 1–8 but the skeleton + navigation shell survives.
