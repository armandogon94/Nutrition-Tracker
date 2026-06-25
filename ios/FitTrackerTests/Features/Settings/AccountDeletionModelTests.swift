//
//  AccountDeletionModelTests.swift
//  Codex review #17 (cycle 1) / #14 (cycle 2): the delete-account button was a
//  no-op. SettingsView now drives `AccountDeletionModel`, which calls the
//  backend `DELETE /api/v1/users/me` and then signs out. The network call and
//  signOut are injected as closures (the view supplies the real
//  `APIClient(...).delete` + `services.auth.signOut()`), so the branching
//  logic is unit-testable:
//    - success            -> sign out, no error
//    - 404 (route not yet deployed) -> sign out anyway (graceful), no error
//    - other failure      -> surface error, DO NOT sign out (user keeps session)
//

import Foundation
import Testing
@testable import FitTracker

@MainActor
@Suite("AccountDeletionModel")
struct AccountDeletionModelTests {

    /// Records whether signOut ran.
    final class SignOutSpy: @unchecked Sendable {
        private(set) var didSignOut = false
        func signOut() async { didSignOut = true }
    }

    @Test("successful delete signs the user out and clears state")
    func success_signsOut() async {
        let spy = SignOutSpy()
        let model = AccountDeletionModel()
        await model.performDeletion(
            delete: { /* 204 No Content success */ },
            signOut: { await spy.signOut() }
        )
        #expect(spy.didSignOut, "a successful deletion must sign the user out")
        #expect(model.errorMessage == nil)
        #expect(model.isDeleting == false)
    }

    @Test("404 (route not deployed yet) still signs out gracefully")
    func notFound_signsOutGracefully() async {
        let spy = SignOutSpy()
        let model = AccountDeletionModel()
        await model.performDeletion(
            delete: { throw APIError.notFound },
            signOut: { await spy.signOut() }
        )
        #expect(spy.didSignOut, "a 404 means the backend route isn't live yet — sign out locally rather than trap the user")
        #expect(model.errorMessage == nil)
    }

    @Test("server error surfaces a message and does NOT sign out")
    func serverError_surfacesAndKeepsSession() async {
        let spy = SignOutSpy()
        let model = AccountDeletionModel()
        await model.performDeletion(
            delete: { throw APIError.server(status: 500, detail: "boom") },
            signOut: { await spy.signOut() }
        )
        #expect(spy.didSignOut == false, "a real failure must not silently log the user out")
        #expect(model.errorMessage != nil, "the failure must be surfaced to the user")
        #expect(model.isDeleting == false)
    }

    @Test("offline error surfaces a message and does NOT sign out")
    func offline_surfacesAndKeepsSession() async {
        let spy = SignOutSpy()
        let model = AccountDeletionModel()
        await model.performDeletion(
            delete: { throw APIError.offline },
            signOut: { await spy.signOut() }
        )
        #expect(spy.didSignOut == false)
        #expect(model.errorMessage != nil)
    }

    @Test("isDeleting is reset after completion")
    func isDeleting_resets() async {
        let model = AccountDeletionModel()
        await model.performDeletion(delete: { }, signOut: { })
        #expect(model.isDeleting == false)
    }
}
