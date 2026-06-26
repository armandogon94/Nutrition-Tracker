//
//  AccountService.swift
//  Thin account-management service for destructive account actions
//  (currently just deletion). Exists so views never build their own
//  `APIClient(tokenProvider:)` for `DELETE /api/v1/users/me`: that ad-hoc
//  client reads the keychain token but has no `TokenRefreshing` coordinator,
//  so a normal expired access token yields a hard 401 instead of
//  refresh + retry (codex-review-4 P1).
//
//  Production wiring injects the ONE shared refresh-aware `APIClient`
//  (`MockServiceContainer.production()`); previews/tests inject the mock.
//

import Foundation

protocol AccountServiceProtocol: AnyObject, Sendable {
    /// Permanently deletes the authenticated user's account. A `404` means the
    /// backend route isn't deployed yet — callers degrade to a local sign-out
    /// (see `AccountDeletionModel`).
    func deleteAccount() async throws
}

/// Concrete account service backed by the shared authenticated `APIClient`,
/// so deletion inherits the 401 → refresh → retry path like every other call.
final class AccountService: AccountServiceProtocol, @unchecked Sendable {
    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    func deleteAccount() async throws {
        try await api.delete("/api/v1/users/me")
    }
}
