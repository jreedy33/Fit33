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
    @State private var nutritionGoals: NutritionGoals?
    
    var body: some View {
        NavigationView {
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
                }
            }
            .toolbarBackground(
                LinearGradient(
                    gradient: Gradient(colors: [Color.green.opacity(0.1), Color.mint.opacity(0.05)]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ), for: .navigationBar
            )
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .onAppear {
            SessionLogManager.shared.logScreen(.mealsTab, metadata: [
                "date": Date().description
            ])
            loadTodaysData()
        }
        .sheet(isPresented: $showingAddFood) {
            FoodSearchView(mealType: selectedMeal) { foodEntry in
                print("Food entry received: \(foodEntry.name)")
                addFoodEntry(foodEntry)
            }
        }
        .onChange(of: showingAddFood) { isShowing in
            print("Sheet presentation state changed: \(isShowing)")
        }
    }
    
    private var needsProfileSetup: Bool {
        guard let user = userManager.currentUser else { return true }
        
        // Check Core Data first, fallback to UserDefaults
        let userWeight = user.weight > 0 ? Int(user.weight) : UserDefaults.standard.integer(forKey: "userWeight")
        let userHeight = user.height > 0 ? Int(user.height) : UserDefaults.standard.integer(forKey: "userHeight")
        
        return userWeight == 0 || userHeight == 0 || nutritionGoals == nil
    }
    
    private var mainNutritionView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Nutrition Goals Overview
                nutritionOverviewCard
                
                // Meal Sections
                ForEach(MealType.allCases, id: \.self) { mealType in
                    mealSection(for: mealType)
                }
            }
            .padding()
        }
        .background(
            LinearGradient(
                gradient: Gradient(colors: colorScheme == .dark
                    ? [Color.green.opacity(0.15), Color.mint.opacity(0.05), Color(red: 0.05, green: 0.05, blue: 0.07)]
                    : [Color.green.opacity(0.1), Color.mint.opacity(0.05), Color.white]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(.all)
        )
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
                
                NutritionProgressCard(
                    title: "Protein",
                    current: currentProtein,
                    goal: nutritionGoals?.protein ?? 150,
                    unit: "g",
                    color: .blue,
                    colorScheme: colorScheme
                )
                
                NutritionProgressCard(
                    title: "Carbs",
                    current: currentCarbs,
                    goal: nutritionGoals?.carbs ?? 250,
                    unit: "g",
                    color: .orange,
                    colorScheme: colorScheme
                )
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
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
    
    private func mealSection(for mealType: MealType) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(mealType.displayName)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button(action: {
                    print("Add food button tapped for \(mealType.displayName)")
                    selectedMeal = mealType
                    showingAddFood = true
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.green)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
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
                        RoundedRectangle(cornerRadius: 12)
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
        .padding(16)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16)
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
                RoundedRectangle(cornerRadius: 16)
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
        print("🍽️ [MEAL PLAN] addFoodEntry called for: \(entry.name)")
        print("🍽️ [MEAL PLAN] Meal type: \(selectedMeal)")
        print("🍽️ [MEAL PLAN] FDC ID: \(entry.fdcId ?? -1)")
        
        guard let user = userManager.currentUser else {
            print("❌ [MEAL PLAN] No current user found!")
            return
        }
        
        print("✅ [MEAL PLAN] User found: \(user.email ?? "no email")")
        print("🔄 [MEAL PLAN] Calling mealService.addMealEntry...")
        mealService.addMealEntry(entry, mealType: selectedMeal, user: user)
        print("✅ [MEAL PLAN] addMealEntry call completed")
    }
    
    private func clearAllMeals() {
        print("🗑️ [MEAL PLAN] Clearing ALL meal entries from database")
        mealService.clearAllMeals()
        print("✅ [MEAL PLAN] All meals cleared, reloading...")
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
            print("✅ [PROFILE] Saved weight: \(weightValue), height: \(heightValue), age: \(ageValue)")
            showingProfileSetup = false
        } catch {
            print("❌ [PROFILE] Error saving: \(error)")
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
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
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
            
            // Favorite star button
            if entry.fdcId > 0 {
                Button(action: toggleFavorite) {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.system(size: 16))
                        .foregroundColor(isFavorite ? .yellow : .gray)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            Button(action: onDelete) {
                Image(systemName: "minus.circle.fill")
                    .foregroundColor(.red)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(colorScheme == .dark ? Color(white: 0.18) : Color(.systemBackground))
        .cornerRadius(8)
        .onAppear {
            // Check if this food is already favorited
            if entry.fdcId > 0 {
                isFavorite = foodService.isFavorite(foodItemId: entry.fdcId)
            }
        }
    }
    
    private func toggleFavorite() {
        guard entry.fdcId > 0 else { return }
        
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

#Preview {
    MealPlanView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(UserManager())
}
