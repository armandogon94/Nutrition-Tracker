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
        // Replay any leftover queue from a prior launch. `.unknown` (cold
        // launch before NWPathMonitor's first callback) is treated as
        // worth-trying: drain stops on the first failure, so an attempt
        // while genuinely offline is cheap and self-correcting.
        if reachability.status != .offline {
            Task { @MainActor in await self.drainNow() }
        }
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
        // Snapshot before/after so we know exactly which mutations flushed.
        let before = await queue.peekAll()
        let drained = await queue.drain { mutation in
            try await Self.execute(mutation, with: api)
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
                                 with api: APIClient) async throws {
        switch mutation {
        case .logMealItem(let payload):
            // Replay the exact `POST /api/v1/meals/log` the optimistic write
            // would have sent. The body carries `client_item_id`, so the
            // backend dedupes a re-sent log and returns the existing item
            // instead of inserting a duplicate row — safe to retry forever.
            let _: MealDTO = try await api.post(mutation.endpoint,
                                                body: payload.asRequest())

        case .deleteMealItem:
            // `DELETE /api/v1/meals/items/{id}` is idempotent: deleting an
            // already-gone item returns 204, so a replayed delete is safe.
            try await api.delete(mutation.endpoint)
        }
    }
}
