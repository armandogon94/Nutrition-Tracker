# ADR-0005: Exercise Form-Video Playback Strategy

- **Date:** 2026-04-25
- **Status:** Accepted
- **Deciders:** Armando Gonzalez
- **Related:** [SPEC.md](../../SPEC.md) §4 row 14, [plans/slice-06-programs-exercises.md](../../plans/slice-06-programs-exercises.md) Task 6.5

## Context

`ExerciseDetailView` is meant to play a short demonstration of correct technique for each exercise. The seed catalog (~56 exercises today, headed for 800+) ships `video_url` values that come from `free-exercise-db` — overwhelmingly **YouTube** links (`youtube.com/watch?...`, `youtu.be/...`, `m.youtube.com/...`).

AVKit's `AVPlayer` (and SwiftUI's `VideoPlayer`) cannot load a YouTube watch URL directly. AVKit wants a direct media URL — typically progressive MP4 or HLS playlists. YouTube only exposes its content via:

1. The official IFrame player (web embed), which requires a `WKWebView`.
2. The YouTube iOS SDK — abandoned by Google for years; not App-Store-clean.
3. Scraped CDN URLs — terms-of-service violation; URLs change frequently.

We must pick a playback strategy for v1 and document the trade-off so we can revisit when content scales.

## Options considered

### Option A — Open in Safari / YouTube app via `UIApplication.shared.open(url)`

- **Cost:** zero engineering. Single button, single line of code.
- **UX:** breaks in-app feel. The user leaves the app, has to tap back.
- **Compliance:** clean. Apple has no problem with apps that link out.
- **Future-proof:** if YouTube changes its watch URL shape, the system handler still works.

### Option B — Re-host as direct MP4 (or HLS) under our control

- **Cost:** high. Need licensing-clean source clips, server hosting + CDN, transcoding pipeline, and an admin tool to upload them. The CC0 / CC-BY corner of YouTube is small; most form clips are non-commercial reuse only.
- **UX:** native AVKit playback inline. Polished, professional.
- **Compliance:** clean if licensed; otherwise infringing.
- **Future-proof:** strong — we own the URLs.

### Option C — `WKWebView` wrapping YouTube's IFrame embed

- **Cost:** medium. Need to wrap WKWebView in a UIViewRepresentable, keep the page bundled or load over the network, and route messages.
- **UX:** plays inline, almost native-feeling.
- **Compliance:** **risky for App Store review**. Apps that host significant third-party web content can be rejected under guideline 4.7 ("apps that primarily display web content"). A single embed inside an otherwise-native app is usually OK, but the boundary is fuzzy and historically reviewers have flagged YouTube embeds when they look like a reskin.
- **Future-proof:** brittle — Google occasionally changes the embed handshake.

## Decision

**Adopt Option A for Slice 6 v1.** Specifically:

1. `Exercise.videoURL` is checked at view-render time.
2. If the host is in `youtube.com`, `youtu.be`, or `m.youtube.com`, render a CTA button that reads "Ver en YouTube" and calls `UIApplication.shared.open(url)`.
3. If the URL is **not** YouTube (i.e. a direct MP4 or any future hosted asset), render an inline `AVKit.VideoPlayer(player:)` so the user gets the polished native experience for content we control.
4. If `videoURL` is `nil`, show a placeholder (`exercises.detail.noVideo`).

This means the view is forward-compatible: the moment a backend URL points at a non-YouTube asset, the UI upgrades automatically without code changes.

## Consequences

### Positive
- Zero blocking work. Slice 6 ships on time.
- No compliance risk — Apple's review of an outbound link is uncontentious.
- The split policy (`isYouTube → external; otherwise inline`) means we can migrate exercise-by-exercise as we acquire licensed clips.
- Minimal surface area for tests — the host-check is a pure function and is unit-testable.

### Negative
- The first version of the app loses in-app polish for ~100% of v1 entries. Users see a "Watch on YouTube" button instead of an inline player.
- App-switch animation interrupts the workout-prep flow.
- Power users testing alongside competitors (Strong, Hevy, Stronger) will notice the gap.

### Neutral
- We acquire a content roadmap: a v1.x exercise content package can replace YouTube URLs with direct MP4 progressively. This becomes a content-ops tool surfaced through the admin portal (Slice 10 can grow an upload form).

## Out of scope for this ADR

- Video pre-caching / offline playback. Once we host MP4s we can introduce `AVAssetDownloadURLSession` for offline use. Right now even the YouTube path requires a live network.
- Captions / subtitles. Spanish caption tracks are a future content-ops concern.
- Picture-in-picture support. AVKit supports it natively for our self-hosted clips; no additional UI work needed.

## Follow-ups

- Slice 11 (TestFlight): include a privacy-manifest declaration if we end up self-hosting media (NSPrivacyAccessedAPICategoryFileTimestamp may apply to disk-cached clips).
- Slice 10 (Admin portal): exercise curation UI should let the admin replace the `video_url` with a self-hosted MP4 and mark the entry as "in-app playable".
- Track usage: a `video_open_external` event so we can quantify how many users actually tap through. If it's < 20% we may invest in re-hosting sooner.
