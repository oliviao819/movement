// Cross-device sync for the member's progress, backed by Firestore. Mirrors
// the AuthBackend/AuthBackendFactory pattern in AuthService.swift: a real
// implementation when the Firestore SDK is linked, a no-op otherwise, so
// MovementStore never needs `#if canImport` checks of its own.

import Foundation
#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

/// The subset of MovementStore's persisted state that's synced to Firestore.
/// Excludes `account`/`isAuthenticated` — identity lives in Firebase Auth
/// itself, and a password (even the empty placeholder the remote backend
/// uses) should never be written to Firestore.
struct SyncedState: Codable, Equatable {
    var profile: Profile?
    var theme: AppTheme
    var aesthetic: AestheticMode
    var appearance: AppearanceMode
    var remindersEnabled: Bool
    var lenientStreaks: Bool
    var weekStartKey: String
    var weeklyCompletionsByDay: [String: [String]]
    var completionDates: [String]
    var completionLog: [CompletionRecord]
}

protocol SyncBackend {
    /// The member's saved state from a prior session on another device, or
    /// nil if they've never synced before (first login after sign up, or a
    /// device that only ever had local data).
    func fetchState(uid: String) async throws -> SyncedState?
    func saveState(_ state: SyncedState, uid: String) async throws
    func deleteState(uid: String) async throws
}

enum SyncBackendFactory {
    static func make() -> SyncBackend {
        #if canImport(FirebaseFirestore)
        return FirestoreSyncBackend()
        #else
        return NoopSyncBackend()
        #endif
    }
}

/// Used for the local auth fallback, or if Firestore isn't linked yet —
/// progress simply stays device-only, same as before this file existed.
struct NoopSyncBackend: SyncBackend {
    func fetchState(uid: String) async throws -> SyncedState? { nil }
    func saveState(_ state: SyncedState, uid: String) async throws {}
    func deleteState(uid: String) async throws {}
}

#if canImport(FirebaseFirestore)
struct FirestoreSyncBackend: SyncBackend {
    private let collection = "users"

    func fetchState(uid: String) async throws -> SyncedState? {
        let snapshot = try await Firestore.firestore().collection(collection).document(uid).getDocument()
        guard snapshot.exists, let data = snapshot.data() else { return nil }
        return try Firestore.Decoder().decode(SyncedState.self, from: data)
    }

    func saveState(_ state: SyncedState, uid: String) async throws {
        let data = try Firestore.Encoder().encode(state)
        try await Firestore.firestore().collection(collection).document(uid).setData(data)
    }

    func deleteState(uid: String) async throws {
        try await Firestore.firestore().collection(collection).document(uid).delete()
    }
}
#endif
