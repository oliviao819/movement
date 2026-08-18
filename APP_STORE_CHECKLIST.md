# App Store readiness checklist

Code-side work for auth completion, Firestore sync, local reminders, and the
privacy manifest is done (see `firestore.rules`, `Movement/PrivacyInfo.xcprivacy`,
`Movement/FirestoreSyncService.swift`, `Movement/NotificationService.swift`).
Everything below needs your Firebase/Apple Developer/App Store Connect
accounts, which can't be done from here.

## Firebase console

- [ ] Finish linking the Firebase SDK per `FIREBASE_SETUP.md` if you haven't
      (packages are already declared in the Xcode project; this is mostly
      about enabling providers and adding `GoogleService-Info.plist`).
- [ ] Enable **Firestore** (Build → Firestore Database → Create database).
- [ ] Deploy `firestore.rules`: install the Firebase CLI (`npm install -g
      firebase-tools`), `firebase login`, `firebase use <your-project-id>`,
      then `firebase deploy --only firestore:rules` from the repo root
      (`firebase.json` is already set up to point at the rules file). You can
      also just paste the contents of `firestore.rules` into Firebase console
      → Firestore → Rules.
- [ ] Double check the "Email/Password", "Google", and "Apple" providers are
      enabled per `FIREBASE_SETUP.md` — password reset only works once
      Email/Password is on.

## Apple Developer / Xcode

- [ ] Add the "Sign in with Apple" capability (needs a paid Apple Developer
      Program membership) — required if Apple sign-in stays offered.
- [ ] Build once in full Xcode to confirm everything links — this environment
      only has Command Line Tools, so the Firestore/Firebase-dependent code
      added here hasn't been build-verified.
- [ ] (Optional, later) Add FirebaseAnalytics and/or FirebaseCrashlytics via
      Xcode's **File → Add Package Dependencies** on the already-added
      `firebase-ios-sdk` package — pick the additional products, then (for
      Crashlytics) add its **Run Script** build phase per Firebase's docs so
      dSYMs upload for symbolicated crash reports.

## Privacy / App Store Connect

- [ ] Fill in the date and contact email in `PRIVACY_POLICY.md`, then host it
      somewhere with a stable URL (e.g. GitHub Pages).
- [ ] In App Store Connect → App Privacy, fill in the "nutrition label"
      answers to match `PRIVACY_POLICY.md` and `Movement/PrivacyInfo.xcprivacy`
      (email, name, and fitness/workout data — linked to identity, used for
      app functionality, not used for tracking).
- [ ] Add the hosted privacy policy URL in App Store Connect's app
      information.
- [ ] Double-check `Movement/PrivacyInfo.xcprivacy`'s `CA92.1` reason code
      against Apple's current required-reason API list at submission time —
      Apple occasionally revises the approved reason codes.

## Testing

- [ ] Sign up, log out, log back in on a second simulator/device and confirm
      progress (profile, completions, streak) actually shows up — this
      exercises the new Firestore sync path end-to-end.
- [ ] Test Delete Account end-to-end and confirm the Firestore document is
      gone (Firebase console → Firestore → `users/<uid>`).
- [ ] Test "Forgot password?" and confirm the reset email arrives.
- [ ] Turn on reminders and confirm a local notification fires (easiest to
      test by temporarily changing the hour in
      `NotificationScheduler.scheduleDailyReminder()` to a few minutes out).
- [ ] Run through TestFlight before public submission.
