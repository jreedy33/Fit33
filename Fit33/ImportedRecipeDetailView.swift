import SwiftUI

// MARK: - Imported Recipe Detail View
/// Clean detail view for recipes imported from URL
struct ImportedRecipeDetailView: View {
    let recipe: ExtractedRecipe
    let sourceURL: String?
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var userManager: UserManager
    @ObservedObject private var savedMealsService = SavedMealsService.shared
    
    @State private var isSaved = false
    @State private var showingMealPicker = false
    @State private var showingAddedToList = false
    @State private var showingSaveConfirmation = false
    @State private var portionServings: Int = 1
    
    private var savedMeal: SavedMeal {
        SavedMeal.fromExtractedRecipe(recipe, sourceURL: sourceURL)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                backgroundGradient
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 0) {
                        // Hero Image
                        heroImage
                        
                        // Content
                        VStack(spacing: 20) {
                            // Title & Source
                            titleSection
                            
                            // Health Score (if available)
                            if let healthScore = recipe.nutrition?.nutrients?.first(where: { $0.name.lowercased().contains("score") })?.amount {
                                healthScoreSection(score: healthScore)
                            }
                            
                            // Nutrition Card
                            nutritionCard
                            
                            // Action Buttons
                            actionButtons
                            
                            // Ingredients Section
                            ingredientsSection
                            
                            // Instructions (if available)
                            if let instructions = recipe.instructions, !instructions.isEmpty {
                                instructionsSection(instructions)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                    }
                }
                .scrollIndicators(.hidden)
                
                // Confirmation Toasts
                if showingAddedToList {
                    addedToListToast
                }
                
                if showingSaveConfirmation {
                    savedConfirmationToast
                }
            }
            .navigationTitle("Recipe Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        // Save button
                        Button {
                            toggleSave()
                        } label: {
                            Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                                .foregroundColor(isSaved ? .orange : .primary)
                        }
                        
                        // Share button
                        if let url = URL(string: sourceURL ?? recipe.sourceUrl ?? "") {
                            ShareLink(item: url) {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                    }
                }
            }
            .onAppear {
                isSaved = savedMealsService.isMealSaved(id: savedMeal.id)
            }
            .sheet(isPresented: $showingMealPicker) {
                ImportedRecipeMealPickerSheet(
                    recipe: recipe,
                    portionServings: $portionServings,
                    onAddToMeal: { mealType in
                        addToMeal(mealType)
                        showingMealPicker = false
                    }
                )
            }
        }
    }
    
    // MARK: - Hero Image
    private var heroImage: some View {
        ZStack(alignment: .bottomLeading) {
            if let imageURL = recipe.image, let url = URL(string: imageURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        recipeImagePlaceholder
                            .overlay(ProgressView().tint(.white))
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        recipeImagePlaceholder
                    @unknown default:
                        recipeImagePlaceholder
                    }
                }
            } else {
                recipeImagePlaceholder
            }
        }
        .frame(height: 250)
        .clipped()
    }
    
    private var recipeImagePlaceholder: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.blue.opacity(0.3), .cyan.opacity(0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Image(systemName: "fork.knife")
                    .font(.system(size: 50))
                    .foregroundColor(.white.opacity(0.5))
            )
    }
    
    // MARK: - Title Section
    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(recipe.title)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            HStack(spacing: 16) {
                if let source = recipe.sourceName {
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                            .font(.caption)
                        Text("from \(source)")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }
                
                if let time = recipe.readyInMinutes {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.caption)
                        Text("\(time) min")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }
                
                if let servings = recipe.servings {
                    HStack(spacing: 4) {
                        Image(systemName: "person.2")
                            .font(.caption)
                        Text("\(servings) servings")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 16)
    }
    
    // MARK: - Health Score Section
    private func healthScoreSection(score: Double) -> some View {
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
                    .foregroundColor(healthScoreColor(score))
            }
            
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 8)
                    
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(
                                colors: [healthScoreColor(score), healthScoreColor(score).opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * CGFloat(score / 100), height: 8)
                }
            }
            .frame(height: 8)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(colorScheme == .dark ? Color(white: 0.12) : Color.white)
                .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        )
    }
    
    private func healthScoreColor(_ score: Double) -> Color {
        if score >= 70 { return .green }
        else if score >= 40 { return .orange }
        else { return .red }
    }
    
    // MARK: - Nutrition Card
    private var nutritionCard: some View {
        VStack(spacing: 16) {
            Text("Nutrition per Serving")
                .font(.headline)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 12) {
                NutritionCircleSmall(
                    value: recipe.calories / max(recipe.servings ?? 1, 1),
                    unit: "",
                    label: "Calories",
                    color: .orange,
                    icon: "flame.fill"
                )
                
                NutritionCircleSmall(
                    value: recipe.protein / max(recipe.servings ?? 1, 1),
                    unit: "g",
                    label: "Protein",
                    color: .blue,
                    icon: "p.circle.fill"
                )
                
                NutritionCircleSmall(
                    value: recipe.carbs / max(recipe.servings ?? 1, 1),
                    unit: "g",
                    label: "Carbs",
                    color: .green,
                    icon: "c.circle.fill"
                )
                
                NutritionCircleSmall(
                    value: recipe.fat / max(recipe.servings ?? 1, 1),
                    unit: "g",
                    label: "Fat",
                    color: .purple,
                    icon: "f.circle.fill"
                )
            }
            
            // Additional nutrients if available
            if let nutrients = recipe.nutrition?.nutrients {
                let additionalNutrients = nutrients.filter { nutrient in
                    let name = nutrient.name.lowercased()
                    return name.contains("fiber") || name.contains("sugar") || name.contains("sodium")
                }
                
                if !additionalNutrients.isEmpty {
                    Divider()
                    
                    HStack(spacing: 20) {
                        ForEach(additionalNutrients.prefix(3)) { nutrient in
                            VStack(spacing: 2) {
                                Text(formatNutrientValue(nutrient.amount, unit: nutrient.unit))
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                                Text(nutrient.name)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(white: 0.12) : .white)
                .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    LinearGradient(
                        colors: [.blue.opacity(0.3), .cyan.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
    
    private func formatNutrientValue(_ value: Double, unit: String) -> String {
        if value == value.rounded() {
            return "\(Int(value))\(unit)"
        }
        return "\(String(format: "%.1f", value))\(unit)"
    }
    
    // MARK: - Action Buttons
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
                        colors: [Color.blue, Color.cyan],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(16)
                .shadow(color: .blue.opacity(0.4), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Add to Shopping List Button
            if let ingredients = recipe.extendedIngredients, !ingredients.isEmpty {
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
    
    // MARK: - Ingredients Section
    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Ingredients")
                    .font(.title3)
                    .fontWeight(.bold)
                
                Spacer()
                
                if let count = recipe.extendedIngredients?.count {
                    Text("\(count) items")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.blue.opacity(0.1))
                        )
                }
            }
            
            if let ingredients = recipe.extendedIngredients, !ingredients.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(ingredients.enumerated()), id: \.element.id) { index, ingredient in
                        ImportedIngredientRow(
                            ingredient: ingredient,
                            isLast: index == ingredients.count - 1
                        )
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(colorScheme == .dark ? Color(white: 0.12) : .white)
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
    
    // MARK: - Instructions Section
    private func instructionsSection(_ instructions: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Instructions")
                .font(.title3)
                .fontWeight(.bold)
            
            // Clean HTML tags from instructions
            let cleanedInstructions = instructions
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "&nbsp;", with: " ")
                .replacingOccurrences(of: "&amp;", with: "&")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            Text(cleanedInstructions)
                .font(.body)
                .foregroundColor(.secondary)
                .lineSpacing(6)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(colorScheme == .dark ? Color(white: 0.12) : Color(white: 0.98))
                )
        }
    }
    
    // MARK: - Background
    private var backgroundGradient: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color(white: 0.08), Color(white: 0.05)]
                : [Color(red: 0.96, green: 0.98, blue: 1.0), .white],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    // MARK: - Toast Views
    private var addedToListToast: some View {
        VStack {
            Spacer()
            
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.green)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Added to Shopping List")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text("\(recipe.extendedIngredients?.count ?? 0) ingredients added")
                        .font(.caption)
                        .foregroundColor(.secondary)
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
    
    private var savedConfirmationToast: some View {
        VStack {
            Spacer()
            
            HStack(spacing: 12) {
                Image(systemName: isSaved ? "bookmark.fill" : "bookmark.slash")
                    .font(.title2)
                    .foregroundColor(isSaved ? .orange : .secondary)
                
                Text(isSaved ? "Recipe Saved!" : "Recipe Removed")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
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
    
    // MARK: - Actions
    
    private func toggleSave() {
        withAnimation(.spring(response: 0.3)) {
            if isSaved {
                savedMealsService.removeSavedMeal(id: savedMeal.id)
            } else {
                savedMealsService.saveMeal(savedMeal)
            }
            isSaved.toggle()
            showingSaveConfirmation = true
        }
        
        HapticManager.tap()
        
        // Hide toast after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeOut(duration: 0.3)) {
                showingSaveConfirmation = false
            }
        }
    }
    
    private func addIngredientsToShoppingList() {
        guard let ingredients = recipe.extendedIngredients else { return }
        
        let shoppingItems = ingredients.map { ingredient in
            ShoppingListItem(
                name: ingredient.name,
                amount: ingredient.amount,
                unit: ingredient.unit ?? "",
                aisle: ingredient.aisle,
                fromRecipe: recipe.title
            )
        }
        
        savedMealsService.addToShoppingList(ingredients: shoppingItems)
        HapticManager.success()
        
        withAnimation(.spring(response: 0.4)) {
            showingAddedToList = true
        }
        
        // Hide toast after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.easeOut(duration: 0.3)) {
                showingAddedToList = false
            }
        }
    }
    
    private func addToMeal(_ mealType: MealType) {
        guard let user = userManager.currentUser else {
            print("❌ [IMPORTED RECIPE] Cannot add to meal - no user")
            return
        }
        
        let servings = recipe.servings ?? 1
        let caloriesPerServing = recipe.calories / max(servings, 1)
        let proteinPerServing = recipe.protein / max(servings, 1)
        let carbsPerServing = recipe.carbs / max(servings, 1)
        let fatPerServing = recipe.fat / max(servings, 1)
        
        let adjustedCalories = caloriesPerServing * portionServings
        let adjustedProtein = proteinPerServing * portionServings
        let adjustedCarbs = carbsPerServing * portionServings
        let adjustedFat = fatPerServing * portionServings
        
        let foodEntry = FoodEntry(
            name: recipe.title,
            quantity: portionServings,
            unit: portionServings == 1 ? "serving" : "servings",
            calories: adjustedCalories,
            protein: adjustedProtein,
            carbs: adjustedCarbs,
            fat: adjustedFat,
            fdcId: recipe.id,
            foodItemId: recipe.id
        )
        
        MealService.shared.addMealEntry(foodEntry, mealType: mealType, user: user)
        HapticManager.success()
        
        print("✅ [IMPORTED RECIPE] Added '\(recipe.title)' to \(mealType.displayName)")
    }
}

// MARK: - Supporting Views

struct NutritionCircleSmall: View {
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
                    .frame(width: 52, height: 52)
                
                VStack(spacing: 0) {
                    Text("\(value)")
                        .font(.subheadline)
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
        .frame(maxWidth: .infinity)
    }
}

struct ImportedIngredientRow: View {
    let ingredient: ExtendedIngredient
    let isLast: Bool
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 0) {
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
                            .fill(Color.blue.opacity(0.1))
                            .overlay(
                                Image(systemName: "leaf.fill")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            )
                    @unknown default:
                        Circle()
                            .fill(Color.gray.opacity(0.2))
                    }
                }
                .frame(width: 40, height: 40)
                .clipShape(Circle())
                
                // Name and original text
                VStack(alignment: .leading, spacing: 2) {
                    Text(ingredient.name.capitalized)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text(ingredient.original)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Amount
                Text("\(ingredient.formattedAmount) \(ingredient.unit ?? "")")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            if !isLast {
                Divider()
                    .padding(.leading, 68)
            }
        }
    }
}

// MARK: - Imported Recipe Meal Picker Sheet
struct ImportedRecipeMealPickerSheet: View {
    let recipe: ExtractedRecipe
    @Binding var portionServings: Int
    let onAddToMeal: (MealType) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedMealType: MealType = .lunch
    
    private var servings: Int {
        recipe.servings ?? 1
    }
    
    private var caloriesPerServing: Int {
        recipe.calories / max(servings, 1)
    }
    
    private var proteinPerServing: Int {
        recipe.protein / max(servings, 1)
    }
    
    private var carbsPerServing: Int {
        recipe.carbs / max(servings, 1)
    }
    
    private var fatPerServing: Int {
        recipe.fat / max(servings, 1)
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
                            Text(recipe.title)
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.center)
                            
                            Text("Recipe makes \(servings) servings")
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
                                            .foregroundColor(portionServings > 1 ? .blue : .gray)
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
                                        if portionServings < servings {
                                            HapticManager.selectionChanged()
                                            portionServings += 1
                                        }
                                    } label: {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.system(size: 36))
                                            .foregroundColor(portionServings < servings ? .blue : .gray)
                                    }
                                    .disabled(portionServings >= servings)
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
                                    value: "\(caloriesPerServing * portionServings)",
                                    color: .orange
                                )
                                
                                NutritionBadge(
                                    label: "Protein",
                                    value: "\(proteinPerServing * portionServings)g",
                                    color: .blue
                                )
                            }
                            
                            HStack(spacing: 12) {
                                NutritionBadge(
                                    label: "Carbs",
                                    value: "\(carbsPerServing * portionServings)g",
                                    color: .green
                                )
                                
                                NutritionBadge(
                                    label: "Fat",
                                    value: "\(fatPerServing * portionServings)g",
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
                                ForEach(MealType.allCases, id: \.self) { meal in
                                    MealTypeButton(
                                        mealType: meal,
                                        isSelected: selectedMealType == meal,
                                        action: { selectedMealType = meal }
                                    )
                                }
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
                                    colors: [.blue, .cyan],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(14)
                            .shadow(color: .blue.opacity(0.4), radius: 8, x: 0, y: 4)
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

// MARK: - Preview
#Preview {
    ImportedRecipeDetailView(
        recipe: ExtractedRecipe(
            id: 12345,
            title: "Homemade Pasta with Marinara Sauce",
            image: "https://img.spoonacular.com/recipes/716429-556x370.jpg",
            servings: 4,
            readyInMinutes: 45,
            sourceUrl: "https://example.com/recipe",
            sourceName: "Example Kitchen",
            summary: "A delicious homemade pasta recipe",
            instructions: "Cook pasta according to package directions...",
            extendedIngredients: [],
            nutrition: nil
        ),
        sourceURL: "https://example.com/recipe"
    )
}
