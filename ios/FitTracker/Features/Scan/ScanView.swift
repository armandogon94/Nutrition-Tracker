//
//  ScanView.swift
//  Slice 3 — Real Scan & Log entry point. Hosts the VisionKit barcode
//  scanner, falls through to manual entry when the camera is denied
//  or unsupported, and orchestrates ProductLookupSheet + log flow.
//
//  Mock viewfinder from Slice 0.5 lives behind `#if SLICE_0_MOCK` for
//  reference — we keep none of it in the production view.
//

import SwiftUI
import SwiftData
import VisionKit

struct ScanView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(MockServiceContainer.self) private var services

    @State private var scannedBarcode: String? = nil
    @State private var lookupState: ProductLookupState? = nil
    @State private var showManualSheet = false
    @State private var showPhotoSheet = false
    @State private var pendingMealType: MealType = .snack
    @State private var statusBanner: BannerState? = nil

    var body: some View {
        ZStack(alignment: .bottom) {
            scannerLayer
            actionsBar
            if let banner = statusBanner {
                bannerView(banner)
            }
        }
        .navigationTitle(Text("scan_section_view"))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: scannedBarcode) { _, newValue in
            guard let code = newValue else { return }
            Task { await runLookup(barcode: code) }
        }
        .sheet(item: lookupBinding) { state in
            ProductLookupSheet(
                state: state,
                defaultMealType: pendingMealType,
                onLog: { product, servings, mealType in
                    await logProduct(product, servings: servings, mealType: mealType)
                },
                onCreateCustom: {
                    lookupState = nil
                    showManualSheet = true
                }
            )
        }
        .sheet(isPresented: $showManualSheet) {
            ManualEntrySheet(
                onSelect: { product in
                    showManualSheet = false
                    lookupState = .found(product)
                },
                productsService: services.products
            )
        }
        .sheet(isPresented: $showPhotoSheet) {
            PhotoCaptureView(
                onRecognized: { recognition in
                    showPhotoSheet = false
                    let product = recognition.intoProduct()
                    lookupState = .found(product)
                }
            )
        }
    }

    // MARK: - Scanner

    @ViewBuilder
    private var scannerLayer: some View {
        if #available(iOS 16.0, *) {
            BarcodeScannerHostView(scannedBarcode: $scannedBarcode)
        } else {
            unsupportedFallback
        }
    }

    private var unsupportedFallback: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(theme.negative)
                Text("scan_unsupported_title")
                    .font(theme.font.titleCompact)
                    .foregroundStyle(.white)
                Text("scan_unsupported_body")
                    .font(theme.font.body)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
            }
            .padding(28)
        }
    }

    // MARK: - Actions bar

    private var actionsBar: some View {
        HStack(spacing: 12) {
            Button {
                showManualSheet = true
            } label: {
                actionTile(icon: "magnifyingglass", title: Text("scan_action_search"))
            }
            Button {
                showPhotoSheet = true
            } label: {
                actionTile(icon: "camera.fill", title: Text("scan_action_photo"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 22)
    }

    private func actionTile(icon: String, title: Text) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
            title
                .font(theme.font.captionMedium)
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private func bannerView(_ banner: BannerState) -> some View {
        HStack(spacing: 8) {
            Image(systemName: banner.kind.symbol)
                .font(.system(size: 13, weight: .semibold))
            Text(verbatim: banner.text)
                .font(theme.font.caption)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(bannerColor(for: banner.kind).opacity(0.95), in: Capsule())
        .padding(.bottom, 96)
        .transition(.opacity)
    }

    /// Maps a banner kind to a theme colour: positive for a confirmed sync, a
    /// secondary accent for "pending" (it's fine, just not done yet), and the
    /// theme's negative colour for a real failure.
    private func bannerColor(for kind: BannerKind) -> Color {
        switch kind {
        case .success: return theme.positive
        case .pending: return theme.accentSecondary
        case .failure: return theme.negative
        }
    }

    // MARK: - Flow

    @MainActor
    private func runLookup(barcode: String) async {
        lookupState = .loading
        do {
            if let product = try await services.products.lookup(barcode: barcode) {
                lookupState = .found(product)
            } else {
                lookupState = .notFound
            }
        } catch {
            lookupState = .failed(error.localizedDescription)
        }
        // Reset the binding so the same code can rescan after dismissal
        scannedBarcode = nil
    }

    @MainActor
    private func logProduct(_ product: Product, servings: Double, mealType: MealType) async {
        guard let userId = services.auth.currentUser?.id else { return }
        // Use the injected, app-wide meal service (one shared authenticated
        // APIClient + the live SwiftData store + the shared offline queue)
        // rather than building an ad-hoc MealService here — an ad-hoc one
        // bypasses 401-refresh and never feeds the durable offline queue.
        let outcome = await logViaContainer(product, servings: servings,
                                            mealType: mealType, userId: userId)

        // Honest UX: distinguish a confirmed server write from a durable
        // local-only save from an outright failure — never a blanket success.
        switch outcome {
        case .synced:
            withAnimation { statusBanner = .init(text: String(localized: "meals_log_saved_synced"),
                                                 kind: .success) }
        case .pending:
            withAnimation { statusBanner = .init(text: String(localized: "meals_log_saved_offline"),
                                                 kind: .pending) }
        case .failed:
            withAnimation { statusBanner = .init(text: String(localized: "meals_log_failed"),
                                                 kind: .failure) }
        }

        // Mirror to Apple Health only when something was actually saved
        // (synced or pending). Best-effort; HealthKit failure must never
        // block meal-log UX. HealthKitService dedupes on its ExternalUUID.
        if let item = outcome.item {
            Task { @MainActor in
                _ = try? await HealthKitService.shared.writeMealEntry(item)
            }
        }
        // A failure stays on screen a touch longer so the user notices it.
        let dismissAfter: UInt64 = outcome.isFailure ? 4_000_000_000 : 2_500_000_000
        Task {
            try? await Task.sleep(nanoseconds: dismissAfter)
            withAnimation { statusBanner = nil }
        }
    }

    /// Logs through `services.meals`, mapping the result to a UI-facing
    /// outcome. Prefers the concrete `MealService` so we can report the true
    /// synced-vs-pending state; falls back to the protocol surface (mocks /
    /// previews), where a successful return is treated as saved-pending and a
    /// throw as a failure.
    @MainActor
    private func logViaContainer(_ product: Product, servings: Double,
                                 mealType: MealType, userId: UUID) async -> LogOutcome {
        if let real = services.meals as? MealService {
            do {
                let res = try await real.logItemReturningOutcome(
                    product: product, servings: servings,
                    mealType: mealType, mealDate: Date(), userId: userId)
                return res.state == .synced ? .synced(res.item) : .pending(res.item)
            } catch {
                return .failed   // the LOCAL write failed — genuinely lost
            }
        }
        if let logging = services.meals as? any MealLoggingServiceProtocol {
            do {
                let item = try await logging.logItem(
                    product: product, servings: servings,
                    mealType: mealType, mealDate: Date(), userId: userId)
                return .pending(item)   // can't tell synced from pending here
            } catch {
                return .failed
            }
        }
        return .failed
    }

    // MARK: - Sheet binding

    /// Bridge a non-Identifiable enum to `.sheet(item:)` by wrapping it.
    private var lookupBinding: Binding<IdentifiableLookupState?> {
        Binding(
            get: { lookupState.map(IdentifiableLookupState.init) },
            set: { newValue in
                if newValue == nil { lookupState = nil }
            }
        )
    }
}

// MARK: - Log outcome + banner state

/// The user-facing result of a meal-log attempt, derived from MealService's
/// sync state. Drives an HONEST banner: a confirmed server write, a durable
/// local-only save (will replay), or a genuine save failure — never a
/// blanket success (Codex finding #4).
enum LogOutcome {
    case synced(MealItem)    // backend confirmed
    case pending(MealItem)   // saved locally + durably queued; will sync later
    case failed              // the local write itself failed — data lost

    /// The inserted item when something was actually saved (synced/pending),
    /// used to mirror the entry to HealthKit. `nil` on failure.
    var item: MealItem? {
        switch self {
        case .synced(let i), .pending(let i): return i
        case .failed: return nil
        }
    }

    var isFailure: Bool { if case .failed = self { return true } else { return false } }
}

/// What a scan-status banner shows + how it's styled.
struct BannerState: Equatable {
    let text: String
    let kind: BannerKind
}

enum BannerKind: Equatable {
    case success   // synced to the backend
    case pending   // saved locally, pending sync
    case failure   // failed to save

    /// SF Symbol that reinforces the meaning at a glance.
    var symbol: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .pending: return "arrow.triangle.2.circlepath"   // "will sync"
        case .failure: return "exclamationmark.triangle.fill"
        }
    }
}

/// Wrapper so we can use `.sheet(item:)` with a non-Identifiable enum.
struct IdentifiableLookupState: Identifiable {
    let id = UUID()
    let state: ProductLookupState
    init(_ state: ProductLookupState) { self.state = state }
}

private extension View {
    /// Sugar for `sheet(item:content:)` accepting our wrapper directly.
    func sheet(item: Binding<IdentifiableLookupState?>,
               @ViewBuilder content: @escaping (ProductLookupState) -> some View) -> some View {
        sheet(item: item) { wrapper in content(wrapper.state) }
    }
}

#Preview("Scan — Liquid Glass") {
    NavigationStack { ScanView() }
        .environment(\.appTheme, LiquidGlassTheme())
        .environment(MockServiceContainer())
        .preferredColorScheme(.dark)
}
