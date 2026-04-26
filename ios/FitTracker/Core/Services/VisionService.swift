//
//  VisionService.swift
//  Slice 3.5: thin client for OUR backend's /api/v1/nutrition/recognize
//  endpoint. The backend (food_recognition.py) handles the actual
//  Claude Vision call so the Anthropic API key never lives on device.
//
//  Privacy contract:
//    - Outgoing body contains ONLY the JPEG data + a generic prompt.
//      Never user id / email / display name / device id.
//    - Test `visionService_sendsImageWithNoPII` enforces this.
//
//  Cost & retries: Claude Vision is metered; the backend caches by
//  perceptual image hash for 24h. Client doesn't retry — let the user
//  re-tap on transient failures so we don't double-bill on network
//  blips.
//

import Foundation

/// Plain-Swift representation of a Claude-Vision recognition. Mirrors
/// `VisionRecognitionResponse` in DTO.swift but without the snake_case
/// keys, so views and tests don't deal with the wire format.
struct VisionRecognition: Sendable, Hashable {
    let food: String
    let grams: Double
    let confidence: String
    let calories: Double?
    let proteinG: Double?
    let carbsG: Double?
    let fatG: Double?

    init(from dto: VisionRecognitionResponse) {
        self.food = dto.food
        self.grams = dto.grams
        self.confidence = dto.confidence
        self.calories = dto.calories
        self.proteinG = dto.protein_g
        self.carbsG = dto.carbs_g
        self.fatG = dto.fat_g
    }

    init(food: String, grams: Double, confidence: String,
         calories: Double? = nil, proteinG: Double? = nil,
         carbsG: Double? = nil, fatG: Double? = nil) {
        self.food = food
        self.grams = grams
        self.confidence = confidence
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
    }

    /// Convert a recognition into a Product placeholder so the user can
    /// edit servings and log it through the existing ProductLookupSheet
    /// flow. Confidence is folded into the brand string for now so it
    /// surfaces in the UI without a separate field.
    func intoProduct() -> Product {
        Product(
            id: UUID(),
            barcode: nil,
            name: food,
            brand: "Vision · \(confidence)",
            servingSizeG: grams,
            caloriesPerServing: calories ?? 0,
            proteinG: proteinG ?? 0,
            carbsG: carbsG ?? 0,
            fatG: fatG ?? 0,
            fiberG: 0,
            category: "Vision"
        )
    }
}

protocol VisionServiceProtocol: Sendable {
    func recognize(jpegData: Data) async throws -> VisionRecognition
}

/// Backend client. We do not route through `APIClient` because Slice 3
/// is the first caller of multipart and we don't want to widen
/// APIClient's surface for one consumer. Once a second caller appears
/// we can promote the helper.
final class VisionService: VisionServiceProtocol, @unchecked Sendable {

    private let baseURL: URL
    private let session: URLSession
    private let tokenProvider: (any TokenProvider)?

    init(baseURL: URL = APIConfig.baseURL,
         session: URLSession = .shared,
         tokenProvider: (any TokenProvider)? = nil) {
        self.baseURL = baseURL
        self.session = session
        self.tokenProvider = tokenProvider
    }

    /// Convenience init mirroring APIClient's: pulls Keychain token for
    /// authorization. Slice-3 production wiring uses this overload.
    convenience init(api: APIClient,
                     baseURL: URL = APIConfig.baseURL,
                     tokenProvider: (any TokenProvider)? = KeychainTokenStore.shared) {
        // We accept the APIClient just for ergonomic parity with our
        // other services; we don't actually use it here.
        _ = api
        self.init(baseURL: baseURL, session: .shared, tokenProvider: tokenProvider)
    }

    func recognize(jpegData: Data) async throws -> VisionRecognition {
        let boundary = "fittracker.\(UUID().uuidString)"
        let body = Self.makeMultipartBody(jpegData: jpegData, boundary: boundary)

        let url = baseURL.appendingPathComponent("/api/v1/nutrition/recognize")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)",
                     forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = tokenProvider?.currentAccessToken() {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = body

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw APIError.unknown("Non-HTTP response")
        }
        switch http.statusCode {
        case 200..<300:
            let decoder = JSONDecoder()
            let dto = try decoder.decode(VisionRecognitionResponse.self, from: data)
            return VisionRecognition(from: dto)
        case 401:
            throw APIError.unauthorized
        case 404:
            throw APIError.notFound
        case 429:
            let retry = http.value(forHTTPHeaderField: "Retry-After").flatMap { Int($0) }
            throw APIError.rateLimited(retryAfterSeconds: retry)
        default:
            throw APIError.server(status: http.statusCode,
                                   detail: String(data: data, encoding: .utf8))
        }
    }

    /// Builds an RFC-7578 multipart body containing only the image part.
    /// Exposed `internal static` so VisionServiceTests can inspect the
    /// bytes for the no-PII assertion.
    static func makeMultipartBody(jpegData: Data, boundary: String) -> Data {
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"meal.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(jpegData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }
}
