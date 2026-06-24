//
//  ProductServiceTests.swift
//  Slice 3.1: validates the real ProductService against MockURLProtocol.
//  We assert URL/path shape, query encoding, and DTO → Product mapping.
//

import Foundation
import Testing
@testable import FitTracker

@Suite("ProductService", .serialized)
struct ProductServiceTests {

    init() { MockURLProtocol.reset() }

    private func makeSUT() -> ProductService {
        let session = MockURLProtocol.makeSession()
        let api = APIClient(baseURL: URL(string: "http://test.local")!,
                            tokenProvider: nil,
                            session: session)
        return ProductService(api: api)
    }

    // Realistic backend `ProductResponse` payload: the backend emits
    // `calories` and `source` (plus image_url / created_at, which the client
    // ignores). It does NOT emit `calories_per_serving` or `category`.
    private static let oatmealJSON = #"""
    {
      "id": "00000000-0000-0000-0000-000000000010",
      "barcode": "7501055302345",
      "name": "Avena tradicional",
      "brand": "Quaker",
      "serving_size_g": 40,
      "calories": 150,
      "protein_g": 5,
      "carbs_g": 27,
      "fat_g": 3,
      "fiber_g": 4,
      "source": "open_food_facts",
      "image_url": null,
      "created_at": "2026-06-04T12:00:00Z"
    }
    """#

    private static let searchJSON = #"""
    {"results":[\#(oatmealJSON)]}
    """#

    @Test("lookup(barcode:) hits /products/barcode/{barcode} and decodes")
    func lookup_decodesProduct() async throws {
        let sut = makeSUT()
        MockURLProtocol.handler = { req in
            // Barcode lookup MUST use the dedicated /barcode/ route. The bare
            // /products/{id} route is UUID-typed on the backend and 422s on a
            // numeric barcode, so a raw-barcode path there never resolves.
            #expect(req.url?.path.hasSuffix("/api/v1/products/barcode/7501055302345") == true)
            return (Self.ok(req), Data(Self.oatmealJSON.utf8))
        }

        let product = try await sut.lookup(barcode: "7501055302345")
        #expect(product?.name == "Avena tradicional")
        #expect(product?.barcode == "7501055302345")
        #expect(product?.caloriesPerServing == 150)   // decoded from backend `calories`
        // Backend has no category column → defaulted to "" (server-only
        // fields source/image_url/created_at are ignored, not required).
        #expect(product?.category == "")
    }

    @Test("lookup(barcode:) returns nil on 404")
    func lookup_returnsNilOnNotFound() async throws {
        let sut = makeSUT()
        MockURLProtocol.handler = { req in
            (Self.notFound(req), Data())
        }
        let product = try await sut.lookup(barcode: "0000000000000")
        #expect(product == nil)
    }

    @Test("search(query:) calls /products/search?q= and parses results")
    func search_parsesResults() async throws {
        let sut = makeSUT()
        MockURLProtocol.handler = { req in
            let url = req.url!
            #expect(url.path.hasSuffix("/api/v1/products/search"))
            let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "q" }?.value
            #expect(q == "avena")
            return (Self.ok(req), Data(Self.searchJSON.utf8))
        }

        let results = try await sut.search(query: "avena")
        #expect(results.count == 1)
        #expect(results.first?.brand == "Quaker")
    }

    @Test("search(query:) returns [] for blank input without any network call")
    func search_blankQueryShortCircuits() async throws {
        let sut = makeSUT()
        MockURLProtocol.handler = { req in
            Issue.record("search(blank) must not perform a network request")
            return (Self.ok(req), Data(Self.searchJSON.utf8))
        }
        let results = try await sut.search(query: "   ")
        #expect(results.isEmpty)
    }

    @Test("search(query:) percent-encodes multi-word queries in the q param")
    func search_encodesMultiWordQuery() async throws {
        let sut = makeSUT()
        MockURLProtocol.handler = { req in
            let url = req.url!
            #expect(url.path.hasSuffix("/api/v1/products/search"))
            let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "q" }?.value
            #expect(q == "pan integral")
            return (Self.ok(req), Data(Self.searchJSON.utf8))
        }
        _ = try await sut.search(query: "pan integral")
    }

    // MARK: - Helpers

    private static func ok(_ req: URLRequest) -> HTTPURLResponse {
        HTTPURLResponse(url: req.url!, statusCode: 200,
                        httpVersion: "HTTP/1.1",
                        headerFields: ["Content-Type": "application/json"])!
    }
    private static func notFound(_ req: URLRequest) -> HTTPURLResponse {
        HTTPURLResponse(url: req.url!, statusCode: 404,
                        httpVersion: "HTTP/1.1",
                        headerFields: nil)!
    }
}
