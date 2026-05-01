import SwiftUI
import CoreData
import UserNotifications
import Combine

struct DashboardView: View {
    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.scrollToTopTrigger) var scrollToTopTrigger
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.scenePhase) var scenePhase
    @EnvironmentObject var userManager: UserManager
    @EnvironmentObject var workoutManager: WorkoutManager
    
    @State var showingWorkoutCreation = false
    @State var workoutCreationType: WorkoutCreationType = .custom
    @State var showingProgramConflictAlert = false
    @State var pendingWorkoutType: PendingWorkoutType? = nil
    @State var navigateToTodaysWorkout = false
    @State var programWidgetRotation: Double = 0
    @State var challengeGlowPhase: CGFloat = 0
    
    // Phone verification prompt for existing users (v1.14.3+)
    @State var showPhoneVerificationPrompt = false
    @AppStorage("hasSeenPhonePrompt_v1143") var hasSeenPhonePrompt = false
    @AppStorage("userHasVerifiedPhone") var userHasVerifiedPhone = false
    
    // Swipeable widget state (challenges only now)
    @State var selectedWidgetPage: Int = 0
    @State var widgetSwipeInProgress: Bool = false
    
    // Swipeable workout carousel (workout buttons + active program)
    @State var selectedWorkoutPage: Int = 0
    let challengeService = ChallengeService.shared
    let dailyQuestService = DailyQuestService.shared
    let stravaService = StravaService.shared
    let streakShieldService = StreakShieldService.shared
    let healthKitService = HealthKitService.shared
    @State var navigateToCustomWorkout = false
    @State var navigateToAutoWorkout = false
    @State var navigateToGeneratedPrograms = false
    @State var isNavigating = false  // 🔧 Debounce protection
    
    // Smart personalized recommendation.
    // Hydrated synchronously from the disk cache on view init so the
    // welcome card renders the last known "close the gap" nudge the
    // instant the dashboard appears — no blank state, no flicker. The
    // cache is kept fresh by `BackgroundChallengeSyncService` (every
    // HealthKit background delivery + BGAppRefresh/BGProcessing cycle).
    @State var personalizedRecommendation: AdvancedIntelligenceService.PersonalizedRecommendation? = RecommendationCache.read()
    @State var isLoadingRecommendation = false
    @State var currentMotivationalMessage: String = ""
    
    // Personalized insights service for smart rotating messages (plain let — only called from .task, never read in body)
    let insightsService = PersonalizedInsightsService.shared
    
    // Cardio workouts from Supabase
    @State var recentCardioWorkouts: [CardioWorkoutDTO] = []
    @State var totalCardioWorkoutCount: Int = 0  // All-time cardio count (not limited to 5)
    
    // Profile photo for home icon
    @State var profilePhotoURL: String? = nil
    
    // Track last challenge refresh date for midnight auto-sync
    @State var lastChallengeRefreshDate: Date = Date()
    
    // Combined workout item for unified display
    enum RecentWorkoutItem: Identifiable {
        case strength(Workout, isMostRecent: Bool)
        case cardio(CardioWorkoutDTO, isMostRecent: Bool)
        
        var id: String {
            switch self {
            case .strength(let workout, _):
                return "strength-\(workout.objectID.uriRepresentation().absoluteString)"
            case .cardio(let cardio, _):
                return "cardio-\(cardio.id)"
            }
        }
        
        var date: Date {
            switch self {
            case .strength(let workout, _):
                return workout.date ?? Date.distantPast
            case .cardio(let cardio, _):
                // Use centralized ISO8601 parser (cached formatters)
                return ISO8601Parser.parse(cardio.completedAt, fallback: Date.distantPast)
            }
        }
    }
    
    // ⚡️ PERFORMANCE: Cached combined workouts — updated via onChange, not recomputed every body eval
    @State var combinedRecentWorkouts: [RecentWorkoutItem] = []
    /// Map of Fit33 `Workout.id` → wearable cardio row that overlapped it.
    /// Computed in `rebuildCombinedWorkouts` via `WorkoutWearableMerger` so
    /// `RecentWorkoutCard` can render the origin chip (WHOOP / Apple Watch /
    /// …) without re-running the overlap math on every body eval.
    @State var wearableEnrichmentByWorkout: [UUID: CardioWorkoutDTO] = [:]
    @State var showRecoveryWidget: Bool = false

    private func rebuildCombinedWorkouts() {
        let strengthList = Array(recentWorkouts.prefix(5))
        // Collapse wearable-origin strength cardio rows (WHOOP / Apple Watch /
        // Oura / Fitbit / Garmin) that overlap a Fit33 strength workout —
        // otherwise the user sees the same session twice on the Home
        // "Recent Activity" list.
        let merged = WorkoutWearableMerger.merge(
            strength: strengthList,
            cardio: recentCardioWorkouts
        )

        var items: [RecentWorkoutItem] = []
        for workout in strengthList {
            items.append(.strength(workout, isMostRecent: false))
        }
        for cardio in merged.filteredCardio {
            items.append(.cardio(cardio, isMostRecent: false))
        }
        items.sort { $0.date > $1.date }
        if !items.isEmpty {
            switch items[0] {
            case .strength(let workout, _):
                items[0] = .strength(workout, isMostRecent: true)
            case .cardio(let cardio, _):
                items[0] = .cardio(cardio, isMostRecent: true)
            }
        }
        combinedRecentWorkouts = items
        wearableEnrichmentByWorkout = merged.enrichmentByWorkoutID
    }
    
    // Streak info popup
    @State var showStreakInfo = false
    
    // Challenge widget navigation - goes to Profile's FriendsListView
    @State var showFriendsListForChallenge = false
    
    // Challenge creation flow states
    @State var showingChallengeCreation = false
    @State var showCommunityHub = false
    
    // Widget settings
    @State var showingWidgetSettings = false
    @AppStorage("showWeightTrackerWidget") var showWeightTrackerWidget = true  // Default ON
    @AppStorage("showHydrationWidget") var showHydrationWidget = false
    @AppStorage("showMacrosWidget") var showMacrosWidget = false  // Nutrition macros quick-access
    @AppStorage("showChallengeWidget") var showChallengeWidget = true  // Challenge a Friend widget (premium can hide)
    @AppStorage("showRecommendedWidget") var showRecommendedWidget = true  // Recommended For You widget (premium can hide)
    @AppStorage("showWhoopWidget") var showWhoopWidget = true  // WHOOP Recovery widget (only renders when connected)
    @AppStorage("showOuraWidget") var showOuraWidget = true  // Oura Readiness widget (only renders when connected)
    @AppStorage("showStravaWidget") var showStravaWidget = true  // Strava latest-activity widget (only renders when connected + fresh activity)
    
    // Nutrition data for macros widget (plain let — macros widget wraps its own @ObservedObject)
    let mealService = MealService.shared
    @State var selectedMacrosPage: Int = 0  // For swipeable macros cards
    
    // Used to force NavigationStack to reset when switching tabs
    @State var navigationViewId = UUID()
    @State var dashboardNavPath = NavigationPath()
    let deepLinkManager = DeepLinkManager.shared
    let generatedProgramService = GeneratedProgramService.shared
    let smartProgramEngine = SmartProgramEngine.shared
    
    // Notification banner
    @AppStorage("notification_banner_dismissed") var dismissedNotificationBanner = false
    
    // Data loading throttle
    @State var lastCardioFetchTime: Date?
    
    // Challenge state
    @State var challengeToCancel: UUID?
    
    // Program widget state
    @State var activeWidgetGlowRotation: Double = 0
    @State var navigateToProgramDay = false
    @State var showStartProgramConfirm = false
    @State var programToStart: PersonalizedProgram?
    @State var programGlowRotation: Double = 0
    
    @FetchRequest(fetchRequest: {
        let request: NSFetchRequest<Workout> = Workout.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Workout.date, ascending: false)]
        request.predicate = NSPredicate(format: "isCompleted == true")
        request.fetchLimit = 10
        return request
    }(), animation: .none)
    var recentWorkouts: FetchedResults<Workout>
    
    var displayedWorkouts: [Workout] {
        Array(recentWorkouts.prefix(10))
    }
    
    
    var body: some View {
        NavigationStack(path: $dashboardNavPath) {
            ZStack {
                // Animated background with colored orbs
                AnimatedOrbBackground.home(colorScheme: colorScheme)
                    .accessibilityHidden(true)

                // Pinned header + scroll share one full-screen orb behind
                // the ZStack so the header strip stays see-through.
                VStack(spacing: 0) {
                    pinnedTopHeader

                    ScrollViewReader { scrollProxy in
                        ScrollView(showsIndicators: false) {
                    Color.clear
                    .frame(height: 0)
                    .id("top")
                    
                    LazyVStack(spacing: 0) {
                    DashboardNotificationBannerWrapper()

                    // Sprint 2 Q2-34 — shows when a workout save failed offline and is queued for retry.
                    DashboardOfflineSyncChip()

                    // Header with user info
                    headerView
                        .padding(.bottom, 16)
                    
                    // Unified notification carousel (friend requests, received workouts, challenge invites)
                    DashboardNotificationCarousel()
                        .environmentObject(workoutManager)
                        .environmentObject(userManager)
                        .padding(.bottom, 16)
                    
                    // Daily Quests widget (isolated view to prevent quest updates from recomputing parent)
                    DashboardQuestsWrapper()
                        .padding(.bottom, 16)
                    
                    // Recovery Day widget (cached — avoids 10-muscle evaluation per body pass)
                    if showRecoveryWidget {
                        RecoveryDayDashboardWidget()
                            .padding(.horizontal, Spacing.md)
                            .padding(.bottom, 16)
                    }
                    
                    HStack(spacing: 10) {
                        Image(systemName: "dumbbell.fill")
                            .foregroundStyle(
                                LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .font(.title3)
                        Text("Ready for today's workout?")
                            .font(.title3)
                            .fontWeight(.bold)
                        Spacer()
                    }
                    .padding(.bottom, 12)

                    // Swipeable Workout Carousel: [Custom+Auto Buttons] <-> [Active Program]
                    // Ordered above Challenges so the "Ready for today's workout?"
                    // header leads directly into the primary workout CTA; the
                    // Challenge widget is a secondary social action.
                    swipeableWorkoutCarousel
                        .padding(.bottom, 16)

                    // Challenge Cards (1v1 active, group active, pending sent, get started)
                    if showChallengeWidget {
                        DashboardChallengesWrapper(showingChallengeCreation: $showingChallengeCreation)
                            .environmentObject(userManager)
                            .padding(.bottom, 16)
                    }
                    
                    // Weight/Hydration Widget Row (below challenge widget)
                    if showWeightTrackerWidget || showHydrationWidget {
                        dashboardWidgetsRow
                            .padding(.bottom, 16)
                    }
                    
                    // Quick Macros Widget (isolated to prevent MealService re-renders from reaching parent)
                    if showMacrosWidget {
                        DashboardMacrosWrapper()
                            .environmentObject(userManager)
                            .padding(.bottom, 16)
                    }

                    // Step Tracker Card — placed above the wearable widgets
                    // (WHOOP / Oura / Strava) and beneath the Weight/Hydration
                    // / Macros block so Daily Steps lives in the same
                    // "physical activity at a glance" cluster as Weight,
                    // not buried beneath the wearable strip.
                    StepTrackerCard()
                        .id("stepTracker")
                        .padding(.bottom, 16)

                    // WHOOP Recovery Widget (isolated — only renders when WHOOP connected + widget enabled)
                    if showWhoopWidget {
                        DashboardWhoopWrapper(navigationPath: $dashboardNavPath)
                            .padding(.bottom, 16)
                    }

                    // Oura Readiness Widget (isolated — only renders when Oura connected + widget enabled)
                    if showOuraWidget {
                        DashboardOuraWrapper()
                            .padding(.bottom, 16)
                    }

                    // Strava Latest Activity Widget (isolated — only renders when Strava connected + an activity from the last 36h)
                    if showStravaWidget {
                        DashboardStravaWrapper(navigationPath: $dashboardNavPath)
                            .padding(.bottom, 20)
                    }

                    // Recent workouts section (in-app + synced HealthKit/Strava/Fitbit)
                    if !recentWorkouts.isEmpty || !recentCardioWorkouts.isEmpty {
                        recentWorkoutsSection
                            .id("workoutHistory")
                            .padding(.bottom, 20)
                    }
                    
                }
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, 20)
                }
                .scrollContentBackground(.hidden)
                .contentMargins(.top, 0, for: .scrollContent)
                .onChange(of: scrollToTopTrigger) { _, _ in
                    scrollProxy.scrollTo("top", anchor: .top)
                }
                // Handle deep link scroll-to-widget notifications
                .onReceive(NotificationCenter.default.publisher(for: .scrollToWidget)) { notification in
                    guard let widgetId = notification.object as? String else { return }
                    withAnimation(.easeInOut(duration: 0.3)) {
                        switch widgetId {
                        case "stepTracker":
                            scrollProxy.scrollTo("stepTracker", anchor: .top)
                        case "workoutHistory":
                            scrollProxy.scrollTo("workoutHistory", anchor: .top)
                        case "streakInfo":
                            // Scroll to header then show streak popup
                            scrollProxy.scrollTo("top", anchor: .top)
                            Task { @MainActor in
                                try? await Task.sleep(for: .seconds(0.3))
                                guard !Task.isCancelled else { return }
                                showStreakInfo = true
                            }
                        case "hydration", "weightTracker":
                            // These are in SimpleMealPlanView, not Dashboard
                            // But if user lands on Dashboard, scroll to top
                            scrollProxy.scrollTo("top", anchor: .top)
                        default:
                            break
                        }
                    }
                    AppLogger.debug("[DASHBOARD] Scrolled to widget: \(widgetId)", category: .ui)
                }
                }
                .refreshable {
                    // Sprint 2026-04-24 Phase 3 — pull-to-refresh trimmed.
                    //
                    // Phase 2 kept 10 tasks in the awaited group; both 1.38 (54) pulls
                    // still hit the 8s timeout cap, meaning "user waits 8s then sees
                    // stale UI update in background anyway". Phase 3 trims the awaited
                    // group to the 4 truly-visible-on-dashboard widgets, moves heavy
                    // challenge refreshes to fire-and-forget (they publish when ready),
                    // and tightens the cap 8s → 5s. Background work is unchanged; user
                    // just stops waiting for it.
                    //
                    // AWAITED (≤5s, 4 tasks): quests, hydration, cardio list, welcome
                    // card recommendation. These ARE the dashboard body.
                    //
                    // FIRE-AND-FORGET: HealthDataService (coalesced per Sprint 3 I1 —
                    // won't stack), FriendService home refresh, community challenge
                    // full refresh, private challenge full refresh, ChallengeService
                    // pending invites / active / group / sent.
                    let refreshStart = CFAbsoluteTimeGetCurrent()
                    
                    // Fire-and-forget heavy / non-dashboard-critical work.
                    // Coalesced HealthDataService means stacking these is safe.
                    Task { await HealthDataService.shared.syncAllHealthData(force: true) }
                    Task { await FriendService.shared.refreshHomeScreenData() }
                    Task { await CommunityChallengeService.shared.refreshAll(force: true) }
                    Task { await PrivateChallengeService.shared.refreshAll(force: true) }
                    Task { await ChallengeService.shared.fetchPendingInvites() }
                    Task { await ChallengeService.shared.fetchActiveChallenges() }
                    Task { await ChallengeService.shared.fetchActiveGroupChallenges() }
                    Task { await ChallengeService.shared.fetchPendingSentChallenges() }
                    
                    // Awaited group — only the 4 widgets on the visible dashboard,
                    // raced against a 5s hard cap. After 5s the spinner ALWAYS
                    // clears; in-flight awaited tasks also get cancelled so their
                    // next re-trigger is clean.
                    let realWork = Task { @MainActor in
                        await withTaskGroup(of: Void.self) { group in
                            group.addTask { await DailyQuestService.shared.fetchDailyQuests(force: true) }
                            group.addTask { await HydrationService.shared.loadTodayData() }
                            group.addTask { await loadRecentCardioWorkouts() }
                            group.addTask { await loadPersonalizedRecommendation() }
                        }
                    }
                    let timedOut = await withTaskGroup(of: Bool.self, returning: Bool.self) { outer in
                        outer.addTask {
                            await realWork.value
                            return false   // false = "didn't time out"
                        }
                        outer.addTask {
                            try? await Task.sleep(nanoseconds: 5_000_000_000)
                            return true    // true = "timed out"
                        }
                        let firstResult = await outer.next() ?? true
                        outer.cancelAll()
                        if firstResult {
                            realWork.cancel()
                        }
                        return firstResult
                    }
                    if timedOut {
                        AppLogger.warning("[DASHBOARD] Pull-to-refresh hit 5s timeout — clearing spinner (background work continues)", category: .ui)
                    }
                    
                    // Meals loader is synchronous — run after the awaited group.
                    MealService.shared.loadTodaysMeals()
                    
                    // Timing log. Uses the actual wall clock from refreshStart, not
                    // the withTaskGroup exit time (Phase 2's log was mathematically
                    // wrong when the timeout branch won — the final elapsed was
                    // dominated by how long `outer`'s cancel+exit took to drain,
                    // which is tens of ms, not the full 8s the user actually waited).
                    let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - refreshStart) * 1000)
                    AppLogger.debug("[DASHBOARD] Pull-to-refresh visible-work completed in \(elapsedMs)ms (timed_out: \(timedOut))", category: .ui)
                }
                }   // closes VStack(spacing: 0) — pinned-header wrapper
                .padding(.top, TabPinnedChrome.rootTopPullUp)
            }
            .navigationBarHidden(true)
            .adaptiveToolbarBackground()
            .sheet(isPresented: $showingWorkoutCreation) {
                WorkoutCreationView(workoutType: workoutCreationType)
            }
            .sheet(isPresented: $showStreakInfo) {
                StreakInfoSheet()
                    .environmentObject(userManager)
            }
            .fullScreenCover(isPresented: $showingChallengeCreation) {
                NavigationStack {
                    ChallengeFlowStartView()
                        .environmentObject(userManager)
                }
            }
            .fullScreenCover(isPresented: $showingWidgetSettings) {
                WidgetSettingsSheet(
                    showWeightTracker: $showWeightTrackerWidget,
                    showHydration: $showHydrationWidget,
                    showMacros: $showMacrosWidget,
                    showChallenge: $showChallengeWidget,
                    showRecommended: $showRecommendedWidget,
                    showWhoop: $showWhoopWidget,
                    showOura: $showOuraWidget,
                    showStrava: $showStravaWidget
                )
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showPhoneVerificationPrompt) {
                phoneVerificationPromptSheet
            }
            .navigationDestination(isPresented: $navigateToCustomWorkout) {
                CustomWorkoutBuilderView()
                    .environmentObject(workoutManager)
                    .environmentObject(userManager)
            }
            .navigationDestination(isPresented: $navigateToAutoWorkout) {
                WorkoutGeneratorSelectionView()
                    .environmentObject(workoutManager)
                    .environmentObject(userManager)
            }
            .navigationDestination(isPresented: $navigateToGeneratedPrograms) {
                GeneratedProgramsListView()
                    .environmentObject(generatedProgramService)
            }
            .navigationDestination(isPresented: $showFriendsListForChallenge) {
                FriendsListView(initialTab: 0)
            }
            // MARK: - Value-Based Navigation Destinations
            .modifier(DashboardNavigationDestinations(
                userManager: userManager,
                workoutManager: workoutManager,
                generatedProgramService: generatedProgramService,
                smartProgramEngine: smartProgramEngine
            ))
            .overlay(
                programConflictAlert
            )
            .overlay(alignment: .top) {
                DashboardQuestCelebrationWrapper()
                    .padding(.top, 60)
            }
        }
        .id(navigationViewId)  // Forces NavigationStack to reset when ID changes
        .onChange(of: workoutManager.shouldPopToRootHome) { _, shouldPop in
            if shouldPop {
                let hasDeepNavigation = navigateToAutoWorkout || navigateToCustomWorkout ||
                                        navigateToGeneratedPrograms || navigateToTodaysWorkout ||
                                        showingChallengeCreation ||
                                        !dashboardNavPath.isEmpty
                
                workoutManager.shouldPopToRootHome = false
                
                guard hasDeepNavigation else { return }
                
                navigateToAutoWorkout = false
                navigateToCustomWorkout = false
                navigateToGeneratedPrograms = false
                navigateToTodaysWorkout = false
                showingChallengeCreation = false
                dashboardNavPath = NavigationPath()
                navigationViewId = UUID()
            }
        }
        // MARK: - Challenge Deep Link Navigation
        .onReceive(deepLinkManager.$pendingDashboardRoute) { route in
            handlePendingDashboardRoute(route)
        }
        .onChange(of: workoutManager.isWorkoutActive) { _, isActive in
            // 🔧 FIX: Reset navigation states AND force NavigationStack reset when workout starts
            // This prevents the generator/preview from reappearing after tab switch
            if isActive {
                // Reset navigation link states
                navigateToAutoWorkout = false
                navigateToCustomWorkout = false
                navigateToGeneratedPrograms = false
                navigateToTodaysWorkout = false
                isNavigating = false  // Reset debounce
                dashboardNavPath = NavigationPath()
                
                // 🔧 FORCE NavigationStack to completely reset
                // This eliminates the "smashed header" with double back buttons
                navigationViewId = UUID()
            }
        }
        .onAppear {
            showRecoveryWidget = RecoveryDayEngine.shared.shouldShowRecoveryWidget
            
            if let user = userManager.currentUser {
                streakShieldService.checkStreakRisk(
                    lastWorkoutDate: user.lastWorkoutDate,
                    currentStreak: Int(user.currentStreak)
                )
            }
            
            // Fetch friend reactions for workout stickers
            Task { await ActivityFeedService.shared.fetchMyReactions() }
            
            // ⚡️ PERFORMANCE: Only log, don't trigger heavy refreshes on every appear
            SessionLogManager.shared.logScreen(.dashboard, metadata: [
                "workouts_count": Int(userManager.currentUser?.totalWorkouts ?? 0),
                "has_active_program": generatedProgramService.activeProgram != nil
            ])
            // NUJ telemetry — see NewUserJourneyTracker. No-op when user is
            // outside their 72h window (Self.isActive guard inside).
            NewUserJourneyTracker.shared.logScreen("dashboard")
            
            // 🎯 SMART CAROUSEL DEFAULT: Active Program (page 1) if user has one, otherwise Custom/Auto (page 0)
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                if activeSmartProgramForWidget != nil {
                    selectedWorkoutPage = 1
                } else {
                    selectedWorkoutPage = 0
                }
            }
            if activeSmartProgramForWidget != nil {
                AppLogger.debug("[CAROUSEL] Defaulting to Active Program (page 1)", category: .ui)
            } else {
                AppLogger.debug("[CAROUSEL] Defaulting to Custom/Auto (page 0)", category: .ui)
            }
            
            rebuildCombinedWorkouts()
            
            // Mark user as welcomed after first visit (delayed slightly to show "Welcome to Fit33" first)
            if let userId = userManager.currentUser?.id {
                let welcomeKey = "has_been_welcomed_\(userId.uuidString)"
                if !UserDefaults.standard.bool(forKey: welcomeKey) {
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(2.0))
                        guard !Task.isCancelled else { return }
                        UserDefaults.standard.set(true, forKey: welcomeKey)
                        AppLogger.debug("[WELCOME] User marked as welcomed - will show 'Welcome back' next time", category: .ui)
                    }
                }
            }
            
            // 📱 PHONE VERIFICATION PROMPT (v1.14.3+)
            if !hasSeenPhonePrompt && !userHasVerifiedPhone && userManager.hasCompletedOnboarding {
                let alreadyChecked = UserDefaults.standard.bool(forKey: "phone_verified_check_done")
                if alreadyChecked {
                    hasSeenPhonePrompt = true
                } else {
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1.5))
                        guard !Task.isCancelled else { return }
                        guard !hasSeenPhonePrompt && !userHasVerifiedPhone else { return }
                        let existingPhone = await SupabaseManager.shared.getUserPhoneNumber()
                        if let phone = existingPhone, !phone.isEmpty {
                            userHasVerifiedPhone = true
                            hasSeenPhonePrompt = true
                            UserDefaults.standard.set(true, forKey: "phone_verified_check_done")
                        } else {
                            showPhoneVerificationPrompt = true
                        }
                    }
                }
            }
            
        }
        .task(id: "dashboard_initial_load") {
            // Whole hydrate path measured — p50/p95/p99 trend fed into
            // performance_metrics.op='dashboard.hydrate' by Cluster I.
            let hydrateState = PerformanceSignposts.begin(.dashboardHydrate)
            defer { PerformanceSignposts.end(hydrateState, slowThresholdMs: 4_000) }

            let dashStart = CFAbsoluteTimeGetCurrent()

            // Fire all independent work in parallel — nothing waits for anything else
            
            // 1. Insights (independent)
            Task {
                await insightsService.fetchActiveInsights()
                await insightsService.fetchStreaks()
            }
            
            // 2. Motivational message is ONLY used as a last-resort fallback
            // when the personalized recommendation can't be loaded (e.g.
            // unauthenticated / offline). We generate it lazily so it's
            // ready if needed, but we don't commit it to the welcome card
            // until after the recommendation has been attempted — otherwise
            // the card flashes a random motivational line ("your back could
            // use some work") before the real "close the gap" nudge
            // ("so close — walk 493 more steps") arrives.
            let messageTask = Task { await self.generateMotivationalMessage() }
            
            // 3. Cardio (independent, fire-and-forget)
            Task { await loadRecentCardioWorkouts() }
            
            // 4. Health sync (awaitable — recommendation needs fresh step
            // counts so the "walk N more steps" nudge can surface on first
            // load instead of only after pull-to-refresh)
            let healthTask = Task { await HealthDataService.shared.syncAllHealthData(force: false) }
            
            // 5. Social/challenge data (needs auth — wait only for these)
            let socialTask = Task {
                // Cluster D centralized gate — replaces the inline
                // publisher-race pattern. `waitForFreshSession` calls
                // `recoverSessionIfNeeded` once + awaits `$isAuthenticated`
                // with a timeout, collapsing what used to be 14 independent
                // 401 races into one.
                let authReady = await SupabaseManager.shared.waitForFreshSession(timeout: 10.0)
                guard !Task.isCancelled, authReady else {
                    AppLogger.warning(
                        "[DASHBOARD] Auth not available — skipping social fetch",
                        category: .performance,
                        context: DiagnosticContext(op: "dashboard.social_fanout", endpoint: "gate_timeout")
                    )
                    return
                }
                
                let authMs = Int((CFAbsoluteTimeGetCurrent() - dashStart) * 1000)
                AppLogger.info("[DASHBOARD] Auth ready (\(authMs)ms), starting all social fetches", category: .performance)

                // ⚡️ Cold-start sprint 2026-04-25 (Restore Cold-Start Performance plan, Change 1):
                //
                // PREVIOUSLY: 12-wide `async let` group awaited every social /
                // challenge / quest / photo fetch before the dashboard
                // considered itself "ready". The slowest-of-12 was usually a
                // network round-trip on cold start, dominating user-perceived
                // load (observed `dashboard.social_fanout` 4288ms in
                // 2026-04-25T19:49 logs — UI was unresponsive throughout).
                //
                // NEW BEHAVIOR — split into TWO buckets:
                //   CRITICAL (awaited): the four fetches whose results the
                //     dashboard body actually renders meaningfully on first
                //     paint — `friends`, `activeCh`, `priv`, `photo`. All
                //     four already have cached values pre-decoded by
                //     StartupCachePreloader, so the `await` here just upgrades
                //     cached → fresh; it doesn't gate first paint.
                //   DEFERRED (fire-and-forget): everything else. Each fetch
                //     publishes to its own `@Published` and the dashboard
                //     swaps cached → fresh in place when it lands. No
                //     flicker — same-shape state replacement. The
                //     `dailyQuestService.completedCount` `.onChange` handler
                //     at the bottom of this view re-runs
                //     `loadPersonalizedRecommendation` when quests arrive,
                //     so the welcome-card "close the gap" nudge still
                //     surfaces post-fan-out.
                //
                // Result: `dashboard.social_fanout` interval bounded by ~4
                // mostly-cached calls instead of 12 network round-trips.
                let fanOutState = PerformanceSignposts.begin(.dashboardSocialFanOut)

                // Fire-and-forget (not dashboard-body-critical)
                Task { await PrivateChallengeService.shared.subscribeToRealtimeUpdates() }
                Task { await ContactsService.shared.refreshSuggestions() }
                Task { await FriendService.shared.loadPendingRequests() }
                Task { await FriendService.shared.loadReceivedWorkouts() }
                Task { await ActivityFeedService.shared.fetchFeed() }
                Task { await FriendRankingService.shared.fetchRankedFriends() }
                Task { await ChallengeService.shared.fetchActiveGroupChallenges() }
                Task { await ChallengeService.shared.fetchPendingInvites() }
                Task { await ChallengeService.shared.fetchPendingSentChallenges() }

                // Dashboard-body-critical — awaited. All five have pre-decoded
                // cached values that the body already shows; await upgrades
                // them to fresh. `quests` stays in this bucket because
                // `loadPersonalizedRecommendation` (called after this Task
                // completes) reads fresh quest state to pick the right
                // welcome-card priority. Without this await, the welcome
                // card would briefly flash a lower-priority message before
                // the "close the gap" nudge could surface — the exact
                // flicker the previous Phase 4 N2 sprint fixed.
                async let friends: () = FriendService.shared.fetchFriends()
                async let activeCh: () = ChallengeService.shared.fetchActiveChallenges()
                async let priv: () = PrivateChallengeService.shared.refreshAll()
                async let photo: () = loadProfilePhoto()
                async let quests: () = dailyQuestService.fetchDailyQuests()
                _ = await (friends, activeCh, priv, photo, quests)
                PerformanceSignposts.end(fanOutState, slowThresholdMs: 3_000)
            }
            
            // Wait for steps + quests to be loaded before computing the
            // recommendation. This eliminates the welcome-card flicker
            // where the card briefly showed a lower-priority message
            // (e.g. "You perform best in the afternoons") before the
            // Priority 1.5 "close the gap" nudge could surface with live
            // quest/step data.
            _ = await (healthTask.value, socialTask.value)
            await loadPersonalizedRecommendation()
            
            // Only fall back to the random motivational message if the
            // recommendation truly couldn't load (unauth / offline).
            // Otherwise keep the motivational text suppressed so it never
            // flashes on top of the real recommendation.
            if personalizedRecommendation == nil {
                currentMotivationalMessage = await messageTask.value
            } else {
                messageTask.cancel()
            }
            
            let dashMs = Int((CFAbsoluteTimeGetCurrent() - dashStart) * 1000)
            AppLogger.info("[DASHBOARD] Initial load completed in \(dashMs)ms", category: .performance)
        }
        .onChange(of: recentWorkouts.count) { _, _ in rebuildCombinedWorkouts() }
        .onChange(of: recentCardioWorkouts.count) { _, _ in rebuildCombinedWorkouts() }
        .onChange(of: userManager.currentUser?.totalWorkouts) { _, _ in
            rebuildCombinedWorkouts()
            Task {
                try? await Task.sleep(nanoseconds: 500_000_000)
                await loadPersonalizedRecommendation()
            }
        }
        // Refresh the welcome card recommendation when quest state changes.
        // This keeps the "close the gap" nudge accurate — e.g. as soon as
        // the user finishes their workout quest, the card flips from
        // "great day for legs" to "walk 500 more steps to hit 3/3 goals".
        .onChange(of: dailyQuestService.completedCount) { _, _ in
            Task { await loadPersonalizedRecommendation() }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            // Only refresh when coming from background (not from inactive which happens during navigation)
            // This prevents refresh from interfering with navigation
            if oldPhase == .background && newPhase == .active {
                if let user = userManager.currentUser {
                    streakShieldService.checkStreakRisk(
                        lastWorkoutDate: user.lastWorkoutDate,
                        currentStreak: Int(user.currentStreak)
                    )
                }
                
                // Dashboard-specific foreground work only (social/health handled by Fit33App)
                Task {
                    let calendar = Calendar.current
                    let dayChanged = calendar.startOfDay(for: lastChallengeRefreshDate) < calendar.startOfDay(for: Date())
                    
                    MealService.shared.loadTodaysMeals()
                    await HydrationService.shared.loadTodayData()
                    
                    if dayChanged {
                        await dailyQuestService.fetchDailyQuests(force: true)
                        lastChallengeRefreshDate = Date()
                    }
                    
                    await FriendService.shared.refreshHomeScreenData()
                }
            }
        }
        .onReceive(stravaService.$lastSyncDate) { newDate in
            if newDate != nil {
                Task { await loadRecentCardioWorkouts() }
            }
        }
        .onReceive(healthKitService.$lastSyncDate) { newDate in
            if newDate != nil {
                Task { await loadRecentCardioWorkouts() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .externalWorkoutSynced)) { _ in
            // Reload cardio workouts when an external workout (Apple Watch, Nike Run Club, etc.)
            // is detected and synced to Supabase via the HealthKit workout observer
            Task { await loadRecentCardioWorkouts() }
        }
    }

    // MARK: - Deep Link Helper
    /// Extracted from `body` to keep the SwiftUI type-checker happy. The
    /// inline closure plus its nested `if let` chain was tipping `body` over
    /// the "expression too complex" budget.
    ///
    /// Bug fix 2026-04-27 — widget→detail flicker: the previous version
    /// wrapped this in `Task { ... try? await Task.sleep(for: .seconds(0.15)) }`
    /// which made the user stare at the Dashboard for 150ms before the
    /// navigation push slid in. The sleep was a workaround for the cold-
    /// launch race where `ChallengeService.activeChallenges` hadn't
    /// hydrated yet. We now address that race directly via retry-on-miss
    /// (`pushChallengeDetailIfPossible`) and push immediately + with
    /// animation disabled on the warm path. Result: tap widget → detail
    /// is on-screen at the next frame, no Dashboard glimpse, no slide.
    private func handlePendingDashboardRoute(_ route: String?) {
        guard let route else { return }
        if route == "ChallengeCreation" {
            showingChallengeCreation = true
            deepLinkManager.pendingDashboardRoute = nil
            return
        }
        if route.hasPrefix("ChallengeDetail:") {
            let idStr = String(route.dropFirst("ChallengeDetail:".count))
            pushChallengeDetailIfPossible(idStr: idStr, attempt: 0)
        }
    }

    /// Resolves a challenge id against `ChallengeService` caches and
    /// pushes it onto `dashboardNavPath` with animation disabled so the
    /// transition from widget → detail looks instant. Falls back to a
    /// short retry loop (max ~360ms total) when the cache hasn't
    /// hydrated yet on cold launch — once it lands or we exhaust
    /// attempts, we clear the pending route.
    private func pushChallengeDetailIfPossible(idStr: String, attempt: Int) {
        if let challenge = ChallengeService.shared.activeChallenges.first(where: { $0.challengeId.uuidString == idStr }) {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                dashboardNavPath.append(challenge)
            }
            AppLogger.debug("[DEEPLINK] Pushed 1v1 challenge detail: \(challenge.title)", category: .ui)
            deepLinkManager.pendingDashboardRoute = nil
            return
        }
        if let groupChallenge = ChallengeService.shared.activeGroupChallenges.first(where: { $0.challengeId.uuidString == idStr }) {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                dashboardNavPath.append(groupChallenge)
            }
            AppLogger.debug("[DEEPLINK] Pushed group challenge detail: \(groupChallenge.displayTitle)", category: .ui)
            deepLinkManager.pendingDashboardRoute = nil
            return
        }
        // Cache miss — typical only on cold launch where the active-
        // challenges cache hasn't hydrated yet. Three quick retries at
        // 120ms each cover the gap; after that we give up and leave the
        // user on the Dashboard rather than spin forever.
        guard attempt < 3 else {
            AppLogger.warning("[DEEPLINK] Challenge not found after \(attempt) retries for ID: \(idStr) — staying on dashboard", category: .ui)
            deepLinkManager.pendingDashboardRoute = nil
            return
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            pushChallengeDetailIfPossible(idStr: idStr, attempt: attempt + 1)
        }
    }
}

#Preview {
    DashboardView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(UserManager())
}

