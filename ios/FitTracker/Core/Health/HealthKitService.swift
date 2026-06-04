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

/// A bodyweight reading carried out of the HealthKit boundary as a plain
/// Sendable value (HKQuantitySample is neither Sendable nor exposed to the
/// rest of the app). `weightKg` is the sample value converted to kilograms;
/// `date` is the sample's end date, used by callers to judge freshness.
struct BodyMassReading: Hashable, Sendable {
    let weightKg: Double
    let date: Date
}

@MainActor
final class HealthKitService {

    /// Shared instance — there's only one HKHealthStore per app.
    static let shared = HealthKitService()

    private let store: HKHealthStore?
    private(set) var isAuthorized: Bool = false

    /// Slice 2.5: seam for the bodyweight READ query. HKHealthStore /
    /// HKSampleQuery can't be mocked directly, so tests inject a closure
    /// that returns the `[HKQuantitySample]` a real `.bodyMass` query would
    /// yield (newest-first). In production this is nil and `latestBodyMass`
    /// runs the real HKSampleQuery against `store`.
    typealias BodyMassFetcher = @Sendable (_ sampleType: HKQuantityType) async throws -> [HKQuantitySample]
    private let bodyMassFetcher: BodyMassFetcher?

    init(store: HKHealthStore? = HKHealthStore.isHealthDataAvailable() ? HKHealthStore() : nil,
         bodyMassFetcher: BodyMassFetcher? = nil) {
        self.store = store
        self.bodyMassFetcher = bodyMassFetcher
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

    /// The set of types we READ (Slice 2.5). Kept narrow per PHI minimization:
    /// only bodyweight, used to refine the dashboard's TDEE when the user has
    /// a fresher Health sample than their saved profile. Active energy is
    /// reserved for a later slice.
    static let readTypes: Set<HKObjectType> = {
        var set: Set<HKObjectType> = []
        if let bodyMass = HKObjectType.quantityType(forIdentifier: .bodyMass) {
            set.insert(bodyMass)
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

    /// Request READ permission for bodyweight (Slice 2.5). Requested at the
    /// point the dashboard wants to refine TDEE, NOT at launch (Apple HIG).
    /// Note: HealthKit deliberately hides whether the user *granted* a read
    /// scope (to avoid leaking the absence of data), so we never inspect the
    /// returned status — we just attempt the query and treat "no samples" the
    /// same as "not authorized": both yield nil and fall back to the profile.
    func requestBodyMassReadAuthorizationIfNeeded() async throws {
        guard let store else { throw HealthKitError.unavailable }
        do {
            try await store.requestAuthorization(toShare: [], read: Self.readTypes)
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

    // MARK: - Bodyweight READ (Slice 2.5)

    /// The most recent bodyweight sample, in kilograms, or nil when there is
    /// no sample / no store / the user hasn't granted read access. Never
    /// throws for the "no data" case — callers (HomeView) must degrade to the
    /// profile's stored weight, so a nil is the expected quiet path.
    func latestBodyMass() async throws -> Double? {
        try await latestBodyMassReading()?.weightKg
    }

    /// The most recent bodyweight sample as a `BodyMassReading` (value in kg
    /// + the sample's end date), or nil. The date lets the dashboard decide
    /// whether the sample is fresh enough to override the profile weight
    /// (Slice 2.6 TDEE refinement).
    ///
    /// Concurrency: HKQuantitySample isn't Sendable, so the injectable
    /// fetcher hands back the samples and ALL inspection (sort selection +
    /// unit conversion) happens here on the MainActor. We never let an
    /// HKQuantitySample cross an isolation boundary.
    func latestBodyMassReading() async throws -> BodyMassReading? {
        guard store != nil else { return nil }
        let bodyMassType = HKQuantityType(.bodyMass)
        let samples: [HKQuantitySample]
        if let bodyMassFetcher {
            samples = try await bodyMassFetcher(bodyMassType)
        } else {
            samples = try await runBodyMassQuery(type: bodyMassType)
        }
        // The query sorts newest-first (endDate descending) and limits to 1,
        // but be defensive: pick the max by endDate regardless of order.
        guard let newest = samples.max(by: { $0.endDate < $1.endDate }) else {
            return nil
        }
        return BodyMassReading(
            weightKg: newest.quantity.doubleValue(for: .gramUnit(with: .kilo)),
            date: newest.endDate
        )
    }

    /// Runs the real HKSampleQuery for the single most-recent bodyweight
    /// sample. Wrapped in a continuation so the callback-based HealthKit API
    /// presents an async surface. Only used in production — tests inject
    /// `bodyMassFetcher` instead.
    private func runBodyMassQuery(type: HKQuantityType) async throws -> [HKQuantitySample] {
        guard let store else { return [] }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: HealthKitError.writeFailed(error.localizedDescription))
                    return
                }
                continuation.resume(returning: (samples as? [HKQuantitySample]) ?? [])
            }
            store.execute(query)
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
