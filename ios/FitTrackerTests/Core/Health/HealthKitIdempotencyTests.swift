//
//  HealthKitIdempotencyTests.swift
//  Codex review #14 (cycle 1) / #13 (cycle 2): the dietary + workout writes
//  *claimed* idempotency via HKMetadataKeyExternalUUID but actually called
//  `store.save(_:)` unconditionally, so a re-log produced duplicate Health
//  rows. These tests drive the real behavior through the injectable store
//  seams:
//    - `existingExternalUUIDFetcher` reports whether a sample/workout with a
//      given ExternalUUID already exists.
//    - `sampleSaver` / `workoutSaver` record what was actually persisted.
//
//  HKHealthStore can't be mocked (opaque, permission UI), so we inject these
//  closures; production wires them to a real HKSampleQuery + store.save.
//

import Foundation
import HealthKit
import Testing
@testable import FitTracker

@MainActor
@Suite("HealthKitService idempotency", .serialized)
struct HealthKitIdempotencyTests {

    private func sampleItem(id: UUID = UUID()) -> MealItem {
        MealItem(
            id: id, productId: UUID(),
            productName: "Avena", brand: nil,
            servings: 1, calories: 150, proteinG: 5, carbsG: 27, fatG: 3
        )
    }

    @Test("writeMealEntry saves macro samples the first time (no existing UUID)")
    func writeMealEntry_savesWhenNew() async throws {
        let saved = SavedSamplesBox()
        let service = HealthKitService(
            store: HKHealthStore(),
            authorizationRequester: { _, _ in },
            existingExternalUUIDFetcher: { _, _ in false },
            sampleSaver: { samples in await saved.append(samples) }
        )
        try await service.writeMealEntry(sampleItem())
        let count = await saved.totalSampleCount
        #expect(count > 0, "first write must persist the macro samples")
    }

    @Test("writeMealEntry is a no-op on a duplicate ExternalUUID")
    func writeMealEntry_skipsDuplicate() async throws {
        let saved = SavedSamplesBox()
        // Fetcher reports the UUID already exists in HealthKit.
        let service = HealthKitService(
            store: HKHealthStore(),
            authorizationRequester: { _, _ in },
            existingExternalUUIDFetcher: { _, _ in true },
            sampleSaver: { samples in await saved.append(samples) }
        )
        try await service.writeMealEntry(sampleItem())
        let count = await saved.totalSampleCount
        #expect(count == 0, "a second write with the same ExternalUUID must not duplicate samples")
    }

    @Test("repeated writeMealEntry with the same id only persists once")
    func writeMealEntry_repeatedSameId_persistsOnce() async throws {
        let saved = SavedSamplesBox()
        let store = SimulatedHealthStore(saved: saved)
        let item = sampleItem()
        let service = HealthKitService(
            store: HKHealthStore(),
            authorizationRequester: { _, _ in },
            existingExternalUUIDFetcher: { uuid, _ in await store.contains(uuid) },
            sampleSaver: { samples in await store.save(samples) }
        )
        try await service.writeMealEntry(item)
        try await service.writeMealEntry(item)   // same id → must dedupe
        let saveCalls = await store.saveCallCount
        #expect(saveCalls == 1, "the second identical write must be skipped, not re-saved")
    }

    @Test("writeWorkout saves the first time (no existing UUID)")
    func writeWorkout_savesWhenNew() async throws {
        let workoutSaved = WorkoutSavedBox()
        let session = WorkoutSession(
            id: UUID(), startedAt: Date().addingTimeInterval(-1800),
            completedAt: Date(), programName: "PPL", dayName: "Push", sets: []
        )
        let service = HealthKitService(
            store: HKHealthStore(),
            authorizationRequester: { _, _ in },
            existingExternalUUIDFetcher: { _, _ in false },
            workoutSaver: { session in await workoutSaved.record(session.id) }
        )
        try await service.writeWorkout(session)
        let count = await workoutSaved.count
        #expect(count == 1, "first workout write must persist")
    }

    @Test("writeWorkout is a no-op on a duplicate ExternalUUID")
    func writeWorkout_skipsDuplicate() async throws {
        let workoutSaved = WorkoutSavedBox()
        let session = WorkoutSession(
            id: UUID(), startedAt: Date().addingTimeInterval(-1800),
            completedAt: Date(), programName: "PPL", dayName: "Push", sets: []
        )
        let service = HealthKitService(
            store: HKHealthStore(),
            authorizationRequester: { _, _ in },
            existingExternalUUIDFetcher: { _, _ in true },
            workoutSaver: { session in await workoutSaved.record(session.id) }
        )
        try await service.writeWorkout(session)
        let count = await workoutSaved.count
        #expect(count == 0, "a duplicate workout (same session id) must not be written again")
    }
}

/// Thread-safe accumulator for samples a fake saver received.
private actor SavedSamplesBox {
    private(set) var batches: [[HKSample]] = []
    func append(_ samples: [HKSample]) { batches.append(samples) }
    var totalSampleCount: Int { batches.reduce(0) { $0 + $1.count } }
    var saveCallCount: Int { batches.count }
}

/// A minimal in-memory stand-in for HealthKit's store: remembers which
/// ExternalUUIDs it has seen so the second save can be deduped.
private actor SimulatedHealthStore {
    private let saved: SavedSamplesBox
    private var seenUUIDs: Set<String> = []
    private(set) var saveCallCount = 0

    init(saved: SavedSamplesBox) { self.saved = saved }

    func contains(_ uuid: String) -> Bool { seenUUIDs.contains(uuid) }

    func save(_ samples: [HKSample]) async {
        saveCallCount += 1
        for s in samples {
            if let uuid = s.metadata?[HKMetadataKeyExternalUUID] as? String {
                seenUUIDs.insert(uuid)
            }
        }
        await saved.append(samples)
    }
}

private actor WorkoutSavedBox {
    private(set) var ids: [UUID] = []
    func record(_ id: UUID) { ids.append(id) }
    var count: Int { ids.count }
}
