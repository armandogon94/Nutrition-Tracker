//
//  SyncManager.swift
//  Coordinates network reads + queued writes against the FastAPI backend.
//  Slice 2.2.
//
//  Read pattern (stale-while-revalidate): callers ask SwiftData first,
//  and SyncManager kicks off a background fetch that upserts on success.
//  Implementation per service in Slices 2.3–8.
//
//  Write pattern: callers `enqueue(...)` immediately; SyncManager attempts
//  to flush right away when online, otherwise queues until reconnect.
//  When Reachability flips to .online, drain runs automatically.
//

import Foundation
import SwiftData

@MainActor
final class SyncManager {

    private let api: APIClient
    private let queue: OfflineQueue
    private let reachability: Reachability
    /// Live SwiftData context used to reconcile local rows after a confirmed
    /// server write (clear `pendingSync` once a queued `.logMealItem` flushes).
    /// Optional so the read/queue-only tests can omit it; FitTrackerApp injects
    /// the live context so a background replay leaves the cache truthful.
    private let context: ModelContext?
    private var didWireDrainOnReconnect = false

    /// Resolves the currently signed-in user's id (the SAME id stamped onto
    /// every `PendingMutation`). Replay is owner-guarded against this: a
    /// queued write is only flushed when its `ownerId` matches, so user A's
    /// offline write never replays under user B's token after an account
    /// switch (Codex review #4 P0). FitTrackerApp wires this to
    /// `AuthService.currentUser?.id` via `setCurrentUserProvider`. When unset
    /// (or it returns nil — no one signed in) NOTHING is replayed, which is
    /// the safe default: better to hold writes than send them unowned.
    private var currentUserProvider: (@MainActor () -> UUID?)?

    /// Reads the LIVE auth-session generation (`AuthService.sessionGeneration`).
    /// Captured alongside the owner when a replay begins so the request-level
    /// auth guard can detect a sign-out / account-switch that happens mid-drain
    /// — even a re-login as the SAME user bumps the generation (Codex review #5
    /// P0). Optional: when unset, replay falls back to owner-only guarding
    /// (the Wave-5 behavior), which is still safe for the cross-user case but
    /// does not catch the same-user re-auth race. FitTrackerApp wires this to
    /// `AuthService.sessionGeneration`.
    private var sessionGenerationProvider: (@MainActor () -> Int)?

    init(api: APIClient = APIClient(),
         queue: OfflineQueue = OfflineQueue(),
         reachability: Reachability = .shared,
         context: ModelContext? = nil) {
        self.api = api
        self.queue = queue
        self.reachability = reachability
        self.context = context
    }

    /// The queue this manager drains. Exposed so the app can hand the SAME
    /// instance to services that enqueue failed writes (e.g. MealService),
    /// guaranteeing one shared durable queue rather than two that never see
    /// each other's mutations.
    var offlineQueue: OfflineQueue { queue }

    /// Register the 401 → refresh → retry coordinator on the replay client.
    /// FitTrackerApp calls this once the live AuthService exists, so a queued
    /// write whose token expired offline still refreshes + retries on
    /// reconnect instead of dying with a 401. Forwards to the underlying
    /// `APIClient` (whose setter is itself `nonisolated`).
    func setRefresher(_ refresher: any TokenRefreshing) {
        api.setRefresher(refresher)
    }

    /// Register the source of truth for "who is signed in right now" so replay
    /// can owner-guard every mutation. FitTrackerApp calls this once with a
    /// closure reading `AuthService.currentUser?.id`. Until it's set, replay
    /// is a no-op (see `currentUserProvider`) — the queue is never flushed
    /// under an unknown identity. Kept as a closure (rather than holding the
    /// AuthService) so SyncManager stays free of a concrete auth dependency.
    func setCurrentUserProvider(_ provider: @escaping @MainActor () -> UUID?) {
        currentUserProvider = provider
    }

    /// Register the source of truth for the current auth-session generation so
    /// replay can bind each mutation to the exact session it was captured under
    /// (Codex review #5 P0). FitTrackerApp calls this with a closure reading
    /// `AuthService.sessionGeneration`. When unset, `drainNow` guards on owner
    /// id alone (Wave-5 behavior).
    func setSessionGenerationProvider(_ provider: @escaping @MainActor () -> Int) {
        sessionGenerationProvider = provider
    }

    /// Call once at app launch (FitTrackerApp). Wires the
    /// reachability-flip observer so queued writes drain automatically, then
    /// kicks off an immediate drain so anything left queued from a previous
    /// session (app killed mid-flush, or written while offline) is replayed
    /// as soon as we're online — not only on the NEXT reconnect.
    func startObservingConnectivity() {
        guard !didWireDrainOnReconnect else { return }
        didWireDrainOnReconnect = true
        reachability.onChange { [weak self] status in
            guard status == .online else { return }
            Task { @MainActor in await self?.drainNow() }
        }
        // Replay any leftover queue from a prior launch. This ALSO covers the
        // "path was already online before we subscribed" case, so the listener
        // above only needs to handle the NEXT online flip — no double drain.
        // `.unknown` (cold launch before NWPathMonitor's first callback) is
        // treated as worth-trying: drain stops on the first failure, so an
        // attempt while genuinely offline is cheap and self-correcting. NOTE:
        // at cold launch the current user is usually still nil here (AuthGate
        // restores later), so this drain flushes nothing — the leftover queue
        // is replayed once auth is established via `replayAfterAuthChange()`
        // (Codex review #5 P1).
        if reachability.status != .offline {
            Task { @MainActor in await self.drainNow() }
        }
    }

    /// Replay the queue right after the signed-in user becomes known
    /// (successful restore / login / register / Apple sign-in). Sync starts
    /// from `FitTrackerApp.task` BEFORE `AuthGate.restoreSession()` sets the
    /// user, so the launch drain runs with a nil user and flushes nothing; if
    /// reachability already went online, nothing else would re-trigger a drain.
    /// The app calls this once auth is established so the leftover queue from a
    /// prior session actually replays (Codex review #5 P1). Skips the network
    /// when offline — `.unknown` (pre-first-NWPathMonitor-callback) is treated
    /// as worth-trying, exactly like `startObservingConnectivity`; a drain
    /// while genuinely offline is cheap and self-correcting.
    func replayAfterAuthChange() async {
        guard reachability.status != .offline else { return }
        await drainNow()
    }

    /// Enqueue a write. If online, attempt an immediate flush; if that
    /// fails, the mutation stays queued for the next reconnect.
    func enqueue(_ mutation: PendingMutation) async {
        await queue.enqueue(mutation)
        if reachability.status == .online {
            await drainNow()
        }
    }

    /// Manually trigger a drain. Returns how many mutations succeeded. After
    /// draining, reconciles the local store: any mutation that left the queue
    /// (i.e. was confirmed by the server) has its corresponding `pendingSync`
    /// flag cleared, so a successful BACKGROUND replay leaves the cache
    /// truthful — not stuck "pending" forever.
    @discardableResult
    func drainNow() async -> Int {
        let api = self.api
        // Owner-guard: only replay the signed-in user's mutations. If we don't
        // yet know who's signed in (provider unset, or it returns nil because
        // no one is), replay NOTHING — never flush a queued write under an
        // unknown or mismatched identity (Codex review #4 P0). Once a provider
        // is wired (production), a missing current user means signed-out, so
        // holding the queue is exactly right.
        let currentUserId: UUID?
        if let provider = currentUserProvider {
            currentUserId = provider()
        } else {
            currentUserId = nil
        }
        guard let ownerId = currentUserId else { return 0 }

        // Capture the auth-session generation at the moment replay begins, so
        // each queued write is bound to the exact session it will be sent
        // under. The per-request `authGuard` (re-checked by APIClient before
        // the initial send AND before swapping a refreshed token on a 401)
        // compares the LIVE owner+generation to these captured values; a
        // sign-out or account switch A→B that lands mid-drain flips one of
        // them, aborting the send so A's mutation is never transmitted under
        // B's bearer (Codex review #5 P0). `nil` generation provider → fall
        // back to owner-only guarding (still safe for the cross-user case).
        let userProvider = currentUserProvider
        let genProvider = sessionGenerationProvider
        let capturedGeneration = genProvider?()

        // Snapshot before/after so we know exactly which mutations flushed.
        let before = await queue.peekAll()
        let drained = await queue.drain(ownedBy: ownerId) { mutation in
            // Re-evaluated on the MainActor against the live AuthService just
            // before the bytes are sent (and again across a 401 refresh).
            let authGuard: @Sendable () async -> Bool = {
                await MainActor.run {
                    let liveOwner = userProvider?()
                    let liveGen = genProvider?()
                    // Owner must still be the mutation's owner...
                    guard liveOwner == mutation.ownerId else { return false }
                    // ...and, when a generation provider exists, the session
                    // must be the SAME one captured when the drain began.
                    if let capturedGeneration {
                        return liveGen == capturedGeneration
                    }
                    return true
                }
            }
            try await Self.execute(mutation, with: api, authGuard: authGuard)
        }
        if drained > 0 {
            let stillQueued = Set(await queue.peekAll().map(\.id))
            let flushed = before.filter { !stillQueued.contains($0.id) }
            reconcileLocal(flushed)
        }
        return drained
    }

    /// Clear local `pendingSync` flags for writes the server has now confirmed.
    /// Runs on the MainActor with the live context (never inside the actor's
    /// `@Sendable` drain closure, where a non-Sendable `ModelContext` could
    /// not be captured). A `.deleteMealItem` has no local row to update (it was
    /// already removed optimistically), so only `.logMealItem` is reconciled.
    private func reconcileLocal(_ flushed: [PendingMutation]) {
        guard let context else { return }
        var didChange = false
        for mutation in flushed {
            guard case .logMealItem(let payload) = mutation else { continue }
            let itemId = payload.clientItemId
            let descriptor = FetchDescriptor<MealItemEntity>(
                predicate: #Predicate { $0.id == itemId }
            )
            guard let item = try? context.fetch(descriptor).first else { continue }
            if item.pendingSync {
                item.pendingSync = false
                item.lastSyncedAt = .now
                didChange = true
            }
            // Clear the parent meal's flag too once all its items are synced.
            if let parent = item.meal, parent.pendingSync,
               parent.items.allSatisfy({ !$0.pendingSync }) {
                parent.pendingSync = false
                parent.lastSyncedAt = .now
                didChange = true
            }
        }
        if didChange { try? context.save() }
    }

    /// Inspection helpers used by views (e.g. an "Offline — N pending"
    /// banner) and tests.
    func pendingCount() async -> Int { await queue.peekAll().count }
    func pendingMutations() async -> [PendingMutation] { await queue.peekAll() }

    // MARK: - Mutation dispatcher

    private static func execute(_ mutation: PendingMutation,
                                 with api: APIClient,
                                 authGuard: @escaping @Sendable () async -> Bool) async throws {
        switch mutation {
        case .logMealItem(let payload):
            // Replay the exact `POST /api/v1/meals/log` the optimistic write
            // would have sent. The body carries `client_item_id`, so the
            // backend dedupes a re-sent log and returns the existing item
            // instead of inserting a duplicate row — safe to retry forever.
            // The auth-guarded overload aborts (without sending) if the auth
            // session changed since the drain began (Codex review #5 P0).
            let _: MealDTO = try await api.post(mutation.endpoint,
                                                body: payload.asRequest(),
                                                authGuard: authGuard)

        case .deleteMealItem:
            // `DELETE /api/v1/meals/items/{id}` is idempotent: deleting an
            // already-gone item returns 204, so a replayed delete is safe.
            // Auth-guarded so a stale-session replay never deletes under the
            // wrong user's token.
            try await api.delete(mutation.endpoint, authGuard: authGuard)
        }
    }
}
