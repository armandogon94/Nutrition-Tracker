//
//  PhotoCaptureView.swift
//  Slice 3.5: lets the user take a photo of a meal, ships the image
//  to OUR backend (which proxies Claude Vision), and renders an editable
//  recognition card. Compresses to JPEG quality 0.7, max 1024px on the
//  longest edge so we keep payloads tiny and predictable.
//
//  Security & PHI: image bytes leave the device only to OUR backend.
//  We never call Anthropic directly from iOS — the API key would have
//  to ship inside the binary. The backend forwards via the existing
//  food_recognition.py service. No PII (email, user id, name) is
//  attached to the request body — see VisionService.
//

import SwiftUI
import UIKit
import PhotosUI

struct PhotoCaptureView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(MockServiceContainer.self) private var services

    /// Surface the recognized food back to the parent. Parent decides
    /// what to do with it — typically opens ProductLookupSheet so the
    /// user can edit grams + meal type before logging.
    let onRecognized: (VisionRecognition) -> Void
    /// Optional override for tests/previews. When nil (production), the view
    /// uses `services.vision` — the real `VisionService` over the ONE shared
    /// refresh-aware `APIClient` — instead of building its own client that
    /// would bypass 401 → refresh → retry (codex-review-4 P1).
    var injectedVisionService: (any VisionServiceProtocol)?

    private var visionService: any VisionServiceProtocol {
        injectedVisionService ?? services.vision
    }

    @State private var pickedImage: UIImage? = nil
    @State private var photoItem: PhotosPickerItem? = nil
    @State private var isAnalyzing = false
    @State private var recognition: VisionRecognition? = nil
    @State private var errorMessage: String? = nil
    @State private var showCamera = false

    var body: some View {
        NavigationStack {
            ZStack {
                ThemedBackdrop()
                ScrollView {
                    VStack(spacing: 18) {
                        previewCard
                        actionButtons
                        if isAnalyzing {
                            HStack(spacing: 10) {
                                ProgressView().tint(theme.accent)
                                Text("photo_capture_analyzing")
                                    .font(theme.font.body)
                                    .foregroundStyle(theme.textSecondary)
                            }
                            .padding(.top, 8)
                        }
                        if let recognition {
                            recognitionCard(recognition)
                        }
                        if let errorMessage {
                            Text(verbatim: errorMessage)
                                .font(theme.font.caption)
                                .foregroundStyle(theme.negative)
                        }
                        Spacer(minLength: 60)
                    }
                    .padding(20)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(Text("photo_capture_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Text("common_close")
                            .foregroundStyle(theme.accent)
                    }
                }
            }
            .sheet(isPresented: $showCamera) {
                CameraPicker(image: $pickedImage)
                    .ignoresSafeArea()
            }
            .onChange(of: pickedImage) { _, newImage in
                guard let image = newImage else { return }
                Task { await analyze(image) }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        pickedImage = image
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var previewCard: some View {
        if let image = pickedImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: theme.radii.card))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: theme.radii.card)
                    .fill(theme.surface.opacity(0.4))
                    .frame(height: 240)
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(theme.textSecondary)
            }
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button {
                showCamera = true
            } label: {
                Text("photo_capture_take")
                    .font(theme.font.bodyMedium)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(theme.accent, in: RoundedRectangle(cornerRadius: 14))
            }
            // PhotosPicker label is a @Sendable closure on iOS 26 so we
            // can't reference @Environment-bound theme tokens inside it.
            // Plain Text + tint() gets us the same look without the
            // isolation hop.
            PhotosPicker(selection: $photoItem, matching: .images) {
                Text("photo_capture_choose_library")
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(theme.accent)
        }
    }

    private func recognitionCard(_ rec: VisionRecognition) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("photo_capture_recognized")
                .font(theme.font.captionMedium)
                .tracking(1.2)
                .foregroundStyle(theme.textTertiary)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: rec.food)
                        .font(theme.font.titleCompact)
                        .foregroundStyle(theme.textPrimary)
                    Text(verbatim: "\(Int(rec.grams)) g · \(rec.confidence)")
                        .font(theme.font.caption)
                        .foregroundStyle(theme.textSecondary)
                }
                Spacer()
                if let calories = rec.calories {
                    Text(verbatim: "\(Int(calories)) kcal")
                        .font(theme.font.bodyMedium)
                        .foregroundStyle(theme.textPrimary)
                }
            }
            Button {
                onRecognized(rec)
            } label: {
                Text("product_lookup_log_button")
                    .font(theme.font.bodyMedium)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(theme.accent, in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(.top, 4)
        }
        .padding(16)
        .themedCard()
    }

    @MainActor
    private func analyze(_ image: UIImage) async {
        isAnalyzing = true
        errorMessage = nil
        recognition = nil
        defer { isAnalyzing = false }

        guard let payload = ImageCompressor.compressForVision(image) else {
            errorMessage = String(localized: "photo_capture_error")
            return
        }
        do {
            let result = try await visionService.recognize(jpegData: payload)
            recognition = result
        } catch {
            errorMessage = String(localized: "photo_capture_error")
        }
    }
}

// MARK: - Image compression

/// Compresses an image for Claude Vision. Resizes the longest edge to
/// 1024px and applies JPEG quality 0.7. Returns nil if the input is
/// degenerate (zero size). Pure helper — no UIKit dependency on a
/// specific view, so it's testable in isolation.
enum ImageCompressor {
    static func compressForVision(_ image: UIImage,
                                  maxDimension: CGFloat = 1024,
                                  quality: CGFloat = 0.7) -> Data? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(1.0, maxDimension / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}

// MARK: - UIImagePickerController bridge for the camera

struct CameraPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                    didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage {
                parent.image = img
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
