# ADR-0003: Refresh Token Rotation Strategy

- **Date:** 2026-04-25
- **Status:** Accepted
- **Deciders:** Armando Gonzalez
- **Related:** [SPEC.md §3](../../SPEC.md), [plans/slice-01-auth.md](../../plans/slice-01-auth.md), [plans/slice-09-backend-debt.md](../../plans/slice-09-backend-debt.md) Phase B

## Context and Problem Statement

FitTracker v2.1 issues a single 24-hour JWT access token at login and stores it in `localStorage` (web) / Keychain (iOS). On expiry the user is forcibly logged out. Two problems:

1. **24h is a long blast radius.** A leaked or stolen token gives an attacker a full day. We can't invalidate it before expiry without a client-side check.
2. **Re-authenticating every 24h is hostile UX**, especially on mobile where Face ID has primed users to expect days-or-weeks of seamless return.

We need a scheme that gives short-lived access tokens (low blast radius) and long-lived refresh tokens (smooth UX), with a way to invalidate refresh tokens server-side.

## Decision Drivers

- iOS app (Slice 1) needs to stay logged in across days without re-prompting
- Apple App Store wants minimal authentication friction for legitimate users
- Stolen-device scenario: user logs out from another device and the stolen one immediately loses access
- We don't ship enterprise SSO/SAML — keep it simple
- Backend currently has no refresh table or revocation mechanism (accepted tech debt from v2.1)

## Considered Options

### A. Long-lived JWTs (current state)
**Pros:** zero new infra. **Cons:** unrevokable, large blast radius, no logout-everywhere flow.

### B. Short-lived access JWT + opaque refresh token in DB (chosen)
- Access token: JWT, 1-hour expiry, stateless
- Refresh token: random 256-bit value, hashed in `refresh_tokens` table, 30-day expiry
- Each refresh **rotates** the token: old one is invalidated, new pair issued
- Logout endpoint marks `revoked_at = now()`
- Account deletion cascades and wipes all refresh tokens

**Pros:** small access-token blast radius, server-revocable refresh, audit trail (created/expired/revoked timestamps), supports "log out everywhere" by revoking all rows for a user.
**Cons:** one DB write per refresh (~once an hour per active user; still cheap).

### C. Short-lived access JWT + long-lived JWT refresh
**Pros:** fully stateless. **Cons:** revocation requires a deny-list anyway, so we'd be reinventing option B without the cleaner shape.

### D. Session cookies + CSRF tokens
**Pros:** classical, well-understood for web. **Cons:** poor fit for iOS native client, complicates the multi-client architecture (ADR-0001).

## Decision Outcome

**Chosen: B.** Short access JWT (1h) + DB-backed refresh token (30d) with rotation.

### Concrete protocol

| Operation | Endpoint | Behavior |
|---|---|---|
| Login | `POST /auth/login` | Validates email/password; issues access (1h) + refresh (30d). Inserts `refresh_tokens` row with bcrypt hash. |
| Sign in with Apple | `POST /auth/apple` | Verifies Apple identity-token JWT against Apple's JWKs; upserts user by `apple_user_id`; issues same pair. |
| Refresh | `POST /auth/refresh` | Validates refresh token (lookup by hash), checks not expired/revoked, **rotates** (revokes old, issues new), returns new pair. |
| Logout | `POST /auth/logout` | Authenticated. Marks active refresh token `revoked_at = now()`. |
| Account delete | `DELETE /users/me` | Cascades and wipes all refresh tokens for the user. |

### Rotation invariants

- Each refresh token is single-use. Hash stored, never the plaintext.
- Concurrent refresh requests with the same token: first wins; second receives 401 (token already rotated). This catches token-theft scenarios — if both legit and attacker tried to refresh, one of them gets logged out.
- Rotation is implemented with `SELECT … FOR UPDATE` on the row to serialize.

## Consequences

### Positive
- Stolen access token: max 1h lifetime
- Logout invalidates immediately on the next refresh
- "Sign out everywhere" possible: `UPDATE refresh_tokens SET revoked_at = now() WHERE user_id = ?`
- Token-theft detection signal (concurrent refresh attempts produce a 401 — actionable for monitoring)
- Aligns with iOS Keychain best practice: short-lived bearer tokens are the norm

### Negative
- Adds one DB table + ~one write per active-user-hour
- Adds two endpoints (`/refresh`, `/logout`) — covered in [plan slice-09 Phase B](../../plans/slice-09-backend-debt.md)
- iOS `AuthService` (Slice 1) needs an actor-isolated semaphore so concurrent API calls don't all attempt to refresh at once

### Neutral
- We pin access token to 1h. If users complain about latency on refresh, we can bump to 4h without changing the protocol.
- Refresh token storage is bcrypt-hashed. Slow on writes (intentional) but acceptable at our scale.

## Implementation notes

- **Migration** (Slice 9.4): `refresh_tokens (id uuid pk, user_id uuid fk, token_hash varchar(255) unique, expires_at timestamptz, revoked_at timestamptz null, created_at timestamptz default now())` + indexes on `user_id` and `token_hash`.
- **Apple-specific** (Slice 9.6): we store `apple_user_id` on users (UNIQUE, nullable). On Apple sign-in, upsert by this id.
- **Rate limit** (Slice 9 Phase C): `/auth/refresh` 10/min/IP (refresh storms = abuse signal).
- **iOS** (Slice 1): `AuthService` actor holds an `AsyncSemaphore`; multiple API calls hitting expired access token serialize through one refresh.

## Follow-ups

- ADR-0006 (Slice 9 Phase C) — admin role gate
- Token-theft monitoring dashboard in admin portal (Slice 10) — count concurrent-refresh 401s per user
- Possible "trusted device" feature post-v1: longer refresh windows on user-marked devices
