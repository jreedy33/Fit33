import Foundation
import Combine

// MARK: - Spoonacular API Service
/// Service for fetching healthy recipes from the Spoonacular API
@MainActor
class SpoonacularService: ObservableObject {
    static let shared = SpoonacularService()
    
    // MARK: - API Configuration
    // API key centralized in AppConfig
    private let apiKey = AppConfig.spoonacularApiKey
    private let baseURL = "https://api.spoonacular.com"
    
    // MARK: - Published Properties
    @Published var healthyRecipes: [SpoonacularRecipe] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedRecipeDetail: RecipeDetail?
    
    // MARK: - Caching
    private var recipeCache: [Int: RecipeDetail] = [:]
    private var lastFetchTime: Date?
    private let cacheDuration: TimeInterval = 3600 // 1 hour cache
    
    private init() {
        // Load cached recipes on init
        loadCachedRecipes()
    }
    
    // MARK: - Public Methods
    
    /// Fetches healthy recipes optimized for fitness enthusiasts
    /// - Parameters:
    ///   - diet: Optional diet type (e.g., "high-protein", "low-carb")
    ///   - maxCalories: Maximum calories per serving
    ///   - minProtein: Minimum protein per serving
    func fetchHealthyRecipes(
        diet: String? = nil,
        maxCalories: Int = 600,
        minProtein: Int = 20,
        number: Int = 10
    ) async {
        // Check cache validity
        if let lastFetch = lastFetchTime,
           Date().timeIntervalSince(lastFetch) < cacheDuration,
           !healthyRecipes.isEmpty {
            AppLogger.debug("🍽️ [SPOONACULAR] Using cached recipes", category: .nutrition)
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        // Build query parameters for HEALTHY, high-protein MEALS (not desserts!)
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "apiKey", value: apiKey),
            URLQueryItem(name: "number", value: String(number)),
            URLQueryItem(name: "addRecipeNutrition", value: "true"),
            URLQueryItem(name: "maxCalories", value: String(maxCalories)),
            URLQueryItem(name: "minProtein", value: String(minProtein)),
            URLQueryItem(name: "sort", value: "healthiness"),
            URLQueryItem(name: "sortDirection", value: "desc"),
            // STRICT FILTERS - no junk food!
            URLQueryItem(name: "minHealthScore", value: "50"),
            URLQueryItem(name: "maxSugar", value: "15"),
            // MAIN COURSES ONLY - no desserts, cakes, or snacks!
            URLQueryItem(name: "type", value: "main course,salad,soup,breakfast"),
            URLQueryItem(name: "instructionsRequired", value: "true"),
            // Fitness-focused query - REAL meals
            URLQueryItem(name: "query", value: "healthy chicken salmon vegetable protein lean")
        ]
        
        if let diet = diet {
            queryItems.append(URLQueryItem(name: "diet", value: diet))
        }
        
        guard var urlComponents = URLComponents(string: "\(baseURL)/recipes/complexSearch") else {
            errorMessage = "Invalid URL"
            isLoading = false
            return
        }
        urlComponents.queryItems = queryItems
        
        guard let url = urlComponents.url else {
            errorMessage = "Invalid URL"
            isLoading = false
            return
        }
        
        AppLogger.debug("🍽️ [SPOONACULAR] Fetching HEALTHY recipes (minHealth: 50, main courses only)", category: .nutrition)
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw SpoonacularError.invalidResponse
            }
            
            // Log quota usage
            if let quotaUsed = httpResponse.value(forHTTPHeaderField: "X-API-Quota-Used"),
               let quotaLeft = httpResponse.value(forHTTPHeaderField: "X-API-Quota-Left") {
                AppLogger.debug("🍽️ [SPOONACULAR] Quota used: \(quotaUsed), left: \(quotaLeft)", category: .nutrition)
            }
            
            guard httpResponse.statusCode == 200 else {
                if httpResponse.statusCode == 402 {
                    throw SpoonacularError.quotaExceeded
                } else if httpResponse.statusCode == 401 {
                    throw SpoonacularError.invalidApiKey
                }
                throw SpoonacularError.httpError(httpResponse.statusCode)
            }
            
            let decoder = JSONDecoder()
            let searchResponse = try decoder.decode(RecipeSearchResponse.self, from: data)
            
            healthyRecipes = searchResponse.results
            lastFetchTime = Date()
            
            // Cache the recipes
            cacheRecipes()
            
            AppLogger.debug("🍽️ [SPOONACULAR] Successfully fetched \(healthyRecipes.count) HEALTHY recipes", category: .nutrition)
            
        } catch let error as SpoonacularError {
            errorMessage = error.localizedDescription
            AppLogger.error("🍽️ [SPOONACULAR] Error: \(error.localizedDescription)", category: .nutrition)
        } catch {
            errorMessage = "Failed to fetch recipes: \(error.localizedDescription)"
            AppLogger.error("🍽️ [SPOONACULAR] Error: \(error)", category: .nutrition)
        }
        
        isLoading = false
    }
    
    /// Fetches detailed information for a specific recipe
    func fetchRecipeDetail(recipeId: Int) async -> RecipeDetail? {
        // Check cache first
        if let cached = recipeCache[recipeId] {
            AppLogger.debug("🍽️ [SPOONACULAR] Using cached detail for recipe \(recipeId)", category: .nutrition)
            return cached
        }
        
        guard let url = URL(string: "\(baseURL)/recipes/\(recipeId)/information?apiKey=\(apiKey)&includeNutrition=true") else {
            AppLogger.error("❌ [SPOONACULAR] Invalid URL for recipe detail", category: .network)
            return nil
        }
        
        AppLogger.debug("🍽️ [SPOONACULAR] Fetching detail for recipe \(recipeId)", category: .nutrition)
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                AppLogger.error("🍽️ [SPOONACULAR] Failed to fetch recipe detail", category: .nutrition)
                return nil
            }
            
            let decoder = JSONDecoder()
            let detail = try decoder.decode(RecipeDetail.self, from: data)
            
            // Cache the detail
            recipeCache[recipeId] = detail
            
            AppLogger.debug("🍽️ [SPOONACULAR] Successfully fetched detail for: \(detail.title)", category: .nutrition)
            return detail
            
        } catch {
            AppLogger.error("🍽️ [SPOONACULAR] Error fetching detail: \(error)", category: .nutrition)
            return nil
        }
    }
    
    /// Fetches recipes similar to a given recipe
    func fetchSimilarRecipes(recipeId: Int, number: Int = 4) async -> [SimilarRecipe] {
        guard let url = URL(string: "\(baseURL)/recipes/\(recipeId)/similar?apiKey=\(apiKey)&number=\(number)") else {
            AppLogger.error("❌ [SPOONACULAR] Invalid URL for similar recipes", category: .network)
            return []
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return []
            }
            
            let decoder = JSONDecoder()
            return try decoder.decode([SimilarRecipe].self, from: data)
            
        } catch {
            AppLogger.error("🍽️ [SPOONACULAR] Error fetching similar recipes: \(error)", category: .nutrition)
            return []
        }
    }
    
    /// Fetches random healthy recipes (good for "Discover" feature)
    func fetchRandomHealthyRecipes(tags: [String] = ["healthy", "high-protein"], number: Int = 5) async {
        isLoading = true
        errorMessage = nil
        
        let tagsString = tags.joined(separator: ",")
        guard let url = URL(string: "\(baseURL)/recipes/random?apiKey=\(apiKey)&number=\(number)&tags=\(tagsString)") else {
            errorMessage = SpoonacularError.invalidURL.localizedDescription
            isLoading = false
            return
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw SpoonacularError.invalidResponse
            }
            
            let decoder = JSONDecoder()
            let randomResponse = try decoder.decode(RandomRecipeResponse.self, from: data)
            
            // Convert RandomRecipe to SpoonacularRecipe format
            healthyRecipes = randomResponse.recipes.map { randomRecipe in
                SpoonacularRecipe(
                    id: randomRecipe.id,
                    title: randomRecipe.title,
                    image: randomRecipe.image,
                    imageType: randomRecipe.imageType ?? "jpg",
                    nutrition: randomRecipe.nutrition
                )
            }
            
            AppLogger.debug("🍽️ [SPOONACULAR] Fetched \(healthyRecipes.count) random recipes", category: .nutrition)
            
        } catch {
            errorMessage = "Failed to fetch random recipes"
            AppLogger.error("🍽️ [SPOONACULAR] Error: \(error)", category: .nutrition)
        }
        
        isLoading = false
    }
    
    // MARK: - Caching
    
    private func cacheRecipes() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(healthyRecipes)
            UserDefaults.standard.set(data, forKey: "cachedSpoonacularRecipes")
            UserDefaults.standard.set(Date(), forKey: "cachedSpoonacularRecipesDate")
            AppLogger.debug("🍽️ [SPOONACULAR] Cached \(healthyRecipes.count) recipes", category: .nutrition)
        } catch {
            AppLogger.error("🍽️ [SPOONACULAR] Failed to cache recipes: \(error)", category: .nutrition)
        }
    }
    
    private func loadCachedRecipes() {
        guard let data = UserDefaults.standard.data(forKey: "cachedSpoonacularRecipes"),
              let cacheDate = UserDefaults.standard.object(forKey: "cachedSpoonacularRecipesDate") as? Date,
              Date().timeIntervalSince(cacheDate) < cacheDuration else {
            return
        }
        
        do {
            let decoder = JSONDecoder()
            healthyRecipes = try decoder.decode([SpoonacularRecipe].self, from: data)
            lastFetchTime = cacheDate
            AppLogger.debug("🍽️ [SPOONACULAR] Loaded \(healthyRecipes.count) cached recipes", category: .nutrition)
        } catch {
            AppLogger.error("🍽️ [SPOONACULAR] Failed to load cached recipes: \(error)", category: .nutrition)
        }
    }
    
    /// Clears the recipe cache
    func clearCache() {
        healthyRecipes = []
        recipeCache.removeAll()
        lastFetchTime = nil
        UserDefaults.standard.removeObject(forKey: "cachedSpoonacularRecipes")
        UserDefaults.standard.removeObject(forKey: "cachedSpoonacularRecipesDate")
        AppLogger.debug("🍽️ [SPOONACULAR] Cache cleared", category: .nutrition)
    }
}

// MARK: - Error Types

enum SpoonacularError: LocalizedError {
    case invalidApiKey
    case quotaExceeded
    case invalidResponse
    case invalidURL
    case httpError(Int)
    case decodingError
    
    var errorDescription: String? {
        switch self {
        case .invalidApiKey:
            return "Invalid API key. Please check your Spoonacular API key."
        case .quotaExceeded:
            return "API quota exceeded. Recipes will refresh tomorrow."
        case .invalidResponse:
            return "Invalid response from server."
        case .invalidURL:
            return "Failed to construct API request URL."
        case .httpError(let code):
            return "Server error (code: \(code))"
        case .decodingError:
            return "Failed to parse recipe data."
        }
    }
}
