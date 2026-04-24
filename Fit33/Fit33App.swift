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
        AppLogger.debug("User manually signed out - will show onboarding", category: .auth)
        // Clear the flag so it doesn't persist forever
        // The flag will be set again if they sign out again
        return  // Don't override - let the normal flow show onboarding
    }
    
    // Skip reset if we want to stay logged in during development
    if SKIP_ONBOARDING_FOR_DEVELOPMENT {
        AppLogger.debug("Development mode - keeping existing session", category: .auth)
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
        AppLogger.debug("Onboarding reset - will show onboarding flow", category: .general)
    } catch {
        AppLogger.warning("Could not reset onboarding: \(error.localizedDescription)", category: .general)
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
    
    /// Silent push entry point (aps.content-available = 1). iOS invokes this
    /// when a background-priority APNs payload arrives, giving us ~30s to do
    /// work before we MUST call `completionHandler(_:)`. See `SilentPushHandler`
    /// for routing; currently handles `type: "challenge_wake"` from the
    /// `wake-challenge-opponents` edge function.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        Task { @MainActor in
            SilentPushHandler.handle(userInfo: userInfo, completion: completionHandler)
        }
    }
}

@main
struct Fit33App: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    let persistenceController = PersistenceController.shared
    let premiumManager = PremiumManager.shared
    @StateObject private var storeKitManager = StoreKitManager.shared
    @StateObject private var supabaseManager = SupabaseManager.shared
    @StateObject private var appearanceManager = AppearanceManager.shared
    @StateObject private var notificationManager = NotificationManager.shared
    @StateObject private var shakeManager = ShakeDetectionManager.shared
    @StateObject private var sessionLogManager = SessionLogManager.shared
    @StateObject private var pushNotificationService = PushNotificationService.shared
    @StateObject private var realtimeService = RealtimeService.shared
    
    @Environment(\.scenePhase) private var scenePhase
    
    init() {
        // ═══════════════════════════════════════════════════════════════
        // CRITICAL PATH — Must run before first frame
        // Only the absolute minimum to show UI and satisfy Apple requirements
        // ═══════════════════════════════════════════════════════════════
        
        // BGTaskScheduler.register must be called before app finishes launching
        BackgroundChallengeSyncService.shared.setup()

        // ⚡️ Touch ExerciseLibraryService.shared on the FIRST tick of app init so its
        // preWarmCache() Task.detached runs immediately (bg context fetch + inline bundle seed
        // if Core Data is empty). This guarantees the Exercise Library tab has real cards
        // ready before the user can navigate to it — no "Loading exercises..." state, no
        // grey placeholder cards. See ExerciseLibraryService.preWarmCache() for seed logic.
        _ = ExerciseLibraryService.shared

        // One-time Core Data migration — moved off main thread to prevent startup freeze
        let needsExerciseRefresh = !UserDefaults.standard.bool(forKey: "exercise_lever_fix_applied_v1")
        if needsExerciseRefresh {
            let container = PersistenceController.shared.container
            Task.detached(priority: .userInitiated) {
                AppLogger.debug("FORCING EXERCISE REFRESH - CLEARING CACHED DATA", category: .general)
                let bgContext = container.newBackgroundContext()
                await bgContext.perform {
                    let fetchRequest: NSFetchRequest<NSFetchRequestResult> = Exercise.fetchRequest()
                    let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
                    do {
                        try bgContext.execute(deleteRequest)
                        try bgContext.save()
                    } catch {
                        AppLogger.error("Error clearing exercises: \(error.localizedDescription)", category: .general)
                    }

                    // Immediately re-seed from bundle on the SAME bg context so the Exercise
                    // Library tab always has real cards to show — no grey placeholder state.
                    let bundleExercises = ExerciseDataProvider.shared.exercises
                    guard !bundleExercises.isEmpty else { return }
                    AppLogger.info("🌱 [ExerciseLibrary] Re-seeding \(bundleExercises.count) exercises from bundle after migration wipe", category: .data)
                    var inserted = 0
                    for data in bundleExercises {
                        guard !data.name.isEmpty, !data.category.isEmpty else { continue }
                        let exercise = Exercise(context: bgContext)
                        exercise.id = UUID()
                        exercise.name = data.name
                        exercise.category = data.category
                        exercise.muscleGroups = data.muscleGroups as NSObject
                        exercise.equipment = data.equipment
                        exercise.instructions = data.instructions
                        exercise.isFavorite = false
                        inserted += 1
                    }
                    do {
                        try bgContext.save()
                        AppLogger.info("✅ [ExerciseLibrary] Bundle re-seed saved: \(inserted) exercises (viewContext auto-merges)", category: .data)
                    } catch {
                        AppLogger.error("❌ [ExerciseLibrary] Bundle re-seed save failed: \(error.localizedDescription)", category: .data)
                    }
                }
                await MainActor.run {
                    ExerciseLibraryService.shared.invalidateCache()
                    ExerciseLibraryService.shared.isExercisesReady = true
                    UserDefaults.standard.set(true, forKey: "exercise_lever_fix_applied_v1")
                    AppLogger.info("Core Data cleared and re-seeded from bundle - cloud sync will replace with fresh catalog later", category: .general)
                }
            }
        }
        
        // Session logging
        SessionLogManager.shared.startSession()
        SessionLogManager.shared.log(.info, category: .session, message: "App initializing")
        
        // ═══════════════════════════════════════════════════════════════
        // DEFERRED PATH — Runs 0.5s after init so the first frame renders fast
        // Crash reporting, perf monitors, video engine, haptics, etc.
        // ═══════════════════════════════════════════════════════════════
        
        Task.detached(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(500))
            
            // Singleton inits that don't need main thread
            _ = MemoryPressureHandler.shared
            _ = TaskThrottler.shared
            _ = CPUProtection.shared
            _ = HeavyWorkSentinel.shared
            
            // UIKit / CADisplayLink work must be on main
            await MainActor.run {
                StartupWaterfall.shared.mark("DeferredInit (total)")
                // ⚡️ Battery: MainThreadWatchdog runs a 500ms-loop thread and
                // ProductionFPSMonitor schedules a CADisplayLink at 60Hz —
                // both are development instruments, not production telemetry.
                // Gate to DEBUG so release builds don't burn battery doing
                // work no one reads. MetricKit covers real-world crashes.
                #if DEBUG
                MainThreadWatchdog.shared.start()
                ProductionFPSMonitor.shared.start()
                #endif
                _ = MetricKitSubscriber.shared
                HapticManager.shared.prepareAll()

                #if DEBUG
                SessionLogManager.shared.checkForCrashLog()
                #endif

                StartupWaterfall.shared.end("DeferredInit (total)")
            }
            
            await MainActor.run {
                StartupCoordinator.shared.beginStartupSequence()
            }
            
            AppLogger.info("✅ [PERF] Performance optimizations initialized (watchdog + MetricKit + FPS monitor)", category: .general)
        }
        
        Task.detached(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(500))
            CrashReportingService.shared.initialize()
            VideoThumbnailService.shared.prewarmCDNConnection()
            _ = GenderFilterService.shared
            _ = VideoPlaybackEngine.shared
        }
        
        // ═══════════════════════════════════════════════════════════════
        // STAGED STARTUP PIPELINE
        // Stage 1 (0.5s): StartupCache — lightweight user stats for Dashboard
        // Stage 2 (3s):   TabPreloader — background data for other tabs
        // Stage 3 (8s):   Intelligence — learning engine, mappings, etc.
        // ═══════════════════════════════════════════════════════════════
        
        Task(priority: .userInitiated) {
            let context = PersistenceController.shared.container.viewContext
            
            await StartupWaterfall.shared.measure("StartupCache.warmUp") {
                await StartupCache.shared.warmUp(context: context)
            }
            
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3s
            
            await StartupWaterfall.shared.measure("TabPreloader.beginPreloading") {
                await TabPreloader.shared.beginPreloading(context: context)
            }
        }
        
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
            AppLogger.debug("FAST STARTUP enabled - skipping heavy cloud syncs", category: .general)
        }
        #endif
        
        // iOS 26+: Let Liquid Glass handle bar styling automatically.
        // Pre-iOS 26: Force transparent nav bars for our custom dark theme.
        if #available(iOS 26, *) {
            UINavigationBar.appearance().isTranslucent = true
        } else {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithTransparentBackground()
            appearance.backgroundColor = UIColor.clear
            appearance.shadowColor = UIColor.clear
            UINavigationBar.appearance().standardAppearance = appearance
            UINavigationBar.appearance().compactAppearance = appearance
            UINavigationBar.appearance().scrollEdgeAppearance = appearance
            UINavigationBar.appearance().backgroundColor = UIColor.clear
            UINavigationBar.appearance().isTranslucent = true
            
            UIView.appearance(whenContainedInInstancesOf: [UIWindow.self]).backgroundColor = UIColor.clear
        }
        
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
            AppLogger.warning("Memory warning - cleared video prefetch cache", category: .general)
        }
        
        // 📺 ATT + AdMob: Request tracking authorization then init SDK.
        // ATT dialog requires the app to be active, so we delay slightly
        // and check applicationState before presenting.
        #if DEBUG
        if !FAST_STARTUP_MODE {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3.0))
                guard !Task.isCancelled else { return }
                guard UIApplication.shared.applicationState == .active else {
                    AppLogger.debug("App not active yet, deferring ATT request", category: .general)
                    return
                }
                if AdManager.shared.adsEnabled {
                    AppLogger.debug("Requesting ATT and pre-warming AdMob SDK...", category: .general)
                    AdManager.shared.requestTrackingAndInitialize()
                }
            }
        } else {
            AppLogger.debug("FAST STARTUP - Skipping AdMob pre-warm", category: .general)
        }
        #else
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3.0))
            guard !Task.isCancelled else { return }
            guard UIApplication.shared.applicationState == .active else {
                AppLogger.debug("App not active yet, deferring ATT request", category: .general)
                return
            }
            if AdManager.shared.adsEnabled {
                AppLogger.debug("Requesting ATT and pre-warming AdMob SDK...", category: .general)
                AdManager.shared.requestTrackingAndInitialize()
            }
        }
        #endif
        
        // 🧠 Initialize Exercise Intelligence Engine and Mapping Service
        // DELAYED: Don't block app startup - initialize after a delay
        #if DEBUG
        if !FAST_STARTUP_MODE {
            scheduleIntelligenceInit()
        } else {
            AppLogger.debug("FAST STARTUP - Skipping intelligence engine initialization", category: .general)
        }
        #else
        scheduleIntelligenceInit()
        #endif
    }
    
    /// ⚡️ PERFORMANCE: Coordinated startup sequence
    /// Intelligence init is HEAVY (10+ seconds). Defer until app is fully settled.
    private func scheduleIntelligenceInit() {
        Task { @MainActor in
            StartupCoordinator.shared.onPhaseComplete(.intelligence) {
                Task.detached(priority: .background) {
                    await performIntelligenceInit()
                }
            }
        }
    }
    
    
    @State private var showCoreDataFatalError = false
    
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
            // MARK: - Core Data Fatal Error (store cannot load at all)
            .onReceive(NotificationCenter.default.publisher(for: .coreDataLoadFailed)) { _ in
                showCoreDataFatalError = true
            }
            .alert("Unable to Load Data", isPresented: $showCoreDataFatalError) {
                Button("Try Again") {
                    // Force quit and relaunch is the safest recovery
                    fatalError("Core Data fatal failure — forcing app restart for clean state")
                }
                Button("Contact Support", role: .cancel) {
                    shakeManager.showBugReportSheet = true
                }
            } message: {
                Text("The app's local database could not be loaded. Please try restarting the app. If the problem persists, contact support via the bug report tool.")
            }
                .task {
                    // Wrap whole startup in signpost so Instruments + performance_metrics
                    // can trend cold-start p50/p95/p99. slowThreshold kept generous
                    // (5s) because first-run devices legitimately take longer.
                    let launchState = PerformanceSignposts.begin(.appLaunch)
                    defer { PerformanceSignposts.end(launchState, slowThresholdMs: 5_000) }

                    let startupStart = CFAbsoluteTimeGetCurrent()

                    // Check for Core Data fatal failure (notification may fire before view is ready)
                    if PersistenceController.storeLoadFailed {
                        showCoreDataFatalError = true
                    }

                    // FAST AUTH: Verify session only (<200ms). Dashboard renders from cached Core Data.
                    // Cloud sync is deferred so the UI is interactive immediately.
                    let authState = PerformanceSignposts.begin(.authSessionRecovery)
                    let authStart = CFAbsoluteTimeGetCurrent()
                    await supabaseManager.checkAuthOnly()
                    let authMs = Int((CFAbsoluteTimeGetCurrent() - authStart) * 1000)
                    PerformanceSignposts.end(authState, slowThresholdMs: 2_000)
                    AppLogger.info("[STARTUP] checkAuthOnly completed in \(authMs)ms", category: .performance)
                    
                    // UI-critical post-auth work (keep minimal — limitations RPC was ~1s+ and blocked first-frame interactivity)
                    if supabaseManager.isAuthenticated {
                        SessionLogManager.shared.log(.info, category: .profile, message: "User authenticated", metadata: [
                            "user_id": supabaseManager.currentUser?.id ?? "unknown"
                        ])
                        
                        await pushNotificationService.registerForPushNotifications()
                    }
                    
                    notificationManager.checkAuthorizationStatus()
                    if notificationManager.isAuthorized {
                        notificationManager.scheduleAllNotifications()
                    }
                    
                    // Mark critical path complete — UI is now interactive
                    let criticalMs = Int((CFAbsoluteTimeGetCurrent() - startupStart) * 1000)
                    AppLogger.info("[STARTUP] Critical path complete in \(criticalMs)ms (auth: \(authMs)ms)", category: .performance)
                    StartupCoordinator.shared.markPhaseComplete(.critical)

                    // Cluster I: start the performance metrics uploader.
                    // Drains the `PerformanceSignposts.pendingMetrics` queue
                    // into Supabase every 30s (+ once on background). No-op
                    // until the 20260514 migration is applied to the env.
                    PerformanceMetricsUploader.shared.start()
                    
                    // Deferred: injury/limitation rows from Supabase — safe after critical; generator uses empty list until loaded
                    if supabaseManager.isAuthenticated {
                        Task {
                            let limStart = CFAbsoluteTimeGetCurrent()
                            await LimitationsService.shared.fetchUserLimitations()
                            let limMs = Int((CFAbsoluteTimeGetCurrent() - limStart) * 1000)
                            AppLogger.info("[STARTUP] fetchUserLimitations completed in \(limMs)ms (deferred)", category: .performance)
                        }
                    }
                    
                    // DEFERRED CLOUD SYNC: Runs after UI is interactive.
                    // Core Data already has cached data from previous sessions.
                    if supabaseManager.isAuthenticated {
                        Task {
                            try? await Task.sleep(for: .seconds(3))
                            guard !Task.isCancelled else { return }
                            
                            let syncStart = CFAbsoluteTimeGetCurrent()
                            await supabaseManager.syncAllDataFromCloud()
                            let syncMs = Int((CFAbsoluteTimeGetCurrent() - syncStart) * 1000)
                            AppLogger.info("[STARTUP] syncAllDataFromCloud completed in \(syncMs)ms", category: .performance)
                            
                            if PersistenceController.storeWasReset {
                                PersistenceController.storeWasReset = false
                                persistenceController.cleanupStoreBackup()
                                AppLogger.info("Store reset auto-recovered via cloud sync — user unaffected", category: .general)
                            }
                            
                            await MainActor.run {
                                StartupCoordinator.shared.markPhaseComplete(.essential)
                            }
                        }
                        
                        // Non-blocking post-auth services (don't hold up the task chain)
                        Task {
                            realtimeService.setupDefaultCallbacks()
                            await realtimeService.connect()
                            await supabaseManager.updateLastLogin()
                            await AdvancedSessionLogger.shared.checkIfEnabled()
                        }
                        
                        Task.detached(priority: .background) {
                            await SupabaseManager.shared.syncAllIntegrationStatuses()
                        }
                    } else {
                        // No auth — no sync needed, mark essential immediately
                        StartupCoordinator.shared.markPhaseComplete(.essential)
                    }
                    
                    // Run off the main task chain — does not need to block startup
                    Task { await checkForComebackReminder() }
                    
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
                    AppLogger.debug("OAuthCallback notification received!", category: .auth)
                    if let url = notification.object as? URL {
                        AppLogger.debug("Processing OAuth callback — URL: \(url.absoluteString), fragment: \(url.fragment ?? "none")", category: .auth)
                        Task {
                            do {
                                let (isNewUser, socialUsername) = try await supabaseManager.handleOAuthCallback(url: url)
                                AppLogger.info("OAuth callback handled successfully (new user: \(isNewUser), email: \(supabaseManager.currentUser?.email ?? "nil"))", category: .auth)
                                
                                // Force UI update and store data on main thread
                                await MainActor.run {
                                    // Store social username for onboarding pre-fill (Facebook/Instagram)
                                    if let username = socialUsername, isNewUser {
                                        UserDefaults.standard.set(username, forKey: "pending_social_username")
                                        AppLogger.debug("Stored social username for onboarding: @\(username)", category: .auth)
                                    }
                                    
                                    // Store OAuth-provided name for onboarding BEFORE posting notification
                                    if isNewUser {
                                        if let fullName = supabaseManager.currentUser?.userMetadata["full_name"] as? String, !fullName.isEmpty {
                                            UserDefaults.standard.set(fullName, forKey: "pending_oauth_name")
                                            AppLogger.debug("Stored OAuth name (full_name) for onboarding: \(fullName)", category: .auth)
                                        } else if let name = supabaseManager.currentUser?.userMetadata["name"] as? String, !name.isEmpty {
                                            UserDefaults.standard.set(name, forKey: "pending_oauth_name")
                                            AppLogger.debug("Stored OAuth name (name) for onboarding: \(name)", category: .auth)
                                        }
                                        
                                        // Also store email for pre-fill
                                        if let email = supabaseManager.currentUser?.email, !email.isEmpty {
                                            UserDefaults.standard.set(email, forKey: "pending_oauth_email")
                                            AppLogger.debug("Stored OAuth email for onboarding: \(email)", category: .auth)
                                        }
                                    }
                                    
                                    UserManager.shared.reloadCurrentUser()
                                    
                                    // Post notification to trigger onboarding navigation for new users
                                    // AFTER storing the name data
                                    if isNewUser {
                                        AppLogger.debug("New user - posting notification to start onboarding (stored name: \(UserDefaults.standard.string(forKey: "pending_oauth_name") ?? "nil"))", category: .auth)
                                        NotificationCenter.default.post(
                                            name: Notification.Name("OAuthNewUserNeedsOnboarding"),
                                            object: nil
                                        )
                                    }
                                }
                            } catch {
                                AppLogger.error("OAuth callback error: \(error.localizedDescription)", category: .auth)
                            }
                        }
                    }
                }
                .onOpenURL { url in
                    // Handle deep link URLs
                    AppLogger.debug("App opened with URL: \(url.absoluteString) (scheme: \(url.scheme ?? "none"), host: \(url.host ?? "none"), fragment: \(url.fragment ?? "none"))", category: .general)
                    
                    let scheme = url.scheme?.lowercased() ?? ""
                    
                    // Handle our custom scheme (fit33://)
                    if scheme == "fit33" {
                        // Direct OAuth callback handling (highest priority)
                        if url.host?.lowercased() == "login-callback" {
                            AppLogger.debug("OAuth callback detected - posting notification directly", category: .auth)
                            NotificationCenter.default.post(name: Notification.Name("OAuthCallback"), object: url)
                            return
                        }
                        
                        // Use the DeepLinkManager to route
                        if DeepLinkManager.shared.handleURL(url) {
                            AppLogger.info("Deep link handled by DeepLinkManager", category: .general)
                            return
                        }
                    }
                    
                    // Legacy: Handle old gofit scheme
                    if scheme == "gofit" {
                        // Handle different deep link paths
                        if url.host == "running" {
                            // Deep link from Live Activity - navigate to running view
                            AppLogger.debug("Deep link to running workout", category: .general)
                            DeepLinkManager.shared.pendingDestination = .running
                            return
                        }
                        
                        // Handle OAuth callback
                        Task {
                            do {
                                let (isNewUser, socialUsername) = try await supabaseManager.handleOAuthCallback(url: url)
                                AppLogger.info("OAuth callback handled successfully (new user: \(isNewUser))", category: .auth)
                                
                                // Store social username for onboarding pre-fill (Facebook/Instagram)
                                if let username = socialUsername, isNewUser {
                                    UserDefaults.standard.set(username, forKey: "pending_social_username")
                                    AppLogger.debug("Stored social username for onboarding: @\(username)", category: .auth)
                                }
                                
                                // Force UI update after successful OAuth
                                await MainActor.run {
                                    UserManager.shared.reloadCurrentUser()
                                }
                            } catch {
                                AppLogger.error("OAuth callback error: \(error.localizedDescription)", category: .auth)
                            }
                        }
                        return
                    }
                    
                    // Handle universal links (https://fit33.app/...)
                    if scheme == "https" {
                        if DeepLinkManager.shared.handleURL(url) {
                            AppLogger.info("Universal link handled", category: .general)
                            return
                        }
                    }
                    
                    AppLogger.warning("Unhandled URL: \(url.absoluteString)", category: .general)
                }
                .onChange(of: scenePhase) { oldPhase, newPhase in
                    switch newPhase {
                    case .active:
                        SessionLogManager.shared.log(.info, category: .session, message: "App became active")
                        #if DEBUG
                        MainThreadWatchdog.shared.resume()
                        ProductionFPSMonitor.shared.start()
                        #endif
                        
                        // ═══ IMMEDIATE (main thread, sync) ═══
                        NotificationManager.shared.performSmartCheck()
                        NotificationManager.shared.clearBadge() // Clear app icon badge immediately on open
                        WorkoutManager.shared.checkWorkoutStateOnForeground()
                        HealthKitManager.shared.checkAuthorizationStatus()
                        HealthKitService.shared.checkAuthorizationStatus()

                        // Dashboard WHOOP widget must reflect latest recovery/strain/sleep
                        // every time the user opens the app. Both `HealthDataService.syncAllHealthData`
                        // and `WhoopService.syncAllData` have 5-minute throttles, so run a
                        // dedicated force sync in parallel with the main coordinated Task below.
                        if WhoopService.shared.isConnected {
                            Task(priority: .userInitiated) {
                                await WhoopService.shared.syncAllData(force: true)
                            }
                        }
                        
                        // ═══ FOREGROUND TASKS (single coordinated Task) ═══
                        // Consolidate into ONE Task to prevent 7+ concurrent Tasks
                        // competing for CPU on every foreground event. Whole
                        // block wrapped in signpost so Cluster A hangs can be
                        // traced by a single `app.foreground` interval.
                        Task {
                            let fgState = PerformanceSignposts.begin(.appForeground)
                            defer { PerformanceSignposts.end(fgState, slowThresholdMs: 4_000) }

                            if !supabaseManager.isAuthenticated {
                                await supabaseManager.recoverSessionIfNeeded()
                            }
                            guard supabaseManager.isAuthenticated else { return }

                            await supabaseManager.recordLastActive()

                            // Priority 1: Reconnect realtime (instant social updates)
                            if !realtimeService.isConnected {
                                realtimeService.setupDefaultCallbacks()
                                await realtimeService.connect()
                            }
                            
                            // Priority 2: Refresh actionable social items immediately
                            // These must load fast so user sees friend requests / challenge invites instantly
                            async let pendingRequests: () = FriendService.shared.fetchPendingRequests()
                            async let pendingInvites: () = ChallengeService.shared.fetchPendingInvites()
                            async let privateInvites: () = PrivateChallengeService.shared.fetchPendingInvites()
                            async let newWorkouts: () = FriendService.shared.checkForNewWorkouts()
                            _ = await (pendingRequests, pendingInvites, privateInvites, newWorkouts)
                            
                            // Priority 3: Health sync FIRST so HealthKit values are fresh
                            // (must run BEFORE community/private refresh so leaderboard data is current)
                            // Snapshot which challenge types were loaded BEFORE health sync.
                            // HealthDataService.syncAllSourcesToChallenges() skips empty services,
                            // so we only re-sync after refresh for services that were empty.
                            let hadCommunity = !CommunityChallengeService.shared.myChallenges.isEmpty
                            let hadPrivate = !PrivateChallengeService.shared.myChallenges.isEmpty
                            await HealthDataService.shared.syncAllHealthData()
                            
                            // Priority 4: Community + Private challenge leaderboards (now has up-to-date health data)
                            async let communityRefresh: () = CommunityChallengeService.shared.refreshAll(force: false)
                            async let privateRefresh: () = PrivateChallengeService.shared.refreshAll(force: false)
                            _ = await (communityRefresh, privateRefresh)
                            
                            // Priority 4.5: Only re-sync tracking for services that were empty during
                            // HealthDataService's sync (challenges weren't loaded yet).
                            if !hadCommunity && !CommunityChallengeService.shared.myChallenges.isEmpty {
                                await CommunityChallengeService.shared.syncAllTrackingToCommunityChallenges()
                            }
                            if !hadPrivate && !PrivateChallengeService.shared.myChallenges.isEmpty {
                                await PrivateChallengeService.shared.syncAllTrackingToPrivateChallenges()
                            }
                            
                            // Priority 5: Background work (lower urgency)
                            await pushNotificationService.recheckAndRegister()
                            pushNotificationService.performTokenHealthCheck()
                            await DailyResetService.shared.checkAndPerformDailyResetIfNeeded()
                            
                            // Priority 6: Profile sync (only if needed)
                            if UserManager.shared.hasCompletedOnboarding {
                                try? await UserManager.shared.syncProfileToCloud()
                            }
                            
                            // Priority 7: Update badge with real counts now that data is fresh
                            await NotificationManager.shared.updateBadgeCount()

                            // Priority 8 (Sprint 2 Q2-34): drain any queued cloud writes
                            // that failed while offline / during a previous finish.
                            await MainActor.run { CloudSyncRetryQueue.shared.drainIfDue() }
                            
                            // Priority 9 (2026-04-20): silent-push opponent wake.
                            // Once our own data is fresh on the server, poke our
                            // opponents' devices so their HealthKit / meal /
                            // hydration data syncs too — meaning we see the most
                            // up-to-date numbers on the very next refresh. The
                            // edge function applies a 15-min/recipient server
                            // throttle; this call is also device-debounced to 60s.
                            await ChallengeOpponentWakeService.shared.requestWake(trigger: .foreground)
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
                        #if DEBUG
                        MainThreadWatchdog.shared.pause()
                        ProductionFPSMonitor.shared.stop()
                        #endif
                        AdvancedSessionLogger.shared.deactivate()
                        SessionLogManager.shared.log(.info, category: .session, message: "App entered background")
                        // 🔧 DEV: Mark clean shutdown before going to background
                        #if DEBUG
                        SessionLogManager.shared.markCleanShutdown()
                        #endif
                        // End session when app goes to background (logs cleared unless bug report pending)
                        SessionLogManager.shared.endSession()
                        
                        // 📅 Schedule next background challenge sync
                        BackgroundChallengeSyncService.shared.scheduleNextBackgroundSync()
                        
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
    
    private func checkForComebackReminder() async {
        let udDate = UserDefaults.standard.object(forKey: "last_workout_date") as? Date
        
        let context = persistenceController.container.viewContext
        let fetchRequest: NSFetchRequest<User> = User.fetchRequest()
        fetchRequest.fetchLimit = 1
        
        // Use context.perform to avoid blocking the main thread with a sync fetch
        let cdDate: Date? = await withCheckedContinuation { continuation in
            context.perform {
                let users = try? context.fetch(fetchRequest)
                continuation.resume(returning: users?.first?.lastWorkoutDate)
            }
        }
        
        guard let lastWorkout = [udDate, cdDate].compactMap({ $0 }).max() else { return }
        if Calendar.current.isDateInToday(lastWorkout) { return }
        
        let daysSinceLastWorkout = Calendar.current.dateComponents([.day], from: lastWorkout, to: Date()).day ?? 0
            
        if daysSinceLastWorkout >= 3 && daysSinceLastWorkout <= 30 {
            let lastComebackReminder = UserDefaults.standard.object(forKey: "last_comeback_reminder") as? Date
            
            if daysSinceLastWorkout <= 7 {
                if let lastReminder = lastComebackReminder {
                    let daysSinceReminder = Calendar.current.dateComponents([.day], from: lastReminder, to: Date()).day ?? 0
                    if daysSinceReminder < 1 { return }
                }
            } else {
                guard daysSinceLastWorkout == 14 || daysSinceLastWorkout == 30 else { return }
                if let lastReminder = lastComebackReminder {
                    let daysSinceReminder = Calendar.current.dateComponents([.day], from: lastReminder, to: Date()).day ?? 0
                    if daysSinceReminder < 1 { return }
                }
            }
            
            notificationManager.sendComebackReminder(daysAway: daysSinceLastWorkout)
            UserDefaults.standard.set(Date(), forKey: "last_comeback_reminder")
        }
    }
}

// MARK: - Intelligence Init (free function — nonisolated to avoid @MainActor from App protocol)

private func performIntelligenceInit() async {
    HeavyWorkSentinel.shared.beginHeavyWork(reason: "Intelligence initialization")
    defer { HeavyWorkSentinel.shared.endHeavyWork(reason: "Intelligence initialization") }
    
    let wf = StartupWaterfall.shared
    wf.mark("Intelligence (total)")
    
    AppLogger.debug("Starting background intelligence initialization...", category: .general)
    
    // Phase 1 — loadExerciseData is cheap (49ms observed) and consumed by the
    // Workout tab's Recommended section. Run eagerly BEFORE the 10s defer so
    // the Recommended strip isn't blank on first tab visit.
    await CPUProtection.shared.waitForCPUSettled(maxWait: 3.0)
    await wf.measure("Intel: loadExerciseData") {
        ExerciseIntelligenceEngine.shared.loadExerciseData()
    }
    AppLogger.debug("Intelligence engine data loading started", category: .general)
    
    // ═══════════════════════════════════════════════════════════════════════
    // Sprint 2026-04-24 Phase 2: unfettered-first-10s policy
    // ═══════════════════════════════════════════════════════════════════════
    // 1.38 (53) logs showed intelligence running 21s of CPU work starting at
    // t=6s, overlapping with first-time tab init (each tab's LazyTabManager
    // render hits main thread HARD on first visit). Result: 2-3fps sustained
    // drops and 900ms slow tab transitions because 4-5 background tasks were
    // thrashing all cores.
    //
    // Policy: give the user 10 seconds of unfettered CPU after `.intelligence`
    // phase fires and `loadExerciseData` completes. That's typically enough to
    // visit a couple tabs and scroll before the heavy analytical work begins.
    // Each heavy phase then:
    //   (a) waits for CPU + UI idle (no active tab switch / transition)
    //   (b) sleeps 1s between phases (not 500ms) so any gesture the user
    //       started mid-phase gets a full frame budget before next phase starts
    //
    // Invariant: QP #17 (bulk work off main) still holds — this is just
    // additional cooperation with the main-thread animator.
    // ═══════════════════════════════════════════════════════════════════════
    try? await Task.sleep(for: .seconds(10))
    guard !Task.isCancelled else { return }
    
    await CPUProtection.shared.waitForUIIdle(maxWait: 5.0)
    
    // Phase 2 — buildMaps: the biggest CPU consumer (8.2s observed). Has its
    // own per-chunk CPU gate via CPUProtection inside `buildMaps`, plus we now
    // gate the phase start on UI-idle so it never kicks off mid-transition.
    if !CPUProtection.shared.isCPUCritical() {
        await wf.measure("Intel: buildMaps") {
            let cachedDTOs = try? await SupabaseManager.shared.fetchAllExercisesDeduped()
            await ExerciseMappingService.shared.buildMaps(prefetchedExercises: cachedDTOs)
        }
        AppLogger.debug("Exercise mapping service initialized", category: .general)
    }
    
    await CPUProtection.shared.waitForUIIdle(maxWait: 3.0)
    try? await Task.sleep(for: .seconds(1))
    
    // Phase 3 — pairingEngine: analyzes 5431 exercises. Observed 2fps sustained
    // drop in 1.38 (53). Gated strictly on CPUCritical (not the looser "too high")
    // so we bail if other work is stealing CPU rather than piling on.
    if !CPUProtection.shared.isCPUCritical() {
        await wf.measure("Intel: pairingEngine") {
            SmartExercisePairingEngine.shared.initialize()
        }
        AppLogger.debug("Smart exercise pairing engine initialized", category: .general)
    }
    
    await CPUProtection.shared.waitForUIIdle(maxWait: 3.0)
    try? await Task.sleep(for: .seconds(1))
    
    // Phase 4 — popularity: 3 sequential network calls (2020ms). Skip if CPU is
    // "too high" (not just critical) since network decode happens on background
    // but JSON deserialization of 100+ exercises still competes for CPU.
    if !CPUProtection.shared.isCPUTooHigh() {
        await wf.measure("Intel: popularity") {
            await ExercisePopularityService.shared.refreshFromServer()
        }
        AppLogger.debug("Exercise popularity data loaded", category: .general)
    }
    
    await CPUProtection.shared.waitForUIIdle(maxWait: 3.0)
    try? await Task.sleep(for: .seconds(1))
    
    if !CPUProtection.shared.isCPUTooHigh() {
        await wf.measure("Intel: collaborative") {
            await CollaborativeLearningEngine.shared.syncGlobalData()
        }
        AppLogger.debug("Collaborative learning engine synced", category: .general)
    }
    
    await CPUProtection.shared.waitForUIIdle(maxWait: 5.0)
    try? await Task.sleep(for: .seconds(2))
    
    // Phase 6 — behaviorAnalysis: 5810ms observed, dominated by the 4698-exercise
    // similarity map build inside UserBehaviorLearningEngine. Hard-gated on
    // CPUCritical — this is the LAST phase and the one we most want to defer
    // past the user's initial session. If user is actively gesturing when we
    // get here, bail entirely; the service reloads next session from cache.
    await CPUProtection.shared.waitForCPUSettled(maxWait: 5.0)
    
    if !CPUProtection.shared.isCPUCritical() {
        await wf.measure("Intel: behaviorAnalysis") {
            let context = PersistenceController.shared.container.viewContext
            await UserBehaviorLearningEngine.shared.analyzeUserBehavior(context: context)
        }
        AppLogger.debug("User behavior learning engine initialized", category: .general)
    } else {
        AppLogger.warning("Skipping behavior analysis - CPU too high (will retry next session)", category: .general)
    }
    
    wf.end("Intelligence (total)")
    
    AppLogger.info("Exercise intelligence systems fully initialized", category: .general)
    
    wf.printWaterfall()
    
    #if DEBUG
    let budget = wf.mainThreadBudgetMs()
    if budget > 5000 {
        AppLogger.warning("[STARTUP AUDIT] FAIL: Main thread budget \(budget)ms exceeds 5000ms target", category: .performance)
    } else {
        AppLogger.info("[STARTUP AUDIT] PASS: Main thread budget \(budget)ms", category: .performance)
    }
    #endif
}
