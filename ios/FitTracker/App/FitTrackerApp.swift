//
//  FitTrackerApp.swift
//  @main entry. Resolves the active theme via ThemeStore and injects it
//  into the environment. A debug-only toggle in AppRoot flips themes at
//  runtime during Slice 0 / 0.5 design validation. Replaced in Slice 11
//  with a proper Settings picker.
//

import SwiftUI
import SwiftData

@main
struct FitTrackerApp: App {
    @State private var themeStore = ThemeStore()
    @State private var services = FitTrackerApp.makeServiceContainer()
    /// The single app-wide offline-sync coordinator. Built once at launch
    /// over the SAME durable queue (`OfflineQueue.shared`) that MealService
    /// enqueues failed writes into, so queued mutations actually get
    /// replayed. Without this, `pendingSync` rows would sit forever and the
    /// "saved offline" UI would be a lie (Codex finding #4).
    @State private var syncManager = FitTrackerApp.makeSyncManager()

    var body: some Scene {
        WindowGroup {
            ThemedRootView()
                .environment(themeStore)
                .environment(services)
                // Slice 3.7: install the SwiftData container so any view
                // using @Query / @Environment(\.modelContext) works.
                .modelContainer(PersistenceController.live.container)
                // Offline-sync: wire the reachability observer and replay
                // anything left from a prior session. `.task` runs once when
                // the scene's root appears.
                .task { startSync() }
                // Cold-launch replay (Codex review #5 P1): `startSync()` above
                // fires its first drain BEFORE AuthGate.restoreSession() sets
                // the user, so that drain flushes nothing (nil owner). When the
                // user later becomes known (restore / login / register / Apple),
                // re-trigger a drain so a queue left over from a prior session
                // actually replays. Keyed on the user id so it fires on every
                // sign-in transition, not just the first.
                .onChange(of: services.auth.currentUser?.id) { _, newUserId in
                    guard newUserId != nil else { return }
                    Task { await syncManager.replayAfterAuthChange() }
                }
        }
    }

    /// Production wiring: real AuthService + real NutritionService against
    /// APIClient + Keychain + the live SwiftData store (Slice 2.4b).
    /// Pass `-useMockAuth` at launch to fall back to the all-mock container
    /// (used by Slice 0.5 design-review screenshots and preview-driven
    /// testing).
    @MainActor
    private static func makeServiceContainer() -> MockServiceContainer {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-useMockAuth") {
            return MockServiceContainer()  // all-mock path
        }
        #endif
        return MockServiceContainer.production()
    }

    /// Build the one `SyncManager` for the whole app. It drains
    /// `OfflineQueue.shared` — the exact queue MealService enqueues failed
    /// writes into — over an authenticated client (Bearer from the same
    /// `KeychainTokenStore.shared` every service uses) and the system-wide
    /// `Reachability`. The 401-refresh coordinator is wired later in
    /// `startSync()` once the container's AuthService exists.
    @MainActor
    private static func makeSyncManager() -> SyncManager {
        SyncManager(
            api: APIClient(tokenProvider: KeychainTokenStore.shared),
            queue: .shared,
            reachability: .shared,
            // Live context so a successful background replay clears the local
            // `pendingSync` flag (keeps the cache truthful, matches the
            // foreground write path in MealService).
            context: PersistenceController.live.container.mainContext
        )
    }

    /// Wires the sync manager's replay client to the live AuthService for
    /// 401 → refresh → retry (the container's `auth` IS the real AuthService
    /// in production), then begins observing connectivity + drains the queue.
    /// In the all-mock path (`-useMockAuth`) there is no `TokenRefreshing`,
    /// so we skip wiring the refresher but still start the manager (harmless:
    /// the queue is empty in mock mode).
    @MainActor
    private func startSync() {
        if let refresher = services.auth as? any TokenRefreshing {
            syncManager.setRefresher(refresher)
        }
        // Owner-guard for replay: tell SyncManager who is signed in so it only
        // flushes the current user's queued writes and never replays user A's
        // offline mutation under user B's token after an account switch (Codex
        // review #4 P0). Captures the container (a reference type) so the
        // closure reads the LIVE current user on every drain, not a snapshot.
        let container = services
        syncManager.setCurrentUserProvider { container.auth.currentUser?.id }
        // Bind replay to the auth-session generation too (Codex review #5 P0):
        // the request-level guard aborts a queued write if the session changed
        // (sign-out, or account switch A→B) between drain start and the actual
        // send/401-refresh. Only the concrete AuthService exposes the counter;
        // the all-mock path has no generation, so replay there guards on owner
        // id alone (harmless: the mock queue is empty).
        if let authService = container.auth as? AuthService {
            syncManager.setSessionGenerationProvider { authService.sessionGeneration }
        }
        syncManager.startObservingConnectivity()
    }
}

/// Bridges the system color scheme into our theme protocol. `@Environment
/// (\.colorScheme)` is reliable inside Views but not at the App / Scene
/// level — a launch-time read in FitTrackerApp.body does not refresh when
/// system appearance changes. Resolving here means theme + system stay
/// in sync across appearance toggles and explicit user selections.
private struct ThemedRootView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(ThemeStore.self) private var themeStore

    var body: some View {
        let active = themeStore.theme(forColorScheme: colorScheme)
        // Only override system appearance when the user has explicitly
        // picked a theme. In automatic mode we let the system drive so
        // the colorScheme environment can flip and re-render the theme.
        let preferred: ColorScheme? = themeStore.selectedID == nil
            ? nil
            : active.preferredColorScheme
        AppRoot()
            .environment(\.appTheme, active)
            .preferredColorScheme(preferred)
    }
}
