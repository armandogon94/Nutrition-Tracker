# ADR-0004: SwiftData Schema, Cascade Rules, and Sync Strategy

- **Date:** 2026-04-26
- **Status:** Accepted
- **Deciders:** Armando Gonzalez
- **Related:** [SPEC.md](../../SPEC.md) §3 (architecture), [plans/slice-02-dashboard.md](../../plans/slice-02-dashboard.md) Task 2.1

## Context

The iOS client needs a local store so the app:

1. Renders the dashboard, meals list, exercise browser, and history offline (within minutes of last sync)
2. Lets the user log a meal or workout while disconnected and flushes the writes when connectivity returns
3. Avoids hammering the backend on every screen render — the backend is the source of truth, but the local cache is the read source

We considered SQLite via GRDB, Core Data, and SwiftData. SwiftData was chosen for the v1 scope because it ships with iOS 26, integrates natively with SwiftUI's `@Query`, requires zero schema-management code in 95% of cases, and stays current with Apple's evolving Swift Concurrency story. GRDB would offer more SQL control but at the cost of a learning curve and more boilerplate; we'll revisit if SwiftData performance disappoints in Slice 8 (history charts).

This ADR locks the schema invariants, cascade rules, and sync flag conventions that all feature slices must respect. The Schema.swift file is owned by the **main agent only** during Phase C parallel execution — subagents extend it via coordinated requests (per [plans/000-OVERVIEW.md §4](../../plans/000-OVERVIEW.md)).

## Decisions

### 1. Two-shape model: Sendable struct + @Model class

| Layer | Type | File |
|---|---|---|
| Transport (DTO, mock, view binding) | Plain `Sendable` struct | `Models/Models.swift` |
| Persistence (SwiftData) | `@Model final class` | `Core/Persistence/Schema.swift` |

**Rationale:** SwiftData @Model classes are reference types and not `Sendable`. Crossing actor boundaries with them is hostile. Keeping mocks + DTOs as plain structs lets MockServiceContainer keep working from previews, and lets URLSession decoding land in immutable structs first. A small `Mappers.swift` converts struct ↔ @Model when needed.

### 2. Versioned schema from day 1

Every model is registered through a `VersionedSchema` (`FitTrackerSchemaV1`). The `ModelContainer` is built with a `SchemaMigrationPlan` that today has only V1, but the structure is in place so adding V2 in Slice 4/5/6 doesn't require a destructive migration.

### 3. ID strategy

- Server-assigned UUIDs are the persistent identifier (`@Attribute(.unique) var id: UUID`)
- Local-first writes (offline meal log, etc.) generate a client-side UUID and set `pendingSync: true`. The backend response replaces the ID **only if** it returns a different one — otherwise the local UUID becomes the canonical id permanently. This avoids "ghost row" duplication after sync.

### 4. Sync flags on every persisted entity

```swift
@Attribute var pendingSync: Bool   // true = local write not yet flushed
@Attribute var lastSyncedAt: Date?
```

Slice 2.2 SyncManager consults these to drive its OfflineQueue.

### 5. Cascade rules

| Parent → Child | Delete rule | Why |
|---|---|---|
| Meal → MealItem | `.cascade` | items are fully owned by the meal |
| WorkoutSession → WorkoutSet | `.cascade` | sets are fully owned by the session |
| WorkoutProgram → WorkoutProgramDay → WorkoutProgramExerciseSpec | `.cascade` | days + specs are program-owned |
| MealPlan → MealPlanItem | `.cascade` | items belong to the plan |
| ShoppingList → ShoppingListItem | `.cascade` | items belong to the list |
| MealItem → Product | `.nullify` | product is a shared catalog entry; deleting a product orphans `productId` to nil but keeps the meal item's frozen nutrition snapshot |
| WorkoutSet → Exercise | `.nullify` | exercise catalog is shared; nullify keeps historical weight + reps even if the exercise is later deleted in admin |
| User → all user-scoped data | `.cascade` | account deletion (Slice 11) wipes everything for that user |

### 6. Frozen vs. live nutrition

`MealItem` snapshots calories/protein/carbs/fat at the moment of logging. If the underlying `Product` is later corrected by an admin, historical meals do **not** retroactively change — that would break weekly reports. Live product data is fetched separately for new meals.

### 7. Indexes (SwiftData `@Attribute(.unique)`)

- `User.email`
- `User.appleUserId` (nullable)
- `Product.barcode` (nullable but unique when present)
- `Exercise.name` (case-insensitive search)

Other lookups rely on `@Relationship` traversal.

### 8. Schema ownership during parallel slices

Phase C runs Slices 2, 3, 5, 6 simultaneously. They all read Schema.swift but only the **main agent** (Slice 2) edits it. If a subagent needs a new entity or column it stops, posts a request in its task log, and the main agent adds it on `slice/02-dashboard`. Subagents then rebase. This rule is the single point of serialization in an otherwise parallel phase.

## Consequences

### Positive
- Offline-first dashboard from Slice 2.4 onward
- Account deletion (Slice 11) becomes a one-row `DELETE` cascading
- No N+1 fetches in views — `@Query` materializes related data lazily
- Versioned schema means future column additions ship without `WHERE 1=0` shims

### Negative
- SwiftData has fewer escape hatches than raw SQLite — if we hit a perf wall we may need to wrap with FTS5 or accept the limitation
- Two-shape model (struct + @Model) doubles boilerplate; mitigated by the Mappers.swift convention

### Neutral
- Schema.swift becomes a coordination point. We accept this as a feature of Phase C, not a bug.

## Follow-ups

- ADR-0005 (Slice 6) — exercise video playback (YouTube vs AVKit)
- SyncManager + OfflineQueue (Slice 2.2)
- Snapshot tests for the v1 schema before any v2 changes land
