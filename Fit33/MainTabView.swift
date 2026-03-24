import SwiftUI
import CoreData
import UserNotifications

struct MainTabView: View {
    @EnvironmentObject var workoutManager: WorkoutManager
    @EnvironmentObject var userManager: UserManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var deepLinkManager = DeepLinkManager.shared
    @StateObject private var notificationManager = NotificationManager.shared
    @StateObject private var badgeCounter = HomeBadgeCounter.shared
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
        // Workout tab turns red when workout is active
        if selectedTab == 2 && workoutManager.isWorkoutActive {
            return .red
        }
        return tabs[selectedTab].color
    }
    
    var body: some View {
        VStack(spacing: 0) {
            OfflineBanner()
                .animation(.easeInOut(duration: 0.3), value: NetworkMonitor.shared.isConnected)
            
            ZStack(alignment: .bottom) {
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
                    if workoutManager.isWorkoutActive && selectedTab != 2 {
                        Label {
                            Text(tabs[2].title)
                                .foregroundColor(.red)
                        } icon: {
                            Image(uiImage: UIImage(systemName: "dumbbell.fill")!
                                .withTintColor(.red, renderingMode: .alwaysOriginal))
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
            // Animations managed per-tab via tabContentOptimized() during active transitions only
        .tint(currentTabColor)
        .onChange(of: workoutManager.shouldNavigateToWorkoutTab) { _, shouldNavigate in
            if shouldNavigate {
                selectedTab = 2
                workoutManager.shouldNavigateToWorkoutTab = false
            }
        }
        .onChange(of: workoutManager.isWorkoutActive) { _, isActive in
            // Also switch to workout tab when workout becomes active (backup)
            if isActive && selectedTab != 2 {
                selectedTab = 2
            }
            // 🔧 Reset "came from home" flag when workout starts (user pressed GO)
            if isActive {
                workoutManager.autoGenCameFromHomeTab = false
            }
        }
        .onChange(of: workoutManager.shouldNavigateToHomeTab) { _, shouldNavigate in
            if shouldNavigate {
                // 🔧 Reset IMMEDIATELY to prevent race conditions
                workoutManager.shouldNavigateToHomeTab = false
                workoutManager.shouldClearWorkoutTabNav = false  // Also reset clear flag
                
                AppLogger.debug("ContentView: Switching to home tab", category: .ui)
                withAnimation {
                    selectedTab = 0
                }
            }
        }
        .onChange(of: workoutManager.shouldNavigateToHomeTabInstant) { _, shouldNavigate in
            // 🔧 Instant tab switch (no animation) for auto-gen back navigation
            // This prevents flicker during transition
            if shouldNavigate {
                workoutManager.shouldNavigateToHomeTabInstant = false
                workoutManager.shouldClearWorkoutTabNav = false
                
                AppLogger.debug("ContentView: Switching to home tab (instant)", category: .ui)
                // NO animation - instant switch
                selectedTab = 0
            }
        }
        .onChange(of: workoutManager.shouldNavigateToAutoGen) { _, shouldNavigate in
            // 🔧 Redirect auto-gen from Home tab to Workout tab
            // This prevents cross-tab navigation issues when starting workout
            if shouldNavigate {
                workoutManager.shouldNavigateToAutoGen = false
                workoutManager.autoGenCameFromHomeTab = true  // Track origin for back navigation
                workoutManager.shouldShowWorkoutGenerator = true
                selectedTab = 2  // Switch to Workout tab
            }
        }
        .onChange(of: workoutManager.shouldNavigateToPrograms) { _, shouldNavigate in
            // 🔧 Redirect to programs from Home tab to Workout tab
            if shouldNavigate {
                selectedTab = 2  // Switch to Workout tab (will trigger navigation in WorkoutTabView)
            }
        }
        .onChange(of: workoutManager.shouldNavigateToFindFriends) { _, shouldNavigate in
            // 🔧 Redirect to find friends from Home tab to Workout tab (for challenges)
            if shouldNavigate {
                selectedTab = 2  // Switch to Workout tab (will trigger navigation in WorkoutTabView)
            }
        }
        .onChange(of: workoutManager.shouldNavigateToProgramOverview) { _, shouldNavigate in
            // 🔧 Navigate to Program Overview on Workout tab (from Dashboard)
            if shouldNavigate {
                selectedTab = 2  // Switch to Workout tab first
            }
        }
        .onChange(of: workoutManager.shouldNavigateToProgramDay) { _, shouldNavigate in
            // 🔧 Navigate to Program Day Preview on Workout tab (from Dashboard)
            if shouldNavigate {
                selectedTab = 2  // Switch to Workout tab first
            }
        }
        .onChange(of: workoutManager.shouldNavigateToCustomWorkoutBuilder) { _, shouldNavigate in
            // Navigate to Custom Workout Builder (from Exercise Detail "Add to workout" button)
            if shouldNavigate {
                selectedTab = 2  // Switch to Workout tab first, WorkoutTabView handles the navigation
                AppLogger.debug("Switching to Workout tab for Custom Workout Builder", category: .ui)
            }
        }
        .onChange(of: selectedTab) { oldValue, newValue in
            if oldValue != newValue {
                let switchStartTime = CACurrentMediaTime()
                
                MainThreadWatchdog.shared.setContext("tab_switch_\(oldValue)→\(newValue)")
                let isInstantSwitch = tabPreloader.isPreloadingComplete || lazyTabManager.isEagerModeEnabled
                tabSwitchOptimizer.beginTransition(from: oldValue, to: newValue)
                
                // Mark tab as visited for lazy loading
                if let tab = LazyTabManager.Tab(rawValue: newValue) {
                    lazyTabManager.markVisited(tab)
                    // Only prefetch if not already preloaded
                    if !isInstantSwitch {
                        SmartPrefetch.shared.prefetchForTab(tab)
                    }
                }
                
                
                // Log tab switch with screen IDs
                let tabScreens: [SessionLogManager.Screen] = [.dashboard, .exerciseLibrary, .workoutTab, .mealsTab, .statsTab]
                let fromScreen = oldValue < tabScreens.count ? tabScreens[oldValue] : .unknown
                let toScreen = newValue < tabScreens.count ? tabScreens[newValue] : .unknown
                
                // Start transition tracking
                SessionLogManager.shared.beginTransition(to: toScreen, from: .tabBarHome, action: "tab_switch")
                SessionLogManager.shared.logTabSwitch(from: fromScreen.displayName, to: toScreen.displayName)
                SessionLogManager.shared.log(.info, category: .navigation, message: "🔀 TAB: [\(fromScreen.rawValue)] → [\(toScreen.rawValue)]", metadata: [
                    "from_tab_index": oldValue,
                    "to_tab_index": newValue,
                    "from_screen_id": fromScreen.rawValue,
                    "to_screen_id": toScreen.rawValue,
                    "timestamp_ms": Int(Date().timeIntervalSince1970 * 1000),
                    "is_instant": isInstantSwitch
                ])
                

                scrollToTopTrigger = UUID()
                // Immediately hide GO button when switching tabs
                GoButtonState.shared.hide(reason: "tab_switch")
                
                // Always pop to root when switching to Home tab
                // This prevents stale navigation states from showing unexpected views
                if newValue == 0 {
                    workoutManager.shouldPopToRootHome = true
                }
                
                // 🔧 Reset "came from home" flag when user manually leaves Workout tab
                // This ensures if they come back manually, they stay on Workout tab when pressing back
                if oldValue == 2 && newValue != 2 {
                    workoutManager.autoGenCameFromHomeTab = false
                }
                
                
                
                // ⚡️ End transition tracking (async to not block)
                DispatchQueue.main.async { [self] in
                    let endTime = CACurrentMediaTime()
                    let totalMs = (endTime - switchStartTime) * 1000
                    tabSwitchOptimizer.endTransition()
                    MainThreadWatchdog.shared.clearContext()
                    if totalMs > 300 {
                        AppLogger.warning("⚠️ [TAB SWITCH] Slow transition: \(String(format: "%.1f", totalMs))ms", category: .ui)
                    } else if totalMs > 150 {
                        AppLogger.debug("🟡 [TAB SWITCH] Transition: \(String(format: "%.1f", totalMs))ms", category: .ui)
                    } else {
                        AppLogger.debug("✅ [TAB SWITCH] Fast transition: \(String(format: "%.1f", totalMs))ms", category: .ui)
                    }
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
        }
        .environment(\.scrollToTopTrigger, scrollToTopTrigger)
        .onChange(of: workoutManager.isWorkoutActive) { _, isActive in
            updateWorkoutTabLabelColor(isRed: isActive && selectedTab != 2)
        }
        .onChange(of: selectedTab) { _, newTab in
            updateWorkoutTabLabelColor(isRed: workoutManager.isWorkoutActive && newTab != 2)
        }
        .onAppear {
            updateWorkoutTabLabelColor(isRed: workoutManager.isWorkoutActive && selectedTab != 2)
            updateTabBarScale(isGoButtonVisible: GoButtonState.shared.isVisible)
        }
        .onReceive(NotificationCenter.default.publisher(for: .goButtonVisibilityChanged)) { notification in
            if let isVisible = notification.object as? Bool {
                updateTabBarScale(isGoButtonVisible: isVisible)
            }
        }
        // MARK: - Deep Link Tab Navigation
        .onReceive(deepLinkManager.$pendingDestination) { destination in
            guard let destination = destination else { return }
            handleDeepLinkDestination(destination)
        }
        // ✅ SwiftUI handles orientation changes naturally
        // ⚠️ DO NOT add .id() here - it destroys active workout state on rotation!
        .preferredColorScheme(.light)
            
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
        // MARK: - Notification Permission Prompt
        .task {
            // Check notification permission status on app launch
            // Only prompt once per session to avoid being annoying
            guard !hasCheckedNotificationPermission else { return }
            hasCheckedNotificationPermission = true
            
            // Short delay to let the UI settle
            try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 second delay
            
            // Check current notification authorization status
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            
            switch settings.authorizationStatus {
            case .notDetermined:
                // First time - request permission directly (iOS will show native prompt)
                let granted = await notificationManager.requestAuthorization()
                if !granted {
                    // If user denied, show our custom prompt to guide to Settings
                    await MainActor.run {
                        showNotificationPermissionPrompt = true
                    }
                }
            case .denied:
                // Previously denied - show prompt to guide to Settings
                // Only show this once per install (track with UserDefaults)
                let hasShownDeniedPrompt = UserDefaults.standard.bool(forKey: "has_shown_notification_denied_prompt")
                if !hasShownDeniedPrompt {
                    UserDefaults.standard.set(true, forKey: "has_shown_notification_denied_prompt")
                    await MainActor.run {
                        showNotificationPermissionPrompt = true
                    }
                }
            case .authorized, .provisional, .ephemeral:
                // Already authorized - ensure notifications are scheduled
                await MainActor.run {
                    notificationManager.scheduleAllNotifications()
                }
            @unknown default:
                break
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
        }
    }
    
    // Update the workout tab label color
    private func updateWorkoutTabLabelColor(isRed: Bool) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first else { return }
            
            if let tabBar = findTabBar(in: window) {
                let tabBarButtons = tabBar.subviews.filter { String(describing: type(of: $0)).contains("Button") }
                if tabBarButtons.count > 2 {
                    let workoutButton = tabBarButtons.sorted { $0.frame.minX < $1.frame.minX }[2]
                    updateLabelsInView(workoutButton, isRed: isRed)
                }
            }
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
    
    // Scale the Workout tab (index 2) when GO button is visible
    private func updateTabBarScale(isGoButtonVisible: Bool) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first else { return }
            
            if let tabBar = findTabBar(in: window) {
                let tabBarButtons = tabBar.subviews.filter { String(describing: type(of: $0)).contains("Button") }
                if tabBarButtons.count > 2 {
                    let sortedButtons = tabBarButtons.sorted { $0.frame.minX < $1.frame.minX }
                    let workoutButton = sortedButtons[2]
                    
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
    }
}
