import SwiftUI

// MARK: - Unified Card Background Style
// Matches the exercise library card style with gradient/glow effect for cohesiveness

/// Card background that matches exercise library card style - used across all onboarding screens
struct OnboardingCardBackgroundStyle: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    let accentColor: Color
    let secondaryAccentColor: Color
    let isSelected: Bool
    let cornerRadius: CGFloat
    
    init(accentColor: Color, secondaryAccentColor: Color? = nil, isSelected: Bool, cornerRadius: CGFloat = 24) {
        self.accentColor = accentColor
        self.secondaryAccentColor = secondaryAccentColor ?? accentColor.opacity(0.7)
        self.isSelected = isSelected
        self.cornerRadius = cornerRadius
    }
    
    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    // Bottom shadow layer (deepest) - accent colored glow
                    RoundedRectangle(cornerRadius: cornerRadius + 4, style: .continuous)
                        .fill(accentColor.opacity(colorScheme == .dark ? (isSelected ? 0.15 : 0.08) : (isSelected ? 0.10 : 0.04)))
                        .offset(y: isSelected ? 10 : 8)
                        .blur(radius: isSelected ? 6 : 4)
                    
                    // Middle shadow layer
                    RoundedRectangle(cornerRadius: cornerRadius + 2, style: .continuous)
                        .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                        .offset(y: 4)
                    
                    // Main card background with gradient
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: Color.cardGradientStops(for: colorScheme),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    
                    // Inner highlight (top edge glow)
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
                    
                    // Colored accent border - always present for depth
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    accentColor.opacity(colorScheme == .dark ? (isSelected ? 0.6 : 0.35) : (isSelected ? 0.5 : 0.25)),
                                    secondaryAccentColor.opacity(colorScheme == .dark ? (isSelected ? 0.4 : 0.25) : (isSelected ? 0.35 : 0.15))
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: isSelected ? 2 : 1
                        )
                }
            )
            // Multi-layer shadow effect matching workout buttons
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 12, x: 0, y: 6)
            .shadow(color: accentColor.opacity(colorScheme == .dark ? (isSelected ? 0.25 : 0.15) : (isSelected ? 0.15 : 0.08)), radius: isSelected ? 20 : 12, x: 0, y: isSelected ? 10 : 6)
    }
}

extension View {
    /// Applies the standard onboarding card background style matching exercise library cards
    func onboardingCardStyle(accentColor: Color, secondaryColor: Color? = nil, isSelected: Bool, cornerRadius: CGFloat = 24) -> some View {
        self.modifier(OnboardingCardBackgroundStyle(
            accentColor: accentColor,
            secondaryAccentColor: secondaryColor,
            isSelected: isSelected,
            cornerRadius: cornerRadius
        ))
    }
    
    /// Applies the selected card style with gradient fill
    func onboardingSelectedStyle(accentColor: Color, secondaryColor: Color? = nil, cornerRadius: CGFloat = 24) -> some View {
        self.modifier(OnboardingSelectedCardStyle(accentColor: accentColor, secondaryColor: secondaryColor, cornerRadius: cornerRadius))
    }
}

/// Selected card background with prominent accent color gradient
struct OnboardingSelectedCardStyle: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    let accentColor: Color
    let secondaryColor: Color
    let cornerRadius: CGFloat
    
    init(accentColor: Color, secondaryColor: Color? = nil, cornerRadius: CGFloat = 24) {
        self.accentColor = accentColor
        self.secondaryColor = secondaryColor ?? accentColor.opacity(0.7)
        self.cornerRadius = cornerRadius
    }
    
    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    // Bottom glow layer
                    RoundedRectangle(cornerRadius: cornerRadius + 4, style: .continuous)
                        .fill(accentColor.opacity(0.35))
                        .offset(y: 10)
                        .blur(radius: 8)
                    
                    // Main gradient background
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [accentColor, secondaryColor],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    // Inner highlight (top edge glow)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.4), Color.white.opacity(0.1), Color.clear],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1.5
                        )
                }
            )
            // Glow shadow
            .shadow(color: accentColor.opacity(colorScheme == .dark ? 0.5 : 0.35), radius: 20, x: 0, y: 10)
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.1), radius: 12, x: 0, y: 6)
    }
}

// MARK: - Unified Onboarding Card Style
// Matches the exercise library card style exactly

/// Standard card for onboarding selections - matches exercise library card style
struct OnboardingSelectionCard: View {
    @Environment(\.colorScheme) var colorScheme
    
    let title: String
    let subtitle: String?
    let icon: String
    let color: Color
    let isSelected: Bool
    let onTap: () -> Void
    
    private let selectionFeedback = UISelectionFeedbackGenerator()
    
    init(title: String, subtitle: String? = nil, icon: String, color: Color, isSelected: Bool, onTap: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.color = color
        self.isSelected = isSelected
        self.onTap = onTap
    }
    
    var body: some View {
        Button(action: {
            selectionFeedback.selectionChanged()
            onTap()
        }) {
            VStack(spacing: 8) {
                // Icon with glow effect
                ZStack {
                    // Soft glow when selected
                    if isSelected {
                        Circle()
                            .fill(color.opacity(0.4))
                            .frame(width: 52, height: 52)
                            .blur(radius: 12)
                    }
                    
                    Circle()
                        .fill(
                            isSelected
                                ? LinearGradient(colors: [color, color.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LinearGradient(colors: [colorScheme == .dark ? Color(white: 0.22) : Color.gray.opacity(0.08), colorScheme == .dark ? Color(white: 0.18) : Color.gray.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: icon)
                        .font(.ds_heading3).fontWeight(.semibold)
                        .foregroundColor(isSelected ? .white : (colorScheme == .dark ? .gray : .gray.opacity(0.8)))
                }
                
                VStack(spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(isSelected ? color : .primary)
                        .lineLimit(1)
                    
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .onboardingCardStyle(accentColor: color, secondaryColor: color.opacity(0.7), isSelected: isSelected, cornerRadius: 20)
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isSelected ? 1.03 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

/// Large card with emoji for goals/experience - matches exercise library card style
struct OnboardingLargeCard: View {
    @Environment(\.colorScheme) var colorScheme
    
    let title: String
    let emoji: String
    let subtitle: String
    let color: Color
    let isSelected: Bool
    let onTap: () -> Void
    
    private let selectionFeedback = UISelectionFeedbackGenerator()
    
    var body: some View {
        Button(action: {
            selectionFeedback.selectionChanged()
            onTap()
        }) {
            VStack(spacing: 10) {
                // Emoji with glow
                ZStack {
                    if isSelected {
                        Circle()
                            .fill(color.opacity(0.35))
                            .frame(width: 60, height: 60)
                            .blur(radius: 14)
                    }
                    
                    Text(emoji)
                        .font(.system(size: 36))
                }
                
                VStack(spacing: 3) {
                    Text(title)
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(isSelected ? color : .primary)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 130)
            .onboardingCardStyle(accentColor: color, secondaryColor: color.opacity(0.7), isSelected: isSelected, cornerRadius: CornerRadius.xl)
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isSelected ? 1.03 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

/// Wide horizontal card for single selections - matches exercise library card style
struct OnboardingWideCard: View {
    @Environment(\.colorScheme) var colorScheme
    
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let isSelected: Bool
    let onTap: () -> Void
    
    private let selectionFeedback = UISelectionFeedbackGenerator()
    
    var body: some View {
        Button(action: {
            selectionFeedback.selectionChanged()
            onTap()
        }) {
            HStack(spacing: 14) {
                // Icon with glow
                ZStack {
                    if isSelected {
                        Circle()
                            .fill(color.opacity(0.4))
                            .frame(width: 52, height: 52)
                            .blur(radius: 10)
                    }
                    
                    Circle()
                        .fill(
                            isSelected
                                ? LinearGradient(colors: [color, color.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LinearGradient(colors: [colorScheme == .dark ? Color(white: 0.22) : Color.gray.opacity(0.08), colorScheme == .dark ? Color(white: 0.18) : Color.gray.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: icon)
                        .font(.ds_heading3)
                        .foregroundColor(isSelected ? .white : (colorScheme == .dark ? .gray : .gray.opacity(0.8)))
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(isSelected ? color : .primary)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                // Selection indicator
                ZStack {
                    Circle()
                        .stroke(isSelected ? color : Color.gray.opacity(0.3), lineWidth: 2)
                        .frame(width: 24, height: 24)
                    
                    if isSelected {
                        Circle()
                            .fill(color)
                            .frame(width: 16, height: 16)
                    }
                }
            }
            .padding(14)
            .onboardingCardStyle(accentColor: color, secondaryColor: color.opacity(0.7), isSelected: isSelected, cornerRadius: 20)
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - Onboarding Layout Components

/// Floating navigation bar at top of onboarding
struct OnboardingNavBar: View {
    let canGoBack: Bool
    let onBack: () -> Void
    let onContinue: () -> Void
    let continueEnabled: Bool
    let continueLabel: String
    
    var body: some View {
        HStack {
            // Back button
            if canGoBack {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.ds_labelMedium)
                        Text("Back")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.secondary)
                }
            } else {
                Spacer().frame(width: 60)
            }
            
            Spacer()
            
            // Continue button
            Button(action: onContinue) {
                HStack(spacing: 4) {
                    Text(continueLabel)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Image(systemName: "chevron.right")
                        .font(.ds_labelMedium)
                }
                .foregroundStyle(
                    continueEnabled
                        ? AnyShapeStyle(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing))
                        : AnyShapeStyle(Color.gray.opacity(0.5))
                )
            }
            .disabled(!continueEnabled)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, Spacing.sm)
    }
}

/// Progress indicator for onboarding
struct OnboardingProgressBar: View {
    let currentStep: Int
    let totalSteps: Int
    let stepName: String
    
    var progress: Double {
        guard totalSteps > 0 else { return 0 }
        return Double(currentStep) / Double(totalSteps)
    }
    
    var body: some View {
        // Progress bar only (no dots)
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                Capsule()
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 4)
                
                // Progress fill with gradient
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * progress, height: 4)
                    .animation(.easeInOut(duration: 0.3), value: progress)
            }
        }
        .frame(height: 4)
        .padding(.horizontal, 40)
    }
}

/// Question header for onboarding steps
struct OnboardingQuestionHeader: View {
    let question: String
    let subtitle: String?
    
    var body: some View {
        VStack(spacing: 8) {
            Text(question)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
            
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, Spacing.lg)
    }
}

/// Standard onboarding step container with consistent layout
struct OnboardingStepContainer<Content: View>: View {
    @Environment(\.colorScheme) var colorScheme
    
    let canGoBack: Bool
    let onBack: () -> Void
    let onContinue: () -> Void
    let continueEnabled: Bool
    let continueLabel: String
    let currentStep: Int
    let totalSteps: Int
    let question: String
    let subtitle: String?
    @ViewBuilder let content: Content
    
    init(
        canGoBack: Bool = true,
        onBack: @escaping () -> Void,
        onContinue: @escaping () -> Void,
        continueEnabled: Bool = true,
        continueLabel: String = "Continue",
        currentStep: Int,
        totalSteps: Int,
        question: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.canGoBack = canGoBack
        self.onBack = onBack
        self.onContinue = onContinue
        self.continueEnabled = continueEnabled
        self.continueLabel = continueLabel
        self.currentStep = currentStep
        self.totalSteps = totalSteps
        self.question = question
        self.subtitle = subtitle
        self.content = content()
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Floating nav bar
            OnboardingNavBar(
                canGoBack: canGoBack,
                onBack: onBack,
                onContinue: onContinue,
                continueEnabled: continueEnabled,
                continueLabel: continueLabel
            )
            
            // Progress indicator
            OnboardingProgressBar(
                currentStep: currentStep,
                totalSteps: totalSteps,
                stepName: ""
            )
            .padding(.top, 4)
            
            // Question header
            OnboardingQuestionHeader(
                question: question,
                subtitle: subtitle
            )
            .padding(.top, 32)
            .padding(.bottom, 24)
            
            // Content
            content
            
            Spacer(minLength: 20)
        }
    }
}

// MARK: - Onboarding Background

struct OnboardingBackground: View {
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        LinearGradient(
            gradient: Gradient(colors: colorScheme == .dark
                ? [
                    Color.purple.opacity(0.15),
                    Color.blue.opacity(0.08),
                    Color(red: 0.06, green: 0.06, blue: 0.08),
                    Color(red: 0.04, green: 0.04, blue: 0.06)
                ]
                : [
                    Color.purple.opacity(0.15),
                    Color.blue.opacity(0.1),
                    Color(red: 0.96, green: 0.97, blue: 1.0),
                    Color.white
                ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        OnboardingBackground()
        
        OnboardingStepContainer(
            canGoBack: true,
            onBack: {},
            onContinue: {},
            continueEnabled: true,
            currentStep: 2,
            totalSteps: 8,
            question: "What's your goal?",
            subtitle: "Select one or more"
        ) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                OnboardingLargeCard(
                    title: "Build Muscle",
                    emoji: "💪",
                    subtitle: "Gain size & strength",
                    color: .blue,
                    isSelected: true,
                    onTap: {}
                )
                OnboardingLargeCard(
                    title: "Get Lean",
                    emoji: "🔥",
                    subtitle: "Burn fat",
                    color: .orange,
                    isSelected: false,
                    onTap: {}
                )
            }
            .padding(.horizontal, 20)
        }
    }
}

