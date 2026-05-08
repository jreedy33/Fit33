import SwiftUI
import StoreKit
import AuthenticationServices

// MARK: - Tutorial Demo Data

enum TutorialDemoData {
    static var userName: String {
        UserManager.shared.currentUser?.name ?? "You"
    }

    static var userInitials: String {
        let name = userName
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    static var demoActiveChallenge: ActiveChallenge {
        ActiveChallenge(
            challengeId: UUID(),
            challengeType: "active_minutes",
            title: "30 Min Movement",
            description: "Be active for at least 30 minutes every day",
            dailyTarget: 30,
            totalTarget: nil,
            targetUnit: "minutes",
            startDate: Calendar.current.date(byAdding: .day, value: -4, to: Date()) ?? Date(),
            endDate: Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date(),
            durationDays: 7,
            daysElapsed: 4,
            daysRemaining: 3,
            status: "active",
            myTotalProgress: 135,
            myTodayProgress: 25,
            myDaysCompleted: 4,
            myCurrentStreak: 4,
            opponentId: UUID(),
            opponentName: "Alex M.",
            opponentUsername: "alexm",
            opponentPhotoUrl: nil,
            opponentTotalProgress: 110,
            opponentTodayProgress: 18,
            opponentDaysCompleted: 3,
            amWinning: true,
            amWinningToday: true
        )
    }

    static var demoCommunityChallenge: FeaturedCommunityChallenge {
        FeaturedCommunityChallenge(
            challengeId: UUID(),
            title: "5K Morning Walk",
            description: "Start every morning with 5,000 steps before noon.",
            emoji: "🚶",
            challengeType: "steps",
            dailyTarget: 5000,
            targetUnit: "steps",
            participantCount: 234,
            totalCompletions: 1820,
            joinCode: "WALK5K",
            inviteSlug: "walk-5k",
            isFeatured: true,
            isOfficial: true,
            isRecurring: true,
            category: "walking",
            createdBy: nil,
            creatorName: nil,
            creatorUsername: nil,
            alreadyJoined: false
        )
    }

    static var demoBreakfastMeals: [MealEntryData] {
        [
            MealEntryData(
                id: UUID(),
                foodName: "Protein Smoothie",
                quantity: 1,
                unit: "serving",
                calories: 320,
                protein: 28,
                carbs: 35,
                fat: 8,
                mealType: .breakfast,
                date: Date(),
                fdcId: 0
            ),
            MealEntryData(
                id: UUID(),
                foodName: "Overnight Oats",
                quantity: 1,
                unit: "bowl",
                calories: 280,
                protein: 12,
                carbs: 42,
                fat: 9,
                mealType: .breakfast,
                date: Date(),
                fdcId: 0
            )
        ]
    }
}

// MARK: - Tutorial Page Kind

enum TutorialPageKind: CaseIterable, Identifiable {
    case welcome
    case findFriends
    case autoWorkout
    case programs
    case challenges1v1
    case community
    case league
    case wearables
    case fuel
    case trial

    var id: Self { self }

    var title: String {
        switch self {
        case .welcome:        return "Welcome to"
        case .findFriends:    return "Find Your Friends"
        case .autoWorkout:    return "Smart Workouts"
        case .programs:       return "Multi-Week Programs"
        case .challenges1v1:  return "Challenge a Friend"
        case .community:      return "Join the Community"
        case .league:         return "Climb the League"
        case .wearables:      return "Sync Your Wearables"
        case .fuel:           return "Fuel & Hydrate"
        case .trial:          return "Unlock Everything"
        }
    }

    var subtitle: String {
        switch self {
        case .welcome:        return "Your intelligent fitness companion"
        case .findFriends:    return "Sync contacts, train together"
        case .autoWorkout:    return "Smart-built or fully custom"
        case .programs:       return "30-day transformations"
        case .challenges1v1:  return "Compete head-to-head"
        case .community:      return "Featured challenges, real people"
        case .league:         return "Duolingo-style weekly leagues"
        case .wearables:      return "WHOOP, Fitbit, Strava, Apple Health"
        case .fuel:           return "Macros, meals, hydration"
        case .trial:          return "Start your free trial"
        }
    }

    var description: String {
        switch self {
        case .welcome:
            return "Workouts that adapt to you, friends to compete with,\nand wearables that bring it all together."
        case .findFriends:
            return "We'll match contacts already on Fit33\nso you can challenge them in seconds."
        case .autoWorkout:
            return "Pick your time, muscles, and equipment\nfor a Smart Workout — or build from 6,000+ exercises."
        case .programs:
            return "Progressive 7, 14, 21, or 30-day programs\nbuilt around your goals and schedule."
        case .challenges1v1:
            return "Challenge friends 1v1 or in groups.\nLive scoreboards, daily stakes, real accountability."
        case .community:
            return "Join featured community challenges.\nThousands of athletes pushing the same goal."
        case .league:
            return "Train every week, climb the ranks.\nTop finishers get promoted. Bottom drops down."
        case .wearables:
            return "Connect your favorite apps for a more\npersonalized Fit33 experience."
        case .fuel:
            return "Log meals with USDA + label OCR.\nStay hydrated with one-tap water tracking."
        case .trial:
            return "Unlimited Smart Workouts, advanced analytics,\ncustom meal plans, and more."
        }
    }

    var accent: LinearGradient {
        switch self {
        case .welcome:        return .ds_logoBlueAccent
        case .findFriends:    return .ds_socialAccent
        case .autoWorkout:    return .ds_primaryAccent
        case .programs:       return .ds_successAccent
        case .challenges1v1:  return .ds_socialAccent
        case .community:      return .ds_socialAccent
        case .league:         return .ds_energyAccent
        case .wearables:      return .ds_successAccent
        case .fuel:           return .ds_energyAccent
        case .trial:          return .ds_primaryAccent
        }
    }

    /// Single accent color (used for orb tint, sleekCard accent, page-indicator pill).
    var accentColor: Color {
        switch self {
        case .welcome, .autoWorkout, .trial: return .blue
        case .findFriends, .challenges1v1, .community: return .cyan
        case .programs, .wearables: return Color(red: 0.2, green: 0.7, blue: 0.3)
        case .league, .fuel: return .orange
        }
    }

    /// 0...1 phase used by the rotating logo-blue gradient that paints the
    /// onboarding navigation chrome (page indicator, Continue / Get Started
    /// buttons) AND every page's H1 title. Page 0 (welcome) is phase 0 —
    /// vertical top→bottom — so the welcome step's title + CTA match the
    /// "33" of the Fit33 logo exactly. Each subsequent page rotates the
    /// gradient by `1 / (pages - 1)` of a full revolution so the gradient
    /// appears to "scroll" as the user swipes step-by-step.
    var gradientPhase: Double {
        let all = TutorialPageKind.allCases
        guard all.count > 1, let idx = all.firstIndex(of: self) else { return 0 }
        return Double(idx) / Double(all.count - 1)
    }
}

// MARK: - Welcome Tutorial View

struct WelcomeTutorialView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var isPresented: Bool

    @State private var currentPage = 0
    @State private var animateContent = false

    private let pages: [TutorialPageKind] = TutorialPageKind.allCases

    private let selectionFeedback = UISelectionFeedbackGenerator()

    var body: some View {
        ZStack {
            AnimatedOrbBackground.onboarding(colorScheme: colorScheme)
                .ignoresSafeArea(.all)

            VStack(spacing: 0) {
                // Skip pill
                HStack {
                    Spacer()
                    if currentPage < pages.count - 1 {
                        Button(action: skipTutorial) {
                            Text("Skip")
                                .font(.ds_labelMedium)
                                .foregroundColor(.adaptiveSecondaryText)
                                .padding(.horizontal, Spacing.md)
                                .padding(.vertical, Spacing.xs)
                                .background(
                                    Capsule()
                                        .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                                )
                        }
                        .accessibilityLabel("Skip tutorial")
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm)

                // Pages
                TabView(selection: $currentPage) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, kind in
                        TutorialPageView(
                            kind: kind,
                            isActive: currentPage == index,
                            animateContent: animateContent,
                            isPresented: $isPresented
                        )
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .background(.clear)
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: currentPage)

                // Page indicator + primary CTA
                VStack(spacing: Spacing.lg) {
                    pageIndicator

                    if pages[currentPage] == .trial {
                        EmptyView() // Trial page hosts its own CTA
                    } else if currentPage == pages.count - 1 {
                        primaryButton(title: "Get Started", icon: "arrow.right", action: completeTutorial)
                    } else {
                        secondaryButton(title: "Continue", icon: "chevron.right", action: nextPage)
                    }
                }
                .padding(.bottom, Spacing.xl + Spacing.lg)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6).delay(0.2)) {
                animateContent = true
            }
        }
        .onChange(of: currentPage) { _, _ in
            selectionFeedback.selectionChanged()
        }
    }

    // MARK: - Subviews

    private var pageIndicator: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(0..<pages.count, id: \.self) { index in
                Capsule()
                    .fill(
                        index == currentPage
                            ? AnyShapeStyle(LinearGradient.ds_logoBlueAccent(phase: pages[currentPage].gradientPhase))
                            : AnyShapeStyle(Color.gray.opacity(0.25))
                    )
                    .frame(width: index == currentPage ? 28 : 8, height: 8)
                    .animation(.spring(response: 0.35, dampingFraction: 0.75), value: currentPage)
            }
        }
    }

    private func primaryButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                Text(title).font(.ds_labelLarge)
                Image(systemName: icon).font(.ds_bodyMedium.weight(.bold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(
                Capsule()
                    .fill(LinearGradient.ds_logoBlueAccent(phase: pages[currentPage].gradientPhase))
                    .shadow(color: Self.logoBlueShadowColor.opacity(0.5), radius: 16, x: 0, y: 8)
            )
        }
        .scaleButtonStyle(.standard, withHaptic: true)
        .padding(.horizontal, Spacing.xl)
        .accessibilityLabel(title)
    }

    private func secondaryButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                Text(title).font(.ds_labelLarge)
                Image(systemName: icon).font(.ds_bodySmall.weight(.bold))
            }
            .foregroundStyle(LinearGradient.ds_logoBlueAccent(phase: pages[currentPage].gradientPhase))
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(
                Capsule()
                    .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
            )
            .overlay(
                Capsule().stroke(
                    LinearGradient.ds_logoBlueAccent(phase: pages[currentPage].gradientPhase),
                    lineWidth: 2
                )
            )
        }
        .scaleButtonStyle(.standard, withHaptic: true)
        .padding(.horizontal, Spacing.xl)
        .accessibilityLabel(title)
    }

    /// Static brand-blue color used for the primary CTA's drop shadow. We
    /// intentionally pin this to a single color (the mid-point of the logo
    /// blue gradient) rather than rotating it with the page — the shadow is
    /// always "down/back" and reads as a constant brand glow under the CTA.
    private static let logoBlueShadowColor = Color(red: 0.20, green: 0.55, blue: 0.95)

    // MARK: - Actions

    private func nextPage() {
        HapticManager.tap()
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            currentPage += 1
        }
    }

    private func skipTutorial() {
        HapticManager.tap()
        completeTutorial()
    }

    private func completeTutorial() {
        HapticManager.tap()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            isPresented = false
        }
    }
}

// MARK: - Tutorial Page View

struct TutorialPageView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let kind: TutorialPageKind
    let isActive: Bool
    let animateContent: Bool
    @Binding var isPresented: Bool

    @State private var heroAnimation = false
    @State private var hasBeenActive = false

    private var shouldDisableMotion: Bool {
        ProcessInfo.processInfo.isLowPowerModeEnabled || reduceMotion
    }

    var body: some View {
        GeometryReader { geometry in
            // Two steps own bespoke layouts that anchor their hero
            // content directly below the parent's Skip-pill chrome
            // (matching button position) instead of using the generic
            // hero-band sizing path:
            //   • Auto-Workout — Custom/Auto buttons + scrollable card
            //     list + title block (`autoWorkoutLayout`).
            //   • Challenges 1v1 — slim hero card + dashboard-style
            //     active challenge widget + title block
            //     (`challengesLayout`).
            // Branching here keeps the standard path untouched.
            switch kind {
            case .autoWorkout:
                self.autoWorkoutLayout(geometry)
            case .challenges1v1:
                self.challengesLayout(geometry)
            default:
                self.standardLayout(geometry)
            }
        }
        .onAppear {
            if isActive { hasBeenActive = true }
            startHeroAnimation()
        }
        .onChange(of: isActive) { _, active in
            if active {
                hasBeenActive = true
                startHeroAnimation()
            }
        }
    }

    // MARK: - Standard layout (every step except Auto-Workout)

    @ViewBuilder
    private func standardLayout(_ geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
                if kind == .welcome {
                    // Anchor the "Welcome to" headline ABOVE the hero band so
                    // it stays in a fixed position regardless of how the
                    // logo+glow inside the hero scales or animates. (Embedding
                    // it inside the hero VStack caused it to get pushed up
                    // off-screen when the glow circle exceeded `heroMaxHeight`.)
                    Text(kind.title)
                        .font(.ds_displayMedium)
                        .foregroundStyle(LinearGradient.ds_logoBlueAccent(phase: kind.gradientPhase))
                        .tracking(-0.5)
                        .multilineTextAlignment(.center)
                        .padding(.top, Spacing.lg)
                        .padding(.bottom, Spacing.sm)
                        .opacity(animateContent ? 1 : 0)
                        .offset(y: animateContent ? 0 : -10)
                        .animation(.easeOut(duration: 0.5).delay(0.10), value: animateContent)
                } else {
                    Spacer(minLength: Spacing.md)
                }

            Group {
                if hasBeenActive {
                    heroView
                        .scaleEffect(animateContent ? 1 : 0.85)
                        .opacity(animateContent ? 1 : 0)
                } else {
                    Color.clear
                }
            }
            .frame(maxWidth: .infinity)
            .frame(maxHeight: heroMaxHeight(geometry))

            Spacer(minLength: Spacing.md)

            copyBlock
                .padding(.horizontal, Spacing.md)

            Spacer(minLength: Spacing.lg)
        }
    }

    // MARK: - Auto-Workout layout (custom)
    //
    // Three vertical bands stacked top→bottom in a `VStack`:
    //
    //   1. BUTTONS — the two full-size home-tab quick actions (Custom +
    //      Auto). Anchored just below the parent's Skip pill so they sit
    //      cleanly below the header edge.
    //   2. HARD EDGE — a hairline divider with a soft drop shadow. The
    //      `ScrollView` sits flush below this edge, so when the user
    //      scrolls cards UP they get hard-clipped at this line — the
    //      visual "the card slides behind the buttons" effect the design
    //      brief asks for.
    //   3. SCROLLABLE CARDS — bounded `ScrollView` of mock exercise rows.
    //      A bottom-only fade mask dissolves the last visible card into
    //      the title block underneath. Because the `ScrollView` is
    //      bounded by the layout, cards can never physically extend into
    //      the title area, so the title text never has cards bleeding
    //      through it.
    //   4. COPY BLOCK — same `copyBlock` every other step uses (title +
    //      subtitle + description). Sits flush below the scroll view's
    //      faded bottom edge.
    @ViewBuilder
    private func autoWorkoutLayout(_ geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            // Tiny breathing gap below the parent's Skip pill row so the
            // buttons aren't kissing the header edge.
            Spacer().frame(height: Spacing.xs)

            // BUTTONS — full home-tab size, no `compact` flag.
            HStack(spacing: Spacing.sm) {
                DepthQuickActionCard(
                    title: "Custom Workout",
                    subtitle: "Build your own",
                    icon: "plus.circle.fill",
                    gradient: [Color.blue, Color.cyan],
                    action: {}
                )

                DepthQuickActionCard(
                    title: "Auto Workout",
                    subtitle: "Auto-generated routine",
                    icon: "dumbbell.fill",
                    gradient: [Color.purple, Color.pink],
                    action: {}
                )
            }
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.md)
            .opacity(animateContent ? 1 : 0)
            .offset(y: animateContent ? 0 : 12)
            .animation(.easeOut(duration: 0.5).delay(0.10), value: animateContent)

            // HARD EDGE — hairline + downward shadow that the cards
            // appear to scroll up behind. Shadow gives the line depth so
            // the user reads it as "this is a clipping edge", not a
            // separator.
            Rectangle()
                .fill(colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.10))
                .frame(height: 1)
                .padding(.horizontal, Spacing.md)
                .shadow(
                    color: Color.black.opacity(colorScheme == .dark ? 0.55 : 0.18),
                    radius: 5,
                    x: 0,
                    y: 4
                )

            // SCROLLABLE CARDS — flexible-height region between the hard
            // edge and the title block. The `ScrollView` itself owns its
            // top-edge clipping; the bottom edge gets a gradient mask so
            // the bottom-most visible card dissolves cleanly into the
            // title block beneath. `.scrollIndicators(.visible)` keeps
            // the scroll bar persistently visible so the user knows the
            // list is scrollable on first appearance (default
            // `.automatic` only flashes during active scrolling, which
            // most users miss in onboarding).
            ScrollView(.vertical) {
                VStack(spacing: Spacing.xs) {
                    ForEach(
                        Array(Self.autoWorkoutSampleExercises.enumerated()),
                        id: \.offset
                    ) { _, exercise in
                        TutorialMockExerciseRow(exercise: exercise)
                    }

                    // Overscroll padding so the user can pull the bottom
                    // rows fully into view before the fade hides them.
                    Color.clear.frame(height: 60)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm)
            }
            .scrollIndicators(.visible)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0.0),
                        .init(color: .black, location: 0.62),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .opacity(animateContent ? 1 : 0)
            .animation(.easeOut(duration: 0.5).delay(0.20), value: animateContent)

            // TITLE BLOCK — same `copyBlock` every other step uses. No
            // explicit solid background needed because the `ScrollView`
            // above is bounded and its bottom mask already fades cards
            // to fully transparent before they could reach this band, so
            // nothing physically overlaps the title text.
            copyBlock
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm)

            Spacer(minLength: Spacing.lg)
        }
    }

    // MARK: - Challenges 1v1 layout (custom)
    //
    // Anchors a slim hero card + a dashboard-style active-challenge
    // widget directly below the parent's Skip-pill chrome — same
    // `Spacing.xs` breathing gap the Auto-Workout step uses so the top
    // card sits at the SAME y-position as the Custom/Auto buttons on
    // the Auto-Workout page. No `Spacer(minLength: Spacing.md)` above
    // the hero (the standard layout's "extra background" the user
    // asked us to trim out), and a tight `Spacing.xs` gap between the
    // last card and the title block keeps everything visually compact.
    @ViewBuilder
    private func challengesLayout(_ geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            Spacer().frame(height: Spacing.xs)

            Group {
                if hasBeenActive {
                    TutorialChallengeHero(kind: kind, isAnimating: heroAnimation)
                        .scaleEffect(animateContent ? 1 : 0.85)
                        .opacity(animateContent ? 1 : 0)
                } else {
                    Color.clear
                }
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: Spacing.xs)

            copyBlock
                .padding(.horizontal, Spacing.md)

            Spacer(minLength: Spacing.md)
        }
    }

    // MARK: - Auto-Workout sample data
    //
    // Names match the canonical exercise names in
    // `Fit33/Resources/exercises.json` (and the Supabase
    // `video_mappings` table) EXACTLY. That's the lookup key
    // `VideoStreamingService.getVideoURL(for:)` uses (case-insensitive
    // match against `genderVideoCache`) — and the cache that
    // `ExercisePosterRingIcon` consults is gender-aware
    // (`GenderFilterService.shared.preferredGender`), so male users see
    // the male glyphs and female users see the female glyphs, exactly
    // like the Exercises tab.
    //
    // Each name was verified against `exercises.json` before being added
    // here — using a name that doesn't exist as a canonical key (e.g.
    // "Leg Press" instead of "Lever Seated Leg Press") makes the cache
    // lookup miss silently and the card falls back to the SF Symbol
    // forever, which is the bug the user just reported.
    //
    // 8 rows is enough that even on iPhone 16 Pro Max at least one row
    // sits below the fold, so scrollability is discoverable.
    private static let autoWorkoutSampleExercises: [TutorialMockExerciseRow.SampleExercise] = [
        .init(
            name: "Barbell Full Squat",
            category: "Legs",
            equipment: "Barbell",
            fallbackSymbol: "figure.strengthtraining.traditional"
        ),
        .init(
            name: "Barbell Romanian Deadlift",
            category: "Legs",
            equipment: "Barbell",
            fallbackSymbol: "figure.strengthtraining.functional"
        ),
        .init(
            name: "Barbell Lunge",
            category: "Legs",
            equipment: "Barbell",
            fallbackSymbol: "figure.walk"
        ),
        .init(
            name: "Barbell Hip Thrust",
            category: "Legs",
            equipment: "Barbell",
            fallbackSymbol: "figure.strengthtraining.functional"
        ),
        .init(
            name: "Barbell Front Squat",
            category: "Legs",
            equipment: "Barbell",
            fallbackSymbol: "figure.strengthtraining.traditional"
        ),
        .init(
            name: "Dumbbell Goblet Squat",
            category: "Legs",
            equipment: "Dumbbell",
            fallbackSymbol: "figure.strengthtraining.traditional"
        ),
        .init(
            name: "Lever Seated Leg Press",
            category: "Legs",
            equipment: "Machine",
            fallbackSymbol: "figure.strengthtraining.traditional"
        ),
        .init(
            name: "Lever Lying Leg Curl",
            category: "Legs",
            equipment: "Machine",
            fallbackSymbol: "figure.strengthtraining.traditional"
        )
    ]

    // MARK: - Hero

    @ViewBuilder
    private var heroView: some View {
        switch kind {
        case .welcome:
            TutorialWelcomeHero(kind: kind, isAnimating: heroAnimation)
        case .findFriends:
            TutorialFindFriendsHero(kind: kind, isAnimating: heroAnimation)
        case .autoWorkout:
            // The Auto-Workout step short-circuits the hero / copy layout
            // entirely (see `autoWorkoutLayout`), so this branch is never
            // reached at runtime. Kept as `EmptyView` only to satisfy the
            // exhaustive switch.
            EmptyView()
        case .programs:
            TutorialProgramHero(kind: kind, isAnimating: heroAnimation)
        case .challenges1v1:
            // Like Auto-Workout, the 1v1 Challenges step uses its own
            // bespoke layout (`challengesLayout`) that anchors the hero
            // directly below the Skip-pill chrome and never goes through
            // the generic hero-band sizing path.
            EmptyView()
        case .community:
            TutorialCommunityHero(kind: kind, isAnimating: heroAnimation)
        case .league:
            TutorialLeagueHero(kind: kind, isAnimating: heroAnimation)
        case .wearables:
            TutorialConnectIntegrationsView(kind: kind)
        case .fuel:
            TutorialFuelCard(kind: kind, isAnimating: heroAnimation)
        case .trial:
            TutorialTrialCTA(kind: kind, isAnimating: heroAnimation, isPresented: $isPresented)
        }
    }

    // MARK: - Copy

    private var copyBlock: some View {
        VStack(spacing: 0) {
            if kind != .welcome { // Welcome shows logo + anchored title above hero
                // Every step's H1 title shares the same logo-blue gradient as
                // the navigation chrome (page indicator + CTAs), with the
                // gradient angle phase-shifted per step so the gradient
                // appears to scroll as the user swipes through onboarding.
                // (Each page's `kind.accent` is still used by its hero
                // illustration to keep the per-step identity color.)
                Text(kind.title)
                    .font(.ds_displayMedium)
                    .foregroundStyle(LinearGradient.ds_logoBlueAccent(phase: kind.gradientPhase))
                    .tracking(-0.5)
                    .multilineTextAlignment(.center)
                    .opacity(animateContent ? 1 : 0)
                    .offset(y: animateContent ? 0 : 20)
                    .padding(.bottom, Spacing.xs)
            }

            Text(kind.subtitle)
                .font(.ds_labelLarge)
                .foregroundColor(.adaptiveSecondaryText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(animateContent ? 1 : 0)
                .offset(y: animateContent ? 0 : 15)
                .padding(.bottom, Spacing.sm)

            Text(kind.description)
                .font(.ds_bodyRegular)
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.65) : Color.black.opacity(0.55))
                .multilineTextAlignment(.center)
                .lineSpacing(5)
                .padding(.horizontal, Spacing.xl)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(animateContent ? 1 : 0)
                .offset(y: animateContent ? 0 : 10)
        }
        .animation(.easeOut(duration: 0.5).delay(0.15), value: animateContent)
    }

    // MARK: - Layout helpers

    private func heroMaxHeight(_ geometry: GeometryProxy) -> CGFloat {
        switch kind {
        // Welcome step's title is rendered as a separate element ABOVE the
        // hero band (see `body`), so the hero band itself only needs to fit
        // the logo + radial glow — slightly smaller share of the screen than
        // the trial step which still hosts its own internal title + CTA.
        case .welcome:                            return geometry.size.height * 0.40
        case .trial:                              return geometry.size.height * 0.46
        case .wearables:                          return geometry.size.height * 0.50
        // Community step renders the live `CommunityLeaderboardWidget` once
        // the user joins from this screen — needs more vertical room than the
        // discovery card so the mini-leaderboard rows aren't clipped.
        case .community:                          return geometry.size.height * 0.52
        // Find-Friends renders a 3×3 grid of real PYMK-ranked suggestions
        // so the user can quick-add inline — needs more height than the old
        // 5-circle decorative cluster.
        case .findFriends:                        return geometry.size.height * 0.48
        // Challenges 1v1 step uses its own bespoke layout
        // (`challengesLayout`) — anchors the hero directly below the
        // Skip-pill chrome rather than centering inside a hero band —
        // so this value is unused for that case. Kept as a placeholder
        // so the switch is exhaustive.
        case .challenges1v1:                      return geometry.size.height * 0.58
        case .programs, .fuel, .league:           return geometry.size.height * 0.38
        // Auto-Workout step uses its own bespoke layout (`autoWorkoutLayout`)
        // and never goes through the hero-band sizing path, so this value
        // is unused for that case. Kept as a placeholder so the switch is
        // exhaustive.
        case .autoWorkout:                        return geometry.size.height * 0.50
        }
    }

    private func startHeroAnimation() {
        guard !shouldDisableMotion else { return }
        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
            heroAnimation = true
        }
    }
}

// MARK: - Welcome Hero

struct TutorialWelcomeHero: View {
    let kind: TutorialPageKind
    let isAnimating: Bool

    var body: some View {
        // Hero is JUST the logo + glow. The "Welcome to" title is rendered
        // separately above the hero band by `TutorialPageView` so it stays
        // anchored regardless of how this ZStack scales/animates. Sizing
        // here is tuned to fit cleanly inside the welcome band's
        // `heroMaxHeight = 0.40 * geometry.height` on every iPhone class
        // (SE → Pro Max) without overflowing into the title or copy slots.
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [kind.accentColor.opacity(0.35), Color.clear],
                        center: .center, startRadius: 30, endRadius: 140
                    )
                )
                .frame(width: 260, height: 260)
                .blur(radius: 30)
                .scaleEffect(isAnimating ? 1.06 : 1.0)

            // Use the hero-only `fit33-logo-hero` asset (the same wordmark
            // cropped tight to the visible glyphs, ~3.35:1). Other surfaces
            // (Auth, Dashboard header) keep using `fit33-logo` (1024×1024
            // with built-in transparent padding) — those layouts depend on
            // that intrinsic padding to look right.
            Image("fit33-logo-hero")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 280, maxHeight: 100)
                .shadow(color: kind.accentColor.opacity(0.5), radius: 30, x: 0, y: 12)
                .scaleEffect(isAnimating ? 1.02 : 0.98)
                .offset(y: isAnimating ? -4 : 4)
        }
    }
}

// MARK: - Find Friends Hero

struct TutorialFindFriendsHero: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var contactsService = ContactsService.shared
    @ObservedObject private var friendService = FriendService.shared
    @ObservedObject private var orientation = OrientationManager.shared
    let kind: TutorialPageKind
    let isAnimating: Bool

    @State private var isWorking = false
    @State private var didFetchPYMK = false
    /// Tutorial-local optimistic state. Avoid mutating `friendService.sentRequests`
    /// directly — the service refreshes from server on its own cadence and we
    /// don't want UI flicker mid-animation.
    @State private var sentIds: Set<UUID> = []
    @State private var loadingIds: Set<UUID> = []
    @State private var failedIds: Set<UUID> = []

    private var matchedCount: Int { contactsService.suggestedFriends.count }
    private var hasSynced: Bool {
        contactsService.canAccessContacts && contactsService.hasCheckedContacts
    }

    /// Top-of-friends-tab uses `allSuggestions(...)` which sorts by:
    /// (1) is friend-of-friend, (2) has photo, (3) mutual_friend_count DESC,
    /// (4) name. That is the "smart interaction" ranking the user asked for —
    /// we mirror it exactly so the tutorial grid agrees with the in-app strip.
    private var rankedSuggestions: [SuggestedFriend] {
        let friendIds = Set(friendService.friends.map { $0.friendId })
        let serverSent = Set(friendService.sentRequests.map { $0.toUserId })
        return contactsService.allSuggestions(
            excludingFriendIds: friendIds,
            excludingSentIds: serverSent
        )
    }

    /// Hard ceiling on rows × cols. 3 cols × 3 rows = 9 slots on standard;
    /// 2 cols × 3 rows = 6 on compact (iPhone SE-class). The actual column
    /// count below is clamped down by `displayedSuggestions.count` so the
    /// grid never renders an orphan-only row.
    private var maxColumnCap: Int {
        orientation.deviceTier == .compact ? 2 : 3
    }
    private var maxQuickAddSlots: Int {
        maxColumnCap * 3
    }

    /// Suggestions actually rendered in the grid (capped at `maxQuickAddSlots`).
    /// Shared between `gridColumnCount` (drives column layout) and
    /// `quickAddGrid` (drives the ForEach), so the column math always agrees
    /// with the row count even mid-frame.
    private var displayedSuggestions: [SuggestedFriend] {
        Array(rankedSuggestions.prefix(maxQuickAddSlots))
    }

    /// Smart column count — picks the layout that produces the cleanest
    /// rectangle for the friends-on-Fit33 count, capped at the device tier:
    ///   1 → 1 col (single avatar)            5 → 3 cols (3 + 2)
    ///   2 → 2 cols                           6 → 3 cols (3 × 2)
    ///   3 → 3 cols (single row, or 2 cols    7 → 3 cols (3 + 3 + 1)
    ///       on compact)                      8 → 3 cols (3 + 3 + 2)
    ///   4 → 2 cols (2 × 2 — special-case so  9 → 3 cols (3 × 3)
    ///       we don't get an ugly 3 + 1)
    /// On compact tier (max 2 cols) the same rules apply but capped at 2.
    private var gridColumnCount: Int {
        let n = displayedSuggestions.count
        guard n > 0 else { return maxColumnCap }
        if n == 4 { return min(2, maxColumnCap) }
        return min(n, maxColumnCap)
    }

    var body: some View {
        VStack(spacing: Spacing.sm) {
            if hasSynced && !displayedSuggestions.isEmpty {
                quickAddGrid
            } else if contactsService.permissionDenied {
                statusCard { deniedState }
            } else if hasSynced && displayedSuggestions.isEmpty {
                statusCard { emptyState }
            } else {
                statusCard { pendingState }
            }
        }
        .padding(.horizontal, Spacing.md)
        .onAppear { triggerPYMKFetchIfNeeded() }
    }

    // MARK: - Quick-add grid

    private var quickAddGrid: some View {
        VStack(spacing: Spacing.md) {
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: Spacing.md),
                    count: gridColumnCount
                ),
                spacing: Spacing.md
            ) {
                ForEach(displayedSuggestions) { suggestion in
                    TutorialFriendQuickAddCircle(
                        suggestion: suggestion,
                        isSent: sentIds.contains(suggestion.userId),
                        isLoading: loadingIds.contains(suggestion.userId),
                        hasFailed: failedIds.contains(suggestion.userId),
                        onTap: { sendRequest(to: suggestion) }
                    )
                    .scaleEffect(isAnimating ? 1.01 : 1.0)
                }
            }
            .frame(maxWidth: gridMaxWidth)

            // Caption sits BELOW the grid so it acts as a footer / context
            // line rather than a banner, and so the layout reads top-down:
            // avatars first, then "21 on Fit33 — tap to add".
            HStack(spacing: Spacing.xxs) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.ds_caption)
                    .foregroundColor(.green)
                Text("\(matchedCount) on Fit33 — tap to add")
                    .font(.ds_labelMedium)
                    .foregroundColor(.adaptiveSecondaryText)
            }
        }
    }

    /// Width budget for the LazyVGrid. Sized with extra slack per column so
    /// the cells breathe (vs. hugging a tight 72pt-per-cell minimum) — the
    /// avatar inside is fixed at 60pt, so the surplus shows up as horizontal
    /// padding around each circle, which is what "spaced out more" really
    /// means visually.
    private var gridMaxWidth: CGFloat? {
        switch gridColumnCount {
        case 3: return 340
        case 2: return 240
        case 1: return 120
        default: return nil
        }
    }

    // MARK: - Status card

    private func statusCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: Spacing.sm) {
            avatarCluster

            VStack(spacing: Spacing.sm) { content() }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.md)
                .frame(maxWidth: 360)
                .adaptiveSleekCard(cornerRadius: CornerRadius.xl, accentColor: kind.accentColor)
        }
    }

    private var avatarCluster: some View {
        HStack(spacing: -12) {
            ForEach(0..<5, id: \.self) { i in
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [
                                Color.blue.opacity(0.8 - Double(i) * 0.1),
                                Color.cyan.opacity(0.7 - Double(i) * 0.1)
                            ],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 44, height: 44)
                    Image(systemName: "person.fill")
                        .font(.ds_bodyMedium)
                        .foregroundColor(.white.opacity(0.95))
                }
                .overlay(Circle().stroke(Color.cardBackground, lineWidth: 2))
                .scaleEffect(isAnimating ? 1.02 : 1.0)
                .offset(y: isAnimating ? CGFloat(i % 2 == 0 ? -2 : 2) : 0)
            }
        }
    }

    // MARK: - States

    private var pendingState: some View {
        VStack(spacing: Spacing.sm) {
            Text("Find friends already on Fit33")
                .font(.ds_heading3)
                .foregroundColor(.adaptiveText)
                .multilineTextAlignment(.center)

            Text("We securely match emails and phone numbers you already have. Nothing is shared with anyone.")
                .font(.ds_bodySmall)
                .foregroundColor(.adaptiveSecondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: requestContacts) {
                HStack(spacing: Spacing.xs) {
                    if isWorking {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.ds_labelLarge)
                    }
                    Text(isWorking ? "Syncing…" : "Sync Contacts")
                        .font(.ds_labelLarge)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.sm)
                .background(Capsule().fill(kind.accent))
            }
            .scaleButtonStyle(.standard, withHaptic: true)
            .disabled(isWorking)
            .accessibilityLabel("Sync contacts to find friends")

            Text("You can also do this anytime in Settings.")
                .font(.ds_caption)
                .foregroundColor(.adaptiveSecondaryText)
        }
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.ds_heading3)
                    .foregroundColor(.green)
                Text("Contacts synced")
                    .font(.ds_heading3)
                    .foregroundColor(.adaptiveText)
            }
            Text("No matches yet — invite some friends from the Social tab.")
                .font(.ds_bodyRegular)
                .foregroundColor(.adaptiveSecondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var deniedState: some View {
        VStack(spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.ds_heading3)
                    .foregroundColor(.orange)
                Text("Contact access denied")
                    .font(.ds_heading3)
                    .foregroundColor(.adaptiveText)
            }
            Text("Enable contacts in Settings → Fit33 to find friends here.")
                .font(.ds_bodySmall)
                .foregroundColor(.adaptiveSecondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: openSystemSettings) {
                Text("Open Settings")
                    .font(.ds_labelLarge)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.sm)
                    .background(Capsule().fill(kind.accent))
            }
            .scaleButtonStyle(.standard, withHaptic: true)
        }
    }

    // MARK: - Actions

    private func requestContacts() {
        guard !isWorking else { return }
        isWorking = true
        Task { @MainActor in
            let granted = await contactsService.requestAccess()
            if granted, !contactsService.hasCheckedContacts {
                await contactsService.fetchContactsAndFindFriends()
            }
            isWorking = false
            triggerPYMKFetchIfNeeded()
        }
    }

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    /// Without PYMK enrichment, `allSuggestions` can't compute `isMutual` /
    /// `mutualFriendCount` so the ranking degrades to "has photo + name" —
    /// we want the smart FoF boost. Fire-and-forget on first appear.
    private func triggerPYMKFetchIfNeeded() {
        guard !didFetchPYMK,
              hasSynced,
              SupabaseManager.shared.isAuthenticated else { return }
        didFetchPYMK = true
        Task { @MainActor in
            await contactsService.fetchPeopleYouMayKnow()
        }
    }

    @MainActor
    private func sendRequest(to suggestion: SuggestedFriend) {
        guard !sentIds.contains(suggestion.userId),
              !loadingIds.contains(suggestion.userId) else { return }

        failedIds.remove(suggestion.userId)
        loadingIds.insert(suggestion.userId)
        HapticManager.impact(.medium)

        Task { @MainActor in
            let success = await FriendService.shared.sendFriendRequest(toUserId: suggestion.userId)
            loadingIds.remove(suggestion.userId)
            if success {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                    _ = sentIds.insert(suggestion.userId)
                }
                HapticManager.notification(.success)
                AppLogger.info(
                    "[TUTORIAL] Friend request sent to \(suggestion.displayName)",
                    category: .social
                )
            } else {
                failedIds.insert(suggestion.userId)
                HapticManager.notification(.error)
                AppLogger.error(
                    "[TUTORIAL] Failed to send friend request to \(suggestion.displayName)",
                    category: .social
                )
            }
        }
    }
}

// MARK: - Tutorial Friend Quick-Add Circle
//
// Visual twin of `FriendsSuggestionCircle` (Friends-tab top strip) but with
// inline-send semantics — tap fires `sendFriendRequest` directly instead of
// opening a profile sheet, which would interrupt the tutorial flow.

private struct TutorialFriendQuickAddCircle: View {
    let suggestion: SuggestedFriend
    let isSent: Bool
    let isLoading: Bool
    let hasFailed: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: {
            guard !isSent && !isLoading else { return }
            onTap()
        }) {
            VStack(spacing: 4) {
                ZStack {
                    CachedFriendPhoto(
                        friendId: suggestion.userId.uuidString,
                        photoUrl: suggestion.profilePhotoUrl,
                        name: suggestion.name ?? suggestion.username ?? "?",
                        size: 56,
                        showGradientRing: false,
                        gradientColors: [.blue.opacity(0.6), .cyan.opacity(0.4)]
                    )

                    if isLoading {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 56, height: 56)
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.8)
                    } else if isSent {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 56, height: 56)
                        VStack(spacing: 1) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.ds_heading3)
                                .foregroundColor(.green)
                            Text("Sent")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.green)
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(width: 60, height: 60)
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: isSent
                                    ? [.green.opacity(0.6), .green.opacity(0.3)]
                                    : [.blue.opacity(0.5), .cyan.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                        .frame(width: 62, height: 62)
                )
                .overlay(alignment: .bottomTrailing) {
                    if !isSent && !isLoading {
                        ZStack {
                            Circle()
                                .fill(Color(.systemBackground))
                                .frame(width: 20, height: 20)

                            Image(systemName: hasFailed ? "exclamationmark.circle.fill" : "plus.circle.fill")
                                .font(.ds_bodySmall)
                                .foregroundStyle(
                                    hasFailed
                                        ? AnyShapeStyle(Color.orange)
                                        : AnyShapeStyle(LinearGradient(
                                            colors: [.blue, .cyan],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ))
                                )
                        }
                        .offset(x: 2, y: 2)
                    }
                }

                Text(displayFirstName)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(isSent ? .green : .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(width: 72)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            isSent
                ? "Friend request sent to \(suggestion.displayName)"
                : "Add \(suggestion.displayName) as friend"
        )
        .accessibilityHint(isSent ? "" : "Sends a friend request")
    }

    private var displayFirstName: String {
        if let name = suggestion.name?.components(separatedBy: " ").first, !name.isEmpty {
            return name
        }
        if let username = suggestion.username, !username.isEmpty { return username }
        return "Add"
    }
}

// MARK: - Tutorial Mock Exercise Row
//
// Visual twin of `AutoExerciseCard` for the welcome tutorial. Uses the
// SAME `ExercisePosterRingIcon` the Exercises tab + Auto Workout
// preview use, so the cards show real cached video stills of the
// exercise (gender-aware — the icon's cache key reads
// `GenderFilterService.shared.preferredGender`, so male videos show
// for users who picked male, female videos show for female). The
// rendered card matches the live preview screen pixel-for-pixel
// (sleek card, gradient-ring icon, name + colored category +
// equipment, info glyph, swap glyph) so the user recognizes the
// layout when they reach the real auto-generated workout flow.

struct TutorialMockExerciseRow: View {
    struct SampleExercise {
        let name: String
        let category: String
        let equipment: String
        /// SF Symbol shown until the smart-cropped video still finishes
        /// baking on disk. After the first appearance the cache is warm
        /// and the real glyph renders synchronously.
        let fallbackSymbol: String
    }

    let exercise: SampleExercise

    private var categoryColor: Color {
        switch exercise.category.lowercased() {
        case "chest": return .purple
        case "back": return .blue
        case "legs": return .green
        case "shoulders": return .orange
        case "arms": return .purple
        case "core": return .yellow
        case "full body": return .pink
        default: return .gray
        }
    }

    private var categoryGradient: [Color] {
        switch exercise.category.lowercased() {
        case "chest": return [Color.purple, Color.pink]
        case "back": return [Color.blue, Color.cyan]
        case "legs": return [Color.green, Color.teal]
        case "shoulders": return [Color.orange, Color.yellow]
        case "arms": return [Color.purple, Color.indigo]
        case "core": return [Color.yellow, Color.orange]
        case "full body": return [Color.pink, Color.red]
        default: return [Color.gray, Color.gray.opacity(0.7)]
        }
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // Same component the Exercises tab uses. Loads the cached
            // smart-cropped video still synchronously when warm, falls
            // back to the gradient ring + SF Symbol on cold cache, and
            // updates itself via `.exercisePosterSmartCropReady` once
            // the bake finishes — so the tutorial cards "fill in" with
            // real glyphs the first time the user sees them.
            ExercisePosterRingIcon(
                exerciseName: exercise.name,
                gradientColors: categoryGradient,
                fallbackSymbol: exercise.fallbackSymbol,
                isCoreCategory: exercise.category.lowercased() == "core",
                size: 56,
                ringWidth: 2.5
            )

            VStack(alignment: .leading, spacing: Spacing.xxxs) {
                Text(exercise.name)
                    .font(.ds_bodyLarge)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: Spacing.xs) {
                    Text(exercise.category)
                        .font(.ds_bodySmall)
                        .foregroundColor(categoryColor)
                        .fontWeight(.medium)

                    Text("•")
                        .font(.ds_labelSmall)
                        .foregroundColor(.secondary)

                    Text(exercise.equipment)
                        .font(.ds_bodySmall)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: Spacing.xxs)

            Image(systemName: "info.circle")
                .font(.ds_bodyRegular)
                .fontWeight(.medium)
                .foregroundColor(.blue)

            Image(systemName: "arrow.triangle.swap")
                .font(.ds_bodyRegular)
                .fontWeight(.medium)
                .foregroundColor(categoryColor)
                .padding(Spacing.xs)
                .background(Circle().fill(categoryColor.opacity(0.15)))
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .adaptiveSleekCardSubtle(cornerRadius: CornerRadius.lg)
    }
}

// MARK: - Programs Hero

struct TutorialProgramHero: View {
    @Environment(\.colorScheme) private var colorScheme
    let kind: TutorialPageKind
    let isAnimating: Bool

    private let completionPercentage: Double = 0.68
    private let currentDay = 9
    private let totalDays = 21
    private let programName = "Foundation Builder"
    private let weekLabel = "Week 2/3"

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: Spacing.sm) {
                progressRing
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(programName).font(.ds_heading3).foregroundColor(.adaptiveText)
                    HStack(spacing: Spacing.xxs) {
                        Text(weekLabel).font(.ds_caption).foregroundColor(.adaptiveSecondaryText)
                        Text("•").font(.ds_caption).foregroundColor(.adaptiveSecondaryText)
                        Text("\(currentDay)/\(totalDays) days")
                            .font(.ds_labelMedium).foregroundColor(kind.accentColor)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.ds_labelMedium)
                    .foregroundColor(.adaptiveSecondaryText)
            }
            .padding(Spacing.md)

            Divider().padding(.horizontal, Spacing.md)

            HStack(spacing: Spacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                        .fill(kind.accent)
                        .frame(width: 44, height: 44)
                    Text("Day \(currentDay)")
                        .font(.ds_caption.weight(.bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                VStack(alignment: .leading, spacing: Spacing.xxxs) {
                    Text("Full Body A").font(.ds_labelLarge).foregroundColor(.adaptiveText)
                    Text("4 exercises • Hamstrings, Calves…")
                        .font(.ds_caption).foregroundColor(.adaptiveSecondaryText).lineLimit(1)
                }
                Spacer()
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: "play.fill").font(.ds_caption)
                    Text("Start").font(.ds_labelMedium)
                }
                .foregroundColor(.white)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.xs)
                .background(Capsule().fill(kind.accent))
            }
            .padding(Spacing.md)
        }
        .frame(maxWidth: 360)
        .adaptiveSleekCard(cornerRadius: CornerRadius.xl, accentColor: kind.accentColor)
        .scaleEffect(0.92)
        .offset(y: isAnimating ? -3 : 3)
    }

    private var progressRing: some View {
        ZStack {
            Circle().stroke(Color.gray.opacity(0.15), lineWidth: 5)
                .frame(width: 64, height: 64)
            Circle()
                .trim(from: 0, to: completionPercentage)
                .stroke(kind.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .frame(width: 64, height: 64)
                .rotationEffect(.degrees(-90))
            VStack(spacing: -2) {
                Text("\(Int(completionPercentage * 100))")
                    .font(.ds_statSmall)
                    .foregroundColor(kind.accentColor)
                Text("%").font(.ds_caption).foregroundColor(.adaptiveSecondaryText)
            }
        }
    }
}

// MARK: - 1v1 Challenge Hero

struct TutorialChallengeHero: View {
    @Environment(\.colorScheme) private var colorScheme
    let kind: TutorialPageKind
    let isAnimating: Bool

    // MARK: Sample challenge fixture
    //
    // The 1v1 challenge tutorial is a STATIC PREVIEW of what an active
    // 1v1 challenge looks like in the app. The screen renders TWO
    // pieces, top → bottom:
    //   1. A slim `ChallengeHeroCard` (the same component the live
    //      `ChallengeDetailView` uses) with the day-progress pills
    //      suppressed (passing `durationDays: 0` skips them) — gives
    //      the user the title + brand color + one-line description
    //      without the chronology pills the user said cluttered the
    //      preview.
    //   2. A `TutorialActiveChallengePreview` that mirrors the
    //      dashboard's active-challenge widget (header row + accent bar
    //      + head-to-head competition row) so onboarding users
    //      recognize the exact UI they'll see on their dashboard once
    //      they've started a real challenge.
    //
    // No real challenge is created from this screen; the post-
    // onboarding Friends tab is where users send real challenges.
    //
    // Fixture is a 7-day Lift Challenge ("3 Lifts a Week") with the
    // current user beating a fake opponent ("Alex") 2-to-1 with 3 days
    // remaining. Mirrors the `.lift` ChallengeType (purple/pink
    // gradient, dumbbell icon, 🏋️ emoji) so the brand color story
    // matches what users see post-onboarding.
    private static let challengeType: ChallengeType = .lift
    private static let challengeTitle = "3 Lifts a Week"
    private static let challengeDescription = "Race your friend to 3 strength workouts this week. First one to hit the target wins more XP points toward your next league."
    private static let weeklyTarget = 3
    private static let myProgress = 2
    private static let opponentProgress = 1
    private static let daysRemaining = 3
    /// Fake opponent. Verified badge demonstrates the platform's
    /// verified-account treatment to brand-new users (the badge they
    /// see here is the same one rendered next to a real verified
    /// account's name in the live `competitionProgressSection`).
    private static let opponentName = "Joe"
    private static let opponentIsVerified = true

    private var myDisplayName: String {
        UserManager.shared.currentUser?.name?
            .components(separatedBy: " ")
            .first ?? "You"
    }

    var body: some View {
        VStack(spacing: Spacing.sm) {
            ChallengeHeroCard(
                title: Self.challengeTitle,
                emoji: Self.challengeType.emoji,
                typeColor: Self.challengeType.color,
                gradient: Self.challengeType.gradientColors,
                typeLabel: Self.challengeType.displayName,
                description: Self.challengeDescription,
                // Day-progress pills suppressed per design feedback —
                // passing `durationDays: 0` short-circuits the
                // calendar/clock pill row inside `ChallengeHeroCard`
                // so the hero is visually slimmer and the focus stays
                // on the title + description.
                daysElapsed: 0,
                durationDays: 0,
                daysRemaining: 0,
                endDate: nil,
                memberCountSuffix: nil
            )

            TutorialActiveChallengePreview(
                challengeType: Self.challengeType,
                myName: myDisplayName,
                myProgress: Self.myProgress,
                opponentName: Self.opponentName,
                opponentProgress: Self.opponentProgress,
                opponentIsVerified: Self.opponentIsVerified,
                weeklyTarget: Self.weeklyTarget,
                daysRemaining: Self.daysRemaining
            )
        }
        .padding(.horizontal, Spacing.md)
        .scaleEffect(0.94)
        .offset(y: isAnimating ? -2 : 2)
    }
}

// MARK: - Tutorial Active Challenge Preview
//
// Static, non-interactive mirror of the dashboard's active-challenge
// widget (`DashboardView+Challenges.swift::activeChallengeDetailWidget`).
// Reuses the same visual shell — emoji avatar + title + "vs Friend ·
// 3d left" subtitle + accent-bar separator + head-to-head row — but
// with no NavigationLinks (would attempt to push out of the
// onboarding fullScreenCover), no battle-cry sheet plumbing, and no
// service dependencies (`ChallengeProgressResolver`,
// `RealtimeService`, etc.). Pure preview.
struct TutorialActiveChallengePreview: View {
    @Environment(\.colorScheme) private var colorScheme

    let challengeType: ChallengeType
    let myName: String
    let myProgress: Int
    let opponentName: String
    let opponentProgress: Int
    let weeklyTarget: Int
    let daysRemaining: Int

    private var typeColor: Color { challengeType.color }
    private var typeGradient: [Color] { challengeType.gradientColors }
    private var amWinning: Bool { myProgress > opponentProgress }
    private var leadDelta: Int { abs(myProgress - opponentProgress) }
    private var unitLabel: String { weeklyTarget == 1 ? "lift" : "lifts" }

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            progressRow
                .padding(.vertical, Spacing.sm)
                .padding(.horizontal, Spacing.sm)
                .padding(.bottom, 4)
        }
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: CornerRadius.xl + 4, style: .continuous)
                    .fill(typeColor.opacity(colorScheme == .dark ? 0.12 : 0.06))
                    .offset(y: 6)
                    .blur(radius: 3)

                RoundedRectangle(cornerRadius: CornerRadius.xl + 2, style: .continuous)
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                    .offset(y: 4)

                AdaptiveCardSurface(cornerRadius: CornerRadius.xl)

                RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color.white.opacity(0.1), Color.white.opacity(0.02), Color.clear]
                                : [Color.white, Color.white.opacity(0.5), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1.5
                    )

                RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                typeColor.opacity(colorScheme == .dark ? 0.35 : 0.25),
                                typeColor.opacity(colorScheme == .dark ? 0.25 : 0.15)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: typeColor.opacity(colorScheme == .dark ? 0.1 : 0.06), radius: 12, x: 0, y: 3)
    }

    // MARK: Header row (mirrors `ActiveChallengeHeaderRow` visuals)

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                Circle()
                    .stroke(
                        LinearGradient(colors: typeGradient, startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 2.5
                    )
                    .frame(width: 36, height: 36)
                Text(challengeType.emoji)
                    .font(.ds_heading3)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("3 Lifts a Week")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text("vs \(opponentName)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("•")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("\(daysRemaining)d left")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(typeColor)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "face.smiling")
                .font(.ds_heading3)
                .foregroundStyle(
                    LinearGradient(colors: [.orange, .red], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .padding(.trailing, 8)

            Image(systemName: "chevron.right")
                .font(.ds_labelMedium)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, Spacing.sm)
    }

    // MARK: Head-to-head progress row (mirrors `competitionProgressSection`)

    private var progressRow: some View {
        HStack(spacing: 0) {
            // Left accent bar — type-colored
            RoundedRectangle(cornerRadius: 2)
                .fill(LinearGradient(colors: typeGradient, startPoint: .top, endPoint: .bottom))
                .frame(width: 4)
                .padding(.vertical, Spacing.xxs)

            HStack(spacing: 10) {
                // You side
                HStack(spacing: 10) {
                    avatarBubble(initial: String(myName.prefix(1)), isLeading: amWinning)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("You")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)

                        Text("\(myProgress) \(unitLabel)")
                            .font(.ds_heading2).fontDesign(.rounded)
                            .foregroundColor(amWinning ? .green : .primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: 100, alignment: .leading)
                }

                Spacer(minLength: 4)

                VStack(spacing: 2) {
                    Text("⚔️")
                        .font(.ds_bodySmall)
                    if leadDelta > 0 {
                        Text(amWinning ? "+\(leadDelta)" : "-\(leadDelta)")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundColor(amWinning ? .green : .red)
                    }
                }
                .frame(minWidth: 30)

                Spacer(minLength: 4)

                // Opponent side
                HStack(spacing: 10) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(opponentName)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .lineLimit(1)

                        Text("\(opponentProgress) \(opponentProgress == 1 ? "lift" : "lifts")")
                            .font(.ds_heading2).fontDesign(.rounded)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: 100, alignment: .trailing)

                    avatarBubble(initial: String(opponentName.prefix(1)), isLeading: !amWinning)
                }
            }
            .padding(.horizontal, 10)
        }
    }

    @ViewBuilder
    private func avatarBubble(initial: String, isLeading: Bool) -> some View {
        ZStack(alignment: .top) {
            Circle()
                .fill(LinearGradient(colors: typeGradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 44, height: 44)
                .overlay(
                    Text(initial.uppercased())
                        .font(.ds_labelLarge)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                )
                .overlay(
                    Circle().stroke(Color.white.opacity(0.25), lineWidth: 1.5)
                )

            if isLeading {
                Image(systemName: "crown.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.yellow)
                    .offset(y: -12)
            }
        }
    }
}

// MARK: - Community Hero
//
// The community step on the welcome tutorial is REAL — not a static mock.
// It picks the most contact-relevant community challenge to feature
// (top friend-density first, then top popular fallback) and lets the new
// user actually join from this screen. Once joined, the card flips to the
// live `CommunityLeaderboardWidget` so the user immediately sees themselves
// alongside their friends on the leaderboard before they even leave the
// onboarding flow. (Replaces the prior demo "5K Morning Walk" mock card.)

struct TutorialCommunityHero: View {
    @ObservedObject private var communityService = CommunityChallengeService.shared
    @ObservedObject private var contactsService = ContactsService.shared
    let kind: TutorialPageKind
    let isAnimating: Bool

    @State private var didTriggerRefresh = false
    @State private var didLoadPYMKCommunities = false
    @State private var didBuildPreview = false
    @State private var isJoining = false
    @State private var joinedChallengeId: UUID?
    /// Communities surfaced via friends-of-friends / "people you may know".
    /// Held locally (not on the service) because it's onboarding-only —
    /// other surfaces (Friends tab, Community Hub) keep using the
    /// friend-only `discoverableChallenges`.
    @State private var pymkCommunities: [DiscoverableCommunityChallenge] = []
    /// Synthesized live-shape `CommunityChallenge` rendered in the
    /// preview `CommunityLeaderboardWidget`. Built from the picked
    /// source (default: 10K-steps community) + a real leaderboard
    /// fetched via `getChallengeDetail` and `fetchContactsLeaderboard`
    /// so the user sees actual member scores BEFORE joining.
    @State private var previewChallenge: CommunityChallenge?
    /// The picked source backing `previewChallenge`. Retained so the
    /// Join tap can route to the correct join RPC: friend-gated for
    /// `.discoverable`, code-based for `.featured`.
    @State private var previewSource: PreviewSource?

    /// Backing source of the preview challenge.
    private enum PreviewSource {
        case discoverable(DiscoverableCommunityChallenge, isContactBased: Bool)
        case featured(FeaturedCommunityChallenge)

        var title: String {
            switch self {
            case .discoverable(let c, _): return c.title
            case .featured(let c):        return c.title
            }
        }
        var challengeId: UUID {
            switch self {
            case .discoverable(let c, _): return c.challengeId
            case .featured(let c):        return c.challengeId
            }
        }
    }

    /// The just-joined challenge (live `CommunityChallenge` from
    /// `myChallenges`), resolved by id so the leaderboard widget
    /// renders with real top-N data + the user's row.
    private var joinedChallenge: CommunityChallenge? {
        guard let id = joinedChallengeId else { return nil }
        return communityService.myChallenges.first(where: { $0.challengeId == id })
    }

    var body: some View {
        VStack(spacing: Spacing.sm) {
            content
                .frame(maxWidth: 360)

            footerCaption
        }
        .scaleEffect(stackScale)
        .offset(y: isAnimating ? -2 : 2)
        .padding(.horizontal, Spacing.md)
        .onAppear { triggerInitialFetch() }
    }

    /// The big leaderboard widget is taller than the old card stack,
    /// so we scale it down a touch more so the page copy + dots +
    /// Continue CTA below all fit comfortably on the iPhone SE-class
    /// vertical budget without clipping.
    private var stackScale: CGFloat {
        (joinedChallenge != nil || previewChallenge != nil) ? 0.78 : 0.92
    }

    // MARK: - Initial fetch + preview build

    private func triggerInitialFetch() {
        guard !didTriggerRefresh else { return }
        didTriggerRefresh = true
        Task { @MainActor in
            // Force-refresh so brand-new accounts always pull fresh
            // discoverable + featured lists, even if the service
            // already ran its 5s-throttled refresh during sign-in.
            await communityService.refreshAll(force: true)
            // PYMK pool feeds both the contact-density picker AND the
            // contacts-leaderboard population in the preview widget,
            // so we always load it (not gated on direct-friend count
            // like the prior single-card flow).
            await loadPYMKCommunities()
            await buildPreviewChallenge()
        }
    }

    @MainActor
    private func loadPYMKCommunities() async {
        guard !didLoadPYMKCommunities else { return }
        didLoadPYMKCommunities = true

        var candidateIds = currentContactCandidateIds()
        // PYMK list might not have been fetched yet (cold launch). Trigger
        // a server fetch and re-collect.
        if candidateIds.isEmpty, SupabaseManager.shared.isAuthenticated {
            await contactsService.fetchPeopleYouMayKnow()
            candidateIds = currentContactCandidateIds()
        }

        guard !candidateIds.isEmpty else { return }

        let result = await communityService.fetchPYMKCommunityChallenges(
            userIds: candidateIds
        )
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            pymkCommunities = result
        }
    }

    /// Pick the default preview community, fetch real leaderboard
    /// data for it (contacts + global top-10 fallback), and synthesize
    /// the live-shape `CommunityChallenge` the preview widget renders.
    @MainActor
    private func buildPreviewChallenge() async {
        guard !didBuildPreview else { return }
        didBuildPreview = true

        guard let pickedSource = pickPreviewSource() else { return }

        let challengeId = pickedSource.challengeId
        let contactIds = currentContactCandidateIds()

        // Run the contacts-leaderboard fetch + the global detail fetch
        // in parallel — both are needed to populate the widget rows
        // (contacts first, then global top to fill any remaining slots).
        async let contactsTask = communityService.fetchContactsLeaderboard(
            challengeId: challengeId,
            userIds: contactIds
        )
        async let detailTask = communityService.getChallengeDetail(
            challengeId: challengeId
        )
        let contactRows = await contactsTask
        let detailResp  = await detailTask

        let mergedRows = mergeLeaderboardRows(
            contacts: contactRows,
            globalTop: detailResp?.topLeaderboard ?? []
        )

        // Friends row above the leaderboard surfaces the contacts in
        // this challenge (= "people you know" already here). Built
        // from the contacts-leaderboard response so the avatars match
        // the highlighted leaderboard rows.
        let friends: [CommunityFriendInfo] = contactRows.map { row in
            CommunityFriendInfo(
                userId: row.userId,
                name: row.name,
                username: row.username,
                profilePhotoUrl: row.profilePhotoUrl
            )
        }

        let synthesized = synthesizeChallenge(
            from: pickedSource,
            participantCount: detailResp?.participantCount,
            topParticipants: mergedRows,
            friendsIn: friends
        )

        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            previewChallenge = synthesized
            previewSource = pickedSource
        }
        AppLogger.info(
            "[TUTORIAL] Built community preview '\(pickedSource.title)' (\(contactRows.count) contacts in leaderboard, \(mergedRows.count) total rows)",
            category: .social
        )
    }

    /// Selection priority:
    ///   1. PYMK 10K-steps community with the most synced contacts in it
    ///   2. Friend-discoverable 10K-steps community with the most friends
    ///   3. Official 10K-steps featured community (most participants)
    ///   4. Any 10K-steps featured community (most participants)
    ///   5. Top contact-based community (any target) — keeps a contacts
    ///      hook even if no 10K exists on the server
    ///   6. Top direct-friend community (any target)
    ///   7. Top featured community as last-resort filler
    private func pickPreviewSource() -> PreviewSource? {
        let is10kSteps: (String, Int) -> Bool = { type, target in
            type == "steps" && target == 10_000
        }

        if let c = pymkCommunities
            .filter({ is10kSteps($0.challengeType, $0.dailyTarget) && $0.friendsCount > 0 })
            .max(by: { $0.friendsCount < $1.friendsCount }) {
            return .discoverable(c, isContactBased: true)
        }
        if let c = communityService.discoverableChallenges
            .filter({ is10kSteps($0.challengeType, $0.dailyTarget) && $0.friendsCount > 0 })
            .max(by: { $0.friendsCount < $1.friendsCount }) {
            return .discoverable(c, isContactBased: false)
        }
        if let c = communityService.featuredChallenges
            .filter({ is10kSteps($0.challengeType, $0.dailyTarget) && $0.isOfficial && !$0.alreadyJoined })
            .max(by: { $0.participantCount < $1.participantCount }) {
            return .featured(c)
        }
        if let c = communityService.featuredChallenges
            .filter({ is10kSteps($0.challengeType, $0.dailyTarget) && !$0.alreadyJoined })
            .max(by: { $0.participantCount < $1.participantCount }) {
            return .featured(c)
        }
        if let c = pymkCommunities
            .filter({ $0.friendsCount > 0 })
            .max(by: { $0.friendsCount < $1.friendsCount }) {
            return .discoverable(c, isContactBased: true)
        }
        if let c = communityService.discoverableChallenges
            .filter({ $0.friendsCount > 0 })
            .max(by: { $0.friendsCount < $1.friendsCount }) {
            return .discoverable(c, isContactBased: false)
        }
        if let c = communityService.featuredChallenges
            .filter({ !$0.alreadyJoined })
            .max(by: { $0.participantCount < $1.participantCount }) {
            return .featured(c)
        }
        return nil
    }

    /// PYMK candidate user-id list = `peopleYouMayKnow` ∪ unfriended
    /// contacts-on-Fit33 from `suggestedFriends`. Same set we feed the
    /// PYMK community-discovery RPC, reused here as the input to the
    /// contacts-leaderboard RPC so the highlighted rows match the
    /// communities surfaced in the picker.
    private func currentContactCandidateIds() -> [UUID] {
        var ids = Set(contactsService.peopleYouMayKnow.map { $0.userId })
        for suggestion in contactsService.suggestedFriends where !suggestion.isFriend {
            ids.insert(suggestion.userId)
        }
        return Array(ids)
    }

    /// Merge contact rows + global-top rows into a single leaderboard,
    /// deduped by user_id, contacts first (so people the user knows
    /// surface at the top), capped at 10. The merged list is re-ranked
    /// 1..N because the server returns two independently-ranked sets
    /// (contacts ranked among themselves, global ranked among everyone),
    /// and mixing them as-is would show duplicate "1" / "2" rank emojis.
    private func mergeLeaderboardRows(
        contacts: [LeaderboardSnippetEntry],
        globalTop: [LeaderboardSnippetEntry]
    ) -> [LeaderboardSnippetEntry] {
        var seen = Set<UUID>()
        var out: [LeaderboardSnippetEntry] = []
        for entry in contacts where out.count < 10 {
            if seen.insert(entry.userId).inserted {
                out.append(entry)
            }
        }
        for entry in globalTop where out.count < 10 {
            if seen.insert(entry.userId).inserted {
                out.append(entry)
            }
        }
        return out.enumerated().map { index, entry in
            var copy = entry
            copy.rank = index + 1
            return copy
        }
    }

    /// Build a `CommunityChallenge` (the live-state shape used by
    /// `CommunityLeaderboardWidget`) from a preview source. The
    /// `my_*` fields are nil because the user hasn't joined yet — the
    /// widget's preview mode hides the my-stats banner so these
    /// values are never surfaced to the user.
    private func synthesizeChallenge(
        from source: PreviewSource,
        participantCount: Int?,
        topParticipants: [LeaderboardSnippetEntry],
        friendsIn: [CommunityFriendInfo]
    ) -> CommunityChallenge {
        switch source {
        case .discoverable(let c, _):
            return CommunityChallenge(
                challengeId: c.challengeId,
                title: c.title,
                description: c.description,
                emoji: c.emoji,
                challengeType: c.challengeType,
                dailyTarget: c.dailyTarget,
                targetUnit: c.targetUnit,
                participantCount: participantCount ?? c.participantCount,
                maxParticipants: c.maxParticipants,
                joinCode: c.joinCode,
                inviteSlug: c.inviteSlug,
                isRecurring: c.isRecurring,
                isFeatured: c.isFeatured,
                isOfficial: c.isOfficial,
                myTodayProgress: nil,
                myDaysCompleted: nil,
                myCurrentStreak: nil,
                myBestStreak: nil,
                myRank: nil,
                createdBy: c.createdBy,
                creatorName: nil,
                creatorUsername: nil,
                topParticipants: topParticipants,
                friendsIn: friendsIn,
                friendsCount: friendsIn.count,
                targetCadence: nil,
                myPeriodProgress: nil
            )
        case .featured(let c):
            return CommunityChallenge(
                challengeId: c.challengeId,
                title: c.title,
                description: c.description,
                emoji: c.emoji,
                challengeType: c.challengeType,
                dailyTarget: c.dailyTarget,
                targetUnit: c.targetUnit,
                participantCount: participantCount ?? c.participantCount,
                maxParticipants: nil,
                joinCode: c.joinCode,
                inviteSlug: c.inviteSlug,
                isRecurring: c.isRecurring,
                isFeatured: c.isFeatured,
                isOfficial: c.isOfficial,
                myTodayProgress: nil,
                myDaysCompleted: nil,
                myCurrentStreak: nil,
                myBestStreak: nil,
                myRank: nil,
                createdBy: c.createdBy,
                creatorName: c.creatorName,
                creatorUsername: c.creatorUsername,
                topParticipants: topParticipants,
                friendsIn: friendsIn,
                friendsCount: friendsIn.count,
                targetCadence: nil,
                myPeriodProgress: nil
            )
        }
    }

    // MARK: - Card stack

    @ViewBuilder
    private var content: some View {
        if let joined = joinedChallenge {
            // Real-time win moment: user just joined, so flip from the
            // preview to the live widget that shows them on the
            // leaderboard alongside their contacts.
            CommunityLeaderboardWidget(challenge: joined)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.94).combined(with: .opacity),
                    removal: .opacity
                ))
                .accessibilityLabel("You joined the \(joined.title) community")
        } else if let preview = previewChallenge {
            CommunityLeaderboardWidget(
                challenge: preview,
                previewJoin: { handlePreviewJoin() }
            )
            .opacity(isJoining ? 0.6 : 1.0)
            .disabled(isJoining)
            .transition(.opacity)
            .accessibilityLabel("\(preview.title) preview — \(preview.formattedParticipantCount) members. Tap Join to enter.")
        } else {
            // Loading placeholder — preserves layout while the
            // discovery + detail RPCs are in flight.
            FeaturedChallengeCard(
                challenge: TutorialDemoData.demoCommunityChallenge,
                onJoin: {}
            )
            .allowsHitTesting(false)
            .redacted(reason: .placeholder)
        }
    }

    // MARK: - Footer caption

    @ViewBuilder
    private var footerCaption: some View {
        if let joined = joinedChallenge {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.ds_caption)
                    .foregroundColor(.green)
                Text("You're in! \(joined.formattedParticipantCount) members")
                    .font(.ds_labelMedium)
                    .foregroundColor(.adaptiveSecondaryText)
            }
            .accessibilityElement(children: .combine)
        } else {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "person.3.fill")
                    .font(.ds_caption)
                    .foregroundStyle(kind.accent)
                Text(previewCaption)
                    .font(.ds_labelMedium)
                    .foregroundColor(.adaptiveSecondaryText)
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// Caption for the preview state. Mirrors the picked source so the
    /// footer matches the card: contacts-first signal when contacts are
    /// in the community, friends-fallback when only direct friends are,
    /// participant scale for the featured fallback.
    private var previewCaption: String {
        guard let src = previewSource else {
            return "Featured challenges, real people"
        }
        switch src {
        case .discoverable(let c, let isContactBased):
            let label = isContactBased ? "your contacts" : "your friends"
            return connectionsCaption(c.friendsCount, label: label)
        case .featured(let c):
            if c.participantCount > 0 {
                return "\(formattedParticipants(c.participantCount)) athletes already pushing"
            }
            return "Featured challenges, real people"
        }
    }

    private func connectionsCaption(_ count: Int, label: String) -> String {
        switch count {
        case 0:  return "Athletes pushing the same goal"
        case 1:  return "1 of \(label) is already in"
        default: return "\(count) of \(label) are already in"
        }
    }

    private func formattedParticipants(_ count: Int) -> String {
        if count >= 1000 {
            return String(format: "%.1fK", Double(count) / 1000)
        }
        return "\(count)"
    }

    // MARK: - Real-time Join

    /// Routes the preview widget's Join tap to the correct join RPC
    /// based on the picked source: friend-gated for discoverable
    /// (PYMK / friend-discovery surfaces), code-based for featured
    /// (no friend-chain requirement on official challenges).
    private func handlePreviewJoin() {
        guard let src = previewSource, !isJoining else { return }
        switch src {
        case .discoverable(let challenge, _):
            joinDiscoverableCommunity(challenge)
        case .featured(let challenge):
            joinFeaturedCommunity(challenge)
        }
    }

    /// Used for both direct-friend AND PYMK communities — they share the
    /// `DiscoverableCommunityChallenge` shape, and the server-side join
    /// gate (`can_join_community_challenge`) accepts both direct friends
    /// and friends-of-friends as the qualifying connection.
    private func joinDiscoverableCommunity(_ challenge: DiscoverableCommunityChallenge) {
        guard !isJoining else { return }
        isJoining = true
        HapticManager.impact(.medium)
        Task { @MainActor in
            let joinedId = await communityService.joinChallengeFriendGated(
                challengeId: challenge.challengeId
            )
            isJoining = false
            guard joinedId != nil else { return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                joinedChallengeId = challenge.challengeId
                // Drop the just-joined community from the local PYMK
                // list so it doesn't flicker back if state ever
                // re-evaluates pre-leaderboard render.
                pymkCommunities.removeAll { $0.challengeId == challenge.challengeId }
            }
            AppLogger.info(
                "[TUTORIAL] Joined friend-chain community '\(challenge.title)' from onboarding tour (\(challenge.friendsCount) connections)",
                category: .social
            )
        }
    }

    private func joinFeaturedCommunity(_ challenge: FeaturedCommunityChallenge) {
        guard !isJoining else { return }
        isJoining = true
        HapticManager.impact(.medium)
        Task { @MainActor in
            let joinedId = await communityService.joinChallenge(code: challenge.joinCode)
            isJoining = false
            guard joinedId != nil else { return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                joinedChallengeId = challenge.challengeId
            }
            AppLogger.info(
                "[TUTORIAL] Joined featured community '\(challenge.title)' from onboarding tour",
                category: .social
            )
        }
    }
}

// MARK: - League Hero

struct TutorialLeagueHero: View {
    @Environment(\.colorScheme) private var colorScheme
    let kind: TutorialPageKind
    let isAnimating: Bool

    private struct Rank {
        let name: String
        let icon: String
        let colors: [Color]
    }

    private let ranks: [Rank] = [
        Rank(name: "Bronze", icon: "shield.fill", colors: [Color(red: 0.7, green: 0.5, blue: 0.3), Color(red: 0.6, green: 0.4, blue: 0.2)]),
        Rank(name: "Silver", icon: "shield.lefthalf.filled", colors: [Color(white: 0.75), Color(white: 0.55)]),
        Rank(name: "Gold", icon: "rosette", colors: [Color(red: 1.0, green: 0.85, blue: 0.3), Color(red: 0.95, green: 0.65, blue: 0.1)]),
        Rank(name: "Plat.", icon: "crown.fill", colors: [Color(red: 0.5, green: 0.85, blue: 0.95), Color(red: 0.3, green: 0.6, blue: 0.85)]),
        Rank(name: "Diam.", icon: "diamond.fill", colors: [Color(red: 0.6, green: 0.4, blue: 1.0), Color(red: 0.4, green: 0.2, blue: 0.85)])
    ]

    private let userIndex = 1 // Silver

    var body: some View {
        VStack(spacing: Spacing.md) {
            HStack(spacing: Spacing.xs) {
                ForEach(Array(ranks.enumerated()), id: \.offset) { index, rank in
                    rankChip(rank: rank, isUser: index == userIndex)
                }
            }
            .padding(.horizontal, Spacing.md)

            HStack(spacing: Spacing.sm) {
                arrowChip(icon: "arrow.up.circle.fill", label: "Top 10 promote", tint: .green)
                arrowChip(icon: "arrow.down.circle.fill", label: "Bottom 5 drop", tint: .orange)
            }

            Text("Resets every Monday at midnight")
                .font(.ds_caption)
                .foregroundColor(.adaptiveSecondaryText)
        }
        .scaleEffect(isAnimating ? 1.01 : 1.0)
    }

    private func rankChip(rank: Rank, isUser: Bool) -> some View {
        VStack(spacing: Spacing.xxs) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: rank.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: isUser ? 56 : 44, height: isUser ? 56 : 44)
                    .shadow(color: rank.colors[0].opacity(0.4), radius: isUser ? 12 : 6, x: 0, y: 4)

                Image(systemName: rank.icon)
                    .font(isUser ? .ds_heading3 : .ds_labelLarge)
                    .foregroundColor(.white)
            }
            .overlay(
                Circle().stroke(isUser ? kind.accentColor : Color.clear, lineWidth: 2)
                    .frame(width: isUser ? 60 : 0, height: isUser ? 60 : 0)
            )

            Text(rank.name)
                .font(.ds_caption)
                .foregroundColor(isUser ? .adaptiveText : .adaptiveSecondaryText)
        }
        .scaleEffect(isUser ? 1.0 : 0.92)
    }

    private func arrowChip(icon: String, label: String, tint: Color) -> some View {
        HStack(spacing: Spacing.xxs) {
            Image(systemName: icon).font(.ds_labelMedium).foregroundColor(tint)
            Text(label).font(.ds_labelMedium).foregroundColor(.adaptiveText)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xxs)
        .background(
            Capsule().fill(tint.opacity(0.12))
        )
        .overlay(Capsule().stroke(tint.opacity(0.3), lineWidth: 1))
    }
}

// MARK: - Connect Integrations (the centerpiece)

struct TutorialConnectIntegrationsView: View {
    let kind: TutorialPageKind

    var body: some View {
        VStack(spacing: Spacing.xs) {
            IntegrationRow(integration: .appleHealth)
            IntegrationRow(integration: .whoop)
            // Oura row temporarily hidden — coming back in a future update.
            IntegrationRow(integration: .fitbit)
            IntegrationRow(integration: .strava)

            Text("Skip — connect later in Settings")
                .font(.ds_caption)
                .foregroundColor(.adaptiveSecondaryText)
                .padding(.top, Spacing.xs)
        }
        .frame(maxWidth: 380)
        .padding(.horizontal, Spacing.md)
    }
}

private enum TutorialIntegration {
    case appleHealth, whoop, oura, fitbit, strava

    var title: String {
        switch self {
        case .appleHealth: return "Apple Health"
        case .whoop:       return "WHOOP"
        case .oura:        return "Oura"
        case .fitbit:      return "Fitbit"
        case .strava:      return "Strava"
        }
    }

    var dataLine: String {
        switch self {
        case .appleHealth: return "Steps, calories, workouts"
        case .whoop:       return "Recovery, strain, sleep, HRV"
        case .oura:        return "Readiness, sleep, activity"
        case .fitbit:      return "Steps, heart rate, sleep"
        // Kept short so the green "Connected" pill (wider than "Connect")
        // doesn't force "GPS activities" to truncate to "GPS…" on the
        // narrow card width when the user is already linked to Strava.
        case .strava:      return "Runs, rides & GPS"
        }
    }

    var icon: String {
        switch self {
        case .appleHealth: return "heart.fill"
        case .whoop:       return "waveform.path.ecg"
        case .oura:        return "circle.hexagongrid.fill"
        case .fitbit:      return "figure.walk"
        case .strava:      return "figure.run"
        }
    }

    var brandColors: [Color] {
        switch self {
        case .appleHealth: return [.red, .pink]
        case .whoop:       return [Color(red: 0.0, green: 0.7, blue: 0.5), Color(red: 0.0, green: 0.55, blue: 0.7)]
        case .oura:        return [Color(red: 0.45, green: 0.45, blue: 0.85), Color(red: 0.25, green: 0.25, blue: 0.5)]
        case .fitbit:      return [.teal, .cyan]
        case .strava:      return [Color(red: 0.99, green: 0.30, blue: 0.04), Color(red: 0.95, green: 0.45, blue: 0.10)]
        }
    }

    var tint: Color { brandColors[0] }

    /// True for integrations whose icon badge is the brand's own wordmark / lockup
    /// (so we don't render a redundant text title above the dataline).
    var usesBrandBadge: Bool {
        switch self {
        case .whoop, .fitbit, .strava: return true
        case .appleHealth, .oura:      return false
        }
    }
}

private struct IntegrationRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let integration: TutorialIntegration

    var body: some View {
        // Only subscribe to the relevant service for this row to avoid 25 Combine
        // subscriptions on a 5-row screen (which can hammer the main thread when
        // a service fires objectWillChange during onboarding sync).
        switch integration {
        case .appleHealth:
            AppleHealthIntegrationRowBody(integration: integration)
        case .whoop:
            WhoopIntegrationRowBody(integration: integration)
        case .oura:
            OuraIntegrationRowBody(integration: integration)
        case .fitbit:
            FitbitIntegrationRowBody(integration: integration)
        case .strava:
            StravaIntegrationRowBody(integration: integration)
        }
    }
}

private struct AppleHealthIntegrationRowBody: View {
    @ObservedObject private var service = HealthKitManager.shared
    let integration: TutorialIntegration
    var body: some View { IntegrationRowBody(integration: integration, isConnected: service.isAuthorized) }
}

private struct WhoopIntegrationRowBody: View {
    @ObservedObject private var service = WhoopService.shared
    let integration: TutorialIntegration
    var body: some View { IntegrationRowBody(integration: integration, isConnected: service.isConnected) }
}

private struct OuraIntegrationRowBody: View {
    @ObservedObject private var service = OuraService.shared
    let integration: TutorialIntegration
    var body: some View { IntegrationRowBody(integration: integration, isConnected: service.isConnected) }
}

private struct FitbitIntegrationRowBody: View {
    @ObservedObject private var service = FitbitService.shared
    let integration: TutorialIntegration
    var body: some View { IntegrationRowBody(integration: integration, isConnected: service.isConnected) }
}

private struct StravaIntegrationRowBody: View {
    @ObservedObject private var service = StravaService.shared
    let integration: TutorialIntegration
    var body: some View { IntegrationRowBody(integration: integration, isConnected: service.isConnected) }
}

private struct IntegrationRowBody: View {
    @Environment(\.colorScheme) private var colorScheme
    let integration: TutorialIntegration
    let isConnected: Bool

    @State private var isConnecting = false
    @State private var hasLaunchedAuth = false

    var body: some View {
        HStack(spacing: Spacing.sm) {
            iconBadge

            VStack(alignment: .leading, spacing: Spacing.xxxs) {
                // For third-party brands the badge IS the title (their official
                // wordmark / "compatible with" lockup), so don't double up with a
                // text label. Apple Health keeps the textual title.
                if integration.usesBrandBadge == false {
                    Text(integration.title)
                        .font(.ds_heading3)
                        .foregroundColor(.adaptiveText)
                }
                Text(integration.dataLine)
                    .font(.ds_bodySmall)
                    .foregroundColor(.adaptiveSecondaryText)
                    .lineLimit(2)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(integration.title). \(integration.dataLine)")

            Spacer(minLength: Spacing.xxs)

            connectPill
        }
        .padding(Spacing.sm)
        .adaptiveSleekCard(cornerRadius: CornerRadius.lg, accentColor: integration.tint)
    }

    // MARK: - Brand badge constants
    //
    // ALL four integration badges are the same 88×44 brand chip so the rows line
    // up and the logos read as a consistent set. Inner logo frames are picked
    // per-brand to make the visual weight of the wordmarks/glyphs feel equal —
    // WHOOP's tall thin "WHOOP" wordmark, Fitbit's wide horizontal lockup, and
    // Strava's stacked "Compatible with" badge each need a slightly different
    // inner frame to look the same size to the eye.
    private static let chipSize = CGSize(width: 88, height: 44)
    private static let chipCornerRadius: CGFloat = 12

    @ViewBuilder
    private var iconBadge: some View {
        switch integration {
        case .appleHealth:
            // Red→pink gradient chip mirroring the Apple Health brand identity.
            // Same dimensions as the third-party brand chips so all four icons
            // read as a clean grid.
            chipBackground(fill: AnyShapeStyle(
                LinearGradient(colors: integration.brandColors,
                               startPoint: .topLeading,
                               endPoint: .bottomTrailing)
            ), shadow: integration.tint.opacity(0.35)) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white)
            }
        case .whoop:
            // Black puck with the official white WHOOP wordmark — matches WHOOP
            // brand guidelines (white logotype on dark background only).
            chipBackground(fill: AnyShapeStyle(Color.black),
                           shadow: Color.black.opacity(0.4)) {
                Image("WhoopWordmark")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(.white)
                    .frame(width: 60, height: 18)
            }
            .accessibilityHidden(true)
        case .fitbit:
            // Fitbit official wordmark on a clean white chip. Inner frame is
            // sized to leave generous horizontal padding so the dark navy
            // wordmark doesn't crowd the chip edge — fixes the "dark issues"
            // where the wordmark appeared to bleed into the row background.
            chipBackground(fill: AnyShapeStyle(Color.white),
                           shadow: Color.black.opacity(0.25)) {
                Image("FitbitLogo")
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 22)
            }
            .accessibilityHidden(true)
        case .strava:
            // "Compatible with STRAVA" lockup — Strava brand guidelines require
            // the official badge whenever Strava data is shown to the user.
            // Stacked badge sits taller; frame tuned so the orange "STRAVA"
            // visually matches the WHOOP/Fitbit wordmark weight.
            chipBackground(fill: AnyShapeStyle(Color.white),
                           shadow: Color.black.opacity(0.25)) {
                Image("CompatibleWithStrava")
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 56, height: 34)
            }
            .accessibilityHidden(true)
        case .oura:
            // Retained for compile-safety only — Oura row is currently hidden
            // from this screen (see TutorialConnectIntegrationsView).
            chipBackground(fill: AnyShapeStyle(
                LinearGradient(colors: integration.brandColors,
                               startPoint: .topLeading,
                               endPoint: .bottomTrailing)
            ), shadow: integration.tint.opacity(0.35)) {
                Image(systemName: integration.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
    }

    /// Shared chip container used by every integration row so the badges line
    /// up at the same 88×44 footprint regardless of what's drawn inside.
    @ViewBuilder
    private func chipBackground<Content: View>(
        fill: AnyShapeStyle,
        shadow: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: Self.chipCornerRadius)
                .fill(fill)
                .frame(width: Self.chipSize.width, height: Self.chipSize.height)
                .shadow(color: shadow, radius: 6, x: 0, y: 3)
            content()
        }
    }

    @ViewBuilder
    private var connectPill: some View {
        if isConnected {
            HStack(spacing: Spacing.xxxs) {
                Image(systemName: "checkmark.seal.fill").font(.ds_caption)
                Text("Connected").font(.ds_labelMedium)
            }
            .foregroundColor(connectPillForeground)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xxs)
            .background(Capsule().fill(connectPillBackground))
            .overlay(Capsule().stroke(connectPillStroke, lineWidth: connectPillStrokeWidth))
            .accessibilityLabel("\(integration.title) connected")
        } else {
            Button(action: launchConnect) {
                HStack(spacing: Spacing.xxxs) {
                    if isConnecting {
                        ProgressView().tint(connectPillForeground).controlSize(.small)
                    } else {
                        Text("Connect").font(.ds_labelMedium)
                    }
                }
                .foregroundColor(connectPillForeground)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(Capsule().fill(connectPillBackground))
                .overlay(
                    // Subtle hairline so the white WHOOP pill stays legible on
                    // the card background regardless of color scheme.
                    Capsule().stroke(connectPillStroke, lineWidth: connectPillStrokeWidth)
                )
            }
            .scaleButtonStyle(.standard, withHaptic: true)
            .disabled(isConnecting)
            .accessibilityLabel("Connect \(integration.title)")
        }
    }

    // MARK: - Per-brand Connect / Connected Pill Styling
    //
    // Brand guidelines (and good UX) require each integration's CTA to look
    // unmistakably like the destination brand. The SAME styling is used whether
    // the user is connecting (Connect) or already linked (Connected) — the
    // checkmark.seal.fill icon is the only signal of state, so the pill stays
    // brand-colored end-to-end and the row reads as that brand at a glance.
    //   • Apple Health — red→pink gradient (matches the heart chip / brand)
    //   • WHOOP        — solid white pill, black text (WHOOP: white on black)
    //   • Fitbit       — solid Fitbit teal, white text (#00B0BD)
    //   • Strava       — solid Strava orange, white text (#FD4D0A)

    private var connectPillBackground: AnyShapeStyle {
        switch integration {
        case .whoop:
            return AnyShapeStyle(Color.white)
        case .fitbit:
            return AnyShapeStyle(Color(red: 0.0, green: 0.69, blue: 0.74))
        case .strava:
            return AnyShapeStyle(Color(red: 0.99, green: 0.30, blue: 0.04))
        case .appleHealth, .oura:
            return AnyShapeStyle(LinearGradient(colors: integration.brandColors, startPoint: .leading, endPoint: .trailing))
        }
    }

    private var connectPillForeground: Color {
        switch integration {
        case .whoop: return .black
        default:     return .white
        }
    }

    private var connectPillStroke: Color {
        switch integration {
        case .whoop: return Color.black.opacity(0.12)
        default:     return Color.clear
        }
    }

    private var connectPillStrokeWidth: CGFloat {
        switch integration {
        case .whoop: return 1
        default:     return 0
        }
    }

    // MARK: - Actions

    private func launchConnect() {
        switch integration {
        case .appleHealth:
            connectAppleHealth()
        case .whoop, .oura, .fitbit, .strava:
            connectOAuth()
        }
    }

    private func connectAppleHealth() {
        guard !isConnecting else { return }
        isConnecting = true
        Task { @MainActor in
            do {
                try await HealthKitManager.shared.requestAuthorization()
            } catch {
                AppLogger.error("[TUTORIAL] HealthKit auth failed: \(error.localizedDescription)", category: .health)
            }
            isConnecting = false
        }
    }

    private func connectOAuth() {
        guard !hasLaunchedAuth else { return }
        guard let authURL = oauthURL else {
            AppLogger.error("[TUTORIAL] Failed to build authorization URL for \(integration.title)", category: .auth)
            return
        }

        hasLaunchedAuth = true
        isConnecting = true

        let session = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: "fit33"
        ) { callbackURL, error in
            Task { @MainActor in
                hasLaunchedAuth = false
                defer { isConnecting = false }

                if let error = error {
                    let nsError = error as NSError
                    if nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        AppLogger.debug("[TUTORIAL] User cancelled \(integration.title) login", category: .auth)
                    } else {
                        AppLogger.error("[TUTORIAL] \(integration.title) auth error: \(error.localizedDescription)", category: .auth)
                    }
                    return
                }

                guard let url = callbackURL else {
                    AppLogger.error("[TUTORIAL] \(integration.title) returned nil callbackURL", category: .auth)
                    return
                }

                do {
                    try await handleCallback(url: url)
                } catch {
                    AppLogger.error("[TUTORIAL] \(integration.title) callback failed: \(error.localizedDescription)", category: .auth)
                }
            }
        }

        session.presentationContextProvider = WebAuthContextProvider.shared
        session.prefersEphemeralWebBrowserSession = false
        session.start()
    }

    private var oauthURL: URL? {
        switch integration {
        case .whoop:  return WhoopService.shared.getAuthorizationURL()
        case .oura:   return OuraService.shared.getAuthorizationURL()
        case .fitbit: return FitbitService.shared.getAuthorizationURL()
        case .strava: return StravaService.shared.getAuthorizationURL()
        case .appleHealth: return nil
        }
    }

    private func handleCallback(url: URL) async throws {
        switch integration {
        case .whoop:  try await WhoopService.shared.handleCallback(url: url)
        case .oura:   try await OuraService.shared.handleCallback(url: url)
        case .fitbit: try await FitbitService.shared.handleCallback(url: url)
        case .strava: try await StravaService.shared.handleCallback(url: url)
        case .appleHealth: break
        }
    }
}

// MARK: - Fuel & Hydrate Card

struct TutorialFuelCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let kind: TutorialPageKind
    let isAnimating: Bool

    private let hydrationProgress: Double = 0.72
    private let currentMl: Int = 1800
    private let goalMl: Int = 2500

    var body: some View {
        VStack(spacing: Spacing.sm) {
            // Mini meal preview
            SwipeableMealCard(
                mealType: .breakfast,
                meals: TutorialDemoData.demoBreakfastMeals,
                isCurrentMealTime: true,
                onAddFood: {},
                onDelete: { _ in }
            )
            .frame(maxWidth: 360)
            .allowsHitTesting(false)
            .scaleEffect(0.86)

            // Hydration row
            HStack(spacing: Spacing.sm) {
                hydrationRing
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Hydration").font(.ds_heading3).foregroundColor(.adaptiveText)
                    Text("\(formatMl(currentMl)) / \(formatMl(goalMl))")
                        .font(.ds_labelMedium)
                        .foregroundColor(.adaptiveSecondaryText)
                    Text("Tap to add a cup or bottle")
                        .font(.ds_caption)
                        .foregroundColor(.adaptiveSecondaryText)
                }
                Spacer()
            }
            .padding(Spacing.md)
            .frame(maxWidth: 360)
            .adaptiveSleekCard(cornerRadius: CornerRadius.lg, accentColor: .cyan)
        }
        .offset(y: isAnimating ? -2 : 2)
    }

    private var hydrationRing: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.15), lineWidth: 5)
                .frame(width: 56, height: 56)
            Circle()
                .trim(from: 0, to: hydrationProgress)
                .stroke(
                    LinearGradient(colors: [.cyan, .blue], startPoint: .top, endPoint: .bottom),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .frame(width: 56, height: 56)
                .rotationEffect(.degrees(-90))
            Image(systemName: "drop.fill")
                .font(.ds_heading3)
                .foregroundStyle(LinearGradient(colors: [.cyan, .blue], startPoint: .top, endPoint: .bottom))
        }
    }

    private func formatMl(_ ml: Int) -> String {
        if ml >= 1000 { return String(format: "%.1fL", Double(ml) / 1000.0) }
        return "\(ml)ml"
    }
}

// MARK: - Trial CTA

struct TutorialTrialCTA: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var storeKit = StoreKitManager.shared
    let kind: TutorialPageKind
    let isAnimating: Bool
    @Binding var isPresented: Bool

    private struct TrialFeature {
        let icon: String
        let text: String
    }

    private let features: [TrialFeature] = [
        TrialFeature(icon: "wand.and.stars", text: "Unlimited Smart Workouts"),
        TrialFeature(icon: "chart.xyaxis.line", text: "Advanced Analytics & Insights"),
        TrialFeature(icon: "fork.knife", text: "Custom Meal Plans & Recipes"),
        TrialFeature(icon: "flame.fill", text: "Streak Shields & Premium Features")
    ]

    var body: some View {
        VStack(spacing: Spacing.md) {
            ZStack {
                Circle()
                    .fill(RadialGradient(
                        colors: [Color.yellow.opacity(0.3), Color.clear],
                        center: .center, startRadius: 10, endRadius: 60))
                    .frame(width: 100, height: 100)
                    .scaleEffect(isAnimating ? 1.08 : 0.96)

                Circle()
                    .fill(LinearGradient(
                        colors: [Color(red: 1.0, green: 0.84, blue: 0), Color(red: 1.0, green: 0.6, blue: 0.1)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 56, height: 56)
                    .shadow(color: Color.yellow.opacity(0.5), radius: 12, x: 0, y: 6)

                Image(systemName: "crown.fill")
                    .font(.ds_heading2)
                    .foregroundColor(.white)
            }

            VStack(spacing: Spacing.xs) {
                ForEach(Array(features.enumerated()), id: \.offset) { _, feature in
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.ds_labelLarge)
                            .foregroundStyle(kind.accent)
                        Text(feature.text)
                            .font(.ds_bodyMedium)
                            .fontWeight(.medium)
                            .foregroundColor(.adaptiveText)
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, Spacing.xs)

            Button(action: {
                HapticManager.tap()
                Task { await startTrial() }
            }) {
                HStack(spacing: Spacing.xs) {
                    if storeKit.purchaseState == .purchasing {
                        ProgressView().tint(.white)
                    } else {
                        Text("Start Free 3-Day Trial").font(.ds_labelLarge)
                        Image(systemName: "arrow.right").font(.ds_bodyMedium.weight(.bold))
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.md)
                .background(
                    Capsule()
                        .fill(LinearGradient.ds_primaryAccent)
                        .shadow(color: .purple.opacity(0.4), radius: 12, x: 0, y: 6)
                )
            }
            .scaleButtonStyle(.standard, withHaptic: true)
            .disabled(storeKit.purchaseState == .purchasing)

            HStack(spacing: Spacing.xxs) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.ds_caption)
                    .foregroundColor(.green)
                Text("Cancel anytime • No commitment")
                    .font(.ds_caption)
                    .foregroundColor(.adaptiveSecondaryText)
            }

            Button(action: {
                HapticManager.tap()
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    isPresented = false
                }
            }) {
                Text("Maybe Later")
                    .font(.ds_bodyMedium)
                    .fontWeight(.medium)
                    .foregroundColor(.adaptiveSecondaryText)
            }
        }
        .padding(.horizontal, Spacing.md)
    }

    private func startTrial() async {
        guard let product = storeKit.yearlyProduct ?? storeKit.monthlyProduct else {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { isPresented = false }
            return
        }
        let success = await storeKit.purchase(product)
        if success {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { isPresented = false }
        }
    }
}

// MARK: - Preview

#Preview {
    WelcomeTutorialView(isPresented: .constant(true))
}
