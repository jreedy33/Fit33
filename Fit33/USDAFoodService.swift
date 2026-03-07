import Foundation
import Combine

// MARK: - USDA API Models

struct USDAFoodSearchResponse: Codable {
    let foods: [USDAFoodItem]
    let totalHits: Int
    let currentPage: Int
    let totalPages: Int
}

struct USDAFoodItem: Codable, Identifiable {
    let fdcId: Int
    let description: String
    let dataType: String
    let foodCategory: String?
    let publishedDate: String
    let brandOwner: String?
    let brandName: String?
    let ingredients: String?
    let marketCountry: String?
    let foodCode: String?
    let gtinUpc: String?
    let householdServingFullText: String?
    let servingSize: Double?
    let servingSizeUnit: String?
    let packageWeight: String?
    let foodNutrients: [USDANutrient]?
    
    var id: Int { fdcId }
    
    var displayName: String {
        if let brandName = brandName, !brandName.isEmpty {
            return "\(brandName) \(description)"
        }
        return description
    }
    
    var servingInfo: String {
        if let servingSize = servingSize, let unit = servingSizeUnit {
            return "\(Int(servingSize)) \(unit)"
        } else if let householdServing = householdServingFullText {
            return householdServing
        }
        return "100g"
    }
}

struct USDANutrient: Codable {
    let nutrientId: Int
    let nutrientName: String
    let nutrientNumber: String
    let unitName: String
    let value: Double
    let rank: Int?
    let indentLevel: Int?
    let foodNutrientId: Int?
    
    enum CodingKeys: String, CodingKey {
        case nutrientId
        case nutrientName
        case nutrientNumber
        case unitName
        case value
        case rank
        case indentLevel
        case foodNutrientId
        // Alternative keys from different API formats
        case number  // Alternative for nutrientNumber
        case name    // Alternative for nutrientName
        case amount  // Alternative for value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // nutrientId: required with fallback to 0
        nutrientId = (try? container.decode(Int.self, forKey: .nutrientId)) ?? 0
        
        // nutrientName: try nutrientName then name
        if let name = try? container.decode(String.self, forKey: .nutrientName) {
            nutrientName = name
        } else if let name = try? container.decode(String.self, forKey: .name) {
            nutrientName = name
        } else {
            nutrientName = "Unknown"
        }
        
        // nutrientNumber: try nutrientNumber then number
        if let num = try? container.decode(String.self, forKey: .nutrientNumber) {
            nutrientNumber = num
        } else if let num = try? container.decode(String.self, forKey: .number) {
            nutrientNumber = num
        } else {
            nutrientNumber = "0"
        }
        
        // unitName: with fallback
        unitName = (try? container.decode(String.self, forKey: .unitName)) ?? "g"
        
        // value: try value then amount
        if let val = try? container.decode(Double.self, forKey: .value) {
            value = val
        } else if let val = try? container.decode(Double.self, forKey: .amount) {
            value = val
        } else {
            value = 0
        }
        
        // Optional fields
        rank = try? container.decode(Int.self, forKey: .rank)
        indentLevel = try? container.decode(Int.self, forKey: .indentLevel)
        foodNutrientId = try? container.decode(Int.self, forKey: .foodNutrientId)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(nutrientId, forKey: .nutrientId)
        try container.encode(nutrientName, forKey: .nutrientName)
        try container.encode(nutrientNumber, forKey: .nutrientNumber)
        try container.encode(unitName, forKey: .unitName)
        try container.encode(value, forKey: .value)
        try container.encodeIfPresent(rank, forKey: .rank)
        try container.encodeIfPresent(indentLevel, forKey: .indentLevel)
        try container.encodeIfPresent(foodNutrientId, forKey: .foodNutrientId)
    }
}

struct USDAFoodDetailsResponse: Codable {
    let fdcId: Int
    let description: String
    let dataType: String
    let foodClass: String?
    let foodCategory: USDAFoodCategory?
    let foodNutrients: [USDADetailedNutrient]
    let foodPortions: [USDAFoodPortion]?
    let brandOwner: String?
    let brandName: String?
    let ingredients: String?
    let servingSize: Double?
    let servingSizeUnit: String?
    let householdServingFullText: String?
}

struct USDAFoodCategory: Codable {
    let id: Int
    let code: String
    let description: String
}

struct USDADetailedNutrient: Codable {
    let type: String
    let id: Int?
    let nutrient: USDANutrientInfo
    let foodNutrientDerivation: USDANutrientDerivation?
    let amount: Double
}

struct USDANutrientInfo: Codable {
    let id: Int
    let number: String
    let name: String
    let rank: Int
    let unitName: String
}

struct USDANutrientDerivation: Codable {
    let id: Int
    let code: String
    let description: String
}

struct USDAFoodPortion: Codable {
    let id: Int
    let amount: Double
    let measureUnit: USDAMeasureUnit
    let modifier: String?
    let gramWeight: Double
    let sequenceNumber: Int?
}

struct USDAMeasureUnit: Codable {
    let id: Int
    let abbreviation: String
    let name: String
}

// MARK: - Processed Food Models

struct ProcessedFoodItem: Identifiable {
    let id: Int
    let name: String
    let brandName: String?
    let description: String
    let category: String?
    let servingSize: Double
    let servingUnit: String
    let nutrition: NutritionInfo
    let portions: [FoodPortion]
    let dataType: String?  // "Foundation", "SR Legacy", "Branded", etc.
    
    var displayName: String {
        if let brandName = brandName, !brandName.isEmpty {
            return "\(brandName) - \(name)"
        }
        return name
    }
}

struct NutritionInfo {
    let calories: Double
    let protein: Double // grams
    let carbohydrates: Double // grams
    let totalFat: Double // grams
    let saturatedFat: Double // grams
    let fiber: Double // grams
    let sugar: Double // grams
    let sodium: Double // mg
    let cholesterol: Double // mg
    let calcium: Double // mg
    let iron: Double // mg
    let vitaminC: Double // mg
    
    // Per serving calculations
    func perServing(servingSize: Double, servingUnit: String, originalServingSize: Double) -> NutritionInfo {
        let multiplier = servingSize / originalServingSize
        return NutritionInfo(
            calories: calories * multiplier,
            protein: protein * multiplier,
            carbohydrates: carbohydrates * multiplier,
            totalFat: totalFat * multiplier,
            saturatedFat: saturatedFat * multiplier,
            fiber: fiber * multiplier,
            sugar: sugar * multiplier,
            sodium: sodium * multiplier,
            cholesterol: cholesterol * multiplier,
            calcium: calcium * multiplier,
            iron: iron * multiplier,
            vitaminC: vitaminC * multiplier
        )
    }
}

struct FoodPortion: Identifiable {
    let id: Int
    let amount: Double
    let unit: String
    let gramWeight: Double
    let description: String?
    
    var displayText: String {
        let baseText = "\(formatAmount(amount)) \(unit)"
        if let desc = description, !desc.isEmpty {
            return "\(baseText) (\(desc))"
        }
        return baseText
    }
    
    private func formatAmount(_ amount: Double) -> String {
        if amount == floor(amount) {
            return String(Int(amount))
        } else {
            return String(format: "%.1f", amount)
        }
    }
}

// MARK: - USDA Food Service

class USDAFoodService: ObservableObject {
    static let shared = USDAFoodService()
    
    // Cloud-based food database service
    private let cloudService = FoodDatabaseService.shared
    private var cancellables = Set<AnyCancellable>()
    
    @Published var searchResults: [ProcessedFoodItem] = []
    @Published var isSearching = false
    @Published var searchError: String?
    
    // Recent and favorite foods for quick access
    @Published var recentFoods: [ProcessedFoodItem] = []
    @Published var favoriteFoods: [ProcessedFoodItem] = []
    @Published var popularFoods: [ProcessedFoodItem] = []
    @Published var frequentFoods: [ProcessedFoodItem] = []  // Most frequently used foods
    
    // Local common foods for instant search
    private var localFoods: [ProcessedFoodItem] = []
    
    private init() {
        print("🎯 [USDA] Initializing USDAFoodService")
        
        // Load local common foods database
        loadLocalFoods()
        
        // Subscribe to cloud service updates
        cloudService.$recentFoods
            .map { foods in
                print("🔄 [USDA] Converting \(foods.count) recent foods")
                return foods.map { $0.toProcessedFoodItem() }
            }
            .assign(to: &$recentFoods)
        
        cloudService.$favoriteFoods
            .map { foods in
                print("🔄 [USDA] Converting \(foods.count) favorite foods")
                return foods.map { $0.toProcessedFoodItem() }
            }
            .assign(to: &$favoriteFoods)
        
        cloudService.$popularFoods
            .map { foods in
                print("🔄 [USDA] Converting \(foods.count) popular foods")
                return foods.map { $0.toProcessedFoodItem() }
            }
            .assign(to: &$popularFoods)
        
        cloudService.$frequentFoods
            .map { foods in
                print("🔄 [USDA] Converting \(foods.count) frequent foods")
                return foods.map { $0.toProcessedFoodItem() }
            }
            .assign(to: &$frequentFoods)
        
        print("✅ [USDA] USDAFoodService initialized with \(localFoods.count) local foods")
    }
    
    // MARK: - Local Foods Database (for instant search)
    
    private func loadLocalFoods() {
        // ~300 common whole foods with approximate nutrition per 100g
        // This provides instant results while cloud data loads
        localFoods = [
            // ===== PROTEINS (60+ items) =====
            // Chicken - with full USDA nutrition data
            makeLocalFood(id: 1, name: "Chicken Breast, raw", category: "Poultry", cal: 120, p: 22.5, c: 0, f: 2.6, satFat: 0.6, fiber: 0, sugar: 0, sodium: 45, chol: 64, calcium: 5, iron: 0.4, vitC: 0),
            makeLocalFood(id: 2, name: "Chicken Breast, cooked", category: "Poultry", cal: 165, p: 31, c: 0, f: 3.6, satFat: 1.0, fiber: 0, sugar: 0, sodium: 74, chol: 85, calcium: 15, iron: 1.0, vitC: 0),
            makeLocalFood(id: 3, name: "Chicken Breast, grilled", category: "Poultry", cal: 165, p: 31, c: 0, f: 3.6, satFat: 1.0, fiber: 0, sugar: 0, sodium: 74, chol: 85, calcium: 15, iron: 1.0, vitC: 0),
            makeLocalFood(id: 4, name: "Chicken Thigh, raw", category: "Poultry", cal: 177, p: 19.7, c: 0, f: 10.9, satFat: 3.0, fiber: 0, sugar: 0, sodium: 84, chol: 115, calcium: 9, iron: 0.9, vitC: 0),
            makeLocalFood(id: 5, name: "Chicken Thigh, cooked", category: "Poultry", cal: 209, p: 26, c: 0, f: 11, satFat: 3.0, fiber: 0, sugar: 0, sodium: 84, chol: 130, calcium: 12, iron: 1.3, vitC: 0),
            makeLocalFood(id: 6, name: "Chicken Drumstick", category: "Poultry", cal: 172, p: 28, c: 0, f: 5.7, satFat: 1.5, fiber: 0, sugar: 0, sodium: 90, chol: 93, calcium: 15, iron: 1.3, vitC: 0),
            makeLocalFood(id: 7, name: "Chicken Wing", category: "Poultry", cal: 203, p: 30, c: 0, f: 8.1, satFat: 2.3, fiber: 0, sugar: 0, sodium: 82, chol: 111, calcium: 18, iron: 1.2, vitC: 0),
            makeLocalFood(id: 8, name: "Chicken, rotisserie", category: "Poultry", cal: 190, p: 27, c: 0, f: 8.5, satFat: 2.4, fiber: 0, sugar: 0, sodium: 300, chol: 90, calcium: 14, iron: 1.2, vitC: 0),
            makeLocalFood(id: 9, name: "Chicken, ground", category: "Poultry", cal: 143, p: 17, c: 0, f: 8, satFat: 2.2, fiber: 0, sugar: 0, sodium: 77, chol: 86, calcium: 10, iron: 0.9, vitC: 0),
            
            // Turkey - with full USDA nutrition data
            makeLocalFood(id: 10, name: "Turkey Breast, raw", category: "Poultry", cal: 104, p: 24, c: 0, f: 0.7, satFat: 0.2, fiber: 0, sugar: 0, sodium: 54, chol: 65, calcium: 10, iron: 0.7, vitC: 0),
            makeLocalFood(id: 11, name: "Turkey Breast, cooked", category: "Poultry", cal: 135, p: 30, c: 0, f: 0.7, satFat: 0.2, fiber: 0, sugar: 0, sodium: 46, chol: 83, calcium: 8, iron: 1.4, vitC: 0),
            makeLocalFood(id: 12, name: "Turkey, ground, 93% lean", category: "Poultry", cal: 150, p: 21, c: 0, f: 7, satFat: 2.0, fiber: 0, sugar: 0, sodium: 88, chol: 80, calcium: 20, iron: 1.5, vitC: 0),
            makeLocalFood(id: 13, name: "Turkey, ground, 85% lean", category: "Poultry", cal: 203, p: 20, c: 0, f: 13, satFat: 3.6, fiber: 0, sugar: 0, sodium: 90, chol: 90, calcium: 22, iron: 1.6, vitC: 0),
            makeLocalFood(id: 14, name: "Turkey Bacon", category: "Poultry", cal: 218, p: 17, c: 1, f: 16, satFat: 4.5, fiber: 0, sugar: 0, sodium: 1050, chol: 80, calcium: 10, iron: 1.2, vitC: 0),
            makeLocalFood(id: 15, name: "Turkey Sausage", category: "Poultry", cal: 196, p: 16, c: 2, f: 14, satFat: 4.0, fiber: 0, sugar: 1, sodium: 665, chol: 70, calcium: 15, iron: 1.5, vitC: 0),
            
            // Beef - with full USDA nutrition data
            makeLocalFood(id: 20, name: "Ground Beef, 90% lean", category: "Beef", cal: 176, p: 20, c: 0, f: 10, satFat: 4.0, fiber: 0, sugar: 0, sodium: 66, chol: 70, calcium: 12, iron: 2.3, vitC: 0),
            makeLocalFood(id: 21, name: "Ground Beef, 85% lean", category: "Beef", cal: 215, p: 19, c: 0, f: 15, satFat: 5.9, fiber: 0, sugar: 0, sodium: 66, chol: 73, calcium: 14, iron: 2.2, vitC: 0),
            makeLocalFood(id: 22, name: "Ground Beef, 80% lean", category: "Beef", cal: 254, p: 17.2, c: 0, f: 20, satFat: 7.8, fiber: 0, sugar: 0, sodium: 72, chol: 77, calcium: 16, iron: 2.1, vitC: 0),
            makeLocalFood(id: 23, name: "Ground Beef, 73% lean", category: "Beef", cal: 295, p: 16, c: 0, f: 25, satFat: 10.0, fiber: 0, sugar: 0, sodium: 75, chol: 80, calcium: 18, iron: 2.0, vitC: 0),
            makeLocalFood(id: 24, name: "Steak, sirloin", category: "Beef", cal: 183, p: 27, c: 0, f: 8, satFat: 3.0, fiber: 0, sugar: 0, sodium: 56, chol: 75, calcium: 18, iron: 2.8, vitC: 0),
            makeLocalFood(id: 25, name: "Steak, ribeye", category: "Beef", cal: 291, p: 24, c: 0, f: 21, satFat: 9.0, fiber: 0, sugar: 0, sodium: 59, chol: 80, calcium: 11, iron: 2.2, vitC: 0),
            makeLocalFood(id: 26, name: "Steak, filet mignon", category: "Beef", cal: 196, p: 28, c: 0, f: 9, satFat: 3.5, fiber: 0, sugar: 0, sodium: 54, chol: 82, calcium: 8, iron: 3.3, vitC: 0),
            makeLocalFood(id: 27, name: "Steak, flank", category: "Beef", cal: 164, p: 27, c: 0, f: 6, satFat: 2.4, fiber: 0, sugar: 0, sodium: 60, chol: 65, calcium: 7, iron: 2.0, vitC: 0),
            makeLocalFood(id: 28, name: "Steak, strip", category: "Beef", cal: 210, p: 26, c: 0, f: 11, satFat: 4.3, fiber: 0, sugar: 0, sodium: 55, chol: 73, calcium: 14, iron: 2.6, vitC: 0),
            makeLocalFood(id: 29, name: "Beef, chuck roast", category: "Beef", cal: 198, p: 26, c: 0, f: 10, satFat: 4.0, fiber: 0, sugar: 0, sodium: 63, chol: 83, calcium: 12, iron: 3.0, vitC: 0),
            makeLocalFood(id: 30, name: "Beef, brisket", category: "Beef", cal: 234, p: 25, c: 0, f: 14, satFat: 5.3, fiber: 0, sugar: 0, sodium: 68, chol: 80, calcium: 8, iron: 2.5, vitC: 0),
            makeLocalFood(id: 31, name: "Beef Jerky", category: "Beef", cal: 410, p: 33, c: 11, f: 26, satFat: 10.8, fiber: 0, sugar: 9, sodium: 2081, chol: 65, calcium: 20, iron: 6.1, vitC: 0),
            
            // Pork - with full USDA nutrition data
            makeLocalFood(id: 35, name: "Pork Tenderloin, raw", category: "Pork", cal: 120, p: 21, c: 0, f: 3.5, satFat: 1.2, fiber: 0, sugar: 0, sodium: 48, chol: 55, calcium: 5, iron: 0.9, vitC: 0),
            makeLocalFood(id: 36, name: "Pork Tenderloin, cooked", category: "Pork", cal: 143, p: 26, c: 0, f: 4, satFat: 1.4, fiber: 0, sugar: 0, sodium: 54, chol: 73, calcium: 6, iron: 1.2, vitC: 0),
            makeLocalFood(id: 37, name: "Pork Chop, bone-in", category: "Pork", cal: 231, p: 26, c: 0, f: 14, satFat: 5.0, fiber: 0, sugar: 0, sodium: 62, chol: 75, calcium: 19, iron: 0.8, vitC: 0),
            makeLocalFood(id: 38, name: "Pork Chop, boneless", category: "Pork", cal: 196, p: 27, c: 0, f: 9, satFat: 3.2, fiber: 0, sugar: 0, sodium: 58, chol: 72, calcium: 8, iron: 0.7, vitC: 0),
            makeLocalFood(id: 39, name: "Bacon", category: "Pork", cal: 541, p: 37, c: 1, f: 42, satFat: 14.0, fiber: 0, sugar: 0, sodium: 1717, chol: 110, calcium: 11, iron: 1.4, vitC: 0),
            makeLocalFood(id: 40, name: "Bacon, center cut", category: "Pork", cal: 360, p: 32, c: 2, f: 25, satFat: 8.5, fiber: 0, sugar: 0, sodium: 1200, chol: 85, calcium: 10, iron: 1.2, vitC: 0),
            makeLocalFood(id: 41, name: "Ham, sliced", category: "Pork", cal: 145, p: 21, c: 2, f: 5, satFat: 1.7, fiber: 0, sugar: 0, sodium: 1203, chol: 53, calcium: 8, iron: 1.0, vitC: 0),
            makeLocalFood(id: 42, name: "Pork Sausage", category: "Pork", cal: 339, p: 19, c: 0, f: 29, satFat: 10.1, fiber: 0, sugar: 0, sodium: 749, chol: 84, calcium: 13, iron: 1.4, vitC: 1),
            makeLocalFood(id: 43, name: "Pork Ribs", category: "Pork", cal: 277, p: 25, c: 0, f: 19, satFat: 6.9, fiber: 0, sugar: 0, sodium: 79, chol: 86, calcium: 26, iron: 1.1, vitC: 0),
            makeLocalFood(id: 44, name: "Pork, ground", category: "Pork", cal: 263, p: 17, c: 0, f: 21, satFat: 7.7, fiber: 0, sugar: 0, sodium: 65, chol: 76, calcium: 14, iron: 1.0, vitC: 0),
            
            // Fish & Seafood - with full USDA nutrition data
            makeLocalFood(id: 50, name: "Salmon, raw", category: "Fish", cal: 208, p: 20, c: 0, f: 13, satFat: 3.1, fiber: 0, sugar: 0, sodium: 59, chol: 55, calcium: 9, iron: 0.3, vitC: 0),
            makeLocalFood(id: 51, name: "Salmon, cooked", category: "Fish", cal: 182, p: 25, c: 0, f: 8, satFat: 1.6, fiber: 0, sugar: 0, sodium: 59, chol: 63, calcium: 12, iron: 0.5, vitC: 0),
            makeLocalFood(id: 52, name: "Salmon, smoked", category: "Fish", cal: 117, p: 18, c: 0, f: 4, satFat: 0.9, fiber: 0, sugar: 0, sodium: 784, chol: 23, calcium: 11, iron: 0.9, vitC: 0),
            makeLocalFood(id: 53, name: "Tuna, canned in water", category: "Fish", cal: 116, p: 26, c: 0, f: 0.8, satFat: 0.2, fiber: 0, sugar: 0, sodium: 338, chol: 42, calcium: 11, iron: 1.0, vitC: 0),
            makeLocalFood(id: 54, name: "Tuna, canned in oil", category: "Fish", cal: 198, p: 29, c: 0, f: 8, satFat: 1.4, fiber: 0, sugar: 0, sodium: 354, chol: 31, calcium: 13, iron: 1.2, vitC: 0),
            makeLocalFood(id: 55, name: "Tuna, fresh, raw", category: "Fish", cal: 144, p: 23, c: 0, f: 5, satFat: 1.3, fiber: 0, sugar: 0, sodium: 39, chol: 38, calcium: 16, iron: 1.0, vitC: 0),
            makeLocalFood(id: 56, name: "Tilapia, raw", category: "Fish", cal: 96, p: 20, c: 0, f: 1.7, satFat: 0.6, fiber: 0, sugar: 0, sodium: 52, chol: 50, calcium: 10, iron: 0.5, vitC: 0),
            makeLocalFood(id: 57, name: "Tilapia, cooked", category: "Fish", cal: 128, p: 26, c: 0, f: 2.7, satFat: 0.9, fiber: 0, sugar: 0, sodium: 56, chol: 57, calcium: 14, iron: 0.7, vitC: 0),
            makeLocalFood(id: 58, name: "Cod, raw", category: "Fish", cal: 82, p: 18, c: 0, f: 0.7, satFat: 0.1, fiber: 0, sugar: 0, sodium: 54, chol: 43, calcium: 16, iron: 0.4, vitC: 1),
            makeLocalFood(id: 59, name: "Cod, cooked", category: "Fish", cal: 105, p: 23, c: 0, f: 0.9, satFat: 0.2, fiber: 0, sugar: 0, sodium: 78, chol: 55, calcium: 14, iron: 0.5, vitC: 1),
            makeLocalFood(id: 60, name: "Shrimp, raw", category: "Seafood", cal: 85, p: 20, c: 0, f: 0.5, satFat: 0.1, fiber: 0, sugar: 0, sodium: 119, chol: 161, calcium: 64, iron: 0.3, vitC: 0),
            makeLocalFood(id: 61, name: "Shrimp, cooked", category: "Seafood", cal: 99, p: 24, c: 0, f: 0.3, satFat: 0.1, fiber: 0, sugar: 0, sodium: 224, chol: 189, calcium: 70, iron: 0.5, vitC: 0),
            makeLocalFood(id: 62, name: "Crab, meat", category: "Seafood", cal: 97, p: 19, c: 0, f: 1.5, satFat: 0.2, fiber: 0, sugar: 0, sodium: 395, chol: 78, calcium: 91, iron: 0.7, vitC: 3),
            makeLocalFood(id: 63, name: "Lobster", category: "Seafood", cal: 89, p: 19, c: 0, f: 0.9, satFat: 0.2, fiber: 0, sugar: 0, sodium: 486, chol: 72, calcium: 96, iron: 0.4, vitC: 0),
            makeLocalFood(id: 64, name: "Scallops", category: "Seafood", cal: 88, p: 17, c: 3, f: 0.8, satFat: 0.1, fiber: 0, sugar: 0, sodium: 392, chol: 33, calcium: 24, iron: 0.5, vitC: 0),
            makeLocalFood(id: 65, name: "Mahi Mahi", category: "Fish", cal: 85, p: 19, c: 0, f: 0.7, satFat: 0.2, fiber: 0, sugar: 0, sodium: 88, chol: 73, calcium: 16, iron: 1.1, vitC: 0),
            makeLocalFood(id: 66, name: "Halibut", category: "Fish", cal: 111, p: 23, c: 0, f: 2.3, satFat: 0.3, fiber: 0, sugar: 0, sodium: 68, chol: 41, calcium: 7, iron: 0.2, vitC: 0),
            makeLocalFood(id: 67, name: "Sardines, canned", category: "Fish", cal: 208, p: 25, c: 0, f: 11, satFat: 1.5, fiber: 0, sugar: 0, sodium: 505, chol: 142, calcium: 382, iron: 2.9, vitC: 0),
            makeLocalFood(id: 68, name: "Trout", category: "Fish", cal: 148, p: 21, c: 0, f: 6.6, satFat: 1.2, fiber: 0, sugar: 0, sodium: 52, chol: 58, calcium: 43, iron: 0.3, vitC: 1),
            
            // Eggs - with full USDA nutrition data
            makeLocalFood(id: 70, name: "Eggs, whole, raw", category: "Eggs", cal: 143, p: 13, c: 0.7, f: 9.5, satFat: 3.1, fiber: 0, sugar: 0.4, sodium: 142, chol: 372, calcium: 56, iron: 1.8, vitC: 0),
            makeLocalFood(id: 71, name: "Eggs, whole, cooked", category: "Eggs", cal: 155, p: 13, c: 1.1, f: 11, satFat: 3.3, fiber: 0, sugar: 1.1, sodium: 124, chol: 373, calcium: 50, iron: 1.2, vitC: 0),
            makeLocalFood(id: 72, name: "Eggs, scrambled", category: "Eggs", cal: 149, p: 10, c: 2, f: 11, satFat: 3.5, fiber: 0, sugar: 1.4, sodium: 227, chol: 286, calcium: 66, iron: 1.2, vitC: 0),
            makeLocalFood(id: 73, name: "Eggs, hard boiled", category: "Eggs", cal: 155, p: 13, c: 1.1, f: 11, satFat: 3.3, fiber: 0, sugar: 1.1, sodium: 124, chol: 373, calcium: 50, iron: 1.2, vitC: 0),
            makeLocalFood(id: 74, name: "Eggs, fried", category: "Eggs", cal: 196, p: 14, c: 1, f: 15, satFat: 4.0, fiber: 0, sugar: 0.4, sodium: 207, chol: 401, calcium: 62, iron: 1.9, vitC: 0),
            makeLocalFood(id: 75, name: "Egg Whites", category: "Eggs", cal: 52, p: 11, c: 0.7, f: 0.2, satFat: 0, fiber: 0, sugar: 0.7, sodium: 166, chol: 0, calcium: 7, iron: 0.1, vitC: 0),
            makeLocalFood(id: 76, name: "Egg Yolk", category: "Eggs", cal: 322, p: 16, c: 3.6, f: 27, satFat: 9.6, fiber: 0, sugar: 0.6, sodium: 48, chol: 1085, calcium: 129, iron: 2.7, vitC: 0),
            
            // ===== DAIRY (35+ items) ===== with full USDA nutrition data
            // Yogurt
            makeLocalFood(id: 80, name: "Greek Yogurt, plain, nonfat", category: "Dairy", cal: 59, p: 10, c: 3.6, f: 0.7, satFat: 0.1, fiber: 0, sugar: 3.2, sodium: 36, chol: 5, calcium: 110, iron: 0.1, vitC: 0),
            makeLocalFood(id: 81, name: "Greek Yogurt, plain, 2%", category: "Dairy", cal: 73, p: 10, c: 4, f: 2, satFat: 1.0, fiber: 0, sugar: 4, sodium: 47, chol: 8, calcium: 115, iron: 0.1, vitC: 0),
            makeLocalFood(id: 82, name: "Greek Yogurt, plain, whole milk", category: "Dairy", cal: 97, p: 9, c: 4, f: 5, satFat: 3.3, fiber: 0, sugar: 4, sodium: 47, chol: 13, calcium: 100, iron: 0, vitC: 0),
            makeLocalFood(id: 83, name: "Greek Yogurt, vanilla", category: "Dairy", cal: 100, p: 9, c: 12, f: 2, satFat: 1.0, fiber: 0, sugar: 11, sodium: 50, chol: 8, calcium: 110, iron: 0.1, vitC: 0),
            makeLocalFood(id: 84, name: "Yogurt, regular, plain", category: "Dairy", cal: 63, p: 5, c: 7, f: 1.6, satFat: 1.0, fiber: 0, sugar: 7, sodium: 70, chol: 6, calcium: 183, iron: 0.1, vitC: 1),
            makeLocalFood(id: 85, name: "Yogurt, regular, flavored", category: "Dairy", cal: 99, p: 5, c: 19, f: 1, satFat: 0.6, fiber: 0, sugar: 15, sodium: 58, chol: 5, calcium: 152, iron: 0.1, vitC: 1),
            makeLocalFood(id: 86, name: "Skyr, plain", category: "Dairy", cal: 63, p: 11, c: 4, f: 0.3, satFat: 0.1, fiber: 0, sugar: 3, sodium: 55, chol: 5, calcium: 150, iron: 0.1, vitC: 0),
            
            // Cheese - with full USDA nutrition data
            makeLocalFood(id: 90, name: "Cottage Cheese, 2% milkfat", category: "Dairy", cal: 84, p: 11, c: 4.3, f: 2.3, satFat: 1.5, fiber: 0, sugar: 4, sodium: 321, chol: 12, calcium: 91, iron: 0.1, vitC: 0),
            makeLocalFood(id: 91, name: "Cottage Cheese, 4% milkfat", category: "Dairy", cal: 98, p: 11, c: 3.4, f: 4.3, satFat: 1.9, fiber: 0, sugar: 2.7, sodium: 364, chol: 17, calcium: 83, iron: 0.1, vitC: 0),
            makeLocalFood(id: 92, name: "Cottage Cheese, nonfat", category: "Dairy", cal: 72, p: 12, c: 4, f: 0.4, satFat: 0.2, fiber: 0, sugar: 4, sodium: 330, chol: 7, calcium: 86, iron: 0.3, vitC: 0),
            makeLocalFood(id: 93, name: "Cheddar Cheese", category: "Dairy", cal: 403, p: 25, c: 1.3, f: 33, satFat: 21.0, fiber: 0, sugar: 0.5, sodium: 621, chol: 105, calcium: 721, iron: 0.7, vitC: 0),
            makeLocalFood(id: 94, name: "Mozzarella Cheese", category: "Dairy", cal: 280, p: 28, c: 2.2, f: 17, satFat: 10.9, fiber: 0, sugar: 1.0, sodium: 627, chol: 54, calcium: 505, iron: 0.4, vitC: 0),
            makeLocalFood(id: 95, name: "Mozzarella, part-skim", category: "Dairy", cal: 254, p: 25, c: 3, f: 16, satFat: 9.7, fiber: 0, sugar: 1.1, sodium: 619, chol: 64, calcium: 731, iron: 0.3, vitC: 0),
            makeLocalFood(id: 96, name: "Parmesan Cheese", category: "Dairy", cal: 431, p: 38, c: 4.1, f: 29, satFat: 17.3, fiber: 0, sugar: 0.9, sodium: 1529, chol: 88, calcium: 1184, iron: 0.8, vitC: 0),
            makeLocalFood(id: 97, name: "Swiss Cheese", category: "Dairy", cal: 380, p: 27, c: 5, f: 28, satFat: 17.8, fiber: 0, sugar: 1.7, sodium: 192, chol: 92, calcium: 791, iron: 0.2, vitC: 0),
            makeLocalFood(id: 98, name: "Feta Cheese", category: "Dairy", cal: 264, p: 14, c: 4, f: 21, satFat: 14.9, fiber: 0, sugar: 4.1, sodium: 917, chol: 89, calcium: 493, iron: 0.6, vitC: 0),
            makeLocalFood(id: 99, name: "Cream Cheese", category: "Dairy", cal: 342, p: 6, c: 4, f: 34, satFat: 19.3, fiber: 0, sugar: 3.8, sodium: 321, chol: 110, calcium: 97, iron: 1.2, vitC: 0),
            makeLocalFood(id: 100, name: "Cream Cheese, light", category: "Dairy", cal: 201, p: 7, c: 6, f: 17, satFat: 10.0, fiber: 0, sugar: 5, sodium: 350, chol: 54, calcium: 89, iron: 0.9, vitC: 0),
            makeLocalFood(id: 101, name: "Ricotta Cheese", category: "Dairy", cal: 174, p: 11, c: 3, f: 13, satFat: 8.3, fiber: 0, sugar: 0.3, sodium: 84, chol: 51, calcium: 207, iron: 0.4, vitC: 0),
            makeLocalFood(id: 102, name: "Goat Cheese", category: "Dairy", cal: 364, p: 22, c: 0, f: 30, satFat: 20.6, fiber: 0, sugar: 0, sodium: 515, chol: 79, calcium: 298, iron: 1.9, vitC: 0),
            makeLocalFood(id: 103, name: "Blue Cheese", category: "Dairy", cal: 353, p: 21, c: 2, f: 29, satFat: 18.7, fiber: 0, sugar: 0.5, sodium: 1395, chol: 75, calcium: 528, iron: 0.3, vitC: 0),
            makeLocalFood(id: 104, name: "American Cheese", category: "Dairy", cal: 307, p: 18, c: 2, f: 25, satFat: 14.1, fiber: 0, sugar: 2, sodium: 1433, chol: 73, calcium: 552, iron: 0.4, vitC: 0),
            makeLocalFood(id: 105, name: "String Cheese", category: "Dairy", cal: 280, p: 28, c: 2, f: 17, satFat: 10.9, fiber: 0, sugar: 1, sodium: 620, chol: 54, calcium: 500, iron: 0.4, vitC: 0),
            
            // Milk - with full USDA nutrition data
            makeLocalFood(id: 110, name: "Milk, whole", category: "Dairy", cal: 61, p: 3.2, c: 4.8, f: 3.3, satFat: 1.9, fiber: 0, sugar: 5.1, sodium: 43, chol: 10, calcium: 113, iron: 0, vitC: 0),
            makeLocalFood(id: 111, name: "Milk, 2%", category: "Dairy", cal: 50, p: 3.3, c: 4.8, f: 2, satFat: 1.3, fiber: 0, sugar: 5.1, sodium: 41, chol: 8, calcium: 117, iron: 0, vitC: 0),
            makeLocalFood(id: 112, name: "Milk, 1%", category: "Dairy", cal: 42, p: 3.4, c: 5, f: 1, satFat: 0.6, fiber: 0, sugar: 5.2, sodium: 44, chol: 5, calcium: 119, iron: 0, vitC: 0),
            makeLocalFood(id: 113, name: "Milk, skim", category: "Dairy", cal: 34, p: 3.4, c: 5, f: 0.1, satFat: 0.1, fiber: 0, sugar: 5.1, sodium: 42, chol: 2, calcium: 122, iron: 0, vitC: 0),
            makeLocalFood(id: 114, name: "Chocolate Milk", category: "Dairy", cal: 83, p: 3.4, c: 12, f: 2.1, satFat: 1.3, fiber: 0.5, sugar: 11, sodium: 60, chol: 8, calcium: 112, iron: 0.2, vitC: 1),
            makeLocalFood(id: 115, name: "Almond Milk, unsweetened", category: "Dairy Alternatives", cal: 17, p: 0.6, c: 0.6, f: 1.4, satFat: 0.1, fiber: 0, sugar: 0, sodium: 173, chol: 0, calcium: 516, iron: 0.4, vitC: 0),
            makeLocalFood(id: 116, name: "Oat Milk", category: "Dairy Alternatives", cal: 47, p: 1, c: 7, f: 1.5, satFat: 0.2, fiber: 0.8, sugar: 4, sodium: 101, chol: 0, calcium: 350, iron: 0.3, vitC: 0),
            makeLocalFood(id: 117, name: "Soy Milk", category: "Dairy Alternatives", cal: 54, p: 3.3, c: 6, f: 1.8, satFat: 0.2, fiber: 0.5, sugar: 5, sodium: 51, chol: 0, calcium: 301, iron: 0.6, vitC: 0),
            makeLocalFood(id: 118, name: "Half and Half", category: "Dairy", cal: 130, p: 3, c: 4, f: 12, satFat: 7.0, fiber: 0, sugar: 4.3, sodium: 41, chol: 37, calcium: 105, iron: 0.1, vitC: 1),
            makeLocalFood(id: 119, name: "Heavy Cream", category: "Dairy", cal: 340, p: 2, c: 3, f: 36, satFat: 23.0, fiber: 0, sugar: 3, sodium: 38, chol: 137, calcium: 65, iron: 0, vitC: 1),
            makeLocalFood(id: 120, name: "Sour Cream", category: "Dairy", cal: 193, p: 2.4, c: 4.6, f: 19, satFat: 11.5, fiber: 0, sugar: 3.5, sodium: 80, chol: 52, calcium: 116, iron: 0.1, vitC: 1),
            makeLocalFood(id: 121, name: "Butter", category: "Dairy", cal: 717, p: 0.9, c: 0.1, f: 81, satFat: 51.4, fiber: 0, sugar: 0.1, sodium: 643, chol: 215, calcium: 24, iron: 0, vitC: 0),
            
            // ===== GRAINS & CARBS (40+ items) ===== with full USDA nutrition data
            // Rice
            makeLocalFood(id: 130, name: "White Rice, cooked", category: "Grains", cal: 130, p: 2.7, c: 28, f: 0.3, satFat: 0.1, fiber: 0.4, sugar: 0, sodium: 1, chol: 0, calcium: 10, iron: 1.2, vitC: 0),
            makeLocalFood(id: 131, name: "White Rice, dry", category: "Grains", cal: 365, p: 7, c: 80, f: 0.6, satFat: 0.2, fiber: 1.3, sugar: 0, sodium: 5, chol: 0, calcium: 28, iron: 0.8, vitC: 0),
            makeLocalFood(id: 132, name: "Brown Rice, cooked", category: "Grains", cal: 111, p: 2.6, c: 23, f: 0.9, satFat: 0.2, fiber: 1.8, sugar: 0.4, sodium: 5, chol: 0, calcium: 10, iron: 0.4, vitC: 0),
            makeLocalFood(id: 133, name: "Brown Rice, dry", category: "Grains", cal: 370, p: 8, c: 77, f: 2.7, satFat: 0.5, fiber: 3.5, sugar: 0.9, sodium: 7, chol: 0, calcium: 23, iron: 1.5, vitC: 0),
            makeLocalFood(id: 134, name: "Jasmine Rice, cooked", category: "Grains", cal: 130, p: 2.7, c: 28, f: 0.3, satFat: 0.1, fiber: 0.4, sugar: 0, sodium: 1, chol: 0, calcium: 10, iron: 1.2, vitC: 0),
            makeLocalFood(id: 135, name: "Basmati Rice, cooked", category: "Grains", cal: 121, p: 3, c: 25, f: 0.4, satFat: 0.1, fiber: 0.4, sugar: 0, sodium: 1, chol: 0, calcium: 13, iron: 1.0, vitC: 0),
            makeLocalFood(id: 136, name: "Wild Rice, cooked", category: "Grains", cal: 101, p: 4, c: 21, f: 0.3, satFat: 0.1, fiber: 1.8, sugar: 0.7, sodium: 3, chol: 0, calcium: 3, iron: 0.6, vitC: 0),
            
            // Oats - with full USDA nutrition data
            makeLocalFood(id: 140, name: "Oatmeal, cooked", category: "Grains", cal: 71, p: 2.5, c: 12, f: 1.5, satFat: 0.3, fiber: 1.7, sugar: 0.5, sodium: 4, chol: 0, calcium: 9, iron: 1.4, vitC: 0),
            makeLocalFood(id: 141, name: "Oats, dry", category: "Grains", cal: 389, p: 17, c: 66, f: 7, satFat: 1.2, fiber: 10.6, sugar: 1, sodium: 2, chol: 0, calcium: 54, iron: 4.7, vitC: 0),
            makeLocalFood(id: 142, name: "Oats, instant, plain", category: "Grains", cal: 375, p: 12, c: 67, f: 6.5, satFat: 1.1, fiber: 9.4, sugar: 1, sodium: 8, chol: 0, calcium: 52, iron: 3.4, vitC: 0),
            makeLocalFood(id: 143, name: "Overnight Oats", category: "Grains", cal: 150, p: 6, c: 25, f: 3, satFat: 0.6, fiber: 4, sugar: 4, sodium: 70, chol: 3, calcium: 100, iron: 2, vitC: 0),
            
            // Other grains - with full USDA nutrition data
            makeLocalFood(id: 145, name: "Quinoa, cooked", category: "Grains", cal: 120, p: 4.4, c: 21, f: 1.9, satFat: 0.2, fiber: 2.8, sugar: 0.9, sodium: 7, chol: 0, calcium: 17, iron: 1.5, vitC: 0),
            makeLocalFood(id: 146, name: "Quinoa, dry", category: "Grains", cal: 368, p: 14, c: 64, f: 6, satFat: 0.7, fiber: 7, sugar: 0, sodium: 5, chol: 0, calcium: 47, iron: 4.6, vitC: 0),
            makeLocalFood(id: 147, name: "Couscous, cooked", category: "Grains", cal: 112, p: 3.8, c: 23, f: 0.2, satFat: 0, fiber: 1.4, sugar: 0.1, sodium: 5, chol: 0, calcium: 8, iron: 0.4, vitC: 0),
            makeLocalFood(id: 148, name: "Bulgur, cooked", category: "Grains", cal: 83, p: 3, c: 19, f: 0.2, satFat: 0, fiber: 4.5, sugar: 0.1, sodium: 5, chol: 0, calcium: 10, iron: 1.0, vitC: 0),
            makeLocalFood(id: 149, name: "Farro, cooked", category: "Grains", cal: 110, p: 4, c: 22, f: 0.8, satFat: 0.1, fiber: 3.5, sugar: 0, sodium: 3, chol: 0, calcium: 8, iron: 1.2, vitC: 0),
            makeLocalFood(id: 150, name: "Barley, cooked", category: "Grains", cal: 123, p: 2.3, c: 28, f: 0.4, satFat: 0.1, fiber: 3.8, sugar: 0.3, sodium: 3, chol: 0, calcium: 11, iron: 1.3, vitC: 0),
            
            // Bread - with full USDA nutrition data
            makeLocalFood(id: 155, name: "Bread, whole wheat", category: "Grains", cal: 247, p: 13, c: 41, f: 3.4, satFat: 0.6, fiber: 6, sugar: 5, sodium: 400, chol: 0, calcium: 161, iron: 2.4, vitC: 0),
            makeLocalFood(id: 156, name: "Bread, white", category: "Grains", cal: 265, p: 9, c: 49, f: 3.2, satFat: 0.7, fiber: 2.7, sugar: 5, sodium: 491, chol: 0, calcium: 144, iron: 3.6, vitC: 0),
            makeLocalFood(id: 157, name: "Bread, sourdough", category: "Grains", cal: 289, p: 12, c: 55, f: 3, satFat: 0.6, fiber: 2, sugar: 3, sodium: 602, chol: 0, calcium: 63, iron: 3.8, vitC: 0),
            makeLocalFood(id: 158, name: "Bread, rye", category: "Grains", cal: 259, p: 9, c: 48, f: 3.3, satFat: 0.6, fiber: 5.8, sugar: 3, sodium: 603, chol: 0, calcium: 73, iron: 2.8, vitC: 0),
            makeLocalFood(id: 159, name: "Bagel, plain", category: "Grains", cal: 275, p: 11, c: 53, f: 1.5, satFat: 0.2, fiber: 2.3, sugar: 5, sodium: 430, chol: 0, calcium: 19, iron: 4.5, vitC: 0),
            makeLocalFood(id: 160, name: "English Muffin", category: "Grains", cal: 227, p: 9, c: 44, f: 2, satFat: 0.3, fiber: 2.6, sugar: 2, sodium: 393, chol: 0, calcium: 99, iron: 2.5, vitC: 0),
            makeLocalFood(id: 161, name: "Tortilla, flour", category: "Grains", cal: 310, p: 8, c: 50, f: 8, satFat: 3.0, fiber: 2, sugar: 3, sodium: 520, chol: 0, calcium: 128, iron: 3.0, vitC: 0),
            makeLocalFood(id: 162, name: "Tortilla, corn", category: "Grains", cal: 218, p: 6, c: 44, f: 3, satFat: 0.4, fiber: 6.3, sugar: 1, sodium: 46, chol: 0, calcium: 80, iron: 1.5, vitC: 0),
            makeLocalFood(id: 163, name: "Pita Bread", category: "Grains", cal: 275, p: 9, c: 55, f: 1.2, satFat: 0.2, fiber: 2.2, sugar: 1, sodium: 322, chol: 0, calcium: 52, iron: 2.6, vitC: 0),
            makeLocalFood(id: 164, name: "Naan Bread", category: "Grains", cal: 310, p: 10, c: 54, f: 6, satFat: 1.5, fiber: 2, sugar: 3, sodium: 418, chol: 5, calcium: 92, iron: 3.0, vitC: 0),
            makeLocalFood(id: 165, name: "Croissant", category: "Grains", cal: 406, p: 8, c: 45, f: 21, satFat: 12.0, fiber: 2, sugar: 7, sodium: 424, chol: 67, calcium: 37, iron: 2.2, vitC: 0),
            
            // Pasta - with full USDA nutrition data
            makeLocalFood(id: 170, name: "Pasta, cooked", category: "Grains", cal: 131, p: 5, c: 25, f: 1.1, satFat: 0.2, fiber: 1.8, sugar: 0.6, sodium: 1, chol: 0, calcium: 7, iron: 1.3, vitC: 0),
            makeLocalFood(id: 171, name: "Pasta, whole wheat, cooked", category: "Grains", cal: 124, p: 5.3, c: 25, f: 0.5, satFat: 0.1, fiber: 4.5, sugar: 0.8, sodium: 3, chol: 0, calcium: 15, iron: 1.5, vitC: 0),
            makeLocalFood(id: 172, name: "Pasta, dry", category: "Grains", cal: 371, p: 13, c: 74, f: 1.5, satFat: 0.3, fiber: 3.2, sugar: 2.7, sodium: 6, chol: 0, calcium: 21, iron: 1.3, vitC: 0),
            makeLocalFood(id: 173, name: "Spaghetti, cooked", category: "Grains", cal: 131, p: 5, c: 25, f: 1.1, satFat: 0.2, fiber: 1.8, sugar: 0.6, sodium: 1, chol: 0, calcium: 7, iron: 1.3, vitC: 0),
            makeLocalFood(id: 174, name: "Penne, cooked", category: "Grains", cal: 131, p: 5, c: 25, f: 1.1, satFat: 0.2, fiber: 1.8, sugar: 0.6, sodium: 1, chol: 0, calcium: 7, iron: 1.3, vitC: 0),
            makeLocalFood(id: 175, name: "Rice Noodles, cooked", category: "Grains", cal: 109, p: 0.9, c: 24, f: 0.2, satFat: 0, fiber: 0.9, sugar: 0, sodium: 33, chol: 0, calcium: 4, iron: 0.1, vitC: 0),
            
            // Potatoes - with full USDA nutrition data
            makeLocalFood(id: 180, name: "Potato, white, raw", category: "Vegetables", cal: 77, p: 2, c: 17, f: 0.1, satFat: 0, fiber: 2.2, sugar: 0.8, sodium: 6, chol: 0, calcium: 12, iron: 0.8, vitC: 19.7),
            makeLocalFood(id: 181, name: "Potato, baked", category: "Vegetables", cal: 93, p: 2.5, c: 21, f: 0.1, satFat: 0, fiber: 2.2, sugar: 1.2, sodium: 10, chol: 0, calcium: 15, iron: 1.1, vitC: 9.6),
            makeLocalFood(id: 182, name: "Potato, mashed", category: "Vegetables", cal: 83, p: 2, c: 17, f: 0.6, satFat: 0.2, fiber: 1.5, sugar: 1.5, sodium: 318, chol: 1, calcium: 23, iron: 0.3, vitC: 6),
            makeLocalFood(id: 183, name: "Sweet Potato, raw", category: "Vegetables", cal: 86, p: 1.6, c: 20, f: 0.1, satFat: 0, fiber: 3, sugar: 4.2, sodium: 55, chol: 0, calcium: 30, iron: 0.6, vitC: 2.4),
            makeLocalFood(id: 184, name: "Sweet Potato, baked", category: "Vegetables", cal: 90, p: 2, c: 21, f: 0.1, satFat: 0, fiber: 3.3, sugar: 6.5, sodium: 36, chol: 0, calcium: 38, iron: 0.7, vitC: 19.6),
            makeLocalFood(id: 185, name: "French Fries", category: "Vegetables", cal: 312, p: 3.4, c: 41, f: 15, satFat: 2.3, fiber: 3.8, sugar: 0.3, sodium: 282, chol: 0, calcium: 18, iron: 1.0, vitC: 5.6),
            makeLocalFood(id: 186, name: "Hash Browns", category: "Vegetables", cal: 250, p: 3, c: 30, f: 13, satFat: 2.0, fiber: 2.5, sugar: 0.5, sodium: 400, chol: 0, calcium: 15, iron: 0.8, vitC: 4),
            
            // ===== FRUITS (45+ items) ===== with full USDA nutrition data
            makeLocalFood(id: 190, name: "Banana", category: "Fruits", cal: 89, p: 1.1, c: 23, f: 0.3, satFat: 0.1, fiber: 2.6, sugar: 12.2, sodium: 1, chol: 0, calcium: 5, iron: 0.3, vitC: 8.7),
            makeLocalFood(id: 191, name: "Apple", category: "Fruits", cal: 52, p: 0.3, c: 14, f: 0.2, satFat: 0, fiber: 2.4, sugar: 10.4, sodium: 1, chol: 0, calcium: 6, iron: 0.1, vitC: 4.6),
            makeLocalFood(id: 192, name: "Apple, with skin", category: "Fruits", cal: 52, p: 0.3, c: 14, f: 0.2, satFat: 0, fiber: 2.4, sugar: 10.4, sodium: 1, chol: 0, calcium: 6, iron: 0.1, vitC: 4.6),
            makeLocalFood(id: 193, name: "Orange", category: "Fruits", cal: 47, p: 0.9, c: 12, f: 0.1, satFat: 0, fiber: 2.4, sugar: 9.4, sodium: 0, chol: 0, calcium: 40, iron: 0.1, vitC: 53.2),
            makeLocalFood(id: 194, name: "Strawberries", category: "Fruits", cal: 32, p: 0.7, c: 7.7, f: 0.3, satFat: 0, fiber: 2.0, sugar: 4.9, sodium: 1, chol: 0, calcium: 16, iron: 0.4, vitC: 58.8),
            makeLocalFood(id: 195, name: "Blueberries", category: "Fruits", cal: 57, p: 0.7, c: 14, f: 0.3, satFat: 0, fiber: 2.4, sugar: 10, sodium: 1, chol: 0, calcium: 6, iron: 0.3, vitC: 9.7),
            makeLocalFood(id: 196, name: "Raspberries", category: "Fruits", cal: 52, p: 1.2, c: 12, f: 0.7, satFat: 0, fiber: 6.5, sugar: 4.4, sodium: 1, chol: 0, calcium: 25, iron: 0.7, vitC: 26.2),
            makeLocalFood(id: 197, name: "Blackberries", category: "Fruits", cal: 43, p: 1.4, c: 10, f: 0.5, satFat: 0, fiber: 5.3, sugar: 4.9, sodium: 1, chol: 0, calcium: 29, iron: 0.6, vitC: 21),
            makeLocalFood(id: 198, name: "Grapes, red", category: "Fruits", cal: 69, p: 0.7, c: 18, f: 0.2, satFat: 0.1, fiber: 0.9, sugar: 15.5, sodium: 2, chol: 0, calcium: 10, iron: 0.4, vitC: 3.2),
            makeLocalFood(id: 199, name: "Grapes, green", category: "Fruits", cal: 69, p: 0.7, c: 18, f: 0.2, satFat: 0.1, fiber: 0.9, sugar: 15.5, sodium: 2, chol: 0, calcium: 10, iron: 0.4, vitC: 3.2),
            makeLocalFood(id: 200, name: "Watermelon", category: "Fruits", cal: 30, p: 0.6, c: 7.6, f: 0.2, satFat: 0, fiber: 0.4, sugar: 6.2, sodium: 1, chol: 0, calcium: 7, iron: 0.2, vitC: 8.1),
            makeLocalFood(id: 201, name: "Cantaloupe", category: "Fruits", cal: 34, p: 0.8, c: 8, f: 0.2, satFat: 0, fiber: 0.9, sugar: 7.9, sodium: 16, chol: 0, calcium: 9, iron: 0.2, vitC: 36.7),
            makeLocalFood(id: 202, name: "Honeydew", category: "Fruits", cal: 36, p: 0.5, c: 9, f: 0.1, satFat: 0, fiber: 0.8, sugar: 8.1, sodium: 18, chol: 0, calcium: 6, iron: 0.2, vitC: 18),
            makeLocalFood(id: 203, name: "Mango", category: "Fruits", cal: 60, p: 0.8, c: 15, f: 0.4, satFat: 0.1, fiber: 1.6, sugar: 13.7, sodium: 1, chol: 0, calcium: 11, iron: 0.2, vitC: 36.4),
            makeLocalFood(id: 204, name: "Pineapple", category: "Fruits", cal: 50, p: 0.5, c: 13, f: 0.1, satFat: 0, fiber: 1.4, sugar: 9.9, sodium: 1, chol: 0, calcium: 13, iron: 0.3, vitC: 47.8),
            makeLocalFood(id: 205, name: "Avocado", category: "Fruits", cal: 160, p: 2, c: 8.5, f: 15, satFat: 2.1, fiber: 6.7, sugar: 0.7, sodium: 7, chol: 0, calcium: 12, iron: 0.6, vitC: 10),
            makeLocalFood(id: 206, name: "Peach", category: "Fruits", cal: 39, p: 0.9, c: 10, f: 0.3, satFat: 0, fiber: 1.5, sugar: 8.4, sodium: 0, chol: 0, calcium: 6, iron: 0.3, vitC: 6.6),
            makeLocalFood(id: 207, name: "Nectarine", category: "Fruits", cal: 44, p: 1.1, c: 11, f: 0.3, satFat: 0, fiber: 1.7, sugar: 7.9, sodium: 0, chol: 0, calcium: 6, iron: 0.3, vitC: 5.4),
            makeLocalFood(id: 208, name: "Plum", category: "Fruits", cal: 46, p: 0.7, c: 11, f: 0.3, satFat: 0, fiber: 1.4, sugar: 9.9, sodium: 0, chol: 0, calcium: 6, iron: 0.2, vitC: 9.5),
            makeLocalFood(id: 209, name: "Cherries", category: "Fruits", cal: 63, p: 1.1, c: 16, f: 0.2, satFat: 0, fiber: 2.1, sugar: 12.8, sodium: 0, chol: 0, calcium: 13, iron: 0.4, vitC: 7),
            makeLocalFood(id: 210, name: "Pear", category: "Fruits", cal: 57, p: 0.4, c: 15, f: 0.1, satFat: 0, fiber: 3.1, sugar: 9.8, sodium: 1, chol: 0, calcium: 9, iron: 0.2, vitC: 4.3),
            makeLocalFood(id: 211, name: "Kiwi", category: "Fruits", cal: 61, p: 1.1, c: 15, f: 0.5, satFat: 0, fiber: 3, sugar: 9, sodium: 3, chol: 0, calcium: 34, iron: 0.3, vitC: 92.7),
            makeLocalFood(id: 212, name: "Grapefruit", category: "Fruits", cal: 42, p: 0.8, c: 11, f: 0.1, satFat: 0, fiber: 1.6, sugar: 7, sodium: 0, chol: 0, calcium: 22, iron: 0.1, vitC: 31.2),
            makeLocalFood(id: 213, name: "Lemon", category: "Fruits", cal: 29, p: 1.1, c: 9, f: 0.3, satFat: 0, fiber: 2.8, sugar: 2.5, sodium: 2, chol: 0, calcium: 26, iron: 0.6, vitC: 53),
            makeLocalFood(id: 214, name: "Lime", category: "Fruits", cal: 30, p: 0.7, c: 11, f: 0.2, satFat: 0, fiber: 2.8, sugar: 1.7, sodium: 2, chol: 0, calcium: 33, iron: 0.6, vitC: 29.1),
            makeLocalFood(id: 215, name: "Papaya", category: "Fruits", cal: 43, p: 0.5, c: 11, f: 0.3, satFat: 0.1, fiber: 1.7, sugar: 7.8, sodium: 8, chol: 0, calcium: 20, iron: 0.3, vitC: 60.9),
            makeLocalFood(id: 216, name: "Pomegranate Seeds", category: "Fruits", cal: 83, p: 1.7, c: 19, f: 1.2, satFat: 0.1, fiber: 4, sugar: 13.7, sodium: 3, chol: 0, calcium: 10, iron: 0.3, vitC: 10.2),
            makeLocalFood(id: 217, name: "Coconut, raw", category: "Fruits", cal: 354, p: 3.3, c: 15, f: 33, satFat: 29.7, fiber: 9, sugar: 6.2, sodium: 20, chol: 0, calcium: 14, iron: 2.4, vitC: 3.3),
            makeLocalFood(id: 218, name: "Coconut, shredded", category: "Fruits", cal: 456, p: 5, c: 16, f: 43, satFat: 38, fiber: 11.6, sugar: 4.3, sodium: 28, chol: 0, calcium: 14, iron: 1.8, vitC: 1.5),
            makeLocalFood(id: 219, name: "Dates, medjool", category: "Fruits", cal: 277, p: 1.8, c: 75, f: 0.2, satFat: 0, fiber: 6.7, sugar: 66.5, sodium: 1, chol: 0, calcium: 64, iron: 0.9, vitC: 0),
            makeLocalFood(id: 220, name: "Raisins", category: "Fruits", cal: 299, p: 3.1, c: 79, f: 0.5, satFat: 0.1, fiber: 3.7, sugar: 59, sodium: 11, chol: 0, calcium: 50, iron: 1.9, vitC: 2.3),
            makeLocalFood(id: 221, name: "Dried Cranberries", category: "Fruits", cal: 308, p: 0.1, c: 82, f: 1.4, satFat: 0.1, fiber: 5.7, sugar: 65, sodium: 3, chol: 0, calcium: 9, iron: 0.4, vitC: 0.2),
            makeLocalFood(id: 222, name: "Dried Apricots", category: "Fruits", cal: 241, p: 3.4, c: 63, f: 0.5, satFat: 0, fiber: 7.3, sugar: 53, sodium: 10, chol: 0, calcium: 55, iron: 2.7, vitC: 1),
            makeLocalFood(id: 223, name: "Applesauce, unsweetened", category: "Fruits", cal: 42, p: 0.2, c: 11, f: 0.1, satFat: 0, fiber: 1.1, sugar: 9, sodium: 2, chol: 0, calcium: 4, iron: 0.1, vitC: 1.2),
            makeLocalFood(id: 224, name: "Frozen Berries, mixed", category: "Fruits", cal: 48, p: 0.7, c: 12, f: 0.3, satFat: 0, fiber: 3.5, sugar: 6, sodium: 1, chol: 0, calcium: 18, iron: 0.5, vitC: 25),
            
            // ===== VEGETABLES (50+ items) ===== with full USDA nutrition data
            makeLocalFood(id: 230, name: "Broccoli, raw", category: "Vegetables", cal: 34, p: 2.8, c: 7, f: 0.4, satFat: 0, fiber: 2.6, sugar: 1.7, sodium: 33, chol: 0, calcium: 47, iron: 0.7, vitC: 89.2),
            makeLocalFood(id: 231, name: "Broccoli, cooked", category: "Vegetables", cal: 35, p: 2.4, c: 7, f: 0.4, satFat: 0.1, fiber: 3.3, sugar: 1.4, sodium: 41, chol: 0, calcium: 40, iron: 0.7, vitC: 64.9),
            makeLocalFood(id: 232, name: "Spinach, raw", category: "Vegetables", cal: 23, p: 2.9, c: 3.6, f: 0.4, satFat: 0.1, fiber: 2.2, sugar: 0.4, sodium: 79, chol: 0, calcium: 99, iron: 2.7, vitC: 28.1),
            makeLocalFood(id: 233, name: "Spinach, cooked", category: "Vegetables", cal: 23, p: 3, c: 3.8, f: 0.3, satFat: 0, fiber: 2.4, sugar: 0.5, sodium: 70, chol: 0, calcium: 136, iron: 3.6, vitC: 9.8),
            makeLocalFood(id: 234, name: "Carrots, raw", category: "Vegetables", cal: 41, p: 0.9, c: 10, f: 0.2, satFat: 0, fiber: 2.8, sugar: 4.7, sodium: 69, chol: 0, calcium: 33, iron: 0.3, vitC: 5.9),
            makeLocalFood(id: 235, name: "Carrots, cooked", category: "Vegetables", cal: 35, p: 0.8, c: 8, f: 0.2, satFat: 0, fiber: 2.8, sugar: 3.5, sodium: 58, chol: 0, calcium: 30, iron: 0.3, vitC: 3.6),
            makeLocalFood(id: 236, name: "Bell Pepper, red", category: "Vegetables", cal: 31, p: 1, c: 6, f: 0.3, satFat: 0, fiber: 2.1, sugar: 4.2, sodium: 4, chol: 0, calcium: 7, iron: 0.4, vitC: 127.7),
            makeLocalFood(id: 237, name: "Bell Pepper, green", category: "Vegetables", cal: 20, p: 0.9, c: 4.6, f: 0.2, satFat: 0, fiber: 1.7, sugar: 2.4, sodium: 3, chol: 0, calcium: 10, iron: 0.3, vitC: 80.4),
            makeLocalFood(id: 238, name: "Bell Pepper, yellow", category: "Vegetables", cal: 27, p: 1, c: 6, f: 0.2, satFat: 0, fiber: 0.9, sugar: 0, sodium: 2, chol: 0, calcium: 11, iron: 0.5, vitC: 183.5),
            makeLocalFood(id: 239, name: "Tomatoes", category: "Vegetables", cal: 18, p: 0.9, c: 3.9, f: 0.2, satFat: 0, fiber: 1.2, sugar: 2.6, sodium: 5, chol: 0, calcium: 10, iron: 0.3, vitC: 13.7),
            makeLocalFood(id: 240, name: "Cherry Tomatoes", category: "Vegetables", cal: 18, p: 0.9, c: 3.9, f: 0.2, satFat: 0, fiber: 1.2, sugar: 2.6, sodium: 5, chol: 0, calcium: 10, iron: 0.3, vitC: 13.7),
            makeLocalFood(id: 241, name: "Cucumber", category: "Vegetables", cal: 16, p: 0.7, c: 3.6, f: 0.1, satFat: 0, fiber: 0.5, sugar: 1.7, sodium: 2, chol: 0, calcium: 16, iron: 0.3, vitC: 2.8),
            makeLocalFood(id: 242, name: "Lettuce, romaine", category: "Vegetables", cal: 17, p: 1.2, c: 3.3, f: 0.3, satFat: 0, fiber: 2.1, sugar: 1.2, sodium: 8, chol: 0, calcium: 33, iron: 1.0, vitC: 4),
            makeLocalFood(id: 243, name: "Lettuce, iceberg", category: "Vegetables", cal: 14, p: 0.9, c: 3, f: 0.1, satFat: 0, fiber: 1.2, sugar: 2, sodium: 10, chol: 0, calcium: 18, iron: 0.4, vitC: 2.8),
            makeLocalFood(id: 244, name: "Lettuce, mixed greens", category: "Vegetables", cal: 20, p: 1.5, c: 3.5, f: 0.3, satFat: 0, fiber: 1.8, sugar: 1, sodium: 25, chol: 0, calcium: 55, iron: 1.2, vitC: 18),
            makeLocalFood(id: 245, name: "Onion", category: "Vegetables", cal: 40, p: 1.1, c: 9.3, f: 0.1, satFat: 0, fiber: 1.7, sugar: 4.2, sodium: 4, chol: 0, calcium: 23, iron: 0.2, vitC: 7.4),
            makeLocalFood(id: 246, name: "Onion, red", category: "Vegetables", cal: 40, p: 1.1, c: 9.3, f: 0.1, satFat: 0, fiber: 1.7, sugar: 4.2, sodium: 4, chol: 0, calcium: 23, iron: 0.2, vitC: 7.4),
            makeLocalFood(id: 247, name: "Garlic", category: "Vegetables", cal: 149, p: 6.4, c: 33, f: 0.5, satFat: 0.1, fiber: 2.1, sugar: 1, sodium: 17, chol: 0, calcium: 181, iron: 1.7, vitC: 31.2),
            makeLocalFood(id: 248, name: "Mushrooms, white", category: "Vegetables", cal: 22, p: 3.1, c: 3.3, f: 0.3, satFat: 0, fiber: 1, sugar: 2, sodium: 5, chol: 0, calcium: 3, iron: 0.5, vitC: 2.1),
            makeLocalFood(id: 249, name: "Mushrooms, portobello", category: "Vegetables", cal: 22, p: 2.1, c: 3.9, f: 0.4, satFat: 0.1, fiber: 1.3, sugar: 2.5, sodium: 9, chol: 0, calcium: 3, iron: 0.3, vitC: 0),
            makeLocalFood(id: 250, name: "Asparagus", category: "Vegetables", cal: 20, p: 2.2, c: 3.9, f: 0.1, satFat: 0, fiber: 2.1, sugar: 1.9, sodium: 2, chol: 0, calcium: 24, iron: 2.1, vitC: 5.6),
            makeLocalFood(id: 251, name: "Green Beans", category: "Vegetables", cal: 31, p: 1.8, c: 7, f: 0.2, satFat: 0, fiber: 3.4, sugar: 1.4, sodium: 6, chol: 0, calcium: 37, iron: 1.0, vitC: 16.3),
            makeLocalFood(id: 252, name: "Cauliflower", category: "Vegetables", cal: 25, p: 1.9, c: 5, f: 0.3, satFat: 0, fiber: 2, sugar: 1.9, sodium: 30, chol: 0, calcium: 22, iron: 0.4, vitC: 48.2),
            makeLocalFood(id: 253, name: "Zucchini", category: "Vegetables", cal: 17, p: 1.2, c: 3.1, f: 0.3, satFat: 0.1, fiber: 1, sugar: 2.5, sodium: 8, chol: 0, calcium: 16, iron: 0.4, vitC: 17.9),
            makeLocalFood(id: 254, name: "Kale, raw", category: "Vegetables", cal: 49, p: 4.3, c: 9, f: 0.9, satFat: 0.1, fiber: 3.6, sugar: 2.3, sodium: 38, chol: 0, calcium: 150, iron: 1.5, vitC: 120),
            makeLocalFood(id: 255, name: "Brussels Sprouts", category: "Vegetables", cal: 43, p: 3.4, c: 9, f: 0.3, satFat: 0.1, fiber: 3.8, sugar: 2.2, sodium: 25, chol: 0, calcium: 42, iron: 1.4, vitC: 85),
            makeLocalFood(id: 256, name: "Celery", category: "Vegetables", cal: 16, p: 0.7, c: 3, f: 0.2, satFat: 0, fiber: 1.6, sugar: 1.3, sodium: 80, chol: 0, calcium: 40, iron: 0.2, vitC: 3.1),
            makeLocalFood(id: 257, name: "Cabbage", category: "Vegetables", cal: 25, p: 1.3, c: 6, f: 0.1, satFat: 0, fiber: 2.5, sugar: 3.2, sodium: 18, chol: 0, calcium: 40, iron: 0.5, vitC: 36.6),
            makeLocalFood(id: 258, name: "Cabbage, red", category: "Vegetables", cal: 31, p: 1.4, c: 7, f: 0.2, satFat: 0, fiber: 2.1, sugar: 3.8, sodium: 27, chol: 0, calcium: 45, iron: 0.8, vitC: 57),
            makeLocalFood(id: 259, name: "Corn", category: "Vegetables", cal: 96, p: 3.4, c: 21, f: 1.5, satFat: 0.2, fiber: 2.4, sugar: 4.5, sodium: 1, chol: 0, calcium: 2, iron: 0.5, vitC: 6.2),
            makeLocalFood(id: 260, name: "Peas", category: "Vegetables", cal: 81, p: 5.4, c: 14, f: 0.4, satFat: 0.1, fiber: 5.1, sugar: 5.7, sodium: 5, chol: 0, calcium: 25, iron: 1.5, vitC: 40),
            makeLocalFood(id: 261, name: "Edamame", category: "Vegetables", cal: 121, p: 11, c: 9, f: 5, satFat: 0.6, fiber: 5.2, sugar: 2.2, sodium: 6, chol: 0, calcium: 63, iron: 2.3, vitC: 6.1),
            makeLocalFood(id: 262, name: "Eggplant", category: "Vegetables", cal: 25, p: 1, c: 6, f: 0.2, satFat: 0, fiber: 3, sugar: 3.5, sodium: 2, chol: 0, calcium: 9, iron: 0.2, vitC: 2.2),
            makeLocalFood(id: 263, name: "Artichoke", category: "Vegetables", cal: 47, p: 3.3, c: 11, f: 0.2, satFat: 0, fiber: 5.4, sugar: 1, sodium: 94, chol: 0, calcium: 44, iron: 1.3, vitC: 11.7),
            makeLocalFood(id: 264, name: "Beets", category: "Vegetables", cal: 43, p: 1.6, c: 10, f: 0.2, satFat: 0, fiber: 2.8, sugar: 7, sodium: 78, chol: 0, calcium: 16, iron: 0.8, vitC: 4.9),
            makeLocalFood(id: 265, name: "Radishes", category: "Vegetables", cal: 16, p: 0.7, c: 3.4, f: 0.1, satFat: 0, fiber: 1.6, sugar: 1.9, sodium: 39, chol: 0, calcium: 25, iron: 0.3, vitC: 14.8),
            makeLocalFood(id: 266, name: "Squash, butternut", category: "Vegetables", cal: 45, p: 1, c: 12, f: 0.1, satFat: 0, fiber: 2, sugar: 2.2, sodium: 4, chol: 0, calcium: 48, iron: 0.7, vitC: 21),
            makeLocalFood(id: 267, name: "Squash, spaghetti", category: "Vegetables", cal: 31, p: 0.6, c: 7, f: 0.6, satFat: 0.1, fiber: 1.5, sugar: 2.8, sodium: 17, chol: 0, calcium: 23, iron: 0.3, vitC: 2.1),
            makeLocalFood(id: 268, name: "Squash, acorn", category: "Vegetables", cal: 40, p: 0.8, c: 10, f: 0.1, satFat: 0, fiber: 1.5, sugar: 0, sodium: 3, chol: 0, calcium: 33, iron: 0.7, vitC: 11),
            makeLocalFood(id: 269, name: "Leeks", category: "Vegetables", cal: 61, p: 1.5, c: 14, f: 0.3, satFat: 0, fiber: 1.8, sugar: 3.9, sodium: 20, chol: 0, calcium: 59, iron: 2.1, vitC: 12),
            makeLocalFood(id: 270, name: "Bok Choy", category: "Vegetables", cal: 13, p: 1.5, c: 2.2, f: 0.2, satFat: 0, fiber: 1, sugar: 1.2, sodium: 65, chol: 0, calcium: 105, iron: 0.8, vitC: 45),
            makeLocalFood(id: 271, name: "Arugula", category: "Vegetables", cal: 25, p: 2.6, c: 3.7, f: 0.7, satFat: 0, fiber: 1.6, sugar: 2, sodium: 27, chol: 0, calcium: 160, iron: 1.5, vitC: 15),
            makeLocalFood(id: 272, name: "Swiss Chard", category: "Vegetables", cal: 19, p: 1.8, c: 3.7, f: 0.2, satFat: 0, fiber: 1.6, sugar: 1.1, sodium: 213, chol: 0, calcium: 51, iron: 1.8, vitC: 30),
            makeLocalFood(id: 273, name: "Collard Greens", category: "Vegetables", cal: 32, p: 3, c: 5.4, f: 0.6, satFat: 0.1, fiber: 4, sugar: 0.5, sodium: 17, chol: 0, calcium: 232, iron: 0.5, vitC: 35.3),
            makeLocalFood(id: 274, name: "Turnips", category: "Vegetables", cal: 28, p: 0.9, c: 6, f: 0.1, satFat: 0, fiber: 1.8, sugar: 3.8, sodium: 67, chol: 0, calcium: 30, iron: 0.3, vitC: 21),
            makeLocalFood(id: 275, name: "Parsnips", category: "Vegetables", cal: 75, p: 1.2, c: 18, f: 0.3, satFat: 0.1, fiber: 4.9, sugar: 4.8, sodium: 10, chol: 0, calcium: 36, iron: 0.6, vitC: 17),
            makeLocalFood(id: 276, name: "Jalapeno", category: "Vegetables", cal: 29, p: 0.9, c: 6.5, f: 0.4, satFat: 0, fiber: 2.8, sugar: 4.1, sodium: 3, chol: 0, calcium: 12, iron: 0.3, vitC: 118.6),
            
            // ===== NUTS & SEEDS (20+ items) ===== with full USDA nutrition data
            makeLocalFood(id: 280, name: "Almonds", category: "Nuts", cal: 579, p: 21, c: 22, f: 50, satFat: 3.8, fiber: 12.5, sugar: 4.4, sodium: 1, chol: 0, calcium: 269, iron: 3.7, vitC: 0),
            makeLocalFood(id: 281, name: "Almonds, sliced", category: "Nuts", cal: 579, p: 21, c: 22, f: 50, satFat: 3.8, fiber: 12.5, sugar: 4.4, sodium: 1, chol: 0, calcium: 269, iron: 3.7, vitC: 0),
            makeLocalFood(id: 282, name: "Almond Butter", category: "Nuts", cal: 614, p: 21, c: 19, f: 56, satFat: 4.4, fiber: 10.3, sugar: 4.4, sodium: 5, chol: 0, calcium: 347, iron: 3.5, vitC: 0),
            makeLocalFood(id: 283, name: "Peanuts", category: "Nuts", cal: 567, p: 26, c: 16, f: 49, satFat: 6.8, fiber: 8.5, sugar: 4, sodium: 18, chol: 0, calcium: 92, iron: 4.6, vitC: 0),
            makeLocalFood(id: 284, name: "Peanut Butter", category: "Nuts", cal: 588, p: 25, c: 20, f: 50, satFat: 10.1, fiber: 6, sugar: 9.2, sodium: 459, chol: 0, calcium: 43, iron: 1.9, vitC: 0),
            makeLocalFood(id: 285, name: "Peanut Butter, natural", category: "Nuts", cal: 588, p: 25, c: 20, f: 50, satFat: 7.7, fiber: 6, sugar: 5, sodium: 17, chol: 0, calcium: 54, iron: 1.7, vitC: 0),
            makeLocalFood(id: 286, name: "Walnuts", category: "Nuts", cal: 654, p: 15, c: 14, f: 65, satFat: 6.1, fiber: 6.7, sugar: 2.6, sodium: 2, chol: 0, calcium: 98, iron: 2.9, vitC: 1.3),
            makeLocalFood(id: 287, name: "Cashews", category: "Nuts", cal: 553, p: 18, c: 30, f: 44, satFat: 7.8, fiber: 3.3, sugar: 5.9, sodium: 12, chol: 0, calcium: 37, iron: 6.7, vitC: 0.5),
            makeLocalFood(id: 288, name: "Cashew Butter", category: "Nuts", cal: 587, p: 18, c: 27, f: 49, satFat: 8.5, fiber: 2, sugar: 5.4, sodium: 15, chol: 0, calcium: 43, iron: 5.1, vitC: 0),
            makeLocalFood(id: 289, name: "Pistachios", category: "Nuts", cal: 560, p: 20, c: 28, f: 45, satFat: 5.6, fiber: 10.6, sugar: 7.7, sodium: 1, chol: 0, calcium: 105, iron: 3.9, vitC: 5.6),
            makeLocalFood(id: 290, name: "Pecans", category: "Nuts", cal: 691, p: 9, c: 14, f: 72, satFat: 6.2, fiber: 9.6, sugar: 4, sodium: 0, chol: 0, calcium: 70, iron: 2.5, vitC: 1.1),
            makeLocalFood(id: 291, name: "Macadamia Nuts", category: "Nuts", cal: 718, p: 8, c: 14, f: 76, satFat: 12.1, fiber: 8.6, sugar: 4.6, sodium: 5, chol: 0, calcium: 85, iron: 3.7, vitC: 1.2),
            makeLocalFood(id: 292, name: "Hazelnuts", category: "Nuts", cal: 628, p: 15, c: 17, f: 61, satFat: 4.5, fiber: 9.7, sugar: 4.3, sodium: 0, chol: 0, calcium: 114, iron: 4.7, vitC: 6.3),
            makeLocalFood(id: 293, name: "Brazil Nuts", category: "Nuts", cal: 656, p: 14, c: 12, f: 66, satFat: 15.1, fiber: 7.5, sugar: 2.3, sodium: 3, chol: 0, calcium: 160, iron: 2.4, vitC: 0.7),
            makeLocalFood(id: 294, name: "Mixed Nuts", category: "Nuts", cal: 607, p: 17, c: 21, f: 54, satFat: 7, fiber: 7, sugar: 4, sodium: 185, chol: 0, calcium: 78, iron: 3.5, vitC: 0.5),
            makeLocalFood(id: 295, name: "Chia Seeds", category: "Seeds", cal: 486, p: 17, c: 42, f: 31, satFat: 3.3, fiber: 34.4, sugar: 0, sodium: 16, chol: 0, calcium: 631, iron: 7.7, vitC: 1.6),
            makeLocalFood(id: 296, name: "Flax Seeds", category: "Seeds", cal: 534, p: 18, c: 29, f: 42, satFat: 3.7, fiber: 27.3, sugar: 1.6, sodium: 30, chol: 0, calcium: 255, iron: 5.7, vitC: 0.6),
            makeLocalFood(id: 297, name: "Flax Seeds, ground", category: "Seeds", cal: 534, p: 18, c: 29, f: 42, satFat: 3.7, fiber: 27.3, sugar: 1.6, sodium: 30, chol: 0, calcium: 255, iron: 5.7, vitC: 0.6),
            makeLocalFood(id: 298, name: "Sunflower Seeds", category: "Seeds", cal: 584, p: 21, c: 20, f: 51, satFat: 4.5, fiber: 8.6, sugar: 2.6, sodium: 9, chol: 0, calcium: 78, iron: 5.3, vitC: 1.4),
            makeLocalFood(id: 299, name: "Pumpkin Seeds", category: "Seeds", cal: 559, p: 30, c: 11, f: 49, satFat: 8.7, fiber: 6, sugar: 1.4, sodium: 7, chol: 0, calcium: 46, iron: 8.8, vitC: 1.9),
            makeLocalFood(id: 300, name: "Hemp Seeds", category: "Seeds", cal: 553, p: 32, c: 9, f: 49, satFat: 4.6, fiber: 4, sugar: 1.5, sodium: 5, chol: 0, calcium: 70, iron: 7.9, vitC: 0.5),
            makeLocalFood(id: 301, name: "Sesame Seeds", category: "Seeds", cal: 573, p: 18, c: 23, f: 50, satFat: 7, fiber: 11.8, sugar: 0.3, sodium: 11, chol: 0, calcium: 975, iron: 14.6, vitC: 0),
            makeLocalFood(id: 302, name: "Tahini", category: "Seeds", cal: 595, p: 17, c: 21, f: 54, satFat: 7.6, fiber: 9.3, sugar: 0.5, sodium: 115, chol: 0, calcium: 426, iron: 8.9, vitC: 0),
            
            // ===== LEGUMES (15+ items) ===== with full USDA nutrition data
            makeLocalFood(id: 310, name: "Black Beans, cooked", category: "Legumes", cal: 132, p: 8.9, c: 24, f: 0.5, satFat: 0.1, fiber: 8.7, sugar: 0.3, sodium: 1, chol: 0, calcium: 46, iron: 2.1, vitC: 0),
            makeLocalFood(id: 311, name: "Black Beans, canned", category: "Legumes", cal: 91, p: 6, c: 16, f: 0.4, satFat: 0.1, fiber: 6, sugar: 0.3, sodium: 405, chol: 0, calcium: 27, iron: 1.6, vitC: 0),
            makeLocalFood(id: 312, name: "Chickpeas, cooked", category: "Legumes", cal: 164, p: 8.9, c: 27, f: 2.6, satFat: 0.3, fiber: 7.6, sugar: 4.8, sodium: 7, chol: 0, calcium: 49, iron: 2.9, vitC: 1.3),
            makeLocalFood(id: 313, name: "Chickpeas, canned", category: "Legumes", cal: 139, p: 7, c: 23, f: 2.4, satFat: 0.2, fiber: 5.3, sugar: 3.6, sodium: 284, chol: 0, calcium: 48, iron: 1.7, vitC: 0),
            makeLocalFood(id: 314, name: "Lentils, cooked", category: "Legumes", cal: 116, p: 9, c: 20, f: 0.4, satFat: 0.1, fiber: 7.9, sugar: 1.8, sodium: 2, chol: 0, calcium: 19, iron: 3.3, vitC: 1.5),
            makeLocalFood(id: 315, name: "Kidney Beans, cooked", category: "Legumes", cal: 127, p: 8.7, c: 23, f: 0.5, satFat: 0.1, fiber: 6.4, sugar: 0.3, sodium: 2, chol: 0, calcium: 35, iron: 2.2, vitC: 1.2),
            makeLocalFood(id: 316, name: "Pinto Beans, cooked", category: "Legumes", cal: 143, p: 9, c: 26, f: 0.7, satFat: 0.1, fiber: 9, sugar: 0.3, sodium: 1, chol: 0, calcium: 46, iron: 2.1, vitC: 0.8),
            makeLocalFood(id: 317, name: "Navy Beans, cooked", category: "Legumes", cal: 140, p: 8, c: 26, f: 0.6, satFat: 0.1, fiber: 10.5, sugar: 0.4, sodium: 1, chol: 0, calcium: 69, iron: 2.4, vitC: 0.9),
            makeLocalFood(id: 318, name: "Lima Beans, cooked", category: "Legumes", cal: 115, p: 8, c: 21, f: 0.4, satFat: 0.1, fiber: 7, sugar: 2.9, sodium: 2, chol: 0, calcium: 17, iron: 2.4, vitC: 0),
            makeLocalFood(id: 319, name: "Refried Beans", category: "Legumes", cal: 108, p: 6, c: 16, f: 2.2, satFat: 0.7, fiber: 5, sugar: 0.5, sodium: 529, chol: 2, calcium: 44, iron: 1.4, vitC: 0),
            makeLocalFood(id: 320, name: "Hummus", category: "Legumes", cal: 166, p: 8, c: 14, f: 10, satFat: 1.4, fiber: 6, sugar: 0.3, sodium: 379, chol: 0, calcium: 38, iron: 2.4, vitC: 0),
            makeLocalFood(id: 321, name: "Tofu, firm", category: "Legumes", cal: 144, p: 17, c: 3, f: 8, satFat: 1.2, fiber: 2.3, sugar: 0.6, sodium: 12, chol: 0, calcium: 683, iron: 2.7, vitC: 0.2),
            makeLocalFood(id: 322, name: "Tofu, silken", category: "Legumes", cal: 55, p: 5, c: 2, f: 2.7, satFat: 0.4, fiber: 0.2, sugar: 1.4, sodium: 7, chol: 0, calcium: 111, iron: 0.6, vitC: 0),
            makeLocalFood(id: 323, name: "Tempeh", category: "Legumes", cal: 192, p: 20, c: 8, f: 11, satFat: 2.2, fiber: 0, sugar: 0, sodium: 9, chol: 0, calcium: 111, iron: 2.7, vitC: 0),
            
            // ===== OILS & FATS (10+ items) ===== with full USDA nutrition data
            makeLocalFood(id: 330, name: "Olive Oil", category: "Oils", cal: 884, p: 0, c: 0, f: 100, satFat: 13.8, fiber: 0, sugar: 0, sodium: 2, chol: 0, calcium: 1, iron: 0.6, vitC: 0),
            makeLocalFood(id: 331, name: "Olive Oil, extra virgin", category: "Oils", cal: 884, p: 0, c: 0, f: 100, satFat: 13.8, fiber: 0, sugar: 0, sodium: 2, chol: 0, calcium: 1, iron: 0.6, vitC: 0),
            makeLocalFood(id: 332, name: "Coconut Oil", category: "Oils", cal: 862, p: 0, c: 0, f: 100, satFat: 82.5, fiber: 0, sugar: 0, sodium: 0, chol: 0, calcium: 0, iron: 0, vitC: 0),
            makeLocalFood(id: 333, name: "Avocado Oil", category: "Oils", cal: 884, p: 0, c: 0, f: 100, satFat: 11.6, fiber: 0, sugar: 0, sodium: 1, chol: 0, calcium: 0, iron: 0, vitC: 0),
            makeLocalFood(id: 334, name: "Vegetable Oil", category: "Oils", cal: 884, p: 0, c: 0, f: 100, satFat: 7.4, fiber: 0, sugar: 0, sodium: 0, chol: 0, calcium: 0, iron: 0, vitC: 0),
            makeLocalFood(id: 335, name: "Canola Oil", category: "Oils", cal: 884, p: 0, c: 0, f: 100, satFat: 7.4, fiber: 0, sugar: 0, sodium: 0, chol: 0, calcium: 0, iron: 0, vitC: 0),
            makeLocalFood(id: 336, name: "Sesame Oil", category: "Oils", cal: 884, p: 0, c: 0, f: 100, satFat: 14.2, fiber: 0, sugar: 0, sodium: 0, chol: 0, calcium: 0, iron: 0, vitC: 0),
            makeLocalFood(id: 337, name: "Ghee", category: "Oils", cal: 900, p: 0, c: 0, f: 100, satFat: 62.0, fiber: 0, sugar: 0, sodium: 2, chol: 256, calcium: 4, iron: 0, vitC: 0),
            
            // ===== CONDIMENTS & SAUCES (15+ items) ===== with full USDA nutrition data
            makeLocalFood(id: 340, name: "Honey", category: "Sweeteners", cal: 304, p: 0.3, c: 82, f: 0, satFat: 0, fiber: 0.2, sugar: 82, sodium: 4, chol: 0, calcium: 6, iron: 0.4, vitC: 0.5),
            makeLocalFood(id: 341, name: "Maple Syrup", category: "Sweeteners", cal: 260, p: 0, c: 67, f: 0.1, satFat: 0, fiber: 0, sugar: 60, sodium: 12, chol: 0, calcium: 102, iron: 0.1, vitC: 0),
            makeLocalFood(id: 342, name: "Ketchup", category: "Condiments", cal: 112, p: 1.7, c: 26, f: 0.1, satFat: 0, fiber: 0.3, sugar: 22, sodium: 907, chol: 0, calcium: 18, iron: 0.4, vitC: 4.2),
            makeLocalFood(id: 343, name: "Mustard", category: "Condiments", cal: 66, p: 4, c: 6, f: 3, satFat: 0.2, fiber: 3.2, sugar: 2.2, sodium: 1135, chol: 0, calcium: 58, iron: 1.5, vitC: 0.3),
            makeLocalFood(id: 344, name: "Mayonnaise", category: "Condiments", cal: 680, p: 1, c: 0.6, f: 75, satFat: 11.8, fiber: 0, sugar: 0.1, sodium: 635, chol: 42, calcium: 8, iron: 0.2, vitC: 0),
            makeLocalFood(id: 345, name: "Mayonnaise, light", category: "Condiments", cal: 231, p: 0, c: 3, f: 24, satFat: 3.7, fiber: 0, sugar: 2, sodium: 700, chol: 18, calcium: 0, iron: 0, vitC: 0),
            makeLocalFood(id: 346, name: "Soy Sauce", category: "Condiments", cal: 53, p: 8, c: 5, f: 0, satFat: 0, fiber: 0.8, sugar: 0.4, sodium: 5493, chol: 0, calcium: 20, iron: 1.9, vitC: 0),
            makeLocalFood(id: 347, name: "Hot Sauce", category: "Condiments", cal: 11, p: 0.5, c: 2, f: 0.1, satFat: 0, fiber: 0.5, sugar: 0.9, sodium: 2643, chol: 0, calcium: 12, iron: 0.6, vitC: 4),
            makeLocalFood(id: 348, name: "Salsa", category: "Condiments", cal: 36, p: 1.5, c: 7, f: 0.2, satFat: 0, fiber: 1.9, sugar: 3.9, sodium: 571, chol: 0, calcium: 24, iron: 0.5, vitC: 4.8),
            makeLocalFood(id: 349, name: "BBQ Sauce", category: "Condiments", cal: 172, p: 0.8, c: 41, f: 0.6, satFat: 0.1, fiber: 0.4, sugar: 33, sodium: 989, chol: 0, calcium: 17, iron: 0.6, vitC: 0.2),
            makeLocalFood(id: 350, name: "Ranch Dressing", category: "Condiments", cal: 455, p: 1.5, c: 5, f: 47, satFat: 7.1, fiber: 0.3, sugar: 2, sodium: 758, chol: 26, calcium: 36, iron: 0.1, vitC: 0.7),
            makeLocalFood(id: 351, name: "Italian Dressing", category: "Condiments", cal: 280, p: 0.5, c: 7, f: 28, satFat: 4.1, fiber: 0.2, sugar: 6, sodium: 946, chol: 0, calcium: 8, iron: 0.3, vitC: 0.2),
            makeLocalFood(id: 352, name: "Balsamic Vinegar", category: "Condiments", cal: 88, p: 0.5, c: 17, f: 0, satFat: 0, fiber: 0, sugar: 15, sodium: 23, chol: 0, calcium: 27, iron: 0.7, vitC: 0),
            makeLocalFood(id: 353, name: "Sriracha", category: "Condiments", cal: 93, p: 2, c: 19, f: 0.9, satFat: 0.1, fiber: 0.4, sugar: 16, sodium: 2260, chol: 0, calcium: 16, iron: 0.5, vitC: 18),
            makeLocalFood(id: 354, name: "Guacamole", category: "Condiments", cal: 150, p: 2, c: 8, f: 13, satFat: 1.8, fiber: 6, sugar: 0.6, sodium: 360, chol: 0, calcium: 12, iron: 0.5, vitC: 8),
            
            // ===== SUPPLEMENTS & BEVERAGES (15+ items) ===== with full USDA nutrition data
            makeLocalFood(id: 360, name: "Protein Powder, whey", category: "Supplements", cal: 120, p: 24, c: 3, f: 1, satFat: 0.5, fiber: 0, sugar: 1, sodium: 130, chol: 30, calcium: 130, iron: 0.4, vitC: 0),
            makeLocalFood(id: 361, name: "Protein Powder, whey isolate", category: "Supplements", cal: 100, p: 25, c: 1, f: 0.5, satFat: 0.3, fiber: 0, sugar: 1, sodium: 100, chol: 20, calcium: 120, iron: 0.3, vitC: 0),
            makeLocalFood(id: 362, name: "Protein Powder, casein", category: "Supplements", cal: 120, p: 24, c: 3, f: 1, satFat: 0.5, fiber: 0, sugar: 1, sodium: 85, chol: 30, calcium: 480, iron: 0.4, vitC: 0),
            makeLocalFood(id: 363, name: "Protein Powder, plant", category: "Supplements", cal: 110, p: 20, c: 5, f: 2, satFat: 0.3, fiber: 2, sugar: 1, sodium: 300, chol: 0, calcium: 100, iron: 4, vitC: 0),
            makeLocalFood(id: 364, name: "Creatine", category: "Supplements", cal: 0, p: 0, c: 0, f: 0, satFat: 0, fiber: 0, sugar: 0, sodium: 0, chol: 0, calcium: 0, iron: 0, vitC: 0),
            makeLocalFood(id: 365, name: "Orange Juice", category: "Beverages", cal: 45, p: 0.7, c: 10, f: 0.2, satFat: 0, fiber: 0.2, sugar: 8.4, sodium: 1, chol: 0, calcium: 11, iron: 0.2, vitC: 50),
            makeLocalFood(id: 366, name: "Apple Juice", category: "Beverages", cal: 46, p: 0.1, c: 11, f: 0.1, satFat: 0, fiber: 0.2, sugar: 10, sodium: 4, chol: 0, calcium: 8, iron: 0.1, vitC: 0.9),
            makeLocalFood(id: 367, name: "Cranberry Juice", category: "Beverages", cal: 46, p: 0, c: 12, f: 0.1, satFat: 0, fiber: 0.1, sugar: 12, sodium: 2, chol: 0, calcium: 8, iron: 0.2, vitC: 9.3),
            makeLocalFood(id: 368, name: "Coffee, black", category: "Beverages", cal: 2, p: 0.3, c: 0, f: 0, satFat: 0, fiber: 0, sugar: 0, sodium: 5, chol: 0, calcium: 2, iron: 0, vitC: 0),
            makeLocalFood(id: 369, name: "Tea, unsweetened", category: "Beverages", cal: 1, p: 0, c: 0, f: 0, satFat: 0, fiber: 0, sugar: 0, sodium: 3, chol: 0, calcium: 0, iron: 0, vitC: 0),
            makeLocalFood(id: 370, name: "Coconut Water", category: "Beverages", cal: 19, p: 0.7, c: 4, f: 0.2, satFat: 0.2, fiber: 1.1, sugar: 2.6, sodium: 105, chol: 0, calcium: 24, iron: 0.3, vitC: 2.4),
            
            // ===== COMMON PREPARED FOODS (10+ items) ===== with full USDA nutrition data
            makeLocalFood(id: 380, name: "Pizza, cheese", category: "Prepared Foods", cal: 266, p: 11, c: 33, f: 10, satFat: 4.5, fiber: 2.3, sugar: 3.6, sodium: 598, chol: 22, calcium: 171, iron: 2.1, vitC: 1.5),
            makeLocalFood(id: 381, name: "Pizza, pepperoni", category: "Prepared Foods", cal: 298, p: 13, c: 30, f: 14, satFat: 5.6, fiber: 2, sugar: 3.5, sodium: 760, chol: 35, calcium: 156, iron: 2.4, vitC: 1),
            makeLocalFood(id: 382, name: "Hamburger", category: "Prepared Foods", cal: 295, p: 17, c: 24, f: 14, satFat: 5.2, fiber: 1.3, sugar: 5, sodium: 562, chol: 52, calcium: 126, iron: 2.8, vitC: 1),
            makeLocalFood(id: 383, name: "Hot Dog", category: "Prepared Foods", cal: 290, p: 10, c: 24, f: 17, satFat: 6.0, fiber: 0.8, sugar: 4, sodium: 860, chol: 45, calcium: 62, iron: 2.3, vitC: 0),
            makeLocalFood(id: 384, name: "Burrito", category: "Prepared Foods", cal: 206, p: 9, c: 26, f: 7, satFat: 2.5, fiber: 2.8, sugar: 1.3, sodium: 495, chol: 23, calcium: 72, iron: 1.6, vitC: 1.2),
            makeLocalFood(id: 385, name: "Taco", category: "Prepared Foods", cal: 210, p: 9, c: 21, f: 10, satFat: 4.0, fiber: 2, sugar: 2, sodium: 485, chol: 26, calcium: 98, iron: 1.4, vitC: 2),
            makeLocalFood(id: 386, name: "Sushi Roll", category: "Prepared Foods", cal: 200, p: 6, c: 38, f: 2, satFat: 0.3, fiber: 1.5, sugar: 5, sodium: 380, chol: 12, calcium: 20, iron: 0.8, vitC: 1),
            makeLocalFood(id: 387, name: "Grilled Cheese Sandwich", category: "Prepared Foods", cal: 291, p: 10, c: 26, f: 16, satFat: 8.3, fiber: 1.2, sugar: 3, sodium: 598, chol: 43, calcium: 248, iron: 1.5, vitC: 0),
            makeLocalFood(id: 388, name: "Pancakes", category: "Prepared Foods", cal: 227, p: 6, c: 38, f: 5, satFat: 1.4, fiber: 1.2, sugar: 8, sodium: 439, chol: 22, calcium: 83, iron: 1.6, vitC: 0),
            makeLocalFood(id: 389, name: "Waffles", category: "Prepared Foods", cal: 291, p: 8, c: 33, f: 14, satFat: 2.9, fiber: 1.5, sugar: 5, sodium: 511, chol: 52, calcium: 196, iron: 2.1, vitC: 0),
            makeLocalFood(id: 390, name: "French Toast", category: "Prepared Foods", cal: 229, p: 8, c: 24, f: 11, satFat: 2.6, fiber: 0.7, sugar: 7, sodium: 435, chol: 87, calcium: 86, iron: 1.7, vitC: 0),
        ]
    }
    
    /// Create local food with full nutrition - estimates detailed values based on category if not provided
    private func makeLocalFood(
        id: Int, 
        name: String, 
        category: String, 
        cal: Double, 
        p: Double, 
        c: Double, 
        f: Double,
        satFat: Double? = nil,
        fiber: Double? = nil,
        sugar: Double? = nil,
        sodium: Double? = nil,
        chol: Double? = nil,
        calcium: Double? = nil,
        iron: Double? = nil,
        vitC: Double? = nil
    ) -> ProcessedFoodItem {
        // Estimate detailed nutrition based on category if not provided
        let estimated = estimateDetailedNutrition(
            category: category,
            totalFat: f,
            carbs: c,
            protein: p
        )
        
        return ProcessedFoodItem(
            id: 100000 + id,
            name: name,
            brandName: nil,
            description: name,
            category: category,
            servingSize: 100,
            servingUnit: "g",
            nutrition: NutritionInfo(
                calories: cal,
                protein: p,
                carbohydrates: c,
                totalFat: f,
                saturatedFat: satFat ?? estimated.satFat,
                fiber: fiber ?? estimated.fiber,
                sugar: sugar ?? estimated.sugar,
                sodium: sodium ?? estimated.sodium,
                cholesterol: chol ?? estimated.chol,
                calcium: calcium ?? estimated.calcium,
                iron: iron ?? estimated.iron,
                vitaminC: vitC ?? estimated.vitC
            ),
            portions: [],
            dataType: "Local"  // Local hardcoded foods
        )
    }
    
    /// Estimate detailed nutrition based on food category
    private func estimateDetailedNutrition(category: String, totalFat: Double, carbs: Double, protein: Double) -> (satFat: Double, fiber: Double, sugar: Double, sodium: Double, chol: Double, calcium: Double, iron: Double, vitC: Double) {
        let cat = category.lowercased()
        
        // Protein sources (meat, fish, eggs)
        if cat.contains("poultry") || cat.contains("chicken") || cat.contains("turkey") {
            return (satFat: totalFat * 0.3, fiber: 0, sugar: 0, sodium: 70, chol: 85, calcium: 15, iron: 1.0, vitC: 0)
        }
        if cat.contains("beef") {
            return (satFat: totalFat * 0.4, fiber: 0, sugar: 0, sodium: 65, chol: 75, calcium: 18, iron: 2.5, vitC: 0)
        }
        if cat.contains("pork") {
            return (satFat: totalFat * 0.35, fiber: 0, sugar: 0, sodium: 60, chol: 70, calcium: 12, iron: 1.0, vitC: 0)
        }
        if cat.contains("fish") || cat.contains("seafood") {
            return (satFat: totalFat * 0.25, fiber: 0, sugar: 0, sodium: 80, chol: 55, calcium: 15, iron: 0.5, vitC: 0)
        }
        if cat.contains("egg") {
            return (satFat: totalFat * 0.35, fiber: 0, sugar: 0.5, sodium: 140, chol: 370, calcium: 50, iron: 1.8, vitC: 0)
        }
        
        // Dairy
        if cat.contains("dairy") || cat.contains("cheese") || cat.contains("milk") || cat.contains("yogurt") {
            return (satFat: totalFat * 0.6, fiber: 0, sugar: carbs * 0.8, sodium: 100, chol: 30, calcium: 120, iron: 0.1, vitC: 1)
        }
        
        // Grains
        if cat.contains("grain") || cat.contains("bread") || cat.contains("pasta") || cat.contains("rice") {
            return (satFat: totalFat * 0.2, fiber: carbs * 0.08, sugar: carbs * 0.05, sodium: 5, chol: 0, calcium: 15, iron: 1.5, vitC: 0)
        }
        
        // Vegetables
        if cat.contains("vegetable") || cat.contains("leafy") {
            return (satFat: 0, fiber: carbs * 0.4, sugar: carbs * 0.3, sodium: 20, chol: 0, calcium: 40, iron: 1.0, vitC: 15)
        }
        
        // Fruits
        if cat.contains("fruit") {
            return (satFat: 0, fiber: carbs * 0.15, sugar: carbs * 0.7, sodium: 2, chol: 0, calcium: 10, iron: 0.3, vitC: 20)
        }
        
        // Nuts & Seeds
        if cat.contains("nut") || cat.contains("seed") {
            return (satFat: totalFat * 0.1, fiber: 6, sugar: 2, sodium: 5, chol: 0, calcium: 70, iron: 2.5, vitC: 0)
        }
        
        // Legumes
        if cat.contains("legume") || cat.contains("bean") {
            return (satFat: 0, fiber: 8, sugar: 1, sodium: 5, chol: 0, calcium: 45, iron: 2.5, vitC: 2)
        }
        
        // Prepared/Other foods
        if cat.contains("prepared") || cat.contains("snack") {
            return (satFat: totalFat * 0.3, fiber: 1, sugar: carbs * 0.2, sodium: 400, chol: 20, calcium: 20, iron: 1.0, vitC: 0)
        }
        
        // Default estimates
        return (satFat: totalFat * 0.3, fiber: 1, sugar: carbs * 0.1, sodium: 50, chol: 0, calcium: 20, iron: 1.0, vitC: 2)
    }
    
    /// Search local foods instantly (no network required)
    /// Returns results ranked by relevance to the query with commonality scoring
    func searchLocalFoods(query: String) -> [ProcessedFoodItem] {
        let normalizedQuery = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return [] }
        
        // Filter matching foods
        let matches = localFoods.filter { food in
            let name = food.name.lowercased()
            let category = food.category?.lowercased() ?? ""
            return name.contains(normalizedQuery) || category.contains(normalizedQuery)
        }
        
        // Sort by relevance with commonality scoring
        return matches.sorted { food1, food2 in
            let score1 = localFoodRelevanceScore(food: food1, query: normalizedQuery)
            let score2 = localFoodRelevanceScore(food: food2, query: normalizedQuery)
            return score1 < score2 // Lower = better
        }
    }
    
    /// Calculate relevance score for local foods with commonality priority
    /// Lower score = higher ranking. Cooked/common variants rank first.
    private func localFoodRelevanceScore(food: ProcessedFoodItem, query: String) -> Int {
        let name = food.name.lowercased()
        var score = 0
        
        // PRIORITY 0: User's frequently logged foods (personal history)
        let usageCount = cloudService.getUsageCount(fdcId: food.id, foodName: food.name)
        if usageCount > 0 {
            score -= 500000 + (usageCount * 1000)
        }
        
        // PRIORITY 1: Exact match
        if name == query { score -= 400000 }
        
        // PRIORITY 2: Starts with query
        if name.hasPrefix(query) { score -= 200000 }
        
        // PRIORITY 3: Commonality scoring - most commonly eaten forms first
        // People eat cooked chicken breast far more than raw
        let highCommonalityKeywords = ["cooked", "grilled", "baked", "roasted", "boneless", "skinless"]
        let mediumCommonalityKeywords = ["whole", "plain", "steamed", "boiled", "scrambled", "hard boiled"]
        let lowCommonalityKeywords = ["raw", "uncooked", "dry", "dehydrated", "freeze-dried"]
        
        let hasHighCommonality = highCommonalityKeywords.contains(where: { name.contains($0) })
        let hasMedCommonality = mediumCommonalityKeywords.contains(where: { name.contains($0) })
        let hasLowCommonality = lowCommonalityKeywords.contains(where: { name.contains($0) })
        
        if hasHighCommonality { score -= 100000 }
        else if hasMedCommonality { score -= 50000 }
        else if hasLowCommonality { score += 50000 }
        
        // PRIORITY 4: Common staple foods get a bonus
        // These are the most commonly tracked foods in fitness apps
        let stapleBoosts: [String: Int] = [
            "chicken breast, cooked": -80000, "chicken breast, grilled": -80000,
            "eggs, whole, cooked": -75000, "eggs, scrambled": -75000, "eggs, hard boiled": -75000,
            "white rice, cooked": -70000, "brown rice, cooked": -70000,
            "greek yogurt, plain, nonfat": -70000,
            "oatmeal, cooked": -65000, "banana": -65000,
            "salmon, cooked": -65000, "ground beef, 90% lean": -60000,
            "avocado": -60000, "sweet potato, baked": -60000,
            "broccoli, cooked": -55000, "spinach, raw": -55000,
            "protein powder, whey": -55000, "almonds": -50000,
            "peanut butter": -50000, "cottage cheese, 2% milkfat": -50000,
        ]
        
        if let boost = stapleBoosts[name] {
            score += boost
        }
        
        // PRIORITY 5: Simpler names (fewer words) are more common
        let wordCount = name.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.count
        score += wordCount * 500
        
        return score
    }
    
    // MARK: - Public Methods
    
    func searchFoods(query: String, pageNumber: Int = 1, pageSize: Int = 25) {
        print("🎯 [USDAFoodService] searchFoods() called with query: '\(query)'")
        
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("⚠️ [USDAFoodService] Query is empty, returning")
            searchResults = []
            return
        }
        
        searchError = nil
        
        // STEP 1: Show local results INSTANTLY (no network delay)
        let localResults = searchLocalFoods(query: query)
        
        // Always show local results immediately if we have them
        if !localResults.isEmpty {
            print("⚡️ [USDA] Found \(localResults.count) local results instantly")
            self.searchResults = localResults
        }
        
        // ALWAYS fetch from cloud to supplement with non-hardcoded foods
        // Show loading indicator only if no local results
        self.isSearching = localResults.isEmpty
        
        // STEP 2: Fetch from cloud in parallel (always - to get non-hardcoded foods)
        Task { @MainActor in
            do {
                let cloudResults = try await cloudService.searchFoods(query: query)
                
                // Convert cloud foods to processed foods
                let processedFoods = cloudResults.map { $0.toProcessedFoodItem() }
                
                // Apply client-side ranking to prioritize generic items
                let rankedCloudResults = self.rankSearchResults(processedFoods, query: query)
                
                // Smart merge with priority: Frequent > Hardcoded > Favorites > Cloud
                var seenIds = Set<Int>()
                var seenNames = Set<String>()
                var frequentResults: [ProcessedFoodItem] = []
                var hardcodedResults: [ProcessedFoodItem] = []
                var favoriteResults: [ProcessedFoodItem] = []
                var cloudOnlyResults: [ProcessedFoodItem] = []
                
                // Get usage counts and favorite IDs for sorting
                let favoriteIds = Set(self.favoriteFoods.map { $0.id })
                let frequentIds = Set(self.frequentFoods.map { $0.id })
                
                // Helper to check if food matches query and add to appropriate bucket
                func categorizeFood(_ food: ProcessedFoodItem, isHardcoded: Bool) {
                    guard !seenIds.contains(food.id) else { return }
                    
                    let simpleName = self.simplifyFoodName(food.name)
                    let hasSimilarName = seenNames.contains { existingName in
                        existingName.contains(simpleName) || simpleName.contains(existingName)
                    }
                    
                    guard !hasSimilarName else { return }
                    
                    seenIds.insert(food.id)
                    seenNames.insert(simpleName)
                    
                    // Categorize by priority
                    let usageCount = self.cloudService.getUsageCount(fdcId: food.id, foodName: food.name)
                    
                    if usageCount > 0 || frequentIds.contains(food.id) {
                        // HIGHEST PRIORITY: Frequently used
                        frequentResults.append(food)
                    } else if isHardcoded {
                        // HIGH PRIORITY: Hardcoded/curated foods
                        hardcodedResults.append(food)
                    } else if favoriteIds.contains(food.id) {
                        // MEDIUM PRIORITY: Favorites
                        favoriteResults.append(food)
                    } else {
                        // LOWER PRIORITY: Cloud/non-hardcoded
                        cloudOnlyResults.append(food)
                    }
                }
                
                // STEP A: Categorize local/hardcoded results
                for food in localResults {
                    categorizeFood(food, isHardcoded: true)
                }
                
                // STEP B: Categorize cloud results
                for food in rankedCloudResults {
                    categorizeFood(food, isHardcoded: false)
                }
                
                // Sort frequent results by usage count (highest first)
                frequentResults.sort { food1, food2 in
                    let count1 = self.cloudService.getUsageCount(fdcId: food1.id, foodName: food1.name)
                    let count2 = self.cloudService.getUsageCount(fdcId: food2.id, foodName: food2.name)
                    return count1 > count2
                }
                
                // Combine in priority order
                let mergedResults = frequentResults + hardcodedResults + favoriteResults + cloudOnlyResults
                
                self.searchResults = mergedResults
                print("✅ [USDA] Final: \(mergedResults.count) results (frequent: \(frequentResults.count), hardcoded: \(hardcodedResults.count), favorites: \(favoriteResults.count), cloud: \(cloudOnlyResults.count))")
                
                self.isSearching = false
            } catch {
                print("❌ Cloud search error: \(error)")
                
                // If cloud fails but we have local results, keep showing them
                if !localResults.isEmpty {
                    print("⚠️ [USDA] Using local results only due to cloud error")
                    self.searchResults = localResults
                    self.isSearching = false
                } else {
                    self.handleSearchError("Search failed: \(error.localizedDescription)")
                    self.isSearching = false
                }
            }
        }
    }
    
    /// Simplify food name for duplicate detection
    /// Only removes minor descriptive suffixes — preserves cooking method
    /// so "Chicken Breast, cooked" and "Chicken Breast, raw" both appear
    private func simplifyFoodName(_ name: String) -> String {
        var simplified = name.lowercased()

        // Only remove trivial presentation suffixes, NOT cooking methods
        // Keep: raw, cooked, grilled, baked, etc. — these are meaningfully different
        let suffixesToRemove = [
            ", fresh", ", whole", ", sliced", ", chopped", ", diced",
            ", shredded", ", minced"
        ]

        for suffix in suffixesToRemove {
            if simplified.hasSuffix(suffix) {
                simplified = String(simplified.dropLast(suffix.count))
            }
        }

        // Remove brand names for generic deduplication
        // e.g., "Tyson Chicken Breast" and "Perdue Chicken Breast" are duplicates
        return simplified.trimmingCharacters(in: .whitespaces)
    }
    
    /// Refresh quick-access foods (recent, favorites, popular)
    func refreshQuickAccessFoods() {
        Task {
            await cloudService.loadRecentFoods()
            await cloudService.loadFavoriteFoods()
            await cloudService.loadPopularFoods()
        }
    }
    
    /// Toggle favorite status for a food
    func toggleFavorite(fdcId: Int, foodItemId: Int) async {
        do {
            if cloudService.isFavorite(foodItemId: foodItemId) {
                try await cloudService.removeFromFavorites(foodItemId: foodItemId)
            } else {
                try await cloudService.addToFavorites(foodItemId: foodItemId)
            }
        } catch {
            print("❌ Error toggling favorite: \(error)")
        }
    }
    
    /// Check if a food is favorited
    func isFavorite(foodItemId: Int) -> Bool {
        return cloudService.isFavorite(foodItemId: foodItemId)
    }
    
    func getFoodDetails(fdcId: Int, completion: @escaping (Result<ProcessedFoodItem, Error>) -> Void) {
        Task {
            do {
                let cloudFood = try await cloudService.getFoodDetails(fdcId: fdcId)
                let processedFood = cloudFood.toProcessedFoodItem()
                completion(.success(processedFood))
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Private Methods
    
    /// Rank search results intelligently based on query and food properties
    private func rankSearchResults(_ foods: [ProcessedFoodItem], query: String) -> [ProcessedFoodItem] {
        print("🎯 [RANK] Starting to rank \(foods.count) foods")
        
        guard !foods.isEmpty else {
            print("⚠️ [RANK] No foods to rank, returning empty array")
            return []
        }
        
        let normalizedQuery = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        print("🔄 [RANK] Normalized query: '\(normalizedQuery)'")
        
        print("🔄 [RANK] Starting sort...")
        let sorted = foods.sorted { food1, food2 in
            let score1 = calculateRelevanceScore(food: food1, query: normalizedQuery)
            let score2 = calculateRelevanceScore(food: food2, query: normalizedQuery)
            return score1 < score2 // Lower score = better match
        }
        
        print("✅ [RANK] Sort complete! Top 5:")
        for (i, food) in sorted.prefix(5).enumerated() {
            let isGeneric = food.brandName?.isEmpty ?? true
            let score = calculateRelevanceScore(food: food, query: normalizedQuery)
            print("  \(i+1). \(food.name) - Generic: \(isGeneric), dataType: \(food.dataType ?? "?"), score: \(score)")
        }
        
        return sorted
    }
    
    /// Calculate relevance score for ranking (lower = better)
    /// Uses a multi-factor scoring: user history > commonality > data quality > query match
    private func calculateRelevanceScore(food: ProcessedFoodItem, query: String) -> Int {
        let nameText = food.name.lowercased()
        let category = (food.category ?? "").lowercased()
        let dataType = food.dataType ?? ""
        var score = 0
        
        // Normalize query for comparison (remove commas, extra spaces)
        let normalizedName = nameText.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespaces)
        let normalizedQuery = query.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespaces)
        
        // Check if all query words appear in name
        let queryWords = normalizedQuery.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        let nameWords = normalizedName.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        let allQueryWordsMatch = queryWords.allSatisfy { queryWord in
            nameWords.contains { $0.contains(queryWord) || queryWord.contains($0) }
        }
        
        // ═══ TIER 0: USER PERSONAL HISTORY (highest priority) ═══
        
        // PRIORITY 0a: USER'S FREQUENTLY LOGGED FOODS
        let usageCount = cloudService.getUsageCount(fdcId: food.id, foodName: food.name)
        if usageCount > 0 {
            score -= 600000 + (usageCount * 2000)  // More usage = higher rank
        }
        
        // PRIORITY 0b: FAVORITED FOODS
        if isFavorite(foodItemId: food.id) {
            score -= 550000
        }
        
        // ═══ TIER 1: QUERY RELEVANCE ═══
        
        // PRIORITY 1: EXACT QUERY MATCH
        if normalizedName == normalizedQuery {
            score -= 400000
        } else if allQueryWordsMatch && queryWords.count >= 2 {
            score -= 300000
        }
        
        // ═══ TIER 2: COMMONALITY - Most commonly eaten forms first ═══
        
        // PRIORITY 2a: Cooked/prepared forms rank ABOVE raw for proteins & grains
        let cookedKeywords = ["cooked", "grilled", "baked", "roasted", "steamed", "boiled", "poached", "sauteed"]
        let rawKeywords = ["raw", "uncooked", "unprepared"]
        let isCookedForm = cookedKeywords.contains(where: { nameText.contains($0) })
        let isRawForm = rawKeywords.contains(where: { nameText.contains($0) })
        
        // For proteins and grains, cooked is far more commonly tracked
        let isProteinOrGrain = category.contains("poultry") || category.contains("beef") || category.contains("pork") ||
                               category.contains("fish") || category.contains("seafood") || category.contains("egg") ||
                               category.contains("grain") || category.contains("rice") || category.contains("pasta") ||
                               nameText.contains("chicken") || nameText.contains("turkey") || nameText.contains("salmon") ||
                               nameText.contains("rice") || nameText.contains("oatmeal")
        
        if isProteinOrGrain {
            if isCookedForm { score -= 250000 }  // Cooked chicken breast > raw
            else if isRawForm { score += 20000 }  // Raw forms rank lower
        }
        
        // PRIORITY 2b: Common staple food forms
        let highCommonalityTerms = ["boneless", "skinless", "lean", "plain", "nonfat", "low fat", "2%"]
        if highCommonalityTerms.contains(where: { nameText.contains($0) }) {
            score -= 30000
        }
        
        // ═══ TIER 3: DATA QUALITY ═══
        
        // PRIORITY 3a: FOUNDATION FOODS from USDA (lab-verified, most accurate)
        if dataType == "Foundation" {
            score -= 200000
        } else if dataType == "SR Legacy" {
            score -= 150000
        }
        
        // PRIORITY 3b: Generic foods over branded
        if food.brandName?.isEmpty ?? true {
            score -= 100000
        } else {
            score += 100000
        }
        
        // ═══ TIER 4: QUERY MATCH QUALITY ═══
        
        // PRIORITY 4: Starts with query
        if normalizedName.hasPrefix(normalizedQuery) || nameText.hasPrefix(query) {
            score -= 80000
        }
        
        // PRIORITY 5: WHOLE FOOD categories
        let wholeFoodCategories = ["fruits", "vegetables", "poultry", "beef", "pork", "lamb", "fish",
                                   "seafood", "eggs", "nuts", "seeds", "grains", "legumes"]
        let isWholeFoodCategory = wholeFoodCategories.contains(where: { category.contains($0) })
        let meatCuts = ["breast", "thigh", "drumstick", "wing", "leg", "tenderloin", "loin",
                       "chop", "steak", "roast", "ribs", "ground", "filet", "fillet"]
        let isMeatCut = meatCuts.contains(where: { nameText.contains($0) })
        
        if isWholeFoodCategory || isMeatCut {
            score -= 50000
        }
        
        // ═══ TIER 5: PENALTIES ═══
        
        // Non-food items
        let nonWholeFoodTypes = ["beverage", "drink", "juice", "soda", "tea", "coffee", "smoothie",
                                 "shake", "supplement", "baby food", "infant formula", "meal replacement",
                                 "energy drink", "sports drink"]
        if nonWholeFoodTypes.contains(where: { nameText.contains($0) || category.contains($0) }) {
            score += 80000
        }
        
        // Pre-packaged
        let prePackagedKeywords = ["pre-packaged", "prepackaged", "frozen", "canned", "jarred",
                                   "packaged", "mix", "instant", "ready-to-eat"]
        if prePackagedKeywords.contains(where: { nameText.contains($0) || category.contains($0) }) {
            score += 70000
        }
        
        // Complex prepared dishes
        let preparedKeywords = ["benedict", "burrito", "sandwich", "casserole",
                                "deviled", "creamed", "frittata", "quiche", "souffle",
                                "foo young", "stir-fry", "stew", "curry",
                                "lasagna", "breaded", "stuffed", "marinated", "glazed"]
        if preparedKeywords.contains(where: { nameText.contains($0) }) {
            score += 60000
        }
        
        // Basic descriptors bonus
        let basicDescriptors = ["grade a", "grade aa", "large", "medium", "small",
                               "organic", "boneless", "skinless", "bone-in"]
        if basicDescriptors.contains(where: { nameText.contains($0) }) {
            score -= 5000
        }
        
        // Contains query bonus
        if nameText.contains(query) {
            score -= 10000
        }
        
        // Simplicity (fewer words = simpler = better)
        let wordCount = nameText.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.count
        score += wordCount * 100
        
        return score
    }
    
    private func processSearchResults(_ foods: [USDAFoodItem], query: String) {
        let normalizedQuery = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !normalizedQuery.isEmpty else {
            searchResults = []
            return
        }

        let brandKeywords: [String] = [
            "tyson", "perdue", "foster farms", "jennie o", "oscar mayer", "jimmy dean", "hillshire",
            "hormel", "kirkland", "great value", "members mark", "member's mark", "trader joe",
            "whole foods", "365", "wegmans", "publix", "aldi", "lidl", "heb", "meijer", "costco",
            "walmart", "target", "safeway", "kroger", "sprouts", "central market", "randalls",
            "molly", "organic valley", "horizon", "fairlife", "silk", "almond breeze", "oatly",
            "chobani", "fage", "yoplait", "oikos", "dannon", "siggi", "activia", "yoplait",
            "bob's red mill", "arrowhead mills", "quaker", "nature's path", "kashi", "cheerios",
            "kellogg", "general mills", "post", "nestle", "hershey", "mars", "snicker", "snickers",
            "twix", "kit kat", "kitkat", "m&m", "reeses", "oreo", "chips ahoy", "dorito", "doritos",
            "cheeto", "cheetos", "frito", "tostitos", "ruffles", "pringles", "lays", "hostess",
            "little debbie", "entemann", "bimbo", "stromboli", "pepperidge farm", "nature valley",
            "kind", "clif", "rxbar", "quest", "pure protein", "muscle milk", "premier protein",
            "bodyarmor", "gatorade", "powerade", "red bull", "monster", "bang", "prime", "starbucks",
            "dunkin", "tim hortons", "pepsi", "coke", "cola", "sprite", "dr pepper", "7-up",
            "taco bell", "chipotle", "mcdonald", "mcdonald's", "burger king", "wendy's", "panera",
            "panera bread", "subway", "quiznos", "kfc", "papa john", "domino", "pizza hut",
            "foster dairy", "tyson foods", "oscar meyer", "just", "just egg", "justegg"
        ]

        let junkKeywords: [String] = [
            "candy", "chocolate", "sweet", "dessert", "snack", "bar", "cookie", "cake", "pie",
            "ice cream", "brownie", "fudge", "sundae", "gummy", "marshmallow", "soda",
            "energy drink", "frappe", "frappuccino", "shake", "donut", "doughnut", "pastry",
            "frosting", "milkshake", "caramel", "syrup"
        ]

        let wholeFoodKeywords: [String] = [
            "raw", "fresh", "whole", "boneless", "skinless", "breast", "tenderloin", "fillet",
            "filet", "loin", "lean", "ground", "uncooked", "cooked", "plain", "unsalted", "steamed",
            "roasted", "grilled", "baked", "boiled", "poached", "pastured", "organic", "large",
            "medium", "small", "cage free"
        ]

        let produceCategoryHints: [String] = [
            "vegetable", "vegetables", "fruit", "fruits", "berry", "berries", "produce", "meat",
            "poultry", "chicken", "beef", "pork", "seafood", "fish", "egg", "eggs", "dairy", "grain",
            "grains", "rice", "oat", "oats", "bean", "beans", "lentil", "legume", "legumes", "nut",
            "nuts", "seed", "seeds", "yogurt", "cheese", "milk", "greens", "spinach", "kale",
            "broccoli", "pepper", "lettuce", "apple", "banana", "carrot", "potato", "sweet potato"
        ]

        func tokenize(_ text: String) -> [String] {
            text
                .lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
        }

        func singularize(_ word: String) -> String {
            if word.hasSuffix("ies") {
                return String(word.dropLast(3)) + "y"
            }
            if word.hasSuffix("es") {
                return String(word.dropLast(2))
            }
            if word.hasSuffix("s") {
                return String(word.dropLast())
            }
            return word
        }

        func containsAny(_ text: String, keywords: [String]) -> Bool {
            guard !text.isEmpty else { return false }
            return keywords.contains { keyword in
                text.contains(keyword)
            }
        }

        let queryTokens = tokenize(normalizedQuery)
        let singularQueryTokens = queryTokens.map(singularize)
        let queryTokenSet = Set(queryTokens + singularQueryTokens + [normalizedQuery])
        let primaryToken = singularQueryTokens.first ?? normalizedQuery

        let queryBrandKeywords = brandKeywords.filter { normalizedQuery.contains($0) }
        let isBrandQuery = !queryBrandKeywords.isEmpty

        func isGenericItem(_ item: USDAFoodItem) -> Bool {
            let brandName = item.brandName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let brandOwner = item.brandOwner?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let isGeneric = brandName.isEmpty && brandOwner.isEmpty
            
            // Debug: Print first 10 items to see what's happening
            if foods.firstIndex(where: { $0.fdcId == item.fdcId }) ?? 0 < 10 {
                print("🔍 Item: \(item.description)")
                print("   dataType: \(item.dataType)")
                print("   brandName: \(brandName.isEmpty ? "NONE" : brandName)")
                print("   brandOwner: \(brandOwner.isEmpty ? "NONE" : brandOwner)")
                print("   isGeneric: \(isGeneric)")
            }
            
            return isGeneric
        }

        func getGenericTier(_ item: USDAFoodItem) -> Int {
            if item.dataType == "Foundation" || item.dataType == "SR Legacy" { return 0 }
            if item.dataType == "Survey (FNDDS)" && isGenericItem(item) { return 1 }
            return 2
        }

        func matchesQueryBrand(_ item: USDAFoodItem, nameText: String) -> Bool {
            guard !queryBrandKeywords.isEmpty else { return false }
            let brandFieldText = [item.brandName ?? "", item.brandOwner ?? ""]
                .joined(separator: " ")
                .lowercased()
            if containsAny(nameText, keywords: queryBrandKeywords) { return true }
            return containsAny(brandFieldText, keywords: queryBrandKeywords)
        }

        func brandIntentScore(for item: USDAFoodItem, nameText: String) -> Int {
            let hasBrand = !isGenericItem(item)
            let brandFieldText = [item.brandName ?? "", item.brandOwner ?? ""]
                .joined(separator: " ")
                .lowercased()
            let brandMention = containsAny(nameText, keywords: brandKeywords) ||
                containsAny(brandFieldText, keywords: brandKeywords)
            let matchesBrand = matchesQueryBrand(item, nameText: nameText)
            
            let score: Int
            if isBrandQuery {
                // User is searching for a brand - prioritize matching brands
                if matchesBrand { score = 0 }
                else { score = hasBrand ? 1 : 2 }
            } else {
                // User wants generic items - heavily penalize ANY branded item
                if !hasBrand { score = 0 }  // Generic item - best score
                else { score = 1000 }  // Any branded item - sink to bottom
            }
            
            // Debug: Print scoring for first few items
            if foods.firstIndex(where: { $0.fdcId == item.fdcId }) ?? 0 < 10 {
                print("   brandScore: \(score) (hasBrand: \(hasBrand), isBrandQuery: \(isBrandQuery))")
            }
            
            return score
        }

        func junkScore(nameText: String, categoryText: String) -> Int {
            if containsAny(categoryText, keywords: junkKeywords) { return 2 }
            if containsAny(nameText, keywords: junkKeywords) { return 2 }
            return 0
        }

        func categoryScore(categoryText: String) -> Int {
            guard !categoryText.isEmpty else { return 4 }
            // Exact category match (e.g., "egg" search → "Dairy and Egg Products" category)
            if categoryText.contains(primaryToken) { return 0 }
            // Good food categories
            if produceCategoryHints.contains(where: categoryText.contains) { return 1 }
            // Unknown/processed categories
            return 3
        }

        func queryAffinityScore(nameText: String, nameTokens: [String]) -> Int {
            if nameText == normalizedQuery { return 0 }
            if nameText.hasPrefix(normalizedQuery) || nameText.hasPrefix(primaryToken) { return 1 }
            if nameTokens.contains(where: { queryTokenSet.contains($0) }) { return 2 }
            if nameText.contains(normalizedQuery) { return 3 }
            return 4
        }

        func wholeFoodScore(nameText: String) -> Int {
            containsAny(nameText, keywords: wholeFoodKeywords) ? 0 : 1
        }

        func sortKey(for item: USDAFoodItem, originalIndex: Int) -> (Int, Int, Int, Int, Int, Int, Int, Int, Int) {
            let nameText = item.description.lowercased()
            let categoryText = (item.foodCategory ?? "").lowercased()
            let nameTokens = tokenize(nameText)

            let brandScore = brandIntentScore(for: item, nameText: nameText)
            let junk = junkScore(nameText: nameText, categoryText: categoryText)
            let category = categoryScore(categoryText: categoryText)
            let tier = getGenericTier(item)
            let affinity = queryAffinityScore(nameText: nameText, nameTokens: nameTokens)
            let wholeFood = wholeFoodScore(nameText: nameText)
            let complexity = nameTokens.count
            let exactMatch = nameText == normalizedQuery ? 0 : 1

            return (brandScore, junk, tier, category, affinity, wholeFood, complexity, exactMatch, originalIndex)
        }

        print("🔍 Total foods returned by API: \(foods.count)")
        let genericCount = foods.filter { isGenericItem($0) }.count
        let brandedCount = foods.count - genericCount
        print("🔍 Generic items: \(genericCount), Branded items: \(brandedCount)")
        
        let rankedFoods = foods.enumerated()
            .sorted { lhs, rhs in
                let leftKey = sortKey(for: lhs.element, originalIndex: lhs.offset)
                let rightKey = sortKey(for: rhs.element, originalIndex: rhs.offset)
                
                // Compare each element of the tuple manually
                if leftKey.0 != rightKey.0 { return leftKey.0 < rightKey.0 }
                if leftKey.1 != rightKey.1 { return leftKey.1 < rightKey.1 }
                if leftKey.2 != rightKey.2 { return leftKey.2 < rightKey.2 }
                if leftKey.3 != rightKey.3 { return leftKey.3 < rightKey.3 }
                if leftKey.4 != rightKey.4 { return leftKey.4 < rightKey.4 }
                if leftKey.5 != rightKey.5 { return leftKey.5 < rightKey.5 }
                if leftKey.6 != rightKey.6 { return leftKey.6 < rightKey.6 }
                if leftKey.7 != rightKey.7 { return leftKey.7 < rightKey.7 }
                return leftKey.8 < rightKey.8
            }
            .map { $0.element }
        
        print("🔍 After sorting, first 5 items:")
        for (index, food) in rankedFoods.prefix(5).enumerated() {
            let isGen = isGenericItem(food)
            print("   \(index + 1). \(food.description) - Generic: \(isGen)")
        }
        
        var uniqueIDs = Set<Int>()
        
        let processed = rankedFoods.compactMap { food -> ProcessedFoodItem? in
            // Ensure uniqueness
            guard !uniqueIDs.contains(food.fdcId) else { return nil }
            uniqueIDs.insert(food.fdcId)
            
            guard let nutrients = food.foodNutrients else { return nil }
            
            let nutrition = extractNutritionInfo(from: nutrients)
            let servingSize = max(0.1, food.servingSize ?? 100.0) // Prevent zero division
            let servingUnit = food.servingSizeUnit ?? "g"
            
            return ProcessedFoodItem(
                id: food.fdcId,
                name: food.description,
                brandName: food.brandName,
                description: food.description,
                category: food.foodCategory,
                servingSize: servingSize,
                servingUnit: servingUnit,
                nutrition: nutrition,
                portions: [],
                dataType: food.dataType
            )
        }
        
        searchResults = processed
    }
    
    private func processDetailedFood(_ food: USDAFoodDetailsResponse) -> ProcessedFoodItem {
        let nutrition = extractDetailedNutritionInfo(from: food.foodNutrients)
        let portions = food.foodPortions?.map { portion in
            FoodPortion(
                id: portion.id,
                amount: portion.amount,
                unit: portion.measureUnit.name,
                gramWeight: portion.gramWeight,
                description: portion.modifier
            )
        } ?? []
        
        let servingSize = max(0.1, food.servingSize ?? 100.0) // Prevent zero division
        let servingUnit = food.servingSizeUnit ?? "g"
        
        return ProcessedFoodItem(
            id: food.fdcId,
            name: food.description,
            brandName: food.brandName,
            description: food.description,
            category: food.foodCategory?.description,
            servingSize: servingSize,
            servingUnit: servingUnit,
            nutrition: nutrition,
            portions: portions,
            dataType: food.dataType
        )
    }
    
    private func extractNutritionInfo(from nutrients: [USDANutrient]) -> NutritionInfo {
        var calories: Double = 0
        var protein: Double = 0
        var carbs: Double = 0
        var fat: Double = 0
        var saturatedFat: Double = 0
        var fiber: Double = 0
        var sugar: Double = 0
        var sodium: Double = 0
        var cholesterol: Double = 0
        var calcium: Double = 0
        var iron: Double = 0
        var vitaminC: Double = 0
        
        for nutrient in nutrients {
            switch nutrient.nutrientNumber {
            case "208": calories = nutrient.value // Energy (kcal)
            case "203": protein = nutrient.value // Protein
            case "205": carbs = nutrient.value // Carbohydrate, by difference
            case "204": fat = nutrient.value // Total lipid (fat)
            case "606": saturatedFat = nutrient.value // Fatty acids, total saturated
            case "291": fiber = nutrient.value // Fiber, total dietary
            case "269": sugar = nutrient.value // Sugars, total including NLEA
            case "307": sodium = nutrient.value // Sodium, Na
            case "601": cholesterol = nutrient.value // Cholesterol
            case "301": calcium = nutrient.value // Calcium, Ca
            case "303": iron = nutrient.value // Iron, Fe
            case "401": vitaminC = nutrient.value // Vitamin C, total ascorbic acid
            default: break
            }
        }
        
        return NutritionInfo(
            calories: calories,
            protein: protein,
            carbohydrates: carbs,
            totalFat: fat,
            saturatedFat: saturatedFat,
            fiber: fiber,
            sugar: sugar,
            sodium: sodium,
            cholesterol: cholesterol,
            calcium: calcium,
            iron: iron,
            vitaminC: vitaminC
        )
    }
    
    private func extractDetailedNutritionInfo(from nutrients: [USDADetailedNutrient]) -> NutritionInfo {
        var calories: Double = 0
        var protein: Double = 0
        var carbs: Double = 0
        var fat: Double = 0
        var saturatedFat: Double = 0
        var fiber: Double = 0
        var sugar: Double = 0
        var sodium: Double = 0
        var cholesterol: Double = 0
        var calcium: Double = 0
        var iron: Double = 0
        var vitaminC: Double = 0
        
        for nutrient in nutrients {
            switch nutrient.nutrient.number {
            case "208": calories = nutrient.amount // Energy (kcal)
            case "203": protein = nutrient.amount // Protein
            case "205": carbs = nutrient.amount // Carbohydrate, by difference
            case "204": fat = nutrient.amount // Total lipid (fat)
            case "606": saturatedFat = nutrient.amount // Fatty acids, total saturated
            case "291": fiber = nutrient.amount // Fiber, total dietary
            case "269": sugar = nutrient.amount // Sugars, total including NLEA
            case "307": sodium = nutrient.amount // Sodium, Na
            case "601": cholesterol = nutrient.amount // Cholesterol
            case "301": calcium = nutrient.amount // Calcium, Ca
            case "303": iron = nutrient.amount // Iron, Fe
            case "401": vitaminC = nutrient.amount // Vitamin C, total ascorbic acid
            default: break
            }
        }
        
        return NutritionInfo(
            calories: calories,
            protein: protein,
            carbohydrates: carbs,
            totalFat: fat,
            saturatedFat: saturatedFat,
            fiber: fiber,
            sugar: sugar,
            sodium: sodium,
            cholesterol: cholesterol,
            calcium: calcium,
            iron: iron,
            vitaminC: vitaminC
        )
    }
    
    private func handleSearchError(_ message: String) {
        searchError = message
        searchResults = []
        print("USDA API Error: \(message)")
    }
}

// MARK: - Errors

enum USDAError: LocalizedError {
    case invalidURL
    case noData
    case decodingError
    case networkError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .noData:
            return "No data received"
        case .decodingError:
            return "Failed to decode response"
        case .networkError(let message):
            return "Network error: \(message)"
        }
    }
}
