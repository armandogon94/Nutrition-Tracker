# Slice 10 — Admin Portal (`admin-web/`)

**Branch:** `slice/10-admin-portal`
**Estimate:** 22h realistic (14h optimistic, 30h if admin UX gets ambitious)
**Owner:** Opus subagent in dedicated worktree — completely independent Next.js project

---

## Dependencies

- **Slice 9 Phase B merged** (`users.role`, `apple_user_id`)
- **Slice 9 Phase C merged** (`require_admin` dependency exists)

## Parallelizable peers

- **Slice 8** (iOS History) — zero overlap, main agent owns Slice 8
- **Slice 11 prep** (App Store metadata collection) — can trickle

## Objective

Stand up a separate Next.js 14 backoffice at `admin.fit.armandointeligencia.com` where Armando (and future admins) manage users, curate product + exercise databases, view system metrics, and audit activity.

No consumer features. Optimize for data density, not aesthetics.

## Acceptance criteria

- [ ] `admin-web/` new Next.js 14 App Router project, pnpm, TypeScript, Tailwind
- [ ] `admin-web` service in `docker-compose.yml` exposes port 3004
- [ ] Login page → authenticates via backend → stores admin JWT
- [ ] Non-admin user attempting to log in is rejected with clear message
- [ ] `/users` — search, filter by role, suspend/reactivate, change role, reset password (generates temp password + email via backend)
- [ ] `/products` — search cached products, edit nutrition, merge duplicates (pick winner), delete
- [ ] `/exercises` — list, add new, edit, delete, reorder muscle-group taxonomy
- [ ] `/metrics` — cards for: active users (7d / 30d), requests/min, error rate, DB size, Claude Vision spend
- [ ] `/audit` — append-only log of admin actions (who / what / when / target)
- [ ] Playwright smoke tests cover happy path for each page
- [ ] Backend: 8 new pytest tests for admin endpoints
- [ ] No admin secrets stored client-side beyond session JWT

## Skills to invoke

1. `documentation-and-adrs` — ADR-0007 on admin split (why separate web, not integrated into user web)
2. `api-and-interface-design` — admin API surface
3. `security-and-hardening` — role gate, audit log integrity, CSRF, session hygiene
4. `frontend-ui-engineering` — Next.js app structure (mirror `frontend/` patterns)
5. `everything-claude-code:e2e-testing` — Playwright smoke
6. `browser-testing-with-devtools` — runtime verification
7. `test-driven-development` — RED tests for admin endpoints and Playwright specs
8. `performance-optimization` — tables with pagination, not full-load
9. `code-review-and-quality`
10. `everything-claude-code:postgres-patterns` — efficient metric queries

---

## Tasks

### Task 10.1 — ADR + Next.js scaffold

**Skills:** `documentation-and-adrs`, `frontend-ui-engineering`

**Files:**
- `docs/adr/0007-admin-portal-split.md` — why separate web app (smaller attack surface, separate deploy cadence, different audience)
- `admin-web/` — `pnpm create next-app@14` (App Router, TS, Tailwind, no src dir, no app router experimental)
- `admin-web/package.json` — pin `next@14.2.x`, match frontend versions where possible
- `admin-web/tsconfig.json`, `tailwind.config.ts`, `next.config.js`
- Dockerfile matching `frontend/Dockerfile` pattern
- `admin-web/.env.example` — `NEXT_PUBLIC_API_URL=http://localhost:8001`

**Acceptance:** `pnpm dev` runs on port 3004, shows default Next.js page.

**Est:** 2h

---

### Task 10.2 — Admin auth flow + layout shell

**Skills:** `security-and-hardening`, `frontend-ui-engineering`, `test-driven-development`

**RED test (Playwright):**
```ts
test('non-admin cannot log in', async ({ page }) => { ... })
test('admin logs in → lands on /users', async ({ page }) => { ... })
```

**Files:**
- `admin-web/app/login/page.tsx` — email + password; POSTs to backend `/auth/login`; checks returned `user.role === 'admin'` — if not, signs out and shows "Not authorized"
- `admin-web/lib/api.ts` — copy of `frontend/lib/api.ts` with stricter 403 handling (redirects to /login on any 403)
- `admin-web/lib/auth.ts` — same shape as user web
- `admin-web/app/layout.tsx` — sidebar with links: Users, Products, Exercises, Metrics, Audit, Logout
- `admin-web/components/AdminGuard.tsx` — ensures role admin; redirects to /login if not
- `admin-web/components/Sidebar.tsx`

**Acceptance:** admin@ logs in successfully; user@ rejected.

**Est:** 3h

---

### Task 10.3 — `/users` page + backend endpoints

**Skills:** `api-and-interface-design`, `security-and-hardening`, `test-driven-development`

**Backend RED tests:**
- `test_admin_users.py::test_list_users_requires_admin`
- `test_admin_users.py::test_suspend_user_flags_account`
- `test_admin_users.py::test_change_role_persists`

**Backend routes (`backend/app/api/v1/admin/users.py`):**
- `GET /api/v1/admin/users?q=&role=&page=1` — paginated list
- `PATCH /api/v1/admin/users/{id}/role` — body `{role: 'user'|'admin'}`
- `PATCH /api/v1/admin/users/{id}/suspend` — body `{suspended: bool}`
- `POST /api/v1/admin/users/{id}/reset-password` — generates temp password, returns it (admin emails user out of band)

All gated by `require_admin` dep.

**Migration:** `users.suspended_at` timestamp column (nullable). Suspended users receive 403 on any authed call.

**Frontend:** `admin-web/app/users/page.tsx` — table with search, row actions in kebab menu.

**Acceptance:** Admin can search "carlos" → see row → change role → verify in DB.

**Est:** 4h

---

### Task 10.4 — `/products` page + backend endpoints

**Skills:** `api-and-interface-design`, `frontend-ui-engineering`, `test-driven-development`

**Backend routes:**
- `GET /api/v1/admin/products?q=&source=&page=1`
- `PATCH /api/v1/admin/products/{id}` — edit all fields
- `POST /api/v1/admin/products/merge` — body `{winner_id, loser_ids: [...]}` — updates all `meal_items.product_id` pointing to losers, deletes losers
- `DELETE /api/v1/admin/products/{id}` — cascade deletes via existing FK

**Frontend:** `admin-web/app/products/page.tsx` — table; row click → detail/edit drawer; multi-select for merge.

**Acceptance:** Admin can find two "oatmeal" entries, merge them; user's meals keep the winning product_id.

**Est:** 3h

---

### Task 10.5 — `/exercises` page + backend endpoints

**Skills:** `api-and-interface-design`, `frontend-ui-engineering`

**Backend routes:**
- `GET /api/v1/admin/exercises` (paginated)
- `POST /api/v1/admin/exercises` (create)
- `PATCH /api/v1/admin/exercises/{id}` (edit)
- `DELETE /api/v1/admin/exercises/{id}` (cascade handled, program exercise rows set exercise to tombstone)

**Frontend:** `admin-web/app/exercises/page.tsx` — table + edit drawer.

**Est:** 2.5h

---

### Task 10.6 — `/metrics` page + backend endpoints

**Skills:** `everything-claude-code:postgres-patterns`, `performance-optimization`

**Backend:**
- `GET /api/v1/admin/metrics/summary` — aggregates for last 7 + 30 days from audit log + backend access log (if we add simple logging)
- `GET /api/v1/admin/metrics/claude-vision-spend` — sums cost-per-request stored in a new `claude_vision_events` table (optional for v1; show "coming soon" if not implemented)

**Decision:** v1 surfaces user count (7d active, 30d active), total meals logged, total sessions logged, DB size. Claude Vision spend deferred unless trivial.

**Frontend:** `admin-web/app/metrics/page.tsx` — simple stat cards + Recharts line chart of weekly active users.

**Est:** 3h

---

### Task 10.7 — `/audit` page + `audit_log` table

**Skills:** `everything-claude-code:database-migrations`, `security-and-hardening`

**Migration:** new `audit_log` table (append-only): `id, actor_user_id, action, target_type, target_id, details_json, created_at`.

**Backend:** middleware or per-route helper: every admin mutation writes an audit entry.

**Frontend:** `admin-web/app/audit/page.tsx` — reverse-chronological table, filterable by actor / action / date range.

**Est:** 2h

---

### Task 10.8 — Docker Compose addition

**Files:** `docker-compose.yml` adds `admin-web` service on port 3004 with healthcheck.

**Est:** 0.5h

---

### Task 10.9 — Playwright smoke tests

**Skills:** `everything-claude-code:e2e-testing`, `test-driven-development`

**Files:**
- `admin-web/e2e/admin-happy-path.spec.ts` — login → users → products → exercises → metrics → audit → logout
- `admin-web/playwright.config.ts` — uses backend 8099 + admin-web 3099 (analogous to frontend)

**Est:** 2h

---

## Parallelization strategy

Subagent runs this entire slice in a worktree while main agent handles Slice 8 on the main worktree. Zero overlap (different trees, different dependencies).

```
Agent(
  description: "Slice 10 — Admin Portal (admin-web)",
  subagent_type: "general-purpose",
  isolation: "worktree",
  model: "opus",
  prompt: """
    Read plans/slice-10-admin-portal.md and execute Tasks 10.1 through 10.9.
    Base: main after Slice 9 Phase C merge.
    Branch: slice/10-admin-portal

    Scope boundaries:
    - admin-web/* (new Next.js app)
    - backend/app/api/v1/admin/* (new admin endpoints)
    - backend/app/models/audit_log.py (new)
    - backend/alembic/versions/YYYYMMDD_admin_and_audit.py (migration)
    - docker-compose.yml (add admin-web service)
    - docs/adr/0007-admin-portal-split.md

    Do NOT touch:
    - ios/* (Slice 8 concurrent on main)
    - frontend/* (user web frozen)
    - backend/app/api/v1/* (non-admin routes)

    TDD RED-first for backend endpoints. Playwright specs for admin-web. Invoke skills per task.
    Commit per task. Push branch. Report.
  """,
  run_in_background: true
)
```

### Merge discipline
1. Subagent reports done → main agent pulls, rebases on current main
2. Full backend pytest green + Playwright admin-web smoke green
3. `security-reviewer` agent audits admin routes for authz correctness
4. Merge; tag `slice-10-complete`

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| Role escalation bug (user→admin via wrong payload) | Explicit `require_admin` on every admin route; integration test asserts regular user gets 403 on each endpoint |
| Password-reset temp password leaked in logs | Response body only; never logged; admin emails out-of-band via copy-paste |
| Admin can suspend self, locking everyone out | UI disables suspend on own row; backend also checks |
| Audit log manipulable | Table has no UPDATE endpoints; DB role for app cannot DELETE (future hardening — note in ADR) |
| Admin-web session JWT reused on user web | Different cookie names, different localStorage keys (`admin_token` vs `token`) |
| Merge conflict with Slice 8 | Different trees; should not happen |
| Admin portal CSS bloat when copied from frontend | Start with minimal Tailwind; no shadcn or component library v1 |

## Verification before merge

```bash
# Backend
cd backend && uv run pytest tests/test_admin*.py tests/test_audit*.py -v

# Admin web
cd admin-web && pnpm test && pnpm test:e2e

# Manual
# 1. docker compose up admin-web → http://localhost:3004 loads
# 2. Login as admin → users → search carlos → change role to admin → verify in DB
# 3. Products → search → merge two → verify meal_items moved
# 4. Audit log shows all above actions
# 5. Login as regular user → redirected with "Not authorized"
```

Screenshots:
- [ ] Admin login page
- [ ] /users table with search
- [ ] /products merge dialog
- [ ] /metrics dashboard
- [ ] /audit log
- [ ] 403 redirect for non-admin

## Post-merge

Tag `slice-10-complete`. Deploy to `admin.fit.armandointeligencia.com` via Traefik label addition (handled in Slice 11 ops).
