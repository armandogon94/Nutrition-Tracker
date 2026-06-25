//
//  HistoryServiceWiringTests.swift
//  Slice 8 B1 fix — verifies the DI container wires the REAL HistoryService
//  in the production path while debug / preview / tap-through keep using
//  MockHistoryService.
//
//  Background: MockServiceContainer's `history` slot was a hardcoded
//  `let = MockHistoryService()` with no init override, so even the
//  production build rendered the Progreso tab on MockData. This mirrors the
//  Slice 2.4b nutrition wiring: `history` is now `any HistoryServiceProtocol`
//  filled by the production factory with a real
//  `HistoryService(container:userId:)` over the live SwiftData store, while
//  the default mock initializer keeps returning `MockHistoryService` for
//  previews and tap-through.
//

import Foundation
import SwiftData
import Testing
@testable import FitTracker

@MainActor
@Suite("HistoryService DI wiring (Slice 8 B1)", .serialized)
struct HistoryServiceWiringTests {

    @Test("Production container yields a REAL HistoryService, not the mock")
    func production_yieldsRealHistoryService() throws {
        let container = MockServiceContainer.production()
        #expect(container.history is HistoryService,
                "production must inject the real HistoryService")
        #expect(!(container.history is MockHistoryService),
                "production must NOT fall back to the mock")
    }

    @Test("Default (debug/preview) container keeps the MockHistoryService")
    func debug_keepsMockHistoryService() {
        let container = MockServiceContainer()
        #expect(container.history is MockHistoryService,
                "default init must stay on the mock for previews + tap-through")
        #expect(!(container.history is HistoryService),
                "default init must not reach for the real service / store")
    }

    @Test("Explicit history injection is honored over the default")
    func explicitInjection_isHonored() throws {
        let pc = try PersistenceController.makeInMemory()
        let real = HistoryService(container: pc.container, userId: { nil })
        let container = MockServiceContainer(history: real)
        #expect(container.history is HistoryService)
        // Same instance, not a copy.
        #expect(container.history as AnyObject === real)
    }
}
