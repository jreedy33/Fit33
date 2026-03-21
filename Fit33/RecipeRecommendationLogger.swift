//
//  RecipeRecommendationLogger.swift
//  Fit33
//
//  Comprehensive logging for recipe recommendations to debug and improve quality
//

import Foundation

// MARK: - Recipe Recommendation Logger
class RecipeRecommendationLogger {
    static let shared = RecipeRecommendationLogger()
    
    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss.SSS"
        return df
    }()
    
    private var sessionLogs: [String] = []
    private let maxLogs = 500
    
    private init() {}
    
    // MARK: - Log Categories
    
    /// Log user preferences
    func logPreferences(liked: [String], disliked: [String], dietaryRestrictions: [String] = []) {
        let log = """
        
        ═══════════════════════════════════════════════════════════════
        🧑 USER PREFERENCES @ \(timestamp)
        ═══════════════════════════════════════════════════════════════
        ✅ LIKED INGREDIENTS (\(liked.count)):
           \(liked.isEmpty ? "None set" : liked.joined(separator: ", "))
        
        ❌ DISLIKED INGREDIENTS (\(disliked.count)):
           \(disliked.isEmpty ? "None set" : disliked.joined(separator: ", "))
        
        🥗 DIETARY RESTRICTIONS:
           \(dietaryRestrictions.isEmpty ? "None" : dietaryRestrictions.joined(separator: ", "))
        ═══════════════════════════════════════════════════════════════
        """
        AppLogger.debug("\(log)", category: .nutrition)
        addToSession(log)
    }
    
    /// Log API request
    func logAPIRequest(
        endpoint: String,
        query: String?,
        includeIngredients: String?,
        excludeIngredients: String?,
        minHealthScore: Int?,
        minProtein: Int?,
        maxSugar: Int?,
        mealType: String?,
        count: Int,
        offset: Int
    ) {
        let log = """
        
        📤 API REQUEST @ \(timestamp)
        ───────────────────────────────────────────────────────────────
        Endpoint: \(endpoint)
        Query: \(query ?? "none")
        Include: \(includeIngredients ?? "none")
        Exclude: \(excludeIngredients ?? "none")
        Min Health Score: \(minHealthScore.map { String($0) } ?? "not set")
        Min Protein: \(minProtein.map { "\($0)g" } ?? "not set")
        Max Sugar: \(maxSugar.map { "\($0)g" } ?? "not set")
        Meal Type: \(mealType ?? "any")
        Requesting: \(count) recipes, offset: \(offset)
        ───────────────────────────────────────────────────────────────
        """
        AppLogger.debug("\(log)", category: .nutrition)
        addToSession(log)
    }
    
    /// Log API response with recipe details
    func logAPIResponse(
        totalResults: Int,
        returnedCount: Int,
        recipes: [(id: Int, title: String, healthScore: Int?, calories: Int?, protein: Int?)]
    ) {
        var recipeList = ""
        for (index, recipe) in recipes.prefix(15).enumerated() {
            let healthEmoji = getHealthEmoji(score: recipe.healthScore)
            recipeList += """
               \(index + 1). \(healthEmoji) "\(recipe.title)"
                  Health: \(recipe.healthScore.map { "\($0)/100" } ?? "N/A") | Cal: \(recipe.calories.map { "\($0)" } ?? "N/A") | Protein: \(recipe.protein.map { "\($0)g" } ?? "N/A")
            
            """
        }
        
        let log = """
        
        📥 API RESPONSE @ \(timestamp)
        ───────────────────────────────────────────────────────────────
        Total Available: \(totalResults)
        Returned: \(returnedCount)
        
        TOP RECIPES:
        \(recipeList.isEmpty ? "   No recipes returned!" : recipeList)
        ───────────────────────────────────────────────────────────────
        """
        AppLogger.debug("\(log)", category: .nutrition)
        addToSession(log)
    }
    
    /// Log final recommendations shown to user
    func logFinalRecommendations(
        recipes: [(id: Int, title: String, healthScore: Int?, calories: Int?, protein: Int?)],
        source: String
    ) {
        var recipeList = ""
        var healthScores: [Int] = []
        
        for (index, recipe) in recipes.enumerated() {
            let healthEmoji = getHealthEmoji(score: recipe.healthScore)
            if let score = recipe.healthScore {
                healthScores.append(score)
            }
            recipeList += """
               \(index + 1). \(healthEmoji) "\(recipe.title)"
                  Health: \(recipe.healthScore.map { "\($0)/100" } ?? "N/A") | Cal: \(recipe.calories.map { "\($0)" } ?? "N/A") | Protein: \(recipe.protein.map { "\($0)g" } ?? "N/A")
            
            """
        }
        
        let avgHealth = healthScores.isEmpty ? 0 : healthScores.reduce(0, +) / healthScores.count
        let minHealth = healthScores.min() ?? 0
        let maxHealth = healthScores.max() ?? 0
        
        let qualityEmoji: String
        if avgHealth >= 70 {
            qualityEmoji = "🌟 EXCELLENT"
        } else if avgHealth >= 50 {
            qualityEmoji = "✅ GOOD"
        } else if avgHealth >= 30 {
            qualityEmoji = "⚠️ MEDIOCRE"
        } else {
            qualityEmoji = "❌ POOR - NEEDS FIX!"
        }
        
        let log = """
        
        ═══════════════════════════════════════════════════════════════
        🍽️ FINAL RECOMMENDATIONS @ \(timestamp)
        ═══════════════════════════════════════════════════════════════
        Source: \(source)
        Total Shown: \(recipes.count)
        
        QUALITY METRICS:
           Average Health Score: \(avgHealth)/100 \(qualityEmoji)
           Min Health Score: \(minHealth)/100
           Max Health Score: \(maxHealth)/100
        
        RECIPES DISPLAYED:
        \(recipeList.isEmpty ? "   ⚠️ NO RECIPES TO SHOW!" : recipeList)
        ═══════════════════════════════════════════════════════════════
        """
        AppLogger.debug("\(log)", category: .nutrition)
        addToSession(log)
        
        // Alert if quality is poor
        if avgHealth < 40 && !recipes.isEmpty {
            logWarning("⚠️ LOW QUALITY RECOMMENDATIONS! Average health score \(avgHealth) is below 40. Check API filters!")
        }
    }
    
    /// Log a warning
    func logWarning(_ message: String) {
        let log = "\n⚠️ WARNING @ \(timestamp): \(message)\n"
        AppLogger.debug("\(log)", category: .nutrition)
        addToSession(log)
    }
    
    /// Log an error
    func logError(_ message: String, error: Error? = nil) {
        let errorDetail = error.map { " - \($0.localizedDescription)" } ?? ""
        let log = "\n❌ ERROR @ \(timestamp): \(message)\(errorDetail)\n"
        AppLogger.debug("\(log)", category: .nutrition)
        addToSession(log)
    }
    
    /// Log successful operation
    func logSuccess(_ message: String) {
        let log = "✅ \(timestamp): \(message)"
        AppLogger.debug("\(log)", category: .nutrition)
        addToSession(log)
    }
    
    /// Log info
    func logInfo(_ message: String) {
        let log = "ℹ️ \(timestamp): \(message)"
        AppLogger.debug("\(log)", category: .nutrition)
        addToSession(log)
    }
    
    /// Log cache status
    func logCacheStatus(hasCache: Bool, cacheAge: TimeInterval?, shouldRefresh: Bool) {
        let ageString = cacheAge.map { "\(Int($0 / 60)) minutes old" } ?? "no cache"
        let log = """
        
        💾 CACHE STATUS @ \(timestamp)
        ───────────────────────────────────────────────────────────────
        Has Cache: \(hasCache ? "Yes" : "No")
        Cache Age: \(ageString)
        Should Refresh: \(shouldRefresh ? "Yes" : "No")
        ───────────────────────────────────────────────────────────────
        """
        AppLogger.debug("\(log)", category: .nutrition)
        addToSession(log)
    }
    
    // MARK: - Helpers
    
    private var timestamp: String {
        dateFormatter.string(from: Date())
    }
    
    private func getHealthEmoji(score: Int?) -> String {
        guard let score = score else { return "❓" }
        if score >= 70 { return "🌟" }
        if score >= 50 { return "✅" }
        if score >= 30 { return "⚠️" }
        return "❌"
    }
    
    private func addToSession(_ log: String) {
        sessionLogs.append(log)
        if sessionLogs.count > maxLogs {
            sessionLogs.removeFirst(100)
        }
    }
    
    /// Get all session logs (for debugging UI if needed)
    func getSessionLogs() -> [String] {
        return sessionLogs
    }
    
    /// Clear session logs
    func clearSessionLogs() {
        sessionLogs.removeAll()
        AppLogger.debug("🗑️ Session logs cleared", category: .nutrition)
    }
    
    /// Export logs as string
    func exportLogs() -> String {
        return sessionLogs.joined(separator: "\n")
    }
}

// MARK: - Convenience Extensions
extension RecipeRecommendationLogger {
    /// Quick log for recipe array
    func logRecipes(_ recipes: [SpoonacularRecipe], source: String) {
        let recipeData = recipes.map { recipe -> (id: Int, title: String, healthScore: Int?, calories: Int?, protein: Int?) in
            (
                id: recipe.id,
                title: recipe.title,
                healthScore: nil, // SpoonacularRecipe doesn't have healthScore directly
                calories: recipe.calories,
                protein: recipe.protein
            )
        }
        logFinalRecommendations(recipes: recipeData, source: source)
    }
}
