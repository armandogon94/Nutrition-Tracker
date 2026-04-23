//
//  TokenProvider.swift
//  Decouples APIClient from Keychain specifics. AuthService (Slice 1)
//  provides a concrete Keychain-backed implementation; tests provide an
//  in-memory stub.
//

import Foundation

protocol TokenProvider: AnyObject, Sendable {
    func currentAccessToken() -> String?
    func updateAccessToken(_ token: String?) async
}
