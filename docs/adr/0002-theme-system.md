# ADR-0002: Theme System — Protocol-Based Dual Theme (Liquid Glass + Health Cards)

- **Date:** 2026-04-23
- **Status:** Accepted
- **Deciders:** Armando Gonzalez
- **Related:** [SPEC.md](../../SPEC.md) §7, [plans/slice-00-foundation.md](../../plans/slice-00-foundation.md) Task 0.3

## Context and Problem Statement

The iOS FitTracker app must render in two distinct visual languages:

1. **Liquid Glass** — iOS 26 native aesthetic: dark mode default, `.ultraThinMaterial` cards on a layered blue/violet gradient backdrop, luminous borders, SF Rounded heroNumeral at 48pt semibold. Shows off iOS 26's depth materials.
2. **Health Cards** — Apple Health vibe: light mode default, bright white surfaces with soft shadows, rose/indigo accents, SF Rounded at 44pt bold. Warmer, less sci-fi.

The user should be able to switch themes at runtime from Settings. Every screen must render cleanly in both modes without per-theme code paths inside views.

The sibling `04-Finance-Tracker/ios` project already proved this pattern works. Can we adopt the same approach, or does fitness content demand something different?

## Decision Drivers

- Single codebase must render both themes; no per-theme `if` ladders in views
- Runtime switching must be instantaneous (no re-launch)
- New slices (Slices 2–11) must add views without fighting the system
- Theme must be testable via SwiftUI `#Preview` for both light + dark in both themes
- Accessibility: both themes respect Dynamic Type, VoiceOver, and `accessibility*` environment values

## Considered Options

### A. Environment-injected `AppTheme` protocol with concrete implementations
Pattern copied from Finance Tracker. Define `protocol AppTheme` with colors/fonts/radii/spacing tokens and `heroGradient() / cardBackground()` methods. Two structs (`LiquidGlassTheme`, `HealthCardsTheme`) conform. Inject into SwiftUI environment via `@Environment(\.appTheme)`. `ThemedCardModifier` dispatches per-theme.

**Pros:** Proven. Views never reference concrete themes. Adding a third theme later = add a struct. Easy to unit test (protocol mockable). `#Preview` just swaps the injected theme.
**Cons:** More ceremony than a flat `enum`. Every new screen must decorate with `.themedCard()` — if someone forgets, visual drift.

### B. SwiftUI native `.tint()` + `ColorScheme` only
Use `.preferredColorScheme(.dark)` + a few `.tint()` accents. No custom protocol.

**Pros:** Zero custom code.
**Cons:** Can't express both Liquid Glass (dark + material) and Health Cards (light + solid) with just color scheme. The whole point is different *surface treatments*, which `.tint()` can't control.

### C. Asset Catalog color sets with semantic names
Use Xcode's color assets: `PrimaryText`, `CardSurface`, etc. with `any` / `dark` variants.

**Pros:** Native Xcode tooling.
**Cons:** Can't express material vs solid surfaces — assets only handle colors, not `.ultraThinMaterial`. Limits future themes.

### D. Styled components library (à la shadcn-ui)
Define per-component variants via a central config.

**Pros:** Central source of truth per component.
**Cons:** Over-engineered for two themes. SwiftUI modifiers already provide composition.

## Decision Outcome

**Chosen: A.** Protocol-based `AppTheme` with `ThemedCardModifier` dispatch, copied verbatim from `04-Finance-Tracker/ios/FinanceTracker/Core/Theme/`.

Specifically:
- `AppTheme` protocol in `ios/FitTracker/Core/Theme/AppTheme.swift` — `Sendable`, declares all tokens
- `LiquidGlassTheme` and `HealthCardsTheme` concrete structs
- `ThemedCardModifier` switches on `theme.id` and applies the right surface treatment (material + luminous border vs. solid fill + soft shadow)
- `ThemedBackdrop` for full-screen backdrop (gradient for Liquid Glass, flat background for Health Cards)
- Theme selected via `@AppStorage("selected_theme")` at app root; read by environment key `\.appTheme`

Color accents adjusted for fitness context (warmer positives, less finance-blue) but structure stays identical to prevent reinventing the wheel.

## Consequences

### Positive
- Views remain theme-agnostic: `Text(...)  .foregroundStyle(theme.textPrimary)`, `.themedCard()` — no branches
- Theme can be swapped in preview, tests, and runtime uniformly
- Third/fourth themes (e.g., AMOLED Black for Slice 11 stretch) drop in as one file
- SPEC §7 parity with Finance Tracker lets us borrow unit tests and patterns
- Runtime switch visually correct because all surfaces read tokens, not literals

### Negative
- `.themedCard()` discipline required on every card-shaped view; missed application = visual inconsistency (mitigated: PR reviewer checks)
- `AppTheme` protocol has 15+ requirements; adding a token means editing both theme implementations (explicit, not implicit)

### Neutral
- The two initial themes are copied; we're not reinventing a design system from scratch. This is a constraint by choice.

## Implementation Notes

- File paths fixed: `Core/Theme/` (not `Features/Theme/` — it's infrastructure)
- `@AppStorage` key: `selected_theme` — stores `ThemeID.rawValue`
- Default theme on fresh install: follow system (`.dark` → Liquid Glass, `.light` → Health Cards)
- Theme change triggers no persistence invalidation — pure UI-only concern

## Follow-ups

- Task 0.3 in [slice-00-foundation.md](../../plans/slice-00-foundation.md) implements the theme files
- Task 0.5.15 in [slice-005-mockup.md](../../plans/slice-005-mockup.md) adds the user-facing theme switcher in Settings
- Add snapshot tests per view per theme (stretch, Slice 11)
