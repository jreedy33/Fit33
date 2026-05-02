import SwiftUI

// MARK: - Cardio First-Open Mini-Onboarding (Wave 3b)
//
// 60-second 4-screen flow that surfaces ONCE on the user's first open
// of `CardioLandingView`. Captures four lightweight prefs that the
// rest of the cardio surface reads back via `@AppStorage`:
//
//   1. Distance unit (km / mi)            → `cardio_unit_pref_v1`
//   2. Experience tier (new / weekly /     → `cardio_experience_tier_v1`
//      daily)
//   3. Strava connect ask (now / later)    → no storage; opens
//      `StravaSettingsView` if "now" is tapped, otherwise no-ops
//   4. Preferred default goal type         → `cardio_default_goal_type_v1`
//      (open / time / distance / calories)
//
// The flow is gated by `cardio_intro_seen_v1` — once completed (or
// skipped) the sheet never re-appears. All prefs are optional —
// nothing in the app HARD-DEPENDS on them; they're nudges that bias
// the goal-setup defaults when present.
//
// Why a sheet instead of a navigation push: this is a setup workflow
// that should feel modal (you finish it, then continue) — closer to
// "Quick picker" than "browse a destination". Per PE invariant 5 a
// configuration sheet is correct here.
struct CardioFirstOpenIntroView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    /// Index of the active page in the 4-step flow. Moves
    /// monotonically forward via the primary CTA; the user can also
    /// tap "Skip" (top-trailing) at any step to dismiss + flag the
    /// intro as seen with no prefs persisted.
    @State private var page: Int = 0

    @AppStorage("cardio_unit_pref_v1") private var unitPref: String = "auto"
    @AppStorage("cardio_experience_tier_v1") private var experienceTier: String = ""
    @AppStorage("cardio_default_goal_type_v1") private var defaultGoalType: String = ""
    @AppStorage("cardio_intro_seen_v1") private var introSeen: Bool = false

    @State private var showingStravaConnect = false

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedOrbBackground.workout(colorScheme: colorScheme)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    progressDots
                        .padding(.top, 12)

                    TabView(selection: $page) {
                        unitsPage.tag(0)
                        experiencePage.tag(1)
                        stravaPage.tag(2)
                        goalTypePage.tag(3)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .animation(.easeInOut(duration: 0.25), value: page)

                    primaryCTA
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Skip") { complete(saving: false) }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.secondary)
                }
            }
            .adaptiveToolbarBackground()
            .sheet(isPresented: $showingStravaConnect) {
                NavigationStack { StravaSettingsView() }
            }
        }
    }

    // MARK: - Progress dots

    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<4, id: \.self) { idx in
                Capsule()
                    .fill(idx == page ? Color.green : Color.secondary.opacity(0.3))
                    .frame(width: idx == page ? 24 : 8, height: 6)
                    .animation(.easeInOut(duration: 0.25), value: page)
            }
        }
    }

    // MARK: - Page 1 — Units

    private var unitsPage: some View {
        introPageScaffold(
            icon: "ruler.fill",
            iconAccent: .mint,
            eyebrow: "QUICK SETUP",
            headline: "Pick your units",
            subhead: "Used everywhere we show distance and pace. You can change this later in Settings."
        ) {
            VStack(spacing: 12) {
                introChoice(
                    title: "Kilometers",
                    subtitle: "5 km · 5:00 /km",
                    isSelected: unitPref == "km",
                    accent: .mint
                ) { unitPref = "km"; HapticManager.selectionChanged() }

                introChoice(
                    title: "Miles",
                    subtitle: "3.1 mi · 8:03 /mi",
                    isSelected: unitPref == "mi",
                    accent: .mint
                ) { unitPref = "mi"; HapticManager.selectionChanged() }

                introChoice(
                    title: "Match my phone",
                    subtitle: Locale.current.measurementSystem == .metric
                        ? "Currently kilometers"
                        : "Currently miles",
                    isSelected: unitPref == "auto",
                    accent: .mint
                ) { unitPref = "auto"; HapticManager.selectionChanged() }
            }
        }
    }

    // MARK: - Page 2 — Experience tier

    private var experiencePage: some View {
        introPageScaffold(
            icon: "figure.run",
            iconAccent: .green,
            eyebrow: "ABOUT YOUR CARDIO",
            headline: "How often do you do cardio?",
            subhead: "We'll right-size your default goals so they feel doable, not punishing."
        ) {
            VStack(spacing: 12) {
                introChoice(
                    title: "I'm just starting",
                    subtitle: "0–1 cardio days a week",
                    isSelected: experienceTier == "new",
                    accent: .green
                ) { experienceTier = "new"; HapticManager.selectionChanged() }

                introChoice(
                    title: "A few times a week",
                    subtitle: "2–4 cardio days a week",
                    isSelected: experienceTier == "weekly",
                    accent: .green
                ) { experienceTier = "weekly"; HapticManager.selectionChanged() }

                introChoice(
                    title: "Pretty much daily",
                    subtitle: "5+ days · I'm an enthusiast",
                    isSelected: experienceTier == "daily",
                    accent: .green
                ) { experienceTier = "daily"; HapticManager.selectionChanged() }
            }
        }
    }

    // MARK: - Page 3 — Strava

    private var stravaPage: some View {
        introPageScaffold(
            icon: "link",
            iconAccent: .orange,
            eyebrow: "POWERED BY STRAVA",
            headline: "Already on Strava?",
            subhead: "Connect once and your runs, rides, and walks pull in automatically. Your streak, quests, and league points stay in sync — even when you don't start the workout in Fit33."
        ) {
            VStack(spacing: 12) {
                Button {
                    HapticManager.impact(.medium)
                    showingStravaConnect = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "link")
                            .font(.headline)
                        Text("Connect Strava")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption.weight(.bold))
                            .opacity(0.6)
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(LinearGradient(
                                colors: [.orange, Color(red: 0.95, green: 0.45, blue: 0.10)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                    )
                    .foregroundColor(.white)
                }
                .buttonStyle(UniversalScaleButtonStyle(scale: .standard))

                Text("Skip if you'd rather use Fit33's native walk + run engine.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
        }
    }

    // MARK: - Page 4 — Default goal type

    private var goalTypePage: some View {
        introPageScaffold(
            icon: "target",
            iconAccent: .blue,
            eyebrow: "DEFAULT GOAL",
            headline: "How do you like to track?",
            subhead: "We'll pre-select this when you start a walk or run. You can switch any time."
        ) {
            VStack(spacing: 10) {
                introChoice(
                    title: "Open Goal",
                    subtitle: "No target — just go",
                    isSelected: defaultGoalType == "open",
                    accent: .blue
                ) { defaultGoalType = "open"; HapticManager.selectionChanged() }

                introChoice(
                    title: "Time",
                    subtitle: "30 minutes · 45 minutes · 1 hour",
                    isSelected: defaultGoalType == "time",
                    accent: .blue
                ) { defaultGoalType = "time"; HapticManager.selectionChanged() }

                introChoice(
                    title: "Distance",
                    subtitle: "5 km · 10 km · half · full",
                    isSelected: defaultGoalType == "distance",
                    accent: .blue
                ) { defaultGoalType = "distance"; HapticManager.selectionChanged() }

                introChoice(
                    title: "Calories",
                    subtitle: "300 · 500 · 750 cal",
                    isSelected: defaultGoalType == "calories",
                    accent: .blue
                ) { defaultGoalType = "calories"; HapticManager.selectionChanged() }
            }
        }
    }

    // MARK: - Scaffolds

    @ViewBuilder
    private func introPageScaffold<Content: View>(
        icon: String,
        iconAccent: Color,
        eyebrow: String,
        headline: String,
        subhead: String,
        @ViewBuilder body: () -> Content
    ) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [iconAccent.opacity(0.30), iconAccent.opacity(0.10)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 84, height: 84)
                    Image(systemName: icon)
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundColor(iconAccent)
                }
                .padding(.top, 18)

                VStack(alignment: .leading, spacing: 6) {
                    Text(eyebrow)
                        .font(.caption.weight(.bold))
                        .foregroundColor(.secondary)
                        .tracking(1)
                    Text(headline)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.primary)
                    Text(subhead)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                body()

                Spacer(minLength: 100)
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private func introChoice(
        title: String,
        subtitle: String,
        isSelected: Bool,
        accent: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                ZStack {
                    Circle()
                        .stroke(isSelected ? accent : Color.secondary.opacity(0.4), lineWidth: 2)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle()
                            .fill(accent)
                            .frame(width: 12, height: 12)
                    }
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(isSelected ? accent.opacity(0.55) : Color.clear, lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(UniversalScaleButtonStyle(scale: .standard))
    }

    // MARK: - Primary CTA

    @ViewBuilder
    private var primaryCTA: some View {
        Button(action: advance) {
            Text(page < 3 ? "Continue" : "Start")
                .font(.headline.weight(.semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: ctaColors,
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(14)
        }
        .buttonStyle(UniversalScaleButtonStyle(scale: .standard))
    }

    private var ctaColors: [Color] {
        switch page {
        case 0: return [.mint, .green]
        case 1: return [.green, .mint]
        case 2: return [.orange, Color(red: 0.95, green: 0.45, blue: 0.10)]
        default: return [.blue, .purple]
        }
    }

    // MARK: - Flow control

    private func advance() {
        HapticManager.impact(.medium)
        if page < 3 {
            withAnimation(.easeInOut(duration: 0.25)) { page += 1 }
        } else {
            complete(saving: true)
        }
    }

    /// Marks the intro as seen and dismisses. When `saving` is false
    /// (Skip path) we DO still flip `cardio_intro_seen_v1` so the
    /// sheet doesn't reappear next open — but we leave any partially-
    /// chosen prefs as-is rather than wiping them. (User who picks
    /// units on page 1 then taps Skip keeps their unit pref.)
    private func complete(saving: Bool) {
        introSeen = true
        if saving {
            // No-op — values were written to AppStorage as the user
            // tapped each row. Just dismiss.
        }
        dismiss()
    }
}

#Preview {
    CardioFirstOpenIntroView()
}
