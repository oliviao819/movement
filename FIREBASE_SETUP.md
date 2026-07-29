# Turning on real authentication (Firebase)

The app ships with a **local fallback** auth backend (`LocalAuthBackend`) so it
builds and runs with no setup — sign up / log in work offline against
`UserDefaults`, and the Google/Apple buttons start a local demo session.

The **real** backend (`FirebaseAuthBackend`) is already written but only
compiles once the Firebase SDK is linked. It's wrapped in
`#if canImport(FirebaseAuth)`, so the moment you add the packages below,
`AuthBackendFactory.make()` switches the whole app over to Firebase — no code
changes needed.

Everything below is done in **Xcode / the Firebase & Google consoles** — I
can't do these steps for you because they need accounts and credentials.

---

## 1. Create a Firebase project

1. Go to <https://console.firebase.google.com> → **Add project**.
2. Add an **iOS app** with bundle ID **`com.example.movement`**
   (matches `PRODUCT_BUNDLE_IDENTIFIER`; change both if you use your own).
3. Download **`GoogleService-Info.plist`** and drag it into the `Movement/`
   folder in Xcode (it's a synchronized group, so it'll be included
   automatically — just make sure "Copy items if needed" is checked and the
   Movement target is selected).

## 2. Add the Swift packages

In Xcode: **File ▸ Add Package Dependencies…**

- `https://github.com/firebase/firebase-ios-sdk` → add product **FirebaseAuth**
  (and **FirebaseCore** if listed separately).
- `https://github.com/google/GoogleSignIn-iOS` → add product **GoogleSignIn**.

Once these link, `canImport(FirebaseAuth)` becomes true and the real backend
activates.

## 3. Enable sign-in providers (Firebase console ▸ Authentication ▸ Sign-in method)

- **Email/Password** → Enable.
- **Google** → Enable (set a support email).
- **Apple** → Enable (needs the Apple Developer setup in step 5).

## 4. Google sign-in URL scheme

Google needs your app to handle a redirect URL:

1. Open `GoogleService-Info.plist`, copy the **`REVERSED_CLIENT_ID`** value.
2. Xcode ▸ target **Movement** ▸ **Info** ▸ **URL Types** ▸ **+**, paste the
   reversed client ID into **URL Schemes**.

(The app already calls `GIDSignIn.sharedInstance.handle(url)` in
`MovementApp.onOpenURL`, so no code is needed here.)

## 5. Apple sign-in (needs an Apple Developer Program membership)

Apple sign-in stays inert until this is configured:

1. Xcode ▸ target **Movement** ▸ **Signing & Capabilities** ▸ **+ Capability**
   ▸ **Sign in with Apple**. (Requires selecting a Development Team, i.e. a paid
   Apple Developer account.)
2. In the Firebase console, finish the **Apple** provider setup (Services ID +
   key) per Firebase's instructions.

The nonce generation, token exchange, and Firebase credential handoff are
already implemented in `FirebaseAuthService.swift`.

---

## What works after each step

| You've done | Email/Password | Google | Apple |
|---|---|---|---|
| Nothing (as shipped) | ✅ local/offline | demo session | demo session |
| Steps 1–3 | ✅ Firebase | — | — |
| + Step 4 | ✅ Firebase | ✅ Firebase | — |
| + Step 5 | ✅ Firebase | ✅ Firebase | ✅ Firebase |

## Notes

- **Phone numbers:** Firebase email/password auth requires an email. Phone
  sign-in is a separate SMS-verification flow, so the Firebase backend asks
  phone users to sign up with email. The local fallback accepts either.
- The local fallback stores raw passwords in `UserDefaults` — fine for offline
  prototyping, never for production. The Firebase backend never persists a
  password on device.
- To verify the switch happened, check `store.usesRemoteBackend` (true =
  Firebase).
