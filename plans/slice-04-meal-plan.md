# Slice 4 — Meal Plan + Shopping List

**Branch:** `slice/04-meal-plan`
**Estimate:** 12h realistic (8h optimistic, 16h if SwiftUI DnD fights on iPad)
**Owner:** Main agent (Phase D) OR Opus subagent — see parallelization

---

## Dependencies

- **Slice 3 merged** (`MealService`, `ProductService`, SwiftData has `Meal`, `Product`)
- `MealPlan`, `MealPlanItem`, `ShoppingList`, `ShoppingListItem` already in Schema.swift from Slice 2.1

## Parallelizable peers

- **Slice 7** (workout session) — different features, zero overlap. Run as subagent in parallel worktree.
- **Slice 9 Phase C** (rate limits, shared httpx) — backend worktree

## Objective

Deliver a weekly meal planner with drag-and-drop, plus an auto-generated categorized shopping list that persists check state across sessions.

## Acceptance criteria

- [ ] MealPlanWeekView shows 7 days × 4 meal-type rows; each cell is a drop target
- [ ] User can drag a meal from one day to another; backend + SwiftData update
- [ ] User can add meal to a day by tapping "+" → product search sheet → confirm
- [ ] "Generate shopping list" button creates list grouped by category
- [ ] ShoppingListView shows checkboxes; state persists to SwiftData + backend
- [ ] All 8 new Swift tests pass
- [ ] Works offline — drag + check state queued

## Skills to invoke

1. `api-and-interface-design` — `MealPlanService`, `ShoppingListService`
2. `source-driven-development` — SwiftUI `.draggable` / `.dropDestination` docs (iOS 16+)
3. `everything-claude-code:swiftui-patterns` — grid layout, drag state, sheets
4. `everything-claude-code:swift-actor-persistence` — optimistic writes
5. `test-driven-development`
6. `everything-claude-code:liquid-glass-design` + `ux-design:ios-hig-design`
7. `performance-optimization` — avoid re-renders on drag
8. `code-review-and-quality`

---

## Tasks

### Task 4.1 — `MealPlanService` + `ShoppingListService`

**Skills:** `api-and-interface-design`, `everything-claude-code:swift-actor-persistence`, `test-driven-development`

**RED tests:**
```swift
@Test func mealPlan_createsWeeklyPlan() async throws { ... }
@Test func mealPlan_moveItemBetweenDaysUpdatesBackend() async throws { ... }
@Test func shoppingList_generatedFromMealPlanGroupsByCategory() async throws { ... }
@Test func shoppingList_checkStatePersists() async throws { ... }
```

**Files:**
- `Core/Services/MealPlanService.swift` — actor; CRUD for MealPlan + MealPlanItem
- `Core/Services/ShoppingListService.swift` — actor; wraps `/meals/shopping-list/generate/{planId}` and patch checkbox

**Est:** 2.5h

---

### Task 4.2 — `MealPlanWeekView` layout

**Skills:** `everything-claude-code:swiftui-patterns`, `ux-design:ios-hig-design`

**Files:**
- `Features/MealPlan/MealPlanWeekView.swift` — horizontal `ScrollView` of 7 day columns; each column is `VStack` of 4 meal-type cells
- `Features/MealPlan/MealPlanCell.swift` — shows items; tap "+" opens product search
- `Features/MealPlan/WeekPicker.swift` — top bar: "‹ Week of Apr 20 ›"

**Key decision:** days as columns (horizontal scroll) feels more mobile-native than a vertical table. Each cell is tall enough for 2–3 items before overflow.

**Est:** 3h

---

### Task 4.3 — SwiftUI drag-and-drop for cells

**Skills:** `source-driven-development`, `everything-claude-code:swiftui-patterns`, `performance-optimization`

**RED test (drag state):** not directly testable in Swift Testing; rely on integration + manual QA

**Files:**
- Extend `MealPlanCell.swift` with `.draggable(item.id.uuidString)` on each item chip
- `.dropDestination(for: String.self) { uuids, _ in ... }` on each cell — matches uuid back to item, calls service to move

**Design:** haptic feedback via `UIImpactFeedbackGenerator(style: .medium)` on drop start and success.

**Acceptance:** Drag item from breakfast Monday to dinner Wednesday → backend updates; optimistic UI moves the chip immediately.

**Est:** 2.5h

---

### Task 4.4 — "Add item" flow

**Files:**
- Tap "+" in cell → sheet with product search (reuse `ManualEntrySheet` from Slice 3 or embed)
- Select product → prompts for quantity → inserts item

**Est:** 1h

---

### Task 4.5 — `ShoppingListView`

**Skills:** `everything-claude-code:swiftui-patterns`, `ux-design:ios-hig-design`

**Files:**
- `Features/MealPlan/ShoppingListView.swift` — sectioned list by category (Produce, Dairy, Proteins, Grains, Pantry, Frozen, Beverages)
- Swipe-to-check with haptic; strike-through style on checked items
- "Clear checked" and "Regenerate list" actions in toolbar

**Acceptance:** Generate from an active plan → see ingredients grouped. Check state round-trips to backend.

**Est:** 2h

---

### Task 4.6 — Offline drag-and-drop correctness

**Skills:** `everything-claude-code:swift-actor-persistence`

**Files:** existing `SyncManager` handles this; ensure `UpdateMealPlanItem` mutation is in `OfflineQueue` set.

**Test:** Airplane mode → drag → re-enable → backend receives PATCH.

**Est:** 1h

---

## Parallelization strategy

**Option A (recommended):** Main agent owns Slice 4 in Phase D while dispatching Slice 7 to an Opus subagent.

```
# Main agent: Slice 4 on main worktree
# Subagent: Slice 7 in another worktree
Agent(description: "Slice 7 — Workout Session + Timer", isolation: "worktree", model: "opus",
      prompt: "Read plans/slice-07-workout-session.md and execute. MealPlanService will be added by main agent in parallel — do not touch Features/MealPlan/*. Touch only Features/Workouts/*, Core/Services/WorkoutService.swift, Core/Health/HealthKitService.swift (add writeWorkout method).", run_in_background: true)
```

Merge order: whichever finishes first. Conflicts unlikely (different folders).

**Option B:** Main agent does both in sequence. Slower but lower coordination cost. Pick if we're feeling conservative about merge conflicts.

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| SwiftUI `.draggable` doesn't support custom preview on iPhone | Accept system preview in v1; customize in Slice 11 polish if time permits |
| Multi-finger drag glitches | Constrain to single gesture via `.simultaneousGesture` |
| Shopping list category mapping incomplete (products without category) | Fallback to "Other" category; surface in admin portal for curation (Slice 10) |
| Performance: 28 cells × items rerendering on drag | `Equatable` conformance + `@Observable` fine-grained updates |

## Verification before merge

```bash
cd ios && xcodebuild test
# Manual:
# 1. Create plan → add 5 items → drag between days → reload → state preserved
# 2. Generate shopping list → check some items → kill app → relaunch → state preserved
# 3. Airplane mode → drag → disable → backend updated
```

Screenshots:
- [ ] MealPlanWeekView both themes
- [ ] Drag-in-progress state
- [ ] ShoppingListView grouped by category
- [ ] Checkbox state persisted after relaunch

## Post-merge

Tag `slice-04-complete`.
