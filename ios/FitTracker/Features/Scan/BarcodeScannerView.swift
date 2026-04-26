//
//  BarcodeScannerView.swift
//  Slice 3.2: SwiftUI bridge for VisionKit's DataScannerViewController.
//
//  Why VisionKit and not AVFoundation: DataScannerViewController ships
//  with the OS-native viewfinder, multi-symbology recognition, and the
//  same on-device ML Apple uses in the Camera app. iOS 16+ ; we gate
//  the entire scanner path on `DataScannerViewController.isSupported`
//  (which is false on devices without a Neural Engine — vanishingly
//  rare on our iOS 26 baseline, but the fallback is just "use the
//  manual search sheet").
//
//  Camera permission (NSCameraUsageDescription) is requested on first
//  scan, NOT at app launch — Apple HIG and SPEC.md §15. The flow:
//      1. User taps "Scan" tab/FAB
//      2. ScanView checks AVCaptureDevice authorizationStatus
//      3. If .notDetermined, request access; on denial flip to manual
//         entry with "Open Settings" affordance.
//

import SwiftUI
import VisionKit
import AVFoundation

/// SwiftUI wrapper around DataScannerViewController. Emits decoded
/// barcode strings via `onScan`. The view does NOT perform product
/// lookup itself — the host (`ScanView`) wires the callback to
/// `ProductService.lookup(barcode:)` so the same scanner can be reused
/// elsewhere (e.g. workout-equipment QR codes in a future slice).
@available(iOS 16.0, *)
struct BarcodeScannerView: UIViewControllerRepresentable {

    /// Called once per decoded barcode. The coordinator pauses the
    /// scanner for `pauseAfterScan` seconds so a single visible barcode
    /// doesn't fire dozens of duplicate events. Caller is responsible
    /// for dismissing/popping if appropriate.
    let onScan: @Sendable (String) -> Void

    /// How long to pause after a successful scan before resuming. Apple
    /// recommends ≥500ms; 1s feels right on real devices.
    var pauseAfterScan: TimeInterval = 1.0

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan, pauseAfterScan: pauseAfterScan)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [
                .barcode(symbologies: [.ean13, .ean8, .upce, .code128, .qr])
            ],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        // No-op: the coordinator manages start/stop.
    }

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onScan: @Sendable (String) -> Void
        private let pauseAfterScan: TimeInterval
        private var isPaused = false

        init(onScan: @escaping @Sendable (String) -> Void, pauseAfterScan: TimeInterval) {
            self.onScan = onScan
            self.pauseAfterScan = pauseAfterScan
        }

        func dataScanner(_ dataScanner: DataScannerViewController,
                          didAdd addedItems: [RecognizedItem],
                          allItems: [RecognizedItem]) {
            guard !isPaused else { return }
            for item in addedItems {
                if case .barcode(let barcode) = item, let value = barcode.payloadStringValue {
                    handleScan(value, scanner: dataScanner)
                    return
                }
            }
        }

        func dataScanner(_ dataScanner: DataScannerViewController,
                          didTapOn item: RecognizedItem) {
            guard !isPaused else { return }
            if case .barcode(let barcode) = item, let value = barcode.payloadStringValue {
                handleScan(value, scanner: dataScanner)
            }
        }

        private func handleScan(_ value: String, scanner: DataScannerViewController) {
            isPaused = true
            onScan(value)
            // Brief pause prevents duplicate emission for the same
            // barcode while it remains in the viewfinder.
            Task { [weak self, pauseAfterScan] in
                try? await Task.sleep(nanoseconds: UInt64(pauseAfterScan * 1_000_000_000))
                self?.isPaused = false
            }
        }
    }
}

/// Host view that owns the scanner lifecycle, permission flow, and
/// post-scan navigation to ProductLookupSheet. Designed so future
/// callers (FAB on HomeView) can present this as a sheet or a push.
@available(iOS 16.0, *)
struct BarcodeScannerHostView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    /// Bound by the parent so scanned codes can drive sheet
    /// presentation (e.g. ProductLookupSheet).
    @Binding var scannedBarcode: String?

    @State private var permissionState: CameraPermissionState = .checking

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch permissionState {
            case .checking, .denied, .restricted:
                permissionFallback
            case .granted:
                if DataScannerViewController.isSupported {
                    BarcodeScannerView { value in
                        scannedBarcode = value
                    }
                    .ignoresSafeArea()
                    overlay
                } else {
                    unsupportedFallback
                }
            }
        }
        .task { await checkPermission() }
        .navigationTitle(Text("scan_title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var overlay: some View {
        VStack {
            Spacer()
            Text("scan_hold_steady")
                .font(theme.font.caption)
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.bottom, 40)
        }
    }

    private var permissionFallback: some View {
        VStack(spacing: 18) {
            Image(systemName: "camera.metering.unknown")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(theme.textSecondary)
            Text("scan_permission_needed_title")
                .font(theme.font.titleCompact)
                .foregroundStyle(theme.textPrimary)
            Text("scan_permission_needed_body")
                .font(theme.font.body)
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
            Button {
                openSettings()
            } label: {
                Text("scan_open_settings")
                    .font(theme.font.bodyMedium)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(theme.accent, in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(.top, 8)
        }
        .padding(28)
        .frame(maxWidth: 360)
    }

    private var unsupportedFallback: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(theme.negative)
            Text("scan_unsupported_title")
                .font(theme.font.titleCompact)
                .foregroundStyle(theme.textPrimary)
            Text("scan_unsupported_body")
                .font(theme.font.body)
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
    }

    @MainActor
    private func checkPermission() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            permissionState = .granted
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            permissionState = granted ? .granted : .denied
        case .denied:
            permissionState = .denied
        case .restricted:
            permissionState = .restricted
        @unknown default:
            permissionState = .denied
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

enum CameraPermissionState: Sendable {
    case checking, granted, denied, restricted
}
