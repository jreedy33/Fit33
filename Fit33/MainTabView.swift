import SwiftUI
import CoreData
import UserNotifications

struct MainTabView: View {
    @EnvironmentObject var workoutManager: WorkoutManager
    @EnvironmentObject var userManager: UserManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var deepLinkManager = DeepLinkManager.shared
    @StateObject private var notificationManager = NotificationManager.shared
    @StateObject private var badgeCounter = HomeBadgeCounter.shared
    @StateObject private var pushPermissionCoordinator = PushPermissionCoordinator.shared
    /// Cardio Redesign — Wave 4f (2026-05-02 per-user request).
    /// Drives the GLOBAL active-cardio cover so the user can minimize
    /// the running/walking screen and return via the red Workout tab.
    @ObservedObject private var cardioSession = CardioSessionManager.shared
    // ⚡️ Tab infrastructure — plain references (NOT @StateObject) to avoid
    // re-rendering ALL tabs whenever isTransitioning/isPreloadingComplete changes.
    // These are only used for method calls in onChange handlers.
    private let lazyTabManager = LazyTabManager.shared
    private let tabSwitchOptimizer = TabSwitchOptimizer.shared
    private let tabPreloader = TabPreloader.shared
    @State private var selectedTab: Int = 0
    @State private var scrollToTopTrigger: UUID = UUID()
    @State private var showNotificationPermissionPrompt = false
    @State private var hasCheckedNotificationPermission = false
    
    private let tabs = [
        TabItem(icon: "house", selectedIcon: "house.fill", title: "Home", color: .white),
        TabItem(icon: "book", selectedIcon: "book.fill", title: "Exercises", color: .blue),
        TabItem(icon: "dumbbell", selectedIcon: "dumbbell.fill", title: "Workout", color: .green),
        TabItem(icon: "leaf", selectedIcon: "leaf.fill", title: "Nutrition", color: .mint),
        TabItem(icon: "person.2", selectedIcon: "person.2.fill", title: "Friends", color: .cyan)
    ]
    
    private var currentTabColor: Color {
        // Workout tab turns red when ANY workout is active — strength
        // (`workoutManager.isWorkoutActive`) OR cardio (the new
        // `CardioSessionManager` flow). Both paths share the same
        // visual signal so the user always knows there's a session in
        // flight to come back to.
        if selectedTab == 2 && (workoutManager.isWorkoutActive || cardioSession.hasLiveSession) {
            return .red
        }
        return tabs[selectedTab].color
    }

    /// `true` when an outdoor cardio session is in flight (active /
    /// paused / pre-start). Drives the red Workout tab indicator AND
    /// the tap-to-restore behavior in `handleSelectedTabChange`.
    private var hasActiveCardio: Bool {
        cardioSession.hasLiveSession
    }
    
    var body: some View {
        mainTabChrome
    }

    /// Just the `TabView { ... }` body. Split out so the modifier chain in
    /// `tabViewWithModifiers` stays inside the Swift type-checker's budget.
    @ViewBuilder
    private var coreTabView: some View {
        // ⚡️ INSTANT TAB SWITCHING: All tabs preloaded for zero-lag transitions
        TabView(selection: $selectedTab) {
            // Tab 0: Dashboard (always loaded - primary tab)
            DashboardView()
                .tabContentOptimized()
                .tabItem {
                    Label {
                        Text(tabs[0].title)
                    } icon: {
                        Image(systemName: selectedTab == 0 ? tabs[0].selectedIcon : tabs[0].icon)
                    }
                    .accessibilityLabel(badgeCounter.count > 0 ? "Home tab, \(badgeCounter.count) notifications" : "Home tab")
                    .accessibilityHint("View your dashboard and daily summary")
                }
                .tag(0)
                .badge(badgeCounter.count)

            // Tab 1: Exercise Library (preloaded for instant access)
            LazyTabContent(tab: .exercises) {
                ExerciseLibraryView()
            }
            .tabContentOptimized()
            .tabItem {
                Label {
                    Text(tabs[1].title)
                } icon: {
                    Image(systemName: selectedTab == 1 ? tabs[1].selectedIcon : tabs[1].icon)
                }
                .accessibilityLabel("Exercises tab")
                .accessibilityHint("Browse exercise library")
            }
            .tag(1)

            // Tab 2: Workout (preloaded and prioritized)
            LazyTabContent(tab: .workout) {
                WorkoutTabView()
            }
            .tabContentOptimized()
            .tabItem {
                if (workoutManager.isWorkoutActive || hasActiveCardio) && selectedTab != 2 {
                    Label {
                        Text(tabs[2].title)
                            .foregroundColor(.red)
                    } icon: {
                        // Audit PR-36: no force unwraps in production —
                        // fall back to the SwiftUI symbol image if UIKit
                        // ever fails to resolve the SF Symbol.
                        if let dumbbell = UIImage(systemName: "dumbbell.fill")?
                            .withTintColor(.red, renderingMode: .alwaysOriginal) {
                            Image(uiImage: dumbbell)
                        } else {
                            Image(systemName: "dumbbell.fill")
                        }
                    }
                    .foregroundColor(.red)
                    .accessibilityLabel("Workout tab, workout in progress")
                    .accessibilityHint("Return to your active workout")
                } else {
                    Label {
                        Text(tabs[2].title)
                    } icon: {
                        Image(systemName: selectedTab == 2 ? tabs[2].selectedIcon : tabs[2].icon)
                    }
                    .accessibilityLabel("Workout tab")
                    .accessibilityHint("Start or manage workouts")
                }
            }
            .tag(2)

            // Tab 3: Meals (preloaded)
            LazyTabContent(tab: .nutrition) {
                SimpleMealPlanView()
            }
            .tabContentOptimized()
            .tabItem {
                Label {
                    Text(tabs[3].title)
                } icon: {
                    Image(systemName: selectedTab == 3 ? tabs[3].selectedIcon : tabs[3].icon)
                }
                .accessibilityLabel("Nutrition tab")
                .accessibilityHint("Track meals and macros")
            }
            .tag(3)

            // Tab 4: Friends (social hub)
            LazyTabContent(tab: .progress) {
                FriendsTabView()
                    .environmentObject(workoutManager)
                    .environmentObject(userManager)
            }
            .tabContentOptimized()
            .tabItem {
                Label {
                    Text(tabs[4].title)
                } icon: {
                    Image(systemName: selectedTab == 4 ? tabs[4].selectedIcon : tabs[4].icon)
                }
                .accessibilityLabel("Friends tab")
                .accessibilityHint("View friends and social activity")
            }
            .tag(4)
        }
    }

    /// Modifiers + onChange handlers wrapped around `coreTabView`. Split into
    /// two halves (`applyNavigationTriggers` + `applyLifecycleAndOverlays`) so
    /// the Swift type-checker can handle the full chain in budget.
    private var tabViewWithModifiers: some View {
        applyLifecycleAndOverlays(
            applyNavigationTriggers(
                coreTabView.tint(currentTabColor)
            )
        )
    }

    /// First half of the tab-stack modifier chain: every imperative
    /// "shouldNavigateTo*" trigger from `WorkoutManager`.
    @ViewBuilder
    private func applyNavigationTriggers<V: View>(_ content: V) -> some View {
        content
            .onChange(of: workoutManager.shouldNavigateToWorkoutTab) { _, shouldNavigate in
                if shouldNavigate {
                    selectedTab = 2
                    workoutManager.shouldNavigateToWorkoutTab = false
                }
            }
            .onChange(of: workoutManager.isWorkoutActive) { _, isActive in
                if isActive && selectedTab != 2 {
                    selectedTab = 2
                }
                if isActive {
                    workoutManager.autoGenCameFromHomeTab = false
                }
                updateWorkoutTabLabelColor(isRed: isActive && selectedTab != 2)
            }
            .onChange(of: workoutManager.shouldNavigateToHomeTab) { _, shouldNavigate in
                if shouldNavigate {
                    workoutManager.shouldNavigateToHomeTab = false
                    workoutManager.shouldClearWorkoutTabNav = false
                    AppLogger.debug("ContentView: Switching to home tab", category: .ui)
                    withAnimation {
                        selectedTab = 0
                    }
                }
            }
            .onChange(of: workoutManager.shouldNavigateToHomeTabInstant) { _, shouldNavigate in
                if shouldNavigate {
                    workoutManager.shouldNavigateToHomeTabInstant = false
                    workoutManager.shouldClearWorkoutTabNav = false
                    AppLogger.debug("ContentView: Switching to home tab (instant)", category: .ui)
                    selectedTab = 0
                }
            }
            .onChange(of: workoutManager.shouldNavigateToAutoGen) { _, shouldNavigate in
                if shouldNavigate {
                    workoutManager.shouldNavigateToAutoGen = false
                    workoutManager.autoGenCameFromHomeTab = true
                    workoutManager.shouldShowWorkoutGenerator = true
                    selectedTab = 2
                }
            }
            .onChange(of: workoutManager.shouldNavigateToPrograms) { _, shouldNavigate in
                if shouldNavigate { selectedTab = 2 }
            }
            .onChange(of: workoutManager.shouldNavigateToFindFriends) { _, shouldNavigate in
                if shouldNavigate { selectedTab = 2 }
            }
            .onChange(of: workoutManager.shouldNavigateToProgramOverview) { _, shouldNavigate in
                if shouldNavigate { selectedTab = 2 }
            }
            .onChange(of: workoutManager.shouldNavigateToProgramDay) { _, shouldNavigate in
                if shouldNavigate { selectedTab = 2 }
            }
            .onChange(of: workoutManager.shouldNavigateToCustomWorkoutBuilder) { _, shouldNavigate in
                if shouldNavigate {
                    selectedTab = 2
                    AppLogger.debug("Switching to Workout tab for Custom Workout Builder", category: .ui)
                }
            }
            .onChange(of: workoutManager.shouldNavigateToMealsTab) { _, shouldNavigate in
                // Daily Brief CTA — pushing `SimpleMealPlanView` onto the dashboard's
                // NavigationStack auto-bounces back to root because it wraps its own
                // NavigationStack (PE invariant 6).
                if shouldNavigate {
                    workoutManager.shouldNavigateToMealsTab = false
                    selectedTab = 3
                }
            }
    }

    /// Second half of the tab-stack modifier chain: lifecycle (`onAppear`,
    /// scenePhase), tab-switch handling, deep-link routing, and overlays.
    @ViewBuilder
    private func applyLifecycleAndOverlays<V: View>(_ content: V) -> some View {
        content
            .onChange(of: selectedTab) { oldValue, newValue in
                handleSelectedTabChange(oldValue: oldValue, newValue: newValue)
                updateWorkoutTabLabelColor(isRed: workoutManager.isWorkoutActive && newValue != 2)
                syncDashboardBattleCryHostVisibility()
            }
            .environment(\.scrollToTopTrigger, scrollToTopTrigger)
            .onAppear {
                updateWorkoutTabLabelColor(isRed: workoutManager.isWorkoutActive && selectedTab != 2)
                updateTabBarScale(isGoButtonVisible: GoButtonState.shared.isVisible)
                syncDashboardBattleCryHostVisibility()
            }
            .onChange(of: scenePhase) { _, _ in
                syncDashboardBattleCryHostVisibility()
            }
            .onReceive(NotificationCenter.default.publisher(for: .goButtonVisibilityChanged)) { notification in
                if let isVisible = notification.object as? Bool {
                    updateTabBarScale(isGoButtonVisible: isVisible)
                }
            }
            .onReceive(deepLinkManager.$pendingDestination) { destination in
                guard let destination = destination else { return }
                handleDeepLinkDestination(destination)
            }
            // ⚠️ DO NOT add .id() here - it destroys active workout state on rotation.
            .preferredColorScheme(AppearanceManager.shared.colorScheme)
    }

    /// Offline banner + tab stack + GO overlay + sheets/alerts.
    @ViewBuilder
    private var mainTabChrome: some View {
        VStack(spacing: 0) {
            OfflineBanner()
                .animation(.easeInOut(duration: 0.3), value: NetworkMonitor.shared.isConnected)

            ZStack(alignment: .bottom) {
                tabViewWithModifiers

                // GO! Button overlay - isolated view that observes its own state
                GoButtonOverlay()
            }
        } // end VStack (offline banner + tab content)
        // Shared Workout Sheet - shows when user opens a shared workout link
        .sheet(isPresented: $deepLinkManager.showSharedWorkoutSheet) {
            if let workoutId = deepLinkManager.pendingSharedWorkoutId {
                SharedWorkoutView(
                    workoutId: workoutId,
                    previewData: WorkoutSharingService.shared.pendingSharedWorkout
                )
                .environment(\.managedObjectContext, viewContext)
                .environmentObject(workoutManager)
            }
        }
        // Community Join Sheet - shows when user opens a community challenge share link
        .sheet(isPresented: $deepLinkManager.showCommunityJoinSheet) {
            if let slug = deepLinkManager.pendingCommunitySlug {
                CommunityJoinSheet(codeOrSlug: slug)
            }
        }
        // Private Challenge Join Sheet - shows when user opens a /pc/ deep link
        .sheet(isPresented: $deepLinkManager.showPrivateJoinSheet) {
            if let code = deepLinkManager.pendingPrivateJoinCode {
                PrivateChallengeJoinSheet(code: code)
            }
        }
        // MARK: - Push permission primer (coordinated single-ask path)
        // Smart Notification Engine — Phase 1 (2026-08-01).
        // Replaced three independent ask paths (onboarding, post-auth,
        // MainTabView .task) with one coordinator. The primer sheet
        // explains WHY before the cold system dialog.
        .sheet(isPresented: $pushPermissionCoordinator.showPrimerSheet) {
            NotificationPrimerSheet()
        }
        // MARK: - Global active-cardio cover (Wave 4f — 2026-05-02)
        //
        // `OutdoorCardioActiveView` is presented at the ROOT of the app
        // so the user can minimize it (chevron-down in top-left) and
        // browse other tabs while their walk / run / cycle continues
        // running in the background. Tapping the red Workout tab in the
        // bottom tab bar restores it (handled in `handleSelectedTabChange`).
        // The binding's setter routes "swipe / programmatic dismiss"
        // through `minimize()` so the GPS engine + Live Activity stay
        // alive — the only way to actually END a session is the red
        // "End" button inside the active view.
        .fullScreenCover(isPresented: Binding(
            get: { cardioSession.isPresentingActive },
            set: { newValue in
                if !newValue && cardioSession.hasLiveSession {
                    cardioSession.minimize()
                }
            }
        )) {
            CardioActiveSessionHost(isPresented: Binding(
                get: { cardioSession.isPresentingActive },
                set: { newValue in
                    if !newValue && cardioSession.hasLiveSession {
                        cardioSession.minimize()
                    }
                }
            ))
            .environmentObject(userManager)
            .environmentObject(workoutManager)
        }
        .task {
            guard !hasCheckedNotificationPermission else { return }
            hasCheckedNotificationPermission = true

            // Let the UI settle so the primer sheet doesn't fight onboarding
            // dismissal animations.
            try? await Task.sleep(nanoseconds: 1_500_000_000)

            let status = await pushPermissionCoordinator.ensureAskedOnce(useSoftPrompt: true)
            if status == .denied && pushPermissionCoordinator.shouldShowPostDenyPrompt() {
                pushPermissionCoordinator.markPostDenyPromptShown()
                await MainActor.run { showNotificationPermissionPrompt = true }
            }
        }
        .alert("Stay on Track with Notifications", isPresented: $showNotificationPermissionPrompt) {
            Button("Enable Notifications") {
                // Open iOS Settings for this app
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Maybe Later", role: .cancel) { }
        } message: {
            Text("Get workout reminders, streak alerts, and celebrate your achievements! Enable notifications in Settings to never miss a beat.")
        }
    }
    
    /// Home dashboard is the only surface that shows `BattleCryShoutBubble`.
    /// While off Home or when the app is backgrounded, incoming reactions
    /// buffer in `RealtimeService`; see `BattleCryShoutBubble` + `RealtimeService`.
    private func syncDashboardBattleCryHostVisibility() {
        let onHomeSurface = selectedTab == 0 && scenePhase != .background
        RealtimeService.shared.setDashboardBattleCryHostVisible(onHomeSurface)
    }

    /// Extracted from the `.onChange(of: selectedTab)` closure so the SwiftUI
    /// body can type-check within budget. Owns: tab-transition logging, prefetch,
    /// scroll-to-top, GO-button hide, per-tab notifications, pop-to-root, and
    /// post-switch HealthKit / wearable preloads.
    private func handleSelectedTabChange(oldValue: Int, newValue: Int) {
        // Cardio Redesign — Wave 4f. Tapping the (red) Workout tab while
        // a cardio session is minimized re-presents the active screen
        // INSTEAD of switching tabs. Matches the user's "tap workout
        // button → back to running screen" requirement. We don't change
        // `selectedTab`; we just flip `isMinimized` so the global cover
        // re-presents over whatever tab they were on.
        if newValue == 2 && cardioSession.isMinimized && cardioSession.hasLiveSession {
            cardioSession.restore()
            // Bounce the selection back so the user lands where they
            // were when the cover dismisses (prevents an awkward
            // "you're suddenly on the workout tab" surprise).
            if oldValue != 2 {
                Task { @MainActor in
                    selectedTab = oldValue
                }
            }
            return
        }

        if oldValue != newValue {
            MainThreadWatchdog.shared.setContext("tab_switch_\(oldValue)→\(newValue)")
            let isInstantSwitch = tabPreloader.isPreloadingComplete || lazyTabManager.isEagerModeEnabled
            tabSwitchOptimizer.beginTransition(from: oldValue, to: newValue)

            if let tab = LazyTabManager.Tab(rawValue: newValue) {
                lazyTabManager.markVisited(tab)
                // 2026-05-03 perf sprint: do NOT call SmartPrefetch.prefetchForTab here.
                // tabSwitchOptimizer.beginTransition(from:to:) above already invokes
                // SmartPrefetch.shared.prefetchForTab(tab); calling it a second time
                // duplicated the Core Data prefetch task on every non-instant tab switch.
                _ = isInstantSwitch
            }

            logTabSwitch(oldValue: oldValue, newValue: newValue, isInstantSwitch: isInstantSwitch)

            scrollToTopTrigger = UUID()
            GoButtonState.shared.hide(reason: "tab_switch")

            // 🔁 Exercises tab resets its filter to Recommended on every tap.
            if newValue == 1 {
                NotificationCenter.default.post(name: .exerciseTabSelected, object: nil)
            }

            if newValue == 0 {
                workoutManager.shouldPopToRootHome = true
            }

            if oldValue == 2 && newValue != 2 {
                workoutManager.autoGenCameFromHomeTab = false
            }

            // ⚡️ End transition tracking (async to not block).
            // swiftui-rules.mdc §3: structured concurrency, never DispatchQueue.
            Task { @MainActor [self] in
                tabSwitchOptimizer.endTransition()
                MainThreadWatchdog.shared.clearContext()
            }
        }

        if newValue == 0 && HealthKitManager.shared.isAuthorized {
            Task.detached(priority: .background) {
                try? await Task.sleep(nanoseconds: 300_000_000)
                await HealthKitManager.shared.fetchTodaySteps()
                await HealthKitManager.shared.fetchWeeklySteps()
                await HealthKitManager.shared.fetchMonthlyAverage()
            }
        }

        // Wearable widget preload on return to Dashboard. WHOOP / Oura widgets
        // can go stale while the user is on another tab for >5 min. Quiet
        // force-sync IF last sync is older than 60s. Service-level `isSyncing`
        // guard coalesces with any in-flight foreground sync.
        if newValue == 0 && oldValue != 0 {
            Task(priority: .userInitiated) {
                let now = Date()
                let whoopStale: Bool = {
                    guard WhoopService.shared.isConnected else { return false }
                    guard let last = WhoopService.shared.lastSyncDate else { return true }
                    return now.timeIntervalSince(last) > 60
                }()
                let ouraStale: Bool = {
                    guard OuraService.shared.isConnected else { return false }
                    guard let last = OuraService.shared.lastSyncDate else { return true }
                    return now.timeIntervalSince(last) > 60
                }()
                if whoopStale {
                    await WhoopService.shared.syncAllData(force: true)
                }
                if ouraStale {
                    await OuraService.shared.syncAllData(force: true)
                }
            }
        }
    }

    /// Heterogeneous metadata dictionary literal — pulled out of the
    /// `onChange` closure where it added significant type-checker cost.
    private func logTabSwitch(oldValue: Int, newValue: Int, isInstantSwitch: Bool) {
        let tabScreens: [SessionLogManager.Screen] = [.dashboard, .exerciseLibrary, .workoutTab, .mealsTab, .statsTab]
        let fromScreen = oldValue < tabScreens.count ? tabScreens[oldValue] : .unknown
        let toScreen = newValue < tabScreens.count ? tabScreens[newValue] : .unknown

        SessionLogManager.shared.beginTransition(to: toScreen, from: .tabBarHome, action: "tab_switch")
        SessionLogManager.shared.logTabSwitch(from: fromScreen.displayName, to: toScreen.displayName)

        let metadata: [String: Any] = [
            "from_tab_index": oldValue,
            "to_tab_index": newValue,
            "from_screen_id": fromScreen.rawValue,
            "to_screen_id": toScreen.rawValue,
            "timestamp_ms": Int(Date().timeIntervalSince1970 * 1000),
            "is_instant": isInstantSwitch
        ]
        SessionLogManager.shared.log(
            .info,
            category: .navigation,
            message: "🔀 TAB: [\(fromScreen.rawValue)] → [\(toScreen.rawValue)]",
            metadata: metadata
        )
    }
    
    // MARK: - Deep Link Handling
    
    /// Handle deep link destinations by switching tabs and posting notifications for widget scrolling
    private func handleDeepLinkDestination(_ destination: DeepLinkManager.Destination) {
        switch destination {
        // Tab Navigation
        case .dashboard:
            selectedTab = 0
            deepLinkManager.pendingDestination = nil
            AppLogger.debug("[DEEPLINK] Switched to Home tab", category: .ui)
            
        case .workout, .running:
            selectedTab = 2
            // Don't clear destination - WorkoutTabView needs to handle specific navigation
            AppLogger.debug("[DEEPLINK] Switched to Workout tab", category: .ui)
            
        case .mealsTab:
            selectedTab = 3
            deepLinkManager.pendingDestination = nil
            AppLogger.debug("[DEEPLINK] Switched to Meals tab", category: .ui)
            
        case .addFood(let mealType):
            selectedTab = 3
            deepLinkManager.pendingMealType = mealType
            deepLinkManager.pendingDestination = nil
            AppLogger.debug("[DEEPLINK] Switched to Meals tab → Add Food (\(mealType))", category: .ui)
            
        case .statsTab, .personalRecord:
            selectedTab = 4
            deepLinkManager.pendingDestination = nil
            AppLogger.debug("[DEEPLINK] Switched to Friends tab", category: .ui)
            
        // Dashboard Widget Navigation (Home tab + scroll to widget)
        case .hydration:
            selectedTab = 3
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                NotificationCenter.default.post(name: .scrollToWidget, object: "hydration")
            }
            deepLinkManager.pendingDestination = nil
            AppLogger.debug("[DEEPLINK] Navigating to Hydration widget on Meals tab", category: .ui)
            
        case .stepTracker:
            selectedTab = 0
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                NotificationCenter.default.post(name: .scrollToWidget, object: "stepTracker")
            }
            deepLinkManager.pendingDestination = nil
            AppLogger.debug("[DEEPLINK] Navigating to Step Tracker widget on Home tab", category: .ui)
            
        case .weightTracker:
            selectedTab = 3
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                NotificationCenter.default.post(name: .scrollToWidget, object: "weightTracker")
            }
            deepLinkManager.pendingDestination = nil
            AppLogger.debug("[DEEPLINK] Navigating to Weight Tracker widget on Meals tab", category: .ui)
            
        case .workoutHistory:
            selectedTab = 0
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                NotificationCenter.default.post(name: .scrollToWidget, object: "workoutHistory")
            }
            deepLinkManager.pendingDestination = nil
            AppLogger.debug("[DEEPLINK] Navigating to Workout History", category: .ui)
            
        case .streakInfo:
            selectedTab = 0
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                NotificationCenter.default.post(name: .scrollToWidget, object: "streakInfo")
            }
            deepLinkManager.pendingDestination = nil
            AppLogger.debug("[DEEPLINK] Navigating to Streak Info", category: .ui)

        case .programs:
            selectedTab = 2
            workoutManager.shouldNavigateToPrograms = true
            deepLinkManager.pendingDestination = nil
            AppLogger.debug("[DEEPLINK] Switched to Workout tab → opening program schedule", category: .ui)
            
        // Social - handled by Friends tab with deep push
        case .friends:
            selectedTab = 4
            deepLinkManager.pendingFriendsRoute = "FriendsList"
            deepLinkManager.pendingDestination = nil
            AppLogger.debug("[DEEPLINK] Switched to Friends tab → pushing FriendsList", category: .ui)
            
        case .friendRequests:
            selectedTab = 4
            deepLinkManager.pendingFriendsRoute = "FriendRequests"
            deepLinkManager.pendingDestination = nil
            AppLogger.debug("[DEEPLINK] Switched to Friends tab → pushing FriendRequests", category: .ui)

        case .friendSearch:
            selectedTab = 4
            deepLinkManager.pendingFriendsRoute = "FriendSearch"
            deepLinkManager.pendingDestination = nil
            AppLogger.debug("[DEEPLINK] Switched to Friends tab → pushing FriendSearch", category: .ui)

        // Activity-feed reactions (`activity_reaction` push). Land on the
        // Friends tab landing screen — the activity feed is rendered INLINE
        // there. Pushing `FriendsList` would hide the feed behind the
        // friends-list sheet. Bug-intel `184e70c6`: tapping a reaction
        // notification used to fall through to `default` → silent no-op.
        case .friendsActivity:
            selectedTab = 4
            // Intentionally NO pendingFriendsRoute — keep the navigation stack
            // at root so the inline activity feed is visible.
            deepLinkManager.pendingDestination = nil
            AppLogger.debug("[DEEPLINK] Switched to Friends tab landing for activity reaction", category: .ui)
            
        // Received workouts - handled by WorkoutTabView
        case .receivedWorkouts, .receivedWorkout, .sharedWorkout:
            selectedTab = 2
            // Don't clear - WorkoutTabView handles the navigation
            AppLogger.debug("[DEEPLINK] Switched to Workout tab for shared workout", category: .ui)
            
        // Challenges - route based on specificity
        case .challenges:
            selectedTab = 4
            deepLinkManager.pendingDestination = nil
            AppLogger.debug("[DEEPLINK] Switched to Friends tab for challenges list", category: .ui)
            
        case .challengeCreation:
            selectedTab = 0
            deepLinkManager.pendingDashboardRoute = "ChallengeCreation"
            deepLinkManager.pendingDestination = nil
            AppLogger.debug("[DEEPLINK] Switched to Home tab → opening challenge creation flow", category: .ui)
            
        case .challengeInvite:
            // Invite widget is on Dashboard (Home tab)
            selectedTab = 0
            deepLinkManager.pendingDestination = nil
            AppLogger.debug("[DEEPLINK] Switched to Home tab for challenge invite widget", category: .ui)
            
        case .challengeDetail(let challengeId):
            // Navigate to Home tab and push the challenge detail view
            selectedTab = 0
            deepLinkManager.pendingDashboardRoute = "ChallengeDetail:\(challengeId)"
            deepLinkManager.pendingDestination = nil
            AppLogger.debug("[DEEPLINK] Switched to Home tab → pushing challenge detail: \(challengeId)", category: .ui)
            
        // Community Challenges - join sheet is presented from ContentView
        case .communityChallenge(let slug):
            deepLinkManager.pendingCommunitySlug = slug
            deepLinkManager.showCommunityJoinSheet = true
            deepLinkManager.pendingDestination = nil
            AppLogger.debug("[DEEPLINK] Showing community join sheet for: \(slug)", category: .ui)
            
        case .communityChallengeBrowse:
            selectedTab = 2
            deepLinkManager.pendingDestination = nil
            AppLogger.debug("[DEEPLINK] Switched to Workout tab for community browse", category: .ui)
            
        // Private Challenges - navigate to Friends tab where detail views exist
        case .privateChallengeDetail(let challengeId):
            selectedTab = 4
            deepLinkManager.pendingFriendsRoute = "PrivateChallenge_\(challengeId)"
            deepLinkManager.pendingDestination = nil
            AppLogger.debug("[DEEPLINK] Switched to Friends tab → pushing private challenge detail: \(challengeId)", category: .ui)
            
        case .privateChallengeInvite:
            // Private invite widget shows on Dashboard
            selectedTab = 0
            deepLinkManager.pendingDestination = nil
            AppLogger.debug("[DEEPLINK] Switched to Home tab for private challenge invite", category: .ui)
            
        // Private Challenge Join by Code - show preview sheet
        case .privateChallengeJoinByCode(let code):
            deepLinkManager.pendingPrivateJoinCode = code
            deepLinkManager.showPrivateJoinSheet = true
            deepLinkManager.pendingDestination = nil
            AppLogger.debug("[DEEPLINK] Showing private challenge join sheet for code: \(code)", category: .ui)

        // ── Smart Notification Engine destinations (2026-08-01) ─────────
        case .leagues:
            // League widget lives on Stats tab (tab 4 — same as personalRecord).
            selectedTab = 4
            deepLinkManager.pendingDestination = nil
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                NotificationCenter.default.post(name: .scrollToWidget, object: "leagueWidget")
            }
            AppLogger.debug("[DEEPLINK] Switched to Stats tab → scrolling to League widget", category: .ui)

        case .readinessDetail:
            // Land on Home tab; the wrapper presents `ReadinessDrillDownSheet`
            // locally via .sheet() (PE invariant 25d — sheets must own their
            // presentation context). The dashboard wrapper subscribes to a
            // `showReadinessDetail` flag set here.
            selectedTab = 0
            deepLinkManager.pendingDashboardRoute = "ReadinessDetail"
            deepLinkManager.pendingDestination = nil
            AppLogger.debug("[DEEPLINK] Switched to Home tab → opening readiness drill-down", category: .ui)

        case .smackTalk(let challengeId):
            // Smack-talk composer is hosted by the challenge detail view —
            // route to challenge detail with a "open composer" flag.
            selectedTab = 0
            deepLinkManager.pendingDashboardRoute = "ChallengeDetail:\(challengeId):smackTalk"
            deepLinkManager.pendingDestination = nil
            AppLogger.debug("[DEEPLINK] Switched to Home tab → smack-talk composer for: \(challengeId)", category: .ui)

        case .proRecap:
            // Monetization Phase 5 — Sunday Pro Recap. Switch to Home
            // tab so the cover presents over the dashboard (same surface
            // the user lives on after a push tap), then flip the
            // showProRecap flag observed by ContentView.
            selectedTab = 0
            deepLinkManager.pendingDestination = nil
            MonetizationState.shared.requestProRecapPresentation()
            AppLogger.debug("[DEEPLINK] Routed to Pro Recap — Home tab + recap cover", category: .ui)

        case .mealLogger(let mealType):
            // Alias of addFood when meal type provided, or mealsTab landing.
            selectedTab = 3
            if let mealType = mealType {
                deepLinkManager.pendingMealType = mealType
            }
            deepLinkManager.pendingDestination = nil
            AppLogger.debug("[DEEPLINK] Switched to Meals tab for meal logger (\(mealType ?? "any"))", category: .ui)

        case .olympianPath:
            // 2026-05-04 — Path to 33 deep link `fit33://olympian`.
            // Switch to Home tab; DashboardView already observes
            // `pendingDashboardRoute == "olympian"` to push
            // `DashboardRoute.olympianPath` onto its NavigationStack.
            selectedTab = 0
            deepLinkManager.pendingDashboardRoute = "olympian"
            deepLinkManager.pendingDestination = nil
            AppLogger.debug("[DEEPLINK] Switched to Home tab → pushing Olympian Path", category: .ui)
        }
    }
    
    // Update the workout tab label color
    private func updateWorkoutTabLabelColor(isRed: Bool) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard let workoutButton = TabBarLookupCache.shared.resolveWorkoutTabButton() else { return }
            updateLabelsInView(workoutButton, isRed: isRed)
        }
    }
    
    private func updateLabelsInView(_ view: UIView, isRed: Bool) {
        for subview in view.subviews {
            if let label = subview as? UILabel, label.text == "Workout" {
                label.textColor = isRed ? .red : .label
            }
            updateLabelsInView(subview, isRed: isRed)
        }
    }
    
    // Scale the Workout tab (index 2) when GO button is visible
    private func updateTabBarScale(isGoButtonVisible: Bool) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard let workoutButton = TabBarLookupCache.shared.resolveWorkoutTabButton() else { return }
            
            UIView.animate(withDuration: 0.2) {
                if isGoButtonVisible {
                    workoutButton.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
                    workoutButton.alpha = 0.2
                } else {
                    workoutButton.transform = .identity
                    workoutButton.alpha = 1.0
                }
            }
        }
    }
}

// MARK: - Tab Bar Lookup Cache (2026-05-03 perf sprint)
//
// `updateWorkoutTabLabelColor` + `updateTabBarScale` are called from
// SwiftUI `.onChange` handlers tied to `workoutManager.isWorkoutActive`,
// `selectedTab`, and `GoButtonState.isVisible`. Each call USED to walk
// the entire UIView hierarchy from `windowScene.windows.first` down,
// recursively, and then sort + filter all subviews of `UITabBar` to
// locate the third `*Button*`-typed view (the "Workout" tab button).
//
// The walk is small (depth ~5), but the work is pure waste — the
// `UITabBar` and its child buttons are constructed once per scene and
// never replaced for the lifetime of the `MainTabView`. Caching a
// weak reference to the resolved workout button removes the recursive
// `findTabBar` + the `subviews.filter { String(describing: type(of: $0))…}`
// + the `sorted` on every state change.
//
// `weak` so that if iOS rebuilds the tab bar (rotation, multitasking
// transitions, scene reconfiguration) the cache transparently falls
// back to a fresh lookup. No invalidation hooks needed.
@MainActor
final class TabBarLookupCache {
    static let shared = TabBarLookupCache()
    
    private weak var cachedWorkoutButton: UIView?
    
    private init() {}
    
    /// Returns the resolved Workout tab button. Uses a cached weak
    /// reference when valid; otherwise re-walks the view hierarchy and
    /// re-caches. Returns `nil` only when the window scene isn't yet
    /// attached or the tab bar hasn't been laid out.
    func resolveWorkoutTabButton() -> UIView? {
        if let cached = cachedWorkoutButton {
            return cached
        }
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let tabBar = findTabBar(in: window) else {
            return nil
        }
        let tabBarButtons = tabBar.subviews.filter { String(describing: type(of: $0)).contains("Button") }
        guard tabBarButtons.count > 2 else { return nil }
        let resolved = tabBarButtons.sorted { $0.frame.minX < $1.frame.minX }[2]
        cachedWorkoutButton = resolved
        return resolved
    }
    
    /// Force a re-walk on the next call. Intended for testing / future
    /// scene-reconfiguration hooks; the `weak` reference handles the
    /// common cases automatically.
    func invalidate() {
        cachedWorkoutButton = nil
    }
    
    private func findTabBar(in view: UIView) -> UITabBar? {
        if let tabBar = view as? UITabBar {
            return tabBar
        }
        for subview in view.subviews {
            if let tabBar = findTabBar(in: subview) {
                return tabBar
            }
        }
        return nil
    }
}
