//
//  APIError.swift
//  Typed errors bubbled up from APIClient. Features translate these into
//  user-facing messages via their view models.
//

import Foundation

enum APIError: Error, Sendable, Equatable {
    case unauthorized                          // 401
    case notFound                              // 404
    case rateLimited(retryAfterSeconds: Int?)  // 429
    case server(status: Int, detail: String?)  // 4xx / 5xx
    case decoding(String)
    case network(String)
    case offline
    case cancelled
    case unknown(String)

    static func == (lhs: APIError, rhs: APIError) -> Bool {
        switch (lhs, rhs) {
        case (.unauthorized, .unauthorized): return true
        case (.notFound, .notFound): return true
        case (.rateLimited(let a), .rateLimited(let b)): return a == b
        case (.server(let sa, let da), .server(let sb, let db)):
            return sa == sb && da == db
        case (.decoding(let a), .decoding(let b)): return a == b
        case (.network(let a), .network(let b)): return a == b
        case (.offline, .offline): return true
        case (.cancelled, .cancelled): return true
        case (.unknown(let a), .unknown(let b)): return a == b
        default: return false
        }
    }
}
