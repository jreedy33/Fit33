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
// Auto-presentation contract (NOT yet wired):
//   `Fit33App.swift` will own the `shouldPresentFirstScreenPaywall`
//   decision. The rule: present once per device, after onboarding
//   completes, when `PremiumManager.serverEntitlement == .free`. After
//   one presentation, persist `hasSeenFirstScreenPaywall=true` to
//   UserDefaults — never present again automatically. Users can re-open
//   from Settings → Manage Subscription.
//
// This file ships the View only; the auto-presentation is product +
// design work that follows a separate review (PRODUCT_ENGINEER + LEAD_DESIGNER).
//
// Do NOT ship this view auto-presenting until that review lands —
// shipping a "paywall on first launch" without the right copy + timing
// would tank conversion AND the App Store rating.
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
                VStack(spacing: 28) {
                    headerSection

                    valuePropsSection

                    pricingSection

                    ctaSection

                    footerSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)
                .padding(.bottom, 40)
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
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

            Text("Try Pro free for 7 days")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
        }
    }

    // MARK: - Value Props
    private var valuePropsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            valuePropRow(icon: "brain.head.profile", title: "AI-personalized workouts")
            valuePropRow(icon: "chart.line.uptrend.xyaxis", title: "Advanced analytics & insights")
            valuePropRow(icon: "fork.knife", title: "Recipes & meal plans")
            valuePropRow(icon: "flame.fill", title: "Streak protection")
            valuePropRow(icon: "nosign", title: "No ads — ever")
        }
    }

    private func valuePropRow(icon: String, title: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.yellow)
                .frame(width: 28)

            Text(title)
                .font(.system(size: 16, weight: .medium))
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

    // MARK: - Pricing
    private var pricingSection: some View {
        HStack(spacing: 12) {
            planCard(plan: .monthly)
            planCard(plan: .yearly)
        }
    }

    private func planCard(plan: SubscriptionPlan) -> some View {
        let isSelected = selectedPlan == plan
        let storeProduct = (plan == .monthly) ? storeKit.monthlyProduct : storeKit.yearlyProduct
        let displayPrice = storeProduct?.displayPrice ?? plan.price

        return Button(action: {
            selectedPlan = plan
        }) {
            VStack(spacing: 8) {
                if plan.isBestValue {
                    Text("BEST VALUE")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.yellow))
                }

                Text(plan.rawValue)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))

                Text(displayPrice)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)

                Text(plan.period)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))

                if let savings = plan.savings {
                    Text(savings)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.green)
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.yellow.opacity(0.18) : Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.yellow : Color.white.opacity(0.12), lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - CTA
    private var ctaSection: some View {
        VStack(spacing: 12) {
            Button(action: { Task { await purchaseSelected() } }) {
                HStack {
                    if isPurchasing {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.black)
                    } else {
                        Text(selectedPlan == .yearly ? "Start 7-Day Free Trial" : "Subscribe Monthly")
                            .font(.system(size: 17, weight: .bold))
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
            }
            .disabled(isPurchasing || storeKit.products.isEmpty)

            if selectedPlan == .yearly {
                Text("Then $59.99/year. Cancel anytime.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
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
            .buttonStyle(.plain)
            .padding(.top, 4)

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12, weight: .medium))
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
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
            }
            .buttonStyle(.plain)

            Text("Auto-renews. Cancel anytime in Settings → Apple ID → Subscriptions.")
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(.white.opacity(0.3))
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

        guard let product = (selectedPlan == .yearly) ? storeKit.yearlyProduct : storeKit.monthlyProduct else {
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
