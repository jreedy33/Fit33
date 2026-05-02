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

    @State private var selectedGoalType: CardioGoalType = .time
    @State private var timeGoal: Int = 30 // minutes
    @State private var distanceGoal: Double = 5.0 // km
    @State private var calorieGoal: Int = 300
    @State private var showingBluetoothSheet = false
    @State private var startWorkout = false
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
    
    // 2026-05-02 (per-user request): goal setup is now a pushed page
    // (NOT a sheet) hosted by `CardioLandingView`'s
    // `.navigationDestination(item:)`. We MUST NOT wrap our own
    // `NavigationStack` here — PE invariant 6 (no nested stacks). The
    // system back chevron handles dismiss; the legacy custom "X" close
    // button is gone. Background swapped from the activity-tinted
    // gradient to the canonical `AnimatedOrbBackground.workout(...)`
    // for visual consistency with the rest of the cardio surface.
    var body: some View {
        ZStack {
            AnimatedOrbBackground.workout(colorScheme: colorScheme)
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 28) {
                    activityHeader
                    goalTypeSelector
                    goalInputSection
                    smartRecommendationCard
                    if activityType.supportsBluetooth {
                        bluetoothSection
                    }
                    Spacer(minLength: 100)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }

            VStack {
                Spacer()
                goButton
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
        .fullScreenCover(isPresented: $startNativeWorkout) {
            CardioActiveSessionHost(isPresented: $startNativeWorkout)
                .environmentObject(userManager)
        }
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

    
    // MARK: - Activity Header
    private var activityHeader: some View {
        VStack(spacing: 16) {
            // Large icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [activityType.color.opacity(0.3), activityType.color.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                
                Image(systemName: activityType.icon)
                    .font(.system(size: 44))
                    .foregroundColor(activityType.color)
            }
            
            VStack(spacing: 4) {
                Text(activityType.rawValue)
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text(activityType.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.top, 20)
    }
    
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
        if selectedGoalType != .openGoal {
            VStack(alignment: .leading, spacing: 16) {
                Text("SET YOUR GOAL")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                    .tracking(1)
                
                switch selectedGoalType {
                case .time:
                    TimeGoalPicker(minutes: $timeGoal, color: activityType.color)
                case .distance:
                    DistanceGoalPicker(distance: $distanceGoal, color: activityType.color)
                case .calories:
                    CalorieGoalPicker(calories: $calorieGoal, color: activityType.color)
                case .openGoal:
                    EmptyView()
                }
            }
        }
    }
    
    // MARK: - Smart Recommendation Card
    private var smartRecommendationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.orange)
                Text("RECOMMENDED FOR YOU")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                    .tracking(1)
            }
            
            HStack(spacing: 16) {
                RecommendationBubble(
                    icon: "clock.fill",
                    value: "\(recommendations.time)",
                    unit: "min",
                    color: .blue
                ) {
                    selectedGoalType = .time
                    timeGoal = recommendations.time
                }
                
                if activityType.defaultDistance > 0 {
                    RecommendationBubble(
                        icon: "point.topleft.down.to.point.bottomright.curvepath.fill",
                        value: String(format: "%.1f", recommendations.distance),
                        unit: "km",
                        color: .green
                    ) {
                        selectedGoalType = .distance
                        distanceGoal = recommendations.distance
                    }
                }
                
                RecommendationBubble(
                    icon: "flame.fill",
                    value: "\(recommendations.calories)",
                    unit: "cal",
                    color: .orange
                ) {
                    selectedGoalType = .calories
                    calorieGoal = recommendations.calories
                }
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color(.systemGray6))
        )
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
                    RoundedRectangle(cornerRadius: 14)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color(.systemGray6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(
                                    bluetoothManager.connectionState == .connected
                                        ? Color.green.opacity(0.3)
                                        : Color.cyan.opacity(0.2),
                                    lineWidth: 1
                                )
                        )
                )
            }
            .buttonStyle(PlainButtonStyle())
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
        startNativeWorkout = true
        // `start()` flips the session into `.preStart` and runs the
        // 3-2-1 countdown. The host view's first render is the
        // countdown overlay sitting on top of the empty active layout
        // (map + zeroed metrics), then transitions to live.
        CardioSessionManager.shared.start()
    }

    // MARK: - GO Button
    // Cardio Redesign Phase 1 — Wave 4d (polish, 2026-05-02).
    //
    // Sticky bottom CTA with a subtle scrim above the button so it
    // reads as anchored to the bottom of the sheet rather than
    // floating over the scrolling content. The button itself uses
    // `UniversalScaleButtonStyle` for tactile feedback consistent
    // with the rest of the cardio surface (CardioLanding hero tiles,
    // preset chips, intro CTAs).
    private var goButton: some View {
        VStack(spacing: 0) {
            // Scrim — fades the scrolling content under the sticky
            // button so text doesn't crash into the GO label.
            LinearGradient(
                colors: [Color.clear, (colorScheme == .dark ? Color.black : Color.white).opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 28)
            .allowsHitTesting(false)

            Button(action: {
                HapticManager.impact(.heavy)
                if usesNativeOutdoorEngine {
                    routeToNativeSession()
                } else {
                    startWorkout = true
                }
            }) {
                HStack(spacing: 10) {
                    Image(systemName: "play.fill")
                        .font(.ds_heading2)

                    Text("GO")
                        .font(.title2)
                        .fontWeight(.bold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    LinearGradient(
                        colors: [activityType.color, activityType.color.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(CornerRadius.lg)
                .shadow(color: activityType.color.opacity(0.4), radius: 12, y: 6)
            }
            .buttonStyle(UniversalScaleButtonStyle(scale: .standard))
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
            .background(
                (colorScheme == .dark ? Color.black : Color.white)
                    .opacity(0.85)
                    .ignoresSafeArea(edges: .bottom)
            )
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

// MARK: - Time Goal Picker
struct TimeGoalPicker: View {
    @Binding var minutes: Int
    let color: Color
    
    private let timeOptions = [10, 15, 20, 25, 30, 45, 60, 90]
    
    var body: some View {
        VStack(spacing: 16) {
            // Large display
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("\(minutes)")
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .foregroundColor(color)
                
                Text("min")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            
            // Quick select buttons
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(timeOptions, id: \.self) { time in
                        Button(action: {
                            HapticManager.selectionChanged()
                            minutes = time
                        }) {
                            Text("\(time)")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(minutes == time ? .white : .primary)
                                .frame(width: 50, height: 40)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(minutes == time ? color : Color(.systemGray5))
                                )
                        }
                    }
                }
            }
            
            // Slider for fine control
            Slider(value: Binding(
                get: { Double(minutes) },
                set: { minutes = Int($0) }
            ), in: 5...120, step: 5)
            .tint(color)
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .fill(Color(.systemGray6).opacity(0.5))
        )
    }
}

// MARK: - Distance Goal Picker
struct DistanceGoalPicker: View {
    @Binding var distance: Double
    let color: Color
    
    private let distanceOptions: [Double] = [1.0, 2.0, 3.0, 5.0, 10.0, 15.0, 21.1, 42.2]
    
    var body: some View {
        VStack(spacing: 16) {
            // Large display
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(String(format: "%.1f", distance))
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .foregroundColor(color)
                
                Text("km")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            
            // Quick select buttons
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(distanceOptions, id: \.self) { dist in
                        Button(action: {
                            HapticManager.selectionChanged()
                            distance = dist
                        }) {
                            Text(dist == 21.1 ? "Half" : dist == 42.2 ? "Full" : String(format: "%.0f", dist))
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(distance == dist ? .white : .primary)
                                .frame(width: 45, height: 40)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(distance == dist ? color : Color(.systemGray5))
                                )
                        }
                    }
                }
            }
            
            // Slider for fine control
            Slider(value: $distance, in: 0.5...50, step: 0.5)
                .tint(color)
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .fill(Color(.systemGray6).opacity(0.5))
        )
    }
}

// MARK: - Calorie Goal Picker
struct CalorieGoalPicker: View {
    @Binding var calories: Int
    let color: Color
    
    private let calorieOptions = [100, 200, 300, 400, 500, 750, 1000]
    
    var body: some View {
        VStack(spacing: 16) {
            // Large display
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("\(calories)")
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .foregroundColor(color)
                
                Text("cal")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            
            // Quick select buttons
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(calorieOptions, id: \.self) { cal in
                        Button(action: {
                            HapticManager.selectionChanged()
                            calories = cal
                        }) {
                            Text("\(cal)")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(calories == cal ? .white : .primary)
                                .frame(width: 50, height: 40)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(calories == cal ? color : Color(.systemGray5))
                                )
                        }
                    }
                }
            }
            
            // Slider for fine control
            Slider(value: Binding(
                get: { Double(calories) },
                set: { calories = Int($0) }
            ), in: 50...1500, step: 50)
            .tint(color)
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .fill(Color(.systemGray6).opacity(0.5))
        )
    }
}

// MARK: - Recommendation Bubble
struct RecommendationBubble: View {
    let icon: String
    let value: String
    let unit: String
    let color: Color
    let onTap: () -> Void
    
    var body: some View {
        Button(action: {
            HapticManager.selectionChanged()
            onTap()
        }) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.ds_bodyRegular)
                    .foregroundColor(color)
                
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(value)
                        .font(.headline)
                        .fontWeight(.bold)
                    Text(unit)
                        .font(.caption2)
                }
                .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .fill(color.opacity(0.1))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    NavigationStack {
        CardioGoalSetupView(activityType: .treadmill)
            .environmentObject(UserManager.shared)
    }
}
