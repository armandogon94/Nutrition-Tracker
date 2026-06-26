//
//  ProgramDetailHydrationTests.swift
//  codex-review-4 P1 ("Program detail still cannot hydrate days in normal
//  production navigation"): the list endpoint maps `days: []`, and
//  `ProgramDetailView.loadDays()` used to only call `service.program(id:)`
//  when an explicit `injectedService` was present — which is nil in
//  production. So real backend programs showed a "no days" detail screen and
//  the user could never start the workout.
//
//  The view fix resolves the service from the environment container (so
//  `loadDays()` always has one). This test pins the underlying contract the
//  fixed view depends on: a program coming from the LIST has empty `days`, and
//  fetching that same program by id via the SAME service hydrates the days +
//  exercises. If `program(id:)` regressed (or the list started leaking days),
//  this fails.
//

import Foundation
import SwiftData
import Testing
@testable import FitTracker

@Suite("Program list → detail day hydration", .serialized)
struct ProgramDetailHydrationTests {

    init() { MockURLProtocol.reset() }

    @MainActor
    private func makeService() throws -> ProgramsService {
        let session = MockURLProtocol.makeSession()
        let api = APIClient(baseURL: URL(string: "http://test.local")!,
                            tokenProvider: nil, session: session)
        let container = try PersistenceController.makeInMemory().container
        return ProgramsService(api: api, container: container)
    }

    /// The id shared between the list row and the detail fetch — the exact
    /// hand-off the detail screen performs.
    private static let pid = "00000000-0000-0000-0000-00000000B001"

    private static let listJSON = """
    [
      {
        "id": "\(pid)",
        "name": "PPL — Push / Pull / Legs",
        "description": "6 dias",
        "program_type": "ppl",
        "days_per_week": 6,
        "difficulty": "intermediate",
        "is_preset": true
      }
    ]
    """

    private static let detailJSON = """
    {
      "id": "\(pid)",
      "name": "PPL — Push / Pull / Legs",
      "description": "6 dias",
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

    @MainActor
    @Test("A program from the list has no days; the detail fetch by the same id hydrates them")
    func listProgram_isHydratedByDetailFetch() async throws {
        let sut = try makeService()

        // 1. List load — this is what populates ProgramsListView. It returns
        //    the program WITHOUT days (the backend list contract).
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200,
                                       httpVersion: "1.1", headerFields: nil)!
            return (resp, Data(Self.listJSON.utf8))
        }
        let listed = try await sut.allPrograms()
        let listProgram = try #require(listed.first)
        #expect(listProgram.id == UUID(uuidString: Self.pid))
        #expect(listProgram.days.isEmpty,
                "list DTOs intentionally map days: [] — this is the gap detail must close")

        // 2. Detail hydration — exactly what the fixed loadDays() does for a
        //    list-sourced program with empty days: fetch by the SAME id.
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200,
                                       httpVersion: "1.1", headerFields: nil)!
            return (resp, Data(Self.detailJSON.utf8))
        }
        let detail = try #require(try await sut.program(id: listProgram.id))
        #expect(detail.days.count == 1, "detail fetch must hydrate the days")
        #expect(detail.days.first?.dayName == "Push")
        #expect(detail.days.first?.exercises.first?.exerciseName == "Bench Press")
        #expect(detail.days.first?.exercises.first?.sets == 4)
    }
}
