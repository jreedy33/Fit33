import SwiftUI
import StoreKit

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

// MARK: - Welcome Tutorial View

struct WelcomeTutorialView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var isPresented: Bool
    @StateObject private var storeKit = StoreKitManager.shared

    @State private var currentPage = 0
    @State private var animateContent = false
    @State private var iconBounce = false
    @State private var backgroundPulse = false

    private let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
    private let selectionFeedback = UISelectionFeedbackGenerator()

    // 9 screens: Welcome -> Create Workouts -> Programs -> Challenges & Friends -> Streaks -> Nutrition -> Hydration -> Health Apps -> Free Trial
    private let tutorialPages: [TutorialPage] = [
        TutorialPage(
            title: "Welcome to",
            subtitle: "Your intelligent fitness companion",
            description: "Build the perfect workout every time.\nLet's see what you can do.",
            icon: "figure.strengthtraining.traditional",
            iconColor: .blue,
            gradient: [Color.blue, Color.cyan.opacity(0.8)],
            animationType: .pulse,
            useLogoImage: true
        ),
        TutorialPage(
            title: "Create Workouts",
            subtitle: "AI-powered or fully custom",
            description: "Pick your time, muscles, and equipment for an AI workout\n— or build from scratch with 5,000+ exercises.",
            icon: "sparkles",
            iconColor: .purple,
            gradient: [Color.purple, Color.pink],
            animationType: .sparkle,
            useWorkoutCards: true
        ),
        TutorialPage(
            title: "Programs",
            subtitle: "Your 30-day transformation",
            description: "Progressive training programs tailored to your goals.\nTrack every day with built-in scheduling.",
            icon: "calendar.badge.clock",
            iconColor: .green,
            gradient: [Color.green, Color.mint],
            animationType: .wave,
            useProgramWidget: true
        ),
        TutorialPage(
            title: "Challenges & Friends",
            subtitle: "Compete & stay accountable",
            description: "Challenge friends 1v1, join community competitions,\nand see what your crew is training.",
            icon: "trophy.fill",
            iconColor: .orange,
            gradient: [Color.orange, Color.red],
            animationType: .bounce,
            useLiveChallengeWidget: true
        ),
        TutorialPage(
            title: "Streaks",
            subtitle: "Consistency builds champions",
            description: "Work out daily to build your streak.\nThe longer your streak, the stronger your habit.",
            icon: "flame.fill",
            iconColor: .orange,
            gradient: [Color.orange, Color.red],
            animationType: .pulse,
            useStreakFlame: true
        ),
        TutorialPage(
            title: "Nutrition",
            subtitle: "Fuel your progress",
            description: "Track meals, calories, and macros.\nStay on top of your nutrition goals.",
            icon: "fork.knife",
            iconColor: .pink,
            gradient: [Color.pink, Color.purple],
            animationType: .float,
            useRealMealCard: true
        ),
        TutorialPage(
            title: "Hydration",
            subtitle: "Stay optimally hydrated",
            description: "Track daily water intake with one tap.\nReach your hydration goals effortlessly.",
            icon: "drop.fill",
            iconColor: .cyan,
            gradient: [Color.cyan, Color.blue],
            animationType: .wave,
            useWaterWidget: true
        ),
        TutorialPage(
            title: "Connect Your Health",
            subtitle: "Sync everything automatically",
            description: "Link your favorite health apps to auto-track\nsteps, calories, and workouts.",
            icon: "heart.fill",
            iconColor: .red,
            gradient: [Color.red, Color.pink],
            animationType: .float,
            useHealthAppsWidget: true
        ),
        TutorialPage(
            title: "Unlock Everything",
            subtitle: "Start your free trial",
            description: "Get unlimited AI workouts, advanced analytics,\ncustom meal plans, and more.",
            icon: "crown.fill",
            iconColor: .yellow,
            gradient: [Color.yellow, Color.orange],
            animationType: .celebrate,
            useTrialCTA: true
        )
    ]
    
    var body: some View {
        ZStack {
            animatedBackground
                .ignoresSafeArea(.all)
            
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    
                    if currentPage < tutorialPages.count - 1 {
                        Button(action: skipTutorial) {
                            Text("Skip")
                                .font(.ds_bodyMedium)
                                .foregroundColor(.secondary.opacity(0.8))
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(
                                    Capsule()
                                        .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                                )
                        }
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, 12)
                
                TabView(selection: $currentPage) {
                    ForEach(Array(tutorialPages.enumerated()), id: \.offset) { index, page in
                        TutorialPageView(
                            page: page,
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
                
                VStack(spacing: 28) {
                    HStack(spacing: 10) {
                        ForEach(0..<tutorialPages.count, id: \.self) { index in
                            Capsule()
                                .fill(
                                    index == currentPage
                                        ? LinearGradient(colors: tutorialPages[currentPage].gradient, startPoint: .leading, endPoint: .trailing)
                                        : LinearGradient(colors: [Color.gray.opacity(0.25)], startPoint: .leading, endPoint: .trailing)
                                )
                                .frame(width: index == currentPage ? 28 : 8, height: 8)
                                .animation(.spring(response: 0.35, dampingFraction: 0.75), value: currentPage)
                        }
                    }
                    
                    if currentPage == tutorialPages.count - 1 && tutorialPages[currentPage].useTrialCTA {
                        EmptyView()
                    } else if currentPage == tutorialPages.count - 1 {
                        Button(action: completeTutorial) {
                            HStack(spacing: 10) {
                                Text("Get Started")
                                    .font(.ds_labelLarge)
                                Image(systemName: "arrow.right")
                                    .font(.ds_bodyMedium)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 58)
                            .background(
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: tutorialPages[currentPage].gradient,
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .shadow(color: tutorialPages[currentPage].gradient[0].opacity(0.5), radius: 16, x: 0, y: 8)
                            )
                        }
                        .scaleButtonStyle(.standard, withHaptic: true)
                        .padding(.horizontal, 36)
                    } else {
                        Button(action: nextPage) {
                            HStack(spacing: 10) {
                                Text("Continue")
                                    .font(.ds_labelLarge)
                                Image(systemName: "chevron.right")
                                    .font(.ds_bodySmall).fontWeight(.bold)
                            }
                            .foregroundStyle(
                                LinearGradient(
                                    colors: tutorialPages[currentPage].gradient,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(maxWidth: .infinity)
                            .frame(height: 58)
                            .background(
                                Capsule()
                                    .fill(colorScheme == .dark ? Color(white: 0.08).opacity(0.8) : Color(white: 0.96).opacity(0.9))
                            )
                            .overlay(
                                Capsule()
                                    .stroke(
                                        LinearGradient(
                                            colors: tutorialPages[currentPage].gradient,
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        ),
                                        lineWidth: 2.5
                                    )
                            )
                        }
                        .scaleButtonStyle(.standard, withHaptic: true)
                        .padding(.horizontal, 36)
                    }
                }
                .background(.clear)
                .padding(.bottom, 56)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6).delay(0.2)) {
                animateContent = true
            }
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                backgroundPulse = true
            }
        }
        .onChange(of: currentPage) { _, _ in
            selectionFeedback.selectionChanged()
        }
    }
    
    // MARK: - Background
    
    private var animatedBackground: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: colorScheme == .dark
                    ? [
                        Color(red: 0.05, green: 0.05, blue: 0.12),
                        Color(red: 0.08, green: 0.06, blue: 0.15),
                        Color(red: 0.04, green: 0.04, blue: 0.08)
                    ]
                    : [
                        Color(red: 0.96, green: 0.97, blue: 1.0),
                        Color.white,
                        Color(red: 0.98, green: 0.98, blue: 1.0)
                    ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea(.all)
            
            GeometryReader { geometry in
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    tutorialPages[currentPage].gradient[0].opacity(0.35),
                                    tutorialPages[currentPage].gradient[0].opacity(0.15),
                                    tutorialPages[currentPage].gradient[0].opacity(0)
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: 350
                            )
                        )
                        .frame(width: 700, height: 700)
                        .position(x: geometry.size.width * 0.5, y: geometry.size.height * 0.35)
                        .scaleEffect(backgroundPulse ? 1.1 : 0.95)
                        .animation(.easeInOut(duration: 4).repeatForever(autoreverses: true), value: backgroundPulse)
                    
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    tutorialPages[currentPage].gradient[0].opacity(0.25),
                                    tutorialPages[currentPage].gradient[0].opacity(0)
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: 200
                            )
                        )
                        .frame(width: 400, height: 400)
                        .position(x: backgroundPulse ? 50 : 0, y: backgroundPulse ? 100 : 50)
                        .animation(.easeInOut(duration: 5).repeatForever(autoreverses: true), value: backgroundPulse)
                    
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    tutorialPages[currentPage].gradient[1].opacity(0.25),
                                    tutorialPages[currentPage].gradient[1].opacity(0)
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: 280
                            )
                        )
                        .frame(width: 560, height: 560)
                        .position(
                            x: backgroundPulse ? geometry.size.width * 0.85 : geometry.size.width * 0.9,
                            y: backgroundPulse ? geometry.size.height * 0.75 : geometry.size.height * 0.8
                        )
                        .animation(.easeInOut(duration: 6).repeatForever(autoreverses: true), value: backgroundPulse)
                }
            }
            .ignoresSafeArea(.all)
            .animation(.easeInOut(duration: 0.8), value: currentPage)
        }
    }
    
    // MARK: - Actions
    
    private func nextPage() {
        impactFeedback.impactOccurred()
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            currentPage += 1
        }
    }
    
    private func skipTutorial() {
        impactFeedback.impactOccurred()
        completeTutorial()
    }
    
    private func completeTutorial() {
        impactFeedback.impactOccurred()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            isPresented = false
        }
    }
}

// MARK: - Tutorial Page Model

struct TutorialPage {
    let title: String
    let subtitle: String
    let description: String
    let icon: String
    let iconColor: Color
    let gradient: [Color]
    let animationType: AnimationType
    var useLogoImage: Bool = false
    var useWorkoutCards: Bool = false
    var useProgramWidget: Bool = false
    var useLiveChallengeWidget: Bool = false
    var useStreakFlame: Bool = false
    var useRealMealCard: Bool = false
    var useWaterWidget: Bool = false
    var useHealthAppsWidget: Bool = false
    var useTrialCTA: Bool = false

    enum AnimationType {
        case pulse, sparkle, bounce, wave, float, celebrate
    }
}

// MARK: - Tutorial Page View

struct TutorialPageView: View {
    @Environment(\.colorScheme) private var colorScheme
    let page: TutorialPage
    let isActive: Bool
    let animateContent: Bool
    @Binding var isPresented: Bool

    @State private var iconAnimation = false
    @State private var sparkleOffset: CGFloat = 0
    @State private var particles: [ParticleData] = []
    
    private var screenHeight: CGFloat {
        UIScreen.main.bounds.height
    }
    
    private var topPadding: CGFloat {
        if page.useTrialCTA { return screenHeight * 0.04 }
        if page.useLogoImage { return screenHeight * 0.08 }
        if page.useRealMealCard || page.useWaterWidget { return screenHeight * 0.06 }
        if page.useLiveChallengeWidget { return screenHeight * 0.03 }
        return screenHeight * 0.06
    }
    
    private var contentSpacing: CGFloat {
        if page.useLogoImage { return 0 }
        if page.useTrialCTA { return 16 }
        if page.useLiveChallengeWidget { return 14 }
        if page.useRealMealCard || page.useWaterWidget || page.useProgramWidget { return 20 }
        return 28
    }
    
    private var visualMaxHeight: CGFloat {
        if page.useTrialCTA { return 0.52 }
        if page.useLogoImage { return 0.42 }
        if page.useLiveChallengeWidget { return 0.48 }
        if page.useRealMealCard { return 0.38 }
        if page.useWaterWidget || page.useProgramWidget { return 0.36 }
        if page.useHealthAppsWidget { return 0.38 }
        if page.useStreakFlame { return 0.32 }
        if page.useWorkoutCards { return 0.34 }
        return 0.28
    }
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                Spacer()
                    .frame(height: page.useLogoImage ? 30 : topPadding)
                
                Spacer()
                    .frame(minHeight: 10, maxHeight: page.useLogoImage ? 60 : 40)
                
                // === CENTER SECTION: Visual Element ===
                ZStack {
                    if page.useLogoImage {
                        welcomeLogoView
                    } else if page.useWorkoutCards {
                        workoutCardsView
                    } else if page.useProgramWidget {
                        TutorialProgramWidget(gradient: page.gradient, isAnimating: iconAnimation)
                            .scaleEffect(0.9)
                            .offset(y: iconAnimation ? -3 : 3)
                    } else if page.useLiveChallengeWidget {
                        liveChallengeView
                    } else if page.useStreakFlame {
                        TutorialStreakFlame(gradient: page.gradient, isAnimating: iconAnimation)
                    } else if page.useRealMealCard {
                        realMealCardView
                            .scaleEffect(0.88)
                    } else if page.useWaterWidget {
                        TutorialWaterTracking(gradient: page.gradient, isAnimating: iconAnimation)
                            .scaleEffect(0.88)
                    } else if page.useHealthAppsWidget {
                        TutorialHealthAppsWidget(gradient: page.gradient, isAnimating: iconAnimation)
                    } else if page.useTrialCTA {
                        TutorialTrialCTA(gradient: page.gradient, isAnimating: iconAnimation, isPresented: $isPresented)
                            .scaleEffect(0.92)
                    } else {
                        defaultIconView
                    }
                }
                .scaleEffect(animateContent ? 1 : 0.8)
                .opacity(animateContent ? 1 : 0)
                .frame(maxWidth: .infinity)
                .frame(maxHeight: geometry.size.height * (page.useLogoImage ? 0.35 : visualMaxHeight))
                
                Spacer()
                    .frame(minHeight: page.useLogoImage ? 30 : contentSpacing, maxHeight: page.useLogoImage ? 50 : contentSpacing + 20)
                
                // === BOTTOM SECTION: Text Content ===
                VStack(spacing: 0) {
                    if !page.useLogoImage {
                        Text(page.title)
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: page.gradient,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .tracking(-0.5)
                            .multilineTextAlignment(.center)
                            .opacity(animateContent ? 1 : 0)
                            .offset(y: animateContent ? 0 : 20)
                            .padding(.bottom, 10)
                    }
                    
                    Text(page.subtitle)
                        .font(.ds_labelLarge)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .opacity(animateContent ? 1 : 0)
                        .offset(y: animateContent ? 0 : 15)
                        .padding(.bottom, 14)
                    
                    Text(page.description)
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
                .padding(.horizontal, Spacing.md)
                
                Spacer(minLength: 30)
            }
        }
        .onAppear {
            startIconAnimation()
            if page.animationType == .sparkle || page.animationType == .celebrate {
                generateParticles()
            }
        }
        .onChange(of: isActive) { _, active in
            if active { startIconAnimation() }
        }
    }
    
    // MARK: - Welcome Logo View
    private var welcomeLogoView: some View {
        VStack(spacing: 20) {
            Text(page.title)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(colors: page.gradient, startPoint: .leading, endPoint: .trailing)
                )
                .tracking(-0.5)
                .multilineTextAlignment(.center)
            
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [page.gradient[0].opacity(0.35), page.gradient[1].opacity(0.2), Color.clear],
                            center: .center, startRadius: 40, endRadius: 280
                        )
                    )
                    .frame(width: 500, height: 500)
                    .blur(radius: 40)
                    .scaleEffect(iconAnimation ? 1.08 : 1.0)
                
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [page.gradient[0].opacity(0.25), Color.clear],
                            center: .center, startRadius: 100, endRadius: 180
                        )
                    )
                    .frame(width: 360, height: 360)
                    .scaleEffect(iconAnimation ? 1.05 : 0.98)
                
                Image("fit33-logo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: min(UIScreen.main.bounds.width * 0.85, 380), height: 180)
                    .shadow(color: page.gradient[0].opacity(0.7), radius: 50, x: 0, y: 20)
                    .shadow(color: page.gradient[1].opacity(0.5), radius: 35, x: 0, y: 12)
                    .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 8)
                    .scaleEffect(iconAnimation ? 1.02 : 0.98)
                    .offset(y: iconAnimation ? -6 : 6)
            }
        }
    }
    
    // MARK: - Workout Cards (Auto + Custom side by side)
    private var workoutCardsView: some View {
        HStack(spacing: 14) {
            DepthQuickActionCard(
                title: "Auto Workout",
                subtitle: "AI-powered routine",
                icon: "sparkles",
                gradient: [.purple, .pink],
                action: {}
            )
            
            DepthQuickActionCard(
                title: "Custom Workout",
                subtitle: "Build your own",
                icon: "dumbbell.fill",
                gradient: [.blue, .cyan],
                action: {}
            )
        }
        .scaleEffect(0.92)
        .offset(y: iconAnimation ? -3 : 3)
    }
    
    // MARK: - Live Challenge View (1v1 + Community)
    private var liveChallengeView: some View {
        VStack(spacing: 12) {
            ActiveChallengeWidget(
                challenge: TutorialDemoData.demoActiveChallenge,
                onTap: {}
            )
            .frame(maxWidth: 340)
            
            FeaturedChallengeCard(
                challenge: TutorialDemoData.demoCommunityChallenge,
                onJoin: {}
            )
            .frame(maxWidth: 340)
        }
        .scaleEffect(0.82)
        .offset(y: iconAnimation ? -2 : 2)
    }
    
    // MARK: - Real Meal Card
    private var realMealCardView: some View {
        SwipeableMealCard(
            mealType: .breakfast,
            meals: TutorialDemoData.demoBreakfastMeals,
            isCurrentMealTime: true,
            onAddFood: {},
            onDelete: { _ in }
        )
        .frame(maxWidth: 340)
        .allowsHitTesting(false)
    }
    
    // MARK: - Default Icon View
    private var defaultIconView: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            page.iconColor.opacity(iconAnimation ? 0.45 : 0.2),
                            page.iconColor.opacity(0)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: iconAnimation ? 110 : 85
                    )
                )
                .frame(width: 220, height: 220)
            
            Circle()
                .fill(
                    LinearGradient(colors: page.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .frame(width: 140, height: 140)
                .shadow(color: page.gradient[0].opacity(0.6), radius: 25, x: 0, y: 12)
            
            Image(systemName: page.icon)
                .font(.system(size: 58, weight: .semibold))
                .foregroundColor(.white)
                .offset(y: iconAnimation ? -4 : 4)
            
            if page.animationType == .sparkle || page.animationType == .celebrate {
                ForEach(particles) { particle in
                    Image(systemName: "sparkle")
                        .font(.system(size: particle.size))
                        .foregroundColor(page.iconColor.opacity(particle.opacity))
                        .offset(x: particle.x, y: particle.y)
                }
            }
        }
    }
    
    private func startIconAnimation() {
        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
            iconAnimation = true
        }
    }
    
    private func generateParticles() {
        particles = (0..<8).map { _ in
            ParticleData(
                x: CGFloat.random(in: -90...90),
                y: CGFloat.random(in: -90...90),
                size: CGFloat.random(in: 10...18),
                opacity: Double.random(in: 0.4...0.9)
            )
        }
        withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
            particles = particles.map { particle in
                ParticleData(
                    x: particle.x + CGFloat.random(in: -25...25),
                    y: particle.y + CGFloat.random(in: -25...25),
                    size: particle.size,
                    opacity: Double.random(in: 0.4...0.9)
                )
            }
        }
    }
}

// MARK: - Particle Data

struct ParticleData: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    var size: CGFloat
    var opacity: Double
}

// MARK: - Tutorial Program Widget

struct TutorialProgramWidget: View {
    @Environment(\.colorScheme) private var colorScheme
    let gradient: [Color]
    let isAnimating: Bool
    
    private let completionPercentage: Double = 0.68
    private let currentDay = 9
    private let totalDays = 21
    private let programName = "Foundation Builder"
    private let weekLabel = "Week 2/3"
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.15), lineWidth: 5)
                        .frame(width: 68, height: 68)
                    
                    Circle()
                        .trim(from: 0, to: completionPercentage)
                        .stroke(
                            LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing),
                            style: StrokeStyle(lineWidth: 5, lineCap: .round)
                        )
                        .frame(width: 68, height: 68)
                        .rotationEffect(.degrees(-90))
                    
                    VStack(spacing: -2) {
                        Text("\(Int(completionPercentage * 100))")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(gradient.first ?? .green)
                        Text("%")
                            .font(.ds_caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(programName)
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 4) {
                        Text(weekLabel)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(currentDay)/\(totalDays) days")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(gradient.first ?? .green)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.ds_labelMedium)
                    .foregroundColor(.secondary)
            }
            .padding(Spacing.md)
            
            Divider()
                .padding(.horizontal, Spacing.md)
            
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 44, height: 44)
                    
                    Text("Day \(currentDay)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Full Body A")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text("4 exercises • Hamstrings, Calves,...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                        .font(.ds_caption)
                    Text("Start")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.xs)
                .background(LinearGradient(colors: gradient, startPoint: .leading, endPoint: .trailing))
                .clipShape(Capsule())
            }
            .padding(Spacing.md)
        }
        .frame(maxWidth: 340)
        .background(TutorialCardBackground(gradient: gradient))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 12, x: 0, y: 6)
        .shadow(color: (gradient.first ?? .gray).opacity(colorScheme == .dark ? 0.2 : 0.12), radius: 20, x: 0, y: 10)
    }
}

// MARK: - Tutorial Streak Flame

struct TutorialStreakFlame: View {
    let gradient: [Color]
    let isAnimating: Bool
    
    private let streakNumber = 7
    
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.orange.opacity(0.3), Color.clear],
                        center: .center, startRadius: 50, endRadius: 120
                    )
                )
                .frame(width: 240, height: 240)
                .scaleEffect(isAnimating ? 1.1 : 1.0)
            
            Circle()
                .fill(LinearGradient(gradient: Gradient(colors: gradient), startPoint: .top, endPoint: .bottom))
                .frame(width: 80, height: 80)
                .offset(y: 12)
            
            Image(systemName: "flame.fill")
                .font(.system(size: 120, weight: .regular))
                .foregroundStyle(LinearGradient(gradient: Gradient(colors: gradient), startPoint: .top, endPoint: .bottom))
                .shadow(color: .orange.opacity(0.5), radius: 20, x: 0, y: 4)
                .offset(y: isAnimating ? -4 : 4)
            
            Text("\(streakNumber)")
                .font(.system(size: 56, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 2)
                .offset(y: 12)
        }
        .frame(width: 180, height: 180)
    }
}

// MARK: - Tutorial Water Tracking

struct TutorialWaterTracking: View {
    @Environment(\.colorScheme) private var colorScheme
    let gradient: [Color]
    let isAnimating: Bool
    
    private let progress: Double = 0.72
    private let currentMl: Int = 1800
    private let goalMl: Int = 2500
    private let remainingMl: Int = 700
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Image(systemName: "drop.fill")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                
                Text("Hydration")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            
            HStack(spacing: 20) {
                ZStack {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 90))
                        .foregroundColor(.blue.opacity(0.15))
                    
                    Image(systemName: "drop.fill")
                        .font(.system(size: 90))
                        .foregroundStyle(LinearGradient(colors: gradient, startPoint: .bottom, endPoint: .top))
                        .mask(
                            VStack(spacing: 0) {
                                Rectangle().fill(Color.clear).frame(height: 90 * (1 - progress))
                                Rectangle().fill(Color.white)
                            }
                        )
                    
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 2)
                        .offset(y: 15)
                }
                .frame(width: 100, height: 110)
                .scaleEffect(isAnimating ? 1.05 : 1.0)
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(formatMl(currentMl))
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        Text("/ \(formatMl(goalMl))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Text("\(formatMl(remainingMl)) remaining")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 6) {
                        Circle().fill(gradient[0]).frame(width: 8, height: 8)
                        Text("Great progress!")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(gradient[0])
                    }
                    .padding(.top, 4)
                }
                
                Spacer()
            }
            .padding(.horizontal, 20)
            
            HStack(spacing: 10) {
                quickAddButton(amount: 250, label: "Cup")
                quickAddButton(amount: 500, label: "Bottle")
                quickAddButton(amount: 750, label: "Large")
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: 340)
        .background(TutorialCardBackground(gradient: gradient))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 12, x: 0, y: 6)
        .shadow(color: (gradient.first ?? .cyan).opacity(colorScheme == .dark ? 0.2 : 0.12), radius: 20, x: 0, y: 10)
    }
    
    private func quickAddButton(amount: Int, label: String) -> some View {
        VStack(spacing: 4) {
            Text("\(amount)")
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(gradient[0])
            Text("ml")
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color(white: 0.15), Color.cardBackground]
                            : [Color.white, Color.white.opacity(0.95)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(gradient[0].opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.2 : 0.05), radius: 4, x: 0, y: 2)
    }
    
    private func formatMl(_ ml: Int) -> String {
        if ml >= 1000 {
            return String(format: "%.1fL", Double(ml) / 1000.0)
        }
        return "\(ml)ml"
    }
}

// MARK: - Tutorial Health Apps Widget

struct TutorialHealthAppsWidget: View {
    @Environment(\.colorScheme) private var colorScheme
    let gradient: [Color]
    let isAnimating: Bool
    
    private struct HealthApp {
        let name: String
        let icon: String
        let colors: [Color]
        let description: String
    }
    
    private let apps: [HealthApp] = [
        HealthApp(name: "Apple Health", icon: "heart.fill", colors: [.red, .pink], description: "Steps, calories, workouts"),
        HealthApp(name: "Strava", icon: "figure.run", colors: [.orange, Color(red: 0.95, green: 0.4, blue: 0.1)], description: "Runs, rides, activities"),
        HealthApp(name: "Fitbit", icon: "waveform.path.ecg", colors: [.teal, .cyan], description: "Steps, sleep, heart rate")
    ]
    
    var body: some View {
        VStack(spacing: 12) {
            ForEach(Array(apps.enumerated()), id: \.offset) { index, app in
                healthAppRow(app: app, delay: Double(index) * 0.1)
            }
        }
        .frame(maxWidth: 340)
    }
    
    private func healthAppRow(app: HealthApp, delay: Double) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: app.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 48, height: 48)
                    .shadow(color: app.colors[0].opacity(0.4), radius: 8, x: 0, y: 4)
                
                Image(systemName: app.icon)
                    .font(.ds_heading2)
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(app.name)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text(app.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text("Connect")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.xs)
                .background(
                    LinearGradient(colors: app.colors, startPoint: .leading, endPoint: .trailing)
                )
                .clipShape(Capsule())
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 14)
        .background(TutorialCardBackground(gradient: app.colors))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.2 : 0.06), radius: 8, x: 0, y: 4)
        .shadow(color: app.colors[0].opacity(colorScheme == .dark ? 0.15 : 0.08), radius: 12, x: 0, y: 6)
    }
}

// MARK: - Tutorial Trial CTA

struct TutorialTrialCTA: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var storeKit = StoreKitManager.shared
    let gradient: [Color]
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
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [gradient[0].opacity(0.3), Color.clear], center: .center, startRadius: 10, endRadius: 60))
                    .frame(width: 100, height: 100)
                    .scaleEffect(isAnimating ? 1.1 : 0.95)

                Circle()
                    .fill(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 56, height: 56)
                    .shadow(color: gradient[0].opacity(0.5), radius: 12, x: 0, y: 6)

                Image(systemName: "crown.fill")
                    .font(.ds_heading2)
                    .foregroundColor(.white)
            }

            VStack(spacing: 10) {
                ForEach(Array(features.enumerated()), id: \.offset) { _, feature in
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.ds_labelLarge)
                            .foregroundStyle(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                        Text(feature.text)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, Spacing.xs)

            Button(action: {
                HapticManager.tap()
                Task { await startTrial() }
            }) {
                HStack(spacing: 8) {
                    if storeKit.purchaseState == .purchasing {
                        ProgressView().tint(.white)
                    } else {
                        Text("Start Free 3-Day Trial")
                            .font(.headline)
                            .fontWeight(.bold)
                        Image(systemName: "arrow.right")
                            .font(.subheadline.weight(.bold))
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.md)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.4, green: 0.5, blue: 1.0), Color(red: 0.6, green: 0.4, blue: 1.0)],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .shadow(color: .purple.opacity(0.4), radius: 12, x: 0, y: 6)
                )
            }
            .disabled(storeKit.purchaseState == .purchasing)

            HStack(spacing: 4) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.caption2)
                    .foregroundColor(.green)
                Text("Cancel anytime • No commitment")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Button(action: {
                HapticManager.tap()
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    isPresented = false
                }
            }) {
                Text("Maybe Later")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 20)
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

// MARK: - Shared Tutorial Card Background

struct TutorialCardBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    let gradient: [Color]

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill((gradient.first ?? .gray).opacity(colorScheme == .dark ? 0.15 : 0.08))
                .offset(y: 8)
                .blur(radius: 4)

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                .offset(y: 4)

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(colorScheme == .dark ? Color(red: 0.11, green: 0.11, blue: 0.12) : Color.white)

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color.white.opacity(0.1), Color.white.opacity(0.02), Color.clear]
                            : [Color.white, Color.white.opacity(0.5), Color.clear],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 1.5
                )

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            (gradient.first ?? .gray).opacity(colorScheme == .dark ? 0.4 : 0.3),
                            (gradient.last ?? .gray).opacity(colorScheme == .dark ? 0.3 : 0.2)
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
    }
}

// MARK: - Preview

#Preview {
    WelcomeTutorialView(isPresented: .constant(true))
}
