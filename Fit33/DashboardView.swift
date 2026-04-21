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
                
                ScrollViewReader { scrollProxy in
                    ScrollView(showsIndicators: false) {
                    Color.clear
                    .frame(height: 0)
                    .id("top")
                    
                    LazyVStack(spacing: 0) {
                    // Custom header with title and profile icon
                    customHeaderView
                        .padding(.top, 0)
                        .padding(.bottom, 16)
                    
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
                    DashboardChallengesWrapper(showingChallengeCreation: $showingChallengeCreation)
                        .environmentObject(userManager)
                        .padding(.bottom, 16)
                    
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
                    
                    // WHOOP Recovery Widget (isolated — only renders when WHOOP connected + widget enabled)
                    if showWhoopWidget {
                        DashboardWhoopWrapper()
                            .padding(.bottom, 16)
                    }

                    // Oura Readiness Widget (isolated — only renders when Oura connected + widget enabled)
                    if showOuraWidget {
                        DashboardOuraWrapper()
                            .padding(.bottom, 16)
                    }

                    // Step Tracker Card
                    StepTrackerCard()
                        .id("stepTracker")
                        .padding(.bottom, 20)

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
                    // STEP 1: Sync ALL connected health sources (HealthKit, Strava, Fitbit)
                    // force: true bypasses 5-minute throttle since user explicitly pulled to refresh
                    await HealthDataService.shared.syncAllHealthData(force: true)
                    
                    // STEP 2: Fetch ALL challenge types from database (parallel for speed)
                    async let r1: () = ChallengeService.shared.fetchPendingInvites()
                    async let r2: () = ChallengeService.shared.fetchActiveChallenges()
                    async let r3: () = ChallengeService.shared.fetchActiveGroupChallenges()
                    async let r4: () = ChallengeService.shared.fetchPendingSentChallenges()
                    async let r5: () = CommunityChallengeService.shared.refreshAll(force: true)
                    async let r6: () = PrivateChallengeService.shared.refreshAll(force: true)
                    _ = await (r1, r2, r3, r4, r5, r6)
                    
                    // STEP 3: Refresh friend data and other home screen content
                    await FriendService.shared.refreshHomeScreenData()
                    await loadRecentCardioWorkouts()
                    await loadPersonalizedRecommendation()
                }
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
                    showOura: $showOuraWidget
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
            guard let route = route else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.15))
                guard !Task.isCancelled else { return }
                if route == "ChallengeCreation" {
                    showingChallengeCreation = true
                } else if route.hasPrefix("ChallengeDetail:") {
                    let idStr = String(route.dropFirst("ChallengeDetail:".count))
                    if let challenge = ChallengeService.shared.activeChallenges.first(where: { $0.challengeId.uuidString == idStr }) {
                        dashboardNavPath.append(challenge)
                        AppLogger.debug("[DEEPLINK] Pushed 1v1 challenge detail: \(challenge.title)", category: .ui)
                    }
                    // Look up group challenge
                    else if let groupChallenge = ChallengeService.shared.activeGroupChallenges.first(where: { $0.challengeId.uuidString == idStr }) {
                        dashboardNavPath.append(groupChallenge)
                        AppLogger.debug("[DEEPLINK] Pushed group challenge detail: \(groupChallenge.displayTitle)", category: .ui)
                    } else {
                        AppLogger.warning("[DEEPLINK] Challenge not found for ID: \(idStr) — staying on dashboard", category: .ui)
                    }
                }
                deepLinkManager.pendingDashboardRoute = nil
            }
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
                if !SupabaseManager.shared.isAuthenticated {
                    AppLogger.info("[DASHBOARD] Auth not ready — waiting via publisher (up to 10s)...", category: .performance)
                    let authReady = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                        let resumed = NSLock()
                        var hasResumed = false
                        var cancellable: AnyCancellable?
                        
                        let sleepTask = Task {
                            try? await Task.sleep(for: .seconds(10))
                            resumed.lock()
                            guard !hasResumed else { resumed.unlock(); return }
                            hasResumed = true
                            resumed.unlock()
                            cancellable?.cancel()
                            continuation.resume(returning: false)
                        }
                        
                        cancellable = SupabaseManager.shared.$isAuthenticated
                            .first(where: { $0 })
                            .sink { _ in
                                resumed.lock()
                                guard !hasResumed else { resumed.unlock(); return }
                                hasResumed = true
                                resumed.unlock()
                                sleepTask.cancel()
                                continuation.resume(returning: true)
                            }
                    }
                    guard !Task.isCancelled, authReady else {
                        if !authReady {
                            AppLogger.warning("[DASHBOARD] Auth not available — skipping social fetch", category: .performance)
                        }
                        return
                    }
                }
                
                guard SupabaseManager.shared.isAuthenticated else {
                    AppLogger.warning("[DASHBOARD] Auth not available — skipping social fetch", category: .performance)
                    return
                }
                
                let authMs = Int((CFAbsoluteTimeGetCurrent() - dashStart) * 1000)
                AppLogger.info("[DASHBOARD] Auth ready (\(authMs)ms), starting all social fetches", category: .performance)
                
                // All social, challenge, quest, and contact fetches in ONE parallel group
                async let friends: () = FriendService.shared.fetchFriends()
                async let pending: () = FriendService.shared.loadPendingRequests()
                async let received: () = FriendService.shared.loadReceivedWorkouts()
                async let feed: () = ActivityFeedService.shared.fetchFeed()
                async let ranked: () = FriendRankingService.shared.fetchRankedFriends()
                async let activeCh: () = ChallengeService.shared.fetchActiveChallenges()
                async let groupCh: () = ChallengeService.shared.fetchActiveGroupChallenges()
                async let invites: () = ChallengeService.shared.fetchPendingInvites()
                async let sent: () = ChallengeService.shared.fetchPendingSentChallenges()
                async let priv: () = PrivateChallengeService.shared.refreshAll()
                async let rt: () = PrivateChallengeService.shared.subscribeToRealtimeUpdates()
                async let quests: () = dailyQuestService.fetchDailyQuests()
                async let contacts: () = ContactsService.shared.refreshSuggestions()
                async let photo: () = loadProfilePhoto()
                _ = await (friends, pending, received, feed, ranked, activeCh, groupCh, invites, sent, priv, rt, quests, contacts, photo)
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

}

#Preview {
    DashboardView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(UserManager())
}

