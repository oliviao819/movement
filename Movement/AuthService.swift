import Foundation

/// An authentication error carrying a message that's safe to show the member.
struct AuthError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Abstracts *where* authentication happens so the rest of the app doesn't
/// care whether it's talking to Firebase or the offline local fallback.
///
/// The real implementation (`FirebaseAuthBackend`) only compiles when the
/// Firebase SDK is linked (see `FirebaseAuthService.swift`). Until then
/// `AuthBackendFactory` returns `LocalAuthBackend`, so the app still builds
/// and runs — it just authenticates against `UserDefaults` instead of a
/// server. Adding the Firebase Swift packages flips the whole app over to the
/// real backend with no other code changes.
@MainActor
protocol AuthBackend {
    /// True for a real remote backend (Firebase); false for the local fallback.
    /// The UI uses this to decide, e.g., whether to trust the backend's own
    /// session persistence on launch.
    var isRemote: Bool { get }

    /// The account for the currently live session, if any. Remote backends
    /// answer from their own persisted session (e.g. `Auth.auth().currentUser`);
    /// the local fallback returns nil and lets the store use its saved flag.
    func currentAccount() -> Account?

    func signUp(contact: String, username: String, password: String) async throws -> Account
    func logIn(identifier: String, password: String) async throws -> Account
    func signInWithGoogle() async throws -> Account
    func signInWithApple() async throws -> Account
    func signOut()

    /// Sends a password reset email to `contact`. Throws if the backend can't
    /// do this offline (the local fallback) or the send fails.
    func sendPasswordReset(contact: String) async throws

    /// Permanently deletes `account` from the backend. Apple requires that
    /// any app with account creation also offer in-app account deletion
    /// (App Review Guideline 5.1.1(v)).
    func deleteAccount(_ account: Account) async throws
}

/// Picks the real backend when Firebase is linked, otherwise the local one.
enum AuthBackendFactory {
    @MainActor
    static func make() -> AuthBackend {
        #if canImport(FirebaseAuth)
        return FirebaseAuthBackend()
        #else
        return LocalAuthBackend()
        #endif
    }
}

/// Offline authentication backed by `UserDefaults`. Real enough to exercise
/// the whole sign up / log in flow without a network, but NOT secure — it
/// stores raw passwords locally. It's only the fallback used before the
/// Firebase SDK is added. Google/Apple here just start a local demo session,
/// since there's no OAuth without the real backend.
@MainActor
final class LocalAuthBackend: AuthBackend {
    var isRemote: Bool { false }

    private let storageKey = "movement-local-credentials"
    private struct Store: Codable { var accounts: [Account] }

    private func loadAccounts() -> [Account] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let store = try? JSONDecoder().decode(Store.self, from: data) else { return [] }
        return store.accounts
    }

    private func persist(_ accounts: [Account]) {
        guard let data = try? JSONEncoder().encode(Store(accounts: accounts)) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    func currentAccount() -> Account? { nil }

    func signUp(contact: String, username: String, password: String) async throws -> Account {
        let cleanContact = contact.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)

        guard AuthValidator.isValidContact(cleanContact) else {
            throw AuthError(message: "Enter a valid email address or phone number.")
        }
        guard cleanUsername.count >= 3 else {
            throw AuthError(message: "Choose a username of at least 3 characters.")
        }
        let problems = AuthValidator.passwordProblems(password)
        guard problems.isEmpty else {
            throw AuthError(message: "Your password needs " + problems.joined(separator: ", ") + ".")
        }

        var accounts = loadAccounts()
        let contactExists = accounts.contains { $0.contact.lowercased() == cleanContact.lowercased() }
        let usernameExists = accounts.contains { $0.username.lowercased() == cleanUsername.lowercased() }
        guard !contactExists, !usernameExists else {
            throw AuthError(message: "An account with that email/phone or username already exists.")
        }

        let isEmail = AuthValidator.isEmail(cleanContact)
        let account = Account(
            username: cleanUsername,
            contact: cleanContact,
            contactIsEmail: isEmail,
            password: password,
            provider: isEmail ? .email : .phone
        )
        accounts.append(account)
        persist(accounts)
        return account
    }

    func logIn(identifier: String, password: String) async throws -> Account {
        let id = identifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let accounts = loadAccounts()
        guard let match = accounts.first(where: { $0.contact.lowercased() == id || $0.username.lowercased() == id }) else {
            throw AuthError(message: "We couldn't find an account for that email, phone, or username.")
        }
        guard match.password == password else {
            throw AuthError(message: "That password doesn't match. Please try again.")
        }
        return match
    }

    func signInWithGoogle() async throws -> Account {
        // No OAuth without Firebase — start a local demo session.
        Account(username: "Google member", contact: "", contactIsEmail: false, password: "", provider: .google)
    }

    func signInWithApple() async throws -> Account {
        Account(username: "Apple member", contact: "", contactIsEmail: false, password: "", provider: .apple)
    }

    func signOut() {}

    func sendPasswordReset(contact: String) async throws {
        throw AuthError(message: "Password reset needs the real backend — see FIREBASE_SETUP.md.")
    }

    func deleteAccount(_ account: Account) async throws {
        var accounts = loadAccounts()
        accounts.removeAll { $0.contact.lowercased() == account.contact.lowercased() && $0.username.lowercased() == account.username.lowercased() }
        persist(accounts)
    }
}
