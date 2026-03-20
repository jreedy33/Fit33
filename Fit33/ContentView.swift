import SwiftUI
import CoreData
import Combine
import Charts
import UserNotifications

// MARK: - Scroll To Top Environment Key
private struct ScrollToTopTriggerKey: EnvironmentKey {
    static let defaultValue: UUID = UUID()
}

extension EnvironmentValues {
    var scrollToTopTrigger: UUID {
        get { self[ScrollToTopTriggerKey.self] }
        set { self[ScrollToTopTriggerKey.self] = newValue }
    }
}

// MARK: - Meal Types

enum MealType: String, CaseIterable {
    case breakfast = "breakfast"
    case lunch = "lunch"
    case dinner = "dinner"
    case snacks = "snacks"
    
    var displayName: String {
        switch self {
        case .breakfast: return "Breakfast"
        case .lunch: return "Lunch"
        case .dinner: return "Dinner"
        case .snacks: return "Snacks"
        }
    }
    
    var icon: String {
        switch self {
        case .breakfast: return "sunrise.fill"
        case .lunch: return "sun.max.fill"
        case .dinner: return "moon.stars.fill"
        case .snacks: return "leaf.fill"
        }
    }
    
    var gradientColors: (Color, Color) {
        switch self {
        case .breakfast: return (.orange, .yellow)
        case .lunch: return (.green, .teal)
        case .dinner: return (.blue, .cyan)
        case .snacks: return (.purple, .pink)
        }
    }
    
    var timeDescription: String {
        switch self {
        case .breakfast: return "5 AM - 10 AM"
        case .lunch: return "12 PM - 2 PM"
        case .dinner: return "6 PM onwards"
        case .snacks: return "Anytime"
        }
    }
}

struct FoodEntry {
    let name: String
    let quantity: Int
    let unit: String
    let calories: Int
    let protein: Int
    let carbs: Int
    let fat: Int
    let fdcId: Int? // For cloud tracking
    let foodItemId: Int? // Cloud food database ID
}

// MARK: - Nutrition Chart Data
struct MacronutrientData: Identifiable {
    let id = UUID()
    let name: String
    let value: Double
    let color: Color
    let calories: Double
}

struct NutritionInsight {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color
    let trend: String?
}

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var userManager = UserManager.shared
    @StateObject private var workoutManager = WorkoutManager.shared
    
    // Welcome tutorial state - shown once per session when user completes onboarding
    @State private var showWelcomeTutorial = false
    @State private var hasShownTutorialThisSession = false
    
    // Track the last known onboarding state to detect transitions
    @State private var lastKnownOnboardingState: Bool? = nil
    
    var body: some View {
        ZStack {
            Group {
                if userManager.hasCompletedOnboarding {
                    MainTabView()
                } else {
                    NewOnboardingView()
                }
            }
            .environmentObject(userManager)
            .environmentObject(workoutManager)
        }
        .fullScreenCover(isPresented: $showWelcomeTutorial) {
            WelcomeTutorialView(isPresented: $showWelcomeTutorial)
        }
        .overlay(alignment: .top) {
            if BadgeService.shared.showUnlockToast,
               let achievement = BadgeService.shared.lastUnlockedAchievement {
                AchievementUnlockToast(achievement: achievement)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(998)
                    .padding(.top, 50)
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: BadgeService.shared.showUnlockToast)
        .overlay {
            if userManager.showLevelUpCelebration {
                LevelUpCelebrationOverlay(
                    level: userManager.newLevelReached,
                    levelTitle: userManager.getLevelTitle(),
                    levelIcon: userManager.getLevelIcon(),
                    levelColor: userManager.getLevelColor()
                ) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        userManager.showLevelUpCelebration = false
                    }
                }
                .transition(.opacity.combined(with: .scale))
                .zIndex(999)
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: userManager.showLevelUpCelebration)
        .onChange(of: userManager.hasCompletedOnboarding) { oldValue, newValue in
            AppLogger.debug("[TUTORIAL] hasCompletedOnboarding changed: \(oldValue) → \(newValue), lastKnown: \(String(describing: lastKnownOnboardingState))", category: .ui)
            
            // Detect actual onboarding completion (user went from not-onboarded to onboarded)
            if newValue && !oldValue {
                AppLogger.debug("[TUTORIAL] Onboarding completed! lastKnown: \(String(describing: lastKnownOnboardingState)), shownThisSession: \(hasShownTutorialThisSession)", category: .ui)
                
                // Show tutorial if:
                // 1. Haven't shown it already this session, AND
                // 2. This is a real onboarding completion (not just app loading existing user)
                //    - lastKnownOnboardingState being nil means app just launched with existing user (skip)
                //    - lastKnownOnboardingState being false means user actually went through onboarding flow
                if !hasShownTutorialThisSession && lastKnownOnboardingState == false {
                    AppLogger.info("[TUTORIAL] Showing welcome tutorial!", category: .ui)
                    hasShownTutorialThisSession = true
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 1_200_000_000)
                        showWelcomeTutorial = true
                    }
                }
            }
            
            // Update our tracking state
            lastKnownOnboardingState = newValue
        }
        .task {
            // Wait for UserManager to fully initialize
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            
            await MainActor.run {
                // Record the initial state AFTER UserManager has loaded
                // If user is already onboarded, we won't show tutorial (returning user)
                // If user is not onboarded, we'll show tutorial when they complete it
                AppLogger.debug("[TUTORIAL] Initial state captured: hasCompletedOnboarding = \(userManager.hasCompletedOnboarding)", category: .ui)
                lastKnownOnboardingState = userManager.hasCompletedOnboarding
            }
            
            // 🔄 ONE-TIME FORCE SYNC: Check if we need to refresh exercise data
            // This ensures users get the latest improved exercise data
            // Bump version when exercise DB schema/data changes (e.g., CSV updates)
            let currentExerciseVersion = "v2.1" // Bumped: exercise classification data update
            let needsRefresh = UserDefaults.standard.string(forKey: "exerciseDataVersion") != currentExerciseVersion
            
            if needsRefresh && SupabaseManager.shared.isAuthenticated {
                AppLogger.debug("Detected new exercise data version - forcing fresh sync...", category: .ui)
                await ExerciseLibraryService.shared.forceSyncExercises()
                UserDefaults.standard.set(currentExerciseVersion, forKey: "exerciseDataVersion")
                AppLogger.info("Exercise data updated to \(currentExerciseVersion)", category: .ui)
            }
        }
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let goButtonVisibilityChanged = Notification.Name("goButtonVisibilityChanged")
    static let scrollToWidget = Notification.Name("scrollToWidget")
}

// MARK: - GO Button State (Singleton)
class GoButtonState: ObservableObject {
    static let shared = GoButtonState()
    @Published var isVisible: Bool = false {
        didSet {
            // Post notification for non-reactive observers
            NotificationCenter.default.post(name: .goButtonVisibilityChanged, object: isVisible)
        }
    }
    private var startAction: (() -> Void)? = nil
    private var isTriggering: Bool = false // Prevent double-triggers
    private var showVersion: Int = 0 // Track show/hide cycles to prevent race conditions
    var primaryColor: Color = Color(red: 0.2, green: 0.7, blue: 0.3)
    var secondaryColor: Color = Color(red: 0.15, green: 0.55, blue: 0.85)
    var accessibilityText: String = "Start workout"
    
    // Tracking
    private var showTime: Date?
    private var showSource: String = ""
    
    private init() {}
    
    func show(primaryColor: Color = Color(red: 0.2, green: 0.7, blue: 0.3),
              secondaryColor: Color? = nil,
              accessibilityText: String = "Start workout",
              source: String = "unknown",
              action: @escaping () -> Void) {
        AppLogger.debug("[GoButton] show() called", category: .ui)
        showTime = Date()
        showSource = source
        
        // Log to session manager
        SessionLogManager.shared.logGoButtonShow(frame: nil)
        SessionLogManager.shared.log(.info, category: .userAction, message: "🟢 GO! SHOW", metadata: [
            "source": source,
            "element_id": "E200"
        ])
        
        // Reset state completely when showing
        self.isTriggering = false
        self.primaryColor = primaryColor
        self.secondaryColor = secondaryColor ?? primaryColor.opacity(0.7)
        self.accessibilityText = accessibilityText
        self.startAction = action
        self.showVersion += 1 // Increment version to invalidate pending hide() calls
        
        DispatchQueue.main.async {
            self.isVisible = true
            AppLogger.debug("[GoButton] isVisible = true", category: .ui)
        }
    }
    
    func hide(reason: String = "navigation") {
        AppLogger.debug("[GoButton] hide() called", category: .ui)
        
        // Calculate visible duration
        var visibleMs: Int = 0
        if let start = showTime {
            visibleMs = Int(Date().timeIntervalSince(start) * 1000)
        }
        
        // Log to session manager
        SessionLogManager.shared.logGoButtonHide(reason: reason)
        SessionLogManager.shared.log(.info, category: .userAction, message: "🔴 GO! HIDE", metadata: [
            "reason": reason,
            "visible_ms": visibleMs,
            "source": showSource,
            "element_id": "E200"
        ])
        
        // Capture current version to check in async block
        let hideVersion = self.showVersion
        
        DispatchQueue.main.async {
            self.isVisible = false
            self.isTriggering = false // Reset triggering state
            
            // Only clear action if no new show() was called since this hide() was initiated
            // This prevents race condition where show() sets action, then pending hide() clears it
            if self.showVersion == hideVersion {
                self.startAction = nil
                AppLogger.debug("[GoButton] Hidden and cleared", category: .ui)
            } else {
                AppLogger.debug("[GoButton] Hidden but action preserved (new show() pending)", category: .ui)
            }
        }
    }
    
    func triggerStart() {
        let startTime = CFAbsoluteTimeGetCurrent()
        AppLogger.debug("[GoButton] triggerStart() BEGIN", category: .ui)
        
        // Calculate response time (how long user took to tap)
        var responseMs: Int = 0
        if let start = showTime {
            responseMs = Int(Date().timeIntervalSince(start) * 1000)
        }
        
        // Log tap to session manager
        SessionLogManager.shared.logGoButtonTap(tapPoint: nil)
        SessionLogManager.shared.log(.info, category: .userAction, message: "👆 GO! TAP", metadata: [
            "response_time_ms": responseMs,
            "source": showSource,
            "element_id": "E200"
        ])
        
        // Prevent double-triggers
        guard !isTriggering else {
            AppLogger.warning("[GoButton] Already triggering, ignoring duplicate call", category: .ui)
            SessionLogManager.shared.log(.warning, category: .userAction, message: "⚠️ GO! DOUBLE TAP BLOCKED")
            return
        }
        
        // Capture action before any state changes
        guard let action = startAction else {
            AppLogger.error("[GoButton] No startAction set!", category: .ui)
            SessionLogManager.shared.log(.error, category: .error, message: "❌ GO! NO ACTION", metadata: [
                "element_id": "E200"
            ])
            return
        }
        
        // Mark as triggering and hide button immediately
        isTriggering = true
        isVisible = false
        
        AppLogger.debug("[GoButton] Executing action...", category: .ui)
        let actionStart = CFAbsoluteTimeGetCurrent()
        
        // Execute action synchronously
        action()
        
        let actionDuration = (CFAbsoluteTimeGetCurrent() - actionStart) * 1000
        let totalDuration = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        
        AppLogger.debug("[GoButton] Action took: \(actionDuration)ms", category: .ui)
        AppLogger.debug("[GoButton] TOTAL: \(totalDuration)ms", category: .ui)
        
        // Log timing
        SessionLogManager.shared.log(.info, category: .userAction, message: "⏱️ GO! ACTION COMPLETE", metadata: [
            "action_duration_ms": Int(actionDuration),
            "total_duration_ms": Int(totalDuration),
            "element_id": "E200"
        ])
        
        // Flag slow action
        if actionDuration > 500 {
            SessionLogManager.shared.log(.warning, category: .userAction, message: "🐢 GO! SLOW ACTION", metadata: [
                "duration_ms": Int(actionDuration),
                "element_id": "E200"
            ])
        }
        
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            self?.startAction = nil
            self?.isTriggering = false
            AppLogger.debug("[GoButton] State reset complete", category: .ui)
        }
    }
}

// Isolated overlay view - only this re-renders when GoButtonState changes
struct GoButtonOverlay: View {
    @ObservedObject var state = GoButtonState.shared
    
    var body: some View {
        if state.isVisible {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    FloatingGoButton(
                        action: { state.triggerStart() },
                        primaryColor: state.primaryColor,
                        secondaryColor: state.secondaryColor,
                        accessibilityText: state.accessibilityText
                    )
                    .offset(x: 3, y: 2) // Fine-tune centering between Exercises and Meals tabs
                    Spacer()
                }
                .padding(.bottom, 18) // Align bottom of button with bottom of tab icons
            }
            .ignoresSafeArea(.keyboard)
            .transition(.opacity)
            .animation(.easeOut(duration: 0.1), value: state.isVisible)
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - Home Badge Counter (Combine-based, prevents render cascade)
// ═══════════════════════════════════════════════════════════════════════════════
/// Lightweight counter that tracks ONLY the Home tab badge count via Combine.
///
/// 🔴 WHY THIS EXISTS:
/// Previously, MainTabView directly observed FriendService (12 @Published),
/// ChallengeService (8 @Published), and PrivateChallengeService (4 @Published).
/// ANY change to ANY of those 24 properties forced a full re-render of ALL 5 tab
/// views — causing catastrophic render cascades during HealthKit sync.
///
/// This class subscribes to only the 5 specific properties needed for the badge
/// and uses .removeDuplicates() so MainTabView ONLY re-renders when the actual
/// badge count changes.
@MainActor
final class HomeBadgeCounter: ObservableObject {
    static let shared = HomeBadgeCounter()
    @Published private(set) var count: Int = 0
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        let friendPending = FriendService.shared.$pendingRequests
            .map(\.count)
        let friendWorkouts = FriendService.shared.$receivedWorkouts
            .map { $0.filter { $0.viewedAt == nil && $0.isPending }.count }
        let challengeInvites = ChallengeService.shared.$pendingInvites
            .map(\.count)
        let groupInvites = ChallengeService.shared.$activeGroupChallenges
            .map { $0.filter(\.isMyInvitePending).count }
        let privateInvites = PrivateChallengeService.shared.$pendingInvites
            .map(\.count)
        
        Publishers.CombineLatest3(friendPending, friendWorkouts, challengeInvites)
            .combineLatest(Publishers.CombineLatest(groupInvites, privateInvites))
            .map { triple, pair in triple.0 + triple.1 + triple.2 + pair.0 + pair.1 }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.count = $0 }
            .store(in: &cancellables)
    }
}

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
                        .accessibilityLabel("Home tab")
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
                        .accessibilityLabel("Workout tab")
                    } else {
                        Label {
                            Text(tabs[2].title)
                        } icon: {
                            Image(systemName: selectedTab == 2 ? tabs[2].selectedIcon : tabs[2].icon)
                        }
                        .accessibilityLabel("Workout tab")
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
                
                // 🔍 FREEZE DEBUG: Step-by-step logging to find where tab switch hangs
                AppLogger.debug("[TAB FREEZE] onChange START: tab \(oldValue)→\(newValue)", category: .ui)
                MainThreadWatchdog.shared.setContext("tab_switch_\(oldValue)→\(newValue)")
                
                // ⚡️ INSTANT TAB SWITCHING: When tabs are preloaded, transition is instant
                let isInstantSwitch = tabPreloader.isPreloadingComplete || lazyTabManager.isEagerModeEnabled
                AppLogger.debug("[TAB FREEZE] step 1: isInstantSwitch=\(isInstantSwitch) (\(String(format: "%.1f", (CACurrentMediaTime() - switchStartTime) * 1000))ms)", category: .ui)
                
                // ⚡️ PERFORMANCE: Start optimized tab transition
                tabSwitchOptimizer.beginTransition(from: oldValue, to: newValue)
                AppLogger.debug("[TAB FREEZE] step 2: beginTransition done (\(String(format: "%.1f", (CACurrentMediaTime() - switchStartTime) * 1000))ms)", category: .ui)
                
                // Mark tab as visited for lazy loading
                if let tab = LazyTabManager.Tab(rawValue: newValue) {
                    lazyTabManager.markVisited(tab)
                    // Only prefetch if not already preloaded
                    if !isInstantSwitch {
                        SmartPrefetch.shared.prefetchForTab(tab)
                    }
                }
                AppLogger.debug("[TAB FREEZE] step 3: markVisited+prefetch done (\(String(format: "%.1f", (CACurrentMediaTime() - switchStartTime) * 1000))ms)", category: .ui)
                
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
                AppLogger.debug("[TAB FREEZE] step 4: session logging done (\(String(format: "%.1f", (CACurrentMediaTime() - switchStartTime) * 1000))ms)", category: .ui)

                scrollToTopTrigger = UUID()
                // Immediately hide GO button when switching tabs
                GoButtonState.shared.hide(reason: "tab_switch")
                AppLogger.debug("[TAB FREEZE] step 5: GoButton hidden (\(String(format: "%.1f", (CACurrentMediaTime() - switchStartTime) * 1000))ms)", category: .ui)
                
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
                
                let onChangeElapsed = (CACurrentMediaTime() - switchStartTime) * 1000
                AppLogger.debug("[TAB FREEZE] step 6: onChange handler COMPLETE (\(String(format: "%.1f", onChangeElapsed))ms)", category: .ui)
                if onChangeElapsed > 100 {
                    AppLogger.warning("[TAB FREEZE] onChange handler took \(String(format: "%.0f", onChangeElapsed))ms — may cause jank", category: .ui)
                }
                
                // ⚡️ End transition tracking (async to not block)
                DispatchQueue.main.async { [self] in
                    let endTime = CACurrentMediaTime()
                    let totalMs = (endTime - switchStartTime) * 1000
                    AppLogger.debug("[TAB FREEZE] step 7: endTransition callback fired (\(String(format: "%.1f", totalMs))ms since start)", category: .ui)
                    tabSwitchOptimizer.endTransition()
                    MainThreadWatchdog.shared.clearContext()
                    AppLogger.debug("[TAB FREEZE] onChange FULLY DONE: tab \(oldValue)→\(newValue) (\(String(format: "%.1f", totalMs))ms)", category: .ui)
                }
            }
            // Defer HealthKit fetches to not block tab switch animation
            if newValue == 0 {
                Task.detached(priority: .background) {
                    try? await Task.sleep(nanoseconds: 300_000_000) // 300ms delay
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

struct TabItem {
    let icon: String
    let selectedIcon: String
    let title: String
    let color: Color
}

// MARK: - Simple Meal Plan View

struct SimpleMealPlanView: View {
    @Environment(\.scrollToTopTrigger) private var scrollToTopTrigger
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var userManager: UserManager
    @StateObject private var mealService = MealService.shared
    @StateObject private var insightsService = PersonalizedInsightsService.shared
    @State private var showingProfileSetup = false
    @State private var showingMacroGoalsExplainer = false
    @AppStorage("hasSeenMacroGoalsExplainer") private var hasSeenMacroGoalsExplainer = false
    @State private var selectedMeal: MealType? = nil {
        didSet {
            AppLogger.debug("[CONTENTVIEW] selectedMeal changed to: \(String(describing: selectedMeal))", category: .ui)
        }
    }
    
    // Quick Action States
    @State private var showMealPlanGenerator = false
    @State private var showRecipeImport = false
    @State private var showRestaurantSearch = false
    @State private var showShoppingList = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Hidden NavigationLink for food search
                NavigationLink(
                    destination: Group {
                        if let meal = selectedMeal {
                            FoodSearchView(mealType: meal) { foodEntry in
                                AppLogger.debug("[CONTENTVIEW] Food entry received: \(foodEntry.name), meal: \(meal.rawValue), calories: \(foodEntry.calories)", category: .ui)
                                
                                // Save to meal service
                                if let user = userManager.currentUser {
                                    AppLogger.debug("[CONTENTVIEW] User found, calling MealService.addMealEntry", category: .ui)
                                    MealService.shared.addMealEntry(foodEntry, mealType: meal, user: user)
                                    AppLogger.debug("[CONTENTVIEW] MealService.addMealEntry completed", category: .ui)
                                    
                                    // Show macro goals explainer on first meal input
                                    if !hasSeenMacroGoalsExplainer {
                                        Task { @MainActor in
                                            try? await Task.sleep(nanoseconds: 500_000_000)
                                            showingMacroGoalsExplainer = true
                                            hasSeenMacroGoalsExplainer = true
                                        }
                                    }
                                } else {
                                    AppLogger.error("[CONTENTVIEW] No current user found!", category: .ui)
                                }
                                
                                // Reset selection to dismiss
                                selectedMeal = nil
                            }
                            .environmentObject(userManager)
                            .onAppear {
                                AppLogger.debug("[CONTENTVIEW] FoodSearchView appeared for meal: \(meal.rawValue)", category: .ui)
                            }
                        }
                    },
                    isActive: Binding(
                        get: { selectedMeal != nil },
                        set: { if !$0 { selectedMeal = nil } }
                    )
                ) {
                    EmptyView()
                }
                .frame(width: 0, height: 0)
                .hidden()
                
            ScrollViewReader { scrollProxy in
                ScrollView {
                    Color.clear.frame(height: 0).id("top")
                    
                    VStack(spacing: 0) {
                        // Custom header
                        customNutritionHeaderView
                            .padding(.top, 4)
                            .padding(.bottom, 16)
                        
                        VStack(spacing: 24) {
                            if needsProfileSetup {
                                profileSetupCard
                            } else {
                                // Comprehensive nutrition content
                                comprehensiveNutritionView
                            }
                        }
                        .onAppear {
                            // 🧠 Fetch personalized insights for daily insights card
                            Task {
                                await insightsService.fetchActiveInsights()
                                await insightsService.fetchStreaks()
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.top, 8)
                    .padding(.bottom, 20)
                }
                .background(
                    AnimatedOrbBackground.home(colorScheme: colorScheme)
                )
                .onChange(of: scrollToTopTrigger) { _, _ in
                    scrollProxy.scrollTo("top", anchor: .top)
                }
                // Handle deep link scroll-to-widget notifications
                .onReceive(NotificationCenter.default.publisher(for: .scrollToWidget)) { notification in
                    guard let widgetId = notification.object as? String else { return }
                    withAnimation(.easeInOut(duration: 0.3)) {
                        switch widgetId {
                        case "hydration":
                            scrollProxy.scrollTo("hydration", anchor: .center)
                            AppLogger.debug("[MEALS] Scrolled to Hydration widget", category: .ui)
                        case "weightTracker":
                            scrollProxy.scrollTo("weightTracker", anchor: .center)
                            AppLogger.debug("[MEALS] Scrolled to Weight Tracker widget", category: .ui)
                        default:
                            break
                        }
                    }
                }
            }
            .navigationBarHidden(true)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            }
        }
        .onAppear {
            AppLogger.debug("[MEAL PLAN] View appeared, loading today's meals", category: .ui)
            mealService.loadTodaysMeals()
            AppLogger.debug("[MEAL PLAN] Loaded \(mealService.todaysMeals.count) meals, consumed calories: \(consumedCalories)", category: .ui)
        }
        .onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .sheet(isPresented: $showingProfileSetup) {
            SimpleProfileSetupView(showingProfileSetup: $showingProfileSetup)
        }
        .sheet(isPresented: $showingMacroGoalsExplainer) {
            MacroGoalsExplainerView()
        }
        .sheet(isPresented: $showMealPlanGenerator) {
            SmartMealPlannerView()
                .environmentObject(userManager)
        }
        .sheet(isPresented: $showRecipeImport) {
            RecipeImportSheet()
        }
        .sheet(isPresented: $showRestaurantSearch) {
            RestaurantSearchSheet()
                .environmentObject(userManager)
        }
        .sheet(isPresented: $showShoppingList) {
            MyShoppingListView()
        }
    }
    
    // MARK: - Actual Consumed Data
    private var sampleMacroData: [MacronutrientData] {
        [
            MacronutrientData(name: "Protein", value: Double(consumedProtein), color: .blue, calories: Double(consumedProtein * 4)),
            MacronutrientData(name: "Carbs", value: Double(consumedCarbs), color: .orange, calories: Double(consumedCarbs * 4)),
            MacronutrientData(name: "Fat", value: Double(consumedFat), color: .red, calories: Double(consumedFat * 9))
        ]
    }
    
    // MARK: - Goal Data (for empty state)
    private var goalMacroData: [MacronutrientData] {
        [
            MacronutrientData(name: "Protein", value: Double(proteinGoal), color: .blue, calories: Double(proteinGoal * 4)),
            MacronutrientData(name: "Carbs", value: Double(carbGoal), color: .orange, calories: Double(carbGoal * 4)),
            MacronutrientData(name: "Fat", value: Double(fatGoal), color: .red, calories: Double(fatGoal * 9))
        ]
    }
    
    private var sampleNutritionInsights: [NutritionInsight] {
        [
            NutritionInsight(
                title: "Hydration",
                value: "6.2L",
                subtitle: "Daily water intake",
                icon: "drop.fill",
                color: .blue,
                trend: "+12%"
            ),
            NutritionInsight(
                title: "Fiber",
                value: "28g",
                subtitle: "Daily fiber intake",
                icon: "leaf.fill",
                color: .green,
                trend: "Goal met"
            ),
            NutritionInsight(
                title: "Meal Timing",
                value: "6.5hrs",
                subtitle: "Average meal spacing",
                icon: "clock.fill",
                color: .purple,
                trend: "Optimal"
            ),
            NutritionInsight(
                title: "Food Quality",
                value: "85%",
                subtitle: "Whole food sources",
                icon: "star.fill",
                color: .yellow,
                trend: "+3%"
            )
        ]
    }
    
    // MARK: - Custom Header View
    private var customNutritionHeaderView: some View {
        HStack {
            Text("Nutrition")
                .font(.ds_displayLarge)
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.teal, Color.teal, Color.mint.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: Color.teal.opacity(0.4), radius: 6, x: 0, y: 2)
            
            Spacer()
            
            // Active workout timer (only shows when workout is active)
            if WorkoutManager.shared.isWorkoutActive {
                Text(WorkoutManager.shared.formattedDuration)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .fill(.ultraThinMaterial)
                    )
            }
        }
        .padding(.leading, 4)
    }
    
    private var needsProfileSetup: Bool {
        guard let user = userManager.currentUser else { return true }
        
        // Check if user has weight and height in their profile
        // First check Core Data, fallback to UserDefaults for legacy data
        let userWeight = user.weight > 0 ? Int(user.weight) : UserDefaults.standard.integer(forKey: "userWeight")
        let userHeight = user.height > 0 ? Int(user.height) : UserDefaults.standard.integer(forKey: "userHeight")
        
        return userWeight == 0 || userHeight == 0
    }
    
    // MARK: - Consumed Macros Calculations
    
    private var consumedCalories: Int {
        mealService.todaysMeals.reduce(0) { $0 + Int($1.calories) }
    }
    
    private var consumedProtein: Int {
        mealService.todaysMeals.reduce(0) { $0 + Int($1.protein) }
    }
    
    private var consumedCarbs: Int {
        mealService.todaysMeals.reduce(0) { $0 + Int($1.carbs) }
    }
    
    private var consumedFat: Int {
        mealService.todaysMeals.reduce(0) { $0 + Int($1.fat) }
    }
    
    private var calorieGoal: Int {
        // Calculate based on user's weight, height, and activity level
        guard let user = userManager.currentUser else { return 2200 }
        let weight = user.weight > 0 ? Int(user.weight) : UserDefaults.standard.integer(forKey: "userWeight")
        let height = user.height > 0 ? Int(user.height) : UserDefaults.standard.integer(forKey: "userHeight")
        
        // Simple BMR calculation (Mifflin-St Jeor equation for males)
        if weight > 0 && height > 0 {
            let bmr = (10.0 * Double(weight)) + (6.25 * Double(height)) - (5.0 * Double(user.age)) + 5.0
            return Int(bmr * 1.55) // Moderate activity level
        }
        return 2200 // Default
    }
    
    private var proteinGoal: Int {
        // 30% of calories from protein (1g = 4 calories)
        return (calorieGoal * 30 / 100) / 4
    }
    
    private var carbGoal: Int {
        // 40% of calories from carbs (1g = 4 calories)
        return (calorieGoal * 40 / 100) / 4
    }
    
    private var fatGoal: Int {
        // 30% of calories from fat (1g = 9 calories)
        return (calorieGoal * 30 / 100) / 9
    }
    
    // Progress values for nutrition rings
    private var caloriesProgress: Double {
        guard calorieGoal > 0 else { return 0 }
        return min(Double(consumedCalories) / Double(calorieGoal), 1.0)
    }
    
    private var proteinProgress: Double {
        guard proteinGoal > 0 else { return 0 }
        return min(Double(consumedProtein) / Double(proteinGoal), 1.0)
    }
    
    private var fatProgress: Double {
        guard fatGoal > 0 else { return 0 }
        return min(Double(consumedFat) / Double(fatGoal), 1.0)
    }
    
    // Check if user exceeded the buffer (for visual warning)
    private var caloriesExceeded: Bool {
        let calorieMax = Int(Double(calorieGoal) * 1.15)
        return consumedCalories > calorieMax
    }
    
    private var fatExceeded: Bool {
        let fatMax = Int(Double(fatGoal) * 1.20)
        return consumedFat > fatMax
    }
    
    private var profileSetupCard: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 60))
                .foregroundColor(.green)
            
            VStack(spacing: 8) {
                Text("Complete Your Profile")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Based on your goal: \"\(userManager.currentUser?.fitnessGoal ?? "Build Muscle")\", we'll calculate your personalized nutrition targets.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button("Set Up Nutrition Goals") {
                showingProfileSetup = true
            }
            .font(.headline)
            .fontWeight(.bold)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [Color.green, Color.mint]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(CornerRadius.md)
        }
        .padding(Spacing.xl)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.xl)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
        )
    }
    
    // MARK: - Redesigned Nutrition Overview
    private var nutritionOverviewCard: some View {
        VStack(spacing: 20) {
            // Header similar to home tab
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Today's Nutrition")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text("Track your daily intake")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Removed View All button - content now on main page
            }
            
            // Macronutrient Cards with home tab styling
            HStack(spacing: 12) {
                NutritionMetricCard(title: "Calories", current: consumedCalories, goal: calorieGoal, unit: "", color: .red, icon: "flame.fill")
                NutritionMetricCard(title: "Protein", current: consumedProtein, goal: proteinGoal, unit: "g", color: .blue, icon: "dumbbell.fill")
                NutritionMetricCard(title: "Carbs", current: consumedCarbs, goal: carbGoal, unit: "g", color: .orange, icon: "leaf.fill")
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.xl)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
        )
    }
    
    // Helper: Find which meal type was logged most recently
    private var mostRecentMealType: MealType? {
        guard !mealService.todaysMeals.isEmpty else { return nil }
        let sortedMeals = mealService.todaysMeals.sorted { $0.date > $1.date }
        return sortedMeals.first?.mealType
    }
    
    // Current meal time colors based on time of day
    private var currentMealTimeColors: (primary: Color, secondary: Color) {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<10:  // Breakfast: 5 AM - 9:59 AM
            return (.orange, .yellow)
        case 10..<12: // Morning snack: 10 AM - 11:59 AM
            return (.purple, .pink)
        case 12..<14: // Lunch: 12 PM - 1:59 PM
            return (.green, .teal)
        case 14..<18: // Afternoon snack: 2 PM - 5:59 PM
            return (.purple, .pink)
        default:      // Dinner: 6 PM onward & late night
            return (.blue, .cyan)
        }
    }
    
    // MARK: - Swipeable Meal Carousel (like Challenge/Program widget)
    @State private var selectedMealPage: Int = -1 // -1 means not initialized
    @State private var selectedNutritionPage = 1 // Default to macros (center card)
    @State private var insightsViewMode = 0 // 0 = icons/numbers, 1 = text insights
    
    /// Get the current meal time index based on time of day
    private var currentMealTimeIndex: Int {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<10:  return 0 // Breakfast: 5 AM - 9:59 AM
        case 10..<12: return 3 // Morning snack: 10 AM - 11:59 AM
        case 12..<14: return 1 // Lunch: 12 PM - 1:59 PM
        case 14..<18: return 3 // Afternoon snack: 2 PM - 5:59 PM
        default:      return 2 // Dinner: 6 PM onward & late night
        }
    }
    
    private var mealSectionsCard: some View {
        let mealTypes: [MealType] = [.breakfast, .lunch, .dinner, .snacks]
        let currentIndex = currentMealTimeIndex
        
        return VStack(spacing: 8) {
            // Section header
            HStack {
                Image(systemName: "fork.knife")
                    .font(.ds_heading2)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [mealTypes[max(0, selectedMealPage == -1 ? currentIndex : selectedMealPage)].gradientColors.0,
                                    mealTypes[max(0, selectedMealPage == -1 ? currentIndex : selectedMealPage)].gradientColors.1],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                Text("Track Your Meal")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Spacer()
            }
            .padding(.horizontal, Spacing.xxs)
            
            // Swipeable meal cards
            GeometryReader { geometry in
                let cardWidth = geometry.size.width
                let spacing: CGFloat = 16
                let pageIndex = selectedMealPage == -1 ? currentIndex : selectedMealPage
                
                HStack(spacing: spacing) {
                    ForEach(0..<mealTypes.count, id: \.self) { index in
                        SwipeableMealCard(
                            mealType: mealTypes[index],
                            meals: mealService.todaysMeals.filter { $0.mealType == mealTypes[index] },
                            isCurrentMealTime: index == currentIndex,
                            onAddFood: {
                                selectedMeal = mealTypes[index]
                            },
                            onDelete: { meal in
                                mealService.removeMealEntry(meal)
                            }
                        )
                        .frame(width: cardWidth)
                        .opacity(pageIndex == index ? 1 : 0)
                    }
                }
                .offset(x: -CGFloat(pageIndex) * (cardWidth + spacing))
            }
            .frame(height: 180)
            .animation(.easeOut(duration: 0.25), value: selectedMealPage == -1 ? currentIndex : selectedMealPage)
            .highPriorityGesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { value in
                        let horizontalAmount = value.translation.width
                        let verticalAmount = abs(value.translation.height)
                        let pageIndex = selectedMealPage == -1 ? currentIndex : selectedMealPage
                        
                        // Only trigger if movement is primarily horizontal
                        if abs(horizontalAmount) > verticalAmount * 1.5 && abs(horizontalAmount) > 20 {
                            HapticManager.impact(.medium)
                            if horizontalAmount < 0 && pageIndex < mealTypes.count - 1 {
                                // Swipe left - go to next
                                selectedMealPage = pageIndex + 1
                            } else if horizontalAmount > 0 && pageIndex > 0 {
                                // Swipe right - go to previous
                                selectedMealPage = pageIndex - 1
                            }
                        }
                    }
            )
            
            // Page indicators (tappable)
            HStack(spacing: 6) {
                ForEach(0..<mealTypes.count, id: \.self) { index in
                    let pageIndex = selectedMealPage == -1 ? currentIndex : selectedMealPage
                    let isSelected = pageIndex == index
                    let mealColor = mealTypes[index].gradientColors.0
                    
                    Circle()
                        .fill(isSelected ? mealColor : Color.gray.opacity(0.3))
                        .frame(width: 6, height: 6)
                        .scaleEffect(isSelected ? 1.0 : 0.8)
                        .animation(.easeOut(duration: 0.2), value: pageIndex)
                        .onTapGesture {
                            HapticManager.impact(.light)
                            selectedMealPage = index
                        }
                }
            }
            .padding(.vertical, Spacing.xxs)
        }
        .onAppear {
            // Initialize to current meal time on first appear
            if selectedMealPage == -1 {
                selectedMealPage = currentIndex
            }
        }
    }
    
    // MARK: - Main Comprehensive Nutrition View
    private var comprehensiveNutritionView: some View {
        VStack(spacing: 16) {
            // 0. "What Should I Eat?" contextual card
            WhatToEatDashboardCard()
                .padding(.horizontal, Spacing.md)
            
            // 1. Today's Macros + Weekly Progress (swipeable cards)
            nutritionSwipeableCards
            
            // 2. Track Your Meals - ALL meals visible at once (old design)
            allMealSectionsView
            
            // 3. Quick Actions - Meal Plan, Import, Restaurant, Shopping (same style as workout buttons)
            MealsQuickActionsView(
                showMealPlanGenerator: $showMealPlanGenerator,
                showRecipeImport: $showRecipeImport,
                showRestaurantSearch: $showRestaurantSearch,
                showShoppingList: $showShoppingList
            )
            
            // 4. Healthy Recipes Carousel - Swipeable recipe cards from Spoonacular
            HealthyRecipesCarousel()
            
            // 5. Weight Tracking - Daily weigh-ins and progress
            WeightTrackerWidget()
                .id("weightTracker")
            
            // 6. Hydration Tracking
            HydrationWidget()
                .id("hydration")
        }
    }
    
    // MARK: - All Meals View (shows all meal sections at once)
    private var allMealSectionsView: some View {
        VStack(spacing: 12) {
            // Section header
            HStack {
                Image(systemName: "fork.knife")
                    .font(.ds_heading2)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.green, .mint],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                Text("Track Your Meals")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Spacer()
            }
            .padding(.horizontal, Spacing.xxs)
            
            // All meal sections stacked
            ForEach(MealType.allCases, id: \.self) { mealType in
                compactMealSection(for: mealType)
            }
        }
    }
    
    // MARK: - Compact Meal Section (for all-meals view)
    private func compactMealSection(for mealType: MealType) -> some View {
        let meals = mealService.todaysMeals.filter { $0.mealType == mealType }
        let isCurrentMealTime = currentMealTimeIndex == MealType.allCases.firstIndex(of: mealType)
        
        return VStack(alignment: .leading, spacing: 8) {
            // Header row
            HStack {
                // Meal icon with gradient
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [mealType.gradientColors.0, mealType.gradientColors.1],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: mealType.icon)
                        .font(.ds_labelMedium)
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(mealType.displayName)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        if isCurrentMealTime {
                            Text("NOW")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(mealType.gradientColors.0)
                                )
                        }
                    }
                    
                    Text(mealType.timeDescription)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Add button
                Button {
                    selectedMeal = mealType
                } label: {
                    Text("+ Add Food")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [mealType.gradientColors.0, mealType.gradientColors.1],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                }
            }
            
            // Logged items or empty state
            if meals.isEmpty {
                HStack {
                    Text("No food logged yet")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("Tap + to add your \(mealType.displayName.lowercased())")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .padding(.leading, 40)
            } else {
                VStack(spacing: 4) {
                    ForEach(meals, id: \.id) { meal in
                        HStack {
                            Text(meal.foodName)
                                .font(.caption)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            
                            Spacer()
                            
                            Text("\(meal.calories) cal")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Button {
                                mealService.removeMealEntry(meal)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(.secondary.opacity(0.5))
                            }
                        }
                        .padding(.leading, 40)
                    }
                }
            }
        }
        .padding(Spacing.sm)
        .background(
            ZStack {
                if isCurrentMealTime {
                    // Bottom shadow layer (deepest) - color glow for current meal
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(mealType.gradientColors.0.opacity(colorScheme == .dark ? 0.2 : 0.12))
                        .offset(y: 6)
                        .blur(radius: 6)
                    
                    // Middle shadow layer
                    RoundedRectangle(cornerRadius: 25, style: .continuous)
                        .fill(Color.black.opacity(colorScheme == .dark ? 0.15 : 0.03))
                        .offset(y: 3)
                }
                
                // Main card background
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(colorScheme == .dark ? Color.cardBackground : Color.white)
                
                if isCurrentMealTime {
                    // Inner highlight (top edge glow)
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: colorScheme == .dark
                                    ? [Color.white.opacity(0.08), Color.white.opacity(0.02), Color.clear]
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
                                colors: [mealType.gradientColors.0.opacity(colorScheme == .dark ? 0.5 : 0.4), mealType.gradientColors.1.opacity(colorScheme == .dark ? 0.4 : 0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                }
            }
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.06), radius: isCurrentMealTime ? 12 : 8, x: 0, y: isCurrentMealTime ? 6 : 4)
        .shadow(color: isCurrentMealTime ? mealType.gradientColors.0.opacity(colorScheme == .dark ? 0.25 : 0.15) : Color.clear, radius: 16, x: 0, y: 8)
    }
    
    // MARK: - Swipeable Nutrition Cards (Insights, Macros & Weekly Progress)
    private var nutritionSwipeableCards: some View {
        VStack(spacing: 12) {
            // Swipeable header (changes with cards)
            GeometryReader { geometry in
                let headerWidth = geometry.size.width
                let spacing: CGFloat = 16
                
                HStack(spacing: spacing) {
                    // Header 0: Daily Insights
                    HStack {
                        Image(systemName: "lightbulb.fill")
                            .font(.ds_heading2)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.teal, .mint],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        Text("Daily Insights")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        // Score summary
                        VStack(alignment: .trailing, spacing: 0) {
                            Text("\(insightsScore)")
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(insightsScoreColor)
                            
                            Text("score")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(width: headerWidth)
                    .opacity(selectedNutritionPage == 0 ? 1 : 0)
                    
                    // Header 1: Today's Macros (center/default)
                    HStack {
                        Image(systemName: "chart.pie.fill")
                            .font(.ds_heading2)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.teal, .mint],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        Text("Today's Macros")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        // Calorie summary
                        VStack(alignment: .trailing, spacing: 0) {
                            Text("\(consumedCalories)")
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(caloriesExceeded ? .red : .primary)
                            
                            Text("of \(calorieGoal) cal")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(width: headerWidth)
                    .opacity(selectedNutritionPage == 1 ? 1 : 0)
                    
                    // Header 2: Weekly Progress
                    HStack {
                        Image(systemName: "chart.bar.fill")
                            .font(.ds_heading2)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.teal, .mint],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        Text("Weekly Progress")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        // Weekly summary
                        VStack(alignment: .trailing, spacing: 0) {
                            Text("\(weeklyCalorieDaysMet)/7")
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                            
                            Text("days on target")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(width: headerWidth)
                    .opacity(selectedNutritionPage == 2 ? 1 : 0)
                }
                .offset(x: -CGFloat(selectedNutritionPage) * (headerWidth + spacing))
            }
            .frame(height: 28)
            .padding(.horizontal, Spacing.xxs)
            .animation(.easeOut(duration: 0.25), value: selectedNutritionPage)
            
            // Swipeable cards
            GeometryReader { geometry in
                let cardWidth = geometry.size.width
                let spacing: CGFloat = 16
                
                HStack(spacing: spacing) {
                    // Card 0: Daily Insights
                    dailyInsightsCard
                        .frame(width: cardWidth)
                        .opacity(selectedNutritionPage == 0 ? 1 : 0)
                    
                    // Card 1: Today's Macros (center/default)
                    todaysMacrosCard
                        .frame(width: cardWidth)
                        .opacity(selectedNutritionPage == 1 ? 1 : 0)
                    
                    // Card 2: Weekly Progress
                    weeklyProgressCard
                        .frame(width: cardWidth)
                        .opacity(selectedNutritionPage == 2 ? 1 : 0)
                }
                .offset(x: -CGFloat(selectedNutritionPage) * (cardWidth + spacing))
            }
            .frame(height: 145)
            .animation(.easeOut(duration: 0.25), value: selectedNutritionPage)
            .highPriorityGesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { value in
                        let horizontalAmount = value.translation.width
                        let verticalAmount = abs(value.translation.height)
                        
                        // Only trigger if movement is primarily horizontal
                        if abs(horizontalAmount) > verticalAmount * 1.5 && abs(horizontalAmount) > 20 {
                            HapticManager.impact(.medium)
                            if horizontalAmount < 0 && selectedNutritionPage < 2 {
                                // Swipe left - go to next card
                                selectedNutritionPage += 1
                            } else if horizontalAmount > 0 && selectedNutritionPage > 0 {
                                // Swipe right - go to previous card
                                selectedNutritionPage -= 1
                            }
                        }
                    }
            )
            
            // Page indicators - right below the card
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(selectedNutritionPage == index ? Color.teal : Color.gray.opacity(0.3))
                        .frame(width: 6, height: 6)
                        .scaleEffect(selectedNutritionPage == index ? 1.0 : 0.8)
                        .animation(.easeOut(duration: 0.2), value: selectedNutritionPage)
                        .onTapGesture {
                            HapticManager.impact(.light)
                            selectedNutritionPage = index
                        }
                }
            }
        }
    }
    
    // MARK: - Daily Insights Card
    private var dailyInsightsCard: some View {
        HStack(spacing: 0) {
            // Main content area - toggles between icons and text on tap
            ZStack {
                // View 0: Floating icons/numbers
                insightsIconsView
                    .opacity(insightsViewMode == 0 ? 1 : 0)
                    .scaleEffect(insightsViewMode == 0 ? 1 : 0.95)
                
                // View 1: Text insights
                insightsTextView
                    .opacity(insightsViewMode == 1 ? 1 : 0)
                    .scaleEffect(insightsViewMode == 1 ? 1 : 0.95)
            }
            .animation(.easeOut(duration: 0.2), value: insightsViewMode)
            .frame(maxWidth: .infinity)
            .padding(.leading, 12)
            
            // Vertical page indicators - flush right edge
            VStack(spacing: 6) {
                ForEach(0..<2, id: \.self) { index in
                    Circle()
                        .fill(insightsViewMode == index ? Color.teal : Color.gray.opacity(0.3))
                        .frame(width: 6, height: 6)
                        .scaleEffect(insightsViewMode == index ? 1.0 : 0.8)
                        .animation(.easeOut(duration: 0.2), value: insightsViewMode)
                }
            }
            .padding(.trailing, 8)
            .padding(.leading, 4)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(insightsCardBackground)
        .contentShape(Rectangle())
        .onTapGesture {
            HapticManager.impact(.light)
            withAnimation(.easeOut(duration: 0.2)) {
                insightsViewMode = insightsViewMode == 0 ? 1 : 0
            }
        }
    }
    
    // Shared card background for insights (teal glow - matches other cards)
    private var insightsCardBackground: some View {
        ZStack {
            // Bottom shadow layer - teal glow
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.teal.opacity(colorScheme == .dark ? 0.15 : 0.08))
                .offset(y: 6)
                .blur(radius: 3)
            
            // Middle shadow layer
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                .offset(y: 3)
            
            // Main card background
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color(white: 0.14), Color(white: 0.09)]
                            : [Color.white, Color.white.opacity(0.95)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            
            // Inner highlight
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color.white.opacity(0.1), Color.white.opacity(0.02), Color.clear]
                            : [Color.white, Color.white.opacity(0.5), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            
            // Teal accent border (matches other cards)
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
    }
    
    // MARK: - Insights Icons View (floating icons with values)
    private var insightsIconsView: some View {
        VStack {
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                MiniInsightTile(
                    icon: "drop.fill",
                    title: "Hydration",
                    value: hydrationPercentage,
                    color: .blue
                )
                
                MiniInsightTile(
                    icon: "leaf.fill",
                    title: "Protein",
                    value: proteinPercentage,
                    color: .green
                )
                
                MiniInsightTile(
                    icon: "flame.fill",
                    title: "Calories",
                    value: caloriePercentage,
                    color: .orange
                )
                
                MiniInsightTile(
                    icon: "fork.knife",
                    title: "Meals",
                    value: mealsLoggedToday,
                    color: .purple
                )
            }
            Spacer(minLength: 0)
        }
    }
    
    // MARK: - Insights Text View (actionable text insights)
    private var insightsTextView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Generate smart text insights based on current data (limit to 3)
            // Evenly spaced to fill the card
            ForEach(Array(generateTextInsights().prefix(3).enumerated()), id: \.element) { index, insight in
                if index > 0 {
                    Spacer(minLength: 0)
                }
                
                HStack(spacing: 8) {
                    Image(systemName: insight.icon)
                        .font(.ds_bodySmall)
                        .foregroundColor(insight.color)
                        .frame(width: 16)
                    
                    Text(insight.text)
                        .font(.ds_bodySmall).fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                    
                    Spacer(minLength: 0)
                }
                
                if index < 2 {
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, Spacing.xs)
        .frame(maxHeight: .infinity)
    }
    
    // Generate smart text insights (detailed style matching SmartDailySummaryWidget)
    private func generateTextInsights() -> [InsightItem] {
        var insights: [InsightItem] = []
        let hour = Calendar.current.component(.hour, from: Date())
        
        // 🧠 PERSONALIZED INSIGHTS: Add database-driven insights first (highest priority)
        for personalInsight in insightsService.activeInsights.prefix(1) {
            // Only show nutrition-related insights here
            if personalInsight.insightCategory == .nutrition || 
               personalInsight.insightCategory == .goal ||
               personalInsight.insightCategory == .streak {
                insights.append(InsightItem(
                    icon: personalInsight.icon,
                    text: personalInsight.message,
                    color: personalInsight.color
                ))
            }
        }
        
        // 🔥 STREAK-BASED INSIGHTS: Show relevant streaks
        if let proteinStreak = insightsService.streaks.first(where: { $0.streakType == "protein_goal" }),
           proteinStreak.currentStreak >= 3 {
            insights.append(InsightItem(
                icon: "flame.fill",
                text: "\(proteinStreak.currentStreak)-day protein streak! Keep it going! 🔥",
                color: .orange
            ))
        }
        
        if let hydrationStreak = insightsService.streaks.first(where: { $0.streakType == "hydration" }),
           hydrationStreak.currentStreak >= 3 {
            insights.append(InsightItem(
                icon: "drop.fill",
                text: "\(hydrationStreak.currentStreak) days hitting hydration! 💧",
                color: .cyan
            ))
        }
        
        // Protein insight with quick fix suggestions
        let proteinRemaining = max(0, proteinGoal - consumedProtein)
        let proteinProgress = proteinGoal > 0 ? Double(consumedProtein) / Double(proteinGoal) : 0
        if proteinProgress < 0.6 && hour >= 14 {
            let quickFixes = ["Greek yogurt (20g)", "chicken breast (30g)", "protein shake (25g)", "3 eggs (18g)", "cottage cheese (14g)"]
            insights.append(InsightItem(icon: "arrow.up.circle.fill", text: "Need \(proteinRemaining)g protein still! Quick fix: \(quickFixes.randomElement()!)", color: .blue))
        } else if proteinRemaining > 0 {
            insights.append(InsightItem(icon: "arrow.up.circle", text: "Add \(proteinRemaining)g more protein – your muscles are waiting! 💪", color: .blue))
        } else {
            insights.append(InsightItem(icon: "checkmark.seal.fill", text: "Protein goal crushed! Your body has the building blocks it needs. 🏗️", color: .green))
        }
        
        // Calorie insight with context
        let caloriesRemaining = calorieGoal - consumedCalories
        let calorieProgress = calorieGoal > 0 ? Double(consumedCalories) / Double(calorieGoal) : 0
        if calorieProgress < 0.5 && hour >= 14 {
            insights.append(InsightItem(icon: "exclamationmark.triangle.fill", text: "Only \(consumedCalories) cal by afternoon! Under-eating slows metabolism. 🍽️", color: .red))
        } else if calorieProgress > 1.2 {
            let over = consumedCalories - calorieGoal
            insights.append(InsightItem(icon: "chart.bar.xaxis.ascending", text: "\(over) cal over budget. Consider a lighter dinner or evening walk! 🚶", color: .orange))
        } else if caloriesRemaining > 200 {
            insights.append(InsightItem(icon: "flame.fill", text: "\(caloriesRemaining) calories remaining – keep fueling your day! ⚡", color: .orange))
        } else if caloriesRemaining > 0 {
            insights.append(InsightItem(icon: "target", text: "Almost at calorie goal! Just \(caloriesRemaining) cal to go. 🎯", color: .green))
        } else {
            insights.append(InsightItem(icon: "checkmark.circle.fill", text: "Calorie goal reached! Perfect balance today. 🎯", color: .green))
        }
        
        // Hydration insight with urgency
        let hydrationProgress = HydrationService.shared.todayProgress
        let waterGoal = HydrationService.shared.settings.dailyGoalMl
        let waterIntake = HydrationService.shared.todayTotal
        if hydrationProgress < 0.3 && hour >= 14 {
            let remainingMl = waterGoal - waterIntake
            insights.append(InsightItem(icon: "drop.triangle.fill", text: "Dehydration alert! ⚠️ Drink \(remainingMl)ml to catch up – your brain needs it!", color: .red))
        } else if hydrationProgress < 0.5 {
            let remainingMl = waterGoal - waterIntake
            insights.append(InsightItem(icon: "drop", text: "\(remainingMl)ml to go! Keep a water bottle nearby. 💧", color: .cyan))
        } else if hydrationProgress >= 1.0 {
            insights.append(InsightItem(icon: "drop.fill", text: "Hydration on point! Your body is thanking you. 💧", color: .cyan))
        }
        
        // Meals insight
        let mealsLogged = mealService.getMealsForDate(Date()).count
        if mealsLogged == 0 && hour >= 11 {
            insights.append(InsightItem(icon: "pencil.and.list.clipboard", text: "No meals logged yet! Even a quick entry helps you stay aware. 📝", color: .gray))
        } else if mealsLogged == 1 && hour >= 15 {
            insights.append(InsightItem(icon: "clock.fill", text: "Only 1 meal tracked. Logging helps identify patterns! 📊", color: .gray))
        }
        
        return insights
    }
    
    // Computed properties for insights
    private var hydrationPercentage: String {
        // Calculate from hydration service
        let current = HydrationService.shared.todayTotal
        let goal = HydrationService.shared.settings.dailyGoalMl
        let percent = goal > 0 ? Int((Double(current) / Double(goal)) * 100) : 0
        return "\(percent)%"
    }
    
    private var proteinPercentage: String {
        let percent = proteinGoal > 0 ? Int((Double(consumedProtein) / Double(proteinGoal)) * 100) : 0
        return "\(percent)%"
    }
    
    private var caloriePercentage: String {
        let percent = calorieGoal > 0 ? Int((Double(consumedCalories) / Double(calorieGoal)) * 100) : 0
        return "\(percent)%"
    }
    
    private var mealsLoggedToday: String {
        let count = MealService.shared.getMealsForDate(Date()).count
        return "\(count) logged"
    }
    
    // Score for insights header
    private var insightsScore: Int {
        var score = 0
        
        // Calorie accuracy (max 30 points)
        let calorieProgressValue = calorieGoal > 0 ? Double(consumedCalories) / Double(calorieGoal) : 0
        let calorieDiff = abs(calorieProgressValue - 1.0)
        if calorieDiff < 0.1 { score += 30 }
        else if calorieDiff < 0.2 { score += 20 }
        else if calorieDiff < 0.3 { score += 10 }
        
        // Protein goal (max 30 points)
        let proteinProgressValue = proteinGoal > 0 ? Double(consumedProtein) / Double(proteinGoal) : 0
        if proteinProgressValue >= 1.0 { score += 30 }
        else if proteinProgressValue >= 0.8 { score += 20 }
        else if proteinProgressValue >= 0.6 { score += 10 }
        
        // Meals logged (max 20 points)
        let mealCount = MealService.shared.getMealsForDate(Date()).count
        if mealCount >= 3 { score += 20 }
        else if mealCount >= 2 { score += 15 }
        else if mealCount >= 1 { score += 10 }
        
        // Hydration (max 20 points)
        let hydrationGoal = HydrationService.shared.settings.dailyGoalMl
        let hydrationPercent = hydrationGoal > 0 
            ? Double(HydrationService.shared.todayTotal) / Double(hydrationGoal) 
            : 0
        if hydrationPercent >= 1.0 { score += 20 }
        else if hydrationPercent >= 0.7 { score += 15 }
        else if hydrationPercent >= 0.5 { score += 10 }
        
        return score
    }
    
    private var insightsScoreColor: Color {
        if insightsScore >= 80 { return .green }
        else if insightsScore >= 60 { return .yellow }
        else if insightsScore >= 40 { return .orange }
        else { return .red }
    }
    
    // MARK: - Today's Macros Card
    private var todaysMacrosCard: some View {
        // Nutrition Rings with Legend (no header - header is outside)
        HStack(spacing: 16) {
            // Triple Nutrition Ring (shows red + warning if exceeded)
            NutritionTripleRing(
                caloriesProgress: caloriesProgress,
                proteinProgress: proteinProgress,
                fatProgress: fatProgress,
                size: 95,
                caloriesExceeded: caloriesExceeded,
                fatExceeded: fatExceeded
            )
            
            VStack(alignment: .leading, spacing: 10) {
                MacroLegendRow(name: "Calories", current: consumedCalories, goal: calorieGoal, color: caloriesExceeded ? .red : .teal, exceeded: caloriesExceeded)
                MacroLegendRow(name: "Protein", current: consumedProtein, goal: proteinGoal, color: .blue)
                MacroLegendRow(name: "Fat", current: consumedFat, goal: fatGoal, color: fatExceeded ? .red : .purple, exceeded: fatExceeded)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            ZStack {
                // Bottom shadow layer (deepest) - teal color glow
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.teal.opacity(colorScheme == .dark ? 0.15 : 0.08))
                    .offset(y: 8)
                    .blur(radius: 4)
                
                // Middle shadow layer
                RoundedRectangle(cornerRadius: 25, style: .continuous)
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                    .offset(y: 4)
                
                // Main card background with gradient
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
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.06), radius: 8, x: 0, y: 4)
        .shadow(color: .teal.opacity(colorScheme == .dark ? 0.2 : 0.12), radius: 12, x: 0, y: 6)
    }
    
    // MARK: - Weekly Progress Card
    private var weeklyProgressCard: some View {
        // Content only (no header - header is outside and swipes with card)
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            WeeklyProgressRow(title: "Calorie Target", daysCompleted: weeklyCalorieDaysMet, totalDays: 7, color: .teal)
            WeeklyProgressRow(title: "Protein Goals Met", daysCompleted: weeklyProteinDaysMet, totalDays: 7, color: .blue)
            WeeklyProgressRow(title: "Fat Goals Met", daysCompleted: weeklyFatDaysMet, totalDays: 7, color: .purple)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            ZStack {
                // Bottom shadow layer (deepest) - teal color glow
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.teal.opacity(colorScheme == .dark ? 0.15 : 0.08))
                    .offset(y: 8)
                    .blur(radius: 4)
                
                // Middle shadow layer
                RoundedRectangle(cornerRadius: 25, style: .continuous)
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                    .offset(y: 4)
                
                // Main card background with gradient
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
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.06), radius: 8, x: 0, y: 4)
        .shadow(color: .teal.opacity(colorScheme == .dark ? 0.2 : 0.12), radius: 12, x: 0, y: 6)
    }
    
    // MARK: - Smart Daily Summary Widget
    private var dailySummaryMainCard: some View {
        SmartDailySummaryWidget(
            consumedCalories: consumedCalories,
            calorieGoal: calorieGoal,
            consumedProtein: consumedProtein,
            proteinGoal: proteinGoal,
            consumedFat: consumedFat,
            fatGoal: fatGoal,
            mealsLogged: mealService.todaysMeals.count,
            waterIntake: HydrationService.shared.todaySummary?.totalMl ?? 0,
            waterGoal: HydrationService.shared.settings.dailyGoalMl
        )
    }
    
    // MARK: - Weekly Progress for Main Page
    private var weeklyProgressMainCard: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Weekly Progress")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Spacer()
            }
            
            VStack(spacing: 14) {
                WeeklyProgressRow(title: "Calorie Target", daysCompleted: weeklyCalorieDaysMet, totalDays: 7, color: .green)
                WeeklyProgressRow(title: "Protein Goals Met", daysCompleted: weeklyProteinDaysMet, totalDays: 7, color: .blue)
                WeeklyProgressRow(title: "Fat Goals Met", daysCompleted: weeklyFatDaysMet, totalDays: 7, color: .purple)
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
    
    // MARK: - Weekly Progress Calculations
    private var weeklyProteinDaysMet: Int {
        calculateDaysMeetingGoal { dailyMeals in
            let totalProtein = dailyMeals.reduce(0) { $0 + $1.protein }
            return totalProtein >= proteinGoal
        }
    }
    
    private var weeklyCalorieDaysMet: Int {
        calculateDaysMeetingGoal { dailyMeals in
            let totalCalories = dailyMeals.reduce(0) { $0 + $1.calories }
            return totalCalories >= Int(Double(calorieGoal) * 0.9) && totalCalories <= Int(Double(calorieGoal) * 1.1)
        }
    }
    
    private var weeklyFatDaysMet: Int {
        calculateDaysMeetingGoal { dailyMeals in
            let totalFat = dailyMeals.reduce(0) { $0 + $1.fat }
            return totalFat >= Int(Double(fatGoal) * 0.8)
        }
    }
    
    private var weeklyMealConsistencyDays: Int {
        calculateDaysMeetingGoal { dailyMeals in
            // Consider consistent if at least 3 meals logged
            return dailyMeals.count >= 3
        }
    }
    
    private func calculateDaysMeetingGoal(criteria: ([MealEntryData]) -> Bool) -> Int {
        let calendar = Calendar.current
        let today = Date()
        var daysMet = 0
        
        for dayOffset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            
            // Use MealService to get meals for each day
            let dayMeals = mealService.getMealsForDate(date)
            
            if criteria(dayMeals) {
                daysMet += 1
            }
        }
        
        return daysMet
    }
}

// MARK: - Smart Daily Summary Widget
struct SmartDailySummaryWidget: View {
    @Environment(\.colorScheme) private var colorScheme
    
    let consumedCalories: Int
    let calorieGoal: Int
    let consumedProtein: Int
    let proteinGoal: Int
    let consumedFat: Int
    let fatGoal: Int
    let mealsLogged: Int
    let waterIntake: Int
    let waterGoal: Int
    
    // Computed insights
    private var calorieProgress: Double {
        guard calorieGoal > 0 else { return 0 }
        return Double(consumedCalories) / Double(calorieGoal)
    }
    
    private var proteinProgress: Double {
        guard proteinGoal > 0 else { return 0 }
        return Double(consumedProtein) / Double(proteinGoal)
    }
    
    private var fatProgress: Double {
        guard fatGoal > 0 else { return 0 }
        return Double(consumedFat) / Double(fatGoal)
    }
    
    private var waterProgress: Double {
        guard waterGoal > 0 else { return 0 }
        return Double(waterIntake) / Double(waterGoal)
    }
    
    private var nutritionScore: Int {
        var score = 0
        
        // Calorie accuracy (max 30 points) - best if within 10% of goal
        let calorieDiff = abs(calorieProgress - 1.0)
        if calorieDiff < 0.1 {
            score += 30
        } else if calorieDiff < 0.2 {
            score += 20
        } else if calorieDiff < 0.3 {
            score += 10
        }
        
        // Protein (max 25 points)
        if proteinProgress >= 1.0 {
            score += 25
        } else if proteinProgress >= 0.8 {
            score += 20
        } else if proteinProgress >= 0.5 {
            score += 10
        }
        
        // Fat balance (max 20 points) - best if not exceeding
        if fatProgress <= 1.0 && fatProgress >= 0.7 {
            score += 20
        } else if fatProgress <= 1.1 {
            score += 15
        } else if fatProgress <= 1.2 {
            score += 5
        }
        
        // Meal consistency (max 15 points)
        if mealsLogged >= 4 {
            score += 15
        } else if mealsLogged >= 3 {
            score += 10
        } else if mealsLogged >= 2 {
            score += 5
        }
        
        // Hydration (max 10 points)
        if waterProgress >= 1.0 {
            score += 10
        } else if waterProgress >= 0.75 {
            score += 7
        } else if waterProgress >= 0.5 {
            score += 4
        }
        
        return score
    }
    
    private var scoreColor: Color {
        if nutritionScore >= 80 { return .green }
        else if nutritionScore >= 60 { return .yellow }
        else if nutritionScore >= 40 { return .orange }
        else { return .red }
    }
    
    // Smart insights - Enhanced with more variety and personality
    private var positiveInsights: [DailyInsight] {
        var insights: [DailyInsight] = []
        let hour = Calendar.current.component(.hour, from: Date())
        
        // Protein achievements with varied messages
        if proteinProgress >= 1.2 {
            let extraProtein = consumedProtein - proteinGoal
            insights.append(DailyInsight(
                icon: "bolt.fill",
                text: "Protein powerhouse! +\(extraProtein)g over goal. 💪 Your muscles are loving this!",
                color: .blue
            ))
        } else if proteinProgress >= 1.0 {
            let messages = [
                "Protein goal crushed! Your body has the building blocks it needs. 🏗️",
                "Perfect protein intake! Muscle recovery: activated. 💪",
                "\(consumedProtein)g protein logged – your gains thank you! 🎯"
            ]
            insights.append(DailyInsight(
                icon: "checkmark.seal.fill",
                text: messages.randomElement()!,
                color: .green
            ))
        }
        
        // Perfect calorie balance
        if calorieProgress >= 0.95 && calorieProgress <= 1.05 {
            insights.append(DailyInsight(
                icon: "target",
                text: "Bullseye! 🎯 Calories within 5% of goal. That's precision nutrition!",
                color: .green
            ))
        } else if calorieProgress >= 0.9 && calorieProgress <= 1.1 {
            insights.append(DailyInsight(
                icon: "checkmark.circle.fill",
                text: "Calories on target – sustainable eating at its finest!",
                color: .green
            ))
        }
        
        // Hydration celebration
        if waterProgress >= 1.0 {
            let messages = [
                "Hydration hero! 💧 Your cells are swimming in happiness.",
                "Water goal smashed! Proper hydration boosts energy by 20%.",
                "Fully hydrated! Your skin, brain, and muscles thank you. 💧"
            ]
            insights.append(DailyInsight(
                icon: "drop.fill",
                text: messages.randomElement()!,
                color: .cyan
            ))
        }
        
        // Meal consistency
        if mealsLogged >= 4 {
            insights.append(DailyInsight(
                icon: "fork.knife.circle.fill",
                text: "Meal master! 🍽️ \(mealsLogged) meals tracked. Consistency = results!",
                color: .green
            ))
        } else if mealsLogged >= 3 {
            insights.append(DailyInsight(
                icon: "fork.knife",
                text: "Great tracking today! Knowing what you eat is half the battle. 📊",
                color: .green
            ))
        }
        
        // Balanced macros
        if fatProgress <= 1.0 && fatProgress >= 0.7 && proteinProgress >= 0.8 {
            insights.append(DailyInsight(
                icon: "heart.fill",
                text: "Macro balance on point! ❤️ Heart-healthy eating today.",
                color: .pink
            ))
        }
        
        // Early morning wins
        if hour < 10 && mealsLogged >= 1 && waterProgress >= 0.2 {
            insights.append(DailyInsight(
                icon: "sunrise.fill",
                text: "Strong start! Morning nutrition sets the tone for the day. ☀️",
                color: .orange
            ))
        }
        
        // Evening accomplishment
        if hour >= 18 && nutritionScore >= 70 {
            insights.append(DailyInsight(
                icon: "star.fill",
                text: "Solid nutrition day! You showed up for yourself. 🌟",
                color: .yellow
            ))
        }
        
        return insights.prefix(2).map { $0 }
    }
    
    private var improvementSuggestions: [DailyInsight] {
        var suggestions: [DailyInsight] = []
        let hour = Calendar.current.component(.hour, from: Date())
        
        // Protein suggestions with specific food ideas
        if proteinProgress < 0.6 && hour >= 14 {
            let remaining = proteinGoal - consumedProtein
            let quickFixes = ["Greek yogurt (20g)", "chicken breast (30g)", "protein shake (25g)", "3 eggs (18g)", "cottage cheese (14g)"]
            suggestions.append(DailyInsight(
                icon: "arrow.up.circle.fill",
                text: "Need \(remaining)g protein still! Quick fix: \(quickFixes.randomElement()!)",
                color: .blue
            ))
        } else if proteinProgress < 0.8 {
            let remaining = proteinGoal - consumedProtein
            suggestions.append(DailyInsight(
                icon: "arrow.up.circle",
                text: "Add \(remaining)g more protein – your muscles are waiting! 💪",
                color: .blue
            ))
        }
        
        // Calorie warnings with context
        if calorieProgress < 0.5 && hour >= 14 {
            suggestions.append(DailyInsight(
                icon: "exclamationmark.triangle.fill",
                text: "Only \(consumedCalories) cal by afternoon! Under-eating slows metabolism. 🍽️",
                color: .red
            ))
        } else if calorieProgress < 0.7 && hour >= 12 {
            suggestions.append(DailyInsight(
                icon: "exclamationmark.triangle",
                text: "Calorie intake low – your body needs fuel to perform! Don't skip meals.",
                color: .orange
            ))
        } else if calorieProgress > 1.2 {
            let over = consumedCalories - calorieGoal
            suggestions.append(DailyInsight(
                icon: "chart.bar.xaxis.ascending",
                text: "\(over) cal over budget. Consider a lighter dinner or evening walk! 🚶",
                color: .orange
            ))
        } else if calorieProgress > 1.1 {
            suggestions.append(DailyInsight(
                icon: "gauge.with.dots.needle.67percent",
                text: "Slightly over goal – no stress! A short walk burns it off. 🚶‍♂️",
                color: .orange
            ))
        }
        
        // Hydration with urgency based on time
        if waterProgress < 0.3 && hour >= 14 {
            let remainingMl = waterGoal - waterIntake
            suggestions.append(DailyInsight(
                icon: "drop.triangle.fill",
                text: "Dehydration alert! ⚠️ Drink \(remainingMl)ml to catch up – your brain needs it!",
                color: .red
            ))
        } else if waterProgress < 0.5 {
            let remainingMl = waterGoal - waterIntake
            suggestions.append(DailyInsight(
                icon: "drop",
                text: "\(remainingMl)ml to go! Keep a water bottle nearby. 💧",
                color: .cyan
            ))
        }
        
        // Fat intake
        if fatProgress > 1.3 {
            let overFat = consumedFat - fatGoal
            suggestions.append(DailyInsight(
                icon: "chart.bar.xaxis",
                text: "\(overFat)g over fat goal. Try grilled over fried tomorrow! 🥗",
                color: .purple
            ))
        } else if fatProgress > 1.15 {
            suggestions.append(DailyInsight(
                icon: "leaf.fill",
                text: "Fat intake elevated – balance with lean proteins at dinner. 🥬",
                color: .purple
            ))
        }
        
        // Meal logging encouragement
        if mealsLogged == 0 && hour >= 11 {
            suggestions.append(DailyInsight(
                icon: "pencil.and.list.clipboard",
                text: "No meals logged yet! Even a quick entry helps you stay aware. 📝",
                color: .gray
            ))
        } else if mealsLogged == 1 && hour >= 15 {
            suggestions.append(DailyInsight(
                icon: "clock.fill",
                text: "Only 1 meal tracked. Logging helps identify patterns! 📊",
                color: .gray
            ))
        }
        
        // Time-specific suggestions
        if hour >= 20 && calorieProgress < 0.85 {
            let remaining = calorieGoal - consumedCalories
            suggestions.append(DailyInsight(
                icon: "moon.fill",
                text: "Room for \(remaining) cal snack! Greek yogurt + berries = perfect evening fuel. 🍇",
                color: .indigo
            ))
        }
        
        return suggestions.prefix(2).map { $0 }
    }
    
    private var dailyTip: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let dayOfWeek = Calendar.current.component(.weekday, from: Date())
        let isWeekend = dayOfWeek == 1 || dayOfWeek == 7
        
        if hour < 10 {
            // Morning tips
            let tips = [
                "💡 Protein at breakfast = less hunger all day. Science says so!",
                "💡 A glass of water before coffee boosts metabolism by 24%.",
                "💡 Morning sunshine + breakfast = better sleep tonight.",
                "💡 Front-loading calories in the AM helps with evening cravings.",
                "💡 Breakfast skippers often overeat 40% more at dinner!"
            ]
            return tips.randomElement()!
        } else if hour < 14 {
            // Midday tips
            let tips = [
                "💡 A 10-min walk after lunch stabilizes blood sugar for hours.",
                "💡 Afternoon protein keeps energy steady – no 3pm crash!",
                "💡 Hydration dips around noon. Time for a water check! 💧",
                "💡 Midday meals with fiber = sustained focus all afternoon.",
                isWeekend ? "💡 Weekend lunches count too! Stay mindful. 🍽️" : "💡 Meal prep saves 6+ hours per week. Future you will thank you!"
            ]
            return tips.randomElement()!
        } else if hour < 18 {
            // Afternoon tips
            let tips = [
                "💡 Afternoon snacks prevent the 'I'm starving' dinner binges.",
                "💡 30g protein snack now = better gym performance later. 💪",
                "💡 Green tea at 3pm: caffeine + antioxidants, minus the jitters.",
                "💡 Stretch break! 5 minutes improves focus and posture.",
                "💡 Planning dinner now? Protein + veggies + complex carbs = 🔥"
            ]
            return tips.randomElement()!
        } else {
            // Evening tips
            let tips = [
                "💡 Stop eating 2-3 hours before bed = better sleep + recovery.",
                "💡 Evening protein (casein) works while you sleep! 🌙",
                "💡 Tomorrow's success starts with tonight's meal prep.",
                "💡 Reflect: What went well today? Build on wins!",
                "💡 Quality sleep = better gains. Your muscles grow at rest! 😴",
                "💡 Herbal tea before bed aids digestion and relaxation. 🍵"
            ]
            return tips.randomElement()!
        }
    }
    
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let dayOfWeek = Calendar.current.component(.weekday, from: Date())
        
        if nutritionScore >= 85 {
            return ["Crushing it today! 🌟", "Elite nutrition mode! 💯", "You're on fire! 🔥"].randomElement()!
        } else if nutritionScore >= 70 {
            return ["Solid progress! Keep pushing! 💪", "Good work today! 👏", "On the right track! 🎯"].randomElement()!
        } else if nutritionScore >= 50 {
            return ["Room to grow – you've got this! 💪", "Every meal is a chance to level up! 🚀", "Progress over perfection! ✨"].randomElement()!
        }
        
        // Time-based greetings
        if hour < 10 {
            return ["New day, new opportunities! ☀️", "Let's own this day! 🌅", "Morning fuel time! ⚡"].randomElement()!
        } else if hour < 14 {
            return ["Midday momentum! 🎯", "Keep the energy up! 💪", "Stay focused! 🧠"].randomElement()!
        } else if hour < 18 {
            // Day-specific afternoon messages
            if dayOfWeek == 6 { return "Friday vibes – finish strong! 🎉" }
            return ["Afternoon push! 💪", "Home stretch! 🏁", "You're doing great! ✨"].randomElement()!
        } else {
            return ["Evening reflection time 🌙", "Finish strong tonight! 🌟", "Wind down well! 😌"].randomElement()!
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with Score
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "brain.head.profile")
                            .font(.title3)
                            .foregroundColor(.purple)
                        Text("Daily Insights")
                            .font(.title2)
                            .fontWeight(.bold)
                    }
                    
                    Text(greeting)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Nutrition Score Badge
                VStack(spacing: 2) {
                    Text("\(nutritionScore)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(scoreColor)
                    Text("Score")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(width: 60, height: 60)
                .background(
                    Circle()
                        .fill(scoreColor.opacity(0.15))
                )
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, 16)
            .padding(.bottom, 12)
            
            Divider()
                .padding(.horizontal, Spacing.md)
            
            // What's Going Well
            if !positiveInsights.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "hand.thumbsup.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                        Text("What's Going Well")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.green)
                    }
                    
                    ForEach(positiveInsights) { insight in
                        InsightRow(insight: insight)
                    }
                }
                .padding(Spacing.md)
            }
            
            // Opportunities
            if !improvementSuggestions.isEmpty {
                if !positiveInsights.isEmpty {
                    Divider()
                        .padding(.horizontal, Spacing.md)
                }
                
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "lightbulb.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                        Text("Opportunities")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.orange)
                    }
                    
                    ForEach(improvementSuggestions) { insight in
                        InsightRow(insight: insight)
                    }
                }
                .padding(Spacing.md)
            }
            
            // Quick Stats Row
            Divider()
                .padding(.horizontal, Spacing.md)
            
            HStack(spacing: 0) {
                QuickInsightStat(
                    value: "\(mealsLogged)",
                    label: "Meals",
                    icon: "fork.knife",
                    color: mealsLogged >= 3 ? .green : .gray
                )
                
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 1, height: 40)
                
                QuickInsightStat(
                    value: "\(Int(calorieProgress * 100))%",
                    label: "Calories",
                    icon: "flame.fill",
                    color: calorieProgress >= 0.9 && calorieProgress <= 1.1 ? .green : (calorieProgress > 1.15 ? .orange : .gray)
                )
                
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 1, height: 40)
                
                QuickInsightStat(
                    value: "\(Int(proteinProgress * 100))%",
                    label: "Protein",
                    icon: "bolt.fill",
                    color: proteinProgress >= 1.0 ? .green : (proteinProgress >= 0.8 ? .yellow : .gray)
                )
                
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 1, height: 40)
                
                QuickInsightStat(
                    value: "\(Int(waterProgress * 100))%",
                    label: "Water",
                    icon: "drop.fill",
                    color: waterProgress >= 1.0 ? .cyan : (waterProgress >= 0.5 ? .blue : .gray)
                )
            }
            .padding(.vertical, 14)
            
            // Daily Tip
            Divider()
                .padding(.horizontal, Spacing.md)
            
            Text(dailyTip)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(
                    LinearGradient(
                        colors: [scoreColor.opacity(0.3), scoreColor.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: colorScheme == .dark ? .clear : .black.opacity(0.08), radius: 12, x: 0, y: 6)
    }
}

// MARK: - Daily Insight Model
struct DailyInsight: Identifiable {
    let id = UUID()
    let icon: String
    let text: String
    let color: Color
}

// MARK: - Insight Row
struct InsightRow: View {
    let insight: DailyInsight
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: insight.icon)
                .font(.ds_bodySmall)
                .foregroundColor(insight.color)
                .frame(width: 20)
            
            Text(insight.text)
                .font(.subheadline)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Quick Insight Stat
struct QuickInsightStat: View {
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

struct SimpleNutritionCard: View {
    let title: String
    let current: Int
    let goal: Int
    let unit: String
    let color: Color
    
    private var progress: Double {
        guard goal > 0 else { return 0 }
        return min(Double(current) / Double(goal), 1.0)
    }
    
    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .fontWeight(.medium)
            
            Text("\(current)\(unit)")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(color)
            
            Text("of \(goal)\(unit)")
                .font(.caption2)
                .foregroundColor(.secondary)
            
            ProgressView(value: progress)
                .progressViewStyle(LinearProgressViewStyle(tint: color))
                .scaleEffect(x: 1, y: 0.5)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.sm)
        .padding(.horizontal, Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .fill(color.opacity(0.05))
        )
    }
}

struct SimpleMealSection: View {
    let title: String
    let icon: String
    let color: Color
    let onTap: () -> Void
    
    var body: some View {
        Button(action: { HapticManager.selectionChanged(); onTap() }) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                    .frame(width: 30)
                
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text("Add Food")
                    .font(.subheadline)
                    .foregroundColor(.blue)
                
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundColor(.blue)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(Color(.systemBackground))
            .cornerRadius(CornerRadius.md)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Swipeable Meal Card (Large carousel card like Challenge/Program widget)
struct SwipeableMealCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let mealType: MealType
    let meals: [MealEntryData]
    let isCurrentMealTime: Bool
    let onAddFood: () -> Void
    let onDelete: (MealEntryData) -> Void
    
    @State private var showingMealDetail = false
    
    private var totalCalories: Int {
        meals.reduce(0) { $0 + $1.calories }
    }
    
    private var totalProtein: Int {
        meals.reduce(0) { $0 + $1.protein }
    }
    
    private var totalCarbs: Int {
        meals.reduce(0) { $0 + $1.carbs }
    }
    
    private var totalFat: Int {
        meals.reduce(0) { $0 + $1.fat }
    }
    
    private var gradientColors: [Color] {
        [mealType.gradientColors.0, mealType.gradientColors.1]
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header - Meal type info
            HStack(alignment: .center, spacing: 12) {
                // Meal icon with gradient background
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [gradientColors[0].opacity(0.2), gradientColors[0].opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: mealType.icon)
                        .font(.ds_heading2)
                        .foregroundStyle(
                            LinearGradient(
                                colors: gradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                
                // Meal info
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(mealType.displayName)
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        
                        if isCurrentMealTime {
                            Text("NOW")
                                .font(.caption2)
                                .fontWeight(.heavy)
                                .foregroundColor(.white)
                                .padding(.horizontal, Spacing.xs)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: gradientColors,
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                )
                        }
                    }
                    
                    Text(mealType.timeDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Calories badge (if has items)
                if !meals.isEmpty {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(totalCalories)")
                            .font(.ds_stat)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: gradientColors,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        Text("calories")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, 16)
            .padding(.bottom, 12)
            
            // Divider with accent
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [gradientColors[0].opacity(0.3), gradientColors[1].opacity(0.1)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
                .padding(.horizontal, Spacing.md)
            
            // Content area - either items summary or add prompt
            HStack(spacing: 16) {
                // Left accent bar
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            colors: gradientColors,
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 4)
                    .padding(.vertical, Spacing.xs)
                
                if meals.isEmpty {
                    // Empty state - prompt to add
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No food logged yet")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Text("Tap + to add your \(mealType.displayName.lowercased())")
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                    
                    Spacer()
                    
                    // Add button
                    Button(action: onAddFood) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.ds_bodySmall).fontWeight(.bold)
                            Text("Add Food")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: gradientColors,
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                        .shadow(color: gradientColors[0].opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                    .buttonStyle(PlainButtonStyle())
                } else {
                    // Has items - show summary
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(meals.count) item\(meals.count == 1 ? "" : "s") logged")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        
                        // Macro summary
                        HStack(spacing: 12) {
                            MacroPill(value: totalProtein, label: "P", color: .blue)
                            MacroPill(value: totalCarbs, label: "C", color: .green)
                            MacroPill(value: totalFat, label: "F", color: .orange)
                        }
                    }
                    
                    Spacer()
                    
                    // Add more button
                    Button(action: onAddFood) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: gradientColors,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
        }
        .background(
            ZStack {
                // Bottom shadow layer (deepest) - meal colored
                RoundedRectangle(cornerRadius: 28)
                    .fill(gradientColors[0].opacity(colorScheme == .dark ? 0.08 : 0.04))
                    .offset(y: 6)
                    .blur(radius: 3)
                
                // Middle shadow layer
                RoundedRectangle(cornerRadius: 26)
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.12 : 0.03))
                    .offset(y: 3)
                
                // Main card background
                RoundedRectangle(cornerRadius: CornerRadius.xl)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark 
                                ? [Color(white: 0.15), Color(white: 0.10)]
                                : [Color.white, Color.white.opacity(0.95)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                // Inner highlight (top edge glow)
                RoundedRectangle(cornerRadius: CornerRadius.xl)
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
                
                // Accent border
                RoundedRectangle(cornerRadius: CornerRadius.xl)
                    .stroke(
                        LinearGradient(
                            colors: [
                                gradientColors[0].opacity(colorScheme == .dark ? 0.4 : 0.25),
                                gradientColors[1].opacity(colorScheme == .dark ? 0.25 : 0.15)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            }
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 12, x: 0, y: 6)
        .shadow(color: gradientColors[0].opacity(colorScheme == .dark ? 0.2 : 0.12), radius: 16, x: 0, y: 8)
    }
}

// MARK: - Macro Pill (for meal card summary)
struct MacroPill: View {
    let value: Int
    let label: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Text("\(value)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, Spacing.xxs)
        .background(
            Capsule()
                .fill(color.opacity(0.12))
        )
    }
}

// MARK: - Meal Row Card (Matching Exercise Library Card Style)
struct MealRowCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let mealType: MealType
    let meals: [MealEntryData]
    let isMostRecent: Bool
    let onAddFood: () -> Void
    let onDelete: (MealEntryData) -> Void
    
    @State private var isExpanded = false
    @State private var glowRotation: Double = 0
    
    private var totalCalories: Int {
        meals.reduce(0) { $0 + $1.calories }
    }
    
    private var totalProtein: Int {
        meals.reduce(0) { $0 + $1.protein }
    }
    
    private var totalCarbs: Int {
        meals.reduce(0) { $0 + $1.carbs }
    }
    
    private var totalFat: Int {
        meals.reduce(0) { $0 + $1.fat }
    }
    
    private var mealIcon: String {
        switch mealType {
        case .breakfast: return "sunrise.fill"
        case .lunch: return "sun.max.fill"
        case .dinner: return "moon.stars.fill"
        case .snacks: return "leaf.fill"
        }
    }
    
    private var mealColor: Color {
        switch mealType {
        case .breakfast: return .orange
        case .lunch: return .green
        case .dinner: return .blue
        case .snacks: return .purple
        }
    }
    
    private var gradientColors: [Color] {
        switch mealType {
        case .breakfast: return [.orange, .yellow]
        case .lunch: return [.green, .teal]
        case .dinner: return [.blue, .cyan]
        case .snacks: return [.purple, .pink]
        }
    }
    
    // Check if this meal corresponds to the current time of day
    private var isCurrentMealTime: Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        switch mealType {
        case .breakfast:
            return hour >= 5 && hour < 10  // 5 AM - 9:59 AM
        case .lunch:
            return hour >= 12 && hour < 14  // 12 PM - 1:59 PM
        case .dinner:
            return hour >= 18 || hour < 5  // 6 PM onward & late night until 5 AM
        case .snacks:
            // Snacks fills the gaps: 10-12 (morning snack) and 14-18 (afternoon snack)
            return (hour >= 10 && hour < 12) || (hour >= 14 && hour < 18)
        }
    }
    
    // Use time-based glow instead of most recent
    private var shouldGlow: Bool {
        isCurrentMealTime
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Main row card
            Button(action: {
                if meals.isEmpty {
                    onAddFood()
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        isExpanded.toggle()
                    }
                }
            }) {
                HStack(spacing: 12) {
                    // Circular gradient icon (matching exercise card style)
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: gradientColors,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 40, height: 40)
                            .shadow(color: gradientColors[0].opacity(0.25), radius: 4, x: 0, y: 2)
                        
                        Image(systemName: mealIcon)
                            .font(.ds_labelLarge)
                            .foregroundColor(.white)
                    }
                    
                    // Meal info
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mealType.displayName)
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        HStack(spacing: 8) {
                            if meals.isEmpty {
                                Text("Tap to add food")
                                    .font(.caption)
                                    .foregroundColor(mealColor)
                                    .fontWeight(.medium)
                            } else {
                                Text("\(meals.count) item\(meals.count == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundColor(mealColor)
                                    .fontWeight(.medium)
                                
                                Text("•")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                
                                Text("\(totalCalories) cal")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                        }
                    }
                    
                    Spacer()
                    
                    // Right side - Add button or Calorie display + Chevron
                    if meals.isEmpty {
                        // Add button (solid color)
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(mealColor)
                    } else {
                        // Calorie badge
                        HStack(spacing: 6) {
                            Text("\(totalCalories)")
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(mealColor)
                            Text("cal")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Chevron (always visible, matching exercise cards)
                    Image(systemName: "chevron.right")
                        .font(.ds_bodySmall).fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(
                    ZStack {
                        // Bottom shadow layer (deepest) - meal colored (subtle)
                        RoundedRectangle(cornerRadius: 28)
                            .fill(gradientColors[0].opacity(colorScheme == .dark ? 0.06 : 0.03))
                            .offset(y: 4)
                            .blur(radius: 2)
                        
                        // Middle shadow layer (subtle)
                        RoundedRectangle(cornerRadius: 26)
                            .fill(Color.black.opacity(colorScheme == .dark ? 0.08 : 0.02))
                            .offset(y: 2)
                        
                        // Main card background
                        RoundedRectangle(cornerRadius: 25)
                            .fill(
                                LinearGradient(
                                    colors: colorScheme == .dark 
                                        ? [Color(white: 0.15), Color.cardBackground]
                                        : [Color.white, Color.white.opacity(0.98)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        
                        // Inner highlight (top edge glow)
                        RoundedRectangle(cornerRadius: 25)
                            .stroke(
                                LinearGradient(
                                    colors: colorScheme == .dark 
                                        ? [Color.white.opacity(0.08), Color.clear]
                                        : [Color.white, Color.white.opacity(0.3), Color.clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                        
                        // Subtle accent border (when not glowing)
                        if !shouldGlow {
                            RoundedRectangle(cornerRadius: 25)
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            gradientColors[0].opacity(colorScheme == .dark ? 0.2 : 0.12),
                                            gradientColors[1].opacity(colorScheme == .dark ? 0.1 : 0.06)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        }
                    }
                )
                .overlay(
                    Group {
                        if shouldGlow {
                            // Seamless animated glowing border for current meal time
                            RoundedRectangle(cornerRadius: 25)
                                .strokeBorder(
                                    AngularGradient(
                                        gradient: Gradient(colors: [
                                            gradientColors[0].opacity(0.7),
                                            gradientColors[1].opacity(0.5),
                                            gradientColors[0].opacity(0.3),
                                            gradientColors[1].opacity(0.5),
                                            gradientColors[0].opacity(0.7)
                                        ]),
                                        center: .center,
                                        startAngle: .degrees(glowRotation),
                                        endAngle: .degrees(glowRotation + 360)
                                    ),
                                    lineWidth: 2
                                )

                            // Subtle outer glow layer
                            RoundedRectangle(cornerRadius: 25)
                                .strokeBorder(
                                    AngularGradient(
                                        gradient: Gradient(colors: [
                                            gradientColors[0].opacity(0.25),
                                            gradientColors[1].opacity(0.15),
                                            gradientColors[0].opacity(0.25)
                                        ]),
                                        center: .center,
                                        startAngle: .degrees(glowRotation),
                                        endAngle: .degrees(glowRotation + 360)
                                    ),
                                    lineWidth: 4
                                )
                                .blur(radius: 4)
                        }
                    }
                )
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.12 : 0.05), radius: 6, x: 0, y: 3)
                .shadow(color: gradientColors[0].opacity(colorScheme == .dark ? 0.08 : 0.04), radius: 8, x: 0, y: 4)
                .shadow(color: shouldGlow ? mealColor.opacity(0.2) : .clear, radius: 12, x: 0, y: 0)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Expanded content with all food items
            if isExpanded && !meals.isEmpty {
                VStack(spacing: 0) {
                    // Divider
                    Rectangle()
                        .fill(mealColor.opacity(0.2))
                        .frame(height: 1)
                        .padding(.horizontal, Spacing.md)
                    
                    // Food items list - NO TRUNCATION
                    VStack(spacing: 0) {
                        ForEach(meals, id: \.id) { meal in
                            ExpandedMealItemRow(meal: meal, color: mealColor) {
                                onDelete(meal)
                            }
                            
                            // Separator between items
                            if meal.id != meals.last?.id {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.1))
                                    .frame(height: 1)
                                    .padding(.horizontal, Spacing.md)
                            }
                        }
                    }
                    .padding(.vertical, Spacing.xs)
                    
                    // Macros summary row
                    HStack(spacing: 12) {
                        MacroBadge(label: "P", value: totalProtein, color: .blue)
                        MacroBadge(label: "C", value: totalCarbs, color: .orange)
                        MacroBadge(label: "F", value: totalFat, color: .purple)
                        
                        Spacer()
                        
                        // Add more button
                        Button(action: onAddFood) {
                            HStack(spacing: 5) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.ds_bodySmall)
                                Text("Add more")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(mealColor)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background(mealColor.opacity(0.1))
                            .clipShape(Capsule())
                            .contentShape(Capsule())
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, 10)
                    .background(gradientColors[0].opacity(0.05))
                }
                .background(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: 25,
                        bottomTrailingRadius: 25,
                        topTrailingRadius: 0
                    )
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark 
                                ? [Color(white: 0.15), Color.cardBackground]
                                : [Color.white, Color.white.opacity(0.98)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: gradientColors[0].opacity(0.10), radius: 6, x: 0, y: 4)
                    .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 2)
                )
                .contentShape(Rectangle()) // Ensure proper hit testing
                .overlay(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: 25,
                        bottomTrailingRadius: 25,
                        topTrailingRadius: 0
                    )
                    .stroke(
                        LinearGradient(
                            colors: [
                                gradientColors[0].opacity(colorScheme == .dark ? 0.3 : 0.2),
                                gradientColors[1].opacity(colorScheme == .dark ? 0.2 : 0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                    .allowsHitTesting(false) // Don't block button taps
                    .mask(
                        VStack(spacing: 0) {
                            Rectangle()
                                .fill(Color.clear)
                                .frame(height: 1)
                            Rectangle()
                                .fill(Color.black)
                        }
                    )
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
    }
}

// MARK: - Expanded Meal Item Row (Full Display)
struct ExpandedMealItemRow: View {
    let meal: MealEntryData
    let color: Color
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Food info - NO LINE LIMIT, shows full text
            VStack(alignment: .leading, spacing: 4) {
                Text(meal.foodName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true) // Allows text to wrap
                
                HStack(spacing: 8) {
                    Text("\(meal.displayQuantity) \(meal.unit)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.5))
                    
                    Text("\(meal.protein)p · \(meal.carbs)c · \(meal.fat)f")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Calories
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(meal.calories)")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(color)
                Text("cal")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            // Delete button
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.ds_heading3)
                    .foregroundColor(.red.opacity(0.6))
                    .frame(width: 32, height: 32) // Larger hit area
                    .contentShape(Rectangle())
            }
            .buttonStyle(BorderlessButtonStyle())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle()) // Ensure row doesn't steal taps
    }
}

// MARK: - Macro Badge
struct MacroBadge: View {
    let label: String
    let value: Int
    let color: Color
    
    var body: some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text("\(value)g")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.primary)
        }
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, Spacing.xxs)
        .background(color.opacity(0.1))
        .clipShape(Capsule())
    }
}


// NOTE: Legacy meal components removed (MealWidgetCard, MealItemRow, MealQuickStat, MealSectionWithItems)
// Active meal tracking uses the newer components in MealPlanView.swift

struct SimpleProfileSetupView: View {
    @EnvironmentObject var userManager: UserManager
    @Binding var showingProfileSetup: Bool
    @State private var weight: String = ""
    @State private var height: String = ""
    @State private var gender: String = "Male"
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 16) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.green)
                        
                        Text("Complete Your Profile")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("We'll calculate your nutrition goals based on your fitness goal: \"\(userManager.currentUser?.fitnessGoal ?? "Build Muscle")\"")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    
                    VStack(spacing: 20) {
                        SimpleInputField(title: "Weight (lbs)", value: $weight, placeholder: "150")
                        SimpleInputField(title: "Height (inches)", value: $height, placeholder: "70")
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Gender")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Picker("Gender", selection: $gender) {
                                Text("Male").tag("Male")
                                Text("Female").tag("Female")
                            }
                            .pickerStyle(SegmentedPickerStyle())
                        }
                    }
                    .padding(.horizontal)
                    
                    Button(action: { HapticManager.impact(.medium); saveProfile() }) {
                        Text("Calculate My Nutrition Goals")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.md)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.green, Color.mint]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .cornerRadius(CornerRadius.md)
                    }
                    .padding(.horizontal)
                    .disabled(!isFormValid)
                }
                .padding(.vertical)
            }
            .navigationTitle("Profile Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        showingProfileSetup = false
                    }
                }
            }
        }
    }
    
    private var isFormValid: Bool {
        !weight.isEmpty && !height.isEmpty &&
        Int(weight) != nil && Int(height) != nil
    }
    
    private func saveProfile() {
        guard let weightValue = Int(weight),
              let heightValue = Int(height),
              let user = userManager.currentUser else { return }
        
        // Save to Core Data (primary storage)
        user.weight = Int16(weightValue)
        user.height = Int16(heightValue)
        user.gender = gender
        
        // Also save to UserDefaults for backwards compatibility
        UserDefaults.standard.set(weightValue, forKey: "userWeight")
        UserDefaults.standard.set(heightValue, forKey: "userHeight")
        UserDefaults.standard.set(gender, forKey: "userGender")
        
        do {
            try PersistenceController.shared.container.viewContext.save()
            AppLogger.info("[PROFILE] Saved weight: \(weightValue), height: \(heightValue)", category: .ui)
        } catch {
            AppLogger.error("[PROFILE] Error saving: \(error.localizedDescription)", category: .ui)
        }
        
        showingProfileSetup = false
    }
}

struct SimpleInputField: View {
    let title: String
    @Binding var value: String
    let placeholder: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
            
            TextField(placeholder, text: $value)
                .keyboardType(.numberPad)
                .textFieldStyle(RoundedBorderTextFieldStyle())
        }
    }
}

// MARK: - Workout Timer Indicator

struct WorkoutTimerIndicator: View {
    @ObservedObject var workoutManager: WorkoutManager
    
    var body: some View {
        Button(action: {
            // Tap to navigate to workout tab - could add this functionality
        }) {
            Text(workoutManager.formattedDuration)
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, Spacing.xxs)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .fill(.ultraThinMaterial)
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - USDA Food Search View (Real API Integration)

struct USDAFoodSearchView: View {
    let mealType: MealType
    let onAdd: (FoodEntry) -> Void
    @Environment(\.dismiss) private var dismiss
    
    @ObservedObject private var foodService = USDAFoodService.shared
    @State private var searchText = ""
    @State private var searchDebouncer: Timer?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search Header
                searchHeader
                
                // Search Results
                if foodService.isSearching {
                    loadingView
                } else if let error = foodService.searchError {
                    errorView(error)
                } else if searchText.isEmpty {
                    emptySearchView
                } else if foodService.searchResults.isEmpty && !searchText.isEmpty {
                    noResultsView
                } else {
                    searchResultsList
                }
            }
            .navigationTitle("Add to \(mealType.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onDisappear {
                searchDebouncer?.invalidate()
                searchDebouncer = nil
            }
        }
    }
    
    // MARK: - View Components
    
    private var searchHeader: some View {
        VStack(spacing: 16) {
            // Meal Type Badge
            HStack {
                Image(systemName: mealTypeIcon)
                    .foregroundColor(mealTypeColor)
                Text("Adding to \(mealType.displayName)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(mealTypeColor)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 8)
            
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search USDA database (e.g., eggs, chicken)", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .onChange(of: searchText) { newValue in
                        AppLogger.debug("[CONTENTVIEW] Search text changed to: '\(newValue)'", category: .ui)
                        searchDebouncer?.invalidate()
                        searchDebouncer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
                            AppLogger.debug("[CONTENTVIEW] Debounce timer fired for: '\(newValue)'", category: .ui)
                            if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                AppLogger.debug("[CONTENTVIEW] Calling foodService.searchFoods() for: '\(newValue)'", category: .ui)
                                foodService.searchFoods(query: newValue)
                            } else {
                                AppLogger.warning("[CONTENTVIEW] Query empty, clearing results", category: .ui)
                                foodService.searchResults = []
                            }
                        }
                    }
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .fill(Color(.systemGray6))
            )
            .padding(.horizontal)
        }
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
            Text("Searching USDA database...")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("400,000+ foods")
                .font(.caption)
                .foregroundColor(.green)
                .fontWeight(.medium)
            Spacer()
        }
    }
    
    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            Text("Search Error")
                .font(.headline)
                .fontWeight(.bold)
            Text(error)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Try Again") {
                if !searchText.isEmpty {
                    foodService.searchFoods(query: searchText)
                }
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
    }
    
    private var emptySearchView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "magnifyingglass.circle")
                .font(.system(size: 64))
                .foregroundColor(.green)
            
            VStack(spacing: 12) {
                Text("Search USDA Database")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Search over 400,000 foods from the U.S. Department of Agriculture database")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Try searching for:")
                    .font(.headline)
                    .fontWeight(.medium)
                
                ForEach(sampleSearches, id: \.self) { search in
                    Button(action: { searchText = search }) {
                        HStack {
                            Text(search)
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.left")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xs)
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.sm)
                                .fill(Color(.systemGray6))
                        )
                    }
                }
            }
            .padding(.horizontal)
            
            Spacer()
        }
    }
    
    private var noResultsView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No Results Found")
                .font(.headline)
                .fontWeight(.bold)
            Text("Try a different search term or check your spelling")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
    }
    
    private var searchResultsList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(foodService.searchResults) { food in
                    USDAFoodResultRow(food: food) {
                        addFood(food)
                    }
                }
            }
            .padding()
        }
        .scrollDismissesKeyboard(.immediately)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
        )
        .onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .background(Color(.systemGroupedBackground))
    }
    
    // MARK: - Computed Properties
    
    private var mealTypeIcon: String {
        switch mealType {
        case .breakfast: return "sunrise"
        case .lunch: return "sun.max"
        case .dinner: return "sunset"
        case .snacks: return "leaf"
        }
    }
    
    private var mealTypeColor: Color {
        switch mealType {
        case .breakfast: return .orange
        case .lunch: return .yellow
        case .dinner: return .purple
        case .snacks: return .green
        }
    }
    
    private var sampleSearches: [String] {
        ["eggs", "chicken breast", "brown rice", "banana", "greek yogurt", "salmon"]
    }
    
    private func addFood(_ food: ProcessedFoodItem) {
        let foodEntry = FoodEntry(
            name: food.displayName,
            quantity: 1,
            unit: food.servingUnit,
            calories: Int(food.nutrition.calories),
            protein: Int(food.nutrition.protein),
            carbs: Int(food.nutrition.carbohydrates),
            fat: Int(food.nutrition.totalFat),
            fdcId: food.id,
            foodItemId: nil
        )
        
        onAdd(foodEntry)
        dismiss()
    }
}

// MARK: - USDA Food Result Row

struct USDAFoodResultRow: View {
    let food: ProcessedFoodItem
    let onTap: () -> Void
    
    var body: some View {
        Button(action: { HapticManager.selectionChanged(); onTap() }) {
            HStack(spacing: 12) {
                // Food Icon
                Image(systemName: foodIcon)
                    .font(.title2)
                    .foregroundColor(.green)
                    .frame(width: 32)
                
                VStack(alignment: .leading, spacing: 4) {
                    // Food Name
                    Text(food.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    // Brand and Category
                    if let category = food.category {
                        Text(category)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    // Serving Info
                    Text("Per \(formatServingSize(food.servingSize)) \(food.servingUnit)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Nutrition Preview
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int(food.nutrition.calories)) cal")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text("\(Int(food.nutrition.protein))p • \(Int(food.nutrition.carbohydrates))c • \(Int(food.nutrition.totalFat))f")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(Color(.systemBackground))
            .cornerRadius(CornerRadius.md)
            .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var foodIcon: String {
        guard let category = food.category?.lowercased() else { return "leaf" }
        
        if category.contains("dairy") || category.contains("milk") {
            return "drop"
        } else if category.contains("meat") || category.contains("poultry") || category.contains("beef") || category.contains("chicken") {
            return "flame"
        } else if category.contains("fish") || category.contains("seafood") {
            return "fish"
        } else if category.contains("fruit") {
            return "apple"
        } else if category.contains("vegetable") {
            return "carrot"
        } else if category.contains("grain") || category.contains("cereal") || category.contains("bread") {
            return "wheat"
        } else if category.contains("nut") || category.contains("seed") {
            return "circle.hexagongrid"
        } else {
            return "leaf"
        }
    }
    
    private func formatServingSize(_ size: Double) -> String {
        if size == floor(size) {
            return String(Int(size))
        } else {
            return String(format: "%.1f", size)
        }
    }
}

// MARK: - New Nutrition Components
struct NutritionMetricCard: View {
    let title: String
    let current: Int
    let goal: Int
    let unit: String
    let color: Color
    let icon: String
    
    var progress: Double {
        guard goal > 0 else { return 0 }
        return min(1.0, Double(current) / Double(goal))
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Icon and title
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: icon)
                        .font(.ds_labelMedium)
                        .foregroundColor(color)
                }
                
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            // Current value
            VStack(spacing: 2) {
                Text("\(current)")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            // Progress indicator
            VStack(spacing: 4) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(.systemGray5))
                        .frame(height: 4)
                    
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: 50 * progress, height: 4)
                        .animation(.easeInOut(duration: 0.5), value: progress)
                }
                .frame(width: 50)
                
                Text("\(goal) goal")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .padding(Spacing.md)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xl))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.xl)
                .stroke(Color.white.opacity(0.01), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}

// MARK: - Nutrition Insights Card
struct NutritionInsightsCard: View {
    let insights: [NutritionInsight]
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Nutrition Insights")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text("Your daily nutrition analysis")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                ForEach(insights.indices, id: \.self) { index in
                    WorkingNutritionInsightCard(insight: insights[index])
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
        )
    }
}

struct NutritionInsightCard: View {
    let insight: NutritionInsight
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: insight.icon)
                    .font(.title2)
                    .foregroundColor(insight.color)
                Spacer()
                if let trend = insight.trend {
                    Text(trend)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(insight.color)
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, 2)
                        .background(insight.color.opacity(0.1))
                        .cornerRadius(4)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(insight.value)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text(insight.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text(insight.subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer()
        }
        .frame(height: 100)
        .padding(Spacing.md)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xl))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.xl)
                .stroke(Color.white.opacity(0.01), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}

// MARK: - Macronutrient Pie Chart
struct MacronutrientPieChart: View {
    let macroData: [MacronutrientData]
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Macronutrient Breakdown")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text("Today's calorie distribution")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            HStack(spacing: 24) {
                // Pie Chart
                Chart(macroData) { macro in
                    SectorMark(
                        angle: .value("Calories", macro.calories),
                        innerRadius: .ratio(0.5),
                        angularInset: 2
                    )
                    .foregroundStyle(macro.color)
                }
                .frame(width: 120, height: 120)
                
                // Legend
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(macroData) { macro in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(macro.color)
                                .frame(width: 12, height: 12)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(macro.name)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                                
                                Text("\(Int(macro.value))g • \(Int(macro.calories)) cal")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                        }
                    }
                }
            }
        }
        .padding(Spacing.lg)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.01), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}

// MARK: - Detailed Nutrition View
struct DetailedNutritionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    let macroData: [MacronutrientData]
    let insights: [NutritionInsight]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Detailed Macronutrient Chart
                    MacronutrientPieChart(macroData: macroData)
                    
                    // Detailed Insights
                    NutritionInsightsCard(insights: insights)
                    
                    // Daily Summary Card
                    dailySummaryCard
                    
                    // Weekly Progress Card  
                    weeklyProgressCard
                }
                .padding()
                .padding(.bottom, 60)
            }
            .background(
                AdaptiveGradient.meals(for: colorScheme)
                .ignoresSafeArea(.all, edges: .all)
            )
            .navigationTitle("Nutrition Details")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.green)
                    .fontWeight(.medium)
                }
            }
        }
    }
    
    private var dailySummaryCard: some View {
        VStack(spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Daily Summary")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text("Today's complete nutrition breakdown")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                SummaryMetricCard(title: "Total Calories", value: "1,920", target: "2,200", color: .red, icon: "flame.fill")
                SummaryMetricCard(title: "Water Intake", value: "6.2L", target: "8L", color: .blue, icon: "drop.fill")
                SummaryMetricCard(title: "Meals Logged", value: "3", target: "4", color: .green, icon: "fork.knife")
                SummaryMetricCard(title: "Nutrition Score", value: "85%", target: "90%", color: .purple, icon: "star.fill")
            }
        }
        .padding(Spacing.lg)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.01), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
    
    private var weeklyProgressCard: some View {
        VStack(spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Weekly Progress")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text("Your nutrition trends this week")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            VStack(spacing: 16) {
                // These show 0 for new users - data comes from actual meal entries
                ProgressRow(title: "Protein Goals Met", progress: 0.0, color: .blue)
                ProgressRow(title: "Hydration Goals", progress: 0.0, color: .cyan)
                ProgressRow(title: "Whole Foods", progress: 0.0, color: .green)
                ProgressRow(title: "Meal Consistency", progress: 0.0, color: .orange)
            }
        }
        .padding(Spacing.lg)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.01), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}

struct SummaryMetricCard: View {
    let title: String
    let value: String
    let target: String
    let color: Color
    let icon: String
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text("Goal: \(target)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 100)
        .padding(Spacing.md)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xl))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.xl)
                .stroke(Color.white.opacity(0.01), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}

struct ProgressRow: View {
    let title: String
    let progress: Double
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text("\(Int(progress * 100))%")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(color)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(height: 8)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: geometry.size.width * progress, height: 8)
                        .animation(.easeInOut(duration: 0.5), value: progress)
                }
            }
            .frame(height: 8)
        }
    }
}

// Simple macro progress row for Today's Macros widget
struct MacroProgressRow: View {
    let title: String
    let current: Int
    let goal: Int
    let unit: String
    let color: Color
    
    private var progress: Double {
        guard goal > 0 else { return 0 }
        return min(Double(current) / Double(goal), 1.0)
    }
    
    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text("\(current)\(unit) / \(goal)\(unit)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(height: 8)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: geometry.size.width * progress, height: 8)
                        .animation(.easeInOut(duration: 0.5), value: progress)
                }
            }
            .frame(height: 8)
        }
    }
}

// Insight item for text view
struct InsightItem: Hashable {
    let icon: String
    let text: String
    let color: Color
    
    init(icon: String = "circle.fill", text: String, color: Color) {
        self.icon = icon
        self.text = text
        self.color = color
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(text)
    }
    
    static func == (lhs: InsightItem, rhs: InsightItem) -> Bool {
        lhs.text == rhs.text
    }
}

// Mini Insight Tile for Daily Insights card - floating style (no background)
struct MiniInsightTile: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            // Floating icon
            Image(systemName: icon)
                .font(.ds_heading3).fontWeight(.semibold)
                .foregroundColor(color)
            
            // Value
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            
            // Title
            Text(title)
                .font(.ds_caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// Simple legend row for Today's Macros (just text, no progress bar)
struct MacroLegendRow: View {
    let name: String
    let current: Int
    let goal: Int
    let color: Color
    var exceeded: Bool = false
    
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            
            Text(name)
                .font(.subheadline)
                .foregroundColor(.primary)
            
            // Show warning icon if exceeded
            if exceeded {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundColor(.red)
            }
            
            Spacer()
            
            Text("\(current)g/\(goal)g")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(exceeded ? .red : .secondary)
        }
    }
}

// Weekly progress row showing days completed out of 7
struct WeeklyProgressRow: View {
    let title: String
    let daysCompleted: Int
    let totalDays: Int
    let color: Color
    
    private var progress: Double {
        guard totalDays > 0 else { return 0 }
        return Double(daysCompleted) / Double(totalDays)
    }
    
    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text("\(daysCompleted)/\(totalDays) days")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(color)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(height: 8)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: geometry.size.width * progress, height: 8)
                        .animation(.easeInOut(duration: 0.5), value: progress)
                }
            }
            .frame(height: 8)
        }
    }
}


// MARK: - Working Nutrition Cards
struct WorkingNutritionInsightCard: View {
    let insight: NutritionInsight
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: insight.icon)
                    .font(.title2)
                    .foregroundColor(insight.color)
                Spacer()
                if let trend = insight.trend {
                    Text(trend)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(insight.color)
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, 2)
                        .background(insight.color.opacity(0.1))
                        .cornerRadius(4)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(insight.value)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text(insight.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text(insight.subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .frame(height: 100)
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.xl)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
        )
    }
}

struct WorkingSummaryMetricCard: View {
    let title: String
    let value: String
    let target: String
    let color: Color
    let icon: String
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text("Goal: \(target)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .frame(height: 100)
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.xl)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
        )
    }
}

// MARK: - Macro Goals Explainer View (First-time popup)
struct MacroGoalsExplainerView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "chart.pie.fill")
                            .font(.system(size: 50))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.green, .blue, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        Text("How Macro Goals Work")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("A quick guide to hitting your nutrition targets")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 20)
                    
                    // Rings Visual
                    HStack(spacing: 30) {
                        MacroRingExample(
                            title: "Calories",
                            color: .green,
                            icon: "flame.fill",
                            minPercent: "100%",
                            maxPercent: "115%"
                        )
                        
                        MacroRingExample(
                            title: "Fat",
                            color: .purple,
                            icon: "drop.fill",
                            minPercent: "100%",
                            maxPercent: "120%"
                        )
                    }
                    .padding(.vertical)
                    
                    // Explanation Cards
                    VStack(spacing: 16) {
                        MacroExplainerCard(
                            icon: "checkmark.circle.fill",
                            iconColor: .green,
                            title: "Hit Your Goals",
                            description: "Reach 100% of your calorie and fat targets to complete your rings."
                        )
                        
                        MacroExplainerCard(
                            icon: "arrow.up.circle.fill",
                            iconColor: .orange,
                            title: "Buffer Zone",
                            description: "Life happens! You can go up to 15% over on calories and 20% over on fat and still hit your goal."
                        )
                        
                        MacroExplainerCard(
                            icon: "xmark.circle.fill",
                            iconColor: .red,
                            title: "Excessive Overage",
                            description: "Go beyond the buffer zone and you'll miss your goal for the day. This helps keep you accountable!"
                        )
                        
                        MacroExplainerCard(
                            icon: "leaf.fill",
                            iconColor: .blue,
                            title: "Protein Exception",
                            description: "Protein has no upper limit — more protein supports muscle building and recovery!"
                        )
                    }
                    .padding(.horizontal)
                    
                    Spacer(minLength: 20)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Got It!") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Macro Ring Example
struct MacroRingExample: View {
    let title: String
    let color: Color
    let icon: String
    let minPercent: String
    let maxPercent: String
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                // Background ring
                Circle()
                    .stroke(color.opacity(0.2), lineWidth: 8)
                    .frame(width: 70, height: 70)
                
                // Progress ring (showing ~100%)
                Circle()
                    .trim(from: 0, to: 0.85)
                    .stroke(
                        LinearGradient(
                            colors: [color, color.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .frame(width: 70, height: 70)
                    .rotationEffect(.degrees(-90))
                
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
            }
            
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 2) {
                Text("Min: \(minPercent)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Max: \(maxPercent)")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }
}

// MARK: - Macro Explainer Card
struct MacroExplainerCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(iconColor)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
    }
}

#Preview {
    ContentView()
}
