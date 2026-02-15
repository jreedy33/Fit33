import SwiftUI
import CoreData
import UserNotifications

// MARK: - Debug Helper
#if DEBUG
// ⚠️ DEVELOPMENT MODE BEHAVIOR ⚠️
// When SKIP_ONBOARDING_FOR_DEVELOPMENT = true:
//   - App rebuilds will keep you logged in (no onboarding shown)
//   - Manual sign-outs WILL show onboarding (respects user action)
//   - Deleted accounts WILL show onboarding (respects server state)
// When SKIP_ONBOARDING_FOR_DEVELOPMENT = false:
//   - Every app launch will show onboarding (for testing the flow)
private let SKIP_ONBOARDING_FOR_DEVELOPMENT = true

// 🚀 FAST STARTUP MODE - Skip heavy cloud syncs during development
// PRODUCTION: Set to FALSE for full cloud sync behavior
// DEBUG ONLY: Set to TRUE for fast rebuilds (uses cached data)
#if DEBUG
private let FAST_STARTUP_MODE = false  // Set to true only for fast local testing
#else
private let FAST_STARTUP_MODE = false  // Always false in production
#endif

private func resetOnboardingForTesting() {
    // Check if user manually signed out - always respect this
    let userManuallySignedOut = UserDefaults.standard.bool(forKey: "user_manually_signed_out")
    
    if userManuallySignedOut {
        print("🔐 [DEBUG] User manually signed out - will show onboarding")
        // Clear the flag so it doesn't persist forever
        // The flag will be set again if they sign out again
        return  // Don't override - let the normal flow show onboarding
    }
    
    // Skip reset if we want to stay logged in during development
    if SKIP_ONBOARDING_FOR_DEVELOPMENT {
        print("⏭️ [DEBUG] Development mode - keeping existing session")
        return
    }
    
    // For testing onboarding flow - reset onboarding state
    let context = PersistenceController.shared.container.viewContext
    let fetchRequest: NSFetchRequest<User> = User.fetchRequest()
    
    do {
        let users = try context.fetch(fetchRequest)
        for user in users {
            user.hasCompletedOnboarding = false
        }
        try context.save()
        print("🔄 [DEBUG] Onboarding reset - will show onboarding flow")
    } catch {
        print("⚠️ [DEBUG] Could not reset onboarding: \(error)")
    }
}
#endif

// MARK: - App Delegate for Push Notifications
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in
            PushNotificationService.shared.handleDeviceToken(deviceToken)
        }
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in
            PushNotificationService.shared.handleRegistrationError(error)
        }
    }
}

@main
struct Fit33App: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    let persistenceController = PersistenceController.shared
    let premiumManager = PremiumManager.shared
    @StateObject private var supabaseManager = SupabaseManager.shared
    @StateObject private var appearanceManager = AppearanceManager.shared
    @StateObject private var notificationManager = NotificationManager.shared
    @StateObject private var shakeManager = ShakeDetectionManager.shared
    @StateObject private var sessionLogManager = SessionLogManager.shared
    @StateObject private var pushNotificationService = PushNotificationService.shared
    @StateObject private var realtimeService = RealtimeService.shared
    
    @Environment(\.scenePhase) private var scenePhase
    
    init() {
        // 🔧 DEV: Check for crash from previous session
        #if DEBUG
        SessionLogManager.shared.checkForCrashLog()
        #endif
        
        // 🔥 FORCE EXERCISE REFRESH - ONE TIME FIX FOR LEVER NAMES
        // This will clear Core Data and force fresh sync from Supabase
        let needsExerciseRefresh = !UserDefaults.standard.bool(forKey: "exercise_lever_fix_applied_v1")
        if needsExerciseRefresh {
            print("🔥🔥🔥 FORCING EXERCISE REFRESH - CLEARING CACHED DATA 🔥🔥🔥")
            let context = PersistenceController.shared.container.viewContext
            let fetchRequest: NSFetchRequest<NSFetchRequestResult> = Exercise.fetchRequest()
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
            
            do {
                try context.execute(deleteRequest)
                try context.save()
                ExerciseLibraryService.shared.invalidateCache()
                UserDefaults.standard.set(true, forKey: "exercise_lever_fix_applied_v1")
                print("✅ Core Data cleared - exercises will reload from Supabase automatically")
            } catch {
                print("❌ Error clearing exercises: \(error)")
            }
        }
        
        // Start session logging
        SessionLogManager.shared.startSession()
        SessionLogManager.shared.log(.info, category: .session, message: "App initializing")
        
        // 🚀 PERFORMANCE: Initialize performance optimizations (memory monitoring, throttling)
        initializePerformanceOptimizations()
        
        // 🌐 Pre-warm CDN connection for instant video playback (1 tiny HEAD request)
        VideoThumbnailService.shared.prewarmCDNConnection()
        
        // ⚡ Pre-warm haptic generators for instant tap feedback
        HapticManager.shared.prepareAll()
        
        // 🚀 PERFORMANCE: Pre-warm startup cache (critical data for instant tab loads)
        Task(priority: .userInitiated) {
            let context = PersistenceController.shared.container.viewContext
            await StartupCache.shared.warmUp(context: context)
            
            // ⚡️ INSTANT TAB SWITCHING: Enable eager mode after startup cache is warmed
            await MainActor.run {
                LazyTabManager.shared.enableEagerMode()
            }
        }
        
        // ⚡️ INSTANT TAB SWITCHING: Begin aggressive preloading for all tabs
        // This runs in parallel with startup cache and pre-fetches ALL tab data
        Task(priority: .userInitiated) {
            // Short delay to let the UI appear first
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
            
            let context = PersistenceController.shared.container.viewContext
            await TabPreloader.shared.beginPreloading(context: context)
        }
        
        // 👤 Initialize gender filter service (centralized gender management)
        _ = GenderFilterService.shared
        
        // 🚀 Initialize high-performance video engine (pre-warms favorites cache)
        _ = VideoPlaybackEngine.shared
        
        // Track app version for update detection
        let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let currentBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let lastVersion = UserDefaults.standard.string(forKey: "last_app_version")
        let lastBuild = UserDefaults.standard.string(forKey: "last_app_build")
        
        if lastVersion == nil {
            // First launch ever
            SessionLogManager.shared.logAppFirstLaunch(version: currentVersion, build: currentBuild)
        } else if lastVersion != currentVersion || lastBuild != currentBuild {
            // App was updated
            SessionLogManager.shared.logAppUpdated(
                previousVersion: lastVersion ?? "unknown",
                newVersion: currentVersion,
                previousBuild: lastBuild ?? "unknown",
                newBuild: currentBuild
            )
        }
        
        // Save current version
        UserDefaults.standard.set(currentVersion, forKey: "last_app_version")
        UserDefaults.standard.set(currentBuild, forKey: "last_app_build")
        
        // Track session count for retention metrics
        let sessionCount = UserDefaults.standard.integer(forKey: "total_session_count") + 1
        UserDefaults.standard.set(sessionCount, forKey: "total_session_count")
        
        let lastSessionTimestamp = UserDefaults.standard.double(forKey: "last_session_timestamp")
        var daysSinceLastSession: Int? = nil
        if lastSessionTimestamp > 0 {
            let lastDate = Date(timeIntervalSince1970: lastSessionTimestamp)
            daysSinceLastSession = Calendar.current.dateComponents([.day], from: lastDate, to: Date()).day
        }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "last_session_timestamp")
        
        // Log session with retention metrics (totalWorkouts will be updated once user data loads)
        SessionLogManager.shared.logSessionStart(
            sessionNumber: sessionCount,
            daysSinceLastSession: daysSinceLastSession,
            totalWorkoutsCompleted: UserDefaults.standard.integer(forKey: "cached_total_workouts")
        )
        
        // Register the custom value transformer for Core Data array handling
        StringArrayValueTransformer.register()
        
        // DEBUG: Reset onboarding on every launch to test the flow
        // Use the Skip button in the onboarding to bypass during development
        #if DEBUG
        resetOnboardingForTesting()
        
        // 🚀 Set fast startup mode flag for SupabaseManager
        UserDefaults.standard.set(FAST_STARTUP_MODE, forKey: "FAST_STARTUP_MODE")
        if FAST_STARTUP_MODE {
            print("⚡ [FAST STARTUP] Enabled - skipping heavy cloud syncs")
        }
        #endif
        
        // Make navigation bars completely transparent
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = UIColor.clear
        appearance.shadowColor = UIColor.clear
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().backgroundColor = UIColor.clear
        UINavigationBar.appearance().isTranslucent = true
        
        // Remove any system backgrounds and make status bar transparent
        UIView.appearance(whenContainedInInstancesOf: [UIWindow.self]).backgroundColor = UIColor.clear
        
        // Apply saved appearance setting on launch
        AppearanceManager.shared.applyAppearance()
        
        // Set up notification center delegate
        UNUserNotificationCenter.current().delegate = NotificationManager.shared
        
        // 🚀 Clear video prefetch cache on memory warning
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { _ in
            VideoStreamingService.shared.clearPreloadCache()
            VideoPreloadManager.shared.reduceCache()
            print("⚠️ Memory warning - cleared video prefetch cache")
        }
        
        // 📺 Pre-warm AdMob SDK after a short delay (doesn't block UI)
        // This gives ads more time to load before user starts a workout
        #if DEBUG
        if !FAST_STARTUP_MODE {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                if AdManager.shared.adsEnabled {
                    print("📺 Pre-warming AdMob SDK...")
                    AdManager.shared.prepareForWorkout()
                }
            }
        } else {
            print("⚡ [FAST STARTUP] Skipping AdMob pre-warm")
        }
        #else
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            if AdManager.shared.adsEnabled {
                print("📺 Pre-warming AdMob SDK...")
                AdManager.shared.prepareForWorkout()
            }
        }
        #endif
        
        // 🧠 Initialize Exercise Intelligence Engine and Mapping Service
        // DELAYED: Don't block app startup - initialize after a delay
        #if DEBUG
        if !FAST_STARTUP_MODE {
            scheduleIntelligenceInit()
        } else {
            print("⚡ [FAST STARTUP] Skipping intelligence engine initialization")
        }
        #else
        scheduleIntelligenceInit()
        #endif
    }
    
    /// ⚡️ PERFORMANCE: Coordinated startup sequence
    /// Staggers heavy operations to prevent CPU spikes and maintain smooth UI
    private func scheduleIntelligenceInit() {
        // Wait for essential phase to complete (user data synced)
        Task { @MainActor in
            StartupCoordinator.shared.onPhaseComplete(.intelligence) {
                Task(priority: .utility) {
                    await self.runIntelligenceInit()
                }
            }
        }
    }
    
    /// Run intelligence initialization with proper CPU protection
    private func runIntelligenceInit() async {
        // Signal heavy work starting
        HeavyWorkSentinel.shared.beginHeavyWork(reason: "Intelligence initialization")
        defer { HeavyWorkSentinel.shared.endHeavyWork(reason: "Intelligence initialization") }
        
        print("🧠 [INIT] Starting background intelligence initialization...")
        
        // Wait for CPU to settle before starting heavy work
        await CPUProtection.shared.waitForCPUSettled(maxWait: 3.0)
        
        // Step 1: Load exercise data (light)
        ExerciseIntelligenceEngine.shared.loadExerciseData()
        print("🧠 [INIT] Intelligence engine data loading started")
        
        // Yield and wait before next heavy operation
        await Task.yield()
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        // Step 2: Build exercise maps (CPU intensive - staggered)
        if !CPUProtection.shared.isCPUCritical() {
            await ExerciseMappingService.shared.buildMaps()
            print("🧠 [INIT] Exercise mapping service initialized")
        }
        
        await Task.yield()
        try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
        
        // Step 3: Initialize pairing engine (moderate)
        if !CPUProtection.shared.isCPUCritical() {
            SmartExercisePairingEngine.shared.initialize()
            print("🧠 [INIT] Smart exercise pairing engine initialized")
        }
        
        await Task.yield()
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        // Step 4: Popularity data (network + light processing)
        if !CPUProtection.shared.isCPUTooHigh() {
            await ExercisePopularityService.shared.refreshFromServer()
            print("📊 [INIT] Exercise popularity data loaded")
        }
        
        await Task.yield()
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        // Step 5: Collaborative learning (network + moderate processing)
        if !CPUProtection.shared.isCPUTooHigh() {
            await CollaborativeLearningEngine.shared.syncGlobalData()
            print("🌐 [INIT] Collaborative learning engine synced")
        }
        
        await Task.yield()
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        // Step 6: User behavior analysis (CPU intensive - was taking 5.7 seconds!)
        // Only run if CPU is settled
        await CPUProtection.shared.waitForCPUSettled(maxWait: 5.0)
        
        if !CPUProtection.shared.isCPUCritical() {
            let context = PersistenceController.shared.container.viewContext
            await UserBehaviorLearningEngine.shared.analyzeUserBehavior(context: context)
            print("🧠 [INIT] User behavior learning engine initialized")
        } else {
            print("⚠️ [INIT] Skipping behavior analysis - CPU too high")
        }
        
        print("🧠 [INIT] Exercise intelligence systems fully initialized")
    }
    
    var body: some Scene {
        WindowGroup {
            // New onboarding flow includes auth, so always show ContentView
            // ContentView will show NewOnboardingView (with auth) if not completed
            ShakeDetectingView {
                ContentView()
                    .environment(\.managedObjectContext, persistenceController.container.viewContext)
                    .environmentObject(premiumManager)
                    .environmentObject(supabaseManager)
                    .environmentObject(appearanceManager)
                    .environmentObject(notificationManager)
                    .preferredColorScheme(appearanceManager.colorScheme)
                    .ignoresSafeArea(.all, edges: .all)
            }
            .sheet(isPresented: $shakeManager.showBugReportSheet) {
                BugReportView()
            }
                .task {
                    await supabaseManager.checkAuth()

                    // Load user limitations for safety filtering
                    if supabaseManager.isAuthenticated {
                        await LimitationsService.shared.fetchUserLimitations()
                        print("🛡️ [SAFETY] User limitations loaded")
                        
                        // Update session log with user info
                        SessionLogManager.shared.log(.info, category: .profile, message: "User authenticated", metadata: [
                            "user_id": supabaseManager.currentUser?.id ?? "unknown"
                        ])
                        
                        // Register for push notifications (after auth so we can save token)
                        await pushNotificationService.registerForPushNotifications()
                        
                        // 🔄 Connect to Supabase Realtime for instant social updates
                        // This enables instant notifications for: friend requests, shared workouts, challenges
                        realtimeService.setupDefaultCallbacks()
                        await realtimeService.connect()
                        
                        // Track activity: Update last login timestamp
                        await supabaseManager.updateLastLogin()
                        
                        // Track activity: Sync integration connection statuses
                        Task.detached(priority: .background) {
                            await SupabaseManager.shared.syncAllIntegrationStatuses()
                        }
                    }
                    
                    // Check notification authorization and schedule if authorized
                    notificationManager.checkAuthorizationStatus()
                    if notificationManager.isAuthorized {
                        notificationManager.scheduleAllNotifications()
                    }
                    
                    // Check for comeback reminder (if user hasn't worked out in a while)
                    await checkForComebackReminder()
                    
                    // Refresh community insights in background (non-blocking)
                    // Only if stale (> 1 hour old)
                    #if DEBUG
                    if !UserDefaults.standard.bool(forKey: "FAST_STARTUP_MODE") {
                        if SmartRecommendationEngine.shared.communityInsights.needsRefresh {
                            Task.detached(priority: .background) {
                                await SmartRecommendationEngine.shared.communityInsights.refreshInsights()
                            }
                        }
                    }
                    #else
                    if SmartRecommendationEngine.shared.communityInsights.needsRefresh {
                        Task.detached(priority: .background) {
                            await SmartRecommendationEngine.shared.communityInsights.refreshInsights()
                        }
                    }
                    #endif
                }
                .onReceive(appearanceManager.$appearanceMode) { _ in
                    // Re-apply appearance when mode changes
                    appearanceManager.applyAppearance()
                }
                .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OAuthCallback"))) { notification in
                    // Handle OAuth callback (Google, Facebook Sign-In)
                    print("🔐🔐🔐 [AUTH] OAuthCallback notification received!")
                    if let url = notification.object as? URL {
                        print("🔐 [AUTH] Processing OAuth callback from notification")
                        print("🔐 [AUTH] Callback URL: \(url.absoluteString)")
                        print("🔐 [AUTH] Fragment: \(url.fragment ?? "none")")
                        Task {
                            do {
                                let (isNewUser, socialUsername) = try await supabaseManager.handleOAuthCallback(url: url)
                                print("✅ OAuth callback handled successfully (new user: \(isNewUser))")
                                print("✅ Current user email: \(supabaseManager.currentUser?.email ?? "nil")")
                                print("✅ User metadata: \(supabaseManager.currentUser?.userMetadata ?? [:])")
                                
                                // Force UI update and store data on main thread
                                await MainActor.run {
                                    // Store social username for onboarding pre-fill (Facebook/Instagram)
                                    if let username = socialUsername, isNewUser {
                                        UserDefaults.standard.set(username, forKey: "pending_social_username")
                                        print("📘 Stored social username for onboarding: @\(username)")
                                    }
                                    
                                    // Store OAuth-provided name for onboarding BEFORE posting notification
                                    if isNewUser {
                                        if let fullName = supabaseManager.currentUser?.userMetadata["full_name"] as? String, !fullName.isEmpty {
                                            UserDefaults.standard.set(fullName, forKey: "pending_oauth_name")
                                            UserDefaults.standard.synchronize() // Force immediate write
                                            print("🔐 Stored OAuth name (full_name) for onboarding: \(fullName)")
                                        } else if let name = supabaseManager.currentUser?.userMetadata["name"] as? String, !name.isEmpty {
                                            UserDefaults.standard.set(name, forKey: "pending_oauth_name")
                                            UserDefaults.standard.synchronize() // Force immediate write
                                            print("🔐 Stored OAuth name (name) for onboarding: \(name)")
                                        }
                                        
                                        // Also store email for pre-fill
                                        if let email = supabaseManager.currentUser?.email, !email.isEmpty {
                                            UserDefaults.standard.set(email, forKey: "pending_oauth_email")
                                            print("🔐 Stored OAuth email for onboarding: \(email)")
                                        }
                                    }
                                    
                                    UserManager.shared.reloadCurrentUser()
                                    
                                    // Post notification to trigger onboarding navigation for new users
                                    // AFTER storing the name data
                                    if isNewUser {
                                        print("👤 [OAUTH] New user - posting notification to start onboarding")
                                        print("👤 [OAUTH] Verifying stored name: \(UserDefaults.standard.string(forKey: "pending_oauth_name") ?? "nil")")
                                        NotificationCenter.default.post(
                                            name: Notification.Name("OAuthNewUserNeedsOnboarding"),
                                            object: nil
                                        )
                                    }
                                }
                            } catch {
                                print("❌ OAuth callback error: \(error)")
                            }
                        }
                    }
                }
                .onOpenURL { url in
                    // Handle deep link URLs
                    print("🔗🔗🔗 [ONOPENURL] App opened with URL: \(url.absoluteString)")
                    print("🔗 [ONOPENURL] URL scheme: \(url.scheme ?? "none")")
                    print("🔗 [ONOPENURL] URL host: \(url.host ?? "none")")
                    print("🔗 [ONOPENURL] URL fragment: \(url.fragment ?? "none")")
                    
                    let scheme = url.scheme?.lowercased() ?? ""
                    
                    // Handle our custom scheme (fit33://)
                    if scheme == "fit33" {
                        // Direct OAuth callback handling (highest priority)
                        if url.host?.lowercased() == "login-callback" {
                            print("🔐 [ONOPENURL] OAuth callback detected - posting notification directly")
                            NotificationCenter.default.post(name: Notification.Name("OAuthCallback"), object: url)
                            return
                        }
                        
                        // Use the DeepLinkManager to route
                        if DeepLinkManager.shared.handleURL(url) {
                            print("✅ [ONOPENURL] Deep link handled by DeepLinkManager")
                            return
                        }
                    }
                    
                    // Legacy: Handle old gofit scheme
                    if scheme == "gofit" {
                        // Handle different deep link paths
                        if url.host == "running" {
                            // Deep link from Live Activity - navigate to running view
                            print("🏃 Deep link to running workout")
                            DeepLinkManager.shared.pendingDestination = .running
                            return
                        }
                        
                        // Handle OAuth callback
                        Task {
                            do {
                                let (isNewUser, socialUsername) = try await supabaseManager.handleOAuthCallback(url: url)
                                print("✅ OAuth callback handled successfully (new user: \(isNewUser))")
                                
                                // Store social username for onboarding pre-fill (Facebook/Instagram)
                                if let username = socialUsername, isNewUser {
                                    UserDefaults.standard.set(username, forKey: "pending_social_username")
                                    print("📘 Stored social username for onboarding: @\(username)")
                                }
                                
                                // Force UI update after successful OAuth
                                await MainActor.run {
                                    UserManager.shared.reloadCurrentUser()
                                }
                            } catch {
                                print("❌ OAuth callback error: \(error)")
                            }
                        }
                        return
                    }
                    
                    // Handle universal links (https://fit33.app/...)
                    if scheme == "https" {
                        if DeepLinkManager.shared.handleURL(url) {
                            print("✅ Universal link handled")
                            return
                        }
                    }
                    
                    print("⚠️ Unhandled URL: \(url.absoluteString)")
                }
                .onChange(of: scenePhase) { oldPhase, newPhase in
                    switch newPhase {
                    case .active:
                        SessionLogManager.shared.log(.info, category: .session, message: "App became active")
                        
                        // Smart notification check - cancel unnecessary reminders
                        NotificationManager.shared.performSmartCheck()
                        
                        // ⚡️ PERSISTENCE: Check if workout expired while app was closed
                        WorkoutManager.shared.checkWorkoutStateOnForeground()
                        
                        // 🔄 Reconnect to Realtime when app becomes active
                        // BUG FIX: Setup callbacks BEFORE connect() so we don't miss events
                        Task {
                            if supabaseManager.isAuthenticated && !realtimeService.isConnected {
                                realtimeService.setupDefaultCallbacks()
                                await realtimeService.connect()
                            }
                        }
                        
                        // 📬 Check for new shared workouts from friends
                        Task {
                            await FriendService.shared.checkForNewWorkouts()
                        }
                        
                        // 📱 Re-check push notification registration (in case user enabled in Settings)
                        Task {
                            await pushNotificationService.recheckAndRegister()
                        }
                        
                        // 🏥 Re-check HealthKit authorization (in case user enabled in Settings during onboarding)
                        HealthKitManager.shared.checkAuthorizationStatus()
                        HealthKitService.shared.checkAuthorizationStatus()
                        
                        // ☁️ Retry profile sync if user completed onboarding but sync may have failed
                        Task {
                            if SupabaseManager.shared.isAuthenticated,
                               UserManager.shared.hasCompletedOnboarding {
                                try? await UserManager.shared.syncProfileToCloud()
                            }
                        }
                        
                        // 📊 Sync all health data (Fitbit, Strava, etc.) - throttled to prevent excessive syncs
                        // This single call handles Fitbit, Strava, and aggregated health data
                        Task {
                            await HealthDataService.shared.syncAllHealthData()
                        }
                        
                        // 🌙 DAILY RESET: Check if new day and perform daily archival/reset
                        Task {
                            await DailyResetService.shared.checkAndPerformDailyResetIfNeeded()
                        }
                    case .inactive:
                        SessionLogManager.shared.log(.info, category: .session, message: "App became inactive")
                        // 🔧 DEV: Persist logs on inactive (in case of crash)
                        #if DEBUG
                        SessionLogManager.shared.persistLogsForCrashRecovery()
                        #endif
                        
                        // ⚡️ PERSISTENCE: Save workout state before app becomes inactive
                        WorkoutManager.shared.saveWorkoutStateOnBackground()
                    case .background:
                        SessionLogManager.shared.log(.info, category: .session, message: "App entered background")
                        // 🔧 DEV: Mark clean shutdown before going to background
                        #if DEBUG
                        SessionLogManager.shared.markCleanShutdown()
                        #endif
                        // End session when app goes to background (logs cleared unless bug report pending)
                        SessionLogManager.shared.endSession()
                        
                        // 🔌 Disconnect from Realtime to save battery (will reconnect on .active)
                        Task {
                            await realtimeService.disconnect()
                        }
                        
                        // ⚡️ MEMORY FIX: Aggressively free video players when backgrounded.
                        // iOS will kill network requests if memory stays high while backgrounded.
                        // Video players are the single biggest memory consumer (~20-50MB each).
                        VideoPlaybackEngine.shared.clearAllCaches()
                        VideoPreloadManager.shared.clearCache()
                        VideoStreamingService.shared.clearPreloadCache()
                        FriendPhotoCache.shared.clearMemoryCache()
                        
                        // ⚡️ PERSISTENCE: Ensure workout state is saved before background
                        WorkoutManager.shared.saveWorkoutStateOnBackground()
                    @unknown default:
                        break
                    }
                }
        }
    }
    
    // Check if user should receive a comeback reminder
    private func checkForComebackReminder() async {
        let context = persistenceController.container.viewContext
        let fetchRequest: NSFetchRequest<User> = User.fetchRequest()
        fetchRequest.fetchLimit = 1
        
        do {
            let users = try context.fetch(fetchRequest)
            if let user = users.first, let lastWorkout = user.lastWorkoutDate {
                let daysSinceLastWorkout = Calendar.current.dateComponents([.day], from: lastWorkout, to: Date()).day ?? 0
                
                // Send comeback reminder if it's been 2+ days
                if daysSinceLastWorkout >= 2 {
                    // Only send once per day max
                    let lastComebackReminder = UserDefaults.standard.object(forKey: "last_comeback_reminder") as? Date
                    if let lastReminder = lastComebackReminder {
                        let daysSinceReminder = Calendar.current.dateComponents([.day], from: lastReminder, to: Date()).day ?? 0
                        if daysSinceReminder < 1 { return }
                    }
                    
                    notificationManager.sendComebackReminder(daysAway: daysSinceLastWorkout)
                    UserDefaults.standard.set(Date(), forKey: "last_comeback_reminder")
                }
            }
        } catch {
            print("❌ Error checking for comeback reminder: \(error)")
        }
    }
}

