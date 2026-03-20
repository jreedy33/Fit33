import SwiftUI

// MARK: - Meals Quick Actions Grid
/// Quick action buttons for meal planning features matching auto/custom workout button style
struct MealsQuickActionsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var showMealPlanGenerator: Bool
    @Binding var showRecipeImport: Bool
    @Binding var showRestaurantSearch: Bool  // Kept for compatibility but not used here
    @Binding var showShoppingList: Bool
    
    private var cardBackgroundGradient: [Color] {
        colorScheme == .dark
            ? [Color(white: 0.14), Color(white: 0.09)]
            : [Color.white, Color.white.opacity(0.95)]
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .padding(.leading, 4)
            
            // 3 tall/skinny tiles in a row
            HStack(spacing: 12) {
                // Meal Plan Generator
                MealQuickActionTile(
                    icon: "calendar.badge.plus",
                    title: "Meal\nPlanner",
                    gradient: [.mint, .green],
                    action: { showMealPlanGenerator = true }
                )
                
                // Import Recipe
                MealQuickActionTile(
                    icon: "link.badge.plus",
                    title: "Import\nRecipe",
                    gradient: [.blue, .cyan],
                    action: { showRecipeImport = true }
                )
                
                // Shopping List
                MealQuickActionTile(
                    icon: "cart.fill",
                    title: "Shopping\nList",
                    gradient: [.purple, .pink],
                    action: { showShoppingList = true }
                )
            }
        }
    }
}

// MARK: - Meal Quick Action Tile (Tall/Skinny style)
struct MealQuickActionTile: View {
    let icon: String
    let title: String
    let gradient: [Color]
    let action: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var cardBackgroundGradient: [Color] {
        colorScheme == .dark
            ? [Color(white: 0.14), Color(white: 0.09)]
            : [Color.white, Color.white.opacity(0.95)]
    }
    
    var body: some View {
        Button(action: {
            HapticManager.impact(.medium)
            action()
        }) {
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: gradient),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 50, height: 50)
                        .shadow(color: gradient[0].opacity(0.5), radius: 8, x: 0, y: 4)
                    
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 140)
            .background(
                ZStack {
                    // Bottom shadow layer (deepest) - color glow
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(gradient[0].opacity(colorScheme == .dark ? 0.15 : 0.08))
                        .offset(y: 8)
                        .blur(radius: 4)
                    
                    // Middle shadow layer
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                        .offset(y: 4)
                    
                    // Main card background with gradient
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: cardBackgroundGradient,
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
                    
                    // Colored accent border
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [gradient[0].opacity(colorScheme == .dark ? 0.4 : 0.3), gradient[1].opacity(colorScheme == .dark ? 0.3 : 0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 12, x: 0, y: 6)
            .shadow(color: gradient[0].opacity(colorScheme == .dark ? 0.2 : 0.12), radius: 20, x: 0, y: 10)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Meal Quick Action Button (matches Auto/Custom Workout style)
struct MealQuickActionButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let gradient: [Color]
    let action: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var cardBackgroundGradient: [Color] {
        colorScheme == .dark
            ? [Color(white: 0.14), Color(white: 0.09)]
            : [Color.white, Color.white.opacity(0.95)]
    }
    
    var body: some View {
        Button(action: {
            HapticManager.impact(.medium)
            action()
        }) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: gradient),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 50, height: 50)
                        .shadow(color: gradient[0].opacity(0.4), radius: 8, x: 0, y: 4)
                    
                    Image(systemName: icon)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                }
                
                VStack(spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 140)
            .background(
                ZStack {
                    // Bottom shadow layer (deepest) - color glow
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(gradient[0].opacity(colorScheme == .dark ? 0.15 : 0.08))
                        .offset(y: 8)
                        .blur(radius: 4)
                    
                    // Middle shadow layer
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                        .offset(y: 4)
                    
                    // Main card background with gradient
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: cardBackgroundGradient,
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
                    
                    // Colored accent border
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [gradient[0].opacity(colorScheme == .dark ? 0.4 : 0.3), gradient[1].opacity(colorScheme == .dark ? 0.3 : 0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 12, x: 0, y: 6)
            .shadow(color: gradient[0].opacity(colorScheme == .dark ? 0.2 : 0.12), radius: 20, x: 0, y: 10)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Legacy Quick Action Tile (kept for compatibility)
struct QuickActionTile: View {
    let icon: String
    let title: String
    let subtitle: String
    let gradient: [Color]
    let action: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            HapticManager.tap()
            action()
        }) {
            HStack(spacing: 12) {
                // Gradient icon circle
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: gradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                        .shadow(color: gradient[0].opacity(0.4), radius: 6, x: 0, y: 3)
                    
                    Image(systemName: icon)
                        .font(.ds_heading3)
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(colorScheme == .dark ? Color.cardBackground : Color(white: 0.97))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(
                                gradient[0].opacity(colorScheme == .dark ? 0.2 : 0.15),
                                lineWidth: 1
                            )
                    )
            )
        }
        .scaleButtonStyle(.standard, withHaptic: true)
    }
}

// MARK: - Meal Plan Generator Sheet
struct MealPlanGeneratorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var userManager: UserManager
    @StateObject private var advancedService = SpoonacularAdvancedService.shared
    
    @State private var targetCalories: Int = 2000
    @State private var selectedDiet: DietOption? = nil
    @State private var timeFrame: MealPlanTimeFrame = .day
    @State private var excludedFoods: String = ""
    @State private var isGenerating = false
    @State private var generatedPlan: GeneratedMealPlan?
    
    enum DietOption: String, CaseIterable {
        case none = "No Restriction"
        case vegetarian = "Vegetarian"
        case vegan = "Vegan"
        case glutenFree = "Gluten Free"
        case ketogenic = "Ketogenic"
        case paleo = "Paleo"
        
        var apiValue: String? {
            switch self {
            case .none: return nil
            default: return rawValue.lowercased().replacingOccurrences(of: " ", with: "-")
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                (colorScheme == .dark ? Color.black : Color(white: 0.95))
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        headerSection
                        
                        // Configuration
                        configurationSection
                        
                        // Generate Button
                        generateButton
                        
                        // Results
                        if let plan = generatedPlan {
                            resultsSection(plan)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Meal Planner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear {
            // Set default calories based on user goals
            if let user = userManager.currentUser {
                let weight = user.weight > 0 ? Int(user.weight) : UserDefaults.standard.integer(forKey: "userWeight")
                let height = user.height > 0 ? Int(user.height) : UserDefaults.standard.integer(forKey: "userHeight")
                if weight > 0 && height > 0 {
                    let bmr = (10.0 * Double(weight)) + (6.25 * Double(height)) - (5.0 * Double(user.age)) + 5.0
                    targetCalories = Int(bmr * 1.55)
                }
            }
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.mint, .green],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 70, height: 70)
                    .shadow(color: .mint.opacity(0.4), radius: 10, x: 0, y: 5)
                
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            Text("AI Meal Planner")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Generate personalized meal plans\nbased on your nutrition goals")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, Spacing.xs)
    }
    
    private var configurationSection: some View {
        VStack(spacing: 16) {
            // Time Frame
            VStack(alignment: .leading, spacing: 8) {
                Text("Plan Duration")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Picker("Time Frame", selection: $timeFrame) {
                    Text("Day").tag(MealPlanTimeFrame.day)
                    Text("Week").tag(MealPlanTimeFrame.week)
                }
                .pickerStyle(SegmentedPickerStyle())
            }
            .padding(Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(colorScheme == .dark ? Color.cardBackground : Color.white)
            )
            
            // Calories
            VStack(alignment: .leading, spacing: 8) {
                Text("Target Calories")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                HStack {
                    Slider(value: Binding(
                        get: { Double(targetCalories) },
                        set: { targetCalories = Int($0) }
                    ), in: 1200...4000, step: 100)
                    .tint(.mint)
                    
                    Text("\(targetCalories)")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.mint)
                        .frame(width: 60)
                }
            }
            .padding(Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(colorScheme == .dark ? Color.cardBackground : Color.white)
            )
            
            // Diet
            VStack(alignment: .leading, spacing: 8) {
                Text("Dietary Preference")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(DietOption.allCases, id: \.self) { diet in
                            DietChip(
                                title: diet.rawValue,
                                isSelected: selectedDiet == diet,
                                action: {
                                    selectedDiet = (selectedDiet == diet) ? nil : diet
                                }
                            )
                        }
                    }
                }
            }
            .padding(Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(colorScheme == .dark ? Color.cardBackground : Color.white)
            )
            
            // Excluded Foods
            VStack(alignment: .leading, spacing: 8) {
                Text("Exclude Foods")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                TextField("e.g., shellfish, peanuts", text: $excludedFoods)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                Text("Comma-separated list of foods to avoid")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(colorScheme == .dark ? Color.cardBackground : Color.white)
            )
        }
    }
    
    private var generateButton: some View {
        Button(action: generateMealPlan) {
            HStack(spacing: 8) {
                if isGenerating {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "sparkles")
                }
                Text(isGenerating ? "Generating..." : "Generate Meal Plan")
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
            .background(
                LinearGradient(
                    colors: [.mint, .green],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(14)
            .shadow(color: .mint.opacity(0.4), radius: 8, x: 0, y: 4)
        }
        .disabled(isGenerating)
    }
    
    private func resultsSection(_ plan: GeneratedMealPlan) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Your Meal Plan")
                    .font(.title3)
                    .fontWeight(.bold)
                
                Spacer()
                
                if let days = plan.days, let first = days.first {
                    Text("\(Int(first.nutrients.calories)) cal")
                        .font(.subheadline)
                        .foregroundColor(.mint)
                        .fontWeight(.semibold)
                }
            }
            
            if let days = plan.days, let dayPlan = days.first {
                ForEach(Array(dayPlan.meals.enumerated()), id: \.element.id) { index, meal in
                    MealPlanMealCard(meal: meal, mealIndex: index)
                }
            } else if let week = plan.week {
                ForEach(week.week.allDays, id: \.0) { dayName, dayPlan in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(dayName)
                            .font(.headline)
                            .foregroundColor(.mint)
                        
                        ForEach(Array(dayPlan.meals.enumerated()), id: \.element.id) { index, meal in
                            MealPlanMealCard(meal: meal, mealIndex: index)
                        }
                    }
                }
            }
        }
    }
    
    private func generateMealPlan() {
        isGenerating = true
        HapticManager.tap()
        
        Task {
            let excluded = excludedFoods.isEmpty ? nil : excludedFoods.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            
            let plan = await advancedService.generateMealPlan(
                timeFrame: timeFrame,
                targetCalories: targetCalories,
                diet: selectedDiet?.apiValue,
                exclude: excluded
            )
            
            await MainActor.run {
                generatedPlan = plan
                isGenerating = false
            }
        }
    }
}

// MARK: - Diet Chip
struct DietChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, Spacing.xs)
                .background(
                    Capsule()
                        .fill(isSelected
                              ? LinearGradient(colors: [.mint, .green], startPoint: .leading, endPoint: .trailing)
                              : LinearGradient(colors: [colorScheme == .dark ? Color(white: 0.18) : Color(white: 0.92)], startPoint: .leading, endPoint: .trailing)
                        )
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Meal Plan Meal Card
struct MealPlanMealCard: View {
    let meal: MealPlanMeal
    let mealIndex: Int
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var mealType: String {
        switch mealIndex {
        case 0: return "Breakfast"
        case 1: return "Lunch"
        case 2: return "Dinner"
        default: return "Snack"
        }
    }
    
    private var mealIcon: String {
        switch mealIndex {
        case 0: return "sunrise.fill"
        case 1: return "sun.max.fill"
        case 2: return "moon.stars.fill"
        default: return "leaf.fill"
        }
    }
    
    private var mealGradient: [Color] {
        switch mealIndex {
        case 0: return [.orange, .yellow]
        case 1: return [.blue, .cyan]
        case 2: return [.indigo, .purple]
        default: return [.green, .mint]
        }
    }
    
    var body: some View {
        HStack(spacing: 14) {
            // Meal type icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: mealGradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                
                Image(systemName: mealIcon)
                    .font(.ds_heading3)
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(mealType)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(meal.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                
                HStack(spacing: 8) {
                    Label("\(meal.readyInMinutes) min", systemImage: "clock")
                    Label("\(meal.servings) serv", systemImage: "person.2")
                }
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
                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
    }
}

// MARK: - Preview
#Preview {
    MealsQuickActionsView(
        showMealPlanGenerator: .constant(false),
        showRecipeImport: .constant(false),
        showRestaurantSearch: .constant(false),
        showShoppingList: .constant(false)
    )
    .padding()
}
