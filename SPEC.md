# SPEC — iOS FitTracker v1.0

**Author:** Armando Gonzalez
**Date:** 2026-04-23
**Status:** Draft — awaiting approval before `/plan`
**Supersedes:** PLAN.md v2.0 (PLAN.md remains the source of truth for the backend schema and web client; this SPEC defines the iOS client + admin split)

---

## 1. Objective

Convert FitTracker from a web-only product into a **mobile-first native iOS app**, with the existing Next.js web app demoted to a secondary user surface and a **new standalone Next.js admin portal** spun up as a separate backoffice service. All three clients share a single FastAPI + PostgreSQL backend.

- **Primary surface:** iOS 26 SwiftUI app, TestFlight distribution (personal/family), design ready for App Store review
- **Secondary surface:** existing Next.js web app at `fit.armandointeligencia.com` — kept working, not actively expanded
- **Backoffice:** new `admin-web/` Next.js app at `admin.fit.armandointeligencia.com` — role-gated, never shipped to end users

## 2. Target Users

| Persona | Surface | Notes |
|---|---|---|
| LATAM Spanish-speaking fitness-tracker | iOS app | Mobile-first, offline-tolerant, Liquid Glass or Health Cards theme |
| Armando (self-use, desktop sessions) | Web app | Same features as v2.1 today |
| Armando (admin) | Admin portal | User mgmt, product/exercise curation, system metrics — role-gated |

## 3. Architecture — Three Clients, One Backend

```
                    ┌────────────────────────────────┐
                    │   FastAPI backend (unchanged)  │
                    │   PostgreSQL 16 (unchanged)    │
                    │   + /api/v1/admin/* (new)      │
                    │   + /api/v1/auth/refresh (new) │
                    │   + /api/v1/auth/apple (new)   │
                    └──────┬────────┬────────┬───────┘
                           │        │        │
                  Bearer JWT        │   role=admin JWT
                           │        │        │
              ┌────────────┤        │        ├─────────────┐
              │                     │                      │
      ┌───────▼────────┐   ┌────────▼─────────┐  ┌─────────▼───────────┐
      │   iOS app      │   │  Next.js web     │  │  Next.js admin      │
      │  (new, primary)│   │ (existing, keep) │  │  (new, backoffice)  │
      │  LATAM users   │   │  Desktop users   │  │  Armando only       │
      └────────────────┘   └──────────────────┘  └─────────────────────┘
          ios/                frontend/              admin-web/
```

### Repo layout (final)

```
03-Nutrition-Tracker/
├── backend/              # FastAPI — unchanged shape, adds admin + auth refresh
├── frontend/             # Next.js user web app — frozen feature set
├── admin-web/            # NEW Next.js admin portal
├── ios/                  # NEW SwiftUI app, xcodegen project
├── docker-compose.yml    # adds admin-web service
├── SPEC.md               # this file
├── PLAN.md               # original web plan
└── plans/                # slice plans created by /plan
```

## 4. iOS App — Feature Inventory (Parity + iOS-Native Additions)

### Parity with web (v1 must ship all of these)

| # | Feature | Web screen | iOS screen |
|---|---|---|---|
| 1 | Email/password login | `/login` | `LoginView` |
| 2 | Register | `/register` | `RegisterView` |
| 3 | Dashboard (daily macros) | `/dashboard` | `HomeView` |
| 4 | Barcode scan + log meal | `/scan` | `ScanView` |
| 5 | Manual food entry | `/scan` (fallback) | `ManualEntrySheet` |
| 6 | Photo food recognition | `/scan` (Claude Vision) | `PhotoCaptureView` |
| 7 | Meals log (today/date) | `/meals` | `MealsListView` |
| 8 | Weekly meal plan | `/meals/plan` | `MealPlanWeekView` |
| 9 | Shopping list | `/meals/plan` shopping tab | `ShoppingListView` |
| 10 | Profile + TDEE | `/profile` | `ProfileView` |
| 11 | Goals (presets + custom) | `/goals` | `GoalsView` |
| 12 | Workout programs | `/workouts` | `ProgramsListView` |
| 13 | Active session logger + rest timer | `/workouts/log/[id]` | `SessionView` + `RestTimerView` |
| 14 | Exercise database | `/exercises` | `ExercisesBrowserView` |
| 15 | Workout history | `/workouts/history` | `HistoryView` |

### iOS-native additions (not on web)

- **Sign in with Apple** (required if we ship to App Store later; also nicer UX)
- **HealthKit integration** — read bodyweight, active energy burned; write dietary calories/macros + workouts back to Health app
- **Offline cache via SwiftData** — meals, products, exercises cached locally; writes queued when offline, flushed on reconnect
- **Push notifications** — daily meal reminders, goal achievement, inactivity nudges
- **Live Activity + Dynamic Island** — rest timer survives backgrounding, shows countdown on Lock Screen + Dynamic Island
- **CoreHaptics + AVAudioPlayer** — haptic + beep on rest timer completion (iOS replacement for Vibration API which doesn't work on iOS Safari)
- **VisionKit `DataScannerViewController`** — native iOS 16+ barcode scanner; replaces html5-qrcode entirely, no third-party dep
- **Widgets (stretch, not v1)** — home screen widget for today's macros

## 5. Admin Portal — Feature Inventory

Separate Next.js 14 app in `admin-web/`. **No consumer features.** All endpoints under `/api/v1/admin/*`, gated by `users.role = 'admin'`.

- User management: list, search, suspend/reactivate, reset password, change role
- Product database curation: search cached products, edit nutrition, merge duplicates, delete junk entries
- Exercise database curation: add/edit/delete exercises, upload video URLs
- System health: request volume by endpoint, error rate, DB size, Claude Vision spend
- Audit log: who did what when (append-only table)

## 6. Tech Stack

### iOS
- **iOS 26** deployment target
- **Swift 6.0**, **SwiftUI**, **Xcode 16**
- **xcodegen** for `project.yml` (same shape as `04-Finance-Tracker/ios`)
- **Swift Testing** framework (not XCTest) for unit tests
- **SwiftUI Charts** for all visualizations
- **SwiftData** for offline persistence
- **VisionKit** for barcode scanning, **AVFoundation** for camera control
- **HealthKit**, **ActivityKit** (Live Activity), **CoreHaptics**, **UserNotifications**
- **URLSession** + actor-based `APIClient` (shape copied from Finance Tracker)
- **Keychain** for JWT storage (never UserDefaults)
- **No third-party SPM packages** unless explicitly approved

### Admin web
- **Next.js 14** (App Router) — same stack as user web for reuse
- TailwindCSS, **no** design system heroics — this is a backoffice, optimize for data density
- Reuses `frontend/lib/api.ts` client pattern, different base URL

### Backend (additions)
- **slowapi** for rate limiting
- **Refresh token table** (migration in Slice 9)
- **Apple ID token verification** (PyJWT with Apple public keys)
- **`users.role`** column migration (enum: `user`, `admin`)

## 7. Design System — Liquid Glass + Health Cards

Copied from `04-Finance-Tracker/ios/FinanceTracker/Core/Theme/`. The `AppTheme` protocol + `ThemedCardModifier` + `ThemedBackdrop` system. User toggles themes in Settings; defaults to system appearance (dark → Liquid Glass, light → Health Cards).

- **Liquid Glass** (dark): `ultraThinMaterial` cards, deep blue/violet gradient backdrop, luminous borders, SF Rounded heroNumeral at 48pt semibold
- **Health Cards** (light): solid white surfaces, soft shadows, rose/indigo accents, SF Rounded heroNumeral at 44pt bold

Macro ring visualization for dashboard (like Apple Health activity rings) rendered with SwiftUI Charts + custom `Canvas` overlay — works identically in both themes, colors come from theme tokens.

## 8. Slice Roadmap — 12 Slices with Skill Mapping

Each slice is a vertical, shippable increment. Acceptance = builds, tests pass, user can tap through the new functionality. Invoke skills listed **in order** during `/plan` and `/build`.

| # | Slice | Primary deliverable | Skills to invoke |
|---|---|---|---|
| **0** | **Foundation & Scaffold** | xcodegen project, folder structure, `AppTheme` + both themes, `APIClient`, Keychain token store, Info.plist permissions, `AppRoot` + `AppStorage` theme selector | `swiftui-patterns`, `liquid-glass-design`, `ios-hig-design`, `swift-concurrency-6-2`, `swift-protocol-di-testing`, `api-and-interface-design`, `security-and-hardening`, `documentation-and-adrs` (ADR: theme system + arch) |
| **0.5** | **Mockup Tap-Through Prototype** | All 14 screens wired with navigation but backed by `MockData` service; no real network calls; both themes switchable live; runs in Simulator for design review | `liquid-glass-design`, `swiftui-patterns`, `ios-hig-design`, `frontend-ui-engineering` (adapted), `incremental-implementation` |
| **1** | **Auth** | `LoginView`, `RegisterView`, `AuthGate`, Sign in with Apple, `AuthService`, refresh token flow, test-account quick-select | `security-and-hardening`, `api-and-interface-design`, `test-driven-development`, `source-driven-development` (SIWA docs), `swiftui-patterns` |
| **2** | **Dashboard + Offline Cache** | `HomeView` with macro rings + hero calories + recent meals; `SwiftData` schema + write-through cache; network-aware service layer; HealthKit read bodyweight | `swift-actor-persistence`, `swiftui-patterns`, `source-driven-development` (HealthKit, SwiftData), `performance-optimization`, `test-driven-development` |
| **3** | **Scan & Log Meal** | VisionKit `DataScannerViewController` wrapper, `ProductLookupSheet`, `ManualEntrySheet`, photo capture → Claude Vision, meal CRUD, HealthKit write dietary calories | `source-driven-development` (VisionKit), `claude-api` (Claude Vision), `security-and-hardening` (camera perms), `swiftui-patterns`, `test-driven-development` |
| **4** | **Meal Plan + Shopping List** | `MealPlanWeekView` (7-column grid w/ drag-and-drop), `ShoppingListView` grouped by category with checkbox state | `swiftui-patterns`, `source-driven-development` (SwiftUI DnD), `ios-hig-design`, `test-driven-development` |
| **5** | **Profile + TDEE + Goals** | Form w/ live BMR/TDEE/macro preview, preset selector (fat loss/maintenance/bulk), custom macro editor | `swiftui-patterns`, `test-driven-development`, `ios-hig-design` |
| **6** | **Programs + Exercise DB** | Programs list, program detail view, exercise browser with search + filters, AVKit video player for exercise form videos | `swiftui-patterns`, `source-driven-development` (AVKit), `performance-optimization` (lazy loading), `test-driven-development` |
| **7** | **Workout Session + Rest Timer** | Set/rep/weight logger, timestamp-based timer surviving backgrounding, Live Activity + Dynamic Island, UNUserNotificationCenter, CoreHaptics + AVAudioPlayer, PR detection, HealthKit workout write | `source-driven-development` (ActivityKit, CoreHaptics, HealthKit), `swift-concurrency-6-2`, `performance-optimization`, `security-and-hardening` (notification perms), `test-driven-development` |
| **8** | **History + Analytics** | Calendar view, volume trend charts (SwiftUI Charts), PR list, export CSV | `swiftui-patterns`, `source-driven-development` (SwiftUI Charts), `performance-optimization` (N+1 fix lands here too), `test-driven-development` |
| **9** | **Backend Tech Debt + Refresh Tokens + Role-Based Access** | `datetime.now(tz=UTC)` sweep, N+1 fix in workout history, slowapi rate limits, refresh token table + endpoint, token revocation, shared `httpx.AsyncClient`, `users.role` migration, admin route gating, token expiration tests | `api-and-interface-design`, `security-and-hardening`, `database-migrations`, `postgres-patterns`, `test-driven-development`, `performance-optimization`, `code-review-and-quality` |
| **10** | **Admin Portal (`admin-web/`)** | Next.js scaffold, admin auth flow (role gate), user mgmt, product curation, exercise curation, system metrics, audit log | `frontend-ui-engineering`, `api-and-interface-design`, `security-and-hardening`, `browser-testing-with-devtools`, `e2e-testing`, `test-driven-development`, `documentation-and-adrs` (ADR: admin split) |
| **11** | **Polish + TestFlight Submission** | Spanish `Localizable.xcstrings`, app icon, launch screen, privacy manifest (`PrivacyInfo.xcprivacy`), account deletion flow, App Store metadata draft (for future), TestFlight upload via Xcode Cloud or Fastlane | `shipping-and-launch`, `ci-cd-and-automation`, `security-and-hardening`, `documentation-and-adrs`, `code-review-and-quality` |

### Slice ordering logic

Slices 0 → 2 build the foundation and prove the architecture with a real screen. Slice 0.5 is a design checkpoint — if the themes don't feel right in the Simulator, we adjust before building 14 screens on top. Slices 3–8 are feature parity with web, one module at a time, always touching real backend. Slice 9 is debt pay-down, scheduled **after** enough iOS code exists that we can see which debt actually hurt (so we don't over-fix). Slices 10–11 close out the scope.

## 9. Mockup Approach — Slice 0.5 Detail (user chose Option B)

**Deliverable:** a SwiftUI app that launches in the Simulator showing all 14 screens with navigation, using `MockData` instead of API calls. Both themes switchable from a Settings toggle. Goal: judge look AND feel before committing to the full build.

- **Mock service layer:** `ExpensesService`-style protocols (see Finance Tracker) with two implementations — `MockService` (static fixtures) and `LiveService` (real `APIClient`). App picks one via launch argument `-useMocks`.
- **Seed mock data:** ~5 meals, 3 workouts, 10 exercises, 1 meal plan, 1 shopping list, 1 profile, 1 user — enough to render every screen without empty states.
- **Scope boundary:** NO real logic. Buttons that would mutate state just log + dismiss. The prototype exists only to validate design direction.
- **Exit criteria:** Armando reviews the tap-through in Simulator and says "go" on one (or both) themes. Then we proceed to Slice 1.

## 10. Commands (project-level)

### iOS
```bash
cd ios
xcodegen                          # regenerate project from project.yml
open FitTracker.xcodeproj         # open in Xcode
xcodebuild -scheme FitTracker \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test
```

### Admin web
```bash
cd admin-web
pnpm install
pnpm dev                          # port 3004
pnpm test
pnpm build
```

### Full stack (dev)
```bash
docker compose up -d postgres
cd backend && uv run uvicorn app.main:app --port 8001 &
cd frontend && pnpm dev --port 3003 &
cd admin-web && pnpm dev --port 3004 &
cd ios && xcodegen && open FitTracker.xcodeproj
```

## 11. Project Structure Conventions

### iOS (mirrors Finance Tracker)

```
ios/
├── project.yml                    # xcodegen config
├── FitTracker/
│   ├── Core/
│   │   ├── Networking/            # APIClient, APIConfig, APIError, DTO
│   │   ├── Security/              # KeychainTokenStore, AppleIDVerifier
│   │   ├── Theme/                 # AppTheme, LiquidGlass, HealthCards, ThemedCard
│   │   ├── Persistence/           # SwiftData schema, sync manager
│   │   ├── Services/              # AuthService, MealService, WorkoutService, …
│   │   ├── MockData/              # Seed fixtures for Slice 0.5 + unit tests
│   │   └── Health/                # HealthKit read/write facade
│   ├── Features/
│   │   ├── Auth/                  # LoginView, RegisterView, AuthGate
│   │   ├── Home/                  # HomeView, MacroRingView
│   │   ├── Scan/                  # ScanView, ManualEntrySheet, PhotoCaptureView
│   │   ├── Meals/                 # MealsListView, MealDetailView
│   │   ├── MealPlan/              # MealPlanWeekView, ShoppingListView
│   │   ├── Profile/               # ProfileView, TDEECalculatorView, GoalsView
│   │   ├── Workouts/              # ProgramsListView, SessionView, RestTimerView
│   │   ├── Exercises/             # ExercisesBrowserView, ExerciseDetailView
│   │   ├── History/               # HistoryView, VolumeChartView, PRListView
│   │   └── Settings/              # SettingsView (theme picker, account deletion)
│   ├── Models/                    # Codable DTOs mirroring backend schemas
│   ├── Resources/
│   │   ├── Assets.xcassets
│   │   ├── Localizable.xcstrings  # es-419 (LATAM Spanish) + en
│   │   ├── PrivacyInfo.xcprivacy  # Apple privacy manifest
│   │   └── Info.plist
│   └── App/
│       └── FitTrackerApp.swift    # @main entry, theme + token injection
└── FitTrackerTests/
    ├── Services/                  # Unit tests per service
    ├── ViewModels/                # If any; prefer direct SwiftUI
    └── Snapshot/                  # Optional: snapshot tests per theme
```

### Admin web

```
admin-web/
├── app/
│   ├── login/
│   ├── users/
│   ├── products/
│   ├── exercises/
│   ├── metrics/
│   └── audit/
├── components/
├── lib/                           # Reuses patterns from frontend/lib
├── package.json
└── next.config.js
```

## 12. Code Style

### Swift
- Swift 6 strict concurrency — all shared state uses `actor` or `@MainActor`
- Protocols for every service (for DI + test doubles)
- `@Observable` over `ObservableObject`
- `NavigationStack` over `NavigationView`
- No `UIKit` except via `UIViewControllerRepresentable` (VisionKit, AVKit)
- One view per file, filename matches view name
- Previews required on every view, both themes
- SwiftFormat via Xcode default settings — no custom config

### TypeScript (admin-web)
- Match existing `frontend/` conventions (no divergence)
- Data-dense layouts: no fancy cards, just tables

### Backend (Slice 9 additions)
- `datetime.now(timezone.utc)` everywhere — lint rule to block `utcnow`
- `@limiter.limit("N/minute")` decorator on all `/auth/*` and `/products/*` endpoints
- `Depends(require_admin)` on every `/admin/*` endpoint

## 13. Testing Strategy

| Layer | Framework | What we test | Target coverage |
|---|---|---|---|
| iOS unit | Swift Testing | Services, parsers, TDEE calc, timer logic, SwiftData mappers | 80%+ |
| iOS snapshot | swift-snapshot-testing (stretch) | Every view in both themes, light + dark | 1 per view |
| iOS UI | XCUITest | Happy-path per feature flow | Smoke only |
| Backend unit | pytest | Existing 95 tests + new refresh-token, role-gate, rate-limit, expiry tests | 95%+ |
| Backend integration | pytest | Real Postgres on 5433 — already in place | — |
| Web user E2E | Playwright | Existing 22 specs — keep green | — |
| Admin web E2E | Playwright | Per-feature happy path | Smoke only |

**TDD discipline:** every backend change in Slice 9 and every service in Slices 1–8 starts with a failing Swift Test or pytest.

## 14. Boundaries

### Always
- Store tokens in Keychain, never UserDefaults
- Include IDOR ownership checks on every backend mutation endpoint
- Run `xcodegen` after any `project.yml` change (never hand-edit `.xcodeproj`)
- Write Spanish strings into `Localizable.xcstrings`, never hardcode
- Add a `#Preview` for every new view, with mock data
- Request HealthKit permissions at point-of-use, not app launch
- Rate-limit every `/auth/*` endpoint
- Invoke the skills listed in each slice's row before building

### Ask first
- Adding any third-party Swift Package Manager dependency
- Database schema migrations (Alembic)
- Anything that breaks the web API contract (both `frontend/` and `admin-web/` depend on it)
- Bumping iOS deployment target below 26
- Pushing to main without review

### Never
- Store JWT or API keys in UserDefaults or NSUserDefaults
- Commit API keys or `.env` files
- Ship an iOS-only endpoint that breaks web parity (add versioning if needed)
- Bypass `AuthGate` for "quick testing" in release builds
- Use HealthKit data for advertising, sell it, or ship it to a third party (App Store violation)
- Write synthetic/fake data to HealthKit (App Store violation)
- Use private iOS APIs (App Store rejection guaranteed)

## 15. App Store Readiness Checklist (for future submission)

User asked to surface App Store acceptance criteria now so we can build toward them even while only TestFlight is the target. Verify against the latest [App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) at submission time; this is a 2026-04 snapshot.

### Will Slice 11 deliver

- [ ] **Privacy manifest** `PrivacyInfo.xcprivacy` at `ios/FitTracker/Resources/` — declares data collected, tracking domains, required-reason API usage (required since 2024)
- [ ] **Purpose strings** in `Info.plist` for every permission: `NSCameraUsageDescription`, `NSFaceIDUsageDescription`, `NSPhotoLibraryUsageDescription`, `NSHealthShareUsageDescription`, `NSHealthUpdateUsageDescription`, `NSUserTrackingUsageDescription` (if we ever add tracking)
- [ ] **Account deletion from within the app** (required since 2022) — Settings → Account → Delete Account. Hits `/api/v1/users/me` DELETE, cascade wipes meals/workouts/etc.
- [ ] **Sign in with Apple** offered alongside email (required if any third-party social login is offered; safer to include regardless)
- [ ] **Privacy policy URL** — hosted page, linked from Settings and App Store Connect
- [ ] **Terms of service URL** — same
- [ ] **Accurate screenshots** — generated from real app state, not marketing mockups
- [ ] **App name, subtitle, description** in Spanish + English
- [ ] **Keywords** — fitness, nutrition, macros, workouts (Spanish equivalents)
- [ ] **Category**: Health & Fitness (primary), Food & Drink (secondary)
- [ ] **Age rating**: 12+ (due to health data sensitivity)
- [ ] **Support URL** — where users report issues
- [ ] **Marketing URL** — optional but helpful (can point to web app)

### HealthKit-specific (guideline 1.4.1 + 5.1.3)

- [ ] Purpose strings explain *why* read/write for each data type
- [ ] No HealthKit data in crash reports or analytics
- [ ] No HealthKit data shared with third parties (not even Claude Vision — keep PII out of prompts)
- [ ] No fraudulent data writes (e.g. fake workouts)

### General guidelines we must respect

- **2.1 App Completeness** — TestFlight build has all 15 parity features working (no placeholder screens)
- **2.3 Accurate Metadata** — description matches the app
- **4.0 Design** — at least minimum functionality; Liquid Glass + Health Cards themes both count as real UI work
- **4.2 Minimum Functionality** — app must do more than be a reskinned website (HealthKit + scanner + offline cache all satisfy)
- **5.1.1 Data Collection** — nutrition logs are "Health & Fitness" data, must be disclosed in nutrition label
- **5.1.2 Data Use** — no ads, no tracking, no third-party SDKs outside of Apple's — **zero** tracking posture is easiest path to approval
- **5.6 Developer Code of Conduct** — nothing misleading, no fake reviews

### Things we will NOT do (avoid rejection)

- Collect IDFA / run ads (would require ATT prompt + privacy manifest updates)
- Add in-app purchases in v1 (app is free; if we ever add Pro, route through StoreKit, never Stripe)
- Rely on a web view as the primary interface (guideline 4.2 reskinned-website rejection risk)
- Ship without at least one iOS-native capability (we have several: scanner, HealthKit, Live Activity, offline cache)

## 16. Acceptance Criteria (v1 done)

- [ ] All 12 slices shipped and merged to `main`
- [ ] iOS: 15 parity screens working against real backend
- [ ] iOS: both themes render correctly in dark + light environments
- [ ] iOS: offline mode — user can view cached meals + log new meals, queued writes flush on reconnect
- [ ] iOS: rest timer survives backgrounding, notifies via Lock Screen + Dynamic Island
- [ ] iOS: HealthKit writes dietary calories after meal log; writes workout after session complete
- [ ] Web user app: still green on E2E
- [ ] Admin web: user search, product edit, metrics dashboard functional
- [ ] Backend: all 6 tech-debt items closed with tests
- [ ] TestFlight build installable on Armando's phone
- [ ] App Store readiness checklist 100% green (even without submitting)

## 17. Out of Scope (v1)

- iPad-specific layouts (auto-upscale only)
- Apple Watch companion
- Home screen widgets
- Shortcuts / Siri integration
- Social features (following, sharing, feed)
- In-app purchases / Pro tier
- iCloud sync across multiple devices (backend sync covers this)
- Android client
- Public user profiles or sharing
- macOS Catalyst build

---

## Next Step

Reply with either:
- **"Approve SPEC, run /plan for Slice 0"** — I'll break Slice 0 into tasks with acceptance criteria
- **"Approve SPEC, run /plan for all slices at a high level, detailed for Slice 0"** — same but with a one-page per-slice overview
- **"Change X in SPEC"** — tell me what to revise before we move on

After SPEC is approved, the workflow is: `/plan [slice]` → `/build [task]` → `/test` → `/review` per slice, until all 12 are done, ending with `/ship` on Slice 11.
