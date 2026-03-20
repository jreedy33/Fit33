import SwiftUI
import CoreData

// MARK: - Models

struct MealSuggestion: Identifiable {
    let id = UUID()
    let name: String
    let reason: String
    let calories: Int
    let protein: Int
    let carbs: Int
    let fat: Int
    let mealType: String
    let source: SuggestionSource
    let priority: Int
    
    enum SuggestionSource {
        case frequentFood
        case savedMeal
        case general
    }
}

struct MealContext {
    let timeOfDay: TimeOfDay
    let caloriesEaten: Int
    let proteinEaten: Int
    let carbsEaten: Int
    let fatEaten: Int
    let calorieTarget: Int
    let proteinTarget: Int
    let carbTarget: Int
    let fatTarget: Int
    let fitnessGoal: String
    
    var caloriesRemaining: Int { max(0, calorieTarget - caloriesEaten) }
    var proteinRemaining: Int { max(0, proteinTarget - proteinEaten) }
    var carbsRemaining: Int { max(0, carbTarget - carbsEaten) }
    var fatRemaining: Int { max(0, fatTarget - fatEaten) }
    
    var biggestMacroGap: String {
        let proteinPct = proteinTarget > 0 ? Double(proteinEaten) / Double(proteinTarget) : 1.0
        let carbPct = carbTarget > 0 ? Double(carbsEaten) / Double(carbTarget) : 1.0
        let fatPct = fatTarget > 0 ? Double(fatEaten) / Double(fatTarget) : 1.0
        
        let min = Swift.min(proteinPct, carbPct, fatPct)
        if min == proteinPct { return "protein" }
        if min == carbPct { return "carbs" }
        return "fat"
    }
    
    enum TimeOfDay: String {
        case earlyMorning, morning, midday, afternoon, evening, lateNight
        
        var mealType: String {
            switch self {
            case .earlyMorning, .morning: return "breakfast"
            case .midday: return "lunch"
            case .afternoon: return "snacks"
            case .evening: return "dinner"
            case .lateNight: return "snacks"
            }
        }
        
        var label: String {
            switch self {
            case .earlyMorning: return "Early Morning"
            case .morning: return "Morning"
            case .midday: return "Lunchtime"
            case .afternoon: return "Afternoon"
            case .evening: return "Dinner Time"
            case .lateNight: return "Late Night"
            }
        }
    }
}

// MARK: - Engine

class ContextualMealEngine: ObservableObject {
    static let shared = ContextualMealEngine()
    
    @Published var suggestions: [MealSuggestion] = []
    @Published var context: MealContext?
    
    private init() {}
    
    private func computeNutritionTargets() -> (calories: Int, protein: Int, carbs: Int, fat: Int, goal: String) {
        guard let user = UserManager.shared.currentUser else {
            return (calories: 2200, protein: 160, carbs: 250, fat: 70, goal: "maintain")
        }
        
        let weightKg = Double(user.weight)
        let goal = (user.fitnessGoal ?? "maintain").lowercased()
        
        guard weightKg > 0 else {
            return (calories: 2200, protein: 160, carbs: 250, fat: 70, goal: goal)
        }
        
        let baseCalories: Double
        if goal.contains("lose") || goal.contains("cut") {
            baseCalories = weightKg * 26
        } else if goal.contains("bulk") || goal.contains("gain") || goal.contains("muscle") {
            baseCalories = weightKg * 35
        } else {
            baseCalories = weightKg * 30
        }
        
        let calories = Int(baseCalories)
        let protein = Int(weightKg * 2.0)
        let fat = Int(baseCalories * 0.25 / 9.0)
        let carbs = Int((baseCalories - Double(protein) * 4.0 - Double(fat) * 9.0) / 4.0)
        
        return (calories: calories, protein: protein, carbs: max(carbs, 100), fat: fat, goal: goal)
    }
    
    func refresh() {
        let ctx = buildContext()
        self.context = ctx
        self.suggestions = generateSuggestions(context: ctx)
    }
    
    // MARK: - Build Context
    
    private func buildContext() -> MealContext {
        let now = Date()
        let hour = Calendar.current.component(.hour, from: now)
        
        let timeOfDay: MealContext.TimeOfDay
        switch hour {
        case 0..<6: timeOfDay = .lateNight
        case 6..<9: timeOfDay = .earlyMorning
        case 9..<11: timeOfDay = .morning
        case 11..<14: timeOfDay = .midday
        case 14..<17: timeOfDay = .afternoon
        case 17..<21: timeOfDay = .evening
        default: timeOfDay = .lateNight
        }
        
        let summary = MealService.shared.getDailySummary(for: now)
        
        let targets = computeNutritionTargets()
        
        return MealContext(
            timeOfDay: timeOfDay,
            caloriesEaten: summary.calories,
            proteinEaten: summary.protein,
            carbsEaten: summary.carbs,
            fatEaten: summary.fat,
            calorieTarget: targets.calories,
            proteinTarget: targets.protein,
            carbTarget: targets.carbs,
            fatTarget: targets.fat,
            fitnessGoal: targets.goal
        )
    }
    
    // MARK: - Generate Suggestions
    
    private func generateSuggestions(context: MealContext) -> [MealSuggestion] {
        var suggestions: [MealSuggestion] = []
        
        // Macro-gap based suggestions
        let gap = context.biggestMacroGap
        
        if gap == "protein" && context.proteinRemaining > 20 {
            suggestions.append(contentsOf: proteinSuggestions(remaining: context.proteinRemaining, timeOfDay: context.timeOfDay))
        }
        
        if gap == "carbs" && context.carbsRemaining > 30 {
            suggestions.append(contentsOf: carbSuggestions(remaining: context.carbsRemaining, timeOfDay: context.timeOfDay))
        }
        
        if context.caloriesRemaining > 400 {
            suggestions.append(contentsOf: balancedMealSuggestions(
                caloriesRemaining: context.caloriesRemaining,
                timeOfDay: context.timeOfDay
            ))
        } else if context.caloriesRemaining < 200 && context.caloriesRemaining > 0 {
            suggestions.append(MealSuggestion(
                name: "Light Snack",
                reason: "Only \(context.caloriesRemaining) cals left — keep it light",
                calories: min(150, context.caloriesRemaining), protein: 10, carbs: 15, fat: 5,
                mealType: "snacks", source: .general, priority: 2
            ))
        }
        
        return suggestions.sorted { $0.priority < $1.priority }.prefix(5).map { $0 }
    }
    
    private func proteinSuggestions(remaining: Int, timeOfDay: MealContext.TimeOfDay) -> [MealSuggestion] {
        let meals: [(String, Int, Int, Int, Int)] = [
            ("Grilled Chicken Breast", 280, 45, 0, 8),
            ("Greek Yogurt with Berries", 180, 20, 18, 4),
            ("Protein Shake", 160, 30, 8, 2),
            ("Scrambled Eggs (3)", 240, 18, 2, 16),
            ("Tuna Salad", 220, 30, 5, 8),
        ]
        
        return meals.prefix(2).map { meal in
            MealSuggestion(
                name: meal.0,
                reason: "High protein to fill your \(remaining)g gap",
                calories: meal.1, protein: meal.2, carbs: meal.3, fat: meal.4,
                mealType: timeOfDay.mealType, source: .general, priority: 1
            )
        }
    }
    
    private func carbSuggestions(remaining: Int, timeOfDay: MealContext.TimeOfDay) -> [MealSuggestion] {
        let meals: [(String, Int, Int, Int, Int)] = [
            ("Oatmeal with Banana", 320, 10, 55, 6),
            ("Rice Bowl with Vegetables", 380, 8, 65, 6),
            ("Whole Wheat Toast with Avocado", 280, 8, 35, 14),
            ("Sweet Potato", 180, 4, 41, 0),
        ]
        
        return meals.prefix(2).map { meal in
            MealSuggestion(
                name: meal.0,
                reason: "Carbs to fill your \(remaining)g gap and fuel recovery",
                calories: meal.1, protein: meal.2, carbs: meal.3, fat: meal.4,
                mealType: timeOfDay.mealType, source: .general, priority: 1
            )
        }
    }
    
    private func balancedMealSuggestions(caloriesRemaining: Int, timeOfDay: MealContext.TimeOfDay) -> [MealSuggestion] {
        switch timeOfDay {
        case .earlyMorning, .morning:
            return [MealSuggestion(
                name: "Eggs, Toast & Fruit",
                reason: "Balanced breakfast to start your day right",
                calories: 450, protein: 25, carbs: 45, fat: 18,
                mealType: "breakfast", source: .general, priority: 1
            )]
        case .midday:
            return [MealSuggestion(
                name: "Chicken & Rice Bowl",
                reason: "Balanced lunch — \(caloriesRemaining) cals remaining today",
                calories: 550, protein: 40, carbs: 55, fat: 14,
                mealType: "lunch", source: .general, priority: 1
            )]
        case .afternoon:
            return [MealSuggestion(
                name: "Trail Mix & Protein Bar",
                reason: "Afternoon fuel to carry you through",
                calories: 350, protein: 20, carbs: 35, fat: 16,
                mealType: "snacks", source: .general, priority: 1
            )]
        case .evening:
            return [MealSuggestion(
                name: "Salmon with Veggies & Quinoa",
                reason: "Nutrient-dense dinner — \(caloriesRemaining) cals left",
                calories: 520, protein: 38, carbs: 40, fat: 20,
                mealType: "dinner", source: .general, priority: 1
            )]
        case .lateNight:
            return [MealSuggestion(
                name: "Cottage Cheese & Almonds",
                reason: "Casein protein for overnight recovery",
                calories: 250, protein: 28, carbs: 8, fat: 12,
                mealType: "snacks", source: .general, priority: 1
            )]
        }
    }
}
