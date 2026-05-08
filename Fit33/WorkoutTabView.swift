import SwiftUI
import CoreData

struct WorkoutTabView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var userManager: UserManager
    @EnvironmentObject var workoutManager: WorkoutManager
    @StateObject private var deepLinkManager = DeepLinkManager.shared
    @State private var navigationPath = NavigationPath()
    @State private var showingStretchModeOverlay = false
    
    var body: some View {
        ZStack {
            // Layer 1: Navigation Stack (always present)
            NavigationStack(path: $navigationPath) {
                WorkoutHomeView(navigationPath: $navigationPath, showingStretchModeOverlay: $showingStretchModeOverlay)
                    .navigationBarHidden(true)
                    .adaptiveToolbarBackground()
                    .navigationDestination(for: String.self) { destination in
                        navigationDestinationView(for: destination)
                    }
            }
            
            // Layer 2: Transition overlay - hides navigation during transitions
            if (workoutManager.shouldClearWorkoutTabNav && !workoutManager.isWorkoutActive) || workoutManager.isTransitioningBackToHome {
                LinearGradient(
                    gradient: Gradient(colors: colorScheme == .dark
                        ? [Color(red: 0.08, green: 0.10, blue: 0.18), Color(red: 0.05, green: 0.06, blue: 0.10)]
                        : [Color.blue.opacity(0.15), Color.purple.opacity(0.08)]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                .zIndex(5)
            }
            
            // Layer 3: Active Workout (on top when active)
            if workoutManager.isWorkoutActive,
               let workout = workoutManager.currentWorkout,
               !workoutManager.currentExercises.isEmpty {
                ActiveWorkoutView(
                    isPresented: .constant(true),
                    workout: workout,
                    exercises: workoutManager.currentExercises
                )
                .zIndex(10)
            } else if workoutManager.isWorkoutActive && workoutManager.currentExercises.isEmpty {
                // Safety: If workout is active but exercises are empty, auto-clear the stuck state
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.orange)
                    
                    Text("Workout Data Error")
                        .font(.title2.bold())
                    
                    Text("Your workout data is corrupted. Tap below to clear it and start fresh.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Button {
                        workoutManager.forceResetWorkoutState()
                    } label: {
                        Text("Clear Stuck Workout")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red)
                            .cornerRadius(CornerRadius.md)
                    }
                    .padding(.horizontal, 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
                .zIndex(10)
            }
            
            // Layer 4: Stretch Mode (on top when active, like ActiveWorkoutView)
            if showingStretchModeOverlay {
                StretchModeView(isPresented: $showingStretchModeOverlay)
                    .environmentObject(userManager)
                    .zIndex(11)
                    .transition(.opacity)
            }
        }
        .onAppear {
            if workoutManager.shouldShowWorkoutGenerator {
                navigationPath.append("WorkoutGenerator")
                workoutManager.shouldShowWorkoutGenerator = false
            }
            NewUserJourneyTracker.shared.logScreen("workout_tab")
        }
        .onChange(of: workoutManager.shouldNavigateToCustomWorkoutBuilder) { _, shouldNavigate in
            if shouldNavigate {
                navigationPath.append("CustomWorkout")
                workoutManager.shouldNavigateToCustomWorkoutBuilder = false
                AppLogger.debug("➕ Navigating to Custom Workout Builder with pre-selected exercise", category: .workout)
            }
        }
        .onReceive(deepLinkManager.$pendingDestination) { destination in
            // Handle deep links that belong to the Workout tab (tab 2)
            // Other destinations are handled by ContentView (tab switching) + t`   qheir target tab views
            guard let destination = destination else { return }
            switch destination {
            case .running:
                navigationPath.append("OutdoorRun")
                deepLinkManager.pendingDestination = nil
                AppLogger.debug("🏃 Deep link: Navigating to running workout", category: .workout)
            case .workout:
                navigationPath.append("WorkoutGenerator")
                deepLinkManager.pendingDestination = nil
                AppLogger.debug("🏋️ Deep link: Navigating to workout generator", category: .workout)
            case .sharedWorkout:
                deepLinkManager.pendingDestination = nil
                AppLogger.debug("🔗 Deep link: Shared workout will be displayed in sheet", category: .workout)
            case .receivedWorkout(let workoutId):
                deepLinkManager.pendingReceivedWorkoutId = workoutId
                navigationPath.append("ReceivedWorkouts")
                deepLinkManager.pendingDestination = nil
                AppLogger.debug("📬 Deep link: Navigating to received workout \(workoutId)", category: .workout)
            case .receivedWorkouts:
                navigationPath.append("ReceivedWorkouts")
                deepLinkManager.pendingDestination = nil
                AppLogger.debug("📬 Deep link: Navigating to received workouts", category: .workout)
            case .communityChallengeBrowse:
                navigationPath.append("CommunityChallenges")
                deepLinkManager.pendingDestination = nil
                AppLogger.debug("🌍 Deep link: Navigating to community challenges", category: .workout)
                
            // These destinations are handled by ContentView + DashboardView/FriendsTabView
            // Don't handle or clear them here — let the correct tab consume them
            case .friends, .friendsActivity, .friendRequests, .friendSearch, .challenges, .challengeCreation, .challengeInvite, .challengeDetail:
                break  // Handled by ContentView → FriendsTabView / DashboardView
            case .communityChallenge:
                break  // Handled by ContentView (join sheet)
            case .privateChallengeDetail, .privateChallengeInvite, .privateChallengeJoinByCode:
                break  // Handled by ContentView → DashboardView (sheet)
            case .programs:
                navigationPath.append("PersonalizedPrograms")
                deepLinkManager.pendingDestination = nil
                AppLogger.debug("📋 Deep link: Navigating to programs", category: .workout)
            case .dashboard, .mealsTab, .statsTab, .hydration, .stepTracker, .weightTracker,
                 .workoutHistory, .personalRecord, .streakInfo, .addFood,
                 .leagues, .readinessDetail, .smackTalk, .mealLogger:
                break  // Handled by ContentView (tab switch + scroll) / target tab views
            case .proRecap, .olympianPath:
                // 2026-05-04 — Path to 33 (`.olympianPath`) and `.proRecap`
                // are dashboard-tab destinations; ContentView switches the
                // tab and DashboardView pushes the route. The Workout tab
                // intentionally ignores them — DON'T clear `pendingDestination`
                // here or the dashboard tab will never see the deep link.
                break
            }
        }
        .onChange(of: workoutManager.shouldShowWorkoutGenerator) { _, shouldShow in
            // 🔧 Handle auto-gen redirect from Home tab
            if shouldShow {
                navigationPath.append("WorkoutGenerator")
                workoutManager.shouldShowWorkoutGenerator = false
            }
        }
        .onChange(of: workoutManager.shouldNavigateToPrograms) { _, shouldShow in
            // 🔧 Handle programs redirect from Home tab
            if shouldShow {
                navigationPath.append("PersonalizedPrograms")
                workoutManager.shouldNavigateToPrograms = false
            }
        }
        .onChange(of: workoutManager.shouldNavigateToFindFriends) { _, shouldShow in
            // 🔧 Handle find friends redirect from Home tab (for challenges)
            if shouldShow {
                navigationPath.append("FriendsSearch")
                workoutManager.shouldNavigateToFindFriends = false
            }
        }
        .onChange(of: workoutManager.shouldClearWorkoutTabNav) { _, shouldClear in
            if shouldClear {
                navigationPath = NavigationPath()
            }
        }
        .onChange(of: workoutManager.isWorkoutActive) { _, isActive in
            if isActive {
                navigationPath = NavigationPath()
            }
        }
        .onChange(of: workoutManager.shouldNavigateToProgramOverview) { _, shouldNavigate in
            // 🔧 Navigate to Program Overview from Dashboard
            if shouldNavigate {
                navigationPath = NavigationPath()  // Clear first
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(0.1))
                    guard !Task.isCancelled else { return }
                    navigationPath.append("SmartProgramOverview")
                    workoutManager.shouldNavigateToProgramOverview = false
                }
            }
        }
        .onChange(of: workoutManager.shouldNavigateToProgramDay) { _, shouldNavigate in
            // 🔧 Navigate to Program Day from Dashboard
            if shouldNavigate {
                navigationPath = NavigationPath()  // Clear first
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(0.1))
                    guard !Task.isCancelled else { return }
                    navigationPath.append("SmartProgramDay")
                    workoutManager.shouldNavigateToProgramDay = false
                }
            }
        }
    }
    
    // MARK: - Navigation Destination Helper
    // Extracted to reduce body complexity for compiler
    @ViewBuilder
    private func navigationDestinationView(for destination: String) -> some View {
        switch destination {
        case "WorkoutGenerator":
            WorkoutGeneratorSelectionView()
        case "GeneratedPrograms":
            GeneratedProgramsListView()
        case "ProgramLibrary":
            CloudProgramLibraryView()
        case "ProgramExplorer":
            ProgramExplorerView()
        case "PersonalizedPrograms":
            PersonalizedProgramsView()
        case "CloudProgramSchedule":
            CloudProgramScheduleView()
        case "CustomWorkout":
            CustomWorkoutBuilderView()
        case "FavoriteRoutines":
            FavoriteRoutinesView()
        case "OutdoorRun":
            RunningWorkoutView()
        case "CardioLanding":
            // Cardio Redesign Phase 1 — pushed detail (NOT sheet, per
            // user request 2026-05-02). `CardioLandingView` no longer
            // wraps its own `NavigationStack` — this case relies on the
            // outer `WorkoutTabView` navigation stack to host it.
            CardioLandingView()
                .environmentObject(userManager)
        case "SmartProgramOverview":
            if let program = workoutManager.navigateProgramData {
                SmartProgramOverviewView(
                    program: program,
                    template: workoutManager.navigateProgramTemplate
                )
                .environmentObject(workoutManager)
                .environmentObject(userManager)
            }
        case "SmartProgramDay":
            if let program = workoutManager.navigateProgramData,
               let day = workoutManager.navigateProgramDay {
                SmartProgramDayPreviewView(
                    program: program,
                    day: day,
                    programName: program.personalizedName,
                    totalDays: program.generatedDays.count
                )
                .environmentObject(workoutManager)
                .environmentObject(userManager)
            }
        case "WorkoutHistory":
            WorkoutHistoryFullView()
        case "SmartWorkoutPreview":
            if let program = GeneratedProgramService.shared.activeProgram,
               let day = GeneratedProgramService.shared.currentDay {
                SmartWorkoutPreviewView(day: day, program: program)
                    .environmentObject(GeneratedProgramService.shared)
            }
        case "ReceivedWorkouts":
            ReceivedWorkoutsView()
        case "FriendsList":
            FriendsListView()
        case "FriendRequests":
            FriendsListView(initialTab: 1)  // Navigate directly to Requests tab
        case "FriendsSearch":
            FriendsListView(initialTab: 2)  // Navigate directly to Search tab (for adding friends)
        case "CommunityChallenges":
            CommunityChallengesHubView()
                .environmentObject(userManager)
        case "SmartWorkoutPreview":
            if let day = GeneratedProgramService.shared.currentDay,
               let program = GeneratedProgramService.shared.activeProgram {
                SmartWorkoutPreviewView(day: day, program: program)
                    .environmentObject(GeneratedProgramService.shared)
            }
        case "WorkoutHistory":
            WorkoutHistoryFullView()
        default:
            if destination.hasPrefix("ProgramDetail:") {
                let programId = String(destination.dropFirst("ProgramDetail:".count))
                CloudProgramDetailView(programId: programId)
            } else {
                EmptyView()
            }
        }
    }
}

// MARK: - Recent Activity item (Workout tab)
//
// Parallel to `DashboardView.RecentWorkoutItem` but scoped to this
// file so the workout-tab recent-activity section can wrap both a
// `Workout` (Core Data strength row) and a `CardioWorkoutDTO` in a
// single `ForEach`. `enrichment` mirrors the wearable-overlap
// `CardioWorkoutDTO` that `WorkoutWearableMerger` attaches to a
// strength row (WHOOP / Apple Watch / Oura / Fitbit / Garmin) so
// `RecentWorkoutCard` can render the origin chip.
enum RecentActivityItem: Identifiable {
    case strength(Workout, isMostRecent: Bool, enrichment: CardioWorkoutDTO?)
    case cardio(CardioWorkoutDTO, isMostRecent: Bool)

    var id: String {
        switch self {
        case .strength(let w, _, _):
            return "strength-\(w.objectID.uriRepresentation().absoluteString)"
        case .cardio(let c, _):
            return "cardio-\(c.id)"
        }
    }

    var date: Date {
        switch self {
        case .strength(let w, _, _):
            return w.date ?? Date.distantPast
        case .cardio(let c, _):
            return ISO8601Parser.parse(c.completedAt, fallback: Date.distantPast)
        }
    }
}

struct WorkoutHomeView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.scrollToTopTrigger) private var scrollToTopTrigger
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var userManager: UserManager
    @Binding var navigationPath: NavigationPath
    @Binding var showingStretchModeOverlay: Bool
    // Workout Home shows recent stats; 200 is well beyond any UI surface that
    // reads this (carousel, counters). Per QP invariant #3.
    @FetchRequest(fetchRequest: {
        let request: NSFetchRequest<Workout> = Workout.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Workout.date, ascending: false)]
        request.predicate = NSPredicate(format: "isCompleted == YES")
        request.fetchLimit = 200
        return request
    }(), animation: .none)
    private var workouts: FetchedResults<Workout>
    @State private var forceRenderID = UUID()
    @State private var isNavigating = false  // 🔧 Debounce protection
    @State private var showingEquipmentConnection = false
    @ObservedObject private var cloudProgramService = CloudProgramService.shared
    @ObservedObject private var generatedProgramService = GeneratedProgramService.shared
    
    private let smartProgramEngine = SmartProgramEngine.shared
    @AppStorage("showRecommendedWidget") private var showRecommendedWidget = true
    
    // Cardio workouts for combined goal tracking (includes Strava activities)
    @State private var cardioWorkoutsThisWeek: [CardioWorkoutDTO] = []

    // ⚡️ SCROLL PERF (2026-05-04): `getRecommendedProgram()` calls
    // `SmartProgramRecommender.shared.getSuggestedProgram(for: user)`, which
    // synchronously scores all ~10 `WorkoutProgram` entries on the main thread.
    // It USED to be invoked inline from `programRecommendationCard`'s body, so
    // every body re-eval (navigation push/pop, state flip, even ActiveWorkoutView
    // overlay state changes — `WorkoutTabView` is the parent) re-ran the full
    // scoring pass. The trace showed `SmartProgramRecommender` analyzing the
    // catalog 20+ times per scroll session.
    //
    // We now cache the result in `@State` and refresh it ONLY on:
    //   - first appear
    //   - userManager.currentUser identity change
    //   - userManager.currentUser.equipment / goal / experience change (the
    //     inputs the recommender actually consults)
    // Per QUALITY_PERFORMANCE_AGENT invariant #30 — "expensive computed
    // properties read from a SwiftUI body must be cached in `@State`".
    @State private var cachedRecommendedProgram: SuggestedProgram?

    // Snappiness Overhaul Phase 6 — first-render telemetry.
    //
    // `phase6FirstAppearStart` is captured at @State default-init time, which
    // SwiftUI evaluates exactly once per WorkoutHomeView struct lifetime
    // (preserved across re-renders, recomputed on full re-mount). The
    // delta from this timestamp to the moment `.onAppear` fires on the
    // ScrollView approximates the body-construction + initial-layout cost.
    // `phase6DidLogFirstRender` guards single-shot logging — a tab
    // re-visit re-fires `.onAppear` but doesn't re-init @State.
    @State private var phase6FirstAppearStart: CFTimeInterval = CACurrentMediaTime()
    @State private var phase6DidLogFirstRender: Bool = false

    private var topFadeOverlay: some View {
        VStack(spacing: 0) {
            let fadeColor = colorScheme == .dark
                ? Color(red: 0.06, green: 0.06, blue: 0.06)
                : Color.white
            fadeColor.frame(height: 30)
            LinearGradient(
                stops: [
                    .init(color: fadeColor, location: 0),
                    .init(color: fadeColor.opacity(0.6), location: 0.4),
                    .init(color: fadeColor.opacity(0), location: 1.0)
                ],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 50)
            .allowsHitTesting(false)
            Spacer()
        }
        .ignoresSafeArea(.all, edges: .top)
    }
    
    var body: some View {
        ZStack {
        // Pinned title row + scroll share one full-screen orb (scroll no
        // longer owns the background alone — avoids a dark band above).
        AnimatedOrbBackground.workout(colorScheme: colorScheme)
            .accessibilityHidden(true)

        VStack(spacing: 0) {
            PinnedTabHeader {
                customWorkoutHeaderView
            }

            ScrollViewReader { scrollProxy in
            ScrollView(.vertical) {
                Color.clear.frame(height: 0).id("top")

                // IA (2026-05-08): Nutrition-parity quick tiles — Custom +
                // Auto, then Favorites / Cardio / Stretch — each
                // `MealQuickActionTile` (140pt, same as Meal Planner /
                // Import Recipe on Nutrition). Programs widget follows.
                VStack(spacing: Spacing.md) {
                    // 1–2. Quick actions (same tile spec as `MealsQuickActionsView`)
                    workoutMealStyleQuickActions
                        .id(forceRenderID)

                    // 3. Programs widget — full-width. Active program
                    // day preview OR recommendation card if user has
                    // no active program.
                    if PerfFlags.phase1BodyChurn {
                        programsWidget
                            .task(id: userManager.currentUser?.id) {
                                refreshCachedRecommendedProgram()
                            }
                    } else {
                        programsWidget
                    }

                    // 4. Recent Activity — mirrors DashboardView's
                    // `recentWorkoutsSection` (prefix 3 + "View All").
                    recentActivitySection

                    // 5. Next Up — single highest-priority `NextGoal`
                    // from `generateNextGoals()`. Self-hides when empty.
                    nextUpCard

                    // 6. My Stats Dashboard (chart wall) — owned by QP.
                    //
                    // Snappiness Overhaul Phase 6 (`perf_phase6_workout_tab_render`):
                    // wrap in a 500ms-deferred mount so the initial
                    // tab-transition frame does NOT pay the cost of
                    // instantiating 12 chart widgets (`WorkoutStatsView.swift:94`
                    // explicitly uses non-lazy `VStack` so children evaluate
                    // their `body` even off-screen). Off-screen, below the
                    // fold, deferral is visually imperceptible. When the flag
                    // is OFF this falls back to the inline mount — byte-identical
                    // to pre-Phase-6 behavior.
                    if PerfFlags.phase6WorkoutTabRender {
                        Phase6DeferredWorkoutStatsSection()
                    } else {
                        WorkoutStatsSection()
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, Spacing.lg)
            }
            .scrollContentBackground(.hidden)
            .onAppear {
                forceRenderID = UUID()
                // Populate the recommended-program cache so the
                // `programRecommendationCard` body never has to call
                // `SmartProgramRecommender` synchronously. See the cache
                // invariant on `cachedRecommendedProgram`.
                if cachedRecommendedProgram == nil {
                    refreshCachedRecommendedProgram()
                }
                // Phase 6 telemetry — measure body-construction → first-appear.
                // Always emits (independent of flag) so a single build can be
                // compared with the flag flipped via UserDefaults override.
                logPhase6FirstRenderIfNeeded()
            }
            .onChange(of: userManager.currentUser?.id) { _, _ in
                // User switched (login/logout or profile swap) — recompute the
                // program recommendation off the new user's profile.
                refreshCachedRecommendedProgram()
            }
            .task {
                // Sprint 2026-04-24: defer non-critical fetch past the tab-transition
                // animation frame. 1.38 (53) session logs showed `[CARDIO] Fetched 50
                // workouts` landing mid-transition → 1352ms slow transition observed
                // (Nutrition→Workout). The 250ms delay is past the SwiftUI tab-switch
                // default animation curve (~200ms), so the decode + @Published publish
                // lands after the GPU commits the new tab content. QP invariant #19
                // "tab switch handlers are minimal".
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled else { return }
                await loadCardioWorkoutsThisWeek()
            }
            .contentMargins(.top, 0, for: .scrollContent)
            .onChange(of: scrollToTopTrigger) { _, _ in
                scrollProxy.scrollTo("top", anchor: .top)
            }
        }
        }   // closes VStack(spacing: 0) — pinned-header wrapper
        .padding(.top, TabPinnedChrome.rootTopPullUp)
        }
        .scrollDismissesKeyboard(.immediately)
        .onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .sheet(isPresented: $showingEquipmentConnection) {
            FitnessEquipmentView()
        }
    }
    
    // MARK: - Custom Header View
    //
    // Pinned title row + 1-line sub-brief, matches the Dashboard/Friends
    // header rhythm. Title uses the canonical Workout-tab gradient
    // (white → green) from `FriendsTabView` for tab parity.
    private var customWorkoutHeaderView: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            HStack(alignment: .center) {
                Text("Workout")
                    .font(.ds_displayLarge)
                    .italic()
                    .foregroundStyle(
                        LinearGradient(
                            stops: [
                                .init(color: .white, location: 0.0),
                                .init(color: .white, location: 0.68),
                                .init(color: Color.green, location: 0.82),
                                .init(color: Color(red: 0.4, green: 0.95, blue: 0.5), location: 1.0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .shadow(color: Color.green.opacity(0.2), radius: 4, x: 0, y: 1)
                    .frame(height: 55)

                Spacer()

                if WorkoutManager.shared.isWorkoutActive {
                    Text(WorkoutManager.shared.formattedDuration)
                        .font(.ds_labelMedium.monospacedDigit())
                        .foregroundColor(.secondary)
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, Spacing.xxs)
                        .background(
                            Capsule()
                                .fill(.ultraThinMaterial)
                        )
                }
            }

            Text(headerSubBriefCopy)
                .font(.ds_bodyMedium)
                .foregroundColor(.adaptiveSecondaryText)
                .padding(.leading, Spacing.xxs)
        }
        .padding(.horizontal, Spacing.xxs)
    }

    /// One-line coaching sub-brief under the page title. Mirrors the
    /// Dashboard's "WELCOME BACK" secondary-line pattern so the two tabs
    /// share visual rhythm. Copy adapts to user state (active workout,
    /// already trained today, general morning/evening nudge) — the tab
    /// feels alive instead of static.
    private var headerSubBriefCopy: String {
        if WorkoutManager.shared.isWorkoutActive {
            return "Locked in — finish strong."
        }
        if calculateWorkoutsToday() > 0 {
            return "Great work today. Tomorrow's you is watching."
        }
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 11 { return "Start the day strong." }
        if hour < 17 { return "Let's get after it." }
        return "One more session before bed?"
    }

    
    // MARK: - Quick actions (Nutrition-parity `MealQuickActionTile`)
    //
    // 2026-05-08: Row 1 uses `DashboardStyleWorkoutQuickStartTile` — exact
    // home-tab Custom + Auto (blue/cyan + purple/pink, subtitles). Row 2
    // uses `MealQuickActionTile` (140pt, same height) for Favorites /
    // Cardio / Stretch with caption subtexts where set.
    private var workoutMealStyleQuickActions: some View {
        VStack(spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                DashboardStyleWorkoutQuickStartTile(
                    title: "Custom Workout",
                    subtitle: "Build your own",
                    icon: "plus.circle.fill",
                    circleGradient: [Color.blue, Color.cyan],
                    cardGlowBase: .blue,
                    borderGradient: [Color.blue, Color.cyan],
                    outerGlowColor: .blue,
                    outerGlowOpacityDark: 0.2,
                    outerGlowOpacityLight: 0.12,
                    accessibilityLabelText: "Start custom workout",
                    accessibilityHintText: "Build your own workout from scratch",
                    action: {
                        guard !isNavigating else { return }
                        isNavigating = true
                        Task { @MainActor in try? await Task.sleep(for: .seconds(0.5)); isNavigating = false }

                        WorkoutManager.shared.shouldNavigateToHomeTab = false

                        SessionLogManager.shared.logTap("Custom Workout", screen: .workoutTab, element: .dashboardCustomButton)
                        SessionLogManager.shared.beginTransition(to: .customWorkoutBuilder, action: "custom_workout_tap")
                        navigationPath.append("CustomWorkout")
                    }
                )

                DashboardStyleWorkoutQuickStartTile(
                    title: "Auto Workout",
                    subtitle: "Auto-generated routine",
                    icon: "dumbbell.fill",
                    circleGradient: [Color.purple, Color.pink],
                    cardGlowBase: .purple,
                    borderGradient: [Color.purple, Color.pink],
                    outerGlowColor: .purple,
                    outerGlowOpacityDark: 0.12,
                    outerGlowOpacityLight: 0.12,
                    accessibilityLabelText: "Start auto workout",
                    accessibilityHintText: "Generate a workout based on your history",
                    action: {
                        guard !isNavigating else { return }
                        isNavigating = true
                        Task { @MainActor in try? await Task.sleep(for: .seconds(0.5)); isNavigating = false }

                        WorkoutManager.shared.shouldNavigateToHomeTab = false

                        SessionLogManager.shared.logTap("Auto Workout", screen: .workoutTab, element: .dashboardAutoGenButton)
                        SessionLogManager.shared.beginTransition(to: .workoutGenerator, action: "auto_workout_tap")
                        navigationPath.append("WorkoutGenerator")
                    }
                )
            }

            HStack(spacing: Spacing.sm) {
                MealQuickActionTile(
                    icon: "star.fill",
                    title: "Favorites",
                    subtitle: "Saved workouts",
                    gradient: [Color.orange, Color.yellow],
                    action: {
                        guard !isNavigating else { return }
                        isNavigating = true
                        Task { @MainActor in try? await Task.sleep(for: .seconds(0.5)); isNavigating = false }

                        navigationPath.append("FavoriteRoutines")
                    }
                )

                MealQuickActionTile(
                    icon: "figure.run",
                    title: "Cardio",
                    subtitle: "Walking, Running",
                    gradient: [Color.cyan, Color(red: 0.40, green: 0.80, blue: 0.98)],
                    action: {
                        guard !isNavigating else { return }
                        isNavigating = true
                        Task { @MainActor in try? await Task.sleep(for: .seconds(0.5)); isNavigating = false }

                        navigationPath.append("CardioLanding")
                    }
                )

                MealQuickActionTile(
                    icon: "figure.flexibility",
                    title: "Stretch",
                    subtitle: "Move your body",
                    gradient: [Color.mint, Color(red: 0.50, green: 0.92, blue: 0.70)],
                    action: {
                        guard !isNavigating else { return }
                        isNavigating = true
                        Task { @MainActor in try? await Task.sleep(for: .seconds(0.5)); isNavigating = false }

                        withAnimation(.easeInOut(duration: 0.3)) {
                            showingStretchModeOverlay = true
                        }
                    }
                )
            }
        }
    }

    private var personalizedPrograms: [PersonalizedProgram] {
        smartProgramEngine.getPersonalizedPrograms(for: userManager.currentUser)
    }
    
    private var activeSmartProgramForWidget: SmartActiveProgram? {
        smartProgramEngine.userPrograms
            .filter { !$0.isCompleted }
            .sorted { $0.startDate > $1.startDate }
            .first
    }
    
    // MARK: - Programs Widget
    //
    // Full-width slot below the Nutrition-parity quick tiles (layout
    // 2026-05-08): Custom + Auto, then Favorites / Cardio / Stretch,
    // then this widget.
    //
    //   State A — active program, today not done → day name + muscle
    //             targets + Start CTA (existing ping-pong via
    //             `WorkoutManager.shouldNavigateToProgramDay`).
    //   State B — active program, today done     → Great work + Next
    //             day preview CTA.
    //   State C — no active program                → program
    //             recommendation card driven by
    //             `SmartProgramRecommender.shared.getSuggestedProgram`,
    //             tap → PersonalizedPrograms.
    @ViewBuilder
    private var programsWidget: some View {
        if let activeProgram = activeSmartProgramForWidget {
            activeSmartProgramDetailWidget(program: activeProgram)
        } else {
            programRecommendationCard
        }
    }

    /// State C — no active program. Full-width recommendation card
    /// surfaced by `SmartProgramRecommender`. Hero medallion +
    /// recommended program name + description + stat chips
    /// (days/week + duration + difficulty). Tap anywhere (chevron hint)
    /// routes to the Programs list; the specific recommendation is a
    /// preview — users pick from the full library there.
    private var programRecommendationCard: some View {
        let suggested = getRecommendedProgram()
        let accent = suggested.primaryColor

        return Button {
            guard !isNavigating else { return }
            isNavigating = true
            Task { @MainActor in try? await Task.sleep(for: .seconds(0.5)); isNavigating = false }

            HapticManager.impact(.light)
            SessionLogManager.shared.logTap("Program Recommendation", screen: .workoutTab)
            SessionLogManager.shared.beginTransition(to: .programsList, action: "program_recommendation_tap")
            navigationPath.append("PersonalizedPrograms")
        } label: {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(alignment: .center, spacing: Spacing.sm) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [suggested.primaryColor, suggested.secondaryColor],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 48, height: 48)
                            .shadow(color: accent.opacity(0.35), radius: 8, x: 0, y: 4)

                        Image(systemName: suggested.icon)
                            .font(.ds_heading3)
                            .foregroundColor(.white)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Recommended for you")
                            .font(.ds_labelSmall)
                            .foregroundColor(.adaptiveSecondaryText)
                            .tracking(1)

                        Text(suggested.title)
                            .font(.ds_heading3)
                            .foregroundColor(.adaptiveText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.ds_labelMedium)
                        .foregroundColor(.adaptiveSecondaryText)
                }

                Text(suggested.description)
                    .font(.ds_bodySmall)
                    .foregroundColor(.adaptiveSecondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: Spacing.xs) {
                    recommendationStatChip(
                        icon: "calendar",
                        label: suggested.workoutsPerWeek,
                        color: accent
                    )
                    .frame(maxWidth: .infinity)
                    recommendationStatChip(
                        icon: "clock.fill",
                        label: suggested.duration,
                        color: accent
                    )
                    .frame(maxWidth: .infinity)
                    recommendationStatChip(
                        icon: "chart.line.uptrend.xyaxis",
                        label: suggested.difficulty,
                        color: accent
                    )
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(Spacing.md)
        }
        .buttonStyle(PlainButtonStyle())
        .adaptiveSleekCard(cornerRadius: CornerRadius.xl, accentColor: accent)
    }

    private func recommendationStatChip(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: Spacing.xxs) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(label)
                .font(.ds_labelSmall)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(minWidth: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
        .foregroundColor(color)
        .padding(.vertical, 4)
    }
    
    private func activeSmartProgramDetailWidget(program: SmartActiveProgram) -> some View {
        let programColor = Color.green
        let template = personalizedPrograms.first { $0.template.id == program.templateId }?.template
        let completedDays = program.completedDays.count
        let totalDays = template?.totalDays ?? program.generatedDays.count
        let totalWeeks = (totalDays + 6) / 7
        let currentWeek = (program.currentDay - 1) / max(1, template?.daysPerWeek ?? 4) + 1
        let progress = totalDays > 0 ? Double(completedDays) / Double(totalDays) * 100 : 0
        
        let currentDay = program.generatedDays.first { $0.dayNumber == program.currentDay }
        let isTodayCompleted = currentDay?.isCompleted ?? false
        let nextDay = program.generatedDays.first { !$0.isCompleted && $0.dayNumber > program.currentDay }
        let dayToShow = isTodayCompleted ? nextDay : currentDay
        
        return VStack(spacing: 0) {
            Button {
                WorkoutManager.shared.navigateProgramData = program
                WorkoutManager.shared.navigateProgramTemplate = template
                WorkoutManager.shared.shouldNavigateToProgramOverview = true
            } label: {
                HStack(alignment: .center, spacing: 10) {
                    ZStack {
                        Circle()
                            .stroke(Color.gray.opacity(0.2), lineWidth: 4)
                            .frame(width: 44, height: 44)
                        
                        Circle()
                            .trim(from: 0, to: progress / 100)
                            .stroke(
                                LinearGradient(
                                    colors: [programColor, programColor.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                style: StrokeStyle(lineWidth: 4, lineCap: .round)
                            )
                            .frame(width: 44, height: 44)
                            .rotationEffect(.degrees(-90))
                        
                        Text("\(Int(progress))%")
                            .font(.ds_caption)
                            .foregroundColor(programColor)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(template?.baseName ?? "Training Program")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        HStack(spacing: 6) {
                            Text("Week \(currentWeek)/\(totalWeeks)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            Text("•")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            Text("\(completedDays)/\(totalDays) days")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(programColor)
                        }
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.ds_labelMedium)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, Spacing.sm)
            }
            .buttonStyle(PlainButtonStyle())
            
            if isTodayCompleted {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.ds_heading1)
                        .foregroundColor(.green)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Great work!")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        
                        if let next = nextDay {
                            Text("Next up: \(next.name)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("You're all caught up!")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    if let next = nextDay {
                        Button {
                            WorkoutManager.shared.navigateProgramData = program
                            WorkoutManager.shared.navigateProgramDay = next
                            WorkoutManager.shared.shouldNavigateToProgramDay = true
                        } label: {
                            Text("Preview")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(programColor)
                                .padding(.horizontal, Spacing.sm)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .stroke(programColor.opacity(0.5), lineWidth: 1)
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.md)
                        .fill(Color.green.opacity(colorScheme == .dark ? 0.08 : 0.06))
                )
                .padding(.horizontal, Spacing.sm)
                .padding(.bottom, 12)
            } else if let day = dayToShow {
                Button {
                    WorkoutManager.shared.navigateProgramData = program
                    WorkoutManager.shared.navigateProgramDay = day
                    WorkoutManager.shared.shouldNavigateToProgramDay = true
                } label: {
                    HStack(spacing: 0) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(programColor)
                            .frame(width: 4)
                            .padding(.vertical, Spacing.xxs)
                        
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(day.name)
                                        .font(.subheadline)
                                        .fontWeight(.bold)
                                        .foregroundColor(.primary)
                                    
                                    Text("Day \(day.dayNumber)")
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                        .foregroundColor(programColor)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(
                                            Capsule()
                                                .fill(programColor.opacity(0.15))
                                        )
                                }
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(day.exercises.count) exercises")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    let muscleTargets = getMuscleTargets(for: day.exercises)
                                    if !muscleTargets.isEmpty {
                                        Text(muscleTargets)
                                            .font(.caption2)
                                            .foregroundColor(.secondary.opacity(0.8))
                                            .lineLimit(2)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                            
                            Spacer()
                            
                            HStack(spacing: 4) {
                                Image(systemName: "play.fill")
                                    .font(.ds_caption)
                                Text("Start")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [programColor.opacity(0.9), programColor.opacity(0.7)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                            )
                        }
                        .padding(.leading, 12)
                        .padding(.trailing, 14)
                    }
                    .padding(.vertical, Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.md)
                            .fill(colorScheme == .dark
                                ? Color.white.opacity(0.04)
                                : Color.black.opacity(0.03))
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, Spacing.sm)
                .padding(.bottom, 12)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "trophy.fill")
                        .font(.ds_heading1)
                        .foregroundColor(.yellow)
                    
                    Text("Program Complete! 🎉")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text("Congratulations on finishing your program!")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(20)
            }
        }
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 26)
                    .stroke(programColor.opacity(isTodayCompleted ? 0 : 0.3), lineWidth: 2)
                    .blur(radius: 6)
                
                RoundedRectangle(cornerRadius: CornerRadius.xl)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color(white: 0.16), Color(white: 0.10)]
                                : [Color.white, Color(white: 0.98)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                RoundedRectangle(cornerRadius: CornerRadius.xl)
                    .stroke(
                        LinearGradient(
                            colors: isTodayCompleted
                                ? [Color.gray.opacity(0.15), Color.gray.opacity(0.05), Color.clear]
                                : [programColor.opacity(0.35), programColor.opacity(0.15), Color.clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            }
        )
        .shadow(color: programColor.opacity(colorScheme == .dark ? 0.25 : 0.18), radius: 16, x: 0, y: 4)
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.2 : 0.06), radius: 8, x: 0, y: 3)
    }
    
    private func getMuscleTargets(for exercises: [SmartProgramExercise]) -> String {
        let exerciseLibrary = ExerciseLibraryService.shared
        var muscleGroups: [String: Int] = [:]
        
        for exercise in exercises {
            if let libraryExercise = exerciseLibrary.getExercise(byName: exercise.exerciseName) {
                if let muscles = libraryExercise.muscleGroups as? [String], let primary = muscles.first {
                    muscleGroups[primary, default: 0] += 1
                }
            } else {
                let nameLower = exercise.exerciseName.lowercased()
                if nameLower.contains("chest") || nameLower.contains("bench") || nameLower.contains("fly") {
                    muscleGroups["Chest", default: 0] += 1
                } else if nameLower.contains("back") || nameLower.contains("row") || nameLower.contains("lat") || nameLower.contains("pull") {
                    muscleGroups["Back", default: 0] += 1
                } else if nameLower.contains("shoulder") || nameLower.contains("delt") || nameLower.contains("press") {
                    muscleGroups["Shoulders", default: 0] += 1
                } else if nameLower.contains("bicep") || nameLower.contains("curl") || nameLower.contains("tricep") {
                    muscleGroups["Arms", default: 0] += 1
                } else if nameLower.contains("leg") || nameLower.contains("squat") || nameLower.contains("quad") || nameLower.contains("hamstring") || nameLower.contains("glute") {
                    muscleGroups["Legs", default: 0] += 1
                } else if nameLower.contains("core") || nameLower.contains("ab") || nameLower.contains("plank") {
                    muscleGroups["Core", default: 0] += 1
                }
            }
        }
        
        let sorted = muscleGroups.sorted {
            if $0.value != $1.value { return $0.value > $1.value }
            return $0.key < $1.key
        }
        let topMuscles = sorted.prefix(3).map { $0.key }
        
        return topMuscles.joined(separator: ", ")
    }
    
    // MARK: - Next Goals Section (Revamped "Almost There!")
    private var nextGoalsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your Next Goals")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Tap to take action")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "target")
                    .foregroundStyle(
                        LinearGradient(colors: [.orange, .yellow], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .font(.title3)
            }
            .padding(.horizontal, Spacing.xxs)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    let goals = generateNextGoals()
                    if goals.isEmpty {
                        EmptyNextGoalsCard()
                    } else {
                        ForEach(goals) { goal in
                            NextGoalCard(goal: goal) { action in
                                handleGoalAction(action)
                            }
                        }
                    }
                }
                .padding(.horizontal, Spacing.xxs)
                .padding(.vertical, Spacing.xxs)
            }
        }
    }
    
    // Handle goal card tap actions
    private func handleGoalAction(_ action: GoalAction) {
        // 🔧 Debounce: Prevent double-taps
        guard !isNavigating else { return }
        
        switch action {
        case .startWorkout(let focus):
            isNavigating = true
            Task { @MainActor in try? await Task.sleep(for: .seconds(0.5)); isNavigating = false }
            // Navigate to workout generator with optional muscle focus
            navigationPath.append("WorkoutGenerator")
        case .viewAchievements, .viewProgress:
            // Could navigate to a dedicated achievements/progress view
            // For now, this is informational
            break
        case .none:
            break
        }
    }
    
    // MARK: - Goal Generation
    private func generateNextGoals() -> [NextGoal] {
        var goals: [NextGoal] = []
        
        let totalWorkouts = Int(userManager.currentUser?.totalWorkouts ?? 0)
        let currentStreak = Int(userManager.currentUser?.currentStreak ?? 0)
        let longestStreak = Int(userManager.currentUser?.longestStreak ?? 0)
        let userLevel = userManager.getLevel()
        let userXP = Int(userManager.currentUser?.xp ?? 0)
        let workoutsThisWeek = calculateWorkoutsThisWeek()
        let workoutsToday = calculateWorkoutsToday()
        
        // Calculate workout stats
        let heaviestWeight = calculateHeaviestWeight()
        
        // 1. DAILY CHALLENGE - Workout today (if haven't already)
        if workoutsToday == 0 {
            goals.append(NextGoal(
                id: "daily_workout",
                type: .dailyChallenge,
                title: "Daily Workout",
                subtitle: "Complete a workout today",
                icon: "sun.max.fill",
                progress: 0.0,
                remaining: "1 workout to go",
                timeContext: "today",
                accentColor: .orange,
                action: .startWorkout(focus: nil),
                priority: 1,
                xpReward: 50
            ))
        }
        
        // 2. WEEKLY CHALLENGE - Hit weekly target
        let weeklyTarget = 4 // Aim for 4 workouts per week
        if workoutsThisWeek < weeklyTarget {
            let remaining = weeklyTarget - workoutsThisWeek
            goals.append(NextGoal(
                id: "weekly_target",
                type: .weeklyChallenge,
                title: "Weekly Target",
                subtitle: "Hit your weekly goal",
                icon: "calendar.badge.checkmark",
                progress: Double(workoutsThisWeek) / Double(weeklyTarget),
                remaining: "\(remaining) more workout\(remaining == 1 ? "" : "s")",
                timeContext: "this week",
                accentColor: .blue,
                action: .startWorkout(focus: nil),
                priority: 2,
                xpReward: 100
            ))
        }
        
        // 3. STREAK MAINTENANCE - Keep the streak alive
        if currentStreak > 0 && workoutsToday == 0 {
            goals.append(NextGoal(
                id: "streak_maintain",
                type: .streakMaintain,
                title: "Keep the Fire!\(currentStreak >= 7 ? " 🔥" : "")",
                subtitle: "\(currentStreak)-day streak active",
                icon: "flame.fill",
                progress: min(0.9, Double(currentStreak) / 30.0), // Visual progress toward 30-day goal
                remaining: "Workout today to continue",
                timeContext: nil,
                accentColor: currentStreak >= 7 ? .red : .orange,
                action: .startWorkout(focus: nil),
                priority: 0, // Highest priority if streak is at risk
                xpReward: currentStreak >= 7 ? 75 : 25
            ))
        }
        
        // 4. WORKOUT MILESTONE - Next workout count achievement
        let workoutMilestones = [5, 10, 25, 50, 75, 100, 150, 200, 250, 300, 500, 750, 1000]
        if let nextMilestone = workoutMilestones.first(where: { $0 > totalWorkouts }) {
            let remaining = nextMilestone - totalWorkouts
            let progress = Double(totalWorkouts) / Double(nextMilestone)
            
            if progress >= 0.5 { // Only show if at least 50% there
                goals.append(NextGoal(
                    id: "workout_milestone_\(nextMilestone)",
                    type: .achievement,
                    title: getMilestoneTitle(nextMilestone),
                    subtitle: "Complete \(nextMilestone) workouts",
                    icon: getWorkoutMilestoneIcon(nextMilestone),
                    progress: progress,
                    remaining: "\(remaining) workout\(remaining == 1 ? "" : "s") to go",
                    timeContext: nil,
                    accentColor: getMilestoneColor(nextMilestone),
                    action: .startWorkout(focus: nil),
                    priority: 5,
                    xpReward: nextMilestone >= 100 ? 500 : (nextMilestone >= 50 ? 250 : 100)
                ))
            }
        }
        
        // 5. STREAK MILESTONE - Next streak achievement
        let streakMilestones = [7, 14, 21, 30, 60, 90, 180, 365]
        let activeStreak = max(currentStreak, longestStreak)
        if let nextStreakMilestone = streakMilestones.first(where: { $0 > currentStreak }) {
            let progress = Double(currentStreak) / Double(nextStreakMilestone)
            
            if progress >= 0.4 && currentStreak > 0 { // Only show if at least 40% there
                let remaining = nextStreakMilestone - currentStreak
                goals.append(NextGoal(
                    id: "streak_milestone_\(nextStreakMilestone)",
                    type: .achievement,
                    title: getStreakMilestoneTitle(nextStreakMilestone),
                    subtitle: "Reach a \(nextStreakMilestone)-day streak",
                    icon: "flame.fill",
                    progress: progress,
                    remaining: "\(remaining) day\(remaining == 1 ? "" : "s") remaining",
                    timeContext: nil,
                    accentColor: .red,
                    action: .startWorkout(focus: nil),
                    priority: 4,
                    xpReward: nextStreakMilestone >= 30 ? 300 : 150
                ))
            }
        }
        
        // 6. PROMOTION ZONE — points toward the next league tier (League
        //    Redesign Plan §B1 / §A2). Replaces the legacy "Level N+1 Awaits!"
        //    XP-based nudge. Source-of-truth: `WeeklyLeagueService.shared.standing`.
        //    Reads the singleton directly because `getNextGoals` is a synchronous
        //    pure function on a snapshot — adding an @ObservedObject would force
        //    the entire workout tab to recompute on every league poll.
        if let standing = WeeklyLeagueService.shared.standing,
           standing.promotionCount > 0,
           !standing.isInPromotionZone {
            // Top-of-promotion-zone points = points held by the rank just
            // above the cutoff. We need to BEAT that to enter the zone, so
            // "remaining" reflects the actual required gap.
            let cutoffRank = standing.promotionCount
            let cutoffEntry = standing.leaderboard.first(where: { $0.rank == cutoffRank })
            let pointsToBeat = (cutoffEntry?.points ?? standing.myPoints) + 1
            let pointsNeeded = max(1, pointsToBeat - standing.myPoints)
            let progress = standing.myPoints == 0
                ? 0.0
                : min(1.0, Double(standing.myPoints) / Double(pointsToBeat))

            // Only show once the user is at least 60% of the way there —
            // matches the discoverability bar the legacy Level-Up nudge used.
            if progress >= 0.6 {
                let nextTierName = standing.nextTierName ?? "the next tier"
                goals.append(NextGoal(
                    id: "promotion_zone",
                    type: .levelUp,
                    title: "Promotion Zone",
                    subtitle: "Climb into \(nextTierName)",
                    icon: "arrow.up.circle.fill",
                    progress: progress,
                    remaining: "\(pointsNeeded) pts to advance",
                    timeContext: nil,
                    accentColor: standing.tierSwiftUIColor,
                    action: .startWorkout(focus: nil),
                    priority: 6,
                    xpReward: nil
                ))
            }
        }

        
        // 7. WEIGHT MILESTONE - Next lifting achievement (if lifting heavy)
        if heaviestWeight > 50 {
            let weightMilestones = [100, 135, 185, 225, 275, 315, 365, 405, 495, 500]
            if let nextWeightMilestone = weightMilestones.first(where: { Double($0) > heaviestWeight }) {
                let progress = heaviestWeight / Double(nextWeightMilestone)
                
                if progress >= 0.7 { // Only show if 70%+ there
                    let remaining = Double(nextWeightMilestone) - heaviestWeight
                    goals.append(NextGoal(
                        id: "weight_milestone_\(nextWeightMilestone)",
                        type: .personalRecord,
                        title: getWeightMilestoneTitle(nextWeightMilestone),
                        subtitle: "Lift \(nextWeightMilestone) lbs",
                        icon: "scalemass.fill",
                        progress: progress,
                        remaining: "\(Int(remaining)) lbs to go",
                        timeContext: nil,
                        accentColor: .green,
                        action: .startWorkout(focus: nil),
                        priority: 7,
                        xpReward: 200
                    ))
                }
            }
        }
        
        // Sort by priority and limit to 5 goals
        return goals.sorted { $0.priority < $1.priority }.prefix(5).map { $0 }
    }
    
    // MARK: - Goal Helper Functions
    
    /// Load cardio workouts (including Strava activities) for this week
    private func loadCardioWorkoutsThisWeek() async {
        do {
            let cardioWorkouts = try await SupabaseManager.shared.fetchRecentCardioWorkouts(limit: 50)
            await MainActor.run {
                self.cardioWorkoutsThisWeek = cardioWorkouts
            }
        } catch is CancellationError {
            // Tab switch (Workout → Friends, etc.) cancelled the
            // in-flight cardio_workouts query. Bug-intel was
            // mis-classifying these as real warnings — same
            // CancellationError / URLError.cancelled drain we already
            // applied to ContactsService + PrivateChallengeService chat.
            AppLogger.debug("[GOALS] loadCardioWorkoutsThisWeek cancelled (tab switch)", category: .workout)
        } catch {
            if (error as NSError).domain == NSURLErrorDomain && (error as NSError).code == NSURLErrorCancelled {
                AppLogger.debug("[GOALS] cardio_workouts request cancelled (URLSession)", category: .workout)
                return
            }
            AppLogger.warning("⚠️ [GOALS] Failed to load cardio workouts: \(error)", category: .workout)
        }
    }
    
    /// Calculate total workouts this week (strength + cardio/Strava)
    private func calculateWorkoutsThisWeek() -> Int {
        let calendar = Calendar.current
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date()))!
        
        // Count strength workouts
        let strengthCount = workouts.filter { ($0.date ?? Date.distantPast) >= startOfWeek }.count
        
        // Count cardio workouts (includes Strava activities)
        let cardioCount = cardioWorkoutsThisWeek.filter {
            ISO8601Parser.parse($0.completedAt, fallback: Date.distantPast) >= startOfWeek
        }.count
        
        return strengthCount + cardioCount
    }
    
    /// Calculate total workouts today (strength + cardio/Strava)
    private func calculateWorkoutsToday() -> Int {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        
        // Count strength workouts
        let strengthCount = workouts.filter { ($0.date ?? Date.distantPast) >= startOfDay }.count
        
        // Count cardio workouts (includes Strava activities)
        let cardioCount = cardioWorkoutsThisWeek.filter {
            ISO8601Parser.parse($0.completedAt, fallback: Date.distantPast) >= startOfDay
        }.count
        
        return strengthCount + cardioCount
    }
    
    private func getMilestoneTitle(_ count: Int) -> String {
        switch count {
        case 5: return "Getting Started"
        case 10: return "Double Digits"
        case 25: return "Quarter Century"
        case 50: return "Half Century"
        case 75: return "Going Strong"
        case 100: return "Century Club"
        case 150: return "Dedicated"
        case 200: return "Committed"
        case 250: return "Iron Will"
        case 300: return "Legend Status"
        case 500: return "Elite Athlete"
        case 750: return "Gym Warrior"
        case 1000: return "Thousand Strong"
        default: return "\(count) Workouts"
        }
    }
    
    private func getWorkoutMilestoneIcon(_ count: Int) -> String {
        switch count {
        case 1...10: return "figure.walk"
        case 11...50: return "figure.run"
        case 51...100: return "figure.strengthtraining.traditional"
        case 101...250: return "medal.fill"
        case 251...500: return "trophy.fill"
        default: return "crown.fill"
        }
    }
    
    private func getMilestoneColor(_ count: Int) -> Color {
        switch count {
        case 1...10: return .blue
        case 11...50: return .green
        case 51...100: return .orange
        case 101...250: return .purple
        case 251...500: return .red
        default: return .yellow
        }
    }
    
    private func getStreakMilestoneTitle(_ days: Int) -> String {
        switch days {
        case 7: return "One Week Warrior"
        case 14: return "Two Week Titan"
        case 21: return "Three Week Hero"
        case 30: return "Monthly Master"
        case 60: return "Two Month Legend"
        case 90: return "Quarterly Champion"
        case 180: return "Half Year Hero"
        case 365: return "Year of Iron"
        default: return "\(days)-Day Streak"
        }
    }
    
    private func getWeightMilestoneTitle(_ weight: Int) -> String {
        switch weight {
        case 100: return "Century Lift"
        case 135: return "One Plate Club"
        case 185: return "Rising Power"
        case 225: return "Two Plate Club"
        case 275: return "Getting Heavy"
        case 315: return "Three Plate Club"
        case 365: return "Power Lifter"
        case 405: return "Four Plate Club"
        case 495: return "Almost 500"
        case 500: return "Half Ton Hero"
        default: return "\(weight) lbs"
        }
    }
    
    // MARK: - Recent Activity
    //
    // Mirrors DashboardView+Activity.swift `recentWorkoutsSection`
    // exactly so the two tabs share visual DNA (Lead Designer north
    // star: "If your screen doesn't feel like the Dashboard, it's
    // wrong."). Top 3 combined strength + cardio rows (WHOOP / Apple
    // Watch / Oura overlap-dedup via `WorkoutWearableMerger`, matching
    // the dashboard) + "View All" chevron into the full history page.
    //
    // Self-hides when there are zero strength + cardio rows — empty
    // placeholders clutter the tab surface for brand-new users who are
    // staring at a fresh Quick Actions grid directly above this.
    @ViewBuilder
    private var recentActivitySection: some View {
        let combined = combinedRecentForTab
        if !combined.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(alignment: .center, spacing: Spacing.xs) {
                    Image(systemName: "clock.fill")
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .font(.ds_heading3)
                    Text("Recent Activity")
                        .font(.ds_heading2)
                        .foregroundColor(.adaptiveText)

                    Spacer()

                    NavigationLink(value: "WorkoutHistory") {
                        HStack(spacing: 4) {
                            Text("View All")
                                .font(.ds_labelMedium)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundColor(.blue)
                    }
                }

                VStack(spacing: Spacing.sm) {
                    ForEach(combined, id: \.id) { item in
                        switch item {
                        case .strength(let workout, let isMostRecent, let enrichment):
                            RecentWorkoutCard(
                                workout: workout,
                                isMostRecent: isMostRecent,
                                wearableEnrichment: enrichment
                            )
                        case .cardio(let cardioWorkout, let isMostRecent):
                            RecentCardioWorkoutCard(
                                cardioWorkout: cardioWorkout,
                                isMostRecent: isMostRecent
                            )
                        }
                    }
                }
            }
        }
    }

    /// Top 3 combined strength + cardio rows for the tab's Recent
    /// Activity section. Uses `WorkoutWearableMerger` (same helper the
    /// Home tab uses in `DashboardView.rebuildCombinedWorkouts`) so
    /// wearable-origin strength cardio that overlaps a Fit33 strength
    /// session doesn't double-appear. Strength `isMostRecent` lights
    /// the top-of-list card's accent outline — matches the dashboard's
    /// signature "this is fresh" treatment.
    private var combinedRecentForTab: [RecentActivityItem] {
        let strengthList = Array(workouts.prefix(5))
        let merged = WorkoutWearableMerger.merge(
            strength: strengthList,
            cardio: cardioWorkoutsThisWeek
        )

        var items: [RecentActivityItem] = []
        for workout in strengthList {
            let enrichment = workout.id.flatMap { merged.enrichmentByWorkoutID[$0] }
            items.append(.strength(workout, isMostRecent: false, enrichment: enrichment))
        }
        for cardio in merged.filteredCardio {
            items.append(.cardio(cardio, isMostRecent: false))
        }

        items.sort { lhs, rhs in lhs.date > rhs.date }

        if !items.isEmpty {
            switch items[0] {
            case .strength(let w, _, let e):
                items[0] = .strength(w, isMostRecent: true, enrichment: e)
            case .cardio(let c, _):
                items[0] = .cardio(c, isMostRecent: true)
            }
        }

        return Array(items.prefix(3))
    }

    // MARK: - Next Up Card
    //
    // Single full-width sleek card rendering the highest-priority
    // `NextGoal` from `generateNextGoals()`. The goal engine already
    // surfaces 7 goal types (daily/weekly challenge, streak maintain,
    // PR close, muscle balance, level up, weight milestone) sorted by
    // priority — we pick the top one and render it as a "here's the
    // single thing to chase next" card. Self-hides when the engine
    // returns no goals.
    //
    // Gated on `!WorkoutManager.shared.isWorkoutActive` so the card
    // doesn't surface during active workouts (distracts from the
    // timer/exercises overlay).
    @ViewBuilder
    private var nextUpCard: some View {
        if !WorkoutManager.shared.isWorkoutActive,
           let top = generateNextGoals().first {
            WorkoutTabNextUpCard(goal: top) { action in
                handleGoalAction(action)
            }
        }
    }
    
    // Get the glow color based on the most recent workout's muscle group (kept for card content)
    private var recentActivityGlowColor: Color {
        guard let mostRecentWorkout = workouts.first else {
            return .blue // Default fallback
        }
        
        // Get exercises from most recent workout
        let exercises = mostRecentWorkout.exercises?.allObjects as? [WorkoutExercise] ?? []
        let muscles = exercises.compactMap { ($0.exercise?.muscleGroups as? [String])?.first?.lowercased() }
        let primaryMuscle = muscles.first ?? ""
        
        switch primaryMuscle {
        case "chest": return .red
        case "back": return .blue
        case "legs", "quads", "hamstrings", "glutes": return .green
        case "shoulders": return .orange
        case "biceps", "triceps", "arms": return .purple
        case "core", "abs": return .yellow
        default:
            // Fallback to time-based color
            let hour = Calendar.current.component(.hour, from: mostRecentWorkout.date ?? Date())
            if hour >= 5 && hour < 12 {
                return .orange
            } else if hour >= 12 && hour < 17 {
                return .blue
            } else {
                return .purple
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func getRecommendedProgram() -> SuggestedProgram {
        // Snappiness Overhaul Phase 1.1 (flag `perf_phase1_body_churn`):
        // when the flag is ON, this function MUST be a pure read — no
        // `@State` writes from inside `body`. Cache population is owned by
        // the `.task(id: userManager.currentUser?.id)` modifier on
        // `programsWidget` (see body) which calls
        // `refreshCachedRecommendedProgram()`. On the first frame before
        // `.task` fires, we still compute on-the-fly so the card renders
        // a real recommendation — we just don't write back.
        if PerfFlags.phase1BodyChurn {
            if let cached = cachedRecommendedProgram { return cached }
            guard let user = userManager.currentUser else {
                return getDefaultProgram()
            }
            return SmartProgramRecommender.shared.getSuggestedProgram(for: user)
        }
        // Original behavior — preserved byte-for-byte when flag is OFF.
        // Read from the `@State` cache first so a body re-eval is just a load,
        // not a full SmartProgramRecommender scoring pass. The cache is
        // populated/refreshed by `refreshCachedRecommendedProgram()` from
        // `.onAppear` and (currently) on user identity changes — see the
        // declaration of `cachedRecommendedProgram` for the cache invariant.
        if let cached = cachedRecommendedProgram { return cached }
        guard let user = userManager.currentUser else {
            let fallback = getDefaultProgram()
            cachedRecommendedProgram = fallback
            return fallback
        }
        let computed = SmartProgramRecommender.shared.getSuggestedProgram(for: user)
        cachedRecommendedProgram = computed
        return computed
    }

    /// Phase 6 telemetry — emit `perf.signpost.workout_tab.first_render_ms`
    /// once per WorkoutHomeView lifecycle. Captures the elapsed
    /// `CACurrentMediaTime()` between @State default-init (struct birth,
    /// before `body` runs) and the first `.onAppear` firing on the
    /// ScrollView. Both endpoints are well-defined SwiftUI hooks; the
    /// reading approximates body-build + initial-layout. Single-shot via
    /// `phase6DidLogFirstRender`.
    private func logPhase6FirstRenderIfNeeded() {
        guard !phase6DidLogFirstRender else { return }
        phase6DidLogFirstRender = true
        let elapsedMs = (CACurrentMediaTime() - phase6FirstAppearStart) * 1000
        AppLogger.info(
            "perf.signpost.workout_tab.first_render_ms=\(Int(elapsedMs)) flag=\(PerfFlags.phase6WorkoutTabRender ? "on" : "off")",
            category: .performance
        )
    }

    /// Forces a fresh `SmartProgramRecommender` scoring pass and writes the
    /// result back into `cachedRecommendedProgram`. Call from `.onAppear` and
    /// from `.onChange` of any input the recommender consumes (equipment,
    /// goal, experience). NEVER call from a view body — the recommender
    /// scores ~10 programs and emits several AppLogger entries per call.
    private func refreshCachedRecommendedProgram() {
        guard let user = userManager.currentUser else {
            cachedRecommendedProgram = getDefaultProgram()
            return
        }
        cachedRecommendedProgram = SmartProgramRecommender.shared.getSuggestedProgram(for: user)
    }
    
    private func getDefaultProgram() -> SuggestedProgram {
        SuggestedProgram(
            title: "Total Fitness Starter",
            description: "Well-rounded program for overall health and fitness. Start your journey here.",
            duration: "6 weeks",
            workoutsPerWeek: "3 days/week",
            focusAreas: ["Full Body", "Functional Fitness", "Habit Building"],
            difficulty: "Beginner",
            primaryColor: .green,
            secondaryColor: .mint,
            icon: "figure.cooldown",
            callToAction: "Start Journey"
        )
    }
    
    private func daysSince(_ date: Date) -> Int {
        Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
    }
    
    // MARK: - Statistics Calculation Helpers
    
    private func calculateHeaviestWeight() -> Double {
        return workouts.reduce(0.0) { maxWeight, workout in
            guard let exercises = workout.exercises?.allObjects as? [WorkoutExercise] else { return maxWeight }
            let workoutMax = exercises.reduce(0.0) { exerciseMax, exercise in
                guard let sets = exercise.sets?.allObjects as? [WorkoutSet] else { return exerciseMax }
                let exerciseMaxWeight = sets.map { $0.weight }.max() ?? 0
                return max(exerciseMax, exerciseMaxWeight)
            }
            return max(maxWeight, workoutMax)
        }
    }
    
    private func calculateHighestReps() -> Int {
        return workouts.reduce(0) { maxReps, workout in
            guard let exercises = workout.exercises?.allObjects as? [WorkoutExercise] else { return maxReps }
            let workoutMax = exercises.reduce(0) { exerciseMax, exercise in
                guard let sets = exercise.sets?.allObjects as? [WorkoutSet] else { return exerciseMax }
                let exerciseMaxReps = sets.map { Int($0.reps) }.max() ?? 0
                return max(exerciseMax, exerciseMaxReps)
            }
            return max(maxReps, workoutMax)
        }
    }
    
    private func calculateLongestWorkoutMinutes() -> Int {
        return workouts.map { Int($0.duration / 60) }.max() ?? 0
    }
    
    private func calculateMostSetsInWorkout() -> Int {
        return workouts.reduce(0) { maxSets, workout in
            guard let exercises = workout.exercises?.allObjects as? [WorkoutExercise] else { return maxSets }
            let workoutSets = exercises.reduce(0) { total, exercise in
                guard let sets = exercise.sets?.allObjects as? [WorkoutSet] else { return total }
                return total + sets.count
            }
            return max(maxSets, workoutSets)
        }
    }
    
    private func calculateWorkoutsThisMonth() -> Int {
        let calendar = Calendar.current
        let now = Date()
        let startOfMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now
        
        return workouts.filter { workout in
            guard let date = workout.date else { return false }
            return date >= startOfMonth
        }.count
    }
}

// MARK: - Supporting Data Structures

struct SuggestedProgram {
    let title: String
    let description: String
    let duration: String
    let workoutsPerWeek: String
    let focusAreas: [String]
    let difficulty: String
    let primaryColor: Color
    let secondaryColor: Color
    let icon: String
    let callToAction: String
}

struct NearAchievement {
    let id: String
    let title: String
    let description: String
    let progress: Double
    let icon: String
    let color: Color
}

// MARK: - Card Components

struct QuickActionCard: View {
    @Environment(\.colorScheme) private var colorScheme
    
    let title: String
    let subtitle: String
    let icon: String
    let gradient: [Color]
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            HapticManager.impact(.medium)
            action()
        }) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: gradient),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 50, height: 50)
                        .shadow(color: gradient.first?.opacity(0.3) ?? .clear, radius: 5, x: 0, y: 3)
                    
                    Image(systemName: icon)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                }
                
                VStack(spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 140)
            .background(Color.cardBackground)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .fill(Color.cardBackground)
                    .shadow(color: colorScheme == .dark ? .clear : .black.opacity(0.1), radius: 5, x: 0, y: 2)
            )
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.white.opacity(0.01), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Depth Quick Action Card (with 3D effect)
//
// Categorical quick-action tile (design-system sanctioned third
// variant per DESIGN_AGENT §Card System: primary = `.sleekCard()`,
// list-row = `Color.cardBackground`, tile-of-actions = this). Two
// sizes:
//
//   - Default (hero 2-up): 140pt tall, 50pt icon circle, title +
//     subtitle. Daily-driver entry points (Custom + Auto Workout).
//   - Compact (`compact: true`): 88pt tall, 38pt icon circle, title
//     only (subtitle ignored). Secondary paths — Programs /
//     Favorites / Cardio / Stretch — so they read as "alternative
//     paths," not as peers of the hero pair.
struct DepthQuickActionCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let subtitle: String?
    let icon: String
    let gradient: [Color]
    var compact: Bool = false
    let action: () -> Void

    // Backwards-compat convenience (pre-refresh callers passed
    // non-optional subtitle + no compact flag).
    init(
        title: String,
        subtitle: String,
        icon: String,
        gradient: [Color],
        compact: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.gradient = gradient
        self.compact = compact
        self.action = action
    }

    // New call-style used by the refreshed secondary-actions strip
    // where subtitle is intentionally omitted.
    init(
        title: String,
        subtitle: String?,
        icon: String,
        gradient: [Color],
        compact: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.gradient = gradient
        self.compact = compact
        self.action = action
    }

    private var iconCircleSize: CGFloat { compact ? 38 : 50 }
    private var iconFont: Font { compact ? .ds_labelLarge : .ds_heading3 }
    private var cardMinHeight: CGFloat { compact ? 88 : 140 }
    private var titleFont: Font { compact ? .ds_labelMedium : .ds_heading3 }
    private var innerSpacing: CGFloat { compact ? Spacing.xxs : Spacing.sm }

    var body: some View {
        Button(action: {
            HapticManager.impact(.medium)
            action()
        }) {
            VStack(spacing: innerSpacing) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: gradient),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: iconCircleSize, height: iconCircleSize)
                        .shadow(color: gradient.first?.opacity(0.4) ?? .clear, radius: 8, x: 0, y: 4)

                    Image(systemName: icon)
                        .font(iconFont)
                        .foregroundColor(.white)
                }

                VStack(spacing: Spacing.xxs) {
                    Text(title)
                        .font(titleFont)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                        .lineLimit(compact ? 1 : 2)
                        .minimumScaleFactor(0.8)

                    if let subtitle = subtitle, !compact {
                        Text(subtitle)
                            .font(.ds_bodySmall)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .padding(.vertical, compact ? Spacing.xs : 0)
            .frame(maxWidth: .infinity, minHeight: cardMinHeight)
            .background(
                ZStack {
                    // Bottom shadow layer (deepest) - colored based on gradient
                    RoundedRectangle(cornerRadius: CornerRadius.xl + 4, style: .continuous)
                        .fill((gradient.first ?? .gray).opacity(colorScheme == .dark ? 0.15 : 0.08))
                        .offset(y: 8)
                        .blur(radius: 4)

                    // Middle shadow layer
                    RoundedRectangle(cornerRadius: CornerRadius.xl + 2, style: .continuous)
                        .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                        .offset(y: 4)

                    // Main card background — adaptive (frosted ↔ solid via setting)
                    AdaptiveCardSurface(cornerRadius: CornerRadius.xl)

                    // Inner highlight (top edge glow)
                    RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: colorScheme == .dark
                                    ? [Color.white.opacity(0.1), Color.white.opacity(0.02), Color.clear]
                                    : [Color.white, Color.white.opacity(0.5), Color.clear],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1.5
                        )

                    // Colored accent border
                    RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    (gradient.first ?? .gray).opacity(colorScheme == .dark ? 0.4 : 0.3),
                                    (gradient.last ?? .gray).opacity(colorScheme == .dark ? 0.3 : 0.2)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 12, x: 0, y: 6)
            .shadow(color: (gradient.first ?? .gray).opacity(colorScheme == .dark ? 0.2 : 0.12), radius: 20, x: 0, y: 10)
        }
        .scaleButtonStyle(.standard, withHaptic: true)
    }
}

struct ProgramSuggestionCard: View {
    let program: SuggestedProgram
    let userGoal: String
    let userLevel: String
    let action: () -> Void
    
    var body: some View {
        Button(action: { HapticManager.impact(.light); action() }) {
            VStack(alignment: .leading, spacing: 20) {
                // Header with gradient badge
                HStack(alignment: .top, spacing: 16) {
                    // Program icon with gradient
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [program.primaryColor, program.secondaryColor]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 60, height: 60)
                            .shadow(color: program.primaryColor.opacity(0.4), radius: 8, x: 0, y: 4)
                        
                        Image(systemName: program.icon)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        // "Matched for you" badge
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption)
                            Text("Perfect Match")
                                .font(.caption)
                                .fontWeight(.bold)
                        }
                        .foregroundColor(program.primaryColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, Spacing.xxs)
                        .background(program.primaryColor.opacity(0.12))
                        .cornerRadius(CornerRadius.md)
                        
                        Text(program.title)
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                            .lineLimit(2)
                    }
                    
                    Spacer()
                }
                
                // Description
                Text(program.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                
                // Focus areas
                VStack(alignment: .leading, spacing: 8) {
                    Text("Program Focus")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    
                    HStack(spacing: 8) {
                        ForEach(program.focusAreas.prefix(3), id: \.self) { focus in
                            Text(focus)
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(program.primaryColor.opacity(0.1))
                                .foregroundColor(program.primaryColor)
                                .cornerRadius(CornerRadius.sm)
                        }
                    }
                }
                
                // Program details row
                HStack(spacing: 20) {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.caption)
                            .foregroundColor(program.primaryColor)
                        Text(program.duration)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                    }
                    
                    HStack(spacing: 6) {
                        Image(systemName: "dumbbell.fill")
                            .font(.caption)
                            .foregroundColor(program.primaryColor)
                        Text(program.workoutsPerWeek)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                    }
                    
                    Spacer()
                    
                    // Difficulty badge
                    Text(program.difficulty)
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, Spacing.xxs)
                        .background(program.secondaryColor.opacity(0.15))
                        .foregroundColor(program.secondaryColor)
                        .cornerRadius(CornerRadius.sm)
                }
                
                // Prominent CTA Button
                HStack {
                    Spacer()
                    
                    HStack(spacing: 8) {
                        Text(program.callToAction)
                            .font(.headline)
                            .fontWeight(.bold)
                        
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.title3)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [program.primaryColor, program.secondaryColor]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(CornerRadius.lg)
                    .shadow(color: program.primaryColor.opacity(0.3), radius: 8, x: 0, y: 4)
                    
                    Spacer()
                }
            }
            .padding(Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [program.primaryColor.opacity(0.3), program.secondaryColor.opacity(0.3)]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                    )
                    .shadow(color: program.primaryColor.opacity(0.15), radius: 15, x: 0, y: 8)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct NearAchievementCard: View {
    @Environment(\.colorScheme) private var colorScheme
    
    let title: String
    let description: String
    let progress: Double
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 12) {
            // Icon and progress
            ZStack {
                Circle()
                    .stroke(color.opacity(0.2), lineWidth: 4)
                    .frame(width: 60, height: 60)
                
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 60, height: 60)
                    .rotationEffect(.degrees(-90))
                
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(color)
            }
            
            VStack(spacing: 4) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(color)
            }
        }
        .padding(Spacing.md)
        .frame(width: 140)
        .background(Color.cardBackground)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .fill(Color.cardBackground)
                .shadow(color: colorScheme == .dark ? .clear : .black.opacity(0.1), radius: 5, x: 0, y: 2)
        )
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.white.opacity(0.01), lineWidth: 1)
        )
    }
}

struct WorkoutTabRecentCard: View {
    @Environment(\.colorScheme) private var colorScheme
    
    let workout: Workout
    
    var body: some View {
        HStack(spacing: 16) {
            // Workout icon
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.1))
                    .frame(width: 50, height: 50)
                
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.green)
            }
            
            // Workout details
            VStack(alignment: .leading, spacing: 4) {
                Text(workout.name ?? "Workout")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                HStack(spacing: 12) {
                    if let date = workout.date {
                        Text(formatDate(date))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    if workout.duration > 0 {
                        Text("• \(formatDuration(Int(workout.duration)))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // XP earned
            VStack(spacing: 2) {
                Text("+\(Int(workout.xpEarned))")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
                
                Text("XP")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        }
        .padding(Spacing.md)
        .background(Color.cardBackground)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .fill(Color.cardBackground)
                .shadow(color: colorScheme == .dark ? .clear : .black.opacity(0.05), radius: 3, x: 0, y: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.white.opacity(0.01), lineWidth: 1)
        )
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    private func formatDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes)m"
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return "\(hours)h \(remainingMinutes)m"
        }
    }
}

struct EmptyRecentActivityCard: View {
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 40))
                .foregroundColor(.gray.opacity(0.6))
            
            VStack(spacing: 8) {
                Text("No Recent Activity")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text("Complete your first workout to see your activity here!")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(Spacing.xl)
        .background(Color.cardBackground)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .fill(Color.cardBackground)
                .shadow(color: colorScheme == .dark ? .clear : .black.opacity(0.05), radius: 3, x: 0, y: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.white.opacity(0.01), lineWidth: 1)
        )
    }
}

// MARK: - Next Goals System

enum GoalType {
    case achievement      // Based on achievement progress
    case dailyChallenge   // Complete X workouts today
    case weeklyChallenge  // Complete X workouts this week
    case streakMaintain   // Keep your streak going
    case personalRecord   // Close to a PR
    case muscleBalance    // Train a neglected muscle group
    case levelUp          // Close to leveling up
}

enum GoalAction {
    case startWorkout(focus: String?)  // Start a workout, optionally focused on muscle/type
    case viewAchievements              // Go to achievements page
    case viewProgress                  // Go to progress page
    case none                          // No action, just informational
}

struct NextGoal: Identifiable {
    let id: String
    let type: GoalType
    let title: String
    let subtitle: String        // What you need to do
    let icon: String
    let progress: Double        // 0.0 - 1.0
    let remaining: String       // e.g., "2 more workouts", "15 lbs to go"
    let timeContext: String?    // e.g., "this week", "today", nil
    let accentColor: Color
    let action: GoalAction
    let priority: Int           // Lower = higher priority
    let xpReward: Int?          // Optional XP reward for completion
}

struct NextGoalCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let goal: NextGoal
    let onAction: (GoalAction) -> Void
    
    private var gradientColors: [Color] {
        switch goal.accentColor {
        case .orange: return [.orange, .yellow]
        case .blue: return [.blue, .cyan]
        case .green: return [.green, .teal]
        case .purple: return [.purple, .pink]
        case .red: return [.red, .orange]
        case .yellow: return [.yellow, .orange]
        case .pink: return [.pink, .purple]
        case .mint: return [.mint, .teal]
        case .cyan: return [.cyan, .blue]
        default: return [goal.accentColor, goal.accentColor.opacity(0.7)]
        }
    }
    
    private var typeIcon: String {
        switch goal.type {
        case .dailyChallenge: return "sun.max.fill"
        case .weeklyChallenge: return "calendar.badge.clock"
        case .streakMaintain: return "flame.fill"
        case .personalRecord: return "trophy.fill"
        case .muscleBalance: return "figure.strengthtraining.traditional"
        case .levelUp: return "arrow.up.circle.fill"
        case .achievement: return goal.icon
        }
    }
    
    var body: some View {
        Button(action: { HapticManager.impact(.light); onAction(goal.action) }) {
            VStack(spacing: 10) {
                // Icon with progress ring
                ZStack {
                    Circle()
                        .stroke(goal.accentColor.opacity(0.15), lineWidth: 4)
                        .frame(width: 44, height: 44)
                    
                    Circle()
                        .trim(from: 0, to: goal.progress)
                        .stroke(
                            LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .frame(width: 44, height: 44)
                        .rotationEffect(.degrees(-90))
                    
                    Image(systemName: goal.icon)
                        .font(.ds_labelLarge)
                        .foregroundStyle(
                            LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                }
                
                // Title & subtitle
                VStack(spacing: 3) {
                    Text(goal.title)
                        .font(.ds_bodySmall).fontWeight(.bold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    
                    Text(goal.remaining)
                        .font(.ds_labelSmall)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .multilineTextAlignment(.center)
                
                // XP badge or progress
                if let xp = goal.xpReward {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                        Text("+\(xp) XP")
                            .font(.ds_caption)
                    }
                    .foregroundColor(gradientColors[0])
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, Spacing.xxs)
                    .background(
                        Capsule()
                            .fill(gradientColors[0].opacity(0.15))
                    )
                } else {
                    Text("\(Int(goal.progress * 100))%")
                        .font(.ds_caption)
                        .foregroundStyle(
                            LinearGradient(colors: gradientColors, startPoint: .leading, endPoint: .trailing)
                        )
                }
            }
            .frame(width: 160, height: 140)
            .background(
                ZStack {
                    // Bottom shadow layer (deepest) - colored based on gradient
                    RoundedRectangle(cornerRadius: 20)
                        .fill(gradientColors[0].opacity(colorScheme == .dark ? 0.15 : 0.08))
                        .offset(y: 8)
                        .blur(radius: 4)
                    
                    // Middle shadow layer
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                        .offset(y: 4)
                    
                    // Main card background with gradient
                    RoundedRectangle(cornerRadius: CornerRadius.lg)
                        .fill(
                            LinearGradient(
                                colors: colorScheme == .dark 
                                    ? [Color.darkCardBackground, Color.darkSurface]
                                    : [Color.white, Color.white.opacity(0.95)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    
                    // Inner highlight (top edge glow)
                    RoundedRectangle(cornerRadius: CornerRadius.lg)
                        .stroke(
                            LinearGradient(
                                colors: colorScheme == .dark 
                                    ? [Color.white.opacity(0.1), Color.white.opacity(0.02), Color.clear]
                                    : [Color.white, Color.white.opacity(0.5), Color.clear],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1.5
                        )
                    
                    // Colored accent border
                    RoundedRectangle(cornerRadius: CornerRadius.lg)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    gradientColors[0].opacity(colorScheme == .dark ? 0.4 : 0.3),
                                    gradientColors[1].opacity(colorScheme == .dark ? 0.3 : 0.2)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 12, x: 0, y: 6)
            .shadow(color: gradientColors[0].opacity(colorScheme == .dark ? 0.2 : 0.12), radius: 20, x: 0, y: 10)
        }
        .scaleButtonStyle(.standard, withHaptic: true)
    }
}

struct EmptyNextGoalsCard: View {
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(colors: [.green.opacity(0.2), .teal.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 44, height: 44)
                
                Image(systemName: "checkmark.seal.fill")
                    .font(.ds_heading2)
                    .foregroundStyle(
                        LinearGradient(colors: [.green, .teal], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
            }
            
            VStack(spacing: 3) {
                Text("All Done!")
                    .font(.ds_bodySmall).fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text("Goals complete")
                    .font(.ds_labelSmall)
                    .foregroundColor(.secondary)
            }
            .multilineTextAlignment(.center)
            
            // Celebratory badge
            HStack(spacing: 3) {
                Image(systemName: "star.fill")
                    .font(.system(size: 9))
                Text("Great job!")
                    .font(.ds_caption)
            }
            .foregroundColor(.green)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, Spacing.xxs)
            .background(
                Capsule()
                    .fill(Color.green.opacity(0.15))
            )
        }
        .frame(width: 160, height: 140)
        .background(
            ZStack {
                // Bottom shadow layer (deepest) - colored based on gradient
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.green.opacity(colorScheme == .dark ? 0.15 : 0.08))
                    .offset(y: 8)
                    .blur(radius: 4)
                
                // Middle shadow layer
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                    .offset(y: 4)
                
                // Main card background with gradient
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark 
                                ? [Color.darkCardBackground, Color.darkSurface]
                                : [Color.white, Color.white.opacity(0.95)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                // Inner highlight (top edge glow)
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .stroke(
                        LinearGradient(
                            colors: colorScheme == .dark 
                                ? [Color.white.opacity(0.1), Color.white.opacity(0.02), Color.clear]
                                : [Color.white, Color.white.opacity(0.5), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1.5
                    )
                
                // Colored accent border
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.green.opacity(colorScheme == .dark ? 0.4 : 0.3),
                                Color.teal.opacity(colorScheme == .dark ? 0.3 : 0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 12, x: 0, y: 6)
        .shadow(color: Color.green.opacity(colorScheme == .dark ? 0.2 : 0.12), radius: 20, x: 0, y: 10)
    }
}

// MARK: - Workout Tab Next Up Card
//
// Full-width single-goal card rendering the highest-priority
// `NextGoal` from `generateNextGoals()`. Previously the goal engine
// output was unused on-screen — this card wires it into the
// refreshed workout-tab IA as the "here's what to chase next" slot.
// Self-hides (caller guards) when no goals qualify.
//
// Visual treatment: `.adaptiveSleekCard(cornerRadius: .xl)` matches
// the canonical dashboard widget depth. Progress ring on the left
// doubles as the icon container; goal remaining + XP reward on the
// right. Tap triggers the goal's `GoalAction` through the parent's
// `handleGoalAction(_:)` (debounced by the parent's `isNavigating`).
struct WorkoutTabNextUpCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let goal: NextGoal
    let onAction: (GoalAction) -> Void

    private var gradientColors: [Color] {
        switch goal.accentColor {
        case .orange: return [.orange, .yellow]
        case .blue:   return [.blue, .cyan]
        case .green:  return [.green, .teal]
        case .purple: return [.purple, .pink]
        case .red:    return [.red, .orange]
        case .yellow: return [.yellow, .orange]
        case .pink:   return [.pink, .purple]
        case .mint:   return [.mint, .teal]
        case .cyan:   return [.cyan, .blue]
        default:      return [goal.accentColor, goal.accentColor.opacity(0.7)]
        }
    }

    var body: some View {
        Button {
            HapticManager.impact(.light)
            onAction(goal.action)
        } label: {
            HStack(alignment: .center, spacing: Spacing.sm) {
                progressRing

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Spacing.xxs) {
                        Text("Next up")
                            .font(.ds_labelSmall)
                            .foregroundColor(.adaptiveSecondaryText)
                            .tracking(1)

                        if let context = goal.timeContext {
                            Text("• \(context)")
                                .font(.ds_labelSmall)
                                .foregroundColor(.adaptiveSecondaryText)
                        }
                    }

                    Text(goal.title)
                        .font(.ds_heading3)
                        .foregroundColor(.adaptiveText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    Text(goal.remaining)
                        .font(.ds_bodySmall)
                        .foregroundColor(.adaptiveSecondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                trailingChip
            }
            .padding(Spacing.md)
        }
        .buttonStyle(PlainButtonStyle())
        .adaptiveSleekCard(cornerRadius: CornerRadius.xl, accentColor: goal.accentColor)
    }

    private var progressRing: some View {
        ZStack {
            Circle()
                .stroke(goal.accentColor.opacity(0.15), lineWidth: 4)
                .frame(width: 48, height: 48)

            Circle()
                .trim(from: 0, to: max(0.02, min(goal.progress, 1.0)))
                .stroke(
                    LinearGradient(
                        colors: gradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .frame(width: 48, height: 48)
                .rotationEffect(.degrees(-90))

            Image(systemName: goal.icon)
                .font(.ds_labelLarge)
                .foregroundStyle(
                    LinearGradient(
                        colors: gradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }

    @ViewBuilder
    private var trailingChip: some View {
        HStack(spacing: Spacing.xxs) {
            if let xp = goal.xpReward {
                Image(systemName: "star.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text("+\(xp) XP")
                    .font(.ds_labelMedium)
            } else {
                Text("\(Int(goal.progress * 100))%")
                    .font(.ds_labelMedium)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(
            LinearGradient(
                colors: gradientColors,
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(gradientColors[0].opacity(colorScheme == .dark ? 0.18 : 0.10))
        )
    }
}

// MARK: - Floating GO Button

struct FloatingGoButton: View {
    let action: () -> Void
    var primaryColor: Color = Color(red: 0.2, green: 0.7, blue: 0.3)
    var secondaryColor: Color = Color(red: 0.15, green: 0.55, blue: 0.85)
    var accessibilityText: String = "Start workout"
    
    @State private var isPressed = false
    @State private var pulseAnimation = false
    
    // Computed gradient colors
    private var gradientColors: [Color] {
        [primaryColor, secondaryColor]
    }
    
    private var glowColors: [Color] {
        [primaryColor.opacity(0.3), secondaryColor.opacity(0.2)]
    }
    
    var body: some View {
        Button(action: {
            // Haptic feedback
            let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
            impactFeedback.impactOccurred()
            
            // Execute provided action
            action()
        }) {
            ZStack {
                // Solid white background circle (largest - ensures nothing shows through)
                Circle()
                    .fill(Color.white)
                    .frame(width: 82, height: 82)
                    .scaleEffect(isPressed ? 0.9 : 1.0)
                
                // Main gradient button (fully opaque, on top of white)
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: gradientColors),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 78, height: 78)
                    .shadow(color: primaryColor.opacity(0.4), radius: isPressed ? 5 : 15, x: 0, y: isPressed ? 2 : 8)
                    .scaleEffect(isPressed ? 0.9 : 1.0)
                
                // GO! Text
                Text("GO!")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                    .scaleEffect(isPressed ? 0.9 : 1.0)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.easeInOut(duration: 0.1)) {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    withAnimation(.easeInOut(duration: 0.1)) {
                        isPressed = false
                    }
                }
        )
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Active Program Progress Card (Redesigned)
struct ActiveProgramProgressCard: View {
    @Environment(\.colorScheme) private var colorScheme
    
    let program: FullCloudProgram
    let progress: UserActiveProgram
    let totalWorkouts: Int
    let onTap: () -> Void
    
    @State private var animateProgress = false
    
    private var programColor: Color {
        program.program.programColor
    }
    
    private var completionPercentage: Double {
        let totalDays = program.program.durationDays
        let completedDays = progress.completedDays.count
        return totalDays > 0 ? Double(completedDays) / Double(totalDays) : 0
    }
    
    private var daysRemaining: Int {
        max(0, program.program.durationDays - progress.completedDays.count)
    }
    
    private var currentStreak: Int {
        var streak = 0
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        for i in (0..<7).reversed() {
            if let checkDate = calendar.date(byAdding: .day, value: -i, to: today) {
                let dayOfProgram = calendar.dateComponents([.day], from: calendar.startOfDay(for: dateFromString(progress.startDate) ?? Date()), to: checkDate).day ?? 0
                if progress.completedDays.contains(dayOfProgram + 1) {
                    streak += 1
                } else if i < 6 {
                    break
                }
            }
        }
        return max(streak, progress.completedDays.count > 0 ? 1 : 0)
    }
    
    private func dateFromString(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.date(from: string)
    }
    
    private var statusLabel: String {
        let percentage = completionPercentage * 100
        if percentage >= 90 { return "Final Push" }
        if percentage >= 75 { return "Almost There" }
        if percentage >= 50 { return "Halfway" }
        if percentage >= 25 { return "Building" }
        if percentage > 0 { return "Started" }
        return "Ready"
    }
    
    private var statusColor: Color {
        let percentage = completionPercentage * 100
        if percentage >= 75 { return .green }
        if percentage >= 50 { return .blue }
        if percentage >= 25 { return .orange }
        return programColor
    }
    
    var body: some View {
        cardContent
            .buttonStyle(UniversalScaleButtonStyle(scale: .standard, withHaptic: true))
            .onAppear {
                withAnimation(.easeOut(duration: 1.0).delay(0.2)) {
                    animateProgress = true
                }
            }
    }
    
    private var cardContent: some View {
        Button(action: { HapticManager.impact(.light); onTap() }) {
            VStack(spacing: 0) {
                // Top Section - Program Info & Progress Ring
                HStack(alignment: .top, spacing: 14) {
                    // Animated Progress Ring
                    ZStack {
                        // Track
                        Circle()
                            .stroke(Color.gray.opacity(0.15), lineWidth: 5)
                            .frame(width: 68, height: 68)
                        
                        // Progress
                        Circle()
                            .trim(from: 0, to: animateProgress ? completionPercentage : 0)
                            .stroke(
                                LinearGradient(colors: [programColor, programColor.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing),
                                style: StrokeStyle(lineWidth: 5, lineCap: .round)
                            )
                            .frame(width: 68, height: 68)
                            .rotationEffect(.degrees(-90))
                        
                        // Center percentage
                        VStack(spacing: -2) {
                            Text("\(Int(completionPercentage * 100))")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundColor(programColor)
                            Text("%")
                                .font(.ds_caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        // Status badge
                        HStack(spacing: 4) {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 6, height: 6)
                            Text(statusLabel)
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(statusColor)
                        
                        // Program name
                        Text(program.program.name)
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                            .lineLimit(2)
                        
                        // Day progress
                        Text("Day \(progress.currentDay) of \(program.program.durationDays)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                .padding(Spacing.md)
                
                // Thin divider
                Rectangle()
                    .fill(Color.gray.opacity(0.08))
                    .frame(height: 1)
                    .padding(.horizontal, Spacing.md)
                
                // Stats Grid - Clean 3-column layout
                HStack(spacing: 0) {
                    // Days Done
                    statCell(
                        value: "\(progress.completedDays.count)",
                        label: "Done",
                        icon: "checkmark.circle.fill",
                        color: .green
                    )
                    
                    // Vertical divider
                    Rectangle()
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 1, height: 44)
                    
                    // Streak
                    statCell(
                        value: "\(currentStreak)",
                        label: "Streak",
                        icon: "flame.fill",
                        color: .orange
                    )
                    
                    // Vertical divider
                    Rectangle()
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 1, height: 44)
                    
                    // Days Left
                    statCell(
                        value: "\(daysRemaining)",
                        label: "Left",
                        icon: "calendar",
                        color: .blue
                    )
                }
                .padding(.vertical, 14)
                
                // Continue Button - Clean CTA
                HStack(spacing: 8) {
                    Text("Continue Today's Workout")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(colors: [programColor, programColor.opacity(0.85)], startPoint: .leading, endPoint: .trailing)
                )
            }
            .background(Color.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg))
            .background(
                ZStack {
                    // Depth shadows
                    RoundedRectangle(cornerRadius: 20)
                        .fill(programColor.opacity(colorScheme == .dark ? 0.15 : 0.08))
                        .offset(y: 8)
                        .blur(radius: 4)
                    
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                        .offset(y: 4)
                    
                    RoundedRectangle(cornerRadius: CornerRadius.lg)
                        .fill(Color.cardBackground)
                    
                    // Inner highlight
                    RoundedRectangle(cornerRadius: CornerRadius.lg)
                        .stroke(
                            LinearGradient(
                                colors: colorScheme == .dark 
                                    ? [Color.white.opacity(0.1), Color.clear]
                                    : [Color.white, Color.clear],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                    
                    // Accent border
                    RoundedRectangle(cornerRadius: CornerRadius.lg)
                        .stroke(
                            LinearGradient(colors: [programColor.opacity(colorScheme == .dark ? 0.4 : 0.25), programColor.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 1
                        )
                }
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.06), radius: 12, x: 0, y: 6)
            .shadow(color: programColor.opacity(colorScheme == .dark ? 0.2 : 0.1), radius: 20, x: 0, y: 10)
        }
    }
    
    // Clean stat cell component
    private func statCell(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.ds_labelSmall)
                    .foregroundColor(color)
                Text(value)
                    .font(.ds_statSmall)
                    .foregroundColor(.primary)
            }
            Text(label)
                .font(.ds_caption)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Progress Stat Item
struct ProgressStatItem: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.ds_bodySmall)
                    .foregroundColor(color)
                Text(value)
                    .font(.ds_statSmall)
                    .foregroundColor(.primary)
            }
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Smart Insights Card
struct SmartInsightsCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let workouts: [Workout]
    let todayExercises: [String]
    let onViewProgram: () -> Void
    @ObservedObject private var cloudProgramService = CloudProgramService.shared
    
    // MARK: - Muscle Recovery Analysis
    private var muscleLastWorked: [String: Date] {
        var lastWorked: [String: Date] = [:]
        
        for workout in workouts {
            guard let date = workout.date,
                  let exercises = workout.exercises?.allObjects as? [WorkoutExercise] else { continue }
            
            for workoutExercise in exercises {
                // Use safeMuscleGroups for nil-safety
                for muscle in workoutExercise.safeMuscleGroups {
                    if lastWorked[muscle] == nil || date > lastWorked[muscle]! {
                        lastWorked[muscle] = date
                    }
                }
            }
        }
        return lastWorked
    }
    
    private var muscleRecoveryStatus: [(muscle: String, daysRested: Int, status: RecoveryStatus)] {
        let calendar = Calendar.current
        let now = Date()
        
        return muscleLastWorked.map { muscle, lastDate in
            let days = calendar.dateComponents([.day], from: lastDate, to: now).day ?? 0
            let status: RecoveryStatus
            if days <= 1 {
                status = .fatigued
            } else if days <= 2 {
                status = .recovering
            } else if days <= 4 {
                status = .ready
            } else {
                status = .fullyRested
            }
            return (muscle: muscle, daysRested: days, status: status)
        }
        .sorted { $0.daysRested < $1.daysRested }
    }
    
    private var musclesToRest: [String] {
        muscleRecoveryStatus.filter { $0.status == .fatigued }.map { $0.muscle.capitalized }
    }
    
    private var musclesReadyToTrain: [String] {
        muscleRecoveryStatus.filter { $0.status == .ready || $0.status == .fullyRested }.map { $0.muscle.capitalized }
    }
    
    // MARK: - Lift Heavier Suggestions
    private var liftHeavierSuggestions: [(exercise: String, currentMax: Double, suggestion: String)] {
        var suggestions: [(exercise: String, currentMax: Double, suggestion: String)] = []
        var exerciseMaxes: [String: (weight: Double, reps: Int, date: Date)] = [:]
        
        // Find max weight for each exercise in last 30 days
        let recentWorkouts = workouts.filter {
            guard let date = $0.date else { return false }
            return date > Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        }
        
        for workout in recentWorkouts {
            guard let exercises = workout.exercises?.allObjects as? [WorkoutExercise] else { continue }
            for workoutExercise in exercises {
                let exerciseName = workoutExercise.safeDisplayName
                guard exerciseName != "Loading...",
                      let sets = workoutExercise.sets?.allObjects as? [WorkoutSet] else { continue }
                
                for set in sets where set.isCompleted && set.weight > 0 {
                    if let current = exerciseMaxes[exerciseName] {
                        if set.weight > current.weight {
                            exerciseMaxes[exerciseName] = (weight: set.weight, reps: Int(set.reps), date: workout.date ?? Date())
                        }
                    } else {
                        exerciseMaxes[exerciseName] = (weight: set.weight, reps: Int(set.reps), date: workout.date ?? Date())
                    }
                }
            }
        }
        
        // Suggest 5-10% increase for exercises not progressed recently
        for (exercise, data) in exerciseMaxes {
            let daysSinceMax = Calendar.current.dateComponents([.day], from: data.date, to: Date()).day ?? 0
            if daysSinceMax > 7 && data.reps >= 8 {
                let increment = max(5, Int(data.weight * 0.05))
                suggestions.append((
                    exercise: exercise,
                    currentMax: data.weight,
                    suggestion: "Try \(Int(data.weight) + increment) lbs"
                ))
            }
        }
        
        return suggestions.prefix(3).map { $0 }
    }
    
    // MARK: - Recent PRs
    private var recentPRs: [(exercise: String, weight: Double, reps: Int, date: Date)] {
        var prs: [(exercise: String, weight: Double, reps: Int, date: Date)] = []
        var bestSets: [String: (weight: Double, reps: Int)] = [:]
        
        let sortedWorkouts = workouts.sorted { ($0.date ?? Date.distantPast) < ($1.date ?? Date.distantPast) }
        
        for workout in sortedWorkouts {
            guard let exercises = workout.exercises?.allObjects as? [WorkoutExercise] else { continue }
            for workoutExercise in exercises {
                let exerciseName = workoutExercise.safeDisplayName
                guard exerciseName != "Loading...",
                      let sets = workoutExercise.sets?.allObjects as? [WorkoutSet] else { continue }
                
                for set in sets where set.isCompleted {
                    let currentBest = bestSets[exerciseName]
                    let isNewPR: Bool
                    if let best = currentBest {
                        isNewPR = set.weight > best.weight || (set.weight == best.weight && set.reps > best.reps)
                    } else {
                        isNewPR = true
                    }
                    
                    if isNewPR {
                        bestSets[exerciseName] = (weight: set.weight, reps: Int(set.reps))
                        let twoWeeksAgo = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
                        if let date = workout.date, date > twoWeeksAgo {
                            prs.removeAll { $0.exercise == exerciseName }
                            prs.append((exercise: exerciseName, weight: set.weight, reps: Int(set.reps), date: date))
                        }
                    }
                }
            }
        }
        
        return prs.sorted { $0.date > $1.date }.prefix(3).map { $0 }
    }
    
    // MARK: - Performance Stats
    private var workoutsThisWeek: Int {
        workouts.filter {
            guard let date = $0.date else { return false }
            return date > Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        }.count
    }
    
    private var totalVolumeThisWeek: Double {
        let recentWorkouts = workouts.filter {
            guard let date = $0.date else { return false }
            return date > Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        }
        
        return recentWorkouts.reduce(0.0) { total, workout in
            guard let exercises = workout.exercises?.allObjects as? [WorkoutExercise] else { return total }
            return total + exercises.reduce(0.0) { exerciseTotal, workoutExercise in
                guard let sets = workoutExercise.sets?.allObjects as? [WorkoutSet] else { return exerciseTotal }
                return exerciseTotal + sets.filter { $0.isCompleted }.reduce(0.0) { $0 + ($1.weight * Double($1.reps)) }
            }
        }
    }
    
    /// Smart streak - uses centralized UserManager logic that respects rest days
    private var currentStreak: Int {
        return Int(UserManager.shared.currentUser?.currentStreak ?? 0)
    }
    
    // MARK: - Training Score
    private var trainingScore: Int {
        var score = 0
        
        // Consistency (max 30 points)
        if workoutsThisWeek >= 5 { score += 30 }
        else if workoutsThisWeek >= 4 { score += 25 }
        else if workoutsThisWeek >= 3 { score += 20 }
        else if workoutsThisWeek >= 2 { score += 10 }
        else if workoutsThisWeek >= 1 { score += 5 }
        
        // PRs (max 25 points)
        score += min(recentPRs.count * 8, 25)
        
        // Volume progress (max 25 points)
        if totalVolumeThisWeek > 50000 { score += 25 }
        else if totalVolumeThisWeek > 30000 { score += 20 }
        else if totalVolumeThisWeek > 15000 { score += 15 }
        else if totalVolumeThisWeek > 5000 { score += 10 }
        
        // Muscle balance (max 20 points)
        let muscleVariety = Set(muscleRecoveryStatus.map { $0.muscle }).count
        if muscleVariety >= 6 { score += 20 }
        else if muscleVariety >= 4 { score += 15 }
        else if muscleVariety >= 2 { score += 10 }
        
        return min(score, 100)
    }
    
    private var scoreColor: Color {
        if trainingScore >= 80 { return .green }
        else if trainingScore >= 60 { return .yellow }
        else if trainingScore >= 40 { return .orange }
        else { return .red }
    }
    
    // MARK: - Smart Insights
    private var positiveInsights: [TrainingInsight] {
        var insights: [TrainingInsight] = []
        
        if !recentPRs.isEmpty {
            insights.append(TrainingInsight(
                icon: "trophy.fill",
                text: "\(recentPRs.count) new PR\(recentPRs.count > 1 ? "s" : "") this week! Keep pushing! 🔥",
                color: .yellow
            ))
        }
        
        if workoutsThisWeek >= 4 {
            insights.append(TrainingInsight(
                icon: "checkmark.circle.fill",
                text: "Great consistency – \(workoutsThisWeek) workouts this week!",
                color: .green
            ))
        }
        
        if currentStreak >= 3 {
            insights.append(TrainingInsight(
                icon: "flame.fill",
                text: "\(currentStreak)-day training streak! Don't break it!",
                color: .orange
            ))
        }
        
        if !musclesReadyToTrain.isEmpty && musclesReadyToTrain.count >= 3 {
            insights.append(TrainingInsight(
                icon: "bolt.fill",
                text: "Multiple muscle groups fully recovered and ready!",
                color: .green
            ))
        }
        
        return insights.prefix(2).map { $0 }
    }
    
    private var actionableInsights: [TrainingInsight] {
        var insights: [TrainingInsight] = []
        
        if !musclesToRest.isEmpty {
            let muscleList = musclesToRest.prefix(2).joined(separator: ", ")
            insights.append(TrainingInsight(
                icon: "bed.double.fill",
                text: "Rest \(muscleList) – worked recently. Try other muscles today.",
                color: .blue
            ))
        }
        
        if let suggestion = liftHeavierSuggestions.first {
            insights.append(TrainingInsight(
                icon: "arrow.up.circle.fill",
                text: "\(suggestion.exercise): Ready to go heavier! \(suggestion.suggestion)",
                color: .purple
            ))
        }
        
        if workoutsThisWeek < 3 {
            insights.append(TrainingInsight(
                icon: "calendar.badge.plus",
                text: "Only \(workoutsThisWeek) workout\(workoutsThisWeek == 1 ? "" : "s") this week. Aim for 3-4!",
                color: .orange
            ))
        }
        
        if recentPRs.isEmpty && workoutsThisWeek >= 2 {
            insights.append(TrainingInsight(
                icon: "sparkles",
                text: "No PRs lately – try progressive overload this session!",
                color: .purple
            ))
        }
        
        return insights.prefix(2).map { $0 }
    }
    
    private var dailyTip: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let dayOfWeek = Calendar.current.component(.weekday, from: Date())
        
        // Weekend tips
        if dayOfWeek == 1 || dayOfWeek == 7 {
            let tips = [
                "💡 Weekends are great for longer sessions – take your time!",
                "💡 Use rest days for stretching and mobility work.",
                "💡 Meal prep on weekends sets you up for the week.",
            ]
            return tips.randomElement() ?? tips[0]
        }
        
        if hour < 12 {
            let tips = [
                "💡 Morning workouts boost metabolism all day long.",
                "💡 Don't skip warm-up – 5 mins prevents injuries.",
                "💡 High-protein breakfast fuels better performance.",
            ]
            return tips.randomElement() ?? tips[0]
        } else if hour < 17 {
            let tips = [
                "💡 Afternoon is peak strength time for most people.",
                "💡 Stay hydrated – performance drops 10% when dehydrated.",
                "💡 Mind-muscle connection matters more than weight.",
            ]
            return tips.randomElement() ?? tips[0]
        } else {
            let tips = [
                "💡 Evening workouts can improve sleep quality.",
                "💡 Don't train to failure every set – leave 1-2 reps.",
                "💡 Post-workout protein within 2 hours maximizes gains.",
            ]
            return tips.randomElement() ?? tips[0]
        }
    }
    
    private var greeting: String {
        if trainingScore >= 80 {
            return "Outstanding performance! 🏆"
        } else if trainingScore >= 60 {
            return "Solid progress this week! 💪"
        } else if workoutsThisWeek == 0 {
            return "Ready to get back at it? 🎯"
        } else {
            return "Keep building momentum! 🚀"
        }
    }
    
    private func getScoreDescription() -> String {
        if trainingScore >= 80 {
            return "Top performer this week"
        } else if trainingScore >= 60 {
            return "On track for your goals"
        } else if trainingScore >= 40 {
            return "Room for improvement"
        } else {
            return "Let's build consistency"
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Greeting header with score
            HStack(alignment: .center) {
                Text(greeting)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Compact score badge
                HStack(spacing: 4) {
                    Text("\(trainingScore)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(scoreColor)
                    Text("pts")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(scoreColor.opacity(0.12))
                )
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, 14)
            .padding(.bottom, 10)
            
            // Quick Stats Row
            HStack(spacing: 0) {
                QuickTrainingStat(
                    value: "\(workoutsThisWeek)",
                    label: "This Week",
                    icon: "flame.fill",
                    color: workoutsThisWeek >= 3 ? .green : .gray
                )
                
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 1, height: 32)
                
                QuickTrainingStat(
                    value: formatVolume(totalVolumeThisWeek),
                    label: "Volume",
                    icon: "scalemass.fill",
                    color: .blue
                )
                
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 1, height: 32)
                
                QuickTrainingStat(
                    value: "\(recentPRs.count)",
                    label: "PRs",
                    icon: "trophy.fill",
                    color: recentPRs.isEmpty ? .gray : .yellow
                )
                
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 1, height: 32)
                
                QuickTrainingStat(
                    value: "\(currentStreak)",
                    label: "Streak",
                    icon: "bolt.fill",
                    color: currentStreak >= 3 ? .orange : .gray
                )
            }
            .padding(.vertical, 10)
            
            // Insights as stacked text with icons
            if !positiveInsights.isEmpty || !actionableInsights.isEmpty {
                Divider()
                    .padding(.horizontal, Spacing.md)
                
                VStack(alignment: .leading, spacing: 8) {
                    // Positive insights
                    ForEach(positiveInsights.prefix(2)) { insight in
                        TrainingInsightRow(insight: insight)
                    }
                    
                    // Actionable insights
                    ForEach(actionableInsights.prefix(2)) { insight in
                        TrainingInsightRow(insight: insight)
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
            }
            
            // Muscle Recovery Status (compact horizontal scroll)
            if !muscleRecoveryStatus.isEmpty {
                Divider()
                    .padding(.horizontal, Spacing.md)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(muscleRecoveryStatus.prefix(5), id: \.muscle) { item in
                            MuscleRecoveryBadge(muscle: item.muscle, status: item.status, daysRested: item.daysRested)
                        }
                    }
                    .padding(.horizontal, Spacing.md)
                }
                .padding(.vertical, 10)
            }
            
            // View Program Link - subtle, inline style
            Divider()
                .padding(.horizontal, Spacing.md)
            
            Button(action: { HapticManager.impact(.light); onViewProgram() }) {
                HStack(spacing: 10) {
                    // Program icon
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [scoreColor.opacity(0.15), scoreColor.opacity(0.08)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 36, height: 36)
                        
                        Image(systemName: "calendar.badge.clock")
                            .font(.ds_labelLarge)
                            .foregroundColor(scoreColor)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("View Program")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        Text(dailyTip.replacingOccurrences(of: "💡 ", with: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.ds_labelMedium)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, 14)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .background(
            ZStack {
                // Bottom shadow layer (deepest) - colored based on score
                RoundedRectangle(cornerRadius: CornerRadius.xl)
                    .fill(scoreColor.opacity(colorScheme == .dark ? 0.15 : 0.1))
                    .offset(y: 10)
                    .blur(radius: 6)
                
                // Middle shadow layer
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.25 : 0.06))
                    .offset(y: 5)
                
                // Main card background
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark 
                                ? [Color.darkCardBackground, Color.darkSurface]
                                : [Color.white, Color.white.opacity(0.97)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                // Inner highlight (top edge glow)
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            colors: colorScheme == .dark 
                                ? [Color.white.opacity(0.12), Color.white.opacity(0.03), Color.clear]
                                : [Color.white, Color.white.opacity(0.6), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1.5
                    )
                
                // Colored accent border based on score
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            colors: [
                                scoreColor.opacity(colorScheme == .dark ? 0.35 : 0.25),
                                scoreColor.opacity(colorScheme == .dark ? 0.2 : 0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.1), radius: 15, x: 0, y: 8)
        .shadow(color: scoreColor.opacity(colorScheme == .dark ? 0.2 : 0.15), radius: 25, x: 0, y: 12)
    }
    
    private func formatVolume(_ volume: Double) -> String {
        if volume >= 1000000 {
            return String(format: "%.1fM", volume / 1000000)
        } else if volume >= 1000 {
            return String(format: "%.0fK", volume / 1000)
        } else {
            return String(format: "%.0f", volume)
        }
    }
}

// MARK: - Recovery Status
enum RecoveryStatus {
    case fatigued, recovering, ready, fullyRested
    
    var color: Color {
        switch self {
        case .fatigued: return .red
        case .recovering: return .orange
        case .ready: return .green
        case .fullyRested: return .blue
        }
    }
    
    var label: String {
        switch self {
        case .fatigued: return "Rest"
        case .recovering: return "Recovering"
        case .ready: return "Ready"
        case .fullyRested: return "Fresh"
        }
    }
}

// MARK: - Training Insight Model
struct TrainingInsight: Identifiable {
    let id = UUID()
    let icon: String
    let text: String
    let color: Color
}

// MARK: - Training Insight Row (Floating text with icon)
struct TrainingInsightRow: View {
    let insight: TrainingInsight
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: insight.icon)
                .font(.ds_labelMedium)
                .foregroundColor(insight.color)
                .frame(width: 20)
            
            Text(insight.text)
                .font(.ds_bodySmall)
                .foregroundColor(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer()
        }
    }
}

// MARK: - Insight Chip (compact horizontal display)

struct InsightChip: View {
    let insight: TrainingInsight
    let tint: Color
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: insight.icon)
                .font(.ds_labelMedium)
                .foregroundColor(tint)
            
            Text(cleanInsightText(insight.text))
                .font(.ds_bodySmall).fontWeight(.medium)
                .foregroundColor(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(
            Capsule()
                .fill(tint.opacity(0.12))
        )
        .overlay(
            Capsule()
                .stroke(tint.opacity(0.2), lineWidth: 1)
        )
    }
    
    // Clean up the text - remove emojis and shorten
    private func cleanInsightText(_ text: String) -> String {
        var cleaned = text
        // Remove common emojis
        let emojis = ["🔥", "💪", "🎯", "🚀", "🏆", "💡", "😊", "⚡️"]
        for emoji in emojis {
            cleaned = cleaned.replacingOccurrences(of: emoji, with: "")
        }
        // Trim and limit length
        cleaned = cleaned.trimmingCharacters(in: .whitespaces)
        if cleaned.count > 35 {
            let index = cleaned.index(cleaned.startIndex, offsetBy: 32)
            cleaned = String(cleaned[..<index]) + "..."
        }
        return cleaned
    }
}

// MARK: - Muscle Recovery Badge
struct MuscleRecoveryBadge: View {
    let muscle: String
    let status: RecoveryStatus
    let daysRested: Int
    
    var body: some View {
        VStack(spacing: 4) {
            Circle()
                .fill(status.color.opacity(0.2))
                .frame(width: 36, height: 36)
                .overlay(
                    Text("\(daysRested)d")
                        .font(.ds_caption)
                        .foregroundColor(status.color)
                )
            
            Text(muscle.capitalized)
                .font(.ds_caption)
                .foregroundColor(.primary)
                .lineLimit(1)
            
            Text(status.label)
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(status.color)
        }
        .frame(width: 60)
        .padding(.vertical, Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(status.color.opacity(0.08))
        )
    }
}

// MARK: - Quick Training Stat
struct QuickTrainingStat: View {
    let value: String
    let label: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.ds_caption)
                    .foregroundColor(color)
                Text(value)
                    .font(.ds_bodySmall).fontWeight(.bold).fontDesign(.rounded)
                    .foregroundColor(.primary)
            }
            Text(label)
                .font(.ds_caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Compact Stat (for sleeker widget)
struct CompactStat: View {
    let value: String
    let label: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(color)
                Text(value)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            }
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Muscle Progress Bar
struct MuscleProgressBar: View {
    let muscle: String
    let percentage: Double
    let count: Int
    
    private var muscleColor: Color {
        switch muscle.lowercased() {
        case "chest": return .red
        case "back": return .blue
        case "shoulders": return .orange
        case "biceps", "triceps", "arms": return .purple
        case "legs", "quads", "hamstrings", "glutes": return .green
        case "core", "abs": return .yellow
        default: return .gray
        }
    }
    
    var body: some View {
        HStack(spacing: 10) {
            Text(muscle.capitalized)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .frame(width: 70, alignment: .leading)
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.15))
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(colors: [muscleColor, muscleColor.opacity(0.7)], startPoint: .leading, endPoint: .trailing)
                        )
                        .frame(width: geometry.size.width * min(percentage / 40, 1.0)) // 40% = full bar
                }
            }
            .frame(height: 8)
            
            Text("\(Int(percentage))%")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .frame(width: 35, alignment: .trailing)
        }
    }
}

// MARK: - Insight Stat Cell
struct InsightStatCell: View {
    let value: String
    let label: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.ds_labelSmall)
                    .foregroundColor(color)
                Text(value)
                    .font(.ds_statSmall)
                    .foregroundColor(.primary)
            }
            Text(label)
                .font(.ds_caption)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Workout Tab Program Card
struct WorkoutTabProgramCard: View {
    let program: DynamicProgramGenerator.GeneratedProgram
    let onStart: () -> Void
    @Environment(\.colorScheme) var colorScheme
    
    private var programColor: Color {
        switch program.programType {
        case .hypertrophy: return .blue
        case .strength: return .red
        case .fatLoss: return .orange
        case .toning: return .purple
        case .generalFitness: return .green
        case .powerbuilding: return .yellow
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header — icon + split type + program-type chip
            HStack(spacing: Spacing.xs) {
                Image(systemName: program.icon)
                    .font(.ds_labelLarge)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [programColor, programColor.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Text(program.splitType.rawValue)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)

                Spacer(minLength: Spacing.xxs)

                // Program-type pill (Hypertrophy / Strength / Fat Loss / etc)
                Text(program.programType.rawValue)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(programColor)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(programColor.opacity(colorScheme == .dark ? 0.18 : 0.14))
                    )
                    .overlay(
                        Capsule()
                            .stroke(programColor.opacity(0.35), lineWidth: 0.5)
                    )
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }

            // Name — allow up to 2 lines with graceful scale-down
            Text(program.name)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Stats row — Spacer between labels prevents collision on long localizations
            HStack(spacing: Spacing.xs) {
                Label("\(program.daysPerWeek)/wk", systemImage: "calendar")
                    .lineLimit(1)
                Spacer(minLength: Spacing.xs)
                Label("\(program.durationWeeks)wks", systemImage: "clock")
                    .lineLimit(1)
            }
            .font(.ds_bodySmall)
            .foregroundColor(.secondary)
            .minimumScaleFactor(0.9)

            Spacer(minLength: 0)

            // Start button — corner radius bumped to match card; subtle accent shadow lifts off surface
            Button(action: {
                HapticManager.impact(.medium)
                onStart()
            }) {
                Text("Start Program")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.xs)
                    .background(
                        LinearGradient(
                            colors: [programColor, programColor.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
                    .shadow(color: programColor.opacity(0.3), radius: 6, x: 0, y: 3)
            }
        }
        .padding(Spacing.sm)
        .frame(height: 170)
        .background(
            ZStack {
                // Bottom shadow layer — programColor glow
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(programColor.opacity(colorScheme == .dark ? 0.15 : 0.08))
                    .offset(y: 8)
                    .blur(radius: 4)

                // Middle shadow layer
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                    .offset(y: 4)

                // Main surface — adapts frosted ↔ solid via Settings toggle
                AdaptiveCardSurface(cornerRadius: 16)

                // Inner highlight (top-edge gloss)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color.white.opacity(0.1), Color.white.opacity(0.02), Color.clear]
                                : [Color.white, Color.white.opacity(0.5), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1.5
                    )

                // Accent border — programColor gradient
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                programColor.opacity(colorScheme == .dark ? 0.5 : 0.4),
                                programColor.opacity(colorScheme == .dark ? 0.25 : 0.18)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.06), radius: 8, x: 0, y: 4)
        .shadow(color: programColor.opacity(colorScheme == .dark ? 0.2 : 0.12), radius: 12, x: 0, y: 6)
    }
}

// MARK: - Phase 6 Deferred Stats Section
//
// Snappiness Overhaul Phase 6 (`PerfFlags.phase6WorkoutTabRender`).
// `WorkoutStatsSection` is a non-lazy `VStack` of 12 chart widgets
// (per the explicit `// Use VStack (not LazyVStack)` directive at
// `WorkoutStatsView.swift:94`) — every child evaluates `body` on
// first parent eval even though stats live below the fold. On the
// Workout tab's first cold-start render that work compounded with
// `CloudProgramService` / `GeneratedProgramService` cache loads to
// blow past the 300ms tab-transition budget (1.39 (70) cold-start
// log: `[TAB SWITCH] Slow transition: 777.0ms`).
//
// This wrapper renders a 1pt-tall `Color.clear` placeholder until
// 500ms past first appear (mirrors `loadCardioWorkoutsThisWeek`'s
// 250ms QP-19 sleep, doubled because chart widgets are heavier than
// a single Supabase fetch and a below-fold deferral is invisible).
// The first frame paints without 12 chart-widget body evals; the
// real `WorkoutStatsSection` mounts after, swapping in well past
// the tab-transition animation commit. Per QP-19 ("tab switch
// handlers are minimal"), the deferred mount lives entirely in a
// child `.task` — no `Task.sleep` lands on the parent's render
// path. `.task` cancels automatically when the user leaves the tab,
// so a fast tab away never strands the deferred mount.
struct Phase6DeferredWorkoutStatsSection: View {
    @State private var isMounted = false

    var body: some View {
        Group {
            if isMounted {
                WorkoutStatsSection()
            } else {
                // Zero-height placeholder so the surrounding VStack
                // ordering and spacing doesn't shift on mount. (Real
                // `WorkoutStatsSection` is below the fold of the
                // initial viewport — there's nothing for the user to
                // see in this gap on first paint.)
                Color.clear.frame(height: 1)
            }
        }
        .task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            isMounted = true
        }
    }
}

#Preview {
    WorkoutTabView()
        .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
        .environmentObject(UserManager())
        .environmentObject(WorkoutManager.shared)
}
