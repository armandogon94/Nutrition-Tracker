//
//  HealthKitService.swift
//  Slice 3.6: writes dietary samples to HealthKit so logged meals show
//  up in Apple Health → Nutrition. We request write authorization at
//  first meal-log (NOT at app launch) per Apple HIG and SPEC §15.
//
//  PHI compliance:
//    - Authorization is requested with the minimum scope, tracked PER SCOPE
//      (dietary write, workout write, bodyMass read). Requesting one scope
//      never marks another as granted, so e.g. a workout write can't
//      suppress the dietary authorization prompt (Codex review #14/#13).
//    - Idempotency (made real): every sample/workout carries
//      `HKMetadataKeyExternalUUID = <id>.uuidString`. Before saving we run an
//      ExternalUUID-predicated query and SKIP the write when a matching
//      object already exists, so re-logging the same MealItem / re-finishing
//      the same WorkoutSession does not create duplicate Health rows.
//    - Failure modes: a denied authorization, an unavailable Health
//      data store, or a write error all surface as
//      `HealthKitError.unauthorized` / `.unavailable` / `.writeFailed`
//      so the caller can decide whether to retry or just continue —
//      we NEVER block meal logging on a HealthKit failure.
//
//  Testing strategy:
//    The HKHealthStore type is impossible to mock directly (UI permission
//    prompts and an opaque store). We extract the pure pieces — sample
//    construction and quantity conversion — into static helpers, AND we
//    expose closure seams for the three impure operations:
//      - `authorizationRequester` (wraps store.requestAuthorization)
//      - `existingExternalUUIDFetcher` (wraps the ExternalUUID query)
//      - `sampleSaver` / `workoutSaver` (wrap store.save / builder.finish)
//    Production wires these to the real store; tests inject fakes to verify
//    idempotency (skip on duplicate) and per-scope authorization without a
//    permission prompt. The remaining HKWorkoutBuilder glue is verified on a
//    real device per the manual QA checklist.
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

    // MARK: Per-scope authorization (Codex review #14/#13)
    //
    // A single shared flag let one authorization path (e.g. workout) mark the
    // service "authorized" and suppress another scope's prompt (e.g. dietary).
    // We now track each scope independently. These only record that we have
    // ASKED for a scope this session (HealthKit deliberately hides the
    // grant/deny answer for reads, and treats a re-ask as a no-op for writes),
    // so they exist to avoid re-prompting, not to gate the write.
    private(set) var isDietaryWriteAuthorized: Bool = false
    private(set) var isWorkoutWriteAuthorized: Bool = false
    private(set) var isBodyMassReadAuthorized: Bool = false

    /// In-flight ExternalUUIDs currently between their existence-query and save
    /// (review C2). The HealthKit existence query is defense-in-depth, but it is
    /// check-then-save with an `await` in the middle, and `@MainActor` is
    /// REENTRANT across that await — so two concurrent `writeMealEntry` /
    /// `writeWorkout` calls for the same id could both query "not found" and
    /// both save a duplicate. We open a synchronous critical section by
    /// inserting the id here BEFORE the first await; a concurrent call for the
    /// same id sees it in-flight and skips. Set membership is mutated only on
    /// the MainActor with no await in between, so the check-and-insert is atomic.
    private var inFlightExternalUUIDs: Set<String> = []

    /// Slice 2.5: seam for the bodyweight READ query. HKHealthStore /
    /// HKSampleQuery can't be mocked directly, so tests inject a closure
    /// that returns the `[HKQuantitySample]` a real `.bodyMass` query would
    /// yield (newest-first). In production this is nil and `latestBodyMass`
    /// runs the real HKSampleQuery against `store`.
    typealias BodyMassFetcher = @Sendable (_ sampleType: HKQuantityType) async throws -> [HKQuantitySample]
    private let bodyMassFetcher: BodyMassFetcher?

    /// Seam for `store.requestAuthorization(toShare:read:)`. Tests inject a
    /// recorder; production calls the real store.
    typealias AuthorizationRequester = @Sendable (_ share: Set<HKSampleType>, _ read: Set<HKObjectType>) async throws -> Void
    private let authorizationRequester: AuthorizationRequester?

    /// Seam answering "does a sample/workout with this ExternalUUID already
    /// exist?" for the given sample types. Production runs an
    /// ExternalUUID-predicated `HKSampleQuery`; tests inject a fake store.
    typealias ExistingExternalUUIDFetcher = @Sendable (_ externalUUID: String, _ types: Set<HKSampleType>) async throws -> Bool
    private let existingExternalUUIDFetcher: ExistingExternalUUIDFetcher?

    /// Seam for persisting dietary samples (`store.save(_:)`). Tests record
    /// what was saved to assert idempotency.
    typealias SampleSaver = @Sendable (_ samples: [HKSample]) async throws -> Void
    private let sampleSaver: SampleSaver?

    /// Seam for persisting a workout. Production builds + finishes an
    /// `HKWorkoutBuilder`; tests record the session id.
    typealias WorkoutSaver = @Sendable (_ session: WorkoutSession) async throws -> Void
    private let workoutSaver: WorkoutSaver?

    init(store: HKHealthStore? = HKHealthStore.isHealthDataAvailable() ? HKHealthStore() : nil,
         bodyMassFetcher: BodyMassFetcher? = nil,
         authorizationRequester: AuthorizationRequester? = nil,
         existingExternalUUIDFetcher: ExistingExternalUUIDFetcher? = nil,
         sampleSaver: SampleSaver? = nil,
         workoutSaver: WorkoutSaver? = nil) {
        self.store = store
        self.bodyMassFetcher = bodyMassFetcher
        self.authorizationRequester = authorizationRequester
        self.existingExternalUUIDFetcher = existingExternalUUIDFetcher
        self.sampleSaver = sampleSaver
        self.workoutSaver = workoutSaver
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
    /// safe — HealthKit no-ops if the user has already decided. Tracks only
    /// the dietary scope so a workout/read request can't suppress this prompt.
    func requestAuthorizationIfNeeded() async throws {
        guard store != nil else { throw HealthKitError.unavailable }
        do {
            try await requestAuthorization(share: Self.writeTypes, read: [])
            isDietaryWriteAuthorized = true
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
        guard store != nil else { throw HealthKitError.unavailable }
        do {
            try await requestAuthorization(share: [], read: Self.readTypes)
            isBodyMassReadAuthorized = true
        } catch {
            throw HealthKitError.unauthorized
        }
    }

    /// Single funnel for authorization so production and tests share one path.
    /// Uses the injected `authorizationRequester` when present (tests),
    /// otherwise calls the real store.
    private func requestAuthorization(share: Set<HKSampleType>, read: Set<HKObjectType>) async throws {
        if let authorizationRequester {
            try await authorizationRequester(share, read)
        } else if let store {
            try await store.requestAuthorization(toShare: share, read: read)
        } else {
            throw HealthKitError.unavailable
        }
    }

    /// Write the given MealItem's macro samples. Idempotency is REAL: before
    /// saving we query HealthKit for any existing sample carrying this
    /// MealItem's ExternalUUID and skip the write when one is found, so
    /// re-logging the same item never duplicates Health rows. The query+save is
    /// additionally wrapped in a per-UUID in-memory critical section so two
    /// concurrent calls for the same item can't both pass the query and double
    /// up (review C2).
    func writeMealEntry(_ item: MealItem, mealDate: Date = .now) async throws {
        guard store != nil else { throw HealthKitError.unavailable }
        if !isDietaryWriteAuthorized {
            try await requestAuthorizationIfNeeded()
        }
        let samples = Self.makeSamples(for: item, mealDate: mealDate)
        guard !samples.isEmpty else { return }

        let uuid = item.id.uuidString
        // Open the critical section synchronously (no await before the insert),
        // so a concurrent call for the same id is deduped here rather than
        // racing the existence query below.
        guard beginCriticalSection(uuid) else { return }
        defer { endCriticalSection(uuid) }

        // Idempotency guard (defense in depth): skip if a sample with this
        // ExternalUUID already exists in HealthKit from a previous session.
        if try await externalUUIDExists(uuid, types: Self.writeTypes) {
            return
        }

        do {
            try await save(samples)
        } catch {
            throw HealthKitError.writeFailed(error.localizedDescription)
        }
    }

    // MARK: - Per-UUID critical section (review C2)

    /// Claim the in-flight slot for `uuid`. Returns false when another call is
    /// already mid-write for the same id (so the caller should skip). Runs
    /// entirely on the MainActor with NO suspension point between the membership
    /// check and the insert, which is what makes it atomic despite MainActor
    /// reentrancy across the later `await`s.
    private func beginCriticalSection(_ uuid: String) -> Bool {
        if inFlightExternalUUIDs.contains(uuid) { return false }
        inFlightExternalUUIDs.insert(uuid)
        return true
    }

    /// Release the in-flight slot for `uuid` once the query+save completes
    /// (success OR failure) so a later legitimate retry isn't blocked.
    private func endCriticalSection(_ uuid: String) {
        inFlightExternalUUIDs.remove(uuid)
    }

    // MARK: - Idempotency + save funnels

    /// Returns true when HealthKit already holds a sample/workout carrying the
    /// given ExternalUUID. Uses the injected fetcher in tests; production runs
    /// a real `HKSampleQuery` per type with an ExternalUUID predicate.
    private func externalUUIDExists(_ externalUUID: String, types: Set<HKSampleType>) async throws -> Bool {
        if let existingExternalUUIDFetcher {
            return try await existingExternalUUIDFetcher(externalUUID, types)
        }
        guard let store else { return false }
        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeyExternalUUID,
            allowedValues: [externalUUID]
        )
        for type in types {
            let found = try await Self.firstMatch(store: store, type: type, predicate: predicate)
            if found { return true }
        }
        return false
    }

    /// Runs a `limit: 1` HKSampleQuery and reports whether anything matched.
    private static func firstMatch(store: HKHealthStore, type: HKSampleType, predicate: NSPredicate) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: HealthKitError.writeFailed(error.localizedDescription))
                    return
                }
                continuation.resume(returning: !(samples ?? []).isEmpty)
            }
            store.execute(query)
        }
    }

    /// Persist dietary samples via the injected saver (tests) or the store.
    private func save(_ samples: [HKSample]) async throws {
        if let sampleSaver {
            try await sampleSaver(samples)
        } else if let store {
            try await store.save(samples)
        } else {
            throw HealthKitError.unavailable
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
    /// level. Tracks ONLY the workout scope so it can't suppress the dietary
    /// or read prompts (Codex review #14/#13).
    func requestWorkoutAuthorizationIfNeeded() async throws {
        guard store != nil else { throw HealthKitError.unavailable }
        if isWorkoutWriteAuthorized { return }
        do {
            try await requestAuthorization(share: Self.workoutShareTypes, read: [])
            isWorkoutWriteAuthorized = true
        } catch {
            throw HealthKitError.unauthorized
        }
    }

    /// Write a completed `WorkoutSession` to Apple Health as a
    /// functional-strength-training workout. Idempotency is REAL: before
    /// building the workout we query for any existing workout carrying this
    /// session's ExternalUUID and skip when one is found, so re-finishing the
    /// same session never duplicates the Health entry. A still-active session
    /// (no `completedAt`) is rejected.
    func writeWorkout(_ session: WorkoutSession) async throws {
        guard store != nil else { throw HealthKitError.unavailable }
        guard session.completedAt != nil else {
            throw HealthKitError.writeFailed("session has no completedAt")
        }

        try await requestWorkoutAuthorizationIfNeeded()

        let uuid = session.id.uuidString
        // Per-UUID critical section so two concurrent re-finishes of the same
        // session can't both pass the existence query and double-write (C2).
        guard beginCriticalSection(uuid) else { return }
        defer { endCriticalSection(uuid) }

        // Idempotency guard (defense in depth): skip if a workout with this
        // ExternalUUID already exists from a previous session.
        if try await externalUUIDExists(uuid, types: Self.workoutShareTypes) {
            return
        }

        do {
            try await saveWorkout(session)
        } catch let error as HealthKitError {
            throw error
        } catch {
            throw HealthKitError.writeFailed(error.localizedDescription)
        }
    }

    /// Persist a workout via the injected saver (tests) or the real
    /// `HKWorkoutBuilder` flow (production).
    private func saveWorkout(_ session: WorkoutSession) async throws {
        if let workoutSaver {
            try await workoutSaver(session)
            return
        }
        guard let store, let end = session.completedAt else {
            throw HealthKitError.unavailable
        }
        let configuration = Self.workoutConfiguration()
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        try await builder.beginCollection(at: session.startedAt)
        // We don't have per-second energy samples for a strength session;
        // the duration (start..end) is the meaningful signal. Attach the
        // idempotency + provenance metadata.
        try await builder.addMetadata(Self.workoutMetadata(for: session))
        try await builder.endCollection(at: end)
        _ = try await builder.finishWorkout()
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
