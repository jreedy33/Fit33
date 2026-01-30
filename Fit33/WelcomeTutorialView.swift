import SwiftUI

// MARK: - Welcome Tutorial View
// Professional onboarding tutorial shown to new users after account creation
// Designed with Apple/Meta-quality UX patterns

struct WelcomeTutorialView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var isPresented: Bool
    
    @State private var currentPage = 0
    @State private var showingGetStarted = false
    @State private var animateContent = false
    @State private var iconBounce = false
    @State private var backgroundPulse = false
    
    private let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
    private let selectionFeedback = UISelectionFeedbackGenerator()
    
    // Tutorial pages - each represents a key feature
    // Designed with Nike-level polish: concise, impactful copy
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
            title: "Auto-Generate",
            subtitle: "Smart workouts in seconds",
            description: "Set your time, target muscles, and equipment.\nWe'll create your personalized workout.",
            icon: "sparkles",
            iconColor: .purple,
            gradient: [Color.purple, Color.pink],
            animationType: .sparkle,
            useAppButton: true,
            buttonTitle: "Auto Workout",
            buttonSubtitle: "AI-powered routine"
        ),
        TutorialPage(
            title: "Build Custom",
            subtitle: "Complete creative control",
            description: "5,000+ exercises with video demos.\nCreate your perfect routine from scratch.",
            icon: "plus.circle.fill",
            iconColor: .blue,
            gradient: [Color.blue, Color.cyan],
            animationType: .bounce,
            useAppButton: true,
            buttonTitle: "Custom Workout",
            buttonSubtitle: "Build your own"
        ),
        TutorialPage(
            title: "Programs",
            subtitle: "Your 30-day transformation",
            description: "Complete training programs tailored to your goals.\nProgressive workouts that evolve with you.",
            icon: "calendar.badge.clock",
            iconColor: .green,
            gradient: [Color.green, Color.mint],
            animationType: .wave,
            useProgramWidget: true
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
            useMealTracking: true
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
            title: "Community",
            subtitle: "Better together",
            description: "Share workouts with friends.\nStay motivated and accountable.",
            icon: "person.2.fill",
            iconColor: .indigo,
            gradient: [Color.indigo, Color.purple],
            animationType: .float
        ),
        TutorialPage(
            title: "Let's Go",
            subtitle: "Your journey starts now",
            description: "You're ready.\nStart your first workout today.",
            icon: "checkmark.seal.fill",
            iconColor: .green,
            gradient: [Color.green, Color.mint],
            animationType: .celebrate
        )
    ]
    
    var body: some View {
        ZStack {
            // Animated background - fills entire screen
            animatedBackground
                .ignoresSafeArea(.all)
            
            VStack(spacing: 0) {
                // Skip button (top right) - refined styling
                HStack {
                    Spacer()
                    
                    if currentPage < tutorialPages.count - 1 {
                        Button(action: skipTutorial) {
                            Text("Skip")
                                .font(.system(size: 15, weight: .semibold))
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
                .padding(.horizontal, 16)
                .padding(.top, 12)
                
                // Main content
                TabView(selection: $currentPage) {
                    ForEach(Array(tutorialPages.enumerated()), id: \.offset) { index, page in
                        TutorialPageView(
                            page: page,
                            isActive: currentPage == index,
                            animateContent: animateContent
                        )
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .background(.clear)
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: currentPage)
                
                // Page indicator + Navigation - transparent background
                VStack(spacing: 28) {
                    // Custom page indicator - refined dots
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
                    
                    // Navigation button - premium styling
                    if currentPage == tutorialPages.count - 1 {
                        // Get Started button (final page) - FILLED gradient style
                        Button(action: completeTutorial) {
                            HStack(spacing: 10) {
                                Text("Get Started")
                                    .font(.system(size: 17, weight: .bold))
                                
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 15, weight: .bold))
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
                        .buttonStyle(TutorialScaleButtonStyle())
                        .padding(.horizontal, 36)
                    } else {
                        // Continue button - hollow style with gradient border
                        Button(action: nextPage) {
                            HStack(spacing: 10) {
                                Text("Continue")
                                    .font(.system(size: 17, weight: .bold))
                                
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .bold))
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
                        .buttonStyle(TutorialScaleButtonStyle())
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
            
            // Start background animation
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
            // Base gradient - fills entire screen
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
            
            // Animated gradient orbs - must also ignore safe area
            GeometryReader { geometry in
                ZStack {
                    // Center orb (main glow)
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
                    
                    // Top-left orb
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
                    
                    // Bottom-right orb
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
        
        // Dismiss with animation
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
    var useLogoImage: Bool = false  // If true, show Fit33 logo instead of SF Symbol
    var useAppButton: Bool = false  // If true, show actual app button design
    var useProgramWidget: Bool = false  // If true, show program widget
    var useStreakFlame: Bool = false  // If true, show streak flame
    var useMealTracking: Bool = false  // If true, show meal tracking UI
    var useWaterWidget: Bool = false  // If true, show water tracking widget
    var buttonTitle: String = "Auto Workout"  // Title shown on app button
    var buttonSubtitle: String = "Auto-generated routine"  // Subtitle shown on app button
    
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
    
    @State private var iconAnimation = false
    @State private var sparkleOffset: CGFloat = 0
    @State private var particles: [ParticleData] = []
    
    // Screen height for adaptive spacing
    private var screenHeight: CGFloat {
        UIScreen.main.bounds.height
    }
    
    // Adaptive spacing based on screen size and content type
    private var topPadding: CGFloat {
        if page.useLogoImage {
            return screenHeight * 0.08
        } else if page.useMealTracking || page.useWaterWidget {
            // Meal and water widgets need more top space to not crowd the top
            return screenHeight * 0.08
        } else if page.useProgramWidget || page.useStreakFlame {
            return screenHeight * 0.06
        } else {
            return screenHeight * 0.06
        }
    }
    
    private var contentSpacing: CGFloat {
        if page.useLogoImage {
            return 0
        } else if page.useMealTracking || page.useWaterWidget || page.useProgramWidget {
            return 20
        } else {
            return 28
        }
    }
    
    private var bottomTextSpacing: CGFloat {
        page.useLogoImage ? 24 : 36
    }
    
    // Max height for the visual element based on content type
    private var visualMaxHeight: CGFloat {
        if page.useLogoImage {
            return 0.42  // Logo page
        } else if page.useMealTracking {
            return 0.38  // Meal tracking needs less vertical space
        } else if page.useWaterWidget || page.useProgramWidget {
            return 0.36
        } else if page.useStreakFlame {
            return 0.32
        } else if page.useAppButton {
            return 0.30  // Buttons are compact
        } else {
            return 0.28  // Default icons
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            // UNIFIED LAYOUT for all pages (including welcome)
            VStack(spacing: 0) {
                // Top spacer - slightly more for welcome page
                Spacer()
                    .frame(height: page.useLogoImage ? 30 : topPadding)
                
                // Flexible space before visual element
                Spacer()
                    .frame(minHeight: 10, maxHeight: page.useLogoImage ? 60 : 40)
                
                // === CENTER SECTION: Visual Element ===
                ZStack {
                    if page.useLogoImage {
                        // Welcome page: Logo as the visual element
                        welcomeLogoView
                    } else if page.useAppButton {
                        featureButtonView
                    } else if page.useProgramWidget {
                        TutorialProgramWidget(gradient: page.gradient, isAnimating: iconAnimation)
                            .scaleEffect(0.9)
                            .offset(y: iconAnimation ? -3 : 3)
                    } else if page.useStreakFlame {
                        TutorialStreakFlame(gradient: page.gradient, isAnimating: iconAnimation)
                    } else if page.useMealTracking {
                        TutorialMealTracking(gradient: page.gradient, isAnimating: iconAnimation)
                            .scaleEffect(0.85)
                    } else if page.useWaterWidget {
                        TutorialWaterTracking(gradient: page.gradient, isAnimating: iconAnimation)
                            .scaleEffect(0.88)
                    } else {
                        defaultIconView
                    }
                }
                .scaleEffect(animateContent ? 1 : 0.8)
                .opacity(animateContent ? 1 : 0)
                .frame(maxHeight: geometry.size.height * (page.useLogoImage ? 0.35 : visualMaxHeight))
                
                // Flexible space after visual element
                Spacer()
                    .frame(minHeight: page.useLogoImage ? 30 : contentSpacing, maxHeight: page.useLogoImage ? 50 : contentSpacing + 20)
                
                // === BOTTOM SECTION: Text Content ===
                VStack(spacing: 0) {
                    // Title - welcome page shows "Welcome to" above logo, so skip it here
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
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .opacity(animateContent ? 1 : 0)
                        .offset(y: animateContent ? 0 : 15)
                        .padding(.bottom, 14)
                    
                    Text(page.description)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.65) : Color.black.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .lineSpacing(5)
                        .padding(.horizontal, 32)
                        .fixedSize(horizontal: false, vertical: true)
                        .opacity(animateContent ? 1 : 0)
                        .offset(y: animateContent ? 0 : 10)
                }
                .animation(.easeOut(duration: 0.5).delay(0.15), value: animateContent)
                .padding(.horizontal, 16)
                
                // Bottom spacer
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
            if active {
                startIconAnimation()
            }
        }
    }
    
    // MARK: - Welcome Logo View (Grand & Dominant)
    private var welcomeLogoView: some View {
        VStack(spacing: 20) {
            // "Welcome to" title - part of the centered unit
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
            
            // Logo with glow effects
            ZStack {
                // Massive outer glow - creates depth and grandeur
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                page.gradient[0].opacity(0.35),
                                page.gradient[1].opacity(0.2),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 40,
                            endRadius: 280
                        )
                    )
                    .frame(width: 500, height: 500)
                    .blur(radius: 40)
                    .scaleEffect(iconAnimation ? 1.08 : 1.0)
                
                // Secondary glow ring
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                page.gradient[0].opacity(0.25),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 100,
                            endRadius: 180
                        )
                    )
                    .frame(width: 360, height: 360)
                    .scaleEffect(iconAnimation ? 1.05 : 0.98)
                
                // The grand logo
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
    
    // MARK: - Feature Button View
    private var featureButtonView: some View {
        VStack(spacing: 14) {
            ZStack {
                // Glow behind icon
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                page.gradient[0].opacity(0.4),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 10,
                            endRadius: 50
                        )
                    )
                    .frame(width: 100, height: 100)
                    .scaleEffect(iconAnimation ? 1.1 : 0.95)
                
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: page.gradient),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)
                    .shadow(color: page.gradient.first?.opacity(0.5) ?? .clear, radius: 12, x: 0, y: 6)
                
                Image(systemName: page.icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            VStack(spacing: 6) {
                Text(page.buttonTitle)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                
                Text(page.buttonSubtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(width: 180, height: 160)
        .background(
            ZStack {
                // Deep shadow for depth
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill((page.gradient.first ?? .gray).opacity(colorScheme == .dark ? 0.2 : 0.1))
                    .offset(y: 10)
                    .blur(radius: 6)
                
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.25 : 0.05))
                    .offset(y: 5)
                
                // Main card
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        colorScheme == .dark
                            ? Color(red: 0.13, green: 0.13, blue: 0.16)
                            : Color.white
                    )
                
                // Subtle gradient overlay
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                page.gradient[0].opacity(colorScheme == .dark ? 0.5 : 0.35),
                                page.gradient[1].opacity(colorScheme == .dark ? 0.3 : 0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            }
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.1), radius: 16, x: 0, y: 8)
        .shadow(color: (page.gradient.first ?? .gray).opacity(0.2), radius: 24, x: 0, y: 12)
        .scaleEffect(iconAnimation ? 1.03 : 0.98)
        .offset(y: iconAnimation ? -4 : 4)
    }
    
    // MARK: - Default Icon View
    private var defaultIconView: some View {
        ZStack {
            // Glow effect
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
            
            // Background circle
            Circle()
                .fill(
                    LinearGradient(
                        colors: page.gradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 140, height: 140)
                .shadow(color: page.gradient[0].opacity(0.6), radius: 25, x: 0, y: 12)
            
            // Icon
            Image(systemName: page.icon)
                .font(.system(size: 58, weight: .semibold))
                .foregroundColor(.white)
                .offset(y: iconAnimation ? -4 : 4)
            
            // Sparkle particles
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

// MARK: - Tutorial Button Style

struct TutorialScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

// MARK: - Tutorial Program Widget

struct TutorialProgramWidget: View {
    @Environment(\.colorScheme) private var colorScheme
    let gradient: [Color]
    let isAnimating: Bool
    
    // Sample program data
    private let completionPercentage: Double = 0.81 // 17/21 days
    private let currentDay = 17
    private let totalDays = 21
    private let programName = "Foundation Builder"
    private let weekLabel = "Week 3/3"
    
    var body: some View {
        VStack(spacing: 0) {
            // Top Section - Program Info & Progress Ring
            HStack(alignment: .top, spacing: 14) {
                // Progress Ring
                ZStack {
                    // Track
                    Circle()
                        .stroke(Color.gray.opacity(0.15), lineWidth: 5)
                        .frame(width: 68, height: 68)
                    
                    // Progress
                    Circle()
                        .trim(from: 0, to: completionPercentage)
                        .stroke(
                            LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing),
                            style: StrokeStyle(lineWidth: 5, lineCap: .round)
                        )
                        .frame(width: 68, height: 68)
                        .rotationEffect(.degrees(-90))
                    
                    // Center percentage
                    VStack(spacing: -2) {
                        Text("\(Int(completionPercentage * 100))")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(gradient.first ?? .green)
                        Text("%")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    // Program name
                    Text(programName)
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    // Week and day progress
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
                
                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(16)
            
            Divider()
                .padding(.horizontal, 16)
            
            // Today's workout card
            HStack(spacing: 12) {
                // Day badge
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: gradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                    
                    Text("Day \(currentDay)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                
                // Workout info
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
                
                // Start button
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text("Start")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    LinearGradient(
                        colors: gradient,
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(Capsule())
            }
            .padding(16)
        }
        .frame(maxWidth: 340)
        .background(
            ZStack {
                // Depth shadows
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill((gradient.first ?? .gray).opacity(colorScheme == .dark ? 0.15 : 0.08))
                    .offset(y: 8)
                    .blur(radius: 4)
                
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                    .offset(y: 4)
                
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        colorScheme == .dark
                            ? Color(red: 0.11, green: 0.11, blue: 0.12)
                            : Color.white
                    )
                
                // Inner highlight
                RoundedRectangle(cornerRadius: 16, style: .continuous)
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
                
                // Colored accent border
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                (gradient.first ?? .gray).opacity(colorScheme == .dark ? 0.4 : 0.3),
                                (gradient.last ?? .gray).opacity(colorScheme == .dark ? 0.3 : 0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 12, x: 0, y: 6)
        .shadow(color: (gradient.first ?? .gray).opacity(colorScheme == .dark ? 0.2 : 0.12), radius: 20, x: 0, y: 10)
    }
}

// MARK: - Tutorial Streak Flame

struct TutorialStreakFlame: View {
    let gradient: [Color]
    let isAnimating: Bool
    
    private let streakNumber = 10
    
    var body: some View {
        ZStack {
            // Glow effect
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.orange.opacity(0.3), Color.clear],
                        center: .center,
                        startRadius: 50,
                        endRadius: 120
                    )
                )
                .frame(width: 240, height: 240)
                .scaleEffect(isAnimating ? 1.1 : 1.0)
            
            // Solid fill behind the flame to fill the hole
            Circle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: gradient),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 80, height: 80)
                .offset(y: 12)
            
            // Flame icon
            Image(systemName: "flame.fill")
                .font(.system(size: 120, weight: .regular))
                .foregroundStyle(
                    LinearGradient(
                        gradient: Gradient(colors: gradient),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: .orange.opacity(0.5), radius: 20, x: 0, y: 4)
                .offset(y: isAnimating ? -4 : 4)
            
            // Streak number centered in flame
            Text("\(streakNumber)")
                .font(.system(size: 56, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 2)
                .offset(y: 12)
        }
        .frame(width: 180, height: 180)
    }
}

// MARK: - Tutorial Meal Tracking

struct TutorialMealTracking: View {
    @Environment(\.colorScheme) private var colorScheme
    let gradient: [Color]
    let isAnimating: Bool
    
    // Sample meal data
    private struct MealData {
        let name: String
        let icon: String
        let calories: Int
        let items: Int
        let gradientColors: [Color]
    }
    
    private let meals: [MealData] = [
        MealData(name: "Breakfast", icon: "sunrise.fill", calories: 71, items: 1, gradientColors: [.orange, .yellow]),
        MealData(name: "Lunch", icon: "sun.max.fill", calories: 287, items: 1, gradientColors: [.green, .teal]),
        MealData(name: "Dinner", icon: "moon.stars.fill", calories: 130, items: 1, gradientColors: [.blue, .cyan]),
        MealData(name: "Snacks", icon: "leaf.fill", calories: 532, items: 1, gradientColors: [.purple, .pink])
    ]
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "fork.knife")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(
                        LinearGradient(
                            colors: gradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                Text("Track Your Meals")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            
            // Meal cards
            VStack(spacing: 10) {
                ForEach(Array(meals.enumerated()), id: \.offset) { index, meal in
                    mealCard(meal: meal)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: 340)
        .background(
            ZStack {
                // Depth shadows
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill((gradient.first ?? .gray).opacity(colorScheme == .dark ? 0.15 : 0.08))
                    .offset(y: 8)
                    .blur(radius: 4)
                
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                    .offset(y: 4)
                
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        colorScheme == .dark
                            ? Color(red: 0.11, green: 0.11, blue: 0.12)
                            : Color.white
                    )
                
                // Inner highlight
                RoundedRectangle(cornerRadius: 20, style: .continuous)
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
                
                // Colored accent border
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                (gradient.first ?? .gray).opacity(colorScheme == .dark ? 0.4 : 0.3),
                                (gradient.last ?? .gray).opacity(colorScheme == .dark ? 0.3 : 0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 12, x: 0, y: 6)
        .shadow(color: (gradient.first ?? .gray).opacity(colorScheme == .dark ? 0.2 : 0.12), radius: 20, x: 0, y: 10)
    }
    
    private func mealCard(meal: MealData) -> some View {
        HStack(spacing: 12) {
            // Circular gradient icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: meal.gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                    .shadow(color: meal.gradientColors[0].opacity(0.25), radius: 4, x: 0, y: 2)
                
                Image(systemName: meal.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            // Meal info
            VStack(alignment: .leading, spacing: 2) {
                Text(meal.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                HStack(spacing: 8) {
                    Text("\(meal.items) item")
                        .font(.caption)
                        .foregroundColor(meal.gradientColors[0])
                        .fontWeight(.medium)
                    
                    Text("•")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text("\(meal.calories) cal")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Calories display
            HStack(spacing: 6) {
                Text("\(meal.calories)")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(meal.gradientColors[0])
                Text("cal")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            // Chevron
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            ZStack {
                // Subtle shadow layers
                RoundedRectangle(cornerRadius: 28)
                    .fill(meal.gradientColors[0].opacity(colorScheme == .dark ? 0.06 : 0.03))
                    .offset(y: 4)
                    .blur(radius: 2)
                
                RoundedRectangle(cornerRadius: 26)
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.08 : 0.02))
                    .offset(y: 2)
                
                // Main card background
                RoundedRectangle(cornerRadius: 25)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color(white: 0.15), Color(white: 0.12)]
                                : [Color.white, Color.white.opacity(0.98)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                // Inner highlight
                RoundedRectangle(cornerRadius: 25)
                    .stroke(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color.white.opacity(0.08), Color.clear]
                                : [Color.white, Color.white.opacity(0.3), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                
                // Subtle accent border
                RoundedRectangle(cornerRadius: 25)
                    .stroke(
                        LinearGradient(
                            colors: [
                                meal.gradientColors[0].opacity(colorScheme == .dark ? 0.2 : 0.12),
                                meal.gradientColors[1].opacity(colorScheme == .dark ? 0.1 : 0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.15 : 0.04), radius: 6, x: 0, y: 3)
    }
}

// MARK: - Tutorial Water Tracking

struct TutorialWaterTracking: View {
    @Environment(\.colorScheme) private var colorScheme
    let gradient: [Color]
    let isAnimating: Bool
    
    // Sample water data (75% of 2500ml goal)
    private let progress: Double = 0.75
    private let currentMl: Int = 1875
    private let goalMl: Int = 2500
    private let remainingMl: Int = 625
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Image(systemName: "drop.fill")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(
                        LinearGradient(
                            colors: gradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                Text("Hydration")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            
            // Main content - Water drop and stats
            HStack(spacing: 20) {
                // Water drop visual (75% filled)
                ZStack {
                    // Background drop
                    Image(systemName: "drop.fill")
                        .font(.system(size: 90))
                        .foregroundColor(.blue.opacity(0.15))
                    
                    // Filled level (75%)
                    Image(systemName: "drop.fill")
                        .font(.system(size: 90))
                        .foregroundStyle(
                            LinearGradient(
                                colors: gradient,
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .mask(
                            VStack(spacing: 0) {
                                Rectangle()
                                    .fill(Color.clear)
                                    .frame(height: 90 * (1 - progress))
                                Rectangle()
                                    .fill(Color.white)
                            }
                        )
                    
                    // Percentage text
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 2)
                        .offset(y: 15)
                }
                .frame(width: 100, height: 110)
                .scaleEffect(isAnimating ? 1.05 : 1.0)
                
                // Stats
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(formatMl(currentMl))")
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
                    
                    // Status badge
                    HStack(spacing: 6) {
                        Circle()
                            .fill(gradient[0])
                            .frame(width: 8, height: 8)
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
            
            // Quick add buttons
            HStack(spacing: 10) {
                quickAddButton(amount: 250, label: "Cup")
                quickAddButton(amount: 500, label: "Bottle")
                quickAddButton(amount: 750, label: "Large")
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: 340)
        .background(
            ZStack {
                // Depth shadows
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill((gradient.first ?? .cyan).opacity(colorScheme == .dark ? 0.15 : 0.08))
                    .offset(y: 8)
                    .blur(radius: 4)
                
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                    .offset(y: 4)
                
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        colorScheme == .dark
                            ? Color(red: 0.11, green: 0.11, blue: 0.12)
                            : Color.white
                    )
                
                // Inner highlight
                RoundedRectangle(cornerRadius: 20, style: .continuous)
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
                
                // Colored accent border
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                (gradient.first ?? .cyan).opacity(colorScheme == .dark ? 0.4 : 0.3),
                                (gradient.last ?? .blue).opacity(colorScheme == .dark ? 0.3 : 0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
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
                            ? [Color(white: 0.15), Color(white: 0.12)]
                            : [Color.white, Color.white.opacity(0.95)],
                        startPoint: .top,
                        endPoint: .bottom
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
            let liters = Double(ml) / 1000.0
            return String(format: "%.1fL", liters)
        } else {
            return "\(ml)ml"
        }
    }
}

// MARK: - Preview

#Preview {
    WelcomeTutorialView(isPresented: .constant(true))
}
