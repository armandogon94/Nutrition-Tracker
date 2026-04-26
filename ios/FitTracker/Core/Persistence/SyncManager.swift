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

@MainActor
final class SyncManager {

    private let api: APIClient
    private let queue: OfflineQueue
    private let reachability: Reachability
    private var didWireDrainOnReconnect = false

    init(api: APIClient = APIClient(),
         queue: OfflineQueue = OfflineQueue(),
         reachability: Reachability = .shared) {
        self.api = api
        self.queue = queue
        self.reachability = reachability
    }

    /// Call once at app launch (FitTrackerApp). Wires the
    /// reachability-flip observer so queued writes drain automatically.
    func startObservingConnectivity() {
        guard !didWireDrainOnReconnect else { return }
        didWireDrainOnReconnect = true
        reachability.onChange { [weak self] status in
            guard status == .online else { return }
            Task { @MainActor in await self?.drainNow() }
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

    /// Manually trigger a drain. Returns how many mutations succeeded.
    @discardableResult
    func drainNow() async -> Int {
        let api = self.api
        return await queue.drain { mutation in
            try await Self.execute(mutation, with: api)
        }
    }

    /// Inspection helpers used by views (e.g. an "Offline — N pending"
    /// banner) and tests.
    func pendingCount() async -> Int { await queue.peekAll().count }
    func pendingMutations() async -> [PendingMutation] { await queue.peekAll() }

    // MARK: - Mutation dispatcher

    private static func execute(_ mutation: PendingMutation,
                                 with api: APIClient) async throws {
        switch mutation {
        case .createMeal(let payload):
            struct CreateMealResponse: Decodable, Sendable { let id: UUID }
            let _: CreateMealResponse = try await api.post(mutation.endpoint, body: payload)

        case .deleteMealItem:
            try await api.delete(mutation.endpoint)
        }
    }
}
