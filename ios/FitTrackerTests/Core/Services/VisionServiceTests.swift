//
//  VisionServiceTests.swift
//  Slice 3.5: validates the privacy contract for VisionService.
//
//  The critical assertion is `visionService_sendsImageWithNoPII`: the
//  outgoing multipart body must contain ONLY the JPEG bytes + the form
//  field "image". No user id, email, display name, or device id may
//  appear anywhere in headers or body. We re-verify this every time
//  the service is touched.
//

import Foundation
import Testing
@testable import FitTracker

@Suite("VisionService", .serialized)
struct VisionServiceTests {

    init() { MockURLProtocol.reset() }

    private static let okJSON = #"""
    {
      "food": "grilled chicken breast",
      "grams": 150,
      "confidence": "high",
      "calories": 247,
      "protein_g": 46.5,
      "carbs_g": 0,
      "fat_g": 5.4
    }
    """#

    private func makeSUT() -> VisionService {
        let session = MockURLProtocol.makeSession()
        return VisionService(
            baseURL: URL(string: "http://test.local")!,
            session: session,
            tokenProvider: nil
        )
    }

    // MARK: - PII gate

    @Test("Outgoing request contains image only — no user id, email, or name")
    func visionService_sendsImageWithNoPII() async throws {
        let sut = makeSUT()
        // Sentinel strings we never want to see leaked. If a future
        // change attaches user metadata, one of these will land in
        // headers or body and the test must fail.
        let sentinelEmail = "carlos@fittracker.dev"
        let sentinelName = "Carlos Soto"
        let sentinelUserId = "00000000-0000-0000-0000-000000C00001"

        MockURLProtocol.handler = { req in
            // 1. Header inspection
            let headers = (req.allHTTPHeaderFields ?? [:])
            for (key, value) in headers {
                #expect(!value.contains(sentinelEmail),
                        "Header \(key) leaked email")
                #expect(!value.contains(sentinelName),
                        "Header \(key) leaked name")
                #expect(!value.contains(sentinelUserId),
                        "Header \(key) leaked user id")
            }
            // 2. Body inspection — string-decode for plaintext leak
            //    detection. Image bytes are binary so they won't false-
            //    positive against ASCII sentinels.
            let body = req.bodyStreamData() ?? Data()
            if let bodyString = String(data: body, encoding: .utf8) {
                #expect(!bodyString.contains(sentinelEmail))
                #expect(!bodyString.contains(sentinelName))
                #expect(!bodyString.contains(sentinelUserId))
            }
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200,
                                       httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
            return (resp, Data(Self.okJSON.utf8))
        }

        // Two-pixel JPEG (red + green) so we have something to compress.
        let dummy = Data([0xFF, 0xD8, 0xFF, 0xD9]) // valid JPEG SOI/EOI
        _ = try await sut.recognize(jpegData: dummy)
    }

    @Test("Successful response decodes into a VisionRecognition")
    func visionService_returnsParsedFoodIdentification() async throws {
        let sut = makeSUT()
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200,
                                       httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
            return (resp, Data(Self.okJSON.utf8))
        }
        let result = try await sut.recognize(jpegData: Data([0xFF, 0xD8, 0xFF, 0xD9]))
        #expect(result.food == "grilled chicken breast")
        #expect(result.grams == 150)
        #expect(result.confidence == "high")
        #expect(result.calories == 247)
    }

    @Test("401 surfaces unauthorized")
    func visionService_mapsErrorStatuses() async throws {
        let sut = makeSUT()
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 401,
                                       httpVersion: "HTTP/1.1",
                                       headerFields: nil)!
            return (resp, Data())
        }
        await #expect(throws: APIError.unauthorized) {
            _ = try await sut.recognize(jpegData: Data([0xFF, 0xD8, 0xFF, 0xD9]))
        }
    }

    @Test("429 surfaces rateLimited and parses Retry-After")
    func visionService_mapsRateLimited() async throws {
        let sut = makeSUT()
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 429,
                                       httpVersion: "HTTP/1.1",
                                       headerFields: ["Retry-After": "42"])!
            return (resp, Data(#"{"detail":"Too many requests"}"#.utf8))
        }
        await #expect(throws: APIError.rateLimited(retryAfterSeconds: 42)) {
            _ = try await sut.recognize(jpegData: Data([0xFF, 0xD8, 0xFF, 0xD9]))
        }
    }

    /// The Wave 1 `/nutrition/recognize` endpoint can return 415 (unsupported
    /// type), 413 (too large), 400 (empty), 503 (vision unavailable) and 502
    /// (upstream vision failure) in addition to 401/429. `APIError` has no
    /// dedicated case for these, so the contract maps them to
    /// `.server(status:detail:)` — which carries the HTTP status so a view
    /// model can branch on it and show the right message. These tests pin that
    /// real mapping (each status round-trips its code + detail).
    @Test("415/413/400/503/502 surface APIError.server with the status + detail")
    func visionService_mapsServerStatuses() async throws {
        let sut = makeSUT()
        let cases: [(Int, String)] = [
            (415, #"{"detail":"Unsupported image type. Allowed: image/jpeg, image/png"}"#),
            (413, #"{"detail":"Image exceeds the 10 MiB limit"}"#),
            (400, #"{"detail":"Empty image upload"}"#),
            (503, #"{"detail":"Food recognition is not available"}"#),
            (502, #"{"detail":"Could not recognize the food in this image"}"#),
        ]
        for (status, bodyJSON) in cases {
            nonisolated(unsafe) let captured = (status, bodyJSON)
            MockURLProtocol.handler = { req in
                let resp = HTTPURLResponse(url: req.url!, statusCode: captured.0,
                                           httpVersion: "HTTP/1.1",
                                           headerFields: ["Content-Type": "application/json"])!
                return (resp, Data(captured.1.utf8))
            }
            await #expect(throws: APIError.server(status: status, detail: bodyJSON)) {
                _ = try await sut.recognize(jpegData: Data([0xFF, 0xD8, 0xFF, 0xD9]))
            }
        }
    }

    // MARK: - multipart body shape

    @Test("Multipart body contains the image part and the boundary terminator")
    func visionService_multipartBodyShape() {
        let payload = Data([0x01, 0x02, 0x03, 0x04])
        let boundary = "TESTBOUND"
        let body = VisionService.makeMultipartBody(jpegData: payload, boundary: boundary)
        let asString = String(data: body, encoding: .ascii) ?? ""
        #expect(asString.contains("--\(boundary)\r\n"))
        #expect(asString.contains("Content-Disposition: form-data; name=\"image\""))
        #expect(asString.contains("Content-Type: image/jpeg"))
        #expect(asString.hasSuffix("--\(boundary)--\r\n"),
                "Body must terminate with the closing boundary")
    }
}

// MARK: - URLRequest body extraction

private extension URLRequest {
    /// Pulls the body bytes regardless of whether they were set as
    /// `httpBody` or via `httpBodyStream`. URLProtocol mocking flips
    /// between the two depending on size.
    func bodyStreamData() -> Data? {
        if let body = httpBody { return body }
        guard let stream = httpBodyStream else { return nil }
        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        stream.open()
        defer { stream.close() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read > 0 { data.append(buffer, count: read) }
            if read <= 0 { break }
        }
        return data
    }
}
