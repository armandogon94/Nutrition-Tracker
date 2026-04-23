# Slice 0 — Foundation & Scaffold

**Branch:** `slice/00-foundation`
**Estimate:** 10h realistic (6h optimistic, 14h if xcodegen fights us)
**Owner:** Main agent — **do not parallelize this slice**

---

## Dependencies

None. This is the root.

## Parallelizable peers

- **Slice 9 Phase A** (backend `datetime.utcnow()` sweep + N+1 fix) can run in a second worktree by an Opus subagent from day 1 — zero file overlap.

## Objective

Stand up a native iOS 26 SwiftUI project that:
- Builds and runs in the Simulator
- Has both `LiquidGlassTheme` and `HealthCardsTheme` wired up and switchable from a debug toggle
- Has an actor-based `APIClient` that can make a real call to the backend `/health` endpoint
- Stores JWT tokens in the Keychain (not UserDefaults)
- Has Swift Testing harness ready with one green smoke test

No user-facing features yet — this is pure plumbing.

## Acceptance criteria

- [ ] `xcodegen` regenerates `FitTracker.xcodeproj` from `ios/project.yml` cleanly
- [ ] `xcodebuild -scheme FitTracker -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build` succeeds with zero warnings
- [ ] Simulator launch shows a splash screen with "FitTracker" title using current theme
- [ ] Debug toggle in corner flips between Liquid Glass (dark) and Health Cards (light) instantly
- [ ] Tapping a "Ping backend" button shows `{"status":"ok"}` response from `http://localhost:8001/health`
- [ ] `FitTrackerTests` runs and passes a smoke test that mocks `APIClient` and verifies `AuthService.login()` protocol shape
- [ ] `Info.plist` has all permission purpose strings for features we'll add later (even if unused in Slice 0)
- [ ] `PrivacyInfo.xcprivacy` skeleton committed (empty arrays acceptable; we fill it per slice)
- [ ] ADR-0001 written to `docs/adr/0001-three-client-architecture.md`
- [ ] ADR-0002 written to `docs/adr/0002-theme-system.md`
- [ ] Keychain-based token store unit test passes (write → read → delete → read-nil)
- [ ] SwiftFormat (Xcode default) has been run; no uncommitted diffs

## Skills to invoke (in order)

1. `documentation-and-adrs` — write ADRs for architecture + theme system before writing any code
2. `systems-architecture:clean-architecture` — sanity-check layering (Features → Services → Core/Networking)
3. `api-and-interface-design` — define the `APIClient`, `TokenProvider`, and service protocols
4. `everything-claude-code:swiftui-patterns` — App entry, `@Observable` services, environment injection
5. `everything-claude-code:swift-concurrency-6-2` — actor isolation, `Sendable` conformance
6. `everything-claude-code:swift-protocol-di-testing` — every service is a protocol so mocks are trivial
7. `everything-claude-code:liquid-glass-design` — implement both themes
8. `ux-design:ios-hig-design` — verify type scale, tap targets, safe areas
9. `test-driven-development` — at every task start
10. `security-and-hardening` — Keychain code review, `ENABLE_USER_SCRIPT_SANDBOXING=YES`, `SWIFT_TREAT_WARNINGS_AS_ERRORS=NO` (temporary until stable)
11. `code-review-and-quality` — before merge

---

## Tasks

### Task 0.1 — Write ADRs (before any code)

**Skills:** `documentation-and-adrs`

**Files created:**
- `docs/adr/0001-three-client-architecture.md` — why we split into iOS + web + admin-web, what alternatives we rejected (single Expo app, Tauri desktop, etc.)
- `docs/adr/0002-theme-system.md` — why protocol-based `AppTheme` with two concrete themes, why SF Rounded for numerals, why `ultraThinMaterial` on Liquid Glass

**Acceptance:** Both ADRs follow the MADR format (context, decision, consequences). Each ≤1 page.

**Est:** 1h

---

### Task 0.2 — xcodegen project scaffold

**Skills:** `everything-claude-code:swiftui-patterns`, `security-and-hardening` (deployment target, sandboxing flags)

**RED test:** (not applicable — this task is pure scaffold; it's "GREEN" when `xcodebuild build` succeeds)

**Files created:**
- `ios/project.yml` — copy shape from `04-Finance-Tracker/ios/project.yml`. Change `PRODUCT_NAME` to "FitTracker", bundle id to `com.armandointeligencia.FitTracker`, display name "FitTracker"
- `ios/FitTracker/` (empty folder tree matching SPEC §11)
- `ios/FitTrackerTests/` (empty)
- `ios/.gitignore` — ignore `*.xcodeproj`, `build/`, `DerivedData/`, `xcuserdata/`
- `ios/README.md` — "Run `xcodegen` then open FitTracker.xcodeproj"

**Key `project.yml` differences from Finance Tracker:**
```yaml
targets:
  FitTracker:
    info:
      properties:
        NSCameraUsageDescription: "FitTracker uses the camera to scan barcodes on food packaging and take photos of meals."
        NSFaceIDUsageDescription: "Use Face ID to unlock FitTracker."
        NSPhotoLibraryUsageDescription: "Attach photos of meals from your photo library."
        NSHealthShareUsageDescription: "FitTracker reads bodyweight and active energy to calibrate your nutrition and workout tracking."
        NSHealthUpdateUsageDescription: "FitTracker writes dietary intake and completed workouts so you can see them in the Health app."
        NSUserNotificationsUsageDescription: "FitTracker sends rest timer alerts and goal reminders."
        NSMicrophoneUsageDescription: "FitTracker does not use the microphone."  # required placeholder if AVFoundation is linked
```

**Acceptance:**
- `cd ios && xcodegen` completes without errors
- `open FitTracker.xcodeproj` launches Xcode
- Empty skeleton builds

**Est:** 1.5h

---

### Task 0.3 — App entry point + theme environment

**Skills:** `everything-claude-code:swiftui-patterns`, `everything-claude-code:liquid-glass-design`

**RED test:**
```swift
// FitTrackerTests/App/AppRootTests.swift
import Testing
@testable import FitTracker

@Test func appRoot_usesInjectedTheme() throws {
    let theme = LiquidGlassTheme()
    let sut = AppRoot().environment(\.appTheme, theme)
    // Smoke assertion — just verifying the environment key exists and compiles
    #expect(theme.id == .liquidGlass)
}
```

**Files:**
- `ios/FitTracker/App/FitTrackerApp.swift` — `@main` entry with `@State` token store, `@AppStorage("selected_theme")` theme id, environment injection
- `ios/FitTracker/App/AppRoot.swift` — root `View` that swaps between `AuthGate` (Slice 1) and placeholder "hello world" for now
- `ios/FitTracker/Core/Theme/AppTheme.swift` — copy protocol from Finance Tracker verbatim
- `ios/FitTracker/Core/Theme/LiquidGlassTheme.swift` — copy verbatim; adjust accent colors only if needed for fitness context (keep for now)
- `ios/FitTracker/Core/Theme/HealthCardsTheme.swift` — copy verbatim
- `ios/FitTracker/Core/Theme/ThemedCard.swift` — copy verbatim
- `ios/FitTracker/Core/Theme/ThemedBackdrop.swift` — copy verbatim
- `ios/FitTracker/Core/Theme/Environment+AppTheme.swift` — `EnvironmentKey` wiring

**Acceptance:** App launches, shows title "FitTracker", backdrop reflects selected theme.

**Est:** 2h

---

### Task 0.4 — APIClient + APIConfig + APIError + DTO

**Skills:** `api-and-interface-design`, `everything-claude-code:swift-concurrency-6-2`, `test-driven-development`

**RED tests (before implementation):**
```swift
// FitTrackerTests/Core/Networking/APIClientTests.swift
@Test func apiClient_getsJsonAndDecodes() async throws {
    let session = MockURLSession(response: .ok(jsonString: #"{"status":"ok"}"#))
    let sut = APIClient(baseURL: URL(string: "http://test")!, session: session.session)
    struct Health: Decodable, Sendable { let status: String }
    let result: Health = try await sut.get("/health")
    #expect(result.status == "ok")
}

@Test func apiClient_throwsUnauthorizedOn401() async throws {
    let session = MockURLSession(response: .status(401, body: #"{"detail":"not auth"}"#))
    let sut = APIClient(baseURL: URL(string: "http://test")!, session: session.session)
    await #expect(throws: APIError.unauthorized) {
        let _: [String: String] = try await sut.get("/protected")
    }
}

@Test func apiClient_attachesBearerToken() async throws {
    let tokenProvider = StubTokenProvider(token: "abc123")
    let session = MockURLSession(response: .ok(jsonString: "{}"))
    let sut = APIClient(baseURL: URL(string: "http://test")!, tokenProvider: tokenProvider, session: session.session)
    _ = try? await sut.get("/whatever") as [String: String]
    #expect(session.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer abc123")
}
```

**Files:**
- `ios/FitTracker/Core/Networking/APIClient.swift` — copy from Finance Tracker with class changed to `actor`
- `ios/FitTracker/Core/Networking/APIConfig.swift` — `baseURL` reads from `Info.plist` `API_BASE_URL` key (default `http://localhost:8001`)
- `ios/FitTracker/Core/Networking/APIError.swift` — enum with `unauthorized`, `notFound`, `rateLimited(Int?)`, `offline`, `cancelled`, `server(status: Int, detail: String?)`, `decoding(String)`, `network(URLError)`, `unknown(String)`
- `ios/FitTracker/Core/Networking/DTO.swift` — empty file for now; each slice appends its DTOs
- `ios/FitTrackerTests/Core/Networking/MockURLSession.swift` — test helper using `URLProtocol`

**Acceptance:** 3 RED tests turn GREEN. No warnings.

**Est:** 2h

---

### Task 0.5 — Keychain token store + TokenProvider

**Skills:** `security-and-hardening`, `everything-claude-code:swift-protocol-di-testing`, `test-driven-development`

**RED tests:**
```swift
// FitTrackerTests/Core/Security/KeychainTokenStoreTests.swift
@Test func keychain_roundTrip() async throws {
    let sut = KeychainTokenStore(service: "test.fittracker", account: "test")
    await sut.updateAccessToken("abc")
    #expect(sut.currentAccessToken() == "abc")
    await sut.updateAccessToken(nil)
    #expect(sut.currentAccessToken() == nil)
}
```

**Files:**
- `ios/FitTracker/Core/Security/KeychainTokenStore.swift` — implements `TokenProvider` using `SecItemAdd/Copy/Update/Delete`. Stores access token + refresh token + expiry.
- `ios/FitTracker/Core/Security/TokenProvider.swift` — protocol from Finance Tracker
- `ios/FitTracker/Core/Security/StubTokenProvider.swift` (test target) — in-memory impl for tests

**Acceptance:** Round-trip test passes. Attempted read after delete returns nil. Also: delete all Keychain items after each test via `setup/tearDown` to avoid pollution.

**Est:** 1.5h

---

### Task 0.6 — PrivacyInfo.xcprivacy skeleton

**Skills:** `security-and-hardening`, `documentation-and-adrs`

**Files:**
- `ios/FitTracker/Resources/PrivacyInfo.xcprivacy` — property list with:
  - `NSPrivacyTracking`: `false`
  - `NSPrivacyTrackingDomains`: empty array
  - `NSPrivacyCollectedDataTypes`: empty array (populated per slice when we add collection)
  - `NSPrivacyAccessedAPITypes`: will populate in Slice 11; Apple's "required reasons" list

**Acceptance:** File is valid property list, committed, Xcode shows it in project navigator.

**Est:** 0.5h

---

### Task 0.7 — Smoke test target + CI hook

**Skills:** `test-driven-development`, `ci-cd-and-automation` (light touch for now)

**Files:**
- `ios/FitTrackerTests/SmokeTest.swift` — single test that imports `FitTracker` and asserts `FitTrackerApp` type exists
- `ios/Makefile` or `ios/scripts/test.sh` — one-line wrapper running `xcodebuild test`

**Acceptance:** `make test` (or script) runs all tests from command line without opening Xcode.

**Est:** 0.5h

---

### Task 0.8 — "Ping backend" debug view

**Skills:** `everything-claude-code:swiftui-patterns`, `api-and-interface-design`

**RED test:** not applicable — visual check

**Files:**
- `ios/FitTracker/Features/Debug/PingView.swift` — button that calls `APIClient.get("/health")`, shows result or error. Visible only in `#if DEBUG`.
- `AppRoot.swift` — mounts `PingView` as the placeholder content

**Acceptance:** Tap button, see `{status: ok}` in UI when backend is running on port 8001.

**Est:** 1h

---

### Task 0.9 — SwiftFormat + commit

**Skills:** `code-review-and-quality`, `git-workflow-and-versioning`

**Files:** no new code; run formatter, stage, commit

**Acceptance:**
- `git diff` after format is empty (idempotent)
- Commit message: `Slice 0: iOS foundation scaffold + theme system + APIClient + Keychain`
- Tag: `slice-0-complete`

**Est:** 0.5h

---

## Parallelization strategy

- **Main agent only.** No subagents for this slice. The files are too intertwined and the build-success signal is shared.
- **BUT:** before starting 0.1, spawn a subagent for **Slice 9 Phase A** (`datetime.utcnow()` sweep + N+1 fix) in a separate worktree:

```
Agent(
  description: "Slice 9-A backend debt",
  subagent_type: "general-purpose",
  isolation: "worktree",
  model: "opus",
  prompt: """
    Execute Slice 9 Phase A from plans/slice-09-backend-debt.md (Tasks 9.1 and 9.2 only):
    1. Replace every `datetime.utcnow()` in backend/ with `datetime.now(timezone.utc)`.
       - Add `from datetime import timezone` imports where missing
       - Run `uv run pytest` after, all 95 tests must still pass
    2. Fix N+1 in backend/app/api/v1/workouts.py workout history endpoint:
       - Find the loop that fetches sets/exercises per session
       - Replace with a single eager-load query using selectinload()
    Commit each task as its own commit. Push branch slice/09-phase-A-debt.
    Report back the exact pytest output and any files changed outside scope.
  """,
  run_in_background: true
)
```

I keep working on Slice 0 while that subagent toils. When it reports done, I rebase + `/review` + merge it. No conflict with Slice 0 iOS work.

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| xcodegen version mismatch with Xcode 16 | Pin `xcodegen` to a known-good version, document in README. Fallback: commit working `.xcodeproj` temporarily |
| Keychain flakiness on Simulator between test runs | `tearDown` deletes all items with service prefix; use unique service per test |
| Theme environment not propagating to deep children | Test with a deep nested preview; if broken, switch to `@Environment(ThemeStore.self)` pattern |
| ADR writing expands to hours | Timebox at 30min per ADR; they are 1-page docs, not design reviews |

## Verification before merge

```bash
cd ios
xcodegen
xcodebuild clean
xcodebuild -scheme FitTracker -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test 2>&1 | tail -20
```

Screenshots required in PR:
- [ ] Liquid Glass theme — splash with Ping button
- [ ] Health Cards theme — splash with Ping button
- [ ] Ping response on-screen

Merge command: rebase on `main`, squash-merge preserving task-level commits where meaningful.

## Post-merge

- Tag `slice-0-complete`
- Update `plans/000-OVERVIEW.md` phase table with completion date
- Kick off Slice 0.5 (Mockup) — main agent picks up next
