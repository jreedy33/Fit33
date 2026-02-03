import SwiftUI

struct FoodDetailsView: View {
    let food: ProcessedFoodItem
    let mealType: MealType
    let onAdd: (FoodEntry) -> Void
    let onDismiss: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedUnit: ServingUnit = .grams
    @State private var servingAmount: String = "100"  // Initialized to USDA default (100g)
    @State private var showingCustomAmount = false
    @State private var isLoading = false
    @State private var showDetailedNutrition: Bool
    
    // Available serving units with gram conversion factors
    enum ServingUnit: String, CaseIterable, Identifiable {
        // Standard units
        case grams = "g"
        case ounces = "oz"
        case tablespoons = "tbsp"
        case teaspoons = "tsp"
        case cups = "cup"
        case milliliters = "ml"
        
        // Standalone food items (contextual)
        case egg = "egg"
        case slice = "slice"
        case strip = "strip"
        case piece = "piece"
        case breast = "breast"
        case thigh = "thigh"
        case drumstick = "drumstick"
        case wing = "wing"
        case patty = "patty"
        case fillet = "fillet"
        case link = "link"
        case whole = "whole"
        case medium = "medium"
        case large = "large"
        case small = "small"
        case scoop = "scoop"
        case bar = "bar"
        case packet = "packet"
        case container = "container"
        
        var id: String { rawValue }
        
        /// Gram weight per unit (based on USDA averages)
        var gramsPerUnit: Double {
            switch self {
            // Standard units
            case .grams: return 1.0
            case .ounces: return 28.3495
            case .tablespoons: return 15.0
            case .teaspoons: return 5.0
            case .cups: return 240.0
            case .milliliters: return 1.0
            
            // Eggs
            case .egg: return 50.0           // 1 large egg
            
            // Bread/sliced items
            case .slice: return 30.0         // 1 slice bread
            case .strip: return 8.0          // 1 strip bacon
            
            // Chicken pieces (raw, bone-in weights)
            case .breast: return 174.0       // 1 chicken breast (boneless)
            case .thigh: return 116.0        // 1 chicken thigh (boneless)
            case .drumstick: return 95.0     // 1 drumstick
            case .wing: return 34.0          // 1 wing
            
            // Other proteins
            case .patty: return 113.0        // 1 burger patty (4 oz)
            case .fillet: return 170.0       // 1 fish fillet (6 oz)
            case .link: return 45.0          // 1 sausage link
            
            // Whole fruits
            case .whole: return 150.0        // Generic whole item
            case .medium: return 150.0       // Medium fruit
            case .large: return 200.0        // Large fruit
            case .small: return 100.0        // Small fruit
            
            // Supplements/packaged
            case .scoop: return 30.0         // 1 protein scoop
            case .bar: return 50.0           // 1 protein/granola bar
            case .packet: return 28.0        // 1 packet (oatmeal, etc.)
            case .piece: return 30.0         // Generic piece
            case .container: return 170.0    // Yogurt container (6 oz)
            }
        }
        
        var displayName: String {
            rawValue
        }
        
        /// Whether this is a standard unit that should always appear in dropdown
        var isStandardUnit: Bool {
            switch self {
            case .grams, .ounces, .tablespoons, .teaspoons, .cups, .milliliters:
                return true
            default:
                return false
            }
        }
    }
    
    /// Returns the appropriate serving units for a given food
    /// Shows standard units plus contextual units based on food type
    private var availableServingUnits: [ServingUnit] {
        var units: [ServingUnit] = [.grams, .ounces]
        let name = food.displayName.lowercased()
        let category = food.category?.lowercased() ?? ""
        
        // Eggs
        if name.contains("egg") && !name.contains("eggplant") {
            units.insert(.egg, at: 0)  // Make egg the first option
        }
        
        // Chicken pieces
        if name.contains("chicken") || name.contains("turkey") {
            if name.contains("breast") {
                units.insert(.breast, at: 0)
            } else if name.contains("thigh") {
                units.insert(.thigh, at: 0)
            } else if name.contains("drumstick") || name.contains("leg") {
                units.insert(.drumstick, at: 0)
            } else if name.contains("wing") {
                units.insert(.wing, at: 0)
            }
        }
        
        // Fish
        if name.contains("salmon") || name.contains("tilapia") || name.contains("cod") ||
           name.contains("halibut") || name.contains("tuna") && name.contains("steak") {
            units.insert(.fillet, at: 0)
        }
        
        // Sausage
        if name.contains("sausage") || name.contains("hot dog") || name.contains("frankfurter") {
            units.insert(.link, at: 0)
        }
        
        // Burger patties
        if name.contains("patty") || name.contains("burger") && name.contains("beef") {
            units.insert(.patty, at: 0)
        }
        
        // Bread & sliced items
        if name.contains("bread") || name.contains("toast") {
            units.insert(.slice, at: 0)
        }
        
        // Bacon
        if name.contains("bacon") {
            units.insert(.strip, at: 0)
        }
        
        // Whole fruits
        if category.contains("fruit") {
            if name.contains("banana") || name.contains("apple") || name.contains("orange") ||
               name.contains("peach") || name.contains("pear") || name.contains("mango") {
                units.insert(.medium, at: 0)
                units.append(.small)
                units.append(.large)
            }
        }
        
        // Yogurt
        if name.contains("yogurt") || name.contains("skyr") {
            units.insert(.container, at: 0)
        }
        
        // Protein powder
        if name.contains("protein") && (name.contains("powder") || name.contains("whey") || name.contains("casein")) {
            units.insert(.scoop, at: 0)
        }
        
        // Protein bars
        if name.contains("bar") && (name.contains("protein") || name.contains("granola") || name.contains("energy")) {
            units.insert(.bar, at: 0)
        }
        
        // Oatmeal packets
        if name.contains("oatmeal") && name.contains("instant") {
            units.insert(.packet, at: 0)
        }
        
        // Always include tablespoons for spreads/condiments/oils
        if name.contains("butter") || name.contains("oil") || name.contains("sauce") ||
           name.contains("dressing") || name.contains("honey") || name.contains("syrup") ||
           category.contains("condiment") {
            if !units.contains(.tablespoons) {
                units.insert(.tablespoons, at: 1)
            }
            if !units.contains(.teaspoons) {
                units.append(.teaspoons)
            }
        }
        
        // Add cups for appropriate foods
        if category.contains("beverage") || category.contains("dairy") || category.contains("grain") ||
           name.contains("rice") || name.contains("milk") || name.contains("cereal") {
            if !units.contains(.cups) {
                units.append(.cups)
            }
        }
        
        return units
    }
    
    // Check if detailed nutrition has any non-zero values
    private var hasDetailedNutrition: Bool {
        let n = food.nutrition
        return n.saturatedFat > 0 || n.fiber > 0 || n.sugar > 0 || 
               n.sodium > 0 || n.cholesterol > 0 || n.calcium > 0 || 
               n.iron > 0 || n.vitaminC > 0
    }
    
    init(food: ProcessedFoodItem, mealType: MealType, onAdd: @escaping (FoodEntry) -> Void, onDismiss: @escaping () -> Void) {
        self.food = food
        self.mealType = mealType
        self.onAdd = onAdd
        self.onDismiss = onDismiss
        
        // Auto-expand detailed nutrition if values exist
        let n = food.nutrition
        let hasValues = n.saturatedFat > 0 || n.fiber > 0 || n.sugar > 0 || 
                       n.sodium > 0 || n.cholesterol > 0 || n.calcium > 0 || 
                       n.iron > 0 || n.vitaminC > 0
        _showDetailedNutrition = State(initialValue: hasValues)
        
        // Initialize with smart default serving (typical real-world portion)
        let smartDefault = Self.getSmartDefaultServing(for: food)
        _servingAmount = State(initialValue: smartDefault.amount)
        _selectedUnit = State(initialValue: smartDefault.unit)
    }
    
    /// Determines the typical real-world serving size for a food item
    /// USDA data is per 100g, but users eat realistic portions
    private static func getSmartDefaultServing(for food: ProcessedFoodItem) -> (amount: String, unit: ServingUnit) {
        let name = food.displayName.lowercased()
        let category = food.category?.lowercased() ?? ""
        
        // ═══════════════════════════════════════════════════════════════════
        // NUT BUTTERS & SPREADS - typically 1-2 tbsp per serving
        // ═══════════════════════════════════════════════════════════════════
        if name.contains("butter") && (name.contains("almond") || name.contains("peanut") || 
           name.contains("cashew") || name.contains("sunflower") || name.contains("hazelnut")) {
            return ("2", .tablespoons)  // 2 tbsp = 32g, typical sandwich/toast amount
        }
        if name.contains("nutella") || name.contains("spread") {
            return ("2", .tablespoons)
        }
        
        // ═══════════════════════════════════════════════════════════════════
        // DAIRY BUTTER, OILS, GHEE - typically 1 tbsp
        // ═══════════════════════════════════════════════════════════════════
        if name.contains("butter") || name.contains("ghee") || name.contains("margarine") {
            return ("1", .tablespoons)  // 1 tbsp = 14g
        }
        if name.contains("oil") && (name.contains("olive") || name.contains("coconut") || 
           name.contains("vegetable") || name.contains("canola") || name.contains("avocado")) {
            return ("1", .tablespoons)
        }
        
        // ═══════════════════════════════════════════════════════════════════
        // CONDIMENTS & SAUCES - typically 1-2 tbsp
        // ═══════════════════════════════════════════════════════════════════
        if name.contains("ketchup") || name.contains("mustard") || name.contains("mayo") ||
           name.contains("mayonnaise") || name.contains("dressing") || name.contains("sauce") {
            return ("1", .tablespoons)
        }
        if name.contains("honey") || name.contains("syrup") || name.contains("jam") || 
           name.contains("jelly") || name.contains("marmalade") {
            return ("1", .tablespoons)
        }
        
        // ═══════════════════════════════════════════════════════════════════
        // EGGS - typically 1-2 eggs (1 large egg ≈ 50g)
        // ═══════════════════════════════════════════════════════════════════
        if name.contains("egg") && !name.contains("eggplant") {
            return ("1", .egg)  // 1 egg = 50g
        }
        
        // ═══════════════════════════════════════════════════════════════════
        // CHICKEN PIECES - use specific piece units
        // ═══════════════════════════════════════════════════════════════════
        if name.contains("chicken breast") || name.contains("turkey breast") {
            return ("1", .breast)  // 1 breast = 174g
        }
        if name.contains("chicken thigh") || name.contains("turkey thigh") {
            return ("1", .thigh)  // 1 thigh = 116g
        }
        if name.contains("drumstick") || name.contains("chicken leg") {
            return ("1", .drumstick)  // 1 drumstick = 95g
        }
        if name.contains("chicken wing") || name.contains("wing") {
            return ("2", .wing)  // 2 wings = 68g
        }
        
        // ═══════════════════════════════════════════════════════════════════
        // FISH FILLETS
        // ═══════════════════════════════════════════════════════════════════
        if name.contains("salmon") || name.contains("tilapia") || name.contains("cod") ||
           name.contains("halibut") || name.contains("mahi") {
            return ("1", .fillet)  // 1 fillet = 170g (6 oz)
        }
        
        // ═══════════════════════════════════════════════════════════════════
        // SAUSAGES & HOT DOGS
        // ═══════════════════════════════════════════════════════════════════
        if name.contains("sausage") || name.contains("hot dog") || name.contains("frankfurter") ||
           name.contains("bratwurst") || name.contains("kielbasa") {
            return ("1", .link)  // 1 link = 45g
        }
        
        // ═══════════════════════════════════════════════════════════════════
        // BURGER PATTIES
        // ═══════════════════════════════════════════════════════════════════
        if name.contains("patty") || (name.contains("burger") && name.contains("beef")) ||
           (name.contains("ground") && name.contains("beef")) {
            return ("1", .patty)  // 1 patty = 113g (4 oz)
        }
        
        // ═══════════════════════════════════════════════════════════════════
        // MEATS & PROTEINS (generic) - typically 4-6 oz per serving
        // ═══════════════════════════════════════════════════════════════════
        if category.contains("meat") || category.contains("poultry") || category.contains("beef") ||
           category.contains("pork") || category.contains("lamb") || category.contains("fish") ||
           category.contains("seafood") {
            return ("4", .ounces)  // 4 oz = 113g, typical protein serving
        }
        if name.contains("chicken") || name.contains("turkey") || name.contains("beef") ||
           name.contains("pork") || name.contains("steak") || name.contains("tuna") ||
           name.contains("shrimp") || name.contains("fish") {
            return ("4", .ounces)
        }
        
        // ═══════════════════════════════════════════════════════════════════
        // CHEESE - typically 1 oz per serving
        // ═══════════════════════════════════════════════════════════════════
        if name.contains("cheese") && !name.contains("cottage") && !name.contains("cream cheese") {
            return ("1", .ounces)  // 1 oz = 28g, typical slice
        }
        if name.contains("cottage cheese") || name.contains("ricotta") {
            return ("0.5", .cups)  // 1/2 cup
        }
        if name.contains("cream cheese") {
            return ("2", .tablespoons)
        }
        
        // ═══════════════════════════════════════════════════════════════════
        // YOGURT & DAIRY - typically 1 cup or 1 container
        // ═══════════════════════════════════════════════════════════════════
        if name.contains("yogurt") || name.contains("skyr") {
            return ("1", .container)  // 1 container = 170g (6 oz)
        }
        if name.contains("milk") && !name.contains("coconut milk") {
            return ("1", .cups)  // 1 cup = 240ml
        }
        if name.contains("cream") && (name.contains("heavy") || name.contains("whipping") || name.contains("sour")) {
            return ("2", .tablespoons)
        }
        
        // ═══════════════════════════════════════════════════════════════════
        // GRAINS & CEREALS - typically 1 cup cooked or 1/2 cup dry
        // ═══════════════════════════════════════════════════════════════════
        if name.contains("rice") || name.contains("quinoa") || name.contains("pasta") ||
           name.contains("couscous") || name.contains("barley") {
            if name.contains("cooked") {
                return ("1", .cups)  // 1 cup cooked
            }
            return ("0.5", .cups)  // 1/2 cup dry
        }
        if name.contains("oatmeal") || name.contains("oats") {
            if name.contains("instant") || name.contains("packet") {
                return ("1", .packet)  // 1 packet = 28g
            }
            return ("0.5", .cups)  // 1/2 cup dry oats
        }
        if name.contains("cereal") || name.contains("granola") {
            return ("1", .cups)
        }
        if name.contains("bread") || name.contains("toast") {
            return ("1", .slice)  // 1 slice = 30g
        }
        
        // ═══════════════════════════════════════════════════════════════════
        // BACON
        // ═══════════════════════════════════════════════════════════════════
        if name.contains("bacon") {
            return ("2", .strip)  // 2 strips = 16g
        }
        
        // ═══════════════════════════════════════════════════════════════════
        // NUTS & SEEDS - typically 1 oz (small handful)
        // ═══════════════════════════════════════════════════════════════════
        if category.contains("nut") || category.contains("seed") {
            if name.contains("butter") { // Already handled above
                return ("2", .tablespoons)
            }
            return ("1", .ounces)  // 1 oz = 28g, about 23 almonds
        }
        if name.contains("almond") || name.contains("walnut") || name.contains("cashew") ||
           name.contains("pistachio") || name.contains("pecan") || name.contains("peanut") ||
           name.contains("macadamia") || name.contains("hazelnut") {
            return ("1", .ounces)
        }
        if name.contains("chia") || name.contains("flax") || name.contains("hemp") ||
           name.contains("sunflower seed") || name.contains("pumpkin seed") {
            return ("1", .tablespoons)
        }
        
        // ═══════════════════════════════════════════════════════════════════
        // FRUITS - typically 1 medium piece or 1 cup
        // ═══════════════════════════════════════════════════════════════════
        if category.contains("fruit") {
            // Whole fruits that come in distinct pieces
            if name.contains("banana") { return ("1", .medium) }   // 1 medium banana = 118g
            if name.contains("apple") { return ("1", .medium) }    // 1 medium apple = 182g
            if name.contains("orange") { return ("1", .medium) }   // 1 medium orange = 131g
            if name.contains("peach") { return ("1", .medium) }
            if name.contains("pear") { return ("1", .medium) }
            if name.contains("mango") { return ("1", .medium) }
            if name.contains("avocado") { return ("0.5", .whole) } // 1/2 avocado
            // Berries and grapes - use cups
            if name.contains("berries") || name.contains("strawberry") || name.contains("blueberry") ||
               name.contains("raspberry") || name.contains("blackberry") {
                return ("1", .cups)
            }
            if name.contains("grape") { return ("1", .cups) }
            return ("1", .cups)  // Default for fruits
        }
        
        // ═══════════════════════════════════════════════════════════════════
        // VEGETABLES - typically 1 cup
        // ═══════════════════════════════════════════════════════════════════
        if category.contains("vegetable") {
            if name.contains("potato") || name.contains("sweet potato") {
                return ("150", .grams)  // 1 medium potato
            }
            return ("1", .cups)
        }
        
        // ═══════════════════════════════════════════════════════════════════
        // BEVERAGES - typically 1 cup (8 oz)
        // ═══════════════════════════════════════════════════════════════════
        if category.contains("beverage") || name.contains("juice") || name.contains("coffee") ||
           name.contains("tea") || name.contains("smoothie") || name.contains("shake") {
            return ("1", .cups)
        }
        
        // ═══════════════════════════════════════════════════════════════════
        // BEANS & LEGUMES - typically 1/2 cup
        // ═══════════════════════════════════════════════════════════════════
        if category.contains("legume") || name.contains("beans") || name.contains("lentils") ||
           name.contains("chickpeas") || name.contains("hummus") {
            if name.contains("hummus") {
                return ("2", .tablespoons)
            }
            return ("0.5", .cups)
        }
        
        // ═══════════════════════════════════════════════════════════════════
        // PROTEIN POWDER & SUPPLEMENTS - typically 1 scoop (30g)
        // ═══════════════════════════════════════════════════════════════════
        if name.contains("protein powder") || name.contains("whey") || name.contains("casein") {
            return ("1", .scoop)  // 1 scoop = 30g
        }
        
        // ═══════════════════════════════════════════════════════════════════
        // PROTEIN/GRANOLA BARS
        // ═══════════════════════════════════════════════════════════════════
        if name.contains("bar") && (name.contains("protein") || name.contains("granola") || 
           name.contains("energy") || name.contains("snack")) {
            return ("1", .bar)  // 1 bar = 50g
        }
        
        // ═══════════════════════════════════════════════════════════════════
        // SUGAR, SWEETENERS - typically 1 tsp
        // ═══════════════════════════════════════════════════════════════════
        if name.contains("sugar") || name.contains("sweetener") || name.contains("stevia") {
            return ("1", .teaspoons)
        }
        
        // ═══════════════════════════════════════════════════════════════════
        // DEFAULT - For unrecognized foods, use a reasonable portion
        // If USDA serving is 100g, default to 1 oz (28g) as a starting point
        // ═══════════════════════════════════════════════════════════════════
        if food.servingSize >= 99 && food.servingSize <= 101 {
            return ("1", .ounces)  // 1 oz is a reasonable starting point
        }
        
        // Use USDA's serving size if it's not 100g (might be a branded food with real serving)
        return (String(Int(food.servingSize)), .grams)
    }
    
    /// Calculates nutrition based on current serving amount and unit
    /// All conversions are based on gram weights for accuracy
    private var currentNutrition: NutritionInfo {
        let amount = Double(servingAmount) ?? 0
        // USDA nutrition data is per servingSize (usually 100g for Foundation/SR Legacy foods)
        let baseServing = max(0.1, food.servingSize)
        
        // Convert the user's input to grams based on selected unit
        let totalGrams = amount * selectedUnit.gramsPerUnit
        
        // Calculate nutrition: (totalGrams / baseServing) × baseNutrition
        return food.nutrition.perServing(servingSize: totalGrams, servingUnit: selectedUnit.rawValue, originalServingSize: baseServing)
    }
    
    /// Converts the current amount to a new unit while preserving the gram weight
    private func convertToUnit(_ newUnit: ServingUnit) {
        guard let currentAmount = Double(servingAmount) else { return }
        
        // Calculate total grams from current unit
        let totalGrams = currentAmount * selectedUnit.gramsPerUnit
        
        // Convert to new unit
        let newAmount = totalGrams / newUnit.gramsPerUnit
        
        // Format nicely (avoid excessive decimals)
        if newAmount >= 10 {
            servingAmount = String(Int(round(newAmount)))
        } else if newAmount >= 1 {
            servingAmount = String(format: "%.1f", newAmount).replacingOccurrences(of: ".0", with: "")
        } else {
            servingAmount = String(format: "%.2f", newAmount)
        }
        
        selectedUnit = newUnit
    }
    
    /// Checks if the current serving approximately matches the given gram weight
    private func isCurrentServing(grams targetGrams: Double) -> Bool {
        guard let amount = Double(servingAmount) else { return false }
        let currentGrams = amount * selectedUnit.gramsPerUnit
        // Allow 1% tolerance for floating point comparison
        return abs(currentGrams - targetGrams) < max(1, targetGrams * 0.01)
    }
    
    /// Quick portion option for the buttons
    private struct QuickPortion {
        let label: String
        let amount: String
        let unit: ServingUnit
        var grams: Double { (Double(amount) ?? 1) * unit.gramsPerUnit }
    }
    
    /// Returns contextual quick portions based on the food type
    private var contextualQuickPortions: [QuickPortion] {
        let name = food.displayName.lowercased()
        let category = food.category?.lowercased() ?? ""
        
        // ═══════════════════════════════════════════════════════════════════
        // EGGS
        // ═══════════════════════════════════════════════════════════════════
        if name.contains("egg") && !name.contains("eggplant") {
            return [
                QuickPortion(label: "1 egg", amount: "1", unit: .egg),
                QuickPortion(label: "2 eggs", amount: "2", unit: .egg),
                QuickPortion(label: "3 eggs", amount: "3", unit: .egg),
                QuickPortion(label: "100g", amount: "100", unit: .grams)
            ]
        }
        
        // ═══════════════════════════════════════════════════════════════════
        // CHICKEN PIECES
        // ═══════════════════════════════════════════════════════════════════
        if name.contains("chicken breast") || name.contains("turkey breast") {
            return [
                QuickPortion(label: "1 breast", amount: "1", unit: .breast),
                QuickPortion(label: "½ breast", amount: "0.5", unit: .breast),
                QuickPortion(label: "4 oz", amount: "4", unit: .ounces),
                QuickPortion(label: "100g", amount: "100", unit: .grams)
            ]
        }
        if name.contains("chicken thigh") || name.contains("turkey thigh") {
            return [
                QuickPortion(label: "1 thigh", amount: "1", unit: .thigh),
                QuickPortion(label: "2 thighs", amount: "2", unit: .thigh),
                QuickPortion(label: "4 oz", amount: "4", unit: .ounces),
                QuickPortion(label: "100g", amount: "100", unit: .grams)
            ]
        }
        if name.contains("drumstick") || name.contains("chicken leg") {
            return [
                QuickPortion(label: "1 drumstick", amount: "1", unit: .drumstick),
                QuickPortion(label: "2 drumsticks", amount: "2", unit: .drumstick),
                QuickPortion(label: "4 oz", amount: "4", unit: .ounces),
                QuickPortion(label: "100g", amount: "100", unit: .grams)
            ]
        }
        if name.contains("wing") {
            return [
                QuickPortion(label: "2 wings", amount: "2", unit: .wing),
                QuickPortion(label: "4 wings", amount: "4", unit: .wing),
                QuickPortion(label: "6 wings", amount: "6", unit: .wing),
                QuickPortion(label: "100g", amount: "100", unit: .grams)
            ]
        }
        
        // ═══════════════════════════════════════════════════════════════════
        // FISH FILLETS
        // ═══════════════════════════════════════════════════════════════════
        if name.contains("salmon") || name.contains("tilapia") || name.contains("cod") ||
           name.contains("halibut") || name.contains("mahi") {
            return [
                QuickPortion(label: "1 fillet", amount: "1", unit: .fillet),
                QuickPortion(label: "½ fillet", amount: "0.5", unit: .fillet),
                QuickPortion(label: "4 oz", amount: "4", unit: .ounces),
                QuickPortion(label: "100g", amount: "100", unit: .grams)
            ]
        }
        
        // ═══════════════════════════════════════════════════════════════════
        // SAUSAGES & HOT DOGS
        // ═══════════════════════════════════════════════════════════════════
        if name.contains("sausage") || name.contains("hot dog") || name.contains("frankfurter") {
            return [
                QuickPortion(label: "1 link", amount: "1", unit: .link),
                QuickPortion(label: "2 links", amount: "2", unit: .link),
                QuickPortion(label: "3 links", amount: "3", unit: .link),
                QuickPortion(label: "100g", amount: "100", unit: .grams)
            ]
        }
        
        // ═══════════════════════════════════════════════════════════════════
        // BACON
        // ═══════════════════════════════════════════════════════════════════
        if name.contains("bacon") {
            return [
                QuickPortion(label: "2 strips", amount: "2", unit: .strip),
                QuickPortion(label: "3 strips", amount: "3", unit: .strip),
                QuickPortion(label: "4 strips", amount: "4", unit: .strip),
                QuickPortion(label: "100g", amount: "100", unit: .grams)
            ]
        }
        
        // ═══════════════════════════════════════════════════════════════════
        // BURGER PATTIES
        // ═══════════════════════════════════════════════════════════════════
        if name.contains("patty") || (name.contains("burger") && name.contains("beef")) {
            return [
                QuickPortion(label: "1 patty", amount: "1", unit: .patty),
                QuickPortion(label: "2 patties", amount: "2", unit: .patty),
                QuickPortion(label: "4 oz", amount: "4", unit: .ounces),
                QuickPortion(label: "100g", amount: "100", unit: .grams)
            ]
        }
        
        // ═══════════════════════════════════════════════════════════════════
        // BREAD
        // ═══════════════════════════════════════════════════════════════════
        if name.contains("bread") || name.contains("toast") {
            return [
                QuickPortion(label: "1 slice", amount: "1", unit: .slice),
                QuickPortion(label: "2 slices", amount: "2", unit: .slice),
                QuickPortion(label: "1 oz", amount: "1", unit: .ounces),
                QuickPortion(label: "100g", amount: "100", unit: .grams)
            ]
        }
        
        // ═══════════════════════════════════════════════════════════════════
        // WHOLE FRUITS
        // ═══════════════════════════════════════════════════════════════════
        if category.contains("fruit") {
            if name.contains("banana") || name.contains("apple") || name.contains("orange") ||
               name.contains("peach") || name.contains("pear") || name.contains("mango") {
                return [
                    QuickPortion(label: "1 medium", amount: "1", unit: .medium),
                    QuickPortion(label: "1 small", amount: "1", unit: .small),
                    QuickPortion(label: "1 large", amount: "1", unit: .large),
                    QuickPortion(label: "100g", amount: "100", unit: .grams)
                ]
            }
            // Berries and other fruits
            return [
                QuickPortion(label: "½ cup", amount: "0.5", unit: .cups),
                QuickPortion(label: "1 cup", amount: "1", unit: .cups),
                QuickPortion(label: "100g", amount: "100", unit: .grams),
                QuickPortion(label: "200g", amount: "200", unit: .grams)
            ]
        }
        
        // ═══════════════════════════════════════════════════════════════════
        // YOGURT
        // ═══════════════════════════════════════════════════════════════════
        if name.contains("yogurt") || name.contains("skyr") {
            return [
                QuickPortion(label: "1 container", amount: "1", unit: .container),
                QuickPortion(label: "½ cup", amount: "0.5", unit: .cups),
                QuickPortion(label: "1 cup", amount: "1", unit: .cups),
                QuickPortion(label: "100g", amount: "100", unit: .grams)
            ]
        }
        
        // ═══════════════════════════════════════════════════════════════════
        // PROTEIN POWDER
        // ═══════════════════════════════════════════════════════════════════
        if name.contains("protein") && (name.contains("powder") || name.contains("whey") || name.contains("casein")) {
            return [
                QuickPortion(label: "1 scoop", amount: "1", unit: .scoop),
                QuickPortion(label: "2 scoops", amount: "2", unit: .scoop),
                QuickPortion(label: "1 oz", amount: "1", unit: .ounces),
                QuickPortion(label: "100g", amount: "100", unit: .grams)
            ]
        }
        
        // ═══════════════════════════════════════════════════════════════════
        // PROTEIN/GRANOLA BARS
        // ═══════════════════════════════════════════════════════════════════
        if name.contains("bar") && (name.contains("protein") || name.contains("granola") || name.contains("energy")) {
            return [
                QuickPortion(label: "1 bar", amount: "1", unit: .bar),
                QuickPortion(label: "½ bar", amount: "0.5", unit: .bar),
                QuickPortion(label: "2 bars", amount: "2", unit: .bar),
                QuickPortion(label: "100g", amount: "100", unit: .grams)
            ]
        }
        
        // ═══════════════════════════════════════════════════════════════════
        // NUT BUTTERS & SPREADS
        // ═══════════════════════════════════════════════════════════════════
        if name.contains("butter") && (name.contains("almond") || name.contains("peanut") || 
           name.contains("cashew") || name.contains("sunflower") || name.contains("hazelnut")) {
            return [
                QuickPortion(label: "1 tbsp", amount: "1", unit: .tablespoons),
                QuickPortion(label: "2 tbsp", amount: "2", unit: .tablespoons),
                QuickPortion(label: "1 oz", amount: "1", unit: .ounces),
                QuickPortion(label: "100g", amount: "100", unit: .grams)
            ]
        }
        
        // ═══════════════════════════════════════════════════════════════════
        // BUTTER, OILS
        // ═══════════════════════════════════════════════════════════════════
        if name.contains("butter") || name.contains("oil") || name.contains("ghee") {
            return [
                QuickPortion(label: "1 tsp", amount: "1", unit: .teaspoons),
                QuickPortion(label: "1 tbsp", amount: "1", unit: .tablespoons),
                QuickPortion(label: "2 tbsp", amount: "2", unit: .tablespoons),
                QuickPortion(label: "100g", amount: "100", unit: .grams)
            ]
        }
        
        // ═══════════════════════════════════════════════════════════════════
        // GENERIC MEATS & PROTEINS
        // ═══════════════════════════════════════════════════════════════════
        if category.contains("meat") || category.contains("poultry") || category.contains("fish") ||
           name.contains("chicken") || name.contains("beef") || name.contains("salmon") {
            return [
                QuickPortion(label: "3 oz", amount: "3", unit: .ounces),
                QuickPortion(label: "4 oz", amount: "4", unit: .ounces),
                QuickPortion(label: "6 oz", amount: "6", unit: .ounces),
                QuickPortion(label: "100g", amount: "100", unit: .grams)
            ]
        }
        
        // ═══════════════════════════════════════════════════════════════════
        // CHEESE
        // ═══════════════════════════════════════════════════════════════════
        if name.contains("cheese") {
            return [
                QuickPortion(label: "1 oz", amount: "1", unit: .ounces),
                QuickPortion(label: "2 oz", amount: "2", unit: .ounces),
                QuickPortion(label: "¼ cup", amount: "0.25", unit: .cups),
                QuickPortion(label: "100g", amount: "100", unit: .grams)
            ]
        }
        
        // ═══════════════════════════════════════════════════════════════════
        // NUTS & SEEDS (not butters)
        // ═══════════════════════════════════════════════════════════════════
        if category.contains("nut") || category.contains("seed") {
            return [
                QuickPortion(label: "1 oz", amount: "1", unit: .ounces),
                QuickPortion(label: "¼ cup", amount: "0.25", unit: .cups),
                QuickPortion(label: "½ cup", amount: "0.5", unit: .cups),
                QuickPortion(label: "100g", amount: "100", unit: .grams)
            ]
        }
        
        // ═══════════════════════════════════════════════════════════════════
        // GRAINS, RICE, PASTA
        // ═══════════════════════════════════════════════════════════════════
        if name.contains("rice") || name.contains("pasta") || name.contains("quinoa") ||
           name.contains("oat") || name.contains("cereal") {
            return [
                QuickPortion(label: "½ cup", amount: "0.5", unit: .cups),
                QuickPortion(label: "1 cup", amount: "1", unit: .cups),
                QuickPortion(label: "1.5 cups", amount: "1.5", unit: .cups),
                QuickPortion(label: "100g", amount: "100", unit: .grams)
            ]
        }
        
        // ═══════════════════════════════════════════════════════════════════
        // VEGETABLES
        // ═══════════════════════════════════════════════════════════════════
        if category.contains("vegetable") {
            return [
                QuickPortion(label: "½ cup", amount: "0.5", unit: .cups),
                QuickPortion(label: "1 cup", amount: "1", unit: .cups),
                QuickPortion(label: "100g", amount: "100", unit: .grams),
                QuickPortion(label: "200g", amount: "200", unit: .grams)
            ]
        }
        
        // ═══════════════════════════════════════════════════════════════════
        // BEVERAGES
        // ═══════════════════════════════════════════════════════════════════
        if category.contains("beverage") || name.contains("milk") || name.contains("juice") {
            return [
                QuickPortion(label: "½ cup", amount: "0.5", unit: .cups),
                QuickPortion(label: "1 cup", amount: "1", unit: .cups),
                QuickPortion(label: "12 oz", amount: "12", unit: .ounces),
                QuickPortion(label: "100ml", amount: "100", unit: .milliliters)
            ]
        }
        
        // ═══════════════════════════════════════════════════════════════════
        // DEFAULT OPTIONS
        // ═══════════════════════════════════════════════════════════════════
        return [
            QuickPortion(label: "1 oz", amount: "1", unit: .ounces),
            QuickPortion(label: "50g", amount: "50", unit: .grams),
            QuickPortion(label: "100g", amount: "100", unit: .grams),
            QuickPortion(label: "1 cup", amount: "1", unit: .cups)
        ]
    }
    
    private var mealGradient: [Color] {
        switch mealType {
        case .breakfast: return [.orange, .yellow]
        case .lunch: return [.green, .teal]
        case .dinner: return [.purple, .pink]
        case .snacks: return [.blue, .cyan]
        }
    }
    
    private func goBack() {
        onDismiss()
        dismiss()
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                // Header bar
                HStack {
                    Button(action: goBack) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Back")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(Color(.systemGray6))
                        )
                    }
                    
                    Spacer()
                    
                    Text("Food Details")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    // Balance spacer
                    Color.clear.frame(width: 70, height: 32)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 16)
                
                // Main content - no scroll for most foods
                VStack(spacing: 16) {
                    // Main Food Card
                    mainFoodCard
                    
                    // Detailed Nutrition (if available)
                    if hasDetailedNutrition {
                        detailedNutritionCard
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
            }
            .background(Color(.systemGroupedBackground))
            
            // Floating Add Button
            floatingAddButton
        }
        .navigationBarHidden(true)
    }
    
    // MARK: - Main Food Card
    private var mainFoodCard: some View {
        VStack(spacing: 0) {
            // Food Header
            HStack(spacing: 14) {
                // Food Icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: categoryGradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)
                    
                    Text(foodEmoji)
                        .font(.system(size: 28))
                }
                
                // Food Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(food.displayName)
                        .font(.system(size: 17, weight: .bold))
                        .lineLimit(2)
                        .foregroundColor(.primary)
                    
                    if let category = food.category {
                        Text(category)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
            .padding(18)
            
            Divider()
                .padding(.horizontal, 18)
            
            // Calories - Big & Prominent
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(Int(currentNutrition.calories))")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: mealGradient,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    Text("calories")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Macros - Vertical stack
                VStack(alignment: .trailing, spacing: 8) {
                    MacroRow(label: "Protein", value: currentNutrition.protein, color: .blue)
                    MacroRow(label: "Carbs", value: currentNutrition.carbohydrates, color: .orange)
                    MacroRow(label: "Fat", value: currentNutrition.totalFat, color: .red)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 20)
            
            Divider()
                .padding(.horizontal, 18)
            
            // Serving Size Section with Input + Unit Dropdown
            HStack(spacing: 12) {
                Text("Serving Size")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .fixedSize()
                
                Spacer()
                
                // Amount input + Unit dropdown
                HStack(spacing: 6) {
                    // Amount input field
                    TextField("100", text: $servingAmount)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 60)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(.systemGray6))
                        )
                    
                    // Unit dropdown picker
                    Menu {
                        ForEach(availableServingUnits) { unit in
                            Button(action: {
                                convertToUnit(unit)
                            }) {
                                HStack {
                                    Text(unit.displayName)
                                    if unit == selectedUnit {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(selectedUnit.displayName)
                                .font(.system(size: 16, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                                .fixedSize(horizontal: false, vertical: true)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .frame(minWidth: 80)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(.systemGray6))
                        )
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            
            // Quick portion shortcuts - contextual based on food type
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Show contextual quick portions based on food type
                    ForEach(contextualQuickPortions, id: \.label) { portion in
                        QuickPortionButton(
                            title: portion.label,
                            isSelected: isCurrentServing(grams: portion.grams)
                        ) {
                            servingAmount = portion.amount
                            selectedUnit = portion.unit
                        }
                    }
                    
                    // Add USDA-provided portions if available (and not duplicates)
                    ForEach(food.portions.prefix(2)) { portion in
                        QuickPortionButton(
                            title: portion.displayText,
                            isSelected: isCurrentServing(grams: portion.gramWeight)
                        ) {
                            servingAmount = String(format: "%.0f", portion.gramWeight)
                            selectedUnit = .grams
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 14)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(colorScheme == .dark ? Color(white: 0.15) : Color.white)
                .shadow(color: categoryGradient[0].opacity(0.15), radius: 12, x: 0, y: 6)
                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
    }
    
    // MARK: - Detailed Nutrition Card
    private var detailedNutritionCard: some View {
        VStack(spacing: 0) {
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showDetailedNutrition.toggle()
                }
            }) {
                HStack {
                    Text("Detailed Nutrition")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(showDetailedNutrition ? 90 : 0))
                }
                .padding(16)
            }
            .buttonStyle(PlainButtonStyle())
            
            if showDetailedNutrition {
                Divider()
                    .padding(.horizontal, 16)
                
                // 2-column grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    NutrientRow(name: "Saturated Fat", value: currentNutrition.saturatedFat, unit: "g")
                    NutrientRow(name: "Fiber", value: currentNutrition.fiber, unit: "g")
                    NutrientRow(name: "Sugar", value: currentNutrition.sugar, unit: "g")
                    NutrientRow(name: "Sodium", value: currentNutrition.sodium, unit: "mg")
                    NutrientRow(name: "Cholesterol", value: currentNutrition.cholesterol, unit: "mg")
                    NutrientRow(name: "Calcium", value: currentNutrition.calcium, unit: "mg")
                    NutrientRow(name: "Iron", value: currentNutrition.iron, unit: "mg")
                    NutrientRow(name: "Vitamin C", value: currentNutrition.vitaminC, unit: "mg")
                }
                .padding(16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(white: 0.15) : Color.white)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 3)
        )
    }
    
    // MARK: - Floating Add Button
    private var floatingAddButton: some View {
        Button(action: addFoodToMeal) {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .bold))
                Text("Add to \(mealType.displayName)")
                    .font(.headline)
                    .fontWeight(.bold)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 32)
            .padding(.vertical, 16)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: mealGradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .shadow(color: mealGradient[0].opacity(0.4), radius: 16, x: 0, y: 8)
                    .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
            )
        }
        .disabled(isLoading)
        .opacity(isLoading ? 0.6 : 1.0)
        .padding(.bottom, 30)
    }
    
    // MARK: - Macro Row Component
    private struct MacroRow: View {
        let label: String
        let value: Double
        let color: Color
        
        var body: some View {
            HStack(spacing: 6) {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(formatValue(value))g")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(color)
            }
        }
        
        private func formatValue(_ val: Double) -> String {
            if val < 1 && val > 0 { return String(format: "%.1f", val) }
            return String(Int(val))
        }
    }
    
    // MARK: - USDA-Based Serving System
    
    /// Returns the USDA default serving unit (always respect what USDA provides)
    private var usdaDefaultServingUnit: String {
        food.servingUnit
    }
    
    /// Returns the USDA default serving size
    private var usdaDefaultServingSize: Double {
        food.servingSize
    }
    
    /// Label for the USDA default portion (e.g., "100g", "1 cup", "28g")
    private var usdaDefaultPortionLabel: String {
        let size = usdaDefaultServingSize
        let unit = usdaDefaultServingUnit
        
        // Format nicely
        if unit == "g" || unit == "G" {
            return "\(formatAmount(size))g"
        } else if unit == "ml" || unit == "ML" {
            return "\(formatAmount(size))ml"
        } else {
            // For units like "cup", "tbsp", etc.
            return "\(formatAmount(size)) \(unit)"
        }
    }
    
    /// Standard portions auto-generated for easy conversion
    /// These allow users to input in any common unit
    private var standardPortions: [FoodPortion] {
        var portions: [FoodPortion] = []
        let existingUnits = Set(food.portions.map { $0.unit.lowercased() })
        
        // Standard conversions (gram weights for each unit)
        // 1g - always available for precise tracking
        if usdaDefaultServingSize != 1 || usdaDefaultServingUnit != "g" {
            portions.append(FoodPortion(id: -100, amount: 1, unit: "g", gramWeight: 1, description: nil))
        }
        
        // 100g - standard reference amount (skip if USDA default is already 100g)
        if !(usdaDefaultServingSize >= 99 && usdaDefaultServingSize <= 101 && usdaDefaultServingUnit == "g") {
            portions.append(FoodPortion(id: -101, amount: 100, unit: "g", gramWeight: 100, description: nil))
        }
        
        // 1 oz = 28.35g (common US measurement)
        if !existingUnits.contains("oz") && !existingUnits.contains("ounce") {
            portions.append(FoodPortion(id: -102, amount: 1, unit: "oz", gramWeight: 28.35, description: nil))
        }
        
        // 1 tbsp = ~15g (common for spreads, oils, butter)
        if !existingUnits.contains("tbsp") && !existingUnits.contains("tablespoon") {
            portions.append(FoodPortion(id: -103, amount: 1, unit: "tbsp", gramWeight: 15, description: nil))
        }
        
        // 1 cup = ~240g (common for liquids, grains)
        // Only add if category suggests it's useful
        let category = food.category?.lowercased() ?? ""
        let name = food.displayName.lowercased()
        if !existingUnits.contains("cup") {
            if category.contains("beverage") || category.contains("dairy") || 
               category.contains("grain") || category.contains("legume") ||
               name.contains("rice") || name.contains("milk") || name.contains("yogurt") ||
               name.contains("juice") || name.contains("cereal") || name.contains("oat") {
                portions.append(FoodPortion(id: -104, amount: 1, unit: "cup", gramWeight: 240, description: nil))
            }
        }
        
        return portions
    }
    
    /// Combines USDA portions with auto-generated standard portions
    private var allAvailablePortions: [FoodPortion] {
        // Start with standard portions, then add USDA-provided portions
        var all = standardPortions
        
        // Add USDA-provided portions (cups, tablespoons, etc. from their database)
        for portion in food.portions {
            // Avoid duplicates by checking unit similarity
            let isDuplicate = all.contains { existing in
                existing.unit.lowercased() == portion.unit.lowercased() &&
                abs(existing.gramWeight - portion.gramWeight) < 1
            }
            if !isDuplicate {
                all.append(portion)
            }
        }
        
        return all
    }
    
    /// Current serving unit based on selection
    private var currentServingUnit: String {
        selectedUnit.rawValue
    }
    
    // Legacy compatibility - maps to new system
    private var smartServingUnit: String {
        usdaDefaultServingUnit
    }
    
    private var smartServingWeight: Double? {
        nil // No longer using smart weight guessing - use USDA data
    }
    
    private var hasSmartPortions: Bool {
        true // Always show portion options now
    }
    
    private var smartDefaultPortionLabel: String {
        usdaDefaultPortionLabel
    }
    
    private var categoryGradient: [Color] {
        guard let category = food.category?.lowercased() else { return [.green, .teal] }
        
        if category.contains("dairy") || category.contains("milk") || category.contains("egg") {
            return [.blue, .cyan]
        } else if category.contains("meat") || category.contains("poultry") || category.contains("beef") || category.contains("pork") {
            return [.red, .orange]
        } else if category.contains("fish") || category.contains("seafood") {
            return [.blue, .indigo]
        } else if category.contains("fruit") {
            return [.pink, .orange]
        } else if category.contains("vegetable") {
            return [.green, .teal]
        } else if category.contains("grain") || category.contains("cereal") || category.contains("bread") {
            return [.orange, .yellow]
        } else if category.contains("nut") || category.contains("seed") {
            return [.brown, .orange]
        } else if category.contains("legume") {
            return [.brown, .green]
        } else {
            return [.green, .teal]
        }
    }
    
    private var foodIcon: String {
        guard let category = food.category?.lowercased() else { return "leaf.fill" }
        
        if category.contains("dairy") || category.contains("milk") {
            return "drop.fill"
        } else if category.contains("egg") {
            return "oval.fill"
        } else if category.contains("meat") || category.contains("poultry") || category.contains("beef") || category.contains("pork") {
            return "flame.fill"
        } else if category.contains("fish") || category.contains("seafood") {
            return "fish.fill"
        } else if category.contains("fruit") {
            return "apple"
        } else if category.contains("vegetable") {
            return "carrot.fill"
        } else if category.contains("grain") || category.contains("cereal") || category.contains("bread") {
            return "leaf.fill"
        } else if category.contains("nut") || category.contains("seed") {
            return "circle.hexagongrid.fill"
        } else if category.contains("legume") {
            return "leaf.fill"
        } else {
            return "leaf.fill"
        }
    }
    
    /// Returns a food emoji based on the food name and category
    /// Comprehensive mapping of foods to their corresponding emojis
    private var foodEmoji: String {
        let name = food.displayName.lowercased()
        let category = food.category?.lowercased() ?? ""
        
        // ═══════════════════════════════════════════════════════════════════
        // FRUITS 🍎
        // ═══════════════════════════════════════════════════════════════════
        if name.contains("apple") { return "🍎" }
        if name.contains("banana") { return "🍌" }
        if name.contains("orange") && !name.contains("chicken") { return "🍊" }
        if name.contains("lemon") { return "🍋" }
        if name.contains("lime") { return "🍋‍🟩" }
        if name.contains("grape") { return "🍇" }
        if name.contains("watermelon") { return "🍉" }
        if name.contains("melon") || name.contains("cantaloupe") || name.contains("honeydew") { return "🍈" }
        if name.contains("strawberry") || name.contains("strawberries") { return "🍓" }
        if name.contains("blueberry") || name.contains("blueberries") { return "🫐" }
        if name.contains("cherry") || name.contains("cherries") { return "🍒" }
        if name.contains("peach") { return "🍑" }
        if name.contains("pear") { return "🍐" }
        if name.contains("mango") { return "🥭" }
        if name.contains("pineapple") { return "🍍" }
        if name.contains("coconut") { return "🥥" }
        if name.contains("kiwi") { return "🥝" }
        if name.contains("avocado") { return "🥑" }
        if name.contains("tomato") { return "🍅" }
        if name.contains("olive") { return "🫒" }
        
        // ═══════════════════════════════════════════════════════════════════
        // VEGETABLES 🥦
        // ═══════════════════════════════════════════════════════════════════
        if name.contains("broccoli") { return "🥦" }
        if name.contains("carrot") { return "🥕" }
        if name.contains("corn") { return "🌽" }
        if name.contains("cucumber") { return "🥒" }
        if name.contains("lettuce") || name.contains("salad") { return "🥬" }
        if name.contains("spinach") || name.contains("kale") || name.contains("greens") { return "🥬" }
        if name.contains("pepper") && !name.contains("black pepper") { return "🫑" }
        if name.contains("hot pepper") || name.contains("chili") || name.contains("jalapeño") { return "🌶️" }
        if name.contains("onion") { return "🧅" }
        if name.contains("garlic") { return "🧄" }
        if name.contains("potato") && !name.contains("sweet") { return "🥔" }
        if name.contains("sweet potato") || name.contains("yam") { return "🍠" }
        if name.contains("eggplant") || name.contains("aubergine") { return "🍆" }
        if name.contains("mushroom") { return "🍄" }
        if name.contains("peanut") && !name.contains("butter") { return "🥜" }
        if name.contains("bean") || name.contains("legume") { return "🫘" }
        if name.contains("pea") { return "🫛" }
        if name.contains("ginger") { return "🫚" }
        
        // ═══════════════════════════════════════════════════════════════════
        // PROTEINS 🥩
        // ═══════════════════════════════════════════════════════════════════
        if name.contains("egg") && !name.contains("eggplant") { return "🥚" }
        if name.contains("chicken") { return "🍗" }
        if name.contains("turkey") { return "🦃" }
        if name.contains("beef") || name.contains("steak") { return "🥩" }
        if name.contains("pork") || name.contains("ham") { return "🥓" }
        if name.contains("bacon") { return "🥓" }
        if name.contains("sausage") || name.contains("hot dog") { return "🌭" }
        if name.contains("fish") || name.contains("salmon") || name.contains("tuna") || 
           name.contains("cod") || name.contains("tilapia") || name.contains("halibut") { return "🐟" }
        if name.contains("shrimp") || name.contains("prawn") { return "🦐" }
        if name.contains("crab") { return "🦀" }
        if name.contains("lobster") { return "🦞" }
        if name.contains("oyster") { return "🦪" }
        if name.contains("squid") || name.contains("calamari") { return "🦑" }
        if name.contains("octopus") { return "🐙" }
        
        // ═══════════════════════════════════════════════════════════════════
        // DAIRY 🧀
        // ═══════════════════════════════════════════════════════════════════
        if name.contains("milk") { return "🥛" }
        if name.contains("cheese") { return "🧀" }
        if name.contains("butter") && !name.contains("peanut") && !name.contains("almond") { return "🧈" }
        if name.contains("yogurt") || name.contains("yoghurt") { return "🥛" }
        if name.contains("ice cream") { return "🍦" }
        
        // ═══════════════════════════════════════════════════════════════════
        // GRAINS & BREAD 🍞
        // ═══════════════════════════════════════════════════════════════════
        if name.contains("bread") || name.contains("toast") { return "🍞" }
        if name.contains("croissant") { return "🥐" }
        if name.contains("bagel") { return "🥯" }
        if name.contains("pretzel") { return "🥨" }
        if name.contains("pancake") { return "🥞" }
        if name.contains("waffle") { return "🧇" }
        if name.contains("rice") { return "🍚" }
        if name.contains("pasta") || name.contains("spaghetti") || name.contains("noodle") { return "🍝" }
        if name.contains("cereal") || name.contains("oat") || name.contains("granola") { return "🥣" }
        if name.contains("cookie") || name.contains("biscuit") { return "🍪" }
        if name.contains("cake") { return "🍰" }
        if name.contains("pie") { return "🥧" }
        if name.contains("donut") || name.contains("doughnut") { return "🍩" }
        if name.contains("muffin") || name.contains("cupcake") { return "🧁" }
        
        // ═══════════════════════════════════════════════════════════════════
        // NUTS & SEEDS 🥜
        // ═══════════════════════════════════════════════════════════════════
        if name.contains("almond") { return "🌰" }
        if name.contains("peanut") { return "🥜" }
        if name.contains("walnut") || name.contains("pecan") || name.contains("hazelnut") { return "🌰" }
        if name.contains("cashew") || name.contains("pistachio") { return "🌰" }
        if name.contains("chestnut") { return "🌰" }
        if category.contains("nut") || category.contains("seed") { return "🌰" }
        
        // ═══════════════════════════════════════════════════════════════════
        // BEVERAGES 🧃
        // ═══════════════════════════════════════════════════════════════════
        if name.contains("coffee") { return "☕" }
        if name.contains("tea") && !name.contains("steak") { return "🍵" }
        if name.contains("juice") { return "🧃" }
        if name.contains("smoothie") || name.contains("shake") { return "🥤" }
        if name.contains("soda") || name.contains("cola") { return "🥤" }
        if name.contains("beer") { return "🍺" }
        if name.contains("wine") { return "🍷" }
        if name.contains("cocktail") { return "🍸" }
        if name.contains("water") { return "💧" }
        
        // ═══════════════════════════════════════════════════════════════════
        // CONDIMENTS & SPREADS 🍯
        // ═══════════════════════════════════════════════════════════════════
        if name.contains("honey") { return "🍯" }
        if name.contains("peanut butter") || name.contains("almond butter") { return "🥜" }
        if name.contains("jam") || name.contains("jelly") { return "🍓" }
        if name.contains("ketchup") { return "🍅" }
        if name.contains("mustard") { return "🟡" }
        if name.contains("mayo") || name.contains("mayonnaise") { return "🥚" }
        if name.contains("sauce") { return "🫙" }
        if name.contains("oil") { return "🫒" }
        if name.contains("vinegar") { return "🫙" }
        if name.contains("salt") { return "🧂" }
        if name.contains("syrup") { return "🍁" }
        
        // ═══════════════════════════════════════════════════════════════════
        // PREPARED FOODS 🍔
        // ═══════════════════════════════════════════════════════════════════
        if name.contains("burger") || name.contains("hamburger") { return "🍔" }
        if name.contains("pizza") { return "🍕" }
        if name.contains("sandwich") || name.contains("sub") { return "🥪" }
        if name.contains("taco") { return "🌮" }
        if name.contains("burrito") { return "🌯" }
        if name.contains("hot dog") || name.contains("hotdog") { return "🌭" }
        if name.contains("fries") || name.contains("french fries") { return "🍟" }
        if name.contains("popcorn") { return "🍿" }
        if name.contains("soup") { return "🍲" }
        if name.contains("salad") { return "🥗" }
        if name.contains("sushi") { return "🍣" }
        if name.contains("ramen") { return "🍜" }
        if name.contains("curry") { return "🍛" }
        if name.contains("dumpling") { return "🥟" }
        
        // ═══════════════════════════════════════════════════════════════════
        // SWEETS & DESSERTS 🍫
        // ═══════════════════════════════════════════════════════════════════
        if name.contains("chocolate") { return "🍫" }
        if name.contains("candy") { return "🍬" }
        if name.contains("lollipop") { return "🍭" }
        if name.contains("pudding") || name.contains("custard") { return "🍮" }
        
        // ═══════════════════════════════════════════════════════════════════
        // SUPPLEMENTS & PROTEIN 💪
        // ═══════════════════════════════════════════════════════════════════
        if name.contains("protein") && (name.contains("powder") || name.contains("shake") || name.contains("bar")) { return "💪" }
        if name.contains("vitamin") || name.contains("supplement") { return "💊" }
        
        // ═══════════════════════════════════════════════════════════════════
        // CATEGORY-BASED FALLBACKS
        // ═══════════════════════════════════════════════════════════════════
        if category.contains("fruit") { return "🍎" }
        if category.contains("vegetable") { return "🥬" }
        if category.contains("meat") || category.contains("poultry") { return "🍖" }
        if category.contains("fish") || category.contains("seafood") { return "🐟" }
        if category.contains("dairy") { return "🥛" }
        if category.contains("grain") || category.contains("cereal") { return "🌾" }
        if category.contains("legume") { return "🫘" }
        if category.contains("beverage") { return "🥤" }
        if category.contains("snack") { return "🍿" }
        if category.contains("sweet") || category.contains("dessert") { return "🍰" }
        if category.contains("condiment") || category.contains("sauce") { return "🫙" }
        
        // Default
        return "🍽️"
    }
    
    // MARK: - Methods
    
    private func addFoodToMeal() {
        let amount = Double(servingAmount) ?? 1.0
        let nutrition = currentNutrition
        
        let foodEntry = FoodEntry(
            name: food.displayName,
            quantity: Int(amount),
            unit: currentServingUnit,
            calories: Int(nutrition.calories),
            protein: Int(nutrition.protein),
            carbs: Int(nutrition.carbohydrates),
            fat: Int(nutrition.totalFat),
            fdcId: food.id,
            foodItemId: food.id
        )
        
        onAdd(foodEntry)
        onDismiss()
    }
    
    private func formatAmount(_ amount: Double) -> String {
        if amount == floor(amount) {
            return String(Int(amount))
        } else {
            return String(format: "%.1f", amount)
        }
    }
}

// MARK: - Compact Macro Display
struct CompactMacro: View {
    let label: String
    let value: Double
    let color: Color
    
    var body: some View {
        VStack(spacing: 2) {
            Text(formatValue(value) + "g")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
    }
    
    private func formatValue(_ val: Double) -> String {
        if val < 1 && val > 0 {
            return String(format: "%.1f", val)
        }
        return String(Int(val))
    }
}

// MARK: - Compact Nutrient Row (for 2-column grid)
struct CompactNutrientRow: View {
    let name: String
    let value: Double
    let unit: String
    
    var body: some View {
        HStack {
            Text(name)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Spacer()
            Text("\(formatValue(value))\(unit)")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary)
        }
        .padding(.vertical, 2)
    }
    
    private func formatValue(_ val: Double) -> String {
        if val < 1 && val > 0 {
            return String(format: "%.1f", val)
        }
        return String(Int(val))
    }
}

// MARK: - Supporting Views

struct MacroBar: View {
    let label: String
    let value: Double
    let color: Color
    let maxValue: Double
    
    var body: some View {
        VStack(spacing: 6) {
            Text(formatValue(value) + "g")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(color)
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color.opacity(0.15))
                    
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: geo.size.width * min(value / maxValue, 1.0))
                }
            }
            .frame(height: 6)
            
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
    
    private func formatValue(_ val: Double) -> String {
        if val < 1 && val > 0 {
            return String(format: "%.1f", val)
        }
        return String(Int(val))
    }
}

struct PortionChip: View {
    let title: String
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            Text(title)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .medium)
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.green : Color(.systemGray6))
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// Alias for quick portion buttons (same appearance as PortionChip)
typealias QuickPortionButton = PortionChip

struct NutrientRow: View {
    let name: String
    let value: Double
    let unit: String
    
    var body: some View {
        HStack {
            Text(name)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text("\(formatValue(value))\(unit)")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.primary)
        }
        .padding(.vertical, 4)
    }
    
    private func formatValue(_ val: Double) -> String {
        if val < 1 && val > 0 {
            return String(format: "%.1f", val)
        }
        return String(Int(val))
    }
}

// Keep old components for backwards compatibility
struct ServingOptionRow: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .green : .secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.green.opacity(0.1) : Color(.systemGray6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? Color.green : Color.clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct MacroNutrientRow: View {
    let name: String
    let amount: Double
    let unit: String
    let color: Color
    
    var body: some View {
        HStack {
            HStack(spacing: 8) {
                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)
                
                Text(name)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            
            Spacer()
            
            Text("\(formatNutrientAmount(amount))\(unit)")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
        }
    }
    
    private func formatNutrientAmount(_ amount: Double) -> String {
        if amount < 1 {
            return String(format: "%.1f", amount)
        } else {
            return String(Int(amount))
        }
    }
}

struct DetailedNutrientRow: View {
    let name: String
    let amount: Double
    let unit: String
    
    var body: some View {
        HStack {
            Text(name)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text("\(formatNutrientAmount(amount))\(unit)")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.primary)
        }
    }
    
    private func formatNutrientAmount(_ amount: Double) -> String {
        if amount < 1 {
            return String(format: "%.1f", amount)
        } else {
            return String(Int(amount))
        }
    }
}

#Preview {
    FoodDetailsView(
        food: ProcessedFoodItem(
            id: 1,
            name: "Chicken Breast",
            brandName: nil,
            description: "Chicken, broilers or fryers, breast, meat only, cooked, roasted",
            category: "Poultry Products",
            servingSize: 100,
            servingUnit: "g",
            nutrition: NutritionInfo(
                calories: 165,
                protein: 31,
                carbohydrates: 0,
                totalFat: 3.6,
                saturatedFat: 1,
                fiber: 0,
                sugar: 0,
                sodium: 74,
                cholesterol: 85,
                calcium: 15,
                iron: 1,
                vitaminC: 0
            ),
            portions: [
                FoodPortion(id: 1, amount: 1, unit: "breast", gramWeight: 174, description: "medium"),
                FoodPortion(id: 2, amount: 3, unit: "oz", gramWeight: 85, description: nil)
            ],
            dataType: "Foundation"
        ),
        mealType: .lunch,
        onAdd: { _ in },
        onDismiss: { }
    )
}
