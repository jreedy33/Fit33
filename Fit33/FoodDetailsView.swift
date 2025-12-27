import SwiftUI

struct FoodDetailsView: View {
    let food: ProcessedFoodItem
    let mealType: MealType
    let onAdd: (FoodEntry) -> Void
    let onDismiss: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedPortion: FoodPortion?
    @State private var customAmount: String = "1"
    @State private var showingCustomAmount = false
    @State private var isLoading = false
    @State private var showDetailedNutrition: Bool
    
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
    }
    
    private var currentNutrition: NutritionInfo {
        let amount = Double(customAmount) ?? 1.0
        let baseServing = max(0.1, food.servingSize)
        
        if let portion = selectedPortion {
            let portionWeight = max(0.1, portion.gramWeight)
            return food.nutrition.perServing(servingSize: amount * portionWeight, servingUnit: portion.unit, originalServingSize: baseServing)
        } else {
            // Use smart serving weight if applicable
            let servingWeight = smartServingWeight ?? baseServing
            return food.nutrition.perServing(servingSize: amount * servingWeight, servingUnit: food.servingUnit, originalServingSize: baseServing)
        }
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
                    
                    Image(systemName: foodIcon)
                        .font(.system(size: 24))
                        .foregroundColor(.white)
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
            
            // Serving Size Section
            HStack {
                Text("Serving Size")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Amount input
                HStack(spacing: 8) {
                    TextField("1", text: $customAmount)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 50)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(.systemGray6))
                        )
                    
                    Text(smartServingUnit)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(minWidth: 50, alignment: .leading)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            
            // Portion Chips
            if !food.portions.isEmpty || hasSmartPortions {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        // Smart default serving
                        PortionChip(
                            title: smartDefaultPortionLabel,
                            isSelected: selectedPortion == nil
                        ) {
                            selectedPortion = nil
                            customAmount = "1"
                        }
                        
                        // Per 100g option
                        if food.servingSize != 100 {
                            PortionChip(
                                title: "100g",
                                isSelected: false
                            ) {
                                selectedPortion = FoodPortion(id: -1, amount: 1, unit: "g", gramWeight: 100, description: nil)
                                customAmount = "1"
                            }
                        }
                        
                        ForEach(food.portions.prefix(4)) { portion in
                            PortionChip(
                                title: portion.displayText,
                                isSelected: selectedPortion?.id == portion.id
                            ) {
                                selectedPortion = portion
                                customAmount = "1"
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 14)
                }
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
    
    // MARK: - Smart Serving Unit System
    
    /// Detects the food type and returns a contextual serving unit
    private var smartServingUnit: String {
        if let portion = selectedPortion {
            return portion.unit
        }
        
        let name = food.displayName.lowercased()
        let category = food.category?.lowercased() ?? ""
        
        // Eggs
        if name.contains("egg") && !name.contains("eggplant") {
            return "egg"
        }
        
        // Sliced items
        if name.contains("bread") || name.contains("toast") {
            return "slice"
        }
        if name.contains("bacon") {
            return "strip"
        }
        if name.contains("pizza") {
            return "slice"
        }
        
        // Whole fruits
        if category.contains("fruit") {
            if name.contains("banana") { return "banana" }
            if name.contains("apple") { return "apple" }
            if name.contains("orange") { return "orange" }
            if name.contains("peach") { return "peach" }
            if name.contains("pear") { return "pear" }
            if name.contains("plum") { return "plum" }
            if name.contains("kiwi") { return "kiwi" }
            if name.contains("avocado") { return "avocado" }
            if name.contains("lemon") { return "lemon" }
            if name.contains("lime") { return "lime" }
            if name.contains("mango") { return "mango" }
        }
        
        // Beverages
        if category.contains("beverage") || name.contains("juice") || name.contains("milk") || name.contains("coffee") || name.contains("tea") {
            return "cup"
        }
        
        // Yogurt & Dairy cups
        if name.contains("yogurt") || name.contains("skyr") {
            return "container"
        }
        
        // Prepared foods
        if name.contains("pancake") { return "pancake" }
        if name.contains("waffle") { return "waffle" }
        if name.contains("hot dog") { return "hot dog" }
        if name.contains("hamburger") || name.contains("burger") { return "burger" }
        if name.contains("taco") { return "taco" }
        if name.contains("burrito") { return "burrito" }
        if name.contains("bagel") { return "bagel" }
        if name.contains("muffin") { return "muffin" }
        if name.contains("croissant") { return "croissant" }
        if name.contains("tortilla") { return "tortilla" }
        
        // Chicken pieces
        if name.contains("drumstick") { return "drumstick" }
        if name.contains("wing") { return "wing" }
        if name.contains("thigh") { return "thigh" }
        if name.contains("breast") { return "breast" }
        
        // Nuts & Seeds - use tablespoon or handful
        if category.contains("nut") || category.contains("seed") {
            return "oz"
        }
        
        // Cheese
        if name.contains("cheese") {
            if name.contains("string") { return "stick" }
            if name.contains("cottage") { return "cup" }
            return "oz"
        }
        
        // Butter, oils - use tablespoon
        if name.contains("butter") || name.contains("oil") || name.contains("ghee") {
            return "tbsp"
        }
        
        // Condiments
        if name.contains("ketchup") || name.contains("mustard") || name.contains("mayo") || 
           name.contains("sauce") || name.contains("dressing") || name.contains("honey") ||
           name.contains("syrup") {
            return "tbsp"
        }
        
        // Protein powder
        if name.contains("protein powder") || name.contains("whey") || name.contains("casein") {
            return "scoop"
        }
        
        // Cooked grains - use cup
        if name.contains("rice") || name.contains("quinoa") || name.contains("oatmeal") || 
           name.contains("pasta") || name.contains("couscous") {
            if name.contains("cooked") || !name.contains("dry") {
                return "cup"
            }
        }
        
        // Beans & legumes
        if category.contains("legume") || name.contains("beans") || name.contains("lentils") || name.contains("chickpeas") {
            return "cup"
        }
        
        // Default to grams
        return "g"
    }
    
    /// Returns the approximate weight for one "smart" serving
    private var smartServingWeight: Double? {
        let name = food.displayName.lowercased()
        let category = food.category?.lowercased() ?? ""
        
        // Eggs - 1 large egg ≈ 50g
        if name.contains("egg") && !name.contains("eggplant") {
            return 50
        }
        
        // Bread slice ≈ 30g
        if name.contains("bread") || name.contains("toast") {
            return 30
        }
        
        // Bacon strip ≈ 8g
        if name.contains("bacon") {
            return 8
        }
        
        // Fruits
        if category.contains("fruit") {
            if name.contains("banana") { return 118 }
            if name.contains("apple") { return 182 }
            if name.contains("orange") { return 131 }
            if name.contains("avocado") { return 150 } // half
        }
        
        // Chicken pieces
        if name.contains("drumstick") { return 95 }
        if name.contains("wing") { return 34 }
        if name.contains("thigh") { return 116 }
        if name.contains("breast") { return 174 }
        
        // Use default food serving size
        return nil
    }
    
    private var hasSmartPortions: Bool {
        smartServingUnit != "g"
    }
    
    private var smartDefaultPortionLabel: String {
        let unit = smartServingUnit
        if unit == "g" {
            return "\(formatAmount(food.servingSize))g"
        }
        return "1 \(unit)"
    }
    
    private var currentServingUnit: String {
        selectedPortion?.unit ?? smartServingUnit
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
    
    // MARK: - Methods
    
    private func addFoodToMeal() {
        let amount = Double(customAmount) ?? 1.0
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
            ]
        ),
        mealType: .lunch,
        onAdd: { _ in },
        onDismiss: { }
    )
}
