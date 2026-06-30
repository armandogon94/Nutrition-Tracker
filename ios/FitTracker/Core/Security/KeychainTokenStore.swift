//
//  KeychainTokenStore.swift
//  Keychain-backed TokenProvider. Stores access token, refresh token,
//  and access-token expiry under a configurable service/account pair so
//  test instances don't collide with production data.
//
//  Accessibility: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly — lets
//  background refresh work immediately after device unlock without requiring
//  the user to foreground the app, while the `ThisDeviceOnly` qualifier keeps
//  the items out of iCloud Keychain and encrypted device backups so a copied
//  backup / migration can't exfiltrate a long-lived refresh token (review A3).
//

import Foundation
import Security

final class KeychainTokenStore: TokenProvider, @unchecked Sendable {
    private let service: String
    private let accessAccount: String
    private let refreshAccount: String
    private let expiryAccount: String

    /// Default instance used by the app. Tests construct their own with a
    /// unique service string (see `KeychainTokenStoreTests`).
    static let shared = KeychainTokenStore()

    init(
        service: String = "com.armandointeligencia.FitTracker.auth",
        accountNamespace: String = "default"
    ) {
        self.service = service
        self.accessAccount = "\(accountNamespace).access"
        self.refreshAccount = "\(accountNamespace).refresh"
        self.expiryAccount = "\(accountNamespace).expiry"
    }

    // MARK: - TokenProvider

    func currentAccessToken() -> String? {
        readString(account: accessAccount)
    }

    func updateAccessToken(_ token: String?) async {
        if let token {
            write(token.data(using: .utf8) ?? Data(), account: accessAccount)
        } else {
            delete(account: accessAccount)
        }
    }

    // MARK: - Refresh token + expiry (used by AuthService in Slice 1)

    func currentRefreshToken() -> String? {
        readString(account: refreshAccount)
    }

    func updateRefreshToken(_ token: String?) async {
        if let token {
            write(token.data(using: .utf8) ?? Data(), account: refreshAccount)
        } else {
            delete(account: refreshAccount)
        }
    }

    func accessTokenExpiry() -> Date? {
        guard let data = readData(account: expiryAccount),
              data.count == MemoryLayout<Double>.size else { return nil }
        let ti = data.withUnsafeBytes { $0.load(as: Double.self) }
        return Date(timeIntervalSince1970: ti)
    }

    func updateAccessTokenExpiry(_ date: Date?) async {
        if let date {
            var ti = date.timeIntervalSince1970
            let data = Data(bytes: &ti, count: MemoryLayout<Double>.size)
            write(data, account: expiryAccount)
        } else {
            delete(account: expiryAccount)
        }
    }

    /// Wipe every stored token. Used on sign-out and in test teardown.
    func clearAll() {
        delete(account: accessAccount)
        delete(account: refreshAccount)
        delete(account: expiryAccount)
    }

    // MARK: - Low-level Keychain ops

    /// Accessibility class for every stored token. `ThisDeviceOnly` blocks
    /// inclusion in iCloud Keychain and encrypted backups (review A3); the
    /// `AfterFirstUnlock` part still permits background refresh post-unlock.
    /// Defined once so the add and update paths can never drift. Computed (not a
    /// stored `static let`) so it stays Swift 6 concurrency-safe — `CFString` is
    /// not `Sendable`, but returning the immutable system constant each access is.
    private static var accessibility: CFString { kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: Self.accessibility
        ]
    }

    private func write(_ data: Data, account: String) {
        var query = baseQuery(account: account)
        query.removeValue(forKey: kSecAttrAccessible as String)

        let attrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: Self.accessibility
        ]

        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = baseQuery(account: account)
            addQuery[kSecValueData as String] = data
            _ = SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    private func readData(account: String) -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    private func readString(account: String) -> String? {
        guard let data = readData(account: account) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func delete(account: String) {
        var query = baseQuery(account: account)
        query.removeValue(forKey: kSecAttrAccessible as String)
        _ = SecItemDelete(query as CFDictionary)
    }
}
