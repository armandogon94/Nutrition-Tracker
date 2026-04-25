//
//  APIConfig.swift
//  Centralizes the backend base URL. Reads `API_BASE_URL` from Info.plist
//  so each build configuration (Debug, Release, TestFlight) can target
//  a different backend without recompiling.
//

import Foundation

enum APIConfig {
    /// Resolved at module-load time. Falls back to the local-dev backend.
    static let baseURL: URL = {
        let bundle = Bundle.main
        if let raw = bundle.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
           let url = URL(string: raw) {
            return url
        }
        return URL(string: "http://localhost:8001")!
    }()
}
