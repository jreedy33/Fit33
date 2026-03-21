import SwiftUI
import StoreKit

// MARK: - Premium Feature Enum
enum PremiumFeature: String, CaseIterable {
    case recipes = "Unlimited Recipes"
    case aiWorkouts = "AI Workout Generation"
    case advancedAnalytics = "Advanced Analytics"
    case customMealPlans = "Custom Meal Plans"
    case unlimitedHistory = "Unlimited History"
    case premiumExercises = "Premium Exercises"
    case nutritionInsights = "Nutrition Insights"
    case progressTracking = "Advanced Progress"
    case streakEdit = "Edit Streak"
    case weightTracking = "Weight Tracking"
    case homescreenWidgets = "Homescreen Widgets"
    case savedWorkouts = "Saved Workouts"
    case saveSharedWorkouts = "Save Shared Workouts"
    case removeAds = "Remove Ads"
    
    var icon: String {
        switch self {
        case .recipes: return "fork.knife"
        case .aiWorkouts: return "brain.head.profile"
        case .advancedAnalytics: return "chart.xyaxis.line"
        case .customMealPlans: return "menucard"
        case .unlimitedHistory: return "clock.arrow.circlepath"
        case .premiumExercises: return "figure.strengthtraining.traditional"
        case .nutritionInsights: return "leaf.fill"
        case .progressTracking: return "chart.line.uptrend.xyaxis"
        case .streakEdit: return "flame.fill"
        case .weightTracking: return "scalemass.fill"
        case .homescreenWidgets: return "square.grid.2x2.fill"
        case .savedWorkouts: return "bookmark.fill"
        case .saveSharedWorkouts: return "bookmark.fill"
        case .removeAds: return "nosign"
        }
    }
    
    var shortDescription: String {
        switch self {
        case .recipes: return "Thousands of healthy recipes"
        case .aiWorkouts: return "Smart personalized workouts"
        case .advancedAnalytics: return "Deep fitness insights"
        case .customMealPlans: return "Personalized meal planning"
        case .unlimitedHistory: return "Complete workout history"
        case .premiumExercises: return "500+ exercise library"
        case .nutritionInsights: return "Detailed macro tracking"
        case .progressTracking: return "Track strength gains"
        case .streakEdit: return "Fix or adjust your streak"
        case .weightTracking: return "Daily weight tracking & trends"
        case .homescreenWidgets: return "Customize your dashboard"
        case .savedWorkouts: return "Start workouts shared by friends"
        case .saveSharedWorkouts: return "Save workouts from friends"
        case .removeAds: return "Ad-free workout experience"
        }
    }
    
    var accentColor: Color {
        switch self {
        case .recipes: return .orange
        case .aiWorkouts: return .purple
        case .advancedAnalytics: return .blue
        case .customMealPlans: return .green
        case .unlimitedHistory: return .cyan
        case .premiumExercises: return .pink
        case .nutritionInsights: return .mint
        case .progressTracking: return .indigo
        case .streakEdit: return .orange
        case .weightTracking: return .orange
        case .homescreenWidgets: return .purple
        case .savedWorkouts: return .blue
        case .saveSharedWorkouts: return .blue
        case .removeAds: return .yellow
        }
    }
    
    var gradient: [Color] {
        switch self {
        case .recipes: return [.orange, .yellow]
        case .aiWorkouts: return [.purple, .pink]
        case .advancedAnalytics: return [.blue, .cyan]
        case .customMealPlans: return [.green, .mint]
        case .unlimitedHistory: return [.cyan, .blue]
        case .premiumExercises: return [.pink, .red]
        case .nutritionInsights: return [.mint, .green]
        case .progressTracking: return [.indigo, .purple]
        case .streakEdit: return [.orange, .red]
        case .weightTracking: return [.orange, .yellow]
        case .homescreenWidgets: return [.purple, .pink]
        case .savedWorkouts: return [.blue, .purple]
        case .saveSharedWorkouts: return [.blue, .purple]
        case .removeAds: return [.yellow, .orange]
        }
    }
}

// MARK: - Subscription Plan
enum SubscriptionPlan: String, CaseIterable {
    case monthly = "Monthly"
    case yearly = "Yearly"
    
    var price: String {
        switch self {
        case .monthly: return "$3.99"
        case .yearly: return "$29.99"
        }
    }
    
    var period: String {
        switch self {
        case .monthly: return "/month"
        case .yearly: return "/year"
        }
    }
    
    var monthlyEquivalent: String {
        switch self {
        case .monthly: return "$3.99/mo"
        case .yearly: return "$2.49/mo"
        }
    }
    
    var savings: String? {
        switch self {
        case .monthly: return nil
        case .yearly: return "Save 37%"
        }
    }
    
    var isBestValue: Bool {
        self == .yearly
    }
}

// MARK: - Premium Upgrade View
struct PremiumUpgradeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var storeKit = StoreKitManager.shared
    
    let triggeringFeature: PremiumFeature
    var onUpgrade: ((SubscriptionPlan) -> Void)?
    var onRestore: (() -> Void)?
    
    @State private var selectedPlan: SubscriptionPlan = .yearly
    @State private var glowRotation: Double = 0
    @State private var logoScale: CGFloat = 0.8
    @State private var contentOpacity: Double = 0
    @State private var tilesAppeared = false
    @State private var buttonPulse = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    // Premium benefits with tiles - matching app icon style
    private let benefits: [(icon: String, title: String, subtitle: String, gradient: [Color])] = [
        ("plus", "Unlimited Workouts", "No restrictions", [.blue, .cyan]),
        ("brain.head.profile", "AI-Powered", "Smart adaptation", [.purple, .pink]),
        ("flame.fill", "Streak Protection", "Never lose progress", [.orange, .yellow]),
        ("fork.knife", "Recipes & Meals", "Healthy options", [.green, .mint]),
        ("scalemass.fill", "Weight Tracking", "Body composition", [.pink, .red]),
        ("figure.strengthtraining.traditional", "500+ Exercises", "HD tutorials", [.indigo, .purple])
    ]
    
    var body: some View {
        ZStack {
            // Background
            backgroundView
            
            VStack(spacing: 0) {
                // Close button
                HStack {
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.ds_labelMedium)
                            .foregroundColor(.white.opacity(0.6))
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.white.opacity(0.1)))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        // Hero: Grand Logo
                        heroSection
                        
                        // What you're unlocking
                        unlockingSection
                        
                        // Benefits grid tiles
                        benefitsTilesSection
                        
                        // Pricing
                        pricingSection
                        
                        // CTA
                        ctaSection
                        
                        // Footer
                        footerSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 30)
                }
            }
        }
        .onAppear { startAnimations() }
    }
    
    // MARK: - Background
    private var backgroundView: some View {
        ZStack {
            // Base gradient
            LinearGradient(
                colors: [
                    Color(red: 0.07, green: 0.04, blue: 0.14),
                    Color(red: 0.03, green: 0.02, blue: 0.06)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            // Ambient glow
            VStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.blue.opacity(0.2),
                                Color.purple.opacity(0.1),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 50,
                            endRadius: 200
                        )
                    )
                    .frame(width: 400, height: 400)
                    .offset(y: -80)
                    .blur(radius: 50)
                
                Spacer()
            }
            .ignoresSafeArea()
        }
    }
    
    // MARK: - Hero Section
    private var heroSection: some View {
        VStack(spacing: 16) {
            // Grand logo with glow ring
            ZStack {
                // Rotating glow ring
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: [
                                .blue.opacity(0.7),
                                .purple.opacity(0.4),
                                .blue.opacity(0.1),
                                .clear,
                                .clear,
                                .blue.opacity(0.1),
                                .purple.opacity(0.4),
                                .blue.opacity(0.7)
                            ],
                            center: .center,
                            startAngle: .degrees(glowRotation),
                            endAngle: .degrees(glowRotation + 360)
                        ),
                        lineWidth: 4
                    )
                    .frame(width: 150, height: 150)
                    .blur(radius: 6)
                
                // Inner glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.blue.opacity(0.15),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 30,
                            endRadius: 70
                        )
                    )
                    .frame(width: 140, height: 140)
                
                // Logo container
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.12), Color(white: 0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.12), Color.clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    )
                
                // Fit33 Logo
                Image("fit33-logo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
            }
            .scaleEffect(logoScale)
            
            // PRO Badge
            HStack(spacing: 6) {
                Image(systemName: "crown.fill")
                    .font(.ds_bodySmall)
                Text("PRO")
                    .font(.ds_bodyLarge)
                    .tracking(2)
            }
            .foregroundColor(.black.opacity(0.8))
            .padding(.horizontal, 22)
            .padding(.vertical, 9)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 1.0, green: 0.84, blue: 0), Color(red: 1.0, green: 0.75, blue: 0.3)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .shadow(color: .yellow.opacity(0.5), radius: 12, x: 0, y: 4)
            )
            
            Text("Unlock your full potential")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(.top, 8)
        .opacity(contentOpacity)
    }
    
    // MARK: - Unlocking Section
    private var unlockingSection: some View {
        HStack(spacing: 14) {
            // Gradient circle with white icon (matching DepthQuickActionCard)
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: triggeringFeature.gradient),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                    .shadow(color: triggeringFeature.gradient.first?.opacity(0.4) ?? .clear, radius: 8, x: 0, y: 4)
                
                Image(systemName: triggeringFeature.icon)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text("You're unlocking")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
                
                Text(triggeringFeature.rawValue)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
            
            Spacer()
            
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundColor(.green)
        }
        .padding(14)
        .background(
            ZStack {
                // Bottom shadow layer (deepest) - colored based on gradient
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(triggeringFeature.gradient.first?.opacity(0.15) ?? Color.gray.opacity(0.15))
                    .offset(y: 6)
                    .blur(radius: 3)
                
                // Middle shadow layer
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.black.opacity(0.2))
                    .offset(y: 3)
                
                // Main card background
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.14), Color(white: 0.08)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                // Inner highlight (top edge glow)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.1), Color.white.opacity(0.02), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                
                // Colored accent border
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                triggeringFeature.gradient.first?.opacity(0.4) ?? Color.gray.opacity(0.4),
                                triggeringFeature.gradient.last?.opacity(0.3) ?? Color.gray.opacity(0.3)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
        .shadow(color: triggeringFeature.gradient.first?.opacity(0.2) ?? .clear, radius: 16, x: 0, y: 8)
        .opacity(contentOpacity)
    }
    
    // MARK: - Benefits Tiles Section
    private var benefitsTilesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Everything included")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.white.opacity(0.7))
                .padding(.leading, 4)
            
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ], spacing: 10) {
                ForEach(Array(benefits.enumerated()), id: \.offset) { index, benefit in
                    benefitTile(
                        icon: benefit.icon,
                        title: benefit.title,
                        subtitle: benefit.subtitle,
                        gradient: benefit.gradient,
                        index: index
                    )
                }
            }
        }
        .opacity(contentOpacity)
    }
    
    private func benefitTile(icon: String, title: String, subtitle: String, gradient: [Color], index: Int) -> some View {
        VStack(spacing: 10) {
            // Gradient circle with white icon (matching DepthQuickActionCard)
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: gradient),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                    .shadow(color: gradient.first?.opacity(0.4) ?? .clear, radius: 8, x: 0, y: 4)
                
                Image(systemName: icon)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
            }
            
            VStack(spacing: 3) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 110)
        .background(
            ZStack {
                // Bottom shadow layer (deepest) - colored based on gradient
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(gradient.first?.opacity(0.15) ?? Color.gray.opacity(0.15))
                    .offset(y: 6)
                    .blur(radius: 3)
                
                // Middle shadow layer
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.black.opacity(0.2))
                    .offset(y: 3)
                
                // Main card background
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.14), Color(white: 0.08)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                // Inner highlight (top edge glow)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.1), Color.white.opacity(0.02), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                
                // Colored accent border
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                gradient.first?.opacity(0.4) ?? Color.gray.opacity(0.4),
                                gradient.last?.opacity(0.3) ?? Color.gray.opacity(0.3)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
        .shadow(color: gradient.first?.opacity(0.2) ?? .clear, radius: 16, x: 0, y: 8)
        .opacity(tilesAppeared ? 1 : 0)
        .offset(y: tilesAppeared ? 0 : 10)
        .animation(
            .easeOut(duration: 0.3).delay(0.3 + Double(index) * 0.05),
            value: tilesAppeared
        )
    }
    
    // MARK: - Pricing Section
    private var pricingSection: some View {
        VStack(spacing: 10) {
            ForEach(SubscriptionPlan.allCases, id: \.self) { plan in
                pricingOption(plan: plan)
            }
        }
        .opacity(contentOpacity)
    }
    
    private func pricingOption(plan: SubscriptionPlan) -> some View {
        let isSelected = selectedPlan == plan
        
        return Button(action: {
            withAnimation(.spring(response: 0.3)) { selectedPlan = plan }
            HapticManager.selectionChanged()
        }) {
            HStack(spacing: 12) {
                // Radio
                Circle()
                    .stroke(isSelected ? Color.blue : Color.white.opacity(0.3), lineWidth: 2)
                    .frame(width: 20, height: 20)
                    .overlay(
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 10, height: 10)
                            .opacity(isSelected ? 1 : 0)
                    )
                
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 8) {
                        Text(plan.rawValue)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                        
                        if let savings = plan.savings {
                            Text(savings)
                                .font(.ds_caption)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.green))
                        }
                    }
                    
                    Text(plan.monthlyEquivalent)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                }
                
                Spacer()
                
                Text(displayPrice(for: plan))
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(isSelected ? 0.08 : 0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(
                                isSelected ? Color.blue.opacity(0.5) : Color.white.opacity(0.08),
                                lineWidth: isSelected ? 2 : 1
                            )
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func displayPrice(for plan: SubscriptionPlan) -> String {
        switch plan {
        case .monthly:
            return storeKit.monthlyProduct?.displayPrice ?? plan.price
        case .yearly:
            return storeKit.yearlyProduct?.displayPrice ?? plan.price
        }
    }
    
    // MARK: - CTA Section
    private var ctaSection: some View {
        VStack(spacing: 10) {
            Button(action: {
                HapticManager.tap()
                Task { await purchaseSelectedPlan() }
            }) {
                HStack(spacing: 8) {
                    if storeKit.purchaseState == .purchasing {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Start 7-Day Free Trial")
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
                                colors: [
                                    Color(red: 0.4, green: 0.5, blue: 1.0),
                                    Color(red: 0.6, green: 0.4, blue: 1.0)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .shadow(color: .purple.opacity(0.4), radius: 12, x: 0, y: 6)
                )
            }
            .disabled(storeKit.purchaseState == .purchasing)
            .scaleEffect(buttonPulse ? 1.02 : 1.0)
            
            HStack(spacing: 4) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.caption2)
                    .foregroundColor(.green)
                Text("Cancel anytime • No commitment")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .opacity(contentOpacity)
        .alert("Purchase Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func purchaseSelectedPlan() async {
        let product: Product?
        switch selectedPlan {
        case .monthly: product = storeKit.monthlyProduct
        case .yearly: product = storeKit.yearlyProduct
        }
        
        guard let product else {
            errorMessage = "Product not available. Please try again later."
            showError = true
            return
        }
        
        let success = await storeKit.purchase(product)
        if success {
            HapticManager.notification(.success)
            onUpgrade?(selectedPlan)
            dismiss()
        } else if case .failed(let msg) = storeKit.purchaseState {
            errorMessage = msg
            showError = true
            HapticManager.notification(.error)
        }
    }
    
    // MARK: - Footer
    private var footerSection: some View {
        VStack(spacing: 10) {
            Button(action: {
                Task {
                    await storeKit.restorePurchases()
                    onRestore?()
                    if storeKit.hasActiveSubscription {
                        HapticManager.notification(.success)
                        dismiss()
                    }
                }
            }) {
                Text("Restore Purchases")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.4))
            }
            
            Text("Payment charged to Apple ID. Auto-renews until cancelled.")
                .font(.ds_caption)
                .foregroundColor(.white.opacity(0.25))
                .multilineTextAlignment(.center)
        }
        .opacity(contentOpacity)
    }
    
    // MARK: - Animations
    private func startAnimations() {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            logoScale = 1.0
        }
        
        withAnimation(.easeOut(duration: 0.4).delay(0.15)) {
            contentOpacity = 1.0
        }
        
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.2))
            guard !Task.isCancelled else { return }
            withAnimation {
                tilesAppeared = true
            }
        }
        
        withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
            glowRotation = 360
        }
        
        withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
            buttonPulse = true
        }
    }
}

// MARK: - Supporting Views

struct PremiumBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "crown.fill")
                .font(.caption2)
            Text("PRO")
                .font(.caption2)
                .fontWeight(.bold)
        }
        .foregroundColor(.black.opacity(0.8))
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, Spacing.xxs)
        .background(
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color(red: 1.0, green: 0.84, blue: 0), Color(red: 1.0, green: 0.75, blue: 0.3)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        )
    }
}

struct PremiumLockOverlay: View {
    let feature: PremiumFeature
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                
                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.purple.opacity(0.2))
                            .frame(width: 50, height: 50)
                        
                        Image(systemName: "crown.fill")
                            .font(.title3)
                            .foregroundColor(.yellow)
                    }
                    
                    Text("PRO")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview
#Preview {
    PremiumUpgradeView(triggeringFeature: .recipes)
}
