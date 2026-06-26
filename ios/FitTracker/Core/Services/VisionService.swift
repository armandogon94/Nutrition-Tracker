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

/// Backend client. Routes through the shared `APIClient` via its multipart
/// helper so photo recognition gets the SAME authenticated client as every
/// other domain — and therefore the 401 → refresh → retry path. Previously
/// this held its own `URLSession` and accepted (then discarded) an
/// `APIClient`, so an expired access token produced a hard 401 with no
/// refresh (codex-review-4 P1).
final class VisionService: VisionServiceProtocol, @unchecked Sendable {

    private let api: APIClient

    /// Production wiring: route through the ONE shared refresh-aware client.
    init(api: APIClient) {
        self.api = api
    }

    /// Test/preview convenience: build a private `APIClient` from a baseURL +
    /// mock session + optional token provider. Used by `VisionServiceTests`
    /// (which drive `MockURLProtocol`) and lightweight callers that don't have
    /// a container handy. The status-mapping + multipart contract is identical
    /// because it goes through the same `APIClient.postMultipart`.
    convenience init(baseURL: URL = APIConfig.baseURL,
                     session: URLSession = .shared,
                     tokenProvider: (any TokenProvider)? = nil) {
        self.init(api: APIClient(baseURL: baseURL, tokenProvider: tokenProvider, session: session))
    }

    func recognize(jpegData: Data) async throws -> VisionRecognition {
        let boundary = "fittracker.\(UUID().uuidString)"
        let body = Self.makeMultipartBody(jpegData: jpegData, boundary: boundary)

        // `APIClient.postMultipart` owns auth (shared Bearer + refresher),
        // dispatch, and status mapping. The Wave 1 `/nutrition/recognize`
        // contract still holds: 401 -> unauthorized (after a refresh attempt
        // when a refresher is configured), 429 -> rateLimited (honoring
        // Retry-After), and 415/413/400/503/502 -> `.server(status:detail:)`
        // via the client's default branch — so the caller can still branch on
        // the code and surface the FastAPI `detail`. The endpoint never 404s.
        let dto: VisionRecognitionResponse = try await api.postMultipart(
            "/api/v1/nutrition/recognize", body: body, boundary: boundary
        )
        return VisionRecognition(from: dto)
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
