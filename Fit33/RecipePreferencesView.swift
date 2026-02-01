//
//  RecipePreferencesView.swift
//  Fit33
//
//  User food/ingredient preferences for personalized recipe recommendations
//

import SwiftUI

// MARK: - Recipe Preferences View
struct RecipePreferencesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel = RecipePreferencesViewModel()
    @State private var showingAddIngredient = false
    @State private var newIngredient = ""
    @State private var selectedTab = 0 // 0 = Likes, 1 = Dislikes
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header explanation
                    headerSection
                    
                    // Ingredient Preferences
                    ingredientPreferencesSection
                    
                    // Popular Ingredients Quick Add
                    popularIngredientsSection
                    
                    // Cuisine Preferences
                    cuisinePreferencesSection
                    
                    // Dietary Restrictions
                    dietaryRestrictionsSection
                    
                    // Recipe Preferences
                    recipePreferencesSection
                    
                    Spacer(minLength: 100)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }
            .background(backgroundGradient.ignoresSafeArea())
            .navigationTitle("Food Preferences")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        // Sync preferences to the shared service for immediate recipe updates
                        syncToRecipeService()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(.orange)
                }
            }
            .task {
                await viewModel.loadPreferences()
            }
            .alert("Add Ingredient", isPresented: $showingAddIngredient) {
                TextField("Ingredient name", text: $newIngredient)
                    .textInputAutocapitalization(.words)
                Button("Add to Likes") {
                    Task {
                        await viewModel.addIngredient(newIngredient, type: .like)
                        newIngredient = ""
                    }
                }
                Button("Add to Dislikes") {
                    Task {
                        await viewModel.addIngredient(newIngredient, type: .dislike)
                        newIngredient = ""
                    }
                }
                Button("Cancel", role: .cancel) {
                    newIngredient = ""
                }
            }
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.orange, .red],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: "heart.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Personalize Your Recipes")
                        .font(.headline)
                        .fontWeight(.bold)
                    
                    Text("Tell us what you love and what to avoid")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(cardBackground)
    }
    
    // MARK: - Ingredient Preferences Section
    private var ingredientPreferencesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Your Ingredients")
                    .font(.headline)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button {
                    showingAddIngredient = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                        Text("Add")
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.orange)
                }
            }
            
            // Tab selector
            HStack(spacing: 0) {
                PreferenceTabButton(
                    title: "Favorites",
                    icon: "heart.fill",
                    color: .green,
                    isSelected: selectedTab == 0
                ) {
                    withAnimation { selectedTab = 0 }
                }
                
                PreferenceTabButton(
                    title: "Avoid",
                    icon: "xmark.circle.fill",
                    color: .red,
                    isSelected: selectedTab == 1
                ) {
                    withAnimation { selectedTab = 1 }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? Color(white: 0.12) : Color(white: 0.95))
            )
            
            // Content based on tab
            if selectedTab == 0 {
                // Liked ingredients
                if viewModel.likedIngredients.isEmpty {
                    emptyIngredientState(type: "favorite")
                } else {
                    FlowLayout(spacing: 8) {
                        ForEach(viewModel.likedIngredients, id: \.self) { ingredient in
                            IngredientChip(
                                name: ingredient,
                                color: .green,
                                onRemove: {
                                    Task {
                                        await viewModel.removeIngredient(ingredient, type: .like)
                                    }
                                }
                            )
                        }
                    }
                }
            } else {
                // Disliked ingredients
                if viewModel.dislikedIngredients.isEmpty {
                    emptyIngredientState(type: "avoid")
                } else {
                    FlowLayout(spacing: 8) {
                        ForEach(viewModel.dislikedIngredients, id: \.self) { ingredient in
                            IngredientChip(
                                name: ingredient,
                                color: .red,
                                onRemove: {
                                    Task {
                                        await viewModel.removeIngredient(ingredient, type: .dislike)
                                    }
                                }
                            )
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(cardBackground)
    }
    
    private func emptyIngredientState(type: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: type == "favorite" ? "heart" : "xmark.circle")
                .font(.title2)
                .foregroundColor(.secondary)
            
            Text(type == "favorite" ? "No favorite ingredients yet" : "No ingredients to avoid")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text("Tap + to add or select from popular options below")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
    
    // MARK: - Popular Ingredients Section
    private var popularIngredientsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Quick Add Popular Ingredients")
                .font(.headline)
                .fontWeight(.bold)
            
            // Category pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(IngredientCategory.allCases, id: \.self) { category in
                        CategoryPill(
                            category: category,
                            isSelected: viewModel.selectedCategory == category
                        ) {
                            withAnimation {
                                viewModel.selectedCategory = category
                            }
                        }
                    }
                }
            }
            
            // Filtered ingredients grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 10) {
                ForEach(viewModel.filteredPopularIngredients, id: \.name) { ingredient in
                    PopularIngredientButton(
                        ingredient: ingredient,
                        isLiked: viewModel.likedIngredients.contains(ingredient.name),
                        isDisliked: viewModel.dislikedIngredients.contains(ingredient.name),
                        onLike: {
                            Task {
                                await viewModel.addIngredient(ingredient.name, type: .like)
                            }
                        },
                        onDislike: {
                            Task {
                                await viewModel.addIngredient(ingredient.name, type: .dislike)
                            }
                        },
                        onRemove: {
                            Task {
                                await viewModel.removeIngredient(ingredient.name, type: .like)
                                await viewModel.removeIngredient(ingredient.name, type: .dislike)
                            }
                        }
                    )
                }
            }
        }
        .padding(16)
        .background(cardBackground)
    }
    
    // MARK: - Cuisine Preferences Section
    private var cuisinePreferencesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Cuisine Preferences")
                .font(.headline)
                .fontWeight(.bold)
            
            Text("Double tap to dislike")
                .font(.caption)
                .foregroundColor(.secondary)
            
            FlowLayout(spacing: 8) {
                ForEach(viewModel.popularCuisines, id: \.name) { cuisine in
                    CuisineChip(
                        cuisine: cuisine,
                        isLiked: viewModel.likedCuisines.contains(cuisine.name),
                        isDisliked: viewModel.dislikedCuisines.contains(cuisine.name),
                        onTap: {
                            Task {
                                await viewModel.toggleCuisine(cuisine.name)
                            }
                        },
                        onDoubleTap: {
                            Task {
                                await viewModel.dislikeCuisine(cuisine.name)
                            }
                        }
                    )
                }
            }
        }
        .padding(16)
        .background(cardBackground)
    }
    
    // MARK: - Dietary Restrictions Section
    private var dietaryRestrictionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Dietary Needs")
                .font(.headline)
                .fontWeight(.bold)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 10) {
                ForEach(DietaryRestriction.allCases, id: \.self) { restriction in
                    DietaryToggle(
                        restriction: restriction,
                        isEnabled: viewModel.dietaryRestrictions.contains(restriction),
                        isAllergy: viewModel.allergies.contains(restriction)
                    ) {
                        Task {
                            await viewModel.toggleDietaryRestriction(restriction)
                        }
                    } onLongPress: {
                        Task {
                            await viewModel.toggleAllergy(restriction)
                        }
                    }
                }
            }
            
            Text("💡 Long press to mark as allergy (strict filter)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .background(cardBackground)
    }
    
    // MARK: - Recipe Preferences Section
    private var recipePreferencesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recipe Preferences")
                .font(.headline)
                .fontWeight(.bold)
            
            VStack(spacing: 12) {
                PreferenceToggleRow(
                    icon: "bolt.fill",
                    title: "High Protein",
                    subtitle: "30g+ protein per serving",
                    color: .blue,
                    isEnabled: viewModel.prefersHighProtein
                ) {
                    Task {
                        await viewModel.toggleHighProtein()
                    }
                }
                
                PreferenceToggleRow(
                    icon: "leaf.fill",
                    title: "Low Carb",
                    subtitle: "Under 20g carbs per serving",
                    color: .green,
                    isEnabled: viewModel.prefersLowCarb
                ) {
                    Task {
                        await viewModel.toggleLowCarb()
                    }
                }
                
                PreferenceToggleRow(
                    icon: "flame.fill",
                    title: "Low Calorie",
                    subtitle: "Under 400 calories per serving",
                    color: .orange,
                    isEnabled: viewModel.prefersLowCalorie
                ) {
                    Task {
                        await viewModel.toggleLowCalorie()
                    }
                }
            }
        }
        .padding(16)
        .background(cardBackground)
    }
    
    // MARK: - Sync to Shared Service
    private func syncToRecipeService() {
        let service = RecipePreferenceService.shared
        
        // Update liked ingredients
        service.setLikedIngredients(viewModel.likedIngredients)
        
        // Update disliked ingredients
        service.setDislikedIngredients(viewModel.dislikedIngredients)
        
        print("🔄 [PREFS VIEW] Synced preferences to shared service - recipes will refresh")
    }
    
    // MARK: - Background
    private var backgroundGradient: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color(white: 0.08), Color(white: 0.05)]
                : [Color(red: 0.98, green: 0.96, blue: 0.94), .white],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(colorScheme == .dark ? Color(white: 0.12) : .white)
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 8, x: 0, y: 4)
    }
}

// MARK: - View Model
@MainActor
class RecipePreferencesViewModel: ObservableObject {
    @Published var likedIngredients: [String] = []
    @Published var dislikedIngredients: [String] = []
    @Published var likedCuisines: [String] = []
    @Published var dislikedCuisines: [String] = []
    @Published var dietaryRestrictions: Set<DietaryRestriction> = []
    @Published var allergies: Set<DietaryRestriction> = []
    @Published var prefersHighProtein = false
    @Published var prefersLowCarb = false
    @Published var prefersLowCalorie = false
    @Published var selectedCategory: IngredientCategory = .protein
    @Published var popularIngredients: [PopularIngredient] = []
    @Published var popularCuisines: [PopularCuisine] = []
    @Published var isLoading = false
    
    var filteredPopularIngredients: [PopularIngredient] {
        popularIngredients.filter { $0.category == selectedCategory }
    }
    
    // MARK: - Load Preferences
    func loadPreferences() async {
        isLoading = true
        
        // Load from Supabase
        guard let userId = SupabaseManager.shared.currentUser?.id else {
            // Fall back to local storage
            loadLocalPreferences()
            loadDefaultPopularItems()
            isLoading = false
            return
        }
        
        do {
            // Fetch ingredient preferences
            let ingredients: [IngredientPreferenceDTO] = try await SupabaseManager.shared.supabaseClient
                .from("user_ingredient_preferences")
                .select()
                .eq("user_id", value: userId.uuidString)
                .execute()
                .value
            
            likedIngredients = ingredients.filter { $0.preferenceType == "like" }.map { $0.ingredientName }
            dislikedIngredients = ingredients.filter { $0.preferenceType == "dislike" }.map { $0.ingredientName }
            
            // Fetch cuisine preferences
            let cuisines: [CuisinePreferenceDTO] = try await SupabaseManager.shared.supabaseClient
                .from("user_cuisine_preferences")
                .select()
                .eq("user_id", value: userId.uuidString)
                .execute()
                .value
            
            likedCuisines = cuisines.filter { $0.preferenceType == "like" }.map { $0.cuisineName }
            dislikedCuisines = cuisines.filter { $0.preferenceType == "dislike" }.map { $0.cuisineName }
            
            // Fetch dietary restrictions
            let restrictions: [DietaryRestrictionDTO] = try await SupabaseManager.shared.supabaseClient
                .from("user_dietary_restrictions")
                .select()
                .eq("user_id", value: userId.uuidString)
                .execute()
                .value
            
            dietaryRestrictions = Set(restrictions.compactMap { DietaryRestriction(rawValue: $0.restrictionType) })
            allergies = Set(restrictions.filter { $0.isAllergy }.compactMap { DietaryRestriction(rawValue: $0.restrictionType) })
            
            // Fetch preferences summary for macro preferences
            let summaries: [PreferencesSummaryDTO] = try await SupabaseManager.shared.supabaseClient
                .from("user_recipe_preferences_summary")
                .select()
                .eq("user_id", value: userId.uuidString)
                .execute()
                .value
            
            if let summary = summaries.first {
                prefersHighProtein = summary.prefersHighProtein ?? false
                prefersLowCarb = summary.prefersLowCarb ?? false
                prefersLowCalorie = summary.prefersLowCalorie ?? false
            }
            
            // Fetch popular ingredients
            let popIngredients: [PopularIngredientDTO] = try await SupabaseManager.shared.supabaseClient
                .from("popular_ingredients")
                .select()
                .order("name")
                .execute()
                .value
            
            popularIngredients = popIngredients.map { 
                PopularIngredient(
                    name: $0.name, 
                    category: IngredientCategory(rawValue: $0.category) ?? .other, 
                    emoji: $0.emoji ?? "🍴"
                )
            }
            
            // Fetch popular cuisines
            let popCuisines: [PopularCuisineDTO] = try await SupabaseManager.shared.supabaseClient
                .from("popular_cuisines")
                .select()
                .order("name")
                .execute()
                .value
            
            popularCuisines = popCuisines.map {
                PopularCuisine(name: $0.name, emoji: $0.emoji ?? "🍽️", apiValue: $0.apiValue)
            }
            
            print("✅ [RECIPE PREFS] Loaded from cloud: \(likedIngredients.count) likes, \(dislikedIngredients.count) dislikes")
            
        } catch {
            print("⚠️ [RECIPE PREFS] Failed to load from cloud: \(error)")
            loadLocalPreferences()
            loadDefaultPopularItems()
        }
        
        // Fill in defaults if empty
        if popularIngredients.isEmpty {
            loadDefaultPopularItems()
        }
        
        isLoading = false
    }
    
    private func loadLocalPreferences() {
        likedIngredients = UserDefaults.standard.stringArray(forKey: "recipeLikedIngredients") ?? []
        dislikedIngredients = UserDefaults.standard.stringArray(forKey: "recipeDislikedIngredients") ?? []
        likedCuisines = UserDefaults.standard.stringArray(forKey: "recipeLikedCuisines") ?? []
        dislikedCuisines = UserDefaults.standard.stringArray(forKey: "recipeDislikedCuisines") ?? []
        prefersHighProtein = UserDefaults.standard.bool(forKey: "recipePrefersHighProtein")
        prefersLowCarb = UserDefaults.standard.bool(forKey: "recipePrefersLowCarb")
        prefersLowCalorie = UserDefaults.standard.bool(forKey: "recipePrefersLowCalorie")
        
        let restrictionStrings = UserDefaults.standard.stringArray(forKey: "recipeDietaryRestrictions") ?? []
        dietaryRestrictions = Set(restrictionStrings.compactMap { DietaryRestriction(rawValue: $0) })
        
        let allergyStrings = UserDefaults.standard.stringArray(forKey: "recipeAllergies") ?? []
        allergies = Set(allergyStrings.compactMap { DietaryRestriction(rawValue: $0) })
    }
    
    private func saveLocalPreferences() {
        UserDefaults.standard.set(likedIngredients, forKey: "recipeLikedIngredients")
        UserDefaults.standard.set(dislikedIngredients, forKey: "recipeDislikedIngredients")
        UserDefaults.standard.set(likedCuisines, forKey: "recipeLikedCuisines")
        UserDefaults.standard.set(dislikedCuisines, forKey: "recipeDislikedCuisines")
        UserDefaults.standard.set(prefersHighProtein, forKey: "recipePrefersHighProtein")
        UserDefaults.standard.set(prefersLowCarb, forKey: "recipePrefersLowCarb")
        UserDefaults.standard.set(prefersLowCalorie, forKey: "recipePrefersLowCalorie")
        UserDefaults.standard.set(dietaryRestrictions.map { $0.rawValue }, forKey: "recipeDietaryRestrictions")
        UserDefaults.standard.set(allergies.map { $0.rawValue }, forKey: "recipeAllergies")
    }
    
    private func loadDefaultPopularItems() {
        popularIngredients = [
            // Proteins
            PopularIngredient(name: "Chicken", category: .protein, emoji: "🍗"),
            PopularIngredient(name: "Salmon", category: .protein, emoji: "🐟"),
            PopularIngredient(name: "Beef", category: .protein, emoji: "🥩"),
            PopularIngredient(name: "Turkey", category: .protein, emoji: "🦃"),
            PopularIngredient(name: "Eggs", category: .protein, emoji: "🥚"),
            PopularIngredient(name: "Shrimp", category: .protein, emoji: "🦐"),
            PopularIngredient(name: "Tofu", category: .protein, emoji: "🧈"),
            PopularIngredient(name: "Greek Yogurt", category: .protein, emoji: "🥛"),
            // Vegetables
            PopularIngredient(name: "Broccoli", category: .vegetable, emoji: "🥦"),
            PopularIngredient(name: "Spinach", category: .vegetable, emoji: "🥬"),
            PopularIngredient(name: "Avocado", category: .vegetable, emoji: "🥑"),
            PopularIngredient(name: "Sweet Potato", category: .vegetable, emoji: "🍠"),
            PopularIngredient(name: "Tomatoes", category: .vegetable, emoji: "🍅"),
            PopularIngredient(name: "Bell Peppers", category: .vegetable, emoji: "🫑"),
            PopularIngredient(name: "Mushrooms", category: .vegetable, emoji: "🍄"),
            PopularIngredient(name: "Asparagus", category: .vegetable, emoji: "🌿"),
            // Fruits
            PopularIngredient(name: "Banana", category: .fruit, emoji: "🍌"),
            PopularIngredient(name: "Blueberries", category: .fruit, emoji: "🫐"),
            PopularIngredient(name: "Strawberries", category: .fruit, emoji: "🍓"),
            PopularIngredient(name: "Apple", category: .fruit, emoji: "🍎"),
            PopularIngredient(name: "Mango", category: .fruit, emoji: "🥭"),
            // Grains
            PopularIngredient(name: "Rice", category: .grain, emoji: "🍚"),
            PopularIngredient(name: "Quinoa", category: .grain, emoji: "🌾"),
            PopularIngredient(name: "Oats", category: .grain, emoji: "🥣"),
            PopularIngredient(name: "Pasta", category: .grain, emoji: "🍝"),
            // Other
            PopularIngredient(name: "Almonds", category: .other, emoji: "🥜"),
            PopularIngredient(name: "Cheese", category: .other, emoji: "🧀"),
            PopularIngredient(name: "Olive Oil", category: .other, emoji: "🫒"),
        ]
        
        popularCuisines = [
            PopularCuisine(name: "Italian", emoji: "🇮🇹", apiValue: "italian"),
            PopularCuisine(name: "Mexican", emoji: "🇲🇽", apiValue: "mexican"),
            PopularCuisine(name: "Chinese", emoji: "🇨🇳", apiValue: "chinese"),
            PopularCuisine(name: "Japanese", emoji: "🇯🇵", apiValue: "japanese"),
            PopularCuisine(name: "Indian", emoji: "🇮🇳", apiValue: "indian"),
            PopularCuisine(name: "Thai", emoji: "🇹🇭", apiValue: "thai"),
            PopularCuisine(name: "Mediterranean", emoji: "🫒", apiValue: "mediterranean"),
            PopularCuisine(name: "American", emoji: "🇺🇸", apiValue: "american"),
            PopularCuisine(name: "Greek", emoji: "🇬🇷", apiValue: "greek"),
            PopularCuisine(name: "Korean", emoji: "🇰🇷", apiValue: "korean"),
        ]
    }
    
    // MARK: - Ingredient Actions
    func addIngredient(_ name: String, type: PreferenceType) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        // Remove from opposite list if present
        if type == .like {
            dislikedIngredients.removeAll { $0.lowercased() == trimmed.lowercased() }
            if !likedIngredients.contains(where: { $0.lowercased() == trimmed.lowercased() }) {
                likedIngredients.append(trimmed)
            }
        } else {
            likedIngredients.removeAll { $0.lowercased() == trimmed.lowercased() }
            if !dislikedIngredients.contains(where: { $0.lowercased() == trimmed.lowercased() }) {
                dislikedIngredients.append(trimmed)
            }
        }
        
        saveLocalPreferences()
        await saveToCloud(ingredient: trimmed, type: type)
        
        // Update RecipePreferenceService and trigger refresh
        RecipePreferenceService.shared.updateExplicitPreferences(
            liked: likedIngredients,
            disliked: dislikedIngredients
        )
        
        // Force refresh recommendations with new preferences
        await RecipePreferenceService.shared.forceRefreshRecommendations()
        
        print("✅ [PREFS] Added \(trimmed) to \(type.rawValue)s - refreshing recommendations")
    }
    
    func removeIngredient(_ name: String, type: PreferenceType) async {
        if type == .like {
            likedIngredients.removeAll { $0.lowercased() == name.lowercased() }
        } else {
            dislikedIngredients.removeAll { $0.lowercased() == name.lowercased() }
        }
        
        saveLocalPreferences()
        await removeFromCloud(ingredient: name, type: type)
        
        RecipePreferenceService.shared.updateExplicitPreferences(
            liked: likedIngredients,
            disliked: dislikedIngredients
        )
        
        // Force refresh recommendations
        await RecipePreferenceService.shared.forceRefreshRecommendations()
        
        print("✅ [PREFS] Removed \(name) from \(type.rawValue)s - refreshing recommendations")
    }
    
    private func saveToCloud(ingredient: String, type: PreferenceType) async {
        guard let userId = SupabaseManager.shared.currentUser?.id else { return }
        
        let insert = IngredientPreferenceInsert(
            userId: userId.uuidString,
            ingredientName: ingredient,
            ingredientNormalized: ingredient.lowercased(),
            preferenceType: type.rawValue
        )
        
        do {
            // First delete any existing preference for this ingredient
            try await SupabaseManager.shared.supabaseClient
                .from("user_ingredient_preferences")
                .delete()
                .eq("user_id", value: userId.uuidString)
                .eq("ingredient_normalized", value: ingredient.lowercased())
                .execute()
            
            // Then insert the new preference
            try await SupabaseManager.shared.supabaseClient
                .from("user_ingredient_preferences")
                .insert(insert)
                .execute()
            
            print("✅ [RECIPE PREFS] Saved to cloud: \(ingredient) = \(type.rawValue)")
        } catch {
            print("⚠️ [RECIPE PREFS] Failed to save: \(error)")
        }
    }
    
    private func removeFromCloud(ingredient: String, type: PreferenceType) async {
        guard let userId = SupabaseManager.shared.currentUser?.id else { return }
        
        do {
            try await SupabaseManager.shared.supabaseClient
                .from("user_ingredient_preferences")
                .delete()
                .eq("user_id", value: userId.uuidString)
                .eq("ingredient_normalized", value: ingredient.lowercased())
                .eq("preference_type", value: type.rawValue)
                .execute()
            
            print("✅ [RECIPE PREFS] Removed from cloud: \(ingredient)")
        } catch {
            print("⚠️ [RECIPE PREFS] Failed to remove: \(error)")
        }
    }
    
    // MARK: - Cuisine Actions
    func toggleCuisine(_ name: String) async {
        if likedCuisines.contains(name) {
            likedCuisines.removeAll { $0 == name }
            await removeCuisineFromCloud(name)
        } else {
            dislikedCuisines.removeAll { $0 == name }
            likedCuisines.append(name)
            await saveCuisineToCloud(name, type: .like)
        }
        saveLocalPreferences()
    }
    
    func dislikeCuisine(_ name: String) async {
        likedCuisines.removeAll { $0 == name }
        if dislikedCuisines.contains(name) {
            dislikedCuisines.removeAll { $0 == name }
            await removeCuisineFromCloud(name)
        } else {
            dislikedCuisines.append(name)
            await saveCuisineToCloud(name, type: .dislike)
        }
        saveLocalPreferences()
    }
    
    private func saveCuisineToCloud(_ name: String, type: PreferenceType) async {
        guard let userId = SupabaseManager.shared.currentUser?.id else { return }
        
        let insert = CuisinePreferenceInsert(
            userId: userId.uuidString,
            cuisineName: name,
            preferenceType: type.rawValue
        )
        
        do {
            try await SupabaseManager.shared.supabaseClient
                .from("user_cuisine_preferences")
                .delete()
                .eq("user_id", value: userId.uuidString)
                .eq("cuisine_name", value: name)
                .execute()
            
            try await SupabaseManager.shared.supabaseClient
                .from("user_cuisine_preferences")
                .insert(insert)
                .execute()
        } catch {
            print("⚠️ [RECIPE PREFS] Failed to save cuisine: \(error)")
        }
    }
    
    private func removeCuisineFromCloud(_ name: String) async {
        guard let userId = SupabaseManager.shared.currentUser?.id else { return }
        
        do {
            try await SupabaseManager.shared.supabaseClient
                .from("user_cuisine_preferences")
                .delete()
                .eq("user_id", value: userId.uuidString)
                .eq("cuisine_name", value: name)
                .execute()
        } catch {
            print("⚠️ [RECIPE PREFS] Failed to remove cuisine: \(error)")
        }
    }
    
    // MARK: - Dietary Restriction Actions
    func toggleDietaryRestriction(_ restriction: DietaryRestriction) async {
        if dietaryRestrictions.contains(restriction) {
            dietaryRestrictions.remove(restriction)
            allergies.remove(restriction)
            await removeDietaryFromCloud(restriction)
        } else {
            dietaryRestrictions.insert(restriction)
            await saveDietaryToCloud(restriction, isAllergy: false)
        }
        saveLocalPreferences()
    }
    
    func toggleAllergy(_ restriction: DietaryRestriction) async {
        if allergies.contains(restriction) {
            allergies.remove(restriction)
            await saveDietaryToCloud(restriction, isAllergy: false)
        } else {
            dietaryRestrictions.insert(restriction)
            allergies.insert(restriction)
            await saveDietaryToCloud(restriction, isAllergy: true)
        }
        saveLocalPreferences()
    }
    
    private func saveDietaryToCloud(_ restriction: DietaryRestriction, isAllergy: Bool) async {
        guard let userId = SupabaseManager.shared.currentUser?.id else { return }
        
        let insert = DietaryRestrictionInsert(
            userId: userId.uuidString,
            restrictionType: restriction.rawValue,
            isAllergy: isAllergy
        )
        
        do {
            try await SupabaseManager.shared.supabaseClient
                .from("user_dietary_restrictions")
                .delete()
                .eq("user_id", value: userId.uuidString)
                .eq("restriction_type", value: restriction.rawValue)
                .execute()
            
            try await SupabaseManager.shared.supabaseClient
                .from("user_dietary_restrictions")
                .insert(insert)
                .execute()
        } catch {
            print("⚠️ [RECIPE PREFS] Failed to save dietary: \(error)")
        }
    }
    
    private func removeDietaryFromCloud(_ restriction: DietaryRestriction) async {
        guard let userId = SupabaseManager.shared.currentUser?.id else { return }
        
        do {
            try await SupabaseManager.shared.supabaseClient
                .from("user_dietary_restrictions")
                .delete()
                .eq("user_id", value: userId.uuidString)
                .eq("restriction_type", value: restriction.rawValue)
                .execute()
        } catch {
            print("⚠️ [RECIPE PREFS] Failed to remove dietary: \(error)")
        }
    }
    
    // MARK: - Recipe Preference Toggles
    func toggleHighProtein() async {
        prefersHighProtein.toggle()
        saveLocalPreferences()
        await updatePreferencesSummary()
    }
    
    func toggleLowCarb() async {
        prefersLowCarb.toggle()
        saveLocalPreferences()
        await updatePreferencesSummary()
    }
    
    func toggleLowCalorie() async {
        prefersLowCalorie.toggle()
        saveLocalPreferences()
        await updatePreferencesSummary()
    }
    
    private func updatePreferencesSummary() async {
        guard let userId = SupabaseManager.shared.currentUser?.id else { return }
        
        let update = PreferencesSummaryUpdate(
            userId: userId.uuidString,
            prefersHighProtein: prefersHighProtein,
            prefersLowCarb: prefersLowCarb,
            prefersLowCalorie: prefersLowCalorie
        )
        
        do {
            try await SupabaseManager.shared.supabaseClient
                .from("user_recipe_preferences_summary")
                .upsert(update)
                .execute()
        } catch {
            print("⚠️ [RECIPE PREFS] Failed to update summary: \(error)")
        }
    }
}

// MARK: - Supporting Types
enum PreferenceType: String {
    case like = "like"
    case dislike = "dislike"
}

enum IngredientCategory: String, CaseIterable {
    case protein = "protein"
    case vegetable = "vegetable"
    case fruit = "fruit"
    case grain = "grain"
    case other = "other"
    
    var displayName: String {
        switch self {
        case .protein: return "Protein"
        case .vegetable: return "Veggies"
        case .fruit: return "Fruit"
        case .grain: return "Grains"
        case .other: return "Other"
        }
    }
    
    var emoji: String {
        switch self {
        case .protein: return "🥩"
        case .vegetable: return "🥦"
        case .fruit: return "🍎"
        case .grain: return "🌾"
        case .other: return "🥜"
        }
    }
}

enum DietaryRestriction: String, CaseIterable {
    case vegetarian = "vegetarian"
    case vegan = "vegan"
    case glutenFree = "gluten_free"
    case dairyFree = "dairy_free"
    case nutAllergy = "nut_allergy"
    case shellfishAllergy = "shellfish_allergy"
    case keto = "keto"
    case paleo = "paleo"
    
    var displayName: String {
        switch self {
        case .vegetarian: return "Vegetarian"
        case .vegan: return "Vegan"
        case .glutenFree: return "Gluten-Free"
        case .dairyFree: return "Dairy-Free"
        case .nutAllergy: return "Nut-Free"
        case .shellfishAllergy: return "Shellfish-Free"
        case .keto: return "Keto"
        case .paleo: return "Paleo"
        }
    }
    
    var emoji: String {
        switch self {
        case .vegetarian: return "🥬"
        case .vegan: return "🌱"
        case .glutenFree: return "🌾"
        case .dairyFree: return "🥛"
        case .nutAllergy: return "🥜"
        case .shellfishAllergy: return "🦐"
        case .keto: return "🥑"
        case .paleo: return "🍖"
        }
    }
}

struct PopularIngredient {
    let name: String
    let category: IngredientCategory
    let emoji: String
}

struct PopularCuisine {
    let name: String
    let emoji: String
    let apiValue: String
}

// MARK: - DTOs
struct IngredientPreferenceDTO: Codable {
    let id: String
    let ingredientName: String
    let ingredientNormalized: String
    let preferenceType: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case ingredientName = "ingredient_name"
        case ingredientNormalized = "ingredient_normalized"
        case preferenceType = "preference_type"
    }
}

struct IngredientPreferenceInsert: Codable {
    let userId: String
    let ingredientName: String
    let ingredientNormalized: String
    let preferenceType: String
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case ingredientName = "ingredient_name"
        case ingredientNormalized = "ingredient_normalized"
        case preferenceType = "preference_type"
    }
}

struct CuisinePreferenceDTO: Codable {
    let id: String
    let cuisineName: String
    let preferenceType: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case cuisineName = "cuisine_name"
        case preferenceType = "preference_type"
    }
}

struct CuisinePreferenceInsert: Codable {
    let userId: String
    let cuisineName: String
    let preferenceType: String
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case cuisineName = "cuisine_name"
        case preferenceType = "preference_type"
    }
}

struct DietaryRestrictionDTO: Codable {
    let id: String
    let restrictionType: String
    let isAllergy: Bool
    
    enum CodingKeys: String, CodingKey {
        case id
        case restrictionType = "restriction_type"
        case isAllergy = "is_allergy"
    }
}

struct DietaryRestrictionInsert: Codable {
    let userId: String
    let restrictionType: String
    let isAllergy: Bool
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case restrictionType = "restriction_type"
        case isAllergy = "is_allergy"
    }
}

struct PreferencesSummaryDTO: Codable {
    let prefersHighProtein: Bool?
    let prefersLowCarb: Bool?
    let prefersLowCalorie: Bool?
    
    enum CodingKeys: String, CodingKey {
        case prefersHighProtein = "prefers_high_protein"
        case prefersLowCarb = "prefers_low_carb"
        case prefersLowCalorie = "prefers_low_calorie"
    }
}

struct PreferencesSummaryUpdate: Codable {
    let userId: String
    let prefersHighProtein: Bool
    let prefersLowCarb: Bool
    let prefersLowCalorie: Bool
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case prefersHighProtein = "prefers_high_protein"
        case prefersLowCarb = "prefers_low_carb"
        case prefersLowCalorie = "prefers_low_calorie"
    }
}

struct PopularIngredientDTO: Codable {
    let id: Int
    let name: String
    let category: String
    let emoji: String?
}

struct PopularCuisineDTO: Codable {
    let id: Int
    let name: String
    let emoji: String?
    let apiValue: String
    
    enum CodingKeys: String, CodingKey {
        case id, name, emoji
        case apiValue = "api_value"
    }
}

// MARK: - UI Components

struct PreferenceTabButton: View {
    let title: String
    let icon: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .foregroundColor(isSelected ? .white : color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? color : Color.clear)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct IngredientChip: View {
    let name: String
    let color: Color
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 6) {
            Text(name)
                .font(.subheadline)
                .fontWeight(.medium)
            
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(color.opacity(0.7))
            }
        }
        .foregroundColor(color)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(color.opacity(0.15))
        )
        .overlay(
            Capsule()
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
    }
}

struct CategoryPill: View {
    let category: IngredientCategory
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(category.emoji)
                    .font(.caption)
                Text(category.displayName)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .foregroundColor(isSelected ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? Color.orange : Color.gray.opacity(0.15))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct PopularIngredientButton: View {
    let ingredient: PopularIngredient
    let isLiked: Bool
    let isDisliked: Bool
    let onLike: () -> Void
    let onDislike: () -> Void
    let onRemove: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button {
            if isLiked || isDisliked {
                onRemove()
            } else {
                onLike()
            }
        } label: {
            VStack(spacing: 6) {
                Text(ingredient.emoji)
                    .font(.title2)
                
                Text(ingredient.name)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(borderColor, lineWidth: isLiked || isDisliked ? 2 : 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            Button {
                onLike()
            } label: {
                Label("Add to Favorites", systemImage: "heart.fill")
            }
            
            Button {
                onDislike()
            } label: {
                Label("Add to Avoid", systemImage: "xmark.circle.fill")
            }
        }
    }
    
    private var backgroundColor: Color {
        if isLiked {
            return Color.green.opacity(0.15)
        } else if isDisliked {
            return Color.red.opacity(0.15)
        }
        return colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.97)
    }
    
    private var borderColor: Color {
        if isLiked {
            return .green
        } else if isDisliked {
            return .red
        }
        return Color.gray.opacity(0.2)
    }
}

struct CuisineChip: View {
    let cuisine: PopularCuisine
    let isLiked: Bool
    let isDisliked: Bool
    let onTap: () -> Void
    let onDoubleTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Text(cuisine.emoji)
                    .font(.caption)
                Text(cuisine.name)
                    .font(.subheadline)
                    .fontWeight(isLiked ? .semibold : .regular)
                
                if isLiked {
                    Image(systemName: "heart.fill")
                        .font(.caption2)
                        .foregroundColor(.green)
                } else if isDisliked {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption2)
                        .foregroundColor(.red)
                }
            }
            .foregroundColor(foregroundColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(backgroundColor)
            )
            .overlay(
                Capsule()
                    .stroke(borderColor, lineWidth: isLiked || isDisliked ? 2 : 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded { _ in
                    onDoubleTap()
                }
        )
    }
    
    private var foregroundColor: Color {
        if isLiked { return .green }
        if isDisliked { return .red }
        return .primary
    }
    
    private var backgroundColor: Color {
        if isLiked { return Color.green.opacity(0.15) }
        if isDisliked { return Color.red.opacity(0.15) }
        return Color.gray.opacity(0.1)
    }
    
    private var borderColor: Color {
        if isLiked { return .green }
        if isDisliked { return .red }
        return Color.gray.opacity(0.2)
    }
}

struct DietaryToggle: View {
    let restriction: DietaryRestriction
    let isEnabled: Bool
    let isAllergy: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Text(restriction.emoji)
                    .font(.body)
                
                Text(restriction.displayName)
                    .font(.subheadline)
                    .fontWeight(isEnabled ? .semibold : .regular)
                
                Spacer()
                
                if isAllergy {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                } else if isEnabled {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
            .foregroundColor(isEnabled ? (isAllergy ? .red : .green) : .primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(borderColor, lineWidth: isEnabled ? 2 : 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture {
            onLongPress()
        }
    }
    
    private var backgroundColor: Color {
        if isAllergy { return Color.red.opacity(0.15) }
        if isEnabled { return Color.green.opacity(0.15) }
        return colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.97)
    }
    
    private var borderColor: Color {
        if isAllergy { return .red }
        if isEnabled { return .green }
        return Color.gray.opacity(0.2)
    }
}

struct PreferenceToggleRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let isEnabled: Bool
    let onToggle: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(isEnabled ? color : Color.gray.opacity(0.2))
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(isEnabled ? .white : .secondary)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(isEnabled ? color : .gray.opacity(0.3))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isEnabled ? color.opacity(0.1) : (colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.97)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isEnabled ? color.opacity(0.3) : Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Note: Uses FlowLayout from WorkoutInsightsView.swift

// MARK: - Preview
#Preview {
    RecipePreferencesView()
}
