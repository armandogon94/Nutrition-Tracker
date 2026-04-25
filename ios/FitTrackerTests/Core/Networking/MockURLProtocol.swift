//
//  MockURLProtocol.swift
//  URLProtocol override for testing APIClient against canned responses
//  without hitting the network.
//

import Foundation
@testable import FitTracker

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        MockURLProtocol.lastRequest = request
        guard let handler = MockURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (resp, data) = try handler(request)
            client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    /// Returns a URLSession configured to route through this mock.
    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    static func reset() {
        handler = nil
        lastRequest = nil
    }
}

/// Minimal in-memory stub for TokenProvider.
final class StubTokenProvider: TokenProvider, @unchecked Sendable {
    private var token: String?
    init(token: String? = nil) { self.token = token }
    func currentAccessToken() -> String? { token }
    func updateAccessToken(_ token: String?) async { self.token = token }
}
