//
//  ProgramsService.swift
//  Slice 6.1: backend-backed programs catalog with SwiftData cache
//  fallback. The 9 preset programs change rarely — read-through cache
//  pattern: try the network, on success warm the local store, on
//  network error fall back to whatever the local store has.
//
//  Skills invoked:
//   - api-and-interface-design (protocol surface defined in
//     ServiceProtocols.swift)
//   - everything-claude-code:swift-actor-persistence (offline cache)
//

import Foundation
import SwiftData

/// Concrete `ProgramsServiceProtocol`. Backed by `APIClient` and a
/// SwiftData `ModelContainer`. The container is reached on the main actor;
/// we hop there for any `ModelContext` work.
final class ProgramsService: ProgramsServiceProtocol, @unchecked Sendable {

    private let api: APIClient
    private let container: ModelContainer

    @MainActor
    init(api: APIClient, container: ModelContainer) {
        self.api = api
        self.container = container
    }

    // MARK: - ProgramsServiceProtocol

    func allPrograms() async throws -> [WorkoutProgram] {
        do {
            let dtos: [WorkoutProgramListDTO] = try await api.get("/api/v1/workouts/programs")
            let domain = dtos.compactMap { Self.mapList($0) }
            await Self.warmCache(domain, container: container)
            return domain
        } catch APIError.offline, APIError.network, APIError.cancelled {
            return try await Self.cachedPrograms(container: container)
        } catch let urlErr as URLError where urlErr.code == .notConnectedToInternet
                                          || urlErr.code == .networkConnectionLost {
            return try await Self.cachedPrograms(container: container)
        }
    }

    func program(id: UUID) async throws -> WorkoutProgram? {
        do {
            let dto: WorkoutProgramDTO = try await api.get("/api/v1/workouts/programs/\(id.uuidString)")
            return Self.mapDetail(dto)
        } catch APIError.notFound {
            return nil
        }
    }

    // MARK: - Mapping

    /// List endpoint returns no `days`, so the resulting `WorkoutProgram`
    /// has `days: []`. That matches `WorkoutProgram`'s shape.
    static func mapList(_ dto: WorkoutProgramListDTO) -> WorkoutProgram? {
        guard let id = UUID(uuidString: dto.id) else { return nil }
        let difficulty = Difficulty(rawValue: (dto.difficulty ?? "").lowercased()) ?? .beginner
        return WorkoutProgram(
            id: id,
            name: dto.name,
            summary: dto.description ?? "",
            daysPerWeek: dto.days_per_week,
            difficulty: difficulty,
            days: []
        )
    }

    static func mapDetail(_ dto: WorkoutProgramDTO) -> WorkoutProgram? {
        guard let id = UUID(uuidString: dto.id) else { return nil }
        let difficulty = Difficulty(rawValue: (dto.difficulty ?? "").lowercased()) ?? .beginner
        let days: [WorkoutProgramDay] = dto.days.compactMap { dayDTO in
            guard let dayId = UUID(uuidString: dayDTO.id) else { return nil }
            let specs: [WorkoutProgramExerciseSpec] = dayDTO.exercises.compactMap { exDTO in
                guard let specId = UUID(uuidString: exDTO.id),
                      let exerciseId = UUID(uuidString: exDTO.exercise.id)
                else { return nil }
                return WorkoutProgramExerciseSpec(
                    id: specId,
                    exerciseId: exerciseId,
                    exerciseName: exDTO.exercise.name,
                    sets: exDTO.set_count,
                    repsLow: exDTO.rep_min ?? 0,
                    repsHigh: exDTO.rep_max ?? 0,
                    restSeconds: exDTO.rest_seconds ?? 60
                )
            }
            return WorkoutProgramDay(
                id: dayId,
                dayName: dayDTO.day_name ?? "Día \(dayDTO.day_number)",
                exercises: specs
            )
        }
        return WorkoutProgram(
            id: id,
            name: dto.name,
            summary: dto.description ?? "",
            daysPerWeek: dto.days_per_week,
            difficulty: difficulty,
            days: days
        )
    }

    // MARK: - Cache

    @MainActor
    private static func warmCache(_ programs: [WorkoutProgram], container: ModelContainer) async {
        let ctx = ModelContext(container)
        do {
            for p in programs {
                let pid = p.id
                let existing = try ctx.fetch(FetchDescriptor<WorkoutProgramEntity>(
                    predicate: #Predicate { $0.id == pid }
                ))
                if existing.isEmpty {
                    ctx.insert(WorkoutProgramEntity(
                        id: p.id,
                        name: p.name,
                        summary: p.summary,
                        daysPerWeek: p.daysPerWeek,
                        difficulty: p.difficulty.rawValue,
                        lastSyncedAt: .now
                    ))
                } else if let row = existing.first {
                    row.name = p.name
                    row.summary = p.summary
                    row.daysPerWeek = p.daysPerWeek
                    row.difficulty = p.difficulty.rawValue
                    row.lastSyncedAt = .now
                }
            }
            try ctx.save()
        } catch {
            // Cache warmup is best-effort; never throw.
        }
    }

    @MainActor
    private static func cachedPrograms(container: ModelContainer) throws -> [WorkoutProgram] {
        let ctx = ModelContext(container)
        let rows = try ctx.fetch(FetchDescriptor<WorkoutProgramEntity>(
            sortBy: [SortDescriptor(\.name)]
        ))
        return rows.map { row in
            WorkoutProgram(
                id: row.id,
                name: row.name,
                summary: row.summary,
                daysPerWeek: row.daysPerWeek,
                difficulty: Difficulty(rawValue: row.difficulty) ?? .beginner,
                days: []
            )
        }
    }
}
