import SwiftUI
import CoreData

// MARK: - ProRecapView (Sunday Pro Recap landing — Phase 5)
//
// MONETIZATION_AGENT.md Phase 5 cheat-code: weekly recap retention loop.
//
// Presented as a fullScreenCover when the user taps the
// `fit33://profile/pro-recap` push (or any in-app surface that opens
// the recap). Pro and free tiers see the SAME view — content branches
// on premium status:
//
//   • PRO members: full breakdown — workouts this week + WoW delta +
//     total strength volume + current streak + a "celebrate the week"
//     hero. Pure retention play (Strong + Hevy + MyFitnessPal pattern).
//
//   • FREE members: teaser variant — workouts this week + a "blurred"
//     stats preview + a "Try Pro free" upsell card. The push that
//     deep-linked them here was the lead generator; this view is the
//     conversion surface.
//
// Data source: pure on-device Core Data (`Workout` fetch). We read the
// last 14 days client-side rather than calling a server endpoint so:
//   1. The recap renders instantly (no network spinner on a push tap).
//   2. The push payload never leaks Pro-tier numbers to a free user
//      (the push body has the teaser copy, the Pro reveal lives here).
//   3. We can fall back gracefully if sync is offline.
//
// Heads-up to future maintainers: this is the LANDING for the recap
// push, not the source-of-truth aggregate. The push backend
// (`sunday-pro-recap` edge function + `get_sunday_recap_candidates`
// RPC) computes its OWN numbers from Supabase for the push body. Tiny
// drift between server and client is expected (e.g. a workout logged
// after the push was queued won't be in the push body but WILL be
// here) — that's fine, the push is a teaser and the view is the truth.
struct ProRecapView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext

    // Last 14 days of completed strength workouts (this week + last
    // week for the WoW delta). 14d hard cap keeps the fetch cheap on
    // large libraries. fetchLimit isn't necessary since the predicate
    // already bounds the set.
    @FetchRequest(
        fetchRequest: {
            let request: NSFetchRequest<Workout> = Workout.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(keyPath: \Workout.date, ascending: false)]
            let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
            request.predicate = NSPredicate(
                format: "isCompleted == true AND date >= %@",
                cutoff as NSDate
            )
            return request
        }(),
        animation: .none
    ) private var recentWorkouts: FetchedResults<Workout>

    @ObservedObject private var premiumManager = PremiumManager.shared
    @ObservedObject private var monetizationState = MonetizationState.shared

    @State private var showUpgradePaywall = false

    // Effective Pro state: server-cached entitlement OR active in-app
    // Pro Preview. We deliberately compose with isInProPreview so the
    // recap shows the FULL view to preview-window users — the recap is
    // one of the cheat-code "what you'd lose" moments that drives
    // preview-to-paid conversion.
    private var isProForView: Bool {
        premiumManager.isPremiumUser || monetizationState.isInProPreview
    }

    var body: some View {
        ZStack {
            backgroundLayer

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    closeButtonRow
                    headerSection
                    headlineMetricCard
                    weekDeltaCard

                    if isProForView {
                        proStatsGrid
                        proCelebrateFooter
                    } else {
                        teaserStatsGrid
                        upgradeCard
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .fullScreenCover(isPresented: $showUpgradePaywall) {
            // Fire the canonical contextual paywall, anchored on the
            // smartWorkouts feature so the messaging matches the recap
            // CTA copy.
            PremiumUpgradeView(triggeringFeature: .smartWorkouts)
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

    // MARK: - Close button

    private var closeButtonRow: some View {
        HStack {
            Spacer()
            Button {
                MonetizationState.shared.clearProRecapPresentation()
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.5))
            }
            .accessibilityLabel("Close weekly recap")
        }
        .padding(.top, 12)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            // Pro tier shows a crown — same gold gradient used on
            // PremiumUpgradeView. Free tier shows a chart icon to
            // anchor the "data is the value" framing.
            Image(systemName: isProForView ? "crown.fill" : "chart.line.uptrend.xyaxis")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: isProForView
                            ? [Color(red: 1.0, green: 0.84, blue: 0.0),
                               Color(red: 1.0, green: 0.65, blue: 0.0)]
                            : [.cyan, .blue],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            Text("Your Week, Recapped")
                .font(.ds_displayLarge)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

            Text(weekRangeText)
                .font(.ds_bodyMedium)
                .foregroundColor(.white.opacity(0.7))
        }
    }

    // MARK: - Headline Metric (this-week workout count)

    private var headlineMetricCard: some View {
        VStack(spacing: 8) {
            Text("\(workoutsThisWeek)")
                .font(.system(size: 80, weight: .black, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.cyan, .blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .accessibilityLabel("\(workoutsThisWeek) workouts this week")

            Text(workoutsThisWeek == 1 ? "Workout this week" : "Workouts this week")
                .font(.ds_labelLarge)
                .foregroundColor(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(.white.opacity(0.10), lineWidth: 1)
                )
        )
    }

    // MARK: - Week-over-Week Delta Card

    private var weekDeltaCard: some View {
        let delta = workoutsThisWeek - workoutsLastWeek
        let symbol: String
        let symbolColor: Color
        let label: String

        if delta > 0 {
            symbol = "arrow.up.right.circle.fill"
            symbolColor = .green
            label = "+\(delta) vs last week — keep stacking."
        } else if delta < 0 {
            symbol = "arrow.down.right.circle.fill"
            symbolColor = .orange
            label = "\(delta) vs last week — reset Monday."
        } else if workoutsThisWeek == 0 && workoutsLastWeek == 0 {
            symbol = "calendar.badge.exclamationmark"
            symbolColor = .gray
            label = "Quiet two weeks. Pick a day this week and book it."
        } else {
            symbol = "equal.circle.fill"
            symbolColor = .blue
            label = "Same as last week — consistent is good."
        }

        return HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundColor(symbolColor)
            Text(label)
                .font(.ds_bodyMedium)
                .foregroundColor(.white.opacity(0.85))
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white.opacity(0.05))
        )
    }

    // MARK: - Pro Stats Grid (full breakdown)

    private var proStatsGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "crown.fill")
                    .font(.ds_labelMedium)
                    .foregroundColor(Color(red: 1.0, green: 0.78, blue: 0.0))
                Text("Pro Breakdown")
                    .font(.ds_labelLarge)
                    .foregroundColor(.white)
                Spacer()
            }

            HStack(spacing: 12) {
                statTile(
                    title: "Total Sets",
                    value: "\(totalSetsThisWeek)",
                    icon: "square.stack.3d.up.fill",
                    color: .cyan
                )
                statTile(
                    title: "Avg Duration",
                    value: avgDurationText,
                    icon: "clock.fill",
                    color: .blue
                )
            }

            HStack(spacing: 12) {
                statTile(
                    title: "Streak",
                    value: "\(currentStreak)",
                    icon: "flame.fill",
                    color: .orange
                )
                statTile(
                    title: "Last 14 Days",
                    value: "\(recentWorkouts.count)",
                    icon: "calendar.circle.fill",
                    color: .purple
                )
            }
        }
    }

    private func statTile(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(color)
                Text(title)
                    .font(.ds_labelSmall)
                    .foregroundColor(.white.opacity(0.6))
            }
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(0.05))
        )
    }

    // MARK: - Pro Celebrate Footer

    private var proCelebrateFooter: some View {
        VStack(spacing: 10) {
            Text(celebrateCopy)
                .font(.ds_bodyMedium)
                .foregroundColor(.white.opacity(0.85))
                .multilineTextAlignment(.center)

            Text("New recap every Sunday at 10am.")
                .font(.ds_labelSmall)
                .foregroundColor(.white.opacity(0.4))
        }
        .padding(.top, 8)
    }

    private var celebrateCopy: String {
        if workoutsThisWeek >= 5 { return "5+ in a week. That's the top 5% of users — keep ripping." }
        if workoutsThisWeek >= 3 { return "Three or more is the consistency zone. Lock it in." }
        if workoutsThisWeek == 0 { return "Your Pro dashboard has trends + smart suggestions for Monday." }
        return "Building the habit. Pick one day to add this week."
    }

    // MARK: - Teaser Stats Grid (free tier)

    private var teaserStatsGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "lock.fill")
                    .font(.ds_labelMedium)
                    .foregroundColor(.white.opacity(0.5))
                Text("Pro Members Also See")
                    .font(.ds_labelLarge)
                    .foregroundColor(.white)
                Spacer()
            }

            // Real labels, redacted values. The user knows the data
            // exists — that's the whole point of the lock framing.
            HStack(spacing: 12) {
                lockedStatTile(title: "Total Sets", icon: "square.stack.3d.up.fill", color: .cyan)
                lockedStatTile(title: "Avg Duration", icon: "clock.fill", color: .blue)
            }
            HStack(spacing: 12) {
                lockedStatTile(title: "Volume Trend", icon: "chart.bar.fill", color: .orange)
                lockedStatTile(title: "PR Breakdown", icon: "trophy.fill", color: .purple)
            }
        }
    }

    private func lockedStatTile(title: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(color.opacity(0.6))
                Text(title)
                    .font(.ds_labelSmall)
                    .foregroundColor(.white.opacity(0.6))
            }
            HStack(spacing: 4) {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.4))
                Text("• • •")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(0.04))
        )
    }

    // MARK: - Upgrade Card (free tier CTA)

    private var upgradeCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "crown.fill")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(red: 1.0, green: 0.84, blue: 0.0),
                                 Color(red: 1.0, green: 0.65, blue: 0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            Text("See your full week with Pro")
                .font(.ds_heading2)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

            Text("Unlock weekly volume trends, PR breakdown, smart workout suggestions, and ad-free training. 7-day free trial — cancel anytime.")
                .font(.ds_bodyMedium)
                .foregroundColor(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                showUpgradePaywall = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                    Text("Try Pro Free")
                }
                .font(.ds_labelLarge)
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    Capsule().fill(
                        LinearGradient(
                            colors: [Color(red: 1.0, green: 0.92, blue: 0.0),
                                     Color(red: 1.0, green: 0.75, blue: 0.0)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                )
            }
            .accessibilityLabel("Try Pro free for 7 days")
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.10, green: 0.07, blue: 0.20),
                            Color(red: 0.06, green: 0.04, blue: 0.12)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [Color(red: 1.0, green: 0.84, blue: 0.0).opacity(0.6),
                                         Color(red: 1.0, green: 0.55, blue: 0.0).opacity(0.3)],
                                startPoint: .top, endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                )
        )
    }

    // MARK: - Derived Stats (client-side from Core Data fetch)

    private var weekStartDate: Date {
        // "This week" = last 7 calendar days from now (rolling window).
        // Simpler than calendar-week-Monday math and matches the push
        // copy ("your week").
        Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    }

    private var lastWeekStartDate: Date {
        Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
    }

    private var workoutsThisWeek: Int {
        recentWorkouts.filter { ($0.date ?? .distantPast) >= weekStartDate }.count
    }

    private var workoutsLastWeek: Int {
        recentWorkouts.filter {
            let d = $0.date ?? .distantPast
            return d >= lastWeekStartDate && d < weekStartDate
        }.count
    }

    private var totalSetsThisWeek: Int {
        recentWorkouts
            .filter { ($0.date ?? .distantPast) >= weekStartDate }
            .reduce(0) { sum, workout in
                let exercises = (workout.exercises as? Set<WorkoutExercise>) ?? []
                let exerciseSetCount = exercises.reduce(0) { partial, ex in
                    partial + ((ex.sets as? Set<WorkoutSet>)?.count ?? 0)
                }
                return sum + exerciseSetCount
            }
    }

    private var avgDurationText: String {
        let thisWeek = recentWorkouts.filter { ($0.date ?? .distantPast) >= weekStartDate }
        guard !thisWeek.isEmpty else { return "—" }
        let totalSeconds = thisWeek.reduce(0) { $0 + Int($1.duration) }
        let avgMinutes = (totalSeconds / thisWeek.count) / 60
        return "\(avgMinutes)m"
    }

    private var currentStreak: Int {
        Int(UserManager.shared.currentUser?.currentStreak ?? 0)
    }

    private var weekRangeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let start = formatter.string(from: weekStartDate)
        let end = formatter.string(from: Date())
        return "\(start) – \(end)"
    }
}
