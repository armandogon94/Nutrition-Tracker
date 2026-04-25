//
//  APIClientTests.swift
//  Covers GET decode happy path, 401 → APIError.unauthorized,
//  and Bearer token attachment from TokenProvider.
//

import Foundation
import Testing
@testable import FitTracker

@Suite("APIClient", .serialized)
struct APIClientTests {

    init() { MockURLProtocol.reset() }

    @Test("GET decodes JSON to target type")
    func apiClient_getsJsonAndDecodes() async throws {
        let session = MockURLProtocol.makeSession()
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "1.1", headerFields: nil)!
            return (resp, Data(#"{"status":"ok"}"#.utf8))
        }

        let sut = APIClient(
            baseURL: URL(string: "http://test.local")!,
            session: session
        )

        let result: HealthResponse = try await sut.get("/health")
        #expect(result.status == "ok")
    }

    @Test("401 response surfaces APIError.unauthorized")
    func apiClient_throwsUnauthorizedOn401() async throws {
        let session = MockURLProtocol.makeSession()
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 401, httpVersion: "1.1", headerFields: nil)!
            return (resp, Data(#"{"detail":"not auth"}"#.utf8))
        }

        let sut = APIClient(
            baseURL: URL(string: "http://test.local")!,
            session: session
        )

        await #expect(throws: APIError.unauthorized) {
            let _: HealthResponse = try await sut.get("/protected")
        }
    }

    @Test("Attaches Bearer token from TokenProvider")
    func apiClient_attachesBearerToken() async throws {
        let session = MockURLProtocol.makeSession()
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "1.1", headerFields: nil)!
            return (resp, Data(#"{"status":"ok"}"#.utf8))
        }

        let tokenProvider = StubTokenProvider(token: "abc123")
        let sut = APIClient(
            baseURL: URL(string: "http://test.local")!,
            tokenProvider: tokenProvider,
            session: session
        )

        let _: HealthResponse = try await sut.get("/any")
        #expect(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer abc123")
    }

    @Test("429 rate-limited surfaces retry-after when present")
    func apiClient_rateLimited() async throws {
        let session = MockURLProtocol.makeSession()
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(
                url: req.url!, statusCode: 429, httpVersion: "1.1",
                headerFields: ["Retry-After": "42"]
            )!
            return (resp, Data("{}".utf8))
        }

        let sut = APIClient(
            baseURL: URL(string: "http://test.local")!,
            session: session
        )

        await #expect(throws: APIError.rateLimited(retryAfterSeconds: 42)) {
            let _: HealthResponse = try await sut.get("/any")
        }
    }

    @Test("Server 5xx surfaces with detail extracted from FastAPI envelope")
    func apiClient_serverError() async throws {
        let session = MockURLProtocol.makeSession()
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 500, httpVersion: "1.1", headerFields: nil)!
            return (resp, Data(#"{"detail":"boom"}"#.utf8))
        }

        let sut = APIClient(
            baseURL: URL(string: "http://test.local")!,
            session: session
        )

        await #expect(throws: APIError.server(status: 500, detail: "boom")) {
            let _: HealthResponse = try await sut.get("/crash")
        }
    }
}
