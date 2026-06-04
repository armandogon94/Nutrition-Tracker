//
//  ProfileServiceWiringTests.swift
//  Slice 5.2 — the DI container wires the REAL ProfileService in the
//  production path so ProfileView / TDEECalculatorView / GoalsView /
//  SettingsView talk to the backend, while debug / preview / tap-through
//  keep using MockProfileService.
//
//  Same pattern as `auth` (Slice 1) and `nutrition` (Slice 2.4b): the
//  container's `profile` slot is now `any ProfileServiceProtocol`, the
//  views consume it through that protocol unchanged, and only the injected
//  concrete type differs between production and previews.
//

import Foundation
import Testing
@testable import FitTracker

@MainActor
@Suite("ProfileService DI wiring (Slice 5.2)", .serialized)
struct ProfileServiceWiringTests {

    @Test("Production container yields a REAL ProfileService, not the mock")
    func production_yieldsRealProfileService() {
        let container = MockServiceContainer.production()
        #expect(container.profile is ProfileService,
                "production must inject the real ProfileService")
        #expect(!(container.profile is MockProfileService),
                "production must NOT fall back to the mock")
    }

    @Test("Default (debug/preview) container keeps the MockProfileService")
    func debug_keepsMockProfileService() {
        let container = MockServiceContainer()
        #expect(container.profile is MockProfileService,
                "default init must stay on the mock for previews + tap-through")
        #expect(!(container.profile is ProfileService))
    }

    @Test("Explicit profile injection is honored over the default")
    func explicitInjection_isHonored() {
        let api = APIClient(baseURL: URL(string: "http://test.local")!)
        let real = ProfileService(api: api)
        let container = MockServiceContainer(profile: real)
        #expect(container.profile is ProfileService)
        #expect(container.profile === real)
    }
}
