//
//  APIConfigTests.swift
//  Pins the release-safety policy for the backend base URL (review C1):
//  release builds must reject a missing / non-HTTPS / localhost
//  `API_BASE_URL` rather than silently falling back to the device.
//

import Foundation
import Testing
@testable import FitTracker

@Suite("APIConfig")
struct APIConfigTests {

    @Test("Production HTTPS URL is accepted for release")
    func productionURL_accepted() {
        let url = URL(string: "https://api.fit.armandointeligencia.com")!
        #expect(APIConfig.releaseRejection(for: url) == nil)
    }

    @Test("Non-HTTPS URL is rejected for release")
    func httpURL_rejected() {
        let url = URL(string: "http://api.fit.armandointeligencia.com")!
        #expect(APIConfig.releaseRejection(for: url) == .notHTTPS)
    }

    @Test("localhost is rejected for release even over HTTPS")
    func localhost_rejected() {
        for raw in [
            "https://localhost:8001",
            "https://127.0.0.1:8001",
            "https://0.0.0.0",
            "https://mymac.local"
        ] {
            let url = URL(string: raw)!
            #expect(APIConfig.releaseRejection(for: url) == .localhost,
                    "expected \(raw) to be rejected as localhost")
        }
    }

    @Test("http localhost is rejected as non-HTTPS first")
    func httpLocalhost_rejectedNotHTTPS() {
        let url = URL(string: "http://localhost:8001")!
        // Scheme is checked before host, so the reported reason is notHTTPS.
        #expect(APIConfig.releaseRejection(for: url) == .notHTTPS)
    }

    @Test("resolve accepts a valid production URL")
    func resolve_validProductionURL() {
        let url = APIConfig.resolve(raw: "https://api.fit.armandointeligencia.com")
        #expect(url.absoluteString == "https://api.fit.armandointeligencia.com")
    }

    #if DEBUG
    // In DEBUG the localhost fallback is intentionally retained so the dev
    // build keeps working when the key is absent. (Release traps instead, but
    // a fatalError can't be asserted from a unit test.)
    @Test("DEBUG falls back to localhost when value is missing")
    func resolve_debugFallback() {
        #expect(APIConfig.resolve(raw: nil).absoluteString == "http://localhost:8001")
        #expect(APIConfig.resolve(raw: "   ").absoluteString == "http://localhost:8001")
    }

    @Test("DEBUG honors an explicit override")
    func resolve_debugHonorsOverride() {
        let url = APIConfig.resolve(raw: "https://staging.example.com")
        #expect(url.absoluteString == "https://staging.example.com")
    }
    #endif
}
