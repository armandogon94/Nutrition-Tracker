//
//  ProfileServiceTests.swift
//  Slice 5 (Task 5.1) — verifies ProfileService against a stubbed APIClient.
//  Covers profile create-or-update, TDEE fetch, preset save, custom goal
//  save, and validation guards that mirror backend Pydantic constraints.
//

import Foundation
import Testing
@testable import FitTracker

@Suite("ProfileService", .serialized)
struct ProfileServiceTests {

    init() { MockURLProtocol.reset() }

    @MainActor
    private func makeSUT() -> ProfileService {
        let session = MockURLProtocol.makeSession()
        let api = APIClient(
            baseURL: URL(string: "http://test.local")!,
            tokenProvider: nil,
            session: session
        )
        return ProfileService(api: api)
    }

    private static func ok(_ req: URLRequest, body: String) -> (HTTPURLResponse, Data) {
        let resp = HTTPURLResponse(
            url: req.url!, statusCode: 200, httpVersion: "1.1", headerFields: nil
        )!
        return (resp, Data(body.utf8))
    }

    private static func notFound(_ req: URLRequest) -> (HTTPURLResponse, Data) {
        let resp = HTTPURLResponse(
            url: req.url!, statusCode: 404, httpVersion: "1.1", headerFields: nil
        )!
        return (resp, Data())
    }

    private static let tdeeResponseJSON = #"""
    {
      "bmr": 1780.0,
      "tdee": 2759.0,
      "activity_level": "moderate",
      "goal_preset": "maintenance",
      "daily_calories": 2759,
      "daily_protein_g": 160,
      "daily_fat_g": 76,
      "daily_carbs_g": 354
    }
    """#

    private static let profileResponseJSON = #"""
    {
      "weight_kg": 80.0,
      "height_cm": 180.0,
      "age": 30,
      "sex": "male",
      "activity_level": "moderate",
      "bmr": 1780.0,
      "tdee": 2759.0,
      "goal_preset": "maintenance",
      "daily_calories": 2759,
      "daily_protein_g": 160,
      "daily_carbs_g": 354,
      "daily_fat_g": 76
    }
    """#

    // MARK: - profile()

    @MainActor
    @Test("profile() reads /profile/tdee and populates UserProfile fields from server")
    func profile_decodes() async throws {
        let sut = makeSUT()
        MockURLProtocol.handler = { req in
            #expect(req.httpMethod == "GET")
            #expect(req.url?.path.hasSuffix("/profile/tdee") == true)
            return Self.ok(req, body: Self.tdeeResponseJSON)
        }
        let p = try await sut.profile()
        #expect(p.activity == .moderate)
        #expect(p.weightKg > 0)
    }

    @MainActor
    @Test("profile() returns sensible defaults when no profile exists yet (404)")
    func profile_defaultsOn404() async throws {
        let sut = makeSUT()
        MockURLProtocol.handler = { req in Self.notFound(req) }
        let p = try await sut.profile()
        #expect(p.age >= 13 && p.age <= 120)
        #expect(p.weightKg >= 30 && p.weightKg <= 250)
    }

    // MARK: - updateProfile()

    @MainActor
    @Test("updateProfile() POSTs profile body with snake_case keys to /profile")
    func updateProfile_postsCorrectBody() async throws {
        let sut = makeSUT()
        let captured = ProfileServiceTests.RequestRecorder()
        MockURLProtocol.handler = { req in
            captured.record(req)
            return Self.ok(req, body: Self.profileResponseJSON)
        }
        let p = UserProfile(
            weightKg: 80, heightCm: 180, age: 30, sex: .male, activity: .moderate
        )
        try await sut.updateProfile(p)
        #expect(captured.method == "POST")
        #expect(captured.path?.hasSuffix("/profile") == true)
        let body = captured.bodyJSON ?? [:]
        #expect((body["weight_kg"] as? Double) == 80.0)
        #expect((body["height_cm"] as? Double) == 180.0)
        #expect((body["age"] as? Int) == 30)
        #expect((body["sex"] as? String) == "male")
        #expect((body["activity_level"] as? String) == "moderate")
    }

    @MainActor
    @Test("updateProfile() rejects out-of-range weight client-side (no network call)")
    func updateProfile_rejectsBadWeight() async {
        let sut = makeSUT()
        let didCall = AtomicCounter()
        MockURLProtocol.handler = { req in
            didCall.increment()
            return Self.ok(req, body: Self.profileResponseJSON)
        }
        let bad = UserProfile(
            weightKg: 1000, heightCm: 180, age: 30, sex: .male, activity: .moderate
        )
        await #expect(throws: ProfileError.self) {
            try await sut.updateProfile(bad)
        }
        #expect(didCall.value == 0, "must guard before hitting the network")
    }

    @MainActor
    @Test("updateProfile() rejects bad age client-side")
    func updateProfile_rejectsBadAge() async {
        let sut = makeSUT()
        MockURLProtocol.handler = { _ in
            (HTTPURLResponse(), Data())
        }
        let bad = UserProfile(
            weightKg: 80, heightCm: 180, age: 200, sex: .male, activity: .moderate
        )
        await #expect(throws: ProfileError.self) {
            try await sut.updateProfile(bad)
        }
    }

    // MARK: - goal()

    @MainActor
    @Test("goal() decodes /profile/tdee response into NutritionGoal")
    func goal_decodes() async throws {
        let sut = makeSUT()
        MockURLProtocol.handler = { req in
            #expect(req.url?.path.hasSuffix("/profile/tdee") == true)
            return Self.ok(req, body: Self.tdeeResponseJSON)
        }
        let g = try await sut.goal()
        #expect(g.dailyCalories == 2759)
        #expect(g.proteinG == 160)
        #expect(g.fatG == 76)
        #expect(g.carbsG == 354)
    }

    // MARK: - updatePreset()

    @MainActor
    @Test("updatePreset() POSTs goal_preset to /profile/goals")
    func updatePreset_postsBody() async throws {
        let sut = makeSUT()
        let captured = ProfileServiceTests.RequestRecorder()
        MockURLProtocol.handler = { req in
            captured.record(req)
            return Self.ok(req, body: Self.tdeeResponseJSON)
        }
        try await sut.updatePreset(.fatLoss)
        #expect(captured.method == "POST")
        #expect(captured.path?.hasSuffix("/profile/goals") == true)
        let body = captured.bodyJSON ?? [:]
        #expect((body["goal_preset"] as? String) == "fat_loss")
    }

    // MARK: - updateGoal() (custom)

    @MainActor
    @Test("updateGoal() routes a custom NutritionGoal to PUT /nutrition/goals")
    func updateGoal_customPath() async throws {
        let sut = makeSUT()
        let captured = ProfileServiceTests.RequestRecorder()
        MockURLProtocol.handler = { req in
            captured.record(req)
            let json = #"""
            {"daily_calories":1900,"daily_protein_g":150,"daily_carbs_g":190,"daily_fat_g":63}
            """#
            return Self.ok(req, body: json)
        }
        let custom = NutritionGoal(
            dailyCalories: 1900, proteinG: 150, carbsG: 190, fatG: 63, fiberG: 25
        )
        try await sut.updateGoal(custom)
        #expect(captured.method == "PUT")
        #expect(captured.path?.hasSuffix("/nutrition/goals") == true)
        let body = captured.bodyJSON ?? [:]
        #expect((body["daily_calories"] as? Int) == 1900)
        #expect((body["daily_protein_g"] as? Int) == 150)
    }

    @MainActor
    @Test("updateGoal() rejects calories below 800 (mirrors backend Field(ge=800))")
    func updateGoal_rejectsBadCalories() async {
        let sut = makeSUT()
        let bad = NutritionGoal(
            dailyCalories: 500, proteinG: 100, carbsG: 50, fatG: 20, fiberG: 0
        )
        await #expect(throws: ProfileError.self) {
            try await sut.updateGoal(bad)
        }
    }

    // MARK: - Helpers

    /// Captures the most recent stubbed request's metadata + body for
    /// assertions. Lock-protected so the @Sendable handler can write it.
    final class RequestRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var _method: String?
        private var _path: String?
        private var _bodyJSON: [String: Any]?

        var method: String? { lock.lock(); defer { lock.unlock() }; return _method }
        var path: String? { lock.lock(); defer { lock.unlock() }; return _path }
        var bodyJSON: [String: Any]? { lock.lock(); defer { lock.unlock() }; return _bodyJSON }

        func record(_ req: URLRequest) {
            lock.lock(); defer { lock.unlock() }
            _method = req.httpMethod
            _path = req.url?.path
            // URLProtocol strips httpBody. Read from httpBodyStream instead.
            if let stream = req.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var buf = [UInt8](repeating: 0, count: 4096)
                var data = Data()
                while stream.hasBytesAvailable {
                    let read = stream.read(&buf, maxLength: buf.count)
                    if read <= 0 { break }
                    data.append(buf, count: read)
                }
                _bodyJSON = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            } else if let body = req.httpBody {
                _bodyJSON = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
            }
        }
    }
}
