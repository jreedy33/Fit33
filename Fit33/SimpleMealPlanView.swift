import SwiftUI
import CoreData

// MARK: - Simple Meal Plan View

struct SimpleMealPlanView: View {
    @Environment(\.scrollToTopTrigger) private var scrollToTopTrigger
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var userManager: UserManager
    @StateObject private var mealService = MealService.shared
    @StateObject private var insightsService = PersonalizedInsightsService.shared
    @StateObject private var deepLinkManager = DeepLinkManager.shared
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
    
    // Two-phase rendering: show core content first, heavy widgets after a beat
    @State private var showSecondaryWidgets = false
    @State private var showingWhatToEat = false
    
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
                    
                    LazyVStack(spacing: 0) {
                        customNutritionHeaderView
                            .padding(.top, 0)
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
                    .padding(.bottom, 20)
                }
                .background(
                    AnimatedOrbBackground.home(colorScheme: colorScheme)
                )
                .contentMargins(.top, 0, for: .scrollContent)
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
            .adaptiveToolbarBackground()
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
        .sheet(isPresented: $showingWhatToEat) {
            WhatToEatView()
        }
        .onReceive(deepLinkManager.$pendingMealType) { mealType in
            guard let mealType = mealType else { return }
            if let meal = MealType(rawValue: mealType) {
                Task {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    selectedMeal = meal
                    deepLinkManager.pendingMealType = nil
                }
            }
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
        HStack(alignment: .center) {
            Text("Nutrition")
                .font(.ds_displayLarge)
                .italic()
                .foregroundStyle(
                    LinearGradient(
                        stops: [
                            .init(color: .white, location: 0.0),
                            .init(color: .white, location: 0.72),
                            .init(color: Color.teal, location: 0.85),
                            .init(color: Color.mint, location: 1.0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .shadow(color: Color.teal.opacity(0.2), radius: 4, x: 0, y: 1)
                .frame(height: 55)
            
            Spacer()
            
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
        .padding(.horizontal, Spacing.xxs)
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
    @State private var insightsViewMode = 1 // 0 = icons/numbers, 1 = text insights
    
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
            HStack(spacing: 8) {
                ForEach(0..<mealTypes.count, id: \.self) { index in
                    let pageIndex = selectedMealPage == -1 ? currentIndex : selectedMealPage
                    let isSelected = pageIndex == index
                    let mealColor = mealTypes[index].gradientColors.0
                    
                    Capsule()
                        .fill(isSelected ? mealColor : Color.gray.opacity(0.3))
                        .frame(width: isSelected ? 20 : 8, height: 6)
                        .animation(.easeOut(duration: 0.2), value: pageIndex)
                        .onTapGesture {
                            HapticManager.impact(.light)
                            selectedMealPage = index
                        }
                }
            }
            .padding(.top, 8)
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
            nutritionSwipeableCards
            
            allMealSectionsView
            
            // Phase 2: Heavy widgets (deferred by one frame to unblock tab transition)
            if showSecondaryWidgets {
                WeightTrackerWidget()
                    .id("weightTracker")
                
                HydrationWidget()
                    .id("hydration")
                
                MealsQuickActionsView(
                    showMealPlanGenerator: $showMealPlanGenerator,
                    showRecipeImport: $showRecipeImport,
                    showRestaurantSearch: $showRestaurantSearch,
                    showShoppingList: $showShoppingList
                )
                
                HealthyRecipesCarousel()
            }
        }
        .task {
            if !showSecondaryWidgets {
                try? await Task.sleep(for: .milliseconds(150))
                withAnimation(.easeIn(duration: 0.3)) {
                    showSecondaryWidgets = true
                }
            }
        }
    }
    
    // MARK: - All Meals View (shows all meal sections at once)
    private var allMealSectionsView: some View {
        VStack(spacing: 12) {
            // Section header
            HStack(spacing: 10) {
                Image(systemName: "fork.knife")
                    .font(.title3)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.green, .mint],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Text("Track Your Meals")
                    .font(.title3)
                    .fontWeight(.bold)
                
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
        VStack(spacing: 0) {
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
                    
                    // Card 2: What to Eat Now
                    whatToEatCard
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
            
            // Page indicators
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(selectedNutritionPage == index ? Color.teal : Color.gray.opacity(0.3))
                        .frame(width: selectedNutritionPage == index ? 20 : 8, height: 6)
                        .animation(.easeOut(duration: 0.2), value: selectedNutritionPage)
                        .onTapGesture {
                            HapticManager.impact(.light)
                            selectedNutritionPage = index
                        }
                }
            }
            .padding(.top, 8)
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
            insights.append(InsightItem(icon: "arrow.up.circle.fill", text: "Need \(proteinRemaining)g protein still! Quick fix: \(quickFixes.randomElement() ?? "Greek yogurt (20g)")", color: .blue))
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
                            colors: Color.cardGradientStops(for: colorScheme),
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
                            colors: Color.cardGradientStops(for: colorScheme),
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
    
    // MARK: - What to Eat Now Card
    private var whatToEatCard: some View {
        let engine = ContextualMealEngine.shared
        
        return VStack(alignment: .leading, spacing: 8) {
            // In-card header
            HStack(alignment: .center) {
                Text("What to Eat Now")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Spacer()
                
                HStack(spacing: 3) {
                    Text("More")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.7))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary.opacity(0.5))
                }
            }
            
            if let suggestion = engine.suggestions.first {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.green.opacity(0.12))
                            .frame(width: 36, height: 36)
                        Image(systemName: "fork.knife")
                            .font(.ds_labelMedium)
                            .foregroundColor(.green)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(suggestion.name)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        Text(suggestion.reason)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    Text("\(suggestion.calories) cal")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.green)
                }
                
                if engine.suggestions.count > 1, let second = engine.suggestions.dropFirst().first {
                    Divider().opacity(0.3)
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(Color.teal.opacity(0.12))
                                .frame(width: 30, height: 30)
                            Image(systemName: "leaf.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.teal)
                        }
                        
                        VStack(alignment: .leading, spacing: 1) {
                            Text(second.name)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                            Text(second.reason)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        
                        Spacer()
                        
                        Text("\(second.calories) cal")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(.teal)
                    }
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.green)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("You're On Track")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        if let ctx = engine.context {
                            Text("\(ctx.caloriesRemaining) cal remaining today")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                }
            }
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.green.opacity(colorScheme == .dark ? 0.15 : 0.08))
                    .offset(y: 6)
                    .blur(radius: 3)
                
                RoundedRectangle(cornerRadius: 25, style: .continuous)
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                    .offset(y: 3)
                
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
                
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.green.opacity(colorScheme == .dark ? 0.4 : 0.3), Color.teal.opacity(colorScheme == .dark ? 0.3 : 0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.06), radius: 8, x: 0, y: 4)
        .shadow(color: .green.opacity(colorScheme == .dark ? 0.2 : 0.12), radius: 12, x: 0, y: 6)
        .contentShape(Rectangle())
        .onTapGesture {
            HapticManager.impact(.light)
            showingWhatToEat = true
        }
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
