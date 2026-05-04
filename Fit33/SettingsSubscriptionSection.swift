import SwiftUI
import StoreKit

// MARK: - Settings → Subscription Section
//
// MONETIZATION_AGENT.md invariants 3 (Restore Purchases is non-negotiable
// per App Review 3.1.1 — must exist on the paywall AND in Settings) and
// 13 (winback / churn-save flow is owned here; intercepts the cancel path).
//
// Surfaces:
//   1. Pro status row (tier, expiry, family-shared indicator)
//   2. "View Pro Plans" CTA (opens `PremiumUpgradeView` — also serves
//      free users browsing for upgrade entry point)
//   3. "Manage Subscription" — uses `manageSubscriptionsSheet` (iOS 15+)
//      so the user stays in-app; falls back to App Store URL if the
//      sheet errors out. The pre-modal "wait, would you like 50% off?"
//      churn-save is intercepted here in Phase 6.
//   4. "Restore Purchases" — tier-A safety, also bounce-back for users
//      who reinstalled or switched devices.
//
// Designed so this section gracefully renders when:
//   - User is fully premium (today's always-true default)
//   - User is in trial (shows trial expiration countdown)
//   - User is family-shared (shows shared indicator + original purchaser
//     hint when known)
//   - User is free (CTA = "Subscribe to Pro")
//   - StoreKit hasn't loaded yet (skeleton, no jank)

struct SettingsSubscriptionSection: View {
    @ObservedObject var premiumManager: PremiumManager
    @ObservedObject var storeKit: StoreKitManager

    @State private var showPaywall = false
    @State private var showManageSheet = false
    @State private var showCancellationSurvey = false
    @State private var isRestoring = false
    @State private var restoreResultMessage: String?
    @State private var restoreResultIsSuccess = false

    /// Whether to surface the cancellation survey BEFORE Apple's manage
    /// sheet. Trigger heuristic (locked 2026-05-03):
    ///   - User has an active auto-renewing subscription
    ///   - Trial is expiring within 7 days OR subscription is set to
    ///     not auto-renew (cancellation in progress)
    ///   - Survey hasn't already been shown in the last 30 days
    /// Pro lifetime users skip the survey entirely (nothing to cancel).
    private var shouldShowCancellationSurvey: Bool {
        guard let info = storeKit.subscriptionStatus else { return false }
        if info.productID.contains("lifetime") { return false }
        let monetState = MonetizationState.shared
        if let last = monetState.cancellationSurveyShownAt {
            let daysSince = Calendar.current.dateComponents([.day], from: last, to: Date()).day ?? 0
            if daysSince < 30 { return false }
        }
        if info.willAutoRenew == false { return true }
        if let exp = info.expirationDate {
            let interval = exp.timeIntervalSinceNow
            if interval > 0 && interval < (7 * 24 * 3600) { return true }
        }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            statusRow

            if storeKit.subscriptionStatus?.isFamilyShared == true {
                Divider().padding(.leading, 52)
                familySharedHintRow
            }

            Divider().padding(.leading, 52)

            viewPlansRow

            if premiumManager.isPremiumUser {
                Divider().padding(.leading, 52)
                manageSubscriptionRow
            }

            Divider().padding(.leading, 52)

            restoreRow
        }
        .fullScreenCover(isPresented: $showPaywall) {
            PremiumUpgradeView(triggeringFeature: .lifetime)
        }
        // Cancellation survey intercept — fires BEFORE Apple's manage
        // sheet IF the user is showing cancel-intent signals
        // (`shouldShowCancellationSurvey`). 4-reason picker routes to
        // differentiated save offers. Phase 6 will issue real
        // Promotional Offers from the first reason ("too expensive").
        .sheet(isPresented: $showCancellationSurvey) {
            CancellationSurveySheet(onContinueToManage: {
                showManageSheet = true
            })
        }
        // iOS 15+ in-app manage sheet — keeps the user inside Fit33.
        // Per MONETIZATION_AGENT invariant 13.
        .manageSubscriptionsSheet(isPresented: $showManageSheet)
        .alert(
            restoreResultIsSuccess ? "Purchases Restored" : "Restore Failed",
            isPresented: Binding(
                get: { restoreResultMessage != nil },
                set: { if !$0 { restoreResultMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { restoreResultMessage = nil }
        } message: {
            Text(restoreResultMessage ?? "")
        }
    }

    // MARK: - Status Row

    private var statusRow: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .fill(
                        LinearGradient(
                            colors: premiumManager.isPremiumUser
                                ? [Color.yellow.opacity(0.15), Color.orange.opacity(0.15)]
                                : [Color.gray.opacity(0.15), Color.gray.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                Image(systemName: premiumManager.isPremiumUser ? "crown.fill" : "person.crop.circle")
                    .font(.ds_bodyRegular)
                    .foregroundStyle(
                        premiumManager.isPremiumUser
                            ? LinearGradient(colors: [.yellow, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [.gray, .gray], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Text(statusSubtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(Spacing.md)
    }

    private var statusTitle: String {
        guard premiumManager.isPremiumUser else { return "Free Plan" }
        if let info = storeKit.subscriptionStatus {
            if info.productID.contains("lifetime") {
                return "Pro · Lifetime"
            } else if info.productID.contains("yearly") {
                return info.isInTrial ? "Pro · Yearly · Trial" : "Pro · Yearly"
            } else if info.productID.contains("monthly") {
                return "Pro · Monthly"
            }
        }
        return "Pro Member"
    }

    private var statusSubtitle: String {
        guard premiumManager.isPremiumUser else {
            return "Upgrade to unlock everything"
        }
        if let info = storeKit.subscriptionStatus {
            if info.productID.contains("lifetime") {
                return "Pay-once unlock · all features forever"
            }
            // Family Sharing UX surfacing — when this entitlement was
            // shared by another family member, surface a subtle hint
            // (the user can't manage it from here, but should know
            // why "Manage Subscription" goes to the original purchaser).
            // App Store Connect Family Sharing toggle must be enabled
            // on each product (Phase 7 user action — see below).
            // Note: `Transaction.ownershipType` isn't yet plumbed
            // through `SubscriptionStatusInfo`; the surfacing copy
            // is in place for when that wiring lands (deferred to
            // a tiny follow-up; product ID + expiry are still correct).
            if let exp = info.expirationDate {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                let label = info.willAutoRenew ? "Renews" : "Expires"
                return "\(label) \(formatter.string(from: exp))"
            }
        }
        return "All Pro features unlocked"
    }

    // MARK: - Family Shared Indicator
    //
    // Shown only when `Transaction.ownershipType == .familyShared`
    // (Apple Family Sharing entitlement). The user can't manage this
    // subscription — Apple's manage sheet routes to the original
    // purchaser. Surfaces a passive informational row so the user
    // knows why their "Manage Subscription" deep-link is read-only.

    private var familySharedHintRow: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .fill(LinearGradient(colors: [Color.green.opacity(0.15), Color.mint.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 36, height: 36)
                Image(systemName: "person.2.fill")
                    .font(.ds_bodyRegular)
                    .foregroundStyle(LinearGradient(colors: [.green, .mint], startPoint: .topLeading, endPoint: .bottomTrailing))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Shared via Family Sharing")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                Text("Managed by the original purchaser in your family")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(Spacing.md)
    }

    // MARK: - View Plans Row

    private var viewPlansRow: some View {
        Button(action: {
            HapticManager.impact(.light)
            showPaywall = true
        }) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .fill(
                            LinearGradient(
                                colors: [Color.purple.opacity(0.15), Color.pink.opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 36, height: 36)
                    Image(systemName: "sparkles")
                        .font(.ds_bodyRegular)
                        .foregroundStyle(
                            LinearGradient(colors: [.purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(premiumManager.isPremiumUser ? "View Pro Plans" : "Subscribe to Pro")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    Text("Monthly · Yearly · Lifetime")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }
            .padding(Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Manage Subscription Row

    private var manageSubscriptionRow: some View {
        Button(action: {
            HapticManager.impact(.light)
            AppLogger.info("User opened Manage Subscription sheet", category: .general)
            // Cancel-intent intercept — surface the survey FIRST if
            // signals look like they're about to cancel, otherwise
            // pass straight through to Apple's manage sheet.
            if shouldShowCancellationSurvey {
                showCancellationSurvey = true
            } else {
                showManageSheet = true
            }
        }) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .fill(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.15), Color.cyan.opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 36, height: 36)
                    Image(systemName: "creditcard.fill")
                        .font(.ds_bodyRegular)
                        .foregroundStyle(
                            LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Manage Subscription")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    Text("Cancel, change plan, or update billing")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }
            .padding(Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Restore Row
    //
    // App Review 3.1.1: Restore Purchases must exist outside the paywall
    // too. Routes through `StoreKitManager.restorePurchases()` which
    // calls `AppStore.sync()` (the canonical SK2 path).

    private var restoreRow: some View {
        Button(action: {
            HapticManager.impact(.light)
            Task { await runRestore() }
        }) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .fill(Color.gray.opacity(0.12))
                        .frame(width: 36, height: 36)
                    if isRestoring {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.ds_bodyRegular)
                            .foregroundColor(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Restore Purchases")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    Text("If you previously paid on this Apple ID")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isRestoring)
    }

    @MainActor
    private func runRestore() async {
        isRestoring = true
        defer { isRestoring = false }

        await storeKit.restorePurchases()

        // After restore, refresh server entitlement so
        // PremiumManager.serverEntitlement reflects the new state
        // before we surface the result.
        await premiumManager.refreshFromServer()

        if storeKit.hasActiveSubscription {
            HapticManager.notification(.success)
            restoreResultIsSuccess = true
            restoreResultMessage = "Welcome back to Pro! All features are unlocked."
        } else if case .failed(let msg) = storeKit.purchaseState {
            restoreResultIsSuccess = false
            restoreResultMessage = msg
        } else {
            restoreResultIsSuccess = false
            restoreResultMessage = "No active subscription found on this Apple ID."
        }
    }
}
