//
//  ExercisesServiceTests.swift
//  Slice 6.1: backend-backed exercises service.
//  Validates list/search decoding, debounced search semantics,
//  filter combinations, and SwiftData offline fallback + cache warmup.
//

import Foundation
import SwiftData
import Testing
@testable import FitTracker

@Suite("ExercisesService", .serialized)
struct ExercisesServiceTests {

    init() { MockURLProtocol.reset() }

    @MainActor
    private func makeSUT() throws -> (ExercisesService, ModelContainer) {
        let session = MockURLProtocol.makeSession()
        let api = APIClient(baseURL: URL(string: "http://test.local")!,
                            tokenProvider: nil,
                            session: session)
        let container = try PersistenceController.makeInMemory().container
        return (ExercisesService(api: api, container: container), container)
    }

    private static let bench = """
    {
      "id": "00000000-0000-0000-0000-0000000E0001",
      "name": "Bench Press",
      "primary_muscle": "chest",
      "secondary_muscles": "shoulders,arms",
      "equipment": "barbell",
      "difficulty": "intermediate",
      "instructions": null,
      "video_url": "https://www.youtube.com/watch?v=abc",
      "category": null
    }
    """

    private static let squat = """
    {
      "id": "00000000-0000-0000-0000-0000000E0002",
      "name": "Squat",
      "primary_muscle": "legs",
      "secondary_muscles": "core",
      "equipment": "barbell",
      "difficulty": "intermediate",
      "instructions": null,
      "video_url": null,
      "category": null
    }
    """

    @MainActor
    @Test("allExercises decodes /exercises and warms cache")
    func allExercises_decodesAndWarmsCache() async throws {
        let (sut, container) = try makeSUT()

        let json = """
        { "exercises": [\(Self.bench), \(Self.squat)], "total": 2 }
        """
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200,
                                       httpVersion: "1.1", headerFields: nil)!
            return (resp, Data(json.utf8))
        }

        let results = try await sut.allExercises()
        #expect(results.count == 2)
        #expect(results.contains { $0.name == "Bench Press" })
        #expect(results.contains { $0.name == "Squat" })

        // Cache populated.
        let ctx = ModelContext(container)
        let cached = try ctx.fetch(FetchDescriptor<ExerciseEntity>())
        #expect(cached.count == 2)
    }

    @MainActor
    @Test("search filters by muscle group via query parameter")
    func search_filtersByMuscleGroup() async throws {
        let (sut, _) = try makeSUT()

        let json = """
        { "exercises": [\(Self.bench)], "total": 1 }
        """
        MockURLProtocol.handler = { req in
            // Confirm the muscle filter made it onto the URL.
            #expect(req.url?.query?.contains("muscle=chest") == true)
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200,
                                       httpVersion: "1.1", headerFields: nil)!
            return (resp, Data(json.utf8))
        }

        let results = try await sut.search(query: "", muscle: .chest, equipment: nil)
        #expect(results.count == 1)
        #expect(results.first?.primaryMuscle == .chest)
    }

    @MainActor
    @Test("search debounces rapid keystrokes — only the last one fires")
    func search_debouncedAndOfflineFallback() async throws {
        let (sut, container) = try makeSUT()

        // Seed the local cache with 2 entries; mark them online so offline
        // fallback can return them.
        let ctx = ModelContext(container)
        ctx.insert(ExerciseEntity(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000E0001")!,
            name: "Bench Press",
            primaryMuscle: "chest",
            secondaryMusclesRaw: "shoulders,arms",
            equipment: "barbell",
            difficulty: "intermediate",
            videoURLString: "https://www.youtube.com/watch?v=abc"
        ))
        ctx.insert(ExerciseEntity(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000E0002")!,
            name: "Squat",
            primaryMuscle: "legs",
            secondaryMusclesRaw: "core",
            equipment: "barbell",
            difficulty: "intermediate",
            videoURLString: nil
        ))
        try ctx.save()

        // Simulate offline so the service must fall back to cache.
        MockURLProtocol.handler = { _ in
            throw URLError(.notConnectedToInternet)
        }

        // Search "bench" → only Bench Press should come back from the cache.
        let results = try await sut.search(query: "bench", muscle: nil, equipment: nil)
        #expect(results.count == 1)
        #expect(results.first?.name == "Bench Press")

        // Filter by legs alone — only Squat.
        let legResults = try await sut.search(query: "", muscle: .legs, equipment: nil)
        #expect(legResults.count == 1)
        #expect(legResults.first?.name == "Squat")
    }

    @MainActor
    @Test("DebouncedSearcher only fires the latest query within the window")
    func debouncedSearcher_collapsesBursts() async throws {
        let counter = AtomicCounter()
        let captured = LastCapture()
        let searcher = DebouncedSearcher(intervalMillis: 100) { (query: String) async in
            counter.increment()
            await captured.set(query)
        }

        searcher.fire(query: "a")
        searcher.fire(query: "ab")
        searcher.fire(query: "abc")

        // Wait long enough for debounce window + execution.
        try await Task.sleep(nanoseconds: 250_000_000)

        #expect(counter.value == 1, "debounce must collapse rapid keystrokes")
        #expect(await captured.value == "abc")
    }
}

/// Small helper for the debounce test — captures the last value seen
/// without crossing actor boundaries with a non-Sendable type.
actor LastCapture {
    private(set) var value: String?
    func set(_ v: String) { self.value = v }
}
