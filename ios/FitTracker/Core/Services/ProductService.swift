//
//  ProductService.swift
//  Slice 3: real ProductsServiceProtocol implementation. Routes calls
//  through APIClient and translates DTOs to domain Product structs.
//
//  Backend contract (per SPEC.md §11):
//    GET /api/v1/products/{barcode}        → ProductDTO | 404
//    GET /api/v1/products/search?q=<text>  → { results: [ProductDTO] }
//
//  Network errors propagate; APIError.notFound on lookup is collapsed
//  to `nil` because "no such barcode" is a normal lookup result, not a
//  failure mode. A consumer wants to fall through to manual entry, not
//  show a red toast.
//

import Foundation

final class ProductService: ProductsServiceProtocol, @unchecked Sendable {

    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    /// Search backend-cached products by name. Empty queries return [];
    /// the caller is responsible for not firing requests for blank input.
    func search(query: String) async throws -> [Product] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let resp: ProductSearchResponse = try await api.get(
            "/api/v1/products/search",
            query: ["q": trimmed]
        )
        return resp.results.map(Product.init(from:))
    }

    /// Look up a product by barcode. Returns nil for 404 so the UI can
    /// open the "create custom food" path.
    func lookup(barcode: String) async throws -> Product? {
        do {
            let dto: ProductDTO = try await api.get("/api/v1/products/\(barcode)")
            return Product(from: dto)
        } catch APIError.notFound {
            return nil
        }
    }
}
