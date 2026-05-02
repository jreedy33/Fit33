import SwiftUI
import CoreData

// MARK: - Cardio Activity Type
enum CardioActivityType: String, CaseIterable, Identifiable {
    case outdoorRun = "Outdoor Run"
    case treadmill = "Treadmill"
    case walk = "Walk"
    case indoorCycle = "Indoor Cycle"
    case outdoorCycle = "Outdoor Cycle"
    case rowing = "Rowing"
    case elliptical = "Elliptical"
    case stairClimber = "Stair Climber"
    case hiit = "HIIT"
    case swimming = "Swimming"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .outdoorRun: return "figure.run"
        case .treadmill: return "figure.run.treadmill"
        case .walk: return "figure.walk"
        case .indoorCycle: return "figure.indoor.cycle"
        case .outdoorCycle: return "figure.outdoor.cycle"
        case .rowing: return "figure.rower"
        case .elliptical: return "figure.elliptical"
        case .stairClimber: return "figure.stair.stepper"
        case .hiit: return "bolt.heart.fill"
        case .swimming: return "figure.pool.swim"
        }
    }
    
    var color: Color {
        switch self {
        // 2026-05-02 (per-user request): Outdoor Run is now BLUE,
        // Walk is now TEAL (was green / mint). The pair was chosen
        // so the two GPS-native activities sit at the cool end of
        // the spectrum, leaving warm tones (orange / yellow / red /
        // pink) for indoor / HIIT / niche activities. Cycling pulls
        // toward the run-blue family (cyan) so the related-activity
        // grouping reads at a glance.
        case .outdoorRun: return .blue
        case .treadmill: return .orange
        case .walk: return .teal
        case .indoorCycle: return .yellow
        case .outdoorCycle: return .cyan
        case .rowing: return Color(red: 0.20, green: 0.45, blue: 0.85)
        case .elliptical: return .purple
        case .stairClimber: return .red
        case .hiit: return .pink
        case .swimming: return .mint
        }
    }
    
    var description: String {
        switch self {
        case .outdoorRun: return "GPS • Pace • Route"
        case .treadmill: return "Speed • Incline • Distance"
        case .walk: return "Steps • Distance • Pace"
        case .indoorCycle: return "Cadence • Power • Distance"
        case .outdoorCycle: return "GPS • Speed • Elevation"
        case .rowing: return "Strokes • Power • Split"
        case .elliptical: return "Strides • Resistance • Calories"
        case .stairClimber: return "Floors • Steps • Calories"
        case .hiit: return "Intervals • Heart Rate • Burn"
        case .swimming: return "Laps • Stroke • Pace"
        }
    }
    
    var requiresGPS: Bool {
        switch self {
        case .outdoorRun, .walk, .outdoorCycle: return true
        default: return false
        }
    }
    
    var supportsBluetooth: Bool {
        switch self {
        case .treadmill, .indoorCycle, .rowing, .elliptical, .stairClimber: return true
        default: return false
        }
    }
    
    // Default goal values based on activity
    var defaultDuration: Int { // minutes
        switch self {
        case .hiit: return 20
        case .walk: return 30
        case .outdoorRun, .treadmill: return 30
        case .indoorCycle, .outdoorCycle: return 45
        case .rowing: return 20
        case .elliptical, .stairClimber: return 30
        case .swimming: return 30
        }
    }
    
    var defaultCalories: Int {
        switch self {
        case .hiit: return 300
        case .walk: return 150
        case .outdoorRun, .treadmill: return 350
        case .indoorCycle, .outdoorCycle: return 400
        case .rowing: return 250
        case .elliptical, .stairClimber: return 300
        case .swimming: return 350
        }
    }
    
    var defaultDistance: Double { // km
        switch self {
        case .walk: return 3.0
        case .outdoorRun, .treadmill: return 5.0
        case .outdoorCycle: return 15.0
        case .indoorCycle: return 10.0
        case .rowing: return 2.0
        default: return 0
        }
    }
}

// MARK: - Cardio Landing View
//
// Cardio Redesign Phase 1 — Wave 3.
// Top-half: Walk + Run hero tiles (the only two activities the app
// natively tracks with GPS) + a chip row of 1-tap goal presets.
// Bottom-half: "Powered by Strava" lockup — recent activities row +
// weekly delta when connected; a feature-rich Connect CTA + native
// fallback stats when not. Indoor equipment + "Browse all cardio"
// link sit below the lockup, demoted out of the way.
//
// The exhaustive search + filter + exercise list was moved to a
// sheet-presented `BrowseAllCardioView`, accessible via the link at
// the bottom. This is the single biggest decluttering move in the
// redesign — the legacy landing was 3 stacked grids of activities,
// now it's a hero + a viral surface.
struct CardioLandingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject var userManager: UserManager
    @ObservedObject private var workoutManager = WorkoutManager.shared
    @ObservedObject private var stravaService = StravaService.shared

    /// 2026-05-02 (per-user request): every tap-driven option off the
    /// cardio landing pushes its own page instead of presenting as a
    /// pop-up sheet. Single-source-of-truth state for "which destination
    /// is currently pushed". Setting this to `nil` pops back to the
    /// landing surface.
    @State private var pushedDestination: CardioLandingDestination?
    // 2026-05-02 (per-user request): the "1-day cardio streak" banner
    // and "Just one block" off-day-cure tile were removed from this
    // surface. The `loadCardioStreak()` helper + its `cardioStreakDays`
    // / `cardioStreakLoaded` / `hasNoCardioToday` state vars were the
    // only consumers, so they were stripped too. Streak is still
    // surfaced on the profile (`ProfileView` keeps its own copy of the
    // same fetch).
    /// Cardio Redesign Phase 1 — Wave 3b. First-open mini-onboarding
    /// (units / experience / Strava ask / default goal). Driven by
    /// `cardio_intro_seen_v1` UserDefaults flag — sheet flips on once
    /// per device install, dismisses + sets the flag on completion.
    @AppStorage("cardio_intro_seen_v1") private var cardioIntroSeen: Bool = false
    @State private var showingFirstOpenIntro: Bool = false

    // Cardio Redesign Phase 1 — Wave 3 (revised 2026-05-02 per user
    // request).
    //
    // PUSHED detail view, NOT sheet. Hosted from `WorkoutTabView`
    // navigation stack via `navigationPath.append("CardioLanding")`,
    // resolved by `navigationDestinationView(for:)`. Per PE invariant
    // 6 we MUST NOT wrap our own `NavigationStack` here — the parent
    // stack owns navigation, the system back chevron handles dismiss,
    // and `.navigationDestination(for: CardioLandingDestination.self)`
    // (registered below) propagates up the parent stack so
    // `ConnectStravaCard`'s value-based NavigationLink keeps working.
    var body: some View {
        ZStack {
            backgroundGradient

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 24) {
                    // ── TOP HALF — native walk + run hero tiles + presets ──
                    // 2026-05-02 (per-user request): the
                    // `cardioStreakBanner` ("1-day cardio streak") and
                    // `justOneBlockTile` ("Just one block · 5-min walk")
                    // were removed from this stack to declutter the
                    // surface. Header → hero tiles → quick-start grid
                    // is now the entire above-the-fold story.
                    headerSection
                    walkRunHeroSection
                    presetChipsSection

                    // ── DIVIDER between native top-half and recent/Strava bottom-half ──
                    sectionDivider

                    // ── BOTTOM HALF — unified recent activity log ──
                    // 2026-05-02 (per-user request): the recent log
                    // pulled out of the Strava lockup. Shows ALL cardio
                    // sources (Strava + Fit33 native + WHOOP / Apple
                    // Watch / etc.) with source-colored accents
                    // (orange / blue / white) — NO Strava-connected
                    // gate. See `CardioRecentLogSection` for the source
                    // → accent map.
                    CardioRecentLogSection()

                    // ── Powered by Strava lockup (brand mark + connect CTA) ──
                    stravaLockupSection

                    // ── Indoor equipment + browse-all link (demoted) ──
                    equipmentRowSection
                    browseAllCardioLink

                    Spacer(minLength: 80)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
        }
        .navigationTitle("Cardio")
        .navigationBarTitleDisplayMode(.inline)
        .adaptiveToolbarBackground()
        // 2026-05-02 (per-user request): single navigationDestination
        // registration for ALL tap-driven options off the cardio
        // landing. Replaces three separate `.sheet` modifiers (goal
        // setup, browse all, first-open intro). First-open intro is
        // the only one still presented modally — see `.fullScreenCover`
        // below — because it auto-presents on appear and "push on
        // appear" has weird animation semantics.
        .navigationDestination(item: $pushedDestination) { dest in
            switch dest {
            case .stravaIntegration:
                StravaSettingsView()
            case .goalSetup(let activity):
                CardioGoalSetupView(activityType: activity)
                    .environmentObject(userManager)
            case .browseAll:
                BrowseAllCardioView()
            }
        }
        // 2026-05-02 — unified recent log uses
        // `RecentCardioWorkoutCard`, which fires a value-based
        // NavigationLink with `cardioWorkout`. Register the destination
        // here (NOT inside `CardioRecentLogSection`) so the modifier
        // attaches to the cardio landing root and the push survives any
        // future restructuring of the section list.
        .navigationDestination(for: CardioWorkoutDTO.self) { workout in
            CardioWorkoutDetailView(cardioWorkout: workout)
        }
        .fullScreenCover(isPresented: $showingFirstOpenIntro) {
            // Cardio Redesign Phase 1 — Wave 3b (revised 2026-05-02).
            // First-open mini-onboarding now uses .fullScreenCover (not
            // .sheet) so it reads as its own SCREEN, not a pop-up card,
            // matching the rest of the cardio surface. The orb
            // background already lives inside the intro view itself.
            CardioFirstOpenIntroView()
        }
        .onChange(of: workoutManager.shouldDismissCardioFlow) { _, shouldDismiss in
            if shouldDismiss {
                // Pop the goal-setup / browse-all push if it's open,
                // then dismiss the cardio landing itself.
                pushedDestination = nil
                dismiss()
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(0.5))
                    guard !Task.isCancelled else { return }
                    WorkoutManager.shared.shouldDismissCardioFlow = false
                }
            }
        }
        .task { await triggerHKBackfillIfNeeded() }
        .onAppear { presentFirstOpenIntroIfNeeded() }
    }

    // MARK: - Push helpers (2026-05-02)
    //
    // Centralizes all "tap → push goal setup for this activity" callers
    // (Walk hero, Run hero, 5 preset chips, equipment cards, just-one-
    // block tile) so the haptic + navigation pattern stays consistent.
    // Replaces the legacy
    // `selectedActivity = X; showingGoalSetup = true` two-line dance.
    private func pushGoalSetup(for activity: CardioActivityType, haptic: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        HapticManager.impact(haptic)
        pushedDestination = .goalSetup(activity: activity)
    }

    // MARK: - First-open intro gate (Wave 3b)
    //
    // Surface the 4-step mini-onboarding if `cardio_intro_seen_v1`
    // hasn't been flipped yet. We use `.onAppear` (not `.task`) so the
    // flag check runs synchronously before the view stabilizes, which
    // prevents a flash of the landing UI before the sheet rises.
    //
    // The intro flips the flag on its own (via `@AppStorage`) when
    // the user taps Continue past the last step OR taps Skip — so this
    // is a one-shot gate. We bail early if HK backfill is already
    // running this session to avoid double-scrim.
    private func presentFirstOpenIntroIfNeeded() {
        guard !cardioIntroSeen else { return }
        // Tiny delay so the landing renders first — the sheet rising
        // over an empty/black surface looks broken; rising over the
        // landing reads as "we set up your space, now configure it".
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, !cardioIntroSeen else { return }
            showingFirstOpenIntro = true
        }
    }

    // MARK: - HealthKit 30-day backfill (Wave 2b)
    //
    // Cheat code — on the user's FIRST cardio-landing open after this
    // build ships, we kick off `HealthDataService.syncAllHealthData(force:)`
    // which pulls last-30d HKWorkout rows and upserts them into
    // `cardio_workouts` (dedup via HK uuid → `external_id`). This means
    // a user who joins with months of Apple-Watch / Strava-via-HK
    // history sees a populated cardio surface immediately rather than
    // an empty feed.
    //
    // Gated by a UserDefaults one-shot flag so the backfill never re-runs
    // (subsequent opens rely on the existing background HK observer).
    // We also flip the flag when HK isn't authorized so this isn't a
    // forever-task on every cardio open for users who denied HK.
    @MainActor
    private func triggerHKBackfillIfNeeded() async {
        let flagKey = "cardio_first_open_hk_backfill_done_v1"
        guard !UserDefaults.standard.bool(forKey: flagKey) else { return }
        guard HealthKitService.shared.isAuthorized else {
            UserDefaults.standard.set(true, forKey: flagKey)
            return
        }
        AppLogger.info(
            "[CARDIO] First-cardio-open HK 30d backfill starting",
            category: .health
        )
        await HealthDataService.shared.syncAllHealthData(force: true)
        UserDefaults.standard.set(true, forKey: flagKey)
        AppLogger.info(
            "[CARDIO] First-cardio-open HK 30d backfill complete",
            category: .health
        )
    }

    // MARK: - Background
    private var backgroundGradient: some View {
        AnimatedOrbBackground.workout(colorScheme: colorScheme)
            .ignoresSafeArea()
    }

    // MARK: - Header (compact)
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Cardio")
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.green, .mint],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("Walk, run, and let Strava power the rest.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Walk + Run Hero Tiles (TOP HALF)
    private var walkRunHeroSection: some View {
        HStack(spacing: 12) {
            WalkRunHeroCard(
                activity: .walk,
                title: "Walk",
                subtitle: "GPS · Pace · Calories",
                accent: .teal
            ) {
                pushGoalSetup(for: .walk)
            }

            WalkRunHeroCard(
                activity: .outdoorRun,
                title: "Run",
                subtitle: "GPS · Pace · Splits",
                accent: .blue
            ) {
                pushGoalSetup(for: .outdoorRun)
            }
        }
    }

    // MARK: - Preset Chips (1-tap goal presets)
    //
    // 2026-05-02 (per-user request): the quick-start row is now a
    // 2-column LazyVGrid of 4 floating tiles instead of a horizontally-
    // scrolling chip strip. Tiles are full-width within their column,
    // tap-target-sized (≈44pt tall), and sit directly on the orb
    // background (no surrounding card container) per the "floating"
    // spec. The chip styling itself ("Walk = teal, Run = blue,
    // capsule + ultraThinMaterial + accent stroke") matches the
    // GoalTypeButton + GoalQuickChip pickers downstream so the user
    // feels visual continuity tile-tap → goal-setup. The 4 tiles are
    // chosen as the most-used pair per activity (Walk: 30 min + Open;
    // Run: 5K + 30 min) — the legacy "Open Walk" chip was dropped
    // because it duplicated "30 min Walk"'s entry path and the grid
    // is fixed-cell, so we kept the higher-utility option.
    private var presetChipsSection: some View {
        let columns = [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ]
        return VStack(alignment: .leading, spacing: 12) {
            Text("QUICK START")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .tracking(1)

            LazyVGrid(columns: columns, spacing: 10) {
                CardioPresetChip(label: "30 min Walk", icon: "clock.fill", accent: .teal, fillsWidth: true) {
                    pushGoalSetup(for: .walk, haptic: .light)
                }
                CardioPresetChip(label: "Open Run", icon: "infinity", accent: .blue, fillsWidth: true) {
                    pushGoalSetup(for: .outdoorRun, haptic: .light)
                }
                CardioPresetChip(label: "5K Run", icon: "figure.run", accent: .blue, fillsWidth: true) {
                    pushGoalSetup(for: .outdoorRun, haptic: .light)
                }
                CardioPresetChip(label: "30 min Run", icon: "clock.fill", accent: .blue, fillsWidth: true) {
                    pushGoalSetup(for: .outdoorRun, haptic: .light)
                }
            }
        }
    }

    // MARK: - Section Divider (between native + Strava halves)
    private var sectionDivider: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.clear, .secondary.opacity(0.15), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 1)
            .padding(.vertical, 4)
    }

    // MARK: - Powered by Strava (BOTTOM HALF)
    //
    // 2026-05-02 (per-user request): dropped the "Connected" pill +
    // sync-time chip. The Powered-by-Strava lockup is the brand mark
    // and nothing else; connection state is implicit (recent activities
    // = connected; ConnectStravaCard = not connected).
    private var stravaLockupSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image("PoweredByStrava")
                    .resizable()
                    .renderingMode(.original)
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 17)
                    .accessibilityLabel("Powered by Strava")
                Spacer()
            }

            if stravaService.isConnected {
                CardioStravaSection()
            } else {
                ConnectStravaCard()
            }
        }
    }

    // MARK: - Equipment Row (compact, demoted)
    private var equipmentRowSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("INDOOR EQUIPMENT")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                    .tracking(1)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.caption)
                    Text("Pair")
                        .font(.caption)
                }
                .foregroundColor(.cyan)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(CardioActivityType.allCases.filter { $0.supportsBluetooth }) { activity in
                        EquipmentCard(activity: activity) {
                            pushGoalSetup(for: activity)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Browse All Cardio Link (the demoted exercise list)
    private var browseAllCardioLink: some View {
        Button {
            HapticManager.selectionChanged()
            pushedDestination = .browseAll
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.ds_heading3)
                    .foregroundColor(.green)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Browse all cardio")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    Text("HIIT, swimming, stair climber, and more")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.7))
            )
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .stroke(Color.green.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Walk + Run Hero Card (Cardio Redesign Phase 1, Wave 3)
//
// Big-impact tile that anchors the top half of the cardio landing.
// Two of these sit side-by-side (Walk + Run). Single tap opens the
// goal-setup sheet for that activity.
//
// The accent color drives the gradient + the icon glow + the corner ring,
// reinforcing the activity identity (mint = walk, green = run).
struct WalkRunHeroCard: View {
    let activity: CardioActivityType
    let title: String
    let subtitle: String
    let accent: Color
    let onTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                // Background gradient — softens activity color into bg
                RoundedRectangle(cornerRadius: CornerRadius.xl)
                    .fill(
                        LinearGradient(
                            colors: [
                                accent.opacity(colorScheme == .dark ? 0.35 : 0.22),
                                accent.opacity(colorScheme == .dark ? 0.10 : 0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.xl)
                            .stroke(accent.opacity(0.35), lineWidth: 1)
                    )

                // Watermark icon — large, low-opacity, off-canvas
                Image(systemName: activity.icon)
                    .font(.system(size: 130, weight: .light))
                    .foregroundColor(accent.opacity(0.18))
                    .offset(x: 30, y: 32)
                    .clipped()

                // Foreground content
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        Image(systemName: activity.icon)
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundColor(accent)
                            .padding(10)
                            .background(
                                Circle().fill(accent.opacity(colorScheme == .dark ? 0.15 : 0.20))
                            )
                        Spacer()
                    }

                    Spacer()

                    Text(title)
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundColor(.primary)

                    Text(subtitle)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .padding(.top, 2)

                    HStack(spacing: 4) {
                        Text("Start")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Image(systemName: "arrow.right")
                            .font(.caption)
                            .fontWeight(.bold)
                    }
                    .foregroundColor(accent)
                    .padding(.top, 8)
                }
                .padding(16)
            }
            .frame(height: 188)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xl))
        }
        .scaleButtonStyle(.standard, withHaptic: false)
    }
}

// MARK: - Cardio Preset Chip (Wave 3)
//
// 1-tap shortcut chip for the QUICK START row beneath the hero tiles.
// Currently routes to the goal-setup sheet pre-selected with the right
// activity. Wave 4d will route DIRECTLY to the active screen with a
// pre-filled goal (skipping the sheet for true 1-tap starts).
//
// 2026-05-02 (per-user request): added `fillsWidth` so the chip can
// stretch to fill its parent column when used inside the QUICK START
// 2-column LazyVGrid. Defaults to `false` to keep the legacy
// hug-content behavior for any other caller (none today, but
// preserved for safety per coding-rules "don't change unrelated
// behavior"). When `true` the chip uses a rounded-rectangle shape +
// `frame(maxWidth: .infinity)` so all four grid cells render at the
// same width regardless of label length ("5K Run" vs "30 min Walk").
struct CardioPresetChip: View {
    let label: String
    let icon: String
    let accent: Color
    var fillsWidth: Bool = false
    let onTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
            }
            .foregroundColor(accent)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: fillsWidth ? .infinity : nil)
            .background(
                Group {
                    if fillsWidth {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(accent.opacity(colorScheme == .dark ? 0.10 : 0.08))
                            )
                    } else {
                        Capsule()
                            .fill(accent.opacity(colorScheme == .dark ? 0.12 : 0.10))
                    }
                }
            )
            .overlay(
                Group {
                    if fillsWidth {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(accent.opacity(0.30), lineWidth: 1)
                    } else {
                        Capsule().stroke(accent.opacity(0.30), lineWidth: 1)
                    }
                }
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Connect Strava Card (Wave 3)
//
// Empty-state card shown in the Powered-by-Strava section when the user
// has NOT connected. Replaces the legacy `EmptyView()` no-op which
// produced an awkward gap below the section header. Includes:
//   • The "Powered by Strava" pitch ("If you live in Strava, we'll meet
//     you there — your activities show up here automatically.")
//   • A primary CTA to connect (routes to existing Strava OAuth flow)
//   • A secondary "Or just use Fit33" reassurance — emphasizes that the
//     native walk/run engine above does NOT depend on Strava.
struct ConnectStravaCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var navigateToStrava = false

    private let stravaOrange = Color(red: 0.99, green: 0.30, blue: 0.0)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "link")
                    .font(.ds_heading3)
                    .foregroundColor(stravaOrange)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(stravaOrange.opacity(0.15)))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Connect Strava")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    Text("Auto-sync runs, rides, and segments")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            Text("If you already use Strava, we'll meet you there. Your activities show up here automatically and feed your daily quests, league, and challenges.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Primary connect CTA — opens the existing Strava OAuth flow.
            // Wired via SwiftUI navigation (the Strava connect screen lives
            // in `StravaIntegrationView`).
            NavigationLink(value: CardioLandingDestination.stravaIntegration) {
                HStack {
                    Spacer()
                    Text("Connect Strava")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .fontWeight(.bold)
                    Spacer()
                }
                .foregroundColor(.white)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.md)
                        .fill(stravaOrange)
                )
            }

            Text("Or just use Fit33 — the native walk + run tracker above is fully featured on its own.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 2)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .stroke(stravaOrange.opacity(0.20), lineWidth: 1)
        )
        // Navigation destination registration moved up to
        // `CardioLandingView` (the always-present ancestor) so the
        // value-based push works even when ConnectStravaCard isn't in
        // the hierarchy (Strava connected → CardioStravaSection renders
        // instead, ConnectStravaCard is gone, modifier vanishes).
    }
}

/// Routing values for `CardioLandingView`.
///
/// 2026-05-02 (per-user request): EVERY tap-driven menu off the cardio
/// landing surface is now a pushed page (no `.sheet` "pop-up cards") to
/// match the rest of the app's navigation. Cases:
///   • `.stravaIntegration`        → `StravaSettingsView` (connect CTA)
///   • `.goalSetup(activity:)`     → `CardioGoalSetupView` (Walk/Run
///                                   hero tile, preset chip, equipment
///                                   card, "Just one block" tile)
///   • `.browseAll`                → `BrowseAllCardioView` (the legacy
///                                   exhaustive cardio list)
///
/// First-open mini-onboarding (`CardioFirstOpenIntroView`) is presented
/// as a `.fullScreenCover` rather than a pushed page because it's
/// auto-presented on appear — pushing-on-appear has awkward animation
/// semantics, but a full-screen modal still satisfies "screen, not card"
/// (the orb background already lives inside the intro view itself).
///
/// Active-workout surfaces (`CardioActiveSessionHost`,
/// `CardioActiveWorkoutView`) remain `.fullScreenCover` per the
/// focused-task pattern — they intentionally suppress nav chrome.
enum CardioLandingDestination: Hashable {
    case stravaIntegration
    case goalSetup(activity: CardioActivityType)
    case browseAll
}

// MARK: - Quick Start Card
struct QuickStartCard: View {
    let activity: CardioActivityType
    let onTap: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                // Icon
                ZStack {
                    Circle()
                        .fill(activity.color.opacity(0.2))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: activity.icon)
                        .font(.ds_heading3)
                        .foregroundColor(activity.color)
                }
                
                // Text
                VStack(alignment: .leading, spacing: 2) {
                    Text(activity.rawValue)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text(activity.description)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.white)
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.06), radius: 8, x: 0, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .stroke(activity.color.opacity(0.2), lineWidth: 1)
            )
        }
        .scaleButtonStyle(.standard, withHaptic: true)
    }
}

// MARK: - Equipment Card
struct EquipmentCard: View {
    let activity: CardioActivityType
    let onTap: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: CornerRadius.lg)
                        .fill(
                            LinearGradient(
                                colors: [activity.color.opacity(0.3), activity.color.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: activity.icon)
                        .font(.ds_heading1)
                        .foregroundColor(activity.color)
                }
                
                Text(activity.rawValue)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                // Bluetooth indicator
                HStack(spacing: 2) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 8))
                    Text("BT")
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundColor(.cyan)
            }
            .frame(width: 100)
        }
        .scaleButtonStyle(.standard, withHaptic: true)
    }
}

// MARK: - Cardio Exercise Row
struct CardioExerciseRow: View {
    let exercise: Exercise
    let onTap: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Icon
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.15))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "figure.run")
                        .font(.ds_heading3)
                        .foregroundColor(.green)
                }
                
                // Text
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name ?? "Exercise")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    if let equipment = exercise.equipment {
                        Text(equipment)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color(.systemGray6).opacity(0.5))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Cardio Filter Chip
struct CardioFilterChip: View {
    let title: String
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, Spacing.xs)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.green : Color(.systemGray5))
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    CardioLandingView()
        .environmentObject(UserManager.shared)
}
