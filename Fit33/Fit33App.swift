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
    /// for routing; currently handles `challenge_wake` (HK flush),
    /// `strava_activity_new` (recap re-sync) and `challenge_reaction`
    /// (smack-talk widget shout-bubble paint via `SmackTalkWidgetBridge`).
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

    // ⚡️ Cold-start speedup Phase 5 (2026-04-25):
    // Stored-property default values are evaluated in declaration order
    // before `init()`'s body runs. By placing `_coldStartKickoff` BEFORE
    // `persistenceController` / `premiumManager` / every `@StateObject`
    // (each of which lazily forces a singleton's `.shared` and runs its
    // synchronous init on main), we steal a head start of ~200-400ms for
    // the bg pre-decode wave. By the time SwiftUI later evaluates the
    // ContentView body and triggers FriendService.shared / PrivateChallenge
    // / Contacts / Ranking / ProfilePhoto inits on main, their JSON caches
    // are already decoded and `consume…` returns in O(1). Idempotent —
    // safe even if the App struct is re-instantiated.
    private let _coldStartKickoff: Void = StartupCachePreloader.kickoff()

    let persistenceController = PersistenceController.shared
    let premiumManager = PremiumManager.shared
    @StateObject private var supabaseManager = SupabaseManager.shared
    @StateObject private var appearanceManager = AppearanceManager.shared
    @StateObject private var notificationManager = NotificationManager.shared
    @StateObject private var shakeManager = ShakeDetectionManager.shared

    // ⚡️ Cold-start speedup Phase 5.2 (2026-04-25):
    // The four singletons below USED to be `@StateObject` (so their
    // `.shared` was force-initialized during App.init's stored-property
    // default phase, contributing to a measured 980ms gap between
    // `persistence.init.end` and the start of `init()` body).
    // None of them are read in `Fit33App.body`, used as
    // `@EnvironmentObject`, or bound via `$` anywhere. They are only
    // touched inside `.task { … }` / `.onChange { … }` closures that
    // fire AFTER first frame. Demoting them to direct `.shared` access
    // at the call site means their `.init` runs lazily post-first-frame
    // instead of blocking cold start.
    //   - SessionLogManager  (no body refs at all; bring-up Task.detached
    //                         already fires startSession off-main)
    //   - StoreKitManager    (no body refs at all; products load lazily)
    //   - PushNotificationService (only .task closure refs)
    //   - RealtimeService    (only .task / .onChange closure refs)
    
    @Environment(\.scenePhase) private var scenePhase

    /// Single signpost that bridges `Fit33App.init()` start to the moment the
    /// WindowGroup root view first commits a frame. End is fired from
    /// `ContentView.onAppear`. This is the user-visible cold-start latency
    /// metric; the existing `app.launch` signpost measures only the
    /// init-to-task latency, not first-frame paint. Sprint 2026-04-25
    /// (cold-start speedup Phase 3.10).
    @MainActor private static var firstFrameSignpost: PerformanceSignposts.State?
    @MainActor private static var firstFrameLanded = false

    @MainActor
    static func markFirstFrameIfNeeded() {
        guard !firstFrameLanded else { return }
        firstFrameLanded = true
        if let state = firstFrameSignpost {
            PerformanceSignposts.end(state, slowThresholdMs: 1500)
            firstFrameSignpost = nil
        }
    }

    /// Runs `block` immediately if the StartupCoordinator's `.essential` phase
    /// is already complete (warm foreground) or schedules it to run as soon as
    /// `.essential` fires (cold start). Lets cold-start scenePhase wearable
    /// force-syncs avoid piling onto the contended main thread during the
    /// initial 2-3s freeze window. Sprint 2026-04-25 (cold-start Phase 1.6).
    @MainActor
    private static func runOrDeferUntilEssential(_ block: @escaping @Sendable () -> Void) {
        if StartupCoordinator.shared.isPhaseComplete(.essential) {
            block()
        } else {
            StartupCoordinator.shared.onPhaseComplete(.essential) {
                block()
            }
        }
    }

    /// Async helper used by the consolidated startup pipeline (Phase 2.7) to
    /// gate stages on coordinator phases. Returns immediately if the phase
    /// is already complete; otherwise suspends until the phase fires.
    private static func awaitPhase(_ phase: StartupCoordinator.Phase) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            Task { @MainActor in
                if StartupCoordinator.shared.isPhaseComplete(phase) {
                    cont.resume()
                } else {
                    StartupCoordinator.shared.onPhaseComplete(phase) {
                        cont.resume()
                    }
                }
            }
        }
    }

    init() {
        // ═══════════════════════════════════════════════════════════════
        // CRITICAL PATH — Must run before first frame
        // Only the absolute minimum to show UI and satisfy Apple requirements
        // ═══════════════════════════════════════════════════════════════

        // ⚡️ Cold-start Phase 5 (2026-04-25): timestamp the start of init
        // so we can attribute every chunk of pre-first-frame work in the
        // log. By the time `init()`'s body runs, the @StateObject /
        // PersistenceController / PremiumManager property defaults have
        // ALREADY been evaluated (Swift evaluates stored-property defaults
        // in declaration order before the init body). The kickoff for the
        // JSON pre-decoder is hoisted to `_coldStartKickoff` (the FIRST
        // declared property) so it leads everything else.
        let initStart = CFAbsoluteTimeGetCurrent()
        func mark(_ label: String) {
            let ms = Int((CFAbsoluteTimeGetCurrent() - initStart) * 1000)
            AppLogger.info("⏱️ [STARTUP] +\(ms)ms — \(label)", category: .performance)
        }
        mark("init() body started (after @StateObject property inits)")

        // ⚡️ Cold-start Phase 3.10: capture user-visible first-frame latency.
        // Begin here (earliest point in app lifecycle), end from ContentView's
        // first onAppear via `Fit33App.markFirstFrameIfNeeded()`.
        MainActor.assumeIsolated {
            Fit33App.firstFrameSignpost = PerformanceSignposts.begin(.appFirstFrame)
        }

        // ⚡️ Cold-start speedup Phase 1.1 (2026-04-25):
        // Fire auth check BEFORE SwiftUI evaluates `WindowGroup.body`. The
        // previous implementation kicked it off from `WindowGroup.task`,
        // which only runs AFTER first body evaluation — by which time
        // ContentView/MainTabView have already triggered ~10 singleton
        // inits on the main actor (UserManager, VideoStreamingService,
        // FriendService, etc.), starving `await MainActor.run { isAuthenticated = true }`
        // for 2086ms (1.38(55) logs). Firing here lets auth complete while
        // the view tree is still being constructed, eliminating the queue.
        // The `.task` modifier still calls `checkAuthOnly` for backwards
        // compat; SupabaseManager's `inFlightAuthCheckTask` single-flights
        // both callers onto the same task.
        Task(priority: .userInitiated) {
            await SupabaseManager.shared.checkAuthOnly()
        }
        mark("auth Task spawned")

        // BGTaskScheduler.register must be called before app finishes launching
        BackgroundChallengeSyncService.shared.setup()
        mark("BackgroundChallengeSyncService.setup (BGTask register only)")

        // ⚡️ Touch ExerciseLibraryService.shared on the FIRST tick of app init so its
        // preWarmCache() Task.detached runs immediately (bg context fetch + inline bundle seed
        // if Core Data is empty). This guarantees the Exercise Library tab has real cards
        // ready before the user can navigate to it — no "Loading exercises..." state, no
        // grey placeholder cards. See ExerciseLibraryService.preWarmCache() for seed logic.
        _ = ExerciseLibraryService.shared
        mark("ExerciseLibraryService.shared touched")

        // One-time Core Data migration — moved off main thread to prevent startup freeze
        let needsExerciseRefresh = !UserDefaults.standard.bool(forKey: "exercise_lever_fix_applied_v1")
        if needsExerciseRefresh {
            let container = PersistenceController.shared.container
            Task.detached(priority: .userInitiated) {
                // ⚡️ Cold-start sprint 2026-04-26 (async CD load): wait for the
                // store to attach before the delete/seed migration. Without
                // this, the delete-then-seed runs against an unattached store,
                // returning empty results then inserting bundle rows that
                // duplicate the user's actual exercise data once the store
                // attaches.
                await PersistenceController.waitUntilStoreLoaded()
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
                        exercise.muscleGroups = data.muscleGroups as NSArray
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
        
        mark("CD migration check complete")

        // ⚡️ Cold-start speedup Phase 5.1 (2026-04-25):
        // SessionLogManager's first `.shared` access was costing 628ms on
        // main during cold start (observed in 2026-04-25 launch logs:
        // +3ms → +631ms gap was entirely this singleton + its first
        // `startSession()`/`log()` calls. Type metadata realization for
        // a 3200-line final class with hundreds of nested enum cases is
        // expensive on first touch). Push the entire bring-up to a
        // detached utility task — no UI element waits on session logs
        // landing in memory, and the logQueue is internally async
        // anyway so behavior is identical. This frees ~600-900ms of
        // main-thread budget that was happening BEFORE first frame.
        Task.detached(priority: .utility) {
            SessionLogManager.shared.startSession()
            SessionLogManager.shared.log(.info, category: .session, message: "App initializing")
        }
        mark("SessionLogManager bring-up dispatched (off main)")
        
        // ═══════════════════════════════════════════════════════════════
        // CONSOLIDATED STARTUP PIPELINE
        // ⚡️ Cold-start speedup Phase 2.7 (2026-04-25):
        // The previous code spawned three separate `Task.detached` chains
        // (deferred singletons, crash-reporting + video, StartupCache +
        // TabPreloader) plus one `Task` for warm-up. Each chain raced for
        // CPU and main-actor time independently — the deferred singletons
        // chain alone hopped to main twice, contending with body
        // evaluation. Consolidating them into ONE pipeline driven by
        // `StartupCoordinator` phases serializes the heavy work and lets
        // the OS schedule it after first frame has committed.
        //
        // Stage A (immediate, off-main):  StartupCache.warmUp — dashboard
        //                                  needs cachedUserStats early.
        // Stage B (after critical phase): Light singletons + perf monitors
        //                                  (formerly the 500ms-delay chain).
        // Stage C (essential phase):      TabPreloader, crash reporter, video
        //                                  engine — none are dashboard-body
        //                                  critical, so deferred until after
        //                                  the cold-start contention window.
        // ═══════════════════════════════════════════════════════════════

        Task(priority: .userInitiated) {
            // Wire up the phase chain (essential → intelligence → background
            // and the 8s safety timer) BEFORE anything else awaits a phase.
            // Cheap; just registers handlers on the coordinator's MainActor.
            await MainActor.run {
                StartupCoordinator.shared.beginStartupSequence()
            }

            let context = PersistenceController.shared.container.viewContext

            // Stage A — runs immediately. StartupCache uses bgContext +
            // single MainActor publish (Phase 1.2) so this no longer
            // contends with first-frame work.
            await StartupWaterfall.shared.measure("StartupCache.warmUp") {
                await StartupCache.shared.warmUp(context: context)
            }

            // Stage B — light singletons + perf monitors. Wait for the
            // critical phase so the perf instruments don't sample during
            // the cold-start freeze (skewing baselines). On warm
            // foregrounds .critical fires almost immediately.
            await Self.awaitPhase(.critical)

            _ = MemoryPressureHandler.shared
            _ = TaskThrottler.shared
            _ = CPUProtection.shared
            _ = HeavyWorkSentinel.shared

            await MainActor.run {
                StartupWaterfall.shared.mark("DeferredInit (total)")
                // ⚡️ Battery: MainThreadWatchdog and ProductionFPSMonitor
                // are development instruments only.
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
            AppLogger.info("✅ [PERF] Performance optimizations initialized", category: .general)

            // Stage C — heavy off-main work. Wait for `.essential` so
            // we don't fight `syncAllDataFromCloud` for network/CPU.
            // On warm foreground this is instant.
            await Self.awaitPhase(.essential)

            CrashReportingService.shared.initialize()
            VideoThumbnailService.shared.prewarmCDNConnection()
            _ = GenderFilterService.shared
            _ = VideoPlaybackEngine.shared

            await StartupWaterfall.shared.measure("TabPreloader.beginPreloading") {
                await TabPreloader.shared.beginPreloading(context: context)
            }
        }
        mark("Consolidated startup pipeline scheduled")

        // ⚡️ Cold-start speedup Phase 5.1 (2026-04-25):
        // Version-tracking + retention-metrics block was costing 317ms on
        // main (observed: +631ms → +948ms gap). Pure bookkeeping (Bundle
        // reads, UserDefaults R/W, one SessionLogManager call) — nothing
        // here is needed before first frame. Capture launch wall time
        // synchronously so the bg task computes accurate
        // "days since last session", then offload everything else.
        let launchWallTime = Date()
        Task.detached(priority: .utility) {
            let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
            let currentBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
            let lastVersion = UserDefaults.standard.string(forKey: "last_app_version")
            let lastBuild = UserDefaults.standard.string(forKey: "last_app_build")

            if lastVersion == nil {
                SessionLogManager.shared.logAppFirstLaunch(version: currentVersion, build: currentBuild)
            } else if lastVersion != currentVersion || lastBuild != currentBuild {
                SessionLogManager.shared.logAppUpdated(
                    previousVersion: lastVersion ?? "unknown",
                    newVersion: currentVersion,
                    previousBuild: lastBuild ?? "unknown",
                    newBuild: currentBuild
                )
            }

            UserDefaults.standard.set(currentVersion, forKey: "last_app_version")
            UserDefaults.standard.set(currentBuild, forKey: "last_app_build")

            let sessionCount = UserDefaults.standard.integer(forKey: "total_session_count") + 1
            UserDefaults.standard.set(sessionCount, forKey: "total_session_count")

            let lastSessionTimestamp = UserDefaults.standard.double(forKey: "last_session_timestamp")
            var daysSinceLastSession: Int? = nil
            if lastSessionTimestamp > 0 {
                let lastDate = Date(timeIntervalSince1970: lastSessionTimestamp)
                daysSinceLastSession = Calendar.current.dateComponents([.day], from: lastDate, to: launchWallTime).day
            }
            UserDefaults.standard.set(launchWallTime.timeIntervalSince1970, forKey: "last_session_timestamp")

            SessionLogManager.shared.logSessionStart(
                sessionNumber: sessionCount,
                daysSinceLastSession: daysSinceLastSession,
                totalWorkoutsCompleted: UserDefaults.standard.integer(forKey: "cached_total_workouts")
            )
        }
        mark("Version + session counters bookkeeping dispatched (off main)")

        // Register the custom value transformer for Core Data array handling
        StringArrayValueTransformer.register()
        mark("StringArrayValueTransformer.register")
        
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
        
        mark("UINavigationBar appearance configured")

        // Apply saved appearance setting on launch
        AppearanceManager.shared.applyAppearance()
        mark("AppearanceManager.applyAppearance")

        // Set up notification center delegate
        UNUserNotificationCenter.current().delegate = NotificationManager.shared
        mark("UNUserNotificationCenter delegate set")
        
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

        mark("init() body END (returning to SwiftUI runtime → WindowGroup body next)")
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

    /// ⚡️ Cold-start sprint 2026-04-26 (async Core Data store load):
    /// Tracks whether the persistent store is fully loaded and attached
    /// to the coordinator. Until this flips true, we render a
    /// `LaunchBackground` color overlay (matching the LaunchScreen
    /// asset) instead of `ContentView`. This prevents any
    /// `@FetchRequest` / `viewContext.fetch` from running against an
    /// unloaded store and seeing transient empty results — the
    /// dashboard never sees a "0 workouts" flicker.
    ///
    /// Initialized by reading the static flag (in case the store
    /// loaded BEFORE the body first evaluated — unlikely on cold
    /// start with async loading, but possible on tab/scene restart),
    /// and updated via the `.coreDataDidLoad` notification posted by
    /// `PersistenceController.completeLoad`.
    @State private var isCoreDataReady = PersistenceController.isStoreLoaded

    var body: some Scene {
        WindowGroup {
            ZStack {
                // Always-on launch-color base layer — guarantees no white
                // flash even during the brief moment between iOS dismissing
                // the LaunchScreen and our SwiftUI hierarchy fully painting.
                Color("LaunchBackground")
                    .ignoresSafeArea()

                if isCoreDataReady {
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
                }
            }
            .sheet(isPresented: $shakeManager.showBugReportSheet) {
                BugReportView()
            }
            // ⚡️ Async Core Data: flip the gate when the store finishes loading.
            .onReceive(NotificationCenter.default.publisher(for: .coreDataDidLoad)) { _ in
                if !isCoreDataReady {
                    isCoreDataReady = true
                }
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

                    // 2026-04-28 OAuth-disconnect post-mortem: dump the
                    // persistent `OAuthAuditLog` once per cold start.
                    // Captures every WHOOP/Oura/Strava/Fitbit lifecycle
                    // event from the previous session(s) — connect,
                    // disconnect-with-reason, refresh success/failure,
                    // keychain probe outcomes — so the FIRST session log
                    // after a "WHOOP just disconnected" report contains
                    // the breadcrumb trail that explains why. Only logs
                    // when entries exist; silent otherwise.
                    let auditLines = OAuthAuditLog.dump()
                    if !auditLines.isEmpty {
                        AppLogger.info("[OAUTH_AUDIT] Replaying \(auditLines.count) prior breadcrumb(s) from persistent ring buffer:", category: .auth)
                        for line in auditLines.prefix(20) {
                            AppLogger.info("[OAUTH_AUDIT] \(line)", category: .auth)
                        }
                    }
                    
                    // UI-critical post-auth work (keep minimal — limitations RPC was ~1s+ and blocked first-frame interactivity)
                    if supabaseManager.isAuthenticated {
                        SessionLogManager.shared.log(.info, category: .profile, message: "User authenticated", metadata: [
                            "user_id": supabaseManager.currentUser?.id ?? "unknown"
                        ])
                        
                        await PushNotificationService.shared.registerForPushNotifications()

                        // Realtime Widget Server Pull, Phase 5 (2026-04-26):
                        // Subscribe to the widget extension's Darwin
                        // notification so a successful widget-side
                        // direct Supabase pull (timeline tick or
                        // refresh-button tap) triggers a main-app
                        // round-trip back to `get_active_challenges`.
                        // Lightweight — single CFNotificationCenter
                        // observer registration. Idempotent across
                        // auth-state flips.
                        ActiveChallengeWidgetBridge.startWidgetPullListener()

                        // Realtime Widget Server Pull, Phase 8e (2026-04-26):
                        // Activate the WCSession bridge so the paired
                        // Apple Watch (if installed) receives the
                        // current active-challenge list. The watch app
                        // uses this to know which challenge IDs to
                        // log against from its HealthKit observers.
                        // Activation is a no-op when no watch is
                        // paired or the companion app isn't installed
                        // (PE invariant — phones-only path remains the
                        // default writer of last resort).
                        PhoneToWatchSyncBridge.shared.activate()
                        // Initial push of whatever's already loaded.
                        // Subsequent updates flow through the
                        // ChallengeService publisher observer below.
                        PhoneToWatchSyncBridge.shared.sendActiveChallenges(
                            ChallengeService.shared.activeChallenges
                        )
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
                            RealtimeService.shared.setupDefaultCallbacks()
                            await RealtimeService.shared.connect()
                            await supabaseManager.updateLastLogin()
                            await AdvancedSessionLogger.shared.checkIfEnabled()
                            // New User Journey Tracker — 72h auto-enrolled
                            // high-resolution behavioral telemetry. Idempotent;
                            // safely re-callable on every cold start.
                            await NewUserJourneyTracker.shared.checkEnrollmentAndActivate()
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
                        // Re-activate the new-user journey tracker if the user
                        // is still inside their 72h window. Idempotent — the
                        // tracker no-ops when already active. Safe even if
                        // the user has aged out (server returns is_active=false
                        // and the tracker stays dormant).
                        Task { await NewUserJourneyTracker.shared.checkEnrollmentAndActivate() }
                        #if DEBUG
                        MainThreadWatchdog.shared.resume()
                        ProductionFPSMonitor.shared.start()
                        #endif
                        
                        // ═══ IMMEDIATE (main thread, sync) ═══
                        NotificationManager.shared.performSmartCheck()
                        NotificationManager.shared.clearBadge() // Clear app icon badge immediately on open
                        // Smack-talk widget shout bubble is "show until the
                        // user opens the app" — wipe the slot the moment
                        // we go active so the comic-book "Do better!"
                        // yelling out of the type emoji disappears from
                        // the home-screen widget. Runs on every foreground
                        // (cheap — App Group write + WidgetCenter reload
                        // only when there's actually a payload to clear).
                        SmackTalkWidgetBridge.clear()
                        WorkoutManager.shared.checkWorkoutStateOnForeground()
                        HealthKitManager.shared.checkAuthorizationStatus()
                        HealthKitService.shared.checkAuthorizationStatus()

                        // Dashboard WHOOP / Oura widgets must reflect the latest recovery/strain/sleep
                        // readings every time the user opens the app. Both `HealthDataService.syncAllHealthData`
                        // and each wearable service's `syncAllData` have 5-minute throttles, so run a
                        // dedicated force sync in parallel with the main coordinated Task below.
                        // BGTask path (`BackgroundChallengeSyncService.performSyncBody`) also refreshes
                        // WHOOP + Oura — so if iOS woke us recently there's no network cost; the
                        // service-level `isSyncing` guard coalesces with any in-flight sync.
                        //
                        // CRITICAL: call `refreshConnectionState()` BEFORE reading `isConnected`.
                        // If iOS woke the app via BGTask while the device was locked, the
                        // wearable singleton was constructed with an unreadable keychain →
                        // `isConnected` got stuck at `false`. Re-reading the keychain on
                        // foreground (now that the device is unlocked) repairs that state so
                        // the dashboard widgets reliably appear on every cold start / resume.
                        WhoopService.shared.refreshConnectionState()
                        OuraService.shared.refreshConnectionState()
                        StravaService.shared.refreshConnectionState()

                        // Forward local OAuth audit breadcrumbs to
                        // `dev_session_logs` so "WHOOP/Oura disconnected
                        // with no log line" reports are investigable from
                        // the cloud alone (no device pull required). The
                        // flush is watermarked — it only ships entries
                        // newer than the last flush — so cost is bounded
                        // even on long-running sessions. 2026-04-29:
                        // landed alongside the atomic-keychain rewrite
                        // (KeychainHelper.SecItemUpdate-first) and the
                        // saveAndVerify wrapper for access-token writes.
                        OAuthAuditLog.flushToDevLog()

                        // ⚡️ Cold-start speedup Phase 1.6 (2026-04-25):
                        // On cold start, gate the wearable force-syncs behind
                        // `StartupCoordinator.essential`. Each force-sync spawns
                        // 4–8 network calls, JSON decoders, Core Data writes,
                        // and a `ReadinessService.recompute` — fired together
                        // they routinely added 800–1200ms of CPU contention to
                        // the cold-start window. After `.essential` is complete
                        // (~3–5s post-launch), `runOrDeferUntilEssential` runs
                        // its handler immediately, so warm foregrounds keep the
                        // existing instant-sync behavior. Internal `isSyncing`
                        // throttles + 5-min `syncThrottleInterval` ensure no
                        // duplicate syncs happen.
                        if WhoopService.shared.isConnected {
                            Self.runOrDeferUntilEssential {
                            Task(priority: .userInitiated) {
                                await WhoopService.shared.syncAllData(force: true)
                                // Bug-Intel 2026-04-25 Report 7 (08bcb9e0).
                                // The fire-and-forget WHOOP force-sync above runs in
                                // parallel with the coordinated foreground Task below,
                                // which calls HealthDataService.syncAllHealthData →
                                // ReadinessService.recompute. Inside that path,
                                // syncWhoopData(force: false) hits the WhoopService
                                // `isSyncing` guard (set true by the line above) and
                                // returns early — so recompute runs against the OLD
                                // @Published WHOOP state and writes a stale readiness
                                // band to the dashboard. Snapshot from the bug report
                                // showed whoopLastSyncAgeSec=29s but readiness was
                                // computed 38s earlier (i.e. before the force-sync's
                                // fresh recovery score arrived). Re-running recompute
                                // here, AFTER WHOOP's @Published state has been
                                // refreshed, fixes "first launch shows stale WHOOP
                                // metrics" without introducing a sync recursion (the
                                // recompute path is read-only — it never re-triggers
                                // wearable syncs per ReadinessService invariant #33).
                                await ReadinessService.shared.recompute(force: true)
                            }
                            }
                        }
                        if OuraService.shared.isConnected {
                            Self.runOrDeferUntilEssential {
                            Task(priority: .userInitiated) {
                                await OuraService.shared.syncAllData(force: true)
                                // Same race as the WHOOP path above — Oura's force
                                // sync also runs in parallel with HealthDataService,
                                // and Oura is the fallback readiness source when
                                // WHOOP isn't connected. Recompute here so dashboard
                                // recovery + sleep widgets reflect the freshly-pulled
                                // Oura readings on first launch / scenePhase resume.
                                await ReadinessService.shared.recompute(force: true)
                            }
                            }
                        }
                        // Strava parity with WHOOP / Oura — force-sync on every
                        // foreground so the dashboard widget + cardio section
                        // always reflect the latest activities. Internal
                        // 5-minute throttle (`syncThrottleInterval`) coalesces
                        // rapid scenePhase flicker. Auto-refreshes the
                        // access token first if it expires within 5 min.
                        if StravaService.shared.isConnected {
                            Self.runOrDeferUntilEssential {
                            Task(priority: .userInitiated) {
                                await StravaService.shared.syncActivities(daysBack: 30, force: true)
                            }
                            // 60-day inactivity guard — if Strava revoked
                            // tokens during a long absence, the next probe
                            // will surface that and disconnect cleanly.
                            Task(priority: .background) {
                                await StravaService.shared.evaluateInactivityWindow()
                            }
                            }
                        }
                        
                        // ═══ FOREGROUND TASKS (single coordinated Task) ═══
                        // Consolidate into ONE Task to prevent 7+ concurrent Tasks
                        // competing for CPU on every foreground event. Whole
                        // block wrapped in signpost so Cluster A hangs can be
                        // traced by a single `app.foreground` interval.
                        //
                        // Sprint 2026-04-24 Phase 4 (N3): restructured foreground
                        // pipeline from a 14-step sequential chain (6035ms observed
                        // in 1.38 (55) logs) into "blocking critical path" +
                        // "fire-and-forget housekeeping".
                        //
                        // BLOCKING (user-facing data freshness):
                        //   auth recover → realtime reconnect → social fanout →
                        //   health sync → challenge refresh
                        // FIRE-AND-FORGET (no UI waits on any of these):
                        //   push re-registration, daily-reset check, profile
                        //   sync, badge count, retry-queue drain, opponent wake
                        Task {
                            let fgState = PerformanceSignposts.begin(.appForeground)
                            defer { PerformanceSignposts.end(fgState, slowThresholdMs: 4_000) }

                            if !supabaseManager.isAuthenticated {
                                await supabaseManager.recoverSessionIfNeeded()
                            }
                            guard supabaseManager.isAuthenticated else { return }

                            // recordLastActive is a one-shot UPSERT, fire-and-forget.
                            Task { await supabaseManager.recordLastActive() }

                            // ─── Priority 1: Realtime reconnect-if-stale ───
                            //
                            // Sync-triage 2026-04-28 — the previous
                            // `if !RealtimeService.shared.isConnected` gate was
                            // a no-op for returning users: when iOS suspends
                            // the app, the WebSocket dies but `isConnected`
                            // (a Swift `@Published` flag) stays `true` because
                            // there is no socket-close callback wired to it.
                            // Result: `connect()` is skipped, the Phase 3
                            // post-connect resync never fires, and the user
                            // returns to a stale dashboard while realtime
                            // events from background never arrive.
                            //
                            // Use the new `forceReconnectIfStale()` helper —
                            // it tears down + re-subscribes ONLY when the
                            // last realtime event is older than 30s (or
                            // missing), which is the cheapest reliable
                            // signal that the channel is dead. Inside that
                            // helper, `connect()`'s 10s lockout is bypassed
                            // when stale so the resync actually runs.
                            RealtimeService.shared.setupDefaultCallbacks()
                            await RealtimeService.shared.forceReconnectIfStale()

                            // ─── Priority 2: Unconditional social re-sync ───
                            //
                            // 2026-04-28 sync-triage Layer A — replace the
                            // previous "Priority 2 + Phase 3+4 conditional
                            // fallback" with a single unconditional fan-out.
                            //
                            // The earlier design split fetches across two
                            // blocks gated by `!isConnected`. Both gates
                            // were dead-no-ops on returning users (see the
                            // Priority 1 comment), so neither realtime nor
                            // the fallback was rescuing the carousel — the
                            // user sat on stale `@Published` arrays.
                            //
                            // 2026-04-28 sync-triage Layer A.2 — promoted
                            // `ChallengeService.fetchActiveChallenges()`
                            // into this fan-out (slot s10). Previously the
                            // 1v1 active widget on the dashboard AND the
                            // home-screen widget were kept fresh ONLY
                            // indirectly — through realtime
                            // `OWN_DAILY_PROGRESS` / opponent UPDATE events
                            // triggering `throttledChallengeFetch()`. That
                            // chain breaks whenever there's no fresh HK
                            // data to push during HealthData sync (no
                            // event = no refetch) OR an event is missed
                            // during the iOS-killed-socket window. Other
                            // widget-feeding services (group / private /
                            // community) were already explicit here; 1v1
                            // active was the lone gap. `fetchActiveChallenges`
                            // → `cacheActiveChallenges` → `ActiveChallengeWidgetBridge.publish`
                            // → `WidgetCenter.reloadAllTimelines` is the
                            // canonical foreground refresh path for both
                            // surfaces.
                            //
                            // Cost analysis: 10 RPCs in parallel, all
                            // already-coalesced via `RequestCoalescer` and
                            // each guarded by `SupabaseManager.isAuthenticated`
                            // (Data invariant 26). Returning users hit the
                            // realtime resync inside `connect()` first,
                            // so most of these will short-circuit. The
                            // remaining roundtrip (one per pending surface,
                            // server-side `SECURITY DEFINER` RPCs) is the
                            // worst-case 10× ~80ms ≈ <1s of parallel work
                            // for ironclad reliability across every
                            // widget-feeding surface (friend requests,
                            // 1v1 invites, 1v1 sent, 1v1 active, group
                            // active, private invites, private active,
                            // community active, activity feed, received
                            // workouts).
                            //
                            // Carousel + widget data sources covered
                            // (one fetch per `@Published` the dashboard
                            // reads — see `DashboardModels.DashboardNotificationCarousel`
                            // for carousel sources, `DashboardChallengesWrapper`
                            // for the active-challenge widget):
                            //   FriendService.pendingRequests          ← s1
                            //   ChallengeService.pendingInvites        ← s2
                            //   ChallengeService.pendingSentChallenges ← s3
                            //   ChallengeService.activeGroupChallenges ← s4 (group active + invites)
                            //   PrivateChallengeService.pendingInvites ← s5
                            //   PrivateChallengeService.myChallenges   ← s6
                            //   CommunityChallengeService.myChallenges ← s7
                            //   ActivityFeedService.activities         ← s8
                            //   FriendService.receivedWorkouts         ← s9
                            //   ChallengeService.activeChallenges      ← s10 (1v1 widget + home-screen widget)
                            //
                            // s9 routes through `checkForNewWorkouts` (not
                            // bare `fetchReceivedWorkouts`) so the
                            // per-id "new since last check" notification
                            // path stays intact — that's the existing
                            // FriendService behavior the previous
                            // foreground block invoked.
                            async let s1: () = FriendService.shared.fetchPendingRequests()
                            async let s2: () = ChallengeService.shared.fetchPendingInvites()
                            async let s3: () = ChallengeService.shared.fetchPendingSentChallenges()
                            async let s4: () = ChallengeService.shared.fetchActiveGroupChallenges()
                            async let s5: () = PrivateChallengeService.shared.fetchPendingInvites()
                            async let s6: () = PrivateChallengeService.shared.fetchMyChallenges()
                            async let s7: () = CommunityChallengeService.shared.fetchMyChallenges()
                            async let s8: () = ActivityFeedService.shared.fetchFeed()
                            async let s9: () = FriendService.shared.checkForNewWorkouts()
                            async let s10: () = ChallengeService.shared.fetchActiveChallenges()
                            _ = await (s1, s2, s3, s4, s5, s6, s7, s8, s9, s10)
                            
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
                            
                            // ════ Critical blocking path ends here. Remaining work ════
                            // ════ is all fire-and-forget: UI never waits on these.  ════
                            
                            // Push-notification hygiene
                            Task {
                                await PushNotificationService.shared.recheckAndRegister()
                                PushNotificationService.shared.performTokenHealthCheck()
                            }
                            // Daily-reset (midnight-rollover cleanup)
                            Task { await DailyResetService.shared.checkAndPerformDailyResetIfNeeded() }
                            // Profile sync — no UI element waits on this
                            if UserManager.shared.hasCompletedOnboarding {
                                Task { try? await UserManager.shared.syncProfileToCloud() }
                            }
                            // Badge count — updates silently, lag tolerated
                            Task { await NotificationManager.shared.updateBadgeCount() }
                            // Sprint 2 Q2-34: drain any queued cloud writes that failed
                            // while offline / during a previous finish.
                            Task { @MainActor in CloudSyncRetryQueue.shared.drainIfDue() }
                            // Priority 9 (2026-04-20): silent-push opponent wake.
                            // Once our own data is fresh on the server, poke our
                            // opponents' devices so their HealthKit / meal /
                            // hydration data syncs too — meaning we see the most
                            // up-to-date numbers on the very next refresh. The
                            // edge function applies a 15-min/recipient server
                            // throttle; this call is also device-debounced to 60s.
                            // Observed 1856ms in 1.38 (55) logs — always defer.
                            Task { await ChallengeOpponentWakeService.shared.requestWake(trigger: .foreground) }
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
                        NewUserJourneyTracker.shared.deactivate()
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
                            await RealtimeService.shared.disconnect()
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
