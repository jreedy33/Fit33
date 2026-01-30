import SwiftUI

// MARK: - Recipe Import Sheet
/// Import recipes from any URL
struct RecipeImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var advancedService = SpoonacularAdvancedService.shared
    
    @State private var urlText: String = ""
    @State private var isExtracting = false
    @State private var extractedRecipe: ExtractedRecipe?
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationView {
            ZStack {
                (colorScheme == .dark ? Color.black : Color(white: 0.95))
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        headerSection
                        
                        // URL Input
                        urlInputSection
                        
                        // Extract Button
                        extractButton
                        
                        // Results
                        if let recipe = extractedRecipe {
                            extractedRecipeCard(recipe)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Import Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 70, height: 70)
                    .shadow(color: .blue.opacity(0.4), radius: 10, x: 0, y: 5)
                
                Image(systemName: "link.badge.plus")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            Text("Import from URL")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Paste any recipe URL and we'll extract\nthe ingredients and nutrition info")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 8)
    }
    
    private var urlInputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recipe URL")
                .font(.headline)
                .foregroundColor(.primary)
            
            HStack {
                Image(systemName: "link")
                    .foregroundColor(.secondary)
                
                TextField("https://example.com/recipe", text: $urlText)
                    .autocapitalization(.none)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                
                if !urlText.isEmpty {
                    Button(action: { urlText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? Color(white: 0.15) : Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                    )
            )
            
            Text("Works with most recipe websites like AllRecipes, Food Network, etc.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(colorScheme == .dark ? Color(white: 0.12) : Color(white: 0.98))
        )
    }
    
    private var extractButton: some View {
        Button(action: extractRecipe) {
            HStack(spacing: 8) {
                if isExtracting {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "arrow.down.doc")
                }
                Text(isExtracting ? "Extracting..." : "Extract Recipe")
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: urlText.isEmpty ? [.gray] : [.blue, .cyan],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(14)
            .shadow(color: urlText.isEmpty ? .clear : .blue.opacity(0.4), radius: 8, x: 0, y: 4)
        }
        .disabled(urlText.isEmpty || isExtracting)
    }
    
    private func extractedRecipeCard(_ recipe: ExtractedRecipe) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Success header
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title2)
                
                Text("Recipe Extracted!")
                    .font(.headline)
                    .fontWeight(.bold)
                
                Spacer()
            }
            
            // Recipe info
            VStack(alignment: .leading, spacing: 12) {
                Text(recipe.title)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                if let sourceName = recipe.sourceName {
                    Text("From: \(sourceName)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Nutrition
                HStack(spacing: 16) {
                    NutritionPill(label: "Cal", value: "\(recipe.calories)", color: .orange)
                    NutritionPill(label: "Protein", value: "\(recipe.protein)g", color: .blue)
                    NutritionPill(label: "Carbs", value: "\(recipe.carbs)g", color: .green)
                    NutritionPill(label: "Fat", value: "\(recipe.fat)g", color: .purple)
                }
                
                // Meta info
                if let time = recipe.readyInMinutes, let servings = recipe.servings {
                    HStack(spacing: 16) {
                        Label("\(time) min", systemImage: "clock")
                        Label("\(servings) servings", systemImage: "person.2")
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }
                
                // Ingredients count
                if let ingredients = recipe.extendedIngredients {
                    Text("\(ingredients.count) ingredients")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(colorScheme == .dark ? Color(white: 0.12) : Color.white)
            )
            
            // Action buttons
            HStack(spacing: 12) {
                Button(action: { /* Save to favorites */ }) {
                    HStack {
                        Image(systemName: "star")
                        Text("Save")
                    }
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.95))
                    )
                }
                
                Button(action: { dismiss() }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Add to Meal")
                    }
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(colors: [.blue, .cyan], startPoint: .leading, endPoint: .trailing)
                    )
                    .cornerRadius(12)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(colorScheme == .dark ? Color(white: 0.08) : Color(white: 0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.green.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    private func extractRecipe() {
        guard !urlText.isEmpty else { return }
        
        isExtracting = true
        HapticManager.tap()
        
        Task {
            let recipe = await advancedService.extractRecipeFromURL(urlString: urlText)
            
            await MainActor.run {
                if let recipe = recipe {
                    extractedRecipe = recipe
                } else {
                    errorMessage = "Could not extract recipe from this URL. Please try a different recipe page."
                    showError = true
                }
                isExtracting = false
            }
        }
    }
}

// MARK: - Nutrition Pill
struct NutritionPill: View {
    let label: String
    let value: String
    let color: Color
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(color)
            
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(color.opacity(colorScheme == .dark ? 0.15 : 0.1))
        )
    }
}

// MARK: - Restaurant Search Sheet
struct RestaurantSearchSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var userManager: UserManager
    @StateObject private var advancedService = SpoonacularAdvancedService.shared
    
    @State private var searchQuery: String = ""
    @State private var isSearching = false
    @State private var menuItems: [MenuItem] = []
    @State private var selectedMenuItem: MenuItem?
    @State private var menuItemDetail: MenuItemDetail?
    @State private var showingMealPicker = false
    
    var body: some View {
        NavigationView {
            ZStack {
                (colorScheme == .dark ? Color.black : Color(white: 0.95))
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Search bar
                    searchBar
                    
                    // Results
                    if isSearching {
                        ProgressView("Searching...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if menuItems.isEmpty && !searchQuery.isEmpty {
                        emptyState
                    } else {
                        resultsList
                    }
                }
            }
            .navigationTitle("Restaurant Foods")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showingMealPicker) {
                if let detail = menuItemDetail {
                    MenuItemAddSheet(menuItem: detail)
                }
            }
        }
    }
    
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("Search restaurant foods...", text: $searchQuery)
                .onSubmit { searchMenuItems() }
            
            if !searchQuery.isEmpty {
                Button(action: { searchQuery = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color(white: 0.12) : Color.white)
        )
        .padding()
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "fork.knife.circle")
                .font(.system(size: 50))
                .foregroundColor(.orange.opacity(0.5))
            
            Text("No results found")
                .font(.headline)
            
            Text("Try searching for a restaurant or menu item")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(menuItems) { item in
                    MenuItemRow(item: item) {
                        selectMenuItem(item)
                    }
                }
            }
            .padding()
        }
    }
    
    private func searchMenuItems() {
        guard !searchQuery.isEmpty else { return }
        
        isSearching = true
        
        Task {
            let results = await advancedService.searchMenuItems(query: searchQuery, number: 20)
            
            await MainActor.run {
                menuItems = results
                isSearching = false
            }
        }
    }
    
    private func selectMenuItem(_ item: MenuItem) {
        Task {
            if let detail = await advancedService.getMenuItemDetails(menuItemId: item.id) {
                await MainActor.run {
                    menuItemDetail = detail
                    showingMealPicker = true
                }
            }
        }
    }
}

// MARK: - Menu Item Row
struct MenuItemRow: View {
    let item: MenuItem
    let onSelect: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 14) {
                // Image
                AsyncImage(url: item.imageURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    ZStack {
                        Color.orange.opacity(0.2)
                        Image(systemName: "fork.knife")
                            .foregroundColor(.orange)
                    }
                }
                .frame(width: 60, height: 60)
                .cornerRadius(10)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    
                    if let restaurant = item.restaurantChain {
                        Text(restaurant)
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    
                    if let serving = item.servingSize {
                        Text(serving)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundColor(.orange)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(colorScheme == .dark ? Color(white: 0.12) : Color.white)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Menu Item Add Sheet
struct MenuItemAddSheet: View {
    let menuItem: MenuItemDetail
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var userManager: UserManager
    @State private var selectedMealType: MealType = .lunch
    @State private var servings: Int = 1
    
    var body: some View {
        NavigationView {
            ZStack {
                (colorScheme == .dark ? Color.black : Color(white: 0.95))
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Food info
                        VStack(alignment: .leading, spacing: 12) {
                            Text(menuItem.title)
                                .font(.title3)
                                .fontWeight(.bold)
                            
                            if let restaurant = menuItem.restaurantChain {
                                HStack {
                                    Image(systemName: "building.2")
                                        .foregroundColor(.orange)
                                    Text(restaurant)
                                        .foregroundColor(.secondary)
                                }
                                .font(.subheadline)
                            }
                            
                            // Nutrition
                            HStack(spacing: 16) {
                                NutritionPill(label: "Cal", value: "\(menuItem.calories * servings)", color: .orange)
                                NutritionPill(label: "Protein", value: "\(Int(menuItem.protein * Double(servings)))g", color: .blue)
                                NutritionPill(label: "Carbs", value: "\(Int(menuItem.carbs * Double(servings)))g", color: .green)
                                NutritionPill(label: "Fat", value: "\(Int(menuItem.fat * Double(servings)))g", color: .purple)
                            }
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(colorScheme == .dark ? Color(white: 0.12) : Color.white)
                        )
                        
                        // Servings
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Servings")
                                .font(.headline)
                            
                            HStack {
                                Button(action: { if servings > 1 { servings -= 1 } }) {
                                    Image(systemName: "minus.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(servings > 1 ? .orange : .gray)
                                }
                                .disabled(servings <= 1)
                                
                                Text("\(servings)")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .frame(minWidth: 50)
                                
                                Button(action: { servings += 1 }) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(.orange)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(colorScheme == .dark ? Color(white: 0.12) : Color.white)
                        )
                        
                        // Meal type
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Add to Meal")
                                .font(.headline)
                            
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                ForEach(MealType.allCases, id: \.self) { meal in
                                    MealTypeButton(
                                        mealType: meal,
                                        isSelected: selectedMealType == meal,
                                        action: { selectedMealType = meal }
                                    )
                                }
                            }
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(colorScheme == .dark ? Color(white: 0.12) : Color.white)
                        )
                        
                        // Add button
                        Button(action: addToMeal) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text("Add to \(selectedMealType.displayName)")
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(colors: [.orange, .red.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
                            )
                            .cornerRadius(14)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Add to Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
    
    private func addToMeal() {
        guard let user = userManager.currentUser else { return }
        
        let foodEntry = FoodEntry(
            name: menuItem.title,
            quantity: servings,
            unit: "serving",
            calories: menuItem.calories * servings,
            protein: Int(menuItem.protein * Double(servings)),
            carbs: Int(menuItem.carbs * Double(servings)),
            fat: Int(menuItem.fat * Double(servings)),
            fdcId: menuItem.id,
            foodItemId: menuItem.id
        )
        
        MealService.shared.addMealEntry(foodEntry, mealType: selectedMealType, user: user)
        HapticManager.success()
        dismiss()
    }
}

// MARK: - Preview
#Preview {
    RecipeImportSheet()
}
