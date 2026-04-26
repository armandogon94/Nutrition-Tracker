//
//  Reachability.swift
//  Network connectivity monitor backed by NWPathMonitor. Slice 2.2.
//  Drives SyncManager's drain-on-reconnect behavior.
//

import Foundation
import Network
import Observation

@MainActor
@Observable
final class Reachability {

    enum Status: Sendable, Equatable {
        case unknown
        case online
        case offline
    }

    private(set) var status: Status = .unknown

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.armandointeligencia.FitTracker.reachability")
    private var listeners: [(@Sendable (Status) -> Void)] = []

    /// Singleton; the app starts monitoring on cold launch. Tests build
    /// their own instance.
    static let shared = Reachability()

    init(autoStart: Bool = true) {
        if autoStart { start() }
    }

    /// Begin observing path changes. Idempotent.
    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            let new: Status = (path.status == .satisfied) ? .online : .offline
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.status != new {
                    self.status = new
                    for cb in self.listeners { cb(new) }
                }
            }
        }
        monitor.start(queue: queue)
    }

    /// Convenience for tests / one-shot drain triggers.
    func setStatus(_ status: Status) {
        let changed = self.status != status
        self.status = status
        if changed {
            for cb in listeners { cb(status) }
        }
    }

    /// Subscribe to status flips. The callback is invoked whenever the
    /// status changes (not on subscribe).
    func onChange(_ cb: @escaping @Sendable (Status) -> Void) {
        listeners.append(cb)
    }

    deinit { monitor.cancel() }
}
