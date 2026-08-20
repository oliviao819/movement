import Foundation
import SwiftUI

enum Gender: String, CaseIterable, Codable, Identifiable {
    case woman = "Woman"
    case man = "Man"
    case nonBinary = "Non-binary"
    case preferNot = "Prefer not to say"
    case selfDescribe = "Self-describe"

    var id: String { rawValue }
}

enum Goal: String, CaseIterable, Codable, Identifiable {
    case strength = "Strength"
    case tone = "Tone"
    case energy = "Energy"
    case flexibility = "Flexibility"
    case consistency = "Consistency"
    case confidence = "Confidence"

    var id: String { rawValue }
}

enum Experience: String, CaseIterable, Codable, Identifiable {
    case beginner = "Beginner"
    case some = "Some experience"
    case consistent = "Consistent"
    case advanced = "Advanced"

    var id: String { rawValue }
}

enum AppTheme: String, CaseIterable, Codable, Identifiable {
    case sage = "Sage, white, gold"
    case rose = "Soft rose"
    case ocean = "Clean ocean"
    case charcoal = "Charcoal, gold"

    var id: String { rawValue }

    /// The signature accent hues for this color vibe. Neutrals (background,
    /// surface, ink, muted) are derived separately from the light/dark
    /// appearance setting so every vibe works well in both modes.
    fileprivate var hue: ThemeHue {
        switch self {
        case .sage:
            return ThemeHue(primary: RGB(hex: 0x7F9B73), strong: RGB(hex: 0x526D4B), gold: RGB(hex: 0xC9A94A))
        case .rose:
            return ThemeHue(primary: RGB(hex: 0xBA7D77), strong: RGB(hex: 0x884F4A), gold: RGB(hex: 0xBD9A55))
        case .ocean:
            return ThemeHue(primary: RGB(hex: 0x5C9A9A), strong: RGB(hex: 0x397072), gold: RGB(hex: 0xBFAA63))
        case .charcoal:
            // A cool slate/graphite vibe (not another green) so it reads
            // clearly different from "Sage, white, gold". Gold is pushed a
            // touch brighter to stay lively against the neutral gray.
            return ThemeHue(primary: RGB(hex: 0x5B6473), strong: RGB(hex: 0x333A45), gold: RGB(hex: 0xD8B85C))
        }
    }

    /// Builds the full palette for this color vibe, tuned for the current
    /// light/dark appearance and aesthetic (which shifts how pastel, neon,
    /// or minimal the accent colors read without changing the underlying hue).
    func palette(isDark: Bool, aesthetic: AestheticMode) -> Palette {
        let base = hue
        let primary = base.primary.adjusted(saturation: aesthetic.saturationMultiplier, brightness: aesthetic.brightnessMultiplier(isDark: isDark))
        let strong = base.strong.adjusted(saturation: aesthetic.saturationMultiplier, brightness: aesthetic.brightnessMultiplier(isDark: isDark))
        let gold = base.gold.adjusted(saturation: aesthetic.saturationMultiplier, brightness: aesthetic.brightnessMultiplier(isDark: isDark))
        let neutrals = Self.neutrals(tint: base.primary, isDark: isDark, tintStrength: aesthetic.tintStrength)

        return Palette(
            background: neutrals.background.color,
            surface: neutrals.surface.color,
            soft: neutrals.soft.color,
            ink: neutrals.ink.color,
            muted: neutrals.muted.color,
            primary: primary.color,
            strong: strong.color,
            gold: gold.color,
            isDark: isDark
        )
    }

    /// Derives background/surface/ink/muted neutrals from the appearance
    /// (light or dark) with just a whisper of the vibe's hue mixed in, so
    /// ink text always has strong contrast against the background regardless
    /// of which vibe or aesthetic is selected. This is what keeps text
    /// readable in dark mode, instead of relying on one fixed dark theme.
    private static func neutrals(tint: RGB, isDark: Bool, tintStrength: Double) -> (background: RGB, surface: RGB, soft: RGB, ink: RGB, muted: RGB) {
        let white = RGB(r: 1, g: 1, b: 1)
        let nearBlack = RGB(r: 0.07, g: 0.08, b: 0.07)
        let nearWhite = RGB(r: 0.97, g: 0.98, b: 0.96)

        if isDark {
            let background = nearBlack.mixed(with: tint, amount: tintStrength)
            let surface = background.mixed(with: white, amount: 0.07)
            let soft = background.mixed(with: tint, amount: 0.22)
            let ink = nearWhite.mixed(with: tint, amount: 0.05)
            let muted = nearWhite.mixed(with: nearBlack, amount: 0.42)
            return (background, surface, soft, ink, muted)
        } else {
            let background = white.mixed(with: tint, amount: tintStrength)
            let surface = white
            let soft = white.mixed(with: tint, amount: 0.16)
            let ink = nearBlack.mixed(with: tint, amount: 0.03)
            let muted = nearBlack.mixed(with: white, amount: 0.5)
            return (background, surface, soft, ink, muted)
        }
    }
}

private struct ThemeHue {
    let primary: RGB
    let strong: RGB
    let gold: RGB
}

enum AppearanceMode: String, CaseIterable, Codable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var id: String { rawValue }
}

enum AestheticMode: String, CaseIterable, Codable, Identifiable {
    case calm = "Calming motivation"
    case bright = "High-energy coaching"
    case minimal = "Quiet focus"

    var id: String { rawValue }

    /// Short label shown both on the segmented tab and as the aesthetic card
    /// title, so the two always match and never truncate in the picker. The
    /// `rawValue` stays long/descriptive and is what gets persisted.
    var displayName: String {
        switch self {
        case .calm: return "Calm"
        case .bright: return "Energetic"
        case .minimal: return "Quiet"
        }
    }

    var message: String {
        switch self {
        case .calm: return "Pastel tones, a warm serif headline, and room to breathe."
        case .bright: return "Punchy, high-saturation color and a heavy, high-energy font."
        case .minimal: return "A plain, quiet layout that keeps today's goal and workout front and center."
        }
    }

    /// Quiet focus intentionally strips decoration (gradients, gold borders,
    /// extra spotlight chrome) so the dashboard emphasizes the member's goal
    /// and today's workout rather than styling.
    var isQuiet: Bool { self == .minimal }

    /// How saturated the accent colors read. Calm and minimal stay gentle;
    /// high-energy is pushed well past 1.0 so the accents genuinely pop.
    var saturationMultiplier: Double {
        switch self {
        case .calm: return 0.68
        case .bright: return 1.75
        case .minimal: return 0.42
        }
    }

    /// Pastels want to be a touch lighter, neon a touch more vivid. Dark
    /// mode still gets a real push for "bright" so the high-energy accents
    /// stay punchy against a dark background.
    func brightnessMultiplier(isDark: Bool) -> Double {
        switch self {
        case .calm: return isDark ? 1.04 : 1.1
        case .bright: return isDark ? 1.14 : 1.08
        case .minimal: return isDark ? 0.98 : 0.96
        }
    }

    /// How strongly the background/soft surfaces borrow the vibe's hue.
    var tintStrength: Double {
        switch self {
        case .calm: return 0.06
        case .bright: return 0.14
        case .minimal: return 0.025
        }
    }

    /// Font design used for headline-weight text throughout the app. Each
    /// aesthetic gets a visibly distinct design: calm uses an elegant serif
    /// so it reads softer and clearly unlike quiet focus; bright uses the
    /// rounded design at heavy weight for a high-energy feel; minimal stays
    /// with the plain default design so nothing feels decorative.
    var headlineDesign: Font.Design {
        switch self {
        case .calm: return .serif
        case .bright: return .rounded
        case .minimal: return .default
        }
    }

    var headlineWeight: Font.Weight {
        switch self {
        case .calm: return .semibold
        case .bright: return .black
        case .minimal: return .medium
        }
    }

    var eyebrowWeight: Font.Weight {
        switch self {
        case .calm: return .semibold
        case .bright: return .heavy
        case .minimal: return .medium
        }
    }
}

struct Palette {
    let background: Color
    let surface: Color
    let soft: Color
    let ink: Color
    let muted: Color
    let primary: Color
    let strong: Color
    let gold: Color
    let isDark: Bool
}

struct Profile: Codable, Equatable {
    var name: String
    var birthday: Date
    var gender: Gender
    var goals: [Goal]
    var experience: Experience

    private enum CodingKeys: String, CodingKey {
        case name, birthday, age, gender, goals, experience
    }

    init(name: String, birthday: Date, gender: Gender, goals: [Goal], experience: Experience) {
        self.name = name
        self.birthday = birthday
        self.gender = gender
        self.goals = goals
        self.experience = experience
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        // Date.distantPast used to be the fallback here, but its Unix
        // timestamp (-62135769600) falls just outside the range Firestore's
        // Timestamp type accepts (seconds must be >= -62135596800, midnight
        // 1/1/1), which crashes the app the moment the profile gets synced.
        // Some devices already persisted that bad value locally before this
        // was fixed, so a missing field isn't the only case to guard against
        // — an already-decoded-but-invalid date needs to be caught too.
        let fallbackBirthday = Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date()
        let firestoreMinimumTimestamp: TimeInterval = -62135596800
        let decodedBirthday = try container.decodeIfPresent(Date.self, forKey: .birthday)
        if let decodedBirthday, decodedBirthday.timeIntervalSince1970 >= firestoreMinimumTimestamp {
            birthday = decodedBirthday
        } else {
            birthday = fallbackBirthday
        }
        gender = try container.decode(Gender.self, forKey: .gender)
        goals = try container.decode([Goal].self, forKey: .goals)
        experience = try container.decode(Experience.self, forKey: .experience)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(birthday, forKey: .birthday)
        try container.encode(gender, forKey: .gender)
        try container.encode(goals, forKey: .goals)
        try container.encode(experience, forKey: .experience)
    }
}

/// How the member created or entered their account. Email/phone are the
/// username+password path; google/apple are the one-tap convenience options.
enum AuthProvider: String, Codable {
    case email
    case phone
    case google
    case apple

    var label: String {
        switch self {
        case .email: return "Email"
        case .phone: return "Phone"
        case .google: return "Google"
        case .apple: return "Apple"
        }
    }
}

/// A locally stored account. NOTE: this is a front-end prototype — the
/// password is kept in `UserDefaults` in plain text purely so the sign
/// in / sign up flow works offline. A real build would authenticate against
/// a backend and never persist a raw password on device.
struct Account: Codable, Equatable {
    var username: String
    /// The email address or phone number used to sign up. Empty for the
    /// social (Google/Apple) convenience logins.
    var contact: String
    var contactIsEmail: Bool
    var password: String
    var provider: AuthProvider
    /// The backend's stable user id (Firebase Auth's `uid`), used as the
    /// Firestore document key for synced data. Nil for the local fallback,
    /// which has no server-side identity to key off of.
    var remoteID: String?

    private enum CodingKeys: String, CodingKey {
        case username, contact, contactIsEmail, password, provider, remoteID
    }

    init(username: String, contact: String, contactIsEmail: Bool, password: String, provider: AuthProvider, remoteID: String? = nil) {
        self.username = username
        self.contact = contact
        self.contactIsEmail = contactIsEmail
        self.password = password
        self.provider = provider
        self.remoteID = remoteID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        username = try container.decode(String.self, forKey: .username)
        contact = try container.decode(String.self, forKey: .contact)
        contactIsEmail = try container.decode(Bool.self, forKey: .contactIsEmail)
        password = try container.decode(String.self, forKey: .password)
        provider = try container.decode(AuthProvider.self, forKey: .provider)
        // Predates remoteID; older saved accounts just decode to nil.
        remoteID = try container.decodeIfPresent(String.self, forKey: .remoteID)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(username, forKey: .username)
        try container.encode(contact, forKey: .contact)
        try container.encode(contactIsEmail, forKey: .contactIsEmail)
        try container.encode(password, forKey: .password)
        try container.encode(provider, forKey: .provider)
        try container.encodeIfPresent(remoteID, forKey: .remoteID)
    }
}

/// Validation shared by the sign up form and the store, so the rules ("valid
/// contact", "strong password") are defined in exactly one place.
enum AuthValidator {
    /// A contact is accepted if it looks like an email (has an `@` and a dot
    /// after it) or a phone number (at least 7 digits).
    static func isValidContact(_ raw: String) -> Bool {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if isEmail(value) { return true }
        let digits = value.filter(\.isNumber)
        return digits.count >= 7
    }

    static func isEmail(_ value: String) -> Bool {
        guard let at = value.firstIndex(of: "@") else { return false }
        let domain = value[value.index(after: at)...]
        return !value[..<at].isEmpty && domain.contains(".") && !domain.hasSuffix(".")
    }

    /// Returns the human-readable requirements a password is still missing.
    /// Empty means the password is strong enough. Rule: at least 8
    /// characters, including at least one letter and one special character.
    static func passwordProblems(_ password: String) -> [String] {
        var problems: [String] = []
        if password.count < 8 { problems.append("at least 8 characters") }
        if password.rangeOfCharacter(from: .letters) == nil { problems.append("a letter") }
        let specials = CharacterSet(charactersIn: "!@#$%^&*()_-+=[]{}|;:'\",.<>?/`~\\")
        if password.rangeOfCharacter(from: specials) == nil { problems.append("a special character") }
        return problems
    }

    static func isStrongPassword(_ password: String) -> Bool {
        passwordProblems(password).isEmpty
    }
}

struct WorkoutCategory: Identifiable, Hashable {
    let id: String
    let title: String
    let subcategories: [WorkoutSubcategory]
}

struct WorkoutSubcategory: Identifiable, Hashable {
    let id: String
    let title: String
    let workouts: [Workout]
}

struct Workout: Identifiable, Hashable {
    let id: String
    let name: String
    let category: String
    let subcategory: String
    let materials: String
    let difficulty: String
    let explanation: String
    let formCue: String
    let pose: WorkoutPose
}

enum WorkoutPose: String, Hashable {
    case curl
    case hold
    case dip
    case overheadExtension
    case squat
    case stepUp
    case calfRaise
    case hinge
    case bridge
    case pushUp
    case press
    case row
    case fly
    case deadBug
    case plank
    case march
    case reach
    case stretch
    case catCow
}

struct Prescription {
    let sets: Int
    let reps: String
    let note: String
}

struct StreakSnapshot {
    let rollingSpan: Int
    let completedDays: Int
    let missedDays: Int
    let graceRemaining: Int
    let didReset: Bool
}

/// One logged workout completion, captured at the moment the member marks a
/// workout done. It snapshots the sets/reps that applied at that time (rather
/// than recomputing later) so the Progress history stays accurate even if the
/// member's goal or experience — and therefore the prescription — changes.
struct CompletionRecord: Codable, Identifiable, Hashable {
    let id: UUID
    let workoutID: String
    let workoutName: String
    let sets: Int
    let reps: String
    let date: Date
}

extension Color {
    init(hex: UInt32) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}

/// A small, dependency-free RGB color used for palette math (mixing colors
/// together, and nudging saturation/brightness for the selected aesthetic).
/// Working in plain RGB/HSB numbers here — instead of introspecting an
/// opaque SwiftUI `Color` — keeps this portable and predictable.
struct RGB {
    var r: Double
    var g: Double
    var b: Double

    init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    init(hex: UInt32) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
    }

    var color: Color { Color(red: r, green: g, blue: b) }

    /// Linearly blends toward `other` by `amount` (0 = self, 1 = other).
    func mixed(with other: RGB, amount: Double) -> RGB {
        let t = min(1, max(0, amount))
        return RGB(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t)
    }

    /// Returns a copy with saturation and brightness scaled by the given
    /// multipliers (via an HSB round trip), clamped to valid ranges.
    func adjusted(saturation satMul: Double, brightness briMul: Double) -> RGB {
        let hsb = RGB.rgbToHsb(r: r, g: g, b: b)
        let newS = min(1, max(0, hsb.s * satMul))
        let newV = min(1, max(0, hsb.v * briMul))
        let rgb = RGB.hsbToRgb(h: hsb.h, s: newS, v: newV)
        return RGB(r: rgb.r, g: rgb.g, b: rgb.b)
    }

    private static func rgbToHsb(r: Double, g: Double, b: Double) -> (h: Double, s: Double, v: Double) {
        let maxV = max(r, g, b)
        let minV = min(r, g, b)
        let delta = maxV - minV

        var h: Double = 0
        if delta > 0.0001 {
            if maxV == r {
                h = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
            } else if maxV == g {
                h = (b - r) / delta + 2
            } else {
                h = (r - g) / delta + 4
            }
            h *= 60
            if h < 0 { h += 360 }
        }
        let s = maxV == 0 ? 0 : delta / maxV
        return (h, s, maxV)
    }

    private static func hsbToRgb(h: Double, s: Double, v: Double) -> (r: Double, g: Double, b: Double) {
        let c = v * s
        let x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = v - c

        let segment: (Double, Double, Double)
        switch h {
        case 0..<60: segment = (c, x, 0)
        case 60..<120: segment = (x, c, 0)
        case 120..<180: segment = (0, c, x)
        case 180..<240: segment = (0, x, c)
        case 240..<300: segment = (x, 0, c)
        default: segment = (c, 0, x)
        }
        return (segment.0 + m, segment.1 + m, segment.2 + m)
    }
}
