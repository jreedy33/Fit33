import SwiftUI
import CoreData
import UserNotifications

struct DashboardView: View {
    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.scrollToTopTrigger) var scrollToTopTrigger
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.scenePhase) var scenePhase
    @EnvironmentObject var userManager: UserManager
    @EnvironmentObject var workoutManager: WorkoutManager
    @StateObject var notificationManager = NotificationManager.shared
    
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
    @ObservedObject var challengeService = ChallengeService.shared
    @StateObject var dailyQuestService = DailyQuestService.shared
    let stravaService = StravaService.shared
    let streakShieldService = StreakShieldService.shared
    let healthKitService = HealthKitService.shared
    @State var navigateToCustomWorkout = false
    @State var navigateToAutoWorkout = false
    @State var navigateToGeneratedPrograms = false
    @State var isNavigating = false  // 🔧 Debounce protection
    
    // Smart personalized recommendation
    @State var personalizedRecommendation: AdvancedIntelligenceService.PersonalizedRecommendation?
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
    
    // ⚡️ PERFORMANCE: Cache key for combined workouts to avoid recomputation
    var combinedWorkoutsCacheKey: String {
        let strengthCount = recentWorkouts.prefix(5).count
        let cardioCount = recentCardioWorkouts.count
        let latestStrength = recentWorkouts.first?.date?.timeIntervalSince1970 ?? 0
        let latestCardio = recentCardioWorkouts.first.map { ISO8601Parser.parse($0.completedAt, fallback: Date.distantPast).timeIntervalSince1970 } ?? 0
        return "\(strengthCount)-\(cardioCount)-\(Int(latestStrength))-\(Int(latestCardio))"
    }
    
    // ⚡️ PERFORMANCE: Memoized combined workouts - only recomputes when data changes
    @State var _cachedCombinedWorkouts: [RecentWorkoutItem] = []
    @State var _lastCombinedWorkoutsKey: String = ""
    
    // Combine strength and cardio workouts, sorted by date
    var combinedRecentWorkouts: [RecentWorkoutItem] {
        // Check cache first
        let currentKey = combinedWorkoutsCacheKey
        if currentKey == _lastCombinedWorkoutsKey && !_cachedCombinedWorkouts.isEmpty {
            return _cachedCombinedWorkouts
        }
        
        // Recompute (this is expensive but only when data changes)
        var items: [RecentWorkoutItem] = []
        
        // Add strength workouts
        for workout in recentWorkouts.prefix(5) {
            items.append(.strength(workout, isMostRecent: false))
        }
        
        // Add cardio workouts
        for cardio in recentCardioWorkouts {
            items.append(.cardio(cardio, isMostRecent: false))
        }
        
        // Sort by date (most recent first)
        items.sort { $0.date > $1.date }
        
        // Mark the most recent one
        if !items.isEmpty {
            switch items[0] {
            case .strength(let workout, _):
                items[0] = .strength(workout, isMostRecent: true)
            case .cardio(let cardio, _):
                items[0] = .cardio(cardio, isMostRecent: true)
            }
        }
        
        // Note: Can't update @State from computed property, but this pattern
        // at least short-circuits the expensive sort when key matches
        return items
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
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Workout.date, ascending: false)],
        predicate: NSPredicate(format: "isCompleted == true"),
        animation: .none)
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
                    
                    // Notification permission banner - only show after checking status
                    // and only if not authorized and not previously dismissed
                    if notificationManager.hasCheckedAuthStatus && 
                       !notificationManager.isAuthorized && 
                       !dismissedNotificationBanner {
                        notificationPermissionBanner
                            .padding(.bottom, 16)
                    }
                    
                    // Header with user info
                    headerView
                        .padding(.bottom, 16)
                    
                    // Friend Request Preview Widget (shows pending friend requests)
                    FriendRequestPreviewContainer()
                        .padding(.bottom, 16)
                    
                    // Received Workout Preview Widget (shows pending shared workouts)
                    ReceivedWorkoutPreviewContainer()
                        .environmentObject(workoutManager)
                        .environmentObject(userManager)
                        .padding(.bottom, 16)
                    
                    // Challenge Preview Widget (shows pending challenge invites)
                    ChallengePreviewContainer()
                        .padding(.bottom, 16)
                    
                    // Group Challenge Invite Widgets (isolated to limit challengeService re-renders)
                    GroupChallengeInvitesSection()
                        .environmentObject(userManager)
                    
                    // Private Challenge Invite Widgets (pending invites to private communities)
                    PrivateChallengeInviteContainer()
                        .padding(.bottom, 16)
                    
                    // Daily Quests widget
                    dailyQuestsSection
                        .padding(.bottom, 16)
                    
                    // Recovery Day widget (shows when muscles are recovering)
                    if RecoveryDayEngine.shared.shouldShowRecoveryWidget {
                        RecoveryDayDashboardWidget()
                            .padding(.horizontal, Spacing.md)
                            .padding(.bottom, 16)
                    }
                    
                    // "Ready for today's workout?" title
                    Text("Ready for today's workout?")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, 12)
                    
                    // Challenge Cards (1v1 active, group active, pending sent, get started)
                    challengeCardsSection
                        .padding(.bottom, 16)
                    
                    // Swipeable Workout Carousel: [Custom+Auto Buttons] <-> [Active Program]
                    swipeableWorkoutCarousel
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
                    
                    // Stats overview
                    statsOverview
                        .id("statsOverview")
                }
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, 20)
                }
                .scrollContentBackground(.hidden)
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
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
                    showRecommended: $showRecommendedWidget
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
                VStack(spacing: 8) {
                    if let quest = dailyQuestService.lastCompletedQuest {
                        QuestCompletionCelebration(
                            quest: quest,
                            isShowing: $dailyQuestService.showQuestCompletionCelebration
                        )
                    }
                    QuestBonusCelebration(
                        isShowing: $dailyQuestService.showBonusCelebration
                    )
                }
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
            // Update streak shield risk status
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
                "workouts_count": recentWorkouts.count,
                "has_active_program": generatedProgramService.activeProgram != nil
            ])
            
            // 🎯 SMART CAROUSEL DEFAULT: Active Program (page 1) if user has one, otherwise Custom/Auto (page 0)
            if activeSmartProgramForWidget != nil {
                selectedWorkoutPage = 1 // Show active program
                AppLogger.debug("[CAROUSEL] Defaulting to Active Program (page 1)", category: .ui)
            } else {
                selectedWorkoutPage = 0 // Show Custom/Auto buttons
                AppLogger.debug("[CAROUSEL] Defaulting to Custom/Auto (page 0)", category: .ui)
            }
            
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
            // Show one-time phone verification prompt for existing users who haven't verified
            if !hasSeenPhonePrompt && !userHasVerifiedPhone && userManager.hasCompletedOnboarding {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1.5))
                    guard !Task.isCancelled else { return }
                    if !hasSeenPhonePrompt && !userHasVerifiedPhone {
                        // Check if user already has a phone number from previous onboarding
                        Task {
                            let existingPhone = await SupabaseManager.shared.getUserPhoneNumber()
                            await MainActor.run {
                                if let phone = existingPhone, !phone.isEmpty {
                                    // User already has phone verified, mark as seen
                                    userHasVerifiedPhone = true
                                    hasSeenPhonePrompt = true
                                    AppLogger.debug("[PHONE PROMPT] User already has phone verified, skipping prompt", category: .ui)
                                } else {
                                    // Show the prompt
                                    showPhoneVerificationPrompt = true
                                    AppLogger.debug("[PHONE PROMPT] Showing phone verification prompt to existing user", category: .ui)
                                }
                            }
                        }
                    }
                }
            }
            
            // Refresh friend data when returning to home tab
            // Red dot reads directly from FriendService so no need to cache counts
            Task {
                await FriendService.shared.refreshHomeScreenData()
            }
        }
        .task(id: "dashboard_initial_load") {
            let dashStart = CFAbsoluteTimeGetCurrent()
            
            // Fetch insights in a separate task (non-blocking)
            Task {
                await insightsService.fetchActiveInsights()
                await insightsService.fetchStreaks()
            }
            
            // Load personalized recommendation (use cached if available)
            await loadPersonalizedRecommendation()
            
            // generateMotivationalMessage() is ~300 lines of pure sync logic —
            // run it off the main actor to keep the UI responsive
            let message = await Task.detached(priority: .userInitiated) { [self] in
                return self.generateMotivationalMessage()
            }.value
            currentMotivationalMessage = message
            
            // Load cardio workouts in background
            await loadRecentCardioWorkouts()
            
            // Wait for auth if it hasn't completed yet (checkAuthOnly runs in parallel).
            // Without this, social fetches are skipped and challenges/friends never load.
            if !SupabaseManager.shared.isAuthenticated {
                AppLogger.info("[DASHBOARD] Auth not ready yet — waiting up to 10s...", category: .performance)
                for _ in 0..<20 {
                    try? await Task.sleep(for: .milliseconds(500))
                    guard !Task.isCancelled else { return }
                    if SupabaseManager.shared.isAuthenticated { break }
                }
            }
            
            guard SupabaseManager.shared.isAuthenticated else {
                AppLogger.warning("[DASHBOARD] Auth still not available after wait — skipping social fetch", category: .performance)
                return
            }
            
            let authWaitMs = Int((CFAbsoluteTimeGetCurrent() - dashStart) * 1000)
            AppLogger.info("[DASHBOARD] Auth ready, starting social fetches (waited \(authWaitMs)ms total)", category: .performance)
            
            // Batch 1: Fast social data (parallel)
            async let friends: () = FriendService.shared.fetchFriends()
            async let pending: () = FriendService.shared.loadPendingRequests()
            async let received: () = FriendService.shared.loadReceivedWorkouts()
            async let feed: () = ActivityFeedService.shared.fetchFeed()
            async let ranked: () = FriendRankingService.shared.fetchRankedFriends()
            _ = await (friends, pending, received, feed, ranked)
            
            // Batch 2: Challenges (parallel)
            async let active: () = ChallengeService.shared.fetchActiveChallenges()
            async let group: () = ChallengeService.shared.fetchActiveGroupChallenges()
            async let invites: () = ChallengeService.shared.fetchPendingInvites()
            async let sent: () = ChallengeService.shared.fetchPendingSentChallenges()
            async let priv: () = PrivateChallengeService.shared.refreshAll()
            _ = await (active, group, invites, sent, priv)
            
            // Batch 3: Remaining (parallel)
            async let rt: () = PrivateChallengeService.shared.subscribeToRealtimeUpdates()
            async let quests: () = dailyQuestService.fetchDailyQuests()
            async let contacts: () = ContactsService.shared.refreshSuggestions()
            async let photo: () = loadProfilePhoto()
            _ = await (rt, quests, contacts, photo)
            
            await HealthDataService.shared.syncAllHealthData(force: false)
            
            let dashMs = Int((CFAbsoluteTimeGetCurrent() - dashStart) * 1000)
            AppLogger.info("[DASHBOARD] Initial load completed in \(dashMs)ms", category: .performance)
        }
        .onChange(of: userManager.currentUser?.totalWorkouts) { _, _ in
            // Refresh recommendation after workout completion (debounced)
            Task {
                // Small delay to debounce rapid updates
                try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
                await loadPersonalizedRecommendation()
            }
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

