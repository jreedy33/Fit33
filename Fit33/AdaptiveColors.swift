import SwiftUI

/// Extension providing adaptive colors that work in both light and dark modes
extension Color {
    // MARK: - Dark Mode Base Colors (Consistent across app)
    
    /// Deep dark background - primary dark mode background
    static var darkBackground: Color {
        Color(red: 0.07, green: 0.07, blue: 0.09)
    }
    
    /// Slightly elevated dark surface
    static var darkSurface: Color {
        Color(red: 0.11, green: 0.11, blue: 0.13)
    }
    
    /// Card background in dark mode
    static var darkCardBackground: Color {
        Color(red: 0.14, green: 0.14, blue: 0.16)
    }
    
    /// Card background - white in light mode, dark gray in dark mode
    static var cardBackground: Color {
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.14, green: 0.14, blue: 0.16, alpha: 1)
                : UIColor.white
        })
    }
    
    /// Secondary card background - slightly darker/lighter variant
    static var cardBackgroundSecondary: Color {
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 1)
                : UIColor(red: 0.98, green: 0.98, blue: 0.98, alpha: 1)
        })
    }

    // MARK: - Card Gradient Tokens (Q2-92, Sprint 9 2026-04-28)
    //
    // Replaces the hard-coded `[Color(white: 0.15), Color(white: 0.10)]` pair
    // that appeared ~100 times across the codebase (WorkoutProgressView 30,
    // FriendsTabView 24, DashboardView+Programs 20, DashboardView+Challenges
    // 19, MealPlanView 16). In light mode, callers previously branched on
    // `colorScheme` and used white; so these two tokens expose the dark +
    // light versions explicitly. Use `Color.cardGradientStops(for:)` when the
    // branch is on `@Environment(\.colorScheme)`.

    /// Dark-mode card gradient top stop (`Color(white: 0.15)`).
    static let cardGradientTopDark = Color(white: 0.15)

    /// Dark-mode card gradient bottom stop (`Color(white: 0.10)`).
    static let cardGradientBottomDark = Color(white: 0.10)

    /// Returns the canonical 2-stop card gradient for the given color scheme.
    /// Dark: `[cardGradientTopDark, cardGradientBottomDark]`.
    /// Light: `[.white, .white.opacity(0.95)]` — matches the pre-Sprint-9
    /// light-mode branch in WorkoutProgressView / FriendsTabView / Dashboard.
    static func cardGradientStops(for scheme: ColorScheme) -> [Color] {
        scheme == .dark
            ? [cardGradientTopDark, cardGradientBottomDark]
            : [.white, .white.opacity(0.95)]
    }
    
    /// App background for gradients - adapts to dark mode
    static var appBackgroundTop: Color {
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.09, green: 0.09, blue: 0.11, alpha: 1)
                : UIColor(red: 0.85, green: 0.92, blue: 1.0, alpha: 1)
        })
    }
    
    static var appBackgroundMiddle: Color {
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1)
                : UIColor(red: 0.9, green: 0.95, blue: 1.0, alpha: 1)
        })
    }
    
    static var appBackgroundBottom: Color {
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.06, green: 0.06, blue: 0.07, alpha: 1)
                : UIColor.white
        })
    }
    
    /// Text colors
    static var adaptiveText: Color {
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor.white
                : UIColor.black
        })
    }
    
    static var adaptiveSecondaryText: Color {
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(white: 0.7, alpha: 1)
                : UIColor(white: 0.4, alpha: 1)
        })
    }
    
    /// Divider color
    static var adaptiveDivider: Color {
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(white: 0.2, alpha: 1)
                : UIColor(white: 0.9, alpha: 1)
        })
    }
}

// MARK: - Sleek Card Background (Reusable across app)
/// The multi-layer card style used on Dashboard, ContentView, Meals, etc.
/// Layers: colored shadow glow → depth shadow → gradient fill → inner highlight → accent border

struct SleekCardBackground: View {
    let cornerRadius: CGFloat
    let accentColor: Color
    @Environment(\.colorScheme) private var colorScheme
    
    init(cornerRadius: CGFloat = 24, accentColor: Color = .blue) {
        self.cornerRadius = cornerRadius
        self.accentColor = accentColor
    }
    
    var body: some View {
        ZStack {
            // Layer 1: Bottom shadow (deepest) — colored glow
            // Exactly matches DepthQuickActionCard in WorkoutTabView
            RoundedRectangle(cornerRadius: cornerRadius + 4, style: .continuous)
                .fill(accentColor.opacity(colorScheme == .dark ? 0.15 : 0.08))
                .offset(y: 8)
                .blur(radius: 4)
            
            // Layer 2: Middle depth shadow
            RoundedRectangle(cornerRadius: cornerRadius + 2, style: .continuous)
                .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                .offset(y: 4)
            
            // Layer 3: Main card fill — subtle gradient
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color(white: 0.18), Color(white: 0.12)]
                            : [Color.white, Color.white.opacity(0.95)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            
            // Layer 4: Inner highlight — top edge glow
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
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
            
            // Layer 5: Accent border — subtle color tint
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            accentColor.opacity(colorScheme == .dark ? 0.4 : 0.3),
                            accentColor.opacity(colorScheme == .dark ? 0.3 : 0.2)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
    }
}

/// ViewModifier for easy `.sleekCard()` usage
struct SleekCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    let accentColor: Color
    @Environment(\.colorScheme) private var colorScheme
    
    func body(content: Content) -> some View {
        content
            .background(SleekCardBackground(cornerRadius: cornerRadius, accentColor: accentColor))
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 12, x: 0, y: 6)
            .shadow(color: accentColor.opacity(colorScheme == .dark ? 0.2 : 0.12), radius: 20, x: 0, y: 10)
    }
}

extension View {
    /// Apply the sleek multi-layer card background used across the app
    /// Matches the exact style of DepthQuickActionCard (autogen/custom workout buttons)
    func sleekCard(cornerRadius: CGFloat = 24, accentColor: Color = .blue) -> some View {
        modifier(SleekCardModifier(cornerRadius: cornerRadius, accentColor: accentColor))
    }
    
    /// Gradient card without the colored glow/outline — just the gradient fill + subtle depth
    func sleekCardSubtle(cornerRadius: CGFloat = 16) -> some View {
        modifier(SleekCardSubtleModifier(cornerRadius: cornerRadius))
    }
}

struct SleekCardSubtleModifier: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    
    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: colorScheme == .dark
                                    ? [Color(white: 0.18), Color(white: 0.12)]
                                    : [Color.white, Color.white.opacity(0.93)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: colorScheme == .dark
                                    ? [Color.white.opacity(0.08), Color.white.opacity(0.02), Color.clear]
                                    : [Color.white, Color.white.opacity(0.4), Color.clear],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                }
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.2 : 0.06), radius: 6, x: 0, y: 3)
    }
}

/// Adaptive gradient backgrounds for different tabs - Now unified for consistency
struct AdaptiveGradient {
    
    // MARK: - Universal Dark Gradient (Used across all screens)
    /// Beautiful purple/blue gradient matching the auto-gen flow
    private static var universalDark: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [
                Color.purple.opacity(0.2),              // Purple tint at top
                Color.blue.opacity(0.1),               // Blue transition
                Color(red: 0.06, green: 0.06, blue: 0.08),  // Deep dark
                Color(red: 0.04, green: 0.04, blue: 0.06)   // Near black at bottom
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    static func home(for colorScheme: ColorScheme) -> LinearGradient {
        if colorScheme == .dark {
            return universalDark
        } else {
            return LinearGradient(
                gradient: Gradient(colors: [Color.blue.opacity(0.3), Color.cyan.opacity(0.2), Color.white]),
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
    
    static func exercises(for colorScheme: ColorScheme) -> LinearGradient {
        if colorScheme == .dark {
            return universalDark
        } else {
            return LinearGradient(
                gradient: Gradient(colors: [Color.blue.opacity(0.3), Color.cyan.opacity(0.2), Color.white]),
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
    
    static func workout(for colorScheme: ColorScheme) -> LinearGradient {
        if colorScheme == .dark {
            return universalDark
        } else {
            return LinearGradient(
                gradient: Gradient(colors: [Color.green.opacity(0.3), Color.blue.opacity(0.2), Color.white]),
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
    
    static func meals(for colorScheme: ColorScheme) -> LinearGradient {
        if colorScheme == .dark {
            return universalDark
        } else {
            return LinearGradient(
                gradient: Gradient(colors: [Color.green.opacity(0.3), Color.mint.opacity(0.2), Color.white]),
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
    
    static func stats(for colorScheme: ColorScheme) -> LinearGradient {
        if colorScheme == .dark {
            return universalDark
        } else {
            return LinearGradient(
                gradient: Gradient(colors: [Color.purple.opacity(0.3), Color.blue.opacity(0.2), Color.white]),
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
    
    static func friends(for colorScheme: ColorScheme) -> LinearGradient {
        if colorScheme == .dark {
            return universalDark
        } else {
            return LinearGradient(
                gradient: Gradient(colors: [Color.blue.opacity(0.3), Color.cyan.opacity(0.2), Color.white]),
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
    
    static func stretch(for colorScheme: ColorScheme) -> LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                gradient: Gradient(colors: [
                    Color.teal.opacity(0.15),
                    Color.mint.opacity(0.08),
                    Color(red: 0.05, green: 0.08, blue: 0.10),
                    Color(red: 0.04, green: 0.05, blue: 0.07)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                gradient: Gradient(colors: [Color.teal.opacity(0.25), Color.mint.opacity(0.15), Color.white]),
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
    
    /// Universal background that can be used anywhere
    static func universal(for colorScheme: ColorScheme) -> LinearGradient {
        if colorScheme == .dark {
            return universalDark
        } else {
            return LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.92, green: 0.95, blue: 1.0),
                    Color(red: 0.96, green: 0.97, blue: 1.0),
                    Color.white
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

// MARK: - Animated Orb Background
/// Reusable animated background with floating gradient orbs
/// Used across all main tabs for visual consistency
struct AnimatedOrbBackground: View {
    let baseGradient: LinearGradient
    let primaryOrbColor: Color
    let secondaryOrbColor: Color
    
    @State private var animatePulse = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    /// In Low Power Mode, disable orb animations to save battery and prevent FPS drops.
    /// The orbs render once in their resting position — still looks good, just static.
    private var isLowPowerMode: Bool {
        ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    /// Sprint 3 (Q2-32): unified gate. Respect BOTH the system Low Power Mode
    /// AND the user's Reduce Motion accessibility preference. Either one
    /// means: render orbs statically, no easing animation.
    private var shouldDisableMotion: Bool {
        isLowPowerMode || reduceMotion
    }
    
    // Convenience initializers for each tab
    static func home(colorScheme: ColorScheme) -> AnimatedOrbBackground {
        AnimatedOrbBackground(
            baseGradient: AdaptiveGradient.home(for: colorScheme),
            primaryOrbColor: .blue,
            secondaryOrbColor: .cyan
        )
    }
    
    static func exercises(colorScheme: ColorScheme) -> AnimatedOrbBackground {
        AnimatedOrbBackground(
            baseGradient: AdaptiveGradient.exercises(for: colorScheme),
            primaryOrbColor: .blue,
            secondaryOrbColor: .cyan
        )
    }
    
    static func workout(colorScheme: ColorScheme) -> AnimatedOrbBackground {
        AnimatedOrbBackground(
            baseGradient: AdaptiveGradient.workout(for: colorScheme),
            primaryOrbColor: .blue,
            secondaryOrbColor: .cyan
        )
    }
    
    static func meals(colorScheme: ColorScheme) -> AnimatedOrbBackground {
        AnimatedOrbBackground(
            baseGradient: AdaptiveGradient.meals(for: colorScheme),
            primaryOrbColor: .blue,
            secondaryOrbColor: .cyan
        )
    }
    
    static func stats(colorScheme: ColorScheme) -> AnimatedOrbBackground {
        AnimatedOrbBackground(
            baseGradient: AdaptiveGradient.stats(for: colorScheme),
            primaryOrbColor: .blue,
            secondaryOrbColor: .cyan
        )
    }
    
    static func friends(colorScheme: ColorScheme) -> AnimatedOrbBackground {
        AnimatedOrbBackground(
            baseGradient: AdaptiveGradient.friends(for: colorScheme),
            primaryOrbColor: .blue,
            secondaryOrbColor: .cyan
        )
    }
    
    /// Stretch mode - calming teal/mint tones for recovery and mobility
    static func stretch(colorScheme: ColorScheme) -> AnimatedOrbBackground {
        AnimatedOrbBackground(
            baseGradient: AdaptiveGradient.stretch(for: colorScheme),
            primaryOrbColor: .teal,
            secondaryOrbColor: .mint
        )
    }
    
    /// Onboarding flow - clean, professional with subtle blue/cyan orbs
    static func onboarding(colorScheme: ColorScheme) -> AnimatedOrbBackground {
        AnimatedOrbBackground(
            baseGradient: AdaptiveGradient.universal(for: colorScheme),
            primaryOrbColor: .blue,
            secondaryOrbColor: .cyan
        )
    }
    
    var body: some View {
        ZStack {
            // Base gradient
            baseGradient
            
            // Animated gradient orbs
            GeometryReader { geometry in
                ZStack {
                    // Top primary orb
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    primaryOrbColor.opacity(colorScheme == .dark ? 0.25 : 0.3),
                                    primaryOrbColor.opacity(0)
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: 200
                            )
                        )
                        .frame(width: 400, height: 400)
                        .drawingGroup()
                        .offset(x: animatePulse ? -50 : -100, y: animatePulse ? -150 : -180)
                        .animation(shouldDisableMotion ? nil : .easeInOut(duration: 4), value: animatePulse)
                    
                    // Bottom secondary orb
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    secondaryOrbColor.opacity(colorScheme == .dark ? 0.2 : 0.25),
                                    secondaryOrbColor.opacity(0)
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: 250
                            )
                        )
                        .frame(width: 500, height: 500)
                        .drawingGroup()
                        .offset(x: animatePulse ? 150 : 100, y: animatePulse ? geometry.size.height * 0.4 : geometry.size.height * 0.5)
                        .animation(shouldDisableMotion ? nil : .easeInOut(duration: 5), value: animatePulse)
                    
                    // Accent orb (smaller, faster)
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    primaryOrbColor.opacity(colorScheme == .dark ? 0.15 : 0.2),
                                    primaryOrbColor.opacity(0)
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: 120
                            )
                        )
                        .frame(width: 240, height: 240)
                        .drawingGroup()
                        .offset(x: animatePulse ? geometry.size.width * 0.6 : geometry.size.width * 0.7, y: animatePulse ? geometry.size.height * 0.2 : geometry.size.height * 0.15)
                        .animation(shouldDisableMotion ? nil : .easeInOut(duration: 3), value: animatePulse)
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .onAppear {
            if !shouldDisableMotion {
                animatePulse = true
            }
        }
    }
}
