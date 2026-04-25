# ADR-0001: Three-Client Architecture (iOS + User Web + Admin Web)

- **Date:** 2026-04-23
- **Status:** Accepted
- **Deciders:** Armando Gonzalez
- **Related:** [SPEC.md](../../SPEC.md) §3, [plans/000-OVERVIEW.md](../../plans/000-OVERVIEW.md)

## Context and Problem Statement

FitTracker v2.1 shipped as a single Next.js 14 web app backed by a FastAPI + PostgreSQL backend. Moving forward we want:

1. A native iOS 26 app as the **primary** consumer surface (better camera/health/notification integration, mobile-first audience)
2. The existing web app kept operational for desktop users and as a fallback
3. A new backoffice tool for admin tasks (user moderation, product/exercise curation, metrics) that should never ship to end users

The question is how to partition these surfaces. The 4 main options we considered:

- **A.** One Next.js app with role-gated admin routes (status quo + flag)
- **B.** Two Next.js apps (user + admin), one iOS app, single backend
- **C.** One Next.js app + iOS client + separate server-rendered admin (Django admin style)
- **D.** Rewrite as a single cross-platform app (React Native / Expo / Tauri)

## Decision Drivers

- Minimize App Store attack surface — fewer roles shipped on iOS = easier review
- Allow admin deploys without risking consumer availability
- Keep backend contract stable across all clients (no client-specific endpoint drift)
- Personal/family scale today; shouldn't pay enterprise complexity tax
- Must reuse the existing FastAPI backend with minimal structural changes

## Considered Options

### A. Single Next.js with role-gated admin routes
**Pros:** Zero new infra. Reuses existing auth + routing. Fastest to ship.
**Cons:** Admin bundle ships to every user's browser (even if gated). Any admin UI bug affects consumer app. Deploys are all-or-nothing.

### B. Two Next.js apps + iOS + single FastAPI backend (chosen)
**Pros:** Clean separation, small admin bundle, independent deploy cadence, admin never exposed to consumers, iOS stays slim. Backend gains `/api/v1/admin/*` + `require_admin` dep — one surface change.
**Cons:** +1 Docker service, +1 Traefik rule, +1 deploy artifact. Some duplicated Tailwind config between `frontend/` and `admin-web/`.

### C. Separate server-rendered admin (Django admin)
**Pros:** Very fast to scaffold via Django/FastAPI-admin.
**Cons:** Adds a new framework (Django) to the stack; inconsistent with Next.js patterns; limited custom UI for merge/curation flows.

### D. Cross-platform rewrite
**Pros:** One codebase for web + iOS.
**Cons:** Throws away working v2.1 web + kills native iOS quality bar (HealthKit, Live Activity, CoreHaptics, VisionKit). Not compatible with the "iOS primary, native feel" success criterion.

## Decision Outcome

**Chosen: B.** Three clients (iOS + existing user web + new `admin-web`), one FastAPI backend.

Reasoning: the marginal cost of a second Next.js app (`admin-web/`) is ~1 day of scaffolding, and the benefits compound: smaller iOS review surface, independent admin deploys, and a clean `require_admin` gate on the backend that's easy to audit.

## Consequences

### Positive
- iOS target surface is consumer-only; App Store review has less to scrutinize
- Admin changes deploy without affecting end-user availability
- `admin-web/` can optimize for data density without polluting consumer UX
- Clear responsibility per repo area: `ios/` → mobile UX, `frontend/` → web UX, `admin-web/` → backoffice, `backend/` → contract + data

### Negative
- 3 clients to keep in sync with backend DTO changes (mitigated: typed schemas + pytest contract tests)
- Doubled Tailwind/Next.js build surface
- Team (currently 1 person) must switch context across 3 client stacks
- Docker Compose grows one service; Traefik gets one more subdomain

### Neutral
- Backend remains the single source of truth — any client can catch up later
- Post-v1, a fourth client (e.g., Apple Watch, Android) can slot in without architectural change

## Follow-ups

- [ADR-0002](0002-theme-system.md) — theme system for iOS
- [ADR-0007](0007-admin-portal-split.md) — (Slice 10) details of the admin split
- Contract tests between iOS DTOs and backend Pydantic schemas (Slice 9 Phase C)
