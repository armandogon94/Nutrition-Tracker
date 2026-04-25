//
//  RegisterView.swift
//  Slice 0.5 mock — email + display name + password + confirm fields.
//  Real auth integration lands in Slice 1.
//

import SwiftUI

struct RegisterView: View {
    @Environment(\.appTheme) private var theme
    @Environment(MockServiceContainer.self) private var services
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var name = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var isSubmitting = false
    @State private var errorText: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("Crea tu cuenta")
                    .font(theme.font.title)
                    .foregroundStyle(theme.textPrimary)

                VStack(spacing: 14) {
                    inputField("Correo", text: $email, icon: "envelope.fill", isSecure: false, isEmail: true)
                    inputField("Nombre", text: $name, icon: "person.fill", isSecure: false)
                    inputField("Contraseña", text: $password, icon: "lock.fill", isSecure: true)
                    inputField("Confirmar contraseña", text: $confirm, icon: "lock.shield.fill", isSecure: true)

                    if let errorText {
                        Text(errorText)
                            .font(theme.font.caption)
                            .foregroundStyle(theme.negative)
                    }

                    Button {
                        Task { await register() }
                    } label: {
                        Group {
                            if isSubmitting {
                                ProgressView().tint(.black)
                            } else {
                                Text("Crear cuenta")
                                    .font(theme.font.bodyMedium)
                                    .foregroundStyle(.black)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(theme.accent, in: Capsule())
                    }
                    .disabled(isSubmitting)
                }
                .padding(20)
                .themedCard()

                Text("Al crear una cuenta aceptas nuestros Términos y Política de Privacidad.")
                    .font(theme.font.caption)
                    .foregroundStyle(theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding(20)
        }
        .navigationTitle("Registro")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func inputField(_ placeholder: String, text: Binding<String>, icon: String, isSecure: Bool, isEmail: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(theme.textTertiary)
                .frame(width: 20)
            Group {
                if isSecure {
                    SecureField(placeholder, text: text)
                } else if isEmail {
                    TextField(placeholder, text: text)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } else {
                    TextField(placeholder, text: text)
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

    @MainActor
    private func register() async {
        errorText = nil
        guard !email.isEmpty, !name.isEmpty, !password.isEmpty else {
            errorText = "Completa todos los campos"
            return
        }
        guard password == confirm else {
            errorText = "Las contraseñas no coinciden"
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await services.auth.register(email: email, password: password, displayName: name)
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

#Preview("Register — Liquid Glass") {
    NavigationStack { RegisterView() }
        .environment(\.appTheme, LiquidGlassTheme())
        .environment(MockServiceContainer())
        .preferredColorScheme(.dark)
}

#Preview("Register — Health Cards") {
    NavigationStack { RegisterView() }
        .environment(\.appTheme, HealthCardsTheme())
        .environment(MockServiceContainer())
        .preferredColorScheme(.light)
}
