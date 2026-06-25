//
//  TokenRefreshing.swift
//  Decouples APIClient's 401 interceptor from AuthService. APIClient calls
//  `refreshAccessToken()` once when a request comes back 401, then retries
//  the original request with the returned token. AuthService conforms by
//  reusing its existing single-flight refresh (see ADR-0003), so concurrent
//  401s across the app collapse into a single refresh round-trip.
//
//  Kept separate from `TokenProvider` (which only *reads* the current token)
//  so previews/tests can inject a lightweight refresher stub without the
//  full AuthService graph.
//

import Foundation

protocol TokenRefreshing: AnyObject, Sendable {
    /// Forces a token refresh and returns the new access token. Throws when
    /// no valid session can be re-established (e.g. the refresh token is
    /// expired/revoked), which the caller surfaces as `APIError.unauthorized`.
    func refreshAccessToken() async throws -> String
}
