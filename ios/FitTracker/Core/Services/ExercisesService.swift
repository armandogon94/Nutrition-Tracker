//
//  ExercisesService.swift
//  Slice 6.1: backend-backed exercise catalog with SwiftData cache.
//  - Online: hits /api/v1/exercises with optional muscle/equipment filters
//    and warms the SwiftData cache on success.
//  - Offline: falls back to a SwiftData fetch with the same filters
//    re-applied locally.
//  - Search: 300ms debouncer (`DebouncedSearcher`) for view code; the
//    raw `search()` method itself is synchronous from the caller's POV
//    so tests can drive it directly.
//  - Cache prewarm: `prewarmCache()` is fire-and-forget on first
//    authenticated launch (Slice 6.6).
//
//  Skills invoked:
//   - api-and-interface-design
//   - everything-claude-code:swift-actor-persistence
//   - performance-optimization (cache + scroll readiness)
//

import Foundation
import SwiftData

// MARK: - Service

final class ExercisesService: ExercisesServiceProtocol, @unchecked Sendable {

    private let api: APIClient
    private let container: ModelContainer

    @MainActor
    init(api: APIClient, container: ModelContainer) {
        self.api = api
        self.container = container
    }

    // MARK: - ExercisesServiceProtocol

    func allExercises() async throws -> [Exercise] {
        do {
            let dto: ExerciseListDTO = try await api.get("/api/v1/exercises",
                                                          query: ["limit": "200"])
            let domain = dto.exercises.compactMap { Self.mapDTO($0) }
            await Self.warmCache(domain, container: container)
            return domain
        } catch APIError.offline, APIError.network, APIError.cancelled {
            return try await Self.cachedExercises(query: "", muscle: nil,
                                                   equipment: nil,
                                                   container: container)
        } catch let urlErr as URLError where urlErr.code == .notConnectedToInternet
                                          || urlErr.code == .networkConnectionLost {
            return try await Self.cachedExercises(query: "", muscle: nil,
                                                   equipment: nil,
                                                   container: container)
        }
    }

    func search(query: String, muscle: MuscleGroup?, equipment: Equipment?) async throws -> [Exercise] {
        var params: [String: String] = ["limit": "200"]
        let trimmedQuery = query.trimmingCharacters(in: .whitespaces)
        if !trimmedQuery.isEmpty { params["q"] = trimmedQuery }
        if let muscle { params["muscle"] = muscle.rawValue }
        if let equipment { params["equipment"] = equipment.rawValue }

        do {
            let dto: ExerciseListDTO = try await api.get("/api/v1/exercises", query: params)
            let domain = dto.exercises.compactMap { Self.mapDTO($0) }
            await Self.warmCache(domain, container: container)
            return domain
        } catch APIError.offline, APIError.network, APIError.cancelled {
            return try await Self.cachedExercises(query: trimmedQuery, muscle: muscle,
                                                   equipment: equipment,
                                                   container: container)
        } catch let urlErr as URLError where urlErr.code == .notConnectedToInternet
                                          || urlErr.code == .networkConnectionLost {
            return try await Self.cachedExercises(query: trimmedQuery, muscle: muscle,
                                                   equipment: equipment,
                                                   container: container)
        }
    }

    /// Fire-and-forget. Called once on authenticated app launch so the
    /// browser screen has data to render in airplane mode.
    func prewarmCache() {
        Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            _ = try? await self.allExercises()
        }
    }

    // MARK: - Mapping

    static func mapDTO(_ dto: ExerciseDTO) -> Exercise? {
        guard let id = UUID(uuidString: dto.id) else { return nil }
        let primary = MuscleGroup(rawValue: (dto.primary_muscle).lowercased()) ?? .core
        let secondary: [MuscleGroup] = (dto.secondary_muscles ?? "")
            .split(separator: ",")
            .compactMap { MuscleGroup(rawValue: $0.trimmingCharacters(in: .whitespaces).lowercased()) }
        let equipment = Equipment(rawValue: (dto.equipment ?? "").lowercased()) ?? .bodyweight
        let difficulty = Difficulty(rawValue: (dto.difficulty ?? "").lowercased()) ?? .beginner
        return Exercise(
            id: id,
            name: dto.name,
            primaryMuscle: primary,
            secondaryMuscles: secondary,
            equipment: equipment,
            difficulty: difficulty,
            videoURL: (dto.video_url).flatMap(URL.init(string:))
        )
    }

    // MARK: - Cache

    @MainActor
    private static func warmCache(_ exercises: [Exercise], container: ModelContainer) async {
        let ctx = ModelContext(container)
        do {
            for ex in exercises {
                let exId = ex.id
                let existing = try ctx.fetch(FetchDescriptor<ExerciseEntity>(
                    predicate: #Predicate { $0.id == exId }
                ))
                let secondaryRaw = ex.secondaryMuscles.map(\.rawValue).joined(separator: ",")
                if let row = existing.first {
                    row.name = ex.name
                    row.primaryMuscle = ex.primaryMuscle.rawValue
                    row.secondaryMusclesRaw = secondaryRaw
                    row.equipment = ex.equipment.rawValue
                    row.difficulty = ex.difficulty.rawValue
                    row.videoURLString = ex.videoURL?.absoluteString
                    row.lastSyncedAt = .now
                } else {
                    ctx.insert(ExerciseEntity(
                        id: ex.id,
                        name: ex.name,
                        primaryMuscle: ex.primaryMuscle.rawValue,
                        secondaryMusclesRaw: secondaryRaw,
                        equipment: ex.equipment.rawValue,
                        difficulty: ex.difficulty.rawValue,
                        videoURLString: ex.videoURL?.absoluteString,
                        lastSyncedAt: .now
                    ))
                }
            }
            try ctx.save()
        } catch {
            // Cache warmup is best-effort.
        }
    }

    @MainActor
    private static func cachedExercises(query: String,
                                        muscle: MuscleGroup?,
                                        equipment: Equipment?,
                                        container: ModelContainer) throws -> [Exercise] {
        let ctx = ModelContext(container)
        let rows = try ctx.fetch(FetchDescriptor<ExerciseEntity>(
            sortBy: [SortDescriptor(\.name)]
        ))
        let q = query.lowercased()
        return rows.compactMap { row -> Exercise? in
            // Apply filters in-memory — tiny dataset (<100 rows).
            if let muscle, row.primaryMuscle.lowercased() != muscle.rawValue,
               !row.secondaryMusclesRaw.lowercased().split(separator: ",")
                   .contains(where: { $0.trimmingCharacters(in: .whitespaces) == muscle.rawValue }) {
                return nil
            }
            if let equipment, row.equipment.lowercased() != equipment.rawValue {
                return nil
            }
            if !q.isEmpty, !row.name.lowercased().contains(q) {
                return nil
            }
            return Exercise(
                id: row.id,
                name: row.name,
                primaryMuscle: MuscleGroup(rawValue: row.primaryMuscle.lowercased()) ?? .core,
                secondaryMuscles: row.secondaryMusclesRaw
                    .split(separator: ",")
                    .compactMap { MuscleGroup(rawValue: $0.trimmingCharacters(in: .whitespaces).lowercased()) },
                equipment: Equipment(rawValue: row.equipment.lowercased()) ?? .bodyweight,
                difficulty: Difficulty(rawValue: row.difficulty.lowercased()) ?? .beginner,
                videoURL: row.videoURLString.flatMap(URL.init(string:))
            )
        }
    }
}

// MARK: - DebouncedSearcher

/// Drop-in 300ms debounce helper. Each `fire()` cancels any pending
/// task and replaces it. Only the last call's query reaches the
/// supplied async closure. Lives outside the service so view code
/// can compose it without rebuilding the cache logic on every keystroke.
@MainActor
final class DebouncedSearcher {
    private var pending: Task<Void, Never>?
    private let intervalMillis: UInt64
    private let action: (String) async -> Void

    init(intervalMillis: UInt64 = 300,
         action: @escaping @Sendable (String) async -> Void) {
        self.intervalMillis = intervalMillis
        self.action = action
    }

    func fire(query: String) {
        pending?.cancel()
        let interval = intervalMillis
        let work = action
        pending = Task { @MainActor in
            try? await Task.sleep(nanoseconds: interval * 1_000_000)
            if Task.isCancelled { return }
            await work(query)
        }
    }

    func cancel() {
        pending?.cancel()
        pending = nil
    }
}
