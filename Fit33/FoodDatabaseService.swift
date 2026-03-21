import Foundation
import Combine
import Supabase

// MARK: - Cloud Food Database Service

/// Cloud-based food database service using Supabase
/// - Searches USDA database via edge function
/// - Caches results in cloud for instant retrieval
/// - Tracks user history, favorites, and popular foods
@MainActor
class FoodDatabaseService: ObservableObject {
    static let shared = FoodDatabaseService()
    
    private var supabase: SupabaseClient {
        return SupabaseManager.shared.supabaseClient
    }
    
    @Published var recentFoods: [CloudFood] = []
    @Published var favoriteFoods: [CloudFood] = []
    @Published var popularFoods: [CloudFood] = []
    @Published var frequentFoods: [FrequentFoodItem] = []  // Most frequently used foods
    @Published var isLoadingRecent = false
    @Published var isLoadingFavorites = false
    @Published var isLoadingPopular = false
    @Published var isLoadingFrequent = false
    
    private var favoriteIds = Set<Int>()
    
    // Food usage frequency tracking (fdc_id -> count)
    private(set) var foodUsageCount: [Int: Int] = [:]
    private(set) var foodNameUsageCount: [String: Int] = [:]  // For foods without IDs
    
    // MARK: - Search Cache (for instant repeated searches)
    private var searchCache: [String: (foods: [CloudFood], timestamp: Date)] = [:]
    private let searchCacheLock = NSLock()
    private let cacheValidityDuration: TimeInterval = 300 // 5 minutes
    
    private init() {
        // Load favorites and frequent foods on init
        Task {
            await loadFavoriteIds()
            await loadFrequentFoods()
        }
    }
    
    // MARK: - Frequently Used Foods
    
    /// Load frequently used foods via server-side aggregation RPC
    func loadFrequentFoods() async {
        guard SupabaseManager.shared.isAuthenticated,
              SupabaseManager.shared.currentUser != nil else {
            return
        }
        
        isLoadingFrequent = true
        
        do {
            struct FrequentFoodRow: Codable {
                let fdcId: Int
                let foodName: String
                let calories: Double?
                let protein: Double?
                let carbs: Double?
                let fat: Double?
                let usageCount: Int
                let quantity: Double?
                let servingUnit: String?
                
                enum CodingKeys: String, CodingKey {
                    case fdcId = "fdc_id"
                    case foodName = "food_name"
                    case calories
                    case protein
                    case carbs
                    case fat
                    case usageCount = "usage_count"
                    case quantity
                    case servingUnit = "serving_unit"
                }
            }
            
            let rows: [FrequentFoodRow] = try await supabase
                .rpc("get_user_frequent_foods", params: ["p_limit": 20])
                .execute()
                .value
            
            // Build usage-count dictionaries for search prioritization
            var fdcCounts: [Int: Int] = [:]
            var nameCounts: [String: Int] = [:]
            
            var frequentItems: [FrequentFoodItem] = []
            
            for row in rows {
                let item = FrequentFoodItem(
                    fdcId: row.fdcId,
                    name: row.foodName,
                    calories: Int(row.calories ?? 0),
                    protein: Int(row.protein ?? 0),
                    carbs: Int(row.carbs ?? 0),
                    fat: Int(row.fat ?? 0),
                    servingSize: row.quantity ?? 1.0,
                    servingUnit: row.servingUnit ?? "serving",
                    usageCount: row.usageCount
                )
                frequentItems.append(item)
                
                if row.fdcId > 0 {
                    fdcCounts[row.fdcId] = row.usageCount
                } else {
                    nameCounts[row.foodName.lowercased()] = row.usageCount
                }
            }
            
            self.foodUsageCount = fdcCounts
            self.foodNameUsageCount = nameCounts
            self.frequentFoods = frequentItems
            self.isLoadingFrequent = false
            AppLogger.info("Successfully loaded \(frequentItems.count) frequently used foods", category: .nutrition)
            
        } catch {
            AppLogger.error("Error loading frequent foods: \(error.localizedDescription)", category: .nutrition)
            self.frequentFoods = []
            self.isLoadingFrequent = false
        }
    }
    
    /// Get usage count for a food (by FDC ID or name)
    func getUsageCount(fdcId: Int?, foodName: String) -> Int {
        if let fdcId = fdcId, fdcId > 0 {
            return foodUsageCount[fdcId] ?? 0
        }
        return foodNameUsageCount[foodName.lowercased()] ?? 0
    }
    
    // MARK: - Cache Management
    
    /// Get cached results if available and not expired
    func getCachedResults(for query: String) -> [CloudFood]? {
        let normalizedQuery = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        searchCacheLock.lock()
        defer { searchCacheLock.unlock() }
        guard let cached = searchCache[normalizedQuery] else { return nil }
        
        if Date().timeIntervalSince(cached.timestamp) < cacheValidityDuration {
            AppLogger.debug("Cache hit for '\(normalizedQuery)' - returning \(cached.foods.count) cached results", category: .nutrition)
            return cached.foods
        } else {
            searchCache.removeValue(forKey: normalizedQuery)
            return nil
        }
    }
    
    /// Store results in cache
    private func cacheResults(_ foods: [CloudFood], for query: String) {
        let normalizedQuery = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        searchCacheLock.lock()
        defer { searchCacheLock.unlock() }
        searchCache[normalizedQuery] = (foods: foods, timestamp: Date())
        
        if searchCache.count > 50 {
            let sortedKeys = searchCache.sorted { $0.value.timestamp < $1.value.timestamp }
            for i in 0..<10 {
                searchCache.removeValue(forKey: sortedKeys[i].key)
            }
        }
    }
    
    // MARK: - Search
    
    /// Search foods from cloud database (cached USDA data)
    func searchFoods(query: String) async throws -> [CloudFood] {
        AppLogger.debug("Searching for: '\(query)'", category: .nutrition)
        
        // Check cache first for instant results
        if let cachedResults = getCachedResults(for: query) {
            return cachedResults
        }
        
        // Prepare request body
        struct SearchRequest: Encodable {
            let action: String
            let query: String
            let pageSize: Int
            let pageNumber: Int
        }
        
        let request = SearchRequest(
            action: "search",
            query: query,
            pageSize: 100,
            pageNumber: 1
        )
        
        // Call Supabase edge function
        AppLogger.debug("Invoking edge function for food search", category: .nutrition)
        
        do {
            // Make the request using URLSession to get raw response
            guard let edgeFunctionURL = URL(string: "\(AppConfig.Supabase.url)/functions/v1/usda-food-search") else {
                throw NSError(domain: "FoodDB", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid edge function URL"])
            }
            var urlRequest = URLRequest(url: edgeFunctionURL)
            urlRequest.httpMethod = "POST"
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.setValue("Bearer \(AppConfig.Supabase.anonKey)", forHTTPHeaderField: "Authorization")
            urlRequest.httpBody = try JSONEncoder().encode(request)
            
            let (data, _) = try await URLSession.shared.data(for: urlRequest)
            
            // First check if this is an error response from the edge function
            if let errorResponse = try? JSONDecoder().decode(EdgeFunctionErrorResponse.self, from: data),
               let errorMessage = errorResponse.error {
                AppLogger.error("Edge function error: \(errorMessage)", category: .nutrition)
                throw NSError(domain: "EdgeFunction", code: -1, userInfo: [NSLocalizedDescriptionKey: errorMessage])
            }
            
            // Decode the search response
            let response = try JSONDecoder().decode(CloudFoodSearchResponse.self, from: data)
            
            AppLogger.info("Successfully found \(response.foods.count) foods (source: \(response.source))", category: .nutrition)
            
            // Cache the results for faster future lookups
            cacheResults(response.foods, for: query)
            
            return response.foods
        } catch let DecodingError.typeMismatch(type, context) {
            AppLogger.error("Type mismatch error: expected \(type), context: \(context.debugDescription), path: \(context.codingPath)", category: .nutrition)
            throw DecodingError.typeMismatch(type, context)
        } catch {
            AppLogger.error("Food search error (\(type(of: error))): \(error.localizedDescription)", category: .nutrition)
            throw error
        }
    }
    
    /// Get detailed food information by FDC ID
    func getFoodDetails(fdcId: Int) async throws -> CloudFood {
        AppLogger.debug("Fetching details for FDC ID: \(fdcId)", category: .nutrition)
        
        // Prepare request body
        struct DetailsRequest: Encodable {
            let action: String
            let fdcId: Int
        }
        
        let request = DetailsRequest(
            action: "details",
            fdcId: fdcId
        )
        
        let response: CloudFoodDetailsResponse = try await supabase.functions
            .invoke("usda-food-search", options: FunctionInvokeOptions(body: request))
        
        AppLogger.info("Successfully retrieved food details", category: .nutrition)
        return response.food
    }
    
    // MARK: - User Food History
    
    /// Load user's recent foods
    func loadRecentFoods(limit: Int = 10) async {
        guard SupabaseManager.shared.isAuthenticated,
              let userId = SupabaseManager.shared.currentUser?.id else {
            AppLogger.warning("User not authenticated - skipping recent foods", category: .nutrition)
            recentFoods = []
            return
        }
        
        isLoadingRecent = true
        
        do {
            struct RecentFoodRow: Codable {
                let foodItemId: Int?
                let loggedAt: String?
                
                enum CodingKeys: String, CodingKey {
                    case foodItemId = "food_item_id"
                    case loggedAt = "logged_at"
                }
            }
            
            let recentRows: [RecentFoodRow] = try await supabase
                .from("user_food_history")
                .select("food_item_id, logged_at")
                .eq("user_id", value: userId.uuidString)
                .order("logged_at", ascending: false)
                .limit(limit)
                .execute()
                .value
            
            let foodIds = recentRows.compactMap { $0.foodItemId }
            
            if !foodIds.isEmpty {
                // Fetch full food data
                let foods: [CloudFood] = try await supabase
                    .from("food_items")
                    .select()
                    .in("id", values: foodIds)
                    .execute()
                    .value
                
                self.recentFoods = foods
                self.isLoadingRecent = false
                
                AppLogger.info("Successfully loaded \(foods.count) recent foods", category: .nutrition)
            } else {
                self.recentFoods = []
                self.isLoadingRecent = false
            }
        } catch {
            AppLogger.error("Error loading recent foods: \(error.localizedDescription)", category: .nutrition)
            self.recentFoods = []
            self.isLoadingRecent = false
        }
    }
    
    /// Load user's favorite foods
    func loadFavoriteFoods() async {
        guard SupabaseManager.shared.isAuthenticated,
              let userId = SupabaseManager.shared.currentUser?.id else {
            AppLogger.warning("User not authenticated - skipping favorites", category: .nutrition)
            favoriteFoods = []
            return
        }
        
        isLoadingFavorites = true
        
        do {
            struct FavoriteRow: Codable {
                let foodItemId: Int
                
                enum CodingKeys: String, CodingKey {
                    case foodItemId = "food_item_id"
                }
            }
            
            // Get favorite food IDs
            let favoriteRows: [FavoriteRow] = try await supabase
                .from("user_favorite_foods")
                .select("food_item_id")
                .eq("user_id", value: userId.uuidString)
                .order("created_at", ascending: false)
                .execute()
                .value
            
            let foodIds = favoriteRows.map { $0.foodItemId }
            
            if !foodIds.isEmpty {
                // Fetch full food data
                let foods: [CloudFood] = try await supabase
                    .from("food_items")
                    .select()
                    .in("id", values: foodIds)
                    .execute()
                    .value
                
                self.favoriteFoods = foods
                self.isLoadingFavorites = false
                
                AppLogger.info("Successfully loaded \(foods.count) favorite foods", category: .nutrition)
            } else {
                self.favoriteFoods = []
                self.isLoadingFavorites = false
            }
        } catch {
            AppLogger.error("Error loading favorite foods: \(error.localizedDescription)", category: .nutrition)
            self.favoriteFoods = []
            self.isLoadingFavorites = false
        }
    }
    
    /// Load globally popular foods across all users
    /// Uses both food_items.log_count and aggregated user_food_history
    func loadPopularFoods(limit: Int = 20) async {
        isLoadingPopular = true
        
        do {
            // Strategy 1: Try food_items with log_count (fast, pre-computed)
            let foods: [CloudFood] = try await supabase
                .from("food_items")
                .select()
                .gt("log_count", value: 0)
                .order("log_count", ascending: false)
                .order("search_count", ascending: false)
                .limit(limit)
                .execute()
                .value
            
            if !foods.isEmpty {
                self.popularFoods = foods
                self.isLoadingPopular = false
                AppLogger.info("Successfully loaded \(foods.count) globally popular foods", category: .nutrition)
                return
            }
            
            // Strategy 2: Fallback - aggregate from user_food_history directly
            struct PopularFoodRow: Codable {
                let fdcId: Int
                let foodName: String
                let totalLogs: Int
                let uniqueUsers: Int
                
                enum CodingKeys: String, CodingKey {
                    case fdcId = "fdc_id"
                    case foodName = "food_name"
                    case totalLogs = "total_logs"
                    case uniqueUsers = "unique_users"
                }
            }
            
            let popularRows: [PopularFoodRow] = try await supabase
                .rpc("get_global_food_popularity", params: ["limit_count": limit])
                .execute()
                .value
            
            if !popularRows.isEmpty {
                // Convert to CloudFood by looking up food_items
                let fdcIds = popularRows.map { $0.fdcId }
                let foodItems: [CloudFood] = try await supabase
                    .from("food_items")
                    .select()
                    .in("fdc_id", values: fdcIds)
                    .execute()
                    .value
                
                // Maintain popularity order
                let orderedFoods = fdcIds.compactMap { fdcId in
                    foodItems.first(where: { $0.fdcId == fdcId })
                }
                
                self.popularFoods = orderedFoods
                self.isLoadingPopular = false
                AppLogger.info("Successfully loaded \(orderedFoods.count) popular foods from aggregation", category: .nutrition)
                return
            }
            
            self.popularFoods = []
            self.isLoadingPopular = false
        } catch {
            AppLogger.error("Error loading popular foods: \(error.localizedDescription)", category: .nutrition)
            self.popularFoods = []
            self.isLoadingPopular = false
        }
    }
    
    // MARK: - Favorites Management
    
    private func loadFavoriteIds() async {
        guard SupabaseManager.shared.isAuthenticated,
              let userId = SupabaseManager.shared.currentUser?.id else {
            return
        }
        
        do {
            struct FavoriteRow: Codable {
                let foodItemId: Int
                
                enum CodingKeys: String, CodingKey {
                    case foodItemId = "food_item_id"
                }
            }
            
            let rows: [FavoriteRow] = try await supabase
                .from("user_favorite_foods")
                .select("food_item_id")
                .eq("user_id", value: userId.uuidString)
                .execute()
                .value
            
            self.favoriteIds = Set(rows.map { $0.foodItemId })
        } catch {
            AppLogger.error("Error loading favorite IDs: \(error.localizedDescription)", category: .nutrition)
        }
    }
    
    func isFavorite(foodItemId: Int) -> Bool {
        return favoriteIds.contains(foodItemId)
    }
    
    func addToFavorites(foodItemId: Int) async throws {
        guard let userId = SupabaseManager.shared.currentUser?.id else {
            throw NSError(domain: "FoodDatabase", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        struct FavoriteInsert: Encodable {
            let user_id: String
            let food_item_id: Int
        }
        
        try await supabase
            .from("user_favorite_foods")
            .insert(FavoriteInsert(user_id: userId.uuidString, food_item_id: foodItemId))
            .execute()
        
        favoriteIds.insert(foodItemId)
        
        AppLogger.info("Successfully added food \(foodItemId) to favorites", category: .nutrition)
    }
    
    func removeFromFavorites(foodItemId: Int) async throws {
        guard let userId = SupabaseManager.shared.currentUser?.id else {
            throw NSError(domain: "FoodDatabase", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        try await supabase
            .from("user_favorite_foods")
            .delete()
            .eq("user_id", value: userId.uuidString)
            .eq("food_item_id", value: foodItemId)
            .execute()
        
        favoriteIds.remove(foodItemId)
        
        AppLogger.info("Successfully removed food \(foodItemId) from favorites", category: .nutrition)
    }
    
    // MARK: - Food History Logging
    
    func logFoodToHistory(
        fdcId: Int,
        foodName: String,
        mealType: MealType,
        quantity: Double,
        servingUnit: String,
        calories: Int,
        protein: Int,
        carbs: Int,
        fat: Int
    ) async throws {
        guard let userId = SupabaseManager.shared.currentUser?.id else {
            AppLogger.warning("User not authenticated - skipping history log", category: .nutrition)
            return
        }
        
        AppLogger.debug("Logging food: \(foodName) (FDC: \(fdcId)) - \(calories)cal, \(protein)p, \(carbs)c, \(fat)f", category: .nutrition)
        
        // First, check if this food exists in our food_items cache
        let foodItemQuery = supabase
            .from("food_items")
            .select("id")
            .eq("fdc_id", value: fdcId)
            .limit(1)
        
        struct FoodItemIdResult: Decodable {
            let id: Int
        }
        
        var foodItemId: Int? = nil
        
        do {
            let results: [FoodItemIdResult] = try await foodItemQuery.execute().value
            foodItemId = results.first?.id
            if let id = foodItemId {
                AppLogger.debug("Found cached food_item ID: \(id)", category: .nutrition)
            } else {
                AppLogger.warning("Food not in cache, logging with FDC ID only", category: .nutrition)
            }
        } catch {
            AppLogger.warning("Error checking food cache: \(error.localizedDescription)", category: .nutrition)
        }
        
        // Log to history
        struct FoodHistoryInsert: Encodable {
            let user_id: String
            let food_item_id: Int?
            let fdc_id: Int
            let food_name: String
            let meal_type: String
            let quantity: Double
            let serving_unit: String
            let calories: Int
            let protein: Int
            let carbs: Int
            let fat: Int
        }
        
        try await supabase
            .from("user_food_history")
            .insert(FoodHistoryInsert(
                user_id: userId.uuidString,
                food_item_id: foodItemId,
                fdc_id: fdcId,
                food_name: foodName,
                meal_type: mealType.rawValue,
                quantity: quantity,
                serving_unit: servingUnit,
                calories: calories,
                protein: protein,
                carbs: carbs,
                fat: fat
            ))
            .execute()
        
        AppLogger.info("Successfully logged food to history", category: .nutrition)
        
        if fdcId > 0 {
            foodUsageCount[fdcId, default: 0] += 1
        } else {
            foodNameUsageCount[foodName.lowercased(), default: 0] += 1
        }
        
        // Immediately update frequent foods list with the new entry
        // This ensures the user sees their logged food in "Quick Add" right away
        let newItem = FrequentFoodItem(
            fdcId: fdcId,
            name: foodName,
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            servingSize: quantity,
            servingUnit: servingUnit,
            usageCount: (fdcId > 0 ? foodUsageCount[fdcId] : foodNameUsageCount[foodName.lowercased()]) ?? 1
        )
        
        if let existingIdx = frequentFoods.firstIndex(where: { $0.fdcId == fdcId && fdcId > 0 || $0.name.lowercased() == foodName.lowercased() }) {
            let existing = frequentFoods[existingIdx]
            frequentFoods[existingIdx] = FrequentFoodItem(
                fdcId: existing.fdcId,
                name: existing.name,
                calories: calories,
                protein: protein,
                carbs: carbs,
                fat: fat,
                servingSize: quantity,
                servingUnit: servingUnit,
                usageCount: existing.usageCount + 1
            )
        } else {
            frequentFoods.insert(newItem, at: 0)
            if frequentFoods.count > 15 {
                frequentFoods = Array(frequentFoods.prefix(15))
            }
        }
        
        frequentFoods.sort { $0.usageCount > $1.usageCount }
        
        // Also increment global popularity count in background
        await incrementGlobalFoodPopularity(fdcId: fdcId, foodName: foodName)
    }
    
    /// Increment the global log_count on food_items for cross-user popularity
    private func incrementGlobalFoodPopularity(fdcId: Int, foodName: String) async {
        guard fdcId > 0 else { return }
        
        do {
            // Try to increment log_count on the food_items table
            // This tracks how popular a food is across ALL users
            try await supabase.rpc("increment_food_log_count", params: ["fdc_id_param": fdcId])
                .execute()
            AppLogger.debug("Incremented global popularity for FDC \(fdcId)", category: .nutrition)
        } catch {
            // Non-critical - just log and continue
            // The RPC might not exist yet, we'll create it
            AppLogger.warning("Could not increment global popularity: \(error.localizedDescription)", category: .nutrition)
        }
    }
    
    /// Remove the most recent entry for a food from history (when meal is deleted)
    func removeFromFoodHistory(fdcId: Int, foodName: String) async {
        guard let userId = SupabaseManager.shared.currentUser?.id else {
            AppLogger.warning("User not authenticated - skipping history removal", category: .nutrition)
            return
        }
        
        do {
            // Delete the most recent entry for this food
            // We use a subquery or just delete based on food identifiers
            if fdcId > 0 {
                // Delete by FDC ID - get the most recent and delete it
                try await supabase
                    .from("user_food_history")
                    .delete()
                    .eq("user_id", value: userId.uuidString)
                    .eq("fdc_id", value: fdcId)
                    .order("logged_at", ascending: false)
                    .limit(1)
                    .execute()
                
                if let count = foodUsageCount[fdcId], count > 0 {
                    foodUsageCount[fdcId] = count - 1
                }
            } else {
                try await supabase
                    .from("user_food_history")
                    .delete()
                    .eq("user_id", value: userId.uuidString)
                    .eq("food_name", value: foodName)
                    .order("logged_at", ascending: false)
                    .limit(1)
                    .execute()
                
                let key = foodName.lowercased()
                if let count = foodNameUsageCount[key], count > 0 {
                    foodNameUsageCount[key] = count - 1
                }
            }
            
            AppLogger.info("Successfully removed food from history: \(foodName)", category: .nutrition)
        } catch {
            AppLogger.error("Error removing from food history: \(error.localizedDescription)", category: .nutrition)
        }
    }
}

// MARK: - Cloud Food Models

/// CloudFood handles BOTH direct USDA API responses AND cached database responses
/// Database returns snake_case columns with direct nutrition values
/// USDA API returns camelCase with foodNutrients array
struct CloudFood: Decodable {
    // Core identifiers
    let fdcId: Int
    let description: String
    let dataType: String?
    let brandName: String?
    let brandOwner: String?
    let foodCategory: String?
    let servingSize: Double?
    let servingSizeUnit: String?
    let householdServingFullText: String?
    
    // Direct nutrition values (from database cache)
    let calories: Double?
    let protein: Double?
    let carbohydrates: Double?
    let totalFat: Double?
    let saturatedFat: Double?
    let fiber: Double?
    let sugar: Double?
    let sodium: Double?
    let cholesterol: Double?
    let calcium: Double?
    let iron: Double?
    let vitaminC: Double?
    
    // Raw nutrient array (from USDA API or database nutrition_data column)
    let foodNutrients: [USDANutrient]?
    
    // Portions from USDA (for serving size options like "1 cup", "100g", etc.)
    let portions: [CloudFoodPortion]?
    
    // CodingKeys to handle snake_case from database AND camelCase from USDA API
    enum CodingKeys: String, CodingKey {
        case fdcId = "fdc_id"
        case fdcIdCamel = "fdcId"
        case description
        case name  // Database uses 'name' column
        case dataType = "data_type"
        case dataTypeCamel = "dataType"
        case brandName = "brand_name"
        case brandNameCamel = "brandName"
        case brandOwner = "brand_owner"
        case brandOwnerCamel = "brandOwner"
        case foodCategory = "category"
        case foodCategoryCamel = "foodCategory"
        case servingSize = "serving_size"
        case servingSizeCamel = "servingSize"
        case servingSizeUnit = "serving_unit"
        case servingSizeUnitCamel = "servingSizeUnit"
        case householdServingFullText = "household_serving"
        case householdServingFullTextCamel = "householdServingFullText"
        // Direct nutrition columns
        case calories
        case protein
        case carbohydrates
        case totalFat = "total_fat"
        case saturatedFat = "saturated_fat"
        case fiber
        case sugar
        case sodium
        case cholesterol
        case calcium
        case iron
        case vitaminC = "vitamin_c"
        // Raw nutrient data
        case foodNutrients
        case nutritionData = "nutrition_data"
        // Portions
        case portions
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // fdcId: try snake_case first, then camelCase
        if let id = try? container.decode(Int.self, forKey: .fdcId) {
            fdcId = id
        } else if let id = try? container.decode(Int.self, forKey: .fdcIdCamel) {
            fdcId = id
        } else {
            throw DecodingError.keyNotFound(CodingKeys.fdcId, DecodingError.Context(codingPath: container.codingPath, debugDescription: "fdcId or fdc_id required"))
        }
        
        // description: try description first, then name (database column)
        if let desc = try? container.decode(String.self, forKey: .description) {
            description = desc
        } else if let name = try? container.decode(String.self, forKey: .name) {
            description = name
        } else {
            throw DecodingError.keyNotFound(CodingKeys.description, DecodingError.Context(codingPath: container.codingPath, debugDescription: "description or name required"))
        }
        
        // dataType
        dataType = (try? container.decode(String.self, forKey: .dataType)) ?? (try? container.decode(String.self, forKey: .dataTypeCamel))
        
        // brandName
        brandName = (try? container.decode(String.self, forKey: .brandName)) ?? (try? container.decode(String.self, forKey: .brandNameCamel))
        
        // brandOwner  
        brandOwner = (try? container.decode(String.self, forKey: .brandOwner)) ?? (try? container.decode(String.self, forKey: .brandOwnerCamel))
        
        // foodCategory
        foodCategory = (try? container.decode(String.self, forKey: .foodCategory)) ?? (try? container.decode(String.self, forKey: .foodCategoryCamel))
        
        // servingSize
        servingSize = (try? container.decode(Double.self, forKey: .servingSize)) ?? (try? container.decode(Double.self, forKey: .servingSizeCamel))
        
        // servingSizeUnit
        servingSizeUnit = (try? container.decode(String.self, forKey: .servingSizeUnit)) ?? (try? container.decode(String.self, forKey: .servingSizeUnitCamel))
        
        // householdServingFullText
        householdServingFullText = (try? container.decode(String.self, forKey: .householdServingFullText)) ?? (try? container.decode(String.self, forKey: .householdServingFullTextCamel))
        
        // Direct nutrition values (from database cache)
        calories = try? container.decode(Double.self, forKey: .calories)
        protein = try? container.decode(Double.self, forKey: .protein)
        carbohydrates = try? container.decode(Double.self, forKey: .carbohydrates)
        totalFat = try? container.decode(Double.self, forKey: .totalFat)
        saturatedFat = try? container.decode(Double.self, forKey: .saturatedFat)
        fiber = try? container.decode(Double.self, forKey: .fiber)
        sugar = try? container.decode(Double.self, forKey: .sugar)
        sodium = try? container.decode(Double.self, forKey: .sodium)
        cholesterol = try? container.decode(Double.self, forKey: .cholesterol)
        calcium = try? container.decode(Double.self, forKey: .calcium)
        iron = try? container.decode(Double.self, forKey: .iron)
        vitaminC = try? container.decode(Double.self, forKey: .vitaminC)
        
        // foodNutrients: try camelCase first, then nutrition_data from database
        if let nutrients = try? container.decode([USDANutrient].self, forKey: .foodNutrients) {
            foodNutrients = nutrients
        } else if let nutrients = try? container.decode([USDANutrient].self, forKey: .nutritionData) {
            foodNutrients = nutrients
        } else {
            foodNutrients = nil
        }
        
        // Portions
        portions = try? container.decode([CloudFoodPortion].self, forKey: .portions)
    }
    
    func toProcessedFoodItem() -> ProcessedFoodItem {
        AppLogger.debug("Converting FDC \(fdcId): \(description)", category: .nutrition)
        
        // PRIORITY 1: Use direct nutrition values from database cache
        // These are the accurate USDA values stored per 100g
        var finalCalories: Double = calories ?? 0
        var finalProtein: Double = protein ?? 0
        var finalCarbs: Double = carbohydrates ?? 0
        var finalFat: Double = totalFat ?? 0
        var finalSaturatedFat: Double = saturatedFat ?? 0
        var finalFiber: Double = fiber ?? 0
        var finalSugar: Double = sugar ?? 0
        var finalSodium: Double = sodium ?? 0
        var finalCholesterol: Double = cholesterol ?? 0
        var finalCalcium: Double = calcium ?? 0
        var finalIron: Double = iron ?? 0
        var finalVitaminC: Double = vitaminC ?? 0
        
        // PRIORITY 2: If direct values are all zero, try foodNutrients array
        let hasDirectValues = finalCalories > 0 || finalProtein > 0 || finalCarbs > 0 || finalFat > 0
        
        if !hasDirectValues, let nutrients = foodNutrients {
            AppLogger.debug("Using foodNutrients array (\(nutrients.count) nutrients)", category: .nutrition)
            for nutrient in nutrients {
                switch nutrient.nutrientNumber {
                case "208": finalCalories = nutrient.value
                case "203": finalProtein = nutrient.value
                case "205": finalCarbs = nutrient.value
                case "204": finalFat = nutrient.value
                case "606": finalSaturatedFat = nutrient.value
                case "291": finalFiber = nutrient.value
                case "269": finalSugar = nutrient.value
                case "307": finalSodium = nutrient.value
                case "601": finalCholesterol = nutrient.value
                case "301": finalCalcium = nutrient.value
                case "303": finalIron = nutrient.value
                case "401": finalVitaminC = nutrient.value
                default: break
                }
            }
        }
        
        AppLogger.debug("Final nutrition: \(Int(finalCalories)) cal, \(finalProtein)p, \(finalCarbs)c, \(finalFat)f", category: .nutrition)
        
        let nutrition = NutritionInfo(
            calories: finalCalories,
            protein: finalProtein,
            carbohydrates: finalCarbs,
            totalFat: finalFat,
            saturatedFat: finalSaturatedFat,
            fiber: finalFiber,
            sugar: finalSugar,
            sodium: finalSodium,
            cholesterol: finalCholesterol,
            calcium: finalCalcium,
            iron: finalIron,
            vitaminC: finalVitaminC
        )
        
        // Convert portions to FoodPortion array
        let foodPortions: [FoodPortion] = (portions ?? []).map { portion in
            FoodPortion(
                id: portion.id,
                amount: portion.amount,
                unit: portion.unit,
                gramWeight: portion.gramWeight,
                description: portion.portionDescription
            )
        }
        
        // For Foundation/SR Legacy foods, ensure we have 100g as default
        // USDA nutrition data is ALWAYS per 100g for these data types
        let effectiveServingSize = servingSize ?? 100.0
        
        let result = ProcessedFoodItem(
            id: fdcId,
            name: description,
            brandName: brandName,
            description: description,
            category: foodCategory,
            servingSize: effectiveServingSize,
            servingUnit: servingSizeUnit ?? "g",
            nutrition: nutrition,
            portions: foodPortions,
            dataType: dataType  // Pass dataType for ranking
        )
        
        AppLogger.info("Successfully converted food with \(foodPortions.count) portions, dataType: \(dataType ?? "unknown")", category: .nutrition)
        return result
    }
}

struct CloudFoodPortion: Decodable {
    let id: Int
    let amount: Double
    let unit: String
    let gramWeight: Double
    let portionDescription: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case amount
        case unit
        case gramWeight = "gram_weight"
        case gramWeightCamel = "gramWeight"
        case description  // Original USDA format
        case portionDescription  // Edge function format
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // id: with fallback to 0
        id = (try? container.decode(Int.self, forKey: .id)) ?? 0
        
        // amount: with fallback to 1
        amount = (try? container.decode(Double.self, forKey: .amount)) ?? 1.0
        
        // unit: with fallback to "serving" if missing or null
        unit = (try? container.decode(String.self, forKey: .unit)) ?? "serving"
        
        // gramWeight: try snake_case first, then camelCase, then default
        if let gw = try? container.decode(Double.self, forKey: .gramWeight) {
            gramWeight = gw
        } else if let gw = try? container.decode(Double.self, forKey: .gramWeightCamel) {
            gramWeight = gw
        } else {
            gramWeight = 100.0 // Default to 100g if not specified
        }
        
        // portionDescription: try both keys
        if let desc = try? container.decode(String.self, forKey: .portionDescription) {
            portionDescription = desc
        } else {
            portionDescription = try? container.decode(String.self, forKey: .description)
        }
    }
}

struct CloudFoodSearchResponse: Decodable {
    let source: String
    let foods: [CloudFood]
    let totalHits: Int?
    let query: String
}

struct CloudFoodDetailsResponse: Decodable {
    let source: String
    let food: CloudFood
}

/// Response when edge function returns an error
struct EdgeFunctionErrorResponse: Decodable {
    let error: String?
}

// MARK: - Frequent Food Item

/// Lightweight struct for frequently used foods
struct FrequentFoodItem: Identifiable {
    let id: String
    let fdcId: Int
    let name: String
    let calories: Int
    let protein: Int
    let carbs: Int
    let fat: Int
    let servingSize: Double
    let servingUnit: String
    let usageCount: Int
    
    init(fdcId: Int, name: String, calories: Int, protein: Int, carbs: Int, fat: Int, servingSize: Double, servingUnit: String, usageCount: Int) {
        self.id = fdcId > 0 ? String(fdcId) : name.lowercased()
        self.fdcId = fdcId
        self.name = name
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.servingSize = servingSize
        self.servingUnit = servingUnit
        self.usageCount = usageCount
    }
    
    /// Convert to ProcessedFoodItem for use in search results
    func toProcessedFoodItem() -> ProcessedFoodItem {
        let nutrition = NutritionInfo(
            calories: Double(calories),
            protein: Double(protein),
            carbohydrates: Double(carbs),
            totalFat: Double(fat),
            saturatedFat: 0,
            fiber: 0,
            sugar: 0,
            sodium: 0,
            cholesterol: 0,
            calcium: 0,
            iron: 0,
            vitaminC: 0
        )
        
        return ProcessedFoodItem(
            id: fdcId > 0 ? fdcId : name.hashValue,
            name: name,
            brandName: nil,
            description: name,
            category: nil,
            servingSize: servingSize,
            servingUnit: servingUnit,
            nutrition: nutrition,
            portions: [],
            dataType: "Hardcoded"  // Local hardcoded foods
        )
    }
}
