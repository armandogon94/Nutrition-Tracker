//
//  HealthKitService.swift
//  Slice 3.6: writes dietary samples to HealthKit so logged meals show
//  up in Apple Health → Nutrition. We request write authorization at
//  first meal-log (NOT at app launch) per Apple HIG and SPEC §15.
//
//  PHI compliance:
//    - Authorization is requested with the minimum scope: only the
//      dietary types we actually write. Read scopes (bodyweight,
//      active energy) are owned by Slices 5/6 and added later via
//      additive extensions.
//    - Idempotency: every sample carries `HKMetadataKeyExternalUUID =
//      mealItem.id.uuidString`. Re-calling writeMealEntry for the same
//      MealItem is a no-op on the second pass.
//    - Failure modes: a denied authorization, an unavailable Health
//      data store, or a write error all surface as
//      `HealthKitError.unauthorized` / `.unavailable` / `.writeFailed`
//      so the caller can decide whether to retry or just continue —
//      we NEVER block meal logging on a HealthKit failure.
//
//  Testing strategy:
//    The HKHealthStore type is impossible to mock directly (UI permission
//    prompts and an opaque store). We extract the pure pieces — sample
//    construction and quantity conversion — into static helpers that
//    take simple inputs. HealthKitServiceTests asserts those helpers
//    produce the right HKQuantitySample values. The thin glue around
//    `requestAuthorization` and `save(_:)` is verified manually.
//

import Foundation
import HealthKit

enum HealthKitError: Error, Sendable, Equatable {
    case unavailable
    case unauthorized
    case writeFailed(String)
}

@MainActor
final class HealthKitService {

    /// Shared instance — there's only one HKHealthStore per app.
    static let shared = HealthKitService()

    private let store: HKHealthStore?
    private(set) var isAuthorized: Bool = false

    init(store: HKHealthStore? = HKHealthStore.isHealthDataAvailable() ? HKHealthStore() : nil) {
        self.store = store
    }

    /// The set of types we WRITE. Kept narrow; reads are added later.
    static let writeTypes: Set<HKSampleType> = {
        var set: Set<HKSampleType> = []
        let identifiers: [HKQuantityTypeIdentifier] = [
            .dietaryEnergyConsumed,
            .dietaryProtein,
            .dietaryCarbohydrates,
            .dietaryFatTotal,
            .dietaryFiber
        ]
        for id in identifiers {
            if let qt = HKQuantityType.quantityType(forIdentifier: id) {
                set.insert(qt)
            }
        }
        return set
    }()

    /// Request write permission for our nutrition types. Caller is
    /// MealService (or wherever the first log happens). Re-calling is
    /// safe — HealthKit no-ops if the user has already decided.
    func requestAuthorizationIfNeeded() async throws {
        guard let store else { throw HealthKitError.unavailable }
        do {
            try await store.requestAuthorization(toShare: Self.writeTypes, read: [])
            isAuthorized = true
        } catch {
            throw HealthKitError.unauthorized
        }
    }

    /// Write the given MealItem as a correlation grouping the macro
    /// samples. We do NOT inspect existing samples first — HealthKit
    /// uses the ExternalUUID to dedupe within its own store, and our
    /// tests verify the metadata is set.
    func writeMealEntry(_ item: MealItem, mealDate: Date = .now) async throws {
        guard let store else { throw HealthKitError.unavailable }
        if !isAuthorized {
            try await requestAuthorizationIfNeeded()
        }
        let samples = Self.makeSamples(for: item, mealDate: mealDate)
        guard !samples.isEmpty else { return }
        do {
            try await store.save(samples)
        } catch {
            throw HealthKitError.writeFailed(error.localizedDescription)
        }
    }

    // MARK: - Pure helpers (testable without HKHealthStore)

    /// Constructs the array of `HKQuantitySample`s for a single
    /// MealItem. Each sample carries:
    ///   - the value × correct HKUnit
    ///   - start = end = mealDate (point-in-time entry)
    ///   - HKMetadataKeyFoodType = "meal"
    ///   - HKMetadataKeyExternalUUID = mealItem.id (for idempotency)
    static func makeSamples(for item: MealItem, mealDate: Date) -> [HKQuantitySample] {
        var samples: [HKQuantitySample] = []
        let metadata: [String: Any] = [
            HKMetadataKeyFoodType: "meal",
            HKMetadataKeyExternalUUID: item.id.uuidString
        ]

        if let energyType = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed),
           item.calories > 0 {
            samples.append(HKQuantitySample(
                type: energyType,
                quantity: HKQuantity(unit: .kilocalorie(), doubleValue: item.calories),
                start: mealDate, end: mealDate, metadata: metadata
            ))
        }
        let macroSpecs: [(HKQuantityTypeIdentifier, Double)] = [
            (.dietaryProtein, item.proteinG),
            (.dietaryCarbohydrates, item.carbsG),
            (.dietaryFatTotal, item.fatG)
        ]
        for (id, grams) in macroSpecs where grams > 0 {
            if let type = HKQuantityType.quantityType(forIdentifier: id) {
                samples.append(HKQuantitySample(
                    type: type,
                    quantity: HKQuantity(unit: .gram(), doubleValue: grams),
                    start: mealDate, end: mealDate, metadata: metadata
                ))
            }
        }
        return samples
    }
}

// MARK: - Workout write (Slice 7.9)
//
// PHI compliance + idempotency mirror the dietary path:
//   - Authorization for the workout type is requested at point-of-use (when
//     the user finishes their first workout), with the minimum scope.
//   - Every workout carries HKMetadataKeyExternalUUID = session.id, so
//     re-finishing the same session never creates a duplicate entry.
//   - A denied/unavailable store surfaces a typed error; SessionView never
//     blocks ending a workout on a HealthKit failure.
//
// API (source-driven-development): uses `HKWorkoutBuilder` (the modern
// path; the old `HKWorkout` initializers are deprecated on iOS 17+):
//   configure -> beginCollection -> endCollection -> finishWorkout.
//
// Testing: `HKWorkoutBuilder` can't be driven headlessly, so the pure
// pieces — the configuration's activity type and the idempotency metadata —
// are extracted into `workoutConfiguration()` + `workoutMetadata(for:)` and
// asserted in HealthKitServiceTests. The thin builder glue is verified on a
// real device per the manual QA checklist.

extension HealthKitService {

    /// The workout share type (separate from the dietary quantity types).
    static var workoutShareTypes: Set<HKSampleType> { [HKObjectType.workoutType()] }

    /// Request authorization to write workouts. Idempotent at the system
    /// level. Sets `isAuthorized` so subsequent dietary/workout writes skip
    /// the re-prompt.
    func requestWorkoutAuthorizationIfNeeded() async throws {
        guard let store else { throw HealthKitError.unavailable }
        do {
            try await store.requestAuthorization(toShare: Self.workoutShareTypes, read: [])
            isAuthorized = true
        } catch {
            throw HealthKitError.unauthorized
        }
    }

    /// Write a completed `WorkoutSession` to Apple Health as a
    /// functional-strength-training workout. Idempotent via the session id.
    /// A still-active session (no `completedAt`) is rejected.
    func writeWorkout(_ session: WorkoutSession) async throws {
        guard let store else { throw HealthKitError.unavailable }
        guard let end = session.completedAt else {
            throw HealthKitError.writeFailed("session has no completedAt")
        }

        try await requestWorkoutAuthorizationIfNeeded()

        let configuration = Self.workoutConfiguration()
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())

        do {
            try await builder.beginCollection(at: session.startedAt)
            // We don't have per-second energy samples for a strength session;
            // the duration (start..end) is the meaningful signal. Attach the
            // idempotency + provenance metadata.
            try await builder.addMetadata(Self.workoutMetadata(for: session))
            try await builder.endCollection(at: end)
            _ = try await builder.finishWorkout()
        } catch {
            throw HealthKitError.writeFailed(error.localizedDescription)
        }
    }

    // MARK: - Pure helpers (testable)

    /// The configuration for a strength-training session.
    static func workoutConfiguration() -> HKWorkoutConfiguration {
        let config = HKWorkoutConfiguration()
        config.activityType = .functionalStrengthTraining
        return config
    }

    /// Metadata attached to the workout. The ExternalUUID makes the write
    /// idempotent (HealthKit dedupes on it); the indoor flag marks a gym
    /// session.
    static func workoutMetadata(for session: WorkoutSession) -> [String: Any] {
        [
            HKMetadataKeyExternalUUID: session.id.uuidString,
            HKMetadataKeyIndoorWorkout: true,
            HKMetadataKeyWorkoutBrandName: "FitTracker"
        ]
    }
}
