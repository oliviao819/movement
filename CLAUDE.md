# Movement — App Overview

Movement is a native iOS fitness/workout app built with SwiftUI. It personalizes a stretching/strength workout library to each member's stated goals and experience level, tracks daily completions, and visualizes consistency (streaks, weekly completion, a running "days tracking" count). It has no social features, no paid tiers, and no server-driven content — it's a personal habit-tracking and workout-reference tool.

## Tech stack

- **Platform:** iOS, native SwiftUI (no UIKit screens, no third-party UI frameworks)
- **Language:** Swift
- **Persistence (local):** `UserDefaults` (JSON-encoded state blobs) — the whole app works fully offline on-device with no backend at all
- **Backend (optional, additive):** Firebase — Firebase Auth (email/password, Google, Apple) and Firestore (cross-device sync of profile/settings/history). The app is written so it **builds and runs with zero backend** and upgrades automatically once the Firebase Swift packages are linked (see "Backend is optional" below)
- **Notifications:** local `UNUserNotificationCenter` reminder only — no push notifications, no server component
- **Project file:** `Movement.xcodeproj`, single app target named `Movement`

## Repo layout

```
Movement/
  MovementApp.swift            App entry point; configures Firebase if linked
  Models.swift                 All data models, enums, theming/color math
  MovementStore.swift          The single @MainActor ObservableObject that owns all app state
  AuthService.swift            AuthBackend protocol + LocalAuthBackend (offline fallback)
  FirebaseAuthService.swift    FirebaseAuthBackend (real auth) — compiles to nothing until Firebase is linked
  FirestoreSyncService.swift   SyncBackend protocol + Firestore/no-op implementations (cross-device sync)
  NotificationService.swift    Daily local reminder notification scheduling
  WorkoutLibrary.swift         Static catalog of all categories/subcategories/workouts
  WorkoutPlanEngine.swift      Turns a workout + profile into a sets/reps/note prescription
  Views.swift                  All SwiftUI screens (single file, ~1800 lines)
firestore.rules                Firestore security rules (per-user document isolation)
firebase.json                 Firebase CLI config (points at firestore.rules)
FIREBASE_SETUP.md              Steps to link Firebase and enable providers
APP_STORE_CHECKLIST.md         Remaining manual steps before App Store submission
PRIVACY_POLICY.md              Privacy policy template
```

## Core concept: the "backend is optional" pattern

This is the most important architectural idea in the codebase. Two protocols abstract away *where* data lives, and the app has a fully working implementation on both sides of that abstraction:

- **`AuthBackend`** (`AuthService.swift`) — `LocalAuthBackend` (stores accounts in `UserDefaults`, plaintext password, no real OAuth) vs. `FirebaseAuthBackend` (`FirebaseAuthService.swift`, real Firebase Auth + Google/Apple OAuth). `AuthBackendFactory.make()` picks whichever is available at compile time via `#if canImport(FirebaseAuth)`.
- **`SyncBackend`** (`FirestoreSyncService.swift`) — `NoopSyncBackend` (progress stays device-only) vs. `FirestoreSyncBackend` (reads/writes one document per user at `users/{uid}` in Firestore). Picked the same way via `#if canImport(FirebaseFirestore)`.

Practical implication: **the app is fully functional today without any Firebase project configured** — sign-up/login work locally, Google/Apple buttons start a stub local session, and progress just doesn't sync across devices. Adding the Firebase Swift packages to the Xcode project flips both backends over to the real implementations with no other code changes required. See `FIREBASE_SETUP.md` for exact linking steps and `APP_STORE_CHECKLIST.md` for what's still manual (enabling providers, deploying `firestore.rules`, Apple Developer capability, hosting the privacy policy, etc.).

Firestore data model: one document per user at `users/{uid}`, containing `SyncedState` (profile, theme, aesthetic, appearance, reminders/streak settings, weekly completions, completion dates, full completion log). Security rules restrict each document to its own signed-in owner only. Auth identity (uid, email) is never duplicated into Firestore — only app state.

## State management

`MovementStore` (`MovementStore.swift`) is the single source of truth — a `@MainActor` `ObservableObject` injected into the SwiftUI environment from `MovementApp`. It owns:

- **Session:** current `Account?`, `isAuthenticated`
- **Profile:** the member's `Profile?` (nil until onboarding quiz is completed)
- **Appearance/theming:** `theme` (color vibe), `aesthetic` (visual personality), `appearance` (light/dark/system)
- **Settings:** `remindersEnabled`, `lenientStreaks`
- **Progress:** `weeklyCompletionsByDay`, `completionDates`, `completionLog` (full history), `weekStartKey`

It persists everything to `UserDefaults` as one JSON blob (`SavedState`, with careful backward-compatible decoding for old key names/migrations), and — when signed in against the real Firebase backend — mirrors every save to Firestore in the background (best-effort; failures don't block or roll back the local save). On login, if a remote document already exists it wins and overwrites local state (so a returning member on a new device picks up their real progress); otherwise the local state is pushed up as the starting point.

## Onboarding & auth flow

1. **Welcome screen** → **first-time quiz is gated behind auth**: the member must sign up or log in *before* personalizing, so progress can be tied to an account from the start.
2. **Auth options:** email/phone + username + password, or one-tap Google/Sign in with Apple.
   - Signup validation (`AuthValidator` in `Models.swift`, shared by both backends): contact must look like an email (has `@` and a dot after it) or a phone number (≥7 digits); username ≥3 characters; password needs ≥8 characters, at least one letter, and at least one special character.
   - "Forgot password" sends a real reset email (Firebase backend only — throws a friendly error on the local fallback).
   - Account deletion is supported end-to-end (required by App Store Guideline 5.1.1(v) for any app with account creation) — deletes the Firestore document, then the auth account, then resets local onboarding.
3. **Onboarding quiz** collects a `Profile`: name, birthday, gender, one or more `Goal`s (Strength / Tone / Energy / Flexibility / Consistency / Confidence), and `Experience` level (Beginner / Some experience / Consistent / Advanced).
4. Completing the quiz (`profile != nil`) unlocks the main app (`MovementStore.hasCompletedOnboarding`).

## Workout content & personalization

- **`WorkoutLibrary`** is a static, hardcoded catalog: 4 top-level categories (Arms, Legs, Upper Body, Full Body), each with subcategories (e.g. Arms → Forearms/Biceps/Triceps; Legs → Quads/Calves/Hamstrings; Upper Body → Chest/Back/Abs; Full Body → Conditioning/Mobility), each with 2 individual workouts. Every `Workout` has a name, materials needed, difficulty label, a plain-English explanation, a one-line form cue, and a `WorkoutPose` enum used to drive an illustrated stick-figure demonstration.
- **`WorkoutPlanEngine.prescription(for:profile:)`** is the personalization logic: it derives sets/reps/coaching note from the member's **primary goal** (first goal picked) and adjusts by **experience level** (beginners get fewer sets and easier reps/durations; advanced members get more sets and harder reps/durations). Plank/hold-type poses always get a duration-based rep scheme regardless of goal. This function is pure (no side effects) and is called both when displaying a workout and when logging a completion.
- Each workout detail screen includes: a SwiftUI-drawn 360°-ish pose demonstration (`Demonstration360View` / `PoseFigure`), the explanation, materials, difficulty, and the quiz-derived sets/reps.
- **Completion is only ever recorded from the workout detail screen** (`MovementStore.complete(_:on:)`), which marks the workout done for the day and appends a `CompletionRecord` snapshotting the sets/reps *as prescribed at that moment* (so history stays accurate even if the member's goals/experience change later and the prescription would now compute differently).

## Progress tracking & streaks

- **Weekly view:** completions are bucketed per calendar day (`weeklyCompletionsByDay`); the week resets automatically when a new week starts (`rollWeekIfNeeded`), using the calendar's week-of-year boundary.
- **Rolling streak:** `streakSnapshot()` looks back up to 120 days from today, counting consecutive completion, with an optional "grace" allowance (`lenientStreaks`, default on) of up to 2 missed days before the streak is considered broken/reset. Surfaces completed days, missed days, remaining grace, and whether the streak just reset.
- **"Days tracking":** `daysTracking()` counts whole days from the very first ever logged completion (`trackingStartDate`) through today — a lifetime consistency metric independent of streak grace.
- **Progress tab:** full completion history (most recent first), a goal summary card, streak visualization, and a week-at-a-glance view.

## Visual design system

`Models.swift` implements a from-scratch color/theming engine (no external color libraries):

- **`AppTheme`** (color "vibe", persisted): Sage/white/gold, Soft rose, Clean ocean, Charcoal/gold. Each defines primary/strong/gold accent hues.
- **`AestheticMode`** (visual personality, persisted): Calming motivation (pastel, serif headline, gentle saturation), High-energy coaching (punchy/neon saturation, heavy rounded font), Quiet focus (minimal/no decorative chrome, plain font, lowest saturation) — this changes saturation/brightness multipliers, background tint strength, and font design/weight app-wide.
- **`AppearanceMode`**: System / Light / Dark, resolved against the device's actual color scheme.
- `theme.palette(isDark:aesthetic:)` combines all three into a final `Palette` (background/surface/soft/ink/muted/primary/strong/gold) via HSB adjustments and neutral-color mixing, guaranteeing readable contrast in both light and dark mode regardless of which vibe/aesthetic is active.

## Screens (`Views.swift`)

`RootView` switches between `WelcomeFlowView` (welcome → auth → onboarding, shown until `hasCompletedOnboarding`) and `MainAppView` (the signed-in, onboarded app shell with a `NavigationStack` and a side menu).

Key screens: `WelcomeView`, `AuthView` (sign up/log in/social/reset), `OnboardingView` (quiz), `DashboardView` (home — motivational quote, `AestheticSpotlightView`, `TodayFocusView`, `WeekCompletionView`, `RollingStreakView`), `SideMenuView` (navigation to categories), `CategoryView` → `SubcategoryView` → `WorkoutDetailView` (with `Demonstration360View`/`PoseFigure`), `ProgressDetailView` (+ `ProgressGoalCard`, `ProgressStreakView`, `ProgressWeekView`), and `SettingsView` (theme/aesthetic/appearance pickers, reminders toggle, lenient streaks toggle, sign out, delete account).

## Privacy & data handling

Per `PRIVACY_POLICY.md` / `Movement/PrivacyInfo.xcprivacy`: the app collects email/name (for account identity) and fitness/workout data (goals, completions), linked to the member's identity, used only for app functionality — **not used for tracking or advertising**, and not shared with third parties beyond the Firebase infrastructure the member's own data lives in.

## Current known state / gaps (see `APP_STORE_CHECKLIST.md`)

- Code is complete for auth, Firestore sync, local reminders, and the privacy manifest — remaining work is account/console configuration, not code: enabling Firebase Auth providers, deploying `firestore.rules`, adding the paid-developer-account-gated "Sign in with Apple" capability, hosting the privacy policy at a public URL, and a full Xcode build/simulator verification pass (this environment has only Command Line Tools, so Firebase-dependent code hasn't been build-verified in Xcode itself, only type-checked with the Swift compiler).
- The local (non-Firebase) auth fallback intentionally stores passwords in plaintext in `UserDefaults` — acceptable only because it's a stand-in until Firebase is linked, never intended as the production auth path.
