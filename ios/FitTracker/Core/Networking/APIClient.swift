//
//  APIClient.swift
//  Single entry point for every call to the FastAPI backend. Actor-isolated
//  URLSession wrapper with pluggable TokenProvider. Reusable across every
//  feature slice — no feature should ever instantiate URLSession directly.
//

import Foundation

/// Thread-safe shared date formatters. Apple documents ISO8601DateFormatter
/// and DateFormatter as safe to use concurrently for *reading* (parsing /
/// formatting) once fully configured. `nonisolated(unsafe)` declares that
/// invariant to the Swift 6 compiler.
private enum DateFormatters {
    nonisolated(unsafe) static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    nonisolated(unsafe) static let dateOnly: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

actor APIClient {
    private let baseURL: URL
    private let session: URLSession
    private let tokenProvider: (any TokenProvider)?
    private let decoder: JSONDecoder

    /// Optional 401 refresh coordinator, injected after construction via
    /// `setRefresher(_:)` because the typical refresher (AuthService) needs a
    /// reference to *this* client first, so they cannot be built in one step.
    /// When set, a 401 triggers a single refresh + one retry (see performRaw).
    ///
    /// Held in a lock-protected box so the setter can be `nonisolated` and
    /// callable synchronously from `production()` (which is not async) without
    /// hopping onto the actor; reads happen on the actor inside `performRaw`.
    private let refresherBox = RefresherBox()

    init(
        baseURL: URL = APIConfig.baseURL,
        tokenProvider: (any TokenProvider)? = nil,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
        self.tokenProvider = tokenProvider

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)
            if let d = DateFormatters.iso.date(from: s) { return d }
            if let d = DateFormatters.isoPlain.date(from: s) { return d }
            if let d = DateFormatters.dateOnly.date(from: s) { return d }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Cannot parse date: \(s)")
        }
        self.decoder = dec
    }

    /// Registers the 401 refresh coordinator. Synchronous + `nonisolated` so
    /// `production()` can wire `AuthService` (built with this client) back as
    /// the refresher without making the whole DI factory async.
    nonisolated func setRefresher(_ refresher: any TokenRefreshing) {
        refresherBox.set(refresher)
    }

    // MARK: - Public API

    /// GET decoded to `T`.
    func get<T: Decodable & Sendable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        let req = try buildRequest(path: path, method: "GET", query: query, body: nil as EmptyBody?)
        return try await perform(req)
    }

    /// POST Encodable body decoded to `T`.
    func post<T: Decodable & Sendable, B: Encodable & Sendable>(
        _ path: String, body: B
    ) async throws -> T {
        let req = try buildRequest(path: path, method: "POST", query: [:], body: body)
        return try await perform(req)
    }

    /// POST body returning no content.
    func postVoid<B: Encodable & Sendable>(_ path: String, body: B) async throws {
        let req = try buildRequest(path: path, method: "POST", query: [:], body: body)
        _ = try await performRaw(req)
    }

    /// PATCH Encodable body decoded to `T`.
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(
        _ path: String, body: B
    ) async throws -> T {
        let req = try buildRequest(path: path, method: "PATCH", query: [:], body: body)
        return try await perform(req)
    }

    /// PUT Encodable body decoded to `T`. Symmetrical to `post`; added for
    /// Slice 5 (`PUT /api/v1/nutrition/goals`).
    func put<T: Decodable & Sendable, B: Encodable & Sendable>(
        _ path: String, body: B
    ) async throws -> T {
        let req = try buildRequest(path: path, method: "PUT", query: [:], body: body)
        return try await perform(req)
    }

    /// DELETE no content.
    func delete(_ path: String) async throws {
        let req = try buildRequest(path: path, method: "DELETE", query: [:], body: nil as EmptyBody?)
        _ = try await performRaw(req)
    }

    // MARK: - Request building

    private struct EmptyBody: Encodable, Sendable {}

    private func buildRequest<B: Encodable & Sendable>(
        path: String, method: String, query: [String: String], body: B?
    ) throws -> URLRequest {
        guard var comps = URLComponents(
            url: baseURL.appendingPathComponent(path, isDirectory: false),
            resolvingAgainstBaseURL: false
        ) else {
            throw APIError.unknown("Bad URL: \(path)")
        }
        if !query.isEmpty {
            comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = comps.url else {
            throw APIError.unknown("Cannot assemble URL.")
        }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = tokenProvider?.currentAccessToken() {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            let enc = JSONEncoder()
            enc.dateEncodingStrategy = .iso8601
            req.httpBody = try enc.encode(body)
        }
        return req
    }

    // MARK: - Dispatch

    private func perform<T: Decodable & Sendable>(_ req: URLRequest) async throws -> T {
        let (data, _) = try await performRaw(req)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }
    }

    /// - Parameter allowRefresh: when `true` (the default), a 401 triggers a
    ///   single refresh + retry. The retry calls back in with `false` so it
    ///   can never refresh again — that one-shot flag is what bounds the loop.
    private func performRaw(_ req: URLRequest,
                            allowRefresh: Bool = true) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch let urlErr as URLError {
            if urlErr.code == .cancelled { throw APIError.cancelled }
            if urlErr.code == .notConnectedToInternet ||
               urlErr.code == .networkConnectionLost {
                throw APIError.offline
            }
            throw APIError.network(urlErr.localizedDescription)
        } catch {
            throw APIError.unknown(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.unknown("Non-HTTP response")
        }

        switch http.statusCode {
        case 200...299:
            return (data, http)
        case 401:
            // Attempt a one-shot refresh + retry. Only when refresh is still
            // allowed (not already a retry) and a coordinator is configured;
            // otherwise fall through to the legacy `.unauthorized`.
            if allowRefresh, let refresher = refresherBox.get() {
                return try await refreshAndRetry(req, refresher: refresher)
            }
            throw APIError.unauthorized
        case 404:
            throw APIError.notFound
        case 429:
            let retry = http.value(forHTTPHeaderField: "Retry-After").flatMap { Int($0) }
            throw APIError.rateLimited(retryAfterSeconds: retry)
        default:
            let detail = Self.extractDetail(from: data)
            throw APIError.server(status: http.statusCode, detail: detail)
        }
    }

    /// Refreshes the access token exactly once (the refresher itself is
    /// single-flight, so concurrent 401s collapse into one round-trip), swaps
    /// the new Bearer token onto the original request, and retries it a single
    /// time with `allowRefresh: false`. A failed refresh — or a retry that is
    /// itself 401 — surfaces `.unauthorized`. Actor reentrancy is safe: the
    /// `await` here is the only suspension, and the `false` flag guarantees a
    /// retried request cannot recurse back into this method.
    private func refreshAndRetry(_ original: URLRequest,
                                 refresher: any TokenRefreshing) async throws -> (Data, HTTPURLResponse) {
        let newToken: String
        do {
            newToken = try await refresher.refreshAccessToken()
        } catch {
            // Refresh failed → the session is unrecoverable.
            throw APIError.unauthorized
        }
        var retryReq = original
        retryReq.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
        return try await performRaw(retryReq, allowRefresh: false)
    }

    private static func extractDetail(from data: Data) -> String? {
        // FastAPI errors: { "detail": "…" } or { "detail": [{msg: ...}] }
        struct DetailWrapper: Decodable { let detail: StringOrArray? }
        enum StringOrArray: Decodable {
            case string(String)
            case array([FieldError])
            init(from decoder: Decoder) throws {
                if let s = try? decoder.singleValueContainer().decode(String.self) {
                    self = .string(s); return
                }
                let arr = try decoder.singleValueContainer().decode([FieldError].self)
                self = .array(arr)
            }
        }
        struct FieldError: Decodable { let msg: String? }

        guard let wrapper = try? JSONDecoder().decode(DetailWrapper.self, from: data),
              let detail = wrapper.detail else {
            return String(data: data, encoding: .utf8)
        }
        switch detail {
        case .string(let s): return s
        case .array(let errs): return errs.compactMap { $0.msg }.joined(separator: "; ")
        }
    }
}

/// Lock-protected holder for the optional `TokenRefreshing` coordinator so
/// `APIClient.setRefresher(_:)` can be a synchronous, `nonisolated` setter
/// while the actor reads the value safely on its own executor.
private final class RefresherBox: @unchecked Sendable {
    private let lock = NSLock()
    private var refresher: (any TokenRefreshing)?

    func set(_ refresher: any TokenRefreshing) {
        lock.lock(); defer { lock.unlock() }
        self.refresher = refresher
    }

    func get() -> (any TokenRefreshing)? {
        lock.lock(); defer { lock.unlock() }
        return refresher
    }
}
