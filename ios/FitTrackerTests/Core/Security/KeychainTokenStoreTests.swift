//
//  KeychainTokenStoreTests.swift
//  Round-trip + delete + refresh-token + expiry tests. Each test uses a
//  unique service string so parallel runs don't collide.
//

import Foundation
import Testing
@testable import FitTracker

@Suite("KeychainTokenStore")
struct KeychainTokenStoreTests {

    private func makeSUT() -> KeychainTokenStore {
        // Unique service per test instance to avoid cross-test pollution.
        let tag = UUID().uuidString
        let sut = KeychainTokenStore(service: "test.fittracker.\(tag)")
        sut.clearAll()
        return sut
    }

    @Test("Access token round-trip: write, read, delete, read-nil")
    func accessToken_roundTrip() async {
        let sut = makeSUT()
        #expect(sut.currentAccessToken() == nil)

        await sut.updateAccessToken("abc123")
        #expect(sut.currentAccessToken() == "abc123")

        await sut.updateAccessToken("def456")
        #expect(sut.currentAccessToken() == "def456")

        await sut.updateAccessToken(nil)
        #expect(sut.currentAccessToken() == nil)

        sut.clearAll()
    }

    @Test("Refresh token stored separately from access token")
    func refreshToken_isolatedFromAccess() async {
        let sut = makeSUT()
        await sut.updateAccessToken("access-1")
        await sut.updateRefreshToken("refresh-1")

        #expect(sut.currentAccessToken() == "access-1")
        #expect(sut.currentRefreshToken() == "refresh-1")

        await sut.updateAccessToken(nil)
        #expect(sut.currentAccessToken() == nil)
        #expect(sut.currentRefreshToken() == "refresh-1")

        sut.clearAll()
    }

    @Test("Access token expiry round-trip via Date")
    func accessTokenExpiry_roundTrip() async {
        let sut = makeSUT()
        let date = Date(timeIntervalSince1970: 1_762_000_000)
        await sut.updateAccessTokenExpiry(date)

        let round = sut.accessTokenExpiry()
        #expect(round != nil)
        if let round {
            // Allow <0.001s drift from Double precision round-trip
            #expect(abs(round.timeIntervalSince(date)) < 0.001)
        }

        await sut.updateAccessTokenExpiry(nil)
        #expect(sut.accessTokenExpiry() == nil)

        sut.clearAll()
    }

    @Test("clearAll wipes access, refresh, and expiry")
    func clearAll_wipesEverything() async {
        let sut = makeSUT()
        await sut.updateAccessToken("a")
        await sut.updateRefreshToken("r")
        await sut.updateAccessTokenExpiry(Date())

        sut.clearAll()

        #expect(sut.currentAccessToken() == nil)
        #expect(sut.currentRefreshToken() == nil)
        #expect(sut.accessTokenExpiry() == nil)
    }
}
