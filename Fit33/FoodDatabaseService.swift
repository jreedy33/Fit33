import Foundation
import Combine
import Supabase

// MARK: - Cloud Food Database Service

/// Cloud-based food database service using Supabase
/// - Searches USDA database via edge function
/// - Caches results in cloud for instant retrieval
/// - Tracks user history, favorites, and popular foods
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
    private let cacheValidityDuration: TimeInterval = 300 // 5 minutes
    
    private init() {
        // Load favorites and frequent foods on init
        Task {
            await loadFavoriteIds()
            await loadFrequentFoods()
        }
    }
    
    // MARK: - Frequently Used Foods
    
    /// Load frequently used foods based on user's food history
    func loadFrequentFoods() async {
        guard SupabaseManager.shared.isAuthenticated,
              let userId = SupabaseManager.shared.currentUser?.id else {
            return
        }
        
        await MainActor.run { isLoadingFrequent = true }
        
        do {
            // Query to get food usage counts grouped by food name
            // We use RPC or aggregate directly from user_food_history
            struct FoodUsageRow: Codable {
                let fdcId: Int
                let foodName: String
                let usageCount: Int
                
                enum CodingKeys: String, CodingKey {
                    case fdcId = "fdc_id"
                    case foodName = "food_name"
                    case usageCount = "usage_count"
                }
            }
            
            // Get aggregated food usage from history
            // Note: This requires a view or function in Supabase, so we'll query raw history and aggregate client-side
            struct HistoryRow: Codable {
                let fdcId: Int
                let foodName: String
                let calories: Int?
                let protein: Int?
                let carbs: Int?
                let fat: Int?
                let quantity: Double?
                let servingUnit: String?
                
                enum CodingKeys: String, CodingKey {
                    case fdcId = "fdc_id"
                    case foodName = "food_name"
                    case calories
                    case protein
                    case carbs
                    case fat
                    case quantity
                    case servingUnit = "serving_unit"
                }
            }
            
            let historyRows: [HistoryRow] = try await supabase
                .from("user_food_history")
                .select("fdc_id, food_name, calories, protein, carbs, fat, quantity, serving_unit")
                .eq("user_id", value: userId.uuidString)
                .execute()
                .value
            
            // Aggregate by food name and count occurrences
            var usageByFdcId: [Int: (count: Int, row: HistoryRow)] = [:]
            var usageByName: [String: (count: Int, row: HistoryRow)] = [:]
            
            for row in historyRows {
                if row.fdcId > 0 {
                    if let existing = usageByFdcId[row.fdcId] {
                        usageByFdcId[row.fdcId] = (count: existing.count + 1, row: row)
                    } else {
                        usageByFdcId[row.fdcId] = (count: 1, row: row)
                    }
                } else {
                    // Use food name for custom/scanned foods
                    let key = row.foodName.lowercased()
                    if let existing = usageByName[key] {
                        usageByName[key] = (count: existing.count + 1, row: row)
                    } else {
                        usageByName[key] = (count: 1, row: row)
                    }
                }
            }
            
            // Update usage counts for search prioritization
            await MainActor.run {
                self.foodUsageCount = usageByFdcId.mapValues { $0.count }
                self.foodNameUsageCount = usageByName.mapValues { $0.count }
            }
            
            // Sort by usage count and take top 15
            let sortedByFdcId = usageByFdcId.sorted { $0.value.count > $1.value.count }
            let sortedByName = usageByName.sorted { $0.value.count > $1.value.count }
            
            // Convert to FrequentFoodItem objects
            var frequentItems: [FrequentFoodItem] = []
            
            // Add FDC-based frequent foods (top 10)
            for (fdcId, data) in sortedByFdcId.prefix(10) {
                let row = data.row
                let item = FrequentFoodItem(
                    fdcId: fdcId,
                    name: row.foodName,
                    calories: row.calories ?? 0,
                    protein: row.protein ?? 0,
                    carbs: row.carbs ?? 0,
                    fat: row.fat ?? 0,
                    servingSize: row.quantity ?? 1.0,
                    servingUnit: row.servingUnit ?? "serving",
                    usageCount: data.count
                )
                frequentItems.append(item)
            }
            
            // Add name-based frequent foods (top 5 that aren't duplicates)
            var addedNames = Set(frequentItems.map { $0.name.lowercased() })
            for (_, data) in sortedByName.prefix(5) {
                let row = data.row
                if !addedNames.contains(row.foodName.lowercased()) {
                    addedNames.insert(row.foodName.lowercased())
                    let item = FrequentFoodItem(
                        fdcId: row.fdcId,
                        name: row.foodName,
                        calories: row.calories ?? 0,
                        protein: row.protein ?? 0,
                        carbs: row.carbs ?? 0,
                        fat: row.fat ?? 0,
                        servingSize: row.quantity ?? 1.0,
                        servingUnit: row.servingUnit ?? "serving",
                        usageCount: data.count
                    )
                    frequentItems.append(item)
                }
            }
            
            // Sort final list by usage count
            frequentItems.sort { $0.usageCount > $1.usageCount }
            
            await MainActor.run {
                self.frequentFoods = frequentItems
                self.isLoadingFrequent = false
                print("✅ [CLOUD] Loaded \(frequentItems.count) frequently used foods")
            }
            
        } catch {
            print("❌ [CLOUD] Error loading frequent foods: \(error)")
            await MainActor.run {
                self.frequentFoods = []
                self.isLoadingFrequent = false
            }
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
        guard let cached = searchCache[normalizedQuery] else { return nil }
        
        // Check if cache is still valid
        if Date().timeIntervalSince(cached.timestamp) < cacheValidityDuration {
            print("⚡️ [CACHE] Hit for '\(normalizedQuery)' - returning \(cached.foods.count) cached results")
            return cached.foods
        } else {
            // Cache expired, remove it
            searchCache.removeValue(forKey: normalizedQuery)
            return nil
        }
    }
    
    /// Store results in cache
    private func cacheResults(_ foods: [CloudFood], for query: String) {
        let normalizedQuery = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        searchCache[normalizedQuery] = (foods: foods, timestamp: Date())
        
        // Limit cache size to 50 queries
        if searchCache.count > 50 {
            // Remove oldest entries
            let sortedKeys = searchCache.sorted { $0.value.timestamp < $1.value.timestamp }
            for i in 0..<10 {
                searchCache.removeValue(forKey: sortedKeys[i].key)
            }
        }
    }
    
    // MARK: - Search
    
    /// Search foods from cloud database (cached USDA data)
    func searchFoods(query: String) async throws -> [CloudFood] {
        print("🔍 [CLOUD] Searching for: '\(query)'")
        
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
        print("📤 [CLOUD] Invoking edge function...")
        
        do {
            // Make the request using URLSession to get raw response
            var urlRequest = URLRequest(url: URL(string: "https://ehooeghabzefgoqzugrc.supabase.co/functions/v1/usda-food-search")!)
            urlRequest.httpMethod = "POST"
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.setValue("Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVob29lZ2hhYnplZmdvcXp1Z3JjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjM4NDc4NjQsImV4cCI6MjA3OTQyMzg2NH0.6-QWDr5B279hybtu9MbPVhmBKlyzFq1GK9P7zlDXuY0", forHTTPHeaderField: "Authorization")
            urlRequest.httpBody = try JSONEncoder().encode(request)
            
            let (data, _) = try await URLSession.shared.data(for: urlRequest)
            
            // First check if this is an error response from the edge function
            if let errorResponse = try? JSONDecoder().decode(EdgeFunctionErrorResponse.self, from: data),
               let errorMessage = errorResponse.error {
                print("❌ [CLOUD] Edge function error: \(errorMessage)")
                throw NSError(domain: "EdgeFunction", code: -1, userInfo: [NSLocalizedDescriptionKey: errorMessage])
            }
            
            // Decode the search response
            let response = try JSONDecoder().decode(CloudFoodSearchResponse.self, from: data)
            
            print("✅ [CLOUD] Found \(response.foods.count) foods (source: \(response.source))")
            
            // Cache the results for faster future lookups
            cacheResults(response.foods, for: query)
            
            return response.foods
        } catch let DecodingError.typeMismatch(type, context) {
            print("❌ [CLOUD] Type mismatch error:")
            print("   Expected type: \(type)")
            print("   Context: \(context.debugDescription)")
            print("   Coding path: \(context.codingPath)")
            throw DecodingError.typeMismatch(type, context)
        } catch {
            print("❌ [CLOUD] Error: \(error)")
            print("   Error type: \(type(of: error))")
            if let decodingError = error as? DecodingError {
                print("   Decoding error details: \(decodingError)")
            }
            throw error
        }
    }
    
    /// Get detailed food information by FDC ID
    func getFoodDetails(fdcId: Int) async throws -> CloudFood {
        print("🔍 [CLOUD] Fetching details for FDC ID: \(fdcId)")
        
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
        
        print("✅ [CLOUD] Retrieved food details")
        return response.food
    }
    
    // MARK: - User Food History
    
    /// Load user's recent foods
    func loadRecentFoods(limit: Int = 10) async {
        guard SupabaseManager.shared.isAuthenticated,
              let userId = SupabaseManager.shared.currentUser?.id else {
            print("⚠️ [CLOUD] User not authenticated - skipping recent foods")
            await MainActor.run { recentFoods = [] }
            return
        }
        
        await MainActor.run { isLoadingRecent = true }
        
        do {
            struct RecentFoodRow: Codable {
                let foodItemId: Int
                let lastLogged: String
                let logFrequency: Int
                
                enum CodingKeys: String, CodingKey {
                    case foodItemId = "food_item_id"
                    case lastLogged = "last_logged"
                    case logFrequency = "log_frequency"
                }
            }
            
            // Get recent food IDs with logging info
            let recentRows: [RecentFoodRow] = try await supabase
                .from("user_food_history")
                .select("food_item_id, logged_at")
                .eq("user_id", value: userId.uuidString)
                .order("logged_at", ascending: false)
                .limit(limit)
                .execute()
                .value
            
            let foodIds = recentRows.map { $0.foodItemId }
            
            if !foodIds.isEmpty {
                // Fetch full food data
                let foods: [CloudFood] = try await supabase
                    .from("food_items")
                    .select()
                    .in("id", values: foodIds)
                    .execute()
                    .value
                
                await MainActor.run {
                    self.recentFoods = foods
                    self.isLoadingRecent = false
                }
                
                print("✅ [CLOUD] Loaded \(foods.count) recent foods")
            } else {
                await MainActor.run {
                    self.recentFoods = []
                    self.isLoadingRecent = false
                }
            }
        } catch {
            print("❌ [CLOUD] Error loading recent foods: \(error)")
            await MainActor.run {
                self.recentFoods = []
                self.isLoadingRecent = false
            }
        }
    }
    
    /// Load user's favorite foods
    func loadFavoriteFoods() async {
        guard SupabaseManager.shared.isAuthenticated,
              let userId = SupabaseManager.shared.currentUser?.id else {
            print("⚠️ [CLOUD] User not authenticated - skipping favorites")
            await MainActor.run { favoriteFoods = [] }
            return
        }
        
        await MainActor.run { isLoadingFavorites = true }
        
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
                
                await MainActor.run {
                    self.favoriteFoods = foods
                    self.isLoadingFavorites = false
                }
                
                print("✅ [CLOUD] Loaded \(foods.count) favorite foods")
            } else {
                await MainActor.run {
                    self.favoriteFoods = []
                    self.isLoadingFavorites = false
                }
            }
        } catch {
            print("❌ [CLOUD] Error loading favorite foods: \(error)")
            await MainActor.run {
                self.favoriteFoods = []
                self.isLoadingFavorites = false
            }
        }
    }
    
    /// Load globally popular foods across all users
    /// Uses both food_items.log_count and aggregated user_food_history
    func loadPopularFoods(limit: Int = 20) async {
        await MainActor.run { isLoadingPopular = true }
        
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
                await MainActor.run {
                    self.popularFoods = foods
                    self.isLoadingPopular = false
                }
                print("✅ [CLOUD] Loaded \(foods.count) globally popular foods")
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
                
                await MainActor.run {
                    self.popularFoods = orderedFoods
                    self.isLoadingPopular = false
                }
                print("✅ [CLOUD] Loaded \(orderedFoods.count) popular foods from aggregation")
                return
            }
            
            await MainActor.run {
                self.popularFoods = []
                self.isLoadingPopular = false
            }
        } catch {
            print("❌ [CLOUD] Error loading popular foods: \(error)")
            await MainActor.run {
                self.popularFoods = []
                self.isLoadingPopular = false
            }
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
            
            await MainActor.run {
                self.favoriteIds = Set(rows.map { $0.foodItemId })
            }
        } catch {
            print("❌ [CLOUD] Error loading favorite IDs: \(error)")
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
        
        await MainActor.run {
            favoriteIds.insert(foodItemId)
        }
        
        print("✅ [CLOUD] Added food \(foodItemId) to favorites")
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
        
        await MainActor.run {
            favoriteIds.remove(foodItemId)
        }
        
        print("✅ [CLOUD] Removed food \(foodItemId) from favorites")
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
            print("⚠️ [CLOUD] User not authenticated - skipping history log")
            return
        }
        
        print("📝 [CLOUD] Logging food: \(foodName) (FDC: \(fdcId)) - \(calories)cal, \(protein)p, \(carbs)c, \(fat)f")
        
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
                print("✅ [CLOUD] Found cached food_item ID: \(id)")
            } else {
                print("⚠️ [CLOUD] Food not in cache, logging with FDC ID only")
            }
        } catch {
            print("⚠️ [CLOUD] Error checking food cache: \(error)")
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
        
        print("✅ [CLOUD] Successfully logged food to history")
        
        // Update local usage count immediately for responsive UI
        await MainActor.run {
            if fdcId > 0 {
                foodUsageCount[fdcId, default: 0] += 1
            } else {
                foodNameUsageCount[foodName.lowercased(), default: 0] += 1
            }
        }
        
        // Immediately update frequent foods list with the new entry
        // This ensures the user sees their logged food in "Quick Add" right away
        await MainActor.run {
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
            
            // Update or insert into frequent foods
            if let existingIdx = frequentFoods.firstIndex(where: { $0.fdcId == fdcId && fdcId > 0 || $0.name.lowercased() == foodName.lowercased() }) {
                // Update count on existing entry
                let existing = frequentFoods[existingIdx]
                frequentFoods[existingIdx] = FrequentFoodItem(
                    fdcId: existing.fdcId,
                    name: existing.name,
                    calories: calories, // Use latest nutrition
                    protein: protein,
                    carbs: carbs,
                    fat: fat,
                    servingSize: quantity,
                    servingUnit: servingUnit,
                    usageCount: existing.usageCount + 1
                )
            } else {
                // Add as new frequent food
                frequentFoods.insert(newItem, at: 0)
                // Keep max 15 items
                if frequentFoods.count > 15 {
                    frequentFoods = Array(frequentFoods.prefix(15))
                }
            }
            
            // Re-sort by usage count
            frequentFoods.sort { $0.usageCount > $1.usageCount }
        }
        
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
            print("📊 [CLOUD] Incremented global popularity for FDC \(fdcId)")
        } catch {
            // Non-critical - just log and continue
            // The RPC might not exist yet, we'll create it
            print("⚠️ [CLOUD] Could not increment global popularity: \(error.localizedDescription)")
        }
    }
    
    /// Remove the most recent entry for a food from history (when meal is deleted)
    func removeFromFoodHistory(fdcId: Int, foodName: String) async {
        guard let userId = SupabaseManager.shared.currentUser?.id else {
            print("⚠️ [CLOUD] User not authenticated - skipping history removal")
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
                
                // Decrement local count
                await MainActor.run {
                    if let count = foodUsageCount[fdcId], count > 0 {
                        foodUsageCount[fdcId] = count - 1
                    }
                }
            } else {
                // Delete by food name
                try await supabase
                    .from("user_food_history")
                    .delete()
                    .eq("user_id", value: userId.uuidString)
                    .eq("food_name", value: foodName)
                    .order("logged_at", ascending: false)
                    .limit(1)
                    .execute()
                
                // Decrement local count
                await MainActor.run {
                    let key = foodName.lowercased()
                    if let count = foodNameUsageCount[key], count > 0 {
                        foodNameUsageCount[key] = count - 1
                    }
                }
            }
            
            print("✅ [CLOUD] Removed food from history: \(foodName)")
        } catch {
            print("❌ [CLOUD] Error removing from history: \(error)")
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
        print("🔄 [CloudFood] Converting FDC \(fdcId): \(description)")
        
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
            print("📊 [CloudFood] Using foodNutrients array (\(nutrients.count) nutrients)")
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
        
        print("📊 [CloudFood] Final nutrition: \(Int(finalCalories)) cal, \(finalProtein)p, \(finalCarbs)c, \(finalFat)f")
        
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
        
        print("✅ [CloudFood] Converted successfully with \(foodPortions.count) portions, dataType: \(dataType ?? "unknown")")
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
