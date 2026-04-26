//
//  LoginView.swift
//  Slice 0.5 mock — email + password fields, Sign-in-with-Apple button
//  (visual only), and 3 quick-select buttons for the seeded test
//  accounts. Real auth lands in Slice 1.
//

import SwiftUI

struct LoginView: View {
    @Environment(\.appTheme) private var theme
    @Environment(MockServiceContainer.self) private var services

    @State private var email = ""
    @State private var password = ""
    @State private var isSubmitting = false
    @State private var errorText: String?
    @State private var appleCoordinator = AppleIDCoordinator()

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                logo

                VStack(spacing: 14) {
                    field("Correo", text: $email, icon: "envelope.fill", isSecure: false)
                    field("Contraseña", text: $password, icon: "lock.fill", isSecure: true)

                    if let errorText {
                        Text(errorText)
                            .font(theme.font.caption)
                            .foregroundStyle(theme.negative)
                    }

                    primaryButton("Iniciar sesión") { Task { await login() } }
                        .disabled(isSubmitting)

                    appleButton

                    HStack(spacing: 4) {
                        Text("¿No tienes cuenta?")
                            .foregroundStyle(theme.textSecondary)
                        NavigationLink("Crear cuenta") { RegisterView() }
                            .foregroundStyle(theme.accent)
                    }
                    .font(theme.font.caption)
                }
                .padding(20)
                .themedCard()

                quickPickCard
            }
            .padding(20)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Subviews

    private var logo: some View {
        VStack(spacing: 4) {
            Image(systemName: "flame.fill")
                .font(.system(size: 40))
                .foregroundStyle(theme.accent)
            Text("FitTracker")
                .font(theme.font.largeTitle)
                .foregroundStyle(theme.textPrimary)
            Text("Nutrición y entrenamientos")
                .font(theme.font.caption)
                .foregroundStyle(theme.textTertiary)
        }
        .padding(.top, 28)
    }

    private func field(_ placeholder: String, text: Binding<String>, icon: String, isSecure: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(theme.textTertiary)
                .frame(width: 20)
            Group {
                if isSecure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .foregroundStyle(theme.textPrimary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme.surfaceSecondary)
        )
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if isSubmitting {
                    ProgressView().tint(.black)
                } else {
                    Text(title)
                        .font(theme.font.bodyMedium)
                        .foregroundStyle(.black)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(theme.accent, in: Capsule())
        }
    }

    private var appleButton: some View {
        Button {
            Task { await signInWithApple() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "applelogo")
                Text("Continuar con Apple")
            }
            .font(theme.font.bodyMedium)
            .foregroundStyle(theme.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .stroke(theme.textTertiary.opacity(0.3), lineWidth: 1)
            )
        }
        .disabled(isSubmitting)
    }

    @MainActor
    private func signInWithApple() async {
        errorText = nil
        do {
            let cred = try await appleCoordinator.requestSignIn()
            isSubmitting = true
            defer { isSubmitting = false }
            try await services.auth.signInWithApple(
                identityToken: cred.identityToken,
                userIdentifier: cred.userIdentifier,
                email: cred.email,
                fullName: cred.fullName
            )
        } catch AppleIDError.userCancelled {
            // Silent — user closed the sheet
        } catch {
            errorText = error.localizedDescription
        }
    }

    private var quickPickCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CUENTAS DE PRUEBA (DEBUG)")
                .font(theme.font.captionMedium)
                .tracking(1.3)
                .foregroundStyle(theme.textTertiary)
            ForEach(MockData.testAccounts) { account in
                Button {
                    quickLogin(as: account)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.displayName)
                                .font(theme.font.bodyMedium)
                                .foregroundStyle(theme.textPrimary)
                            Text(account.email)
                                .font(theme.font.caption)
                                .foregroundStyle(theme.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.right")
                            .foregroundStyle(theme.accent)
                    }
                    .padding(.vertical, 6)
                }
                if account.id != MockData.testAccounts.last?.id {
                    Divider().opacity(0.2)
                }
            }
        }
        .padding(18)
        .themedInnerCard()
    }

    @MainActor
    private func quickLogin(as account: MockUser) {
        // Mock path = instant; Real path = drive the form and submit.
        if let mock = services.auth as? MockAuthService {
            mock.quickLogin(as: account)
            return
        }
        email = account.email
        password = "test1234"
        Task { await login() }
    }

    // MARK: - Actions

    @MainActor
    private func login() async {
        errorText = nil
        guard !email.isEmpty, !password.isEmpty else {
            errorText = "Completa correo y contraseña"
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await services.auth.login(email: email, password: password)
        } catch {
            errorText = error.localizedDescription
        }
    }
}

#Preview("Login — Liquid Glass") {
    NavigationStack { LoginView() }
        .environment(\.appTheme, LiquidGlassTheme())
        .environment(MockServiceContainer())
        .preferredColorScheme(.dark)
}

#Preview("Login — Health Cards") {
    NavigationStack { LoginView() }
        .environment(\.appTheme, HealthCardsTheme())
        .environment(MockServiceContainer())
        .preferredColorScheme(.light)
}
