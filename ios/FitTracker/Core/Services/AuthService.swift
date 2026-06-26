//
//  AuthService.swift
//  Real auth service backed by APIClient + KeychainTokenStore. Replaces
//  MockAuthService for production wiring (mocks remain for previews and
//  for Slice 0.5 tap-through compatibility).
//
//  Uses an actor for thread safety. The refresh path is guarded by an
//  AsyncSemaphore so concurrent API calls across the app never trigger
//  duplicate refresh requests — the first call refreshes, the rest wait
//  and reuse the new access token. See ADR-0003.
//

import Foundation
import Observation

@MainActor
@Observable
final class AuthService: AuthServiceProtocol, TokenRefreshing {

    // MARK: - Public observable state (read by AppRoot / AuthGate)

    private(set) var isAuthenticated: Bool
    private(set) var currentUser: MockUser?

    // MARK: - Dependencies

    private let api: APIClient
    private let keychain: KeychainTokenStore
    /// The app-wide durable offline queue. On sign-out we purge the
    /// signed-out user's queued writes from it so they can NEVER replay
    /// under the next account (Codex review #4 P0). Defaults to
    /// `OfflineQueue.shared` — the exact instance SyncManager drains and
    /// MealService enqueues into — so production wiring needs no extra
    /// plumbing; tests inject an isolated queue (or `nil` to opt out).
    private let offlineQueue: OfflineQueue?

    /// Single in-flight refresh Task. Concurrent callers needing a fresh
    /// access token await the same task, ensuring only one network round
    /// trip per refresh window. See ADR-0003.
    private var inFlightRefresh: Task<String, Error>?

    init(api: APIClient? = nil,
         keychain: KeychainTokenStore = .shared,
         offlineQueue: OfflineQueue? = .shared) {
        self.keychain = keychain
        self.offlineQueue = offlineQueue
        // The APIClient must read tokens from the same Keychain so its
        // Bearer header reflects whatever AuthService just persisted.
        self.api = api ?? APIClient(tokenProvider: keychain)
        // Initial state: trust the Keychain. AuthGate calls
        // restoreSession() on first appear, which hydrates currentUser
        // and falls back to login if the refresh fails.
        self.isAuthenticated = keychain.currentAccessToken() != nil
                              || keychain.currentRefreshToken() != nil
        self.currentUser = nil
    }

    /// Called by AuthGate on first appear. If a session is present,
    /// validates by calling /auth/me (refreshing the access token if
    /// needed). On failure flips isAuthenticated back to false so the
    /// gate routes to LoginView.
    func restoreSession() async {
        guard isAuthenticated else { return }
        do {
            // Will refresh if access token is near expiry
            _ = try await currentAccessTokenIfValid()
            try await loadCurrentUser()
        } catch {
            keychain.clearAll()
            currentUser = nil
            isAuthenticated = false
        }
    }

    // MARK: - Auth flows

    func login(email: String, password: String) async throws {
        let body = LoginRequest(email: email, password: password)
        let tokens: AuthTokens = try await api.post("/api/v1/auth/login", body: body)
        await persist(tokens: tokens)
        try await loadCurrentUser()
        isAuthenticated = true
    }

    func register(email: String, password: String, displayName: String) async throws {
        let body = RegisterRequest(email: email, password: password, display_name: displayName)
        let tokens: AuthTokens = try await api.post("/api/v1/auth/register", body: body)
        await persist(tokens: tokens)
        try await loadCurrentUser()
        isAuthenticated = true
    }

    func signInWithApple(identityToken: String,
                         userIdentifier: String,
                         email: String?,
                         fullName: PersonNameComponents?) async throws {
        let appleName = AppleSignInRequest.AppleFullName(
            firstName: fullName?.givenName,
            lastName: fullName?.familyName
        )
        let body = AppleSignInRequest(
            identity_token: identityToken,
            user_identifier: userIdentifier,
            email: email,
            full_name: appleName
        )
        let tokens: AuthTokens = try await api.post("/api/v1/auth/apple", body: body)
        await persist(tokens: tokens)
        try await loadCurrentUser()
        isAuthenticated = true
    }

    func signOut() async {
        // Capture WHO is signing out before we tear down state, so we can
        // purge exactly their queued writes from the shared offline queue.
        // This is the sign-out half of the cross-user replay fix (Codex
        // review #4 P0): even though SyncManager owner-guards replay, we also
        // drop the signed-out user's mutations here so a stale write can never
        // linger and replay under the next account. Crash-safe (single atomic
        // UserDefaults write). Account deletion routes through sign-out too.
        let signingOutUserId = currentUser?.id

        // Best-effort server-side revocation; ignore failures so local logout
        // always succeeds even when offline.
        if let refresh = keychain.currentRefreshToken() {
            _ = try? await api.postVoid("/api/v1/auth/logout", body: RefreshRequest(refresh_token: refresh))
        }
        if let signingOutUserId {
            await offlineQueue?.removeAll(ownedBy: signingOutUserId)
        }
        keychain.clearAll()
        currentUser = nil
        isAuthenticated = false
    }

    /// Returns the access token, refreshing first when it's expired or
    /// near-expiring (≤60s from expiry). Throws if no valid session.
    func currentAccessTokenIfValid() async throws -> String {
        if let access = keychain.currentAccessToken(), !isExpiringSoon() {
            return access
        }
        return try await refreshSingleFlight()
    }

    /// `TokenRefreshing` conformance. Called by `APIClient` when a request
    /// comes back 401: the access token the server just rejected is stale
    /// regardless of its local expiry clock, so this ALWAYS forces a refresh
    /// (no near-expiry short-circuit) and returns the new token. Shares the
    /// same single-flight task as `currentAccessTokenIfValid()`, so a wave of
    /// concurrent 401s across the app still collapses into one refresh
    /// round-trip (see ADR-0003).
    func refreshAccessToken() async throws -> String {
        try await refreshSingleFlight()
    }

    /// Performs a refresh, deduplicating concurrent callers onto one in-flight
    /// `Task` so only a single `/auth/refresh` round-trip runs per window.
    private func refreshSingleFlight() async throws -> String {
        // Reuse an in-flight refresh if one is already running.
        if let task = inFlightRefresh {
            return try await task.value
        }
        let task = Task<String, Error> { [weak self] in
            guard let self else { throw APIError.unauthorized }
            try await self.refreshNow()
            guard let fresh = self.keychain.currentAccessToken() else {
                throw APIError.unauthorized
            }
            return fresh
        }
        inFlightRefresh = task
        defer { inFlightRefresh = nil }
        return try await task.value
    }

    // MARK: - Private

    private func loadCurrentUser() async throws {
        let resp: AuthMeResponse = try await api.get("/api/v1/auth/me")
        let id = UUID(uuidString: resp.id) ?? UUID()
        currentUser = MockUser(id: id, email: resp.email, displayName: resp.display_name, createdAt: Date())
    }

    private func persist(tokens: AuthTokens) async {
        await keychain.updateAccessToken(tokens.access_token)
        await keychain.updateRefreshToken(tokens.refresh_token)
        let expires = Date().addingTimeInterval(TimeInterval(tokens.expires_in))
        await keychain.updateAccessTokenExpiry(expires)
    }

    private func isExpiringSoon() -> Bool {
        guard let expires = keychain.accessTokenExpiry() else { return true }
        return expires.timeIntervalSinceNow < 60
    }

    private func refreshNow() async throws {
        guard let refresh = keychain.currentRefreshToken() else {
            throw APIError.unauthorized
        }
        do {
            let tokens: AuthTokens = try await api.post(
                "/api/v1/auth/refresh",
                body: RefreshRequest(refresh_token: refresh)
            )
            await persist(tokens: tokens)
        } catch {
            // Refresh failed — clear session so AuthGate flips to LoginView.
            keychain.clearAll()
            currentUser = nil
            isAuthenticated = false
            throw error
        }
    }
}

