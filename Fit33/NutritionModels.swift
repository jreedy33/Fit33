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
    /// User-entered serving count. **MUST** stay Double to preserve fractional
    /// servings (e.g. 0.5 cup). Truncating to Int silently loses 50% of the
    /// log on common cases like "half a banana" or "0.25 cup peanut butter"
    /// — bug found 2026-04-30 by the nutrition pipeline audit.
    let quantity: Double
    let unit: String
    let calories: Int
    let protein: Int
    let carbs: Int
    let fat: Int
    /// USDA FDC ID OR an OFF synthetic NEGATIVE id (`-1 × parseInt(barcode)`).
    /// Type is `Int` (Int64 on 64-bit Swift) so 13-digit barcodes — abs up to
    /// 9.99 × 10^12 — fit. Truncating to Int32 anywhere downstream loses
    /// every OFF meal log on round-trip.
    let fdcId: Int?
    let foodItemId: Int? // Cloud food database ID

    // Detailed nutrition (added 2026-04-30 — were silently lost prior to this).
    // All in their canonical USDA units: fiber/sugar in grams, sodium in mg.
    // Optional with default 0 so existing call sites compile unchanged.
    var fiber: Double = 0
    var sugar: Double = 0
    var sodium: Double = 0

    // Provenance (added 2026-04-30 alongside Open Food Facts integration).
    // - `source` = "usda" | "off" | "ocr" | "spoonacular" | nil (legacy)
    // - `barcode` = EAN/UPC if scanned, nil otherwise
    // Required for: ODbL attribution on render, cross-device cache hits by
    // barcode, and analytics breakdowns by data source in the CMS.
    var source: String? = nil
    var barcode: String? = nil
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
