# Slice 1 — Auth (Email + Apple ID + Refresh Tokens)

**Branch:** `slice/01-auth`
**Estimate:** 16h realistic (10h optimistic, 22h if Apple ID verification surprises)
**Owner:** Main agent — serial (touches AppRoot + every service constructor)

---

## Dependencies

- **Slice 0 merged** (APIClient, Keychain, AppRoot exist)
- **Slice 0.5 merged** (mock LoginView/RegisterView skeletons to swap in real services)
- **Slice 9 Phase B merged** (refresh token table, `/auth/refresh` endpoint, `/auth/apple` endpoint — see [slice-09-backend-debt.md](slice-09-backend-debt.md) for task split)

## Parallelizable peers

None during active implementation. Slice 9 Phase B is the backend prep — it runs in a **separate worktree** and must merge BEFORE Slice 1 work starts (or at least before Task 1.4).

## Objective

Replace mock auth with real JWT-based auth, add Sign in with Apple alongside email/password, and implement refresh-token rotation so users stay logged in across days without storing long-lived tokens.

## Acceptance criteria

- [ ] User can register via email + password → gets back `{access_token, refresh_token, expires_in}`
- [ ] User can log in via email + password → same response
- [ ] User can tap "Sign in with Apple" → backend verifies Apple identity token → creates or links account → returns JWT pair
- [ ] AccessToken stored in Keychain, refreshToken stored in Keychain separately, expiry tracked
- [ ] When access token expires (or near expiry), `AuthService` silently refreshes before next API call
- [ ] `AuthGate` root view shows `LoginView` when no valid token; swaps to `MainTabView` after login
- [ ] Sign-out clears all Keychain entries, dismisses all stacks, returns to `LoginView`
- [ ] 3 test-account quick-select buttons (carlos/maria/roberto) work without typing
- [ ] Backend tests: 8 new tests for refresh token rotation, Apple verification, token revocation
- [ ] iOS tests: 12 new Swift tests for AuthService happy path + all error branches
- [ ] Rate limit on /auth/login and /auth/register verified (5 req/min per IP) — comes from Slice 9

## Skills to invoke (in order)

1. `api-and-interface-design` — design the `AuthService` protocol + refresh flow diagram before code
2. `security-and-hardening` — JWT expiry, refresh rotation, Apple ID token verification, rate limiting
3. `source-driven-development` — Sign in with Apple requires verifying Apple's JWT against their public keys; follow Apple docs, cite. Use Context7 MCP for current Apple authentication docs.
4. `test-driven-development` — RED tests for every branch
5. `everything-claude-code:swiftui-patterns` — `AuthGate`, form validation, error presentation
6. `everything-claude-code:swift-concurrency-6-2` — `AuthService` is an actor; refresh lock prevents races
7. `code-review-and-quality` — pre-merge
8. `documentation-and-adrs` — ADR-0003 on refresh token rotation strategy

---

## Tasks

### Task 1.1 — Write ADR: refresh token strategy

**Skills:** `documentation-and-adrs`, `security-and-hardening`

**File:** `docs/adr/0003-refresh-token-rotation.md`

**Content decisions:**
- Refresh tokens are random 256-bit, stored hashed (bcrypt) in `refresh_tokens` table
- On successful refresh, old token is invalidated and new one issued (rotation)
- Refresh tokens live 30 days; access tokens live 1 hour (reduced from 24h)
- Revocation: signing out or explicit delete endpoint marks token `revoked_at`
- Apple ID: we never store the Apple identity token; we verify once, create our own JWT pair

**Est:** 0.5h

---

### Task 1.2 — iOS: `AuthService` protocol + refresh mechanics

**Skills:** `api-and-interface-design`, `everything-claude-code:swift-concurrency-6-2`, `test-driven-development`

**RED tests:**
```swift
// FitTrackerTests/Services/AuthServiceTests.swift
@Test func login_storesTokens() async throws {
    let api = MockAPIClient(responses: [.ok("""
        {"access_token":"abc","refresh_token":"xyz","token_type":"bearer","expires_in":3600}
    """)])
    let keychain = StubKeychain()
    let sut = AuthService(api: api, keychain: keychain)
    try await sut.login(email: "a@b.co", password: "pw")
    #expect(keychain.accessToken == "abc")
    #expect(keychain.refreshToken == "xyz")
    #expect(await sut.isAuthenticated)
}

@Test func silentRefresh_happensBeforeExpiry() async throws {
    // expires_in = 60, so near-expiry triggers refresh
    let api = MockAPIClient(responses: [
        .ok(#"{"access_token":"new","refresh_token":"new_r","token_type":"bearer","expires_in":3600}"#)
    ])
    let keychain = StubKeychain(accessToken: "old", refreshToken: "old_r", expiresAt: Date().addingTimeInterval(30))
    let sut = AuthService(api: api, keychain: keychain)
    _ = try await sut.currentAccessTokenIfValid()
    #expect(keychain.accessToken == "new")
}

@Test func refreshRaceIsSerialized() async throws {
    // Fire 5 concurrent requests needing refresh; only ONE refresh call hits the network
    // ...
}
```

**Files:**
- `ios/FitTracker/Core/Services/ServiceProtocols.swift` — add `AuthService` protocol (defined in 0.5 as stub; now we expand)
- `ios/FitTracker/Core/Services/AuthService.swift` — actor implementation
- `ios/FitTracker/Core/Networking/DTO.swift` — add `AuthTokens`, `LoginRequest`, `RegisterRequest`, `AppleSignInRequest`

**Key methods:**
```swift
actor AuthService: ServiceProtocols.AuthService {
    func register(email: String, password: String, displayName: String) async throws
    func login(email: String, password: String) async throws
    func signInWithApple(identityToken: String, userIdentifier: String, fullName: PersonNameComponents?) async throws
    func signOut() async
    func currentAccessTokenIfValid() async throws -> String
    var isAuthenticated: Bool { get }
    // Private: func refreshIfNeeded() — guarded by an AsyncSemaphore so concurrent callers wait
}
```

**Acceptance:** 3 RED tests pass. Concurrency test proves only one refresh hits the wire.

**Est:** 3h

---

### Task 1.3 — iOS: `LoginView` (real)

**Skills:** `everything-claude-code:swiftui-patterns`, `ux-design:ios-hig-design`, `test-driven-development`, `everything-claude-code:liquid-glass-design`

**RED test (view-model level):**
```swift
@Test func loginForm_rejectsEmptyEmail() { ... }
@Test func loginForm_showsErrorOnServerFailure() async { ... }
```

**Files:**
- `ios/FitTracker/Features/Auth/LoginView.swift` — replace mock with real `AuthService` call
- `ios/FitTracker/Features/Auth/LoginViewModel.swift` — `@Observable` view model
- Keep quick-select buttons for test accounts (carlos@ / maria@ / roberto@), visible only in `#if DEBUG`

**UI states:** idle, validating, submitting, error (displayed inline), success (AppRoot swaps to MainTabView).

**Est:** 2h

---

### Task 1.4 — iOS: `RegisterView` (real)

**Files:** `Features/Auth/RegisterView.swift` + view model. Same shape as login but with display-name field and confirm-password validation.

**Est:** 1.5h

---

### Task 1.5 — iOS: Sign in with Apple button + flow

**Skills:** `source-driven-development` (Apple SIWA docs via Context7 MCP), `security-and-hardening`

**Files:**
- `ios/FitTracker/Features/Auth/AppleSignInController.swift` — `UIViewControllerRepresentable` or the new SwiftUI `SignInWithAppleButton`
- `ios/FitTracker/Core/Security/AppleIDCoordinator.swift` — handles `ASAuthorizationAppleIDRequest`, receives `ASAuthorizationAppleIDCredential`, extracts identity token + user identifier, forwards to `AuthService.signInWithApple(...)`

**Entitlement:** add `com.apple.developer.applesignin` to `project.yml` (xcodegen supports entitlements under `entitlements.plist` path).

**Backend flow:**
1. iOS sends `{identityToken: String, userIdentifier: String, fullName: {...}?, email: String?}`
2. Backend `/api/v1/auth/apple` verifies the JWT signature using Apple's public keys (`https://appleid.apple.com/auth/keys`), checks `aud`, `iss`, `exp`
3. Backend upserts user by `apple_user_id` column (new in migration). If first time and email provided, uses it; else synthesizes `apple_{userIdentifier}@fittracker.local`
4. Returns our normal `AuthTokens` pair

**Acceptance:** Sign in on real device works first time. Subsequent sign-ins find existing user by apple_user_id.

**Est:** 3h (includes dev-account wrangling)

---

### Task 1.6 — iOS: `AuthGate` + token restoration at launch

**Skills:** `everything-claude-code:swiftui-patterns`, `security-and-hardening`

**Files:**
- `ios/FitTracker/Features/Auth/AuthGate.swift` — root view:
  - On appear: check `Keychain` for token + expiry. If present and not near-expiry, skip to MainTabView. If expired, attempt silent refresh. If refresh fails, show LoginView.
- Updates `AppRoot.swift` to mount `AuthGate` instead of Slice 0's debug `PingView`

**RED test:**
```swift
@Test func authGate_showsLoginWhenNoToken() { ... }
@Test func authGate_restoresSessionOnLaunch() async { ... }
@Test func authGate_showsLoginAfterRefreshFailure() async { ... }
```

**Acceptance:** Launch app, previously logged-in user goes straight to Home. Fresh install goes to Login.

**Est:** 2h

---

### Task 1.7 — iOS: Sign-out flow + session cleanup

**Files:**
- `SettingsView.swift` Sign Out button now calls `AuthService.signOut()` → clears keychain → `AuthGate` observes `isAuthenticated` flip → pops back to `LoginView`
- `AuthService.signOut()` also hits `POST /api/v1/auth/logout` to revoke the refresh token server-side

**Acceptance:** Sign out from Settings, backend logs token revoked, relaunching app shows Login.

**Est:** 1h

---

### Task 1.8 — Backend: rate limit `/auth/*` endpoints

**Skills:** `security-and-hardening`, `api-and-interface-design`

This is a small piece of Slice 9 Phase C but landed here because it specifically protects the endpoints Slice 1 exposes.

**Files:**
- `backend/app/core/rate_limit.py` — slowapi Limiter initialization
- `backend/app/api/v1/auth.py` — `@limiter.limit("5/minute")` on login, `@limiter.limit("3/minute")` on register

**Test:** `backend/tests/test_auth.py::test_login_rate_limited`

**Acceptance:** 6th login request in 60 seconds returns 429.

**Est:** 1h

---

### Task 1.9 — Integration test + documentation

**Skills:** `test-driven-development`, `code-review-and-quality`, `documentation-and-adrs`

**Files:**
- `backend/tests/test_auth_refresh.py` — end-to-end: register → login → 59min later fake expiry → refresh → old refresh invalidated
- `backend/tests/test_auth_apple.py` — mock Apple JWK, verify flow
- `ios/FitTrackerTests/Features/Auth/AuthGateIntegrationTests.swift`
- Update `TEST-ACCOUNTS.md` with Apple-signin test notes (tester email required for sandbox)

**Acceptance:** Full integration test green. PR description includes sequence diagram of refresh flow.

**Est:** 2h

---

## Parallelization strategy

**During Slice 1 implementation:**

Two worktrees running in parallel (coordinated):

### Worktree 1 (main agent) — iOS side
Tasks 1.2 → 1.3 → 1.4 → 1.5 → 1.6 → 1.7 → 1.9

### Worktree 2 (Opus subagent) — Slice 9 Phase B backend side
Must complete BEFORE Task 1.2 can run iOS tests against real backend.

```
Agent(
  description: "Slice 9-B: refresh tokens + /auth/apple + /auth/logout + users.role",
  subagent_type: "general-purpose",
  isolation: "worktree",
  model: "opus",
  prompt: """
    Execute Slice 9 Phase B from plans/slice-09-backend-debt.md (Tasks 9.4 and 9.7):
    1. Create Alembic migration for refresh_tokens table and users.role column and users.apple_user_id column
    2. Implement /api/v1/auth/refresh endpoint
    3. Implement /api/v1/auth/apple endpoint verifying Apple JWK
    4. Implement /api/v1/auth/logout endpoint (revokes current refresh token)
    5. Add 8 pytest cases covering:
       - refresh happy path
       - refresh with invalidated token (should 401)
       - refresh rotation (old token invalidated after use)
       - apple signin first-time creates user
       - apple signin second-time reuses user by apple_user_id
       - apple signin with bad signature (should 401)
       - logout revokes token
       - logout then refresh (should 401)
    All 95 existing tests must still pass.
    Commit per task. Push slice/09-phase-B-auth.
    Report back.
  """,
  run_in_background: true
)
```

When subagent reports done:
1. I pull its branch, run full backend test suite
2. Invoke `security-reviewer` agent on the diff (especially the Apple JWK verification)
3. Merge to main
4. Then I resume Slice 1 Task 1.2 with real backend endpoints available

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| Apple JWK endpoint changes format | Cache keys, refresh daily; fallback to re-fetch on verification failure |
| Refresh token race condition (app backgrounded mid-refresh) | Async semaphore in `AuthService`; test explicitly |
| Keychain access during background wake | Use `kSecAttrAccessibleAfterFirstUnlock` accessibility |
| Apple signin user hides email → we get relay address → no way to contact | Copy hides-email info into user profile, warn in Settings that email sync requires real email |
| Refresh token leak from logs | Never log token bodies; log only hashed prefix |
| Rate limit too aggressive, locks out legitimate retry | Start at 5/min login, 3/min register; monitor after Slice 11 |

## Verification before merge

```bash
# Backend
cd backend
DATABASE_URL="postgresql+asyncpg://postgres:postgres@localhost:5433/fit_db_test" uv run pytest tests/test_auth*.py -v

# iOS
cd ios && xcodegen && xcodebuild -scheme FitTracker -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test

# Manual
# 1. Fresh install → register → kill app → relaunch → lands on Home (token restored)
# 2. Wait for token to expire (or set expires_in=10 for testing) → make an API call → observe silent refresh
# 3. Sign in with Apple on real device → backend should have apple_user_id populated
# 4. Rate limit: hammer /login 10 times → 6th returns 429
```

Screenshots in PR:
- [ ] LoginView both themes
- [ ] RegisterView both themes
- [ ] Sign in with Apple sheet
- [ ] Network inspector showing refresh rotation (old rt invalidated)

## Post-merge

Tag `slice-01-complete`. Now we can fan out to Slices 2/3/5/6 in parallel worktrees (Phase C in [OVERVIEW](000-OVERVIEW.md) §4).
