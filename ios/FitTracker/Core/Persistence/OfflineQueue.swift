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

    /// Remove every mutation owned by `userId`. Called on sign-out / account
    /// deletion so a signed-out user's queued writes can never replay under a
    /// different account (Codex review #4 P0). Crash-safe: it's a single
    /// atomic `UserDefaults` write of the filtered array — no intermediate
    /// state where the queue is half-cleared.
    func removeAll(ownedBy userId: UUID) async {
        let next = read().filter { $0.ownerId != userId }
        write(next)
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

    /// Owner-scoped drain: replay ONLY the mutations owned by `userId`,
    /// skipping (and leaving in place) any that belong to another account.
    /// This is the backstop for the cross-user replay blocker (Codex review
    /// #4 P0): even if a foreign mutation is still in the shared queue, it is
    /// never handed to `apply` — so it can never be sent under the current
    /// user's bearer token. Foreign entries stay quarantined for whenever
    /// their owner signs back in. Among the owner's own mutations, FIFO order
    /// is preserved and draining stops on the first failure (same retry
    /// semantics as `drain`). Returns the number successfully drained.
    @discardableResult
    func drain(ownedBy userId: UUID,
               _ apply: @Sendable (PendingMutation) async throws -> Void) async -> Int {
        var drained = 0
        for mutation in read() {
            // Quarantine anything that isn't this user's — skip without
            // touching it so it remains for its real owner.
            guard mutation.ownerId == userId else { continue }
            do {
                try await apply(mutation)
                await remove(id: mutation.id)
                drained += 1
            } catch {
                // Stop on the owner's first failure; their remaining
                // mutations keep their order for the next retry.
                break
            }
        }
        return drained
    }

    // MARK: - Storage

    /// Key under which a corrupt/undecodable queue blob is preserved instead of
    /// being silently dropped (review C4 / Flash B1). Derived from `storageKey`
    /// so each queue instance (incl. per-test instances) quarantines into its
    /// own slot. Exposed so tests can assert the blob was saved, not lost.
    /// `nonisolated` because it only derives from the immutable `storageKey`
    /// (Sendable) — so callers (and tests) can read it synchronously.
    nonisolated var corruptedKey: String { storageKey + ".corrupted" }

    private func read() -> [PendingMutation] {
        guard let data = defaults.data(forKey: storageKey) else { return [] }
        do {
            return try JSONDecoder.iso8601().decode([PendingMutation].self, from: data)
        } catch {
            // The persisted queue failed to decode (schema drift, partial
            // UserDefaults write, corruption). Returning [] here used to let
            // the NEXT write overwrite the key and permanently drop every
            // pending mutation. Instead we copy the raw bytes to a quarantine
            // key and clear the primary key, so the data is recoverable and we
            // don't re-attempt the same failing decode on every read. The
            // mutations are still lost from the live queue, but preserved for
            // diagnostics / a future migration rather than gone.
            quarantine(data, error: error)
            return []
        }
    }

    /// Preserve an undecodable blob under `corruptedKey` and clear the primary
    /// slot. If a quarantine blob already exists we keep the FIRST one (the
    /// earliest corruption) rather than clobbering it with a later read.
    private func quarantine(_ data: Data, error: Error) {
        if defaults.data(forKey: corruptedKey) == nil {
            defaults.set(data, forKey: corruptedKey)
        }
        defaults.removeObject(forKey: storageKey)
        #if DEBUG
        print("[OfflineQueue] Quarantined corrupt queue (\(data.count) bytes) to \(corruptedKey): \(error)")
        #endif
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
