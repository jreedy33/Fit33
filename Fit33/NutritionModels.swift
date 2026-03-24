import SwiftUI

// MARK: - Meal Types

enum MealType: String, CaseIterable {
    case breakfast = "breakfast"
    case lunch = "lunch"
    case dinner = "dinner"
    case snacks = "snacks"
    
    var displayName: String {
        switch self {
        case .breakfast: return "Breakfast"
        case .lunch: return "Lunch"
        case .dinner: return "Dinner"
        case .snacks: return "Snacks"
        }
    }
    
    var icon: String {
        switch self {
        case .breakfast: return "sunrise.fill"
        case .lunch: return "sun.max.fill"
        case .dinner: return "moon.stars.fill"
        case .snacks: return "leaf.fill"
        }
    }
    
    var gradientColors: (Color, Color) {
        switch self {
        case .breakfast: return (.orange, .yellow)
        case .lunch: return (.green, .teal)
        case .dinner: return (.blue, .cyan)
        case .snacks: return (.purple, .pink)
        }
    }
    
    var timeDescription: String {
        switch self {
        case .breakfast: return "5 AM - 10 AM"
        case .lunch: return "12 PM - 2 PM"
        case .dinner: return "6 PM onwards"
        case .snacks: return "Anytime"
        }
    }
}

struct FoodEntry {
    let name: String
    let quantity: Int
    let unit: String
    let calories: Int
    let protein: Int
    let carbs: Int
    let fat: Int
    let fdcId: Int? // For cloud tracking
    let foodItemId: Int? // Cloud food database ID
}

// MARK: - Nutrition Chart Data
struct MacronutrientData: Identifiable {
    let id = UUID()
    let name: String
    let value: Double
    let color: Color
    let calories: Double
}

struct NutritionInsight {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color
    let trend: String?
}
