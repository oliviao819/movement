import SwiftUI
#if canImport(FirebaseCore)
import FirebaseCore
#endif
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

@main
struct MovementApp: App {
    @StateObject private var store = MovementStore()

    init() {
        // Configures Firebase at launch when its SDK is linked (and a
        // GoogleService-Info.plist is present). No-op otherwise, so the app
        // still runs on the local auth fallback.
        #if canImport(FirebaseCore)
        FirebaseApp.configure()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
            #if canImport(GoogleSignIn)
                // Completes the Google sign-in redirect back into the app.
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
            #endif
        }
    }
}
