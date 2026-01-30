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
    private let tutorialPages: [TutorialPage] = [
        TutorialPage(
            title: "Welcome to",
            subtitle: "Your intelligent fitness companion",
            description: "Build the perfect workout every time. Let's take a quick tour of what you can do.",
            icon: "figure.strengthtraining.traditional",
            iconColor: .blue,
            gradient: [Color.blue, Color.cyan.opacity(0.8)],
            animationType: .pulse,
            useLogoImage: true  // Show Fit33 logo instead of icon
        ),
        TutorialPage(
            title: "Auto-Generate Workouts",
            subtitle: "Smart workouts in seconds",
            description: "Tell us how long you have, what muscles to target, and what equipment you have. Our recommendation system creates a personalized workout instantly.",
            icon: "dumbbell.fill",
            iconColor: .purple,
            gradient: [Color.purple, Color.pink],
            animationType: .sparkle,
            useAppButton: true  // Show actual app button
        ),
        TutorialPage(
            title: "Build Custom Workouts",
            subtitle: "Complete creative control",
            description: "Browse our library of 5,000+ exercises with video demos. Build your perfect routine from scratch.",
            icon: "plus.circle.fill",
            iconColor: .blue,
            gradient: [Color.blue, Color.cyan],
            animationType: .bounce,
            useAppButton: true,  // Show actual app button
            buttonTitle: "Custom Workout",
            buttonSubtitle: "Build your own"
        ),
        TutorialPage(
            title: "Personalized Programs",
            subtitle: "Your 30-day transformation",
            description: "Get a complete training program tailored to your goals, experience, and schedule. Progressive workouts that evolve with you.",
            icon: "calendar.badge.clock",
            iconColor: .green,
            gradient: [Color.green, Color.mint],
            animationType: .wave,
            useProgramWidget: true  // Show actual program widget
        ),
        TutorialPage(
            title: "Build Your Streak",
            subtitle: "Stay consistent, see results",
            description: "Complete a workout each day to build your streak. The longer your streak, the stronger your habit. Miss a day? No worries—your progress stays, and you can start fresh tomorrow.",
            icon: "flame.fill",
            iconColor: .orange,
            gradient: [Color.orange, Color.red],
            animationType: .pulse,
            useStreakFlame: true  // Show actual streak flame
        ),
        TutorialPage(
            title: "Track Your Meals",
            subtitle: "Monitor your nutrition",
            description: "Log your meals throughout the day and track calories, protein, carbs, and fats. Stay on top of your nutrition goals.",
            icon: "fork.knife",
            iconColor: .pink,
            gradient: [Color.pink, Color.purple],
            animationType: .float,
            useMealTracking: true  // Show actual meal widget
        ),
        TutorialPage(
            title: "Stay Hydrated",
            subtitle: "Track your water intake",
            description: "Log your daily water consumption and reach your hydration goals. Get reminders and track your progress with an intuitive interface.",
            icon: "drop.fill",
            iconColor: .cyan,
            gradient: [Color.cyan, Color.blue],
            animationType: .wave,
            useWaterWidget: true  // Show water tracking widget
        ),
        TutorialPage(
            title: "Train With Friends",
            subtitle: "Share your best workouts",
            description: "Send workouts directly to friends, see what they're doing, and stay motivated together. Fitness is better with community.",
            icon: "person.2.fill",
            iconColor: .cyan,
            gradient: [Color.cyan, Color.blue],
            animationType: .float
        ),
        TutorialPage(
            title: "Ready to Go!",
            subtitle: "Let's build something amazing",
            description: "You're all set! Start with an auto-generated workout, or explore on your own. We're here to help you reach your goals.",
            icon: "checkmark.seal.fill",
            iconColor: .green,
            gradient: [Color.green, Color.mint],
            animationType: .celebrate
        )
    ]
    
    var body: some View {
        ZStack {
            // Animated background
            animatedBackground
            
            VStack(spacing: 0) {
                // Skip button (top right)
                HStack {
                    Spacer()
                    
                    if currentPage < tutorialPages.count - 1 {
                        Button(action: skipTutorial) {
                            Text("Skip")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                
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
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: currentPage)
                
                // Page indicator + Navigation
                VStack(spacing: 24) {
                    // Custom page indicator
                    HStack(spacing: 8) {
                        ForEach(0..<tutorialPages.count, id: \.self) { index in
                            Capsule()
                                .fill(
                                    index == currentPage
                                        ? LinearGradient(colors: tutorialPages[currentPage].gradient, startPoint: .leading, endPoint: .trailing)
                                        : LinearGradient(colors: [Color.gray.opacity(0.3)], startPoint: .leading, endPoint: .trailing)
                                )
                                .frame(width: index == currentPage ? 24 : 8, height: 8)
                                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: currentPage)
                        }
                    }
                    .padding(.bottom, 8)
                    
                    // Navigation button
                    if currentPage == tutorialPages.count - 1 {
                        // Get Started button (final page) - hollow style matching page color
                        Button(action: completeTutorial) {
                            HStack(spacing: 8) {
                                Text("Get Started")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundStyle(
                                LinearGradient(
                                    colors: tutorialPages[currentPage].gradient,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(
                                Capsule()
                                    .fill(Color(.systemGray6))
                            )
                            .overlay(
                                Capsule()
                                    .stroke(
                                        LinearGradient(
                                            colors: tutorialPages[currentPage].gradient,
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        ),
                                        lineWidth: 2
                                    )
                            )
                        }
                        .buttonStyle(TutorialScaleButtonStyle())
                        .padding(.horizontal, 40)
                    } else {
                        // Continue button - hollow style matching page color
                        Button(action: nextPage) {
                            HStack(spacing: 8) {
                                Text("Continue")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundStyle(
                                LinearGradient(
                                    colors: tutorialPages[currentPage].gradient,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(
                                Capsule()
                                    .fill(Color(.systemGray6))
                            )
                            .overlay(
                                Capsule()
                                    .stroke(
                                        LinearGradient(
                                            colors: tutorialPages[currentPage].gradient,
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        ),
                                        lineWidth: 2
                                    )
                            )
                        }
                        .buttonStyle(TutorialScaleButtonStyle())
                        .padding(.horizontal, 40)
                    }
                }
                .padding(.bottom, 50)
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
            // Base gradient
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
            .ignoresSafeArea()
            
            // Animated gradient orbs
            GeometryReader { geometry in
                ZStack {
                    // Top orb
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    tutorialPages[currentPage].gradient[0].opacity(0.3),
                                    tutorialPages[currentPage].gradient[0].opacity(0)
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: 200
                            )
                        )
                        .frame(width: 400, height: 400)
                        .offset(x: backgroundPulse ? -50 : -100, y: backgroundPulse ? -150 : -180)
                        .animation(.easeInOut(duration: 4).repeatForever(autoreverses: true), value: backgroundPulse)
                    
                    // Bottom orb
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    tutorialPages[currentPage].gradient[1].opacity(0.25),
                                    tutorialPages[currentPage].gradient[1].opacity(0)
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: 250
                            )
                        )
                        .frame(width: 500, height: 500)
                        .offset(x: backgroundPulse ? 150 : 100, y: backgroundPulse ? geometry.size.height * 0.4 : geometry.size.height * 0.5)
                        .animation(.easeInOut(duration: 5).repeatForever(autoreverses: true), value: backgroundPulse)
                }
            }
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
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(maxHeight: 60)
            
            // Title with gradient (moved above icon/widget)
            Text(page.title)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: page.gradient,
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .multilineTextAlignment(.center)
                .opacity(animateContent ? 1 : 0)
                .offset(y: animateContent ? 0 : 20)
                .padding(.bottom, 24)
            
            // Animated icon/logo container
            ZStack {
                if page.useLogoImage {
                    // Fit33 Logo for welcome page - Grand and prominent
                    VStack(spacing: 0) {
                        ZStack {
                            // Outer glow
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [
                                            page.gradient[0].opacity(0.3),
                                            page.gradient[1].opacity(0.2),
                                            Color.clear
                                        ],
                                        center: .center,
                                        startRadius: 60,
                                        endRadius: 200
                                    )
                                )
                                .frame(width: 400, height: 400)
                                .blur(radius: 25)
                                .scaleEffect(iconAnimation ? 1.1 : 1.0)
                            
                            // Logo with enhanced styling
                            Image("fit33-logo")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 380, height: 160)
                                .shadow(color: page.gradient[0].opacity(0.6), radius: 40, x: 0, y: 15)
                                .shadow(color: page.gradient[1].opacity(0.4), radius: 25, x: 0, y: 10)
                                .shadow(color: .black.opacity(0.3), radius: 15, x: 0, y: 5)
                                .offset(y: iconAnimation ? -4 : 4)
                        }
                    }
                } else if page.useAppButton {
                    // Show actual app button (Auto Workout style)
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: page.gradient),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 50, height: 50)
                                .shadow(color: page.gradient.first?.opacity(0.4) ?? .clear, radius: 8, x: 0, y: 4)
                            
                            Image(systemName: page.icon)
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                        }
                        
                        VStack(spacing: 4) {
                            Text(page.buttonTitle)
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                            
                            Text(page.buttonSubtitle)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(width: 160, height: 140)
                    .background(
                        ZStack {
                            // Bottom shadow layer (deepest) - colored based on gradient
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .fill((page.gradient.first ?? .gray).opacity(colorScheme == .dark ? 0.15 : 0.08))
                                .offset(y: 8)
                                .blur(radius: 4)
                            
                            // Middle shadow layer
                            RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                                .offset(y: 4)
                            
                            // Main card background
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: colorScheme == .dark 
                                            ? [Color(red: 0.15, green: 0.15, blue: 0.2), Color(red: 0.12, green: 0.12, blue: 0.17)]
                                            : [Color.white, Color.white.opacity(0.95)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                            
                            // Inner highlight (top edge glow)
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
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
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            (page.gradient.first ?? .gray).opacity(colorScheme == .dark ? 0.4 : 0.3),
                                            (page.gradient.last ?? .gray).opacity(colorScheme == .dark ? 0.3 : 0.2)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        }
                    )
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 12, x: 0, y: 6)
                    .shadow(color: (page.gradient.first ?? .gray).opacity(colorScheme == .dark ? 0.2 : 0.12), radius: 20, x: 0, y: 10)
                    .scaleEffect(iconAnimation ? 1.05 : 1.0)
                    .offset(y: iconAnimation ? -3 : 3)
                } else if page.useProgramWidget {
                    // Show actual program widget (Foundation Builder sample)
                    TutorialProgramWidget(gradient: page.gradient, isAnimating: iconAnimation)
                        .offset(y: iconAnimation ? -3 : 3)
                } else if page.useStreakFlame {
                    // Show actual streak flame from home tab
                    TutorialStreakFlame(gradient: page.gradient, isAnimating: iconAnimation)
                } else if page.useMealTracking {
                    // Show actual meal tracking UI
                    TutorialMealTracking(gradient: page.gradient, isAnimating: iconAnimation)
                } else if page.useWaterWidget {
                    // Show water tracking widget
                    TutorialWaterTracking(gradient: page.gradient, isAnimating: iconAnimation)
                } else {
                    // Glow effect
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    page.iconColor.opacity(iconAnimation ? 0.4 : 0.2),
                                    page.iconColor.opacity(0)
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: iconAnimation ? 100 : 80
                            )
                        )
                        .frame(width: 200, height: 200)
                    
                    // Background circle
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: page.gradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 130, height: 130)
                        .shadow(color: page.gradient[0].opacity(0.5), radius: 20, x: 0, y: 10)
                    
                    // Icon
                    Image(systemName: page.icon)
                        .font(.system(size: 54, weight: .semibold))
                        .foregroundColor(.white)
                        .offset(y: iconAnimation ? -3 : 3)
                    
                    // Sparkle particles (for certain animations)
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
            .scaleEffect(animateContent ? 1 : 0.5)
            .opacity(animateContent ? 1 : 0)
            
            Spacer()
                .frame(height: 24)
            
            // Text content (subtitle and description below icon/widget)
            VStack(spacing: 14) {
                // Subtitle
                Text(page.subtitle)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(animateContent ? 1 : 0)
                    .offset(y: animateContent ? 0 : 15)
                
                // Description
                Text(page.description)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .padding(.horizontal, 36)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(animateContent ? 1 : 0)
                    .offset(y: animateContent ? 0 : 10)
            }
            .animation(.easeOut(duration: 0.5).delay(0.2), value: animateContent)
            
            Spacer()
                .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 24)
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
    
    private func startIconAnimation() {
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            iconAnimation = true
        }
    }
    
    private func generateParticles() {
        particles = (0..<8).map { _ in
            ParticleData(
                x: CGFloat.random(in: -80...80),
                y: CGFloat.random(in: -80...80),
                size: CGFloat.random(in: 8...16),
                opacity: Double.random(in: 0.3...0.8)
            )
        }
        
        // Animate particles
        withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
            particles = particles.map { particle in
                ParticleData(
                    x: particle.x + CGFloat.random(in: -20...20),
                    y: particle.y + CGFloat.random(in: -20...20),
                    size: particle.size,
                    opacity: Double.random(in: 0.3...0.8)
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
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
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
