# Slice 6 — Programs + Exercise Database

**Branch:** `slice/06-programs-exercises`
**Estimate:** 12h realistic (8h optimistic, 16h if video playback surprises)
**Owner:** Opus subagent in worktree during Phase C

---

## Dependencies

- **Slice 1 merged** (auth)
- **Slice 2 Task 2.1 merged** (Schema has `Exercise`, `WorkoutProgram`, `WorkoutProgramDay`, `WorkoutProgramExercise`)

## Parallelizable peers

- Slices 2, 3, 5 concurrent during Phase C

## Objective

Ship browsing and selection for the 9 pre-built workout programs and the 56-exercise database, with playable form-video links and offline-available exercise data.

## Acceptance criteria

- [ ] `ProgramsListView` shows 9 programs with name / days-per-week / difficulty
- [ ] Tapping a program → `ProgramDetailView` with days + exercises per day
- [ ] "Start workout" button on a day → creates session (wired in Slice 7)
- [ ] `ExercisesBrowserView` with search bar + muscle-group filter + equipment filter
- [ ] Tapping exercise → `ExerciseDetailView` with form-video player (AVKit), muscle groups, equipment, instructions
- [ ] Exercise DB caches locally (SwiftData); offline browsing works
- [ ] All 10 new Swift tests pass
- [ ] Smooth scrolling at 60fps with 100+ exercises

## Skills to invoke

1. `api-and-interface-design` — `ProgramsService`, `ExercisesService`
2. `source-driven-development` — AVKit + SwiftUI `VideoPlayer` docs, URL resolution for YouTube vs direct MP4
3. `everything-claude-code:swiftui-patterns` — lists with search, filters, detail navigation
4. `performance-optimization` — LazyVStack for exercise list, prefetch video thumbnails
5. `everything-claude-code:swift-actor-persistence` — cache exercises
6. `test-driven-development`
7. `everything-claude-code:liquid-glass-design` + `ux-design:ios-hig-design`

---

## Tasks

### Task 6.1 — `ProgramsService` + `ExercisesService`

**Skills:** `api-and-interface-design`, `everything-claude-code:swift-actor-persistence`, `test-driven-development`

**RED tests:**
```swift
@Test func programsService_returnsCachedOnSecondCall() async throws { ... }
@Test func exercisesService_filtersByMuscleGroup() async throws { ... }
@Test func exercisesService_searchDebouncedAndOfflineFallback() async throws { ... }
```

**Files:**
- `Core/Services/ProgramsService.swift`
- `Core/Services/ExercisesService.swift` — 300ms debounced search, falls back to SwiftData query when offline

**Est:** 2.5h

---

### Task 6.2 — `ProgramsListView`

**Files:**
- `Features/Workouts/ProgramsListView.swift` — grid of `ProgramCard`
- `Features/Workouts/ProgramCard.swift` — name, days/week pill, difficulty color, short description

**Design:** Cards use `.themedCard()` modifier; Liquid Glass variant glows with accent tint on difficulty.

**Est:** 1.5h

---

### Task 6.3 — `ProgramDetailView`

**Files:**
- `Features/Workouts/ProgramDetailView.swift` — sectioned list of days, each day shows exercise count + "Start workout" CTA
- Tapping a day expands to exercise list for that day

**"Start workout"** routes to `SessionView` (implemented Slice 7; stub today — show "Coming in Slice 7" toast).

**Est:** 1.5h

---

### Task 6.4 — `ExercisesBrowserView` with search + filters

**Skills:** `everything-claude-code:swiftui-patterns`, `performance-optimization`

**Files:**
- `Features/Exercises/ExercisesBrowserView.swift` — `.searchable()` modifier + filter chips row (muscle groups: chest/back/legs/shoulders/arms/core; equipment: barbell/dumbbell/machine/bodyweight/cable)
- `Features/Exercises/ExerciseRow.swift` — thumbnail + name + muscles tag

**Performance:**
- `LazyVStack` with `id: \.id` for stable scroll
- Thumbnails via `AsyncImage` with `.task` cancellation on scroll
- Search debounced 300ms

**Est:** 2.5h

---

### Task 6.5 — `ExerciseDetailView` with video player

**Skills:** `source-driven-development`, `everything-claude-code:swiftui-patterns`, `performance-optimization`

**Files:**
- `Features/Exercises/ExerciseDetailView.swift`
- `Features/Exercises/ExerciseVideoPlayer.swift` — SwiftUI `VideoPlayer` wrapping `AVPlayer`

**Video sources:** most backend entries have YouTube links. AVKit cannot play YouTube directly. Options:
- **A.** Open in Safari / YouTube app via `UIApplication.shared.open(url)` — zero dev cost, breaks in-app feel
- **B.** Replace with direct MP4 URLs (re-host or find CC-BY sources)
- **C.** Use a WebView wrapping YouTube's embed player

**Decision for v1:** Option A for YouTube links, Option B for any we control. Document in ADR. Polish to embedded player deferred to post-v1.

**Est:** 2h

---

### Task 6.6 — Exercise cache warmup at app launch

**Skills:** `everything-claude-code:swift-actor-persistence`, `performance-optimization`

**Files:**
- `Core/Services/ExercisesService.swift` — add `prewarmCache()` method
- `AppRoot.swift` — on first authenticated launch, fire-and-forget prewarm (background priority)

**Acceptance:** After one online session, Airplane mode → ExercisesBrowserView works fully.

**Est:** 1h

---

### Task 6.7 — Navigation wiring to tab bar

**Files:** `MainTabView.swift` — Workouts tab routes to `ProgramsListView` at root; Exercises as sub-navigation from there OR its own tab if UX demands (let's make it a tab for discoverability).

**Est:** 0.5h

---

## Parallelization strategy

Subagent-owned during Phase C. Dispatch template identical to Slice 3/5.

```
Agent(description: "Slice 6 — Programs & Exercises",
      isolation: "worktree", model: "opus",
      prompt: """
        Read plans/slice-06-programs-exercises.md, execute Tasks 6.1-6.7.
        Branch: slice/06-programs-exercises
        Touch: Features/Workouts/ProgramsListView.swift, ProgramDetailView.swift, Features/Exercises/*,
               Core/Services/ProgramsService.swift, ExercisesService.swift, Core/Networking/DTO.swift (append)
        Do NOT touch Features/Workouts/SessionView.swift or RestTimerView.swift (Slice 7).
        Do NOT touch Schema.swift.
        TDD RED-first, invoke skills per task header.
      """,
      run_in_background: true)
```

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| YouTube player blocked inside App Store apps (policy drift) | Option A (open in Safari) is safest; revisit in v1.1 |
| Exercise DB grows from 56 → 800 later, caching slows | Paginate search, cache LRU 200 entries |
| Video thumbnails absent for YouTube links (auto-fetch requires API) | Use muscle-group icon as fallback thumbnail |
| Filter combinations explode | Fixed whitelist of muscle/equipment tokens; no free-text filters |

## Verification before merge

```bash
cd ios && xcodebuild test
# Manual:
# - Programs list → pick PPL → day 1 → see exercises
# - Browser → search "bench" → filter "chest" → tap Bench Press → video opens in YouTube
# - Airplane mode → browser still works with cached data
```

Screenshots:
- [ ] ProgramsListView both themes
- [ ] ProgramDetailView both themes
- [ ] ExercisesBrowserView with filters applied
- [ ] ExerciseDetailView both themes

## Post-merge

Tag `slice-06-complete`. Slice 7 can now start (needs programs/exercises data to log a session against).
