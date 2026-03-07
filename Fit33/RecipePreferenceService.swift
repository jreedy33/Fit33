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
    @Published var hasPreferencesSet: Bool = false
    
    // MARK: - Private Properties
    private let apiKey = AppConfig.spoonacularApiKey
    private let baseURL = "https://api.spoonacular.com"
    
    // Carousel rotation timing - FASTER refresh for more variety
    private var lastCarouselRefresh: Date?
    private let carouselRefreshInterval: TimeInterval = 1 * 60 * 60 // 1 hour (was 4 hours)
    private var shownRecipeIds: Set<Int> = []
    private var dailyRecipePool: [SpoonacularRecipe] = [] // Cache more recipes
    
    // EXPLICIT User Preferences (new!)
    private var likedIngredients: [String] = []
    private var dislikedIngredients: [String] = []
    
    // Local preference tracking (implicit - from behavior)
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
        hasPreferencesSet = !likedIngredients.isEmpty || !dislikedIngredients.isEmpty
        
        // Sync from cloud in background and learn from food history
        Task {
            await syncPreferencesFromCloud()
            await learnFromFoodHistory()
        }
    }
    
    // MARK: - Learn From Food History (Auto-detect preferences)
    
    /// Analyze user's food logging history to automatically learn their ingredient preferences
    /// This powers the "smart" recipe recommendations based on what users actually eat
    func learnFromFoodHistory() async {
        guard SupabaseManager.shared.isAuthenticated else { return }
        
        let frequentFoods = FoodDatabaseService.shared.frequentFoods
        guard !frequentFoods.isEmpty else {
            print("📊 [RECIPE PREFS] No food history yet - using defaults")
            return
        }
        
        print("📊 [RECIPE PREFS] Learning from \(frequentFoods.count) frequently logged foods...")
        
        // Extract ingredient categories from user's most logged foods
        var detectedIngredients: [String: Int] = [:] // ingredient -> weight
        
        for food in frequentFoods {
            let foodName = food.name.lowercased()
            let weight = food.usageCount
            
            // Smart ingredient extraction from food names
            let ingredientMappings: [(keywords: [String], ingredient: String)] = [
                // Proteins
                (["chicken breast", "chicken thigh", "chicken wing", "chicken drumstick", "rotisserie chicken", "chicken, ground"], "chicken"),
                (["salmon", "smoked salmon"], "salmon"),
                (["tuna"], "tuna"),
                (["tilapia", "cod", "halibut", "mahi", "trout", "fish"], "fish"),
                (["shrimp", "prawn"], "shrimp"),
                (["ground beef", "steak", "sirloin", "ribeye", "filet", "brisket", "beef"], "beef"),
                (["turkey breast", "turkey, ground", "turkey bacon", "turkey sausage", "turkey"], "turkey"),
                (["pork tenderloin", "pork chop", "bacon", "ham", "pork"], "pork"),
                (["egg", "eggs"], "eggs"),
                (["tofu", "tempeh"], "tofu"),
                
                // Grains & Carbs
                (["rice", "white rice", "brown rice", "jasmine rice", "basmati"], "rice"),
                (["oatmeal", "oats", "overnight oats"], "oats"),
                (["quinoa"], "quinoa"),
                (["pasta", "spaghetti", "penne", "noodle"], "pasta"),
                (["bread", "toast", "bagel", "english muffin"], "bread"),
                (["sweet potato"], "sweet potato"),
                (["potato"], "potato"),
                
                // Dairy
                (["greek yogurt", "yogurt"], "yogurt"),
                (["cottage cheese"], "cottage cheese"),
                (["cheese", "cheddar", "mozzarella", "parmesan"], "cheese"),
                (["milk"], "milk"),
                
                // Vegetables
                (["broccoli"], "broccoli"),
                (["spinach"], "spinach"),
                (["avocado"], "avocado"),
                (["bell pepper", "pepper"], "bell pepper"),
                (["asparagus"], "asparagus"),
                
                // Fruits
                (["banana"], "banana"),
                (["apple"], "apple"),
                (["berries", "blueberries", "strawberries", "raspberries"], "berries"),
                
                // Nuts & Seeds
                (["almonds", "almond butter"], "almonds"),
                (["peanut butter", "peanuts"], "peanut butter"),
                
                // Supplements
                (["protein powder", "whey", "protein shake"], "protein"),
            ]
            
            for mapping in ingredientMappings {
                if mapping.keywords.contains(where: { foodName.contains($0) }) {
                    detectedIngredients[mapping.ingredient, default: 0] += weight
                    break // Only match first category per food
                }
            }
        }
        
        // Sort by weight (most logged ingredients first)
        let sortedIngredients = detectedIngredients.sorted { $0.value > $1.value }
        let topIngredients = sortedIngredients.prefix(8).map { $0.key }
        
        if !topIngredients.isEmpty {
            // Merge detected preferences with implicit tracking
            for (ingredient, weight) in sortedIngredients {
                ingredientCounts[ingredient, default: 0] += weight * 3 // Triple weight for actual logged foods
            }
            
            // If user has no explicit likes set, auto-set from history
            if likedIngredients.isEmpty {
                // Use top 5 as auto-detected likes
                let autoLikes = Array(topIngredients.prefix(5))
                likedIngredients = autoLikes
                hasPreferencesSet = true
                saveLocalPreferences()
                
                print("🧠 [RECIPE PREFS] Auto-detected preferences from food history:")
                for (i, ingredient) in autoLikes.enumerated() {
                    let weight = detectedIngredients[ingredient] ?? 0
                    print("  \(i+1). \(ingredient) (logged \(weight)x)")
                }
            } else {
                // Boost existing likes with food history data
                saveLocalPreferences()
                print("🧠 [RECIPE PREFS] Boosted existing preferences with food history data")
            }
        }
    }
    
    // MARK: - Cloud Sync
    /// Sync preferences from Supabase cloud (called on app launch)
    func syncPreferencesFromCloud() async {
        guard let userId = SupabaseManager.shared.currentUser?.id else {
            print("📂 [RECIPE PREFS] No user logged in, using local preferences")
            return
        }
        
        do {
            // Fetch ingredient preferences from cloud
            let ingredients: [CloudIngredientPreference] = try await SupabaseManager.shared.supabaseClient
                .from("user_ingredient_preferences")
                .select()
                .eq("user_id", value: userId.uuidString)
                .execute()
                .value
            
            // Update local state
            likedIngredients = ingredients
                .filter { $0.preferenceType == "like" }
                .map { $0.ingredientName }
            dislikedIngredients = ingredients
                .filter { $0.preferenceType == "dislike" }
                .map { $0.ingredientName }
            
            hasPreferencesSet = !likedIngredients.isEmpty || !dislikedIngredients.isEmpty
            
            // Save to local cache
            UserDefaults.standard.set(likedIngredients, forKey: "recipeLikedIngredients")
            UserDefaults.standard.set(dislikedIngredients, forKey: "recipeDislikedIngredients")
            
            print("☁️ [RECIPE PREFS] Synced from cloud: \(likedIngredients.count) likes, \(dislikedIngredients.count) dislikes")
            
        } catch {
            print("⚠️ [RECIPE PREFS] Cloud sync failed: \(error)")
            // Keep using local preferences
        }
    }
    
    // MARK: - Explicit Preference Management (New!)
    
    /// Get user's explicitly liked ingredients
    func getLikedIngredients() -> [String] {
        return likedIngredients
    }
    
    /// Get user's explicitly disliked ingredients
    func getDislikedIngredients() -> [String] {
        return dislikedIngredients
    }
    
    /// Set user's explicitly liked ingredients
    func setLikedIngredients(_ ingredients: [String]) {
        likedIngredients = ingredients
        hasPreferencesSet = !likedIngredients.isEmpty || !dislikedIngredients.isEmpty
        
        // Also boost these in the implicit tracking
        for ingredient in ingredients {
            ingredientCounts[ingredient.lowercased(), default: 0] += 10
        }
        
        saveLocalPreferences()
        
        // Clear cached recipes to force fresh results with new preferences
        invalidateRecipeCache()
        
        print("💚 [RECIPE PREFS] Set \(ingredients.count) liked ingredients: \(ingredients.joined(separator: ", "))")
    }
    
    /// Set user's explicitly disliked ingredients
    func setDislikedIngredients(_ ingredients: [String]) {
        dislikedIngredients = ingredients
        hasPreferencesSet = !likedIngredients.isEmpty || !dislikedIngredients.isEmpty
        saveLocalPreferences()
        
        // Clear cached recipes to force fresh results with new preferences
        invalidateRecipeCache()
        
        print("❌ [RECIPE PREFS] Set \(ingredients.count) disliked ingredients: \(ingredients.joined(separator: ", "))")
    }
    
    /// Invalidate recipe cache to force fresh fetch with new preferences
    func invalidateRecipeCache() {
        // Clear shown recipe IDs so we get fresh results
        shownRecipeIds.removeAll()
        
        // Clear cached recipes
        personalizedRecipes.removeAll()
        dailyRecipePool.removeAll()
        
        // Reset carousel refresh time to force immediate refresh
        lastCarouselRefresh = nil
        
        // Also clear the SpoonacularService cache to get completely fresh recipes
        Task { @MainActor in
            SpoonacularService.shared.clearCache()
        }
        
        // Save updated state
        saveCarouselState()
        
        print("🔄 [RECIPE PREFS] All caches invalidated - will fetch fresh HEALTHY recipes")
    }
    
    /// Force refresh recommendations (after preference change)
    func forceRefreshRecommendations() async {
        shownRecipeIds.removeAll()
        dailyRecipePool.removeAll()
        lastCarouselRefresh = nil
        
        // Pre-fetch a fresh batch
        _ = await getPersonalizedRecipes(count: 20)
        print("🔄 [RECIPE PREFS] Forced recommendation refresh with new preferences")
    }
    
    /// Update explicit preferences from RecipePreferencesView
    func updateExplicitPreferences(liked: [String], disliked: [String]) {
        likedIngredients = liked
        dislikedIngredients = disliked
        hasPreferencesSet = !liked.isEmpty || !disliked.isEmpty
        
        // Boost liked ingredients in implicit tracking
        for ingredient in liked {
            ingredientCounts[ingredient.lowercased(), default: 0] += 10
        }
        
        saveLocalPreferences()
        
        // Clear cache to get fresh results
        shownRecipeIds.removeAll()
        dailyRecipePool.removeAll()
        lastCarouselRefresh = nil
        
        print("🔄 [RECIPE PREFS] Updated explicit: \(liked.count) likes, \(disliked.count) dislikes")
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
    
    private let logger = RecipeRecommendationLogger.shared
    
    /// Get recipes based on user's preferred ingredients (both explicit and implicit)
    /// Uses SMART MATCHING - finds recipes that USE your ingredients, not require ALL of them
    /// Enhanced: pulls from actual food logging history for accuracy
    func getPersonalizedRecipes(count: Int = 10) async -> [SpoonacularRecipe] {
        isLoadingRecommendations = true
        
        // Always re-learn from food history to pick up newly logged foods
        await learnFromFoodHistory()
        
        // LOG: User preferences at start
        logger.logPreferences(liked: likedIngredients, disliked: dislikedIngredients)
        
        // Combine explicit likes with implicit preferences
        var preferredIngredients: [String] = []
        
        // Add explicit likes first (highest priority - includes auto-detected from food history)
        preferredIngredients.append(contentsOf: likedIngredients)
        
        // Add top implicit ingredients (from search/behavior tracking)
        let implicitIngredients = getTopIngredients(limit: 5)
        for ingredient in implicitIngredients {
            if !preferredIngredients.contains(where: { $0.lowercased() == ingredient.lowercased() }) {
                preferredIngredients.append(ingredient)
            }
        }
        
        // Limit ingredients for API
        preferredIngredients = Array(preferredIngredients.prefix(6))
        
        logger.logInfo("Combined preferred ingredients: \(preferredIngredients.joined(separator: ", "))")
        
        var recipes: [SpoonacularRecipe] = []
        
        // STRATEGY 1: Health-filtered search with preferred ingredients
        if !preferredIngredients.isEmpty {
            logger.logInfo("Strategy 1: Health-filtered search with ingredients")
            let smartMatches = await fetchRecipesByIngredientsSmartMatch(
                ingredients: preferredIngredients,
                count: count * 2
            )
            recipes.append(contentsOf: smartMatches)
            logger.logInfo("Strategy 1 returned \(smartMatches.count) recipes")
        }
        
        // STRATEGY 2: Complex search as backup
        if recipes.count < count && !preferredIngredients.isEmpty {
            logger.logInfo("Strategy 2: Complex search backup (have \(recipes.count), need \(count))")
            let complexSearch = await fetchRecipesWithPreferences(
                includeIngredients: preferredIngredients.prefix(2).joined(separator: ","),
                excludeIngredients: dislikedIngredients.prefix(3).joined(separator: ","),
                count: count
            )
            for recipe in complexSearch {
                if !recipes.contains(where: { $0.id == recipe.id }) {
                    recipes.append(recipe)
                }
            }
            logger.logInfo("Strategy 2 added \(complexSearch.count) more recipes")
        }
        
        // STRATEGY 3: Healthy recipes fallback
        if recipes.count < count {
            logger.logInfo("Strategy 3: Healthy fallback (have \(recipes.count), need \(count))")
            let healthyRecipes = await fetchHealthyRecipesWithExclusions(
                count: count,
                excludeIds: recipes.map { $0.id }
            )
            recipes.append(contentsOf: healthyRecipes)
            logger.logInfo("Strategy 3 added \(healthyRecipes.count) fallback recipes")
        }
        
        // STRATEGY 4: Varied recipes as final fallback
        if recipes.count < count {
            logger.logInfo("Strategy 4: Varied meals fallback (have \(recipes.count), need \(count))")
            let additionalRecipes = await fetchVariedRecipes(
                count: count - recipes.count,
                excludeIds: recipes.map { $0.id }
            )
            recipes.append(contentsOf: additionalRecipes)
            logger.logInfo("Strategy 4 added \(additionalRecipes.count) varied recipes")
        }
        
        // Filter out recently shown (but keep results if we need them)
        let freshRecipes = recipes.filter { !shownRecipeIds.contains($0.id) }
        if freshRecipes.count >= count / 2 {
            recipes = freshRecipes
        }
        
        // Shuffle for variety
        recipes.shuffle()
        
        // Take requested count
        recipes = Array(recipes.prefix(count))
        
        // Mark as shown
        for recipe in recipes {
            shownRecipeIds.insert(recipe.id)
        }
        
        // Add to daily pool for rotation
        dailyRecipePool.append(contentsOf: recipes)
        if dailyRecipePool.count > 100 {
            dailyRecipePool = Array(dailyRecipePool.suffix(100))
        }
        
        isLoadingRecommendations = false
        personalizedRecipes = recipes
        
        // LOG: Final recommendations being shown to user
        let finalRecipeDetails = recipes.map { recipe -> (id: Int, title: String, healthScore: Int?, calories: Int?, protein: Int?) in
            (recipe.id, recipe.title, nil, recipe.calories, recipe.protein)
        }
        logger.logFinalRecommendations(recipes: finalRecipeDetails, source: "getPersonalizedRecipes")
        
        return recipes
    }
    
    /// Fetch recipes that feature user's preferred ingredients
    /// Uses a LENIENT approach - search with health filters, sort by healthiness
    private func fetchRecipesByIngredientsSmartMatch(
        ingredients: [String],
        count: Int
    ) async -> [SpoonacularRecipe] {
        // Use top 2 ingredients for broader matching (not just first)
        let searchIngredients = ingredients.prefix(2).joined(separator: " ")
        let searchQuery = "healthy \(searchIngredients)"
        let randomOffset = Int.random(in: 0...15) // Smaller offset = more common recipes

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "apiKey", value: apiKey),
            URLQueryItem(name: "number", value: String(count)),
            URLQueryItem(name: "addRecipeNutrition", value: "true"),
            URLQueryItem(name: "sort", value: "healthiness"),
            URLQueryItem(name: "sortDirection", value: "desc"),
            URLQueryItem(name: "instructionsRequired", value: "true"),
            // Health filters to ensure quality results
            URLQueryItem(name: "minHealthScore", value: "40"),
            URLQueryItem(name: "maxSugar", value: "25"),
            // Only real meals - no desserts, drinks, or beverages
            URLQueryItem(name: "type", value: "main course,salad,soup,breakfast,side dish,snack"),
            URLQueryItem(name: "query", value: searchQuery),
            URLQueryItem(name: "offset", value: String(randomOffset))
        ]

        // Only exclude disliked ingredients
        if !dislikedIngredients.isEmpty {
            let topDislikes = dislikedIngredients.prefix(3).joined(separator: ",")
            queryItems.append(URLQueryItem(name: "excludeIngredients", value: topDislikes))
        }

        print("🍽️ [RECIPE PREFS] Smart match query: '\(searchQuery)' offset: \(randomOffset)")
        
        guard var urlComponents = URLComponents(string: "\(baseURL)/recipes/complexSearch") else { return [] }
        urlComponents.queryItems = queryItems
        
        guard let url = urlComponents.url else { return [] }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                print("❌ [RECIPE PREFS] Smart match failed: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return []
            }
            
            let decoder = JSONDecoder()
            let searchResponse = try decoder.decode(RecipeSearchResponse.self, from: data)
            
            print("✅ [RECIPE PREFS] Got \(searchResponse.results.count) recipes for '\(searchQuery)' (total: \(searchResponse.totalResults))")
            return searchResponse.results
        } catch {
            print("❌ [RECIPE PREFS] Smart match error: \(error)")
            return []
        }
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
        var healthyQuery: String
        
        // Use HEALTHY meal-appropriate suggestions
        switch hour {
        case 5..<11:
            mealType = "breakfast"
            healthyQuery = "healthy breakfast eggs omelette avocado greek yogurt oatmeal protein"
        case 11..<15:
            mealType = "main course"
            healthyQuery = "healthy lunch salad chicken salmon quinoa lean protein"
        case 15..<18:
            mealType = "snack"
            healthyQuery = "healthy snack protein nuts vegetables hummus"
        default:
            mealType = "main course"
            healthyQuery = "healthy dinner lean protein chicken fish vegetables"
        }
        
        // Combine with user preferences
        var topIngredients = getTopIngredients(limit: 3)
        
        // Add explicit likes
        for liked in likedIngredients.prefix(3) {
            if !topIngredients.contains(where: { $0.lowercased() == liked.lowercased() }) {
                topIngredients.append(liked)
            }
        }
        
        return await fetchRecipesForMealTime(
            mealType: mealType,
            preferredIngredients: topIngredients,
            count: count,
            healthyQuery: healthyQuery
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
    
    /// Fetch recipes with user preferences - health-filtered with preference matching
    private func fetchRecipesWithPreferences(
        includeIngredients: String,
        excludeIngredients: String,
        count: Int
    ) async -> [SpoonacularRecipe] {
        // Use ingredients as search query for broad matching
        let ingredientList = includeIngredients.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        let queryIngredient = ingredientList.prefix(2).joined(separator: " ")
        let searchQuery = "healthy \(queryIngredient)"
        let randomOffset = Int.random(in: 0...15)

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "apiKey", value: apiKey),
            URLQueryItem(name: "number", value: String(count)),
            URLQueryItem(name: "addRecipeNutrition", value: "true"),
            URLQueryItem(name: "sort", value: "healthiness"),
            URLQueryItem(name: "sortDirection", value: "desc"),
            URLQueryItem(name: "instructionsRequired", value: "true"),
            // Health filters
            URLQueryItem(name: "minHealthScore", value: "40"),
            URLQueryItem(name: "maxSugar", value: "25"),
            URLQueryItem(name: "type", value: "main course,salad,soup,breakfast,side dish,snack"),
            URLQueryItem(name: "query", value: searchQuery),
            URLQueryItem(name: "offset", value: String(randomOffset))
        ]

        // Exclude disliked ingredients
        if !excludeIngredients.isEmpty {
            let excludeList = excludeIngredients.split(separator: ",").prefix(3).joined(separator: ",")
            queryItems.append(URLQueryItem(name: "excludeIngredients", value: excludeList))
        }

        print("🍽️ [RECIPE PREFS] Strategy 2 query: '\(searchQuery)' exclude: \(excludeIngredients.prefix(30))...")
        
        guard var urlComponents = URLComponents(string: "\(baseURL)/recipes/complexSearch") else { return [] }
        urlComponents.queryItems = queryItems
        
        guard let url = urlComponents.url else { return [] }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                print("⚠️ [RECIPE PREFS] API returned status: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return []
            }
            
            let decoder = JSONDecoder()
            let searchResponse = try decoder.decode(RecipeSearchResponse.self, from: data)
            
            print("✅ [RECIPE PREFS] Got \(searchResponse.results.count) HEALTHY recipes (query: \(queryIngredient))")
            
            return Array(searchResponse.results.prefix(count))
        } catch {
            print("❌ [RECIPE PREFS] Error fetching with preferences: \(error)")
            return []
        }
    }
    
    /// Fetch healthy recipes - common healthy meals only
    private func fetchHealthyRecipesWithExclusions(count: Int, excludeIds: [Int]) async -> [SpoonacularRecipe] {
        // Common healthy meal queries that return recognizable, everyday healthy recipes
        let healthyQueries = [
            "grilled chicken vegetables",
            "salmon asparagus",
            "chicken breast rice",
            "scrambled eggs toast",
            "avocado toast eggs",
            "greek yogurt granola",
            "chicken salad",
            "stir fry vegetables",
            "quinoa bowl chicken",
            "oatmeal berries",
            "turkey wrap",
            "baked salmon broccoli"
        ]
        let query = healthyQueries.randomElement() ?? "grilled chicken"
        let randomOffset = Int.random(in: 0...10) // Keep offset low for common results
        
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "apiKey", value: apiKey),
            URLQueryItem(name: "number", value: String(count + 5)),
            URLQueryItem(name: "addRecipeNutrition", value: "true"),
            URLQueryItem(name: "sort", value: "healthiness"),
            URLQueryItem(name: "sortDirection", value: "desc"),
            URLQueryItem(name: "instructionsRequired", value: "true"),
            // Health filters to ensure quality
            URLQueryItem(name: "minHealthScore", value: "40"),
            URLQueryItem(name: "maxSugar", value: "25"),
            URLQueryItem(name: "type", value: "main course,salad,soup,breakfast,side dish,snack"),
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "offset", value: String(randomOffset))
        ]

        // Only exclude disliked ingredients (safer)
        if !dislikedIngredients.isEmpty {
            let topDislikes = dislikedIngredients.prefix(3).joined(separator: ",")
            queryItems.append(URLQueryItem(name: "excludeIngredients", value: topDislikes))
        }

        // LOG: API Request
        logger.logAPIRequest(
            endpoint: "complexSearch (Healthy Fallback)",
            query: query,
            includeIngredients: nil,
            excludeIngredients: dislikedIngredients.isEmpty ? nil : dislikedIngredients.prefix(3).joined(separator: ","),
            minHealthScore: 40,
            minProtein: nil,
            maxSugar: 25,
            mealType: "main course,salad,soup,breakfast,side dish,snack",
            count: count + 5,
            offset: randomOffset
        )
        
        guard var urlComponents = URLComponents(string: "\(baseURL)/recipes/complexSearch") else { return [] }
        urlComponents.queryItems = queryItems
        
        guard let url = urlComponents.url else { return [] }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                logger.logError("Healthy fallback request failed")
                return []
            }
            
            let decoder = JSONDecoder()
            let searchResponse = try decoder.decode(RecipeSearchResponse.self, from: data)
            
            let filtered = Array(searchResponse.results.filter { !excludeIds.contains($0.id) }.prefix(count))
            
            // LOG: Response
            let recipeDetails = filtered.map { ($0.id, $0.title, nil as Int?, $0.calories, $0.protein) }
            logger.logAPIResponse(totalResults: searchResponse.totalResults, returnedCount: filtered.count, recipes: recipeDetails)
            
            return filtered
        } catch {
            logger.logError("Error fetching healthy recipes", error: error)
            return []
        }
    }
    
    /// Fetch varied meal recipes - common healthy meals with variety
    private func fetchVariedRecipes(count: Int, excludeIds: [Int]) async -> [SpoonacularRecipe] {
        // Common healthy meal queries people actually search for
        let mealQueries = [
            "chicken breast vegetables",
            "salmon rice",
            "egg breakfast healthy",
            "turkey salad",
            "shrimp stir fry",
            "oatmeal protein",
            "greek yogurt bowl",
            "avocado chicken",
            "lean beef broccoli",
            "sweet potato chicken"
        ]
        let randomQuery = mealQueries.randomElement() ?? "chicken vegetables"
        let randomOffset = Int.random(in: 0...10)

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "apiKey", value: apiKey),
            URLQueryItem(name: "number", value: String(count + 5)),
            URLQueryItem(name: "addRecipeNutrition", value: "true"),
            URLQueryItem(name: "sort", value: "healthiness"),
            URLQueryItem(name: "sortDirection", value: "desc"),
            // Health filters for quality
            URLQueryItem(name: "minHealthScore", value: "40"),
            URLQueryItem(name: "maxSugar", value: "25"),
            URLQueryItem(name: "type", value: "main course,salad,soup,breakfast,side dish,snack"),
            URLQueryItem(name: "query", value: randomQuery),
            URLQueryItem(name: "instructionsRequired", value: "true"),
            URLQueryItem(name: "offset", value: String(randomOffset))
        ]

        // Only exclude disliked ingredients
        if !dislikedIngredients.isEmpty {
            let topDislikes = dislikedIngredients.prefix(3).joined(separator: ",")
            queryItems.append(URLQueryItem(name: "excludeIngredients", value: topDislikes))
        }

        // LOG: API Request
        logger.logAPIRequest(
            endpoint: "complexSearch (Varied Meals)",
            query: randomQuery,
            includeIngredients: nil,
            excludeIngredients: dislikedIngredients.isEmpty ? nil : dislikedIngredients.prefix(3).joined(separator: ","),
            minHealthScore: 40,
            minProtein: nil,
            maxSugar: 25,
            mealType: "main course,salad,soup,breakfast,side dish,snack",
            count: count + 5,
            offset: randomOffset
        )
        
        guard var urlComponents = URLComponents(string: "\(baseURL)/recipes/complexSearch") else { return [] }
        urlComponents.queryItems = queryItems
        
        guard let url = urlComponents.url else { return [] }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                logger.logError("Varied meals request failed")
                return []
            }
            
            let decoder = JSONDecoder()
            let searchResponse = try decoder.decode(RecipeSearchResponse.self, from: data)
            
            let filtered = Array(searchResponse.results.filter { !excludeIds.contains($0.id) }.prefix(count))
            
            // LOG: Response
            let recipeDetails = filtered.map { ($0.id, $0.title, nil as Int?, $0.calories, $0.protein) }
            logger.logAPIResponse(totalResults: searchResponse.totalResults, returnedCount: filtered.count, recipes: recipeDetails)
            
            return filtered
        } catch {
            logger.logError("Error fetching varied recipes", error: error)
            return []
        }
    }
    
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
            URLQueryItem(name: "number", value: String(count + 10)),
            URLQueryItem(name: "addRecipeNutrition", value: "true"),
            URLQueryItem(name: "sort", value: "healthiness"),
            URLQueryItem(name: "sortDirection", value: "desc"),
            URLQueryItem(name: "instructionsRequired", value: "true"),
            URLQueryItem(name: "minHealthScore", value: "40"),
            URLQueryItem(name: "maxSugar", value: "25"),
            URLQueryItem(name: "type", value: "main course,salad,soup,breakfast,side dish,snack"),
            URLQueryItem(name: "query", value: "healthy chicken vegetables protein")
        ]

        // Exclude ONLY TOP 3 disliked ingredients
        if !dislikedIngredients.isEmpty {
            let topDislikes = dislikedIngredients.prefix(3).joined(separator: ",")
            queryItems.append(URLQueryItem(name: "excludeIngredients", value: topDislikes))
        }

        // Small random offset for variety but keep in common results range
        let randomOffset = Int.random(in: 0...10)
        queryItems.append(URLQueryItem(name: "offset", value: String(randomOffset)))
        
        guard var urlComponents = URLComponents(string: "\(baseURL)/recipes/complexSearch") else { return [] }
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
        count: Int,
        healthyQuery: String = "healthy"
    ) async -> [SpoonacularRecipe] {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "apiKey", value: apiKey),
            URLQueryItem(name: "number", value: String(count + 10)), // Fetch extra for filtering
            URLQueryItem(name: "addRecipeNutrition", value: "true"),
            URLQueryItem(name: "type", value: mealType),
            URLQueryItem(name: "sort", value: "healthiness"),
            URLQueryItem(name: "sortDirection", value: "desc"),
            URLQueryItem(name: "instructionsRequired", value: "true"),
            URLQueryItem(name: "fillIngredients", value: "true"),
            URLQueryItem(name: "minHealthScore", value: "40"),
            URLQueryItem(name: "maxSugar", value: "25"),
            // Use full healthy query for better matching
            URLQueryItem(name: "query", value: healthyQuery)
        ]
        
        // Add ONLY TOP 2-3 ingredient preferences for ~70% match
        var allPreferred = preferredIngredients
        allPreferred.append(contentsOf: likedIngredients)
        let uniquePreferred = Array(Set(allPreferred)).prefix(3)
        
        if !uniquePreferred.isEmpty {
            queryItems.append(URLQueryItem(name: "includeIngredients", value: uniquePreferred.joined(separator: ",")))
        }
        
        // Exclude ONLY TOP 3 disliked ingredients to avoid over-filtering
        if !dislikedIngredients.isEmpty {
            let topDislikes = dislikedIngredients.prefix(3).joined(separator: ",")
            queryItems.append(URLQueryItem(name: "excludeIngredients", value: topDislikes))
        }
        
        // Small random offset for variety within common results
        let randomOffset = Int.random(in: 0...10)
        queryItems.append(URLQueryItem(name: "offset", value: String(randomOffset)))

        guard var urlComponents = URLComponents(string: "\(baseURL)/recipes/complexSearch") else { return [] }
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

            print("✅ [RECIPE PREFS] Meal-time query returned \(searchResponse.results.count) results")
            return Array(searchResponse.results.prefix(count))
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
        // Explicit preferences
        UserDefaults.standard.set(likedIngredients, forKey: "recipeLikedIngredients")
        UserDefaults.standard.set(dislikedIngredients, forKey: "recipeDislikedIngredients")
        
        // Implicit preferences
        UserDefaults.standard.set(ingredientCounts, forKey: "recipeIngredientPreferences")
        UserDefaults.standard.set(cuisinePreferences, forKey: "recipeCuisinePreferences")
        UserDefaults.standard.set(searchHistory, forKey: "recipeSearchHistory")
        UserDefaults.standard.set(addedFoods, forKey: "recipeAddedFoods")
        UserDefaults.standard.set(totalRecipesViewed, forKey: "recipeTotalViewed")
        UserDefaults.standard.set(totalRecipesAdded, forKey: "recipeTotalAdded")
        UserDefaults.standard.set(totalRecipesFavorited, forKey: "recipeTotalFavorited")
    }
    
    private func loadLocalPreferences() {
        // Load explicit preferences
        likedIngredients = UserDefaults.standard.stringArray(forKey: "recipeLikedIngredients") ?? []
        dislikedIngredients = UserDefaults.standard.stringArray(forKey: "recipeDislikedIngredients") ?? []
        
        // Load implicit preferences
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
        
        print("📊 [RECIPE PREFS] Loaded: \(likedIngredients.count) liked, \(dislikedIngredients.count) avoided, \(ingredientCounts.count) implicit")
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
        // Clear explicit preferences
        likedIngredients.removeAll()
        dislikedIngredients.removeAll()
        hasPreferencesSet = false
        
        // Clear implicit preferences
        ingredientCounts.removeAll()
        cuisinePreferences.removeAll()
        searchHistory.removeAll()
        addedFoods.removeAll()
        shownRecipeIds.removeAll()
        dailyRecipePool.removeAll()
        lastCarouselRefresh = nil
        totalRecipesViewed = 0
        totalRecipesAdded = 0
        totalRecipesFavorited = 0
        
        UserDefaults.standard.removeObject(forKey: "recipeLikedIngredients")
        UserDefaults.standard.removeObject(forKey: "recipeDislikedIngredients")
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

// MARK: - Smart Ingredient Match DTOs (for findByIngredients API)

/// Recipe returned by the findByIngredients API
/// Shows which of YOUR ingredients are used and which are missing
struct IngredientMatchRecipe: Codable {
    let id: Int
    let title: String
    let image: String?
    let imageType: String?
    let usedIngredientCount: Int?
    let missedIngredientCount: Int?
    let missedIngredients: [IngredientInfo]?
    let usedIngredients: [IngredientInfo]?
    let likes: Int?
}

/// Ingredient info from findByIngredients API
struct IngredientInfo: Codable {
    let id: Int
    let name: String
    let amount: Double?
    let unit: String?
    let original: String?
    let image: String?
}

// MARK: - Cloud DTOs for Recipe Preferences
struct CloudIngredientPreference: Codable {
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
