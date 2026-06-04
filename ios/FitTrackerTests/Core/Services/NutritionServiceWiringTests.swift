//
//  NutritionServiceWiringTests.swift
//  Slice 2.4b — verifies the DI container wires the REAL NutritionService
//  in the production path while debug / preview / tap-through keep using
//  MockNutritionService.
//
//  Background: MockServiceContainer started life (Slice 0.5) returning a
//  mock for every domain. Slice 1 promoted `auth` to a protocol-typed slot
//  that production fills with the real AuthService. Slice 2.4b does the
//  same for `nutrition`: the container's `nutrition` slot is now
//  `any NutritionServiceProtocol`, and the production factory injects a
//  real `NutritionService(api:context:userId:)` reading the live
//  SwiftData container, while the default mock initializer keeps returning
//  `MockNutritionService` so previews and Slice 0.5 tap-through render
//  without a backend.
//

import Foundation
import SwiftData
import Testing
@testable import FitTracker

@MainActor
@Suite("NutritionService DI wiring (Slice 2.4b)", .serialized)
struct NutritionServiceWiringTests {

    @Test("Production container yields a REAL NutritionService, not the mock")
    func production_yieldsRealNutritionService() throws {
        // The production factory mirrors FitTrackerApp.makeServiceContainer():
        // real AuthService + real NutritionService backed by the live store.
        let container = MockServiceContainer.production()
        #expect(container.nutrition is NutritionService,
                "production must inject the real NutritionService")
        #expect(!(container.nutrition is MockNutritionService),
                "production must NOT fall back to the mock")
    }

    @Test("Default (debug/preview) container keeps the MockNutritionService")
    func debug_keepsMockNutritionService() {
        let container = MockServiceContainer()
        #expect(container.nutrition is MockNutritionService,
                "default init must stay on the mock for previews + tap-through")
        #expect(!(container.nutrition is NutritionService),
                "default init must not reach for the real service / backend")
    }

    @Test("Explicit nutrition injection is honored over the default")
    func explicitInjection_isHonored() throws {
        let pc = try PersistenceController.makeInMemory()
        let api = APIClient(baseURL: URL(string: "http://test.local")!)
        let real = NutritionService(
            api: api,
            context: pc.container.mainContext,
            userId: { nil }
        )
        let container = MockServiceContainer(nutrition: real)
        #expect(container.nutrition is NutritionService)
        // Same instance, not a copy.
        #expect(container.nutrition === real)
    }
}
