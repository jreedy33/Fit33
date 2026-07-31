import SwiftUI
import StoreKit

// MARK: - Premium Feature Enum
//
// `PremiumFeature` enum drives the contextual paywall surface
// (`PremiumUpgradeView(triggeringFeature:)`). The case names are
// internal API and free of marketing language — but the rawValues
// ARE user-visible (rendered in the "You're unlocking" header) and
// must follow the canonical product vocabulary:
//   - NEVER use "AI" anywhere user-facing — Fit33's workouts are
//     algorithm-driven, not AI-generated. Canonical user-facing term
//     is "Smart Workouts" (locked 2026-05-03).
//   - Every Pro feature surface must have a case here so analytics
//     can attribute conversions to the right trigger.
enum PremiumFeature: String, CaseIterable {
    case recipes = "Unlimited Recipes"
    case smartWorkouts = "Smart Workouts"
    case advancedAnalytics = "Advanced Analytics"
    case customMealPlans = "Custom Meal Plans"
    case unlimitedHistory = "Unlimited History"
    case premiumExercises = "Premium Exercises"
    case nutritionInsights = "Nutrition Insights"
    case progressTracking = "Advanced Progress"
    case streakEdit = "Edit Streak"
    case streakSaver = "Save Your Streak"
    case weightTracking = "Weight Tracking"
    case homescreenWidgets = "Homescreen Widgets"
    case savedWorkouts = "Saved Workouts"
    case saveSharedWorkouts = "Save Shared Workouts"
    case removeAds = "Remove Ads"
    case proQuests = "Pro Daily Goals"
    case multiWearable = "Connect All Wearables"
    case proBadge = "Pro Badge"
    case lifetime = "Pro for Life"

    var icon: String {
        switch self {
        case .recipes: return "fork.knife"
        case .smartWorkouts: return "wand.and.stars"
        case .advancedAnalytics: return "chart.xyaxis.line"
        case .customMealPlans: return "menucard"
        case .unlimitedHistory: return "clock.arrow.circlepath"
        case .premiumExercises: return "figure.strengthtraining.traditional"
        case .nutritionInsights: return "leaf.fill"
        case .progressTracking: return "chart.line.uptrend.xyaxis"
        case .streakEdit: return "flame.fill"
        case .streakSaver: return "shield.lefthalf.filled"
        case .weightTracking: return "scalemass.fill"
        case .homescreenWidgets: return "square.grid.2x2.fill"
        case .savedWorkouts: return "bookmark.fill"
        case .saveSharedWorkouts: return "bookmark.fill"
        case .removeAds: return "nosign"
        case .proQuests: return "target"
        case .multiWearable: return "applewatch.radiowaves.left.and.right"
        case .proBadge: return "rosette"
        case .lifetime: return "infinity"
        }
    }

    var shortDescription: String {
        switch self {
        case .recipes: return "Thousands of healthy recipes"
        case .smartWorkouts: return "Adapts to your goals & equipment"
        case .advancedAnalytics: return "Deep fitness insights"
        case .customMealPlans: return "Personalized meal planning"
        case .unlimitedHistory: return "Complete workout history"
        case .premiumExercises: return "500+ exercise library"
        case .nutritionInsights: return "Detailed macro tracking"
        case .progressTracking: return "Track strength gains"
        case .streakEdit: return "Fix or adjust your streak"
        case .streakSaver: return "3 streak shields per month"
        case .weightTracking: return "Daily weight tracking & trends"
        case .homescreenWidgets: return "Customize your dashboard"
        case .savedWorkouts: return "Save unlimited workout templates"
        case .saveSharedWorkouts: return "Save workouts from friends"
        case .removeAds: return "Ad-free workout experience"
        case .proQuests: return "5 rerolls · custom goals · 2× XP"
        case .multiWearable: return "Connect all your wearables at once"
        case .proBadge: return "Pro badge + tier rewards"
        case .lifetime: return "Pay once, own Fit33 forever"
        }
    }

    var accentColor: Color {
        switch self {
        case .recipes: return .orange
        case .smartWorkouts: return .purple
        case .advancedAnalytics: return .blue
        case .customMealPlans: return .green
        case .unlimitedHistory: return .cyan
        case .premiumExercises: return .pink
        case .nutritionInsights: return .mint
        case .progressTracking: return .indigo
        case .streakEdit: return .orange
        case .streakSaver: return .red
        case .weightTracking: return .orange
        case .homescreenWidgets: return .purple
        case .savedWorkouts: return .blue
        case .saveSharedWorkouts: return .blue
        case .removeAds: return .yellow
        case .proQuests: return .purple
        case .multiWearable: return .green
        case .proBadge: return .yellow
        case .lifetime: return .yellow
        }
    }

    var gradient: [Color] {
        switch self {
        case .recipes: return [.orange, .yellow]
        case .smartWorkouts: return [.purple, .pink]
        case .advancedAnalytics: return [.blue, .cyan]
        case .customMealPlans: return [.green, .mint]
        case .unlimitedHistory: return [.cyan, .blue]
        case .premiumExercises: return [.pink, .red]
        case .nutritionInsights: return [.mint, .green]
        case .progressTracking: return [.indigo, .purple]
        case .streakEdit: return [.orange, .red]
        case .streakSaver: return [.red, .orange]
        case .weightTracking: return [.orange, .yellow]
        case .homescreenWidgets: return [.purple, .pink]
        case .savedWorkouts: return [.blue, .purple]
        case .saveSharedWorkouts: return [.blue, .purple]
        case .removeAds: return [.yellow, .orange]
        case .proQuests: return [.purple, .indigo]
        case .multiWearable: return [.green, .teal]
        case .proBadge: return [.yellow, .orange]
        case .lifetime: return [Color(red: 1.0, green: 0.84, blue: 0), Color(red: 1.0, green: 0.6, blue: 0.1)]
        }
    }
}

// MARK: - Subscription Plan
//
// Three-tier anchored pricing (decoy-effect aware):
//   - Monthly is the high-friction "discovery" tier; intentionally
//     looks expensive next to yearly to push users toward annual.
//   - Yearly is the "MOST POPULAR" anchor — 7-day free trial only
//     attaches here. ~50–75% of revenue lives in this tier at scale.
//   - Lifetime is the LTV-signal tier — its presence makes yearly
//     look reasonable AND captures the 5–8% of users who think
//     "I'll definitely use this for years" (Strong / Hevy don't
//     offer it; Freeletics does and converts well there).
//
// Pricing locked 2026-05-03 by user decision (intentionally LOWER
// than the previous $9.99 / $59.99 anchor — the user wants to
// optimize for trial-start volume, then raise based on demand
// signal). MONETIZATION_AGENT.md pricing table updated to match.
//
//   Monthly  $3.99/mo   (= $47.88 annualized)
//   Yearly   $29.99/yr  (= $2.49/mo equivalent — Save 37%)
//   Lifetime $149.99    (= ~5 years of yearly; one-time non-renewing IAP)
//
// All values are math-verified:
//   - Yearly $29.99 / 12 = $2.499 → "$2.49/mo"  ✓
//   - (3.99 × 12 - 29.99) / (3.99 × 12) = 17.89 / 47.88 = 37.4% → "Save 37%"  ✓
//
// Display fallback: when StoreKit hasn't loaded `displayPrice` yet,
// these hardcoded strings render. Once products load, every paywall
// surface uses `storeKit.<plan>Product.displayPrice` for locale-aware
// formatting (per MONETIZATION_AGENT invariant 6 — the UI MUST agree
// with what App Store charges).
enum SubscriptionPlan: String, CaseIterable {
    case monthly = "Monthly"
    case yearly = "Yearly"
    case lifetime = "Lifetime"

    var price: String {
        switch self {
        case .monthly: return "$3.99"
        case .yearly: return "$29.99"
        case .lifetime: return "$149.99"
        }
    }

    var period: String {
        switch self {
        case .monthly: return "/month"
        case .yearly: return "/year"
        case .lifetime: return "one-time"
        }
    }

    var monthlyEquivalent: String {
        switch self {
        case .monthly: return "$3.99/mo"
        case .yearly: return "$2.49/mo"
        case .lifetime: return "Pay once"
        }
    }

    var savings: String? {
        switch self {
        case .monthly: return nil
        case .yearly: return "Save 37%"
        case .lifetime: return "Best value"
        }
    }

    /// Marketing badge above each plan card. Copy is intentionally
    /// distinct so each tier has a reason to be looked at:
    ///   - yearly = "MOST POPULAR" (social proof)
    ///   - lifetime = "BEST VALUE" (LTV anchor + decoy)
    var badge: String? {
        switch self {
        case .monthly: return nil
        case .yearly: return "MOST POPULAR"
        case .lifetime: return "BEST VALUE"
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    
    // Premium benefits with tiles - matching app icon style.
    // No "AI" copy anywhere — Fit33's workouts are algorithm-driven,
    // not AI-generated. Canonical user-facing term is "Smart Workouts"
    // (locked 2026-05-03). MONETIZATION_AGENT.md vocabulary section.
    private let benefits: [(icon: String, title: String, subtitle: String, gradient: [Color])] = [
        ("wand.and.stars", "Smart Workouts", "Adapts to you", [.purple, .pink]),
        ("chart.xyaxis.line", "Deep Analytics", "PRs · volume · trends", [.blue, .cyan]),
        ("flame.fill", "Streak Protection", "3 shields per month", [.orange, .yellow]),
        ("fork.knife", "Recipes & Meals", "Unlimited library", [.green, .mint]),
        ("scalemass.fill", "Weight Tracking", "Daily trends & body comp", [.pink, .red]),
        ("nosign", "Zero Ads", "Never see one again", [.indigo, .purple])
    ]
    
    var body: some View {
        ZStack {
            // Background
            backgroundView
            
            VStack(spacing: 0) {
                // Close button
                HStack {
                    Spacer()
                    Button(action: {
                        NewUserJourneyTracker.shared.logPaywall(
                            surface: "tier3_modal",
                            action: "dismiss",
                            triggeringFeature: "\(triggeringFeature)"
                        )
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.ds_labelMedium)
                            .foregroundColor(.white.opacity(0.6))
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.white.opacity(0.1)))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Close")
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
        .onAppear {
            startAnimations()
            NewUserJourneyTracker.shared.logPaywall(
                surface: "tier3_modal",
                action: "view",
                triggeringFeature: "\(triggeringFeature)"
            )
        }
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
                .foregroundColor(.white.opacity(0.7))
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
                    .foregroundColor(.white.opacity(0.7))
                
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
    
    // MARK: - Pricing Section (3-tier anchored: Monthly · Yearly · Lifetime)
    //
    // Yearly defaults selected (LTV anchor). Lifetime exists primarily
    // as a decoy that makes Yearly look reasonable AND captures the
    // 5–8% high-LTV-signal segment. Monthly is the friction-tier.
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
        // Gold badge — matches PaywallFirstScreenView; gold is the
        // sanctioned paywall language (DESIGN_AGENT invariant 5).
        let badgeColor: Color = plan == .lifetime
            ? Color(red: 1.0, green: 0.84, blue: 0)
            : .yellow

        return Button(action: {
            withAnimation(.spring(response: 0.3)) { selectedPlan = plan }
            HapticManager.selectionChanged()
        }) {
            VStack(spacing: 0) {
                if let badge = plan.badge {
                    HStack {
                        Spacer()
                        Text(badge)
                            .font(.system(size: 10, weight: .heavy))
                            .tracking(0.5)
                            .foregroundColor(.black)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(badgeColor))
                            .offset(y: 8)
                        Spacer()
                    }
                }

                HStack(spacing: 12) {
                    Circle()
                        .stroke(isSelected ? Color.yellow : Color.white.opacity(0.3), lineWidth: 2)
                        .frame(width: 20, height: 20)
                        .overlay(
                            Circle()
                                .fill(Color.yellow)
                                .frame(width: 10, height: 10)
                                .opacity(isSelected ? 1 : 0)
                        )

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 8) {
                            Text(plan.rawValue)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)

                            if let savings = plan.savings, plan.badge == nil {
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
                            .foregroundColor(.white.opacity(0.7))
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 1) {
                        Text(displayPrice(for: plan))
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        Text(plan.period)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.65))
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(isSelected ? 0.08 : 0.03))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(
                                    isSelected ? Color.yellow : Color.white.opacity(0.08),
                                    lineWidth: isSelected ? 2 : 1
                                )
                        )
                )
            }
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func displayPrice(for plan: SubscriptionPlan) -> String {
        switch plan {
        case .monthly:
            return storeKit.monthlyProduct?.displayPrice ?? plan.price
        case .yearly:
            return storeKit.yearlyProduct?.displayPrice ?? plan.price
        case .lifetime:
            return storeKit.lifetimeProduct?.displayPrice ?? plan.price
        }
    }

    /// Yearly = 7-day free trial CTA; Monthly = direct subscribe;
    /// Lifetime = direct one-time purchase. Copy MUST exactly match
    /// App Store Connect intro offer config or App Review will reject
    /// (MONETIZATION_AGENT invariant 6).
    private var ctaText: String {
        switch selectedPlan {
        case .yearly:   return "Start 7-Day Free Trial"
        case .monthly:  return "Subscribe Monthly"
        case .lifetime: return "Get Pro for Life"
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
                            .tint(.black)
                    } else {
                        Text(ctaText)
                            .font(.headline)
                            .fontWeight(.bold)

                        Image(systemName: "arrow.right")
                            .font(.subheadline.weight(.bold))
                    }
                }
                // Gold CTA — identical treatment to PaywallFirstScreenView
                // so the same "Start 7-Day Free Trial" action doesn't render
                // as two different buttons (DESIGN_AGENT invariant 5).
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.md)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.yellow, .orange],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .shadow(color: .orange.opacity(0.4), radius: 12, x: 0, y: 6)
                )
                .opacity(storeKit.purchaseState == .purchasing ? 0.6 : 1.0)
            }
            .disabled(storeKit.purchaseState == .purchasing)
            .scaleEffect(buttonPulse ? 1.02 : 1.0)

            HStack(spacing: 6) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.caption2)
                    .foregroundColor(.green)
                Text("Cancel in 2 taps • Auto-renew off anytime")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
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
        case .monthly:  product = storeKit.monthlyProduct
        case .yearly:   product = storeKit.yearlyProduct
        case .lifetime: product = storeKit.lifetimeProduct
        }

        guard let product else {
            errorMessage = "Product not available. Please try again later."
            showError = true
            return
        }

        let success = await storeKit.purchase(product)
        if success {
            HapticManager.notification(.success)
            NewUserJourneyTracker.shared.logPaywall(
                surface: "tier3_modal",
                action: "convert",
                sku: product.id,
                priceUsd: NSDecimalNumber(decimal: product.price).doubleValue,
                triggeringFeature: "\(triggeringFeature)"
            )
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
                    NewUserJourneyTracker.shared.logPaywall(
                        surface: "tier3_modal",
                        action: "restore",
                        triggeringFeature: "\(triggeringFeature)"
                    )
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
                    .foregroundColor(.white.opacity(0.65))
            }
            
            Text("Payment charged to Apple ID. Auto-renews until cancelled.")
                .font(.ds_caption)
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)

            HStack(spacing: 8) {
                Link("Privacy Policy", destination: LegalURLs.privacy)
                Text("·")
                    .foregroundColor(.white.opacity(0.5))
                Link("Terms of Use", destination: LegalURLs.terms)
            }
            .font(.ds_labelSmall)
            .foregroundColor(.white.opacity(0.75))
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
        
        // Infinite glow rotation + button pulse are decorative — gated per
        // motion policy (finding AE: ran under Reduce Motion / Low Power).
        if !MotionPolicy.shouldDisableDecorative(reduceMotion: reduceMotion) {
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                glowRotation = 360
            }
            
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                buttonPulse = true
            }
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
    
    // Full-bleed material cover, so the adaptiveMaterialBackground wrapper
    // (which is a background modifier) doesn't fit — honor Reduce
    // Transparency directly (design-system invariant 8).
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    
    var body: some View {
        Button(action: onTap) {
            ZStack {
                if reduceTransparency {
                    Rectangle().fill(Color.cardBackground)
                } else {
                    Rectangle().fill(.ultraThinMaterial)
                }
                
                VStack(spacing: 10) {
                    ZStack {
                        // Gold, not purple — gold is the sanctioned paywall
                        // language (DESIGN_AGENT invariant 5).
                        Circle()
                            .fill(Color.yellow.opacity(0.2))
                            .frame(width: 50, height: 50)
                        
                        Image(systemName: "crown.fill")
                            .font(.title3)
                            .foregroundColor(.yellow)
                    }
                    
                    Text("PRO")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
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
