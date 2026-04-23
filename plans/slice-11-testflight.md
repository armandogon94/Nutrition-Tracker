# Slice 11 — Polish + TestFlight Submission

**Branch:** `slice/11-testflight-polish`
**Estimate:** 20h realistic (12h optimistic, 30h if App Store Connect setup is new)
**Owner:** Main agent — **serial only**. Final polish is too cross-cutting to parallelize.

---

## Dependencies

- **Slices 0–10 merged.** v1 feature set complete.

## Parallelizable peers

- None during active work. Backend/admin may receive trickle fixes in parallel branches but nothing net-new.

## Objective

Convert the v1-complete app into a TestFlight build ready to install on Armando's + family's devices. Even though v1 distribution is TestFlight-only, this slice closes out **every** App Store–acceptance checkbox so later promotion to App Store is a metadata change, not a code change.

## Acceptance criteria

- [ ] Spanish `Localizable.xcstrings` complete — every user-facing string translated; CI-time lint fails build on hardcoded Swift `Text()` literals
- [ ] App icon: all sizes per `Assets.xcassets/AppIcon.appiconset`
- [ ] Launch screen: `LaunchScreen.storyboard` or SwiftUI + theme
- [ ] `PrivacyInfo.xcprivacy` complete — all data types collected, all required-reason APIs declared
- [ ] `Info.plist` purpose strings polished (English + Spanish)
- [ ] Account deletion from within app: Settings → Account → Delete Account → confirmation → backend cascades deletion → signs out
- [ ] Export/Download my data (Settings → Privacy → Download My Data) — GDPR/CCPA friendly, deferred option: show "Request via email" button if full export not built
- [ ] Privacy policy URL live at `fit.armandointeligencia.com/privacy`
- [ ] Terms of service URL live at `fit.armandointeligencia.com/terms`
- [ ] App Store Connect metadata drafted (name, subtitle, description, keywords in ES + EN) and committed to `docs/appstore/`
- [ ] TestFlight build uploaded via Fastlane or Xcode Cloud
- [ ] Installed on 3 test devices (Armando + 2 family members)
- [ ] All App Store Review Guidelines from SPEC §15 checklist green
- [ ] No warnings at build time (`SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` flipped ON)

## Skills to invoke

1. `shipping-and-launch` — pre-launch checklist, production readiness
2. `documentation-and-adrs` — final ADR on App Store posture
3. `ci-cd-and-automation` — Fastlane setup, TestFlight automation
4. `security-and-hardening` — final security + privacy audit
5. `everything-claude-code:healthcare-phi-compliance` — HealthKit final review
6. `code-review-and-quality` — final pre-merge review
7. `code-simplification` — final pass for anything obviously over-engineered
8. `everything-claude-code:liquid-glass-design` + `ux-design:ios-hig-design` — final visual polish audit
9. `performance-optimization` — Instruments pass for cold launch + scroll

---

## Tasks

### Task 11.1 — Spanish localization sweep

**Skills:** `everything-claude-code:swiftui-patterns`, `code-review-and-quality`

**Files:**
- `ios/FitTracker/Resources/Localizable.xcstrings` — every key translated. Xcode string catalog auto-extracts.
- `scripts/check-no-hardcoded-strings.sh` — grep all `.swift` files for `Text("...")` with non-key strings, fails CI if any found
- Update `project.yml` to run script as a build phase (or keep as pre-commit)

**Keys to translate:** every visible label, button, error message, placeholder. Roughly 120–180 keys.

**Spanish dialect:** es-419 (Latin American Spanish) — "tú" informal pronouns, measurement units metric default, date format dd/MM/yyyy.

**Acceptance:** Settings language → Español → every screen reads in Spanish, no English fallthrough.

**Est:** 4h (+ 2h if any dev-agnostic pluralization edge cases surface)

---

### Task 11.2 — App icon + launch screen

**Skills:** `ux-design:ios-hig-design`

**Files:**
- `ios/FitTracker/Resources/Assets.xcassets/AppIcon.appiconset/` — all required sizes (1024px marketing + all device sizes). Tool: export from a single 1024×1024 PNG via `ios-icon-generator` or Bakery.app.
- `ios/FitTracker/Resources/LaunchScreen.storyboard` OR SwiftUI equivalent — matches Liquid Glass aesthetic (deep gradient + app name)

**Icon design brief:** strong mark visible at 60px. Possibilities: stylized macro ring, dumbbell + leaf combination, minimalist "FT" mark. Commission or use a consistent SF Symbol composition.

**Est:** 2h (assumes Armando or designer provides final art; placeholder generation 30min)

---

### Task 11.3 — Privacy manifest + Info.plist final

**Skills:** `security-and-hardening`, `everything-claude-code:healthcare-phi-compliance`, `documentation-and-adrs`

**Files:**
- `ios/FitTracker/Resources/PrivacyInfo.xcprivacy` — complete:
  - `NSPrivacyTracking`: `false`
  - `NSPrivacyCollectedDataTypes`:
    - Email (for account), Name (if provided via Apple), Health (dietary), Fitness (workouts) — all linked to user, not used for tracking, disclosed via nutrition label
  - `NSPrivacyAccessedAPITypes` — check Apple's required-reason list; likely:
    - File timestamp: reason `C617.1` (display file info)
    - System boot time: reason `35F9.1` (measure time on device for timer accuracy)
    - User defaults: reason `CA92.1` (access user prefs)
- `Info.plist` purpose strings polished:
  - `NSCameraUsageDescription` (ES + EN): "FitTracker usa la cámara para escanear códigos de barras y tomar fotos de tus comidas." / "FitTracker uses the camera to scan barcodes and take photos of meals."
  - All other purpose strings mirrored in both languages

**Est:** 2h

---

### Task 11.4 — Account deletion flow

**Skills:** `security-and-hardening`, `api-and-interface-design`, `test-driven-development`

**Backend (small addition to Slice 9 scope):**
- `DELETE /api/v1/users/me` — soft-delete user (mark `deleted_at`) + cascade SwiftData-synced entities
- Background job or immediate: wipe PII (email, display_name) after 30d retention, keep anonymized audit rows

**RED test:** `test_user_self_delete.py` — verify user can delete own account; data cascades; audit log records the deletion.

**iOS:**
- `Features/Settings/DeleteAccountView.swift` — scary red button → confirmation modal requires typing "ELIMINAR" → calls endpoint → signs out → back to Login

**Acceptance:** Test account → delete → cannot log in anymore → data gone from DB (except audit row).

**Est:** 2h

---

### Task 11.5 — Privacy policy + Terms of service pages

**Skills:** `documentation-and-adrs`, `frontend-ui-engineering`

**Files:**
- `frontend/app/privacy/page.tsx` — markdown-rendered privacy policy. Content drafted from App Store Privacy Nutrition label + HealthKit disclosures.
- `frontend/app/terms/page.tsx` — short ToS draft
- Link both from Settings > About in iOS app (opens in `SFSafariViewController`)

**Content sources:** adapt from standard templates; cover: data we collect (email, nutrition logs, workouts, HealthKit), how we use it (only to render the app), data retention (30d after account deletion), no selling, no ads, no tracking, contact email.

**Est:** 2h

---

### Task 11.6 — App Store Connect metadata draft

**Skills:** `shipping-and-launch`, `documentation-and-adrs`

**Files:**
- `docs/appstore/listing-en.md` — App name "FitTracker", subtitle "Nutrición y entrenamientos", description (500-4000 chars), keywords, category Health & Fitness
- `docs/appstore/listing-es.md` — translated
- `docs/appstore/screenshots/` — 6.9" (iPhone 16 Pro Max) required set, 6 screenshots per language: Home, Scan, Session+Timer, Plan, Programs, History
- `docs/appstore/promotional-text.md` — optional 170-char blurb
- `docs/appstore/what-to-test.md` — for TestFlight tester invite

**Est:** 3h (copywriting + screenshot curation)

---

### Task 11.7 — Fastlane + TestFlight upload

**Skills:** `ci-cd-and-automation`, `security-and-hardening`

**Files:**
- `ios/fastlane/Fastfile` — lanes: `beta` (build + upload to TestFlight)
- `ios/fastlane/Appfile` — app_identifier, team_id
- `ios/fastlane/Matchfile` — optional: certificate management via match (use env-var signing key alternatively)
- `ios/Gemfile` — Fastlane Ruby deps pinned

**App Store Connect setup (manual, one-time):**
- Create App ID for `com.armandointeligencia.FitTracker`
- Enable capabilities: HealthKit, Sign in with Apple, Push Notifications, Live Activities
- Create provisioning profile (dev + distribution)
- Add test users by email to TestFlight internal group

**Automation:**
- `bundle exec fastlane beta` — increments build number, archives, uploads, notifies internal testers

**Acceptance:** TestFlight email arrives in Armando's inbox; app installs and runs on real device.

**Est:** 4h (first-time setup eats hours)

---

### Task 11.8 — Device QA pass

**Skills:** `code-review-and-quality`, `performance-optimization`

**Checklist (each item on real device):**
- [ ] Fresh install → register → land on Home
- [ ] Sign in with Apple works
- [ ] Scan real barcode → product found → log
- [ ] Photo meal recognition works
- [ ] Dashboard offline (airplane mode) still shows cached data
- [ ] Start workout → rest timer → Lock Screen shows Live Activity
- [ ] Timer fires notification + haptic while app backgrounded
- [ ] Complete workout → Health app shows entry
- [ ] Delete account → cannot log back in
- [ ] Both themes render correctly on Lock Screen widget
- [ ] Dynamic Type at XXL legible throughout
- [ ] Spanish language mode end-to-end
- [ ] Instruments: cold launch < 2s on iPhone 14; 60fps scrolling in Meals + Exercises

**Bug fixes land in this slice or a quick patch PR.**

**Est:** 2h + bug fix buffer

---

## Parallelization strategy

None during active polish work. This slice is too cross-cutting and every change needs a full build.

**Exception:** Task 11.5 (privacy + ToS pages) can be handed to a subagent since it's isolated to `frontend/`:

```
Agent(description: "Privacy + ToS pages",
      isolation: "worktree", model: "opus",
      prompt: "Create frontend/app/privacy/page.tsx and frontend/app/terms/page.tsx. Use the content brief in plans/slice-11-testflight.md Task 11.5. Simple markdown rendering. Commit and push slice/11b-legal-pages. Report.")
```

Merge directly when done.

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| App Store developer account not ready | Start enrollment BEFORE Slice 11 starts; 24-48h approval typical |
| TestFlight rejects missing export-compliance answer | Fill questionnaire; our app uses HTTPS only (standard encryption) |
| Spanish pluralization rules miss edge cases | Reviewer (native speaker ideally) reads app end-to-end |
| App icon rejected for resembling Apple Fitness icon | Distinct color palette (not red concentric rings); stylized nutrition + muscle mark |
| HealthKit purpose string "too vague" | Cite Apple guideline 5.1.3: explain specific read+write purpose per data type |
| Privacy manifest missing required-reason API | Use Apple's privacy-manifests.app to audit used APIs before submission |
| Fastlane signing nightmare | Start with manual Xcode signing first for TestFlight; automate later |
| Last-minute bug in critical path | Slice 11 has 20% time buffer built in; worst case we move to TestFlight with known issues documented |

## Verification before merge

```bash
# Full suite
cd ios && xcodegen && xcodebuild -scheme FitTracker -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test
cd backend && DATABASE_URL=... uv run pytest tests/ -v
cd frontend && pnpm test && pnpm test:e2e
cd admin-web && pnpm test && pnpm test:e2e

# Strict warnings on
# ios/project.yml SWIFT_TREAT_WARNINGS_AS_ERRORS: "YES"
# Must still compile clean.

# Localization lint
bash scripts/check-no-hardcoded-strings.sh

# Fastlane dry run
cd ios && bundle exec fastlane beta --skip_upload_ipa --skip_submission
```

Final PR must include:
- [ ] Screen recording of full app in Liquid Glass theme
- [ ] Screen recording of full app in Health Cards theme
- [ ] Screenshot set for App Store (all 6, both languages)
- [ ] `docs/appstore/*.md` metadata files
- [ ] `docs/adr/0008-app-store-readiness.md` — final posture ADR
- [ ] TestFlight invite email (Armando confirms installation)

## Post-merge

- Tag `v1.0-testflight`
- Deploy backend + admin-web to VPS
- Invite family testers
- Collect feedback for v1.1 backlog
- Celebrate 🎉

---

## Post-v1 Backlog (out of scope, captured for later)

From SPEC §17:
- iPad-specific layouts
- Apple Watch companion
- Home screen widgets (macros summary)
- Shortcuts / Siri integration
- Social features
- In-app purchases / Pro tier
- iCloud sync
- macOS Catalyst
- Public user profiles
- Android client

First post-v1 experiment ideas:
- Widgets (small effort, big perceived value)
- Apple Watch session logging (complements timer work in Slice 7)
- Weekly recap notification (Sunday 8pm)
