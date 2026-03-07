import SwiftUI
import CoreData
import UserNotifications

// MARK: - Dashboard Navigation Route

enum DashboardRoute: Hashable {
    case profile
    case mealPlan
    case workoutHistory
    case programDetailsPlaceholder
    case generatedProgramsList
    case personalizedPrograms
    case smartWorkoutPreview  // uses GeneratedProgramService.shared
    case smartProgramOverview(programId: String)
    case smartProgramDayPreview(programId: String, dayNumber: Int)
}

struct DashboardView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.scrollToTopTrigger) private var scrollToTopTrigger
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var userManager: UserManager
    @EnvironmentObject var workoutManager: WorkoutManager
    @StateObject private var notificationManager = NotificationManager.shared
    
    
    
    private var cardBackgroundGradient: [Color] {
        colorScheme == .dark 
            ? [Color(white: 0.18), Color.cardBackground]
            : [Color.white, Color.white.opacity(0.95)]
    }
    @State private var showingWorkoutCreation = false
    @State private var workoutCreationType: WorkoutCreationType = .custom
    @State private var scrollOffset: CGFloat = 0
    @State private var showingProgramConflictAlert = false
    @State private var pendingWorkoutType: PendingWorkoutType? = nil
    @State private var navigateToTodaysWorkout = false
    @State private var programWidgetRotation: Double = 0
    @State private var challengeGlowPhase: CGFloat = 0
    
    // Phone verification prompt for existing users (v1.14.3+)
    @State private var showPhoneVerificationPrompt = false
    @AppStorage("hasSeenPhonePrompt_v1143") private var hasSeenPhonePrompt = false
    @AppStorage("userHasVerifiedPhone") private var userHasVerifiedPhone = false
    
    // Swipeable widget state (challenges only now)
    @State private var selectedWidgetPage: Int = 0
    @State private var widgetSwipeInProgress: Bool = false
    
    
    // Swipeable workout carousel (workout buttons + active program)
    @State private var selectedWorkoutPage: Int = 0
    @ObservedObject private var challengeService = ChallengeService.shared
    @ObservedObject private var privateChallengeService = PrivateChallengeService.shared
    @ObservedObject private var friendService = FriendService.shared
    @StateObject private var dailyQuestService = DailyQuestService.shared
    @ObservedObject private var stravaService = StravaService.shared
    @ObservedObject private var healthKitService = HealthKitService.shared
    @State private var navigateToCustomWorkout = false
    @State private var navigateToAutoWorkout = false
    @State private var navigateToGeneratedPrograms = false
    @State private var isNavigating = false  // 🔧 Debounce protection
    
    // Smart personalized recommendation
    @State private var personalizedRecommendation: AdvancedIntelligenceService.PersonalizedRecommendation?
    @State private var isLoadingRecommendation = false
    @State private var currentMotivationalMessage: String = ""
    
    // Personalized insights service for smart rotating messages
    @StateObject private var insightsService = PersonalizedInsightsService.shared
    
    // Cardio workouts from Supabase
    @State private var recentCardioWorkouts: [CardioWorkoutDTO] = []
    @State private var totalCardioWorkoutCount: Int = 0  // All-time cardio count (not limited to 5)
    
    // Profile photo for home icon
    @State private var profilePhotoURL: String? = nil
    
    // Track last challenge refresh date for midnight auto-sync
    @State private var lastChallengeRefreshDate: Date = Date()
    
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
    private var combinedWorkoutsCacheKey: String {
        let strengthCount = recentWorkouts.prefix(5).count
        let cardioCount = recentCardioWorkouts.count
        let latestStrength = recentWorkouts.first?.date?.timeIntervalSince1970 ?? 0
        let latestCardio = recentCardioWorkouts.first.map { ISO8601Parser.parse($0.completedAt, fallback: Date.distantPast).timeIntervalSince1970 } ?? 0
        return "\(strengthCount)-\(cardioCount)-\(Int(latestStrength))-\(Int(latestCardio))"
    }
    
    // ⚡️ PERFORMANCE: Memoized combined workouts - only recomputes when data changes
    @State private var _cachedCombinedWorkouts: [RecentWorkoutItem] = []
    @State private var _lastCombinedWorkoutsKey: String = ""
    
    // Combine strength and cardio workouts, sorted by date
    private var combinedRecentWorkouts: [RecentWorkoutItem] {
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
    @State private var showStreakInfo = false
    
    // Challenge widget navigation - goes to Profile's FriendsListView
    @State private var showFriendsListForChallenge = false
    
    // Challenge creation flow states
    @State private var showingChallengeCreation = false
    @State private var showCommunityHub = false
    
    // Widget settings
    @State private var showingWidgetSettings = false
    @AppStorage("showWeightTrackerWidget") private var showWeightTrackerWidget = true  // Default ON
    @AppStorage("showHydrationWidget") private var showHydrationWidget = false
    @AppStorage("showMacrosWidget") private var showMacrosWidget = false  // Nutrition macros quick-access
    @AppStorage("showChallengeWidget") private var showChallengeWidget = true  // Challenge a Friend widget (premium can hide)
    @AppStorage("showRecommendedWidget") private var showRecommendedWidget = true  // Recommended For You widget (premium can hide)
    
    // Nutrition data for macros widget
    @ObservedObject private var mealService = MealService.shared
    @State private var selectedMacrosPage: Int = 0  // For swipeable macros cards
    
    // Used to force NavigationStack to reset when switching tabs
    @State private var navigationViewId = UUID()
    @State private var dashboardNavPath = NavigationPath()
    @ObservedObject private var deepLinkManager = DeepLinkManager.shared
    @ObservedObject private var cloudProgramService = CloudProgramService.shared
    @ObservedObject private var generatedProgramService = GeneratedProgramService.shared
    @ObservedObject private var smartProgramEngine = SmartProgramEngine.shared
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Workout.date, ascending: false)],
        predicate: NSPredicate(format: "isCompleted == true"),
        animation: .none)  // Disable animation for faster updates
    private var recentWorkouts: FetchedResults<Workout>
    
    // Only show recent workouts for performance
    private var displayedWorkouts: [Workout] {
        Array(recentWorkouts.prefix(10))
    }
    
    
    var body: some View {
        NavigationStack(path: $dashboardNavPath) {
            ZStack {
                // Animated background with colored orbs
                AnimatedOrbBackground.home(colorScheme: colorScheme)
                
                ScrollViewReader { scrollProxy in
                    ScrollView(showsIndicators: false) {
                    GeometryReader { geometry in
                        Color.clear.preference(key: DashboardScrollOffsetKey.self, value: geometry.frame(in: .named("scroll")).minY)
                    }
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
                    
                    // Group Challenge Invite Widgets (invites I haven't accepted yet)
                    ForEach(challengeService.activeGroupChallenges.filter(\.isMyInvitePending)) { group in
                        GroupChallengeInviteWidget(challenge: group)
                            .environmentObject(userManager)
                            .padding(.bottom, 16)
                    }
                    
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
                    
                    // Quick Macros Widget
                    if showMacrosWidget {
                        dashboardMacrosWidget
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
                .coordinateSpace(name: "scroll")
                .onPreferenceChange(DashboardScrollOffsetKey.self) { value in
                    scrollOffset = value
                }
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
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
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
                    print("📜 [DASHBOARD] Scrolled to widget: \(widgetId)")
                }
                }
                .refreshable {
                    // STEP 1: Sync latest HealthKit data (steps, workouts, etc.)
                    // This will also call syncHealthKitDataToChallenges() internally
                    await HealthKitService.shared.syncAllData(force: true)
                    
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
                // Check if we're actually deep in navigation before doing the expensive .id() reset
                let hasDeepNavigation = navigateToAutoWorkout || navigateToCustomWorkout ||
                                        navigateToGeneratedPrograms || navigateToTodaysWorkout ||
                                        !dashboardNavPath.isEmpty
                
                // Reset all navigation states (pops NavigationLinks back to root)
                navigateToAutoWorkout = false
                navigateToCustomWorkout = false
                navigateToGeneratedPrograms = false
                navigateToTodaysWorkout = false
                showingChallengeCreation = false
                dashboardNavPath = NavigationPath()
                
                // ⚡️ PERFORMANCE FIX: Only destroy/recreate the view if we were actually
                // deep in navigation. For simple tab switches (99% case), just reset the
                // navigation link bindings. The .id() trick destroys the ENTIRE view hierarchy,
                // re-triggering .task (15+ network requests), .onAppear, and all subscriptions.
                if hasDeepNavigation {
                    navigationViewId = UUID()
                }
                
                workoutManager.shouldPopToRootHome = false
            }
        }
        // MARK: - Challenge Deep Link Navigation
        .onReceive(deepLinkManager.$pendingDashboardRoute) { route in
            guard let route = route else { return }
            // Small delay to ensure NavigationStack is ready after tab switch
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                if route.hasPrefix("ChallengeDetail:") {
                    let idStr = String(route.dropFirst("ChallengeDetail:".count))
                    // Look up 1v1 challenge
                    if let challenge = ChallengeService.shared.activeChallenges.first(where: { $0.challengeId.uuidString == idStr }) {
                        dashboardNavPath.append(challenge)
                        print("🏆 [DEEPLINK] Pushed 1v1 challenge detail: \(challenge.title)")
                    }
                    // Look up group challenge
                    else if let groupChallenge = ChallengeService.shared.activeGroupChallenges.first(where: { $0.challengeId.uuidString == idStr }) {
                        dashboardNavPath.append(groupChallenge)
                        print("🏆 [DEEPLINK] Pushed group challenge detail: \(groupChallenge.displayTitle)")
                    } else {
                        print("⚠️ [DEEPLINK] Challenge not found for ID: \(idStr) — staying on dashboard")
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
                print("📱 [CAROUSEL] Defaulting to Active Program (page 1)")
            } else {
                selectedWorkoutPage = 0 // Show Custom/Auto buttons
                print("📱 [CAROUSEL] Defaulting to Custom/Auto (page 0)")
            }
            
            // Mark user as welcomed after first visit (delayed slightly to show "Welcome to Fit33" first)
            if let userId = userManager.currentUser?.id {
                let welcomeKey = "has_been_welcomed_\(userId.uuidString)"
                if !UserDefaults.standard.bool(forKey: welcomeKey) {
                    // Delay marking as welcomed so they see "Welcome to Fit33" on first load
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        UserDefaults.standard.set(true, forKey: welcomeKey)
                        print("👋 [WELCOME] User marked as welcomed - will show 'Welcome back' next time")
                    }
                }
            }
            
            // 📱 PHONE VERIFICATION PROMPT (v1.14.3+)
            // Show one-time phone verification prompt for existing users who haven't verified
            if !hasSeenPhonePrompt && !userHasVerifiedPhone && userManager.hasCompletedOnboarding {
                // Delay slightly to let the home screen render first
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    // Double-check they still haven't seen it (in case of race conditions)
                    if !hasSeenPhonePrompt && !userHasVerifiedPhone {
                        // Check if user already has a phone number from previous onboarding
                        Task {
                            let existingPhone = await SupabaseManager.shared.getUserPhoneNumber()
                            await MainActor.run {
                                if existingPhone != nil && !existingPhone!.isEmpty {
                                    // User already has phone verified, mark as seen
                                    userHasVerifiedPhone = true
                                    hasSeenPhonePrompt = true
                                    print("📱 [PHONE PROMPT] User already has phone verified, skipping prompt")
                                } else {
                                    // Show the prompt
                                    showPhoneVerificationPrompt = true
                                    print("📱 [PHONE PROMPT] Showing phone verification prompt to existing user")
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
            // ⚡️ PERFORMANCE: Debounced initial data load - only runs once per view lifecycle
            // Uses a stable ID to prevent re-running on every appear
            
            // Generate fresh motivational message each time app opens
            currentMotivationalMessage = generateMotivationalMessage()
            
            // 🧠 Fetch personalized insights for smart rotating messages
            Task {
                await insightsService.fetchActiveInsights()
                await insightsService.fetchStreaks()
            }
            
            // Load personalized recommendation (use cached if available)
            await loadPersonalizedRecommendation()
            
            // Load cardio workouts in background
            await loadRecentCardioWorkouts()
            
            // Load friend data — also populates Friends tab cache for instant display
            await FriendService.shared.loadPendingRequests()
            await FriendService.shared.loadReceivedWorkouts()
            await FriendService.shared.fetchFriends() // ⚡️ Pre-fetch for Friends tab (caches to disk)
            
            // Load active challenges, pending invites, and pending sent challenges
            await ChallengeService.shared.fetchActiveChallenges()
            await ChallengeService.shared.fetchActiveGroupChallenges()  // Group challenges (3+ people)
            await ChallengeService.shared.fetchPendingInvites()
            await ChallengeService.shared.fetchPendingSentChallenges()
            
            // Load private challenge data (invites + active challenges) + real-time subscriptions
            await PrivateChallengeService.shared.refreshAll()
            await PrivateChallengeService.shared.subscribeToRealtimeUpdates()
            
            // Load daily quests (must be after auth-dependent calls above so currentUser is available)
            await dailyQuestService.fetchDailyQuests()
            
            // Pre-fetch ranked friends for Friends tab (caches to disk)
            await FriendRankingService.shared.fetchRankedFriends()
            
            // Load profile photo for home icon
            await loadProfilePhoto()
            
            // 🚀 COLD START FIX: Push current HealthKit data to all challenges
            // On cold start the Fit33App.scenePhase handler may fire before auth
            // is ready, so this ensures health data reaches the server ASAP.
            // HealthDataService.syncAllHealthData() handles HealthKit fetch + push
            // to 1v1 AND community challenges in one pass (with internal throttling).
            // ⚡️ Use force: false so the internal throttle prevents a double-sync
            // if Fit33App's scenePhase handler already triggered syncAllHealthData().
            // Using force: true was causing 40+ concurrent requests to flood URLSession,
            // leading to mass NSURLErrorDomain -999 cancellations of challenge RPCs.
            await HealthDataService.shared.syncAllHealthData(force: false)
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
                Task {
                    // 🌙 MIDNIGHT AUTO-SYNC: Check if the day has changed
                    let calendar = Calendar.current
                    let lastRefreshDay = calendar.startOfDay(for: lastChallengeRefreshDate)
                    let today = calendar.startOfDay(for: Date())
                    let dayChanged = lastRefreshDay < today
                    
                    if dayChanged {
                        print("🌙 [CHALLENGES] Day changed! Auto-refreshing for new day...")
                    }
                    
                    // ⚠️ Reload hydration + meal data BEFORE HealthKit sync.
                    // syncAllData() internally calls syncHealthKitDataToChallenges()
                    // which reads todaysMeals — if we don't refresh first, stale
                    // yesterday data gets pushed as today's progress on new days.
                    MealService.shared.loadTodaysMeals()
                    await HydrationService.shared.loadTodayData()
                    
                    // Sync HealthKit (this also syncs to challenges internally)
                    await HealthKitService.shared.syncAllData(force: true)
                    
                    // ⚡ Universal sync: push ALL tracking data (hydration, meals, HealthKit) to ALL challenge types
                    print("🔄 [DASHBOARD] Universal challenge sync on foreground...")
                    async let challengeSync: () = ChallengeService.shared.syncAllTrackingToChallenges()
                    async let communitySync: () = CommunityChallengeService.shared.syncAllTrackingToCommunityChallenges()
                    async let privateSync: () = PrivateChallengeService.shared.syncAllTrackingToPrivateChallenges()
                    _ = await (challengeSync, communitySync, privateSync)
                    
                    // Also refresh pending/sent/group/private lists (all in parallel)
                    async let p1: () = ChallengeService.shared.fetchPendingInvites()
                    async let p2: () = ChallengeService.shared.fetchPendingSentChallenges()
                    async let p3: () = ChallengeService.shared.fetchActiveGroupChallenges()
                    async let p4: () = CommunityChallengeService.shared.refreshAll(force: false)
                    async let p5: () = PrivateChallengeService.shared.refreshAll(force: false)
                    _ = await (p1, p2, p3, p4, p5)
                    print("✅ [DASHBOARD] All challenge data refreshed (1v1 + community + private)")
                    
                    // Update last refresh date
                    lastChallengeRefreshDate = Date()
                    
                    if dayChanged {
                        print("🌙 [CHALLENGES] Midnight sync complete - today's progress reset to 0")
                    }
                    
                    // Refresh daily quests (force on day change to get new quests)
                    await dailyQuestService.fetchDailyQuests(force: dayChanged)
                    
                    // Refresh friend data
                    await FriendService.shared.refreshHomeScreenData()
                }
            }
        }
        .onChange(of: stravaService.lastSyncDate) { _, newDate in
            // Reload cardio workouts when Strava finishes syncing
            if newDate != nil {
                Task { await loadRecentCardioWorkouts() }
            }
        }
        .onChange(of: healthKitService.lastSyncDate) { _, newDate in
            // Reload cardio workouts when HealthKit finishes syncing
            // (HealthKit workouts are now persisted to Supabase after sync)
            if newDate != nil {
                Task { await loadRecentCardioWorkouts() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .externalWorkoutSynced)) { _ in
            // Reload cardio workouts when an external workout (Apple Watch, Nike Run Club, etc.)
            // is detected and synced to Supabase via the HealthKit workout observer
            Task { await loadRecentCardioWorkouts() }
        }
        .onChange(of: smartProgramEngine.userPrograms.count) { _, _ in
            // Trigger refresh when programs change
        }
        .onChange(of: activeProgramWidgetId) { _, _ in
            // Trigger refresh when completion state changes
        }
    }
    
    // MARK: - Load Personalized Recommendation
    private func loadPersonalizedRecommendation() async {
        guard !isLoadingRecommendation else { return }
        
        // Get user ID from Supabase auth
        guard let userId = SupabaseManager.shared.currentUser?.id else {
            print("📊 [DASHBOARD] No user ID for recommendation")
            return
        }
        
        isLoadingRecommendation = true
        let streak = userManager.currentUser?.currentStreak ?? 0
        
        let recommendation = await AdvancedIntelligenceService.shared.getPersonalizedRecommendation(
            userId: userId,
            streak: Int(streak)
        )
        
        self.personalizedRecommendation = recommendation
        self.isLoadingRecommendation = false
        print("💡 [DASHBOARD] Loaded recommendation: \(recommendation.message)")
    }
    
    // ⚡️ PERFORMANCE: Throttle cardio fetches — multiple triggers (HealthKit, Strava, notifications)
    // can fire simultaneously, causing 10+ redundant network requests that flood the dashboard.
    @State private var lastCardioFetchTime: Date?
    private static let cardioFetchCooldown: TimeInterval = 10 // Max once per 10 seconds
    
    private func loadRecentCardioWorkouts() async {
        // Throttle: skip if we just fetched within cooldown
        if let lastFetch = lastCardioFetchTime,
           Date().timeIntervalSince(lastFetch) < Self.cardioFetchCooldown {
            return
        }
        lastCardioFetchTime = Date()
        
        do {
            // Fetch recent for display (limited to 5)
            let cardioWorkouts = try await SupabaseManager.shared.fetchRecentCardioWorkouts(limit: 5)
            
            // Fetch total count for "Your Progress" stats (all-time)
            let allTimeCount = try await SupabaseManager.shared.fetchCardioWorkoutCount()
            
            await MainActor.run {
                self.recentCardioWorkouts = cardioWorkouts
                self.totalCardioWorkoutCount = allTimeCount
                print("🏃 [DASHBOARD] Loaded \(cardioWorkouts.count) recent cardio workouts (\(allTimeCount) total all-time)")
                for workout in cardioWorkouts {
                    print("   └─ \(workout.activityType): \(workout.completedAt)")
                }
            }
        } catch {
            print("⚠️ [DASHBOARD] Failed to load cardio workouts: \(error)")
        }
    }
    
    private func loadProfilePhoto() async {
        guard let userId = SupabaseManager.shared.currentUser?.id else { return }
        
        // Show cached image immediately for fast UX (but don't trust it - verify with database)
        let hasCachedImage = ProfilePhotoCache.shared.cachedImage != nil
        if hasCachedImage {
            await MainActor.run {
                self.profilePhotoURL = "cached"
            }
        }
        
        // ALWAYS fetch fresh from database to ensure correct photo for current user
        do {
            struct ProfilePhotoResult: Codable {
                let profile_photo_url: String?
            }
            
            let result: [ProfilePhotoResult] = try await SupabaseManager.shared.supabaseClient
                .from("user_profiles")
                .select("profile_photo_url")
                .eq("id", value: userId.uuidString)
                .execute()
                .value
            
            if let photoUrl = result.first?.profile_photo_url {
                // Download fresh from database and update cache
                if let url = URL(string: photoUrl) {
                    do {
                        let (data, _) = try await URLSession.shared.data(from: url)
                        if let image = UIImage(data: data) {
                            ProfilePhotoCache.shared.cacheImage(image)
                            await MainActor.run {
                                self.profilePhotoURL = photoUrl
                            }
                        }
                    } catch {
                        print("⚠️ [DASHBOARD] Failed to download profile photo: \(error)")
                    }
                }
            } else {
                // User has no profile photo - clear any stale cache
                ProfilePhotoCache.shared.clearCache()
                await MainActor.run {
                    self.profilePhotoURL = nil
                }
            }
        } catch {
            print("⚠️ [DASHBOARD] Failed to load profile photo: \(error)")
        }
    }
    
    // MARK: - Program Conflict Alert
    @ViewBuilder
    private var programConflictAlert: some View {
        let accentColor: Color = {
            if let program = generatedProgramService.activeProgram {
                return colorFromProgramType(program.programType)
            }
            return .blue
        }()
        
        if showingProgramConflictAlert {
            ZStack {
                // Background overlay with blur
                Color.black.opacity(colorScheme == .dark ? 0.6 : 0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showingProgramConflictAlert = false
                            pendingWorkoutType = nil
                        }
                    }
                
                // Alert card with modern styling
                VStack(spacing: 0) {
                    // Header with animated icon
                    VStack(spacing: 20) {
                        ZStack {
                            // Outer glow ring
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [accentColor.opacity(0.5), accentColor.opacity(0.1)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 3
                                )
                                .frame(width: 80, height: 80)
                            
                            // Main icon circle
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [accentColor, accentColor.opacity(0.7)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 68, height: 68)
                                .shadow(color: accentColor.opacity(0.4), radius: 12, x: 0, y: 6)
                            
                            Image(systemName: generatedProgramService.activeProgram?.icon ?? "calendar")
                                .font(.ds_heading1)
                                .foregroundColor(.white)
                        }
                        
                        VStack(spacing: 10) {
                            Text("Active Program Detected")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.center)
                            
                            Text("You have a workout scheduled for today. Continue your program or start something different.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 28)
                    .padding(.bottom, 20)
                    
                    // Action buttons
                    VStack(spacing: 12) {
                        // Continue with program workout - Primary action
                        Button(action: {
                            HapticManager.impact(.medium)
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showingProgramConflictAlert = false
                                pendingWorkoutType = nil
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                navigateToTodaysWorkout = true
                            }
                        }) {
                            HStack(spacing: 14) {
                                ZStack {
                                    Circle()
                                        .fill(Color.white.opacity(0.2))
                                        .frame(width: 40, height: 40)
                                    
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.white)
                                }
                                
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Continue Program")
                                        .font(.system(size: 17, weight: .semibold))
                                    
                                    if let currentDay = generatedProgramService.currentDay {
                                        Text(currentDay.name)
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.8))
                                    }
                                }
                                
                                Spacer()
                                
                                Image(systemName: "arrow.right.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, 14)
                            .background(
                                ZStack {
                                    RoundedRectangle(cornerRadius: CornerRadius.lg)
                                        .fill(
                                            LinearGradient(
                                                colors: [accentColor, accentColor.opacity(0.85)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                    
                                    // Subtle inner highlight
                                    RoundedRectangle(cornerRadius: CornerRadius.lg)
                                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                }
                            )
                            .shadow(color: accentColor.opacity(0.3), radius: 8, x: 0, y: 4)
                        }
                        .scaleButtonStyle(.standard, withHaptic: true)
                        
                        // Skip and continue with custom/auto workout - Secondary action
                        Button(action: {
                            HapticManager.impact(.light)
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showingProgramConflictAlert = false
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                if pendingWorkoutType == .custom {
                                    navigateToCustomWorkout = true
                                } else if pendingWorkoutType == .auto {
                                    // 🔧 Redirect to Workout tab's auto-gen flow
                                    workoutManager.shouldNavigateToAutoGen = true
                                }
                            }
                        }) {
                            HStack(spacing: 10) {
                                Image(systemName: pendingWorkoutType == .custom ? "plus.circle.fill" : "bolt.circle.fill")
                                    .font(.ds_heading3)
                                
                                Text("Start \(pendingWorkoutType == .custom ? "Custom" : "Auto") Workout Instead")
                                    .font(.ds_labelLarge)
                            }
                            .foregroundColor(accentColor)
                            .padding(.vertical, 14)
                            .frame(maxWidth: .infinity)
                            .background(
                                ZStack {
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(accentColor.opacity(colorScheme == .dark ? 0.15 : 0.1))
                                    
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(accentColor.opacity(0.4), lineWidth: 1.5)
                                }
                            )
                        }
                        .scaleButtonStyle(.standard, withHaptic: true)
                        
                        // Cancel button - Tertiary action
                        Button(action: {
                            HapticManager.selectionChanged()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showingProgramConflictAlert = false
                                pendingWorkoutType = nil
                            }
                        }) {
                            Text("Cancel")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.vertical, 10)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
                .frame(maxWidth: 360)
                .background(
                    ZStack {
                        // Main background
                        RoundedRectangle(cornerRadius: CornerRadius.xl)
                            .fill(colorScheme == .dark 
                                ? Color.cardBackground 
                                : Color.white)
                        
                        // Subtle gradient overlay
                        RoundedRectangle(cornerRadius: CornerRadius.xl)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        accentColor.opacity(colorScheme == .dark ? 0.08 : 0.03),
                                        Color.clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        
                        // Border
                        RoundedRectangle(cornerRadius: CornerRadius.xl)
                            .stroke(
                                LinearGradient(
                                    colors: colorScheme == .dark 
                                        ? [Color.white.opacity(0.1), Color.clear]
                                        : [Color.white, Color.black.opacity(0.05)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    }
                )
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.5 : 0.15), radius: 30, x: 0, y: 15)
                .shadow(color: accentColor.opacity(0.15), radius: 20, x: 0, y: 10)
                .padding(.horizontal, 24)
                .scaleEffect(showingProgramConflictAlert ? 1 : 0.9)
                .opacity(showingProgramConflictAlert ? 1 : 0)
            }
            .transition(.opacity)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showingProgramConflictAlert)
        }
    }
    
    // MARK: - Custom Header View
    private var customHeaderView: some View {
        HStack(alignment: .center) {
            Image("fit33-logo")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 140, height: 55)
                .clipped()
            
            Spacer()
            
            // Timer, widget settings, and profile icon grouped together
            HStack(spacing: 8) {
                // Active workout timer (only shows when workout is active)
                if workoutManager.isWorkoutActive {
                    Text(workoutManager.formattedDuration)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.sm)
                                .fill(.ultraThinMaterial)
                        )
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
                
                // Widget settings button (three dots)
                Button(action: {
                    HapticManager.tap()
                    showingWidgetSettings = true
                }) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                }
                .buttonStyle(PlainButtonStyle())
                
                // Add spacing between ... and profile icon
                Spacer()
                    .frame(width: 4)
                
                // Profile button with hollow blue gradient ring and photo/person icon
                NavigationLink(value: DashboardRoute.profile) {
                    ZStack(alignment: .topTrailing) {
                        ZStack {
                            // Hollow ring with blue gradient
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [.blue, .cyan],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 2.5
                                )
                                .frame(width: 36, height: 36)
                                .shadow(color: .blue.opacity(0.4), radius: 4, x: 0, y: 2)
                            
                            // Show profile photo if available (from cache or URL), otherwise person icon
                            if let cachedImage = ProfilePhotoCache.shared.cachedImage {
                                Image(uiImage: cachedImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 28, height: 28)
                                    .clipShape(Circle())
                            } else if let photoURL = profilePhotoURL, photoURL != "cached", let url = URL(string: photoURL) {
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 28, height: 28)
                                            .clipShape(Circle())
                                    case .failure(_), .empty:
                                        Image(systemName: "person.fill")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(.white)
                                    @unknown default:
                                        Image(systemName: "person.fill")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(.white)
                                    }
                                }
                            } else {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                        }
                        
                        // Red indicator dot - isolated component to prevent DashboardView re-renders
                        FriendNotificationBadge()
                            .offset(x: 3, y: -3)
                    }
                }
                .accessibilityLabel("Profile")
                .offset(y: 2) // Nudge profile icon down slightly
            }
            .animation(.easeInOut(duration: 0.2), value: workoutManager.isWorkoutActive)
        }
        .padding(.horizontal, 4)
    }
    
    // MARK: - Notification Permission Banner
    // Persist dismissed state so it doesn't flicker on view recreation
    @AppStorage("notification_banner_dismissed") private var dismissedNotificationBanner = false
    
    private var notificationPermissionBanner: some View {
        // All conditions are checked in the parent - this just renders the content
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // Bell icon with animation
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.orange, Color.red.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Stay on Track!")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text("Enable notifications to get workout reminders & celebrate your wins")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                // Dismiss button
                Button(action: {
                    withAnimation(.easeOut(duration: 0.2)) {
                        dismissedNotificationBanner = true
                    }
                }) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                        .padding(Spacing.xs)
                }
            }
            
            // Enable button
            Button(action: {
                HapticManager.impact(.medium)
                // Check if we need to request permission or open settings
                Task {
                    let settings = await UNUserNotificationCenter.current().notificationSettings()
                    if settings.authorizationStatus == .notDetermined {
                        // First time - request permission
                        let granted = await NotificationManager.shared.requestAuthorization()
                        if granted {
                            await MainActor.run {
                                withAnimation {
                                    dismissedNotificationBanner = true
                                }
                            }
                        }
                    } else {
                        // Already denied - open settings
                        await MainActor.run {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Enable Notifications")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.sm)
                .background(
                    LinearGradient(
                        colors: [Color.orange, Color.red],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(CornerRadius.md)
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .fill(Color.cardBackground)
                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
        )
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }
    
    // Get the user's first name only (remove last name)
    private func getFirstName() -> String {
        let fullName = userManager.currentUser?.name ?? "there"
        let firstName = fullName.components(separatedBy: " ").first ?? fullName
        return firstName.isEmpty ? "there" : firstName
    }
    
    // Check if this is the user's first time seeing the dashboard after account creation
    private func checkIsFirstVisit() -> Bool {
        guard let userId = userManager.currentUser?.id else { return true }
        return !UserDefaults.standard.bool(forKey: "has_been_welcomed_\(userId.uuidString)")
    }
    
    // Welcome message based on first visit
    private func getWelcomeMessage() -> String {
        checkIsFirstVisit() ? "Welcome to Fit33," : "Welcome back,"
    }
    
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Top section with Welcome back and Level
            HStack {
                Text(getWelcomeMessage())
                    .font(.subheadline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                // User Level Display - floating badge (no background)
                HStack(spacing: 4) {
                    Image(systemName: userManager.getLevelIcon())
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(userManager.getLevelColor())
                    
                    Text(userManager.getLevelTitle())
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(userManager.getLevelColor())
                }
                .accessibilityLabel("Level \(userManager.getLevel()): \(userManager.getLevelTitle())")
            }
            
            // Bottom section with icon and user info
            HStack(spacing: 14) {
                // Hero icon - Flame with streak counter (tappable for info)
                Button(action: {
                    HapticManager.impact(.light)
                    showStreakInfo = true
                }) {
                    ZStack {
                        // Solid fill behind the flame to fill the hole
                        Circle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.orange, Color.red.opacity(0.9)]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 32, height: 32)
                            .offset(y: 6)
                        
                        // Flame icon
                        Image(systemName: "flame.fill")
                            .font(.system(size: 56, weight: .regular))
                            .foregroundStyle(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.orange, Color.red]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .shadow(color: .orange.opacity(0.5), radius: 8, x: 0, y: 2)
                        
                        // Streak number centered in flame
                        Text("\(userManager.currentUser?.currentStreak ?? 0)")
                            .font(.system(size: 24, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
                            .offset(y: 4) // Center in flame body
                    }
                    .frame(width: 58, height: 58)
                }
                .accessibilityLabel("Current streak: \(userManager.currentUser?.currentStreak ?? 0) days")
                .buttonStyle(.plain)
                
                // User info section - moved to the right
                VStack(alignment: .leading, spacing: 6) {
                    // First name only (streak is now in the flame icon)
                    Text(getFirstName())
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    // Motivational message - now prominent
                    Text(personalizedRecommendation?.message ?? currentMotivationalMessage)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer()
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 14)
        .background(
            ZStack {
                // Bottom shadow layer (deepest) - blue glow like Favorites
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.blue.opacity(colorScheme == .dark ? 0.15 : 0.08))
                    .offset(y: 8)
                    .blur(radius: 4)
                
                // Middle shadow layer
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                    .offset(y: 4)
                
                // Main card background
                RoundedRectangle(cornerRadius: 24, style: .continuous)
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
                RoundedRectangle(cornerRadius: 24, style: .continuous)
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
                
                // Blue/purple accent border
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.blue.opacity(colorScheme == .dark ? 0.4 : 0.3),
                                Color.purple.opacity(colorScheme == .dark ? 0.3 : 0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
    }
    
    private var startWorkoutButton: some View {
        VStack(spacing: 12) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                // Custom Workout Button
                Button(action: {
                    HapticManager.impact(.medium)
                    handleWorkoutSelection(type: .custom)
                }) {
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [Color.blue, Color.cyan]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 50, height: 50)
                                .shadow(color: .blue.opacity(0.4), radius: 8, x: 0, y: 4)
                            
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                        }
                        
                        VStack(spacing: 4) {
                        Text("Custom Workout")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                        
                        Text("Build your own")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(width: 160, height: 140)
                .background(
                    ZStack {
                        // Bottom shadow layer (deepest) - color glow
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(Color.blue.opacity(colorScheme == .dark ? 0.15 : 0.08))
                            .offset(y: 8)
                            .blur(radius: 4)
                        
                        // Middle shadow layer
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                            .offset(y: 4)
                        
                        // Main card background with gradient
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: cardBackgroundGradient,
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        
                        // Inner highlight (top edge glow)
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
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
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.blue.opacity(colorScheme == .dark ? 0.4 : 0.3), Color.cyan.opacity(colorScheme == .dark ? 0.3 : 0.2)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
                )
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 12, x: 0, y: 6)
                .shadow(color: .blue.opacity(colorScheme == .dark ? 0.2 : 0.12), radius: 20, x: 0, y: 10)
                }
                .accessibilityLabel("Start custom workout")
                .buttonStyle(PlainButtonStyle())
                
            // Auto Workout Button
            Button(action: {
                HapticManager.impact(.medium)
                handleWorkoutSelection(type: .auto)
            }) {
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [Color.purple, Color.pink]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 50, height: 50)
                                .shadow(color: .purple.opacity(0.4), radius: 8, x: 0, y: 4)
                            
                            Image(systemName: "dumbbell.fill")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                        }
                        
                        VStack(spacing: 4) {
                        Text("Auto Workout")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                        
                        Text("Auto-generated routine")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(width: 160, height: 140)
                .background(
                    ZStack {
                        // Bottom shadow layer (deepest) - color glow
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(Color.purple.opacity(colorScheme == .dark ? 0.15 : 0.08))
                            .offset(y: 8)
                            .blur(radius: 4)
                        
                        // Middle shadow layer
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                            .offset(y: 4)
                        
                        // Main card background with gradient
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: cardBackgroundGradient,
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        
                        // Inner highlight (top edge glow)
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
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
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.purple.opacity(colorScheme == .dark ? 0.4 : 0.3), Color.pink.opacity(colorScheme == .dark ? 0.3 : 0.2)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
                )
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 12, x: 0, y: 6)
                .shadow(color: .purple.opacity(0.12), radius: 20, x: 0, y: 10)
                }
                .accessibilityLabel("Start auto workout")
                .buttonStyle(PlainButtonStyle())
            
            }
        }
    }
    
    // MARK: - Dashboard Widgets Row
    private var dashboardWidgetsRow: some View {
        let showBoth = showWeightTrackerWidget && showHydrationWidget
        
        return Group {
            if showBoth {
                // Two widgets side by side
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                    if showWeightTrackerWidget {
                        DashboardWeightWidget(isCompact: true, cardBackgroundGradient: cardBackgroundGradient)
                    }
                    if showHydrationWidget {
                        DashboardHydrationWidget(isCompact: true, cardBackgroundGradient: cardBackgroundGradient)
                    }
                }
            } else {
                // Single widget expanded
                if showWeightTrackerWidget {
                    DashboardWeightWidget(isCompact: false, cardBackgroundGradient: cardBackgroundGradient)
                }
                if showHydrationWidget {
                    DashboardHydrationWidget(isCompact: false, cardBackgroundGradient: cardBackgroundGradient)
                }
            }
        }
    }
    
    private var destinationForTodaysWorkout: some View {
        Group {
            if let program = generatedProgramService.activeProgram,
               let currentDay = generatedProgramService.currentDay {
                SmartWorkoutPreviewView(
                    day: currentDay,
                    program: program
                )
                .environmentObject(workoutManager)
                .environmentObject(generatedProgramService)
            } else {
                EmptyView()
            }
        }
    }
    
    // MARK: - Dashboard Macros Widget (Quick Access)
    private var dashboardMacrosWidget: some View {
        let consumedCalories = mealService.todaysMeals.reduce(0) { $0 + $1.calories }
        let consumedProtein = mealService.todaysMeals.reduce(0) { $0 + $1.protein }
        let consumedFat = mealService.todaysMeals.reduce(0) { $0 + $1.fat }
        
        // Goals (simplified calculation)
        let calorieGoal: Int = {
            guard let user = userManager.currentUser else { return 2200 }
            let weight = user.weight > 0 ? Int(user.weight) : 150
            let height = user.height > 0 ? Int(user.height) : 170
            if weight > 0 && height > 0 {
                let bmr = (10 * Double(weight)) + (6.25 * Double(height)) - 150
                return Int(bmr * 1.55)
            }
            return 2200
        }()
        let proteinGoal = max(100, Int(Double(userManager.currentUser?.weight ?? 150) * 0.8))
        let fatGoal = (calorieGoal * 30 / 100) / 9
        
        // Progress calculations
        let caloriesProgress = calorieGoal > 0 ? min(Double(consumedCalories) / Double(calorieGoal), 1.5) : 0
        let proteinProgress = proteinGoal > 0 ? min(Double(consumedProtein) / Double(proteinGoal), 1.5) : 0
        let fatProgress = fatGoal > 0 ? min(Double(consumedFat) / Double(fatGoal), 1.5) : 0
        let caloriesExceeded = consumedCalories > calorieGoal
        let fatExceeded = consumedFat > fatGoal
        
        return VStack(spacing: 8) {
            // Swipeable cards (Today's Macros + Weekly Progress)
            GeometryReader { geometry in
                let cardWidth = geometry.size.width
                let spacing: CGFloat = 16
                
                HStack(spacing: spacing) {
                    // Card 0: Today's Macros (compact version)
                    compactMacrosCard(
                        consumedCalories: consumedCalories,
                        calorieGoal: calorieGoal,
                        consumedProtein: consumedProtein,
                        proteinGoal: proteinGoal,
                        consumedFat: consumedFat,
                        fatGoal: fatGoal,
                        caloriesProgress: caloriesProgress,
                        proteinProgress: proteinProgress,
                        fatProgress: fatProgress,
                        caloriesExceeded: caloriesExceeded,
                        fatExceeded: fatExceeded
                    )
                    .frame(width: cardWidth)
                    .opacity(selectedMacrosPage == 0 ? 1 : 0)
                    
                    // Card 1: Weekly Progress (compact version)
                    compactWeeklyProgressCard
                        .frame(width: cardWidth)
                        .opacity(selectedMacrosPage == 1 ? 1 : 0)
                }
                .offset(x: -CGFloat(selectedMacrosPage) * (cardWidth + spacing))
            }
            .frame(height: 160)
            .animation(.easeOut(duration: 0.25), value: selectedMacrosPage)
            .highPriorityGesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { value in
                        let horizontalAmount = value.translation.width
                        let verticalAmount = abs(value.translation.height)
                        
                        if abs(horizontalAmount) > verticalAmount * 1.5 && abs(horizontalAmount) > 20 {
                            HapticManager.impact(.medium)
                            if horizontalAmount < 0 && selectedMacrosPage < 1 {
                                selectedMacrosPage = 1
                            } else if horizontalAmount > 0 && selectedMacrosPage > 0 {
                                selectedMacrosPage = 0
                            }
                        }
                    }
            )
            
            // Page indicators (dash and dot style)
            HStack(spacing: 6) {
                ForEach(0..<2, id: \.self) { index in
                    Capsule()
                        .fill(selectedMacrosPage == index ? Color.teal : Color.gray.opacity(0.3))
                        .frame(width: selectedMacrosPage == index ? 20 : 8, height: 6)
                        .animation(.easeOut(duration: 0.2), value: selectedMacrosPage)
                        .onTapGesture {
                            HapticManager.impact(.light)
                            selectedMacrosPage = index
                        }
                }
            }
        }
    }
    
    private func compactMacrosCard(
        consumedCalories: Int,
        calorieGoal: Int,
        consumedProtein: Int,
        proteinGoal: Int,
        consumedFat: Int,
        fatGoal: Int,
        caloriesProgress: Double,
        proteinProgress: Double,
        fatProgress: Double,
        caloriesExceeded: Bool,
        fatExceeded: Bool
    ) -> some View {
        NavigationLink(value: DashboardRoute.mealPlan) {
            HStack(spacing: 20) {
                // Triple ring (larger to fill space)
                NutritionTripleRing(
                    caloriesProgress: caloriesProgress,
                    proteinProgress: proteinProgress,
                    fatProgress: fatProgress,
                    size: 100,
                    caloriesExceeded: caloriesExceeded,
                    fatExceeded: fatExceeded
                )
                
                // Legend with values
                VStack(alignment: .leading, spacing: 10) {
                    macroLegendRow(name: "Calories", current: consumedCalories, goal: calorieGoal, color: caloriesExceeded ? .red : .teal)
                    macroLegendRow(name: "Protein", current: consumedProtein, goal: proteinGoal, color: .blue)
                    macroLegendRow(name: "Fat", current: consumedFat, goal: fatGoal, color: fatExceeded ? .red : .purple)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(Spacing.md)
            .background(
                ZStack {
                    // Bottom shadow layer (deepest) - teal color glow
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Color.teal.opacity(colorScheme == .dark ? 0.15 : 0.08))
                        .offset(y: 8)
                        .blur(radius: 4)
                    
                    // Middle shadow layer
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                        .offset(y: 4)
                    
                    // Main card background with gradient
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: cardBackgroundGradient,
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    
                    // Inner highlight (top edge glow)
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
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
                    
                    // Colored accent border (teal)
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [Color.teal.opacity(colorScheme == .dark ? 0.4 : 0.3), Color.mint.opacity(colorScheme == .dark ? 0.3 : 0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 12, x: 0, y: 6)
            .shadow(color: .teal.opacity(colorScheme == .dark ? 0.2 : 0.12), radius: 20, x: 0, y: 10)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func macroLegendRow(name: String, current: Int, goal: Int, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            
            Text(name)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text("\(current)")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            +
            Text("/\(goal)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    
    private var compactWeeklyProgressCard: some View {
        NavigationLink(value: DashboardRoute.mealPlan) {
            VStack(spacing: 12) {
                // Header
                HStack {
                    Text("Weekly Progress")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Image(systemName: "chart.bar.fill")
                        .font(.subheadline)
                        .foregroundColor(.teal)
                }
                
                // Simple weekly overview
                HStack(spacing: 6) {
                    ForEach(0..<7, id: \.self) { dayOffset in
                        let date = Calendar.current.date(byAdding: .day, value: -6 + dayOffset, to: Date())!
                        let dayName = Calendar.current.shortWeekdaySymbols[Calendar.current.component(.weekday, from: date) - 1]
                        let mealsLogged = getMealsForDay(date)
                        let hasData = mealsLogged > 0
                        let isToday = Calendar.current.isDateInToday(date)
                        
                        VStack(spacing: 6) {
                            Text(dayName.prefix(1))
                                .font(.system(size: 11, weight: isToday ? .bold : .medium))
                                .foregroundColor(isToday ? .teal : .secondary)
                            
                            RoundedRectangle(cornerRadius: 5)
                                .fill(hasData 
                                    ? LinearGradient(colors: [.teal, .mint], startPoint: .bottom, endPoint: .top)
                                    : LinearGradient(colors: [Color.gray.opacity(0.2)], startPoint: .bottom, endPoint: .top)
                                )
                                .frame(height: CGFloat(min(mealsLogged * 14 + 10, 70)))
                                .frame(maxHeight: 70, alignment: .bottom)
                            
                            Text("\(mealsLogged)")
                                .font(.ds_caption)
                                .foregroundColor(hasData ? .primary : .secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 4)
            }
            .padding(Spacing.md)
            .background(
                ZStack {
                    // Bottom shadow layer (deepest) - teal color glow
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Color.teal.opacity(colorScheme == .dark ? 0.15 : 0.08))
                        .offset(y: 8)
                        .blur(radius: 4)
                    
                    // Middle shadow layer
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                        .offset(y: 4)
                    
                    // Main card background with gradient
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: cardBackgroundGradient,
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    
                    // Inner highlight (top edge glow)
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
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
                    
                    // Colored accent border (teal)
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [Color.teal.opacity(colorScheme == .dark ? 0.4 : 0.3), Color.mint.opacity(colorScheme == .dark ? 0.3 : 0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 12, x: 0, y: 6)
            .shadow(color: .teal.opacity(colorScheme == .dark ? 0.2 : 0.12), radius: 20, x: 0, y: 10)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func getMealsForDay(_ date: Date) -> Int {
        return mealService.getMealsForDate(date).count
    }
    
    private func handleWorkoutSelection(type: PendingWorkoutType) {
        // 🔧 Debounce: Prevent double-taps
        guard !isNavigating else { return }
        isNavigating = true
        
        // Reset after a short delay to allow new navigation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isNavigating = false
        }
        
        if generatedProgramService.activeProgram != nil {
            // Show alert if there's an active program
            pendingWorkoutType = type
            showingProgramConflictAlert = true
        } else {
            // Proceed directly if no active program
            pendingWorkoutType = type
            if type == .custom {
                navigateToCustomWorkout = true
            } else if type == .auto {
                // 🔧 Redirect to Workout tab's auto-gen flow
                // This prevents cross-tab navigation issues when starting workout
                workoutManager.shouldNavigateToAutoGen = true
            }
        }
    }
    
    private var recentWorkoutsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header with stats
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recent Activity")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text("\(totalCombinedWorkouts) workouts completed")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                NavigationLink(value: DashboardRoute.workoutHistory) {
                    Text("View All")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                }
            }
            
            // Combined workout cards - mix strength and cardio workouts, sorted by date
            // Show at most 3 recent workouts
            VStack(spacing: 12) {
                ForEach(combinedRecentWorkouts.prefix(3), id: \.id) { item in
                    switch item {
                    case .strength(let workout, let isMostRecent):
                        RecentWorkoutCard(workout: workout, isMostRecent: isMostRecent)
                    case .cardio(let cardioWorkout, let isMostRecent):
                        RecentCardioWorkoutCard(cardioWorkout: cardioWorkout, isMostRecent: isMostRecent)
                    }
                }
            }
        }
        .padding(24)
        .background(
            ZStack {
                // Clean gradient background matching WorkoutTabView exactly
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color(white: 0.15), Color(white: 0.10)]
                                : [Color.white, Color.white.opacity(0.95)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                // Subtle top highlight
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color.white.opacity(0.08), Color.clear]
                                : [Color.white, Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.06), radius: 10, x: 0, y: 4)
    }
    
    // Get the glow color based on the most recent workout's muscle group (kept for card content)
    private var recentActivityGlowColor: Color {
        guard let mostRecentWorkout = recentWorkouts.first else {
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
    
    // Helper to convert color string to Color
    private func colorFromString(_ colorString: String) -> Color {
        switch colorString.lowercased() {
        case "blue": return .blue
        case "purple": return .purple
        case "orange": return .orange
        case "red": return .red
        case "green": return .green
        case "cyan": return .cyan
        case "indigo": return .indigo
        case "pink": return .pink
        case "yellow": return .yellow
        case "teal": return .teal
        case "mint": return .mint
        default: return .blue
        }
    }
    
    /// Combined total: in-app workouts + synced cardio/HealthKit workouts
    private var totalCombinedWorkouts: Int {
        let inApp = Int(userManager.currentUser?.totalWorkouts ?? 0)
        // Core Data workouts visible in the recent list (completed, all-time)
        let coreDataCount = recentWorkouts.count
        // Use the max of in-app counter vs Core Data count (in-app counter may lag)
        let strength = max(inApp, coreDataCount)
        return strength + totalCardioWorkoutCount
    }
    
    private var statsOverview: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your Progress")
                .font(.title2)
                .fontWeight(.bold)
            
            HStack(spacing: 12) {
                StatCard(
                    title: "Workouts",
                    value: "\(totalCombinedWorkouts)",
                    icon: "dumbbell.fill",
                    color: .blue
                )
                
                StatCard(
                    title: "Best Streak",
                    value: "\(userManager.currentUser?.longestStreak ?? 0)",
                    icon: "flame.fill",
                    color: .orange
                )
                
                StatCard(
                    title: "Level",
                    value: "\(userManager.getLevel())",
                    icon: "star.fill",
                    color: .yellow
                )
            }
        }
        .padding(24)
        .background(
            ZStack {
                // Outer container - darker to let inner cards pop (matches Recent Activity)
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color(white: 0.11), Color(white: 0.07)]
                                : [Color(white: 0.96), Color(white: 0.94)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                // Subtle top highlight
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color.white.opacity(0.1), Color.clear]
                                : [Color.white.opacity(0.8), Color.clear],
                            startPoint: .top,
                            endPoint: .center
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.1), radius: 16, x: 0, y: 8)
    }
    
    private func generateMotivationalMessage() -> String {
        let streak = userManager.currentUser?.currentStreak ?? 0
        let hour = Calendar.current.component(.hour, from: Date())
        let dayOfWeek = Calendar.current.component(.weekday, from: Date())
        let firstName = getFirstName()
        
        // 👤 Gender-aware terms – "queen"/"king", etc.
        let isFemale = userManager.currentUser?.gender?.lowercased().contains("female") == true
        let crown = isFemale ? "queen" : "king"
        let Royal = isFemale ? "Queen" : "King"
        let legend = isFemale ? "goddess" : "legend"
        
        var messages: [String] = []
        
        // ─────────────────────────────────────────────
        // 🏆 CHALLENGE-PERSONALIZED MESSAGES
        // ─────────────────────────────────────────────
        if let challenge = challengeService.activeChallenges.first {
            let oppName = challenge.opponentName?.components(separatedBy: " ").first ?? "your opponent"
            let resolvedType = challenge.resolvedType
            let myProgress = challenge.myTodayProgress ?? 0
            let dailyTarget = challenge.dailyTarget ?? 0
            let remaining = max(0, dailyTarget - myProgress)
            let unit = challenge.targetUnit.lowercased()
            
            // Winning vs. behind messages
            if challenge.amWinning {
                messages.append(contentsOf: [
                    "You're ahead of \(oppName)! Don't let up, \(crown)! 👑",
                    "Leading the battle vs \(oppName)! Keep that crown! 🏆",
                    "\(oppName) is watching your lead – stay locked in! 🔥",
                    "You're winning, \(firstName)! Make \(oppName) sweat! 💪"
                ])
            } else {
                messages.append(contentsOf: [
                    "\(oppName) is ahead – time to close the gap! 🔥",
                    "Behind \(oppName)? Not for long. Let's go, \(crown)! 👑",
                    "\(oppName) thinks they've got this – prove them wrong! 💪",
                    "Comeback energy! \(oppName) won't see you coming! ⚡"
                ])
            }
            
            // Type-specific actionable tips with real numbers
            if remaining > 0 {
                switch resolvedType {
                case .protein:
                    messages.append(contentsOf: [
                        "\(remaining)g protein to go! A chicken breast gets you closer! 🍗",
                        "Need \(remaining)g more protein – Greek yogurt + chicken = easy! 💪",
                        "\(remaining)g left to crush your protein goal, \(crown)! 🥚"
                    ])
                case .hydrate:
                    let unitLabel = unit.contains("oz") ? "oz" : "ml"
                    messages.append(contentsOf: [
                        "\(remaining)\(unitLabel) of water left! Grab that bottle, \(crown)! 💧",
                        "Stay hydrated! \(remaining)\(unitLabel) more to hit your goal! 🌊",
                        "Water check! \(remaining)\(unitLabel) to go – almost there! 💦"
                    ])
                case .steps:
                    messages.append(contentsOf: [
                        "\(remaining.formatted()) steps to go! A quick walk does it! 👟",
                        "\(remaining.formatted()) more steps to beat \(oppName)! 🚶",
                        "So close! \(remaining.formatted()) steps left, \(crown)! 🔥"
                    ])
                case .calories:
                    messages.append(contentsOf: [
                        "\(remaining) calories to go! Get moving, \(crown)! 🔥",
                        "\(remaining) cals left – a solid workout crushes that! 💪"
                    ])
                case .activeMinutes:
                    messages.append(contentsOf: [
                        "\(remaining) active minutes left! Any movement counts! ⏱️",
                        "\(remaining) more minutes to hit your goal, \(crown)! 💪"
                    ])
                case .walk, .run:
                    messages.append(contentsOf: [
                        "Lace up! A little more distance to beat \(oppName)! 🏃",
                        "Almost there! Keep moving, \(crown)! 👟"
                    ])
                case .lift, .workoutStreak:
                    messages.append(contentsOf: [
                        "Time to hit the weights, \(crown)! 🏋️",
                        "One workout closer to winning – let's get it! 💪"
                    ])
                }
            } else if dailyTarget > 0 {
                // Already hit daily target
                messages.append(contentsOf: [
                    "Daily challenge goal CRUSHED! You're a \(legend)! 🎉",
                    "\(firstName), you hit your daily target! \(Royal) behavior! 👑",
                    "Challenge goal: DONE. \(oppName) can't keep up! 🏆"
                ])
            }
        }
        
        // ─────────────────────────────────────────────
        // 🏋️ WORKOUT-PERSONALIZED MESSAGES
        // ─────────────────────────────────────────────
        if let lastWorkout = recentWorkouts.first {
            let workoutName = lastWorkout.name ?? "your workout"
            let daysSince = Calendar.current.dateComponents([.day], from: lastWorkout.date ?? Date(), to: Date()).day ?? 0
            
            if daysSince == 0 {
                messages.append(contentsOf: [
                    "You crushed \(workoutName) today! Amazing, \(crown)! 🔥",
                    "\(workoutName) ✅ – you're on fire, \(firstName)! 🌟",
                    "That \(workoutName) was pure \(Royal) energy! 👑"
                ])
            } else if daysSince == 1 {
                messages.append(contentsOf: [
                    "\(workoutName) yesterday was 🔥! Ready for round two?",
                    "Great \(workoutName) session yesterday, \(crown)! 💪",
                    "Your body is still thanking you for that \(workoutName)! 🌟"
                ])
            } else if daysSince <= 3 {
                messages.append(contentsOf: [
                    "Muscles are rested from \(workoutName) – time to go! 💪",
                    "\(daysSince) days since \(workoutName)? Fresh and ready, \(crown)! 🚀"
                ])
            }
            
            // Workout-type specific fun messages
            let type = (lastWorkout.workoutType ?? workoutName).lowercased()
            if type.contains("leg") || type.contains("lower") || type.contains("squat") {
                messages.append("Those legs are powerful! Walk tall, \(crown)! 🦵👑")
            } else if type.contains("chest") || type.contains("push") || type.contains("bench") {
                messages.append("Chest day champion! Stand proud, \(crown)! 💪✨")
            } else if type.contains("back") || type.contains("pull") {
                messages.append("Back gains loading! Posture on point, \(crown)! 🎯")
            } else if type.contains("arm") || type.contains("bicep") || type.contains("tricep") {
                messages.append("Arms looking toned! Flex on 'em, \(crown)! 💪✨")
            } else if type.contains("shoulder") || type.contains("delt") {
                messages.append("Shoulders looking strong! Go off, \(crown)! 🏋️")
            } else if type.contains("core") || type.contains("ab") {
                messages.append("Core work pays off every day! Love that, \(crown)! 🎯")
            } else if type.contains("cardio") || type.contains("run") || type.contains("hiit") {
                messages.append(isFemale ? "Cardio queen energy! You're glowing! ✨🏃‍♀️" : "Cardio beast mode! Keep that engine running! 🏃‍♂️🔥")
            } else if type.contains("yoga") || type.contains("stretch") || type.contains("flex") {
                messages.append("Flexibility is a superpower! Namaste, \(crown)! 🧘✨")
            } else if type.contains("dance") {
                messages.append(isFemale ? "Dancing queen! You're glowing, keep it going! 💃✨" : "Dance moves AND gains? Unstoppable! 🕺🔥")
            } else if type.contains("full body") || type.contains("total body") {
                messages.append("Full body work = full \(crown) energy! 👑🔥")
            }
        }
        
        // ─────────────────────────────────────────────
        // 🔥 STREAK-BASED MESSAGES (gender-aware)
        // ─────────────────────────────────────────────
        if streak == 0 {
            messages.append(contentsOf: [
                "Today's the day to start something great, \(firstName)! 💪",
                "Every champion started with day one. Let's go! 🚀",
                "Fresh start energy! Let's get it, \(crown)! 🌟",
                "Day one? You're about to surprise yourself! 🔥"
            ])
        } else if streak == 1 {
            messages.append(contentsOf: [
                "Day 1 in the books! The hardest part is done! 🔥",
                "You showed up, \(firstName)! That's \(Royal) behavior! 💪",
                "One day down, so many wins to come! 🚀",
                "First step taken! Momentum starts here, \(crown)! ⚡"
            ])
        } else if streak <= 3 {
            messages.append(contentsOf: [
                "\(streak) days in! You're building something real! 🔥",
                "\(streak) days of showing up – so proud of you! 💪",
                "Keep stacking those days, \(crown)! 🚀",
                "\(streak)-day streak – your future self is cheering! ⭐"
            ])
        } else if streak <= 7 {
            messages.append(contentsOf: [
                "\(streak) days strong! Unstoppable, \(crown)! 🔥",
                "Almost a full week! Champions are made right here! 💪",
                "Discipline AND heart – you've got both, \(firstName)! 🚀",
                "\(streak) days of proving you're the real deal! ⚡"
            ])
        } else if streak <= 14 {
            messages.append(contentsOf: [
                "Over a week! This is becoming who you are! 🔥",
                "\(streak) days – you're an inspiration, \(firstName)! 💪",
                "\(streak)-day streak! Absolutely elite, \(crown)! 🌟",
                "Double digits! Your dedication is beautiful! 🚀"
            ])
        } else if streak <= 30 {
            messages.append(contentsOf: [
                "\(streak) days! Fitness is non-negotiable for you! 👑",
                "\(streak)-day \(legend)! Elite consistency! 🏆",
                "\(streak) days of pure dedication – respect, \(firstName)! 💎",
                "\(streak) days strong! Nothing can stop you, \(crown)! 🔥"
            ])
        } else {
            messages.append(contentsOf: [
                "\(streak) DAYS! Top 1% energy, \(crown)! 👑",
                "\(streak)-day \(legend)! You ARE fitness goals! 🏆",
                "\(streak) days of mastered consistency, \(firstName)! 💎",
                "\(streak) days! Your discipline is legendary! 🔥",
                "\(streak) days! Rewriting what's possible! ⭐"
            ])
        }
        
        // ─────────────────────────────────────────────
        // ⏰ TIME-OF-DAY MESSAGES
        // ─────────────────────────────────────────────
        if hour < 9 {
            messages.append(contentsOf: [
                "Early bird energy! Morning \(crown)s win the day! ☀️",
                "Rise and shine, \(firstName)! Best time to invest in you! 🌅",
                "Morning check-in! You're already ahead! ⚡"
            ])
        } else if hour >= 12 && hour < 14 {
            messages.append(contentsOf: [
                "Lunch break? Perfect time for a protein-packed meal! 🥗",
                "Midday \(crown) energy! Stay fueled, stay strong! 💪"
            ])
        } else if hour >= 17 && hour < 21 {
            messages.append(contentsOf: [
                "Evening power! Perfect time to get it in, \(crown)! 🌙",
                "End the day strong! Your body is ready! 💪",
                "Evening workout = better sleep tonight! Win-win! 🔥"
            ])
        } else if hour >= 21 {
            messages.append(contentsOf: [
                "Winding down? You earned tonight's rest, \(crown)! 🌙",
                "Great day, \(firstName)! Sleep well – gains happen at rest! 😴"
            ])
        }
        
        // ─────────────────────────────────────────────
        // 📅 DAY-OF-WEEK MESSAGES
        // ─────────────────────────────────────────────
        if dayOfWeek == 2 { // Monday
            messages.append(contentsOf: [
                "Monday momentum! Set the tone, \(crown)! 💪",
                "New week, new energy! Let's go, \(firstName)! 🚀",
                "Monday \(crown)s build championship weeks! 🔥"
            ])
        } else if dayOfWeek == 4 { // Wednesday
            messages.append("Halfway through the week! Keep that energy, \(crown)! ⚡")
        } else if dayOfWeek == 6 { // Friday
            messages.append(contentsOf: [
                "Friday vibes! End the week on a high note! 🎉",
                "Weekend \(crown) mode: activated! 💪",
                "Friday flex! You earned this week, \(firstName)! 🏆"
            ])
        } else if dayOfWeek == 1 || dayOfWeek == 7 { // Weekend
            messages.append(contentsOf: [
                "Weekend dedication = next-level results! 🌴",
                "Weekends count too! Stay locked in, \(crown)! 💪",
                "Weekend work builds real results! ⚡"
            ])
        }
        
        // ─────────────────────────────────────────────
        // 🌿 WELLNESS REMINDERS (positive, never insulting)
        // ─────────────────────────────────────────────
        messages.append(contentsOf: [
            "Core work today? Your whole body will thank you! 🎯",
            "Hydration check! Grab that water bottle, \(crown)! 💧",
            "Hit your step goal yet? Every step counts! 👟",
            "Leg day is \(crown) behavior! 🦵👑",
            "Protein fuels progress! Hitting your macros? 🥩",
            "Stretch it out! Flexibility is a superpower! 🧘",
            "Sleep is where the magic happens – 7-8 hours tonight? 😴",
            "Recovery day? Active rest still counts, \(crown)! 🌿",
            "Get that heart rate up today! Your heart loves you! ❤️",
            "Posture check! Stand tall, \(crown)! 👑",
            "Meal prep = future you saying 'thank you!' 🥗",
            "Shoulder day builds confidence! Go get it! 🏋️",
            "Strong core = strong everything! 🎯",
            "Glutes are the powerhouse! Show them love today! 🍑",
            "Water before coffee! Your body will thank you! ☕",
            "Walking counts! 10K steps for the win! 🚶",
            "Rest days build strength too! Listen to your body! 🛏️",
            "You're doing amazing, \(firstName)! Keep going! ✨",
            isFemale ? "Strong is beautiful – and you're proof! 💪✨" : "Putting in the work every day! Respect, \(crown)! 💪🔥"
        ])
        
        // ─────────────────────────────────────────────
        // 🧠 SMART INSIGHTS (prioritized when available)
        // ─────────────────────────────────────────────
        if !insightsService.activeInsights.isEmpty && Int.random(in: 0...9) < 4 {
            if let insight = insightsService.activeInsights.randomElement() {
                return insight.message
            }
        }
        
        // 🔥 STREAK INSIGHTS from tracking
        if !insightsService.streaks.isEmpty {
            if let proteinStreak = insightsService.streaks.first(where: { $0.streakType == "protein_goal" }),
               proteinStreak.currentStreak >= 3 {
                messages.append("\(proteinStreak.currentStreak)-day protein streak! Keep fueling those gains! 🍗")
            }
            if let hydrationStreak = insightsService.streaks.first(where: { $0.streakType == "hydration" }),
               hydrationStreak.currentStreak >= 3 {
                messages.append("\(hydrationStreak.currentStreak) days hydrated! Your body loves you, \(crown)! 💧")
            }
            if let weightStreak = insightsService.streaks.first(where: { $0.streakType == "weight_log" }),
               weightStreak.currentStreak >= 5 {
                messages.append("\(weightStreak.currentStreak)-day weight logging streak! Data drives results! ⚖️")
            }
            if let loggingStreak = insightsService.streaks.first(where: { $0.streakType == "logging" }),
               loggingStreak.currentStreak >= 7 {
                messages.append("\(loggingStreak.currentStreak) days tracking! Consistency is your superpower, \(crown)! 📊")
            }
        }
        
        return messages.randomElement() ?? "Let's make today amazing, \(firstName)! 💪"
    }
    
    // MARK: - Smart Active Program Widget
    
    private func smartActiveProgramWidget(program: DynamicProgramGenerator.GeneratedProgram) -> some View {
        let displayInfo = generatedProgramService.getDisplayInfo(for: program)
        let programColor = colorFromProgramType(program.programType)
        let completedDays = program.generatedDays.filter { $0.isCompleted }.count
        let totalDays = program.durationWeeks * program.daysPerWeek
        
        return VStack(spacing: 0) {
            // Streamlined Header
            VStack(spacing: 10) {
                // Top row: Icon, Name, and Menu
                HStack(alignment: .center, spacing: 12) {
                    // Gradient icon
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [programColor, programColor.opacity(0.7)]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 48, height: 48)
                            .shadow(color: programColor.opacity(0.3), radius: 6, x: 0, y: 3)
                        
                        Image(systemName: program.icon)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                    }
                    
                    // Program info
                    VStack(alignment: .leading, spacing: 3) {
                        Text(program.name)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        
                        HStack(spacing: 8) {
                            // Week and progress combined
                            Text("Week \(displayInfo.currentWeek)/\(program.durationWeeks)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text("•")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            Text("\(completedDays)/\(totalDays) days")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(programColor)
                        }
                    }
                    
                    Spacer()
                    
                    // View all button - placeholder for GeneratedProgram (would need adapter)
                    NavigationLink(value: DashboardRoute.programDetailsPlaceholder) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                }
                
                // Compact progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background
                        Capsule()
                            .fill(Color.gray.opacity(0.12))
                            .frame(height: 8)
                        
                        // Progress fill
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [programColor, programColor.opacity(0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * (displayInfo.progressPercentage / 100), height: 8)
                        
                        // Percentage overlay
                        HStack {
                            Spacer()
                            Text("\(Int(displayInfo.progressPercentage))%")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor((displayInfo.progressPercentage / 100) > 0.15 ? .white : programColor)
                                .padding(.trailing, 6)
                        }
                    }
                }
                .frame(height: 8)
            }
            .padding(14)
            
            // Today's workout - COMPACT with rounded inner card
            if let currentDay = generatedProgramService.currentDay {
                NavigationLink(value: DashboardRoute.smartWorkoutPreview) {
                    HStack(spacing: 12) {
                        // Left: Workout info
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(currentDay.name)
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.primary)
                                
                                Text("Day \(currentDay.dayNumber)")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(programColor)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule()
                                            .fill(programColor.opacity(0.12))
                                    )
                            }
                            
                            HStack(spacing: 6) {
                                Label("\(currentDay.exercises.count)", systemImage: "dumbbell.fill")
                                Label("~\(currentDay.estimatedDuration)min", systemImage: "clock")
                                
                                // Muscle targets from focusMuscles
                                if !currentDay.focusMuscles.isEmpty {
                                    Text("•")
                                        .font(.caption2)
                                    Text(currentDay.focusMuscles.prefix(3).joined(separator: ", "))
                                        .lineLimit(1)
                                }
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        // Right: Start button
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill")
                                .font(.ds_caption)
                            Text("Start")
                                .font(.subheadline)
                                .fontWeight(.bold)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            LinearGradient(
                                colors: [programColor, programColor.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
                    )
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .background(
            ZStack {
                // Base gradient
                RoundedRectangle(cornerRadius: CornerRadius.xl)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark 
                                ? [Color(white: 0.18), Color.cardBackground]
                                : [Color.white, Color.white.opacity(0.95)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                // Inner glow
                RoundedRectangle(cornerRadius: CornerRadius.xl)
                    .stroke(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color.white.opacity(0.12), Color.white.opacity(0.02), Color.clear]
                                : [Color.white, Color.white.opacity(0.5), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1.5
                    )
                
                // Accent border
                RoundedRectangle(cornerRadius: CornerRadius.xl)
                    .stroke(
                        LinearGradient(
                            colors: [programColor.opacity(0.3), programColor.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
            }
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.08), radius: 16, x: 0, y: 8)
        // Subtle glow effect to draw attention
        .shadow(color: programColor.opacity(colorScheme == .dark ? 0.3 : 0.2), radius: 16, x: 0, y: 0)
        .shadow(color: programColor.opacity(colorScheme == .dark ? 0.2 : 0.15), radius: 24, x: 0, y: 0)
    }
    
    // MARK: - Swipeable Program & Challenge Widget
    
    /// Build array of widgets to display (up to 3 challenges + 1 program = max 4, but we allow 3 challenges max)
    // MARK: - Swipeable Workout Carousel
    // Page 0: Custom + Auto workout buttons
    // Page 1: Active Program widget (if available)
    
    private var swipeableWorkoutCarousel: some View {
        let hasActiveProgram = activeSmartProgramForWidget != nil
        let hasRecommendedProgram = topRecommendedSmartProgram != nil || isFirstTimeUser
        let showSecondPage = hasActiveProgram || hasRecommendedProgram
        let pageCount = showSecondPage ? 2 : 1
        
        return VStack(spacing: 4) {
            GeometryReader { geometry in
                let cardWidth = geometry.size.width
                let spacing: CGFloat = 16
                
                HStack(spacing: spacing) {
                    // Page 0: Workout Buttons
                    startWorkoutButton
                        .frame(width: cardWidth)
                    
                    // Page 1: Active Program (if available)
                    if showSecondPage {
                        unifiedProgramWidgetWithGlow(isVisible: selectedWorkoutPage == 1)
                            .frame(width: cardWidth)
                    }
                }
                .offset(x: -CGFloat(selectedWorkoutPage) * (cardWidth + spacing))
            }
            .frame(height: 160)
            .animation(.easeOut(duration: 0.25), value: selectedWorkoutPage)
            .highPriorityGesture(
                DragGesture(minimumDistance: 15)
                    .onEnded { value in
                        let horizontalAmount = value.translation.width
                        let verticalAmount = abs(value.translation.height)
                        
                        if abs(horizontalAmount) > verticalAmount * 1.5 && abs(horizontalAmount) > 30 {
                            HapticManager.impact(.medium)
                            if horizontalAmount < 0 && selectedWorkoutPage < pageCount - 1 {
                                selectedWorkoutPage += 1
                            } else if horizontalAmount > 0 && selectedWorkoutPage > 0 {
                                selectedWorkoutPage -= 1
                            }
                        }
                    }
            )
            
            // Page indicators (only if multiple pages)
            if pageCount > 1 {
                HStack(spacing: 8) {
                    ForEach(0..<pageCount, id: \.self) { index in
                        Capsule()
                            .fill(selectedWorkoutPage == index ? Color.blue : Color.gray.opacity(0.3))
                            .frame(width: selectedWorkoutPage == index ? 20 : 8, height: 6)
                            .animation(.easeOut(duration: 0.2), value: selectedWorkoutPage)
                            .onTapGesture {
                                HapticManager.impact(.light)
                                selectedWorkoutPage = index
                            }
                    }
                }
                .padding(.top, 8)
            }
        }
        .onAppear {
            // Default to Active Program page if user has one, otherwise Custom/Auto
            if activeSmartProgramForWidget != nil {
                selectedWorkoutPage = 1
            } else {
                selectedWorkoutPage = 0
            }
        }
    }
    
    // MARK: - Daily Quests Section
    
    private var dailyQuestsSection: some View {
        DailyQuestsWidget(questService: dailyQuestService)
    }
    
    // MARK: - Challenge Cards Section (kept together)
    
    private var challengeCardsSection: some View {
        // PRIORITY ORDER:
        // 1. Active challenges ALWAYS show first (up to 3)
        // 2. Pending sent challenges fill remaining slots (up to 3 total cards max)
        // 3. If only pending (no active), also show "Challenge a Friend" as swipeable option
        // 4. If no active AND no pending → show default "Challenge a Friend" widget only
        
        // Get active challenges (deduplicated by ID)
        let activeIds = Set(challengeService.activeChallenges.map { $0.id })
        let activeChallenges = Array(challengeService.activeChallenges.prefix(3))
        let groupChallenges = challengeService.activeGroupChallenges.filter { $0.iHaveAccepted }
        let activeCount = activeChallenges.count + groupChallenges.count
        
        // Only show pending if we have room (max 3 total cards)
        // CRITICAL: Filter out any pending that also appears in active (duplicate IDs)
        // Also filter invalid data and deduplicate
        let remainingSlots = max(0, 3 - activeCount)
        var seenPendingIds = Set<UUID>()
        let pendingSent = challengeService.pendingSentChallenges
            .filter { pending in
                // Must have valid data
                guard !pending.title.isEmpty && pending.durationDays > 0 else { return false }
                // Must not be a duplicate of an active challenge
                guard !activeIds.contains(pending.challengeId) else { return false }
                // Must not be a duplicate within pending list
                guard !seenPendingIds.contains(pending.challengeId) else { return false }
                seenPendingIds.insert(pending.challengeId)
                return true
            }
            .prefix(remainingSlots)
        let pendingArray = Array(pendingSent)
        let pendingCount = pendingArray.count
        
        // If we only have pending (no active), add the default widget as an option
        let showDefaultInCarousel = activeCount == 0 && pendingCount > 0 && pendingCount < 3
        let totalWidgetCount = activeCount + pendingCount + (showDefaultInCarousel ? 1 : 0)
        
        // Clamp the page to valid range - this ensures we always show SOMETHING
        let safePageIndex = totalWidgetCount > 0 ? min(max(0, selectedWidgetPage), totalWidgetCount - 1) : 0
        
        return Group {
            if totalWidgetCount > 0 {
                VStack(spacing: 4) {
                    if totalWidgetCount > 1 {
                        // Multiple cards - swipeable (max 3 cards)
                        GeometryReader { geometry in
                            let cardWidth = geometry.size.width
                            let spacing: CGFloat = 16
                            
                            HStack(spacing: spacing) {
                                // Active 1v1 challenges FIRST
                                ForEach(Array(activeChallenges.enumerated()), id: \.element.id) { index, challenge in
                                    activeChallengeDetailWidget(challenge: challenge)
                                        .frame(width: cardWidth)
                                        .opacity(safePageIndex == index ? 1 : 0)
                                }
                                // Group challenges
                                ForEach(Array(groupChallenges.enumerated()), id: \.element.id) { index, group in
                                    groupChallengeWidget(challenge: group)
                                        .frame(width: cardWidth)
                                        .opacity(safePageIndex == (activeChallenges.count + index) ? 1 : 0)
                                }
                                // Then pending sent challenges
                                ForEach(Array(pendingArray.enumerated()), id: \.offset) { index, pending in
                                    pendingSentChallengeWidget(challenge: pending)
                                        .frame(width: cardWidth)
                                        .opacity(safePageIndex == (activeCount + index) ? 1 : 0)
                                }
                                // Then "Challenge a Friend" widget (if only pending, no active)
                                if showDefaultInCarousel {
                                    getStartedChallengeWidget
                                        .frame(width: cardWidth)
                                        .opacity(safePageIndex == (activeCount + pendingCount) ? 1 : 0)
                                }
                            }
                            .offset(x: -CGFloat(safePageIndex) * (cardWidth + spacing))
                        }
                        .frame(height: 156)
                        .animation(.easeOut(duration: 0.2), value: safePageIndex)
                        .highPriorityGesture(
                            DragGesture(minimumDistance: 8)
                                .onEnded { value in
                                    let horizontalAmount = value.translation.width
                                    let verticalAmount = abs(value.translation.height)
                                    // Use the same calculation logic as above (including group challenges)
                                    let activeIdsNow = Set(challengeService.activeChallenges.map { $0.id })
                                    let currentActiveCount = min(3, challengeService.activeChallenges.count) + challengeService.activeGroupChallenges.count
                                    var seenNow = Set<UUID>()
                                    let currentPendingCount = challengeService.pendingSentChallenges
                                        .filter { p in
                                            guard !p.title.isEmpty && p.durationDays > 0 else { return false }
                                            guard !activeIdsNow.contains(p.challengeId) else { return false }
                                            guard !seenNow.contains(p.challengeId) else { return false }
                                            seenNow.insert(p.challengeId)
                                            return true
                                        }
                                        .prefix(max(0, 3 - currentActiveCount))
                                        .count
                                    let hasDefaultWidget = currentActiveCount == 0 && currentPendingCount > 0 && currentPendingCount < 3
                                    let currentTotal = currentActiveCount + currentPendingCount + (hasDefaultWidget ? 1 : 0)
                                    
                                    if abs(horizontalAmount) > verticalAmount * 1.5 && abs(horizontalAmount) > 20 && currentTotal > 0 {
                                        HapticManager.impact(.medium)
                                        if horizontalAmount < 0 && selectedWidgetPage < currentTotal - 1 {
                                            selectedWidgetPage += 1
                                        } else if horizontalAmount > 0 && selectedWidgetPage > 0 {
                                            selectedWidgetPage -= 1
                                        }
                                    }
                                }
                        )
                        
                        // Page indicators (dash and dot style)
                        HStack(spacing: 6) {
                            ForEach(0..<totalWidgetCount, id: \.self) { index in
                                Capsule()
                                    .fill(safePageIndex == index ? Color.blue : Color.gray.opacity(0.3))
                                    .frame(width: safePageIndex == index ? 20 : 8, height: 6)
                                    .animation(.easeOut(duration: 0.2), value: safePageIndex)
                                    .onTapGesture {
                                        HapticManager.impact(.light)
                                        selectedWidgetPage = index
                                    }
                            }
                        }
                        .padding(.vertical, 4)
                    } else if let activeChallenge = activeChallenges.first {
                        // Single active 1v1 challenge (no swiping needed)
                        activeChallengeDetailWidget(challenge: activeChallenge)
                    } else if let groupChallenge = groupChallenges.first {
                        // Single group challenge (pending or active)
                        groupChallengeWidget(challenge: groupChallenge)
                    } else if let firstPending = pendingArray.first {
                        // Single pending (show with default widget as carousel)
                        // When single pending exists, show it + default widget
                        let singlePendingCount = 2 // pending + default
                        let singleSafeIndex = min(max(0, selectedWidgetPage), singlePendingCount - 1)
                        
                        GeometryReader { geometry in
                            let cardWidth = geometry.size.width
                            let spacing: CGFloat = 16
                            
                            HStack(spacing: spacing) {
                                pendingSentChallengeWidget(challenge: firstPending)
                                    .frame(width: cardWidth)
                                    .opacity(singleSafeIndex == 0 ? 1 : 0)
                                
                                getStartedChallengeWidget
                                    .frame(width: cardWidth)
                                    .opacity(singleSafeIndex == 1 ? 1 : 0)
                            }
                            .offset(x: -CGFloat(singleSafeIndex) * (cardWidth + spacing))
                        }
                        .frame(height: 156)
                        .animation(.easeOut(duration: 0.2), value: selectedWidgetPage)
                        .highPriorityGesture(
                            DragGesture(minimumDistance: 8)
                                .onEnded { value in
                                    let horizontalAmount = value.translation.width
                                    let verticalAmount = abs(value.translation.height)
                                    
                                    if abs(horizontalAmount) > verticalAmount * 1.5 && abs(horizontalAmount) > 20 {
                                        HapticManager.impact(.medium)
                                        if horizontalAmount < 0 && selectedWidgetPage < 1 {
                                            selectedWidgetPage = 1
                                        } else if horizontalAmount > 0 && selectedWidgetPage > 0 {
                                            selectedWidgetPage = 0
                                        }
                                    }
                                }
                        )
                        
                        // Page indicators for single pending
                        HStack(spacing: 6) {
                            ForEach(0..<2, id: \.self) { index in
                                Circle()
                                    .fill(singleSafeIndex == index ? Color.orange : Color.gray.opacity(0.3))
                                    .frame(width: 6, height: 6)
                                    .scaleEffect(singleSafeIndex == index ? 1.0 : 0.8)
                                    .animation(.easeOut(duration: 0.2), value: singleSafeIndex)
                                    .onTapGesture {
                                        HapticManager.impact(.light)
                                        selectedWidgetPage = index
                                    }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                // Reset to first page when data changes
                .onChange(of: challengeService.activeChallenges.count) { _, _ in
                    selectedWidgetPage = 0
                }
                .onChange(of: challengeService.pendingSentChallenges.count) { _, _ in
                    // Reset page when pending count changes to avoid out of bounds
                    selectedWidgetPage = 0
                }
                .onAppear {
                    // Default to page 0 when section appears
                    selectedWidgetPage = 0
                }
            } else {
                // NO active challenges AND NO pending sent → show default widget only
                if !PremiumManager.shared.isPremiumUser || showChallengeWidget {
                    getStartedChallengeWidget
                }
            }
        }
    }
    
    // MARK: - Pending Sent Challenge Widget
    
    // State for cancel confirmation - UUID identifies which challenge is being canceled
    @State private var challengeToCancel: UUID?
    
    private func pendingSentChallengeWidget(challenge: PendingSentChallenge) -> some View {
        let resolvedType = challenge.resolvedType
        let challengeType = resolvedType
        let isShowingCancelForThis = Binding(
            get: { challengeToCancel == challenge.challengeId },
            set: { if !$0 { challengeToCancel = nil } }
        )
        
        return VStack(spacing: 0) {
            // Top row: Emoji + Title/Status + PENDING badge
            HStack(alignment: .center, spacing: 12) {
                CachedFriendPhoto(
                    friendId: challenge.opponentId.uuidString,
                    photoUrl: challenge.opponentPhotoUrl,
                    name: challenge.opponentName ?? "Friend",
                    size: 48,
                    showGradientRing: true,
                    gradientColors: [.orange, .yellow]
                )
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(challenge.displayTitle)
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        Text(challengeType.emoji)
                            .font(.system(size: 14))
                    }
                    
                    HStack(spacing: 4) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Text("Sent to \(challenge.opponentName?.components(separatedBy: " ").first ?? "friend")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, 14)
            .padding(.bottom, 10)
            
            // Bottom row: accent bar + details + Cancel button (matches "Challenge a Friend" inner card)
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.orange)
                    .frame(width: 4, height: 36)
                
                VStack(alignment: .leading, spacing: 3) {
                    let target = challenge.dailyTarget ?? 0
                    let formatted = target >= 1000 ? "\(target / 1000)K" : "\(target)"
                    HStack(spacing: 6) {
                        Text("\(formatted) \(challenge.targetUnit)/day")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        Text("PENDING")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.orange.opacity(0.85))
                            )
                    }
                    
                    HStack(spacing: 4) {
                        Text("\(challenge.durationDays) days")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Waiting to accept")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.orange)
                    }
                }
                
                Spacer()
                
                Button(action: {
                    HapticManager.impact(.medium)
                    challengeToCancel = challenge.challengeId
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark")
                            .font(.ds_caption)
                        Text("Cancel")
                            .font(.caption)
                            .fontWeight(.bold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, Spacing.xs)
                    .background(
                        Capsule()
                            .fill(Color.red.opacity(0.85))
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(colorScheme == .dark ? Color(white: 0.10) : Color(white: 0.94))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: CornerRadius.xl)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [
                                Color.orange.opacity(0.7),
                                Color.orange.opacity(0.5),
                                Color.orange.opacity(0.3),
                                Color.clear,
                                Color.clear,
                                Color.orange.opacity(0.2),
                                Color.yellow.opacity(0.4),
                                Color.orange.opacity(0.6)
                            ]),
                            center: .center,
                            angle: .degrees(challengeGlowPhase)
                        ),
                        lineWidth: 2
                    )
                    .blur(radius: 2)
                
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
                            colors: [Color.orange.opacity(0.5), Color.orange.opacity(0.3), Color.orange.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: Color.orange.opacity(0.15), radius: 15, x: 0, y: 0)
        .shadow(color: Color.orange.opacity(0.08), radius: 25, x: 0, y: 4)
        .confirmationDialog(
            "Cancel Challenge?",
            isPresented: isShowingCancelForThis,
            titleVisibility: .visible
        ) {
            Button("Cancel Challenge", role: .destructive) {
                Task {
                    print("🗑️ [DASHBOARD] Cancel challenge button tapped in confirmation dialog")
                    let success = await ChallengeService.shared.cancelPendingChallenge(challengeId: challenge.challengeId)
                    if success {
                        print("✅ [DASHBOARD] Challenge cancelled successfully")
                        HapticManager.notification(.success)
                    } else {
                        print("❌ [DASHBOARD] Cancel failed - refreshing to check if challenge is now active")
                        // Challenge might have just been accepted - refresh all lists
                        await ChallengeService.shared.fetchPendingSentChallenges()
                        await ChallengeService.shared.fetchActiveChallenges()
                        HapticManager.notification(.error)
                    }
                    challengeToCancel = nil
                }
            }
            Button("Keep Challenge", role: .cancel) {
                challengeToCancel = nil
            }
        } message: {
            Text("This will cancel the challenge request. \(challenge.opponentName?.components(separatedBy: " ").first ?? "Your friend") will be notified.")
        }
    }
    
    // Legacy - kept for compatibility
    private var widgetsToDisplay: [AnyView] {
        var widgets: [AnyView] = []
        
        // Add challenge widgets (up to 3)
        for challenge in challengeService.activeChallenges.prefix(3) {
            widgets.append(AnyView(activeChallengeDetailWidget(challenge: challenge)))
        }
        
        // Add program widget if available
        if activeSmartProgramForWidget != nil || topRecommendedSmartProgram != nil || isFirstTimeUser {
            widgets.append(AnyView(unifiedProgramWidget))
        }
        
        return widgets
    }
    
    private var swipeableProgramChallengeWidget: some View {
        let widgets = widgetsToDisplay
        let widgetCount = widgets.count
        
        // If multiple widgets exist, show swipeable container
        if widgetCount > 1 {
            return AnyView(
                VStack(spacing: 4) {
                    GeometryReader { geometry in
                        let cardWidth = geometry.size.width
                        let spacing: CGFloat = 16 // Space between cards
                        
                        HStack(spacing: spacing) {
                            ForEach(0..<widgetCount, id: \.self) { index in
                                widgets[index]
                                    .frame(width: cardWidth)
                                    .opacity(selectedWidgetPage == index ? 1 : 0)
                            }
                        }
                        .offset(x: -CGFloat(selectedWidgetPage) * (cardWidth + spacing))
                    }
                    .frame(height: 156)
                    // No .clipped() - allows glow to render naturally
                    .animation(.easeOut(duration: 0.2), value: selectedWidgetPage) // Snappy animation
                    // High priority gesture that recognizes swipes before buttons
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 8)
                            .onEnded { value in
                                let horizontalAmount = value.translation.width
                                let verticalAmount = abs(value.translation.height)
                                
                                // Only trigger if movement is primarily horizontal
                                if abs(horizontalAmount) > verticalAmount * 1.5 && abs(horizontalAmount) > 20 {
                                    HapticManager.impact(.medium)
                                    if horizontalAmount < 0 && selectedWidgetPage < widgetCount - 1 {
                                        // Swipe left - go to next
                                        selectedWidgetPage += 1
                                    } else if horizontalAmount > 0 && selectedWidgetPage > 0 {
                                        // Swipe right - go to previous
                                        selectedWidgetPage -= 1
                                    }
                                }
                            }
                    )
                    
                    // Custom page indicators (tappable to switch)
                    HStack(spacing: 6) {
                        ForEach(0..<widgetCount, id: \.self) { index in
                            Circle()
                                .fill(selectedWidgetPage == index ? Color.primary : Color.gray.opacity(0.3))
                                .frame(width: 6, height: 6)
                                .scaleEffect(selectedWidgetPage == index ? 1.0 : 0.8)
                                .animation(.easeOut(duration: 0.2), value: selectedWidgetPage)
                                .onTapGesture {
                                    HapticManager.impact(.light)
                                    selectedWidgetPage = index
                                }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onChange(of: widgetCount) { oldCount, newCount in
                    // Reset to valid page if widgets were removed
                    if selectedWidgetPage >= newCount {
                        selectedWidgetPage = max(0, newCount - 1)
                    }
                }
            )
        } else if widgetCount == 1 {
            // Single widget - no pagination needed
            return AnyView(widgets[0])
        } else {
            // No widgets - show program recommendation
            return AnyView(unifiedProgramWidget)
        }
    }
    
    // MARK: - Active Challenge Widget (Legacy - kept for single challenge scenarios)
    
    private var activeChallengeWidget: some View {
        Group {
            if let challenge = challengeService.activeChallenges.first {
                activeChallengeDetailWidget(challenge: challenge)
            } else {
                EmptyView()
            }
        }
    }
    
    private func activeChallengeDetailWidget(challenge: ActiveChallenge) -> some View {
        let isAccountability = challenge.mode == .accountability
        let resolvedType = challenge.resolvedType
        // Type-aware colors — each challenge type gets its own visual identity
        let typeColor: Color = resolvedType.color
        let typeGradient: [Color] = resolvedType.gradientColors
        let opponentFirst = challenge.opponentName?.components(separatedBy: " ").first ?? "Friend"
        
        return VStack(spacing: 0) {
            // Header — shared shape, type-aware content
            NavigationLink(value: challenge) {
                HStack(alignment: .center, spacing: 10) {
                    // Type-specific icon with gradient ring
                    ZStack {
                        Circle()
                            .stroke(LinearGradient(colors: typeGradient, startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2.5)
                            .frame(width: 36, height: 36)
                        Text(resolvedType.emoji)
                            .font(.system(size: 18))
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(challenge.displayTitle)
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        HStack(spacing: 6) {
                            Text(isAccountability ? "with \(opponentFirst)" : "vs \(opponentFirst)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            Text("•")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            Text("\(challenge.daysRemaining)d left")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(typeColor)
                        }
                    }
                    
                    Spacer()
                    
                    // Mode badge
                    Text(isAccountability ? "🤝" : "⚔️")
                        .font(.ds_bodyRegular)
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, Spacing.sm)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Bottom section — different layout per mode, type-aware colors + live data
            HStack(spacing: 0) {
                // Left accent bar — type-colored
                RoundedRectangle(cornerRadius: 2)
                    .fill(LinearGradient(colors: typeGradient, startPoint: .top, endPoint: .bottom))
                    .frame(width: 4)
                    .padding(.vertical, 4)
                
                if isAccountability {
                    accountabilityProgressSection(challenge: challenge, challengeColor: typeColor, typeGradient: typeGradient)
                } else {
                    competitionProgressSection(challenge: challenge, challengeColor: typeColor, typeGradient: typeGradient)
                }
            }
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .fill(colorScheme == .dark
                        ? Color.white.opacity(0.04)
                        : Color.black.opacity(0.03))
            )
            .padding(.horizontal, Spacing.sm)
            .padding(.bottom, 12)
        }
        .background(
            ZStack {
                // Animated glowing border — type-colored
                RoundedRectangle(cornerRadius: CornerRadius.xl)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [
                                typeColor.opacity(0.7),
                                typeGradient.last?.opacity(0.5) ?? typeColor.opacity(0.5),
                                typeColor.opacity(0.3),
                                Color.clear,
                                Color.clear,
                                typeColor.opacity(0.2),
                                typeGradient.last?.opacity(0.4) ?? typeColor.opacity(0.4),
                                typeColor.opacity(0.6)
                            ]),
                            center: .center,
                            angle: .degrees(challengeGlowPhase)
                        ),
                        lineWidth: 2
                    )
                    .blur(radius: 2)
                
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
                            colors: [typeColor.opacity(0.5), typeGradient.last?.opacity(0.3) ?? typeColor.opacity(0.3), typeColor.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: typeColor.opacity(0.15), radius: 15, x: 0, y: 0)
        .shadow(color: typeColor.opacity(0.08), radius: 25, x: 0, y: 4)
    }
    
    // MARK: - Accountability Progress (buddy check-in)
    
    private func accountabilityProgressSection(challenge: ActiveChallenge, challengeColor: Color, typeGradient: [Color]) -> some View {
        let resolver = ChallengeProgressResolver.shared
        let myLiveProgress = resolver.liveProgress(for: challenge)
        // Use today's progress only — 0 means the opponent hasn't started today (correct after midnight reset)
        let oppProgress = challenge.opponentTodayProgress ?? 0
        let myDone = challenge.dailyTarget.map { myLiveProgress >= $0 } ?? false
        let oppDone = challenge.dailyTarget.map { oppProgress >= $0 } ?? false
        let opponentFirst = challenge.opponentName?.components(separatedBy: " ").first ?? "Buddy"
        let livePercent = resolver.progressPercentage(for: challenge)
        let resolvedType = challenge.resolvedType
        
        return HStack(spacing: 12) {
            // Both avatars together with status
            HStack(spacing: -8) {
                challengeAvatar(
                    isUser: true,
                    photoUrl: nil,
                    name: userManager.currentUser?.name,
                    done: myDone,
                    gradientColors: typeGradient
                )
                challengeAvatar(
                    isUser: false,
                    userId: challenge.opponentId.uuidString,
                    photoUrl: challenge.opponentPhotoUrl,
                    name: challenge.opponentName,
                    done: oppDone,
                    gradientColors: typeGradient
                )
            }
            
            VStack(alignment: .leading, spacing: 4) {
                // Live progress value for "my" side
                HStack(spacing: 4) {
                    Text(myDone ? "✅" : "⬜")
                        .font(.system(size: 12))
                    Text(resolver.formattedProgress(for: challenge))
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(myDone ? .green : challengeColor)
                    
                    Text("·")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text(oppDone ? "✅" : "⬜")
                        .font(.system(size: 12))
                    Text(opponentFirst)
                        .font(.caption2)
                        .foregroundColor(oppDone ? .green : .secondary)
                        .lineLimit(1)
                }
                
                // Shared streak
                HStack(spacing: 4) {
                    if challenge.myCurrentStreak > 0 {
                        Image(systemName: "flame.fill")
                            .font(.ds_caption)
                            .foregroundColor(.orange)
                        Text("\(challenge.myCurrentStreak)-day streak together")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(LinearGradient(colors: [.orange, .yellow], startPoint: .leading, endPoint: .trailing))
                    } else {
                        // Type-specific encouragement
                        Text(accountabilityEncouragement(for: resolvedType))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer(minLength: 4)
            
            // Daily progress ring — type-colored with live percentage
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.15), lineWidth: 3)
                    .frame(width: 36, height: 36)
                Circle()
                    .trim(from: 0, to: livePercent)
                    .stroke(LinearGradient(colors: typeGradient, startPoint: .topLeading, endPoint: .bottomTrailing), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 36, height: 36)
                    .rotationEffect(.degrees(-90))
                
                if myDone && oppDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.green)
                } else {
                    Text("\(Int(livePercent * 100))%")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                }
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 14)
    }
    
    /// Returns a type-specific encouragement string for accountability challenges
    private func accountabilityEncouragement(for type: ChallengeType) -> String {
        switch type {
        case .hydrate: return "Drink up together today!"
        case .protein: return "Hit your protein today!"
        case .calories: return "Burn it together!"
        case .steps: return "Start stepping today!"
        case .walk: return "Get walking today!"
        case .run: return "Lace up and go!"
        case .lift: return "Hit the weights today!"
        case .activeMinutes: return "Get moving today!"
        case .workoutStreak: return "Start your streak today!"
        }
    }
    
    // MARK: - Competition Progress (head-to-head battle)
    
    private func competitionProgressSection(challenge: ActiveChallenge, challengeColor: Color, typeGradient: [Color]) -> some View {
        let resolver = ChallengeProgressResolver.shared
        let resolvedType = challenge.resolvedType
        // Use live data for my progress, server data for opponent
        // Use today's progress only — 0 means opponent hasn't started today (correct after midnight reset)
        let myLiveToday = resolver.liveProgress(for: challenge)
        let oppToday = challenge.opponentTodayProgress ?? 0
        let amWinningNow = myLiveToday > oppToday
        
        return HStack(spacing: 8) {
            // Your side
            HStack(spacing: 8) {
                challengeAvatar(
                    isUser: true,
                    photoUrl: nil,
                    name: userManager.currentUser?.name,
                    done: amWinningNow,
                    gradientColors: typeGradient
                )
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 3) {
                        Text("You")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                        if amWinningNow {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 8))
                                .foregroundColor(.yellow)
                        }
                    }
                    
                    Text(resolver.formatValue(myLiveToday, unit: challenge.targetUnit, type: resolvedType))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(amWinningNow ? .green : .primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: 85, alignment: .leading)
            }
            
            Spacer(minLength: 4)
            
            // VS divider with score diff
            VStack(spacing: 2) {
                Text("⚔️")
                    .font(.system(size: 14))
                
                if myLiveToday != oppToday {
                    let diff = abs(myLiveToday - oppToday)
                    let diffStr = resolver.formatValue(diff, unit: challenge.targetUnit, type: resolvedType)
                    Text(amWinningNow ? "+\(diffStr)" : "-\(diffStr)")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundColor(amWinningNow ? .green : .red)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(minWidth: 30)
            
            Spacer(minLength: 4)
            
            // Opponent side
            HStack(spacing: 8) {
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 3) {
                        if !amWinningNow && oppToday > 0 {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 8))
                                .foregroundColor(.yellow)
                        }
                        Text(challenge.opponentName?.components(separatedBy: " ").first ?? "Friend")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    Text(resolver.formatValue(oppToday, unit: challenge.targetUnit, type: resolvedType))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(!amWinningNow && oppToday > 0 ? .green : .primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: 85, alignment: .trailing)
                
                challengeAvatar(
                    isUser: false,
                    userId: challenge.opponentId.uuidString,
                    photoUrl: challenge.opponentPhotoUrl,
                    name: challenge.opponentName,
                    done: !amWinningNow && oppToday > 0,
                    gradientColors: [.orange, .red]
                )
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 14)
    }
    
    // MARK: - Challenge Avatar Helper
    
    private func challengeAvatar(isUser: Bool, userId: String? = nil, photoUrl: String?, name: String?, done: Bool, gradientColors: [Color]) -> some View {
        Group {
            if isUser {
                if let cachedImage = ProfilePhotoCache.shared.cachedImage {
                    Image(uiImage: cachedImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 36, height: 36)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(done ? Color.green : Color.gray.opacity(0.3), lineWidth: 2))
                } else {
                    CachedFriendPhoto(
                        friendId: SupabaseManager.shared.currentUser?.id.uuidString ?? "me",
                        photoUrl: nil,
                        name: name ?? "You",
                        size: 36,
                        showGradientRing: false,
                        gradientColors: gradientColors
                    )
                    .overlay(Circle().stroke(done ? Color.green : Color.gray.opacity(0.3), lineWidth: 2))
                }
            } else {
                CachedFriendPhoto(
                    friendId: userId ?? UUID().uuidString,
                    photoUrl: photoUrl,
                    name: name ?? "Friend",
                    size: 36,
                    showGradientRing: false,
                    gradientColors: gradientColors
                )
                .overlay(Circle().stroke(done ? Color.green : Color.gray.opacity(0.3), lineWidth: 2))
            }
        }
    }
    
    // MARK: - Group Member Avatar Helper
    
    @ViewBuilder
    private func groupMemberAvatar(member: GroupChallengeMember, currentUserId: UUID?, size: CGFloat, accentGradient: [Color]) -> some View {
        if member.userId == currentUserId, let cachedImage = ProfilePhotoCache.shared.cachedImage {
            Image(uiImage: cachedImage)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            CachedFriendPhoto(
                friendId: member.userId.uuidString,
                photoUrl: member.profilePhotoUrl,
                name: member.name ?? member.username ?? "?",
                size: size,
                showGradientRing: false,
                gradientColors: accentGradient
            )
        }
    }
    
    // MARK: - Group Challenge Widget (3-person)
    
    private func groupChallengeWidget(challenge: ActiveGroupChallenge) -> some View {
        let resolvedType = challenge.resolvedType
        let isAccountability = challenge.challengeMode == .accountability
        let accentColor: Color = resolvedType.color
        let accentGradient: [Color] = resolvedType.gradientColors
        let allMembers = challenge.members ?? []
        let acceptedMembers = challenge.acceptedMembers
        let pendingMembers = challenge.pendingMembers
        let isPending = challenge.isPending
        let challengeColor = resolvedType.color
        
        return VStack(spacing: 0) {
            // Header
            NavigationLink(value: challenge) {
                HStack(alignment: .center, spacing: 10) {
                    ZStack {
                        Circle()
                            .stroke(LinearGradient(colors: resolvedType.gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2.5)
                            .frame(width: 36, height: 36)
                        Text(resolvedType.emoji)
                            .font(.system(size: 18))
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(challenge.displayTitle)
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            
                            if isPending {
                                Text("PENDING")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.teal.opacity(0.7)))
                            }
                        }
                        
                        HStack(spacing: 6) {
                            Text("\(allMembers.count) buddies")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            if isPending {
                                let pendingNames = pendingMembers.map { $0.firstName }.prefix(2)
                                Text("• Waiting for \(pendingNames.joined(separator: " & "))")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                                    .lineLimit(1)
                            } else {
                                if pendingMembers.count > 0 {
                                    Text("• \(pendingMembers.count) pending")
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                }
                                
                                Text("• \(challenge.daysRemaining)d left")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(accentColor)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    Text(isAccountability ? "🤝" : "⚔️")
                        .font(.ds_bodyRegular)
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, Spacing.sm)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Head-to-head battle row — User1 vs User2 vs User3
            HStack(spacing: 0) {
                // Left accent bar
                RoundedRectangle(cornerRadius: 2)
                    .fill(LinearGradient(colors: isPending ? [challengeColor, .teal] : accentGradient, startPoint: .top, endPoint: .bottom))
                    .frame(width: 4)
                    .padding(.vertical, 4)
                
                if isPending {
                    // PENDING: Show acceptance status + nudge buttons with "vs" between
                    HStack(spacing: 0) {
                        let currentUserId = SupabaseManager.shared.currentUser?.id
                        let membersArray = Array(allMembers.prefix(4))
                        ForEach(Array(membersArray.enumerated()), id: \.element.id) { index, member in
                            if index > 0 {
                                Text("vs")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.secondary)
                                    .frame(minWidth: 20)
                            }
                            VStack(spacing: 4) {
                                groupMemberAvatar(member: member, currentUserId: currentUserId, size: 28, accentGradient: [challengeColor, .teal])
                                    .opacity(member.isPending ? 0.5 : 1)
                                
                                if member.isAccepted {
                                    Text("✅")
                                        .font(.system(size: 12))
                                } else if member.isPending && member.userId != currentUserId {
                                    // Nudge button for pending members (not yourself)
                                    let nudgeKey = "nudge_\(challenge.challengeId.uuidString)_\(member.userId.uuidString)"
                                    if UserDefaults.standard.bool(forKey: nudgeKey) {
                                        Text("⏳")
                                            .font(.system(size: 12))
                                    } else {
                                        Button {
                                            nudgePendingMember(challengeId: challenge.challengeId, memberId: member.userId)
                                        } label: {
                                            Text("Nudge")
                                                .font(.system(size: 9, weight: .semibold))
                                                .foregroundColor(.white)
                                                .padding(.horizontal, Spacing.xs)
                                                .padding(.vertical, 4)
                                                .background(Capsule().fill(Color.teal.opacity(0.7)))
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                } else {
                                    Text("⏳")
                                        .font(.system(size: 12))
                                }
                                
                                Text(member.userId == currentUserId ? "You" : String(member.firstName.prefix(6)))
                                    .font(.system(size: 8))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, Spacing.sm)
                } else {
                    // ACTIVE: Head-to-head battle layout
                    let currentUserId = SupabaseManager.shared.currentUser?.id
                    let resolver = ChallengeProgressResolver.shared
                    // Use live HealthKit data for "my" progress, DB data for others
                    let myLiveProgress = resolver.liveProgress(for: challenge, serverValue: acceptedMembers.first(where: { $0.userId == currentUserId })?.todayProgress ?? 0)
                    let sorted = acceptedMembers.sorted { m1, m2 in
                        let p1 = m1.userId == currentUserId ? myLiveProgress : m1.todayProgress
                        let p2 = m2.userId == currentUserId ? myLiveProgress : m2.todayProgress
                        return p1 > p2
                    }
                    let leaderId = sorted.first?.userId
                    
                    HStack(spacing: 0) {
                        ForEach(Array(sorted.prefix(4).enumerated()), id: \.element.id) { index, member in
                            if index > 0 {
                                // VS divider
                                Text("⚔️")
                                    .font(.ds_labelSmall)
                                    .frame(minWidth: 20)
                            }
                            
                            let isMe = member.userId == currentUserId
                            let displayProgress = isMe ? myLiveProgress : member.todayProgress
                            let isLeader = member.userId == leaderId
                            let done = challenge.dailyTarget.map { displayProgress >= $0 } ?? false
                            
                            HStack(spacing: 6) {
                                groupMemberAvatar(member: member, currentUserId: currentUserId, size: 32, accentGradient: accentGradient)
                                    .overlay(
                                        Circle()
                                            .stroke(done ? Color.green : (isLeader ? Color.yellow.opacity(0.6) : Color.gray.opacity(0.3)), lineWidth: 2)
                                    )
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 3) {
                                        Text(isMe ? "You" : String(member.firstName.prefix(6)))
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                        if isLeader {
                                            Image(systemName: "crown.fill")
                                                .font(.system(size: 7))
                                                .foregroundColor(.yellow)
                                        }
                                    }
                                    
                                    Text(formatChallengeProgress(displayProgress, unit: challenge.targetUnit))
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                        .foregroundColor(isLeader ? .green : .primary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, 10)
                }
            }
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.03))
            )
            .padding(.horizontal, Spacing.sm)
            .padding(.bottom, 12)
        }
        .background(
            ZStack {
                // Animated glowing border (always on — teal glow for consistency)
                RoundedRectangle(cornerRadius: CornerRadius.xl)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [
                                challengeColor.opacity(0.7),
                                Color.teal.opacity(0.5),
                                challengeColor.opacity(0.3),
                                Color.clear,
                                Color.clear,
                                challengeColor.opacity(0.2),
                                Color.mint.opacity(0.4),
                                challengeColor.opacity(0.6)
                            ]),
                            center: .center,
                            angle: .degrees(challengeGlowPhase)
                        ),
                        lineWidth: 2
                    )
                    .blur(radius: 2)
                
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
                            colors: [challengeColor.opacity(0.5), Color.teal.opacity(0.3), challengeColor.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: challengeColor.opacity(0.15), radius: 15, x: 0, y: 0)
        .shadow(color: challengeColor.opacity(0.08), radius: 25, x: 0, y: 4)
    }
    
    private func nudgePendingMember(challengeId: UUID, memberId: UUID) {
        HapticManager.impact(.medium)
        let nudgeKey = "nudge_\(challengeId.uuidString)_\(memberId.uuidString)"
        
        Task {
            let sent = await ChallengeService.shared.nudgeGroupChallengeMember(
                challengeId: challengeId,
                recipientId: memberId
            )
            if sent {
                UserDefaults.standard.set(true, forKey: nudgeKey)
                HapticManager.notification(.success)
                // Force UI refresh
                await ChallengeService.shared.fetchActiveGroupChallenges()
            }
        }
    }
    
    private func formatChallengeProgress(_ value: Int, unit: String) -> String {
        // Type-aware formatting based on unit
        switch unit.lowercased() {
        case "ml":
            if value >= 1000 {
                return String(format: "%.1fL", Double(value) / 1000)
            }
            return "\(value) ml"
        case "oz":
            return "\(value) oz"
        case "grams", "g":
            return "\(value)g"
        case "cal", "calories", "kcal":
            if value >= 10000 {
                return String(format: "%.1fk", Double(value) / 1000)
            }
            return "\(value) cal"
        default:
            if value >= 10000 {
                return String(format: "%.1fk", Double(value) / 1000)
            }
            return value.formatted()
        }
    }
    
    // MARK: - Unified Smart Program Widget
    
    /// Determines if this is a brand new user who hasn't started any workout or program
    private var isFirstTimeUser: Bool {
        let totalWorkouts = userManager.currentUser?.totalWorkouts ?? 0
        let hasStartedProgram = !smartProgramEngine.userPrograms.isEmpty
        return totalWorkouts == 0 && !hasStartedProgram
    }
    
    /// Get the 10 personalized programs from SmartProgramEngine
    private var personalizedPrograms: [PersonalizedProgram] {
        smartProgramEngine.getPersonalizedPrograms(for: userManager.currentUser)
    }
    
    /// Get the best recommended program (highest match, unlocked)
    private var topRecommendedSmartProgram: PersonalizedProgram? {
        personalizedPrograms
            .filter { !$0.isCompleted && $0.isUnlocked }
            .sorted { $0.matchPercentage > $1.matchPercentage }
            .first
    }
    
    /// Get active SmartProgram if any (most recently started)
    private var activeSmartProgramForWidget: SmartActiveProgram? {
        smartProgramEngine.userPrograms
            .filter { !$0.isCompleted }
            .sorted { $0.startDate > $1.startDate }  // Most recent first
            .first
    }
    
    /// Compute widget refresh ID based on program state
    private var activeProgramWidgetId: String {
        guard let program = activeSmartProgramForWidget else { return "none" }
        let currentDay = program.generatedDays.first { $0.dayNumber == program.currentDay }
        return "\(program.id)-\(program.completedDays.count)-\(currentDay?.isCompleted ?? false)"
    }
    
    @ViewBuilder
    private var unifiedProgramWidget: some View {
        unifiedProgramWidgetWithGlow(isVisible: true)
    }
    
    @ViewBuilder
    private func unifiedProgramWidgetWithGlow(isVisible: Bool) -> some View {
        if !userManager.hasCompletedOnboarding {
            EmptyView()
        } else if let activeProgram = activeSmartProgramForWidget {
            activeSmartProgramDetailWidget(program: activeProgram, isVisible: isVisible)
                .id(activeProgramWidgetId)
        } else if let recommended = topRecommendedSmartProgram, showRecommendedWidget {
            // Show recommended program widget (even for first-time users)
            recommendedSmartProgramWidget(program: recommended)
        } else if !showRecommendedWidget {
            // If recommended is hidden, show browse programs instead
            browseProgramsWidget
        } else {
            browseProgramsWidget
        }
    }
    
    // MARK: - Get Started Widget (First Time Users) - Uses SmartProgramEngine
    
    private var getStartedSmartWidget: some View {
        let accentColor = Color.green
        
        return VStack(spacing: 10) {
            // Compact header with icon and text side by side
            HStack(spacing: 12) {
                // Sparkle icon - smaller
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [accentColor.opacity(0.2), accentColor.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "sparkles")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [accentColor, accentColor.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Get Started!")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text("10 programs created for you")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            // Show top recommended program preview
            if let program = topRecommendedSmartProgram {
                let template = program.template
                let totalWeeks = (template.totalDays + 6) / 7
                
                HStack(spacing: 10) {
                    // Program icon - smaller
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [accentColor, accentColor.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 36, height: 36)
                        
                        Image(systemName: template.category.icon)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text(program.personalizedName)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        HStack(spacing: 4) {
                            Text("\(totalWeeks) weeks")
                            Text("•")
                            Text("\(program.matchPercentage)% match")
                                .foregroundColor(accentColor)
                        }
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Text("Start")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [accentColor, accentColor.opacity(0.8)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.97))
                )
                .onTapGesture {
                    if let user = userManager.currentUser {
                        if let startedProgram = SmartProgramEngine.shared.startProgram(templateId: template.id, for: user) {
                            // Navigate to the first day of the program
                            if let firstDay = startedProgram.generatedDays.first {
                                workoutManager.navigateProgramData = startedProgram
                                workoutManager.navigateProgramDay = firstDay
                                workoutManager.shouldNavigateToProgramDay = true
                            }
                        }
                    }
                }
            }
            
            // Divider
            HStack {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 1)
            }
            .padding(.horizontal, Spacing.md)
            
            // Or explore all programs
            Button(action: {
                // 🔧 Redirect to Workout tab's programs view
                workoutManager.shouldNavigateToPrograms = true
            }) {
                Text("or explore all programs →")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 4)
        }
        .padding(Spacing.md)
        .background(
            ZStack {
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
                
                // Subtle accent border
                RoundedRectangle(cornerRadius: CornerRadius.xl)
                    .stroke(
                        LinearGradient(
                            colors: [accentColor.opacity(0.3), accentColor.opacity(0.1), Color.clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            }
        )
        .shadow(color: accentColor.opacity(0.15), radius: 20, x: 0, y: 8)
    }
    
    // MARK: - Phone Verification Prompt Sheet
    
    @ViewBuilder
    private var phoneVerificationPromptSheet: some View {
        ExistingUserPhonePrompt(
            onComplete: { [self] phoneNumber in
                handlePhoneVerificationComplete(phoneNumber)
            },
            onSkip: { [self] in
                handlePhoneVerificationSkip()
            }
        )
        .interactiveDismissDisabled()
    }
    
    private func handlePhoneVerificationComplete(_ phoneNumber: String) {
        Task {
            do {
                try await SupabaseManager.shared.updatePhoneNumber(phoneNumber)
                await MainActor.run {
                    userHasVerifiedPhone = true
                    hasSeenPhonePrompt = true
                }
                if let user = userManager.currentUser {
                    user.phoneNumber = phoneNumber
                    try? viewContext.save()
                }
                print("📱 [PHONE PROMPT] Phone saved successfully: \(phoneNumber)")
            } catch {
                print("❌ [PHONE PROMPT] Failed to save phone: \(error)")
            }
        }
    }
    
    private func handlePhoneVerificationSkip() {
        hasSeenPhonePrompt = true
        print("📱 [PHONE PROMPT] User skipped phone verification")
    }
    
    // MARK: - Get Started Challenge Widget - "Challenge a Friend!" entry point
    
    private var getStartedChallengeWidget: some View {
        let challengeColor = Color.orange
        
        return Button { showingChallengeCreation = true } label: {
            VStack(spacing: 0) {
                // Top row: Trophy + Title + Chevron
                HStack(alignment: .center, spacing: 12) {
                    ZStack {
                        Circle()
                            .stroke(challengeColor.opacity(0.3), lineWidth: 4)
                            .frame(width: 48, height: 48)
                        
                        Text("🏆")
                            .font(.system(size: 22))
                    }
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Challenge a Friend!")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        
                        Text("Compete head-to-head on fitness goals")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, 14)
                .padding(.bottom, 10)
                
                // Bottom row: Activity info + Challenge button (inner card)
                HStack(spacing: 10) {
                    // Green accent bar
                    RoundedRectangle(cornerRadius: 2)
                        .fill(challengeColor)
                        .frame(width: 4, height: 36)
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Steps, Workouts & More")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        HStack(spacing: 4) {
                            Text("7-30 days")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("•")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("Daily goals")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(challengeColor)
                        }
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .font(.ds_caption)
                        Text("Challenge")
                            .font(.caption)
                            .fontWeight(.bold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, Spacing.xs)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [.orange, Color(red: 1.0, green: 0.6, blue: 0.0)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
                }
                .padding(Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(colorScheme == .dark ? Color(white: 0.10) : Color(white: 0.94))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 1)
                        )
                )
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
        }
        .buttonStyle(.plain)
        .background(
            ZStack {
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
                        AngularGradient(
                            gradient: Gradient(colors: [
                                Color.orange.opacity(0.7),
                                Color.orange.opacity(0.5),
                                Color.orange.opacity(0.3),
                                Color.clear,
                                Color.clear,
                                Color.orange.opacity(0.2),
                                Color.yellow.opacity(0.4),
                                Color.orange.opacity(0.6)
                            ]),
                            center: .center,
                            angle: .degrees(challengeGlowPhase)
                        ),
                        lineWidth: 2
                    )
                    .blur(radius: 2)
                
                RoundedRectangle(cornerRadius: CornerRadius.xl)
                    .stroke(
                        LinearGradient(
                            colors: [Color.orange.opacity(0.5), Color.orange.opacity(0.3), Color.orange.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: Color.orange.opacity(0.15), radius: 15, x: 0, y: 0)
        .shadow(color: Color.orange.opacity(0.08), radius: 25, x: 0, y: 4)
        .onAppear {
            withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                challengeGlowPhase = 360
            }
        }
    }
    
    // MARK: - Challenge Type Button Helper
    
    private func challengeTypeButton(emoji: String, title: String, subtitle: String, gradient: [Color]) -> some View {
        VStack(spacing: 6) {
            Text(emoji)
                .font(.system(size: 26))
            
            Text(title)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .lineLimit(1)
            
            Text(subtitle)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .fill(colorScheme == .dark ? Color.cardBackground : Color(white: 0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.md)
                        .stroke(
                            LinearGradient(colors: [gradient[0].opacity(0.4), gradient[1].opacity(0.2)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 1
                        )
                )
        )
    }
    
    // MARK: - Recommended For You Widget (Returning Users) - Uses SmartProgramEngine
    
    private func recommendedSmartProgramWidget(program: PersonalizedProgram) -> some View {
        let template = program.template
        let programColor = Color.green
        let totalWeeks = (template.totalDays + 6) / 7
        
        return VStack(spacing: 0) {
            // Header - Tap to view all programs (matching active program header style)
            Button {
                workoutManager.shouldNavigateToPrograms = true
            } label: {
                HStack(alignment: .center, spacing: 10) {
                    // Match percentage ring (like progress ring)
                    ZStack {
                        Circle()
                            .stroke(Color.gray.opacity(0.2), lineWidth: 4)
                            .frame(width: 44, height: 44)
                        
                        Circle()
                            .trim(from: 0, to: Double(program.matchPercentage) / 100)
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
                        
                        Text("\(program.matchPercentage)%")
                            .font(.ds_caption)
                            .foregroundColor(programColor)
                    }
                    
                    // Program info
                    VStack(alignment: .leading, spacing: 2) {
                        Text(template.baseName)
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        HStack(spacing: 6) {
                            Text("\(totalWeeks) weeks")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            Text("•")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            Text("\(template.daysPerWeek) days/wk")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(programColor)
                        }
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, Spacing.sm)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Inner card - Program preview with Start button (matching workout card style)
            Button {
                if let user = userManager.currentUser {
                    if let startedProgram = SmartProgramEngine.shared.startProgram(templateId: template.id, for: user) {
                        if let firstDay = startedProgram.generatedDays.first {
                            workoutManager.navigateProgramData = startedProgram
                            workoutManager.navigateProgramDay = firstDay
                            workoutManager.shouldNavigateToProgramDay = true
                        }
                    }
                }
            } label: {
                HStack(spacing: 0) {
                    // Left accent bar
                    RoundedRectangle(cornerRadius: 2)
                        .fill(programColor)
                        .frame(width: 4)
                        .padding(.vertical, 4)
                    
                    HStack(spacing: 12) {
                        // Program details
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text("Recommended")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.primary)
                                
                                Image(systemName: template.category.icon)
                                    .font(.ds_caption)
                                    .foregroundColor(.white)
                                    .padding(4)
                                    .background(
                                        Circle()
                                            .fill(programColor)
                                    )
                            }
                            
                            HStack(spacing: 4) {
                                Text("\(template.estimatedMinutesPerDay) min")
                                Text("•")
                                    .font(.caption2)
                                Text(template.category.rawValue)
                                    .lineLimit(1)
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        .padding(.leading, 10)
                        
                        Spacer()
                        
                        // Start button
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
                                        colors: [programColor, programColor.opacity(0.8)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                    }
                }
                .padding(Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(colorScheme == .dark ? Color.cardBackground : Color(white: 0.96))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(programColor.opacity(0.2), lineWidth: 1)
                        )
                )
                .padding(.horizontal, Spacing.sm)
                .padding(.bottom, 12)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .background(
            ZStack {
                // Main card background
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
                
                // Subtle accent border
                RoundedRectangle(cornerRadius: CornerRadius.xl)
                    .stroke(
                        LinearGradient(
                            colors: [programColor.opacity(0.25), programColor.opacity(0.1), Color.clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        // Subtle shadows matching active program widget
        .shadow(color: programColor.opacity(colorScheme == .dark ? 0.15 : 0.1), radius: 12, x: 0, y: 6)
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.2 : 0.06), radius: 8, x: 0, y: 3)
    }
    
    // MARK: - Active Smart Program Widget (With Today/Tomorrow Preview)
    
    @State private var activeWidgetGlowRotation: Double = 0
    
    private func activeSmartProgramDetailWidget(program: SmartActiveProgram, isVisible: Bool = true) -> some View {
        let programColor = Color.green
        let template = personalizedPrograms.first { $0.template.id == program.templateId }?.template
        let completedDays = program.completedDays.count
        let totalDays = template?.totalDays ?? program.generatedDays.count
        let totalWeeks = (totalDays + 6) / 7
        let currentWeek = (program.currentDay - 1) / max(1, template?.daysPerWeek ?? 4) + 1
        let progress = totalDays > 0 ? Double(completedDays) / Double(totalDays) * 100 : 0
        
        // Determine which day to show
        let currentDay = program.generatedDays.first { $0.dayNumber == program.currentDay }
        let isTodayCompleted = currentDay?.isCompleted ?? false
        let nextDay = program.generatedDays.first { !$0.isCompleted && $0.dayNumber > program.currentDay }
        let dayToShow = isTodayCompleted ? nextDay : currentDay
        let dayLabel = isTodayCompleted ? "Tomorrow's Workout" : "Today's Workout"
        
        return VStack(spacing: 0) {
            // Header - Tap anywhere to go to Program Overview (on Workout tab)
            Button {
                workoutManager.navigateProgramData = program
                workoutManager.navigateProgramTemplate = template
                workoutManager.shouldNavigateToProgramOverview = true
            } label: {
                HStack(alignment: .center, spacing: 10) {
                    // Progress ring as icon
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
                    
                    // Program info
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
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, Spacing.sm)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Today/Tomorrow's workout section
            if isTodayCompleted {
                // Completed state - "Great work!" message
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 28))
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
                            workoutManager.navigateProgramData = program
                            workoutManager.navigateProgramDay = next
                            workoutManager.shouldNavigateToProgramDay = true
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
                // Active workout - Left accent bar style (navigates to Workout tab)
                Button {
                    workoutManager.navigateProgramData = program
                    workoutManager.navigateProgramDay = day
                    workoutManager.shouldNavigateToProgramDay = true
                } label: {
                    HStack(spacing: 0) {
                        // Left accent bar
                        RoundedRectangle(cornerRadius: 2)
                            .fill(programColor)
                            .frame(width: 4)
                            .padding(.vertical, 4)
                        
                        HStack(spacing: 12) {
                            // Workout info
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
                            
                            // Start button
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
                // All days completed
                VStack(spacing: 8) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 28))
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
                // Soft glow when visible and workout not complete
                if isVisible && !isTodayCompleted {
                    RoundedRectangle(cornerRadius: 26)
                        .stroke(programColor.opacity(0.3), lineWidth: 2)
                        .blur(radius: 6)
                }
                
                // Main card background with gradient
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
                
                // Subtle accent border - enhanced when visible
                RoundedRectangle(cornerRadius: CornerRadius.xl)
                    .stroke(
                        LinearGradient(
                            colors: isTodayCompleted 
                                ? [Color.gray.opacity(0.15), Color.gray.opacity(0.05), Color.clear]
                                : [programColor.opacity(isVisible ? 0.35 : 0.2), programColor.opacity(isVisible ? 0.15 : 0.08), Color.clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: isVisible ? 1.5 : 1
                    )
            }
        )
        // Enhanced shadows when visible, subtle when off-screen
        .shadow(color: programColor.opacity(isVisible ? (colorScheme == .dark ? 0.25 : 0.18) : (colorScheme == .dark ? 0.1 : 0.06)), radius: isVisible ? 16 : 8, x: 0, y: isVisible ? 4 : 3)
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.2 : 0.06), radius: 8, x: 0, y: 3)
        .animation(.easeInOut(duration: 0.3), value: isVisible)
    }
    
    // MARK: - Browse Programs Widget (Fallback)
    
    /// Get any program to suggest (broader than topRecommendedSmartProgram)
    private var anyRecommendableProgram: PersonalizedProgram? {
        personalizedPrograms
            .filter { $0.isUnlocked }
            .sorted { $0.matchPercentage > $1.matchPercentage }
            .first
    }
    
    private var browseProgramsWidget: some View {
        let suggestedProgram = anyRecommendableProgram
        let template = suggestedProgram?.template
        let programColor = template?.category.color ?? .blue
        let totalWeeks = ((template?.totalDays ?? 28) + 6) / 7
        
        return VStack(spacing: 0) {
            // Header - Tap to view all programs (matches active program header style)
            Button {
                workoutManager.shouldNavigateToPrograms = true
            } label: {
                HStack(alignment: .center, spacing: 10) {
                    // Category icon in accent circle
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [programColor.opacity(0.2), programColor.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: template?.category.icon ?? "dumbbell.fill")
                            .font(.ds_heading3)
                            .foregroundColor(programColor)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your Programs")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        Text("Find your next challenge")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, Spacing.sm)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Inner card - Recommended program or explore prompt
            if let program = suggestedProgram, let tmpl = template {
                Button {
                    if let user = userManager.currentUser {
                        if let startedProgram = SmartProgramEngine.shared.startProgram(templateId: tmpl.id, for: user) {
                            if let firstDay = startedProgram.generatedDays.first {
                                workoutManager.navigateProgramData = startedProgram
                                workoutManager.navigateProgramDay = firstDay
                                workoutManager.shouldNavigateToProgramDay = true
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 0) {
                        // Left accent bar
                        RoundedRectangle(cornerRadius: 2)
                            .fill(programColor)
                            .frame(width: 4)
                            .padding(.vertical, 4)
                        
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(tmpl.baseName)
                                        .font(.subheadline)
                                        .fontWeight(.bold)
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    
                                    // Match badge
                                    Text("\(program.matchPercentage)% match")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(
                                            Capsule()
                                                .fill(programColor.opacity(0.85))
                                        )
                                }
                                
                                HStack(spacing: 4) {
                                    Text("\(totalWeeks) weeks")
                                    Text("•")
                                        .font(.caption2)
                                    Text("\(tmpl.daysPerWeek) days/wk")
                                    Text("•")
                                        .font(.caption2)
                                    Text("\(tmpl.estimatedMinutesPerDay) min")
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                            .padding(.leading, 10)
                            
                            Spacer()
                            
                            // Start button
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
                                            colors: [programColor, programColor.opacity(0.8)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                            )
                        }
                    }
                    .padding(Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(colorScheme == .dark ? Color.cardBackground : Color(white: 0.96))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(programColor.opacity(0.2), lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, Spacing.sm)
                    .padding(.bottom, 12)
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                // No specific program to suggest - show explore prompt
                Button {
                    workoutManager.shouldNavigateToPrograms = true
                } label: {
                    HStack(spacing: 0) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(programColor)
                            .frame(width: 4)
                            .padding(.vertical, 4)
                        
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
            Text("Explore Programs")
                                    .font(.subheadline)
                .fontWeight(.bold)
                                    .foregroundColor(.primary)
            
                                Text("10+ programs tailored to your goals")
                .font(.caption)
                .foregroundColor(.secondary)
                            }
                            .padding(.leading, 10)
                            
                            Spacer()
                            
                            HStack(spacing: 4) {
                                Text("Browse")
                    .font(.subheadline)
                                    .fontWeight(.bold)
                                Image(systemName: "arrow.right")
                                    .font(.ds_caption)
                            }
                    .foregroundColor(.white)
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, 10)
                    .background(
                        Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [programColor, programColor.opacity(0.8)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                            )
                        }
                    }
                    .padding(Spacing.sm)
        .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(colorScheme == .dark ? Color.cardBackground : Color(white: 0.96))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(programColor.opacity(0.2), lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, Spacing.sm)
                    .padding(.bottom, 12)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .background(
            ZStack {
                // Main card background with gradient
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
                
                // Subtle accent border
                RoundedRectangle(cornerRadius: CornerRadius.xl)
                    .stroke(
                        LinearGradient(
                            colors: [programColor.opacity(0.25), programColor.opacity(0.1), Color.clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        // Matching shadows from active/recommended program widgets
        .shadow(color: programColor.opacity(colorScheme == .dark ? 0.15 : 0.1), radius: 12, x: 0, y: 6)
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.2 : 0.06), radius: 8, x: 0, y: 3)
    }
    
    // MARK: - Program Recommendations Widget (Legacy - kept for scrolling list)
    
    private var smartProgramRecommendationsWidget: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Your Programs")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Spacer()
                
                NavigationLink(value: DashboardRoute.generatedProgramsList) {
                    Text("View All")
                        .font(.subheadline)
                        .foregroundStyle(.blue)
                }
            }
            
            // Show top 2 program recommendations
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(generatedProgramService.generatedPrograms.prefix(3)) { program in
                        SmartProgramMiniCard(
                            program: program,
                            onStart: {
                                generatedProgramService.startProgram(program)
                            }
                        )
                        .frame(width: 260)
                    }
                }
            }
        }
        .padding(Spacing.md)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark 
                                ? [Color(white: 0.18), Color.cardBackground]
                                : [Color.white, Color.white.opacity(0.95)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                RoundedRectangle(cornerRadius: 20)
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
            }
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 12, x: 0, y: 6)
    }
    
    // MARK: - Smart Programs Widget (context-aware)
    
    private var activeSmartProgram: SmartActiveProgram? {
        smartProgramEngine.userPrograms
            .filter { !$0.isCompleted }
            .sorted { $0.startDate > $1.startDate }  // Most recent first
            .first
    }
    
    private var generateProgramsWidget: some View {
        Group {
            if let activeProgram = activeSmartProgram {
                // Show active program status
                activeProgramWidget(activeProgram)
            } else {
                // Show browse programs card
                browseProgramsCard
            }
        }
    }
    
    // MARK: - Active Program Widget
    
    @State private var navigateToProgramDay = false
    
    private func activeProgramWidget(_ program: SmartActiveProgram) -> some View {
        let template = smartProgramEngine.getPersonalizedPrograms(for: userManager.currentUser)
            .first { $0.template.id == program.templateId }?.template
        let currentDay = program.generatedDays.first { $0.dayNumber == program.currentDay }
        let isTodayCompleted = currentDay?.isCompleted ?? false
        let nextDay = program.generatedDays.first { $0.dayNumber == program.currentDay + 1 }
        let completedDays = program.completedDays.count
        let totalDays = template?.totalDays ?? 1
        let progressPercent = Double(completedDays) / Double(totalDays)
        let programColor: Color = .green
        let currentWeek = (program.currentDay - 1) / 7 + 1
        let totalWeeks = (totalDays + 6) / 7
        
        return VStack(spacing: 0) {
            // Streamlined Header
            VStack(spacing: 10) {
                // Top row: Icon, Name, and Menu
                HStack(alignment: .center, spacing: 12) {
                    // Gradient icon
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [programColor, programColor.opacity(0.7)]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 48, height: 48)
                            .shadow(color: programColor.opacity(0.3), radius: 6, x: 0, y: 3)
                        
                        Image(systemName: "figure.strengthtraining.traditional")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                    }
                    
                    // Program info
                    VStack(alignment: .leading, spacing: 3) {
                        Text(program.personalizedName)
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        HStack(spacing: 8) {
                            // Week and progress combined
                            Text("Week \(currentWeek)/\(totalWeeks)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text("•")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            Text("\(completedDays)/\(totalDays) days")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(programColor)
                        }
                    }
                    
                    Spacer()
                    
                    // View all button
                    NavigationLink(value: DashboardRoute.smartProgramOverview(programId: program.id)) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                }
                
                // Compact progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background
                        Capsule()
                            .fill(Color.gray.opacity(0.12))
                            .frame(height: 8)
                        
                        // Progress fill
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [programColor, programColor.opacity(0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * progressPercent, height: 8)
                        
                        // Percentage overlay
                        HStack {
                            Spacer()
                            Text("\(Int(progressPercent * 100))%")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(progressPercent > 0.15 ? .white : programColor)
                                .padding(.trailing, 6)
                        }
                    }
                }
                .frame(height: 8)
            }
            .padding(14)
            
            // Today's workout - COMPACT
            if let day = currentDay {
                if !isTodayCompleted && !day.exercises.isEmpty {
                    NavigationLink(value: DashboardRoute.smartProgramDayPreview(programId: program.id, dayNumber: day.dayNumber)) {
                        HStack(spacing: 12) {
                            // Left: Workout info
                            VStack(alignment: .leading, spacing: 3) {
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
                                                .fill(programColor.opacity(0.12))
                                        )
                                }
                                
                                HStack(spacing: 6) {
                                    Label("\(day.exercises.count)", systemImage: "dumbbell.fill")
                                    Label("~\(day.targetDuration)min", systemImage: "clock")
                                    
                                    // Muscle targets
                                    let muscleTargets = getMuscleTargets(for: day.exercises)
                                    if !muscleTargets.isEmpty {
                                        Text("•")
                                            .font(.caption2)
                                        Text(muscleTargets)
                                            .lineLimit(1)
                                    }
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            // Right: Start button
                            HStack(spacing: 4) {
                                Image(systemName: "play.fill")
                                    .font(.ds_caption)
                                Text("Start")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                LinearGradient(
                                    colors: [programColor, programColor.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(Capsule())
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, Spacing.sm)
                    }
                    .buttonStyle(PlainButtonStyle())
                } else if isTodayCompleted {
                    // Today completed view - more compact
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.green)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Great work!")
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                            
                            if let next = nextDay {
                                Text("Tomorrow: \(next.name)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                    }
                    .padding(Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.green.opacity(0.12))
                    )
                    .padding(.horizontal, 14)
                } else if day.exercises.isEmpty {
                    // Rest day - more compact
                    HStack(spacing: 10) {
                        Image(systemName: "moon.zzz.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Rest Day")
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                            
                            Text("Recovery is important!")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding(Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.blue.opacity(0.12))
                    )
                    .padding(.horizontal, 14)
                }
            }
        }
        .background(
            ZStack {
                // Base gradient
                RoundedRectangle(cornerRadius: CornerRadius.xl)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark 
                                ? [Color(white: 0.18), Color.cardBackground]
                                : [Color.white, Color.white.opacity(0.95)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                // Inner glow
                RoundedRectangle(cornerRadius: CornerRadius.xl)
                    .stroke(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color.white.opacity(0.12), Color.white.opacity(0.02), Color.clear]
                                : [Color.white, Color.white.opacity(0.5), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1.5
                    )
                
                // Accent border
                RoundedRectangle(cornerRadius: CornerRadius.xl)
                    .stroke(
                        LinearGradient(
                            colors: [programColor.opacity(0.3), programColor.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
            }
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.08), radius: 16, x: 0, y: 8)
        // Subtle glow effect to draw attention
        .shadow(color: programColor.opacity(colorScheme == .dark ? 0.3 : 0.2), radius: 16, x: 0, y: 0)
        .shadow(color: programColor.opacity(colorScheme == .dark ? 0.2 : 0.15), radius: 24, x: 0, y: 0)
    }
    
    // MARK: - Helper: Extract Muscle Targets from Exercises
    
    private func getMuscleTargets(for exercises: [SmartProgramExercise]) -> String {
        let exerciseLibrary = ExerciseLibraryService.shared
        var muscleGroups: [String: Int] = [:]
        
        for exercise in exercises {
            // Try to find the exercise in the library
            if let libraryExercise = exerciseLibrary.getExercise(byName: exercise.exerciseName) {
                if let muscles = libraryExercise.muscleGroups as? [String], let primary = muscles.first {
                    muscleGroups[primary, default: 0] += 1
                }
            } else {
                // Fallback: extract from exercise name
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
        
        // Sort by count and take top 2-3
        let sorted = muscleGroups.sorted { $0.value > $1.value }
        let topMuscles = sorted.prefix(3).map { $0.key }
        
        return topMuscles.joined(separator: ", ")
    }
    
    // MARK: - Your Perfect Program Widget (no active program)
    
    private var topRecommendedProgram: PersonalizedProgram? {
        smartProgramEngine.getPersonalizedPrograms(for: userManager.currentUser)
            .filter { !$0.isCompleted && $0.isUnlocked }
            .first
    }
    
    private var browseProgramsCard: some View {
        Group {
            if let recommended = topRecommendedProgram {
                perfectProgramWidget(program: recommended)
            } else {
                fallbackProgramsCard
            }
        }
    }
    
    @State private var showStartProgramConfirm = false
    @State private var programToStart: PersonalizedProgram?
    @State private var programGlowRotation: Double = 0
    
    private func perfectProgramWidget(program: PersonalizedProgram) -> some View {
        let template = program.template
        let matchPercent = program.matchPercentage
        let accentColor = Color.green
        let totalWeeks = (template.totalDays + 6) / 7
        
        return NavigationLink(value: DashboardRoute.personalizedPrograms) {
            HStack(spacing: 14) {
                // Program icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [accentColor, Color.mint],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.ds_heading2)
                        .foregroundColor(.white)
                }
                .shadow(color: accentColor.opacity(0.3), radius: 6, x: 0, y: 3)
                
                // Program info
                VStack(alignment: .leading, spacing: 5) {
                    Text(program.personalizedName)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    HStack(spacing: 8) {
                        Text("\(totalWeeks)wk • \(template.daysPerWeek)x/wk")
                        Text("•")
                        Text("\(matchPercent)% match")
                            .foregroundColor(accentColor)
                    }
                    .font(.ds_labelSmall)
                    .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Compact start button
                Button {
                    HapticManager.impact(.medium)
                    programToStart = program
                    showStartProgramConfirm = true
                } label: {
                    Text("Start")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.xs)
                        .background(
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [accentColor, Color.mint],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(Spacing.md)
            .background(
                ZStack {
                    // Animated glow border - more evenly distributed
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(
                            AngularGradient(
                                gradient: Gradient(colors: [
                                    accentColor.opacity(0.5),
                                    Color.mint.opacity(0.4),
                                    accentColor.opacity(0.5),
                                    Color.mint.opacity(0.4),
                                    accentColor.opacity(0.5),
                                    Color.mint.opacity(0.4),
                                    accentColor.opacity(0.5),
                                    Color.mint.opacity(0.4)
                                ]),
                                center: .center,
                                startAngle: .degrees(programGlowRotation),
                                endAngle: .degrees(programGlowRotation + 360)
                            ),
                            lineWidth: 3
                        )
                        .blur(radius: 6)

                    // Main background
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: cardBackgroundGradient,
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    // Inner border - more evenly distributed
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(
                            AngularGradient(
                                gradient: Gradient(colors: [
                                    accentColor.opacity(0.4),
                                    Color.mint.opacity(0.3),
                                    accentColor.opacity(0.4),
                                    Color.mint.opacity(0.3),
                                    accentColor.opacity(0.4),
                                    Color.mint.opacity(0.3),
                                    accentColor.opacity(0.4),
                                    Color.mint.opacity(0.3)
                                ]),
                                center: .center,
                                startAngle: .degrees(programGlowRotation),
                                endAngle: .degrees(programGlowRotation + 360)
                            ),
                            lineWidth: 1.5
                        )
                }
            )
            .shadow(color: accentColor.opacity(colorScheme == .dark ? 0.3 : 0.2), radius: 12, x: 0, y: 0) // Even glow
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.08), radius: 8, x: 0, y: 3) // Subtle depth
        }
        .buttonStyle(PlainButtonStyle())
        .confirmationDialog("Start \(program.personalizedName)?", isPresented: $showStartProgramConfirm, titleVisibility: .visible) {
            Button("Start Program") {
                if let toStart = programToStart,
                   let user = userManager.currentUser {
                    if let startedProgram = SmartProgramEngine.shared.startProgram(templateId: toStart.template.id, for: user) {
                        // Navigate to the first day of the program
                        if let firstDay = startedProgram.generatedDays.first {
                            workoutManager.navigateProgramData = startedProgram
                            workoutManager.navigateProgramDay = firstDay
                            workoutManager.shouldNavigateToProgramDay = true
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This \(totalWeeks)-week program is \(matchPercent)% matched to your goals and equipment.")
        }
    }
    
    // Fallback card if no programs available
    private var fallbackProgramsCard: some View {
        NavigationLink(value: DashboardRoute.personalizedPrograms) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.green, Color.mint]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 50, height: 50)
                        .shadow(color: .green.opacity(0.4), radius: 8, x: 0, y: 4)
                    
                    Image(systemName: "star.fill")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                }
                
                VStack(spacing: 4) {
                    Text("Training Programs")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text("10 personalized plans")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 120)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: cardBackgroundGradient,
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.green.opacity(0.4), lineWidth: 1.5)
            )
            .shadow(color: .green.opacity(0.2), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Helper Functions
    
    private func colorFromProgramType(_ type: DynamicProgramGenerator.GeneratedProgram.ProgramType) -> Color {
        switch type {
        case .hypertrophy: return .blue
        case .strength: return .red
        case .fatLoss: return .orange
        case .toning: return .purple
        case .generalFitness: return .green
        case .powerbuilding: return .yellow
        }
    }
    
}

// MARK: - Dashboard Navigation Destinations (extracted to help type checker)

private struct DashboardNavigationDestinations: ViewModifier {
    @ObservedObject var userManager: UserManager
    @ObservedObject var workoutManager: WorkoutManager
    @ObservedObject var generatedProgramService: GeneratedProgramService
    @ObservedObject var smartProgramEngine: SmartProgramEngine
    
    func body(content: Content) -> some View {
        content
            .navigationDestination(for: DashboardRoute.self) { route in
                dashboardRouteDestination(route)
            }
            .navigationDestination(for: ActiveChallenge.self) { challenge in
                ChallengeDetailView(challenge: challenge)
            }
            .navigationDestination(for: ActiveGroupChallenge.self) { challenge in
                GroupChallengeDetailView(challenge: challenge)
                    .environmentObject(userManager)
            }
            .navigationDestination(for: Workout.self) { workout in
                WorkoutHistoryDetailView(workout: workout)
            }
            .navigationDestination(for: CardioWorkoutDTO.self) { cardioWorkout in
                CardioWorkoutDetailView(cardioWorkout: cardioWorkout)
            }
    }
    
    @ViewBuilder
    private func dashboardRouteDestination(_ route: DashboardRoute) -> some View {
        switch route {
        case .profile:
            ProfileView()
        case .mealPlan:
            SimpleMealPlanView()
        case .workoutHistory:
            WorkoutHistoryFullView()
        case .programDetailsPlaceholder:
            Text("Program Details - Coming Soon")
        case .generatedProgramsList:
            GeneratedProgramsListView()
        case .personalizedPrograms:
            PersonalizedProgramsView()
                .environmentObject(userManager)
        case .smartWorkoutPreview:
            if let program = generatedProgramService.activeProgram,
               let day = generatedProgramService.currentDay {
                SmartWorkoutPreviewView(day: day, program: program)
                    .environmentObject(generatedProgramService)
            }
        case .smartProgramOverview(let programId):
            if let program = smartProgramEngine.userPrograms.first(where: { $0.id == programId }) {
                let template = smartProgramEngine.getPersonalizedPrograms(for: userManager.currentUser)
                    .first(where: { $0.template.id == program.templateId })?.template
                SmartProgramOverviewView(program: program, template: template)
                    .environmentObject(workoutManager)
                    .environmentObject(userManager)
            }
        case .smartProgramDayPreview(let programId, let dayNumber):
            if let program = smartProgramEngine.userPrograms.first(where: { $0.id == programId }),
               let day = program.generatedDays.first(where: { $0.dayNumber == dayNumber }) {
                let template = smartProgramEngine.getPersonalizedPrograms(for: userManager.currentUser)
                    .first(where: { $0.template.id == program.templateId })?.template
                let totalDays = template?.totalDays ?? program.generatedDays.count
                SmartProgramDayPreviewView(
                    program: program,
                    day: day,
                    programName: program.personalizedName,
                    totalDays: totalDays
                )
                .environmentObject(workoutManager)
                .environmentObject(userManager)
            }
        }
    }
}

// MARK: - Smart Program Mini Card

struct SmartProgramMiniCard: View {
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
            // Header
            HStack(spacing: 8) {
                Image(systemName: program.icon)
                    .font(.system(size: 16, weight: .bold))
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
                
                Spacer()
            }
            
            // Name
            Text(program.name)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .lineLimit(1)
            
            // Stats
            HStack(spacing: 8) {
                Label("\(program.daysPerWeek)/wk", systemImage: "calendar")
                Label("\(program.durationWeeks)wks", systemImage: "clock")
            }
            .font(.caption2)
            .foregroundColor(.secondary)
            
            Spacer()
            
            // Start button
            Button(action: {
                HapticManager.impact(.medium)
                onStart()
            }) {
                Text("Start")
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
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))
            }
        }
        .padding(Spacing.sm)
        .frame(height: 140)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(
                    colorScheme == .dark
                        ? Color(white: 0.15)
                        : Color(white: 0.96)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(programColor.opacity(0.3), lineWidth: 1)
        )
    }
}

struct RecentWorkoutCard: View {
    let workout: Workout
    var isMostRecent: Bool = false // Whether this is the most recent workout (gets special outline)
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.managedObjectContext) private var viewContext
    
    // Local state for immediate UI feedback (prevents lag)
    @State private var isFavorite: Bool = false
    @State private var isProcessing: Bool = false
    
    // Get exercises from workout
    private var workoutExercises: [WorkoutExercise] {
        let exercises = workout.exercises?.allObjects as? [WorkoutExercise] ?? []
        return exercises.sorted { ($0.order) < ($1.order) }
    }
    
    // Smart workout name based on muscle groups
    private var smartWorkoutName: String {
        // First check if it's a program day name (not generic)
        if let name = workout.name, !name.isEmpty {
            let cleanName = cleanWorkoutName(name)
            // If it's a meaningful program name (not just "Workout" or generic)
            if !cleanName.lowercased().contains("workout") || cleanName.count > 15 {
                return cleanName
            }
        }
        
        // Otherwise, generate smart name from muscle groups
        return generateMuscleBasedName()
    }
    
    private func generateMuscleBasedName() -> String {
        var muscleCount: [String: Int] = [:]
        
        for workoutExercise in workoutExercises {
            // Use safeMuscleGroups to handle nil exercise relationships
            for muscle in workoutExercise.safeMuscleGroups {
                muscleCount[muscle.lowercased(), default: 0] += 1
            }
        }
        
        // Sort by count
        let sortedMuscles = muscleCount.sorted { $0.value > $1.value }
        let timeOfDay = getTimeOfDay(for: workout.date ?? Date())
        
        if sortedMuscles.isEmpty {
            return "\(timeOfDay) Workout"
        }
        
        // Check if one muscle dominates (>50% of exercises)
        let total = sortedMuscles.reduce(0) { $0 + $1.value }
        if let topMuscle = sortedMuscles.first, total > 0, Double(topMuscle.value) / Double(total) > 0.5 {
            return "\(timeOfDay) \(topMuscle.key.capitalized)"
        }
        
        // Otherwise, combine top 2 muscles
        if sortedMuscles.count >= 2 {
            return "\(sortedMuscles[0].key.capitalized) & \(sortedMuscles[1].key.capitalized)"
        }
        
        return "\(timeOfDay) \(sortedMuscles[0].key.capitalized)"
    }
    
    private func getTimeOfDay(for date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        if hour >= 5 && hour < 12 {
            return "Morning"
        } else if hour >= 12 && hour < 17 {
            return "Afternoon"
        } else {
            return "Evening"
        }
    }
    
    private var workoutGradient: [Color] {
        // Color based on primary muscle group (use safeMuscleGroups for nil-safety)
        let muscles = workoutExercises.compactMap { $0.safeMuscleGroups.first?.lowercased() }
        let primaryMuscle = muscles.first ?? ""
        
        switch primaryMuscle {
        case "chest": return [.red, .orange]
        case "back": return [.blue, .cyan]
        case "legs", "quads", "hamstrings", "glutes": return [.green, .teal]
        case "shoulders": return [.orange, .yellow]
        case "biceps", "triceps", "arms": return [.purple, .pink]
        case "core", "abs": return [.yellow, .orange]
        default:
            // Fallback to time-based
            let hour = Calendar.current.component(.hour, from: workout.date ?? Date())
            if hour >= 5 && hour < 12 {
                return [.orange, .yellow]
            } else if hour >= 12 && hour < 17 {
                return [.blue, .cyan]
            } else {
                return [.purple, .pink]
            }
        }
    }
    
    // Exercise count
    private var exerciseCount: Int {
        workoutExercises.count
    }
    
    // Total sets completed
    private var totalSets: Int {
        workoutExercises.reduce(0) { total, workoutExercise in
            let sets = workoutExercise.sets?.allObjects as? [WorkoutSet] ?? []
            return total + sets.filter { $0.isCompleted }.count
        }
    }
    
    // Total volume
    private var totalVolume: Double {
        workoutExercises.reduce(0.0) { total, workoutExercise in
            let sets = workoutExercise.sets?.allObjects as? [WorkoutSet] ?? []
            return total + sets.filter { $0.isCompleted }.reduce(0.0) { $0 + ($1.weight * Double($1.reps)) }
        }
    }
    
    // Top muscles worked (for preview)
    private var topMuscles: [String] {
        var muscleCount: [String: Int] = [:]
        for workoutExercise in workoutExercises {
            // Use safeMuscleGroups for nil-safety
            for muscle in workoutExercise.safeMuscleGroups {
                muscleCount[muscle.capitalized, default: 0] += 1
            }
        }
        return muscleCount.sorted { $0.value > $1.value }.prefix(2).map { $0.key }
    }
    
    // Toggle favorite status with debounce protection
    private func toggleFavorite() {
        // Prevent rapid double-taps
        guard !isProcessing else { return }
        isProcessing = true
        
        // Immediate UI feedback
        isFavorite.toggle()
        
        // Haptic feedback immediately
        HapticManager.impact(.light)
        
        // Update Core Data
        workout.isFavorite = isFavorite
        
        do {
            try viewContext.save()
            
            // Log the action
            SessionLogManager.shared.log(.info, category: .userAction, message: isFavorite ? "⭐ Workout favorited" : "☆ Workout unfavorited", metadata: [
                "workout_id": workout.objectID.uriRepresentation().absoluteString,
                "workout_name": smartWorkoutName
            ])
        } catch {
            print("❌ Error saving favorite status: \(error)")
            // Revert on error
            isFavorite.toggle()
        }
        
        // Allow next tap after short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isProcessing = false
        }
    }
    
    var body: some View {
        NavigationLink(value: workout) {
            VStack(alignment: .leading, spacing: 0) {
                // Top section - Title and Date
                HStack(alignment: .top, spacing: 12) {
                    // Hollow transparent icon with gradient ring and checkmark
                    ZStack {
                        // Hollow circle with gradient stroke - fully transparent inside
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: workoutGradient,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2.5
                            )
                            .frame(width: 52, height: 52)
                        
                        // Gradient checkmark floating inside
                        Image(systemName: "checkmark")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: workoutGradient,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        // Smart workout name
                        Text(smartWorkoutName)
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        // Date with relative time
                        Text(formatSmartDate(workout.date ?? Date()))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // Favorite star button - uses local state for instant feedback
                    Button(action: {
                        toggleFavorite()
                    }) {
                        Image(systemName: isFavorite ? "star.fill" : "star")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(isFavorite ? .yellow : .gray.opacity(0.4))
                            .animation(.easeInOut(duration: 0.15), value: isFavorite)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(isProcessing)
                    .padding(.trailing, 8)
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.5))
                }
                
                Divider()
                    .padding(.vertical, Spacing.sm)
                
                // Bottom section - Stats
                HStack(spacing: 0) {
                    // Duration
                    VStack(spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 12))
                                .foregroundColor(workoutGradient[0])
                            Text(formatDuration(workout.duration))
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                        }
                        Text("Duration")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 1, height: 35)
                    
                    // Exercises
                    VStack(spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "figure.strengthtraining.traditional")
                                .font(.system(size: 12))
                                .foregroundColor(workoutGradient[0])
                            Text("\(exerciseCount)")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                        }
                        Text("Exercises")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 1, height: 35)
                    
                    // Sets
                    VStack(spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "repeat")
                                .font(.system(size: 12))
                                .foregroundColor(workoutGradient[0])
                            Text("\(totalSets)")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                        }
                        Text("Sets")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 1, height: 35)
                    
                    // XP
                    VStack(spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.orange)
                            Text("+\(Int(workout.xpEarned))")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                        }
                        Text("XP")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                
                // Muscle tags (if available)
                if !topMuscles.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(topMuscles, id: \.self) { muscle in
                            Text(muscle)
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundColor(workoutGradient[0])
                                .padding(.horizontal, Spacing.xs)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(workoutGradient[0].opacity(0.12))
                                )
                        }
                        Spacer()
                    }
                    .padding(.top, 12)
                }
            }
            .padding(Spacing.md)
            .background(
                // Premium layered background for workout cards
                ZStack {
                    // Bottom shadow layer (deepest) - color glow ONLY for most recent
                    if isMostRecent {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(workoutGradient[0].opacity(colorScheme == .dark ? 0.15 : 0.08))
                            .offset(y: 6)
                            .blur(radius: 4)
                    }
                    
                    // Middle shadow layer
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                        .offset(y: 3)
                    
                    // Main card background with gradient
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: colorScheme == .dark
                                    ? [Color(white: 0.18), Color.cardBackground]
                                    : [Color.white, Color.white.opacity(0.95)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    
                    // Inner highlight (top edge glow)
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
                    
                    // Colored accent border - stronger for most recent, subtle for others
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: isMostRecent
                                    ? [workoutGradient[0].opacity(colorScheme == .dark ? 0.4 : 0.3), workoutGradient[1].opacity(colorScheme == .dark ? 0.3 : 0.2)]
                                    : [Color.gray.opacity(colorScheme == .dark ? 0.2 : 0.1), Color.gray.opacity(colorScheme == .dark ? 0.1 : 0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            )
            // Shadow effects - color glow only for most recent
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 12, x: 0, y: 6)
            .shadow(color: isMostRecent ? workoutGradient[0].opacity(colorScheme == .dark ? 0.2 : 0.12) : Color.clear, radius: 20, x: 0, y: 10)
        }
        .buttonStyle(PlainButtonStyle())
        .overlay(alignment: .topTrailing) {
            reactionStickerOverlay
        }
        .onAppear {
            // Initialize local state from Core Data
            isFavorite = workout.isFavorite
        }
        .onChange(of: workout.isFavorite) { _, newValue in
            // Sync if changed externally (e.g., from detail view)
            if isFavorite != newValue {
                isFavorite = newValue
            }
        }
    }
    
    /// Reaction sticker: shows when a friend sent an emoji on this workout
    @ViewBuilder
    private var reactionStickerOverlay: some View {
        let workoutIdStr = workout.objectID.uriRepresentation().lastPathComponent
        let matchingReactions = ActivityFeedService.shared.myReactions.filter { $0.workoutId == workoutIdStr }
        
        if let reaction = matchingReactions.first {
            HStack(spacing: 3) {
                Text(reaction.emoji)
                    .font(.system(size: 16))
                Text("\(reaction.senderFirstName) sent you \(reaction.emoji)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .shadow(color: .orange.opacity(0.3), radius: 6, x: 0, y: 2)
            )
            .overlay(
                Capsule()
                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
            )
            .rotationEffect(.degrees(-3))
            .offset(x: -8, y: -6)
        }
    }
    
    private func formatSmartDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        
        if calendar.isDateInToday(date) {
            return "Today · \(formatTime(date))"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday · \(formatTime(date))"
        } else if let daysAgo = calendar.dateComponents([.day], from: date, to: now).day, daysAgo < 7 {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE" // Day name
            return "\(formatter.string(from: date)) · \(formatTime(date))"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return "\(formatter.string(from: date)) · \(formatTime(date))"
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
    
    private func getDayName(for date: Date) -> String {
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEEE" // Full day name
        return dayFormatter.string(from: date)
    }
    
    private func getWorkoutType(for date: Date) -> String {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        
        // Determine time of day
        let timeOfDay: String
        if hour >= 5 && hour < 12 {
            timeOfDay = "Morning"
        } else if hour >= 12 && hour < 17 {
            timeOfDay = "Afternoon"
        } else {
            timeOfDay = "Evening"
        }
        
        return "\(timeOfDay) workout"
    }
    
    private func generateSmartWorkoutTitle(for date: Date) -> String {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        
        // Get day name
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEEE" // Full day name
        let dayName = dayFormatter.string(from: date)
        
        // Determine time of day
        let timeOfDay: String
        if hour >= 5 && hour < 12 {
            timeOfDay = "Morning"
        } else if hour >= 12 && hour < 17 {
            timeOfDay = "Afternoon"
        } else {
            timeOfDay = "Evening"
        }
        
        // Create smart title
        return "\(dayName) \(timeOfDay) Workout"
    }
    
    private func formatCompactDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
    
    private func cleanWorkoutName(_ name: String) -> String {
        // Remove any date suffixes like " - Nov 22" or " - Nov"
        var cleanName = name
        
        // Pattern to match " - Month" or " - Month Day" at the end
        let patterns = [
            " - [A-Z][a-z]+ \\d+$",  // Matches " - Nov 22"
            " - [A-Z][a-z]+$",       // Matches " - Nov"
            " - \\d{1,2}/\\d{1,2}$", // Matches " - 11/22"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(cleanName.startIndex..., in: cleanName)
                cleanName = regex.stringByReplacingMatches(in: cleanName, range: range, withTemplate: "")
            }
        }
        
        return cleanName.trimmingCharacters(in: .whitespaces)
    }
    
    private func formatFullDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        
        // Add ordinal suffix
        let day = Calendar.current.component(.day, from: date)
        let ordinalFormatter = NumberFormatter()
        ordinalFormatter.numberStyle = .ordinal
        let ordinalDay = ordinalFormatter.string(from: NSNumber(value: day)) ?? "\(day)"
        
        formatter.dateFormat = "MMMM"
        let month = formatter.string(from: date)
        let year = Calendar.current.component(.year, from: date)
        
        return "\(month) \(ordinalDay), \(year)"
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    private func formatDuration(_ duration: Int32) -> String {
        let minutes = duration / 60
        if minutes < 60 {
            return "\(minutes)m"
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return "\(hours)h \(remainingMinutes)m"
        }
    }
}

// MARK: - Recent Cardio Workout Card
struct RecentCardioWorkoutCard: View {
    let cardioWorkout: CardioWorkoutDTO
    var isMostRecent: Bool = false
    @Environment(\.colorScheme) private var colorScheme
    
    // Parse completed date (uses centralized cached formatters)
    private var completedDate: Date {
        return ISO8601Parser.parse(cardioWorkout.completedAt, fallback: Date())
    }
    
    // Activity type display name and icon
    private var activityInfo: (name: String, icon: String, color: Color) {
        let type = cardioWorkout.activityType.lowercased().replacingOccurrences(of: "_", with: " ")
        switch type {
        case "outdoor run", "run":
            return ("Outdoor Run", "figure.run", .green)
        case "treadmill":
            return ("Treadmill", "figure.walk.motion", .orange)
        case "walk":
            return ("Walk", "figure.walk", .blue)
        case "indoor cycle", "indoor_cycle":
            return ("Indoor Cycle", "bicycle", .cyan)
        case "outdoor cycle", "outdoor_cycle":
            return ("Outdoor Cycle", "bicycle", .green)
        case "rowing":
            return ("Rowing", "figure.rower", .blue)
        case "elliptical":
            return ("Elliptical", "figure.elliptical", .purple)
        case "stair climber", "stair_climber":
            return ("Stair Climber", "figure.stairs", .orange)
        case "hiit":
            return ("HIIT", "flame.fill", .red)
        case "swimming":
            return ("Swimming", "figure.pool.swim", .cyan)
        default:
            return (type.capitalized, "figure.run", .green)
        }
    }
    
    // Format duration
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
    
    // Format distance
    private func formatDistance(_ meters: Double) -> String {
        let km = meters / 1000
        if km < 1 {
            return String(format: "%.0fm", meters)
        } else {
            return String(format: "%.2fkm", km)
        }
    }
    
    // Format pace
    private func formatPace(_ pace: Double?) -> String {
        guard let pace = pace, pace > 0 else { return "--" }
        let minutes = Int(pace)
        let seconds = Int((pace - Double(minutes)) * 60)
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var body: some View {
        NavigationLink(value: cardioWorkout) {
            VStack(alignment: .leading, spacing: 0) {
                // Top section - Title and Date
                HStack(alignment: .top, spacing: 12) {
                    // Activity icon with gradient ring
                    ZStack {
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [activityInfo.color, activityInfo.color.opacity(0.6)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2.5
                            )
                            .frame(width: 52, height: 52)
                        
                        Image(systemName: activityInfo.icon)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [activityInfo.color, activityInfo.color.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        // Activity name with source badge (Strava or Cardio)
                        HStack(spacing: 8) {
                            Text(cardioWorkout.isFromStrava ? (cardioWorkout.workoutName ?? activityInfo.name) : activityInfo.name)
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            
                            // Source badge - Strava (orange) or Cardio (activity color)
                            if cardioWorkout.isFromStrava {
                                HStack(spacing: 3) {
                                    Image(systemName: "figure.run")
                                        .font(.system(size: 9, weight: .bold))
                                    Text("Strava")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [Color(red: 252/255, green: 76/255, blue: 2/255), Color(red: 252/255, green: 100/255, blue: 30/255)],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                )
                            } else {
                                Text("Cardio")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(activityInfo.color)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(
                                        Capsule()
                                            .fill(activityInfo.color.opacity(0.15))
                                    )
                            }
                        }
                        
                        // Date with relative time
                        Text(DateFormatUtils.formatSmartDate(completedDate))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // Goal achieved badge
                    if cardioWorkout.goalAchieved {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.green)
                            .padding(.trailing, 8)
                    }
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.5))
                    }
                
                    Divider()
                        .padding(.vertical, Spacing.sm)
                
                    // Bottom section - Cardio Stats
                    HStack(spacing: 0) {
                        // Duration
                        VStack(spacing: 4) {
                            HStack(spacing: 4) {
                                Image(systemName: "clock.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(activityInfo.color)
                                Text(formatDuration(cardioWorkout.durationSeconds))
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundColor(.primary)
                            }
                            Text("Duration")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 1, height: 35)
                        
                        // Distance
                        VStack(spacing: 4) {
                            HStack(spacing: 4) {
                                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(activityInfo.color)
                                Text(formatDistance(cardioWorkout.distanceMeters))
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundColor(.primary)
                            }
                            Text("Distance")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 1, height: 35)
                        
                        // Calories
                        VStack(spacing: 4) {
                            HStack(spacing: 4) {
                                Image(systemName: "flame.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.orange)
                                Text("\(Int(cardioWorkout.caloriesBurned))")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundColor(.primary)
                            }
                            Text("Calories")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 1, height: 35)
                        
                        // Pace
                        VStack(spacing: 4) {
                            HStack(spacing: 4) {
                                Image(systemName: "speedometer")
                                    .font(.system(size: 12))
                                    .foregroundColor(.purple)
                                Text(formatPace(cardioWorkout.averagePace))
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundColor(.primary)
                            }
                            Text("/km")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                
                    // Heart rate tag (if available)
                    if let heartRate = cardioWorkout.averageHeartRate, heartRate > 0 {
                        HStack(spacing: 6) {
                            HStack(spacing: 4) {
                                Image(systemName: "heart.fill")
                                    .font(.ds_caption)
                                Text("\(heartRate) bpm")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(.red)
                            .padding(.horizontal, Spacing.xs)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.red.opacity(0.12))
                            )
                            
                            Spacer()
                        }
                        .padding(.top, 12)
                    }
                }
                .padding(Spacing.md)
                .background(
                    // Premium layered background for cardio workout cards
                    ZStack {
                        // Bottom shadow layer (deepest) - color glow ONLY for most recent
                        if isMostRecent {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(activityInfo.color.opacity(colorScheme == .dark ? 0.15 : 0.08))
                                .offset(y: 6)
                                .blur(radius: 4)
                        }
                        
                        // Middle shadow layer
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                            .offset(y: 3)
                        
                        // Main card background with gradient
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: colorScheme == .dark
                                        ? [Color(white: 0.18), Color.cardBackground]
                                        : [Color.white, Color.white.opacity(0.95)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        
                        // Inner highlight (top edge glow)
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
                        
                        // Colored accent border - stronger for most recent, subtle for others
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: isMostRecent
                                        ? [activityInfo.color.opacity(colorScheme == .dark ? 0.4 : 0.3), activityInfo.color.opacity(colorScheme == .dark ? 0.25 : 0.15)]
                                        : [Color.gray.opacity(colorScheme == .dark ? 0.2 : 0.1), Color.gray.opacity(colorScheme == .dark ? 0.1 : 0.05)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
                )
                // Shadow effects - color glow only for most recent
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 12, x: 0, y: 6)
                .shadow(color: isMostRecent ? activityInfo.color.opacity(colorScheme == .dark ? 0.2 : 0.12) : Color.clear, radius: 20, x: 0, y: 10)
            }
            .buttonStyle(PlainButtonStyle())
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            VStack(spacing: 4) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 100)
        .padding(.vertical, Spacing.md)
        .padding(.horizontal, Spacing.sm)
        .background(
            ZStack {
                // Card fill - lighter to pop from container
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color(white: 0.18), Color(white: 0.14)]
                                : [Color.white, Color.white.opacity(0.98)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                // Subtle top highlight
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color.white.opacity(0.12), Color.clear]
                                : [Color.white, Color.clear],
                            startPoint: .top,
                            endPoint: .center
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 8, x: 0, y: 4)
    }
}

enum WorkoutCreationType {
    case custom
    case generated
}

enum PendingWorkoutType {
    case custom
    case auto
}

// MARK: - Program Stat Pill Component
struct ProgramStatPill: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text(label)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, Spacing.xs)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))
    }
}

struct DashboardScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Workout History Full View (Full Page Navigation)
struct WorkoutHistoryFullView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.managedObjectContext) private var viewContext
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Workout.date, ascending: false)],
        predicate: NSPredicate(format: "isCompleted == true"),
        animation: .none)  // Disable animation for faster scroll
    private var allWorkouts: FetchedResults<Workout>
    
    @StateObject private var adManager = AdManager.shared
    
    // Group workouts by date
    private var groupedWorkouts: [(Date, [Workout])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: allWorkouts) { workout in
            calendar.startOfDay(for: workout.date ?? Date())
        }
        return grouped.sorted { $0.key > $1.key }
    }
    
    // Stats
    private var totalWorkouts: Int { allWorkouts.count }
    private var totalExercises: Int {
        allWorkouts.reduce(0) { $0 + (($1.exercises?.count) ?? 0) }
    }
    private var totalDuration: TimeInterval {
        allWorkouts.reduce(0.0) { $0 + Double($1.duration) }
    }
    
    var body: some View {
        ZStack {
            // Background
            AdaptiveGradient.home(for: colorScheme)
                .ignoresSafeArea()
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 24) {
                    // Stats summary
                    statsHeader
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    
                    // Workout list
                    if groupedWorkouts.isEmpty {
                        emptyStateView
                            .padding(.horizontal, 20)
                    } else {
                        LazyVStack(spacing: 20) {
                            ForEach(Array(groupedWorkouts.enumerated()), id: \.offset) { _, dayGroup in
                                WorkoutHistoryDaySectionWithAds(
                                    date: dayGroup.0,
                                    workouts: dayGroup.1,
                                    showAds: adManager.adsEnabled
                                )
                                .padding(.horizontal, 20)
                            }
                        }
                    }
                }
                .padding(.bottom, 100)
            }
        }
        .navigationTitle("Workout History")
        .navigationBarTitleDisplayMode(.large)
    }
    
    // MARK: - Stats Header
    private var statsHeader: some View {
        HStack(spacing: 12) {
            HistoryStatPill(icon: "flame.fill", value: "\(totalWorkouts)", label: "Workouts", color: .orange)
            HistoryStatPill(icon: "figure.strengthtraining.traditional", value: "\(totalExercises)", label: "Exercises", color: .blue)
            HistoryStatPill(icon: "clock.fill", value: formatTotalDuration(), label: "Total Time", color: .green)
        }
    }
    
    private func formatTotalDuration() -> String {
        let hours = Int(totalDuration) / 3600
        let minutes = (Int(totalDuration) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
    
    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(
                        LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 3
                    )
                    .frame(width: 80, height: 80)
                
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
            }
            
            VStack(spacing: 8) {
                Text("No Workouts Yet")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text("Complete your first workout to see it here!")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(40)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.1), radius: 12, x: 0, y: 6)
    }
}

// MARK: - History Stat Pill
struct HistoryStatPill: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(color)
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            }
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .fill(Color.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04), lineWidth: 1)
        )
    }
}

// MARK: - Workout History Day Section With Ads
struct WorkoutHistoryDaySectionWithAds: View {
    let date: Date
    let workouts: [Workout]
    let showAds: Bool
    @Environment(\.colorScheme) private var colorScheme
    
    private var displayDate: String {
        if Calendar.current.isDateInToday(date) {
            return "Today"
        } else if Calendar.current.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, MMMM d"
            return formatter.string(from: date)
        }
    }
    
    // Calculate total items including ads
    private var totalItemsWithAds: Int {
        guard showAds else { return workouts.count }
        let workoutCount = workouts.count
        let adCount = workoutCount / 2 // Ad after every 2 workouts
        return workoutCount + adCount
    }
    
    // Check if position should show an ad (positions 2, 5, 8...)
    private func isAdPosition(_ index: Int) -> Bool {
        guard showAds else { return false }
        return (index + 1) % 3 == 0
    }
    
    // Get the actual workout index accounting for ads
    private func getWorkoutIndex(for displayIndex: Int) -> Int {
        guard showAds else { return displayIndex }
        let adsBeforeThisIndex = displayIndex / 3
        return displayIndex - adsBeforeThisIndex
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Date header
            HStack {
                Text(displayDate)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("\(workouts.count) workout\(workouts.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.7))
            }
            .padding(.horizontal, 4)
            
            // Workout cards with ads inserted
            VStack(spacing: 12) {
                ForEach(0..<totalItemsWithAds, id: \.self) { index in
                    if isAdPosition(index) && showAds {
                        // Native ad card
                        NativeAdCardView()
                    } else {
                        // Workout card
                        let workoutIndex = getWorkoutIndex(for: index)
                        if workoutIndex < workouts.count {
                            RecentWorkoutCard(workout: workouts[workoutIndex])
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Workout History Day Section (Legacy - kept for compatibility)
struct WorkoutHistoryDaySection: View {
    let date: Date
    let workouts: [Workout]
    @Environment(\.colorScheme) private var colorScheme
    
    private var displayDate: String {
        if Calendar.current.isDateInToday(date) {
            return "Today"
        } else if Calendar.current.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, MMMM d"
            return formatter.string(from: date)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Date header
            HStack {
                Text(displayDate)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("\(workouts.count) workout\(workouts.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.7))
            }
            .padding(.horizontal, 4)
            
            // Workout cards - using same style as home page
            VStack(spacing: 12) {
                ForEach(workouts, id: \.id) { workout in
                    RecentWorkoutCard(workout: workout)
                }
            }
        }
    }
}

// MARK: - Legacy code removed (WorkoutHistoryView, WorkoutDaySection, ExpandedWorkoutCard, HistoryExerciseRowView, HistoryStatItem, DashboardStatBadge)
// These components were unused - WorkoutHistoryFullView is the active implementation

// NOTE: Legacy components removed (WorkoutHistoryView, WorkoutDaySection, ExpandedWorkoutCard, 
// HistoryExerciseRowView, HistoryStatItem, DashboardStatBadge) - WorkoutHistoryFullView is the active implementation

// NOTE: Legacy code removed (WorkoutHistoryView, WorkoutDaySection, ExpandedWorkoutCard,
// HistoryExerciseRowView, HistoryStatItem, DashboardStatBadge) - WorkoutHistoryFullView is the active implementation

// MARK: - Streak Info Sheet
struct StreakInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var userManager: UserManager
    @StateObject private var premiumManager = PremiumManager.shared
    @State private var showingEditStreak = false
    @State private var showingPremiumUpgrade = false
    
    private var currentStreak: Int {
        Int(userManager.currentUser?.currentStreak ?? 0)
    }
    
    private var longestStreak: Int {
        Int(userManager.currentUser?.longestStreak ?? 0)
    }
    
    private var daysPerWeek: Int {
        max(2, Int(userManager.currentUser?.availableDays ?? 4))
    }
    
    private var maxRestDays: Int {
        userManager.getMaxAllowedRestDays()
    }
    
    private var streakStatus: (isAtRisk: Bool, daysRemaining: Int, message: String) {
        userManager.getStreakStatus()
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Big flame with current streak
                    streakHeroSection
                    
                    // How it works
                    howItWorksSection
                    
                    // Your schedule
                    yourScheduleSection
                    
                    // Tips
                    tipsSection
                }
                .padding()
            }
            .background(
                LinearGradient(
                    colors: colorScheme == .dark 
                        ? [Color(white: 0.08), Color(white: 0.05)]
                        : [Color(white: 0.98), Color(white: 0.95)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            .navigationTitle("Your Streak")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showingEditStreak) {
                EditStreakSheet(currentStreak: currentStreak)
                    .environmentObject(userManager)
                    .presentationDetents([.height(320)])
                    .presentationDragIndicator(.visible)
            }
            .fullScreenCover(isPresented: $showingPremiumUpgrade) {
                PremiumUpgradeView(triggeringFeature: .streakEdit)
            }
        }
    }
    
    // MARK: - Streak Hero
    private var streakHeroSection: some View {
        VStack(spacing: 16) {
            ZStack {
                // Glow effect
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.orange.opacity(0.3), Color.clear],
                            center: .center,
                            startRadius: 40,
                            endRadius: 100
                        )
                    )
                    .frame(width: 200, height: 200)
                
                // Solid fill behind the flame to fill the hole
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.orange, Color.red.opacity(0.9)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 68, height: 68)
                    .offset(y: 10)
                
                // Flame
                Image(systemName: "flame.fill")
                    .font(.system(size: 100))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.orange, .red],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: .orange.opacity(0.5), radius: 20)
                
                // Streak number
                Text("\(currentStreak)")
                    .font(.system(size: 48, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.3), radius: 2)
                    .offset(y: 10)
            }
            
            Text(currentStreak == 1 ? "Workout Streak" : "Workout Streak")
                .font(.title2)
                .fontWeight(.bold)
            
            // Edit Streak button (Premium feature)
            Button(action: {
                HapticManager.tap()
                if premiumManager.isPremiumUser {
                    showingEditStreak = true
                } else {
                    showingPremiumUpgrade = true
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 14))
                    Text("Edit Streak")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    if !premiumManager.isPremiumUser {
                        Image(systemName: "crown.fill")
                            .font(.ds_caption)
                            .foregroundColor(.yellow)
                    }
                }
                .foregroundColor(.orange)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.xs)
                .background(
                    Capsule()
                        .fill(Color.orange.opacity(0.15))
                )
                .overlay(
                    Capsule()
                        .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                )
            }
            
            // Best streak
            if longestStreak > currentStreak {
                HStack(spacing: 4) {
                    Image(systemName: "trophy.fill")
                        .foregroundColor(.yellow)
                    Text("Best: \(longestStreak)")
                        .fontWeight(.semibold)
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 20)
    }
    
    // MARK: - Status Section
    private var statusSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: streakStatus.isAtRisk ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(streakStatus.isAtRisk ? .orange : .green)
                
                Text(streakStatus.message)
                    .font(.headline)
                    .foregroundColor(streakStatus.isAtRisk ? .orange : .primary)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .fill(streakStatus.isAtRisk ? Color.orange.opacity(0.15) : Color.green.opacity(0.15))
            )
        }
    }
    
    // MARK: - How It Works Section
    private var howItWorksSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("How Streaks Work", systemImage: "lightbulb.fill")
                .font(.headline)
                .foregroundColor(.orange)
            
            VStack(alignment: .leading, spacing: 12) {
                streakRuleRow(
                    icon: "checkmark.circle.fill",
                    color: .green,
                    title: "Rest days don't break your streak!",
                    subtitle: "Recovery is part of training"
                )
                
                streakRuleRow(
                    icon: "calendar",
                    color: .blue,
                    title: "Based on YOUR schedule",
                    subtitle: "You work out \(daysPerWeek) days/week"
                )
                
                streakRuleRow(
                    icon: "clock.fill",
                    color: .purple,
                    title: "Up to \(maxRestDays) rest days allowed",
                    subtitle: "Between workouts without losing streak"
                )
                
                streakRuleRow(
                    icon: "xmark.circle.fill",
                    color: .red,
                    title: "Streak resets after \(maxRestDays + 1)+ days",
                    subtitle: "Without completing a workout"
                )
            }
            .padding()
            .frame(minHeight: 240)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .fill(Color(.systemGray6))
            )
        }
    }
    
    // MARK: - Your Schedule Section
    private var yourScheduleSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Your Training Schedule", systemImage: "figure.strengthtraining.traditional")
                .font(.headline)
                .foregroundColor(.blue)
            
            HStack(spacing: 16) {
                scheduleStatCard(
                    value: "\(daysPerWeek)",
                    label: "Days/Week",
                    icon: "calendar.badge.clock",
                    color: .blue
                )
                
                scheduleStatCard(
                    value: "\(maxRestDays)",
                    label: "Max Rest Days",
                    icon: "bed.double.fill",
                    color: .purple
                )
                
                scheduleStatCard(
                    value: "\(currentStreak)",
                    label: "Current",
                    icon: "flame.fill",
                    color: .orange
                )
            }
        }
    }
    
    // MARK: - Tips Section
    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Pro Tips", systemImage: "star.fill")
                .font(.headline)
                .foregroundColor(.yellow)
            
            VStack(alignment: .leading, spacing: 12) {
                tipRow("🏋️", "Any completed workout counts toward your streak")
                tipRow("😴", "Rest days are essential for muscle recovery")
                tipRow("📅", "Consistency > Intensity for building habits")
                tipRow("🔔", "Enable notifications to never miss a workout")
            }
            .padding()
            .frame(minHeight: 240)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .fill(Color(.systemGray6))
            )
        }
    }
    
    // MARK: - Helper Views
    private func streakRuleRow(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 28)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func scheduleStatCard(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .fill(Color(.systemGray6))
        )
    }
    
    private func tipRow(_ emoji: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(emoji)
                .font(.title3)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
        }
    }
}

// MARK: - Edit Streak Sheet
struct EditStreakSheet: View {
    let currentStreak: Int
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var userManager: UserManager
    @State private var newStreak: Int
    @State private var isSaving = false
    
    init(currentStreak: Int) {
        self.currentStreak = currentStreak
        _newStreak = State(initialValue: currentStreak)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Edit Streak")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            
            // Streak input
            VStack(spacing: 12) {
                ZStack {
                    // Glow
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.orange.opacity(0.3), Color.clear],
                                center: .center,
                                startRadius: 20,
                                endRadius: 60
                            )
                        )
                        .frame(width: 120, height: 120)
                    
                    // Flame
                    Image(systemName: "flame.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(
                            LinearGradient(colors: [.orange, .red], startPoint: .top, endPoint: .bottom)
                        )
                }
                
                // Stepper for streak
                HStack(spacing: 20) {
                    Button(action: {
                        if newStreak > 0 {
                            HapticManager.selectionChanged()
                            newStreak -= 1
                        }
                    }) {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(newStreak > 0 ? .orange : .gray.opacity(0.3))
                    }
                    .disabled(newStreak <= 0)
                    
                    Text("\(newStreak)")
                        .font(.system(size: 48, weight: .black, design: .rounded))
                        .foregroundColor(.primary)
                        .frame(minWidth: 80)
                    
                    Button(action: {
                        HapticManager.selectionChanged()
                        newStreak += 1
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(.orange)
                    }
                }
                
                Text("days")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // Save button
            Button(action: saveStreak) {
                HStack {
                    if isSaving {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Save Streak")
                            .fontWeight(.semibold)
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.md)
                .background(
                    LinearGradient(
                        colors: [.orange, .red],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(14)
            }
            .disabled(isSaving || newStreak == currentStreak)
            .opacity(newStreak == currentStreak ? 0.5 : 1)
            .padding(.horizontal, 20)
            
            Spacer()
        }
    }
    
    private func saveStreak() {
        isSaving = true
        HapticManager.success()
        
        // Update the streak in Core Data
        if let user = userManager.currentUser {
            user.currentStreak = Int16(newStreak)
            
            // Update longest streak if needed
            if newStreak > user.longestStreak {
                user.longestStreak = Int16(newStreak)
            }
            
            // Save context
            do {
                try user.managedObjectContext?.save()
                
                // Sync to Supabase
                Task {
                    do {
                        try await SupabaseManager.shared.syncCoreDataProfile(from: user)
                    } catch {
                        print("❌ Failed to sync streak to cloud: \(error)")
                    }
                }
            } catch {
                print("❌ Failed to save streak: \(error)")
            }
        }
        
        dismiss()
    }
}

struct WorkoutDetailBadge: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.12))
                    .frame(width: 44, height: 44)
                
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(color)
            }
            
            VStack(spacing: 2) {
                Text(value)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.primary)
                
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Dashboard Weight Widget
struct DashboardWeightWidget: View {
    let isCompact: Bool
    let cardBackgroundGradient: [Color]
    
    @ObservedObject private var weightService = WeightTrackingService.shared
    @StateObject private var premiumManager = PremiumManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingInput = false
    @State private var showingPremiumUpgrade = false
    @State private var weightInput = ""
    @FocusState private var isInputFocused: Bool
    
    // Match the WeightTrackerWidget color scheme (orange/yellow)
    private let gradientColors: [Color] = [.orange, .yellow]
    
    var body: some View {
        Button(action: {
            HapticManager.tap()
            if premiumManager.isPremiumUser {
                showingInput = true
            } else {
                showingPremiumUpgrade = true
            }
        }) {
            widgetContentWithPremiumBadge
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showingInput) {
            WeightInputSheet(weightService: weightService, autoFocus: $showingInput)
                .presentationDetents([.height(280)])
                .presentationDragIndicator(.visible)
                .presentationBackgroundInteraction(.enabled)
                .interactiveDismissDisabled(false)
        }
        .fullScreenCover(isPresented: $showingPremiumUpgrade) {
            PremiumUpgradeView(triggeringFeature: .weightTracking)
        }
        .onAppear {
            // Refresh weight data when widget appears
            Task {
                await weightService.loadAllData()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .weightDidUpdate)) { _ in
            // Weight was updated elsewhere (e.g., nutrition tab) - force reload to stay in sync
            Task {
                await weightService.loadAllData()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dailyResetCompleted)) { _ in
            // 🌙 Daily reset completed - refresh all dashboard data
            print("🌙 [DASHBOARD] Daily reset notification received - refreshing data")
            Task {
                await ChallengeService.shared.fetchActiveChallenges()
                await HydrationService.shared.loadTodayData()
                await weightService.loadAllData()
                MealService.shared.loadTodaysMeals()
            }
        }
    }
    
    @ViewBuilder
    private var widgetContentWithPremiumBadge: some View {
        ZStack(alignment: .topTrailing) {
            widgetContent
            
            // Premium badge for free users
            if !premiumManager.isPremiumUser {
                HStack(spacing: 4) {
                    Image(systemName: "crown.fill")
                        .font(.ds_caption)
                    Text("PRO")
                        .font(.ds_caption)
                        .tracking(1)
                }
                .foregroundColor(.white)
                .padding(.horizontal, Spacing.xs)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .shadow(color: .blue.opacity(0.4), radius: 4, x: 0, y: 2)
                )
                .offset(x: -8, y: 8)
            }
        }
    }
    
    @ViewBuilder
    private var widgetContent: some View {
        Group {
            if isCompact {
                compactLayout
            } else {
                expandedLayout
            }
        }
        .frame(width: isCompact ? 160 : nil, height: isCompact ? 140 : 80)
        .frame(maxWidth: isCompact ? nil : .infinity)
        .padding(.horizontal, isCompact ? 0 : 20)
        .background(widgetBackground)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 12, x: 0, y: 6)
        .shadow(color: gradientColors[0].opacity(colorScheme == .dark ? 0.2 : 0.12), radius: 20, x: 0, y: 10)
    }
    
    private var compactLayout: some View {
        VStack(spacing: 10) {
            // Icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: gradientColors),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 50, height: 50)
                    .shadow(color: gradientColors[0].opacity(0.4), radius: 8, x: 0, y: 4)
                
                Image(systemName: "scalemass.fill")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
            }
            
            // Weight display
            VStack(spacing: 4) {
                if let todayWeight = weightService.todayLog {
                    let displayWeight = weightService.usesLbs ? todayWeight.weightLbs : todayWeight.weightKg
                    let unit = weightService.usesLbs ? "lbs" : "kg"
                    
                    Text("\(String(format: "%.1f", displayWeight)) \(unit)")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .id(todayWeight.id) // Force refresh when weight changes
                    
                    // 7-day trend
                    trendLabel
                } else {
                    Text("_ _")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary.opacity(0.5))
                    
                    Text("Tap to log")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    @ViewBuilder
    private var trendLabel: some View {
        let weeklyChange = weightService.weeklyChange
        
        if abs(weeklyChange) < 0.1 {
            // Essentially no change
            Text("7-day: maintaining")
                .font(.caption2)
                .foregroundColor(.secondary)
        } else if weeklyChange < 0 {
            // Losing weight
            HStack(spacing: 2) {
                Image(systemName: "arrow.down.right")
                    .font(.system(size: 9, weight: .bold))
                Text("7-day: losing")
                    .font(.caption2)
            }
            .foregroundColor(.green)
        } else {
            // Gaining weight
            HStack(spacing: 2) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .bold))
                Text("7-day: gaining")
                    .font(.caption2)
            }
            .foregroundColor(.orange)
        }
    }
    
    private var expandedLayout: some View {
        HStack(spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: gradientColors),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 50, height: 50)
                    .shadow(color: gradientColors[0].opacity(0.4), radius: 8, x: 0, y: 4)
                
                Image(systemName: "scalemass.fill")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Weight")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                // 7-day trend for expanded view
                expandedTrendLabel
            }
            
            Spacer()
            
            // Show weight or placeholder
            if let todayWeight = weightService.todayLog {
                let displayWeight = weightService.usesLbs ? todayWeight.weightLbs : todayWeight.weightKg
                let unit = weightService.usesLbs ? "lbs" : "kg"
                Text("\(String(format: "%.1f", displayWeight)) \(unit)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(
                        LinearGradient(colors: gradientColors, startPoint: .leading, endPoint: .trailing)
                    )
                    .id(todayWeight.id) // Force refresh when weight changes
            } else {
                Text("_ _")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary.opacity(0.4))
            }
        }
    }
    
    @ViewBuilder
    private var expandedTrendLabel: some View {
        if weightService.todayLog == nil {
            Text("Tap to log today's weight")
                .font(.caption)
                .foregroundColor(.secondary)
        } else {
            let weeklyChange = weightService.weeklyChange
            
            if abs(weeklyChange) < 0.1 {
                Text("7-day: maintaining")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if weeklyChange < 0 {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.down.right")
                        .font(.ds_caption)
                    Text("7-day: losing weight")
                        .font(.caption)
                }
                .foregroundColor(.green)
            } else {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.up.right")
                        .font(.ds_caption)
                    Text("7-day: gaining weight")
                        .font(.caption)
                }
                .foregroundColor(.orange)
            }
        }
    }
    
    private var widgetBackground: some View {
        ZStack {
            // Bottom shadow layer (deepest) - color glow
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(gradientColors[0].opacity(colorScheme == .dark ? 0.15 : 0.08))
                .offset(y: 8)
                .blur(radius: 4)
            
            // Middle shadow layer
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                .offset(y: 4)
            
            // Main card background with gradient
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: cardBackgroundGradient,
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            
            // Inner highlight (top edge glow)
            RoundedRectangle(cornerRadius: 24, style: .continuous)
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
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [gradientColors[0].opacity(colorScheme == .dark ? 0.4 : 0.3), gradientColors[1].opacity(colorScheme == .dark ? 0.3 : 0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
    }
}

// MARK: - Weight Input Sheet
struct WeightInputSheet: View {
    @ObservedObject var weightService: WeightTrackingService
    @Binding var autoFocus: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var weightInput = ""
    @FocusState private var isInputFocused: Bool
    
    // Match the WeightTrackerWidget color scheme (orange/yellow)
    private let gradientColors: [Color] = [.orange, .yellow]
    
    init(weightService: WeightTrackingService, autoFocus: Binding<Bool>) {
        self.weightService = weightService
        self._autoFocus = autoFocus
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Log Weight")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            
            // Weight input
            HStack(spacing: 8) {
                TextField("0.0", text: $weightInput)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .focused($isInputFocused)
                    .frame(maxWidth: 200)
                    .onAppear {
                        // Focus immediately on appear
                        DispatchQueue.main.async {
                            isInputFocused = true
                        }
                    }
                
                Text(weightService.usesLbs ? "lbs" : "kg")
                    .font(.title)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 10)
            
            // Save button
            Button(action: saveWeight) {
                Text("Save")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.md)
                    .background(
                        LinearGradient(
                            colors: gradientColors,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(14)
            }
            .disabled(weightInput.isEmpty)
            .opacity(weightInput.isEmpty ? 0.5 : 1)
            .padding(.horizontal, 20)
            
            Spacer()
        }
        .onAppear {
            // Pre-fill with current weight if logged today
            if weightService.hasLoggedToday, let todayWeight = weightService.todayLog {
                let displayWeight = weightService.usesLbs ? todayWeight.weightLbs : todayWeight.weightKg
                weightInput = String(format: "%.1f", displayWeight)
            }
            // Focus immediately - no delay
            isInputFocused = true
        }
    }
    
    private func saveWeight() {
        guard let weight = Double(weightInput) else {
            print("❌ [Widget] Invalid weight input: '\(weightInput)'")
            return
        }
        
        print("💾 [Widget] Saving weight: \(weight) \(weightService.usesLbs ? "lbs" : "kg")")
        HapticManager.success()
        
        Task {
            let success = await weightService.logWeight(weight)
            if success {
                print("✅ [Widget] Weight saved successfully")
                print("✅ [Widget] todayLog is now: \(weightService.todayLog != nil ? "SET" : "NIL")")
                print("✅ [Widget] hasLoggedToday: \(weightService.hasLoggedToday)")
                // Small delay to ensure UI updates propagate
                try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
            } else {
                print("❌ [Widget] Failed to save weight to cloud")
            }
            await MainActor.run {
                print("🚪 [Widget] Dismissing sheet, todayLog still: \(weightService.todayLog != nil ? "SET" : "NIL")")
                dismiss()
            }
        }
    }
}

// MARK: - Dashboard Hydration Widget
struct DashboardHydrationWidget: View {
    let isCompact: Bool
    let cardBackgroundGradient: [Color]
    
    @ObservedObject private var hydrationService = HydrationService.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingQuickAdd = false
    
    // Unit preference - synced with quick add sheet
    @AppStorage("hydrationUnitPreference") private var usesOz: Bool = true
    
    private let gradientColors: [Color] = [.cyan, .blue]
    private let mlPerOz = 29.5735
    
    var body: some View {
        Button(action: {
            HapticManager.tap()
            showingQuickAdd = true
        }) {
            widgetContent
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showingQuickAdd) {
            HydrationQuickAddSheet(hydrationService: hydrationService)
                .presentationDetents([.height(380)])
                .presentationDragIndicator(.visible)
        }
    }
    
    @ViewBuilder
    private var widgetContent: some View {
        Group {
            if isCompact {
                compactLayout
            } else {
                expandedLayout
            }
        }
        .frame(width: isCompact ? 160 : nil, height: isCompact ? 140 : 80)
        .frame(maxWidth: isCompact ? nil : .infinity)
        .padding(.horizontal, isCompact ? 0 : 20)
        .background(widgetBackground)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 12, x: 0, y: 6)
        .shadow(color: gradientColors[0].opacity(colorScheme == .dark ? 0.2 : 0.12), radius: 20, x: 0, y: 10)
    }
    
    private var compactLayout: some View {
        VStack(spacing: 12) {
            // Icon with progress ring
            ZStack {
                // Background ring
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 4)
                    .frame(width: 50, height: 50)
                
                // Progress ring
                Circle()
                    .trim(from: 0, to: hydrationService.todayProgress)
                    .stroke(
                        LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: 50, height: 50)
                    .rotationEffect(.degrees(-90))
                
                Image(systemName: "drop.fill")
                    .font(.ds_heading3)
                    .foregroundStyle(
                        LinearGradient(colors: gradientColors, startPoint: .top, endPoint: .bottom)
                    )
            }
            
            // Water display - respects unit preference
            VStack(spacing: 4) {
                if usesOz {
                    let totalOz = Int(Double(hydrationService.todayTotal) / mlPerOz)
                    let goalOz = Int(Double(hydrationService.settings.dailyGoalMl) / mlPerOz)
                    
                    Text("\(totalOz)")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text("of \(goalOz) oz")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("\(hydrationService.todayTotal)")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text("of \(hydrationService.settings.dailyGoalMl) ml")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private var expandedLayout: some View {
        HStack(spacing: 16) {
            // Icon with progress ring
            ZStack {
                // Background ring
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 5)
                    .frame(width: 50, height: 50)
                
                // Progress ring
                Circle()
                    .trim(from: 0, to: hydrationService.todayProgress)
                    .stroke(
                        LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .frame(width: 50, height: 50)
                    .rotationEffect(.degrees(-90))
                
                Image(systemName: "drop.fill")
                    .font(.ds_heading3)
                    .foregroundStyle(
                        LinearGradient(colors: gradientColors, startPoint: .top, endPoint: .bottom)
                    )
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Hydration")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                if usesOz {
                    let totalOz = Int(Double(hydrationService.todayTotal) / mlPerOz)
                    let goalOz = Int(Double(hydrationService.settings.dailyGoalMl) / mlPerOz)
                    Text("\(totalOz) of \(goalOz) oz")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("\(hydrationService.todayTotal) of \(hydrationService.settings.dailyGoalMl) ml")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Progress percentage
            Text("\(Int(hydrationService.todayProgress * 100))%")
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(
                    LinearGradient(colors: gradientColors, startPoint: .leading, endPoint: .trailing)
                )
        }
    }
    
    private var widgetBackground: some View {
        ZStack {
            // Bottom shadow layer (deepest) - color glow
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(gradientColors[0].opacity(colorScheme == .dark ? 0.15 : 0.08))
                .offset(y: 8)
                .blur(radius: 4)
            
            // Middle shadow layer
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                .offset(y: 4)
            
            // Main card background with gradient
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: cardBackgroundGradient,
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            
            // Inner highlight (top edge glow)
            RoundedRectangle(cornerRadius: 24, style: .continuous)
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
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [gradientColors[0].opacity(colorScheme == .dark ? 0.4 : 0.3), gradientColors[1].opacity(colorScheme == .dark ? 0.3 : 0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
    }
}

// MARK: - Hydration Quick Add Sheet
struct HydrationQuickAddSheet: View {
    @ObservedObject var hydrationService: HydrationService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var customAmount = ""
    @FocusState private var isInputFocused: Bool
    
    // Unit preference - persisted to UserDefaults
    @AppStorage("hydrationUnitPreference") private var usesOz: Bool = true
    
    private let gradientColors: [Color] = [.cyan, .blue]
    
    // Quick add amounts
    private let quickAddAmountsOz = [8, 12, 16, 24]
    private let quickAddAmountsMl = [250, 350, 500, 750]
    
    // Conversion constants
    private let mlPerOz = 29.5735
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text("Add Water")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            
            // Unit Toggle
            HStack(spacing: 0) {
                Button(action: {
                    HapticManager.selectionChanged()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        usesOz = true
                    }
                }) {
                    Text("oz")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(usesOz ? .white : .secondary)
                        .frame(width: 60, height: 32)
                        .background(
                            usesOz ? LinearGradient(colors: gradientColors, startPoint: .leading, endPoint: .trailing) : LinearGradient(colors: [Color.clear], startPoint: .leading, endPoint: .trailing)
                        )
                        .cornerRadius(CornerRadius.sm)
                }
                
                Button(action: {
                    HapticManager.selectionChanged()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        usesOz = false
                    }
                }) {
                    Text("ml")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(!usesOz ? .white : .secondary)
                        .frame(width: 60, height: 32)
                        .background(
                            !usesOz ? LinearGradient(colors: gradientColors, startPoint: .leading, endPoint: .trailing) : LinearGradient(colors: [Color.clear], startPoint: .leading, endPoint: .trailing)
                        )
                        .cornerRadius(CornerRadius.sm)
                }
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.92))
            )
            
            // Current progress
            if usesOz {
                let totalOz = Int(Double(hydrationService.todayTotal) / mlPerOz)
                let goalOz = Int(Double(hydrationService.settings.dailyGoalMl) / mlPerOz)
                Text("\(totalOz) / \(goalOz) oz today")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                Text("\(hydrationService.todayTotal) / \(hydrationService.settings.dailyGoalMl) ml today")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // Quick add buttons
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                if usesOz {
                    ForEach(quickAddAmountsOz, id: \.self) { oz in
                        quickAddButton(amount: oz, unit: "oz")
                    }
                } else {
                    ForEach(quickAddAmountsMl, id: \.self) { ml in
                        quickAddButton(amount: ml, unit: "ml")
                    }
                }
            }
            .padding(.horizontal, 20)
            
            // Divider
            HStack {
                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(height: 1)
                Text("or")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(height: 1)
            }
            .padding(.horizontal, 20)
            
            // Custom input
            HStack(spacing: 8) {
                TextField("Custom", text: $customAmount)
                    .font(.headline)
                    .keyboardType(.numberPad)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 100)
                    .focused($isInputFocused)
                
                Text(usesOz ? "oz" : "ml")
                    .foregroundColor(.secondary)
                    .frame(width: 30)
                
                Button(action: {
                    if let amount = Int(customAmount) {
                        addWater(amount: amount, isOz: usesOz)
                    }
                }) {
                    Text("Add")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(
                            LinearGradient(colors: gradientColors, startPoint: .leading, endPoint: .trailing)
                        )
                        .cornerRadius(10)
                }
                .disabled(customAmount.isEmpty)
                .opacity(customAmount.isEmpty ? 0.5 : 1)
            }
            .padding(.horizontal, 20)
            
            Spacer()
        }
    }
    
    @ViewBuilder
    private func quickAddButton(amount: Int, unit: String) -> some View {
        Button(action: {
            addWater(amount: amount, isOz: unit == "oz")
        }) {
            VStack(spacing: 4) {
                Image(systemName: "drop.fill")
                    .font(.title3)
                Text("\(amount) \(unit)")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .fill(colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.95))
            )
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .stroke(
                        LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .foregroundStyle(
            LinearGradient(colors: gradientColors, startPoint: .top, endPoint: .bottom)
        )
    }
    
    private func addWater(amount: Int, isOz: Bool) {
        // Always store in ml for consistency
        let ml: Int
        if isOz {
            ml = Int(Double(amount) * mlPerOz)
        } else {
            ml = amount
        }
        
        HapticManager.success()
        
        Task {
            _ = await hydrationService.logWater(amountMl: ml)
            await MainActor.run {
                dismiss()
            }
        }
    }
}

// MARK: - Widget Settings Sheet
struct WidgetSettingsSheet: View {
    @Binding var showWeightTracker: Bool
    @Binding var showHydration: Bool
    @Binding var showMacros: Bool
    @Binding var showChallenge: Bool
    @Binding var showRecommended: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var premiumManager = PremiumManager.shared
    @State private var showingPremiumUpgrade = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Subtitle
                    if premiumManager.isPremiumUser {
                        Text("Customize your dashboard with quick-access widgets")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 24)
                            .lineLimit(2)
                    } else {
                        VStack(spacing: 8) {
                            Text("Customize your dashboard with quick-access widgets")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            
                            HStack(spacing: 4) {
                                Image(systemName: "crown.fill")
                                    .font(.ds_labelSmall)
                                    .foregroundColor(.yellow)
                                Text("Premium Required")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.orange)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                    }
                    
                    // Widget options
                    VStack(spacing: 12) {
                        widgetOptionRow(
                            icon: "chart.pie.fill",
                            title: "Quick Macros",
                            subtitle: "Today's nutrition at a glance",
                            gradientColors: [Color.teal, Color.mint],
                            isSelected: $showMacros
                        )
                        
                        widgetOptionRow(
                            icon: "scalemass.fill",
                            title: "Weight Tracker",
                            subtitle: "Track your weight progress",
                            gradientColors: [Color.orange, Color.yellow],
                            isSelected: $showWeightTracker
                        )
                        
                        widgetOptionRow(
                            icon: "drop.fill",
                            title: "Hydration Tracker",
                            subtitle: "Track your daily water intake",
                            gradientColors: [Color.cyan, Color.blue],
                            isSelected: $showHydration
                        )
                        
                        // Challenge widget - show for all users, but locked for free users
                        challengeWidgetOptionRow(
                            isSelected: $showChallenge
                        )
                        
                        // Recommended For You widget - premium can hide, free users see it locked
                        recommendedWidgetOptionRow(
                            isSelected: $showRecommended
                        )
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                    
                    // Done button
                    Button(action: {
                        HapticManager.tap()
                        dismiss()
                    }) {
                        Text("Done")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.md)
                            .background(
                                LinearGradient(
                                    colors: [.blue, .cyan],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(14)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
                .padding(.top, 16)
            }
            .navigationTitle("Add Widgets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showingPremiumUpgrade) {
            PremiumUpgradeView(triggeringFeature: .homescreenWidgets)
        }
    }
    
    @ViewBuilder
    private func widgetOptionRow(icon: String, title: String, subtitle: String, gradientColors: [Color], isSelected: Binding<Bool>) -> some View {
        Button(action: {
            // Check if user is premium
            if premiumManager.isPremiumUser {
                HapticManager.selectionChanged()
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSelected.wrappedValue.toggle()
                }
            } else {
                // Show premium upgrade for free users
                HapticManager.tap()
                showingPremiumUpgrade = true
            }
        }) {
            HStack(spacing: 14) {
                // Icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: gradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: icon)
                        .font(.ds_heading3)
                        .foregroundColor(.white)
                }
                
                // Text
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        // PRO badge for free users
                        if !premiumManager.isPremiumUser {
                            HStack(spacing: 3) {
                                Image(systemName: "crown.fill")
                                    .font(.system(size: 9, weight: .bold))
                                Text("PRO")
                                    .font(.system(size: 9, weight: .bold))
                                    .tracking(0.5)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [.blue, .purple],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                            )
                        }
                    }
                    
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Show lock icon for free users or checkbox for premium users
                if !premiumManager.isPremiumUser {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                } else {
                    // Checkbox for premium users
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isSelected.wrappedValue ? LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing) : LinearGradient(colors: [Color.clear], startPoint: .top, endPoint: .bottom))
                            .frame(width: 26, height: 26)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(isSelected.wrappedValue ? Color.clear : Color.secondary.opacity(0.4), lineWidth: 2)
                            )
                        
                        if isSelected.wrappedValue {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                }
            }
            .padding(Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .fill(colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.97))
            )
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .stroke(
                        // Show lock color for free users, or selected color for premium users
                        !premiumManager.isPremiumUser
                            ? LinearGradient(colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            : (isSelected.wrappedValue
                                ? LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LinearGradient(colors: [Color.clear], startPoint: .top, endPoint: .bottom)),
                        lineWidth: 2
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .opacity(!premiumManager.isPremiumUser ? 0.8 : 1.0)
    }
    
    // Challenge widget option - shown to all users, locked for free users
    @ViewBuilder
    private func challengeWidgetOptionRow(isSelected: Binding<Bool>) -> some View {
        Button(action: {
            if premiumManager.isPremiumUser {
                HapticManager.selectionChanged()
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSelected.wrappedValue.toggle()
                }
            } else {
                // Show premium upgrade for free users
                HapticManager.tap()
                showingPremiumUpgrade = true
            }
        }) {
            HStack(spacing: 14) {
                // Icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.orange, Color.red],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                    
                    Text("🏆")
                        .font(.system(size: 20))
                    
                    // Lock overlay for free users
                    if !premiumManager.isPremiumUser {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.white)
                            .background(
                                Circle()
                                    .fill(Color.black.opacity(0.5))
                                    .frame(width: 44, height: 44)
                            )
                    }
                }
                
                // Text
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Challenge a Friend")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        // Premium badge for free users
                        if !premiumManager.isPremiumUser {
                            HStack(spacing: 3) {
                                Image(systemName: "crown.fill")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.yellow)
                                Text("PRO")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.orange)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.orange.opacity(0.15))
                            )
                        }
                    }
                    
                    Text(premiumManager.isPremiumUser ? "Hide this widget" : "Unlock to hide this widget")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Toggle indicator or lock
                if premiumManager.isPremiumUser {
                    ZStack {
                        Circle()
                            .fill(isSelected.wrappedValue ? Color.green : Color.gray.opacity(0.3))
                            .frame(width: 28, height: 28)
                        
                        Image(systemName: isSelected.wrappedValue ? "checkmark" : "")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    }
                } else {
                    // Always ON indicator for free users (can't toggle)
                    ZStack {
                        Circle()
                            .fill(Color.green.opacity(0.5))
                            .frame(width: 28, height: 28)
                        
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .fill(colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.97))
            )
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .stroke(
                        !premiumManager.isPremiumUser
                            ? LinearGradient(colors: [Color.orange.opacity(0.3), Color.red.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            : (isSelected.wrappedValue
                                ? LinearGradient(colors: [Color.orange, Color.red], startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LinearGradient(colors: [Color.clear], startPoint: .top, endPoint: .bottom)),
                        lineWidth: 2
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .opacity(!premiumManager.isPremiumUser ? 0.85 : 1.0)
    }
    
    // MARK: - Recommended For You Widget Option Row
    private func recommendedWidgetOptionRow(isSelected: Binding<Bool>) -> some View {
        Button(action: {
            if premiumManager.isPremiumUser {
                HapticManager.selectionChanged()
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSelected.wrappedValue.toggle()
                }
            } else {
                // Show premium upgrade for free users
                HapticManager.tap()
                showingPremiumUpgrade = true
            }
        }) {
            HStack(spacing: 14) {
                // Icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.green, Color.teal],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "star.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                    
                    // Lock overlay for free users
                    if !premiumManager.isPremiumUser {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.white)
                            .background(
                                Circle()
                                    .fill(Color.black.opacity(0.5))
                                    .frame(width: 44, height: 44)
                            )
                    }
                }
                
                // Text
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Recommended For You")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        // Premium badge for free users
                        if !premiumManager.isPremiumUser {
                            HStack(spacing: 3) {
                                Image(systemName: "crown.fill")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.yellow)
                                Text("PRO")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.green)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.green.opacity(0.15))
                            )
                        }
                    }
                    
                    Text(premiumManager.isPremiumUser ? "Hide this widget" : "Unlock to hide this widget")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Toggle indicator or lock
                if premiumManager.isPremiumUser {
                    ZStack {
                        Circle()
                            .fill(isSelected.wrappedValue ? Color.green : Color.gray.opacity(0.3))
                            .frame(width: 28, height: 28)
                        
                        Image(systemName: isSelected.wrappedValue ? "checkmark" : "")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    }
                } else {
                    // Always ON indicator for free users (can't toggle)
                    ZStack {
                        Circle()
                            .fill(Color.green.opacity(0.5))
                            .frame(width: 28, height: 28)
                        
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .fill(colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.97))
            )
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .stroke(
                        !premiumManager.isPremiumUser
                            ? LinearGradient(colors: [Color.green.opacity(0.3), Color.teal.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            : (isSelected.wrappedValue
                                ? LinearGradient(colors: [Color.green, Color.teal], startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LinearGradient(colors: [Color.clear], startPoint: .top, endPoint: .bottom)),
                        lineWidth: 2
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .opacity(!premiumManager.isPremiumUser ? 0.85 : 1.0)
    }
}

// MARK: - Friend Notification Badge (Isolated to prevent parent re-renders)
/// Small isolated view that observes FriendService for notification badges
/// This prevents the entire DashboardView from re-rendering when friend data changes
struct FriendNotificationBadge: View {
    @ObservedObject private var friendService = FriendService.shared
    
    var body: some View {
        if friendService.pendingRequests.count > 0 || friendService.unreadWorkoutCount > 0 {
            Circle()
                .fill(Color.red)
                .frame(width: 14, height: 14)
                .overlay(
                    Circle()
                        .stroke(Color.black.opacity(0.3), lineWidth: 1)
                )
        }
    }
}

#Preview {
    DashboardView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(UserManager())
}

