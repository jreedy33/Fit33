//
//  SmartMealPlannerView.swift
//  Fit33
//
//  Smart Meal Planner — daily/weekly meal planning with personalized suggestions
//  based on user food history, nutrition goals, and preferences.
//  Each day is clearly separated with tappable meals showing ingredients & instructions.
//

import SwiftUI

// MARK: - Smart Meal Planner View

struct SmartMealPlannerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var userManager: UserManager
    
    @StateObject private var advancedService = SpoonacularAdvancedService.shared
    @StateObject private var preferenceService = RecipePreferenceService.shared
    @StateObject private var mealService = MealService.shared
    
    // Plan state
    @State private var weekPlan: [DayPlan] = []
    @State private var selectedDayIndex = 0
    @State private var isGenerating = false
    @State private var hasGenerated = false
    @State private var showingMealDetail: PlanMeal?
    
    // Configuration
    @State private var targetCalories: Int = 2000
    @State private var selectedDiet: DietFilter? = nil
    @State private var planDays: Int = 7
    @State private var showingConfig = false
    
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Animated orb background (consistent with Meals screens)
                AnimatedOrbBackground.meals(colorScheme: colorScheme)
                    .ignoresSafeArea(.all, edges: .all)
                
                if !hasGenerated {
                    setupView
                } else {
                    planView
                }
            }
            .navigationTitle("Meal Planner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
                
                if hasGenerated {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            Button(action: { showingConfig = true }) {
                                Label("Adjust Goals", systemImage: "slider.horizontal.3")
                            }
                            Button(action: { regeneratePlan() }) {
                                Label("Regenerate Plan", systemImage: "arrow.clockwise")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .sheet(item: $showingMealDetail) { meal in
                PlanMealDetailSheet(meal: meal)
                    .environmentObject(userManager)
            }
            .sheet(isPresented: $showingConfig) {
                planConfigSheet
            }
            .onAppear {
                calculateDefaultCalories()
            }
        }
    }
    
    // MARK: - Setup View (before generating)
    
    private var setupView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Hero section
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(colors: [.mint, .green], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .frame(width: 80, height: 80)
                            .shadow(color: .mint.opacity(0.4), radius: 12, x: 0, y: 6)
                        
                        Image(systemName: "calendar.badge.plus")
                            .font(.ds_heading1)
                            .foregroundColor(.white)
                    }
                    
                    Text("Smart Meal Planner")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Plan your week with personalized meals\ntailored to your goals and food preferences")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 20)
                
                // Personalization callout
                if !preferenceService.getLikedIngredients().isEmpty {
                    personalizationBadge
                }
                
                // Configuration cards
                VStack(spacing: 14) {
                    // Calorie target
                    configCard(
                        icon: "flame.fill",
                        iconColor: .orange,
                        title: "Daily Calories",
                        value: "\(targetCalories) cal"
                    ) {
                        HStack {
                            Slider(value: Binding(
                                get: { Double(targetCalories) },
                                set: { targetCalories = Int($0) }
                            ), in: 1200...4000, step: 100)
                            .tint(.orange)
                        }
                    }
                    
                    // Diet filter
                    configCard(
                        icon: "leaf.fill",
                        iconColor: .green,
                        title: "Diet",
                        value: selectedDiet?.displayName ?? "No Filter"
                    ) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                // "No Filter" option
                                Button(action: { selectedDiet = nil }) {
                                    Text("No Filter")
                                        .font(.caption)
                                        .fontWeight(selectedDiet == nil ? .bold : .medium)
                                        .foregroundColor(selectedDiet == nil ? .white : .primary)
                                        .padding(.horizontal, Spacing.sm)
                                        .padding(.vertical, 7)
                                        .background(
                                            Capsule()
                                                .fill(selectedDiet == nil
                                                    ? AnyShapeStyle(LinearGradient(colors: [.green, .mint], startPoint: .leading, endPoint: .trailing))
                                                    : AnyShapeStyle(colorScheme == .dark ? Color(white: 0.2) : Color(white: 0.92)))
                                        )
                                }
                                .buttonStyle(.plain)
                                
                                ForEach(DietFilter.allCases, id: \.self) { diet in
                                    Button(action: { selectedDiet = diet }) {
                                        Text(diet.displayName)
                                            .font(.caption)
                                            .fontWeight(selectedDiet == diet ? .bold : .medium)
                                            .foregroundColor(selectedDiet == diet ? .white : .primary)
                                            .padding(.horizontal, Spacing.sm)
                                            .padding(.vertical, 7)
                                            .background(
                                                Capsule()
                                                    .fill(selectedDiet == diet
                                                        ? AnyShapeStyle(LinearGradient(colors: [.green, .mint], startPoint: .leading, endPoint: .trailing))
                                                        : AnyShapeStyle(colorScheme == .dark ? Color(white: 0.2) : Color(white: 0.92)))
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    
                    // Days
                    configCard(
                        icon: "calendar",
                        iconColor: .blue,
                        title: "Plan Length",
                        value: "\(planDays) days"
                    ) {
                        HStack(spacing: 10) {
                            ForEach([1, 3, 5, 7], id: \.self) { days in
                                Button(action: { planDays = days }) {
                                    Text(days == 1 ? "Today" : "\(days)d")
                                        .font(.caption)
                                        .fontWeight(planDays == days ? .bold : .medium)
                                        .foregroundColor(planDays == days ? .white : .primary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, Spacing.xs)
                                        .background(
                                            RoundedRectangle(cornerRadius: CornerRadius.sm)
                                                .fill(planDays == days
                                                    ? AnyShapeStyle(LinearGradient(colors: [.blue, .cyan], startPoint: .leading, endPoint: .trailing))
                                                    : AnyShapeStyle(colorScheme == .dark ? Color(white: 0.2) : Color(white: 0.92)))
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                
                // Generate button
                Button(action: { Task { await generatePlan() } }) {
                    HStack(spacing: 10) {
                        if isGenerating {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: "sparkles")
                                .font(.ds_heading3)
                        }
                        
                        Text(isGenerating ? "Creating Your Plan..." : "Generate Meal Plan")
                            .font(.headline)
                            .fontWeight(.bold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.md)
                    .background(
                        LinearGradient(colors: [.mint, .green], startPoint: .leading, endPoint: .trailing)
                    )
                    .cornerRadius(CornerRadius.lg)
                    .shadow(color: .mint.opacity(0.4), radius: 12, x: 0, y: 6)
                }
                .disabled(isGenerating)
                .opacity(isGenerating ? 0.7 : 1)
                .padding(.top, 8)
            }
            .padding(20)
        }
    }
    
    // MARK: - Generated Plan View
    
    private var planView: some View {
        VStack(spacing: 0) {
            // Day selector tabs
            dayTabSelector
            
            // Day content
            ScrollView {
                if selectedDayIndex < weekPlan.count {
                    dayContent(weekPlan[selectedDayIndex])
                }
            }
        }
    }
    
    // MARK: - Day Tab Selector
    
    private var dayTabSelector: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(weekPlan.enumerated()), id: \.offset) { index, day in
                        Button(action: {
                            withAnimation(.spring(response: 0.3)) { selectedDayIndex = index }
                        }) {
                            VStack(spacing: 4) {
                                Text(day.dayLabel)
                                    .font(.ds_caption)
                                    .foregroundColor(selectedDayIndex == index ? .white.opacity(0.8) : .secondary)
                                
                                Text(day.dateLabel)
                                    .font(.ds_bodyRegular).fontWeight(.bold).fontDesign(.rounded)
                                    .foregroundColor(selectedDayIndex == index ? .white : .primary)
                                
                                // Calorie indicator dot
                                Circle()
                                    .fill(selectedDayIndex == index ? Color.white : Color.clear)
                                    .frame(width: 4, height: 4)
                            }
                            .frame(width: 52, height: 64)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(selectedDayIndex == index
                                        ? AnyShapeStyle(LinearGradient(colors: [.mint, .green], startPoint: .top, endPoint: .bottom))
                                        : AnyShapeStyle(Color.cardBackground))
                            )
                            .shadow(color: selectedDayIndex == index ? Color.mint.opacity(0.3) : .clear, radius: 6, x: 0, y: 3)
                        }
                        .buttonStyle(.plain)
                        .id(index)
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
            }
            .onChange(of: selectedDayIndex) { _, newIndex in
                withAnimation { proxy.scrollTo(newIndex, anchor: .center) }
            }
        }
        .background(
            colorScheme == .dark ? Color(white: 0.08) : Color(white: 0.97)
        )
    }
    
    // MARK: - Day Content
    
    private func dayContent(_ day: DayPlan) -> some View {
        VStack(spacing: 16) {
            // Day nutrition summary
            dayNutritionHeader(day)
            
            // Meals
            ForEach(day.meals) { meal in
                PlanMealCard(meal: meal, colorScheme: colorScheme) {
                    showingMealDetail = meal
                }
            }
            
            // Swap tip
            HStack(spacing: 8) {
                Image(systemName: "lightbulb.fill")
                    .font(.caption)
                    .foregroundColor(.yellow)
                Text("Tap any meal for full recipe, ingredients & instructions")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 4)
            .padding(.bottom, 32)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, 16)
    }
    
    // MARK: - Day Nutrition Header
    
    private func dayNutritionHeader(_ day: DayPlan) -> some View {
        HStack(spacing: 0) {
            macroRing(label: "Cal", value: day.totalCalories, goal: targetCalories, color: .orange, unit: "")
            Spacer()
            macroRing(label: "Protein", value: day.totalProtein, goal: Int(Double(targetCalories) * 0.3 / 4), color: .blue, unit: "g")
            Spacer()
            macroRing(label: "Carbs", value: day.totalCarbs, goal: Int(Double(targetCalories) * 0.4 / 4), color: .green, unit: "g")
            Spacer()
            macroRing(label: "Fat", value: day.totalFat, goal: Int(Double(targetCalories) * 0.3 / 9), color: .purple, unit: "g")
        }
        .padding(Spacing.md)
        .adaptiveSleekCard(cornerRadius: 16, accentColor: .green)
    }
    
    private func macroRing(label: String, value: Int, goal: Int, color: Color, unit: String) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.2), lineWidth: 4)
                    .frame(width: 48, height: 48)
                
                Circle()
                    .trim(from: 0, to: min(1.0, Double(value) / max(Double(goal), 1)))
                    .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 48, height: 48)
                    .rotationEffect(.degrees(-90))
                
                Text("\(value)\(unit)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            }
            
            Text(label)
                .font(.ds_caption)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Config Card Helper
    
    private func configCard<Content: View>(
        icon: String, iconColor: Color, title: String, value: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.ds_labelLarge)
                    .foregroundColor(iconColor)
                    .frame(width: 32, height: 32)
                    .background(iconColor.opacity(0.15))
                    .cornerRadius(CornerRadius.sm)
                
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(iconColor)
            }
            
            content()
        }
        .padding(14)
        .adaptiveSleekCard(cornerRadius: 14, accentColor: .green)
    }
    
    // MARK: - Personalization Badge
    
    private var personalizationBadge: some View {
        HStack(spacing: 10) {
            Image(systemName: "brain.head.profile")
                .font(.ds_heading3)
                .foregroundColor(.purple)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Personalized for You")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.purple)
                
                let liked = preferenceService.getLikedIngredients()
                let topFoods = FoodDatabaseService.shared.frequentFoods.prefix(3).map(\.name)
                let context = !topFoods.isEmpty ? topFoods.joined(separator: ", ") : liked.prefix(3).joined(separator: ", ")
                
                Text("Based on your love of \(context)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
        }
        .padding(Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .fill(Color.purple.opacity(colorScheme == .dark ? 0.1 : 0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.md)
                        .stroke(Color.purple.opacity(0.2), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Config Sheet
    
    private var planConfigSheet: some View {
        NavigationStack {
            List {
                Section("Calories") {
                    Stepper("\(targetCalories) cal/day", value: $targetCalories, in: 1200...4000, step: 100)
                }
                Section("Diet") {
                    Picker("Diet", selection: $selectedDiet) {
                        Text("No Filter").tag(nil as DietFilter?)
                        ForEach(DietFilter.allCases, id: \.self) { diet in
                            Text(diet.displayName).tag(diet as DietFilter?)
                        }
                    }
                }
            }
            .navigationTitle("Plan Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingConfig = false }
                }
            }
        }
        .presentationDetents([.medium])
    }
    
    // MARK: - Actions
    
    private func calculateDefaultCalories() {
        guard let user = userManager.currentUser else { return }
        let weight = user.weight > 0 ? Int(user.weight) : UserDefaults.standard.integer(forKey: "userWeight")
        let height = user.height > 0 ? Int(user.height) : UserDefaults.standard.integer(forKey: "userHeight")
        
        guard weight > 0, height > 0 else { return }
        
        let bmr = (10.0 * Double(weight) * 0.453592) + (6.25 * Double(height) * 2.54) - (5.0 * Double(user.age)) + 5.0
        var tdee = bmr * 1.55
        
        switch user.fitnessGoal?.lowercased() {
        case "lose weight", "lean out": tdee -= 500
        case "gain weight", "gain muscle", "build muscle": tdee += 300
        default: break
        }
        
        targetCalories = max(1200, Int(tdee / 100) * 100)
    }
    
    private func generatePlan() async {
        isGenerating = true
        HapticManager.impact(.medium)
        
        var allDays: [DayPlan] = []
        let calendar = Calendar.current
        
        // Generate each day's plan
        for dayOffset in 0..<planDays {
            let date = calendar.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
            
            let plan = await advancedService.generateMealPlan(
                timeFrame: .day,
                targetCalories: targetCalories,
                diet: selectedDiet?.apiValue,
                exclude: preferenceService.getDislikedIngredients().isEmpty ? nil : preferenceService.getDislikedIngredients()
            )
            
            if let dayResponse = plan?.days?.first {
                let meals = dayResponse.meals.enumerated().map { index, meal in
                    PlanMeal(
                        id: meal.id,
                        title: meal.title,
                        mealSlot: MealSlot.from(index: index),
                        readyInMinutes: meal.readyInMinutes,
                        servings: meal.servings,
                        imageURL: meal.imageURL,
                        sourceUrl: meal.sourceUrl,
                        calories: Int(dayResponse.nutrients.calories) / max(dayResponse.meals.count, 1),
                        protein: Int(dayResponse.nutrients.protein) / max(dayResponse.meals.count, 1),
                        carbs: Int(dayResponse.nutrients.carbohydrates) / max(dayResponse.meals.count, 1),
                        fat: Int(dayResponse.nutrients.fat) / max(dayResponse.meals.count, 1)
                    )
                }
                
                allDays.append(DayPlan(
                    date: date,
                    meals: meals,
                    totalCalories: Int(dayResponse.nutrients.calories),
                    totalProtein: Int(dayResponse.nutrients.protein),
                    totalCarbs: Int(dayResponse.nutrients.carbohydrates),
                    totalFat: Int(dayResponse.nutrients.fat)
                ))
            }
        }
        
        weekPlan = allDays
        hasGenerated = !allDays.isEmpty
        isGenerating = false
        
        if hasGenerated {
            HapticManager.notification(.success)
        }
    }
    
    private func regeneratePlan() {
        hasGenerated = false
        weekPlan = []
        selectedDayIndex = 0
        Task { await generatePlan() }
    }
}


// MARK: - Plan Meal Card

struct PlanMealCard: View {
    let meal: PlanMeal
    let colorScheme: ColorScheme
    let onTap: () -> Void
    
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Meal slot icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: meal.mealSlot.gradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                        .shadow(color: meal.mealSlot.gradient[0].opacity(0.3), radius: 6, x: 0, y: 3)
                    
                    Image(systemName: meal.mealSlot.icon)
                        .font(.ds_heading3).fontWeight(.semibold)
                        .foregroundColor(.white)
                }
                
                // Meal info
                VStack(alignment: .leading, spacing: 4) {
                    Text(meal.mealSlot.label)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(meal.mealSlot.gradient[0])
                    
                    Text(meal.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    
                    HStack(spacing: 10) {
                        Label("\(meal.calories) cal", systemImage: "flame")
                            .font(.caption)
                            .foregroundColor(.orange)
                        
                        Label("\(meal.protein)g protein", systemImage: "p.circle")
                            .font(.caption)
                            .foregroundColor(.blue)
                        
                        if meal.readyInMinutes > 0 {
                            Label("\(meal.readyInMinutes)m", systemImage: "clock")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                // Recipe image thumbnail
                if let url = meal.imageURL {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Rectangle().fill(Color.gray.opacity(0.15))
                        }
                    }
                    .frame(width: 60, height: 60)
                    .cornerRadius(CornerRadius.md)
                    .clipped()
                }
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(14)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.cardBackground)
                    
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: colorScheme == .dark
                                    ? [Color.white.opacity(0.06), Color.clear]
                                    : [Color.white, Color.white.opacity(0.3)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                }
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.06), radius: 8, x: 0, y: 4)
            )
        }
        .buttonStyle(.plain)
    }
}


// MARK: - Plan Meal Detail Sheet

struct PlanMealDetailSheet: View {
    let meal: PlanMeal
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var userManager: UserManager
    
    @StateObject private var advancedService = SpoonacularAdvancedService.shared
    @State private var recipeDetail: RecipeDetail?
    @State private var isLoading = true
    @State private var addedToMeal = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                (colorScheme == .dark ? Color.black : Color(white: 0.95))
                    .ignoresSafeArea()
                
                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Loading recipe...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            // Hero image
                            heroImage
                            
                            VStack(spacing: 20) {
                                // Title & meta
                                titleSection
                                
                                // Nutrition
                                nutritionRow
                                
                                // Quick add to today's meals
                                addToMealButton
                                
                                // Ingredients
                                if let detail = recipeDetail, let ingredients = detail.extendedIngredients, !ingredients.isEmpty {
                                    ingredientsSection(ingredients)
                                }
                                
                                // Instructions
                                if let detail = recipeDetail, let instructions = detail.instructions, !instructions.isEmpty {
                                    instructionsSection(instructions)
                                } else if let detail = recipeDetail, let steps = detail.analyzedInstructions?.first?.steps, !steps.isEmpty {
                                    stepsSection(steps)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 40)
                        }
                    }
                }
                
                // Added toast
                if addedToMeal {
                    VStack {
                        Spacer()
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Added to today's meals!")
                                .fontWeight(.semibold)
                        }
                        .padding(Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(colorScheme == .dark ? Color(white: 0.15) : .white)
                                .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 4)
                        )
                        .padding(.horizontal, 20)
                        .padding(.bottom, 60)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(100)
                }
            }
            .navigationTitle(meal.mealSlot.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                await loadRecipeDetail()
            }
        }
    }
    
    // MARK: - Hero Image
    
    private var heroImage: some View {
        Group {
            if let url = meal.imageURL {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                            .frame(height: 220)
                            .clipped()
                    } else {
                        placeholderImage
                    }
                }
            } else {
                placeholderImage
            }
        }
    }
    
    private var placeholderImage: some View {
        Rectangle()
            .fill(LinearGradient(colors: meal.mealSlot.gradient.map { $0.opacity(0.3) }, startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(height: 220)
            .overlay(
                Image(systemName: "fork.knife")
                    .font(.system(size: 48))
                    .foregroundColor(.white.opacity(0.5))
            )
    }
    
    // MARK: - Title Section
    
    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(meal.title)
                .font(.title2)
                .fontWeight(.bold)
                .padding(.top, 16)
            
            HStack(spacing: 16) {
                if meal.readyInMinutes > 0 {
                    Label("\(meal.readyInMinutes) min", systemImage: "clock")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if meal.servings > 0 {
                    Label("\(meal.servings) servings", systemImage: "person.2")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                HStack(spacing: 3) {
                    Image(systemName: meal.mealSlot.icon)
                        .font(.caption)
                    Text(meal.mealSlot.label)
                        .font(.caption)
                }
                .foregroundColor(meal.mealSlot.gradient[0])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: - Nutrition Row
    
    private var nutritionRow: some View {
        HStack(spacing: 0) {
            nutritionPill(value: "\(meal.calories)", label: "cal", color: .orange)
            Spacer()
            nutritionPill(value: "\(meal.protein)g", label: "protein", color: .blue)
            Spacer()
            nutritionPill(value: "\(meal.carbs)g", label: "carbs", color: .green)
            Spacer()
            nutritionPill(value: "\(meal.fat)g", label: "fat", color: .purple)
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(colorScheme == .dark ? Color.cardBackground : Color.white)
                .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 3)
        )
    }
    
    private func nutritionPill(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.ds_statSmall)
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Add to Meal Button
    
    private var addToMealButton: some View {
        Button(action: addToTodaysMeals) {
            HStack(spacing: 10) {
                Image(systemName: addedToMeal ? "checkmark.circle.fill" : "plus.circle.fill")
                    .font(.title3)
                Text(addedToMeal ? "Added!" : "Add to Today's \(meal.mealSlot.mealType.displayName)")
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                LinearGradient(
                    colors: addedToMeal ? [.green, .mint] : meal.mealSlot.gradient,
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(14)
            .shadow(color: (addedToMeal ? Color.green : meal.mealSlot.gradient[0]).opacity(0.4), radius: 8, x: 0, y: 4)
        }
        .disabled(addedToMeal)
        .buttonStyle(.plain)
    }
    
    // MARK: - Ingredients
    
    private func ingredientsSection(_ ingredients: [ExtendedIngredient]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Ingredients")
                    .font(.title3)
                    .fontWeight(.bold)
                
                Spacer()
                
                Text("\(ingredients.count) items")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, Spacing.xxs)
                    .background(Capsule().fill(Color.green.opacity(0.1)))
            }
            
            VStack(spacing: 0) {
                ForEach(Array(ingredients.enumerated()), id: \.offset) { index, ingredient in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color.green.opacity(0.1))
                            .frame(width: 32, height: 32)
                            .overlay(
                                Image(systemName: "leaf.fill")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                            )
                        
                        Text(ingredient.original)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                            .lineLimit(2)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    
                    if index < ingredients.count - 1 {
                        Divider().padding(.leading, 58)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(colorScheme == .dark ? Color.cardBackground : .white)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.15), lineWidth: 1))
            )
        }
    }
    
    // MARK: - Instructions (plain text)
    
    private func instructionsSection(_ instructions: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Instructions")
                .font(.title3)
                .fontWeight(.bold)
            
            let cleaned = instructions
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "&nbsp;", with: " ")
                .replacingOccurrences(of: "&amp;", with: "&")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            Text(cleaned)
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
    
    // MARK: - Steps (numbered)
    
    private func stepsSection(_ steps: [InstructionStep]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Instructions")
                .font(.title3)
                .fontWeight(.bold)
            
            VStack(spacing: 0) {
                ForEach(steps, id: \.number) { step in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(step.number)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .frame(width: 26, height: 26)
                            .background(
                                Circle().fill(
                                    LinearGradient(colors: [.mint, .green], startPoint: .topLeading, endPoint: .bottomTrailing)
                                )
                            )
                        
                        Text(step.step)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                            .lineSpacing(4)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    
                    if step.number < (steps.last?.number ?? steps.count) {
                        Divider().padding(.leading, 52)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(colorScheme == .dark ? Color.cardBackground : .white)
            )
        }
    }
    
    // MARK: - Actions
    
    private func loadRecipeDetail() async {
        // Try to fetch full recipe detail from Spoonacular
        let detail = await SpoonacularService.shared.fetchRecipeDetail(recipeId: meal.id)
        await MainActor.run {
            recipeDetail = detail
            isLoading = false
        }
    }
    
    private func addToTodaysMeals() {
        guard let user = userManager.currentUser else { return }
        
        let entry = FoodEntry(
            name: meal.title,
            quantity: 1.0,
            unit: "serving",
            calories: meal.calories,
            protein: meal.protein,
            carbs: meal.carbs,
            fat: meal.fat,
            fdcId: nil,
            foodItemId: nil,
            source: "manual"
        )
        
        MealService.shared.addMealEntry(entry, mealType: meal.mealSlot.mealType, user: user)
        HapticManager.notification(.success)
        
        withAnimation(.spring(response: 0.4)) { addedToMeal = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation { addedToMeal = false }
        }
    }
}


// MARK: - Data Models

struct DayPlan: Identifiable {
    let id = UUID()
    let date: Date
    let meals: [PlanMeal]
    let totalCalories: Int
    let totalProtein: Int
    let totalCarbs: Int
    let totalFat: Int
    
    var dayLabel: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tmrw" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }
    
    var dateLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }
}

struct PlanMeal: Identifiable {
    let id: Int
    let title: String
    let mealSlot: MealSlot
    let readyInMinutes: Int
    let servings: Int
    let imageURL: URL?
    let sourceUrl: String?
    let calories: Int
    let protein: Int
    let carbs: Int
    let fat: Int
}

enum MealSlot: String, CaseIterable {
    case breakfast, lunch, dinner, snack
    
    var label: String {
        switch self {
        case .breakfast: return "Breakfast"
        case .lunch: return "Lunch"
        case .dinner: return "Dinner"
        case .snack: return "Snack"
        }
    }
    
    var icon: String {
        switch self {
        case .breakfast: return "sunrise.fill"
        case .lunch: return "sun.max.fill"
        case .dinner: return "moon.stars.fill"
        case .snack: return "leaf.fill"
        }
    }
    
    var gradient: [Color] {
        switch self {
        case .breakfast: return [.orange, .yellow]
        case .lunch: return [.blue, .cyan]
        case .dinner: return [.indigo, .purple]
        case .snack: return [.green, .mint]
        }
    }
    
    var mealType: MealType {
        switch self {
        case .breakfast: return .breakfast
        case .lunch: return .lunch
        case .dinner: return .dinner
        case .snack: return .snacks
        }
    }
    
    static func from(index: Int) -> MealSlot {
        switch index {
        case 0: return .breakfast
        case 1: return .lunch
        case 2: return .dinner
        default: return .snack
        }
    }
}

// DietFilter enum is defined in RecipeBrowserView.swift — reused here
