import SwiftUI
import CoreData
import Combine
import Charts

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

// MARK: - Robust Adaptive Card Modifier
extension View {
    func robustWhiteCard(cornerRadius: CGFloat = 16, shadowRadius: CGFloat = 5, shadowOpacity: Double = 0.1) -> some View {
        self.modifier(AdaptiveWhiteCardModifier(cornerRadius: cornerRadius, shadowRadius: shadowRadius, shadowOpacity: shadowOpacity))
    }
}

struct AdaptiveWhiteCardModifier: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    let cornerRadius: CGFloat
    let shadowRadius: CGFloat
    let shadowOpacity: Double
    
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.cardBackground)
                    .shadow(color: colorScheme == .dark ? .clear : .black.opacity(shadowOpacity), radius: shadowRadius, x: 0, y: 2)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.clear, lineWidth: 1)
            )
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
    
    var body: some View {
        Group {
            if userManager.hasCompletedOnboarding {
                MainTabView()
            } else {
                NewOnboardingView()
            }
        }
        .environmentObject(userManager)
        .environmentObject(workoutManager)
        .task {
            // 🔄 ONE-TIME FORCE SYNC: Check if we need to refresh exercise data
            // This ensures users get the latest improved exercise data
            let needsRefresh = UserDefaults.standard.string(forKey: "exerciseDataVersion") != "v2.0"
            
            if needsRefresh && SupabaseManager.shared.isAuthenticated {
                print("🔄 Detected new exercise data version - forcing fresh sync...")
                await ExerciseLibraryService.shared.forceSyncExercises()
                UserDefaults.standard.set("v2.0", forKey: "exerciseDataVersion")
                print("✅ Exercise data updated to v2.0")
            }
        }
    }
}

// MARK: - Notification for GO Button visibility
extension Notification.Name {
    static let goButtonVisibilityChanged = Notification.Name("goButtonVisibilityChanged")
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
    
    // Tracking
    private var showTime: Date?
    private var showSource: String = ""
    
    private init() {}
    
    func show(primaryColor: Color = Color(red: 0.2, green: 0.7, blue: 0.3),
              secondaryColor: Color? = nil,
              source: String = "unknown",
              action: @escaping () -> Void) {
        print("🟢 [GoButton] show() called")
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
        self.startAction = action
        self.showVersion += 1 // Increment version to invalidate pending hide() calls
        
        DispatchQueue.main.async {
            self.isVisible = true
            print("🟢 [GoButton] isVisible = true")
        }
    }
    
    func hide(reason: String = "navigation") {
        print("🔴 [GoButton] hide() called")
        
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
                print("🔴 [GoButton] Hidden and cleared")
            } else {
                print("🔴 [GoButton] Hidden but action preserved (new show() pending)")
            }
        }
    }
    
    func triggerStart() {
        let startTime = CFAbsoluteTimeGetCurrent()
        print("⏱️ [GoButton] triggerStart() BEGIN")
        
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
            print("⚠️ [GoButton] Already triggering, ignoring duplicate call")
            SessionLogManager.shared.log(.warning, category: .userAction, message: "⚠️ GO! DOUBLE TAP BLOCKED")
            return
        }
        
        // Capture action before any state changes
        guard let action = startAction else {
            print("❌ [GoButton] No startAction set!")
            SessionLogManager.shared.log(.error, category: .error, message: "❌ GO! NO ACTION", metadata: [
                "element_id": "E200"
            ])
            return
        }
        
        // Mark as triggering and hide button immediately
        isTriggering = true
        isVisible = false
        
        print("⏱️ [GoButton] Executing action...")
        let actionStart = CFAbsoluteTimeGetCurrent()
        
        // Execute action synchronously
        action()
        
        let actionDuration = (CFAbsoluteTimeGetCurrent() - actionStart) * 1000
        let totalDuration = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        
        print("⏱️ [GoButton] Action took: \(actionDuration)ms")
        print("⏱️ [GoButton] TOTAL: \(totalDuration)ms")
        
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
        
        // Clear state after a brief moment
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.startAction = nil
            self?.isTriggering = false
            print("🎯 [GoButton] State reset complete")
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
                        secondaryColor: state.secondaryColor
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

struct MainTabView: View {
    @EnvironmentObject var workoutManager: WorkoutManager
    @EnvironmentObject var userManager: UserManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedTab: Int = 0
    @State private var scrollToTopTrigger: UUID = UUID()
    
    private let tabs = [
        TabItem(icon: "house", selectedIcon: "house.fill", title: "Home", color: .blue),
        TabItem(icon: "book", selectedIcon: "book.fill", title: "Exercises", color: Color(red: 0.0, green: 0.75, blue: 0.75)),
        TabItem(icon: "dumbbell", selectedIcon: "dumbbell.fill", title: "Workout", color: .green),
        TabItem(icon: "leaf", selectedIcon: "leaf.fill", title: "Meals", color: .mint),
        TabItem(icon: "chart.line.uptrend.xyaxis", selectedIcon: "chart.line.uptrend.xyaxis", title: "Stats", color: .purple)
    ]
    
    private var currentTabColor: Color {
        // Workout tab turns red when workout is active
        if selectedTab == 2 && workoutManager.isWorkoutActive {
            return .red
        }
        return tabs[selectedTab].color
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem {
                    Label {
                        Text(tabs[0].title)
                    } icon: {
                        Image(systemName: selectedTab == 0 ? tabs[0].selectedIcon : tabs[0].icon)
                    }
                }
                .tag(0)
            
            ExerciseLibraryView()
                .tabItem {
                    Label {
                        Text(tabs[1].title)
                    } icon: {
                        Image(systemName: selectedTab == 1 ? tabs[1].selectedIcon : tabs[1].icon)
                    }
                }
                .tag(1)
            
            WorkoutTabView()
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
                    } else {
                        Label {
                            Text(tabs[2].title)
                        } icon: {
                            Image(systemName: selectedTab == 2 ? tabs[2].selectedIcon : tabs[2].icon)
                        }
                    }
                }
                .tag(2)
            
            SimpleMealPlanView()
                .tabItem {
                    Label {
                        Text(tabs[3].title)
                    } icon: {
                        Image(systemName: selectedTab == 3 ? tabs[3].selectedIcon : tabs[3].icon)
                    }
                }
                .tag(3)
            
            WorkoutProgressView()
                .tabItem {
                    Label {
                        Text(tabs[4].title)
                    } icon: {
                        Image(systemName: selectedTab == 4 ? tabs[4].selectedIcon : tabs[4].icon)
                    }
                }
                .tag(4)
        }
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
                
                print("🏠 ContentView: Switching to home tab")
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
                
                print("🏠 ContentView: Switching to home tab (instant)")
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
        .onChange(of: selectedTab) { oldValue, newValue in
            if oldValue != newValue {
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
                    "timestamp_ms": Int(Date().timeIntervalSince1970 * 1000)
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
        .preferredColorScheme(.light)
            
            // GO! Button overlay - isolated view that observes its own state
            GoButtonOverlay()
        }
    }
    
    // Update the workout tab label color
    private func updateWorkoutTabLabelColor(isRed: Bool) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first else { return }
            
            // Find all UITabBarButtons and update the workout one (index 2)
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first else { return }
            
            if let tabBar = findTabBar(in: window) {
                let tabBarButtons = tabBar.subviews.filter { String(describing: type(of: $0)).contains("Button") }
                if tabBarButtons.count > 2 {
                    let sortedButtons = tabBarButtons.sorted { $0.frame.minX < $1.frame.minX }
                    let workoutButton = sortedButtons[2] // Workout tab is index 2
                    
                    UIView.animate(withDuration: 0.2) {
                        if isGoButtonVisible {
                            // Scale down the workout tab when GO button is visible
                            workoutButton.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
                            workoutButton.alpha = 0.2
                        } else {
                            // Reset to normal
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
    @State private var showingProfileSetup = false
    @State private var showingMacroGoalsExplainer = false
    @AppStorage("hasSeenMacroGoalsExplainer") private var hasSeenMacroGoalsExplainer = false
    @State private var selectedMeal: MealType? = nil {
        didSet {
            print("🔄 [CONTENTVIEW] selectedMeal changed to: \(String(describing: selectedMeal))")
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Hidden NavigationLink for food search
                NavigationLink(
                    destination: Group {
                        if let meal = selectedMeal {
                            FoodSearchView(mealType: meal) { foodEntry in
                                print("🍽️ [CONTENTVIEW] Food entry received: \(foodEntry.name)")
                                print("🍽️ [CONTENTVIEW] Meal type: \(meal.rawValue)")
                                print("🍽️ [CONTENTVIEW] Calories: \(foodEntry.calories)")
                                
                                // Save to meal service
                                if let user = userManager.currentUser {
                                    print("🍽️ [CONTENTVIEW] User found, calling MealService.addMealEntry")
                                    MealService.shared.addMealEntry(foodEntry, mealType: meal, user: user)
                                    print("🍽️ [CONTENTVIEW] MealService.addMealEntry completed")
                                    
                                    // Show macro goals explainer on first meal input
                                    if !hasSeenMacroGoalsExplainer {
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                            showingMacroGoalsExplainer = true
                                            hasSeenMacroGoalsExplainer = true
                                        }
                                    }
                                } else {
                                    print("❌ [CONTENTVIEW] No current user found!")
                                }
                                
                                // Reset selection to dismiss
                                selectedMeal = nil
                            }
                            .onAppear {
                                print("🚀 [CONTENTVIEW] FoodSearchView appeared for meal: \(meal.rawValue)")
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
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 100)
                }
                .background(
                    AdaptiveGradient.meals(for: colorScheme)
                    .ignoresSafeArea(.all, edges: .all)
                )
                .onChange(of: scrollToTopTrigger) { _, _ in
                    scrollProxy.scrollTo("top", anchor: .top)
                }
            }
            .navigationBarHidden(true)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            }
        }
        .onAppear {
            print("📊 [MEAL PLAN] View appeared, loading today's meals")
            mealService.loadTodaysMeals()
            print("📊 [MEAL PLAN] Loaded \(mealService.todaysMeals.count) meals")
            print("📊 [MEAL PLAN] Consumed calories: \(consumedCalories)")
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
            Text("Meals")
                .font(.system(size: 42, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.mint, .mint, .mint, Color(red: 0.4, green: 0.95, blue: 0.8).opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .mint.opacity(0.4), radius: 6, x: 0, y: 2)
            
            Spacer()
            
            // Active workout timer (only shows when workout is active)
            if WorkoutManager.shared.isWorkoutActive {
                Text(WorkoutManager.shared.formattedDuration)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
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
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [Color.green, Color.mint]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(12)
        }
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 20)
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
            RoundedRectangle(cornerRadius: 20)
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
    
    private var mealSectionsCard: some View {
        let mealColors = currentMealTimeColors
        
        return VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "fork.knife")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [mealColors.primary, mealColors.secondary],
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
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)
            
            Divider()
                .padding(.horizontal, 16)
            
            // Stacked Meal Cards
            VStack(spacing: 10) {
                // Breakfast
                MealRowCard(
                    mealType: .breakfast,
                    meals: mealService.todaysMeals.filter { $0.mealType == .breakfast },
                    isMostRecent: mostRecentMealType == .breakfast,
                    onAddFood: {
                        selectedMeal = .breakfast
                    },
                    onDelete: { meal in
                        mealService.removeMealEntry(meal)
                    }
                )
                
                // Lunch
                MealRowCard(
                    mealType: .lunch,
                    meals: mealService.todaysMeals.filter { $0.mealType == .lunch },
                    isMostRecent: mostRecentMealType == .lunch,
                    onAddFood: {
                        selectedMeal = .lunch
                    },
                    onDelete: { meal in
                        mealService.removeMealEntry(meal)
                    }
                )
                
                // Dinner
                MealRowCard(
                    mealType: .dinner,
                    meals: mealService.todaysMeals.filter { $0.mealType == .dinner },
                    isMostRecent: mostRecentMealType == .dinner,
                    onAddFood: {
                        selectedMeal = .dinner
                    },
                    onDelete: { meal in
                        mealService.removeMealEntry(meal)
                    }
                )
                
                // Snacks
                MealRowCard(
                    mealType: .snacks,
                    meals: mealService.todaysMeals.filter { $0.mealType == .snacks },
                    isMostRecent: mostRecentMealType == .snacks,
                    onAddFood: {
                        selectedMeal = .snacks
                    },
                    onDelete: { meal in
                        mealService.removeMealEntry(meal)
                    }
                )
            }
            .padding(16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .background(
            ZStack {
                // Bottom shadow layer (deepest) - meal time colored
                RoundedRectangle(cornerRadius: 24)
                    .fill(mealColors.primary.opacity(colorScheme == .dark ? 0.15 : 0.08))
                    .offset(y: 8)
                    .blur(radius: 4)
                
                // Middle shadow layer
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                    .offset(y: 4)
                
                // Main card background with gradient
                RoundedRectangle(cornerRadius: 20)
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
                
                // Colored accent border - matches current meal time
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            colors: [
                                mealColors.primary.opacity(colorScheme == .dark ? 0.4 : 0.3),
                                mealColors.secondary.opacity(colorScheme == .dark ? 0.3 : 0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 12, x: 0, y: 6)
        .shadow(color: mealColors.primary.opacity(colorScheme == .dark ? 0.2 : 0.12), radius: 20, x: 0, y: 10)
    }
    
    // MARK: - Main Comprehensive Nutrition View
    private var comprehensiveNutritionView: some View {
        VStack(spacing: 24) {
            // 1. Today's Macros + Weekly Progress (combined widget)
            enhancedNutritionOverviewCard
            
            // 2. Track Your Meals (most important - right after macros)
            mealSectionsCard
            
            // 3. Hydration Tracking
            HydrationWidget()
            
            // 4. Daily Summary
            dailySummaryMainCard
        }
    }
    
    // MARK: - Enhanced Nutrition Overview with Integrated Pie Chart
    private var enhancedNutritionOverviewCard: some View {
        VStack(spacing: 20) {
            // MARK: Today's Macros Section
            VStack(spacing: 14) {
                // Header with Total Calories
                HStack(alignment: .top) {
                    Text("Today's Macros")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(consumedCalories)")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        
                        Text("of \(calorieGoal) cal")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Nutrition Rings with Legend
                HStack(spacing: 20) {
                    // Triple Nutrition Ring (shows red + warning if exceeded)
                    NutritionTripleRing(
                        caloriesProgress: caloriesProgress,
                        proteinProgress: proteinProgress,
                        fatProgress: fatProgress,
                        size: 100,
                        caloriesExceeded: caloriesExceeded,
                        fatExceeded: fatExceeded
                    )
                    
                    VStack(alignment: .leading, spacing: 10) {
                        MacroLegendRow(name: "Calories", current: consumedCalories, goal: calorieGoal, color: caloriesExceeded ? .red : .green, exceeded: caloriesExceeded)
                        MacroLegendRow(name: "Protein", current: consumedProtein, goal: proteinGoal, color: .blue)
                        MacroLegendRow(name: "Fat", current: consumedFat, goal: fatGoal, color: fatExceeded ? .red : .purple, exceeded: fatExceeded)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            
            // Thin grey divider
            Rectangle()
                .fill(Color(.systemGray4))
                .frame(height: 1)
            
            // MARK: Weekly Progress Section
            VStack(spacing: 14) {
                HStack {
                    Text("Weekly Progress")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    Spacer()
                }
                
                VStack(spacing: 12) {
                    WeeklyProgressRow(title: "Calorie Target", daysCompleted: weeklyCalorieDaysMet, totalDays: 7, color: .green)
                    WeeklyProgressRow(title: "Protein Goals Met", daysCompleted: weeklyProteinDaysMet, totalDays: 7, color: .blue)
                    WeeklyProgressRow(title: "Fat Goals Met", daysCompleted: weeklyFatDaysMet, totalDays: 7, color: .purple)
                }
            }
        }
       
        .padding(18)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .background(
            ZStack {
                // Bottom shadow layer (deepest) - teal colored
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.teal.opacity(colorScheme == .dark ? 0.15 : 0.08))
                    .offset(y: 8)
                    .blur(radius: 4)
                
                // Middle shadow layer
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                    .offset(y: 4)
                
                // Main card background with gradient
                RoundedRectangle(cornerRadius: 16)
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
                RoundedRectangle(cornerRadius: 16)
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
                
                // Colored accent border - teal/cyan gradient (matches Daily Steps)
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.teal.opacity(colorScheme == .dark ? 0.4 : 0.3),
                                Color.cyan.opacity(colorScheme == .dark ? 0.3 : 0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 12, x: 0, y: 6)
        .shadow(color: Color.teal.opacity(colorScheme == .dark ? 0.2 : 0.12), radius: 20, x: 0, y: 10)
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
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)
            
            Divider()
                .padding(.horizontal, 16)
            
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
                .padding(16)
            }
            
            // Opportunities
            if !improvementSuggestions.isEmpty {
                if !positiveInsights.isEmpty {
                    Divider()
                        .padding(.horizontal, 16)
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
                .padding(16)
            }
            
            // Quick Stats Row
            Divider()
                .padding(.horizontal, 16)
            
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
                .padding(.horizontal, 16)
            
            Text(dailyTip)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
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
                .font(.system(size: 14))
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
                    .font(.system(size: 10))
                    .foregroundColor(color)
                Text(value)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            }
            Text(label)
                .font(.system(size: 10))
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
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
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
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
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
                            .font(.system(size: 15, weight: .semibold))
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
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
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
                                        ? [Color(white: 0.15), Color(white: 0.12)]
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
                        .padding(.horizontal, 16)
                    
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
                                    .padding(.horizontal, 16)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                    
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
                                    .font(.system(size: 14))
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
                    .padding(.horizontal, 16)
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
                                ? [Color(white: 0.15), Color(white: 0.12)]
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
                    .font(.system(size: 20))
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
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .clipShape(Capsule())
    }
}

// MARK: - Legacy Meal Widget Card (kept for compatibility)
struct MealWidgetCard: View {
    let mealType: MealType
    let meals: [MealEntryData]
    let onAddFood: () -> Void
    let onDelete: (MealEntryData) -> Void
    
    @State private var isExpanded = false
    
    private var totalCalories: Int {
        meals.reduce(0) { $0 + $1.calories }
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
        case .lunch: return .yellow
        case .dinner: return .indigo
        case .snacks: return .green
        }
    }
    
    private var gradientColors: [Color] {
        switch mealType {
        case .breakfast: return [.orange, .yellow]
        case .lunch: return [.yellow, .orange]
        case .dinner: return [.indigo, .purple]
        case .snacks: return [.green, .mint]
        }
    }
    
    private var timeHint: String {
        switch mealType {
        case .breakfast: return "6-10 AM"
        case .lunch: return "11-2 PM"
        case .dinner: return "5-9 PM"
        case .snacks: return "Anytime"
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Main card content
            VStack(spacing: 10) {
                // Floating colored icon
                Image(systemName: mealIcon)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundColor(mealColor)
                    .frame(width: 44, height: 44)
                
                // Meal name and time
                VStack(spacing: 2) {
                    Text(mealType.displayName)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text(timeHint)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                // Status indicator
                if meals.isEmpty {
                    // Empty state - Add button (solid color)
                    Button(action: onAddFood) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(mealColor)
                    }
                    .buttonStyle(PlainButtonStyle())
                } else {
                    // Has items - show calories and count
                    VStack(spacing: 6) {
                        HStack(spacing: 4) {
                            Text("\(totalCalories)")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                            Text("cal")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        // Item count badge
                        Text("\(meals.count) item\(meals.count == 1 ? "" : "s")")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(mealColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(mealColor.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(meals.isEmpty ? Color.gray.opacity(0.15) : mealColor.opacity(0.25), lineWidth: 1.5)
            )
            .onTapGesture {
                if !meals.isEmpty {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isExpanded.toggle()
                    }
                } else {
                    onAddFood()
                }
            }
            
            // Expanded meal items
            if isExpanded && !meals.isEmpty {
                VStack(spacing: 0) {
                    ForEach(meals, id: \.id) { meal in
                        MealItemRow(meal: meal, color: mealColor) {
                            onDelete(meal)
                        }
                    }
                    
                    // Add more button
                    Button(action: onAddFood) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                                .font(.caption)
                            Text("Add more")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(mealColor)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.top, 6)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - Meal Item Row
struct MealItemRow: View {
    let meal: MealEntryData
    let color: Color
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(meal.foodName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text("\(meal.displayQuantity) \(meal.unit)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text("\(meal.calories)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(color)
            
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.red.opacity(0.6))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

// MARK: - Meal Quick Stat
struct MealQuickStat: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(color)
                
                Text(value)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
            }
            
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// Legacy component kept for compatibility
struct MealSectionWithItems: View {
    let title: String
    let icon: String
    let color: Color
    let meals: [MealEntryData]
    let onAddFood: () -> Void
    let onDelete: (MealEntryData) -> Void
    
    var body: some View {
        VStack(spacing: 8) {
            // Header with Add button
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(color)
                
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button(action: onAddFood) {
                    HStack(spacing: 4) {
                        Text("Add Food")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                        Image(systemName: "plus.circle.fill")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            // Meal items list
            if !meals.isEmpty {
                VStack(spacing: 4) {
                    ForEach(meals, id: \.id) { meal in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(meal.foodName)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                                
                                Text("\(Int(meal.quantity)) \(meal.unit)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Text("\(meal.calories) cal")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                            
                            Button(action: {
                                onDelete(meal)
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(.red.opacity(0.6))
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(8)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
}

struct SimpleProfileSetupView: View {
    @EnvironmentObject var userManager: UserManager
    @Binding var showingProfileSetup: Bool
    @State private var weight: String = ""
    @State private var height: String = ""
    @State private var gender: String = "Male"
    
    var body: some View {
        NavigationView {
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
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.green, Color.mint]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .cornerRadius(12)
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
            print("✅ [PROFILE] Saved weight: \(weightValue), height: \(heightValue)")
        } catch {
            print("❌ [PROFILE] Error saving: \(error)")
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
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 8)
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
        NavigationView {
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
                        print("🔍 [CONTENTVIEW] Search text changed to: '\(newValue)'")
                        searchDebouncer?.invalidate()
                        searchDebouncer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
                            print("⏰ [CONTENTVIEW] Debounce timer fired for: '\(newValue)'")
                            if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                print("✅ [CONTENTVIEW] Calling foodService.searchFoods() for: '\(newValue)'")
                                foodService.searchFoods(query: newValue)
                            } else {
                                print("⚠️ [CONTENTVIEW] Query empty, clearing results")
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
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
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
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
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
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
            .cornerRadius(12)
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
                        .font(.system(size: 14, weight: .semibold))
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
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
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
                        .padding(.horizontal, 8)
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
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
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
        .padding(24)
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
        NavigationView {
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
        .padding(24)
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
        .padding(24)
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
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
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
            
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray5))
                    .frame(height: 8)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(color)
                    .frame(width: UIScreen.main.bounds.width * 0.75 * progress, height: 8)
                    .animation(.easeInOut(duration: 0.5), value: progress)
            }
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
                        .padding(.horizontal, 8)
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
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
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
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
        )
    }
}

// MARK: - Macro Goals Explainer View (First-time popup)
struct MacroGoalsExplainerView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
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
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    ContentView()
}
