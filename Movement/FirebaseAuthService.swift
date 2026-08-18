// Real authentication backed by Firebase. This entire file compiles to
// nothing until the Firebase (and, for Google, GoogleSignIn) Swift packages
// are added to the target — see FIREBASE_SETUP.md. Once they're linked,
// `AuthBackendFactory.make()` returns `FirebaseAuthBackend` automatically and
// the app authenticates for real.

#if canImport(FirebaseAuth)
import Foundation
import FirebaseAuth
import AuthenticationServices
import CryptoKit
import UIKit
#if canImport(FirebaseCore)
import FirebaseCore
#endif
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

@MainActor
final class FirebaseAuthBackend: NSObject, AuthBackend {
    var isRemote: Bool { true }

    // MARK: - Session

    func currentAccount() -> Account? {
        guard let user = Auth.auth().currentUser else { return nil }
        return Self.account(from: user)
    }

    /// Maps a Firebase user into our lightweight `Account`.
    private static func account(from user: User) -> Account {
        let provider: AuthProvider
        switch user.providerData.first?.providerID {
        case "google.com": provider = .google
        case "apple.com": provider = .apple
        case "phone": provider = .phone
        default: provider = .email
        }
        let contact = user.email ?? user.phoneNumber ?? ""
        let username: String
        if let name = user.displayName, !name.isEmpty {
            username = name
        } else {
            username = contact.isEmpty ? "\(provider.label) member" : contact
        }
        // Never persist a real password on device; the backend owns the session.
        return Account(username: username, contact: contact, contactIsEmail: user.email != nil, password: "", provider: provider, remoteID: user.uid)
    }

    // MARK: - Email / password

    func signUp(contact: String, username: String, password: String) async throws -> Account {
        let cleanContact = contact.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)

        // Firebase email/password auth needs an email. Phone auth is a
        // separate SMS-verification flow, so we steer phone sign-ups to email.
        guard AuthValidator.isEmail(cleanContact) else {
            throw AuthError(message: "Sign up with an email address. (Phone sign-in needs SMS verification, set up separately.)")
        }
        guard cleanUsername.count >= 3 else {
            throw AuthError(message: "Choose a username of at least 3 characters.")
        }
        let problems = AuthValidator.passwordProblems(password)
        guard problems.isEmpty else {
            throw AuthError(message: "Your password needs " + problems.joined(separator: ", ") + ".")
        }

        do {
            let result = try await Auth.auth().createUser(withEmail: cleanContact, password: password)
            let change = result.user.createProfileChangeRequest()
            change.displayName = cleanUsername
            try await change.commitChanges()
            return Account(username: cleanUsername, contact: cleanContact, contactIsEmail: true, password: "", provider: .email)
        } catch {
            throw AuthError(message: error.localizedDescription)
        }
    }

    func logIn(identifier: String, password: String) async throws -> Account {
        let id = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard AuthValidator.isEmail(id) else {
            throw AuthError(message: "Log in with the email address you used to sign up.")
        }
        do {
            let result = try await Auth.auth().signIn(withEmail: id, password: password)
            return Self.account(from: result.user)
        } catch {
            throw AuthError(message: error.localizedDescription)
        }
    }

    // MARK: - Google

    func signInWithGoogle() async throws -> Account {
        #if canImport(GoogleSignIn)
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            throw AuthError(message: "Missing Firebase client ID. Add GoogleService-Info.plist to the app.")
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

        guard let presenter = Self.topViewController() else {
            throw AuthError(message: "Couldn't present Google sign-in.")
        }

        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
            guard let idToken = result.user.idToken?.tokenString else {
                throw AuthError(message: "Google sign-in returned no identity token.")
            }
            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: result.user.accessToken.tokenString
            )
            let authResult = try await Auth.auth().signIn(with: credential)
            return Self.account(from: authResult.user)
        } catch let error as AuthError {
            throw error
        } catch {
            throw AuthError(message: error.localizedDescription)
        }
        #else
        throw AuthError(message: "Add the GoogleSignIn Swift package to enable Google sign-in.")
        #endif
    }

    // MARK: - Apple

    // Requires the "Sign in with Apple" capability on the target (an Apple
    // Developer Program membership). Without it the authorization request
    // fails and we surface that error to the member.
    private var appleContinuation: CheckedContinuation<Account, Error>?
    private var currentNonce: String?

    func signInWithApple() async throws -> Account {
        let nonce = Self.randomNonceString()
        currentNonce = nonce

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)

        return try await withCheckedThrowingContinuation { continuation in
            self.appleContinuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    func signOut() {
        try? Auth.auth().signOut()
        #if canImport(GoogleSignIn)
        GIDSignIn.sharedInstance.signOut()
        #endif
    }

    func sendPasswordReset(contact: String) async throws {
        let email = contact.trimmingCharacters(in: .whitespacesAndNewlines)
        guard AuthValidator.isEmail(email) else {
            throw AuthError(message: "Enter the email address you signed up with.")
        }
        do {
            try await Auth.auth().sendPasswordReset(withEmail: email)
        } catch {
            throw AuthError(message: error.localizedDescription)
        }
    }

    // MARK: - Account deletion

    func deleteAccount(_ account: Account) async throws {
        guard let user = Auth.auth().currentUser else {
            throw AuthError(message: "You're not signed in.")
        }
        do {
            try await user.delete()
        } catch let error as NSError where error.code == AuthErrorCode.requiresRecentLogin.rawValue {
            throw AuthError(message: "For your security, please log out, log back in, then delete your account again.")
        } catch {
            throw AuthError(message: error.localizedDescription)
        }
    }

    // MARK: - Helpers

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
            ?? UIApplication.shared.connectedScenes.first as? UIWindowScene
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }

    fileprivate static func keyWindow() -> UIWindow? {
        let scene = UIApplication.shared.connectedScenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
            ?? UIApplication.shared.connectedScenes.first as? UIWindowScene
        return scene?.keyWindow
    }

    /// A cryptographically random nonce, required so Firebase can verify the
    /// Apple identity token wasn't replayed.
    private static func randomNonceString(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var random: UInt8 = 0
            let status = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
            if status == errSecSuccess {
                if random < UInt8(charset.count) {
                    result.append(charset[Int(random)])
                    remaining -= 1
                }
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        let hashed = SHA256.hash(data: Data(input.utf8))
        return hashed.map { String(format: "%02x", $0) }.joined()
    }
}

extension FirebaseAuthBackend: ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        Self.keyWindow() ?? ASPresentationAnchor()
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let nonce = currentNonce,
              let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8) else {
            appleContinuation?.resume(throwing: AuthError(message: "Apple sign-in didn't return a valid token."))
            appleContinuation = nil
            return
        }

        let firebaseCredential = OAuthProvider.appleCredential(
            withIDToken: idToken,
            rawNonce: nonce,
            fullName: credential.fullName
        )

        let continuation = appleContinuation
        appleContinuation = nil
        Task {
            do {
                let result = try await Auth.auth().signIn(with: firebaseCredential)
                // Apple only sends the name on first sign-up; capture it if present.
                if let full = credential.fullName, full.givenName != nil {
                    let change = result.user.createProfileChangeRequest()
                    change.displayName = [full.givenName, full.familyName].compactMap { $0 }.joined(separator: " ")
                    try? await change.commitChanges()
                }
                continuation?.resume(returning: Self.account(from: result.user))
            } catch {
                continuation?.resume(throwing: AuthError(message: error.localizedDescription))
            }
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        appleContinuation?.resume(throwing: AuthError(message: error.localizedDescription))
        appleContinuation = nil
    }
}
#endif
