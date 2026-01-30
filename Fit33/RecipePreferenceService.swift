import Foundation
import Combine

// MARK: - Recipe Preference Service
/// Tracks user food preferences and provides personalized recipe recommendations
/// Uses local storage for immediate recommendations with optional cloud sync
@MainActor
class RecipePreferenceService: ObservableObject {
    static let shared = RecipePreferenceService()
    
    // MARK: - Published Properties
    @Published var personalizedRecipes: [SpoonacularRecipe] = []
    @Published var isLoadingRecommendations = false
    @Published var userTasteProfile: UserTasteProfile?
    
    // MARK: - Private Properties
    private let apiKey = AppConfig.spoonacularApiKey
    private let baseURL = "https://api.spoonacular.com"
    
    // Carousel rotation timing
    private var lastCarouselRefresh: Date?
    private let carouselRefreshInterval: TimeInterval = 4 * 60 * 60 // 4 hours
    private var shownRecipeIds: Set<Int> = []
    
    // Local preference tracking
    private var ingredientCounts: [String: Int] = [:]
    private var cuisinePreferences: [String: Int] = [:]
    private var searchHistory: [String] = []
    private var addedFoods: [String] = []
    
    // Stats
    private var totalRecipesViewed: Int = 0
    private var totalRecipesAdded: Int = 0
    private var totalRecipesFavorited: Int = 0
    
    private init() {
        loadLocalPreferences()
    }
    
    // MARK: - Track User Interactions
    
    /// Track when user views a recipe
    func trackRecipeView(recipe: SpoonacularRecipe) {
        totalRecipesViewed += 1
        saveLocalPreferences()
        print("👁️ [RECIPE PREFS] Tracked view: \(recipe.title)")
    }
    
    /// Track when user views recipe detail
    func trackRecipeDetailView(recipe: RecipeDetail) {
        totalRecipesViewed += 1
        
        // Track cuisine preferences from viewed recipes
        if let cuisines = recipe.cuisines {
            for cuisine in cuisines {
                trackCuisinePreference(cuisine, weight: 1)
            }
        }
        
        saveLocalPreferences()
        print("👁️ [RECIPE PREFS] Tracked detail view: \(recipe.title)")
    }
    
    /// Track when user adds a recipe to their meals
    func trackRecipeAddedToMeal(recipe: RecipeDetail, mealType: MealType, servings: Int) {
        totalRecipesAdded += 1
        
        // Extract and track ingredients (higher weight for meals added)
        if let ingredients = recipe.extendedIngredients {
            for ingredient in ingredients {
                trackIngredient(ingredient.name, weight: 2)
            }
        }
        
        // Track cuisines with higher weight for additions
        if let cuisines = recipe.cuisines {
            for cuisine in cuisines {
                trackCuisinePreference(cuisine, weight: 3)
            }
        }
        
        // Add to added foods list
        addedFoods.append(recipe.title)
        if addedFoods.count > 100 { // Keep last 100
            addedFoods.removeFirst()
        }
        
        saveLocalPreferences()
        print("✅ [RECIPE PREFS] Tracked meal addition: \(recipe.title) to \(mealType.displayName)")
    }
    
    /// Track when user favorites a recipe
    func trackRecipeFavorited(recipeId: Int, recipeTitle: String, isFavorite: Bool) {
        if isFavorite {
            totalRecipesFavorited += 1
        } else {
            totalRecipesFavorited = max(0, totalRecipesFavorited - 1)
        }
        saveLocalPreferences()
        print("⭐ [RECIPE PREFS] Tracked favorite: \(recipeTitle) = \(isFavorite)")
    }
    
    /// Track when user searches for a food
    func trackFoodSearch(query: String) {
        let normalized = normalizeIngredient(query)
        ingredientCounts[normalized, default: 0] += 1
        
        // Add to search history
        searchHistory.append(query)
        if searchHistory.count > 50 { // Keep last 50 searches
            searchHistory.removeFirst()
        }
        
        saveLocalPreferences()
        print("🔍 [RECIPE PREFS] Tracked search: \(query) → \(normalized)")
    }
    
    /// Track when user adds a food manually (not from recipe)
    func trackFoodAdded(foodName: String, calories: Int, protein: Int) {
        let normalized = normalizeIngredient(foodName)
        ingredientCounts[normalized, default: 0] += 2 // Higher weight for additions
        
        addedFoods.append(foodName)
        if addedFoods.count > 100 {
            addedFoods.removeFirst()
        }
        
        saveLocalPreferences()
        print("➕ [RECIPE PREFS] Tracked food addition: \(foodName) → \(normalized)")
    }
    
    // MARK: - Get Personalized Recommendations
    
    /// Get recipes based on user's preferred ingredients
    func getPersonalizedRecipes(count: Int = 10) async -> [SpoonacularRecipe] {
        isLoadingRecommendations = true
        
        // Get top ingredients
        let topIngredients = getTopIngredients(limit: 5)
        
        var recipes: [SpoonacularRecipe] = []
        
        if !topIngredients.isEmpty {
            // Search by preferred ingredients
            let ingredientsQuery = topIngredients.joined(separator: ",+")
            recipes = await fetchRecipesByIngredients(ingredients: ingredientsQuery, count: count)
            print("🍽️ [RECIPE PREFS] Got \(recipes.count) recipes for ingredients: \(topIngredients)")
        }
        
        // If not enough personalized results, supplement with healthy defaults
        if recipes.count < count {
            let additionalRecipes = await fetchHealthyRecipes(
                count: count - recipes.count,
                excludeIds: recipes.map { $0.id }
            )
            recipes.append(contentsOf: additionalRecipes)
        }
        
        // Filter out recently shown recipes
        recipes = recipes.filter { !shownRecipeIds.contains($0.id) }
        
        // Mark as shown
        for recipe in recipes {
            shownRecipeIds.insert(recipe.id)
        }
        
        isLoadingRecommendations = false
        personalizedRecipes = recipes
        
        return recipes
    }
    
    /// Check if carousel should refresh (every 4 hours)
    func shouldRefreshCarousel() -> Bool {
        guard let lastRefresh = lastCarouselRefresh else {
            return true
        }
        
        let timeSinceRefresh = Date().timeIntervalSince(lastRefresh)
        return timeSinceRefresh >= carouselRefreshInterval
    }
    
    /// Get fresh recipes for carousel rotation
    func getRotatedCarouselRecipes(count: Int = 10) async -> [SpoonacularRecipe] {
        // Check if it's a new day - reset shown recipes
        if isNewDay() {
            shownRecipeIds.removeAll()
            saveCarouselState()
        }
        
        // Mark refresh time
        lastCarouselRefresh = Date()
        
        // Get personalized recommendations
        let recipes = await getPersonalizedRecipes(count: count)
        
        // Save state
        saveCarouselState()
        
        return recipes
    }
    
    /// Get time-based meal suggestions
    func getMealSuggestionsForCurrentTime(count: Int = 8) async -> [SpoonacularRecipe] {
        let hour = Calendar.current.component(.hour, from: Date())
        
        var mealType: String
        
        switch hour {
        case 5..<11:
            mealType = "breakfast"
        case 11..<15:
            mealType = "lunch"
        case 15..<18:
            mealType = "snack"
        default:
            mealType = "dinner"
        }
        
        // Combine with user preferences
        let topIngredients = getTopIngredients(limit: 3)
        
        return await fetchRecipesForMealTime(
            mealType: mealType,
            preferredIngredients: topIngredients,
            count: count
        )
    }
    
    // MARK: - Private Tracking Methods
    
    private func trackIngredient(_ name: String, weight: Int = 1) {
        let normalized = normalizeIngredient(name)
        ingredientCounts[normalized, default: 0] += weight
    }
    
    private func trackCuisinePreference(_ cuisine: String, weight: Int = 1) {
        cuisinePreferences[cuisine.lowercased(), default: 0] += weight
    }
    
    // MARK: - Private API Methods
    
    private func fetchRecipesByIngredients(ingredients: String, count: Int) async -> [SpoonacularRecipe] {
        guard let encodedIngredients = ingredients.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(baseURL)/recipes/findByIngredients?apiKey=\(apiKey)&ingredients=\(encodedIngredients)&number=\(count)&ranking=2&ignorePantry=true") else {
            return []
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return []
            }
            
            let decoder = JSONDecoder()
            let ingredientRecipes = try decoder.decode([IngredientSearchRecipe].self, from: data)
            
            return ingredientRecipes.map { recipe in
                SpoonacularRecipe(
                    id: recipe.id,
                    title: recipe.title,
                    image: recipe.image,
                    imageType: recipe.imageType,
                    nutrition: nil
                )
            }
        } catch {
            print("❌ [RECIPE PREFS] Error fetching by ingredients: \(error)")
            return []
        }
    }
    
    private func fetchHealthyRecipes(count: Int, excludeIds: [Int]) async -> [SpoonacularRecipe] {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "apiKey", value: apiKey),
            URLQueryItem(name: "number", value: String(count + excludeIds.count)),
            URLQueryItem(name: "addRecipeNutrition", value: "true"),
            URLQueryItem(name: "sort", value: "healthiness"),
            URLQueryItem(name: "sortDirection", value: "desc"),
            URLQueryItem(name: "minProtein", value: "20"),
            URLQueryItem(name: "query", value: "healthy protein")
        ]
        
        var urlComponents = URLComponents(string: "\(baseURL)/recipes/complexSearch")!
        urlComponents.queryItems = queryItems
        
        guard let url = urlComponents.url else { return [] }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return []
            }
            
            let decoder = JSONDecoder()
            let searchResponse = try decoder.decode(RecipeSearchResponse.self, from: data)
            
            return Array(searchResponse.results.filter { !excludeIds.contains($0.id) }.prefix(count))
        } catch {
            print("❌ [RECIPE PREFS] Error fetching healthy recipes: \(error)")
            return []
        }
    }
    
    private func fetchRecipesForMealTime(
        mealType: String,
        preferredIngredients: [String],
        count: Int
    ) async -> [SpoonacularRecipe] {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "apiKey", value: apiKey),
            URLQueryItem(name: "number", value: String(count)),
            URLQueryItem(name: "addRecipeNutrition", value: "true"),
            URLQueryItem(name: "type", value: mealType),
            URLQueryItem(name: "sort", value: "healthiness"),
            URLQueryItem(name: "minProtein", value: "15")
        ]
        
        // Add ingredient preferences if available
        if !preferredIngredients.isEmpty {
            queryItems.append(URLQueryItem(name: "includeIngredients", value: preferredIngredients.joined(separator: ",")))
        }
        
        var urlComponents = URLComponents(string: "\(baseURL)/recipes/complexSearch")!
        urlComponents.queryItems = queryItems
        
        guard let url = urlComponents.url else { return [] }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return []
            }
            
            let decoder = JSONDecoder()
            let searchResponse = try decoder.decode(RecipeSearchResponse.self, from: data)
            return searchResponse.results
        } catch {
            print("❌ [RECIPE PREFS] Error fetching meal-time recipes: \(error)")
            return []
        }
    }
    
    // MARK: - Local Preference Helpers
    
    private func normalizeIngredient(_ name: String) -> String {
        let lowered = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Common ingredient normalization
        if lowered.contains("chicken") { return "chicken" }
        if lowered.contains("salmon") || lowered.contains("fish") || lowered.contains("tuna") { return "fish" }
        if lowered.contains("beef") || lowered.contains("steak") { return "beef" }
        if lowered.contains("egg") { return "eggs" }
        if lowered.contains("rice") { return "rice" }
        if lowered.contains("pasta") || lowered.contains("noodle") { return "pasta" }
        if lowered.contains("broccoli") { return "broccoli" }
        if lowered.contains("spinach") { return "spinach" }
        if lowered.contains("avocado") { return "avocado" }
        if lowered.contains("oat") { return "oats" }
        if lowered.contains("yogurt") || lowered.contains("greek") { return "yogurt" }
        if lowered.contains("protein") || lowered.contains("shake") { return "protein" }
        if lowered.contains("turkey") { return "turkey" }
        if lowered.contains("shrimp") { return "shrimp" }
        if lowered.contains("tofu") { return "tofu" }
        if lowered.contains("banana") { return "banana" }
        if lowered.contains("apple") { return "apple" }
        if lowered.contains("almond") { return "almonds" }
        if lowered.contains("peanut") { return "peanuts" }
        
        // Return first word if nothing matches (e.g., "grilled chicken" → "grilled")
        // Actually return the whole thing for now
        return lowered
    }
    
    private func getTopIngredients(limit: Int) -> [String] {
        return ingredientCounts
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { $0.key }
    }
    
    private func getTopCuisines(limit: Int) -> [String] {
        return cuisinePreferences
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { $0.key }
    }
    
    // MARK: - Persistence
    
    private func saveLocalPreferences() {
        UserDefaults.standard.set(ingredientCounts, forKey: "recipeIngredientPreferences")
        UserDefaults.standard.set(cuisinePreferences, forKey: "recipeCuisinePreferences")
        UserDefaults.standard.set(searchHistory, forKey: "recipeSearchHistory")
        UserDefaults.standard.set(addedFoods, forKey: "recipeAddedFoods")
        UserDefaults.standard.set(totalRecipesViewed, forKey: "recipeTotalViewed")
        UserDefaults.standard.set(totalRecipesAdded, forKey: "recipeTotalAdded")
        UserDefaults.standard.set(totalRecipesFavorited, forKey: "recipeTotalFavorited")
    }
    
    private func loadLocalPreferences() {
        ingredientCounts = UserDefaults.standard.dictionary(forKey: "recipeIngredientPreferences") as? [String: Int] ?? [:]
        cuisinePreferences = UserDefaults.standard.dictionary(forKey: "recipeCuisinePreferences") as? [String: Int] ?? [:]
        searchHistory = UserDefaults.standard.stringArray(forKey: "recipeSearchHistory") ?? []
        addedFoods = UserDefaults.standard.stringArray(forKey: "recipeAddedFoods") ?? []
        totalRecipesViewed = UserDefaults.standard.integer(forKey: "recipeTotalViewed")
        totalRecipesAdded = UserDefaults.standard.integer(forKey: "recipeTotalAdded")
        totalRecipesFavorited = UserDefaults.standard.integer(forKey: "recipeTotalFavorited")
        
        // Load carousel state
        if let data = UserDefaults.standard.data(forKey: "shownRecipeIds"),
           let ids = try? JSONDecoder().decode(Set<Int>.self, from: data) {
            shownRecipeIds = ids
        }
        
        if let lastRefresh = UserDefaults.standard.object(forKey: "lastCarouselRefresh") as? Date {
            lastCarouselRefresh = lastRefresh
        }
        
        print("📊 [RECIPE PREFS] Loaded preferences: \(ingredientCounts.count) ingredients, \(cuisinePreferences.count) cuisines")
    }
    
    private func saveCarouselState() {
        if let data = try? JSONEncoder().encode(shownRecipeIds) {
            UserDefaults.standard.set(data, forKey: "shownRecipeIds")
        }
        UserDefaults.standard.set(lastCarouselRefresh, forKey: "lastCarouselRefresh")
    }
    
    private func isNewDay() -> Bool {
        guard let lastRefresh = lastCarouselRefresh else { return true }
        return !Calendar.current.isDateInToday(lastRefresh)
    }
    
    /// Clear all local preferences (for testing/reset)
    func clearAllPreferences() {
        ingredientCounts.removeAll()
        cuisinePreferences.removeAll()
        searchHistory.removeAll()
        addedFoods.removeAll()
        shownRecipeIds.removeAll()
        lastCarouselRefresh = nil
        totalRecipesViewed = 0
        totalRecipesAdded = 0
        totalRecipesFavorited = 0
        
        UserDefaults.standard.removeObject(forKey: "recipeIngredientPreferences")
        UserDefaults.standard.removeObject(forKey: "recipeCuisinePreferences")
        UserDefaults.standard.removeObject(forKey: "recipeSearchHistory")
        UserDefaults.standard.removeObject(forKey: "recipeAddedFoods")
        UserDefaults.standard.removeObject(forKey: "shownRecipeIds")
        UserDefaults.standard.removeObject(forKey: "lastCarouselRefresh")
        UserDefaults.standard.removeObject(forKey: "recipeTotalViewed")
        UserDefaults.standard.removeObject(forKey: "recipeTotalAdded")
        UserDefaults.standard.removeObject(forKey: "recipeTotalFavorited")
        
        print("🗑️ [RECIPE PREFS] All preferences cleared")
    }
    
    /// Get current preference stats for debugging
    func getPreferenceStats() -> String {
        let topIngredients = getTopIngredients(limit: 5)
        let topCuisines = getTopCuisines(limit: 3)
        
        return """
        📊 Recipe Preferences:
        - Top Ingredients: \(topIngredients.joined(separator: ", "))
        - Top Cuisines: \(topCuisines.joined(separator: ", "))
        - Recipes Viewed: \(totalRecipesViewed)
        - Recipes Added: \(totalRecipesAdded)
        - Recipes Favorited: \(totalRecipesFavorited)
        - Search History: \(searchHistory.suffix(5).joined(separator: ", "))
        """
    }
}

// MARK: - User Taste Profile Model
struct UserTasteProfile: Codable {
    let userId: String
    let preferredIngredients: [String]
    let preferredCuisines: [String]
    let prefersHighProtein: Bool
    let prefersLowCarb: Bool
    let prefersLowCalorie: Bool
    let avgCaloriesPerMeal: Int?
    let avgProteinPerMeal: Int?
    let totalRecipesViewed: Int
    let totalRecipesAdded: Int
    let totalRecipesFavorited: Int
}
