import Foundation
import SwiftUI

// MARK: - Recipe Search Response
struct RecipeSearchResponse: Codable {
    let results: [SpoonacularRecipe]
    let offset: Int
    let number: Int
    let totalResults: Int
}

// MARK: - Spoonacular Recipe (from search)
struct SpoonacularRecipe: Codable, Identifiable {
    let id: Int
    let title: String
    let image: String?
    let imageType: String?
    let nutrition: RecipeNutrition?
    
    // Computed properties for display
    var imageURL: URL? {
        guard let image = image else { return nil }
        // Handle both full URLs and partial paths
        if image.hasPrefix("http") {
            return URL(string: image)
        } else {
            return URL(string: "https://img.spoonacular.com/recipes/\(id)-556x370.\(imageType ?? "jpg")")
        }
    }
    
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
    
    // Formatted display name (truncate long titles)
    var displayTitle: String {
        if title.count > 40 {
            return String(title.prefix(37)) + "..."
        }
        return title
    }
}

// MARK: - Recipe Nutrition
struct RecipeNutrition: Codable {
    let nutrients: [Nutrient]?
    let caloricBreakdown: CaloricBreakdown?
    let ingredients: [NutritionIngredient]?
}

// MARK: - Nutrient
struct Nutrient: Codable, Identifiable {
    var id: String { name }
    let name: String
    let amount: Double
    let unit: String
    let percentOfDailyNeeds: Double?
}

// MARK: - Caloric Breakdown
struct CaloricBreakdown: Codable {
    let percentProtein: Double?
    let percentFat: Double?
    let percentCarbs: Double?
}

// MARK: - Nutrition Ingredient
struct NutritionIngredient: Codable, Identifiable {
    let id: Int
    let name: String
    let amount: Double
    let unit: String
}

// MARK: - Recipe Detail (full information)
struct RecipeDetail: Codable, Identifiable {
    let id: Int
    let title: String
    let image: String?
    let imageType: String?
    let servings: Int
    let readyInMinutes: Int
    let preparationMinutes: Int?
    let cookingMinutes: Int?
    let sourceName: String?
    let sourceUrl: String?
    let spoonacularSourceUrl: String?
    let healthScore: Double?
    let pricePerServing: Double?
    let cheap: Bool?
    let creditsText: String?
    let dairyFree: Bool?
    let glutenFree: Bool?
    let vegan: Bool?
    let vegetarian: Bool?
    let veryHealthy: Bool?
    let veryPopular: Bool?
    let sustainable: Bool?
    let lowFodmap: Bool?
    let weightWatcherSmartPoints: Int?
    let gaps: String?
    let summary: String?
    let cuisines: [String]?
    let dishTypes: [String]?
    let diets: [String]?
    let occasions: [String]?
    let instructions: String?
    let analyzedInstructions: [AnalyzedInstruction]?
    let extendedIngredients: [ExtendedIngredient]?
    let nutrition: RecipeNutrition?
    
    // MARK: - Computed Properties
    
    var imageURL: URL? {
        guard let image = image else { return nil }
        if image.hasPrefix("http") {
            return URL(string: image)
        } else {
            return URL(string: "https://img.spoonacular.com/recipes/\(id)-556x370.\(imageType ?? "jpg")")
        }
    }
    
    var calories: Int {
        guard let nutrients = nutrition?.nutrients else { return 0 }
        return Int(nutrients.first { $0.name.lowercased() == "calories" }?.amount ?? 0)
    }
    
    var protein: Double {
        guard let nutrients = nutrition?.nutrients else { return 0 }
        return nutrients.first { $0.name.lowercased() == "protein" }?.amount ?? 0
    }
    
    var carbs: Double {
        guard let nutrients = nutrition?.nutrients else { return 0 }
        return nutrients.first { $0.name.lowercased() == "carbohydrates" }?.amount ?? 0
    }
    
    var fat: Double {
        guard let nutrients = nutrition?.nutrients else { return 0 }
        return nutrients.first { $0.name.lowercased() == "fat" }?.amount ?? 0
    }
    
    var fiber: Double {
        guard let nutrients = nutrition?.nutrients else { return 0 }
        return nutrients.first { $0.name.lowercased() == "fiber" }?.amount ?? 0
    }
    
    var sugar: Double {
        guard let nutrients = nutrition?.nutrients else { return 0 }
        return nutrients.first { $0.name.lowercased() == "sugar" }?.amount ?? 0
    }
    
    var sodium: Double {
        guard let nutrients = nutrition?.nutrients else { return 0 }
        return nutrients.first { $0.name.lowercased() == "sodium" }?.amount ?? 0
    }
    
    // Clean HTML from summary
    var cleanSummary: String {
        guard let summary = summary else { return "" }
        return summary
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // Diet tags for display
    var dietTags: [RecipeDietTag] {
        var tags: [RecipeDietTag] = []
        
        if veryHealthy == true {
            tags.append(.healthy)
        }
        if glutenFree == true {
            tags.append(.glutenFree)
        }
        if dairyFree == true {
            tags.append(.dairyFree)
        }
        if vegan == true {
            tags.append(.vegan)
        } else if vegetarian == true {
            tags.append(.vegetarian)
        }
        if lowFodmap == true {
            tags.append(.lowFodmap)
        }
        
        // Add high protein tag if protein is significant
        if protein >= 25 {
            tags.append(.highProtein)
        }
        
        return tags
    }
    
    // Formatted time string
    var formattedTime: String {
        if readyInMinutes < 60 {
            return "\(readyInMinutes) min"
        } else {
            let hours = readyInMinutes / 60
            let mins = readyInMinutes % 60
            if mins == 0 {
                return "\(hours) hr"
            }
            return "\(hours) hr \(mins) min"
        }
    }
    
    // Difficulty based on prep time and ingredient count
    var difficulty: RecipeDifficulty {
        let ingredientCount = extendedIngredients?.count ?? 0
        
        if readyInMinutes <= 20 && ingredientCount <= 6 {
            return .easy
        } else if readyInMinutes <= 45 && ingredientCount <= 12 {
            return .medium
        } else {
            return .hard
        }
    }
}

// MARK: - Extended Ingredient
struct ExtendedIngredient: Codable, Identifiable {
    let id: Int
    let aisle: String?
    let image: String?
    let name: String
    let original: String
    let originalName: String?
    let amount: Double
    let unit: String?
    let measures: IngredientMeasures?
    
    var imageURL: URL? {
        guard let image = image else { return nil }
        return URL(string: "https://img.spoonacular.com/ingredients_100x100/\(image)")
    }
    
    var formattedAmount: String {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        
        // Handle fractions nicely
        let rounded = (amount * 4).rounded() / 4 // Round to nearest quarter
        if rounded == rounded.rounded() {
            return "\(Int(rounded))"
        } else {
            return formatter.string(from: NSNumber(value: rounded)) ?? "\(amount)"
        }
    }
}

// MARK: - Ingredient Measures
struct IngredientMeasures: Codable {
    let us: IngredientMeasure?
    let metric: IngredientMeasure?
}

struct IngredientMeasure: Codable {
    let amount: Double
    let unitShort: String?
    let unitLong: String?
}

// MARK: - Analyzed Instruction
struct AnalyzedInstruction: Codable, Identifiable {
    var id: String { name ?? UUID().uuidString }
    let name: String?
    let steps: [InstructionStep]?
}

// MARK: - Instruction Step
struct InstructionStep: Codable, Identifiable {
    var id: Int { number }
    let number: Int
    let step: String
    let ingredients: [StepIngredient]?
    let equipment: [StepEquipment]?
    let length: StepLength?
}

struct StepIngredient: Codable, Identifiable {
    let id: Int
    let name: String
    let image: String?
}

struct StepEquipment: Codable, Identifiable {
    let id: Int
    let name: String
    let image: String?
}

struct StepLength: Codable {
    let number: Int
    let unit: String
}

// MARK: - Similar Recipe
struct SimilarRecipe: Codable, Identifiable {
    let id: Int
    let title: String
    let imageType: String?
    let readyInMinutes: Int
    let servings: Int
    let sourceUrl: String?
    
    var imageURL: URL? {
        URL(string: "https://img.spoonacular.com/recipes/\(id)-312x231.\(imageType ?? "jpg")")
    }
}

// MARK: - Random Recipe Response
struct RandomRecipeResponse: Codable {
    let recipes: [RandomRecipe]
}

struct RandomRecipe: Codable, Identifiable {
    let id: Int
    let title: String
    let image: String?
    let imageType: String?
    let readyInMinutes: Int?
    let servings: Int?
    let nutrition: RecipeNutrition?
}

// MARK: - Supporting Types

enum RecipeDietTag: String, CaseIterable {
    case healthy = "Healthy"
    case highProtein = "High Protein"
    case glutenFree = "Gluten-Free"
    case dairyFree = "Dairy-Free"
    case vegan = "Vegan"
    case vegetarian = "Vegetarian"
    case lowFodmap = "Low FODMAP"
    case keto = "Keto"
    case paleo = "Paleo"
    
    var color: Color {
        switch self {
        case .healthy: return .green
        case .highProtein: return .blue
        case .glutenFree: return .orange
        case .dairyFree: return .purple
        case .vegan: return .mint
        case .vegetarian: return .teal
        case .lowFodmap: return .indigo
        case .keto: return .pink
        case .paleo: return .brown
        }
    }
    
    var icon: String {
        switch self {
        case .healthy: return "heart.fill"
        case .highProtein: return "flame.fill"
        case .glutenFree: return "leaf.fill"
        case .dairyFree: return "drop.fill"
        case .vegan: return "leaf.circle.fill"
        case .vegetarian: return "carrot.fill"
        case .lowFodmap: return "checkmark.seal.fill"
        case .keto: return "bolt.fill"
        case .paleo: return "figure.run"
        }
    }
}

enum RecipeDifficulty: String {
    case easy = "Easy"
    case medium = "Medium"
    case hard = "Advanced"
    
    var color: Color {
        switch self {
        case .easy: return .green
        case .medium: return .orange
        case .hard: return .red
        }
    }
    
    var icon: String {
        switch self {
        case .easy: return "1.circle.fill"
        case .medium: return "2.circle.fill"
        case .hard: return "3.circle.fill"
        }
    }
}

// MARK: - Recipe Category (for filtering)
enum RecipeCategory: String, CaseIterable {
    case all = "All"
    case breakfast = "Breakfast"
    case lunch = "Lunch"
    case dinner = "Dinner"
    case snack = "Snack"
    case highProtein = "High Protein"
    case lowCarb = "Low Carb"
    case quickMeals = "Quick Meals"
    
    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .breakfast: return "sunrise"
        case .lunch: return "sun.max"
        case .dinner: return "moon.stars"
        case .snack: return "leaf"
        case .highProtein: return "flame.fill"
        case .lowCarb: return "chart.bar.doc.horizontal"
        case .quickMeals: return "clock"
        }
    }
}
