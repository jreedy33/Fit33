import SwiftUI
import CoreData

struct MealPlanView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var userManager: UserManager
    @State private var showingProfileSetup = false
    @State private var showingAddFood = false
    @State private var selectedMeal: MealType = .breakfast
    @StateObject private var mealService = MealService.shared
    @ObservedObject private var savedMealsService = SavedMealsService.shared
    @State private var nutritionGoals: NutritionGoals?
    @State private var showingSavedMealDetail: SavedMeal?
    @State private var showingShoppingList = false
    
    var body: some View {
        NavigationStack {
            Group {
                if needsProfileSetup {
                    ProfileSetupView(showingProfileSetup: $showingProfileSetup)
                } else {
                    mainNutritionView
                }
            }
            .navigationTitle("Nutrition")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: clearAllMeals) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .accessibilityLabel("Clear all meals")
                    .accessibilityHint("Remove all food entries for today")
                }
            }
            .adaptiveToolbarBackground()
        }
        .onAppear {
            SessionLogManager.shared.logScreen(.mealsTab, metadata: [
                "date": Date().description
            ])
            loadTodaysData()
        }
        .sheet(isPresented: $showingAddFood) {
            FoodSearchView(mealType: selectedMeal) { foodEntry in
                AppLogger.debug("Food entry received: \(foodEntry.name)", category: .nutrition)
                addFoodEntry(foodEntry)
            }
            .environmentObject(userManager)
        }
        .onChange(of: showingAddFood) { isShowing in
            AppLogger.debug("Sheet presentation state changed: \(isShowing)", category: .nutrition)
        }
    }
    
    private var needsProfileSetup: Bool {
        guard let user = userManager.currentUser else { return true }
        
        // Check Core Data first, fallback to UserDefaults
        let userWeight = user.weight > 0 ? Int(user.weight) : UserDefaults.standard.integer(forKey: "userWeight")
        let userHeight = user.height > 0 ? Int(user.height) : UserDefaults.standard.integer(forKey: "userHeight")
        
        return userWeight == 0 || userHeight == 0 || nutritionGoals == nil
    }
    
    private var topFadeOverlay: some View {
        VStack(spacing: 0) {
            let fadeColor = colorScheme == .dark
                ? Color(red: 0.06, green: 0.06, blue: 0.06)
                : Color.white
            fadeColor.frame(height: 30)
            LinearGradient(
                stops: [
                    .init(color: fadeColor, location: 0),
                    .init(color: fadeColor.opacity(0.6), location: 0.4),
                    .init(color: fadeColor.opacity(0), location: 1.0)
                ],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 50)
            .allowsHitTesting(false)
            Spacer()
        }
        .ignoresSafeArea(.all, edges: .top)
    }
    
    private var mainNutritionView: some View {
        ZStack {
        ScrollView {
            VStack(spacing: 24) {
                // Nutrition Goals Overview
                nutritionOverviewCard
                
                // Saved Meals Section (if any)
                if !savedMealsService.savedMeals.isEmpty {
                    savedMealsSection
                }
                
                // Quick Actions (Shopping List)
                quickActionsSection
                
                // Meal Sections
                ForEach(MealType.allCases, id: \.self) { mealType in
                    mealSection(for: mealType)
                }
            }
            .padding()
        }
        .background(
            AnimatedOrbBackground.meals(colorScheme: colorScheme)
                .ignoresSafeArea(.all, edges: .all)
                .accessibilityHidden(true)
        )
        topFadeOverlay
        }
        .sheet(item: $showingSavedMealDetail) { meal in
            SavedMealDetailView(meal: meal)
        }
        .sheet(isPresented: $showingShoppingList) {
            MyShoppingListView()
        }
    }
    
    private var nutritionOverviewCard: some View {
        VStack(spacing: 16) {
            Text("Today's Macros")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            HStack(spacing: 12) {
                NutritionProgressCard(
                    title: "Calories",
                    current: currentCalories,
                    goal: nutritionGoals?.calories ?? 2000,
                    unit: "",
                    color: .red,
                    colorScheme: colorScheme
                )
                .accessibilityLabel("Calories: \(currentCalories) of \(nutritionGoals?.calories ?? 2000)")
                
                NutritionProgressCard(
                    title: "Protein",
                    current: currentProtein,
                    goal: nutritionGoals?.protein ?? 150,
                    unit: "g",
                    color: .blue,
                    colorScheme: colorScheme
                )
                .accessibilityLabel("Protein: \(currentProtein) of \(nutritionGoals?.protein ?? 150) grams")
                
                NutritionProgressCard(
                    title: "Carbs",
                    current: currentCarbs,
                    goal: nutritionGoals?.carbs ?? 250,
                    unit: "g",
                    color: .orange,
                    colorScheme: colorScheme
                )
                .accessibilityLabel("Carbs: \(currentCarbs) of \(nutritionGoals?.carbs ?? 250) grams")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg))
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
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .fill(
                        LinearGradient(
                            colors: Color.cardGradientStops(for: colorScheme),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                // Inner highlight (top edge glow)
                RoundedRectangle(cornerRadius: CornerRadius.lg)
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
                RoundedRectangle(cornerRadius: CornerRadius.lg)
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
    
    private func mealSection(for mealType: MealType) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(mealType.displayName)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button(action: {
                    AppLogger.debug("Add food button tapped for \(mealType.displayName)", category: .nutrition)
                    selectedMeal = mealType
                    showingAddFood = true
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.green)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Add food to \(mealType.displayName)")
                .accessibilityHint("Search and add a food item")
                .buttonStyle(PlainButtonStyle())
            }
            
            let mealEntries = mealService.todaysMeals.filter { $0.mealType == mealType }
            
            if mealEntries.isEmpty {
                Text("No items added")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.md)
                            .fill(colorScheme == .dark ? Color(white: 0.18) : Color(.systemGray6))
                    )
            } else {
                VStack(spacing: 8) {
                    ForEach(mealEntries, id: \.id) { entry in
                        MealEntryRow(entry: entry, colorScheme: colorScheme) {
                            mealService.removeMealEntry(entry)
                        }
                    }
                }
            }
        }
        .padding(Spacing.md)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color(white: 0.13), Color(white: 0.10)]
                                : [Color.white, Color.white.opacity(0.95)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                // Inner highlight
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .stroke(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color.white.opacity(0.08), Color.clear]
                                : [Color.white, Color.white.opacity(0.5)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 8, x: 0, y: 4)
        )
    }
    
    // MARK: - Saved Meals Section
    
    private var savedMealsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "bookmark.fill")
                    .foregroundColor(.orange)
                
                Text("Saved Meals")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text("\(savedMealsService.savedMeals.count)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, Spacing.xxs)
                    .background(
                        Capsule()
                            .fill(Color.orange)
                    )
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(savedMealsService.savedMeals) { meal in
                        SavedMealCard(meal: meal) {
                            showingSavedMealDetail = meal
                        }
                    }
                }
                .padding(.vertical, Spacing.xxs)
            }
        }
        .padding(Spacing.md)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color(white: 0.13), Color(white: 0.10)]
                                : [Color.white, Color.white.opacity(0.95)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                // Inner highlight
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .stroke(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color.white.opacity(0.08), Color.clear]
                                : [Color.white, Color.white.opacity(0.5)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                
                // Orange accent
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 8, x: 0, y: 4)
        )
    }
    
    // MARK: - Quick Actions Section
    
    private var quickActionsSection: some View {
        HStack(spacing: 12) {
            // Shopping List Button
            Button {
                showingShoppingList = true
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.purple, .pink],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 36, height: 36)
                        
                        Image(systemName: "cart.fill")
                            .font(.ds_labelLarge)
                            .foregroundColor(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Shopping List")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        Text("\(savedMealsService.shoppingListItems.count) items")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(colorScheme == .dark ? Color.cardBackground : Color.white)
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    // MARK: - Computed Properties
    
    private var currentCalories: Int {
        mealService.todaysMeals.reduce(0) { $0 + $1.calories }
    }
    
    private var currentProtein: Int {
        mealService.todaysMeals.reduce(0) { $0 + $1.protein }
    }
    
    private var currentCarbs: Int {
        mealService.todaysMeals.reduce(0) { $0 + $1.carbs }
    }
    
    // MARK: - Methods
    
    private func loadTodaysData() {
        // Load today's meals and calculate nutrition goals
        calculateNutritionGoals()
        mealService.loadTodaysMeals()
    }
    
    private func calculateNutritionGoals() {
        guard let user = userManager.currentUser else { return }
        
        let weight = UserDefaults.standard.integer(forKey: "userWeight")
        let height = UserDefaults.standard.integer(forKey: "userHeight")
        let age = Int(user.age)
        
        guard weight > 0, height > 0, age > 0 else { return }
        
        // Calculate BMR using Mifflin-St Jeor Equation
        let weightKg = Double(weight) * 0.453592 // Convert lbs to kg
        let heightCm = Double(height) * 2.54 // Convert inches to cm
        let ageYears = Double(age)
        
        var bmr: Double
        let gender = UserDefaults.standard.string(forKey: "userGender") ?? "male"
        if gender.lowercased() == "male" {
            bmr = (10 * weightKg) + (6.25 * heightCm) - (5 * ageYears) + 5
        } else {
            bmr = (10 * weightKg) + (6.25 * heightCm) - (5 * ageYears) - 161
        }
        
        // Activity factor (moderate activity)
        let tdee = bmr * 1.55
        
        // Adjust based on fitness goal
        var calorieGoal = tdee
        switch user.fitnessGoal?.lowercased() {
        case "lose weight", "lean out":
            calorieGoal = tdee - 500 // 1 lb per week deficit
        case "gain weight", "gain muscle", "build muscle":
            calorieGoal = tdee + 300 // Moderate surplus
        default:
            calorieGoal = tdee // Maintenance
        }
        
        // Calculate macro goals
        let proteinGoal = Double(weight) * 1.0 // 1g per lb body weight
        let fatGoal = calorieGoal * 0.25 / 9 // 25% of calories from fat
        let carbGoal = (calorieGoal - (proteinGoal * 4) - (fatGoal * 9)) / 4
        
        nutritionGoals = NutritionGoals(
            calories: Int(calorieGoal),
            protein: Int(proteinGoal),
            carbs: Int(carbGoal),
            fat: Int(fatGoal)
        )
    }
    
    private func addFoodEntry(_ entry: FoodEntry) {
        AppLogger.debug("🍽️ [MEAL PLAN] addFoodEntry called for: \(entry.name)", category: .nutrition)
        AppLogger.debug("🍽️ [MEAL PLAN] Meal type: \(selectedMeal)", category: .nutrition)
        AppLogger.debug("🍽️ [MEAL PLAN] FDC ID: \(entry.fdcId ?? -1)", category: .nutrition)
        
        guard let user = userManager.currentUser else {
            AppLogger.error("❌ [MEAL PLAN] No current user found!", category: .nutrition)
            return
        }
        
        AppLogger.info("✅ [MEAL PLAN] User found: \(user.email ?? "no email")", category: .nutrition)
        AppLogger.debug("🔄 [MEAL PLAN] Calling mealService.addMealEntry...", category: .nutrition)
        mealService.addMealEntry(entry, mealType: selectedMeal, user: user)
        AppLogger.info("✅ [MEAL PLAN] addMealEntry call completed", category: .nutrition)
    }
    
    private func clearAllMeals() {
        AppLogger.debug("🗑️ [MEAL PLAN] Clearing ALL meal entries from database", category: .nutrition)
        mealService.clearAllMeals()
        AppLogger.info("✅ [MEAL PLAN] All meals cleared, reloading...", category: .nutrition)
        loadTodaysData()
    }
}

// MARK: - Supporting Views

struct ProfileSetupView: View {
    @EnvironmentObject var userManager: UserManager
    @Binding var showingProfileSetup: Bool
    @State private var weight: String = ""
    @State private var height: String = ""
    @State private var age: String = ""
    @State private var gender: String = "Male"
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 16) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.green)
                    
                    Text("Complete Your Profile")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("We need some basic information to calculate your nutrition goals based on your fitness goal: \"\(userManager.currentUser?.fitnessGoal ?? "Build Muscle")\"")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                // Form
                VStack(spacing: 20) {
                    ProfileInputField(title: "Weight (lbs)", value: $weight, placeholder: "150")
                    ProfileInputField(title: "Height (inches)", value: $height, placeholder: "70")
                    ProfileInputField(title: "Age", value: $age, placeholder: "25")
                    
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
                
                // Save Button
                Button(action: saveProfile) {
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
        .background(
            LinearGradient(
                gradient: Gradient(colors: [Color.green.opacity(0.1), Color.mint.opacity(0.05)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea(.all)
        )
    }
    
    private var isFormValid: Bool {
        !weight.isEmpty && !height.isEmpty && !age.isEmpty &&
        Int(weight) != nil && Int(height) != nil && Int(age) != nil
    }
    
    private func saveProfile() {
        guard let user = userManager.currentUser,
              let weightValue = Int(weight),
              let heightValue = Int(height),
              let ageValue = Int(age) else { return }
        
        // Save to Core Data (primary storage)
        user.weight = Int16(weightValue)
        user.height = Int16(heightValue)
        user.age = Int16(ageValue)
        user.gender = gender
        
        // Also save to UserDefaults for backwards compatibility
        UserDefaults.standard.set(weightValue, forKey: "userWeight")
        UserDefaults.standard.set(heightValue, forKey: "userHeight")
        UserDefaults.standard.set(gender, forKey: "userGender")
        
        do {
            try PersistenceController.shared.container.viewContext.save()
            AppLogger.info("✅ [PROFILE] Saved weight: \(weightValue), height: \(heightValue), age: \(ageValue)", category: .nutrition)
            showingProfileSetup = false
        } catch {
            AppLogger.error("❌ [PROFILE] Error saving: \(error)", category: .nutrition)
        }
    }
}

struct ProfileInputField: View {
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

struct NutritionProgressCard: View {
    let title: String
    let current: Int
    let goal: Int
    let unit: String
    let color: Color
    let colorScheme: ColorScheme
    
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
                .fill(colorScheme == .dark ? color.opacity(0.15) : color.opacity(0.08))
        )
    }
}

struct MealEntryRow: View {
    let entry: MealEntryData
    let colorScheme: ColorScheme
    let onDelete: () -> Void
    
    @StateObject private var foodService = USDAFoodService.shared
    @State private var isFavorite: Bool = false
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.foodName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("\(entry.displayQuantity) \(entry.unit)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(entry.calories) cal")
                    .font(.caption)
                    .fontWeight(.medium)
                
                Text("\(entry.protein)p • \(entry.carbs)c • \(entry.fat)f")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            // Favorite star button. Allow ANY non-zero fdcId — OFF rows
            // have NEGATIVE bigint ids (synthetic from barcode), and we want
            // them favoritable too. The pre-2026-04-30 `> 0` check silently
            // hid the star on every barcode-scanned product.
            if entry.fdcId != 0 {
                Button(action: toggleFavorite) {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.ds_bodyRegular)
                        .foregroundColor(isFavorite ? .yellow : .gray)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            Button(action: onDelete) {
                Image(systemName: "minus.circle.fill")
                    .foregroundColor(.red)
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(colorScheme == .dark ? Color(white: 0.18) : Color(.systemBackground))
        .cornerRadius(CornerRadius.sm)
        .onAppear {
            // Check if this food is already favorited (USDA positive OR OFF negative).
            if entry.fdcId != 0 {
                isFavorite = foodService.isFavorite(foodItemId: entry.fdcId)
            }
        }
    }
    
    private func toggleFavorite() {
        // Accept negative OFF synthetic ids — see fdcId comment above.
        guard entry.fdcId != 0 else { return }
        
        Task {
            await foodService.toggleFavorite(fdcId: entry.fdcId, foodItemId: entry.fdcId)
            await MainActor.run {
                isFavorite.toggle()
            }
        }
    }
}

// MARK: - Data Models

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

struct NutritionGoals {
    let calories: Int
    let protein: Int
    let carbs: Int
    let fat: Int
}

// Note: MealEntry is now handled by Core Data and MealEntryData struct

// Using FoodEntry from ContentView.swift - duplicate removed
// FoodEntry now includes fdcId and foodItemId for cloud tracking

// MARK: - Legacy Food Item (kept for compatibility)

struct FoodItem {
    let name: String
    let caloriesPerUnit: Int
    let proteinPerUnit: Int
    let carbsPerUnit: Int
    let fatPerUnit: Int
    let unit: String
}

// MARK: - Saved Meal Card
struct SavedMealCard: View {
    let meal: SavedMeal
    let onTap: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                // Image
                if let imageURL = meal.imageURL, let url = URL(string: imageURL) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        case .failure, .empty:
                            mealPlaceholder
                        @unknown default:
                            mealPlaceholder
                        }
                    }
                    .frame(width: 140, height: 100)
                    .clipped()
                    .cornerRadius(10)
                } else {
                    mealPlaceholder
                        .frame(width: 140, height: 100)
                        .cornerRadius(10)
                }
                
                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(meal.name)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    
                    HStack(spacing: 4) {
                        Text("\(meal.calories) cal")
                            .font(.caption2)
                            .foregroundColor(.orange)
                        
                        Text("•")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        Text("\(meal.protein)g protein")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                    
                    // Source badge
                    HStack(spacing: 4) {
                        Image(systemName: meal.source == .urlImport ? "link" : "book")
                            .font(.system(size: 8))
                        Text(meal.source == .urlImport ? "Imported" : "Recipe")
                            .font(.system(size: 9))
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(colorScheme == .dark ? Color(white: 0.2) : Color(white: 0.92))
                    )
                }
                .frame(width: 140, alignment: .leading)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.98))
                    .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var mealPlaceholder: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.orange.opacity(0.2), .red.opacity(0.1)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Image(systemName: "fork.knife")
                    .font(.title2)
                    .foregroundColor(.orange.opacity(0.5))
            )
    }
}

// MARK: - Saved Meal Detail View
struct SavedMealDetailView: View {
    let meal: SavedMeal
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var userManager: UserManager
    @ObservedObject private var savedMealsService = SavedMealsService.shared
    
    @State private var showingMealPicker = false
    @State private var portionServings: Int = 1
    @State private var showingAddedToList = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                (colorScheme == .dark ? Color.black : Color(white: 0.95))
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 0) {
                        // Hero Image
                        if let imageURL = meal.imageURL, let url = URL(string: imageURL) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(height: 220)
                                        .clipped()
                                case .failure, .empty:
                                    mealPlaceholder
                                @unknown default:
                                    mealPlaceholder
                                }
                            }
                        } else {
                            mealPlaceholder
                        }
                        
                        // Content
                        VStack(spacing: 20) {
                            // Title & Source
                            VStack(alignment: .leading, spacing: 8) {
                                Text(meal.name)
                                    .font(.title2)
                                    .fontWeight(.bold)
                                
                                HStack(spacing: 16) {
                                    if let source = meal.sourceName {
                                        HStack(spacing: 4) {
                                            Image(systemName: "link")
                                                .font(.caption)
                                            Text("from \(source)")
                                                .font(.caption)
                                        }
                                        .foregroundColor(.secondary)
                                    }
                                    
                                    if let time = meal.readyInMinutes {
                                        HStack(spacing: 4) {
                                            Image(systemName: "clock")
                                                .font(.caption)
                                            Text("\(time) min")
                                                .font(.caption)
                                        }
                                        .foregroundColor(.secondary)
                                    }
                                    
                                    HStack(spacing: 4) {
                                        Image(systemName: "person.2")
                                            .font(.caption)
                                        Text("\(meal.servings) servings")
                                            .font(.caption)
                                    }
                                    .foregroundColor(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 16)
                            
                            // Health Score (if available)
                            if let healthScore = meal.healthScore {
                                healthScoreCard(score: healthScore)
                            }
                            
                            // Diet Tags
                            dietTagsSection
                            
                            // Nutrition
                            nutritionCard
                            
                            // Action Buttons
                            actionButtons
                            
                            // Ingredients
                            ingredientsSection
                            
                            // Instructions
                            if let instructions = meal.instructions, !instructions.isEmpty {
                                instructionsSection(instructions)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                    }
                }
                
                // Toast
                if showingAddedToList {
                    addedToListToast
                }
            }
            .navigationTitle("Saved Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        savedMealsService.removeSavedMeal(id: meal.id)
                        dismiss()
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                }
            }
            .sheet(isPresented: $showingMealPicker) {
                SavedMealPickerSheet(
                    meal: meal,
                    portionServings: $portionServings,
                    onAddToMeal: { mealType in
                        addToMeal(mealType)
                        showingMealPicker = false
                    }
                )
            }
        }
    }
    
    private var mealPlaceholder: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.orange.opacity(0.3), .red.opacity(0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(height: 220)
            .overlay(
                Image(systemName: "fork.knife")
                    .font(.system(size: 50))
                    .foregroundColor(.white.opacity(0.5))
            )
    }
    
    private func healthScoreCard(score: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "heart.fill")
                    .foregroundColor(.pink)
                
                Text("Health Score")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text("\(Int(score))/100")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(score >= 70 ? .green : (score >= 40 ? .orange : .red))
            }
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 8)
                    
                    RoundedRectangle(cornerRadius: 6)
                        .fill(score >= 70 ? Color.green : (score >= 40 ? Color.orange : Color.red))
                        .frame(width: geo.size.width * CGFloat(score / 100), height: 8)
                }
            }
            .frame(height: 8)
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(colorScheme == .dark ? Color.cardBackground : Color.white)
        )
    }
    
    @ViewBuilder
    private var dietTagsSection: some View {
        let tags = getDietTags()
        if !tags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.green)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(Color.green.opacity(0.15))
                            )
                    }
                }
            }
        }
    }
    
    private func getDietTags() -> [String] {
        var tags: [String] = []
        if meal.isVeryHealthy == true { tags.append("Healthy") }
        if meal.isVegetarian == true { tags.append("Vegetarian") }
        if meal.isVegan == true { tags.append("Vegan") }
        if meal.isGlutenFree == true { tags.append("Gluten-Free") }
        if meal.isDairyFree == true { tags.append("Dairy-Free") }
        return tags
    }
    
    private var nutritionCard: some View {
        VStack(spacing: 16) {
            Text("Nutrition per Serving")
                .font(.headline)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 12) {
                NutritionCircleSmall(
                    value: meal.calories / max(meal.servings, 1),
                    unit: "",
                    label: "Calories",
                    color: .orange,
                    icon: "flame.fill"
                )
                
                NutritionCircleSmall(
                    value: meal.protein / max(meal.servings, 1),
                    unit: "g",
                    label: "Protein",
                    color: .blue,
                    icon: "p.circle.fill"
                )
                
                NutritionCircleSmall(
                    value: meal.carbs / max(meal.servings, 1),
                    unit: "g",
                    label: "Carbs",
                    color: .green,
                    icon: "c.circle.fill"
                )
                
                NutritionCircleSmall(
                    value: meal.fat / max(meal.servings, 1),
                    unit: "g",
                    label: "Fat",
                    color: .purple,
                    icon: "f.circle.fill"
                )
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .fill(colorScheme == .dark ? Color.cardBackground : .white)
                .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)
        )
    }
    
    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Add to Meal Button
            Button {
                portionServings = 1
                showingMealPicker = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                    
                    Text("Add to Meal")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.subheadline)
                        .opacity(0.7)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, Spacing.md)
                .background(
                    LinearGradient(
                        colors: [Color.green, Color.mint],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(CornerRadius.lg)
                .shadow(color: .green.opacity(0.4), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Add to Shopping List Button
            if !meal.ingredients.isEmpty {
                Button {
                    addIngredientsToShoppingList()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "cart.fill.badge.plus")
                            .font(.title3)
                        
                        Text("Add to Shopping List")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        Spacer()
                        
                        Text("\(meal.ingredients.count)")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .padding(.horizontal, Spacing.xs)
                            .padding(.vertical, Spacing.xxs)
                            .background(Color.white.opacity(0.2))
                            .cornerRadius(CornerRadius.sm)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, Spacing.md)
                    .background(
                        LinearGradient(
                            colors: [Color.purple, Color.pink],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(CornerRadius.lg)
                    .shadow(color: .purple.opacity(0.4), radius: 8, x: 0, y: 4)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
    
    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Ingredients")
                    .font(.title3)
                    .fontWeight(.bold)
                
                Spacer()
                
                Text("\(meal.ingredients.count) items")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, Spacing.xxs)
                    .background(
                        Capsule()
                            .fill(Color.purple.opacity(0.1))
                    )
            }
            
            if !meal.ingredients.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(meal.ingredients.enumerated()), id: \.element.id) { index, ingredient in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Color.purple.opacity(0.1))
                                .frame(width: 36, height: 36)
                                .overlay(
                                    Image(systemName: "leaf.fill")
                                        .font(.caption)
                                        .foregroundColor(.purple)
                                )
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ingredient.name.capitalized)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                
                                Text(ingredient.original)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            
                            Spacer()
                            
                            if ingredient.amount > 0 {
                                Text("\(formatAmount(ingredient.amount)) \(ingredient.unit ?? "")")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                        
                        if index < meal.ingredients.count - 1 {
                            Divider()
                                .padding(.leading, 64)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(colorScheme == .dark ? Color.cardBackground : .white)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
            } else {
                Text("No ingredients available")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            }
        }
    }
    
    private func formatAmount(_ amount: Double) -> String {
        if amount == amount.rounded() {
            return "\(Int(amount))"
        }
        return String(format: "%.1f", amount)
    }
    
    private func instructionsSection(_ instructions: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Instructions")
                .font(.title3)
                .fontWeight(.bold)
            
            let cleanedInstructions = instructions
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "&nbsp;", with: " ")
                .replacingOccurrences(of: "&amp;", with: "&")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            Text(cleanedInstructions)
                .font(.body)
                .foregroundColor(.secondary)
                .lineSpacing(6)
                .padding(Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(colorScheme == .dark ? Color.cardBackground : Color(white: 0.98))
                )
        }
    }
    
    private var addedToListToast: some View {
        VStack {
            Spacer()
            
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.green)
                
                Text("Added to Shopping List")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Spacer()
            }
            .padding(Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .fill(colorScheme == .dark ? Color(white: 0.15) : .white)
                    .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 4)
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .zIndex(100)
    }
    
    private func addIngredientsToShoppingList() {
        let shoppingItems = meal.ingredients.map { ingredient in
            ShoppingListItem(
                name: ingredient.name,
                amount: ingredient.amount,
                unit: ingredient.unit ?? "",
                aisle: ingredient.aisle,
                fromRecipe: meal.name
            )
        }
        
        savedMealsService.addToShoppingList(ingredients: shoppingItems)
        HapticManager.success()
        
        withAnimation(.spring(response: 0.4)) {
            showingAddedToList = true
        }
        
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                showingAddedToList = false
            }
        }
    }
    
    private func addToMeal(_ mealType: MealType) {
        guard let user = userManager.currentUser else {
            AppLogger.error("❌ [SAVED MEAL] Cannot add to meal - no user", category: .nutrition)
            return
        }
        
        let caloriesPerServing = meal.calories / max(meal.servings, 1)
        let proteinPerServing = meal.protein / max(meal.servings, 1)
        let carbsPerServing = meal.carbs / max(meal.servings, 1)
        let fatPerServing = meal.fat / max(meal.servings, 1)
        
        let foodEntry = FoodEntry(
            name: meal.name,
            quantity: Double(portionServings),
            unit: portionServings == 1 ? "serving" : "servings",
            calories: caloriesPerServing * portionServings,
            protein: proteinPerServing * portionServings,
            carbs: carbsPerServing * portionServings,
            fat: fatPerServing * portionServings,
            fdcId: nil,
            foodItemId: nil,
            source: "manual"
        )
        
        MealService.shared.addMealEntry(foodEntry, mealType: mealType, user: user)
        HapticManager.success()
        
        AppLogger.info("✅ [SAVED MEAL] Added '\(meal.name)' to \(mealType.displayName)", category: .nutrition)
    }
}

// MARK: - Saved Meal Picker Sheet
struct SavedMealPickerSheet: View {
    let meal: SavedMeal
    @Binding var portionServings: Int
    let onAddToMeal: (MealType) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedMealType: MealType = .lunch
    
    private var caloriesPerServing: Int {
        meal.calories / max(meal.servings, 1)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                (colorScheme == .dark ? Color.black : Color(white: 0.95))
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Recipe info
                        VStack(spacing: 12) {
                            Text(meal.name)
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.center)
                            
                            Text("Recipe makes \(meal.servings) servings")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 8)
                        
                        Divider()
                        
                        // Portion selector
                        VStack(alignment: .leading, spacing: 12) {
                            Text("How many servings?")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            HStack {
                                Spacer()
                                
                                HStack(spacing: 20) {
                                    Button {
                                        if portionServings > 1 {
                                            HapticManager.selectionChanged()
                                            portionServings -= 1
                                        }
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .font(.system(size: 36))
                                            .foregroundColor(portionServings > 1 ? .green : .gray)
                                    }
                                    .disabled(portionServings <= 1)
                                    
                                    VStack(spacing: 4) {
                                        Text("\(portionServings)")
                                            .font(.system(size: 44, weight: .bold))
                                            .foregroundColor(.primary)
                                        
                                        Text(portionServings == 1 ? "serving" : "servings")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .frame(minWidth: 100)
                                    
                                    Button {
                                        if portionServings < meal.servings {
                                            HapticManager.selectionChanged()
                                            portionServings += 1
                                        }
                                    } label: {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.system(size: 36))
                                            .foregroundColor(portionServings < meal.servings ? .green : .gray)
                                    }
                                    .disabled(portionServings >= meal.servings)
                                }
                                
                                Spacer()
                            }
                            .padding(.vertical, Spacing.sm)
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.lg)
                                .fill(colorScheme == .dark ? Color.cardBackground : Color.white)
                        )
                        
                        // Meal type selector
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Which meal?")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            LazyVGrid(columns: [
                                GridItem(.flexible(), spacing: 10),
                                GridItem(.flexible(), spacing: 10)
                            ], spacing: 10) {
                                ForEach(MealType.allCases, id: \.self) { mealItem in
                                    MealTypeButton(
                                        mealType: mealItem,
                                        isSelected: selectedMealType == mealItem,
                                        action: { selectedMealType = mealItem }
                                    )
                                }
                            }
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.lg)
                                .fill(colorScheme == .dark ? Color.cardBackground : Color.white)
                        )
                        
                        // Add button
                        Button {
                            HapticManager.tap()
                            onAddToMeal(selectedMealType)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title3)
                                Text("Add to \(selectedMealType.displayName)")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.md)
                            .background(
                                LinearGradient(
                                    colors: [.green, .mint],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(14)
                            .shadow(color: .green.opacity(0.4), radius: 8, x: 0, y: 4)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Add to Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    MealPlanView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(UserManager())
}
