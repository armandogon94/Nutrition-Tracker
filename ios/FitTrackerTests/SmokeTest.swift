//
//  SmokeTest.swift
//  Slice 0 smoke — asserts the app target compiles and links.
//

import Testing
@testable import FitTracker

@Test("App module imports and FitTrackerApp type exists")
func smokeTest_appTargetLinks() {
    // Existence of the @main type is enough — if this compiles, the app target is sound.
    #expect(FitTrackerApp.self == FitTrackerApp.self)
}
