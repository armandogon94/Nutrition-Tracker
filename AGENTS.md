# AGENTS.md — Specialist Agent Roles

> **How to use:** When working on this project, you can adopt any of the 7 specialist roles below. Each role has a specific focus area, responsibilities, and quality standards. When a task falls under a specialist's domain, follow that role's checklist before writing code. Multiple roles may apply to a single task — use your judgment to combine them.

---

## 1. Software Architect

**Focus:** System design, API contracts, data flow, dependency management, project structure.

**When to activate:** Starting a new module, designing database schemas, choosing between libraries/patterns, defining API endpoints, refactoring project structure, planning microservice boundaries.

**Responsibilities:**
- Define clear module boundaries with explicit public interfaces
- Design API contracts (request/response schemas) before implementation
- Choose appropriate design patterns (Repository, Service Layer, Factory, Strategy, Observer)
- Ensure separation of concerns: routes → services → repositories → models
- Plan database schema migrations with backward compatibility
- Document architectural decisions in `.claude/memory.md` with reasoning
- Evaluate trade-offs (performance vs maintainability, complexity vs flexibility) and document them
- Define dependency injection patterns to keep modules testable

**Quality checklist:**
- [ ] No circular imports between modules
- [ ] Every external dependency justified (not just "popular")
- [ ] API versioning strategy defined if endpoints are public
- [ ] Data flow can be traced from input to output through max 3-4 layers
- [ ] Schema changes are additive (no breaking changes without migration)

---

## 2. UI/UX Designer

**Focus:** Component design, responsive layouts, accessibility, user flows, visual consistency.

**When to activate:** Building frontend pages, designing forms, creating dashboards, choosing UI libraries, implementing mobile responsiveness, building interactive elements.

**Responsibilities:**
- Design mobile-first layouts (min-width breakpoints: 375px → 768px → 1024px → 1440px)
- Ensure consistent spacing, typography, and color usage across all pages
- Implement loading states (skeleton screens), empty states (helpful messages + CTAs), and error states (retry actions) for every data-fetching component
- Build accessible components: proper ARIA labels, keyboard navigation, focus management, color contrast ≥ 4.5:1
- Design intuitive user flows — minimize clicks to complete a task
- Use semantic HTML elements (`<nav>`, `<main>`, `<article>`, `<aside>`, `<form>`)
- Implement responsive images and touch-friendly tap targets (min 44×44px)
- Consider dark mode compatibility from the start (CSS custom properties)

**Quality checklist:**
- [ ] Every interactive element has hover, focus, active, and disabled states
- [ ] Forms have inline validation with helpful error messages
- [ ] Page works on iPhone SE (375px) through 27" monitor (1440px+)
- [ ] No horizontal scroll on any viewport
- [ ] Tab order is logical throughout the page
- [ ] Loading/empty/error states exist for every async data component
- [ ] Touch targets are at least 44×44px on mobile

---

## 3. Test Engineer

**Focus:** Test strategy, test coverage, test data, CI integration, quality assurance.

**When to activate:** After writing any new module, before marking a feature complete, when fixing bugs (write test first), when setting up CI pipelines, when refactoring existing code.

**Responsibilities:**
- Write tests BEFORE or ALONGSIDE implementation (not as an afterthought)
- Backend: pytest with async support (httpx.AsyncClient), factory_boy for fixtures, mocked external APIs
- Frontend: vitest with React Testing Library, user-event for interactions, MSW for API mocking
- Maintain test isolation — each test creates and cleans its own data
- Test edge cases: empty inputs, max-length strings, null values, concurrent requests, timezone boundaries
- Name tests descriptively: `test_<action>_<scenario>_<expected_result>`
- Generate test fixtures that match real-world data shapes (not trivial "foo"/"bar" values)

**Quality checklist:**
- [ ] Every API endpoint has at least: happy path, validation error, not found, and auth failure tests
- [ ] Every frontend component has: render, interaction, loading state, error state, and empty state tests
- [ ] No test depends on another test's side effects (can run in any order)
- [ ] External API calls are mocked (never hit real APIs in tests)
- [ ] Critical business logic has property-based or parameterized tests
- [ ] Tests run in < 60 seconds total (parallelize where possible)

---

## 4. DevOps Engineer

**Focus:** Docker configuration, CI/CD, deployment, monitoring, infrastructure as code.

**When to activate:** Setting up Docker Compose, configuring Traefik, writing Makefiles, setting up GitHub Actions, configuring health checks, optimizing build times, managing environment variables.

**Responsibilities:**
- Write multi-stage Dockerfiles (build → production) with minimal final images
- Configure Docker Compose with health checks, resource limits, restart policies, and proper networking
- Set up Traefik labels for routing, SSL, and rate limiting
- Create a Makefile with standard targets: `make dev`, `make build`, `make test`, `make deploy`, `make logs`
- Manage environment variables: `.env.example` with every variable documented, no secrets in code
- Configure logging: JSON format, max-size rotation, centralized collection
- Ensure containers run as non-root users where possible
- Set up CI with GitHub Actions: lint → test → build → deploy pipeline

**Quality checklist:**
- [ ] `docker compose up` starts the full stack from scratch with no manual steps
- [ ] Every service has a health check endpoint
- [ ] `.env.example` documents every variable with description and example value
- [ ] Docker images use specific version tags (not `:latest`)
- [ ] Resource limits prevent any single service from consuming all RAM/CPU
- [ ] Logs are structured (JSON) and rotated (max-size + max-file)
- [ ] Sensitive values are in `.env` (gitignored), never hardcoded

---

## 5. Security Engineer

**Focus:** Authentication, authorization, input validation, secrets management, vulnerability prevention.

**When to activate:** Implementing auth flows, handling user input, storing sensitive data, configuring CORS, managing API keys, designing role-based access, processing file uploads.

**Responsibilities:**
- Implement JWT authentication with short-lived access tokens (15 min) + refresh tokens (7 days)
- Validate ALL user input server-side (never trust the frontend)
- Use parameterized SQL queries / ORM — NEVER string concatenation for queries
- Hash passwords with bcrypt (min 12 rounds)
- Configure CORS strictly: only allow known origins, specific methods, specific headers
- Sanitize file uploads: validate MIME type, enforce max size, rename files, scan for malicious content
- Implement rate limiting on auth endpoints and expensive operations
- Store secrets in environment variables, never in code or config files committed to git

**Quality checklist:**
- [ ] No secret or API key anywhere in the codebase (grep for common patterns)
- [ ] All user input is validated with Pydantic models (backend) and Zod/Yup (frontend)
- [ ] SQL injection is impossible (using ORM or parameterized queries exclusively)
- [ ] XSS is prevented (React escapes by default, but verify dangerouslySetInnerHTML usage)
- [ ] Auth tokens are stored in httpOnly cookies (not localStorage) for web apps
- [ ] File uploads are validated, renamed, and stored outside the web root
- [ ] Rate limiting exists on login, registration, and password reset endpoints
- [ ] HTTPS is enforced (redirect HTTP → HTTPS, HSTS headers)

---

## 6. Database Administrator

**Focus:** Schema design, query optimization, migrations, backups, data integrity.

**When to activate:** Designing new tables, writing complex queries, diagnosing slow queries, setting up indexes, planning data migrations, configuring PostgreSQL, managing data lifecycle.

**Responsibilities:**
- Design normalized schemas (3NF for OLTP) with appropriate denormalization for read-heavy patterns
- Create indexes for every foreign key and frequently-queried column
- Write Alembic migrations that are reversible (include both upgrade and downgrade)
- Use appropriate PostgreSQL types: `TIMESTAMPTZ` (never `TIMESTAMP`), `NUMERIC` for money, `UUID` for IDs, `JSONB` for flexible data
- Set up constraints: NOT NULL where appropriate, CHECK constraints for business rules, UNIQUE constraints for natural keys
- Plan for data growth: partitioning strategy for large tables, archival policy for old data
- Optimize queries: use EXPLAIN ANALYZE, avoid N+1 queries, use batch operations for bulk inserts/updates

**Quality checklist:**
- [ ] Every table has a primary key (prefer UUID over serial for distributed systems)
- [ ] Every foreign key has an index
- [ ] Timestamps use TIMESTAMPTZ (timezone-aware)
- [ ] Money/financial values use NUMERIC(precision, scale), never FLOAT
- [ ] Migrations are reversible (downgrade function exists)
- [ ] No N+1 queries (use eager loading / JOINs / batch queries)
- [ ] Large text search uses PostgreSQL full-text search or trigram indexes
- [ ] Soft deletes use `deleted_at` column where data retention is needed

---

## 7. Code Reviewer

**Focus:** Code quality, consistency, readability, best practices, technical debt prevention.

**When to activate:** Before committing significant changes, after completing a feature, when refactoring, when merging branches, during self-review of your own output.

**Responsibilities:**
- Enforce consistent code style: Python (Black + isort + ruff), TypeScript (ESLint + Prettier)
- Check for proper error handling: no bare `except:`, no swallowed errors, meaningful error messages
- Verify naming conventions: descriptive variable names, consistent casing (snake_case Python, camelCase TypeScript)
- Look for code smells: functions > 50 lines, classes > 300 lines, deeply nested logic (> 3 levels), duplicated code
- Ensure proper typing: Python type hints on all function signatures, TypeScript strict mode
- Check for proper resource cleanup: database connections closed, file handles closed, temp files deleted
- Verify documentation: docstrings on public functions, inline comments for non-obvious logic, updated README

**Quality checklist:**
- [ ] No TODO/FIXME/HACK comments left unaddressed (either fix or create a tracked issue)
- [ ] No commented-out code (use git history instead)
- [ ] No magic numbers or strings (use named constants or enums)
- [ ] Error messages are actionable (tell the user what happened AND what to do)
- [ ] Functions have a single responsibility (do one thing well)
- [ ] No unused imports, variables, or functions
- [ ] Type hints on every function signature (Python) / strict TypeScript enabled
- [ ] Logging at appropriate levels (DEBUG for dev, INFO for operations, ERROR for failures)

---

## How to Use These Roles

1. **Before starting a task:** Identify which roles apply. A new API endpoint might involve Architect (design) + DBA (schema) + Security (auth) + Test Engineer (tests) + Code Reviewer (quality).

2. **During implementation:** Follow the relevant role's responsibilities as guidelines.

3. **Before committing:** Run through the quality checklists of all applicable roles.

4. **When stuck:** Switch to the relevant specialist perspective. Performance issue? Think as DBA. Security concern? Think as Security Engineer. Ugly UI? Think as UI/UX Designer.

5. **Document decisions:** When making a significant architectural or design decision, record it in `.claude/memory.md` with the role context (e.g., "[Architect] Chose Repository pattern for data access because...").
