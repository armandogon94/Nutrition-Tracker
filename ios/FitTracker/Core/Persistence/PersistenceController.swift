//
//  PersistenceController.swift
//  Owns the SwiftData ModelContainer. App passes the live container; tests
//  use `inMemory()` for isolation. Slice 2.1.
//

import Foundation
import SwiftData

@MainActor
final class PersistenceController {

    /// Production container backed by an on-disk store at the app's
    /// default Application Support location.
    static let live: PersistenceController = {
        do {
            return try PersistenceController(inMemory: false)
        } catch {
            fatalError("Failed to construct live SwiftData ModelContainer: \(error)")
        }
    }()

    let container: ModelContainer

    init(inMemory: Bool) throws {
        let schema = Schema(versionedSchema: FitTrackerSchemaV1.self)
        let configuration = ModelConfiguration(
            "FitTracker",
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        self.container = try ModelContainer(
            for: schema,
            migrationPlan: FitTrackerMigrationPlan.self,
            configurations: [configuration]
        )
    }

    /// Convenience for tests. Each call returns a fresh in-memory container
    /// so test cases never see each other's writes.
    static func makeInMemory() throws -> PersistenceController {
        try PersistenceController(inMemory: true)
    }
}
