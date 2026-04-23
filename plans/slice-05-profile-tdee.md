# Slice 5 — Profile + TDEE + Goals

**Branch:** `slice/05-profile-tdee`
**Estimate:** 8h realistic (5h optimistic, 12h if Dynamic Type edges are strict)
**Owner:** Opus subagent in worktree during Phase C

---

## Dependencies

- **Slice 1 merged** (auth)
- **Slice 2 Task 2.1 merged** (Schema has `UserProfile`, `NutritionGoal`)

## Parallelizable peers

- Slices 2, 3, 6 running simultaneously in separate worktrees during Phase C

## Objective

Ship the profile flow: user enters weight/height/age/sex/activity → sees live BMR/TDEE + recommended macros → picks preset (fat loss / maintenance / bulk) OR customizes → saves.

## Acceptance criteria

- [ ] `ProfileView` form: weight (kg), height (cm), age, sex (picker), activity (picker)
- [ ] Live preview panel: BMR, TDEE, suggested calories, protein g, carbs g, fat g — updates as fields change
- [ ] Unit toggle: imperial ↔ metric in Settings (stretch; metric only v1 OK)
- [ ] Preset selector: 4 cards (Fat Loss / Maintenance / Lean Bulk / Muscle Gain) with calorie delta shown
- [ ] Custom mode: override individual macro grams; warn if total < 1200 kcal or protein < 0.8g/kg
- [ ] Save → backend writes profile + goals; returns updated targets
- [ ] All 10 new Swift tests (TDEE calc edge cases + view model state) pass
- [ ] Fully Dynamic Type compliant — form legible at XXL

## Skills to invoke

1. `api-and-interface-design` — `ProfileService` protocol
2. `test-driven-development` — TDEE math has exact expected outputs
3. `everything-claude-code:swiftui-patterns` — form layout, pickers, live preview
4. `ux-design:ios-hig-design` — form accessibility, Dynamic Type
5. `everything-claude-code:liquid-glass-design` — preset card visuals
6. `everything-claude-code:swift-concurrency-6-2`
7. `security-and-hardening` — input validation mirrors backend constraints

---

## Tasks

### Task 5.1 — `ProfileService` + TDEE calc (client-side mirror)

**Skills:** `api-and-interface-design`, `test-driven-development`

**RED tests:**
```swift
@Test func tdee_mifflinStJeorMale() {
    let p = UserProfile(weightKg: 80, heightCm: 180, age: 30, sex: .male, activity: .moderate)
    #expect(tdee(p) == 2816.25)  // BMR 1816.25 × 1.55
}
@Test func tdee_edgeCases() {
    // youngest: 13, oldest: 120, min/max weight/height bounds
}
@Test func macros_respectMinimums() {
    let g = recommendedMacros(tdee: 1200, goal: .fatLoss, weightKg: 80)
    #expect(g.protein_g >= 160)  // 2g/kg
}
```

**Files:**
- `Core/Services/ProfileService.swift` — actor; wraps `/api/v1/profile`, `/profile/tdee`, `/profile/goals`
- `Core/Models/TDEECalculator.swift` — pure Swift struct with static funcs; mirrors backend's `tdee_calculator.py` exactly so preview doesn't lag

**Key decision:** client-side calc for instant preview; backend is source of truth on save (server recalculates, returns its numbers).

**Est:** 2h

---

### Task 5.2 — `ProfileView` form

**Skills:** `everything-claude-code:swiftui-patterns`, `ux-design:ios-hig-design`

**Files:**
- `Features/Profile/ProfileView.swift`
- `Features/Profile/ProfileFormRows.swift` — reusable row types (stepper, picker, slider)

**Rows:**
- Weight kg — `Stepper` with 0.5 step
- Height cm — `Stepper` with 1 step
- Age — `Stepper` years
- Sex — segmented picker (Masculino / Femenino / Otro)
- Activity — wheel picker with descriptions

**Spanish strings:** all labels in `Localizable.xcstrings`.

**Est:** 2h

---

### Task 5.3 — `TDEECalculatorView` live preview panel

**Skills:** `everything-claude-code:swiftui-patterns`, `everything-claude-code:liquid-glass-design`

**Files:**
- `Features/Profile/TDEECalculatorView.swift` — four-tile grid: BMR / TDEE / Daily Calories / Protein g, updates as form state changes
- Animated number transitions with `.contentTransition(.numericText())`

**Acceptance:** Changing weight from 80 → 85 kg visibly updates all four tiles within 100ms (no jank).

**Est:** 1.5h

---

### Task 5.4 — `GoalsView` preset + custom modes

**Skills:** `everything-claude-code:swiftui-patterns`, `ux-design:ios-hig-design`

**Files:**
- `Features/Profile/GoalsView.swift` — segmented control: "Preset" / "Custom"
- Preset mode: 4 `GlassCard` selectable cards (Fat Loss -500, Maintenance, Lean Bulk +250, Muscle Gain +500)
- Custom mode: steppers for calories, protein g, carbs g, fat g with live total validation

**Validation:**
- Total macros must == total calories (±50 kcal tolerance)
- Warn if calories < 1200 (female) / 1500 (male)
- Warn if protein < 0.8g/kg

**Acceptance:** Pick preset → save → backend updates → HomeView next load reflects new goals.

**Est:** 2h

---

### Task 5.5 — Settings integration

**Files:**
- `SettingsView.swift` — add "Profile" row → pushes `ProfileView`; add "Goals" row → pushes `GoalsView`

**Est:** 0.5h

---

## Parallelization strategy

Subagent-owned during Phase C.

```
Agent(
  description: "Slice 5 — Profile + TDEE + Goals",
  subagent_type: "general-purpose",
  isolation: "worktree",
  model: "opus",
  prompt: """
    Read plans/slice-05-profile-tdee.md and execute Tasks 5.1 through 5.5.
    Base: main just after Schema.swift merge.
    Branch: slice/05-profile-tdee

    Constraints:
    - TDD RED-first
    - Invoke skills listed per task
    - Touch ONLY: Features/Profile/*, Core/Services/ProfileService.swift, Core/Models/TDEECalculator.swift, Core/Networking/DTO.swift (append)
    - Do NOT edit Schema.swift, FitTrackerApp.swift, AuthService.swift
    - Run xcodebuild test after each task
    - Commit per task
    - Spanish strings go in Localizable.xcstrings (key-based only in Swift; NEVER hardcoded)
  """,
  run_in_background: true
)
```

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| Client-side TDEE drifts from backend | Shared test fixtures: backend exports JSON of (input → expected) pairs; iOS tests consume same JSON |
| User enters unrealistic values (5000 kg) | Field bounds: weight 20-300, height 100-250, age 13-120; backend enforces too |
| Spanish pluralization (1 hombre vs 2 hombres) | Use Xcode string catalog plural rules; tested with both en + es-419 |
| Dynamic Type XXL breaks layout | Preview at XXL; use `ViewThatFits` where needed |

## Verification before merge

```bash
cd ios && xcodebuild test
# Manual:
# - Enter values → TDEE updates live
# - Pick fat-loss preset → save → HomeView reflects new calorie target
# - Dynamic Type slider at XXL → form still usable
```

Screenshots:
- [ ] ProfileView + TDEECalculatorView (both themes)
- [ ] GoalsView preset mode both themes
- [ ] GoalsView custom mode with warning

## Post-merge

Tag `slice-05-complete`. Once all Phase C slices land, proceed to Phase D (Slices 4, 7).
