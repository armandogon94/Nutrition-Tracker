//
//  SettingsView.swift
//  Slice 0.5 mock — theme switcher (live), language, account actions.
//  Slice 11 / Codex review #17/#14: real account-deletion flow (confirmation
//  dialog → DELETE /api/v1/users/me → signOut), with errors surfaced.
//

import SwiftUI

/// Drives the destructive account-deletion flow. Network + signOut are passed
/// in as closures so SettingsView can supply the real
/// `APIClient(...).delete(...)` + `services.auth.signOut()` while the branching
/// (success / 404-graceful / failure) stays unit-testable. See
/// AccountDeletionModelTests.
@MainActor
@Observable
final class AccountDeletionModel {
    var isDeleting = false
    var errorMessage: String?

    /// Calls `delete`, then signs out on success. A 404 means the backend
    /// route isn't deployed yet (a parallel slice adds it) — we still sign the
    /// user out locally rather than trapping them. Any other failure is
    /// surfaced and the session is preserved.
    func performDeletion(
        delete: () async throws -> Void,
        signOut: () async -> Void
    ) async {
        guard !isDeleting else { return }
        isDeleting = true
        errorMessage = nil
        defer { isDeleting = false }

        do {
            try await delete()
            await signOut()
        } catch APIError.notFound {
            // Route not live yet — degrade gracefully to a local sign-out.
            await signOut()
        } catch {
            errorMessage = String(localized: "settings.deleteAccount.error")
        }
    }
}

struct SettingsView: View {
    @Environment(\.appTheme) private var theme
    @Environment(MockServiceContainer.self) private var services
    @Environment(ThemeStore.self) private var themeStore

    @State private var deletion = AccountDeletionModel()
    @State private var showDeleteConfirmation = false

    var body: some View {
        ZStack {
            ThemedBackdrop()
            ScrollView {
                VStack(spacing: 14) {
                    profileSection
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
        .confirmationDialog(
            Text("settings.deleteAccount.confirm.title"),
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                Task { await deleteAccount() }
            } label: {
                Text("settings.deleteAccount.confirm.action")
            }
            Button(role: .cancel) { } label: {
                Text("common_cancel")
            }
        } message: {
            Text("settings.deleteAccount.confirm.message")
        }
        .alert(
            Text("settings.deleteAccount.error"),
            isPresented: Binding(
                get: { deletion.errorMessage != nil },
                set: { if !$0 { deletion.errorMessage = nil } }
            )
        ) {
            Button(role: .cancel) { deletion.errorMessage = nil } label: {
                Text("common_close")
            }
        }
    }

    /// Performs the real deletion: an authenticated DELETE to the backend, then
    /// a sign-out. Routes through the container's `account` service — the real
    /// `AccountService` over the ONE shared refresh-aware `APIClient` — so an
    /// expired access token refreshes + retries instead of hard-failing
    /// (codex-review-4 P1). Previously this built its own inline client.
    private func deleteAccount() async {
        await deletion.performDeletion(
            delete: {
                try await services.account.deleteAccount()
            },
            signOut: {
                await services.auth.signOut()
            }
        )
    }

    /// Slice 5.5: entry points into the real ProfileView + GoalsView. These
    /// push onto the Settings tab's NavigationStack and consume the real
    /// ProfileService via `any ProfileServiceProtocol`.
    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(String(localized: "settings.section.account"))
            VStack(spacing: 0) {
                NavigationLink {
                    ProfileView()
                } label: {
                    settingsRow(icon: "person.crop.circle", titleKey: "settings.row.profile")
                }
                Divider().opacity(0.2)
                NavigationLink {
                    GoalsView()
                } label: {
                    settingsRow(icon: "target", titleKey: "settings.row.goals")
                }
            }
            .themedCard()
        }
    }

    private func settingsRow(icon: String, titleKey: LocalizedStringKey) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(theme.accent)
                .frame(width: 28)
            Text(titleKey)
                .font(theme.font.bodyMedium)
                .foregroundStyle(theme.textPrimary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundStyle(theme.textTertiary)
        }
        .padding(14)
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
                Button {
                    showDeleteConfirmation = true
                } label: {
                    HStack {
                        Image(systemName: "trash.fill")
                        Text("settings.deleteAccount.button")
                        Spacer()
                        if deletion.isDeleting {
                            ProgressView()
                        }
                    }
                    .padding(14)
                    .foregroundStyle(theme.negative)
                }
                .disabled(deletion.isDeleting)
            }
            .themedCard()
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(theme.font.captionMedium).tracking(1.4)
            .foregroundStyle(theme.textTertiary)
            .padding(.horizontal, 4)
    }
}
