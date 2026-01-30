import Foundation
import SwiftUI
import Combine

// MARK: - Saved Meals Service
/// Manages saved/bookmarked meals from both pre-existing recipes and URL imports
class SavedMealsService: ObservableObject {
    static let shared = SavedMealsService()
    
    @Published var savedMeals: [SavedMeal] = []
    @Published var shoppingListItems: [ShoppingListItem] = []
    
    private let savedMealsKey = "savedMeals"
    private let shoppingListKey = "shoppingListItems"
    
    private init() {
        loadSavedMeals()
        loadShoppingList()
    }
    
    // MARK: - Saved Meals
    
    func saveMeal(_ meal: SavedMeal) {
        // Check if already saved
        if !savedMeals.contains(where: { $0.id == meal.id }) {
            savedMeals.append(meal)
            persistSavedMeals()
            print("✅ [SAVED MEALS] Saved meal: \(meal.name)")
        }
    }
    
    func removeSavedMeal(id: String) {
        savedMeals.removeAll { $0.id == id }
        persistSavedMeals()
        print("🗑️ [SAVED MEALS] Removed meal with id: \(id)")
    }
    
    func isMealSaved(id: String) -> Bool {
        savedMeals.contains { $0.id == id }
    }
    
    func toggleSavedMeal(_ meal: SavedMeal) {
        if isMealSaved(id: meal.id) {
            removeSavedMeal(id: meal.id)
        } else {
            saveMeal(meal)
        }
    }
    
    // MARK: - Shopping List
    
    func addToShoppingList(ingredients: [ShoppingListItem]) {
        for ingredient in ingredients {
            // Check if ingredient already exists and update quantity if so
            if let existingIndex = shoppingListItems.firstIndex(where: { 
                $0.name.lowercased() == ingredient.name.lowercased() && 
                $0.unit.lowercased() == ingredient.unit.lowercased() 
            }) {
                shoppingListItems[existingIndex].amount += ingredient.amount
            } else {
                shoppingListItems.append(ingredient)
            }
        }
        persistShoppingList()
        print("🛒 [SHOPPING] Added \(ingredients.count) items to shopping list")
    }
    
    func removeFromShoppingList(id: String) {
        shoppingListItems.removeAll { $0.id == id }
        persistShoppingList()
    }
    
    func toggleShoppingItemChecked(id: String) {
        if let index = shoppingListItems.firstIndex(where: { $0.id == id }) {
            shoppingListItems[index].isChecked.toggle()
            persistShoppingList()
        }
    }
    
    func clearCheckedItems() {
        shoppingListItems.removeAll { $0.isChecked }
        persistShoppingList()
    }
    
    func clearAllShoppingList() {
        shoppingListItems.removeAll()
        persistShoppingList()
    }
    
    // MARK: - Persistence
    
    private func loadSavedMeals() {
        if let data = UserDefaults.standard.data(forKey: savedMealsKey),
           let meals = try? JSONDecoder().decode([SavedMeal].self, from: data) {
            savedMeals = meals
            print("📂 [SAVED MEALS] Loaded \(meals.count) saved meals")
        }
    }
    
    private func persistSavedMeals() {
        if let data = try? JSONEncoder().encode(savedMeals) {
            UserDefaults.standard.set(data, forKey: savedMealsKey)
        }
    }
    
    private func loadShoppingList() {
        if let data = UserDefaults.standard.data(forKey: shoppingListKey),
           let items = try? JSONDecoder().decode([ShoppingListItem].self, from: data) {
            shoppingListItems = items
            print("📂 [SHOPPING] Loaded \(items.count) shopping list items")
        }
    }
    
    private func persistShoppingList() {
        if let data = try? JSONEncoder().encode(shoppingListItems) {
            UserDefaults.standard.set(data, forKey: shoppingListKey)
        }
    }
}

// MARK: - Saved Meal Model
struct SavedMeal: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let imageURL: String?
    let sourceName: String?
    let sourceURL: String?
    let calories: Int
    let protein: Int
    let carbs: Int
    let fat: Int
    let servings: Int
    let readyInMinutes: Int?
    let healthScore: Double?
    let ingredients: [SavedIngredient]
    let instructions: String?
    let savedDate: Date
    let source: MealSource // Track where the meal came from
    
    // Additional health/diet tags
    let isVegetarian: Bool?
    let isVegan: Bool?
    let isGlutenFree: Bool?
    let isDairyFree: Bool?
    let isVeryHealthy: Bool?
    
    enum MealSource: String, Codable {
        case urlImport = "url_import"
        case recipe = "recipe"
        case custom = "custom"
    }
    
    static func == (lhs: SavedMeal, rhs: SavedMeal) -> Bool {
        lhs.id == rhs.id
    }
    
    // Create from ExtractedRecipe (URL import)
    static func fromExtractedRecipe(_ recipe: ExtractedRecipe, sourceURL: String?) -> SavedMeal {
        SavedMeal(
            id: "imported_\(recipe.id ?? Int.random(in: 100000...999999))",
            name: recipe.title,
            imageURL: recipe.image,
            sourceName: recipe.sourceName,
            sourceURL: sourceURL ?? recipe.sourceUrl,
            calories: recipe.calories,
            protein: recipe.protein,
            carbs: recipe.carbs,
            fat: recipe.fat,
            servings: recipe.servings ?? 1,
            readyInMinutes: recipe.readyInMinutes,
            healthScore: nil,
            ingredients: recipe.extendedIngredients?.map { 
                SavedIngredient.fromExtendedIngredient($0)
            } ?? [],
            instructions: recipe.instructions,
            savedDate: Date(),
            source: .urlImport,
            isVegetarian: nil,
            isVegan: nil,
            isGlutenFree: nil,
            isDairyFree: nil,
            isVeryHealthy: nil
        )
    }
    
    // Create from RecipeDetail (browsed recipe)
    static func fromRecipeDetail(_ detail: RecipeDetail) -> SavedMeal {
        SavedMeal(
            id: "recipe_\(detail.id)",
            name: detail.title,
            imageURL: detail.image,
            sourceName: detail.sourceName,
            sourceURL: detail.sourceUrl,
            calories: detail.calories,
            protein: Int(detail.protein),
            carbs: Int(detail.carbs),
            fat: Int(detail.fat),
            servings: detail.servings,
            readyInMinutes: detail.readyInMinutes,
            healthScore: detail.healthScore,
            ingredients: detail.extendedIngredients?.map {
                SavedIngredient.fromExtendedIngredient($0)
            } ?? [],
            instructions: detail.instructions,
            savedDate: Date(),
            source: .recipe,
            isVegetarian: detail.vegetarian,
            isVegan: detail.vegan,
            isGlutenFree: detail.glutenFree,
            isDairyFree: detail.dairyFree,
            isVeryHealthy: detail.veryHealthy
        )
    }
}

// MARK: - Saved Ingredient Model
struct SavedIngredient: Identifiable, Codable {
    var id: String { "\(name)_\(unit ?? "")" }
    let name: String
    let amount: Double
    let unit: String?
    let aisle: String?
    let original: String // Original text like "2 cups flour"
    
    static func fromExtendedIngredient(_ ingredient: ExtendedIngredient) -> SavedIngredient {
        SavedIngredient(
            name: ingredient.name,
            amount: ingredient.amount,
            unit: ingredient.unit,
            aisle: ingredient.aisle,
            original: ingredient.original
        )
    }
}

// MARK: - Shopping List Item Model
struct ShoppingListItem: Identifiable, Codable {
    let id: String
    let name: String
    var amount: Double
    let unit: String
    let aisle: String?
    var isChecked: Bool
    let fromRecipe: String? // Which recipe this came from
    
    init(id: String = UUID().uuidString, name: String, amount: Double, unit: String, aisle: String? = nil, isChecked: Bool = false, fromRecipe: String? = nil) {
        self.id = id
        self.name = name
        self.amount = amount
        self.unit = unit
        self.aisle = aisle
        self.isChecked = isChecked
        self.fromRecipe = fromRecipe
    }
    
    var formattedAmount: String {
        if amount == amount.rounded() {
            return "\(Int(amount)) \(unit)"
        }
        return "\(String(format: "%.1f", amount)) \(unit)"
    }
    
    static func fromSavedIngredient(_ ingredient: SavedIngredient, recipeName: String) -> ShoppingListItem {
        ShoppingListItem(
            name: ingredient.name,
            amount: ingredient.amount,
            unit: ingredient.unit ?? "",
            aisle: ingredient.aisle,
            fromRecipe: recipeName
        )
    }
}
