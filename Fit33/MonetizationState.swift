import Foundation
import SwiftUI
import Combine

// MARK: - Monetization State (centralized UserDefaults)
//
// MONETIZATION_AGENT.md cheat-code roadmap (Phase 2/3):
//   - First-Week Pro Preview (Headspace/Calm pattern — every new user
//     gets 7d Pro silently; day-7 modal converts the warm cohort)
//   - Smart-workout weekly cap (1/week for free users)
//   - Recipe daily rotation cap (1/day for free users; 1 forever was
//     too punishing — too many "ghost users" who tried 1 then bounced)
//   - PaywallFirstScreenView auto-presentation throttle
//   - Achievement-unlocked Pro Reveal (per-achievement opt-out)
//   - Earn-Pro friend-invite credits (per-month free Pro grant)
//   - Founding-member badge detection (install ≤ launch grace window)
//
// All values stored in UserDefaults so they survive uninstall/reinstall
// of THIS install (UserDefaults is preserved across launches but reset
// on app removal — fine for these flags). When MON-14 lands and we
// have server-side entitlement, the durable counters (achievement
// reveals, earn-pro grants) will mirror to `subscription_grants`.
//
// IMPORTANT: This service NEVER mutates `PremiumManager.isPremiumUser`
// directly — that's MON-14's job. The `isInProPreview` flag is a
// READ-ONLY signal that downstream gates can compose with the server
// entitlement once the entitlement flip lands.
@MainActor
final class MonetizationState: ObservableObject {
    static let shared = MonetizationState()

    // MARK: - UserDefaults Keys
    private enum Key {
        static let installDate = "monetization.installDate"
        static let proPreviewExpiresAt = "monetization.proPreviewExpiresAt"
        static let proPreviewExpiryModalShown = "monetization.proPreviewExpiryModalShownAt"
        static let hasSeenFirstScreenPaywall = "monetization.hasSeenFirstScreenPaywall"
        static let firstScreenPaywallLastShownAt = "monetization.firstScreenPaywallLastShownAt"
        static let smartWorkoutsGeneratedHistory = "monetization.smartWorkoutsGenerated.iso8601Dates"
        static let recipeViewsTodayCount = "monetization.recipeViewsToday.count"
        static let recipeViewsTodayDate = "monetization.recipeViewsToday.date"
        static let achievementProRevealRedeemed = "monetization.achievementProReveal.redeemedIds"
        static let earnedProGrantsMonths = "monetization.earnedPro.totalMonthsGranted"
        static let cancellationSurveyShown = "monetization.cancellationSurvey.shownAt"
    }

    // MARK: - Constants
    static let proPreviewDurationDays: Int = 7
    static let smartWorkoutFreeWeeklyCap: Int = 1
    static let recipeFreeDailyLimit: Int = 1
    static let firstScreenPaywallWorkoutThreshold: Int = 3
    static let firstScreenPaywallCooldownDays: Int = 14
    static let earnedProGrantPerInvites: Int = 3
    static let foundingMemberCutoffComponents = DateComponents(
        calendar: Calendar(identifier: .gregorian),
        timeZone: TimeZone(identifier: "UTC"),
        year: 2026, month: 7, day: 1
    )
    static let trialCountdownThresholdHours: Double = 48

    // MARK: - Published Reactive Hooks
    @Published private(set) var isInProPreview: Bool = false
    @Published private(set) var proPreviewExpiresAt: Date?

    /// Phase 5 — Sunday Pro Recap.
    /// Flipped to `true` by `requestProRecapPresentation()` when the
    /// user taps the Sunday recap push. ContentView observes this flag
    /// and presents `ProRecapView` as a fullScreenCover. Reset to
    /// `false` by `clearProRecapPresentation()` on cover dismiss.
    @Published var pendingProRecapPresentation: Bool = false

    private let defaults = UserDefaults.standard
    private let calendar = Calendar.current

    // MARK: - Init
    private init() {
        ensureInstallDate()
        ensureFirstWeekProPreview()
        recomputeProPreview()
    }

    // MARK: - Install Date / Founding Member

    /// First-launch date (frozen). Used as the anchor for the 7-day
    /// Pro Preview window and the founding-member badge cutoff.
    var installDate: Date {
        if let stored = defaults.object(forKey: Key.installDate) as? Date {
            return stored
        }
        let now = Date()
        defaults.set(now, forKey: Key.installDate)
        return now
    }

    /// True if this user installed Fit33 BEFORE the founding-member
    /// cutoff (currently 2026-07-01 UTC). Founding members get a
    /// permanent "Founding Member" badge on profile + leaderboard
    /// rows once they ever subscribe (vanity = retention).
    var isFoundingMemberEligible: Bool {
        guard let cutoff = Self.foundingMemberCutoffComponents.date else { return false }
        return installDate < cutoff
    }

    private func ensureInstallDate() {
        _ = installDate  // forces lazy creation
    }

    // MARK: - First-Week Pro Preview
    //
    // Every new user gets 7d Pro silently, starting at install.
    // The day-7 modal ("Your Preview ends today — continue with Pro?")
    // is presented by `Fit33App` when `isInProPreview == false` AND
    // `hasShownProPreviewExpiryModal == false` AND
    // `installDate + 7d < now < installDate + 9d` (2-day grace to
    // catch users who didn't open the app on day 7).

    private func ensureFirstWeekProPreview() {
        guard defaults.object(forKey: Key.proPreviewExpiresAt) == nil else { return }
        guard let expiry = calendar.date(
            byAdding: .day,
            value: Self.proPreviewDurationDays,
            to: installDate
        ) else { return }
        defaults.set(expiry, forKey: Key.proPreviewExpiresAt)
        AppLogger.info("Granted first-week Pro Preview until \(expiry)", category: .general)
    }

    /// Re-evaluates `isInProPreview` against the current clock. Call
    /// after extending the preview (e.g. via watch-an-ad or
    /// achievement Pro reveal) and on app foreground.
    func recomputeProPreview() {
        let expiry = defaults.object(forKey: Key.proPreviewExpiresAt) as? Date
        proPreviewExpiresAt = expiry
        if let expiry {
            isInProPreview = expiry > Date()
        } else {
            isInProPreview = false
        }
    }

    /// Extend (or grant) Pro Preview by N days. Used by:
    ///   - watch-an-ad-to-extend rewarded video (1 day per ad)
    ///   - achievement-unlocked Pro Reveal (7 days per milestone)
    ///   - earn-Pro friend-invite credits (30 days per 3 invites)
    /// New expiry = max(currentExpiry, now) + days.
    func extendProPreview(days: Int) {
        let basis = max(proPreviewExpiresAt ?? .distantPast, Date())
        guard let newExpiry = calendar.date(byAdding: .day, value: days, to: basis) else { return }
        defaults.set(newExpiry, forKey: Key.proPreviewExpiresAt)
        AppLogger.info("Extended Pro Preview by \(days)d to \(newExpiry)", category: .general)
        recomputeProPreview()
    }

    /// Whether to show the "Your Preview ends today" modal right now.
    /// True only during the 48h window after preview expiry, and only
    /// once per device.
    var shouldShowProPreviewExpiryModal: Bool {
        guard let expiry = proPreviewExpiresAt else { return false }
        let now = Date()
        let alreadyShown = defaults.object(forKey: Key.proPreviewExpiryModalShown) != nil
        guard !alreadyShown else { return false }
        let graceEnd = calendar.date(byAdding: .day, value: 2, to: expiry) ?? expiry
        return expiry <= now && now <= graceEnd
    }

    func markProPreviewExpiryModalShown() {
        defaults.set(Date(), forKey: Key.proPreviewExpiryModalShown)
    }

    // MARK: - PaywallFirstScreenView Auto-Presentation
    //
    // First-screen paywall fires after workout #3 (per
    // MONETIZATION_AGENT invariant 7 — no paywall during onboarding
    // or first 3 workouts; this triggers AT the 3-workout boundary,
    // which is "just-past-activation" and the highest-ROI moment for
    // a soft-sell paywall). Throttled by `firstScreenPaywallCooldownDays`
    // so re-installs / aggressive use don't spam the user.

    var hasSeenFirstScreenPaywall: Bool {
        defaults.bool(forKey: Key.hasSeenFirstScreenPaywall)
    }

    func markFirstScreenPaywallSeen() {
        defaults.set(true, forKey: Key.hasSeenFirstScreenPaywall)
        defaults.set(Date(), forKey: Key.firstScreenPaywallLastShownAt)
    }

    func shouldPresentFirstScreenPaywall(completedWorkouts: Int) -> Bool {
        guard completedWorkouts >= Self.firstScreenPaywallWorkoutThreshold else { return false }
        guard !hasSeenFirstScreenPaywall else { return false }
        // Already-Pro users skip
        guard !PremiumManager.shared.isPremiumUser || isInProPreview == false else {
            return false
        }
        return true
    }

    // MARK: - Smart-Workout Weekly Cap
    //
    // Free users get 1 Smart Workout generation per rolling 7-day
    // window. Generation count is the trigger for the contextual
    // paywall (Tier 2 nudge — empty-state hint after the 1st;
    // modal sheet on the 2nd attempt).
    //
    // Stored as an array of ISO8601 timestamps (one per generation
    // event) so we can compute "how many in the last 7 days" and
    // also surface "next free generation available in N days" in
    // the upsell copy.

    private var smartWorkoutTimestamps: [Date] {
        get {
            guard let raw = defaults.array(forKey: Key.smartWorkoutsGeneratedHistory) as? [String] else { return [] }
            let formatter = ISO8601DateFormatter()
            return raw.compactMap { formatter.date(from: $0) }
        }
        set {
            let formatter = ISO8601DateFormatter()
            let strings = newValue.map { formatter.string(from: $0) }
            defaults.set(strings, forKey: Key.smartWorkoutsGeneratedHistory)
        }
    }

    var smartWorkoutsGeneratedThisWeek: Int {
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
        return smartWorkoutTimestamps.filter { $0 >= cutoff }.count
    }

    /// Returns true if the free user can still generate this week,
    /// or if they're Pro / in Pro Preview.
    var canGenerateSmartWorkout: Bool {
        if PremiumManager.shared.isPremiumUser || isInProPreview { return true }
        return smartWorkoutsGeneratedThisWeek < Self.smartWorkoutFreeWeeklyCap
    }

    /// Records a generation event. Call AFTER a successful generation,
    /// not on attempt — failed/discarded generations shouldn't count.
    func recordSmartWorkoutGenerated() {
        guard !PremiumManager.shared.isPremiumUser, !isInProPreview else { return }
        var existing = smartWorkoutTimestamps
        existing.append(Date())
        // Cap history to 30 days so the array doesn't grow unbounded
        let cutoff = Date().addingTimeInterval(-30 * 24 * 3600)
        smartWorkoutTimestamps = existing.filter { $0 >= cutoff }
    }

    /// User-facing copy: "Free Smart Workouts this week: 1/1" or
    /// "Next free Smart Workout: Friday".
    var smartWorkoutCapStatusCopy: String {
        let count = smartWorkoutsGeneratedThisWeek
        let cap = Self.smartWorkoutFreeWeeklyCap
        if count < cap {
            return "Free Smart Workouts this week: \(count)/\(cap)"
        }
        guard let oldest = smartWorkoutTimestamps.sorted().first,
              let nextAvailable = calendar.date(byAdding: .day, value: 7, to: oldest)
        else {
            return "Upgrade for unlimited Smart Workouts"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return "Next free Smart Workout: \(formatter.string(from: nextAvailable))"
    }

    // MARK: - Recipe Daily Limit
    //
    // Free tier: 1 recipe view per day (rotating). Was 1 forever — too
    // punishing; users hit it on Day 1 and never came back to recipes,
    // killing both the feature AND the upsell signal. Daily rotation
    // means free users see (and crave) more recipes over time.

    private var recipeViewsTodayDate: Date? {
        defaults.object(forKey: Key.recipeViewsTodayDate) as? Date
    }

    private var recipeViewsTodayCount: Int {
        defaults.integer(forKey: Key.recipeViewsTodayCount)
    }

    private func resetRecipeViewsIfNewDay() {
        let today = calendar.startOfDay(for: Date())
        if let last = recipeViewsTodayDate {
            if !calendar.isDate(last, inSameDayAs: today) {
                defaults.set(today, forKey: Key.recipeViewsTodayDate)
                defaults.set(0, forKey: Key.recipeViewsTodayCount)
            }
        } else {
            defaults.set(today, forKey: Key.recipeViewsTodayDate)
            defaults.set(0, forKey: Key.recipeViewsTodayCount)
        }
    }

    /// True if the free user can still open another recipe today.
    /// Pro users (and Pro Preview) always return true.
    func canViewAnotherRecipe() -> Bool {
        if PremiumManager.shared.isPremiumUser || isInProPreview { return true }
        resetRecipeViewsIfNewDay()
        return recipeViewsTodayCount < Self.recipeFreeDailyLimit
    }

    /// Records a recipe view. Call when the user opens a recipe detail.
    func recordRecipeView() {
        guard !PremiumManager.shared.isPremiumUser, !isInProPreview else { return }
        resetRecipeViewsIfNewDay()
        defaults.set(recipeViewsTodayCount + 1, forKey: Key.recipeViewsTodayCount)
    }

    // MARK: - Achievement-Unlocked Pro Reveal
    //
    // When a free user hits a milestone achievement (30-workout,
    // 100-workout, etc.), we grant a 7-day Pro Reveal one time per
    // achievement ID. Tracked in UserDefaults as a Set<String> of
    // already-redeemed achievement IDs to prevent re-grants on
    // re-unlock or analytics replay.

    private var achievementProRevealRedeemed: Set<String> {
        get {
            let stored = defaults.array(forKey: Key.achievementProRevealRedeemed) as? [String] ?? []
            return Set(stored)
        }
        set {
            defaults.set(Array(newValue), forKey: Key.achievementProRevealRedeemed)
        }
    }

    func canRedeemProRevealForAchievement(_ achievementId: String) -> Bool {
        // Already-Pro users don't need the reveal (already have access)
        guard !PremiumManager.shared.isPremiumUser || isInProPreview else { return false }
        return !achievementProRevealRedeemed.contains(achievementId)
    }

    /// Grants 7 days of Pro Preview (extended atop existing window if
    /// still active) and records the achievement so it can't be re-redeemed.
    func redeemProRevealForAchievement(_ achievementId: String) {
        guard canRedeemProRevealForAchievement(achievementId) else { return }
        var redeemed = achievementProRevealRedeemed
        redeemed.insert(achievementId)
        achievementProRevealRedeemed = redeemed
        extendProPreview(days: Self.proPreviewDurationDays)
        AppLogger.info("Pro Reveal redeemed for achievement \(achievementId)", category: .general)
    }

    // MARK: - Earned-Pro Friend Invites
    //
    // Invite 3 friends who do their first workout = 1 free month of
    // Pro Preview. Drives growth + plants conversion seeds. Total
    // months granted is tracked locally; the source-of-truth grant
    // (post-MON-14) lives in `subscription_grants` table written by
    // the `award-earned-pro` edge function.

    var earnedProTotalMonthsGranted: Int {
        defaults.integer(forKey: Key.earnedProGrantsMonths)
    }

    /// Records a fresh earn-Pro grant from server confirmation
    /// (`award-earned-pro` edge function). Extends Pro Preview by 30d.
    func recordEarnedProGrant() {
        defaults.set(earnedProTotalMonthsGranted + 1, forKey: Key.earnedProGrantsMonths)
        extendProPreview(days: 30)
    }

    // MARK: - Cancellation Survey

    var cancellationSurveyShownAt: Date? {
        defaults.object(forKey: Key.cancellationSurveyShown) as? Date
    }

    func markCancellationSurveyShown() {
        defaults.set(Date(), forKey: Key.cancellationSurveyShown)
    }

    // MARK: - Sunday Pro Recap (Phase 5)
    //
    // Sunday morning push notification deep-links to `fit33://profile/pro-recap`
    // which routes through `DeepLinkManager` → `MainTabView.handleDeepLinkDestination`
    // → here. ContentView observes `pendingProRecapPresentation` and
    // surfaces `ProRecapView` as a fullScreenCover. Pro vs free is
    // resolved at render time (no separate flag needed) — same view,
    // different content per tier.
    //
    // We deliberately don't auto-present on app launch (it would
    // surprise users); presentation is triggered ONLY by tapping the
    // push (or any in-app surface that wants to open the recap).
    func requestProRecapPresentation() {
        pendingProRecapPresentation = true
    }

    func clearProRecapPresentation() {
        pendingProRecapPresentation = false
    }

    // MARK: - Pro Tier Badge Ladder
    //
    // Vanity tier earned by subscription duration. Drives retention
    // (Strava + Duolingo data shows badge-displaying users churn
    // ~20% less than no-badge users at month 6).
    //
    // Tier thresholds (months of continuous Pro):
    //   - silver:  ≥ 1 month
    //   - gold:    ≥ 6 months
    //   - diamond: ≥ 12 months
    //   - founding: install ≤ 2026-07-01 UTC AND ever subscribed
    //
    // Caller provides `subscriptionStartedAt` (Pro start date from
    // `subscriptions.started_at` once MON-14 ships; until then we
    // use `Transaction.currentEntitlements` first-purchase date).

    enum ProBadgeTier: String, CaseIterable {
        case none, silver, gold, diamond, founding

        var displayName: String {
            switch self {
            case .none:     return ""
            case .silver:   return "Silver Pro"
            case .gold:     return "Gold Pro"
            case .diamond:  return "Diamond Pro"
            case .founding: return "Founding Member"
            }
        }

        var iconName: String {
            switch self {
            case .none:     return ""
            case .silver:   return "rosette"
            case .gold:     return "crown.fill"
            case .diamond:  return "crown.fill"
            case .founding: return "star.circle.fill"
            }
        }

        var gradient: [Color] {
            switch self {
            case .none:     return [.gray, .gray]
            case .silver:   return [Color(white: 0.85), Color(white: 0.65)]
            case .gold:     return [Color(red: 1.0, green: 0.84, blue: 0), Color(red: 1.0, green: 0.6, blue: 0.1)]
            case .diamond:  return [Color(red: 0.7, green: 0.95, blue: 1.0), Color(red: 0.4, green: 0.6, blue: 1.0)]
            case .founding: return [Color(red: 1.0, green: 0.5, blue: 0.9), Color(red: 0.6, green: 0.3, blue: 1.0)]
            }
        }
    }

    /// Computes the user's Pro badge tier. Pass the canonical
    /// subscription start date from server entitlement (post-MON-14)
    /// or `Transaction.currentEntitlements` first purchase date.
    func proBadgeTier(subscriptionStartedAt: Date?) -> ProBadgeTier {
        guard PremiumManager.shared.isPremiumUser else { return .none }
        if isFoundingMemberEligible, subscriptionStartedAt != nil { return .founding }
        guard let started = subscriptionStartedAt else { return .silver }
        let months = calendar.dateComponents([.month], from: started, to: Date()).month ?? 0
        if months >= 12 { return .diamond }
        if months >= 6  { return .gold }
        return .silver
    }
}
