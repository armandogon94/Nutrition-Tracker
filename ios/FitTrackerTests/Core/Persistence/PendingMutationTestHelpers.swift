//
//  PendingMutationTestHelpers.swift
//  Test-only conveniences for constructing PendingMutation payloads.
//
//  `ownerId` is a REQUIRED field on the production payloads (it's the
//  cross-user replay guard — Codex review #4 P0). To keep the many existing
//  legacy tests that predate user-scoping readable, these convenience
//  initializers default `ownerId` to `PendingMutationTestOwner.shared`.
//  Tests that exercise the SyncManager owner-guard set their
//  `setCurrentUserProvider` to this SAME id so a default-owned mutation
//  drains as "mine". Tests that need cross-user behavior pass explicit,
//  distinct owner ids (see OfflineQueueUserScopeTests / AuthService /
//  MealService lost-write suites).
//

import Foundation
@testable import FitTracker

/// Stable owner id used by the defaulted test initializers below, so a
/// drain-expecting test can register it as "the current user".
enum PendingMutationTestOwner {
    static let shared = UUID(uuidString: "0000FEED-0000-0000-0000-0000000000FF")!
}

extension LogMealItemPayload {
    /// Legacy-compatible initializer: omit `ownerId` to default it to the
    /// shared test owner. Production code always passes a real `ownerId`.
    init(clientItemId: UUID,
         mealType: String,
         mealDate: String,
         productId: UUID?,
         productName: String,
         brand: String?,
         servings: Double,
         calories: Double,
         proteinG: Double,
         carbsG: Double,
         fatG: Double) {
        self.init(ownerId: PendingMutationTestOwner.shared,
                  clientItemId: clientItemId,
                  mealType: mealType,
                  mealDate: mealDate,
                  productId: productId,
                  productName: productName,
                  brand: brand,
                  servings: servings,
                  calories: calories,
                  proteinG: proteinG,
                  carbsG: carbsG,
                  fatG: fatG)
    }
}

extension DeleteMealItemPayload {
    /// Legacy-compatible initializer: omit `ownerId` to default it to the
    /// shared test owner. Production code always passes a real `ownerId`.
    init(id: UUID) {
        self.init(ownerId: PendingMutationTestOwner.shared, id: id)
    }
}
