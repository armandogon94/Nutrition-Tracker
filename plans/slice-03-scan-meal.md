# Slice 3 — Scan & Log Meal

**Branch:** `slice/03-scan-meal`
**Estimate:** 16h realistic (10h optimistic, 22h if VisionKit setup surprises)
**Owner:** Opus subagent in worktree during Phase C (concurrent with Slices 2, 5, 6)

---

## Dependencies

- **Slice 1 merged** (auth tokens available)
- **Slice 2 Task 2.1 merged** (Schema has `Meal`, `MealItem`, `Product`)

## Parallelizable peers

- Slices 2 (main worktree — dashboard), 5 (profile), 6 (exercises) — all running concurrently

## Objective

Let a user point their phone at a barcode and log the resulting food to today's meals — plus manual entry and photo-based Claude Vision fallback, plus HealthKit write so the dietary data lands in the Health app.

## Acceptance criteria

- [ ] VisionKit `DataScannerViewController` opens on tap; permission prompt only on first use
- [ ] Scanning a barcode → product lookup → confirmation sheet → "Log to breakfast" → meal appears on HomeView within 500ms (optimistic insert)
- [ ] Manual entry sheet: search-as-you-type against backend `/products/search`; debounced 300ms; offline uses SwiftData cache
- [ ] "Take photo of meal" → Claude Vision identifies food + portion → edit sheet → log
- [ ] HealthKit: after meal log, dietary calories + macros write to Health (if authorized)
- [ ] Camera permission denied → graceful fallback with "Open Settings" link
- [ ] All 10 new Swift tests pass
- [ ] Zero PII in Claude Vision prompts (no user email/id sent with image)

## Skills to invoke (in order)

1. `source-driven-development` — VisionKit `DataScannerViewController` docs (iOS 16+); Claude Vision best practices; HealthKit write docs. Use Context7 MCP for Apple SDK and Anthropic SDK docs.
2. `security-and-hardening` — camera permissions, image-data handling, Claude API key storage
3. `everything-claude-code:claude-api` — Claude Vision prompt engineering, caching, cost control
4. `test-driven-development`
5. `everything-claude-code:swiftui-patterns` — sheets, camera overlay, form design
6. `everything-claude-code:swift-concurrency-6-2` — scanner delegate + async bridge
7. `everything-claude-code:healthcare-phi-compliance` — HealthKit write flow
8. `api-and-interface-design` — define `ProductService`, `MealService`, `VisionService`
9. `everything-claude-code:liquid-glass-design` + `ux-design:ios-hig-design`
10. `code-review-and-quality` — pre-merge

---

## Tasks

### Task 3.1 — `MealService` protocol + concrete + optimistic cache

**Skills:** `api-and-interface-design`, `everything-claude-code:swift-actor-persistence`, `test-driven-development`

**RED test:**
```swift
@Test func mealService_optimisticInsertThenSync() async throws { ... }
@Test func mealService_revertsOnApiError() async throws { ... }
@Test func mealService_logsMealItemToExistingMeal() async throws { ... }
```

**Files:**
- `Core/Services/MealService.swift` — actor. Writes to SwiftData immediately with `.pendingSync=true`, async sends to backend, on success marks synced, on failure enqueues in OfflineQueue
- `Core/Services/ProductService.swift` — wraps `/products/search?q=` and `/products/{barcode}`

**Est:** 2.5h

---

### Task 3.2 — VisionKit `DataScannerViewController` wrapper

**Skills:** `source-driven-development`, `everything-claude-code:swiftui-patterns`, `security-and-hardening`

**RED test:** skip (UIKit bridge; integration test only)

**Files:**
- `Features/Scan/BarcodeScannerView.swift` — `UIViewControllerRepresentable` wrapping `DataScannerViewController`, configured for `.barcode(symbologies: [.ean13, .ean8, .upce, .code128])`
- `Features/Scan/BarcodeScannerCoordinator.swift` — delegate; exposes `AsyncStream<String>` of decoded strings
- `Features/Scan/ScanView.swift` — hosts the scanner; overlays viewfinder rectangle + "Hold steady" prompt

**Important:**
- Check `DataScannerViewController.isSupported` at launch (fallback for older-device testers)
- Request camera permission at first tap, not at app launch
- After scan, pause the scanner for 1s to prevent duplicate events

**Acceptance:** Point at a real barcode → decoded string emitted → subsequent ProductLookupSheet opens.

**Est:** 3h

---

### Task 3.3 — `ProductLookupSheet`

**Skills:** `everything-claude-code:swiftui-patterns`, `everything-claude-code:liquid-glass-design`

**Files:**
- `Features/Scan/ProductLookupSheet.swift` — loading spinner → product card (image/name/brand/macros) → serving-size input → "Log to [meal type]" button
- Handles "Product not found" state with option to manually enter

**Acceptance:** After barcode scan, sheet renders product within 2s. "Log" action calls `MealService.logItem(...)` and dismisses.

**Est:** 2h

---

### Task 3.4 — `ManualEntrySheet` with debounced search

**Skills:** `everything-claude-code:swiftui-patterns`, `performance-optimization`

**Files:**
- `Features/Scan/ManualEntrySheet.swift` — search field with 300ms debounce; list of results; "Create custom food" option at bottom if no match

**Debouncing:** Combine or async sequences (`AsyncStream` + `debounce` operator if using swift-async-algorithms; else a simple `Task` + `sleep` pattern)

**Acceptance:** Type "avena" → within 300ms + network latency, list shows products. Offline shows cached.

**Est:** 2h

---

### Task 3.5 — `PhotoCaptureView` + `VisionService`

**Skills:** `source-driven-development`, `everything-claude-code:claude-api`, `security-and-hardening`, `everything-claude-code:healthcare-phi-compliance`

**RED test:**
```swift
@Test func visionService_sendsImageWithNoPII() async throws {
    // Assert the outgoing request body contains only base64 image + prompt, no user id, email, or name
}
@Test func visionService_returnsParsedFoodIdentification() async throws { ... }
```

**Files:**
- `Features/Scan/PhotoCaptureView.swift` — `UIImagePickerController` OR native AVFoundation camera capture
- `Core/Services/VisionService.swift` — wraps `/api/v1/nutrition/recognize` backend endpoint. iOS sends multipart image upload; backend forwards to Claude Vision.

**Security:** image compressed to max 1024px JPEG quality 0.7. Never sent to any 3rd party directly from iOS — always routes through our backend so we control the API key.

**Backend note:** existing `food_recognition.py` service already does Claude Vision. No backend changes unless we need an iOS-specific endpoint shape.

**Acceptance:** Take photo of chicken breast → VisionService returns `{food: "grilled chicken breast", grams: 150, confidence: "high"}` → edit sheet lets user adjust before logging.

**Est:** 3h

---

### Task 3.6 — HealthKit dietary write

**Skills:** `source-driven-development`, `security-and-hardening`, `everything-claude-code:healthcare-phi-compliance`

**RED test:**
```swift
@Test func healthKit_writesDietaryEnergyOnMealLog() async throws { ... }
@Test func healthKit_gracefullyHandlesUnauthorized() async throws { ... }
```

**Files:**
- `Core/Health/HealthKitService.swift` — add `writeMealEntry(mealItem: MealItem)` method

**Implementation:**
- `HKQuantityType` samples: `.dietaryEnergyConsumed`, `.dietaryProtein`, `.dietaryCarbohydrates`, `.dietaryFatTotal`, `.dietaryFiber`
- Batched `HKCorrelation` so all samples for one meal item are grouped
- Metadata: `HKMetadataKeyFoodType = "meal"`, `HKMetadataKeyExternalUUID = mealItem.id.uuidString` for idempotency

**Authorization:** request the write types at first meal log; remember user's decision.

**Acceptance:** Log meal → open Apple Health → "Nutrition" shows the entry.

**Est:** 2.5h

---

### Task 3.7 — HomeView integration + optimistic UI

**Files:**
- `HomeViewModel` subscribes to `MealService.recentMeals` → new meal appears immediately
- FAB "Log Meal" on HomeView routes to `ScanView`

**Est:** 1h

---

## Parallelization strategy

This entire slice runs as a **subagent in an Opus worktree**, started by main agent during Phase C.

**Dispatch:**
```
Agent(
  description: "Slice 3 — Scan & Meal",
  subagent_type: "general-purpose",
  isolation: "worktree",
  model: "opus",
  prompt: """
    You are implementing Slice 3 from plans/slice-03-scan-meal.md.
    Base branch: main at commit <sha> (just after Schema.swift merged).
    Branch name: slice/03-scan-meal

    Constraints:
    - TDD discipline: write RED test first in FitTrackerTests/, run, see it fail, then implement
    - Invoke the skill listed in each task header before writing code
    - Touch ONLY these areas:
      Features/Scan/*, Features/Meals/*
      Core/Services/MealService.swift, ProductService.swift, VisionService.swift
      Core/Health/HealthKitService.swift (ADD method, don't break existing)
      Core/Networking/DTO.swift (APPEND new DTOs)
    - Do NOT modify Core/Persistence/Schema.swift. If you need a new model, stop and report.
    - Run `cd ios && xcodegen && xcodebuild test` after each task; paste output to task log
    - Commit per task with messages: "Slice 3.N: <task name>"

    When done, push branch and report with:
    1. Full task log (skill-by-skill)
    2. Total test count added
    3. Anything you had to change outside scope (escalate)
    4. Any API/backend gaps discovered
  """,
  run_in_background: true
)
```

Main agent (me) continues with Slice 2 Tasks 2.2+ while this runs.

### Merge flow when subagent completes
1. I get notified when background agent finishes
2. Pull the branch locally, rebase onto current main (Slices 2/5/6 may have merged in the meantime)
3. Run full test suite: `cd ios && xcodebuild test` + `cd backend && uv run pytest`
4. Invoke `everything-claude-code:cpp-reviewer` (wait, wrong — use `security-reviewer` + general code-reviewer)
5. Fix any minor conflicts (likely only `DTO.swift`; additive merge)
6. Merge to main with squash preserving task commits
7. Tag `slice-03-complete`

### If subagent reports blocker
- Backend endpoint missing → main agent adds it in a quick backend PR, subagent rebases
- Schema change needed → main agent extends Schema.swift, subagent rebases
- Claude Vision budget concern → escalate, discuss daily-cap implementation

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| VisionKit bad UX in low light | Show "Hold steady / poor lighting" hints; fallback to manual entry always visible |
| Barcode decoded but backend has no product | Surface "Create product" path; don't dead-end |
| Claude Vision portion estimate off by ±40% | Always present editable grams before logging; cross-reference OFF nutrition |
| Camera permission denial | Fallback: show `Manual Entry` sheet directly + "Enable camera in Settings" link |
| HealthKit idempotency: double-writes | Use `HKMetadataKeyExternalUUID = mealItem.id`; check for existing before writing |
| Claude API cost spike | Per-user daily cap (e.g., 20 photos/day); cache photo → product result in backend for 24h |
| PII in Claude Vision prompt | Strict: only send image + generic prompt. Never user name/email/id. Test asserts this. |

## Verification before merge

```bash
# Unit tests
cd ios && xcodebuild -scheme FitTracker -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test

# Backend (ensure we didn't break meals endpoints)
cd backend && DATABASE_URL=... uv run pytest tests/test_meals.py tests/test_products.py -v

# Manual (real device preferred)
# 1. Scan a real barcode (e.g., oatmeal package) → product appears → log → HomeView updates
# 2. Manual entry "oatmeal" → list → log
# 3. Photo of meal → Claude Vision → edit → log
# 4. Open Apple Health → Nutrition → see entry
# 5. Airplane mode → log manually → disable airplane → backend receives write
```

Screenshots:
- [ ] BarcodeScannerView both themes (viewfinder)
- [ ] ProductLookupSheet both themes
- [ ] ManualEntrySheet with debounced search results
- [ ] PhotoCaptureView + Claude Vision result
- [ ] Apple Health app showing our entry

## Post-merge

Tag `slice-03-complete`. Slice 4 (Meal Plan) can now start — it depends on `MealService` existing.
