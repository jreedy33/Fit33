import SwiftUI
import StoreKit

// MARK: - Monetization Cheat-Code Views
//
// Phase 3 conversion + retention surfaces, kept in one file to make
// the suite legible (and easy to sweep / iterate). All components are
// stateless wrappers around `MonetizationState.shared` + `StoreKitManager`
// so a SwiftUI parent can drop one in without wiring extra plumbing.
//
// Composition map:
//   - `TrialCountdownBanner` — dashboard banner during last 48h of trial
//   - `ProBadgeView` — silver/gold/diamond/founding tier badge
//   - `StreakSaverPaywallModal` — fired when free user about to lose streak
//   - `AchievementProRevealModal` — milestone-triggered 7-day Pro Reveal
//   - `CancellationSurveySheet` — pre-manage-subscription churn-save
//
// Each has its own preview at the bottom for design review.

// MARK: - Trial Countdown Banner
//
// Surfaces during the LAST 48h of the App Store trial. Real urgency
// (uses `Transaction.expirationDate` from StoreKit, never fake). Per
// MONETIZATION_AGENT cheat-code roadmap — drives trial-to-paid intent
// in the highest-friction window.
//
// Drop on the dashboard above the welcome card. Auto-hides when no
// trial is active or > 48h remain or user has already converted.
struct TrialCountdownBanner: View {
    @ObservedObject private var storeKit = StoreKitManager.shared
    @ObservedObject private var premium = PremiumManager.shared
    @State private var showPaywall = false

    private var hoursRemaining: Int? {
        guard let info = storeKit.subscriptionStatus, info.isInTrial,
              let expiry = info.expirationDate else { return nil }
        let interval = expiry.timeIntervalSinceNow
        guard interval > 0 else { return 0 }
        let hours = Int(interval / 3600)
        guard Double(hours) <= MonetizationState.trialCountdownThresholdHours else { return nil }
        return hours
    }

    var body: some View {
        if let hours = hoursRemaining {
            Button {
                HapticManager.impact(.light)
                showPaywall = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "hourglass.bottomhalf.filled")
                        .font(.title3)
                        .foregroundColor(.white)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Trial ends in \(hours) \(hours == 1 ? "hour" : "hours")")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        Text("Continue Pro for $29.99/yr · cancel anytime")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.85))
                    }

                    Spacer()

                    Text("Keep Pro")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.white))
                }
                .padding(14)
                .background(
                    LinearGradient(
                        colors: [Color.orange, Color.red],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .orange.opacity(0.4), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(.plain)
            .fullScreenCover(isPresented: $showPaywall) {
                PremiumUpgradeView(triggeringFeature: .lifetime)
            }
        }
    }
}

// MARK: - Pro Badge View
//
// Vanity tier badge — driven by `MonetizationState.proBadgeTier`.
// Render anywhere a Pro user's identity is shown (profile header,
// friend profile header, leaderboard rows). Compact: just the icon
// + (optional) label.

struct ProBadgeView: View {
    let tier: MonetizationState.ProBadgeTier
    var showLabel: Bool = false
    var size: CGFloat = 14

    var body: some View {
        if tier == .none {
            EmptyView()
        } else {
            HStack(spacing: 4) {
                Image(systemName: tier.iconName)
                    .font(.system(size: size, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: tier.gradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                if showLabel {
                    Text(tier.displayName)
                        .font(.system(size: size - 2, weight: .heavy))
                        .foregroundStyle(
                            LinearGradient(
                                colors: tier.gradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            }
            .accessibilityLabel(tier.displayName)
        }
    }
}

// MARK: - Streak Saver Paywall Modal
//
// Loss-aversion paywall — presented when a free user is about to
// lose a streak (last shield consumed AND missed today). 2× stronger
// than gain-framed paywalls (per behavioral-economics research +
// Strava/Duolingo paywall A/B data).

struct StreakSaverPaywallModal: View {
    let currentStreak: Int
    @Environment(\.dismiss) private var dismiss
    @State private var showFullPaywall = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.5, green: 0.05, blue: 0.05), Color(red: 0.15, green: 0.02, blue: 0.02)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [.red, .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 120, height: 120)
                        .shadow(color: .red.opacity(0.5), radius: 20, x: 0, y: 10)

                    Image(systemName: "flame.fill")
                        .font(.system(size: 60, weight: .bold))
                        .foregroundColor(.white)
                }

                VStack(spacing: 12) {
                    Text("Don't lose your \(currentStreak)-day streak")
                        .font(.system(size: 28, weight: .heavy))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)

                    Text("You used your last free shield. Pro unlocks 3 streak shields per month.")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        HapticManager.tap()
                        showFullPaywall = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "shield.lefthalf.filled")
                            Text("Save My Streak with Pro")
                                .font(.system(size: 17, weight: .bold))
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            Capsule()
                                .fill(LinearGradient(colors: [.yellow, .orange], startPoint: .leading, endPoint: .trailing))
                        )
                    }

                    Button {
                        dismiss()
                    } label: {
                        Text("Let it break")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                            .underline()
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .fullScreenCover(isPresented: $showFullPaywall) {
            PremiumUpgradeView(triggeringFeature: .streakSaver)
        }
    }
}

// MARK: - Achievement Pro Reveal Modal
//
// When a free user hits a milestone achievement (30-workout,
// 100-workout, etc.), grant a 7-day Pro Preview. Day-8 = real
// paywall (composes with the existing Pro-Preview-expiry flow).
// Per-achievement opt-in via `MonetizationState.canRedeemProRevealForAchievement`.

struct AchievementProRevealModal: View {
    let achievementId: String
    let achievementTitle: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.02, blue: 0.20), Color(red: 0.02, green: 0.01, blue: 0.06)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(RadialGradient(
                            colors: [Color.yellow.opacity(0.4), Color.clear],
                            center: .center, startRadius: 20, endRadius: 100))
                        .frame(width: 200, height: 200)

                    Image(systemName: "trophy.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(LinearGradient(
                            colors: [.yellow, .orange],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                }

                VStack(spacing: 12) {
                    Text("\(achievementTitle) unlocked!")
                        .font(.system(size: 26, weight: .heavy))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)

                    Text("You've earned a 7-day Pro Reveal — try Smart Workouts, advanced analytics, and unlimited recipes on us.")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Spacer()

                Button {
                    HapticManager.notification(.success)
                    MonetizationState.shared.redeemProRevealForAchievement(achievementId)
                    dismiss()
                } label: {
                    Text("Activate My 7-Day Pro Reveal")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            Capsule()
                                .fill(LinearGradient(colors: [.yellow, .orange], startPoint: .leading, endPoint: .trailing))
                        )
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
    }
}

// MARK: - Cancellation Survey Sheet
//
// Pre-manage-subscription intercept. When user opens "Manage
// Subscription" (intent signal: trial expiring within 7d AND
// approaching expiration date), surface a 4-reason picker that routes
// to differentiated save offers. Phase 6 will route each reason to
// a real save-offer flow; today the survey writes to dev-session-log
// for analytics and routes everyone to Apple's manage sheet.
//
// Reasons (locked 2026-05-03):
//   1. Too expensive            → 50% off 3 months (issued by Promotional Offer)
//   2. Not using enough         → 30-day pause (Phase 6)
//   3. Doesn't fit my needs     → support@gofit.app contact
//   4. Other                    → free-text → support routing

struct CancellationSurveySheet: View {
    @Environment(\.dismiss) private var dismiss
    let onContinueToManage: () -> Void
    @State private var selectedReason: CancellationReason?
    @State private var freeText: String = ""

    enum CancellationReason: String, CaseIterable, Identifiable {
        case tooExpensive    = "Too expensive"
        case notUsingEnough  = "I'm not using it enough"
        case doesntFit       = "Doesn't fit my needs"
        case other           = "Other"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .tooExpensive:   return "dollarsign.circle.fill"
            case .notUsingEnough: return "clock.badge.questionmark.fill"
            case .doesntFit:      return "exclamationmark.bubble.fill"
            case .other:          return "ellipsis.bubble.fill"
            }
        }

        var saveOffer: String {
            switch self {
            case .tooExpensive:   return "Get 50% off your next 3 months"
            case .notUsingEnough: return "Pause your subscription for 30 days"
            case .doesntFit:      return "Email us — we'll find a fit"
            case .other:          return "We'll review and follow up"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        VStack(spacing: 8) {
                            Image(systemName: "heart.text.square.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(LinearGradient(colors: [.purple, .pink], startPoint: .top, endPoint: .bottom))
                            Text("Wait — before you go")
                                .font(.title2)
                                .fontWeight(.bold)
                            Text("Tell us what we can do better, and we'll do our best to make it right.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 16)
                        }
                        .padding(.top, 24)

                        VStack(spacing: 10) {
                            ForEach(CancellationReason.allCases) { reason in
                                reasonRow(reason)
                            }
                        }
                        .padding(.horizontal, 16)

                        if selectedReason == .other {
                            TextField("What's going on? (optional)", text: $freeText, axis: .vertical)
                                .padding(12)
                                .background(Color.gray.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .lineLimit(3...6)
                                .padding(.horizontal, 16)
                        }

                        if let reason = selectedReason {
                            Button {
                                HapticManager.tap()
                                MonetizationState.shared.markCancellationSurveyShown()
                                AppLogger.info("Cancellation survey: reason=\(reason.rawValue) saveOffer=\(reason.saveOffer)", category: .general)
                                dismiss()
                                // Save-offer routing is Phase 6 — today we
                                // log + continue to Apple's manage sheet.
                                onContinueToManage()
                            } label: {
                                Text(reason.saveOffer)
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(
                                        Capsule()
                                            .fill(LinearGradient(colors: [.purple, .pink], startPoint: .leading, endPoint: .trailing))
                                    )
                            }
                            .padding(.horizontal, 16)
                        }

                        Button {
                            MonetizationState.shared.markCancellationSurveyShown()
                            dismiss()
                            onContinueToManage()
                        } label: {
                            Text("No thanks, take me to cancel")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.secondary)
                                .underline()
                        }
                        .padding(.top, 4)
                        .padding(.bottom, 24)
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func reasonRow(_ reason: CancellationReason) -> some View {
        Button {
            withAnimation(.spring(response: 0.3)) {
                selectedReason = reason
            }
            HapticManager.selectionChanged()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: reason.icon)
                    .font(.title3)
                    .foregroundColor(selectedReason == reason ? .white : .purple)
                    .frame(width: 28)
                Text(reason.rawValue)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(selectedReason == reason ? .white : .primary)
                Spacer()
                Image(systemName: selectedReason == reason ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(selectedReason == reason ? .white : .gray.opacity(0.4))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(selectedReason == reason
                          ? LinearGradient(colors: [.purple, .pink], startPoint: .leading, endPoint: .trailing)
                          : LinearGradient(colors: [Color.gray.opacity(0.1), Color.gray.opacity(0.1)], startPoint: .leading, endPoint: .trailing)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
