//
//  HomeViewModel.swift
//  Slice 2.6 — the dashboard refines its TDEE estimate from a FRESH
//  HealthKit bodyweight sample when one exists, otherwise it falls back to
//  the weight saved on the user's profile.
//
//  The decision is split out as a pure static function (`refineTDEE`) so it
//  is unit-testable without HealthKit or SwiftUI. The thin `@Observable`
//  view model wires the real services (ProfileService for the profile,
//  HealthKitService for the sample) and exposes the result to HomeView.
//

import Foundation
import Observation

// `BodyMassReading` (value kg + sample date) is defined alongside
// HealthKitService in Core/Health — it's the value produced by
// `latestBodyMassReading()` and consumed by the refine decision below.

/// The outcome of the refine-TDEE decision: the computed TDEE, which weight
/// it used, and whether that weight came from HealthKit (so the UI can show
/// a "from Apple Health" hint).
struct RefinedTDEE: Hashable, Sendable {
    let tdee: Double
    let effectiveWeightKg: Double
    let usedHealthKit: Bool
}

@MainActor
@Observable
final class HomeViewModel {

    /// How recent a HealthKit bodyweight sample must be to override the
    /// profile. Matches the product default of "within the last week".
    /// `nonisolated` so the pure `refineTDEE` can use it as a default arg.
    nonisolated static let defaultFreshnessWindow: TimeInterval = 7 * 86_400

    // MARK: - Pure decision (testable)

    /// Decide which bodyweight to trust and compute TDEE from it.
    ///
    /// - A HealthKit sample is used when it exists and its age is within
    ///   `freshnessWindow`. Future-dated samples (clock skew) count as fresh.
    /// - Otherwise the profile's saved weight is used.
    /// - TDEE is computed via the shared `TDEECalculator` so it stays in
    ///   lock-step with the backend formula (and never diverges from the
    ///   ProfileView preview).
    ///
    /// `nonisolated` so it stays a pure function callable from tests and any
    /// isolation context — it touches only value types + the pure
    /// `TDEECalculator`, never the view model's actor-isolated state.
    nonisolated static func refineTDEE(
        profile: UserProfile,
        healthKit: BodyMassReading?,
        now: Date = Date(),
        freshnessWindow: TimeInterval = HomeViewModel.defaultFreshnessWindow
    ) -> RefinedTDEE {
        let useHealthKit: Bool
        if let healthKit {
            let age = now.timeIntervalSince(healthKit.date)
            // age < 0 → sample is in the future (clock skew) → treat as fresh.
            useHealthKit = age <= freshnessWindow
        } else {
            useHealthKit = false
        }

        let weight = useHealthKit ? (healthKit?.weightKg ?? profile.weightKg)
                                  : profile.weightKg
        let bmr = TDEECalculator.bmr(
            weightKg: weight,
            heightCm: profile.heightCm,
            age: profile.age,
            sex: profile.sex
        )
        let tdee = TDEECalculator.tdee(bmr: bmr, activity: profile.activity)
        return RefinedTDEE(tdee: tdee, effectiveWeightKg: weight, usedHealthKit: useHealthKit)
    }

    // MARK: - Observable state (consumed by HomeView)

    private(set) var refined: RefinedTDEE?

    /// Non-nil when the last `refresh()` failed to load the profile (review
    /// Flash B3). Drives a user-facing error + retry affordance instead of
    /// silently leaving the TDEE hint blank with no explanation. A "no profile
    /// yet" (404) is NOT an error — `ProfileService` returns defaults for that —
    /// so this only trips on genuine failures (offline / server error).
    private(set) var loadError: String?

    private let profileService: any ProfileServiceProtocol
    private let healthKit: HealthKitService

    init(profileService: any ProfileServiceProtocol,
         healthKit: HealthKitService = .shared) {
        self.profileService = profileService
        self.healthKit = healthKit
    }

    /// Fetch the profile + latest HealthKit bodyweight and publish the refined
    /// TDEE. A profile-fetch failure is surfaced via `loadError` (with a retry
    /// path) rather than swallowed. The HealthKit read stays best-effort: a
    /// denied/absent Health sample is the expected quiet path and simply falls
    /// back to the profile weight.
    func refresh(now: Date = Date()) async {
        do {
            let profile = try await profileService.profile()
            loadError = nil
            // Use the date-carrying read so the freshness check is real: a stale
            // Health sample must NOT silently override a more recent profile weight.
            let sample = try? await healthKit.latestBodyMassReading()
            refined = Self.refineTDEE(profile: profile, healthKit: sample, now: now)
        } catch {
            // Surface the failure so the dashboard can offer a retry instead of
            // leaving the TDEE hint blank with no explanation.
            loadError = String(localized: "home.tdee.error")
        }
    }

    /// Retry affordance for the error surfaced by `refresh()`.
    func retry() async {
        await refresh()
    }
}
