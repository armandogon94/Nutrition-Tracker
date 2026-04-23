# Slice 9 — Backend Tech Debt + Refresh Tokens + Role-Based Access

**Branch:** split into 3 phases (each its own branch):
- `slice/09-phase-A-debt` — `datetime` sweep + N+1 fix (can start day 1)
- `slice/09-phase-B-auth` — refresh tokens + Apple signin + logout + `users.role` + `apple_user_id` (must land before Slice 1)
- `slice/09-phase-C-debt` — rate limits + shared httpx + `require_admin` dep + token expiry tests (must land before Slice 10)

**Estimate:** 16h realistic total (6h phase A, 6h phase B, 4h phase C)
**Owner:** Opus subagents in dedicated backend worktree, main agent merges

---

## Dependencies

- Phase A: none — **starts day 1** alongside Slice 0
- Phase B: Phase A merged (or skipped if no conflict)
- Phase C: Phase B merged

## Parallelizable peers

- All iOS slices (zero file overlap with backend)

## Objective

Retire the 6 pieces of tech debt listed in the project scratchpad + add the backend primitives that both iOS (Slice 1) and the admin portal (Slice 10) need.

From `.claude/scratchpad.md`:

1. `datetime.utcnow()` deprecated (30+ occurrences)
2. N+1 queries in workout history endpoint
3. No rate limiting on `/auth/*` and `/products/*`
4. No token revocation mechanism (24h expiry only)
5. `httpx.AsyncClient` created per-request in product search
6. No IDOR cross-user tests — already added Apr 4; verify; add token-expiration backend test

Additions:
7. Refresh token rotation
8. Apple identity token verification endpoint
9. `users.role` column + `require_admin` dependency

## Acceptance criteria (combined across phases)

- [ ] Zero `datetime.utcnow()` in backend source; lint rule blocks future use
- [ ] Workout history endpoint: one SELECT + JOIN, not N+1 per session
- [ ] `/auth/login` 429s after 5 requests/minute/IP; `/auth/register` after 3/min
- [ ] `/products/search` 429s after 60 requests/minute/user
- [ ] `refresh_tokens` table: token_hash, user_id, expires_at, revoked_at, created_at
- [ ] `/api/v1/auth/refresh` endpoint works; rotates token on use
- [ ] `/api/v1/auth/apple` verifies Apple JWT, creates/links user
- [ ] `/api/v1/auth/logout` revokes refresh token
- [ ] `users.role` enum: 'user' or 'admin'; migration + seed `role=admin` for armando@armandointeligencia.com
- [ ] `users.apple_user_id` nullable unique column
- [ ] `require_admin` FastAPI dependency on every `/api/v1/admin/*` route (defined in Slice 10)
- [ ] Shared `httpx.AsyncClient` app-scoped singleton used everywhere
- [ ] `test_auth_refresh.py`, `test_auth_apple.py`, `test_auth_rate_limit.py`, `test_token_expiry.py` pass
- [ ] All 95 existing tests still pass (no regressions)
- [ ] New tests bring total to ~115

## Skills to invoke

1. `api-and-interface-design` — new endpoints, refresh flow
2. `security-and-hardening` — JWT rotation, rate limits, Apple JWK
3. `everything-claude-code:database-migrations` — Alembic migrations
4. `everything-claude-code:postgres-patterns` — N+1 fix with `selectinload`
5. `test-driven-development` — RED tests for every new endpoint
6. `performance-optimization` — shared httpx, query optimization
7. `documentation-and-adrs` — ADR-0003 refresh strategy (also in Slice 1 ADR section)
8. `code-review-and-quality` — before each phase merges
9. `git-workflow-and-versioning` — three phases, three merges

---

## Phase A Tasks (can run Day 1 in parallel with Slice 0)

### Task 9.1 — `datetime.utcnow()` sweep + lint rule

**Skills:** `code-review-and-quality`, `test-driven-development`

**RED check:** run `rg "datetime.utcnow\(\)"` → must be >0 before, 0 after

**Files changed:** ~30 source files across `backend/app/`

**Implementation:**
- Global find/replace `datetime.utcnow()` → `datetime.now(timezone.utc)`
- Ensure `from datetime import timezone` import added where missing
- Add Ruff rule in `pyproject.toml` to block `datetime.utcnow`:
```toml
[tool.ruff.lint]
# Block datetime.utcnow (it's deprecated in Python 3.12+)
banned-api = ["datetime.datetime.utcnow"]
```

**Acceptance:** all 95 existing tests still pass.

**Est:** 2h

---

### Task 9.2 — Fix N+1 in workout history endpoint

**Skills:** `everything-claude-code:postgres-patterns`, `performance-optimization`

**File:** `backend/app/api/v1/workouts.py` — `GET /api/v1/workouts/history` handler

**Before:** loops over sessions, fires per-session query for sets + exercises

**After:** single query with `selectinload(WorkoutSession.sets).selectinload(WorkoutSet.exercise)` and `selectinload(WorkoutSession.program_day)`

**RED test:** add `test_workouts.py::test_history_uses_single_query` using `sqlalchemy.event` to count queries

**Acceptance:** query count for 20 sessions drops from 40+ to ≤3.

**Est:** 2h

---

### Task 9.3 — Verify IDOR tests + add token expiry test

**Skills:** `security-and-hardening`, `test-driven-development`

**Files:**
- `tests/test_token_expiry.py` — craft JWT with `exp` in past, assert 401 on protected endpoints

**Acceptance:** test passes; 95 → 96 total tests.

**Est:** 1h

---

## Phase B Tasks (must land before Slice 1 iOS work depends on endpoints)

### Task 9.4 — Migration: `refresh_tokens` + `users.role` + `users.apple_user_id`

**Skills:** `everything-claude-code:database-migrations`, `api-and-interface-design`

**Files:**
- `backend/alembic/versions/YYYYMMDD_refresh_tokens_and_role.py`

**Schema:**
```sql
CREATE TABLE refresh_tokens (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash VARCHAR(255) NOT NULL UNIQUE,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    revoked_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT (NOW() AT TIME ZONE 'UTC')
);
CREATE INDEX idx_refresh_tokens_user ON refresh_tokens(user_id);
CREATE INDEX idx_refresh_tokens_hash ON refresh_tokens(token_hash);

ALTER TABLE users
  ADD COLUMN role VARCHAR(20) NOT NULL DEFAULT 'user' CHECK (role IN ('user', 'admin')),
  ADD COLUMN apple_user_id VARCHAR(255) UNIQUE;

CREATE INDEX idx_users_apple ON users(apple_user_id) WHERE apple_user_id IS NOT NULL;
```

**Models:**
- `backend/app/models/refresh_token.py` — RefreshToken model
- `backend/app/models/user.py` — add `role`, `apple_user_id` columns

**Acceptance:** migration applies cleanly up+down on test DB.

**Est:** 1.5h

---

### Task 9.5 — `/api/v1/auth/refresh` endpoint

**Skills:** `api-and-interface-design`, `security-and-hardening`, `test-driven-development`

**RED tests** (in `tests/test_auth_refresh.py`):
- happy path: valid refresh → new access + new refresh, old refresh now revoked
- expired refresh → 401
- revoked refresh → 401
- concurrent refreshes with same token → one succeeds, other 401 (detects token theft)

**Files:**
- `backend/app/api/v1/auth.py` — add `POST /refresh`
- `backend/app/core/security.py` — `create_refresh_token`, `verify_refresh_token`, `rotate_refresh_token` helpers
- `backend/app/schemas/auth.py` — `RefreshRequest`, `RefreshResponse`

**Access token expiry reduced to 1 hour** (from 24h). Refresh token expiry 30 days.

**Acceptance:** 4 tests pass.

**Est:** 2h

---

### Task 9.6 — `/api/v1/auth/apple` endpoint

**Skills:** `security-and-hardening`, `source-driven-development` (Apple JWK docs)

**RED tests** (in `tests/test_auth_apple.py`):
- happy path with stub JWK: creates user, returns tokens
- second signin with same user_identifier: reuses existing user
- bad signature → 401
- expired token → 401
- wrong audience → 401

**Files:**
- `backend/app/api/v1/auth.py` — add `POST /auth/apple`
- `backend/app/services/apple_verifier.py` — fetches Apple JWK (cached 1h), verifies token using PyJWT
- `backend/app/schemas/auth.py` — `AppleSigninRequest { identity_token, user_identifier, email?, full_name? }`

**Acceptance:** 5 tests pass.

**Est:** 2h

---

### Task 9.7 — `/api/v1/auth/logout` endpoint

**Files:** `backend/app/api/v1/auth.py` — `POST /logout` revokes the active refresh token for the requesting user

**Test:** logout → subsequent `/refresh` returns 401.

**Est:** 0.5h

---

## Phase C Tasks (before Slice 10 admin portal; can run during Slice 4/7)

### Task 9.8 — slowapi rate limits

**Skills:** `security-and-hardening`, `api-and-interface-design`

**Files:**
- `backend/app/core/rate_limit.py` — Limiter instance, key function (IP for anon, user_id for authed)
- `backend/app/main.py` — register SlowAPIMiddleware
- Apply `@limiter.limit(...)` to:
  - `/auth/login`: 5/minute
  - `/auth/register`: 3/minute
  - `/auth/refresh`: 10/minute
  - `/auth/apple`: 5/minute
  - `/products/search`: 60/minute (authed, per user)
  - `/products/{barcode}`: 120/minute

**RED test:** `tests/test_auth_rate_limit.py::test_login_rate_limited` — 6th request returns 429.

**Est:** 2h

---

### Task 9.9 — Shared `httpx.AsyncClient`

**Skills:** `performance-optimization`, `api-and-interface-design`

**Files:**
- `backend/app/core/http.py` — app-scoped `AsyncClient` instance via FastAPI lifespan
- `backend/app/main.py` — `@asynccontextmanager async def lifespan(app)` creates client, yields, closes
- Update `product_lookup.py`, `food_recognition.py` to inject shared client instead of creating own

**Acceptance:** perf test or log analysis shows client reused across requests; no per-request TCP handshakes.

**Est:** 1h

---

### Task 9.10 — `require_admin` dependency

**Skills:** `security-and-hardening`, `api-and-interface-design`

**Files:**
- `backend/app/core/deps.py` — `require_admin` FastAPI dependency that checks `user.role == 'admin'`, else 403
- Document usage: every `/api/v1/admin/*` route declares `Depends(require_admin)`. Applied throughout Slice 10.
- Seed: `backend/seed_test_accounts.py` — add `role='admin'` to armando@armandointeligencia.com if not present

**RED test:**
- `tests/test_admin_access.py::test_non_admin_gets_403_on_admin_route` (once Slice 10 adds a route)
- for now: `test_require_admin_dependency_raises_for_user_role`

**Est:** 1h

---

## Parallelization strategy

All three phases dispatched as Opus subagents in a dedicated backend worktree:

```
# Phase A — dispatch DAY 1 (alongside Slice 0)
Agent(description: "Slice 9 Phase A: datetime sweep + N+1 + expiry test",
      isolation: "worktree", model: "opus",
      prompt: "Read plans/slice-09-backend-debt.md Phase A. Execute tasks 9.1, 9.2, 9.3. Branch slice/09-phase-A-debt. Run full pytest after each. Report.",
      run_in_background: true)

# Phase B — dispatch when Slice 0 completes (main agent is beginning Slice 1)
Agent(description: "Slice 9 Phase B: refresh tokens + apple signin + role",
      isolation: "worktree", model: "opus",
      prompt: "Read plans/slice-09-backend-debt.md Phase B. Execute tasks 9.4-9.7. Branch slice/09-phase-B-auth. Must complete before Slice 1 finishes.",
      run_in_background: true)

# Phase C — dispatch during Slice 4/7
Agent(description: "Slice 9 Phase C: rate limits + shared httpx + admin dep",
      isolation: "worktree", model: "opus",
      prompt: "Read plans/slice-09-backend-debt.md Phase C. Execute tasks 9.8, 9.9, 9.10. Branch slice/09-phase-C-debt. Must complete before Slice 10.",
      run_in_background: true)
```

### Main agent merge responsibilities

For each phase as it reports done:
1. Pull branch, run FULL backend pytest (must be green; phase fails on any regression)
2. Invoke `security-reviewer` agent on the diff (Phase B especially — auth is sensitive)
3. Run iOS test suite against the new backend (Phase B affects AuthService)
4. Merge with squash preserving task commits
5. Tag `slice-9-phase-A-complete` / `-B-` / `-C-`
6. Rebase any open iOS slice branches onto new main

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| Alembic migration conflicts with another dev's migration | Only one migration at a time; `alembic upgrade head` verified in CI-like local loop |
| Refresh token race produces double refresh | Serialized per user via DB `SELECT … FOR UPDATE` on token row |
| Apple JWK endpoint down | Cache for 24h; serve stale on fetch failure with warning log |
| Rate limiter uses wrong key (IP for authed) | Key function checks auth first, falls back to IP; test both paths |
| `datetime.utcnow()` sweep introduces tz bugs in old test fixtures | Fix fixtures in same PR; expect 10-15 test minor edits |
| `users.role` migration on populated prod DB | Column default 'user'; safe; armando@ manually set via seed |
| Shared `httpx.AsyncClient` lifecycle with pytest | `conftest.py` fixture manages lifespan; isolated per test session |
| Apple email-relay users later want to delete account | Standard deletion flow works; refresh tokens cascade-delete |

## Verification before each phase merge

```bash
cd backend
DATABASE_URL="postgresql+asyncpg://postgres:postgres@localhost:5433/fit_db_test" \
  uv run pytest tests/ -v
# All 95+ tests green; each phase adds:
# Phase A: +1 (token expiry)
# Phase B: +10 (refresh + apple + logout)
# Phase C: +5 (rate limits + admin dep)
```

Phase B additional check:
```bash
# iOS tests against new backend still green
cd ios && xcodebuild test
```

## Post-merge

Tag each phase; all three phases close out the backend-side debt.

After Phase C: file `docs/adr/0003-refresh-token-rotation.md` is officially implemented; `docs/adr/0006-admin-role-gate.md` written (decision record for role-based access).
