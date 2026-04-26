//
//  ProgramsServiceTests.swift
//  Slice 6.1: backend-backed programs service with SwiftData cache.
//  Validates list/detail decoding, cache reuse on a second call, and
//  offline fallback to the local store.
//

import Foundation
import SwiftData
import Testing
@testable import FitTracker

@Suite("ProgramsService", .serialized)
struct ProgramsServiceTests {

    init() { MockURLProtocol.reset() }

    @MainActor
    private func makeSUT() throws -> (ProgramsService, ModelContainer) {
        let session = MockURLProtocol.makeSession()
        let api = APIClient(baseURL: URL(string: "http://test.local")!,
                            tokenProvider: nil,
                            session: session)
        let container = try PersistenceController.makeInMemory().container
        return (ProgramsService(api: api, container: container), container)
    }

    @MainActor
    @Test("allPrograms decodes /workouts/programs into domain models")
    func allPrograms_decodesAndCaches() async throws {
        let (sut, _) = try makeSUT()

        let json = """
        [
          {
            "id": "00000000-0000-0000-0000-00000000B001",
            "name": "PPL — Push / Pull / Legs",
            "description": "6 dias",
            "program_type": "ppl",
            "days_per_week": 6,
            "difficulty": "intermediate",
            "is_preset": true
          },
          {
            "id": "00000000-0000-0000-0000-00000000B002",
            "name": "Upper / Lower",
            "description": null,
            "program_type": null,
            "days_per_week": 4,
            "difficulty": "intermediate",
            "is_preset": true
          }
        ]
        """
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200,
                                       httpVersion: "1.1", headerFields: nil)!
            return (resp, Data(json.utf8))
        }

        let programs = try await sut.allPrograms()
        #expect(programs.count == 2)
        #expect(programs.first?.name.contains("PPL") == true)
        #expect(programs.first?.daysPerWeek == 6)
        #expect(programs.first?.difficulty == .intermediate)
    }

    @MainActor
    @Test("allPrograms falls back to SwiftData cache when offline")
    func allPrograms_offlineFallbackHitsCache() async throws {
        let (sut, container) = try makeSUT()

        // Pre-seed the cache directly via SwiftData — pretend we synced once.
        let ctx = ModelContext(container)
        let cached = WorkoutProgramEntity(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000B003")!,
            name: "Full Body 3x",
            summary: "3 dias",
            daysPerWeek: 3,
            difficulty: "beginner"
        )
        ctx.insert(cached)
        try ctx.save()

        // Simulate offline.
        MockURLProtocol.handler = { _ in
            throw URLError(.notConnectedToInternet)
        }

        let programs = try await sut.allPrograms()
        #expect(programs.count == 1)
        #expect(programs.first?.name == "Full Body 3x")
    }

    @MainActor
    @Test("program(id:) decodes nested days + exercises")
    func program_decodesDetail() async throws {
        let (sut, _) = try makeSUT()

        let pid = "00000000-0000-0000-0000-00000000B001"
        let detailJSON = """
        {
          "id": "\(pid)",
          "name": "PPL",
          "description": "test",
          "program_type": "ppl",
          "days_per_week": 6,
          "difficulty": "intermediate",
          "is_preset": true,
          "days": [
            {
              "id": "00000000-0000-0000-0000-00000000D001",
              "day_number": 1,
              "day_name": "Push",
              "focus": null,
              "description": null,
              "exercises": [
                {
                  "id": "00000000-0000-0000-0000-00000000E001",
                  "exercise": {
                    "id": "00000000-0000-0000-0000-0000000E0001",
                    "name": "Bench Press",
                    "primary_muscle": "chest",
                    "secondary_muscles": "shoulders,arms",
                    "equipment": "barbell",
                    "difficulty": "intermediate",
                    "instructions": null,
                    "video_url": null,
                    "category": null
                  },
                  "set_count": 4,
                  "rep_min": 6,
                  "rep_max": 8,
                  "rest_seconds": 120,
                  "exercise_order": 1,
                  "notes": null
                }
              ]
            }
          ]
        }
        """
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200,
                                       httpVersion: "1.1", headerFields: nil)!
            return (resp, Data(detailJSON.utf8))
        }

        let p = try await sut.program(id: UUID(uuidString: pid)!)
        #expect(p?.days.count == 1)
        #expect(p?.days.first?.exercises.first?.exerciseName == "Bench Press")
        #expect(p?.days.first?.exercises.first?.sets == 4)
        #expect(p?.days.first?.exercises.first?.repsLow == 6)
        #expect(p?.days.first?.exercises.first?.repsHigh == 8)
    }
}
