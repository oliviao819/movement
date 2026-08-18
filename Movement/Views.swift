import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: MovementStore
    @Environment(\.colorScheme) private var systemScheme

    var body: some View {
        Group {
            if !store.isAuthenticated {
                WelcomeFlowView()
            } else if !store.hasCompletedOnboarding {
                OnboardingView()
            } else {
                MainAppView()
            }
        }
        .tint(store.palette(system: systemScheme).strong)
        .preferredColorScheme(store.preferredColorScheme)
        // Animate the whole palette (backgrounds, ink, accents) whenever the
        // light/dark choice changes so the switch crossfades instead of
        // snapping. Keyed on both the explicit choice and the system scheme
        // so a "System" follow-along transition is smooth too.
        .animation(.easeInOut(duration: 0.35), value: store.appearance)
        .animation(.easeInOut(duration: 0.35), value: systemScheme)
    }
}

struct WelcomeFlowView: View {
    @EnvironmentObject private var store: MovementStore
    @Environment(\.colorScheme) private var systemScheme
    @State private var isAuthVisible = false

    var body: some View {
        // Welcome splash first, then the log in / sign up screen. Once the
        // member authenticates, RootView takes over and shows the quiz.
        if isAuthVisible {
            AuthView()
        } else {
            WelcomeView {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) {
                    isAuthVisible = true
                }
            }
        }
    }
}

struct WelcomeView: View {
    @EnvironmentObject private var store: MovementStore
    @Environment(\.colorScheme) private var systemScheme
    let onBegin: () -> Void

    var body: some View {
        let palette = store.palette(system: systemScheme)

        ZStack {
            palette.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 28) {
                Spacer()
                Demonstration360View(workout: WorkoutLibrary.allWorkouts.first!)
                    .frame(height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 12) {
                    Text("Calm strength, steady progress")
                        .font(.caption.weight(.bold))
                        .textCase(.uppercase)
                        .foregroundStyle(palette.gold)
                    Text("Movement")
                        .font(.system(size: 64, design: store.aesthetic.headlineDesign).weight(store.aesthetic.headlineWeight))
                        .foregroundStyle(palette.ink)
                    Text("Build a workout rhythm that feels encouraging, clear, and forgiving enough to last.")
                        .font(.body)
                        .lineSpacing(4)
                        .foregroundStyle(palette.muted)
                }
                Button(action: onBegin) {
                    Text("Begin")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle(palette: palette))
                Spacer()
            }
            .padding(24)
        }
    }
}

/// The log in / sign up screen shown before the personalization quiz.
/// Sign up takes an email or phone, a username, and a strong password; log in
/// checks those against the stored account. Google/Apple offer a one-tap
/// convenience session (see `MovementStore.signInWithGoogle` / `signInWithApple`).
struct AuthView: View {
    @EnvironmentObject private var store: MovementStore
    @Environment(\.colorScheme) private var systemScheme

    private enum Mode: String, CaseIterable, Identifiable {
        case signUp = "Sign up"
        case logIn = "Log in"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .signUp
    @State private var contact = ""
    @State private var username = ""
    @State private var password = ""
    @State private var identifier = ""
    @State private var revealPassword = false
    @State private var errorMessage: String?
    @State private var isWorking = false
    @State private var isResettingPassword = false
    @State private var resetEmail = ""
    @State private var resetMessage: String?

    var body: some View {
        let palette = store.palette(system: systemScheme)

        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Movement")
                        .font(.system(size: 40, design: store.aesthetic.headlineDesign).weight(store.aesthetic.headlineWeight))
                        .foregroundStyle(palette.ink)
                    Text("Log in or create an account to save your progress.")
                        .font(.body)
                        .foregroundStyle(palette.muted)
                }

                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: mode) { _ in errorMessage = nil }

                if mode == .signUp {
                    signUpFields(palette)
                } else {
                    logInFields(palette)
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(action: submit) {
                    Group {
                        if isWorking {
                            ProgressView().tint(.white)
                        } else {
                            Text(mode == .signUp ? "Create account" : "Log in")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle(palette: palette))
                .disabled(isWorking)

                dividerRow(palette)

                socialButton(provider: .apple, palette: palette)
                socialButton(provider: .google, palette: palette)
            }
            .padding(24)
        }
        .background(palette.background.ignoresSafeArea())
        .alert("Reset password", isPresented: $isResettingPassword) {
            TextField("you@example.com", text: $resetEmail)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Send reset email") {
                Task {
                    let error = await store.sendPasswordReset(contact: resetEmail)
                    resetMessage = error ?? "If that email has an account, a reset link is on its way."
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter the email address you signed up with.")
        }
        .alert("", isPresented: Binding(get: { resetMessage != nil }, set: { if !$0 { resetMessage = nil } })) {
            Button("OK") {}
        } message: {
            Text(resetMessage ?? "")
        }
    }

    // MARK: - Fields

    @ViewBuilder
    private func signUpFields(_ palette: Palette) -> some View {
        field(palette, label: "Email or phone") {
            TextField("you@example.com or 555-123-4567", text: $contact)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        field(palette, label: "Username") {
            TextField("Choose a username", text: $username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("Password", palette: palette)
            passwordField(palette, placeholder: "Create a strong password")
            passwordRequirements(palette)
        }
    }

    @ViewBuilder
    private func logInFields(_ palette: Palette) -> some View {
        field(palette, label: "Email, phone, or username") {
            TextField("Enter your login", text: $identifier)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("Password", palette: palette)
            passwordField(palette, placeholder: "Enter your password")
        }
        Button("Forgot password?") {
            resetEmail = identifier
            resetMessage = nil
            isResettingPassword = true
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(palette.strong)
    }

    @ViewBuilder
    private func field<Content: View>(_ palette: Palette, label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel(label, palette: palette)
            fieldContainer(palette) { content() }
        }
    }

    private func fieldLabel(_ text: String, palette: Palette) -> some View {
        Text(text)
            .font(.caption.weight(.bold))
            .textCase(.uppercase)
            .foregroundStyle(palette.gold)
    }

    @ViewBuilder
    private func fieldContainer<Content: View>(_ palette: Palette, @ViewBuilder content: () -> Content) -> some View {
        content()
            .foregroundStyle(palette.ink)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(palette.muted.opacity(0.2), lineWidth: 1)
            )
    }

    private func passwordField(_ palette: Palette, placeholder: String) -> some View {
        fieldContainer(palette) {
            HStack {
                Group {
                    if revealPassword {
                        TextField(placeholder, text: $password)
                    } else {
                        SecureField(placeholder, text: $password)
                    }
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                Button {
                    revealPassword.toggle()
                } label: {
                    Image(systemName: revealPassword ? "eye.slash" : "eye")
                        .foregroundStyle(palette.muted)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func passwordRequirements(_ palette: Palette) -> some View {
        let problems = AuthValidator.passwordProblems(password)
        return VStack(alignment: .leading, spacing: 4) {
            requirementRow("At least 8 characters", satisfied: !problems.contains("at least 8 characters"), palette: palette)
            requirementRow("A letter", satisfied: !problems.contains("a letter"), palette: palette)
            requirementRow("A special character (! @ # $ …)", satisfied: !problems.contains("a special character"), palette: palette)
        }
    }

    private func requirementRow(_ text: String, satisfied: Bool, palette: Palette) -> some View {
        Label {
            Text(text)
                .font(.caption)
                .foregroundStyle(satisfied ? palette.strong : palette.muted)
        } icon: {
            Image(systemName: satisfied ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(satisfied ? palette.strong : palette.muted.opacity(0.5))
        }
    }

    // MARK: - Social

    private func dividerRow(_ palette: Palette) -> some View {
        HStack(spacing: 12) {
            Rectangle().fill(palette.muted.opacity(0.25)).frame(height: 1)
            Text("or")
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.muted)
            Rectangle().fill(palette.muted.opacity(0.25)).frame(height: 1)
        }
    }

    private func socialButton(provider: AuthProvider, palette: Palette) -> some View {
        let isApple = provider == .apple
        return Button {
            Task {
                isWorking = true
                errorMessage = isApple ? await store.signInWithApple() : await store.signInWithGoogle()
                isWorking = false
            }
        } label: {
            HStack(spacing: 10) {
                if isApple {
                    Image(systemName: "applelogo")
                        .font(.headline)
                } else {
                    GoogleGLogo()
                }
                Text("Continue with \(provider.label)")
                    .font(.headline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(isApple ? Color.white : palette.ink)
            .background(isApple ? Color.black : palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isApple ? Color.clear : palette.muted.opacity(0.3), lineWidth: 1)
            )
        }
        .disabled(isWorking)
    }

    private func submit() {
        Task {
            isWorking = true
            switch mode {
            case .signUp:
                errorMessage = await store.signUp(contact: contact, username: username, password: password)
            case .logIn:
                errorMessage = await store.logIn(identifier: identifier, password: password)
            }
            isWorking = false
        }
    }
}

struct OnboardingView: View {
    @EnvironmentObject private var store: MovementStore
    @Environment(\.colorScheme) private var systemScheme
    @State private var name = ""
    @State private var birthday = Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date()
    @State private var gender: Gender = .preferNot
    @State private var goals: Set<Goal> = [.consistency]
    @State private var experience: Experience = .beginner

    var body: some View {
        let palette = store.palette(system: systemScheme)

        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    DatePicker("Birthday", selection: $birthday, in: ...Date(), displayedComponents: .date)
                    Picker("Gender", selection: $gender) {
                        ForEach(Gender.allCases) { gender in
                            Text(gender.rawValue).tag(gender)
                        }
                    }
                    Picker("Experience", selection: $experience) {
                        ForEach(Experience.allCases) { level in
                            Text(level.rawValue).tag(level)
                        }
                    }
                } header: {
                    Text("About you")
                }

                Section {
                    ForEach(Goal.allCases) { goal in
                        Toggle(goal.rawValue, isOn: Binding(
                            get: { goals.contains(goal) },
                            set: { isOn in
                                if isOn {
                                    goals.insert(goal)
                                } else if goals.count > 1 {
                                    goals.remove(goal)
                                }
                            }
                        ))
                    }
                } header: {
                    Text("End result goals")
                } footer: {
                    Text("Your first selected goal influences sets and reps for every workout.")
                }

                Section {
                    Button("Create my plan") {
                        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        let orderedGoals = Goal.allCases.filter { goals.contains($0) }
                        store.saveProfile(Profile(name: cleanName.isEmpty ? "Friend" : cleanName, birthday: birthday, gender: gender, goals: orderedGoals, experience: experience))
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .scrollContentBackground(.hidden)
            .background(palette.background)
            .navigationTitle("Personalize Movement")
        }
    }
}

private struct GoogleGLogo: View {
    var body: some View {
        Text("G")
            .font(.system(size: 20, weight: .black, design: .rounded))
            .overlay {
                AngularGradient(
                    colors: [
                        Color(hex: 0x4285F4),
                        Color(hex: 0x34A853),
                        Color(hex: 0xFBBC05),
                        Color(hex: 0xEA4335),
                        Color(hex: 0x4285F4)
                    ],
                    center: .center
                )
                .mask(
                    Text("G")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                )
            }
            .foregroundStyle(.clear)
            .frame(width: 22, height: 22)
            .accessibilityHidden(true)
    }
}

struct MainAppView: View {
    @EnvironmentObject private var store: MovementStore
    @Environment(\.colorScheme) private var systemScheme
    @State private var isMenuOpen = false
    @State private var isSettingsOpen = false

    var body: some View {
        let palette = store.palette(system: systemScheme)

        NavigationStack {
            ZStack(alignment: .leading) {
                DashboardView(isMenuOpen: $isMenuOpen, isSettingsOpen: $isSettingsOpen)
                    .navigationDestination(for: WorkoutCategory.self) { category in
                        CategoryView(category: category)
                    }
                    .navigationDestination(for: WorkoutSubcategory.self) { subcategory in
                        SubcategoryView(subcategory: subcategory)
                    }
                    .navigationDestination(for: Workout.self) { workout in
                        WorkoutDetailView(workout: workout)
                    }
                    .navigationDestination(for: ProgressRoute.self) { _ in
                        ProgressDetailView()
                    }

                if isMenuOpen {
                    Color.black.opacity(0.28)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                                isMenuOpen = false
                            }
                        }

                    SideMenuView(isOpen: $isMenuOpen)
                        .frame(width: 310)
                        .transition(.move(edge: .leading))
                        .zIndex(2)
                }
            }
            .background(palette.background)
        }
        .sheet(isPresented: $isSettingsOpen) {
            SettingsView()
                .presentationDetents([.medium, .large])
        }
    }
}

struct DashboardView: View {
    @EnvironmentObject private var store: MovementStore
    @Environment(\.colorScheme) private var systemScheme
    @Binding var isMenuOpen: Bool
    @Binding var isSettingsOpen: Bool
    private let quotes = [
        "Small promises kept become strength.",
        "Move gently. Finish proud.",
        "The calm rep still counts.",
        "Progress likes consistency more than drama.",
        "Start where your breath can stay with you.",
        "Showing up is most of the work.",
        "A little today beats a lot someday.",
        "Slow is smooth, and smooth lasts.",
        "Your only rival is yesterday.",
        "Rest is part of the training, too.",
        "Strong is built one quiet day at a time.",
        "Trust the reps you can repeat.",
        "Breathe first, then move.",
        "Consistency is a kindness to your future self.",
        "The body remembers the effort, not the excuse.",
        "Begin before you feel ready.",
        "Steady hands finish the set.",
        "Momentum is made, not found.",
        "One honest workout is enough for today.",
        "Gentle discipline outlasts harsh motivation.",
        "Every day you move is a day you win.",
        "Form over speed, always.",
        "You don't have to be fast to be forward.",
        "Let today be repeatable tomorrow."
    ]

    var body: some View {
        let palette = store.palette(system: systemScheme)
        let name = store.profile?.name ?? "Friend"
        // Index by the day of the year (not day of month) so a fresh quote
        // shows every day and the app cycles through the whole list before
        // any repeats, rather than looping the same few every month.
        let calendar = Calendar.current
        let dayOfYear = calendar.ordinality(of: .day, in: .year, for: Date())
            ?? calendar.component(.day, from: Date())
        let quote = quotes[dayOfYear % quotes.count]

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Button {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                            isMenuOpen = true
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal")
                    }
                    .buttonStyle(IconButtonStyle(palette: palette))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Movement")
                            .font(.headline.weight(.black))
                            .foregroundStyle(palette.ink)
                        Text(quote)
                            .font(.caption)
                            .foregroundStyle(palette.muted)
                            .lineLimit(2)
                    }

                    Spacer()

                    Button {
                        isSettingsOpen = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                    .buttonStyle(IconButtonStyle(palette: palette))
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Welcome back")
                        .font(.caption.weight(.bold))
                        .textCase(.uppercase)
                        .foregroundStyle(palette.gold)
                    Text("\(name), let's move with intention.")
                        .font(.system(size: 34, design: store.aesthetic.headlineDesign).weight(store.aesthetic.headlineWeight))
                        .foregroundStyle(palette.ink)
                    Text(goalLine)
                        .foregroundStyle(palette.muted)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                TodayFocusView()

                // The aesthetic picker always stays on the dashboard so the
                // member can switch away from Quiet focus without digging into
                // Settings. Quiet focus still strips the decorative chrome
                // (gradient/border) inside the card via its own styling.
                AestheticSpotlightView()
                WeekCompletionView()
                RollingStreakView()
            }
            .padding(18)
        }
        .background(palette.background.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
    }

    private var goalLine: String {
        let goal = store.profile?.goals.first?.rawValue ?? "Consistency"
        let experience = store.profile?.experience.rawValue ?? "Beginner"
        return "Current focus: \(goal). Experience level: \(experience)."
    }
}

struct AestheticSpotlightView: View {
    @EnvironmentObject private var store: MovementStore
    @Environment(\.colorScheme) private var systemScheme

    var body: some View {
        let palette = store.palette(system: systemScheme)

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: energyIcon)
                    .font(.title2)
                    .foregroundStyle(palette.strong)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Aesthetic")
                        .font(.caption.weight(store.aesthetic.eyebrowWeight))
                        .textCase(.uppercase)
                        .foregroundStyle(palette.gold)
                    Text(store.aesthetic.displayName)
                        .font(.system(.title2, design: store.aesthetic.headlineDesign).weight(store.aesthetic.headlineWeight))
                        .foregroundStyle(palette.ink)
                }
                Spacer()
            }

            Text(store.aesthetic.message)
                .font(.subheadline)
                .foregroundStyle(palette.muted)

            Picker("Aesthetic", selection: Binding(
                get: { store.aesthetic },
                set: { store.setAesthetic($0) }
            )) {
                ForEach(AestheticMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(18)
        .background(spotlightBackground(palette))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(palette.gold.opacity(store.aesthetic.isQuiet ? 0 : 0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    /// Quiet focus drops the gradient (and, above, the gold border) for a
    /// flat, low-distraction surface; other aesthetics keep the gradient.
    @ViewBuilder
    private func spotlightBackground(_ palette: Palette) -> some View {
        if store.aesthetic.isQuiet {
            palette.surface
        } else {
            LinearGradient(colors: [palette.soft, palette.surface], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private var energyIcon: String {
        switch store.aesthetic {
        case .calm: return "leaf.fill"
        case .bright: return "bolt.fill"
        case .minimal: return "circle.grid.cross.fill"
        }
    }
}

/// Surfaces the member's primary goal and a suggested workout for today.
/// This is the piece "Quiet focus" leans on — it keeps the day's goal and
/// movement front and center regardless of aesthetic, and taps through to
/// the full workout detail.
struct TodayFocusView: View {
    @EnvironmentObject private var store: MovementStore
    @Environment(\.colorScheme) private var systemScheme

    var body: some View {
        let palette = store.palette(system: systemScheme)
        let workout = todaysWorkout
        let goal = store.profile?.goals.first?.rawValue ?? "Consistency"
        let prescription = WorkoutPlanEngine.prescription(for: workout, profile: store.profile)

        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Today's focus")
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(palette.gold)
                Text("Goal: \(goal)")
                    .font(.system(.title2, design: store.aesthetic.headlineDesign).weight(store.aesthetic.headlineWeight))
                    .foregroundStyle(palette.ink)
            }

            NavigationLink(value: workout) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(workout.name)
                            .font(.headline)
                            .foregroundStyle(palette.ink)
                        Text("\(prescription.sets) sets · \(prescription.reps)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(palette.ink)
                        Text("\(workout.subcategory) · \(workout.materials)")
                            .font(.caption)
                            .foregroundStyle(palette.muted)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(palette.muted)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.soft)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)

            if !store.aesthetic.isQuiet {
                Text("A steady suggestion for today. Open the menu to pick any other workout whenever you like.")
                    .font(.footnote)
                    .foregroundStyle(palette.muted)
            }
        }
        .sectionCard(palette)
    }

    /// Picks one workout per calendar day, stable for the whole day, so the
    /// suggestion doesn't shuffle on every redraw.
    private var todaysWorkout: Workout {
        let all = WorkoutLibrary.allWorkouts
        let calendar = Calendar.current
        let dayOfYear = calendar.ordinality(of: .day, in: .year, for: Date())
            ?? calendar.component(.day, from: Date())
        return all[dayOfYear % all.count]
    }
}

struct WeekCompletionView: View {
    @EnvironmentObject private var store: MovementStore
    @Environment(\.colorScheme) private var systemScheme

    var body: some View {
        let palette = store.palette(system: systemScheme)
        let completed = store.weekCompletionCount()

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Week completion")
                        .font(.caption.weight(.bold))
                        .textCase(.uppercase)
                        .foregroundStyle(palette.gold)
                    Text("\(completed)/7 days")
                        .font(.title2.weight(.black))
                        .foregroundStyle(palette.ink)
                }
                Spacer()
                Text("\(Int(Double(completed) / 7.0 * 100))%")
                    .font(.headline.weight(.black))
                    .foregroundStyle(palette.ink)
                    .padding(14)
                    .background(palette.soft)
                    .clipShape(Circle())
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
                ForEach(store.weekDays(), id: \.self) { day in
                    let didComplete = store.didComplete(on: day)
                    VStack(spacing: 7) {
                        Text(store.shortWeekday(for: day))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(palette.ink)
                        Image(systemName: didComplete ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(didComplete ? palette.strong : palette.muted.opacity(0.45))
                        Text("\(store.completedWorkouts(on: day))")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(palette.muted)
                    }
                    .frame(maxWidth: .infinity, minHeight: 74)
                    .background(didComplete ? palette.soft : palette.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }

            Text("Days check off automatically after you complete a workout. A new week starts fresh.")
                .font(.footnote)
                .foregroundStyle(palette.muted)
        }
        .sectionCard(palette)
    }
}

struct RollingStreakView: View {
    @EnvironmentObject private var store: MovementStore
    @Environment(\.colorScheme) private var systemScheme

    var body: some View {
        let palette = store.palette(system: systemScheme)
        let streak = store.streakSnapshot()

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Rolling streak")
                        .font(.caption.weight(.bold))
                        .textCase(.uppercase)
                        .foregroundStyle(palette.gold)
                    Text("\(streak.rollingSpan) day roll")
                        .font(.title2.weight(.black))
                        .foregroundStyle(palette.ink)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("\(streak.completedDays)")
                        .font(.title.weight(.black))
                        .foregroundStyle(palette.ink)
                    Text("completed")
                        .font(.caption)
                        .foregroundStyle(palette.muted)
                }
            }

            HStack(spacing: 6) {
                ForEach(store.rollingDays(), id: \.self) { day in
                    let complete = store.didComplete(on: day)
                    VStack(spacing: 4) {
                        Circle()
                            .fill(complete ? palette.strong : palette.soft)
                            .overlay(Circle().stroke(palette.muted.opacity(0.18), lineWidth: 1))
                            .frame(width: 18, height: 18)
                        Text(store.shortWeekday(for: day).prefix(1))
                            .font(.caption2)
                            .foregroundStyle(palette.muted)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            Text(streakText(streak))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(streak.didReset ? .red : palette.muted)
        }
        .sectionCard(palette)
    }

    private func streakText(_ streak: StreakSnapshot) -> String {
        if streak.didReset {
            return "The roll reset after too many missed days. Complete one workout to restart today."
        }
        if store.lenientStreaks {
            return "\(streak.missedDays) grace miss\(streak.missedDays == 1 ? "" : "es") used, \(streak.graceRemaining) remaining before reset."
        }
        return "Strict mode is on. Any missed day ends the roll."
    }
}

private enum MenuSection: String, CaseIterable, Identifiable {
    case workouts = "Workouts"
    case progress = "Progress"
    var id: String { rawValue }
}

/// Navigation marker for the full-screen Progress detail page. The sidebar's
/// Progress tab shows a short summary and links here via `NavigationLink`.
struct ProgressRoute: Hashable {}

struct SideMenuView: View {
    @EnvironmentObject private var store: MovementStore
    @Environment(\.colorScheme) private var systemScheme
    @Binding var isOpen: Bool
    @State private var section: MenuSection = .workouts

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    var body: some View {
        let palette = store.palette(system: systemScheme)

        VStack(alignment: .leading, spacing: 16) {
            Text("Movement Library")
                .font(.caption.weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(palette.gold)

            Picker("Section", selection: $section) {
                ForEach(MenuSection.allCases) { menuSection in
                    Text(menuSection.rawValue).tag(menuSection)
                }
            }
            .pickerStyle(.segmented)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    switch section {
                    case .workouts: workoutsSection(palette)
                    case .progress: progressSection(palette)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .padding(20)
        // Keep the content inside the safe area (so the header no longer sits
        // under the status-bar clock) while the surface color still fills the
        // whole panel, including behind the status bar.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.surface.ignoresSafeArea())
    }

    // MARK: - Workouts

    @ViewBuilder
    private func workoutsSection(_ palette: Palette) -> some View {
        ForEach(WorkoutLibrary.categories) { category in
            NavigationLink(value: category) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(category.title)
                        .font(.headline)
                        .foregroundStyle(palette.ink)
                    Text(category.subcategories.map(\.title).joined(separator: " / "))
                        .font(.caption)
                        .foregroundStyle(palette.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(palette.soft)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .simultaneousGesture(TapGesture().onEnded {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                    isOpen = false
                }
            })
        }
    }

    // MARK: - Progress

    @ViewBuilder
    private func progressSection(_ palette: Palette) -> some View {
        let history = store.completionHistory()

        // A short at-a-glance summary. The full breakdown (streak, weekly
        // days, current goal, and every past workout) lives on its own page,
        // reached through the "See full progress" link below.
        if history.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("No workouts logged yet")
                    .font(.headline)
                    .foregroundStyle(palette.ink)
                Text("Finish a workout and it shows up here with its sets, reps, and the date and time you completed it.")
                    .font(.caption)
                    .foregroundStyle(palette.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(palette.soft)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            let days = store.daysTracking()
            let weekCount = store.weekCompletionCount()
            VStack(alignment: .leading, spacing: 4) {
                Text("Day \(days) of moving")
                    .font(.title3.weight(.black))
                    .foregroundStyle(palette.ink)
                Text("\(history.count) workout\(history.count == 1 ? "" : "s") completed · \(weekCount)/7 days this week.")
                    .font(.caption)
                    .foregroundStyle(palette.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(palette.soft)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }

        NavigationLink(value: ProgressRoute()) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("See full progress")
                        .font(.headline)
                        .foregroundStyle(palette.ink)
                    Text("Streak, weekly days, your goal, and every past workout.")
                        .font(.caption)
                        .foregroundStyle(palette.muted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(palette.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(palette.soft)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .simultaneousGesture(TapGesture().onEnded {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                isOpen = false
            }
        })

        // A quick preview of the most recent completions; the full list is on
        // the Progress page.
        ForEach(history.prefix(3)) { record in
            VStack(alignment: .leading, spacing: 4) {
                Text(record.workoutName)
                    .font(.headline)
                    .foregroundStyle(palette.ink)
                Text("\(record.sets) sets · \(record.reps)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.ink)
                Text(Self.timestampFormatter.string(from: record.date))
                    .font(.caption)
                    .foregroundStyle(palette.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(palette.soft)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

/// The full Progress page reached from the sidebar's "See full progress"
/// link. Pulls together the rolling streak, this week's completed days, the
/// member's current goal, and a tappable list of every past workout.
struct ProgressDetailView: View {
    @EnvironmentObject private var store: MovementStore
    @Environment(\.colorScheme) private var systemScheme

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        let palette = store.palette(system: systemScheme)
        let history = store.completionHistory()

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ProgressGoalCard()
                ProgressStreakView()
                ProgressWeekView()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Previous workouts")
                        .font(.caption.weight(.bold))
                        .textCase(.uppercase)
                        .foregroundStyle(palette.gold)

                    if history.isEmpty {
                        Text("Finish a workout and it shows up here. Tap any past workout to revisit its instructions and 360 form view.")
                            .font(.subheadline)
                            .foregroundStyle(palette.muted)
                    } else {
                        ForEach(history) { record in
                            previousWorkoutRow(record, palette: palette)
                        }
                    }
                }
                .sectionCard(palette)
            }
            .padding(18)
        }
        .background(palette.background.ignoresSafeArea())
        .navigationTitle("Progress")
    }

    /// Renders one past completion. If the workout still exists in the
    /// library, the row is a `NavigationLink` into its detail page so the
    /// member can revisit what they did; otherwise it stays a plain card.
    @ViewBuilder
    private func previousWorkoutRow(_ record: CompletionRecord, palette: Palette) -> some View {
        if let workout = WorkoutLibrary.allWorkouts.first(where: { $0.id == record.workoutID }) {
            NavigationLink(value: workout) {
                previousWorkoutContent(record, palette: palette, tappable: true)
            }
            .buttonStyle(.plain)
        } else {
            previousWorkoutContent(record, palette: palette, tappable: false)
        }
    }

    private func previousWorkoutContent(_ record: CompletionRecord, palette: Palette, tappable: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(record.workoutName)
                    .font(.headline)
                    .foregroundStyle(palette.ink)
                Text("\(record.sets) sets · \(record.reps)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.ink)
                Text(Self.timestampFormatter.string(from: record.date))
                    .font(.caption)
                    .foregroundStyle(palette.muted)
            }
            Spacer()
            if tappable {
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(palette.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(palette.soft)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// Shows the member's primary goal (with any secondary goals as pills) on the
/// Progress page, mirroring the goal that drives their sets and reps.
struct ProgressGoalCard: View {
    @EnvironmentObject private var store: MovementStore
    @Environment(\.colorScheme) private var systemScheme

    var body: some View {
        let palette = store.palette(system: systemScheme)
        let goals = store.profile?.goals ?? []
        let primary = goals.first?.rawValue ?? "Consistency"
        let experience = store.profile?.experience.rawValue ?? "Beginner"
        let others = goals.dropFirst().map(\.rawValue)

        VStack(alignment: .leading, spacing: 10) {
            Text("Current goal")
                .font(.caption.weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(palette.gold)
            Text(primary)
                .font(.system(size: 30, design: store.aesthetic.headlineDesign).weight(store.aesthetic.headlineWeight))
                .foregroundStyle(palette.ink)
            Text("Experience level: \(experience). Your goal shapes the sets and reps for every workout.")
                .font(.subheadline)
                .foregroundStyle(palette.muted)

            if !others.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(others, id: \.self) { goal in
                            InfoPill(text: goal, icon: "target")
                        }
                    }
                }
            }
        }
        .sectionCard(palette)
    }
}

/// A pared-down streak card for the Progress page. Unlike the dashboard's
/// two-week `RollingStreakView`, this shows just the current week (7 days) and
/// the plain number of days completed in the streak.
struct ProgressStreakView: View {
    @EnvironmentObject private var store: MovementStore
    @Environment(\.colorScheme) private var systemScheme

    var body: some View {
        let palette = store.palette(system: systemScheme)
        let streak = store.streakSnapshot()

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "flame.fill")
                    .font(.title2)
                    .foregroundStyle(palette.strong)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Streak")
                        .font(.caption.weight(.bold))
                        .textCase(.uppercase)
                        .foregroundStyle(palette.gold)
                    Text("\(streak.completedDays) day\(streak.completedDays == 1 ? "" : "s")")
                        .font(.system(size: 30, design: store.aesthetic.headlineDesign).weight(store.aesthetic.headlineWeight))
                        .foregroundStyle(palette.ink)
                }
                Spacer()
            }

            HStack(spacing: 8) {
                ForEach(weekDaysSundayFirst, id: \.self) { day in
                    let complete = store.didComplete(on: day)
                    VStack(spacing: 6) {
                        Circle()
                            .fill(complete ? palette.strong : palette.soft)
                            .overlay(Circle().stroke(palette.muted.opacity(0.2), lineWidth: 1))
                            .frame(width: 26, height: 26)
                        Text(store.shortWeekday(for: day).prefix(1))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(palette.muted)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .sectionCard(palette)
    }

    /// The seven days of the current week ordered Sunday → Saturday, like a
    /// standard calendar, regardless of the device locale's first weekday.
    private var weekDaysSundayFirst: [Date] {
        var calendar = Calendar.current
        calendar.firstWeekday = 1 // Sunday
        guard let start = calendar.dateInterval(of: .weekOfYear, for: Date())?.start else {
            return store.weekDays()
        }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }
}

/// A simple week-completion card for the Progress page: one filled circle per
/// completed day and a plain "X/7 days completed" line. Deliberately lighter
/// than the dashboard's `WeekCompletionView`, which also shows per-day counts
/// and a percentage.
struct ProgressWeekView: View {
    @EnvironmentObject private var store: MovementStore
    @Environment(\.colorScheme) private var systemScheme

    var body: some View {
        let palette = store.palette(system: systemScheme)
        let completed = store.weekCompletionCount()

        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("This week")
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(palette.gold)
                Text("\(completed)/7 days completed")
                    .font(.system(size: 30, design: store.aesthetic.headlineDesign).weight(store.aesthetic.headlineWeight))
                    .foregroundStyle(palette.ink)
            }

            // Just a count: fill the first `completed` of seven dots, rather
            // than tying each dot to a specific weekday.
            HStack(spacing: 8) {
                ForEach(0..<7, id: \.self) { index in
                    Circle()
                        .fill(index < completed ? palette.strong : palette.soft)
                        .overlay(Circle().stroke(palette.muted.opacity(0.2), lineWidth: 1))
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fit)
                }
            }
        }
        .sectionCard(palette)
    }
}

struct CategoryView: View {
    @EnvironmentObject private var store: MovementStore
    @Environment(\.colorScheme) private var systemScheme
    let category: WorkoutCategory

    var body: some View {
        let palette = store.palette(system: systemScheme)

        List {
            Section {
                ForEach(category.subcategories) { subcategory in
                    NavigationLink(value: subcategory) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(subcategory.title)
                                .font(.headline)
                            Text("\(subcategory.workouts.count) workouts")
                                .font(.caption)
                                .foregroundStyle(palette.muted)
                        }
                        .padding(.vertical, 6)
                    }
                }
            } header: {
                Text("Smaller sections")
            }
        }
        .scrollContentBackground(.hidden)
        .background(palette.background)
        .navigationTitle(category.title)
    }
}

struct SubcategoryView: View {
    @EnvironmentObject private var store: MovementStore
    @Environment(\.colorScheme) private var systemScheme
    let subcategory: WorkoutSubcategory

    var body: some View {
        let palette = store.palette(system: systemScheme)

        List {
            Section {
                ForEach(subcategory.workouts) { workout in
                    NavigationLink(value: workout) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(workout.name)
                                .font(.headline)
                            HStack {
                                Label(workout.difficulty, systemImage: "speedometer")
                                Label(workout.materials, systemImage: "shippingbox.fill")
                            }
                            .font(.caption)
                            .foregroundStyle(palette.muted)
                        }
                        .padding(.vertical, 7)
                    }
                }
            } header: {
                Text("Pick one workout")
            } footer: {
                Text("Each workout opens on its own detail page with its own 360 view, instructions, and completion check.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(palette.background)
        .navigationTitle(subcategory.title)
    }
}

struct WorkoutDetailView: View {
    @EnvironmentObject private var store: MovementStore
    @Environment(\.colorScheme) private var systemScheme
    let workout: Workout

    var body: some View {
        let palette = store.palette(system: systemScheme)
        let prescription = WorkoutPlanEngine.prescription(for: workout, profile: store.profile)
        let completed = store.isCompletedToday(workout)

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Demonstration360View(workout: workout)
                    .frame(height: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 12) {
                    Text(workout.subcategory)
                        .font(.caption.weight(.bold))
                        .textCase(.uppercase)
                        .foregroundStyle(palette.gold)
                    Text(workout.name)
                        .font(.system(size: 34, design: store.aesthetic.headlineDesign).weight(store.aesthetic.headlineWeight))
                        .foregroundStyle(palette.ink)
                    HStack {
                        InfoPill(text: workout.difficulty, icon: "speedometer")
                        InfoPill(text: workout.materials, icon: "shippingbox.fill")
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Label("Your quiz-based target", systemImage: "target")
                        .font(.headline)
                        .foregroundStyle(palette.ink)
                    Text("\(prescription.sets) sets - \(prescription.reps)")
                        .font(.title3.weight(.black))
                        .foregroundStyle(palette.ink)
                    Text(prescription.note)
                        .foregroundStyle(palette.muted)
                }
                .sectionCard(palette)

                VStack(alignment: .leading, spacing: 10) {
                    Label("How to do it", systemImage: "figure.strengthtraining.traditional")
                        .font(.headline)
                        .foregroundStyle(palette.ink)
                    Text(workout.explanation)
                        .foregroundStyle(palette.muted)
                    Text("Form cue: \(workout.formCue)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.ink)
                }
                .sectionCard(palette)

                Button {
                    store.complete(workout)
                } label: {
                    Label(completed ? "Completed today" : "Mark this workout completed", systemImage: completed ? "checkmark.circle.fill" : "circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle(palette: palette))
                .disabled(completed)
            }
            .padding(18)
        }
        .background(palette.background.ignoresSafeArea())
        .navigationTitle(workout.name)
    }
}

struct Demonstration360View: View {
    @EnvironmentObject private var store: MovementStore
    @Environment(\.colorScheme) private var systemScheme
    let workout: Workout
    @State private var manualRotation: Double = 0

    var body: some View {
        let palette = store.palette(system: systemScheme)

        TimelineView(.animation) { timeline in
            let autoRotation = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 8) / 8 * 360
            let rotation = autoRotation + manualRotation

            ZStack {
                LinearGradient(colors: [palette.soft, palette.surface], startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle()
                    .stroke(palette.gold.opacity(0.28), lineWidth: 10)
                    .frame(width: 190, height: 190)
                Circle()
                    .trim(from: 0, to: 0.82)
                    .stroke(palette.gold, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 230, height: 230)
                    .rotationEffect(.degrees(rotation))
                PoseFigure(pose: workout.pose, rotation: rotation)
                    .frame(width: 180, height: 240)
                    .rotation3DEffect(.degrees(rotation), axis: (x: 0, y: 1, z: 0), perspective: 0.65)
                    .shadow(color: palette.strong.opacity(0.2), radius: 18, y: 10)

                VStack {
                    HStack {
                        Text("360 form view")
                            .font(.caption.weight(.bold))
                            .textCase(.uppercase)
                            .foregroundStyle(palette.gold)
                        Spacer()
                        Text("\(Int(rotation) % 360) deg")
                            .font(.caption.monospacedDigit().weight(.bold))
                            .foregroundStyle(palette.muted)
                    }
                    Spacer()
                    Text(workout.formCue)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.muted)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(palette.surface.opacity(0.9))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .padding(14)
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        manualRotation = Double(value.translation.width)
                    }
            )
        }
    }
}

struct PoseFigure: View {
    @EnvironmentObject private var store: MovementStore
    @Environment(\.colorScheme) private var systemScheme
    let pose: WorkoutPose
    let rotation: Double

    var body: some View {
        let palette = store.palette(system: systemScheme)
        let limb = limbAngles

        ZStack {
            Capsule()
                .fill(palette.strong)
                .frame(width: 42, height: bodyHeight)
                .offset(y: 28)
            Circle()
                .fill(palette.strong)
                .frame(width: 44, height: 44)
                .offset(y: -72)

            limbView(angle: limb.leftArm, length: 74, width: 12)
                .offset(x: -28, y: -12)
            limbView(angle: limb.rightArm, length: 74, width: 12)
                .offset(x: 28, y: -12)
            limbView(angle: limb.leftLeg, length: 88, width: 14)
                .offset(x: -14, y: 90)
            limbView(angle: limb.rightLeg, length: 88, width: 14)
                .offset(x: 14, y: 90)
        }
        .scaleEffect(x: max(0.62, abs(cos(rotation * .pi / 180))), y: 1)
    }

    private var bodyHeight: CGFloat {
        switch pose {
        case .plank, .pushUp, .deadBug, .bridge: return 36
        default: return 92
        }
    }

    private var limbAngles: (leftArm: Double, rightArm: Double, leftLeg: Double, rightLeg: Double) {
        let pulse = sin(rotation * .pi / 60) * 8
        switch pose {
        case .curl: return (-38 + pulse, 38 - pulse, -8, 8)
        case .hold: return (-8, 8, -6, 6)
        case .dip: return (-62, 62, -18, 18)
        case .overheadExtension: return (-150 + pulse, 150 - pulse, -6, 6)
        case .squat: return (-24, 24, -34, 34)
        case .stepUp: return (-28, 28, -58, 18)
        case .calfRaise: return (-8, 8, -4, 4)
        case .hinge: return (-18, 18, -12, 12)
        case .bridge: return (-74, 74, -68, 68)
        case .pushUp: return (-72, 72, -72, 72)
        case .press: return (-138 + pulse, 138 - pulse, -8, 8)
        case .row: return (-46 + pulse, 46 - pulse, -16, 16)
        case .fly: return (-82 + pulse, 82 - pulse, -16, 16)
        case .deadBug: return (-120, 120, -46, 46)
        case .plank: return (-70, 70, -78, 78)
        case .march: return (-40, 40, -52 + pulse, 22)
        case .reach: return (-146, 146, -28, 28)
        case .stretch: return (-104, 126, -70, 32)
        case .catCow: return (-48, 48, -48, 48)
        }
    }

    private func limbView(angle: Double, length: CGFloat, width: CGFloat) -> some View {
        Capsule()
            .fill(store.palette(system: systemScheme).primary)
            .frame(width: width, height: length)
            .rotationEffect(.degrees(angle), anchor: .top)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: MovementStore
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingDelete = false
    @State private var isDeletingAccount = false
    @State private var deleteError: String?

    var body: some View {
        let palette = store.palette(system: systemScheme)

        NavigationStack {
            Form {
                Section {
                    Picker("Color vibe", selection: Binding(
                        get: { store.theme },
                        set: { store.setTheme($0) }
                    )) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.rawValue).tag(theme)
                        }
                    }

                    Picker("Appearance", selection: Binding(
                        get: { store.appearance },
                        set: { newValue in
                            withAnimation(.easeInOut(duration: 0.35)) {
                                store.setAppearance(newValue)
                            }
                        }
                    )) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text("Appearance switches the whole app between light and dark backgrounds. Color vibe stays the same in both.")
                }

                Section {
                    AestheticSpotlightView()
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                } header: {
                    Text("Aesthetic")
                } footer: {
                    Text("This changes the feel of coaching, the dashboard emphasis, and the color intensity and font throughout the app.")
                }

                Section {
                    Toggle("Gentle reminders", isOn: Binding(get: { store.remindersEnabled }, set: { store.setReminders($0) }))
                    Toggle("Lenient rolling streak", isOn: Binding(get: { store.lenientStreaks }, set: { store.setLenientStreaks($0) }))
                }

                Section {
                    if let account = store.account {
                        HStack {
                            Text("Signed in with \(account.provider.label)")
                            Spacer()
                            Text(account.username)
                                .foregroundStyle(palette.muted)
                        }
                    }
                    Button("Log out") {
                        store.signOut()
                    }
                } header: {
                    Text("Account")
                }

                Section {
                    Button("Reset first-time quiz", role: .destructive) {
                        store.resetOnboarding()
                    }
                }

                if store.account != nil {
                    Section {
                        Button(role: .destructive) {
                            isConfirmingDelete = true
                        } label: {
                            if isDeletingAccount {
                                ProgressView()
                            } else {
                                Text("Delete Account")
                            }
                        }
                        .disabled(isDeletingAccount)
                    } footer: {
                        Text("Permanently deletes your account and all synced progress. This can't be undone.")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(palette.background)
            .navigationTitle("Settings")
            .confirmationDialog(
                "Delete your account? This permanently removes your account and all synced progress — it can't be undone.",
                isPresented: $isConfirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete Account", role: .destructive) {
                    Task {
                        isDeletingAccount = true
                        let error = await store.deleteAccount()
                        isDeletingAccount = false
                        if let error {
                            deleteError = error
                        } else {
                            dismiss()
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Couldn't delete account", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
                Button("OK") {}
            } message: {
                Text(deleteError ?? "")
            }
        }
        // The settings sheet is its own presentation, so it needs the forced
        // scheme applied here too — otherwise switching to Dark from a Light
        // device (or vice versa) would leave this sheet on the old mode.
        .preferredColorScheme(store.preferredColorScheme)
    }
}

struct InfoPill: View {
    @EnvironmentObject private var store: MovementStore
    @Environment(\.colorScheme) private var systemScheme
    let text: String
    let icon: String

    var body: some View {
        let palette = store.palette(system: systemScheme)
        Label(text, systemImage: icon)
            .font(.caption.weight(.bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(palette.soft)
            .clipShape(Capsule())
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    let palette: Palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.bold))
            .foregroundStyle(.white)
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(palette.strong.opacity(configuration.isPressed ? 0.82 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct IconButtonStyle: ButtonStyle {
    let palette: Palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.bold))
            .foregroundStyle(palette.ink)
            .frame(width: 44, height: 44)
            .background(configuration.isPressed ? palette.soft : palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

extension View {
    func sectionCard(_ palette: Palette) -> some View {
        self
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
