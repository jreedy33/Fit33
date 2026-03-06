import Foundation
import Combine

// MARK: - Spoonacular Advanced API Service
/// Extended Spoonacular API service with meal planning, shopping lists, and more
@MainActor
class SpoonacularAdvancedService: ObservableObject {
    static let shared = SpoonacularAdvancedService()
    
    private let apiKey = AppConfig.spoonacularApiKey
    private let baseURL = "https://api.spoonacular.com"
    
    // MARK: - Published Properties
    @Published var generatedMealPlan: GeneratedMealPlan?
    @Published var shoppingList: [ShoppingAisle] = []
    @Published var extractedRecipe: ExtractedRecipe?
    @Published var ingredientSubstitutes: [IngredientSubstitute] = []
    @Published var analyzedNutrition: AnalyzedNutrition?
    @Published var menuItems: [MenuItem] = []
    @Published var recipeAutocomplete: [RecipeAutocompleteResult] = []
    @Published var priceBreakdown: RecipePriceBreakdown?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private init() {}
    
    // MARK: - 1. Meal Plan Generator
    /// Generate a meal plan based on user's calorie and macro targets
    func generateMealPlan(
        timeFrame: MealPlanTimeFrame = .day,
        targetCalories: Int,
        diet: String? = nil,
        exclude: [String]? = nil
    ) async -> GeneratedMealPlan? {
        isLoading = true
        errorMessage = nil
        
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "apiKey", value: apiKey),
            URLQueryItem(name: "timeFrame", value: timeFrame.rawValue),
            URLQueryItem(name: "targetCalories", value: String(targetCalories))
        ]
        
        if let diet = diet {
            queryItems.append(URLQueryItem(name: "diet", value: diet))
        }
        
        if let exclude = exclude, !exclude.isEmpty {
            queryItems.append(URLQueryItem(name: "exclude", value: exclude.joined(separator: ",")))
        }
        
        guard var urlComponents = URLComponents(string: "\(baseURL)/mealplanner/generate") else {
            errorMessage = "Invalid URL"
            isLoading = false
            return nil
        }
        urlComponents.queryItems = queryItems
        
        guard let url = urlComponents.url else {
            errorMessage = "Invalid URL"
            isLoading = false
            return nil
        }
        
        print("🍽️ [MEAL PLAN] Generating meal plan for \(targetCalories) calories")
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                errorMessage = "Failed to generate meal plan"
                isLoading = false
                return nil
            }
            
            let decoder = JSONDecoder()
            
            if timeFrame == .day {
                let dayPlan = try decoder.decode(DayMealPlanResponse.self, from: data)
                let mealPlan = GeneratedMealPlan(
                    timeFrame: .day,
                    days: [dayPlan],
                    week: nil
                )
                generatedMealPlan = mealPlan
                isLoading = false
                print("🍽️ [MEAL PLAN] Generated day plan with \(dayPlan.meals.count) meals")
                return mealPlan
            } else {
                let weekPlan = try decoder.decode(WeekMealPlanResponse.self, from: data)
                let mealPlan = GeneratedMealPlan(
                    timeFrame: .week,
                    days: nil,
                    week: weekPlan
                )
                generatedMealPlan = mealPlan
                isLoading = false
                print("🍽️ [MEAL PLAN] Generated week plan")
                return mealPlan
            }
            
        } catch {
            errorMessage = "Failed to parse meal plan: \(error.localizedDescription)"
            print("🍽️ [MEAL PLAN] Error: \(error)")
            isLoading = false
            return nil
        }
    }
    
    // MARK: - 2. Shopping List Generator
    /// Generate a shopping list from a list of recipe IDs
    func generateShoppingList(recipeIds: [Int]) async -> [ShoppingAisle] {
        isLoading = true
        errorMessage = nil
        
        var allIngredients: [ShoppingIngredient] = []
        
        // Fetch ingredients for each recipe
        for recipeId in recipeIds {
            if let ingredients = await fetchRecipeIngredients(recipeId: recipeId) {
                allIngredients.append(contentsOf: ingredients)
            }
        }
        
        // Group by aisle
        let grouped = Dictionary(grouping: allIngredients) { $0.aisle ?? "Other" }
        let aisles = grouped.map { aisle, items in
            ShoppingAisle(
                name: aisle,
                items: consolidateIngredients(items)
            )
        }.sorted { $0.name < $1.name }
        
        shoppingList = aisles
        isLoading = false
        
        print("🛒 [SHOPPING] Generated list with \(aisles.count) aisles")
        return aisles
    }
    
    private func fetchRecipeIngredients(recipeId: Int) async -> [ShoppingIngredient]? {
        guard let url = URL(string: "\(baseURL)/recipes/\(recipeId)/ingredientWidget.json?apiKey=\(apiKey)") else {
            print("❌ [SHOPPING] Invalid URL for recipe \(recipeId)")
            return nil
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }
            
            let decoder = JSONDecoder()
            let ingredientResponse = try decoder.decode(IngredientWidgetResponse.self, from: data)
            return ingredientResponse.ingredients.map { ing in
                ShoppingIngredient(
                    name: ing.name,
                    amount: ing.amount.metric.value,
                    unit: ing.amount.metric.unit,
                    aisle: ing.aisle
                )
            }
        } catch {
            print("🛒 [SHOPPING] Error fetching ingredients: \(error)")
            return nil
        }
    }
    
    private func consolidateIngredients(_ ingredients: [ShoppingIngredient]) -> [ShoppingIngredient] {
        var consolidated: [String: ShoppingIngredient] = [:]
        
        for ing in ingredients {
            let key = "\(ing.name.lowercased())_\(ing.unit.lowercased())"
            if var existing = consolidated[key] {
                existing.amount += ing.amount
                consolidated[key] = existing
            } else {
                consolidated[key] = ing
            }
        }
        
        return Array(consolidated.values).sorted { $0.name < $1.name }
    }
    
    // MARK: - 3. Ingredient Substitution
    /// Get substitutes for an ingredient
    func getIngredientSubstitutes(ingredientName: String) async -> [IngredientSubstitute] {
        isLoading = true
        errorMessage = nil
        
        let encoded = ingredientName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ingredientName
        guard let url = URL(string: "\(baseURL)/food/ingredients/substitutes?apiKey=\(apiKey)&ingredientName=\(encoded)") else {
            print("❌ [SUBSTITUTES] Invalid URL for ingredient: \(ingredientName)")
            isLoading = false
            return []
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                isLoading = false
                return []
            }
            
            let decoder = JSONDecoder()
            let subResponse = try decoder.decode(SubstituteResponse.self, from: data)
            
            let substitutes = subResponse.substitutes.map { sub in
                IngredientSubstitute(
                    original: ingredientName,
                    substitute: sub,
                    message: subResponse.message
                )
            }
            
            ingredientSubstitutes = substitutes
            isLoading = false
            
            print("🔄 [SUBSTITUTE] Found \(substitutes.count) substitutes for \(ingredientName)")
            return substitutes
            
        } catch {
            print("🔄 [SUBSTITUTE] Error: \(error)")
            isLoading = false
            return []
        }
    }
    
    // MARK: - 4. Recipe Import from URL
    /// Extract recipe from any URL
    func extractRecipeFromURL(urlString: String) async -> ExtractedRecipe? {
        isLoading = true
        errorMessage = nil
        
        let encoded = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlString
        guard let url = URL(string: "\(baseURL)/recipes/extract?apiKey=\(apiKey)&url=\(encoded)&analyze=true&forceExtraction=true&addRecipeInformation=true") else {
            print("❌ [EXTRACT] Invalid URL for extraction")
            isLoading = false
            return nil
        }
        
        print("📥 [EXTRACT] Extracting recipe from URL")
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                errorMessage = "Failed to extract recipe"
                isLoading = false
                return nil
            }
            
            let decoder = JSONDecoder()
            let recipe = try decoder.decode(ExtractedRecipe.self, from: data)
            
            extractedRecipe = recipe
            isLoading = false
            
            print("📥 [EXTRACT] Successfully extracted: \(recipe.title)")
            return recipe
            
        } catch {
            errorMessage = "Failed to parse extracted recipe"
            print("📥 [EXTRACT] Error: \(error)")
            isLoading = false
            return nil
        }
    }
    
    // MARK: - 5. Recipe Autocomplete
    /// Get recipe search suggestions
    func getRecipeAutocomplete(query: String, number: Int = 10) async -> [RecipeAutocompleteResult] {
        guard query.count >= 2 else { return [] }
        
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "\(baseURL)/recipes/autocomplete?apiKey=\(apiKey)&query=\(encoded)&number=\(number)") else {
            print("❌ [AUTOCOMPLETE] Invalid URL for query: \(query)")
            return []
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return []
            }
            
            let decoder = JSONDecoder()
            let results = try decoder.decode([RecipeAutocompleteResult].self, from: data)
            
            recipeAutocomplete = results
            return results
            
        } catch {
            print("🔍 [AUTOCOMPLETE] Error: \(error)")
            return []
        }
    }
    
    // MARK: - 6. Analyze Recipe from Text
    /// Analyze nutrition from ingredient text
    func analyzeRecipeFromText(ingredientList: String, servings: Int = 1) async -> AnalyzedNutrition? {
        isLoading = true
        errorMessage = nil
        
        guard let url = URL(string: "\(baseURL)/recipes/parseIngredients?apiKey=\(apiKey)&includeNutrition=true") else {
            print("❌ [NUTRITION] Invalid URL for ingredient analysis")
            isLoading = false
            return nil
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let bodyString = "ingredientList=\(ingredientList.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&servings=\(servings)"
        request.httpBody = bodyString.data(using: .utf8)
        
        print("📊 [ANALYZE] Analyzing ingredients")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                errorMessage = "Failed to analyze recipe"
                isLoading = false
                return nil
            }
            
            let decoder = JSONDecoder()
            let parsedIngredients = try decoder.decode([ParsedIngredient].self, from: data)
            
            // Aggregate nutrition
            var totalCalories = 0.0
            var totalProtein = 0.0
            var totalCarbs = 0.0
            var totalFat = 0.0
            
            for ingredient in parsedIngredients {
                if let nutrition = ingredient.nutrition {
                    for nutrient in nutrition.nutrients {
                        switch nutrient.name.lowercased() {
                        case "calories": totalCalories += nutrient.amount
                        case "protein": totalProtein += nutrient.amount
                        case "carbohydrates": totalCarbs += nutrient.amount
                        case "fat": totalFat += nutrient.amount
                        default: break
                        }
                    }
                }
            }
            
            let analyzed = AnalyzedNutrition(
                calories: Int(totalCalories),
                protein: Int(totalProtein),
                carbs: Int(totalCarbs),
                fat: Int(totalFat),
                ingredients: parsedIngredients
            )
            
            analyzedNutrition = analyzed
            isLoading = false
            
            print("📊 [ANALYZE] Analyzed \(parsedIngredients.count) ingredients")
            return analyzed
            
        } catch {
            errorMessage = "Failed to analyze ingredients"
            print("📊 [ANALYZE] Error: \(error)")
            isLoading = false
            return nil
        }
    }
    
    // MARK: - 8. Menu Item Search (Restaurant)
    /// Search restaurant menu items
    func searchMenuItems(query: String, number: Int = 10) async -> [MenuItem] {
        isLoading = true
        errorMessage = nil
        
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "\(baseURL)/food/menuItems/search?apiKey=\(apiKey)&query=\(encoded)&number=\(number)") else {
            print("❌ [MENU] Invalid URL for query: \(query)")
            isLoading = false
            return []
        }
        
        print("🍔 [MENU] Searching for: \(query)")
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                errorMessage = "Failed to search menu items"
                isLoading = false
                return []
            }
            
            let decoder = JSONDecoder()
            let menuResponse = try decoder.decode(MenuItemSearchResponse.self, from: data)
            
            menuItems = menuResponse.menuItems
            isLoading = false
            
            print("🍔 [MENU] Found \(menuResponse.menuItems.count) items")
            return menuResponse.menuItems
            
        } catch {
            errorMessage = "Failed to parse menu items"
            print("🍔 [MENU] Error: \(error)")
            isLoading = false
            return []
        }
    }
    
    /// Get menu item details
    func getMenuItemDetails(menuItemId: Int) async -> MenuItemDetail? {
        guard let url = URL(string: "\(baseURL)/food/menuItems/\(menuItemId)?apiKey=\(apiKey)") else {
            print("❌ [MENU] Invalid URL for menu item \(menuItemId)")
            return nil
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }
            
            let decoder = JSONDecoder()
            return try decoder.decode(MenuItemDetail.self, from: data)
            
        } catch {
            print("🍔 [MENU] Error getting details: \(error)")
            return nil
        }
    }
    
    // MARK: - 9. Price Breakdown
    /// Get price breakdown for a recipe
    func getPriceBreakdown(recipeId: Int) async -> RecipePriceBreakdown? {
        guard let url = URL(string: "\(baseURL)/recipes/\(recipeId)/priceBreakdownWidget.json?apiKey=\(apiKey)") else {
            print("❌ [PRICE] Invalid URL for recipe \(recipeId)")
            return nil
        }
        
        print("💰 [PRICE] Getting price breakdown for recipe \(recipeId)")
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }
            
            let decoder = JSONDecoder()
            let breakdown = try decoder.decode(RecipePriceBreakdown.self, from: data)
            
            priceBreakdown = breakdown
            
            print("💰 [PRICE] Total cost: $\(String(format: "%.2f", breakdown.totalCost / 100.0))")
            return breakdown
            
        } catch {
            print("💰 [PRICE] Error: \(error)")
            return nil
        }
    }
    
    // MARK: - 10. Nutrition Widget Data
    /// Get detailed nutrition widget data for a recipe
    func getNutritionWidget(recipeId: Int) async -> NutritionWidgetData? {
        guard let url = URL(string: "\(baseURL)/recipes/\(recipeId)/nutritionWidget.json?apiKey=\(apiKey)") else {
            print("❌ [NUTRITION] Invalid URL for recipe \(recipeId)")
            return nil
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }
            
            let decoder = JSONDecoder()
            return try decoder.decode(NutritionWidgetData.self, from: data)
            
        } catch {
            print("📊 [NUTRITION] Error: \(error)")
            return nil
        }
    }
}

// MARK: - Supporting Models

enum MealPlanTimeFrame: String {
    case day = "day"
    case week = "week"
}

struct GeneratedMealPlan {
    let timeFrame: MealPlanTimeFrame
    let days: [DayMealPlanResponse]?
    let week: WeekMealPlanResponse?
}

// Day meal plan response
struct DayMealPlanResponse: Codable {
    let meals: [MealPlanMeal]
    let nutrients: MealPlanNutrients
}

struct MealPlanMeal: Codable, Identifiable {
    let id: Int
    let title: String
    let readyInMinutes: Int
    let servings: Int
    let sourceUrl: String?
    let image: String?
    let imageType: String?
    
    var imageURL: URL? {
        guard let image = image else { return nil }
        if image.hasPrefix("http") {
            return URL(string: image)
        }
        return URL(string: "https://img.spoonacular.com/recipes/\(id)-556x370.\(imageType ?? "jpg")")
    }
}

struct MealPlanNutrients: Codable {
    let calories: Double
    let protein: Double
    let fat: Double
    let carbohydrates: Double
}

// Week meal plan response
struct WeekMealPlanResponse: Codable {
    let week: WeekDays
}

struct WeekDays: Codable {
    let monday: DayMealPlanResponse?
    let tuesday: DayMealPlanResponse?
    let wednesday: DayMealPlanResponse?
    let thursday: DayMealPlanResponse?
    let friday: DayMealPlanResponse?
    let saturday: DayMealPlanResponse?
    let sunday: DayMealPlanResponse?
    
    var allDays: [(String, DayMealPlanResponse)] {
        var days: [(String, DayMealPlanResponse)] = []
        if let mon = monday { days.append(("Monday", mon)) }
        if let tue = tuesday { days.append(("Tuesday", tue)) }
        if let wed = wednesday { days.append(("Wednesday", wed)) }
        if let thu = thursday { days.append(("Thursday", thu)) }
        if let fri = friday { days.append(("Friday", fri)) }
        if let sat = saturday { days.append(("Saturday", sat)) }
        if let sun = sunday { days.append(("Sunday", sun)) }
        return days
    }
}

// Shopping list models
struct ShoppingAisle: Identifiable {
    var id: String { name }
    let name: String
    var items: [ShoppingIngredient]
}

struct ShoppingIngredient: Identifiable {
    var id: String { "\(name)_\(unit)" }
    let name: String
    var amount: Double
    let unit: String
    let aisle: String?
    var isChecked: Bool = false
    
    var formattedAmount: String {
        if amount == amount.rounded() {
            return "\(Int(amount)) \(unit)"
        }
        return "\(String(format: "%.1f", amount)) \(unit)"
    }
}

struct IngredientWidgetResponse: Codable {
    let ingredients: [IngredientWidgetItem]
}

struct IngredientWidgetItem: Codable {
    let name: String
    let amount: IngredientWidgetAmount
    let aisle: String?
}

struct IngredientWidgetAmount: Codable {
    let metric: IngredientWidgetMetric
    let us: IngredientWidgetMetric
}

struct IngredientWidgetMetric: Codable {
    let value: Double
    let unit: String
}

// Ingredient substitution models
struct SubstituteResponse: Codable {
    let ingredient: String
    let substitutes: [String]
    let message: String
}

struct IngredientSubstitute: Identifiable {
    var id: String { "\(original)_\(substitute)" }
    let original: String
    let substitute: String
    let message: String
}

// Extracted recipe model
struct ExtractedRecipe: Codable, Identifiable {
    let id: Int?
    let title: String
    let image: String?
    let servings: Int?
    let readyInMinutes: Int?
    let sourceUrl: String?
    let sourceName: String?
    let summary: String?
    let instructions: String?
    let extendedIngredients: [ExtendedIngredient]?
    let nutrition: RecipeNutrition?
    
    var calories: Int {
        guard let nutrients = nutrition?.nutrients else { return 0 }
        return Int(nutrients.first { $0.name.lowercased() == "calories" }?.amount ?? 0)
    }
    
    var protein: Int {
        guard let nutrients = nutrition?.nutrients else { return 0 }
        return Int(nutrients.first { $0.name.lowercased() == "protein" }?.amount ?? 0)
    }
    
    var carbs: Int {
        guard let nutrients = nutrition?.nutrients else { return 0 }
        return Int(nutrients.first { $0.name.lowercased() == "carbohydrates" }?.amount ?? 0)
    }
    
    var fat: Int {
        guard let nutrients = nutrition?.nutrients else { return 0 }
        return Int(nutrients.first { $0.name.lowercased() == "fat" }?.amount ?? 0)
    }
}

// Autocomplete model
struct RecipeAutocompleteResult: Codable, Identifiable {
    let id: Int
    let title: String
    let imageType: String?
    
    var imageURL: URL? {
        URL(string: "https://img.spoonacular.com/recipes/\(id)-90x90.\(imageType ?? "jpg")")
    }
}

// Analyzed nutrition model
struct AnalyzedNutrition {
    let calories: Int
    let protein: Int
    let carbs: Int
    let fat: Int
    let ingredients: [ParsedIngredient]
}

struct ParsedIngredient: Codable, Identifiable {
    var id: String { name }
    let name: String
    let amount: Double?
    let unit: String?
    let nutrition: ParsedIngredientNutrition?
}

struct ParsedIngredientNutrition: Codable {
    let nutrients: [Nutrient]
}

// Menu item models
struct MenuItemSearchResponse: Codable {
    let menuItems: [MenuItem]
    let totalMenuItems: Int
    let type: String
    let offset: Int
    let number: Int
}

struct MenuItem: Codable, Identifiable {
    let id: Int
    let title: String
    let restaurantChain: String?
    let image: String?
    let imageType: String?
    let servingSize: String?
    
    var imageURL: URL? {
        guard let image = image else { return nil }
        return URL(string: image)
    }
}

struct MenuItemDetail: Codable, Identifiable {
    let id: Int
    let title: String
    let restaurantChain: String?
    let image: String?
    let servingSize: String?
    let servings: ServingInfo?
    let nutrition: MenuItemNutrition?
    
    var calories: Int {
        Int(nutrition?.calories ?? 0)
    }
    
    var protein: Double {
        nutrition?.protein ?? 0
    }
    
    var carbs: Double {
        nutrition?.carbs ?? 0
    }
    
    var fat: Double {
        nutrition?.fat ?? 0
    }
}

struct ServingInfo: Codable {
    let number: Double?
    let size: Double?
    let unit: String?
}

struct MenuItemNutrition: Codable {
    let calories: Double?
    let fat: Double?
    let protein: Double?
    let carbs: Double?
}

// Price breakdown model
struct RecipePriceBreakdown: Codable {
    let ingredients: [PriceIngredient]
    let totalCost: Double
    let totalCostPerServing: Double
    
    var formattedTotalCost: String {
        "$\(String(format: "%.2f", totalCost / 100.0))"
    }
    
    var formattedCostPerServing: String {
        "$\(String(format: "%.2f", totalCostPerServing / 100.0))/serving"
    }
}

struct PriceIngredient: Codable, Identifiable {
    var id: String { name }
    let name: String
    let price: Double
    let amount: Double?
    let unit: String?
    
    var formattedPrice: String {
        "$\(String(format: "%.2f", price / 100.0))"
    }
}

// Nutrition widget data
struct NutritionWidgetData: Codable {
    let calories: String
    let carbs: String
    let fat: String
    let protein: String
    let bad: [NutritionWidgetItem]
    let good: [NutritionWidgetItem]
}

struct NutritionWidgetItem: Codable, Identifiable {
    var id: String { title }
    let title: String
    let amount: String
    let percentOfDailyNeeds: Double
}
