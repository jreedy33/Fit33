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
        case .autoWorkout:    return "AI-built or fully custom"
        case .programs:       return "30-day transformations"
        case .challenges1v1:  return "Compete head-to-head"
        case .community:      return "Featured challenges, real people"
        case .league:         return "Duolingo-style weekly leagues"
        case .wearables:      return "WHOOP, Oura, Fitbit, Apple Health"
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
            return "Pick your time, muscles, and equipment\nfor an AI workout — or build from 6,000+ exercises."
        case .programs:
            return "Progressive 7, 14, 21, or 30-day programs\nbuilt around your goals and schedule."
        case .challenges1v1:
            return "Challenge friends 1v1 or in groups.\nLive scoreboards, daily stakes, real accountability."
        case .community:
            return "Join featured community challenges.\nThousands of athletes pushing the same goal."
        case .league:
            return "Train every week, climb the ranks.\nTop finishers get promoted. Bottom drops down."
        case .wearables:
            return "Connect your favorite trackers.\nRecovery, strain, sleep — all read by Fit33."
        case .fuel:
            return "Log meals with USDA + label OCR.\nStay hydrated with one-tap water tracking."
        case .trial:
            return "Unlimited AI workouts, advanced analytics,\ncustom meal plans, and more."
        }
    }

    var accent: LinearGradient {
        switch self {
        case .welcome:        return .ds_primaryAccent
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
                            ? AnyShapeStyle(pages[currentPage].accent)
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
                    .fill(pages[currentPage].accent)
                    .shadow(color: pages[currentPage].accentColor.opacity(0.5), radius: 16, x: 0, y: 8)
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
            .foregroundStyle(pages[currentPage].accent)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(
                Capsule()
                    .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
            )
            .overlay(
                Capsule().stroke(pages[currentPage].accent, lineWidth: 2)
            )
        }
        .scaleButtonStyle(.standard, withHaptic: true)
        .padding(.horizontal, Spacing.xl)
        .accessibilityLabel(title)
    }

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
            VStack(spacing: 0) {
                Spacer(minLength: Spacing.md)

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

    // MARK: - Hero

    @ViewBuilder
    private var heroView: some View {
        switch kind {
        case .welcome:
            TutorialWelcomeHero(kind: kind, isAnimating: heroAnimation)
        case .findFriends:
            TutorialFindFriendsHero(kind: kind, isAnimating: heroAnimation)
        case .autoWorkout:
            TutorialAutoWorkoutHero(kind: kind, isAnimating: heroAnimation)
        case .programs:
            TutorialProgramHero(kind: kind, isAnimating: heroAnimation)
        case .challenges1v1:
            TutorialChallengeHero(kind: kind, isAnimating: heroAnimation)
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
            if kind != .welcome { // Welcome shows logo + own title
                Text(kind.title)
                    .font(.ds_displayMedium)
                    .foregroundStyle(kind.accent)
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
        case .welcome, .trial:                    return geometry.size.height * 0.46
        case .wearables:                          return geometry.size.height * 0.50
        case .challenges1v1, .community:          return geometry.size.height * 0.42
        case .programs, .fuel, .league:           return geometry.size.height * 0.38
        case .autoWorkout, .findFriends:          return geometry.size.height * 0.36
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
        VStack(spacing: Spacing.md) {
            Text(kind.title)
                .font(.ds_displayMedium)
                .foregroundStyle(kind.accent)
                .tracking(-0.5)
                .multilineTextAlignment(.center)

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [kind.accentColor.opacity(0.35), Color.clear],
                            center: .center, startRadius: 40, endRadius: 220
                        )
                    )
                    .frame(width: 360, height: 360)
                    .blur(radius: 30)
                    .scaleEffect(isAnimating ? 1.06 : 1.0)

                Image("fit33-logo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 320, maxHeight: 160)
                    .shadow(color: kind.accentColor.opacity(0.5), radius: 30, x: 0, y: 12)
                    .scaleEffect(isAnimating ? 1.02 : 0.98)
                    .offset(y: isAnimating ? -4 : 4)
            }
        }
    }
}

// MARK: - Find Friends Hero

struct TutorialFindFriendsHero: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var contactsService = ContactsService.shared
    let kind: TutorialPageKind
    let isAnimating: Bool

    @State private var isWorking = false

    private var matchedCount: Int { contactsService.suggestedFriends.count }
    private var hasSynced: Bool {
        contactsService.canAccessContacts && contactsService.hasCheckedContacts
    }

    var body: some View {
        VStack(spacing: Spacing.md) {
            // Avatar cluster
            avatarCluster

            // Status / action card
            VStack(spacing: Spacing.sm) {
                if hasSynced {
                    syncedState
                } else if contactsService.permissionDenied {
                    deniedState
                } else {
                    pendingState
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.md)
            .frame(maxWidth: 360)
            .adaptiveSleekCard(cornerRadius: CornerRadius.xl, accentColor: kind.accentColor)
        }
        .padding(.horizontal, Spacing.md)
    }

    // MARK: - Avatar cluster

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

    private var syncedState: some View {
        VStack(spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.ds_heading3)
                    .foregroundColor(.green)
                Text("Contacts synced")
                    .font(.ds_heading3)
                    .foregroundColor(.adaptiveText)
            }
            if matchedCount > 0 {
                Text("Found \(matchedCount) \(matchedCount == 1 ? "friend" : "friends") already on Fit33")
                    .font(.ds_bodyRegular)
                    .foregroundColor(.adaptiveSecondaryText)
                    .multilineTextAlignment(.center)
            } else {
                Text("No matches yet — invite some friends from the Social tab.")
                    .font(.ds_bodyRegular)
                    .foregroundColor(.adaptiveSecondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
        }
    }

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Auto Workout Hero

struct TutorialAutoWorkoutHero: View {
    let kind: TutorialPageKind
    let isAnimating: Bool

    var body: some View {
        // Mirror the home-page Workout tab quick actions exactly:
        // Custom Workout (blue→cyan, plus.circle.fill, "Build your own"), then
        // Auto Workout (purple→pink, dumbbell.fill, "Auto-generated routine").
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
        .scaleEffect(0.94)
        .offset(y: isAnimating ? -3 : 3)
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
    let kind: TutorialPageKind
    let isAnimating: Bool

    var body: some View {
        VStack(spacing: Spacing.sm) {
            // Use the real "Challenge a Friend!" entry widget that ships on the
            // Home dashboard and Friends tab so users see exactly what they'll
            // tap once they're in the app.
            ChallengeAFriendEntryWidget()
                .frame(maxWidth: 360)

            HStack(spacing: Spacing.xs) {
                badge(icon: "person.2.fill", label: "1v1")
                badge(icon: "person.3.fill", label: "Group")
                badge(icon: "lock.fill", label: "Private")
            }
        }
        .scaleEffect(0.9)
        .offset(y: isAnimating ? -2 : 2)
        .padding(.horizontal, Spacing.md)
    }

    private func badge(icon: String, label: String) -> some View {
        HStack(spacing: Spacing.xxs) {
            Image(systemName: icon).font(.ds_caption)
            Text(label).font(.ds_labelMedium)
        }
        .foregroundStyle(kind.accent)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xxs)
        .background(
            Capsule().fill(kind.accentColor.opacity(0.12))
        )
        .overlay(Capsule().stroke(kind.accentColor.opacity(0.3), lineWidth: 1))
    }
}

// MARK: - Community Hero

struct TutorialCommunityHero: View {
    let kind: TutorialPageKind
    let isAnimating: Bool

    var body: some View {
        VStack(spacing: Spacing.sm) {
            FeaturedChallengeCard(
                challenge: TutorialDemoData.demoCommunityChallenge,
                onJoin: {}
            )
            .frame(maxWidth: 360)
            .allowsHitTesting(false)

            HStack(spacing: Spacing.xs) {
                Image(systemName: "person.3.fill")
                    .font(.ds_caption)
                    .foregroundStyle(kind.accent)
                Text("234 athletes joined this week")
                    .font(.ds_labelMedium)
                    .foregroundColor(.adaptiveSecondaryText)
            }
        }
        .scaleEffect(0.88)
        .offset(y: isAnimating ? -2 : 2)
        .padding(.horizontal, Spacing.md)
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
            IntegrationRow(integration: .oura)
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
        case .strava:      return "Runs, rides, GPS activities"
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
                Text(integration.title)
                    .font(.ds_heading3)
                    .foregroundColor(.adaptiveText)
                Text(integration.dataLine)
                    .font(.ds_bodySmall)
                    .foregroundColor(.adaptiveSecondaryText)
                    .lineLimit(1)
            }

            Spacer()

            connectPill
        }
        .padding(Spacing.sm)
        .adaptiveSleekCard(cornerRadius: CornerRadius.lg, accentColor: integration.tint)
    }

    private var iconBadge: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: integration.brandColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 44, height: 44)
                .shadow(color: integration.tint.opacity(0.4), radius: 6, x: 0, y: 3)
            Image(systemName: integration.icon)
                .font(.ds_labelLarge)
                .foregroundColor(.white)
        }
    }

    @ViewBuilder
    private var connectPill: some View {
        if isConnected {
            HStack(spacing: Spacing.xxxs) {
                Image(systemName: "checkmark.seal.fill").font(.ds_caption)
                Text("Connected").font(.ds_labelMedium)
            }
            .foregroundColor(.white)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xxs)
            .background(Capsule().fill(Color(red: 0.2, green: 0.7, blue: 0.4)))
            .accessibilityLabel("\(integration.title) connected")
        } else {
            Button(action: launchConnect) {
                HStack(spacing: Spacing.xxxs) {
                    if isConnecting {
                        ProgressView().tint(.white).controlSize(.small)
                    } else {
                        Text("Connect").font(.ds_labelMedium)
                    }
                }
                .foregroundColor(.white)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(
                    Capsule()
                        .fill(LinearGradient(colors: integration.brandColors, startPoint: .leading, endPoint: .trailing))
                )
            }
            .scaleButtonStyle(.standard, withHaptic: true)
            .disabled(isConnecting)
            .accessibilityLabel("Connect \(integration.title)")
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
        TrialFeature(icon: "sparkles", text: "Unlimited AI Workout Generation"),
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
