# Plans Overview — iOS FitTracker v1.0

**Companion to:** [SPEC.md](../SPEC.md)
**Date:** 2026-04-23
**Total slices:** 12 (0, 0.5, 1–11)
**Total estimated hours:** 180–240h
**Distribution target:** TestFlight (personal/family), App Store–ready by Slice 11

---

## 1. How to Read These Plans

Each `plans/slice-NN-*.md` file contains:

| Section | What it answers |
|---|---|
| **Dependencies** | Which slice(s) must merge before this one starts |
| **Parallelizable peers** | Which slice(s) can run in parallel git worktrees with this one |
| **Objective** | One-paragraph outcome |
| **Acceptance criteria** | Checkboxes that mean "done" — verified before merge |
| **Tasks** | Numbered, each with: skills invoked, RED test first, files touched, implementation outline, acceptance, time estimate |
| **Parallelization strategy** | Specific subagent dispatch + worktree recipe |
| **Risks & mitigations** | What could go sideways and the plan B |
| **Verification before merge** | Commands run + screenshots captured before PR |

Every task starts with a failing test (Swift Testing or pytest) per TDD skill. Every implementation step lists the exact skill(s) to invoke from `~/.claude/skills/`.

---

## 2. Dependency Graph

```
                     ┌──────────────────────────────────────────┐
                     │  Slice 9 — Backend Tech Debt             │
                     │  CAN START DAY 1 — no iOS deps           │
                     │  (datetime sweep, rate limit, N+1,       │
                     │   shared httpx, refresh tokens,          │
                     │   users.role migration, require_admin)   │
                     └───────────┬──────────────────┬───────────┘
                                 │                  │
                            (auth prep)        (admin prep)
                                 │                  │
       ┌───────────────┐         │                  │
       │  Slice 0      │         │                  │
       │  Foundation   │         │                  │
       │  (no deps)    │         │                  │
       └──────┬────────┘         │                  │
              │                  │                  │
       ┌──────▼────────┐         │                  │
       │  Slice 0.5    │         │                  │
       │  Mockup       │         │                  │
       │  (design gate)│         │                  │
       └──────┬────────┘         │                  │
              │                  │                  │
       ┌──────▼────────┐ ◄───────┘                  │
       │  Slice 1      │                            │
       │  Auth + SIWA  │                            │
       └───┬──┬──┬─────┘                            │
           │  │  │                                  │
    ┌──────┘  │  └──────┐   ┌──────┐               │
    │         │         │   │      │               │
  ┌─▼──┐   ┌─▼──┐    ┌─▼───▼─┐ ┌──▼──┐             │
  │ S2 │   │ S3 │    │  S5   │ │ S6  │             │
  │Home│   │Scan│    │Profile│ │Prog │             │
  │+Off│   │+Meal│   │+TDEE  │ │+Ex  │             │
  └─┬──┘   └─┬──┘    └───┬───┘ └──┬──┘             │
    │        │           │        │                │
    │     ┌──▼────┐      │        │                │
    │     │  S4   │      │        │                │
    │     │ Plan  │      │        │                │
    │     │+Shop  │      │        │                │
    │     └───────┘      │        │                │
    │                    │     ┌──▼──┐             │
    │                    │     │ S7  │             │
    │                    │     │Sess │             │
    │                    │     │+Time│             │
    │                    │     └──┬──┘             │
    │                    │        │                │
    │                    │     ┌──▼──┐             │
    │                    │     │ S8  │             │
    │                    │     │Hist │             │
    │                    │     └──┬──┘             │
    │                    │        │                │
    └────────────────────┴────────┘                │
                         │                         │
                         │                         │
                         │              ┌──────────▼────────┐
                         │              │  Slice 10         │
                         │              │  Admin Portal     │
                         │              │  (needs S9 gate)  │
                         │              └──────────┬────────┘
                         │                         │
                    ┌────▼─────────────────────────▼────┐
                    │  Slice 11 — Polish + TestFlight   │
                    │  needs everything green           │
                    └────────────────────────────────────┘
```

### Critical path (longest chain of must-finish-first dependencies)

`S0 → S0.5 → S1 → S7 → S11` — roughly 8 weeks of linear work if done solo.

With parallelization (see §4), S2/S3/S5/S6 compress into 2–3 calendar weeks because they run side-by-side. S9 runs the entire time in a separate worktree.

---

## 3. Merge Order & Branch Strategy

```
main
 ├── slice/00-foundation            → merge first, unblocks everything
 ├── slice/09-tech-debt-phase-A     → datetime + N+1 (can merge anytime)
 ├── slice/0.5-mockup-tapthrough    → merge after design review
 ├── slice/09-tech-debt-phase-B     → refresh tokens, role gate (merge before S1)
 ├── slice/01-auth                  → merges S1 on top of S9-phase-B
 ├── slice/02-dashboard-offline  ──┐
 ├── slice/03-scan-meal          ──┤ parallel worktrees, each rebased on S1
 ├── slice/05-profile-tdee       ──┤ merge order: whichever finishes first
 ├── slice/06-programs-exercises ──┘
 ├── slice/04-meal-plan             → waits on S3
 ├── slice/07-workout-session       → waits on S6
 ├── slice/08-history               → waits on S7
 ├── slice/09-tech-debt-phase-C     → rate limits, shared httpx (merge anytime)
 ├── slice/10-admin-portal          → needs S9 phase C merged
 └── slice/11-testflight-polish     → final, needs all above
```

**Branch naming:** `slice/NN-short-name` (NN = slice number, no dot — slice 0.5 becomes `slice/005-mockup`).

**Merge discipline:**
- Each slice branch rebases on `main` before opening PR
- PR title: `Slice N: <name>` with SPEC link in description
- `/review` runs on every PR before merge
- After merge, delete branch, tag commit `slice-N-complete`

---

## 4. Parallelization Map — When To Spawn Subagents

A subagent here means an Opus agent dispatched via the `Agent` tool, working in its own git worktree created via `EnterWorktree`. I (the main agent) coordinate and handle merges. Worktrees stay cheap because they share the `.git` directory.

### Parallelization opportunities by phase

**Phase A — Day 1 (no deps)**
- **Worktree 1 (main):** Slice 0 Foundation
- **Worktree 2 (subagent):** Slice 9 Phase A (datetime sweep + N+1 fix). These edit backend only, no conflict with Swift.

**Phase B — After Slice 0 + 0.5 merge**
- **Worktree 1 (main):** Slice 1 Auth (iOS side)
- **Worktree 2 (subagent):** Slice 9 Phase B (refresh token migration + endpoint). Backend work feeds into Slice 1's auth service. Must merge S9-B before S1 finishes.

**Phase C — After Slice 1 merge (big fan-out)**
- **Worktree 1 (main):** Slice 2 Dashboard + Offline — the main-agent keeps this because it touches SwiftData schema, which is foundational for all other feature slices.
- **Worktree 2 (subagent, Opus):** Slice 3 Scan & Meal — isolated to `Features/Scan/` + `Features/Meals/`
- **Worktree 3 (subagent, Opus):** Slice 5 Profile + TDEE — isolated to `Features/Profile/`
- **Worktree 4 (subagent, Opus):** Slice 6 Programs + Exercises — isolated to `Features/Workouts/` + `Features/Exercises/`

Four worktrees run simultaneously. I merge them in whichever order they finish, rebasing the others onto main after each merge. The SwiftData schema in S2 is the only shared surface — I publish the schema contract in `Core/Persistence/Schema.swift` once, then each subagent extends it only for their own models.

**Phase D — After Phase C merges**
- **Worktree 1 (main):** Slice 4 Meal Plan + Shopping (depends on S3's MealService)
- **Worktree 2 (subagent):** Slice 7 Workout Session (depends on S6's program data)
- **Worktree 3 (subagent):** Slice 9 Phase C (rate limits + shared httpx — keep this trickling)

**Phase E — After S7 merge**
- **Worktree 1 (main):** Slice 8 History
- **Worktree 2 (subagent):** Slice 10 Admin Portal — admin-web is a fully independent Next.js project, zero Swift conflict

**Phase F — Launch**
- **Worktree 1 (main):** Slice 11 Polish + TestFlight — final, no parallelism; too many cross-file localization edits and metadata touches

### Subagent dispatch pattern (copy-paste)

When I spawn a slice to a subagent I follow this template:

```
Agent(
  description: "Slice N — <feature name>",
  subagent_type: "general-purpose",
  isolation: "worktree",
  model: "opus",
  prompt: """
    Read plans/slice-NN-name.md and execute tasks N.1 through N.K in order.
    SPEC: /Users/.../03-Nutrition-Tracker/SPEC.md
    Base branch: main at commit <sha>
    Constraints:
      - TDD: every task starts with a failing Swift Test (or pytest for backend)
      - Invoke the skills listed in the task header before writing any code
      - Use xcodegen — never hand-edit the .xcodeproj
      - Run `xcodebuild test` after each task, paste output in task log
      - Do NOT touch files outside Features/<YourFeature>/ + Core/Persistence/Schema.swift's registered models
      - If you discover a blocker outside scope, stop and report
    When done: commit each task as its own commit, push branch, report the task log.
  """,
  run_in_background: true
)
```

I then periodically check on each worktree with `Agent` messages or `TaskOutput` (when background agent finishes it notifies me). When all report complete, I rebase each worktree onto current `main`, run `/review`, merge in finish order.

### Merge conflict protocol

1. `Core/Persistence/Schema.swift` — only the main agent edits this. Subagents request new `@Model` additions via their task log; I add them and they rebase.
2. `Core/Networking/DTO.swift` — same rule: main agent owns, subagents request.
3. `FitTrackerApp.swift` (@main) — same rule.
4. `Info.plist` — additive only; conflicts are trivially resolved manually.
5. Everything else is partitioned by feature folder — conflicts nearly impossible.

### When NOT to parallelize

- Slice 0 Foundation — too much shared structural code; one agent must own it
- Slice 0.5 Mockup — is itself a gate; branching would cause rework
- Slice 1 Auth — touches `AppRoot` and every service constructor; serial
- Slice 7 Workout Session — ActivityKit + CoreHaptics + HealthKit all in same feature, too interdependent to split
- Slice 11 Polish — too many cross-file localization touches

---

## 5. Skill Index — Which Slices Use Which Skills

Cross-reference. Skills from `~/.claude/skills/` (global) plus relevant plugin skills.

| Skill | Slice(s) | Why |
|---|---|---|
| `spec-driven-development` | — | Already done (SPEC.md) |
| `planning-and-task-breakdown` | — | In progress (this doc) |
| `incremental-implementation` | all | Every slice is a vertical slice |
| `test-driven-development` | all | RED-GREEN-REFACTOR on every task |
| `source-driven-development` | 1, 2, 3, 6, 7 | Framework features (SIWA, HealthKit, VisionKit, ActivityKit, AVKit) need doc verification |
| `api-and-interface-design` | 0, 1, 9, 10 | Defining new APIs |
| `security-and-hardening` | 1, 3, 7, 9, 10, 11 | Auth, camera perms, notifications, rate limits, admin, App Store privacy |
| `performance-optimization` | 2, 6, 7, 8, 9 | Offline cache, exercise DB scrolling, timer, history charts, N+1 fix |
| `frontend-ui-engineering` | 10 | Admin web Next.js |
| `browser-testing-with-devtools` | 10 | Admin web E2E |
| `debugging-and-error-recovery` | all | Reactive — invoke when something breaks |
| `code-review-and-quality` | all | Before every merge |
| `code-simplification` | all | Any time code grows too complex |
| `git-workflow-and-versioning` | all | Commit discipline |
| `ci-cd-and-automation` | 11 | Fastlane + TestFlight upload |
| `documentation-and-adrs` | 0, 1, 9, 10, 11 | Architecture decisions |
| `shipping-and-launch` | 11 | Final checklist |
| `everything-claude-code:liquid-glass-design` | 0, 0.5, all UI slices | Theme implementation |
| `everything-claude-code:swiftui-patterns` | 0, 0.5, 2–8 | All SwiftUI views |
| `everything-claude-code:swift-concurrency-6-2` | 0, 2, 7 | Strict concurrency |
| `everything-claude-code:swift-actor-persistence` | 2 | SwiftData + actor isolation |
| `everything-claude-code:swift-protocol-di-testing` | 0, all service work | Protocol-based DI |
| `everything-claude-code:claude-api` | 3 | Claude Vision food recognition |
| `everything-claude-code:postgres-patterns` | 9 | N+1 fix, query optimization |
| `everything-claude-code:database-migrations` | 9 | Refresh token + role migrations |
| `everything-claude-code:e2e-testing` | 10 | Playwright admin smoke |
| `everything-claude-code:healthcare-phi-compliance` | 3, 7, 11 | HealthKit + App Store privacy rules |
| `ux-design:ios-hig-design` | 0, 0.5, all UI slices | Apple HIG compliance |
| `ux-design:refactoring-ui` | 0.5 | Design review after mockup |
| `code-craftsmanship:clean-code` | all | Review gate |
| `systems-architecture:clean-architecture` | 0 | Layered architecture |

---

## 6. Time Estimates

| Slice | Optimistic | Realistic | Risk factor |
|---|---|---|---|
| 0 Foundation | 6h | 10h | xcodegen setup frictions |
| 0.5 Mockup | 8h | 14h | 14 screens × 2 themes |
| 1 Auth (iOS + backend) | 10h | 16h | Apple ID integration, refresh flow |
| 2 Dashboard + Offline | 12h | 20h | SwiftData learning curve |
| 3 Scan + Meal | 10h | 16h | VisionKit + camera edge cases |
| 4 Meal Plan + Shop | 8h | 12h | SwiftUI DnD |
| 5 Profile + TDEE | 5h | 8h | Mostly forms |
| 6 Programs + Exercises | 8h | 12h | AVKit videos, lazy loading |
| 7 Session + Timer | 14h | 22h | ActivityKit, HealthKit write, backgrounding |
| 8 History | 6h | 10h | SwiftUI Charts |
| 9 Backend debt (all phases) | 10h | 16h | Migration risk |
| 10 Admin portal | 14h | 22h | Full Next.js app |
| 11 Polish + TestFlight | 12h | 20h | Localization, App Store prep |
| **Total** | **123h** | **198h** | — |

With parallelization, calendar time compresses ~35–40%. Budget 7–10 weeks at 25h/week to complete v1.

---

## 7. Verification Before Every Merge

Each PR runs through this gate before merging to `main`:

```bash
# iOS
cd ios
xcodegen
xcodebuild -scheme FitTracker \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test

# Backend
cd backend
DATABASE_URL="postgresql+asyncpg://postgres:postgres@localhost:5433/fit_db_test" \
  uv run pytest tests/ -v

# Web (regression check)
cd frontend && pnpm test && pnpm lint

# Admin (Slice 10+)
cd admin-web && pnpm test

# /review skill
```

Plus a manual pass:
- [ ] Skill log visible in PR description (which skills were invoked per task)
- [ ] At least one screenshot per new iOS view, both themes
- [ ] Acceptance criteria checkboxes all ticked in the slice plan

---

## 8. Risk Register (cross-slice)

| Risk | Slice(s) impacted | Mitigation |
|---|---|---|
| iOS 26 API drift before we ship | all | Pin Xcode version in CI, use `#available` guards if bugs appear |
| xcodegen breaks on Xcode update | 0, every rebuild | Commit a working `FitTracker.xcodeproj` snapshot to unblock if needed |
| Apple ID auth flakiness on Simulator | 1 | Test on real device early |
| HealthKit simulator support gaps | 2, 3, 7 | Test on real device; feature-flag write paths for simulator fallback |
| SwiftData schema changes force migration | 2, 3, 4, 6 | Freeze Schema.swift before Phase C fan-out; document via ADR |
| Claude Vision API cost spike | 3, 11 | Per-user daily cap, cache results in `products` table |
| Apple privacy manifest updates break submission | 11 | Check Apple's required-reason API list monthly |
| Admin portal role escalation bug | 10 | `security-reviewer` subagent audit mandatory before merge |
| Localization strings regress to hardcoded | 11 | Lint rule: fail build if any Swift file contains a non-key literal in a `Text()` |

---

## 9. Slice Files

Open in order or jump to one:

- [Slice 0 — Foundation & Scaffold](slice-00-foundation.md)
- [Slice 0.5 — Mockup Tap-Through Prototype](slice-005-mockup.md)
- [Slice 1 — Auth (Email + Apple ID + Refresh)](slice-01-auth.md)
- [Slice 2 — Dashboard + Offline Cache](slice-02-dashboard.md)
- [Slice 3 — Scan & Log Meal](slice-03-scan-meal.md)
- [Slice 4 — Meal Plan + Shopping List](slice-04-meal-plan.md)
- [Slice 5 — Profile + TDEE + Goals](slice-05-profile-tdee.md)
- [Slice 6 — Programs + Exercise DB](slice-06-programs-exercises.md)
- [Slice 7 — Workout Session + Rest Timer](slice-07-workout-session.md)
- [Slice 8 — History + Analytics](slice-08-history-analytics.md)
- [Slice 9 — Backend Tech Debt + Refresh + Roles](slice-09-backend-debt.md)
- [Slice 10 — Admin Portal (`admin-web/`)](slice-10-admin-portal.md)
- [Slice 11 — Polish + TestFlight Submission](slice-11-testflight.md)
