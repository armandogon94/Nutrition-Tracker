//
//  SettingsView.swift
//  Slice 0.5 mock — theme switcher (live), language, account actions.
//  Real account-deletion flow lands in Slice 11.
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.appTheme) private var theme
    @Environment(MockServiceContainer.self) private var services
    @Environment(ThemeStore.self) private var themeStore

    var body: some View {
        ZStack {
            ThemedBackdrop()
            ScrollView {
                VStack(spacing: 14) {
                    themeSection
                    languageSection
                    accountSection
                    Spacer(minLength: 60)
                }
                .padding(16)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Ajustes")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("APARIENCIA")
            VStack(spacing: 8) {
                themeRow(label: "Automático",
                         summary: "Sigue el sistema (oscuro → Liquid Glass, claro → Health Cards)",
                         id: nil,
                         isSelected: themeStore.selectedID == nil)
                themeRow(label: "Liquid Glass",
                         summary: "iOS 26 — translucencias, gradiente profundo",
                         id: .liquidGlass,
                         isSelected: themeStore.selectedID == .liquidGlass)
                themeRow(label: "Health Cards",
                         summary: "Apple Health — superficies claras, sombras suaves",
                         id: .healthCards,
                         isSelected: themeStore.selectedID == .healthCards)
            }
        }
    }

    @ViewBuilder
    private func themeRow(label: String, summary: String, id: ThemeID?, isSelected: Bool) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                themeStore.selectedID = id
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? theme.accent : theme.textTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(theme.font.bodyMedium)
                        .foregroundStyle(theme.textPrimary)
                    Text(summary)
                        .font(theme.font.caption)
                        .foregroundStyle(theme.textSecondary)
                }
                Spacer()
            }
            .padding(14)
            .themedCard()
        }
        .buttonStyle(.plain)
    }

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("IDIOMA")
            HStack {
                Text("Español (es-419)")
                    .font(theme.font.body)
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                Text("Predeterminado")
                    .font(theme.font.caption)
                    .foregroundStyle(theme.textTertiary)
            }
            .padding(14)
            .themedCard()
        }
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("CUENTA")
            VStack(spacing: 0) {
                Button {
                    Task { await services.auth.signOut() }
                } label: {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text("Cerrar sesión")
                        Spacer()
                    }
                    .padding(14)
                    .foregroundStyle(theme.textPrimary)
                }
                Divider().opacity(0.2)
                Button { } label: {
                    HStack {
                        Image(systemName: "trash.fill")
                        Text("Eliminar cuenta")
                        Spacer()
                    }
                    .padding(14)
                    .foregroundStyle(theme.negative)
                }
            }
            .themedCard()

            Text("La eliminación de cuenta llega completa en Slice 11.")
                .font(theme.font.caption)
                .foregroundStyle(theme.textTertiary)
                .padding(.horizontal, 4)
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(theme.font.captionMedium).tracking(1.4)
            .foregroundStyle(theme.textTertiary)
            .padding(.horizontal, 4)
    }
}
