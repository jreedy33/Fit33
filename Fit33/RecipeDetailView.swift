import SwiftUI

// MARK: - Recipe Detail View
/// Full-screen detail view for a recipe with nutrition info, ingredients, and instructions
struct RecipeDetailView: View {
    let recipeId: Int
    let initialRecipe: SpoonacularRecipe?
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var userManager: UserManager
    @StateObject private var spoonacularService = SpoonacularService.shared
    @StateObject private var preferenceService = RecipePreferenceService.shared
    @ObservedObject private var savedMealsService = SavedMealsService.shared
    @State private var recipeDetail: RecipeDetail?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedTab: RecipeTab = .overview
    @State private var servings: Int = 1
    @State private var isFavorite = false
    @State private var isSaved = false
    @State private var showingMealPicker = false
    @State private var showingAddedConfirmation = false
    @State private var showingAddedToList = false
    @State private var addedMealType: MealType?
    @State private var portionServings: Int = 1 // How many servings user actually consumed
    
    enum RecipeTab: String, CaseIterable {
        case overview = "Overview"
        case ingredients = "Ingredients"
        case instructions = "Steps"
    }
    
    var body: some View {
        ZStack {
            // Background
            backgroundGradient
                .ignoresSafeArea()
            
            if isLoading {
                loadingView
            } else if let error = errorMessage {
                errorView(error)
            } else if let detail = recipeDetail {
                recipeContent(detail)
            }
            
            // Success toast
            if showingAddedConfirmation {
                addedConfirmationToast
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    // Favorite star button
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            isFavorite.toggle()
                            saveFavoriteState()
                        }
                    } label: {
                        Image(systemName: isFavorite ? "star.fill" : "star")
                            .font(.body)
                            .foregroundColor(isFavorite ? .yellow : .white)
                    }
                    
                    // Share button
                    if let detail = recipeDetail,
                       let url = URL(string: detail.sourceUrl ?? detail.spoonacularSourceUrl ?? "") {
                        ShareLink(item: url) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.body)
                                .foregroundColor(.white)
                        }
                    }
                }
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .task {
            await loadRecipeDetail()
            loadFavoriteState()
            loadSavedState()
        }
        .sheet(isPresented: $showingMealPicker) {
            if let detail = recipeDetail {
                SmartServingSelectorSheet(
                    recipe: detail,
                    recipeDefaultServings: detail.servings,
                    portionServings: $portionServings,
                    onAddToMeal: { mealType in
                        showingMealPicker = false
                        addToMeal(mealType)
                    }
                )
            }
        }
    }
    
    // MARK: - Recipe Content
    private func recipeContent(_ detail: RecipeDetail) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                // Hero Image — full bleed behind nav bar
                heroImage(detail)
                
                // Content
                VStack(spacing: 20) {
                    // Title & Quick Info
                    titleSection(detail)
                    
                    // Nutrition Card
                    nutritionCard(detail)
                    
                    // Diet Tags
                    if !detail.dietTags.isEmpty {
                        dietTagsSection(detail)
                    }
                    
                    // Add to Meal Button
                    addToMealButton(detail)
                    
                    // Tab Selector
                    tabSelector
                    
                    // Tab Content
                    Group {
                        switch selectedTab {
                        case .overview:
                            overviewSection(detail)
                        case .ingredients:
                            ingredientsSection(detail)
                        case .instructions:
                            instructionsSection(detail)
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: selectedTab)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
    }
    
    // MARK: - Hero Image
    private func heroImage(_ detail: RecipeDetail) -> some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: detail.imageURL) { phase in
                switch phase {
                case .empty:
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [.orange.opacity(0.3), .red.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            ProgressView()
                                .scaleEffect(1.5)
                                .tint(.white)
                        )
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [.orange.opacity(0.4), .red.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            Image(systemName: "photo")
                                .font(.system(size: 50))
                                .foregroundColor(.white.opacity(0.5))
                        )
                @unknown default:
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                }
            }
            .frame(height: 280)
            .clipped()
            
            // Gradient overlay
            LinearGradient(
                colors: [.clear, .clear, .black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
            
            // Quick info badges
            HStack(spacing: 12) {
                // Time
                InfoBadge(
                    icon: "clock.fill",
                    text: detail.formattedTime,
                    color: .blue
                )
                
                // Servings
                InfoBadge(
                    icon: "person.2.fill",
                    text: "\(detail.servings) servings",
                    color: .green
                )
                
                // Difficulty
                InfoBadge(
                    icon: detail.difficulty.icon,
                    text: detail.difficulty.rawValue,
                    color: detail.difficulty.color
                )
            }
            .padding(16)
        }
    }
    
    // MARK: - Title Section
    private func titleSection(_ detail: RecipeDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(detail.title)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            if let source = detail.sourceName {
                HStack(spacing: 4) {
                    Image(systemName: "link")
                        .font(.caption)
                    Text("by \(source)")
                        .font(.caption)
                }
                .foregroundColor(.secondary)
            }
            
            // Health Score
            if let healthScore = detail.healthScore {
                HStack(spacing: 6) {
                    Image(systemName: "heart.fill")
                        .font(.caption)
                        .foregroundColor(.pink)
                    Text("Health Score: \(Int(healthScore))")
                        .font(.caption)
                        .fontWeight(.medium)
                    
                    // Visual indicator
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.2))
                            
                            RoundedRectangle(cornerRadius: 4)
                                .fill(healthScoreColor(healthScore))
                                .frame(width: geo.size.width * CGFloat(healthScore / 100))
                        }
                    }
                    .frame(width: 60, height: 6)
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 16)
    }
    
    // MARK: - Nutrition Card
    private func nutritionCard(_ detail: RecipeDetail) -> some View {
        VStack(spacing: 16) {
            // Header: label + stepper
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(servings == 1 ? "Per Serving" : "For \(servings) Servings")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    Text("Tap ± to adjust")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.45))
                }
                
                Spacer()
                
                // Pill stepper
                HStack(spacing: 4) {
                    Button {
                        if servings > 1 { withAnimation(.spring(response: 0.2)) { servings -= 1 } }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(servings > 1 ? 0.18 : 0.07))
                                .frame(width: 32, height: 32)
                            Image(systemName: "minus")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(servings > 1 ? .white : .white.opacity(0.3))
                        }
                    }
                    .disabled(servings <= 1)
                    
                    Text("\(servings)")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(minWidth: 28)
                        .multilineTextAlignment(.center)
                    
                    Button {
                        if servings < detail.servings { withAnimation(.spring(response: 0.2)) { servings += 1 } }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(servings < detail.servings ? 0.18 : 0.07))
                                .frame(width: 32, height: 32)
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(servings < detail.servings ? .white : .white.opacity(0.3))
                        }
                    }
                    .disabled(servings >= detail.servings)
                }
            }
            
            // Macro tiles
            HStack(spacing: 8) {
                RecipeMacroTile(
                    value: "\(detail.calories * servings)",
                    label: "Calories",
                    unit: "",
                    color: Color(red: 1.0, green: 0.55, blue: 0.1)
                )
                RecipeMacroTile(
                    value: "\(Int(detail.protein * Double(servings)))",
                    label: "Protein",
                    unit: "g",
                    color: Color(red: 0.35, green: 0.6, blue: 1.0)
                )
                RecipeMacroTile(
                    value: "\(Int(detail.carbs * Double(servings)))",
                    label: "Carbs",
                    unit: "g",
                    color: Color(red: 0.25, green: 0.85, blue: 0.5)
                )
                RecipeMacroTile(
                    value: "\(Int(detail.fat * Double(servings)))",
                    label: "Fat",
                    unit: "g",
                    color: Color(red: 0.72, green: 0.42, blue: 1.0)
                )
            }
            
            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 1)
            
            // Secondary nutrients
            HStack(spacing: 0) {
                Spacer()
                VStack(spacing: 3) {
                    Text("\(Int(detail.fiber * Double(servings)))g")
                        .font(.subheadline).fontWeight(.semibold).foregroundColor(.white)
                    Text("Fiber")
                        .font(.caption2).foregroundColor(.white.opacity(0.5))
                }
                Spacer()
                Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 28)
                Spacer()
                VStack(spacing: 3) {
                    Text("\(Int(detail.sugar * Double(servings)))g")
                        .font(.subheadline).fontWeight(.semibold).foregroundColor(Color(red: 1.0, green: 0.45, blue: 0.65))
                    Text("Sugar")
                        .font(.caption2).foregroundColor(.white.opacity(0.5))
                }
                Spacer()
                Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 28)
                Spacer()
                VStack(spacing: 3) {
                    Text("\(Int(detail.sodium * Double(servings)))mg")
                        .font(.subheadline).fontWeight(.semibold).foregroundColor(.cyan)
                    Text("Sodium")
                        .font(.caption2).foregroundColor(.white.opacity(0.5))
                }
                Spacer()
            }
        }
        .padding(18)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.13, green: 0.15, blue: 0.24),
                                Color(red: 0.09, green: 0.10, blue: 0.17)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.09), lineWidth: 1)
            }
        )
        .shadow(color: Color.blue.opacity(0.35), radius: 20, x: 0, y: 8)
    }
    
    // MARK: - Diet Tags Section
    private func dietTagsSection(_ detail: RecipeDetail) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(detail.dietTags, id: \.self) { tag in
                    HStack(spacing: 4) {
                        Image(systemName: tag.icon)
                            .font(.caption2)
                        Text(tag.rawValue)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(tag.color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(tag.color.opacity(0.15))
                    )
                }
            }
        }
    }
    
    // MARK: - Tab Selector
    private var tabSelector: some View {
        HStack(spacing: 0) {
            ForEach(RecipeTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 8) {
                        Text(tab.rawValue)
                            .font(.subheadline)
                            .fontWeight(selectedTab == tab ? .semibold : .regular)
                            .foregroundColor(selectedTab == tab ? .orange : .secondary)
                        
                        Rectangle()
                            .fill(selectedTab == tab ? Color.orange : Color.clear)
                            .frame(height: 2)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 8)
    }
    
    // MARK: - Overview Section
    private func overviewSection(_ detail: RecipeDetail) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if !detail.cleanSummary.isEmpty {
                Text("About This Recipe")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Text(detail.cleanSummary)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .lineSpacing(4)
            }
            
            // Cuisines
            if let cuisines = detail.cuisines, !cuisines.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Cuisine")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    RecipeTagFlowLayout(spacing: 8) {
                        ForEach(cuisines, id: \.self) { cuisine in
                            Text(cuisine)
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.orange.opacity(0.1))
                                .foregroundColor(.orange)
                                .cornerRadius(8)
                        }
                    }
                }
            }
            
            // Dish Types
            if let dishTypes = detail.dishTypes, !dishTypes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Dish Type")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    RecipeTagFlowLayout(spacing: 8) {
                        ForEach(Array(dishTypes.enumerated()), id: \.offset) { index, type in
                            Text(type.capitalized)
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.blue.opacity(0.1))
                                .foregroundColor(.blue)
                                .cornerRadius(8)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
    
    // MARK: - Ingredients Section
    private func ingredientsSection(_ detail: RecipeDetail) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Ingredients")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text("\(detail.extendedIngredients?.count ?? 0) items")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if let ingredients = detail.extendedIngredients {
                VStack(spacing: 0) {
                    ForEach(Array(ingredients.enumerated()), id: \.element.id) { index, ingredient in
                        IngredientRow(
                            ingredient: ingredient,
                            servingMultiplier: Double(servings) / Double(detail.servings),
                            isLast: index == ingredients.count - 1
                        )
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(colorScheme == .dark ? Color(white: 0.12) : .white)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
            }
        }
        .padding(.vertical, 8)
    }
    
    // MARK: - Instructions Section
    private func instructionsSection(_ detail: RecipeDetail) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Instructions")
                .font(.headline)
                .fontWeight(.semibold)
            
            if let analyzedInstructions = detail.analyzedInstructions,
               let instruction = analyzedInstructions.first,
               let steps = instruction.steps {
                VStack(spacing: 16) {
                    ForEach(steps) { step in
                        InstructionStepRow(step: step)
                    }
                }
            } else if let instructions = detail.instructions {
                // Fallback to plain text instructions
                Text(instructions.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression))
                    .font(.body)
                    .foregroundColor(.secondary)
                    .lineSpacing(6)
            } else {
                Text("No instructions available")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
    
    // MARK: - Loading View
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.orange)
            
            Text("Loading recipe...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Error View
    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            
            Text("Failed to load recipe")
                .font(.headline)
            
            Text(error)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button {
                Task {
                    await loadRecipeDetail()
                }
            } label: {
                Label("Try Again", systemImage: "arrow.clockwise")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.orange)
                    .cornerRadius(12)
            }
        }
        .padding()
    }
    
    // MARK: - Background
    private var backgroundGradient: some View {
        AdaptiveGradient.universal(for: colorScheme)
    }
    
    // MARK: - Helper Methods
    private func loadRecipeDetail() async {
        isLoading = true
        errorMessage = nil
        
        if let detail = await spoonacularService.fetchRecipeDetail(recipeId: recipeId) {
            recipeDetail = detail
            servings = 1  // Always start at 1 (per-serving view)
            
            // Track that user viewed this recipe detail
            preferenceService.trackRecipeDetailView(recipe: detail)
        } else {
            errorMessage = "Could not load recipe details"
        }
        
        isLoading = false
    }
    
    private func healthScoreColor(_ score: Double) -> Color {
        if score >= 70 {
            return .green
        } else if score >= 40 {
            return .yellow
        } else {
            return .red
        }
    }
    
    // MARK: - Add to Meal Button
    private func addToMealButton(_ detail: RecipeDetail) -> some View {
        VStack(spacing: 12) {
            Button {
                portionServings = servings // Pre-fill with whatever user set in the card
                showingMealPicker = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add to Meal")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        Text("Track this recipe in your daily meals")
                            .font(.caption)
                            .opacity(0.8)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.subheadline)
                        .opacity(0.7)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [Color.orange, Color.red.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(16)
                .shadow(color: .orange.opacity(0.4), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Add to Shopping List Button
            if let ingredients = detail.extendedIngredients, !ingredients.isEmpty {
                Button {
                    addIngredientsToShoppingList()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "cart.fill.badge.plus")
                            .font(.title3)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Add to Shopping List")
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            Text("\(ingredients.count) ingredients")
                                .font(.caption)
                                .opacity(0.8)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.subheadline)
                            .opacity(0.7)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [Color.purple, Color.pink],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(16)
                    .shadow(color: .purple.opacity(0.4), radius: 8, x: 0, y: 4)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
    
    // MARK: - Added Confirmation Toast
    private var addedConfirmationToast: some View {
        VStack {
            Spacer()
            
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.green)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Added to \(addedMealType?.displayName ?? "Meal")")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    if let detail = recipeDetail {
                        Text("\(detail.calories * servings) cal • \(Int(detail.protein * Double(servings)))g protein")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(colorScheme == .dark ? Color(white: 0.15) : .white)
                    .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 4)
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .zIndex(100)
    }
    
    // MARK: - Add to Meal Function
    private func addToMeal(_ mealType: MealType) {
        guard let detail = recipeDetail,
              let user = userManager.currentUser else {
            print("❌ [RECIPE] Cannot add to meal - missing detail or user")
            return
        }
        
        // detail.calories/protein/carbs/fat are already per-serving values from Spoonacular
        // Multiply by portionServings to get total for what the user actually ate
        let adjustedCalories = detail.calories * portionServings
        let adjustedProtein = Int(detail.protein * Double(portionServings))
        let adjustedCarbs = Int(detail.carbs * Double(portionServings))
        let adjustedFat = Int(detail.fat * Double(portionServings))
        
        // Create a FoodEntry from the recipe
        let foodEntry = FoodEntry(
            name: detail.title,
            quantity: portionServings,
            unit: portionServings == 1 ? "serving" : "servings",
            calories: adjustedCalories,
            protein: adjustedProtein,
            carbs: adjustedCarbs,
            fat: adjustedFat,
            fdcId: detail.id, // Use recipe ID as identifier
            foodItemId: detail.id
        )
        
        // Add to MealService
        MealService.shared.addMealEntry(foodEntry, mealType: mealType, user: user)
        
        // Track this addition for personalized recommendations
        preferenceService.trackRecipeAddedToMeal(recipe: detail, mealType: mealType, servings: portionServings)
        
        print("✅ [RECIPE] Added '\(detail.title)' to \(mealType.displayName)")
        print("   Portion: \(portionServings) serving(s) out of \(detail.servings) total")
        print("   Calories: \(adjustedCalories), Protein: \(adjustedProtein)g")
        
        // Show confirmation
        addedMealType = mealType
        withAnimation(.spring(response: 0.4)) {
            showingAddedConfirmation = true
        }
        
        // Hide confirmation after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.easeOut(duration: 0.3)) {
                showingAddedConfirmation = false
            }
        }
    }
    
    // MARK: - Favorite State Management
    private func saveFavoriteState() {
        var favorites = UserDefaults.standard.array(forKey: "favoriteRecipeIds") as? [Int] ?? []
        
        if isFavorite {
            if !favorites.contains(recipeId) {
                favorites.append(recipeId)
            }
        } else {
            favorites.removeAll { $0 == recipeId }
        }
        
        UserDefaults.standard.set(favorites, forKey: "favoriteRecipeIds")
        print("⭐ [RECIPE] Favorite state saved: \(isFavorite) for recipe \(recipeId)")
        
        // Track favorite interaction for recommendations
        preferenceService.trackRecipeFavorited(
            recipeId: recipeId,
            recipeTitle: recipeDetail?.title ?? initialRecipe?.title ?? "Unknown",
            isFavorite: isFavorite
        )
    }
    
    private func loadFavoriteState() {
        let favorites = UserDefaults.standard.array(forKey: "favoriteRecipeIds") as? [Int] ?? []
        isFavorite = favorites.contains(recipeId)
    }
    
    private func loadSavedState() {
        isSaved = savedMealsService.isMealSaved(id: "recipe_\(recipeId)")
    }
    
    private func toggleSaveMeal() {
        guard let detail = recipeDetail else { return }
        
        let savedMeal = SavedMeal.fromRecipeDetail(detail)
        
        if isSaved {
            savedMealsService.removeSavedMeal(id: savedMeal.id)
        } else {
            savedMealsService.saveMeal(savedMeal)
        }
        
        isSaved.toggle()
        HapticManager.tap()
    }
    
    private func addIngredientsToShoppingList() {
        guard let detail = recipeDetail,
              let ingredients = detail.extendedIngredients else { return }
        
        let shoppingItems = ingredients.map { ingredient in
            ShoppingListItem(
                name: ingredient.name,
                amount: ingredient.amount,
                unit: ingredient.unit ?? "",
                aisle: ingredient.aisle,
                fromRecipe: detail.title
            )
        }
        
        savedMealsService.addToShoppingList(ingredients: shoppingItems)
        HapticManager.success()
        
        withAnimation(.spring(response: 0.4)) {
            showingAddedToList = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.easeOut(duration: 0.3)) {
                showingAddedToList = false
            }
        }
    }
}

// MARK: - Supporting Views

struct RecipeMacroTile: View {
    let value: String
    let label: String
    let unit: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .lastTextBaseline, spacing: 1) {
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(color)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(color.opacity(0.7))
                }
            }
            Text(label)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color.opacity(0.12))
        )
    }
}

struct InfoBadge: View {
    let icon: String
    let text: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption2)
                .fontWeight(.medium)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(color.opacity(0.8))
        )
    }
}

struct NutrientCircle: View {
    let value: Int
    let unit: String
    let label: String
    let color: Color
    let icon: String
    
    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 56, height: 56)
                
                VStack(spacing: 0) {
                    Text("\(value)")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(color)
                    
                    if !unit.isEmpty {
                        Text(unit)
                            .font(.caption2)
                            .foregroundColor(color.opacity(0.8))
                    }
                }
            }
            
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

struct MiniNutrientBadge: View {
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

struct IngredientRow: View {
    let ingredient: ExtendedIngredient
    let servingMultiplier: Double
    let isLast: Bool
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 12) {
            // Ingredient image
            AsyncImage(url: ingredient.imageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                case .failure, .empty:
                    Circle()
                        .fill(Color.orange.opacity(0.1))
                        .overlay(
                            Image(systemName: "leaf.fill")
                                .font(.caption)
                                .foregroundColor(.orange)
                        )
                @unknown default:
                    Circle()
                        .fill(Color.gray.opacity(0.2))
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(Circle())
            
            // Name
            Text(ingredient.name.capitalized)
                .font(.subheadline)
                .foregroundColor(.primary)
            
            Spacer()
            
            // Amount (adjusted for servings)
            let adjustedAmount = ingredient.amount * servingMultiplier
            Text("\(formatAmount(adjustedAmount)) \(ingredient.unit ?? "")")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.clear)
        
        if !isLast {
            Divider()
                .padding(.leading, 68)
        }
    }
    
    private func formatAmount(_ amount: Double) -> String {
        if amount == amount.rounded() {
            return "\(Int(amount))"
        } else {
            return String(format: "%.1f", amount)
        }
    }
}

struct InstructionStepRow: View {
    let step: InstructionStep
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Step number
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.orange, .red],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)
                
                Text("\(step.number)")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text(step.step)
                    .font(.body)
                    .foregroundColor(.primary)
                    .lineSpacing(4)
                
                // Time indicator if available
                if let length = step.length {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.caption2)
                        Text("\(length.number) \(length.unit)")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }
                
                // Equipment if available
                if let equipment = step.equipment, !equipment.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "wrench.and.screwdriver")
                            .font(.caption2)
                        Text(equipment.map { $0.name }.joined(separator: ", "))
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color(white: 0.12) : Color(white: 0.98))
        )
    }
}

// MARK: - Recipe Tag Flow Layout
struct RecipeTagFlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = RecipeFlowResult(in: proposal.replacingUnspecifiedDimensions().width, subviews: subviews, spacing: spacing)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = RecipeFlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y), proposal: .unspecified)
        }
    }
    
    struct RecipeFlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if currentX + size.width > maxWidth && currentX > 0 {
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }
                
                positions.append(CGPoint(x: currentX, y: currentY))
                lineHeight = max(lineHeight, size.height)
                currentX += size.width + spacing
                
                self.size.width = max(self.size.width, currentX)
            }
            
            self.size.height = currentY + lineHeight
        }
    }
}

// MARK: - Smart Serving Selector Sheet
struct SmartServingSelectorSheet: View {
    let recipe: RecipeDetail
    let recipeDefaultServings: Int
    @Binding var portionServings: Int
    let onAddToMeal: (MealType) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedMealType: MealType = .breakfast
    
    // Spoonacular returns per-serving values — use them directly
    private var caloriesPerServing: Int {
        recipe.calories
    }
    
    private var proteinPerServing: Double {
        recipe.protein
    }
    
    private var carbsPerServing: Double {
        recipe.carbs
    }
    
    private var fatPerServing: Double {
        recipe.fat
    }
    
    // Calculate nutrition for selected portion
    private var portionCalories: Int {
        caloriesPerServing * portionServings
    }
    
    private var portionProtein: Int {
        Int(proteinPerServing * Double(portionServings))
    }
    
    private var portionCarbs: Int {
        Int(carbsPerServing * Double(portionServings))
    }
    
    private var portionFat: Int {
        Int(fatPerServing * Double(portionServings))
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                (colorScheme == .dark ? Color.black : Color(white: 0.95))
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Recipe info
                        VStack(spacing: 12) {
                            Text(recipe.title)
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.center)
                            
                            Text("Recipe makes \(recipeDefaultServings) servings")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 8)
                        
                        Divider()
                        
                        // Portion selector
                        VStack(alignment: .leading, spacing: 12) {
                            Text("How many servings did you eat?")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            HStack {
                                Spacer()
                                
                                // Stepper
                                HStack(spacing: 20) {
                                    Button {
                                        if portionServings > 1 {
                                            HapticManager.selectionChanged()
                                            portionServings -= 1
                                        }
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .font(.system(size: 36))
                                            .foregroundColor(portionServings > 1 ? .orange : .gray)
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
                                        if portionServings < recipeDefaultServings {
                                            HapticManager.selectionChanged()
                                            portionServings += 1
                                        }
                                    } label: {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.system(size: 36))
                                            .foregroundColor(portionServings < recipeDefaultServings ? .orange : .gray)
                                    }
                                    .disabled(portionServings >= recipeDefaultServings)
                                }
                                
                                Spacer()
                            }
                            .padding(.vertical, 12)
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(colorScheme == .dark ? Color(white: 0.12) : Color.white)
                        )
                        
                        // Nutrition preview
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Nutrition you're tracking")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            HStack(spacing: 12) {
                                NutritionBadge(
                                    label: "Calories",
                                    value: "\(portionCalories)",
                                    color: .orange
                                )
                                
                                NutritionBadge(
                                    label: "Protein",
                                    value: "\(portionProtein)g",
                                    color: .blue
                                )
                            }
                            
                            HStack(spacing: 12) {
                                NutritionBadge(
                                    label: "Carbs",
                                    value: "\(portionCarbs)g",
                                    color: .green
                                )
                                
                                NutritionBadge(
                                    label: "Fat",
                                    value: "\(portionFat)g",
                                    color: .purple
                                )
                            }
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(colorScheme == .dark ? Color(white: 0.12) : Color.white)
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
                                MealTypeButton(
                                    mealType: .breakfast,
                                    isSelected: selectedMealType == .breakfast,
                                    action: { selectedMealType = .breakfast }
                                )
                                
                                MealTypeButton(
                                    mealType: .lunch,
                                    isSelected: selectedMealType == .lunch,
                                    action: { selectedMealType = .lunch }
                                )
                                
                                MealTypeButton(
                                    mealType: .dinner,
                                    isSelected: selectedMealType == .dinner,
                                    action: { selectedMealType = .dinner }
                                )
                                
                                MealTypeButton(
                                    mealType: .snacks,
                                    isSelected: selectedMealType == .snacks,
                                    action: { selectedMealType = .snacks }
                                )
                            }
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(colorScheme == .dark ? Color(white: 0.12) : Color.white)
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
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(
                                    colors: [.orange, .red.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(14)
                            .shadow(color: .orange.opacity(0.4), radius: 8, x: 0, y: 4)
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

// MARK: - Nutrition Badge
struct NutritionBadge: View {
    let label: String
    let value: String
    let color: Color
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(colorScheme == .dark ? 0.15 : 0.1))
        )
    }
}

// MARK: - Meal Type Button
struct MealTypeButton: View {
    let mealType: MealType
    let isSelected: Bool
    let action: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var icon: String {
        switch mealType {
        case .breakfast: return "sunrise.fill"
        case .lunch: return "sun.max.fill"
        case .dinner: return "moon.stars.fill"
        case .snacks: return "leaf.fill"
        }
    }
    
    private var gradient: [Color] {
        switch mealType {
        case .breakfast: return [.orange, .yellow]
        case .lunch: return [.blue, .cyan]
        case .dinner: return [.indigo, .purple]
        case .snacks: return [.green, .mint]
        }
    }
    
    var body: some View {
        Button(action: {
            HapticManager.selectionChanged()
            action()
        }) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: gradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundColor(.white)
                }
                
                Text(mealType.displayName)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundColor(isSelected ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected 
                          ? gradient[0].opacity(colorScheme == .dark ? 0.2 : 0.15)
                          : Color.clear
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                isSelected ? gradient[0] : Color.gray.opacity(0.3),
                                lineWidth: isSelected ? 2 : 1
                            )
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview
#Preview {
    NavigationView {
        RecipeDetailView(
            recipeId: 716429,
            initialRecipe: SpoonacularRecipe(
                id: 716429,
                title: "Pasta with Garlic, Scallions, Cauliflower & Breadcrumbs",
                image: "https://img.spoonacular.com/recipes/716429-556x370.jpg",
                imageType: "jpg",
                nutrition: nil
            )
        )
    }
}
