//
//  HealthKitAuthScopeTests.swift
//  Codex review #14 (cycle 1) / #13 (cycle 2): a single shared `isAuthorized`
//  flag was set by ANY authorization path (dietary, workout, or — implicitly —
//  body-mass read). Once workout authorization flipped it true, a later
//  dietary write skipped its own authorization request entirely, so dietary
//  samples could be attempted without the user ever being asked for the
//  dietary scope.
//
//  Fix: track authorization per scope. These tests inject an
//  `authorizationRequester` seam that records which (share, read) scopes were
//  actually requested, and assert that requesting one scope never suppresses
//  another.
//

import Foundation
import HealthKit
import Testing
@testable import FitTracker

@MainActor
@Suite("HealthKitService per-scope authorization", .serialized)
struct HealthKitAuthScopeTests {

    private func sampleItem() -> MealItem {
        MealItem(
            id: UUID(), productId: UUID(),
            productName: "Avena", brand: nil,
            servings: 1, calories: 150, proteinG: 5, carbsG: 27, fatG: 3
        )
    }

    private func completedSession() -> WorkoutSession {
        WorkoutSession(
            id: UUID(), startedAt: Date().addingTimeInterval(-1800),
            completedAt: Date(), programName: "PPL", dayName: "Push", sets: []
        )
    }

    @Test("requesting workout auth does NOT mark dietary as authorized")
    func workoutAuth_doesNotImplyDietary() async throws {
        let recorder = AuthRecorder()
        let service = HealthKitService(
            store: HKHealthStore(),
            authorizationRequester: { share, read in await recorder.record(share: share, read: read) },
            existingExternalUUIDFetcher: { _, _ in false },
            sampleSaver: { _ in },
            workoutSaver: { _ in }
        )
        // Workout authorization runs first (e.g. user finished a workout).
        try await service.writeWorkout(completedSession())
        #expect(service.isDietaryWriteAuthorized == false,
                "workout authorization must not flip the dietary-write flag")

        // Now a dietary write must STILL request the dietary scope.
        try await service.writeMealEntry(sampleItem())
        let dietaryRequested = await recorder.requestedDietaryShare
        #expect(dietaryRequested, "dietary write must request dietary authorization even after workout auth ran")
    }

    @Test("requesting dietary auth does NOT mark workout as authorized")
    func dietaryAuth_doesNotImplyWorkout() async throws {
        let recorder = AuthRecorder()
        let service = HealthKitService(
            store: HKHealthStore(),
            authorizationRequester: { share, read in await recorder.record(share: share, read: read) },
            existingExternalUUIDFetcher: { _, _ in false },
            sampleSaver: { _ in },
            workoutSaver: { _ in }
        )
        try await service.writeMealEntry(sampleItem())
        #expect(service.isWorkoutWriteAuthorized == false,
                "dietary authorization must not flip the workout-write flag")

        try await service.writeWorkout(completedSession())
        let workoutRequested = await recorder.requestedWorkoutShare
        #expect(workoutRequested, "workout write must request workout authorization even after dietary auth ran")
    }

    @Test("dietary write only requests dietary authorization once")
    func dietaryAuth_requestedOnce() async throws {
        let recorder = AuthRecorder()
        let service = HealthKitService(
            store: HKHealthStore(),
            authorizationRequester: { share, read in await recorder.record(share: share, read: read) },
            existingExternalUUIDFetcher: { _, _ in false },
            sampleSaver: { _ in }
        )
        try await service.writeMealEntry(sampleItem())
        try await service.writeMealEntry(sampleItem())
        let count = await recorder.dietaryShareRequestCount
        #expect(count == 1, "dietary authorization should be requested once, then cached per-scope")
    }

    @Test("body-mass read authorization is tracked separately and requests the read scope")
    func bodyMassReadAuth_tracked() async throws {
        let recorder = AuthRecorder()
        let service = HealthKitService(
            store: HKHealthStore(),
            authorizationRequester: { share, read in await recorder.record(share: share, read: read) }
        )
        try await service.requestBodyMassReadAuthorizationIfNeeded()
        let readRequested = await recorder.requestedBodyMassRead
        #expect(readRequested, "body-mass read authorization must request the bodyMass read scope")
        #expect(service.isBodyMassReadAuthorized, "body-mass read scope flag must be set after a successful request")
        #expect(service.isDietaryWriteAuthorized == false, "read auth must not imply dietary write")
        #expect(service.isWorkoutWriteAuthorized == false, "read auth must not imply workout write")
    }
}

/// Records the HealthKit authorization scopes requested through the seam.
private actor AuthRecorder {
    private var shareRequests: [Set<HKSampleType>] = []
    private var readRequests: [Set<HKObjectType>] = []

    func record(share: Set<HKSampleType>, read: Set<HKObjectType>) {
        shareRequests.append(share)
        readRequests.append(read)
    }

    private var dietaryType: HKSampleType? {
        HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed)
    }
    private var bodyMassType: HKObjectType? {
        HKObjectType.quantityType(forIdentifier: .bodyMass)
    }

    var requestedDietaryShare: Bool {
        guard let dietaryType else { return false }
        return shareRequests.contains { $0.contains(dietaryType) }
    }
    var dietaryShareRequestCount: Int {
        guard let dietaryType else { return 0 }
        return shareRequests.filter { $0.contains(dietaryType) }.count
    }
    var requestedWorkoutShare: Bool {
        shareRequests.contains { $0.contains(HKObjectType.workoutType()) }
    }
    var requestedBodyMassRead: Bool {
        guard let bodyMassType else { return false }
        return readRequests.contains { $0.contains(bodyMassType) }
    }
}
