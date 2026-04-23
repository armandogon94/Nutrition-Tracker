# Slice 8 — History + Analytics

**Branch:** `slice/08-history-analytics`
**Estimate:** 10h realistic (6h optimistic, 14h if charts need custom interaction)
**Owner:** Main agent during Phase E (concurrent with Slice 10 admin portal by subagent)

---

## Dependencies

- **Slice 7 merged** (sessions + sets data exists to visualize)
- **Slice 9 Phase A** preferably merged (N+1 fix lands here too so history endpoint is fast)

## Parallelizable peers

- **Slice 10** (admin portal) — completely independent web app, subagent worktree

## Objective

Ship the workout history experience: calendar of completed workouts, volume trends by muscle group, PR list, CSV export — all powered by SwiftUI Charts.

## Acceptance criteria

- [ ] HistoryView calendar shows dots on workout days; tap day → list of sessions
- [ ] Session detail shows exercises + sets with weight progression
- [ ] Volume chart: bar per week for last 12 weeks, colored by muscle group
- [ ] PR list: sortable by exercise, shows weight + date + reps
- [ ] CSV export → Share Sheet hands off file (`.csv`) compatible with Numbers/Sheets
- [ ] All 8 new Swift tests pass
- [ ] Chart scroll smooth at 60fps with 52 weeks of data

## Skills to invoke

1. `source-driven-development` — SwiftUI Charts API (Context7 MCP)
2. `api-and-interface-design` — `HistoryService`
3. `everything-claude-code:swiftui-patterns` — calendar layout, charts, share sheet
4. `performance-optimization` — lazy loading, chart data aggregation
5. `everything-claude-code:swift-actor-persistence` — read cached sessions
6. `test-driven-development`
7. `everything-claude-code:liquid-glass-design` + `ux-design:ios-hig-design`

---

## Tasks

### Task 8.1 — `HistoryService` + aggregation logic

**Skills:** `api-and-interface-design`, `test-driven-development`, `performance-optimization`

**RED tests:**
```swift
@Test func volumeByWeek_aggregatesAcrossSessions() async throws { ... }
@Test func volumeByMuscle_primaryOnly() async throws { ... }
@Test func prsByExercise_returnsLatestMaxPerExercise() async throws { ... }
```

**Files:**
- `Core/Services/HistoryService.swift` — `sessions(in: DateInterval)`, `volumeByWeek(weeks: Int)`, `volumeByMuscle(weeks: Int)`, `prs()`
- Aggregation is SwiftData-local (fast) — no need to hit backend every scroll

**Data shape:** volume = sum(weight × reps) per muscle per week.

**Est:** 2.5h

---

### Task 8.2 — `HistoryCalendarView`

**Skills:** `everything-claude-code:swiftui-patterns`, `ux-design:ios-hig-design`

**Files:**
- `Features/History/HistoryView.swift` — top: calendar grid; bottom: selected day's sessions list
- `Features/History/CalendarGrid.swift` — custom 7-col grid; dot on days with a session, color by program type

**Est:** 2h

---

### Task 8.3 — `SessionDetailView`

**Files:**
- `Features/History/SessionDetailView.swift` — list of exercises; each exercise expands to show sets table
- Tap exercise → shows weight-progression sparkline of all past sessions with that exercise

**Est:** 1.5h

---

### Task 8.4 — `VolumeChartView` with SwiftUI Charts

**Skills:** `source-driven-development`, `everything-claude-code:swiftui-patterns`

**Files:**
- `Features/History/VolumeChartView.swift` — stacked `BarMark` per week, `foregroundStyle` by muscle group
- Interaction: tap a bar → sheet showing the sessions in that week

**Est:** 2h

---

### Task 8.5 — `PRListView`

**Files:**
- `Features/History/PRListView.swift` — sorted list with exercise name, weight, reps, date. Sort toggle: by date / by weight / by exercise name.

**Est:** 1h

---

### Task 8.6 — CSV export

**Skills:** `everything-claude-code:swiftui-patterns`, `security-and-hardening`

**Files:**
- `Core/Export/CSVExporter.swift` — produces a `.csv` string/URL from sessions
- `HistoryView` toolbar "Export" button → `ShareLink(item: csvURL)`

**Columns:** `date, program, exercise, set_number, weight_kg, reps, is_pr, duration_minutes`

**Privacy:** user's data only — never include user_id or any identity field.

**Est:** 1h

---

## Parallelization strategy

Main agent does Slice 8 while Opus subagent runs Slice 10:

```
Agent(description: "Slice 10 — Admin Portal (admin-web)",
      isolation: "worktree", model: "opus",
      prompt: "Read plans/slice-10-admin-portal.md and execute. Scope: admin-web/ directory only (new Next.js app). Do NOT touch backend or iOS. Backend admin endpoints should already be live after Slice 9 Phase C.")
```

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| Charts lag with 52 weeks × 10 muscles | Pre-aggregate in `HistoryService` via one SwiftData query; chart reads from immutable struct |
| Calendar renders all 365 days eagerly | `LazyVGrid` + month-at-a-time rendering |
| CSV escaping edge cases (commas in names) | Use RFC 4180 quoting; single unit test covers edge cases |
| History endpoint N+1 slowness | Slice 9 Phase A already fixed; verify still green |
| PR query performance at 1k sessions | SwiftData index on `exerciseId`; covered by Schema |

## Verification before merge

```bash
cd ios && xcodebuild test
# Manual:
# - Generate 10 workouts across 4 weeks (via testing seed or manual)
# - Calendar shows 10 dots
# - Volume chart renders with correct muscle colors
# - PR list accurate
# - Export CSV → open in Numbers → data intact
```

Screenshots:
- [ ] HistoryView calendar both themes
- [ ] Volume chart both themes
- [ ] PR list both themes

## Post-merge

Tag `slice-08-complete`.
