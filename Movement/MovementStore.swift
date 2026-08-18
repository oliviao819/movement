import Foundation
import SwiftUI

@MainActor
final class MovementStore: ObservableObject {
    @Published var profile: Profile?
    /// The stored account, if the member has ever signed up / logged in.
    @Published private(set) var account: Account?
    /// Whether there's an active session. Gated ahead of the quiz so the
    /// member logs in or signs up before personalizing.
    @Published private(set) var isAuthenticated = false
    @Published var theme: AppTheme = .sage
    @Published var aesthetic: AestheticMode = .calm
    @Published var appearance: AppearanceMode = .system
    @Published var remindersEnabled = true
    @Published var lenientStreaks = true
    @Published private(set) var weekStartKey = ""
    @Published private(set) var weeklyCompletionsByDay: [String: [String]] = [:]
    @Published private(set) var completionDates: Set<String> = []
    /// Full history of every completed workout, oldest first. Backs the
    /// Progress tab and the "how long you've been moving" tracking.
    @Published private(set) var completionLog: [CompletionRecord] = []

    private let storageKey = "movement-ios-state"
    private let calendar = Calendar.current

    /// Where authentication actually happens — Firebase when its SDK is
    /// linked, otherwise the offline local fallback (see AuthService.swift).
    private let authBackend: AuthBackend = AuthBackendFactory.make()

    /// Whether the app is talking to a real remote backend (Firebase) rather
    /// than the local fallback. Surfaced so the UI can note the mode.
    var usesRemoteBackend: Bool { authBackend.isRemote }

    init() {
        load()
        rollWeekIfNeeded()

        // A remote backend owns its own session persistence, so let it decide
        // whether we're logged in rather than trusting our saved flag (which
        // could be stale if the session was revoked on the server).
        if authBackend.isRemote {
            if let remote = authBackend.currentAccount() {
                account = remote
                isAuthenticated = true
            } else {
                isAuthenticated = false
            }
        }
    }

    var hasCompletedOnboarding: Bool {
        profile != nil
    }

    // MARK: - Authentication

    /// Signs up with an email/phone + username + password via the active
    /// backend. Returns an error message to show the member, or nil on success
    /// (in which case the session is now active).
    func signUp(contact: String, username: String, password: String) async -> String? {
        await run { try await self.authBackend.signUp(contact: contact, username: username, password: password) }
    }

    /// Logs in with an email/phone/username + password. Returns an error
    /// message, or nil on success.
    func logIn(identifier: String, password: String) async -> String? {
        await run { try await self.authBackend.logIn(identifier: identifier, password: password) }
    }

    /// Google sign in (real OAuth via Firebase once its SDK is linked; a local
    /// demo session otherwise).
    func signInWithGoogle() async -> String? {
        await run { try await self.authBackend.signInWithGoogle() }
    }

    /// Apple sign in (real via Firebase + the "Sign in with Apple" capability
    /// once configured; a local demo session otherwise).
    func signInWithApple() async -> String? {
        await run { try await self.authBackend.signInWithApple() }
    }

    /// Ends the session (the backend keeps the account so the member can log
    /// back in) and returns to the sign in screen.
    func signOut() {
        authBackend.signOut()
        isAuthenticated = false
        save()
    }

    /// Runs an auth action, storing the resulting account and activating the
    /// session on success, or returning the error's message on failure.
    private func run(_ action: () async throws -> Account) async -> String? {
        do {
            let account = try await action()
            self.account = account
            isAuthenticated = true
            save()
            return nil
        } catch let error as AuthError {
            return error.message
        } catch {
            return error.localizedDescription
        }
    }

    func saveProfile(_ profile: Profile) {
        self.profile = profile
        save()
    }

    func resetOnboarding() {
        profile = nil
        weeklyCompletionsByDay = [:]
        completionDates = []
        completionLog = []
        weekStartKey = currentWeekStartKey()
        save()
    }

    func setTheme(_ theme: AppTheme) {
        self.theme = theme
        save()
    }

    func setAesthetic(_ aesthetic: AestheticMode) {
        self.aesthetic = aesthetic
        save()
    }

    func setAppearance(_ appearance: AppearanceMode) {
        self.appearance = appearance
        save()
    }

    /// Whether the app should currently render in dark mode: an explicit
    /// user choice wins, otherwise it follows the device's own appearance.
    func resolvedIsDark(system: ColorScheme) -> Bool {
        switch appearance {
        case .light: return false
        case .dark: return true
        case .system: return system == .dark
        }
    }

    /// The forced color scheme to apply at the root of the app so that
    /// default system text/controls (which don't use our custom palette)
    /// stay legible against whichever background we're drawing.
    var preferredColorScheme: ColorScheme? {
        switch appearance {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// Resolves the full palette for the current theme (color vibe),
    /// aesthetic (calm/bright/minimal), and light/dark appearance.
    func palette(system: ColorScheme) -> Palette {
        theme.palette(isDark: resolvedIsDark(system: system), aesthetic: aesthetic)
    }

    func setReminders(_ enabled: Bool) {
        remindersEnabled = enabled
        save()
    }

    func setLenientStreaks(_ enabled: Bool) {
        lenientStreaks = enabled
        save()
    }

    func complete(_ workout: Workout, on date: Date = Date()) {
        rollWeekIfNeeded(date: date)
        let dayKey = key(for: date)
        let alreadyDoneToday = weeklyCompletionsByDay[dayKey, default: []].contains(workout.id)
        var workouts = Set(weeklyCompletionsByDay[dayKey, default: []])
        workouts.insert(workout.id)
        weeklyCompletionsByDay[dayKey] = Array(workouts).sorted()
        completionDates.insert(dayKey)

        // Log the completion (with the sets/reps in effect right now) unless
        // this workout was already logged today, so the Progress history has
        // one entry per completion rather than duplicates from re-taps.
        if !alreadyDoneToday {
            let prescription = WorkoutPlanEngine.prescription(for: workout, profile: profile)
            completionLog.append(
                CompletionRecord(id: UUID(), workoutID: workout.id, workoutName: workout.name, sets: prescription.sets, reps: prescription.reps, date: date)
            )
        }
        save()
    }

    /// Completed workouts, most recent first, for the Progress tab.
    func completionHistory() -> [CompletionRecord] {
        completionLog.sorted { $0.date > $1.date }
    }

    /// The first day the member ever logged a workout — the anchor for "how
    /// long you've been moving." Nil until the first completion.
    var trackingStartDate: Date? {
        completionLog.map(\.date).min()
    }

    /// Whole days (inclusive) from the first logged workout through today,
    /// used to show how long the member has been at it.
    func daysTracking(today: Date = Date()) -> Int {
        guard let start = trackingStartDate else { return 0 }
        let startDay = calendar.startOfDay(for: start)
        let todayDay = calendar.startOfDay(for: today)
        let days = calendar.dateComponents([.day], from: startDay, to: todayDay).day ?? 0
        return max(0, days) + 1
    }

    func isCompletedToday(_ workout: Workout) -> Bool {
        let dayKey = key(for: Date())
        return weeklyCompletionsByDay[dayKey, default: []].contains(workout.id)
    }

    func completedWorkouts(on date: Date) -> Int {
        weeklyCompletionsByDay[key(for: date), default: []].count
    }

    func weekDays() -> [Date] {
        let start = startOfWeek(for: Date())
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    func weekCompletionCount() -> Int {
        weekDays().filter { completionDates.contains(key(for: $0)) }.count
    }

    func streakSnapshot(today: Date = Date()) -> StreakSnapshot {
        let allowance = lenientStreaks ? 2 : 0
        var span = 0
        var completed = 0
        var missed = 0

        for offset in 0..<120 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let didComplete = completionDates.contains(key(for: day))
            if didComplete {
                completed += 1
            } else {
                missed += 1
                if missed > allowance {
                    return StreakSnapshot(rollingSpan: span, completedDays: completed, missedDays: missed - 1, graceRemaining: 0, didReset: completed == 0)
                }
            }
            span += 1
        }

        return StreakSnapshot(rollingSpan: span, completedDays: completed, missedDays: missed, graceRemaining: max(0, allowance - missed), didReset: false)
    }

    func rollingDays(count: Int = 14) -> [Date] {
        (0..<count).compactMap { offset in
            calendar.date(byAdding: .day, value: offset - count + 1, to: Date())
        }
    }

    func didComplete(on date: Date) -> Bool {
        completionDates.contains(key(for: date))
    }

    func key(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    func shortWeekday(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        return formatter.string(from: date)
    }

    private func rollWeekIfNeeded(date: Date = Date()) {
        let activeWeek = currentWeekStartKey(date: date)
        if weekStartKey.isEmpty {
            weekStartKey = activeWeek
            save()
            return
        }

        if weekStartKey != activeWeek {
            weeklyCompletionsByDay = [:]
            weekStartKey = activeWeek
            save()
        }
    }

    private func currentWeekStartKey(date: Date = Date()) -> String {
        key(for: startOfWeek(for: date))
    }

    private func startOfWeek(for date: Date) -> Date {
        let interval = calendar.dateInterval(of: .weekOfYear, for: date)
        return interval?.start ?? calendar.startOfDay(for: date)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode(SavedState.self, from: data) else {
            weekStartKey = currentWeekStartKey()
            return
        }

        profile = saved.profile
        account = saved.account
        isAuthenticated = saved.isAuthenticated
        theme = saved.theme
        aesthetic = saved.aesthetic
        appearance = saved.appearance
        remindersEnabled = saved.remindersEnabled
        lenientStreaks = saved.lenientStreaks
        weekStartKey = saved.weekStartKey
        weeklyCompletionsByDay = saved.weeklyCompletionsByDay
        completionDates = Set(saved.completionDates)
        completionLog = saved.completionLog
    }

    private func save() {
        let saved = SavedState(profile: profile, account: account, isAuthenticated: isAuthenticated, theme: theme, aesthetic: aesthetic, appearance: appearance, remindersEnabled: remindersEnabled, lenientStreaks: lenientStreaks, weekStartKey: weekStartKey, weeklyCompletionsByDay: weeklyCompletionsByDay, completionDates: Array(completionDates), completionLog: completionLog)
        guard let data = try? JSONEncoder().encode(saved) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

private struct SavedState: Codable {
    var profile: Profile?
    var account: Account?
    var isAuthenticated: Bool
    var theme: AppTheme
    var aesthetic: AestheticMode
    var appearance: AppearanceMode
    var remindersEnabled: Bool
    var lenientStreaks: Bool
    var weekStartKey: String
    var weeklyCompletionsByDay: [String: [String]]
    var completionDates: [String]
    var completionLog: [CompletionRecord]

    // Custom coding keys keep old saved data (which stored the aesthetic
    // under the previous "energy" key, and had no "appearance" key at all)
    // loading correctly instead of resetting the user's whole profile.
    private enum CodingKeys: String, CodingKey {
        case profile, account, isAuthenticated, theme, aesthetic, energy, appearance, remindersEnabled, lenientStreaks, weekStartKey, weeklyCompletionsByDay, completionDates, completionLog
    }

    init(profile: Profile?, account: Account?, isAuthenticated: Bool, theme: AppTheme, aesthetic: AestheticMode, appearance: AppearanceMode, remindersEnabled: Bool, lenientStreaks: Bool, weekStartKey: String, weeklyCompletionsByDay: [String: [String]], completionDates: [String], completionLog: [CompletionRecord]) {
        self.profile = profile
        self.account = account
        self.isAuthenticated = isAuthenticated
        self.theme = theme
        self.aesthetic = aesthetic
        self.appearance = appearance
        self.remindersEnabled = remindersEnabled
        self.lenientStreaks = lenientStreaks
        self.weekStartKey = weekStartKey
        self.weeklyCompletionsByDay = weeklyCompletionsByDay
        self.completionDates = completionDates
        self.completionLog = completionLog
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        profile = try container.decodeIfPresent(Profile.self, forKey: .profile)
        // Older saved data predates accounts; default to signed-out with no
        // account rather than failing the decode (which would wipe the profile).
        account = try container.decodeIfPresent(Account.self, forKey: .account)
        isAuthenticated = try container.decodeIfPresent(Bool.self, forKey: .isAuthenticated) ?? false
        if let themeValue = try? container.decodeIfPresent(AppTheme.self, forKey: .theme) {
            theme = themeValue
        } else if let legacyRaw = try? container.decode(String.self, forKey: .theme), legacyRaw == "Evening focus" {
            theme = .charcoal
        } else {
            theme = .sage
        }
        if let aestheticValue = try container.decodeIfPresent(AestheticMode.self, forKey: .aesthetic) {
            aesthetic = aestheticValue
        } else {
            aesthetic = try container.decodeIfPresent(AestheticMode.self, forKey: .energy) ?? .calm
        }
        appearance = try container.decodeIfPresent(AppearanceMode.self, forKey: .appearance) ?? .system
        remindersEnabled = try container.decode(Bool.self, forKey: .remindersEnabled)
        lenientStreaks = try container.decode(Bool.self, forKey: .lenientStreaks)
        weekStartKey = try container.decode(String.self, forKey: .weekStartKey)
        weeklyCompletionsByDay = try container.decode([String: [String]].self, forKey: .weeklyCompletionsByDay)
        completionDates = try container.decode([String].self, forKey: .completionDates)
        // Older saved data has no completion log; default to empty rather
        // than failing the whole decode (which would wipe the profile).
        completionLog = try container.decodeIfPresent([CompletionRecord].self, forKey: .completionLog) ?? []
    }

    // Written explicitly because CodingKeys has an extra "energy" case (for
    // reading old data) with no matching stored property, which blocks
    // automatic Encodable synthesis.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(profile, forKey: .profile)
        try container.encodeIfPresent(account, forKey: .account)
        try container.encode(isAuthenticated, forKey: .isAuthenticated)
        try container.encode(theme, forKey: .theme)
        try container.encode(aesthetic, forKey: .aesthetic)
        try container.encode(appearance, forKey: .appearance)
        try container.encode(remindersEnabled, forKey: .remindersEnabled)
        try container.encode(lenientStreaks, forKey: .lenientStreaks)
        try container.encode(weekStartKey, forKey: .weekStartKey)
        try container.encode(weeklyCompletionsByDay, forKey: .weeklyCompletionsByDay)
        try container.encode(completionDates, forKey: .completionDates)
        try container.encode(completionLog, forKey: .completionLog)
    }
}
