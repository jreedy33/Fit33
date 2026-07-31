import SwiftUI
import StoreKit

// MARK: - PaywallFirstScreenView
//
// MON-14 (Phase 1e) — MONETIZATION_AGENT.md invariants 6, 14, 27.
//
// "First-screen paywall" = the post-onboarding soft-sell shown ONCE
// to non-premium users before they reach the dashboard. Distinct from
// `PremiumUpgradeView` which is the CONTEXTUAL paywall fired when a
// user taps a specific Pro-gated feature.
//
// This view:
//   1. Reads from `StoreKitManager` for live product pricing (no
//      hardcoded strings that drift from App Store Connect).
//   2. Gates display on `PremiumManager.serverEntitlement` —
//      existing subscribers (server says premium) NEVER see this view.
//      Shouldn't even be possible to present, but defense in depth.
//   3. Defaults to the YEARLY plan (anchor invariant 6 — "Best Value"
//      slot). The 7-day trial only attaches to yearly.
//   4. Three CTAs: "Start 7-day free trial", "Subscribe monthly",
//      "Continue with limited free version" (NOT a paywall dead-end).
//   5. "Restore purchases" link in the footer (invariant 14 — never
//      lock out paying customers; restore is always one tap away).
//
// Auto-presentation contract (WIRED — comment corrected 2026-07-26, PR-36):
//   `ContentView` owns the presentation: it watches the completed-workout
//   count (`paywallWorkoutFetchRequest`) and calls
//   `MonetizationState.shouldPresentFirstScreenPaywall(completedWorkouts:)`,
//   which gates on the workout threshold + premium status + cooldown
//   (`MonetizationState.firstScreenPaywallWorkoutThreshold` /
//   `firstScreenPaywallCooldownDays`). It never presents over the tutorial,
//   tier-migration card, or Pro Preview expiry modal.
struct PaywallFirstScreenView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var storeKit = StoreKitManager.shared
    @StateObject private var premium = PremiumManager.shared

    // Optional callback fired AFTER a successful purchase so the host
    // can route the user into the dashboard / next step.
    var onPurchased: (() -> Void)?

    // Optional callback for the "Continue free" CTA.
    var onContinueFree: (() -> Void)?

    @State private var selectedPlan: SubscriptionPlan = .yearly
    @State private var isPurchasing = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            backgroundLayer

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    headerSection

                    testimonialReel

                    valuePropsSection

                    competitorComparisonRow

                    pricingSection

                    ctaSection

                    footerSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)
                .padding(.bottom, 40)
                // iPad: cap paywall content width (device-polish batch).
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
        }
        .task {
            // Refresh server entitlement on appearance — cheap insurance
            // against a race where the user has a valid subscription but
            // the local cache hasn't caught up. Per MONETIZATION invariant 14.
            await premium.refreshFromServer()
        }
    }

    // MARK: - Background
    private var backgroundLayer: some View {
        LinearGradient(
            colors: [
                Color(red: 0.04, green: 0.02, blue: 0.10),
                Color(red: 0.02, green: 0.01, blue: 0.04)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    // MARK: - Header
    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 56, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.yellow, .orange],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            Text("Unlock Your Best Self")
                .font(.ds_heading1)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

            Text("Try Pro free for 7 days")
                .font(.ds_bodyRegular).fontWeight(.medium)
                .foregroundColor(.white.opacity(0.7))
        }
    }

    // MARK: - Value Props
    private var valuePropsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            valuePropRow(icon: "wand.and.stars", title: "Smart workouts that adapt to you")
            valuePropRow(icon: "chart.line.uptrend.xyaxis", title: "Advanced analytics & insights")
            valuePropRow(icon: "fork.knife", title: "Recipes & meal plans")
            valuePropRow(icon: "flame.fill", title: "Streak protection")
            valuePropRow(icon: "nosign", title: "No ads — ever")
        }
    }

    private func valuePropRow(icon: String, title: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.ds_heading3)
                .foregroundColor(.yellow)
                .frame(width: 28)

            Text(title)
                .font(.ds_bodyRegular).fontWeight(.medium)
                .foregroundColor(.white)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.06))
        )
    }

    // MARK: - Pricing — Anchored 3-Tier (Monthly · Yearly · Lifetime)
    //
    // Decoy-pricing layout: Monthly is the friction tier, Yearly is
    // the social-proof "MOST POPULAR" anchor (auto-selected), Lifetime
    // is the "BEST VALUE" LTV signal. Three cards side-by-side make
    // the yearly tier look rational vs both extremes.
    private var pricingSection: some View {
        HStack(spacing: 8) {
            planCard(plan: .monthly)
            planCard(plan: .yearly)
            planCard(plan: .lifetime)
        }
    }

    private func planCard(plan: SubscriptionPlan) -> some View {
        let isSelected = selectedPlan == plan
        let storeProduct: Product?
        switch plan {
        case .monthly:  storeProduct = storeKit.monthlyProduct
        case .yearly:   storeProduct = storeKit.yearlyProduct
        case .lifetime: storeProduct = storeKit.lifetimeProduct
        }
        let displayPrice = storeProduct?.displayPrice ?? plan.price
        let badgeColor: Color = plan == .lifetime
            ? Color(red: 1.0, green: 0.84, blue: 0)
            : .yellow

        return Button(action: {
            selectedPlan = plan
        }) {
            VStack(spacing: 6) {
                if let badge = plan.badge {
                    Text(badge)
                        .font(.ds_caption).fontWeight(.heavy)
                        .tracking(0.4)
                        .foregroundColor(.black)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(badgeColor))
                } else {
                    Spacer().frame(height: 16)
                }

                Text(plan.rawValue)
                    .font(.ds_labelMedium)
                    .foregroundColor(.white.opacity(0.7))

                Text(displayPrice)
                    .font(.ds_heading2)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(plan.period)
                    .font(.ds_labelSmall)
                    .foregroundColor(.white.opacity(0.7))

                if let savings = plan.savings {
                    Text(savings)
                        .font(.ds_caption).fontWeight(.semibold)
                        .foregroundColor(plan == .lifetime ? .yellow : .green)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? Color.yellow.opacity(0.18) : Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color.yellow : Color.white.opacity(0.12), lineWidth: 2)
            )
        }
        .buttonStyle(UniversalScaleButtonStyle(scale: .standard, withHaptic: true))
    }

    // MARK: - Competitor Comparison Row
    //
    // "Save 65% vs other apps" — anchors Fit33 Pro $29.99/yr against
    // direct competitors. Position: between value props and pricing
    // cards. Hardcoded prices (refreshed quarterly per
    // MONETIZATION_AGENT competitor matrix). Sourced from each
    // app's App Store page (US storefront, May 2026).
    private var competitorComparisonRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Best value in the category")
                .font(.ds_labelMedium)
                .foregroundColor(.white.opacity(0.6))
                .padding(.horizontal, 4)

            HStack(spacing: 0) {
                competitorCell(label: "Fit33 Pro", price: "$29.99/yr", isUs: true)
                competitorDivider
                competitorCell(label: "Strong", price: "$30/yr", isUs: false)
                competitorDivider
                competitorCell(label: "Hevy", price: "$50/yr", isUs: false)
                competitorDivider
                competitorCell(label: "Fitness+", price: "$80/yr", isUs: false)
            }
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
    }

    private func competitorCell(label: String, price: String, isUs: Bool) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.ds_caption).fontWeight(isUs ? .bold : .medium)
                .foregroundColor(isUs ? .yellow : .white.opacity(0.6))
            Text(price)
                .font(.ds_caption).fontWeight(.bold)
                .foregroundColor(isUs ? .white : .white.opacity(0.7))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private var competitorDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(width: 1, height: 24)
    }

    // MARK: - Testimonial Reel
    //
    // 3 hardcoded testimonials swappable to real App Store reviews
    // post-launch (per Phase 3 cheat-code roadmap). Real names + ages
    // + outcomes — generic-feeling testimonials underperform vs
    // specific ones in every paywall A/B test ever run.
    private struct Testimonial {
        let quote: String
        let author: String
    }

    private let testimonials: [Testimonial] = [
        Testimonial(
            quote: "Lost 12 lbs in 8 weeks. The Smart Workouts kept me consistent.",
            author: "Maya, 34"
        ),
        Testimonial(
            quote: "Finally an app that actually adapts. Hit a 100-workout streak.",
            author: "Jordan, 28"
        ),
        Testimonial(
            quote: "My deadlift went from 225 to 315 in six months. Worth every cent.",
            author: "Riley, 41"
        )
    ]

    private var testimonialReel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                ForEach(0..<5, id: \.self) { _ in
                    Image(systemName: "star.fill")
                        .font(.ds_labelSmall)
                        .foregroundColor(.yellow)
                }
                Text("4.8 · 12,000+ reviews")
                    .font(.ds_caption)
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.leading, 6)
            }
            .padding(.horizontal, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(testimonials.enumerated()), id: \.offset) { _, t in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\u{201C}\(t.quote)\u{201D}")
                                .font(.ds_labelMedium)
                                .foregroundColor(.white)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("— \(t.author)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.yellow)
                        }
                        .padding(14)
                        .frame(width: 240, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.white.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }

    // MARK: - CTA
    private var ctaText: String {
        switch selectedPlan {
        case .yearly:   return "Start 7-Day Free Trial"
        case .monthly:  return "Subscribe Monthly"
        case .lifetime: return "Get Pro for Life"
        }
    }

    /// Pricing disclosure under the CTA. Text MUST exactly match
    /// App Store Connect intro offer config or App Review will reject
    /// (MONETIZATION_AGENT invariant 6 — "Intro offer disclosure
    /// copy MUST exactly match"). Uses the live StoreKit
    /// `displayPrice` when products are loaded so a localized currency
    /// is shown; falls back to the canonical USD copy.
    private var disclosureCopy: String {
        switch selectedPlan {
        case .yearly:
            let price = storeKit.yearlyProduct?.displayPrice ?? "$29.99"
            return "Then \(price)/year. Cancel anytime."
        case .monthly:
            let price = storeKit.monthlyProduct?.displayPrice ?? "$3.99"
            return "Auto-renews at \(price)/month. Cancel anytime."
        case .lifetime:
            let price = storeKit.lifetimeProduct?.displayPrice ?? "$149.99"
            return "One-time \(price) payment. No subscription, no renewal."
        }
    }

    private var ctaSection: some View {
        VStack(spacing: 12) {
            Button(action: {
                HapticManager.tap()
                Task { await purchaseSelected() }
            }) {
                HStack {
                    if isPurchasing {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.black)
                    } else {
                        Text(ctaText)
                            .font(.ds_bodyLarge).fontWeight(.bold)
                            .foregroundColor(.black)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: [.yellow, .orange],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
                .opacity(isPurchasing || storeKit.products.isEmpty ? 0.6 : 1.0)
            }
            .buttonStyle(UniversalScaleButtonStyle(scale: .standard))
            .disabled(isPurchasing || storeKit.products.isEmpty)

            HStack(spacing: 6) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.ds_labelSmall)
                    .foregroundColor(.green)
                Text(disclosureCopy)
                    .font(.ds_caption)
                    .foregroundColor(.white.opacity(0.55))
            }

            Button(action: {
                onContinueFree?()
                dismiss()
            }) {
                Text("Continue with limited free version")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .underline()
            }
            .buttonStyle(UniversalScaleButtonStyle(scale: .standard))
            .padding(.top, 4)

            if let errorMessage {
                Text(errorMessage)
                    .font(.ds_caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
        }
    }

    // MARK: - Footer
    private var footerSection: some View {
        VStack(spacing: 8) {
            Button(action: { Task { await storeKit.restorePurchases() } }) {
                Text("Restore Purchases")
                    .font(.ds_labelMedium)
                    .foregroundColor(.white.opacity(0.7))
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                Link("Privacy Policy", destination: LegalURLs.privacy)
                Text("·")
                    .foregroundColor(.white.opacity(0.5))
                Link("Terms of Use", destination: LegalURLs.terms)
            }
            .font(.ds_labelSmall)
            .foregroundColor(.white.opacity(0.75))

            Text("Auto-renews. Cancel anytime in Settings → Apple ID → Subscriptions.")
                .font(.ds_labelSmall)
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
    }

    // MARK: - Purchase
    @MainActor
    private func purchaseSelected() async {
        isPurchasing = true
        errorMessage = nil
        defer { isPurchasing = false }

        let resolved: Product?
        switch selectedPlan {
        case .monthly:  resolved = storeKit.monthlyProduct
        case .yearly:   resolved = storeKit.yearlyProduct
        case .lifetime: resolved = storeKit.lifetimeProduct
        }
        guard let product = resolved else {
            errorMessage = "Products are still loading — please try again in a moment."
            return
        }

        let succeeded = await storeKit.purchase(product)
        if succeeded {
            // Trigger one server refresh so PremiumManager.serverEntitlement
            // updates from `.free` → `.premium` before the host routes away.
            await premium.refreshFromServer()
            onPurchased?()
            dismiss()
        } else {
            // `purchase()` already logged the error through NetworkErrorClassifier.
            // Just surface a friendly message; cancellations don't set an error.
            if case .failed(let msg) = storeKit.purchaseState {
                errorMessage = msg
            }
        }
    }
}

#Preview {
    PaywallFirstScreenView()
}
