//
//  SmartMealRecommendationService.swift
//  Fit33
//
//  Smart meal recommendations that prioritize health, user preferences,
//  and meal-appropriate suggestions
//

import Foundation
import Combine

// MARK: - Smart Meal Recommendation Service
@MainActor
class SmartMealRecommendationService: ObservableObject {
    static let shared = SmartMealRecommendationService()
    
    // MARK: - Published Properties
    @Published var breakfastRecommendations: [HealthyMealRecommendation] = []
    @Published var lunchRecommendations: [HealthyMealRecommendation] = []
    @Published var dinnerRecommendations: [HealthyMealRecommendation] = []
    @Published var snackRecommendations: [HealthyMealRecommendation] = []
    @Published var isLoading = false
    
    // MARK: - Private Properties
    private let apiKey = AppConfig.spoonacularApiKey
    private let baseURL = "https://api.spoonacular.com"
    private let preferenceService = RecipePreferenceService.shared
    
    // Cache settings
    private var lastFetchTime: [MealType: Date] = [:]
    private let cacheDuration: TimeInterval = 30 * 60 // 30 minutes
    
    // Health score thresholds
    private let minimumHealthScore: Int = 40 // Minimum health score (out of 100)
    private let preferredHealthScore: Int = 60 // Preferred health score
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Get smart recommendations for a specific meal type
    func getRecommendations(for mealType: MealType, count: Int = 10) async -> [HealthyMealRecommendation] {
        // Check cache
        if let lastFetch = lastFetchTime[mealType],
           Date().timeIntervalSince(lastFetch) < cacheDuration {
            return getCachedRecommendations(for: mealType)
        }
        
        isLoading = true
        defer { isLoading = false }
        
        // Get user preferences
        let likedIngredients = preferenceService.getLikedIngredients()
        let dislikedIngredients = preferenceService.getDislikedIngredients()
        
        // Build appropriate query based on meal type
        let mealQuery = getMealTypeQuery(mealType)
        let healthyKeywords = getHealthyKeywords(for: mealType)
        
        var recipes: [HealthyMealRecommendation] = []
        
        // Strategy 1: Fetch with user preferences
        if !likedIngredients.isEmpty {
            let personalized = await fetchHealthyRecipes(
                query: healthyKeywords,
                mealType: mealQuery,
                includeIngredients: likedIngredients.prefix(5).joined(separator: ","),
                excludeIngredients: dislikedIngredients.joined(separator: ","),
                count: count
            )
            recipes.append(contentsOf: personalized)
        }
        
        // Strategy 2: Fetch general healthy options for this meal type
        if recipes.count < count {
            let general = await fetchHealthyRecipes(
                query: healthyKeywords,
                mealType: mealQuery,
                includeIngredients: nil,
                excludeIngredients: dislikedIngredients.joined(separator: ","),
                count: count - recipes.count
            )
            
            // Filter out duplicates
            for recipe in general {
                if !recipes.contains(where: { $0.id == recipe.id }) {
                    recipes.append(recipe)
                }
            }
        }
        
        // Sort by health score (highest first)
        recipes.sort { ($0.healthScore ?? 0) > ($1.healthScore ?? 0) }
        
        // Take top results
        let finalRecipes = Array(recipes.prefix(count))
        
        // Cache results
        cacheRecommendations(finalRecipes, for: mealType)
        lastFetchTime[mealType] = Date()
        
        print("🍽️ [SMART MEALS] Got \(finalRecipes.count) \(mealType.displayName) recommendations")
        
        return finalRecipes
    }
    
    /// Refresh all meal recommendations
    func refreshAllRecommendations() async {
        lastFetchTime.removeAll()
        
        async let breakfast = getRecommendations(for: .breakfast)
        async let lunch = getRecommendations(for: .lunch)
        async let dinner = getRecommendations(for: .dinner)
        async let snacks = getRecommendations(for: .snacks)
        
        breakfastRecommendations = await breakfast
        lunchRecommendations = await lunch
        dinnerRecommendations = await dinner
        snackRecommendations = await snacks
    }
    
    /// Track when user adds a meal from recommendations (for learning)
    func trackMealAdded(_ recommendation: HealthyMealRecommendation, mealType: MealType) {
        Task {
            // Save interaction to database for learning
            await saveInteraction(
                recipeId: recommendation.id,
                recipeTitle: recommendation.title,
                mealType: mealType,
                interactionType: "add_to_meal",
                healthScore: recommendation.healthScore
            )
            
            // Update preference service for implicit learning
            if let ingredients = recommendation.ingredients {
                for ingredient in ingredients.prefix(5) {
                    preferenceService.trackFoodAdded(
                        foodName: ingredient,
                        calories: recommendation.calories ?? 0,
                        protein: recommendation.protein ?? 0
                    )
                }
            }
        }
        
        print("✅ [SMART MEALS] Tracked meal addition: \(recommendation.title)")
    }
    
    // MARK: - Private Methods
    
    /// Fetch healthy recipes from API with smart filtering
    private func fetchHealthyRecipes(
        query: String,
        mealType: String?,
        includeIngredients: String?,
        excludeIngredients: String?,
        count: Int
    ) async -> [HealthyMealRecommendation] {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "apiKey", value: apiKey),
            URLQueryItem(name: "number", value: String(count * 2)), // Fetch more to filter
            URLQueryItem(name: "addRecipeNutrition", value: "true"),
            URLQueryItem(name: "sort", value: "healthiness"),
            URLQueryItem(name: "sortDirection", value: "desc"),
            URLQueryItem(name: "minHealthScore", value: String(minimumHealthScore)),
            URLQueryItem(name: "instructionsRequired", value: "true"),
            URLQueryItem(name: "fillIngredients", value: "true"),
            URLQueryItem(name: "query", value: query)
        ]
        
        // Add meal type filter
        if let mealType = mealType, !mealType.isEmpty {
            queryItems.append(URLQueryItem(name: "type", value: mealType))
        }
        
        // Add ingredient preferences
        if let include = includeIngredients, !include.isEmpty {
            queryItems.append(URLQueryItem(name: "includeIngredients", value: include))
        }
        
        if let exclude = excludeIngredients, !exclude.isEmpty {
            queryItems.append(URLQueryItem(name: "excludeIngredients", value: exclude))
        }
        
        // Random offset for variety
        let randomOffset = Int.random(in: 0...50)
        queryItems.append(URLQueryItem(name: "offset", value: String(randomOffset)))
        
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
            let searchResponse = try decoder.decode(SmartRecipeSearchResponse.self, from: data)
            
            // Convert to HealthyMealRecommendation and filter
            return searchResponse.results.compactMap { recipe -> HealthyMealRecommendation? in
                // Skip if health score is too low
                if let healthScore = recipe.healthScore, healthScore < minimumHealthScore {
                    return nil
                }
                
                return HealthyMealRecommendation(
                    id: recipe.id,
                    title: recipe.title,
                    image: recipe.image,
                    healthScore: recipe.healthScore,
                    readyInMinutes: recipe.readyInMinutes,
                    servings: recipe.servings,
                    calories: recipe.nutrition?.nutrients?.first(where: { $0.name == "Calories" })?.amount.map { Int($0) },
                    protein: recipe.nutrition?.nutrients?.first(where: { $0.name == "Protein" })?.amount.map { Int($0) },
                    carbs: recipe.nutrition?.nutrients?.first(where: { $0.name == "Carbohydrates" })?.amount.map { Int($0) },
                    fat: recipe.nutrition?.nutrients?.first(where: { $0.name == "Fat" })?.amount.map { Int($0) },
                    ingredients: recipe.nutrition?.ingredients?.map { $0.name }
                )
            }
            
        } catch {
            print("❌ [SMART MEALS] Error fetching recipes: \(error)")
            return []
        }
    }
    
    /// Get meal-appropriate query string
    private func getMealTypeQuery(_ mealType: MealType) -> String? {
        switch mealType {
        case .breakfast:
            return "breakfast,brunch"
        case .lunch:
            return "main course,salad,soup"
        case .dinner:
            return "main course,main dish"
        case .snacks:
            return "snack,appetizer"
        }
    }
    
    /// Get healthy keywords for search based on meal type
    private func getHealthyKeywords(for mealType: MealType) -> String {
        switch mealType {
        case .breakfast:
            // Healthy breakfast options - avoid heavy/greasy items
            return "healthy breakfast eggs omelette avocado greek yogurt oatmeal protein smoothie"
        case .lunch:
            // Balanced lunch options
            return "healthy lunch salad chicken salmon quinoa vegetables protein bowl"
        case .dinner:
            // Nutritious dinner options
            return "healthy dinner lean protein chicken fish salmon vegetables low carb"
        case .snacks:
            // Healthy snack options
            return "healthy snack protein nuts vegetables hummus yogurt"
        }
    }
    
    /// Save interaction to database for learning
    private func saveInteraction(
        recipeId: Int,
        recipeTitle: String,
        mealType: MealType,
        interactionType: String,
        healthScore: Int?
    ) async {
        guard let userId = SupabaseManager.shared.currentUser?.id else { return }
        
        let interaction = MealInteractionInsert(
            userId: userId.uuidString,
            recipeId: recipeId,
            recipeTitle: recipeTitle,
            interactionType: interactionType,
            mealType: mealType.rawValue
        )
        
        do {
            try await SupabaseManager.shared.supabaseClient
                .from("user_recipe_interactions")
                .insert(interaction)
                .execute()
            
            print("📝 [SMART MEALS] Saved interaction for learning")
        } catch {
            print("⚠️ [SMART MEALS] Failed to save interaction: \(error)")
        }
    }
    
    /// Cache recommendations locally
    private func cacheRecommendations(_ recommendations: [HealthyMealRecommendation], for mealType: MealType) {
        switch mealType {
        case .breakfast:
            breakfastRecommendations = recommendations
        case .lunch:
            lunchRecommendations = recommendations
        case .dinner:
            dinnerRecommendations = recommendations
        case .snacks:
            snackRecommendations = recommendations
        }
    }
    
    /// Get cached recommendations
    private func getCachedRecommendations(for mealType: MealType) -> [HealthyMealRecommendation] {
        switch mealType {
        case .breakfast: return breakfastRecommendations
        case .lunch: return lunchRecommendations
        case .dinner: return dinnerRecommendations
        case .snacks: return snackRecommendations
        }
    }
}

// MARK: - Data Models

struct HealthyMealRecommendation: Identifiable, Codable {
    let id: Int
    let title: String
    let image: String?
    let healthScore: Int?
    let readyInMinutes: Int?
    let servings: Int?
    let calories: Int?
    let protein: Int?
    let carbs: Int?
    let fat: Int?
    let ingredients: [String]?
    
    var healthScoreColor: String {
        guard let score = healthScore else { return "gray" }
        if score >= 70 { return "green" }
        if score >= 50 { return "orange" }
        return "red"
    }
    
    var isHighlyHealthy: Bool {
        (healthScore ?? 0) >= 70
    }
}

struct SmartRecipeSearchResponse: Codable {
    let results: [SmartRecipeResult]
    let totalResults: Int
}

struct SmartRecipeResult: Codable {
    let id: Int
    let title: String
    let image: String?
    let imageType: String?
    let healthScore: Int?
    let readyInMinutes: Int?
    let servings: Int?
    let nutrition: SmartNutrition?
}

struct SmartNutrition: Codable {
    let nutrients: [SmartNutrient]?
    let ingredients: [SmartIngredient]?
}

struct SmartNutrient: Codable {
    let name: String
    let amount: Double
    let unit: String
}

struct SmartIngredient: Codable {
    let name: String
    let amount: Double?
    let unit: String?
}

struct MealInteractionInsert: Codable {
    let userId: String
    let recipeId: Int
    let recipeTitle: String
    let interactionType: String
    let mealType: String
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case recipeId = "recipe_id"
        case recipeTitle = "recipe_title"
        case interactionType = "interaction_type"
        case mealType = "meal_type"
    }
}

// MARK: - Healthy Breakfast Examples
/// Pre-defined healthy meal suggestions when API is unavailable
extension SmartMealRecommendationService {
    
    static let healthyBreakfastSuggestions: [String] = [
        "Egg white omelette with spinach and tomatoes",
        "Greek yogurt parfait with berries and granola",
        "Avocado toast with poached eggs",
        "Overnight oats with banana and almond butter",
        "Protein smoothie bowl with fruits",
        "Turkey sausage with scrambled eggs",
        "Cottage cheese with fresh fruit",
        "Whole grain toast with smoked salmon",
        "Veggie scramble with bell peppers",
        "Protein pancakes with fresh berries"
    ]
    
    static let healthyLunchSuggestions: [String] = [
        "Grilled chicken salad with mixed greens",
        "Quinoa bowl with roasted vegetables",
        "Turkey and avocado wrap",
        "Salmon with steamed broccoli",
        "Mediterranean grain bowl",
        "Chicken stir-fry with vegetables",
        "Tuna salad lettuce wraps",
        "Black bean and corn salad",
        "Grilled chicken breast with sweet potato",
        "Asian chicken salad"
    ]
    
    static let healthyDinnerSuggestions: [String] = [
        "Baked salmon with asparagus",
        "Grilled chicken with roasted vegetables",
        "Lean beef stir-fry with broccoli",
        "Turkey meatballs with zucchini noodles",
        "Baked cod with lemon and herbs",
        "Chicken breast with quinoa",
        "Shrimp and vegetable skewers",
        "Lean pork tenderloin with green beans",
        "Grilled tilapia with mango salsa",
        "Chicken and vegetable curry (light)"
    ]
    
    static let healthySnackSuggestions: [String] = [
        "Apple slices with almond butter",
        "Greek yogurt with honey",
        "Mixed nuts (unsalted)",
        "Hummus with vegetable sticks",
        "Cottage cheese with berries",
        "Hard-boiled eggs",
        "Edamame",
        "Protein bar (low sugar)",
        "Celery with peanut butter",
        "Turkey roll-ups with cheese"
    ]
}
