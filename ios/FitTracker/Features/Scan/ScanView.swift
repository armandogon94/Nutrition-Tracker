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
    @Environment(\.modelContext) private var modelContext

    @State private var scannedBarcode: String? = nil
    @State private var lookupState: ProductLookupState? = nil
    @State private var showManualSheet = false
    @State private var showPhotoSheet = false
    @State private var pendingMealType: MealType = .snack
    @State private var statusBanner: String? = nil

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

    private func bannerView(_ message: String) -> some View {
        Text(verbatim: message)
            .font(theme.font.caption)
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(theme.accent.opacity(0.95), in: Capsule())
            .padding(.bottom, 96)
            .transition(.opacity)
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
        let mealService = MealService(api: APIClient(tokenProvider: KeychainTokenStore.shared),
                                       context: modelContext)
        do {
            _ = try await mealService.logItem(
                product: product,
                servings: servings,
                mealType: mealType,
                mealDate: Date(),
                userId: userId
            )
            withAnimation { statusBanner = String(localized: "meals_log_saved_offline") }
        } catch {
            // Optimistic write succeeded locally; banner notes pending sync.
            withAnimation { statusBanner = String(localized: "meals_log_saved_offline") }
        }
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            withAnimation { statusBanner = nil }
        }
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
