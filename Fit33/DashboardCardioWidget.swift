import SwiftUI

// MARK: - Dashboard Cardio Widget (Wave 3c + 6b)
//
// A compact dashboard surface that combines TWO cheat codes into one
// isolated card:
//
//   • Wave 6b — surfaces the user's cardio streak (separate from the
//     strength streak) on the Dashboard, with a flame badge and copy
//     that responds to whether the streak is "alive today" vs "at
//     risk" (no cardio logged yet).
//   • Wave 3c — when no cardio has been logged today, the card
//     becomes a one-tap "Just one block" 5-minute walk entry. Tap →
//     opens `CardioGoalSetupView(activityType: .walk)` as a sheet.
//
// Visibility rules:
//   • streak ≥ 1 AND cardio today      → celebratory streak chip
//   • streak ≥ 1 AND no cardio today   → "Keep streak alive" + walk CTA
//   • streak == 0 AND no cardio today  → "Just one block" walk CTA
//   • streak == 0 AND cardio today     → hidden entirely (don't nag —
//     they already moved today)
//
// Per the SwiftUI rules ("widget isolation"), this is a standalone
// View so its periodic re-loads (streak fetch on appear) don't reach
// `DashboardView`'s body and re-trigger the workout-carousel rebuild.
//
// Routing:
//   • Tapping the body presents `CardioGoalSetupView(activityType: .walk)`
//     as a `.sheet` directly from the Dashboard. The sheet's existing
//     Smart Goal Auto-Suggest (Wave 4e) seeds defaults from the user's
//     last-7-days median walk session; if they're new, the static
//     activity defaults stand. Either way, the user is two taps from
//     active workout.
//   • Currently this does NOT cross-tab navigate to `CardioLanding` —
//     keeping this card local-tab-only is the simplest correct
//     behavior. A future "View all cardio" CTA could deep-link via
//     `WorkoutManager.shouldNavigateToCardio = true` (not yet defined).
struct DashboardCardioWidget: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var userManager: UserManager

    @State private var streakDays: Int = 0
    @State private var hasCardioToday: Bool = false
    @State private var isLoaded: Bool = false
    @State private var showingWalkSetup: Bool = false

    var body: some View {
        if isLoaded, shouldShow {
            content
                .sheet(isPresented: $showingWalkSetup) {
                    // 2026-05-02: `CardioGoalSetupView` no longer wraps
                    // its own NavigationStack (it became a pushed page
                    // off `CardioLandingView`). When presented as a
                    // sheet from outside that nav stack — e.g. this
                    // dashboard widget — we must provide one here so
                    // the title + navigation bar still render.
                    NavigationStack {
                        // 2026-05-02 (per-user request, Wave 4d.3):
                        // when `CardioGoalSetupView` is reached via
                        // the canonical Workout-tab push, the
                        // circular GO! button is mounted on the
                        // global `GoButtonState.shared` overlay so it
                        // floats over the system tab bar. That
                        // overlay lives on `MainTabView` UNDER this
                        // sheet — invisible from inside the sheet.
                        // We pass `presentedAsSheet: true` so the
                        // view falls back to its in-screen
                        // tab-bar-style `bottomGoBar` instead.
                        CardioGoalSetupView(
                            activityType: .walk,
                            presentedAsSheet: true
                        )
                            .environmentObject(userManager)
                    }
                }
        } else {
            // Empty placeholder while loading — avoids layout flash.
            // Marked `.task` so the load fires once on first appearance
            // and is cancelled if the dashboard scrolls away before
            // completion (cheap network call but still — be polite).
            Color.clear
                .frame(height: 0)
                .task { await loadCardioState() }
        }
    }

    // MARK: - Visibility

    /// Hide entirely on the streak == 0 + cardio today case (no value
    /// to show; it would just be visual noise).
    private var shouldShow: Bool {
        streakDays > 0 || !hasCardioToday
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionHeader
            cardBody
        }
    }

    private var sectionHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "figure.run")
                .foregroundStyle(
                    LinearGradient(colors: [.green, .mint], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .font(.title3)
            Text("Cardio")
                .font(.title3)
                .fontWeight(.bold)
            Spacer()
            if hasCardioToday {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.green)
            }
        }
    }

    @ViewBuilder
    private var cardBody: some View {
        Button(action: { handleTap() }) {
            HStack(spacing: 14) {
                // Leading icon
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: leadingIconGradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 52, height: 52)
                    Image(systemName: leadingIcon)
                        .font(.title2)
                        .foregroundColor(.white)
                }

                // Copy
                VStack(alignment: .leading, spacing: 3) {
                    Text(headline)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    Text(subhead)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                // Trailing affordance
                Image(systemName: trailingIcon)
                    .font(.title3)
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.lg)
                            .stroke(borderAccent.opacity(0.30), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(UniversalScaleButtonStyle(scale: .standard))
    }

    // MARK: - State-driven copy + visuals

    /// Three states:
    ///   - `.streakAliveToday`  — streak alive AND cardio today
    ///   - `.streakAtRisk`      — streak alive AND no cardio today
    ///   - `.justOneBlock`      — no streak AND no cardio today
    private enum WidgetState { case streakAliveToday, streakAtRisk, justOneBlock }

    private var widgetState: WidgetState {
        if streakDays > 0 && hasCardioToday { return .streakAliveToday }
        if streakDays > 0 { return .streakAtRisk }
        return .justOneBlock
    }

    private var leadingIcon: String {
        switch widgetState {
        case .streakAliveToday: return "flame.fill"
        case .streakAtRisk:     return "flame.fill"
        case .justOneBlock:     return "figure.walk.motion"
        }
    }

    private var leadingIconGradient: [Color] {
        switch widgetState {
        case .streakAliveToday: return [.orange, .red]
        case .streakAtRisk:     return [.orange, Color(red: 0.95, green: 0.45, blue: 0.10)]
        case .justOneBlock:     return [.mint, .green]
        }
    }

    private var borderAccent: Color {
        switch widgetState {
        case .streakAliveToday: return .orange
        case .streakAtRisk:     return .orange
        case .justOneBlock:     return .mint
        }
    }

    private var headline: String {
        switch widgetState {
        case .streakAliveToday: return "\(streakDays)-day cardio streak"
        case .streakAtRisk:     return "Keep your \(streakDays)-day streak alive"
        case .justOneBlock:     return "Just one block"
        }
    }

    private var subhead: String {
        switch widgetState {
        case .streakAliveToday: return "Today's cardio is logged. Nice work."
        case .streakAtRisk:     return "5-minute walk · saves the streak"
        case .justOneBlock:     return "Start a 5-minute walk · counts the same as 5K"
        }
    }

    private var trailingIcon: String {
        switch widgetState {
        case .streakAliveToday: return "checkmark.seal.fill"
        case .streakAtRisk:     return "arrow.up.right.circle.fill"
        case .justOneBlock:     return "arrow.up.right.circle.fill"
        }
    }

    // MARK: - Actions

    private func handleTap() {
        switch widgetState {
        case .streakAliveToday:
            // Already done today — no-op. The chevron is celebratory,
            // not a prompt. Keep this gesture inert so the user
            // doesn't trip into a redundant goal-setup sheet.
            HapticManager.impact(.light)
        case .streakAtRisk, .justOneBlock:
            HapticManager.impact(.medium)
            showingWalkSetup = true
        }
    }

    // MARK: - Load

    /// Load streak + today's cardio count from Supabase. Both are cheap
    /// existing endpoints (already used by `CardioLandingView`). Errors
    /// are swallowed silently — widget stays hidden if the load fails.
    @MainActor
    private func loadCardioState() async {
        async let streakTask = SupabaseManager.shared.fetchCardioStreak()
        async let statsTask: CardioStatsDTO? = {
            do {
                let cal = Calendar.current
                let start = cal.startOfDay(for: Date())
                return try await SupabaseManager.shared.fetchCardioStats(
                    startDate: start, endDate: Date()
                )
            } catch {
                return nil
            }
        }()

        let streak = await streakTask
        let stats = await statsTask

        streakDays = streak?.currentStreak ?? 0
        hasCardioToday = (stats?.totalWorkouts ?? 0) > 0
        isLoaded = true
    }
}
