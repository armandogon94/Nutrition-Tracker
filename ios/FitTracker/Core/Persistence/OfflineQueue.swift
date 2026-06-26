//
//  OfflineQueue.swift
//  FIFO persistent queue of PendingMutation values. Backed by
//  UserDefaults JSON for v1 simplicity (~few-hundred-bytes per
//  mutation, atomic writes, survives app kill). Slice 2.2.
//
//  Public surface is an actor so concurrent enqueue/drain calls are
//  serialized without locks.
//

import Foundation

actor OfflineQueue {
    private let storageKey: String
    private let defaults: UserDefaults

    /// App-wide durable queue. The producers of failed writes (MealService)
    /// and the single consumer that replays them (SyncManager, started in
    /// FitTrackerApp) both default to THIS instance, so a failed optimistic
    /// write and its eventual replay always travel through one queue. Tests
    /// build their own isolated instances with a per-test storage key.
    static let shared = OfflineQueue()

    init(storageKey: String = "com.armandointeligencia.FitTracker.OfflineQueue.v1",
         defaults: UserDefaults = .standard) {
        self.storageKey = storageKey
        self.defaults = defaults
    }

    /// Append a mutation, deduped by `id`. If a mutation with the same id is
    /// already queued (e.g. the user re-logs the same item, or a failed
    /// optimistic write is enqueued twice) the newer payload REPLACES the
    /// older one in place, preserving its queue position. This keeps the
    /// queue itself idempotent so a single backend write is never sent twice
    /// from two distinct entries — complementing the backend's own
    /// `client_item_id` dedup. O(n) but n is tiny in v1.
    func enqueue(_ mutation: PendingMutation) async {
        var current = read()
        if let i = current.firstIndex(where: { $0.id == mutation.id }) {
            current[i] = mutation
        } else {
            current.append(mutation)
        }
        write(current)
    }

    /// Returns a snapshot of the queue without removing entries.
    func peekAll() async -> [PendingMutation] { read() }

    /// Returns true if a mutation with the given id is currently queued.
    func contains(id: UUID) async -> Bool {
        read().contains { $0.id == id }
    }

    /// Remove a specific mutation by id (called after successful flush).
    func remove(id: UUID) async {
        let next = read().filter { $0.id != id }
        write(next)
    }

    /// Clear all queued mutations (sign-out, etc).
    func removeAll() async {
        defaults.removeObject(forKey: storageKey)
    }

    /// Iterate over queued mutations and let `apply` execute each. On
    /// success the mutation is dequeued; on failure it stays in place
    /// for a future retry. Returns the number of successfully drained
    /// mutations.
    @discardableResult
    func drain(_ apply: @Sendable (PendingMutation) async throws -> Void) async -> Int {
        var drained = 0
        for mutation in read() {
            do {
                try await apply(mutation)
                await remove(id: mutation.id)
                drained += 1
            } catch {
                // Stop draining on first failure — preserves order and
                // avoids hammering a flaky backend. Caller decides retry.
                break
            }
        }
        return drained
    }

    // MARK: - Storage

    private func read() -> [PendingMutation] {
        guard let data = defaults.data(forKey: storageKey) else { return [] }
        return (try? JSONDecoder.iso8601().decode([PendingMutation].self, from: data)) ?? []
    }

    private func write(_ mutations: [PendingMutation]) {
        guard let data = try? JSONEncoder.iso8601().encode(mutations) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

// MARK: - Codable helpers

private extension JSONDecoder {
    static func iso8601() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

private extension JSONEncoder {
    static func iso8601() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }
}
