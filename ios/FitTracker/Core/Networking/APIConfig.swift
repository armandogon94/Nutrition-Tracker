//
//  APIConfig.swift
//  Centralizes the backend base URL. Reads `API_BASE_URL` from Info.plist
//  so each build configuration (Debug, Release, TestFlight) can target
//  a different backend without recompiling.
//
//  Release safety (review C1): a missing/misconfigured `API_BASE_URL` used to
//  silently fall back to `http://localhost:8001`, so a TestFlight build talked
//  to the device itself instead of production. We now keep the localhost
//  fallback ONLY in DEBUG; release builds fail fast (the value must be present,
//  HTTPS, and not localhost) so a misconfigured archive can never ship.
//

import Foundation

enum APIConfig {

    /// The reasons a resolved base URL is unacceptable for a release build.
    /// Surfaced in the `fatalError` message so a bad archive is obvious.
    private enum Rejection: CustomStringConvertible {
        case missing
        case unparseable(String)
        case notHTTPS(URL)
        case localhost(URL)

        var description: String {
            switch self {
            case .missing:
                return "API_BASE_URL is missing from Info.plist"
            case .unparseable(let raw):
                return "API_BASE_URL is not a valid URL: \(raw)"
            case .notHTTPS(let url):
                return "API_BASE_URL must use HTTPS in release builds: \(url.absoluteString)"
            case .localhost(let url):
                return "API_BASE_URL must not point at localhost in release builds: \(url.absoluteString)"
            }
        }
    }

    /// Resolved at module-load time from the Info.plist value injected by the
    /// per-configuration `API_BASE_URL` build setting.
    static let baseURL: URL = resolve(
        raw: Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String
    )

    /// Pure resolution logic, factored out so it is unit-testable without
    /// mutating the bundle. In DEBUG an absent/blank value falls back to the
    /// local dev backend; otherwise the value is validated and a release build
    /// traps on anything unsafe rather than silently using localhost.
    static func resolve(raw: String?) -> URL {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let trimmed, !trimmed.isEmpty, let url = URL(string: trimmed) {
            #if DEBUG
            return url
            #else
            if let rejection = releaseRejection(for: url) {
                fatalError("APIConfig: \(rejection)")
            }
            return url
            #endif
        }

        // Missing or unparseable.
        #if DEBUG
        return URL(string: "http://localhost:8001")!
        #else
        let rejection: Rejection = (trimmed?.isEmpty ?? true) ? .missing : .unparseable(trimmed ?? "")
        fatalError("APIConfig: \(rejection)")
        #endif
    }

    /// Returns the reason a URL is unacceptable for release, or nil if it's OK.
    /// Exposed (internal) so tests can assert the policy without DEBUG/Release
    /// compilation differences.
    static func releaseRejection(for url: URL) -> RejectionReason? {
        guard url.scheme?.lowercased() == "https" else { return .notHTTPS }
        let host = url.host?.lowercased() ?? ""
        let localHosts: Set<String> = ["localhost", "127.0.0.1", "::1", "0.0.0.0"]
        if localHosts.contains(host) || host.hasSuffix(".local") {
            return .localhost
        }
        return nil
    }

    /// Public-facing rejection reason for `releaseRejection(for:)` so tests can
    /// match on it. Mirrors the private `Rejection` cases that carry no payload.
    enum RejectionReason: Equatable {
        case notHTTPS
        case localhost
    }
}
