//
//  AppleIDCoordinator.swift
//  Bridges ASAuthorizationController callbacks into an async/await
//  result that AuthService consumes. The SignInWithAppleButton in
//  LoginView triggers `requestSignIn()` and awaits the credential.
//

import AuthenticationServices
import Foundation

struct AppleIDCredential: Sendable {
    let identityToken: String
    let userIdentifier: String
    let email: String?
    let fullName: PersonNameComponents?
}

enum AppleIDError: Error, Sendable {
    case missingIdentityToken
    case userCancelled
    case authorizationFailed(String)
}

@MainActor
final class AppleIDCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {

    private var continuation: CheckedContinuation<AppleIDCredential, Error>?

    /// Presents the system Sign-in-with-Apple sheet and awaits the
    /// authorization result. Throws AppleIDError on cancel/failure.
    func requestSignIn() async throws -> AppleIDCredential {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()

        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
        }
    }

    // MARK: - ASAuthorizationControllerDelegate

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let cred = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = cred.identityToken,
              let token = String(data: tokenData, encoding: .utf8) else {
            continuation?.resume(throwing: AppleIDError.missingIdentityToken)
            continuation = nil
            return
        }

        let result = AppleIDCredential(
            identityToken: token,
            userIdentifier: cred.user,
            email: cred.email,
            fullName: cred.fullName
        )
        continuation?.resume(returning: result)
        continuation = nil
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithError error: Error) {
        let nsErr = error as NSError
        if nsErr.code == ASAuthorizationError.canceled.rawValue {
            continuation?.resume(throwing: AppleIDError.userCancelled)
        } else {
            continuation?.resume(throwing: AppleIDError.authorizationFailed(error.localizedDescription))
        }
        continuation = nil
    }

    // MARK: - ASAuthorizationControllerPresentationContextProviding

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // Locate the active key window across connected scenes. UIApplication's
        // delegate and AppDelegate aren't used in our SwiftUI lifecycle so we
        // rely on UIWindowScene.windows directly.
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
           let window = scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first {
            return window
        }
        return ASPresentationAnchor()
    }
}
