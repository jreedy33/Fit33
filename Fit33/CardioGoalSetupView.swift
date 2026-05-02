import SwiftUI

// MARK: - Goal Type
enum CardioGoalType: String, CaseIterable {
    case openGoal = "Open Goal"
    case time = "Time"
    case distance = "Distance"
    case calories = "Calories"

    var icon: String {
        switch self {
        case .openGoal: return "infinity"
        case .time: return "clock.fill"
        case .distance: return "point.topleft.down.to.point.bottomright.curvepath.fill"
        case .calories: return "flame.fill"
        }
    }

    var description: String {
        switch self {
        case .openGoal: return "No specific target"
        case .time: return "Set a duration"
        case .distance: return "Set a distance"
        case .calories: return "Set a calorie burn"
        }
    }

    /// Canonical Supabase key — must match the
    /// `cardio_workouts_goal_type_check` CHECK constraint
    /// (migration #184). NEVER write `rawValue.lowercased()` for the
    /// `goal_type` column — `.openGoal.rawValue.lowercased()` produces
    /// `'open_goal'` which fails the CHECK. Use this property
    /// everywhere the value is written to Supabase. The legacy
    /// `rawValue` is reserved for UI display strings ("Open Goal",
    /// "Time", "Distance", "Calories").
    var canonicalKey: String {
        switch self {
        case .openGoal: return "open"
        case .time:     return "time"
        case .distance: return "distance"
        case .calories: return "calories"
        }
    }
}

// MARK: - Cardio Goal Setup View
struct CardioGoalSetupView: View {
    let activityType: CardioActivityType

    /// When `true`, the view renders an in-screen tab-bar-style sticky
    /// bottom bar with a circular GO! button. When `false` (the
    /// canonical path — pushed onto `WorkoutTabView`'s nav stack from
    /// `CardioLandingView`), the global `GoButtonState.shared` overlay
    /// is used instead so the GO! button floats over the SYSTEM tab
    /// bar exactly like the strength workout-preview flow
    /// (PE invariant 14p — 2026-05-02 per-user request).
    ///
    /// Why we still need an in-screen fallback: `DashboardCardioWidget`
    /// presents this view as a `.sheet` (PE invariant 14k); the global
    /// overlay is mounted on `MainTabView` UNDER the sheet, so it's
    /// visually obscured. The sheet entry passes `presentedAsSheet:
    /// true` to keep a working CTA in that single niche path.
    var presentedAsSheet: Bool = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var userManager: UserManager
    @StateObject private var bluetoothManager = BluetoothFitnessManager.shared
    @ObservedObject private var workoutManager = WorkoutManager.shared
    
    /// Cardio Redesign Phase 1 — Wave 3b. The first-open intro lets
    /// the user pick a preferred default goal type. We read it back
    /// here via `@AppStorage` and seed `selectedGoalType` from it on
    /// init (see `init`). Falls through to `.time` when the value is
    /// missing or unrecognized.
    @AppStorage("cardio_default_goal_type_v1") private var defaultGoalTypePref: String = ""

    /// 2026-05-02: cardio distance UI MUST honor
    /// `UnitSettingsManager.shared.distanceUnit` (swiftui-rules §
    /// "Unit Preferences"). The picker reads this to convert the
    /// canonical km-based `distanceGoal` into the user's preferred
    /// unit for display + chip presets + slider range.
    @ObservedObject private var unitSettings = UnitSettingsManager.shared

    @State private var selectedGoalType: CardioGoalType = .time
    @State private var timeGoal: Int = 30 // minutes
    @State private var distanceGoal: Double = 5.0 // km
    @State private var calorieGoal: Int = 300
    @State private var showingBluetoothSheet = false
    @State private var startWorkout = false
    /// Set to `true` by `applySmartSuggestion()` when there's enough
    /// 7-day history (>=3 sessions) to override the static defaults.
    /// Used by `smartSuggestHint` to surface a one-line "based on your
    /// last 7 days" chip — replaces the legacy "Recommended for you"
    /// card the user removed 2026-05-02.
    @State private var smartSuggestApplied: Bool = false
    /// Cardio Redesign Phase 1 — Wave 4b. Set when GO is tapped for an
    /// outdoor walk / run / cycle. Routes the user into the new
    /// `CardioActiveSessionHost` instead of the legacy
    /// `CardioActiveWorkoutView` (which still owns indoor activities
    /// + the duplicate `CardioLocationManager` until Wave 4b cleanup).
    @State private var startNativeWorkout = false

    /// `true` for the activities the new `OutdoorCardioManager` /
    /// `CardioSessionManager` flow handles. Indoor + niche activities
    /// fall through to the legacy `CardioActiveWorkoutView`.
    private var usesNativeOutdoorEngine: Bool {
        switch activityType {
        case .outdoorRun, .walk, .outdoorCycle: return true
        default: return false
        }
    }
    
    // Smart recommendations based on user profile
    private var recommendations: (time: Int, distance: Double, calories: Int) {
        let user = userManager.currentUser
        let experience = user?.experienceLevel?.lowercased() ?? "beginner"
        let goal = user?.fitnessGoal?.lowercased() ?? ""
        
        // Base values from activity type
        var time = activityType.defaultDuration
        var distance = activityType.defaultDistance
        var calories = activityType.defaultCalories
        
        // Adjust based on experience
        switch experience {
        case "beginner":
            time = Int(Double(time) * 0.7)
            distance = distance * 0.6
            calories = Int(Double(calories) * 0.7)
        case "advanced":
            time = Int(Double(time) * 1.3)
            distance = distance * 1.4
            calories = Int(Double(calories) * 1.3)
        default:
            break // intermediate stays at default
        }
        
        // Adjust based on goal
        if goal.contains("lose") || goal.contains("lean") || goal.contains("fat") {
            calories = Int(Double(calories) * 1.2)
            time = Int(Double(time) * 1.1)
        } else if goal.contains("endurance") {
            time = Int(Double(time) * 1.3)
            distance = distance * 1.3
        }
        
        return (time, distance, calories)
    }
    
    // 2026-05-02 (per-user request — Wave 4d.1 polish): goal setup is
    // now a pushed page (NOT a sheet) hosted by `CardioLandingView`'s
    // `.navigationDestination(item:)`. PE invariant 6 — no nested
    // `NavigationStack`. System back chevron handles dismiss.
    // Background = canonical `AnimatedOrbBackground.workout(...)`.
    //
    // Body composition (revised 2026-05-02 — eyebrow + slider removed):
    //   • goalTypeSelector  — 4-chip row (open / time / distance /
    //                         calories), `.ultraThinMaterial`
    //                         unselected → accent-gradient selected.
    //                         (No "SET UP / Pick a goal — and run."
    //                         eyebrow above it — removed per-user
    //                         request for a denser layout.)
    //   • goalInputSection  — floating "− 64pt value [unit] +"
    //                         stepper row (no card container) + chip
    //                         row of presets. Slider was removed; the
    //                         chip row already covers the typical
    //                         jump-distance values, and the stepper
    //                         handles small ±step nudges. Replaced
    //                         the legacy `GoalPickerCard` boxed
    //                         picker per-user request — the stepper
    //                         floats directly on the orb background.
    //                         (`openGoalHint` still renders for the
    //                         `.openGoal` state.)
    //   • smartSuggestHint  — lightweight inline chip ("Based on your
    //                         last 7 days") that surfaces only when
    //                         `applySmartSuggestion()` actually
    //                         overrode the static defaults. Replaces
    //                         the legacy heavy "Recommended for you"
    //                         card (removed per user request).
    //   • bluetoothSection  — only renders for `.supportsBluetooth`
    //                         activities (treadmill, indoor cycle,
    //                         rowing, elliptical, stair climber).
    //                         Walk + run never see this branch.
    //   • orDivider         — "or" hairline (outdoor run only —
    //                         separates Fit33 path from Strava
    //                         handoff path).
    //   • runWithStravaButton — orange Strava handoff CTA (outdoor
    //                         run only, in scrolling content).
    //   • Floating GO!       — canonical path (pushed off
    //                         `CardioLandingView`): the global
    //                         `GoButtonState.shared` overlay floats
    //                         the circular `FloatingGoButton` over
    //                         the SYSTEM tab bar (centered between
    //                         Exercises + Meals), exactly like the
    //                         strength workout-preview flow.
    //                         `bottomGoBar` is rendered ONLY when
    //                         `presentedAsSheet == true` (dashboard
    //                         widget edge case — the global overlay
    //                         is hidden by the sheet there).
    var body: some View {
        ZStack {
            AnimatedOrbBackground.workout(colorScheme: colorScheme)
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    // 2026-05-02 (per-user request): the heavy
                    // "SET UP / Pick a goal — and run. / GPS · Pace
                    // · Route" eyebrow block was removed. The screen
                    // now starts directly at the Goal Type selector
                    // for a cleaner, denser layout. The nav title
                    // ("Outdoor Run" / "Walk" / etc.) already
                    // identifies the activity, so the duplicate
                    // headline read as filler.
                    goalTypeSelector
                    goalInputSection
                    smartSuggestHint
                    if activityType.supportsBluetooth {
                        bluetoothSection
                    }

                    // 2026-05-02 (per-user request, follow-up): the
                    // "Run with Strava" handoff used to live in the
                    // sticky bottom CTA stack. Per the latest layout
                    // spec, it now sits IN the scrolling content area
                    // with an "or" divider above it — between the
                    // goal input and the floating GO! — so the user
                    // sees: "Set your goal" → "or" → "Run with
                    // Strava" → tab-bar GO!. Outdoor run only; walks
                    // / outdoor cycle can ship their own variants
                    // later.
                    if activityType == .outdoorRun {
                        orDivider
                        runWithStravaButton
                    }

                    // Pad enough that the floating GO! button (which
                    // overlaps the system tab bar) doesn't crash into
                    // the last content section.
                    Spacer(minLength: 140)
                }
                .padding(.horizontal, 22)
                .padding(.top, 12)
            }

            // Sheet-only fallback: the global `GoButtonState.shared`
            // overlay is rendered on `MainTabView` UNDER the sheet,
            // so we still surface an in-screen circular GO! when the
            // dashboard widget presents this as a sheet.
            if presentedAsSheet {
                VStack {
                    Spacer()
                    bottomGoBar
                }
            }
        }
        .navigationTitle(activityType.rawValue)
        .navigationBarTitleDisplayMode(.inline)
        .adaptiveToolbarBackground()
        .sheet(isPresented: $showingBluetoothSheet) {
            FitnessEquipmentView()
        }
        .fullScreenCover(isPresented: $startWorkout) {
            CardioActiveWorkoutView(
                activityType: activityType,
                goalType: selectedGoalType,
                timeGoal: timeGoal,
                distanceGoal: distanceGoal,
                calorieGoal: calorieGoal
            )
            .environmentObject(userManager)
        }
        // 2026-05-02 (Wave 4f — minimize-able active screen): the active
        // cardio cover is now mounted GLOBALLY on `MainTabView` so the
        // user can minimize the running screen and browse other tabs
        // mid-workout. We only flip `startNativeWorkout` here as a
        // local trigger that pops this goal-setup view back to root —
        // the global cover handles the actual presentation.
        .onChange(of: workoutManager.shouldDismissCardioFlow) { _, shouldDismiss in
            if shouldDismiss {
                startWorkout = false
                dismiss()
            }
        }
        .onAppear {
            // Set initial values to recommendations
            timeGoal = recommendations.time
            distanceGoal = recommendations.distance
            calorieGoal = recommendations.calories

            // Cardio Redesign Phase 1 — Wave 3b. Seed `selectedGoalType`
            // from the user's first-open intro choice ONCE per
            // appearance. The user can still flip to any other goal
            // type via the chip row — this is just the initial pin.
            switch defaultGoalTypePref {
            case "open": selectedGoalType = .openGoal
            case "time": selectedGoalType = .time
            case "distance": selectedGoalType = .distance
            case "calories": selectedGoalType = .calories
            default: break
            }

            // 2026-05-02 (per-user request, Wave 4d.3): mount the
            // floating GO! button on the global overlay so it sits
            // OVER the system tab bar — exactly like the strength
            // workout-preview flow. Skipped when the view is hosted
            // inside a sheet (`presentedAsSheet`); see the in-screen
            // `bottomGoBar` fallback above for that path.
            if !presentedAsSheet {
                showFloatingGoButton()
            }
        }
        .onDisappear {
            if !presentedAsSheet {
                GoButtonState.shared.hide(reason: "CardioGoalSetup_disappeared")
            }
        }
        // Re-arm the floating GO! once the active-cardio cover dismisses
        // (the user is back on this screen and may want to start a
        // second session). `triggerStart()` already nilled the action
        // synchronously so we must explicitly re-show.
        .onChange(of: startNativeWorkout) { _, isPresenting in
            if !isPresenting && !presentedAsSheet { showFloatingGoButton() }
        }
        .onChange(of: startWorkout) { _, isPresenting in
            if !isPresenting && !presentedAsSheet { showFloatingGoButton() }
        }
        // Cardio Redesign Phase 1 — Wave 4e (Smart Goal Auto-Suggest).
        // After the static recommendations seed the controls, fire an
        // async query against the user's last 7 days of cardio for this
        // activity type and bias the defaults +5-10% above the median.
        // Falls through silently if there's no history yet (then the
        // static recommendations stand). Kept on the same `.task` view
        // modifier rather than `.onAppear` so SwiftUI cancels the load
        // automatically when the sheet dismisses.
        .task { await applySmartSuggestion() }
    }

    // MARK: - Smart Goal Auto-Suggest (Wave 4e)
    //
    // Pull the user's last-7-days cardio rows from Supabase, filter to
    // matching activity type, compute the median time/distance/calories,
    // and bias defaults +7% above the median (in line with progressive
    // overload — gentle, never aggressive). If there's <3 sessions in
    // the window we don't override — small sample sizes lead to
    // erratic suggestions ("you ran 12 miles last week, here's 13"
    // when really it was a fluke long run).
    private func applySmartSuggestion() async {
        let activityKey = supabaseActivityKey
        guard !activityKey.isEmpty else { return }

        let recent: [CardioWorkoutDTO]
        do {
            recent = try await SupabaseManager.shared.fetchRecentCardioWorkouts(
                limit: 30, activityType: activityKey
            )
        } catch {
            return
        }
        let cutoff = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let inWindow = recent.filter {
            // Best-effort parse — `completed_at` may or may not include
            // fractional seconds. Try both.
            let date = isoFormatter.date(from: $0.completedAt)
                ?? ISO8601DateFormatter().date(from: $0.completedAt)
            return (date ?? .distantPast) >= cutoff
        }
        guard inWindow.count >= 3 else { return }

        let durationsMin = inWindow.map { Double($0.durationSeconds) / 60.0 }.sorted()
        let distancesKm = inWindow.map { $0.distanceMeters / 1000.0 }.sorted()
        let calories = inWindow.map { $0.caloriesBurned }.sorted()

        func median(_ arr: [Double]) -> Double {
            guard !arr.isEmpty else { return 0 }
            let mid = arr.count / 2
            return arr.count % 2 == 0 ? (arr[mid - 1] + arr[mid]) / 2 : arr[mid]
        }

        let suggestedTime = max(5, Int((median(durationsMin) * 1.07).rounded()))
        let suggestedDist = max(0.5, (median(distancesKm) * 1.07 * 10).rounded() / 10)
        let suggestedCal  = max(50, Int((median(calories) * 1.07).rounded()))

        await MainActor.run {
            timeGoal = suggestedTime
            if activityType.defaultDistance > 0 {
                distanceGoal = suggestedDist
            }
            calorieGoal = suggestedCal
            // Surface the inline hint chip so the user knows the seeded
            // values came from their history (not arbitrary defaults).
            // Replaces the legacy heavy "Recommended for you" card.
            withAnimation(.easeInOut(duration: 0.25)) {
                smartSuggestApplied = true
            }
        }
    }

    /// Maps the legacy `CardioActivityType` to the Supabase
    /// `cardio_workouts.activity_type` string we filter on.
    private var supabaseActivityKey: String {
        switch activityType {
        case .outdoorRun:    return "run"
        case .walk:          return "walk"
        case .outdoorCycle:  return "outdoor_cycle"
        case .treadmill:     return "treadmill"
        case .indoorCycle:   return "indoor_cycle"
        case .rowing:        return "rowing"
        case .elliptical:    return "elliptical"
        case .stairClimber:  return "stair_climber"
        case .hiit:          return "hiit"
        case .swimming:      return "swimming"
        }
    }
    
    // 2026-05-02: legacy `backgroundGradient` (LinearGradient + activity-
    // color blur accent) removed. Replaced by canonical
    // `AnimatedOrbBackground.workout(...)` in `body` for visual
    // consistency with `CardioLandingView` and the rest of the cardio
    // surface (per-user request).

    
    // MARK: - Goal Type Selector
    private var goalTypeSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("GOAL TYPE")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .tracking(1)
            
            HStack(spacing: 10) {
                ForEach(CardioGoalType.allCases, id: \.self) { goalType in
                    GoalTypeButton(
                        goalType: goalType,
                        isSelected: selectedGoalType == goalType,
                        color: activityType.color
                    ) {
                        HapticManager.selectionChanged()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedGoalType = goalType
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Goal Input Section
    @ViewBuilder
    private var goalInputSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if selectedGoalType != .openGoal {
                Text("SET YOUR GOAL")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.secondary)
                    .tracking(1)
            }

            switch selectedGoalType {
            case .time:
                TimeGoalPicker(
                    minutes: $timeGoal,
                    color: activityType.color,
                    activity: activityType
                )
            case .distance:
                DistanceGoalPicker(
                    distanceKm: $distanceGoal,
                    color: activityType.color,
                    unit: unitSettings.distanceUnit,
                    activity: activityType
                )
            case .calories:
                CalorieGoalPicker(
                    calories: $calorieGoal,
                    color: activityType.color,
                    activity: activityType
                )
            case .openGoal:
                openGoalHint
            }
        }
    }

    // MARK: - Open Goal Hint (replaces empty state)
    //
    // When the user selects Open Goal, the goal-value picker collapses
    // away. Instead of showing an empty gap, render a friendly inline
    // card reassuring them they can just press GO. Same `.ultraThinMaterial`
    // + accent stroke pattern as the polished pickers + landing chips,
    // so the visual identity stays consistent.
    private var openGoalHint: some View {
        HStack(spacing: 14) {
            Image(systemName: "infinity")
                .font(.title2.weight(.semibold))
                .foregroundColor(activityType.color)
                .frame(width: 44, height: 44)
                .background(Circle().fill(activityType.color.opacity(0.15)))

            VStack(alignment: .leading, spacing: 3) {
                Text("Just go — no target")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                Text("We'll track your time, distance, and pace. Press GO when ready.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.lg)
                        .stroke(activityType.color.opacity(0.30), lineWidth: 1)
                )
        )
    }

    // MARK: - Smart Suggest Hint (replaces "Recommended for you")
    //
    // 2026-05-02 (per-user request): the legacy "Recommended for you"
    // card is gone. The smart-suggest engine still runs in the
    // background (`applySmartSuggestion()` reads last 7 days of cardio
    // and biases defaults +7% above median when >=3 sessions exist),
    // but instead of a heavy 3-bubble card we surface a single inline
    // chip that just says "we used your recent history to seed this".
    // Hidden when smart-suggest didn't fire (small sample / no
    // history) — the static recommendations stand silently in that
    // case, matching the rest of the app's "trust the defaults" UX.
    @ViewBuilder
    private var smartSuggestHint: some View {
        if smartSuggestApplied {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.orange)
                Text("Based on your last 7 days of cardio")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                Capsule().fill(.ultraThinMaterial)
            )
            .overlay(
                Capsule().stroke(Color.orange.opacity(0.25), lineWidth: 1)
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    // MARK: - Bluetooth Section
    private var bluetoothSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("EQUIPMENT")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .tracking(1)
            
            Button(action: {
                showingBluetoothSheet = true
            }) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(bluetoothManager.connectionState == .connected ? Color.green.opacity(0.2) : Color.cyan.opacity(0.2))
                            .frame(width: 48, height: 48)
                        
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.ds_heading3)
                            .foregroundColor(bluetoothManager.connectionState == .connected ? .green : .cyan)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(bluetoothManager.connectionState == .connected
                             ? (bluetoothManager.connectedDevice?.name ?? "Connected")
                             : "Connect Equipment")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        Text(bluetoothManager.connectionState == .connected
                             ? "Tap to manage"
                             : "Sync your \(activityType.rawValue.lowercased()) data")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    if bluetoothManager.connectionState == .connected {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 10, height: 10)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.lg)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: CornerRadius.lg)
                                .stroke(
                                    bluetoothManager.connectionState == .connected
                                        ? Color.green.opacity(0.40)
                                        : Color.cyan.opacity(0.30),
                                    lineWidth: 1
                                )
                        )
                )
            }
            .buttonStyle(UniversalScaleButtonStyle(scale: .standard))
        }
    }
    
    // MARK: - Native Session Bridge (Wave 4b)
    //
    // Maps the legacy `CardioActivityType` + `CardioGoalType` selection
    // into the new `CardioSessionManager` (`CardioActivity` + `RunGoalType`)
    // surface, kicks off the cinematic countdown, and presents the new
    // active-session host. The legacy fullScreenCover stays in place
    // for indoor activities + non-GPS flows.
    private func routeToNativeSession() {
        let mappedActivity: CardioActivity = {
            switch activityType {
            case .outdoorRun:   return .run
            case .walk:         return .walk
            case .outdoorCycle: return .outdoorCycle
            default:            return .run
            }
        }()

        let (goal, value): (RunGoalType, Double) = {
            switch selectedGoalType {
            case .openGoal:  return (.none, 0)
            case .time:      return (.time, Double(timeGoal) * 60)
            case .distance:  return (.distance, distanceGoal * 1000)
            case .calories:  return (.calories, Double(calorieGoal))
            }
        }()

        CardioSessionManager.shared.prepare(activity: mappedActivity)
        CardioSessionManager.shared.setGoal(goal, value: value)
        // `start()` flips the session into `.preStart` and runs the
        // 3-2-1 countdown. The host view's first render is the
        // countdown overlay sitting on top of the empty active layout
        // (map + zeroed metrics), then transitions to live.
        CardioSessionManager.shared.start()
        // Wave 4f (2026-05-02): the active cover is mounted GLOBALLY on
        // `MainTabView`. Navigate to the Home tab and clear the
        // Workout-tab nav stack so the cover presents over a clean
        // Dashboard. This also fixes a SwiftUI race where calling
        // `dismiss()` on the pushed goal-setup view at the same time
        // the global `.fullScreenCover` was trying to present prevented
        // the cover from animating up — the user saw nothing happen on
        // GO. Now the navigation pop is owned by `MainTabView`'s
        // canonical `shouldNavigateToHomeTabInstant` handler, which
        // sequences the tab switch + nav clear deterministically.
        WorkoutManager.shared.shouldClearWorkoutTabNav = true
        WorkoutManager.shared.shouldNavigateToHomeTabInstant = true
    }

    // MARK: - GO! Tap Handler (shared)
    //
    // Single funnel for the GO! tap regardless of where it came from
    // (floating overlay button OR the in-screen `bottomGoBar` sheet
    // fallback). Outdoor walk / run / outdoor cycle route into the
    // new `CardioSessionManager` flow with the cinematic countdown;
    // every other activity falls through to the legacy
    // `CardioActiveWorkoutView` cover until Wave 4b cleanup.
    private func handleGoTapped() {
        if usesNativeOutdoorEngine {
            routeToNativeSession()
        } else {
            startWorkout = true
        }
    }

    // MARK: - Floating GO! Button Mount (Wave 4d.3 — 2026-05-02)
    //
    // Mounts the SAME global `GoButtonState.shared` overlay the
    // strength workout-preview flow uses, so the circular
    // `FloatingGoButton` floats OVER the system tab bar (centered
    // between Exercises + Meals — see `GoButton.swift`'s `.offset(x:
    // 3, y: 2)` fine-tune). Activity color travels through:
    //   tile-tap → goal-setup → live workout
    // (Walk = teal, Run = blue) so the GO! button matches the rest
    // of the cardio surface. Per-user request: "I want the GO!
    // button to float over the tab bar workout tab — exactly as it
    // is on the workout preview screen".
    private func showFloatingGoButton() {
        GoButtonState.shared.show(
            primaryColor: activityType.color,
            secondaryColor: activityType.color.opacity(0.7),
            accessibilityText: "Start \(activityType.rawValue.lowercased())",
            source: "CardioGoalSetup"
        ) {
            handleGoTapped()
        }
    }

    // MARK: - Bottom GO Bar (Wave 4d.2 — 2026-05-02 per-user request)
    //
    // The legacy rectangular GO pill is replaced by a "tab-bar-with-GO!"
    // pattern: a sticky bottom container styled like a secondary tab
    // bar (`.ultraThinMaterial` + rounded top corners + subtle scrim
    // fade above it) that hosts a CIRCULAR `FloatingGoButton` — the
    // SAME 78pt gradient circle the strength flow uses to start a
    // workout (`Fit33/WorkoutTabView.swift::FloatingGoButton`).
    // Reusing that exact component keeps the "tap GO! to start"
    // muscle memory consistent across strength + cardio. The button's
    // primary color now matches the activity (Walk = teal,
    // Run = blue; both also drive the Active screen accent + the
    // landing hero tiles, so the color travels with the user from
    // tile-tap → goal-setup → live workout).
    private var bottomGoBar: some View {
        VStack(spacing: 0) {
            // Scrim — soft fade so scrolling content doesn't crash
            // into the floating GO! button. Sits above the bar.
            LinearGradient(
                colors: [Color.clear, (colorScheme == .dark ? Color.black : Color.white).opacity(0.65)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 28)
            .allowsHitTesting(false)

            HStack {
                Spacer()
                FloatingGoButton(
                    action: { handleGoTapped() },
                    primaryColor: activityType.color,
                    secondaryColor: activityType.color.opacity(0.7),
                    accessibilityText: "Start \(activityType.rawValue.lowercased())"
                )
                Spacer()
            }
            .padding(.top, 14)
            .padding(.bottom, 22)
            .frame(maxWidth: .infinity)
            .background(
                ZStack {
                    // "Tab-bar" surface — rounded top corners +
                    // ultraThinMaterial reads as a secondary
                    // surface anchored to the bottom safe area.
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(.ultraThinMaterial)
                    // 1pt highlight stroke at the top edge —
                    // mimics the system tab bar's hairline divider.
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.18), Color.clear],
                                startPoint: .top,
                                endPoint: .center
                            ),
                            lineWidth: 1
                        )
                }
                .shadow(color: .black.opacity(0.12), radius: 16, y: -4)
                .ignoresSafeArea(edges: .bottom)
            )
        }
    }

    // MARK: - "or" divider (2026-05-02 per-user request)
    //
    // Sits between the goal input section and the "Run with Strava"
    // button. Hairline rule on each side, "or" centered. Subdued —
    // the goal is to softly signal "alternative path", not to compete
    // with the goal-setup or the GO! CTA below.
    private var orDivider: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(Color.secondary.opacity(0.30))
                .frame(height: 1)
            Text("or")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
            Rectangle()
                .fill(Color.secondary.opacity(0.30))
                .frame(height: 1)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Run with Strava (2026-05-02 per user request)
    //
    // Orange brand-color button (Strava #FC4C02) with white text that
    // hands off to the Strava app's record screen. We try two
    // deep-link variants ("strava://record" then plain "strava://")
    // and fall back to the Strava App Store page if the user doesn't
    // have the app installed. `LSApplicationQueriesSchemes` in
    // Info.plist is updated to include `strava` so `canOpenURL` can
    // answer truthfully without an iOS warning.
    private var runWithStravaButton: some View {
        Button(action: openStravaApp) {
            HStack(spacing: 10) {
                Image(systemName: "figure.run")
                    .font(.headline.weight(.bold))
                // 2026-05-02 Strava compliance follow-up: was "Run with
                // Strava" — that phrasing implies live integration during
                // the run, but the button just hands off to Strava's app
                // (Fit33 goes inert). "Record with Strava" makes the
                // handoff explicit and avoids the implied-integration
                // gray area in Strava's brand review.
                Text("Record with Strava")
                    .font(.headline)
                    .fontWeight(.bold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0xFC/255, green: 0x4C/255, blue: 0x02/255),
                        Color(red: 0xFF/255, green: 0x6A/255, blue: 0x1E/255)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(CornerRadius.lg)
            .shadow(
                color: Color(red: 0xFC/255, green: 0x4C/255, blue: 0x02/255).opacity(0.30),
                radius: 8, y: 4
            )
        }
        .buttonStyle(UniversalScaleButtonStyle(scale: .standard))
        .accessibilityLabel("Record with Strava")
        .accessibilityHint("Opens the Strava app to record your run")
    }

    private func openStravaApp() {
        HapticManager.impact(.medium)

        // Try the deep links Strava actually responds to. The "record"
        // variant lands directly on the recording screen on supported
        // versions; "strava://" opens the app's last-used tab on older
        // ones — both are fine. App Store fallback if nothing opens.
        let candidates: [String] = ["strava://record", "strava://"]
        for raw in candidates {
            if let url = URL(string: raw), UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
                AppLogger.info("[CARDIO] Handed off to Strava (\(raw))", category: .ui)
                return
            }
        }

        // Strava not installed — surface the App Store page so the
        // user can install + come back. Strava's iOS App Store id is
        // 426826309 (legacy `Strava: Run, Bike, Hike`).
        if let appStore = URL(string: "https://apps.apple.com/app/strava/id426826309") {
            UIApplication.shared.open(appStore)
            AppLogger.info("[CARDIO] Strava not installed — opened App Store fallback", category: .ui)
        }
    }
}

// MARK: - Goal Type Button
//
// Cardio Redesign Phase 1 — Wave 4d (polish 2026-05-02). Replaces the
// flat `Color(.systemGray5)` unselected fill with `.ultraThinMaterial`
// + per-color stroke, matching the landing page's `CardioPresetChip`
// aesthetic. The selected state preserves the activity-accent color
// fill for clear "this is the chosen goal" feedback.
struct GoalTypeButton: View {
    let goalType: CardioGoalType
    let isSelected: Bool
    let color: Color
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                Image(systemName: goalType.icon)
                    .font(.ds_heading3)

                Text(goalType.rawValue)
                    .font(.caption2)
                    .fontWeight(.semibold)
            }
            .foregroundColor(isSelected ? .white : .primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: CornerRadius.md)
                            .fill(LinearGradient(
                                colors: [color, color.opacity(0.85)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                    } else {
                        RoundedRectangle(cornerRadius: CornerRadius.md)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: CornerRadius.md)
                                    .stroke(color.opacity(0.30), lineWidth: 1)
                            )
                    }
                }
            )
        }
        .buttonStyle(UniversalScaleButtonStyle(scale: .standard))
    }
}

// MARK: - Goal Quick-Select Chip (shared)
//
// Replaces the per-picker chip duplication (Color(.systemGray5)
// unselected → solid `color` selected). Uses the same
// `.ultraThinMaterial` + accent-stroke (unselected) → accent-gradient
// (selected) treatment as `GoalTypeButton` and `CardioPresetChip` for
// pixel-perfect consistency with the landing page chips above.
private struct GoalQuickChip: View {
    let label: String
    let isSelected: Bool
    let color: Color
    let onTap: () -> Void

    var body: some View {
        Button {
            HapticManager.selectionChanged()
            onTap()
        } label: {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(isSelected ? .white : .primary)
                .frame(minWidth: 50)
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .background(
                    ZStack {
                        if isSelected {
                            Capsule().fill(LinearGradient(
                                colors: [color, color.opacity(0.85)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                        } else {
                            Capsule()
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    Capsule().stroke(color.opacity(0.30), lineWidth: 1)
                                )
                        }
                    }
                )
        }
        .buttonStyle(UniversalScaleButtonStyle(scale: .standard))
    }
}

// MARK: - Goal Stepper Row (shared, 2026-05-02 per-user request)
//
// Replaces the legacy `GoalPickerCard` + `Slider` combo for the three
// goal pickers. Renders a floating "− [value][unit] +" row on the orb
// background (no card container) per the spec:
//   "-     50 min.      +     < floating not in a container"
//
// Tapping the chevron buttons increments / decrements by `step`,
// clamped to `range`. Long-press is intentionally NOT wired up — the
// chip row directly below offers the typical jump-distance values
// (15 / 30 / 45 / 60 min, 5K / 10K / Half / Full, etc.), so the
// stepper only needs to handle small ±step nudges.
private struct GoalStepperRow: View {
    let valueText: String
    let unitText: String
    let color: Color
    let canDecrement: Bool
    let canIncrement: Bool
    let onDecrement: () -> Void
    let onIncrement: () -> Void
    /// Used by `.contentTransition(.numericText(...))` so the big
    /// number animates smoothly between values.
    let animationValue: Double

    var body: some View {
        HStack(spacing: Spacing.lg) {
            stepperButton(
                systemName: "minus",
                enabled: canDecrement,
                action: onDecrement
            )

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(valueText)
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .foregroundColor(color)
                    .contentTransition(.numericText(value: animationValue))
                    .animation(.snappy(duration: 0.2), value: animationValue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(unitText)
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)

            stepperButton(
                systemName: "plus",
                enabled: canIncrement,
                action: onIncrement
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private func stepperButton(
        systemName: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            HapticManager.selectionChanged()
            action()
        } label: {
            Image(systemName: systemName)
                .font(.title3.weight(.bold))
                .foregroundColor(enabled ? color : .secondary.opacity(0.4))
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Circle().stroke(
                                (enabled ? color : Color.secondary).opacity(0.30),
                                lineWidth: 1
                            )
                        )
                )
        }
        .buttonStyle(UniversalScaleButtonStyle(scale: .standard))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.55)
        .accessibilityLabel(systemName == "minus" ? "Decrease" : "Increase")
    }
}

// MARK: - Time Goal Picker
struct TimeGoalPicker: View {
    @Binding var minutes: Int
    let color: Color
    let activity: CardioActivityType

    private let minValue: Int = 5
    private let maxValue: Int = 120
    private let step: Int = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GoalStepperRow(
                valueText: "\(minutes)",
                unitText: "min",
                color: color,
                canDecrement: minutes > minValue,
                canIncrement: minutes < maxValue,
                onDecrement: { minutes = max(minValue, minutes - step) },
                onIncrement: { minutes = min(maxValue, minutes + step) },
                animationValue: Double(minutes)
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(activity.timeGoalPresets, id: \.self) { time in
                        GoalQuickChip(
                            label: "\(time)",
                            isSelected: minutes == time,
                            color: color
                        ) { minutes = time }
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }
}

// MARK: - Distance Preset
//
// 2026-05-02 (Wave 4d.2): activity-aware distance presets. Two flavors:
//
//   • `.round(n)` — a round number in the USER'S unit. Label = "\(n)";
//     km value = `n` if metric, `n × 1.609` if imperial. Used for
//     casual activities where vernacular = the unit (walks, cycling).
//   • `.race(label: km:)` — race-distance with a fixed canonical km
//     value and a fixed label that survives unit toggle ("5K", "10K",
//     "Half", "Full"). Running culture uses K labels universally,
//     even in the US, so these are unit-independent.
enum DistancePreset {
    case round(Int)
    case race(label: String, km: Double)

    func km(in unit: UnitSettingsManager.DistanceUnit) -> Double {
        switch self {
        case .round(let n):
            switch unit {
            case .imperial: return Double(n) * 1.609_344
            case .metric:   return Double(n)
            }
        case .race(_, let km):
            return km
        }
    }

    var label: String {
        switch self {
        case .round(let n):              return "\(n)"
        case .race(let label, _):        return label
        }
    }

    /// Stable identity for SwiftUI `ForEach`. Round identity = the
    /// number; race identity = the label (5K/10K/Half/Full are unique).
    var id: String {
        switch self {
        case .round(let n):              return "round-\(n)"
        case .race(let label, _):        return "race-\(label)"
        }
    }
}

// MARK: - Distance Goal Picker
//
// 2026-05-02 (Wave 4d.1 polish): swiftui-rules § "Unit Preferences"
// requires every cardio distance UI to honor
// `UnitSettingsManager.shared.distanceUnit`. Picker now stores the
// canonical km value (`distanceKm` binding) but renders the big
// number, the chip presets, and the slider in the user's preferred
// unit. Conversion happens at the boundary; consumers (Supabase
// payloads, RPC, gamification) keep getting km.
//
// Wave 4d.2 (2026-05-02): chip presets are activity-aware via
// `activity.distanceGoalPresets` — runs use race vernacular
// (5K/10K/Half/Full), walks use round km/mi numbers (1/2/3/5/10),
// cycling uses long chunks (10/25/50/100), etc.
struct DistanceGoalPicker: View {
    @Binding var distanceKm: Double
    let color: Color
    let unit: UnitSettingsManager.DistanceUnit
    let activity: CardioActivityType

    /// Slider range in the user's preferred unit. Cycle activities get
    /// extra headroom (centuries / metric centuries) since 100 mi /
    /// 100 km rides aren't unusual; everything else is capped at
    /// roughly an ultramarathon's worth.
    private var sliderRange: ClosedRange<Double> {
        let isCycle = activity == .outdoorCycle || activity == .indoorCycle
        switch unit {
        case .imperial: return 0.25...(isCycle ? 100 : 30)
        case .metric:   return 0.5...(isCycle ? 160 : 50)
        }
    }

    private var sliderStep: Double {
        switch unit {
        case .imperial: return 0.25
        case .metric:   return 0.5
        }
    }

    private var unitShortLabel: String {
        switch unit {
        case .imperial: return "mi"
        case .metric:   return "km"
        }
    }

    /// Distance in the user's preferred unit (computed from the
    /// canonical km binding). Used for the big display + slider.
    private var distanceInUnit: Double {
        switch unit {
        case .imperial: return distanceKm / 1.609_344
        case .metric:   return distanceKm
        }
    }

    /// Convert a value in the user's preferred unit back to km
    /// (canonical) for the binding write.
    private func toKm(_ valueInUnit: Double) -> Double {
        switch unit {
        case .imperial: return valueInUnit * 1.609_344
        case .metric:   return valueInUnit
        }
    }

    /// Comparison epsilon in km — a chip is "selected" if the
    /// canonical `distanceKm` is within ~50 m of the preset's km value.
    private func isSelected(_ preset: DistancePreset) -> Bool {
        abs(distanceKm - preset.km(in: unit)) < 0.05
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GoalStepperRow(
                valueText: String(format: "%.2f", distanceInUnit),
                unitText: unitShortLabel,
                color: color,
                canDecrement: distanceInUnit > sliderRange.lowerBound + 0.0001,
                canIncrement: distanceInUnit < sliderRange.upperBound - 0.0001,
                onDecrement: {
                    let next = max(sliderRange.lowerBound, distanceInUnit - sliderStep)
                    distanceKm = toKm(next)
                },
                onIncrement: {
                    let next = min(sliderRange.upperBound, distanceInUnit + sliderStep)
                    distanceKm = toKm(next)
                },
                animationValue: distanceInUnit
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(activity.distanceGoalPresets(unit: unit), id: \.id) { preset in
                        GoalQuickChip(
                            label: preset.label,
                            isSelected: isSelected(preset),
                            color: color
                        ) {
                            distanceKm = preset.km(in: unit)
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }
}

// MARK: - Calorie Goal Picker
struct CalorieGoalPicker: View {
    @Binding var calories: Int
    let color: Color
    let activity: CardioActivityType

    private let minValue: Int = 50
    private let maxValue: Int = 1500
    private let step: Int = 50

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GoalStepperRow(
                valueText: "\(calories)",
                unitText: "cal",
                color: color,
                canDecrement: calories > minValue,
                canIncrement: calories < maxValue,
                onDecrement: { calories = max(minValue, calories - step) },
                onIncrement: { calories = min(maxValue, calories + step) },
                animationValue: Double(calories)
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(activity.calorieGoalPresets, id: \.self) { cal in
                        GoalQuickChip(
                            label: "\(cal)",
                            isSelected: calories == cal,
                            color: color
                        ) { calories = cal }
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }
}

// MARK: - Activity-Aware Goal Presets (Wave 4d.2 — 2026-05-02)
//
// Quick-select chip values per activity for the three goal pickers
// (Time / Distance / Calorie). Replaces the previous one-size-fits-all
// arrays which surfaced 90-min "Walk" chips and 100-cal "Cycle" chips
// — neither sensible for the activity. Per-user request: walks should
// suggest leisurely durations, runs should use race vernacular,
// cycling should use longer chunks, etc.
//
// Design notes:
//   • Time presets are minutes (Int).
//   • Calorie presets are calories (Int).
//   • Distance presets are `[DistancePreset]` — see the enum above.
//     `.round(n)` = "n in user's unit" (e.g. 5 km / 5 mi); `.race`
//     uses fixed canonical km values + universal labels (5K, 10K,
//     Half, Full) regardless of unit, since running culture uses
//     K-distance vernacular even in the US.
//   • All preset arrays are kept short (4-6 items) to fit on iPhone
//     SE width without horizontal scrolling for the most common
//     selections — though the ScrollView still scrolls for the longer
//     run + cycle lists.
extension CardioActivityType {

    /// Time-goal chip presets (minutes). Bias toward "what a user of
    /// this activity actually picks" — walks lean longer (15-90),
    /// HIIT/rowing lean shorter (10-30), cycling has the widest range.
    var timeGoalPresets: [Int] {
        switch self {
        case .walk:                              return [15, 30, 45, 60, 90]
        case .outdoorRun, .treadmill:            return [20, 30, 45, 60]
        case .outdoorCycle:                      return [30, 45, 60, 90, 120]
        case .indoorCycle:                       return [20, 30, 45, 60]
        case .rowing:                            return [10, 15, 20, 30, 45]
        case .elliptical:                        return [20, 30, 45, 60]
        case .stairClimber:                      return [15, 20, 30, 45]
        case .hiit:                              return [10, 15, 20, 30, 45]
        case .swimming:                          return [20, 30, 45, 60]
        }
    }

    /// Distance-goal chip presets. Returns `[DistancePreset]` so the
    /// picker can render race-vernacular labels (5K/10K/Half/Full) for
    /// runs and round-number labels for everything else. `unit` is
    /// passed in so cycling can offer different round-number sets for
    /// imperial vs metric users (10/25/50/100 mi feels different from
    /// 10/25/50/100 km — both reasonable, but the value differs).
    func distanceGoalPresets(unit: UnitSettingsManager.DistanceUnit) -> [DistancePreset] {
        switch self {
        case .walk:
            // Same labels for both units — 1/2/3/5/10 mi or km.
            return [.round(1), .round(2), .round(3), .round(5), .round(10)]

        case .outdoorRun, .treadmill:
            // Race vernacular dominates running culture. Universal
            // labels ("5K") with fixed km values that survive unit
            // toggle.
            return [
                .round(1),
                .race(label: "5K", km: 5.0),
                .race(label: "10K", km: 10.0),
                .race(label: "Half", km: 21.0975),
                .race(label: "Full", km: 42.195)
            ]

        case .outdoorCycle:
            // Cycling thinks in 10s. 100 mi (a "century") and 100 km
            // (a "metric century") are the round-number long rides
            // every cyclist knows.
            return [.round(10), .round(25), .round(50), .round(100)]

        case .indoorCycle:
            // Indoor rides are shorter (no terrain to cover).
            return [.round(5), .round(10), .round(20), .round(30)]

        case .rowing:
            // Rowing is short by design — 2K race, 5K threshold,
            // 10K endurance.
            return [
                .round(1),
                .race(label: "2K", km: 2.0),
                .race(label: "5K", km: 5.0),
                .race(label: "10K", km: 10.0)
            ]

        case .swimming:
            // Pool swimming is short. 1/2/3 km in metric world, same
            // in imperial because nobody swims in miles.
            return [.round(1), .round(2), .round(3), .round(5)]

        case .elliptical, .stairClimber, .hiit:
            // Distance isn't typically the goal for these activities,
            // but we still surface a sensible fallback in case the
            // user picks Distance from the goal-type chip row.
            return [.round(1), .round(2), .round(3), .round(5)]
        }
    }

    /// Calorie-goal chip presets. Bias toward typical-session burn
    /// for each activity. Cycling rides burn more than walks; HIIT
    /// and rowing tend to clock 200-400; long bike days hit 1000+.
    var calorieGoalPresets: [Int] {
        switch self {
        case .walk:                              return [100, 200, 300, 500]
        case .outdoorRun, .treadmill:            return [200, 300, 500, 750]
        case .outdoorCycle:                      return [300, 500, 750, 1000]
        case .indoorCycle:                       return [200, 300, 500, 750]
        case .rowing:                            return [100, 200, 300, 500]
        case .elliptical:                        return [200, 300, 500]
        case .stairClimber:                      return [200, 300, 400, 500]
        case .hiit:                              return [200, 300, 400]
        case .swimming:                          return [200, 400, 600]
        }
    }
}

#Preview {
    NavigationStack {
        CardioGoalSetupView(activityType: .treadmill)
            .environmentObject(UserManager.shared)
    }
}
