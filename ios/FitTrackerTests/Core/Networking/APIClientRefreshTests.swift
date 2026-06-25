//
//  APIClientRefreshTests.swift
//  Codex P0 ("401 refresh"): authenticated API traffic must refresh an
//  expired access token on a 401, retry the original request once, and only
//  surface APIError.unauthorized when the refresh itself fails. Previously
//  APIClient threw .unauthorized on any 401 and never invoked the refresh
//  logic that lived in AuthService (codex-review-1 #2, codex-review-2 #2),
//  so users were forced into failures/sign-out the moment the access token
//  expired even with a valid refresh token on hand.
//
//  These tests drive a `TokenRefreshing` coordinator injected into the
//  APIClient via `setRefresher(_:)` and assert: (1) 401-then-success retries
//  exactly once, (2) a failing refresh surfaces .unauthorized, and (3) a
//  persistently-401 endpoint never loops — refresh fires once, the request
//  is attempted at most twice.
//

import Foundation
import Testing
@testable import FitTracker

@Suite("APIClient 401 → refresh → retry", .serialized)
struct APIClientRefreshTests {

    init() { MockURLProtocol.reset() }

    // MARK: - Stubs

    /// Records how many times `refreshAccessToken()` was called and what it
    /// does (return a fresh token, or throw).
    final class StubTokenRefresher: TokenRefreshing, @unchecked Sendable {
        enum Behavior: Sendable {
            case succeed(String)
            case fail(APIError)
        }
        let behavior: Behavior
        let calls = AtomicCounter()
        /// Optional sink so the test can mutate the token the provider returns
        /// after a successful refresh (mirrors AuthService persisting tokens).
        let onRefresh: (@Sendable (String) -> Void)?

        init(_ behavior: Behavior, onRefresh: (@Sendable (String) -> Void)? = nil) {
            self.behavior = behavior
            self.onRefresh = onRefresh
        }

        func refreshAccessToken() async throws -> String {
            calls.increment()
            switch behavior {
            case .succeed(let token):
                onRefresh?(token)
                return token
            case .fail(let err):
                throw err
            }
        }
    }

    /// Mutable in-memory token provider (the stock StubTokenProvider's setter
    /// is async; this one is synchronous so the refresher's `onRefresh` hook
    /// can swap the token between the original request and the retry).
    final class MutableTokenProvider: TokenProvider, @unchecked Sendable {
        private let lock = NSLock()
        private var token: String?
        init(_ token: String?) { self.token = token }
        func currentAccessToken() -> String? {
            lock.lock(); defer { lock.unlock() }; return token
        }
        func updateAccessToken(_ token: String?) async { set(token) }
        func set(_ token: String?) {
            lock.lock(); defer { lock.unlock() }; self.token = token
        }
    }

    // MARK: - 1. 401-then-success retries once

    @Test("401 then 200 refreshes once and retries the original request")
    func refresh_retriesOnceOnSuccess() async throws {
        let session = MockURLProtocol.makeSession()
        let attempts = AtomicCounter()
        let provider = MutableTokenProvider("stale")

        // First attempt (stale token) → 401; any later attempt → 200.
        MockURLProtocol.handler = { req in
            attempts.increment()
            let auth = req.value(forHTTPHeaderField: "Authorization")
            if auth == "Bearer fresh" {
                let resp = HTTPURLResponse(url: req.url!, statusCode: 200,
                                           httpVersion: "1.1", headerFields: nil)!
                return (resp, Data(#"{"status":"ok"}"#.utf8))
            }
            let resp = HTTPURLResponse(url: req.url!, statusCode: 401,
                                       httpVersion: "1.1", headerFields: nil)!
            return (resp, Data(#"{"detail":"expired"}"#.utf8))
        }

        let refresher = StubTokenRefresher(.succeed("fresh")) { newToken in
            provider.set(newToken)
        }
        let sut = APIClient(baseURL: URL(string: "http://test.local")!,
                            tokenProvider: provider, session: session)
        sut.setRefresher(refresher)

        let result: HealthResponse = try await sut.get("/protected")
        #expect(result.status == "ok")
        #expect(refresher.calls.value == 1, "refresh must fire exactly once")
        #expect(attempts.value == 2, "original request + one retry")
    }

    // MARK: - 2. refresh failure surfaces unauthorized

    @Test("failed refresh surfaces APIError.unauthorized")
    func refresh_failureSurfacesUnauthorized() async {
        let session = MockURLProtocol.makeSession()
        let attempts = AtomicCounter()
        MockURLProtocol.handler = { req in
            attempts.increment()
            let resp = HTTPURLResponse(url: req.url!, statusCode: 401,
                                       httpVersion: "1.1", headerFields: nil)!
            return (resp, Data(#"{"detail":"expired"}"#.utf8))
        }

        let refresher = StubTokenRefresher(.fail(.unauthorized))
        let sut = APIClient(baseURL: URL(string: "http://test.local")!,
                            tokenProvider: StubTokenProvider(token: "stale"),
                            session: session)
        sut.setRefresher(refresher)

        await #expect(throws: APIError.unauthorized) {
            let _: HealthResponse = try await sut.get("/protected")
        }
        #expect(refresher.calls.value == 1, "refresh attempted once")
        #expect(attempts.value == 1, "no retry when refresh fails")
    }

    // MARK: - 3. no infinite loop on persistent 401

    @Test("persistent 401 after refresh does not loop")
    func refresh_noInfiniteLoop() async {
        let session = MockURLProtocol.makeSession()
        let attempts = AtomicCounter()
        // Server ALWAYS returns 401, even with the refreshed token.
        MockURLProtocol.handler = { req in
            attempts.increment()
            let resp = HTTPURLResponse(url: req.url!, statusCode: 401,
                                       httpVersion: "1.1", headerFields: nil)!
            return (resp, Data(#"{"detail":"still expired"}"#.utf8))
        }

        let refresher = StubTokenRefresher(.succeed("fresh"))
        let sut = APIClient(baseURL: URL(string: "http://test.local")!,
                            tokenProvider: StubTokenProvider(token: "stale"),
                            session: session)
        sut.setRefresher(refresher)

        await #expect(throws: APIError.unauthorized) {
            let _: HealthResponse = try await sut.get("/protected")
        }
        #expect(refresher.calls.value == 1, "refresh fires once, not per-attempt")
        #expect(attempts.value == 2, "original + exactly one retry, then give up")
    }

    // MARK: - 4. no refresher configured keeps legacy behavior

    @Test("with no refresher, a 401 still surfaces unauthorized immediately")
    func noRefresher_keepsLegacyBehavior() async {
        let session = MockURLProtocol.makeSession()
        let attempts = AtomicCounter()
        MockURLProtocol.handler = { req in
            attempts.increment()
            let resp = HTTPURLResponse(url: req.url!, statusCode: 401,
                                       httpVersion: "1.1", headerFields: nil)!
            return (resp, Data(#"{"detail":"expired"}"#.utf8))
        }
        let sut = APIClient(baseURL: URL(string: "http://test.local")!,
                            tokenProvider: StubTokenProvider(token: "stale"),
                            session: session)

        await #expect(throws: APIError.unauthorized) {
            let _: HealthResponse = try await sut.get("/protected")
        }
        #expect(attempts.value == 1, "no refresher means no retry")
    }
}
