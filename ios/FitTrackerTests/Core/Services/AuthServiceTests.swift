//
//  AuthServiceTests.swift
//  Slice 1.9: validates AuthService against a stubbed APIClient
//  (MockURLProtocol) without hitting the real backend. Covers token
//  persistence, silent refresh, refresh race serialization, sign-out,
//  and restoreSession failure modes.
//

import Foundation
import Testing
@testable import FitTracker

@Suite("AuthService", .serialized)
struct AuthServiceTests {

    init() { MockURLProtocol.reset() }

    /// Build an AuthService with optional Keychain pre-seeding so init
    /// observes the desired starting auth state.
    @MainActor
    private func makeSUT(seedAccess: String? = nil,
                         seedRefresh: String? = nil,
                         seedExpiry: Date? = nil) async -> (AuthService, KeychainTokenStore) {
        let session = MockURLProtocol.makeSession()
        let kc = KeychainTokenStore(service: "test.fittracker.\(UUID().uuidString)")
        kc.clearAll()
        if let seedAccess { await kc.updateAccessToken(seedAccess) }
        if let seedRefresh { await kc.updateRefreshToken(seedRefresh) }
        if let seedExpiry { await kc.updateAccessTokenExpiry(seedExpiry) }
        let api = APIClient(baseURL: URL(string: "http://test.local")!,
                            tokenProvider: nil,
                            session: session)
        return (AuthService(api: api, keychain: kc), kc)
    }

    private static let okTokensJSON = #"""
    {"access_token":"acc1","refresh_token":"ref1","token_type":"bearer","expires_in":3600}
    """#

    private static let meJSON = #"""
    {"id":"00000000-0000-0000-0000-000000C00001","email":"carlos@fittracker.dev","display_name":"Carlos","role":"user"}
    """#

    @MainActor
    @Test("login persists access + refresh tokens to keychain")
    func login_persistsTokens() async throws {
        let (sut, kc) = await makeSUT()
        defer { kc.clearAll() }

        MockURLProtocol.handler = { req in
            let body = req.url?.path ?? ""
            if body.hasSuffix("/auth/login") {
                return (Self.okResponse(req), Data(Self.okTokensJSON.utf8))
            }
            if body.hasSuffix("/auth/me") {
                return (Self.okResponse(req), Data(Self.meJSON.utf8))
            }
            return (Self.notFoundResponse(req), Data())
        }

        try await sut.login(email: "carlos@fittracker.dev", password: "test1234")
        #expect(sut.isAuthenticated)
        #expect(kc.currentAccessToken() == "acc1")
        #expect(kc.currentRefreshToken() == "ref1")
        #expect(kc.accessTokenExpiry() != nil)
        #expect(sut.currentUser?.email == "carlos@fittracker.dev")
    }

    @MainActor
    @Test("currentAccessTokenIfValid refreshes when access is near expiry")
    func silentRefresh_happensBeforeExpiry() async throws {
        // Seed: valid refresh, but access expires in 30s (under our 60s threshold)
        let (sut, kc) = await makeSUT(
            seedAccess: "old_acc",
            seedRefresh: "old_ref",
            seedExpiry: Date().addingTimeInterval(30)
        )
        defer { kc.clearAll() }
        _ = sut

        let counter = AtomicCounter()
        MockURLProtocol.handler = { req in
            if req.url?.path.hasSuffix("/auth/refresh") == true {
                counter.increment()
                let json = #"""
                {"access_token":"new_acc","refresh_token":"new_ref","token_type":"bearer","expires_in":3600}
                """#
                return (Self.okResponse(req), Data(json.utf8))
            }
            return (Self.notFoundResponse(req), Data())
        }

        let token = try await sut.currentAccessTokenIfValid()
        #expect(token == "new_acc")
        #expect(kc.currentRefreshToken() == "new_ref")
        #expect(counter.value == 1)
    }

    @MainActor
    @Test("concurrent refresh requests serialize through one network call")
    func refreshRaceIsSerialized() async throws {
        let (sut, kc) = await makeSUT(
            seedAccess: "old_acc",
            seedRefresh: "old_ref",
            seedExpiry: Date().addingTimeInterval(30)
        )
        defer { kc.clearAll() }
        _ = sut

        let counter = AtomicCounter()
        MockURLProtocol.handler = { req in
            if req.url?.path.hasSuffix("/auth/refresh") == true {
                counter.increment()
                // Simulate 50ms of latency so concurrent callers actually overlap.
                Thread.sleep(forTimeInterval: 0.05)
                let json = #"""
                {"access_token":"new_acc","refresh_token":"new_ref","token_type":"bearer","expires_in":3600}
                """#
                return (Self.okResponse(req), Data(json.utf8))
            }
            return (Self.notFoundResponse(req), Data())
        }

        async let a = sut.currentAccessTokenIfValid()
        async let b = sut.currentAccessTokenIfValid()
        async let c = sut.currentAccessTokenIfValid()
        let results = try await [a, b, c]
        #expect(results.allSatisfy { $0 == "new_acc" })
        #expect(counter.value == 1, "all 3 concurrent callers should share one refresh roundtrip")
    }

    @MainActor
    @Test("signOut clears keychain + isAuthenticated even if backend revoke fails")
    func signOut_alwaysClearsLocally() async throws {
        let (sut, kc) = await makeSUT(
            seedAccess: "acc",
            seedRefresh: "ref",
            seedExpiry: Date().addingTimeInterval(3600)
        )
        defer { kc.clearAll() }

        MockURLProtocol.handler = { req in
            // Backend "down" — return 500
            return (Self.serverError(req), Data())
        }

        await sut.signOut()
        #expect(!sut.isAuthenticated)
        #expect(kc.currentAccessToken() == nil)
        #expect(kc.currentRefreshToken() == nil)
        #expect(kc.accessTokenExpiry() == nil)
    }

    @MainActor
    @Test("restoreSession with bad refresh clears state")
    func restoreSession_failsCleanly() async {
        let (sut, kc) = await makeSUT(
            seedAccess: "expired_acc",
            seedRefresh: "expired_ref",
            seedExpiry: Date().addingTimeInterval(-100)
        )
        defer { kc.clearAll() }
        #expect(sut.isAuthenticated, "init should observe seeded tokens as authenticated")

        MockURLProtocol.handler = { req in
            // /auth/refresh returns 401 (token revoked / expired)
            return (Self.unauthorizedResponse(req), Data(#"{"detail":"refresh expired"}"#.utf8))
        }

        await sut.restoreSession()
        #expect(!sut.isAuthenticated)
        #expect(kc.currentAccessToken() == nil)
    }

    // MARK: - Helpers

    private static func okResponse(_ req: URLRequest) -> HTTPURLResponse {
        HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "1.1", headerFields: nil)!
    }
    private static func notFoundResponse(_ req: URLRequest) -> HTTPURLResponse {
        HTTPURLResponse(url: req.url!, statusCode: 404, httpVersion: "1.1", headerFields: nil)!
    }
    private static func unauthorizedResponse(_ req: URLRequest) -> HTTPURLResponse {
        HTTPURLResponse(url: req.url!, statusCode: 401, httpVersion: "1.1", headerFields: nil)!
    }
    private static func serverError(_ req: URLRequest) -> HTTPURLResponse {
        HTTPURLResponse(url: req.url!, statusCode: 500, httpVersion: "1.1", headerFields: nil)!
    }
}

/// Lock-protected counter for use in @Sendable test handlers.
final class AtomicCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0
    var value: Int {
        lock.lock(); defer { lock.unlock() }
        return _value
    }
    func increment() {
        lock.lock(); defer { lock.unlock() }
        _value += 1
    }
}
