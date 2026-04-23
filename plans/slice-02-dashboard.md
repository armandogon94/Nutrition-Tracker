# Slice 2 — Dashboard + Offline Cache

**Branch:** `slice/02-dashboard-offline`
**Estimate:** 20h realistic (12h optimistic, 28h if SwiftData bites)
**Owner:** Main agent — **keeps this slice** even during parallel fan-out because SwiftData schema is shared infrastructure

---

## Dependencies

- **Slice 1 merged** (AuthService works, we can fetch real user data)
- Backend `/api/v1/nutrition/daily/{date}` already works (existing)

## Parallelizable peers

Once Task 2.1 (SwiftData schema) merges, these can start in other worktrees:

- **Slice 3** — Scan & Meal (uses Meal + Product models, but adds its own Scan feature files)
- **Slice 5** — Profile + TDEE (only uses User + NutritionGoal models, independent)
- **Slice 6** — Programs + Exercises (uses Exercise + WorkoutProgram models, independent)

## Objective

Build the real `HomeView` backed by a SwiftData write-through cache + HealthKit bodyweight read, so the dashboard renders even offline and shows today's macros as rings.

## Acceptance criteria

- [ ] HomeView loads in <300ms cold launch when SwiftData has yesterday's data cached
- [ ] Macro rings render protein/carbs/fat with accurate fills vs daily goal
- [ ] Recent meals list shows 5 most recent with correct relative dates
- [ ] Pull-to-refresh hits the backend and updates SwiftData
- [ ] Airplane mode → HomeView still renders from cache; a banner shows "Offline"
- [ ] New meal logged → dashboard updates optimistically
- [ ] HealthKit bodyweight pulled at launch (when authorized); displayed on hero card
- [ ] All 12 new Swift tests pass
- [ ] No warnings; strict concurrency clean

## Skills to invoke (in order)

1. `everything-claude-code:swift-actor-persistence` — SwiftData + actor isolation patterns
2. `source-driven-development` — SwiftData and HealthKit docs (via Context7 MCP; both APIs shift between iOS versions)
3. `api-and-interface-design` — define `NutritionService`, `SyncManager` protocols
4. `everything-claude-code:swift-concurrency-6-2` — `@ModelActor` for background writes, MainActor for UI
5. `test-driven-development` — RED tests for every service method
6. `performance-optimization` — measure cold launch, ensure LazyVStack in meals list
7. `everything-claude-code:swiftui-patterns` — HomeView layout, macro rings, pull-to-refresh
8. `everything-claude-code:liquid-glass-design` + `ux-design:ios-hig-design` — rendering quality
9. `security-and-hardening` — HealthKit read authorization, purpose strings, PHI handling
10. `everything-claude-code:healthcare-phi-compliance` — review HealthKit data flow
11. `code-review-and-quality` — pre-merge

---

## Tasks

### Task 2.1 — SwiftData schema + ModelContainer setup

**Skills:** `everything-claude-code:swift-actor-persistence`, `api-and-interface-design`, `source-driven-development`

**RED test:**
```swift
@Test func swiftDataSchema_canCreateAndReadMeal() throws {
    let container = try ModelContainer(for: Schema([Meal.self, MealItem.self, Product.self]),
                                       configurations: .init(isStoredInMemoryOnly: true))
    let ctx = ModelContext(container)
    let meal = Meal(id: UUID(), mealType: .breakfast, mealDate: Date())
    ctx.insert(meal)
    try ctx.save()
    let fetched = try ctx.fetch(FetchDescriptor<Meal>())
    #expect(fetched.count == 1)
}
```

**Files:**
- `ios/FitTracker/Core/Persistence/Schema.swift` — `@Model` classes for all 18 backend entities that the iOS client consumes. **This file becomes the shared contract; later slices ADD models by appending, never edit existing ones without coordinator approval.**
  - `User`, `UserProfile`, `NutritionGoal`
  - `Meal`, `MealItem`, `Product`, `DailyNutrition`
  - `MealPlan`, `MealPlanItem`, `ShoppingList`, `ShoppingListItem`
  - `Exercise`, `WorkoutProgram`, `WorkoutProgramDay`, `WorkoutProgramExercise`
  - `WorkoutSession`, `WorkoutSet`, `PersonalRecord`
- `ios/FitTracker/Core/Persistence/PersistenceController.swift` — `ModelContainer` singleton with dev/test configs
- `ios/FitTracker/Core/Persistence/Schema.swift` per-model docs — one-line comment per relationship

**Design decisions (document in ADR-0004):**
- All relationships use `.cascade` delete rule when child is fully owned; `.nullify` when shared (e.g. `Product` is shared across meals)
- IDs are server-assigned `UUID`; local writes before sync use a generated UUID marked `.pendingSync = true`
- Timestamps stored as `Date` (SwiftData uses UTC under the hood)

**Acceptance:** Schema compiles. One test per model validates roundtrip. ADR-0004 committed.

**Est:** 4h

---

### Task 2.2 — `SyncManager` for write-through cache

**Skills:** `everything-claude-code:swift-actor-persistence`, `everything-claude-code:swift-concurrency-6-2`, `api-and-interface-design`, `test-driven-development`

**RED test:**
```swift
@Test func sync_fetchesFromBackendAndWritesToSwiftData() async throws {
    let api = MockAPIClient(responses: [.ok(mealsJson)])
    let container = try ModelContainer(for: Schema([Meal.self, ...]), .inMemory)
    let sut = SyncManager(api: api, container: container)
    try await sut.syncMeals(for: today)
    let stored = try container.mainContext.fetch(FetchDescriptor<Meal>())
    #expect(stored.count == 3)
}

@Test func sync_queuesLocalWritesWhenOffline() async throws { ... }
@Test func sync_flushesQueuedWritesOnReconnect() async throws { ... }
```

**Files:**
- `ios/FitTracker/Core/Persistence/SyncManager.swift` — actor that fetches from API and upserts into SwiftData. Tracks `pendingSync` records and retries.
- `ios/FitTracker/Core/Persistence/OfflineQueue.swift` — append-only queue of mutations waiting for connectivity

**Design:**
- `SyncManager` exposes `fetchLatest<T>(endpoint: String) async throws -> [T]` + `enqueue<T>(mutation: T)`
- Mutations: `CreateMeal`, `DeleteMeal`, `CreateMealItem`, etc. Each is `Codable + Sendable` and has a `func execute(on api: APIClient) async throws`
- Reachability via `NWPathMonitor` — when online flag flips, drain queue

**Acceptance:** 3 RED tests pass. Manual: toggle airplane mode, log a meal, disable airplane mode, verify backend received the write.

**Est:** 5h

---

### Task 2.3 — `NutritionService` with cached reads

**Skills:** `api-and-interface-design`, `test-driven-development`, `everything-claude-code:swift-concurrency-6-2`

**RED test:**
```swift
@Test func nutritionService_returnsCachedWhenAvailable() async throws {
    // seed SwiftData with today's meals
    // call service → expect cached result, no API call
    #expect(api.callCount == 0)
}

@Test func nutritionService_refreshesInBackgroundAfterReturningCached() async throws { ... }
```

**Files:**
- `ios/FitTracker/Core/Services/NutritionService.swift` — protocol + concrete actor
- Methods: `dailyNutrition(for: Date) async throws -> DailyNutrition`, `meals(for: Date) async throws -> [Meal]`, `observe(date: Date) -> AsyncStream<DailyNutrition>`

**Pattern:** "stale-while-revalidate" — return cached immediately, kick off background refresh that emits via `AsyncStream`.

**Acceptance:** 2 RED tests pass. Cold launch dashboard uses cache.

**Est:** 3h

---

### Task 2.4 — `HomeView` real implementation

**Skills:** `everything-claude-code:swiftui-patterns`, `everything-claude-code:liquid-glass-design`, `ux-design:ios-hig-design`, `performance-optimization`

**RED test (view model):**
```swift
@Test func homeVM_showsLoadingThenData() async { ... }
@Test func homeVM_showsOfflineBannerWhenDisconnected() async { ... }
```

**Files:**
- `ios/FitTracker/Features/Home/HomeView.swift` — rewrite of Slice 0.5 mock with real services
- `ios/FitTracker/Features/Home/HomeViewModel.swift`
- `ios/FitTracker/Features/Home/MacroRingView.swift` — real Canvas drawing
- `ios/FitTracker/Features/Home/RecentMealsCard.swift`
- `ios/FitTracker/Features/Home/OfflineBanner.swift`

**Key SwiftUI pieces:**
- `.refreshable` modifier for pull-to-refresh
- `.task { await vm.load() }` on first appear
- `@Environment(NutritionService.self)` for DI (service registered in `FitTrackerApp`)
- `#Preview("Home — Liquid Glass")` and `#Preview("Home — Health Cards")` with mock service

**Acceptance:** All UI states render in both themes. Preview gallery shows both.

**Est:** 4h

---

### Task 2.5 — HealthKit bodyweight read

**Skills:** `source-driven-development` (HealthKit docs), `security-and-hardening`, `everything-claude-code:healthcare-phi-compliance`

**RED test:**
```swift
@Test func healthKit_returnsNilWhenNotAuthorized() async { ... }
@Test func healthKit_returnsLatestBodyMassWhenAuthorized() async { ... }
```

**Files:**
- `ios/FitTracker/Core/Health/HealthKitService.swift` — wraps `HKHealthStore`, read-only for bodyweight + activeEnergyBurned
- `ios/FitTracker/Core/Health/HealthKitAuthorization.swift` — request authorization flow, remembers user's decision

**Entitlement:** `com.apple.developer.healthkit` added to `project.yml`.

**Info.plist:** `NSHealthShareUsageDescription` (already added in Slice 0) explains why we read bodyweight.

**Acceptance:** Run on real device (Simulator has limited HealthKit). Add sample bodyweight in Health app. App shows it on HomeView. Revoke permission in Settings → app gracefully shows empty state.

**Est:** 3h

---

### Task 2.6 — HomeView integration + feature flag for HealthKit

**Files:** wire HealthKit data into HomeViewModel. Feature-flag it: if HealthKit unauthorized, show "Enable in Settings" link instead.

**Est:** 1h

---

## Parallelization strategy

Slice 2 is the **anchor** for Phase C fan-out.

**Sequence:**

1. Main agent completes Task 2.1 (schema). Commit and push intermediate.
2. Broadcast: schema is frozen for this phase. Dispatch Opus subagents for Slices 3, 5, 6 in parallel worktrees:

```
Agent(description: "Slice 3 — Scan & Meal", isolation: "worktree", model: "opus",
      prompt: "Read plans/slice-03-scan-meal.md and execute. Schema models Meal, MealItem, Product already in Core/Persistence/Schema.swift — extend ONLY by adding new models if needed; ask before editing existing ones. ...", run_in_background: true)

Agent(description: "Slice 5 — Profile & TDEE", isolation: "worktree", model: "opus",
      prompt: "Read plans/slice-05-profile-tdee.md and execute. Models UserProfile, NutritionGoal already available. ...", run_in_background: true)

Agent(description: "Slice 6 — Programs & Exercises", isolation: "worktree", model: "opus",
      prompt: "Read plans/slice-06-programs-exercises.md and execute. Models Exercise, WorkoutProgram* already available. ...", run_in_background: true)
```

3. Main agent continues Slice 2 Tasks 2.2 → 2.6 on its own worktree
4. As each subagent reports completion, main agent merges their branch onto main in finish order; remaining subagents rebase
5. Once all four merges complete, Phase C closes. Slice 4 can start.

**Critical invariant:** Schema.swift additions are additive only. If a subagent needs to modify an existing `@Model`, it must stop and request coordination via its task log. Main agent then pushes a schema update; subagent rebases.

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| SwiftData migration pain when we add a field later | Use `VersionedSchema` from day 1; ADR-0004 documents versioning strategy |
| HealthKit unavailable on Simulator | Feature-flag; most development on real device; CI uses `#if targetEnvironment(simulator)` skip |
| Subagents modify Schema.swift concurrently | Schema file owned by main agent; subagents get explicit additive changes through me |
| SwiftData `@Query` misuse causes full scans | Always use `FetchDescriptor` with predicates; profile cold launch with Instruments |
| Pull-to-refresh double-fires cache + network | Debounce in ViewModel; log if refresh triggered while already in-flight |
| PHI (bodyweight) leaks into Crashlytics | No Crashlytics in v1; privacy manifest disallows |

## Verification before merge

```bash
# Build
cd ios && xcodegen && xcodebuild -scheme FitTracker -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test

# Offline test
# 1. Launch app, log in, let dashboard populate
# 2. Enable Airplane mode in Simulator (hardware menu)
# 3. Kill + relaunch → HomeView still shows data with offline banner

# HealthKit (real device only)
# 1. Launch, grant permission
# 2. Observe bodyweight on HomeView
```

Screenshots:
- [ ] HomeView Liquid Glass, data loaded
- [ ] HomeView Health Cards, data loaded
- [ ] Offline banner visible
- [ ] Macro rings at 0%, 50%, 100% fill states

## Post-merge

Tag `slice-02-complete`. Once Slices 3, 5, 6 also merge, proceed to Phase D (Slices 4, 7).
