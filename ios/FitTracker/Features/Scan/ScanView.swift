//
//  ScanView.swift
//  Slice 0.5 mock — fake viewfinder with a scanning animation, plus
//  buttons for manual entry and photo capture. Real VisionKit
//  DataScannerViewController integration in Slice 3.
//

import SwiftUI

struct ScanView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var showManualSheet = false
    @State private var scanLine: CGFloat = 0

    var body: some View {
        ZStack {
            ThemedBackdrop()

            VStack(spacing: 22) {
                viewfinder
                helperText
                Spacer()
                actionsRow
            }
            .padding(20)
        }
        .navigationTitle("Escanear")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showManualSheet) {
            ManualEntrySheet()
                .presentationDetents([.large])
                .presentationBackground(.ultraThinMaterial)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                scanLine = 1.0
            }
        }
    }

    private var viewfinder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.black)

            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(theme.accent, lineWidth: 2)

            // Animated scan line
            GeometryReader { geo in
                Rectangle()
                    .fill(LinearGradient(
                        colors: [.clear, theme.accent.opacity(0.6), .clear],
                        startPoint: .leading, endPoint: .trailing
                    ))
                    .frame(height: 2)
                    .offset(y: geo.size.height * scanLine)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            VStack {
                Spacer()
                Text("Apunta al código de barras")
                    .font(theme.font.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.bottom, 12)
            }
        }
        .frame(height: 320)
    }

    private var helperText: some View {
        Text("Sostén el teléfono firme. La detección VisionKit llega en Slice 3.")
            .font(theme.font.caption)
            .foregroundStyle(theme.textTertiary)
            .multilineTextAlignment(.center)
    }

    private var actionsRow: some View {
        HStack(spacing: 12) {
            Button {
                showManualSheet = true
            } label: {
                actionTile(icon: "square.and.pencil", title: "Buscar")
            }
            Button {
                showManualSheet = true
            } label: {
                actionTile(icon: "camera.fill", title: "Foto")
            }
        }
    }

    private func actionTile(icon: String, title: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(theme.accent)
            Text(title)
                .font(theme.font.bodyMedium)
                .foregroundStyle(theme.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .themedCard()
    }
}

struct ManualEntrySheet: View {
    @Environment(\.appTheme) private var theme
    @Environment(MockServiceContainer.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [Product] = MockData.products

    var body: some View {
        NavigationStack {
            ZStack {
                ThemedBackdrop()
                List {
                    ForEach(results) { product in
                        productRow(product)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .searchable(text: $query, prompt: "Buscar alimento")
            .onChange(of: query) { _, newValue in
                Task {
                    results = (try? await services.products.search(query: newValue)) ?? []
                }
            }
            .navigationTitle("Buscar alimento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }
                        .foregroundStyle(theme.accent)
                }
            }
        }
    }

    private func productRow(_ product: Product) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "cube.box.fill")
                .foregroundStyle(theme.accent)
                .frame(width: 38, height: 38)
                .background(theme.accent.opacity(0.18), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(product.name)
                    .font(theme.font.bodyMedium)
                    .foregroundStyle(theme.textPrimary)
                Text("\(product.brand ?? "Sin marca") · \(Int(product.caloriesPerServing)) kcal / \(Int(product.servingSizeG))g")
                    .font(theme.font.caption)
                    .foregroundStyle(theme.textSecondary)
            }
            Spacer()
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(theme.accent)
        }
        .padding(12)
        .themedInnerCard()
    }
}

#Preview("Scan — Liquid Glass") {
    NavigationStack { ScanView() }
        .environment(\.appTheme, LiquidGlassTheme())
        .environment(MockServiceContainer())
        .preferredColorScheme(.dark)
}
