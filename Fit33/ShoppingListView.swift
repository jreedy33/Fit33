import SwiftUI

// MARK: - Shopping List Sheet
struct ShoppingListSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var advancedService = SpoonacularAdvancedService.shared
    @StateObject private var spoonacularService = SpoonacularService.shared
    
    @State private var shoppingList: [ShoppingAisle] = []
    @State private var isGenerating = false
    @State private var selectedRecipeIds: Set<Int> = []
    @State private var showRecipePicker = false
    
    var body: some View {
        NavigationView {
            ZStack {
                (colorScheme == .dark ? Color.black : Color(white: 0.95))
                    .ignoresSafeArea()
                
                if shoppingList.isEmpty && !isGenerating {
                    emptyState
                } else if isGenerating {
                    ProgressView("Generating list...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    shoppingListContent
                }
            }
            .navigationTitle("Shopping List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !shoppingList.isEmpty {
                        Button(action: shareList) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
            .sheet(isPresented: $showRecipePicker) {
                RecipePickerSheet(
                    selectedIds: $selectedRecipeIds,
                    onGenerate: generateList
                )
            }
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.purple, .pink],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                    .shadow(color: .purple.opacity(0.4), radius: 10, x: 0, y: 5)
                
                Image(systemName: "cart.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            Text("Shopping List")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Generate a shopping list from\nyour favorite recipes")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button(action: { showRecipePicker = true }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Select Recipes")
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(colors: [.purple, .pink], startPoint: .leading, endPoint: .trailing)
                )
                .cornerRadius(14)
            }
        }
        .padding()
    }
    
    private var shoppingListContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Summary header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(totalItems) items")
                            .font(.headline)
                            .fontWeight(.bold)
                        
                        Text("\(checkedItems) checked off")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button(action: { showRecipePicker = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                            Text("Add Recipes")
                        }
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.purple)
                    }
                }
                .padding(.horizontal)
                
                // Aisles
                ForEach($shoppingList) { $aisle in
                    AisleSection(aisle: $aisle)
                }
            }
            .padding(.vertical)
        }
    }
    
    private var totalItems: Int {
        shoppingList.reduce(0) { $0 + $1.items.count }
    }
    
    private var checkedItems: Int {
        shoppingList.reduce(0) { $0 + $1.items.filter { $0.isChecked }.count }
    }
    
    private func generateList() {
        guard !selectedRecipeIds.isEmpty else { return }
        
        isGenerating = true
        
        Task {
            let list = await advancedService.generateShoppingList(recipeIds: Array(selectedRecipeIds))
            
            await MainActor.run {
                shoppingList = list
                isGenerating = false
            }
        }
    }
    
    private func shareList() {
        var listText = "🛒 Shopping List\n\n"
        
        for aisle in shoppingList {
            listText += "📍 \(aisle.name)\n"
            for item in aisle.items {
                let checkbox = item.isChecked ? "✅" : "⬜️"
                listText += "\(checkbox) \(item.name) - \(item.formattedAmount)\n"
            }
            listText += "\n"
        }
        
        let activityVC = UIActivityViewController(
            activityItems: [listText],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
}

// MARK: - Aisle Section
struct AisleSection: View {
    @Binding var aisle: ShoppingAisle
    @Environment(\.colorScheme) private var colorScheme
    @State private var isExpanded = true
    
    private var aisleIcon: String {
        switch aisle.name.lowercased() {
        case let name where name.contains("produce"): return "leaf.fill"
        case let name where name.contains("meat"): return "fork.knife"
        case let name where name.contains("dairy"): return "cup.and.saucer.fill"
        case let name where name.contains("bakery"): return "birthday.cake.fill"
        case let name where name.contains("frozen"): return "snowflake"
        case let name where name.contains("spice"): return "flame.fill"
        case let name where name.contains("baking"): return "takeoutbag.and.cup.and.straw.fill"
        case let name where name.contains("canned"): return "shippingbox.fill"
        case let name where name.contains("pasta"): return "fork.knife.circle.fill"
        default: return "cart.fill"
        }
    }
    
    private var aisleColor: Color {
        switch aisle.name.lowercased() {
        case let name where name.contains("produce"): return .green
        case let name where name.contains("meat"): return .red
        case let name where name.contains("dairy"): return .blue
        case let name where name.contains("bakery"): return .orange
        case let name where name.contains("frozen"): return .cyan
        case let name where name.contains("spice"): return .yellow
        default: return .purple
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(aisleColor.opacity(0.2))
                            .frame(width: 36, height: 36)
                        
                        Image(systemName: aisleIcon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(aisleColor)
                    }
                    
                    Text(aisle.name)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Text("\(aisle.items.count)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(14)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Items
            if isExpanded {
                Divider()
                    .padding(.horizontal)
                
                VStack(spacing: 0) {
                    ForEach($aisle.items) { $item in
                        ShoppingItemRow(item: $item)
                        
                        if item.id != aisle.items.last?.id {
                            Divider()
                                .padding(.leading, 50)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(white: 0.12) : Color.white)
        )
        .padding(.horizontal)
    }
}

// MARK: - Shopping Item Row
struct ShoppingItemRow: View {
    @Binding var item: ShoppingIngredient
    
    var body: some View {
        HStack(spacing: 12) {
            Button(action: { item.isChecked.toggle() }) {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(item.isChecked ? .green : .secondary)
            }
            .buttonStyle(PlainButtonStyle())
            
            Text(item.name.capitalized)
                .font(.subheadline)
                .foregroundColor(item.isChecked ? .secondary : .primary)
                .strikethrough(item.isChecked)
            
            Spacer()
            
            Text(item.formattedAmount)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// MARK: - Recipe Picker Sheet
struct RecipePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var spoonacularService = SpoonacularService.shared
    
    @Binding var selectedIds: Set<Int>
    let onGenerate: () -> Void
    
    var body: some View {
        NavigationView {
            ZStack {
                (colorScheme == .dark ? Color.black : Color(white: 0.95))
                    .ignoresSafeArea()
                
                if spoonacularService.healthyRecipes.isEmpty {
                    ProgressView("Loading recipes...")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(spoonacularService.healthyRecipes) { recipe in
                                RecipeSelectRow(
                                    recipe: recipe,
                                    isSelected: selectedIds.contains(recipe.id),
                                    onToggle: {
                                        if selectedIds.contains(recipe.id) {
                                            selectedIds.remove(recipe.id)
                                        } else {
                                            selectedIds.insert(recipe.id)
                                        }
                                    }
                                )
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Select Recipes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Generate (\(selectedIds.count))") {
                        dismiss()
                        onGenerate()
                    }
                    .fontWeight(.semibold)
                    .disabled(selectedIds.isEmpty)
                }
            }
        }
        .task {
            if spoonacularService.healthyRecipes.isEmpty {
                await spoonacularService.fetchHealthyRecipes()
            }
        }
    }
}

// MARK: - Recipe Select Row
struct RecipeSelectRow: View {
    let recipe: SpoonacularRecipe
    let isSelected: Bool
    let onToggle: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 14) {
                // Checkbox
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundColor(isSelected ? .purple : .secondary)
                
                // Image
                AsyncImage(url: recipe.imageURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.gray.opacity(0.2)
                }
                .frame(width: 50, height: 50)
                .cornerRadius(8)
                
                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(recipe.displayTitle)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    
                    Text("\(recipe.calories) cal • \(recipe.protein)g protein")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(colorScheme == .dark ? Color(white: 0.12) : Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(isSelected ? Color.purple.opacity(0.5) : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - My Shopping List View (Organized by Meal)
struct MyShoppingListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var savedMealsService = SavedMealsService.shared
    
    var body: some View {
        NavigationView {
            ZStack {
                (colorScheme == .dark ? Color.black : Color(white: 0.95))
                    .ignoresSafeArea()
                
                if savedMealsService.shoppingListItems.isEmpty {
                    myEmptyState
                } else {
                    myShoppingListContent
                }
            }
            .navigationTitle("Shopping List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !savedMealsService.shoppingListItems.isEmpty {
                        Menu {
                            Button(role: .destructive, action: {
                                savedMealsService.clearCheckedItems()
                            }) {
                                Label("Clear Checked", systemImage: "checkmark.circle")
                            }
                            
                            Button(role: .destructive, action: {
                                savedMealsService.clearAllShoppingList()
                            }) {
                                Label("Clear All", systemImage: "trash")
                            }
                            
                            Divider()
                            
                            Button(action: shareMyList) {
                                Label("Share List", systemImage: "square.and.arrow.up")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
        }
    }
    
    private var myEmptyState: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.orange, .red],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                    .shadow(color: .orange.opacity(0.4), radius: 10, x: 0, y: 5)
                
                Image(systemName: "cart.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            Text("Shopping List Empty")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Add meals to your shopping list\nfrom the recipe detail page")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
    
    private var myShoppingListContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Summary card
                summaryCard
                
                // Items grouped by MEAL (recipe)
                let groupedByMeal = Dictionary(grouping: savedMealsService.shoppingListItems) { 
                    $0.fromRecipe ?? "Other Items" 
                }
                let sortedMeals = groupedByMeal.keys.sorted()
                
                ForEach(sortedMeals, id: \.self) { mealName in
                    ShoppingMealSection(
                        mealName: mealName,
                        items: groupedByMeal[mealName] ?? []
                    )
                }
            }
            .padding(.vertical)
        }
    }
    
    private var summaryCard: some View {
        HStack(spacing: 16) {
            // Meals count
            VStack(spacing: 4) {
                Text("\(uniqueMealCount)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.orange)
                Text("Meals")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Divider()
                .frame(height: 40)
            
            // Items count
            VStack(spacing: 4) {
                Text("\(savedMealsService.shoppingListItems.count)")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Items")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Divider()
                .frame(height: 40)
            
            // Checked count
            VStack(spacing: 4) {
                Text("\(myCheckedCount)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.green)
                Text("Done")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Progress ring
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 4)
                    .frame(width: 50, height: 50)
                
                Circle()
                    .trim(from: 0, to: progressPercentage)
                    .stroke(
                        LinearGradient(colors: [.green, .mint], startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: 50, height: 50)
                    .rotationEffect(.degrees(-90))
                
                Text("\(Int(progressPercentage * 100))%")
                    .font(.caption2)
                    .fontWeight(.bold)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(white: 0.12) : Color.white)
        )
        .padding(.horizontal)
    }
    
    private var uniqueMealCount: Int {
        Set(savedMealsService.shoppingListItems.compactMap { $0.fromRecipe }).count
    }
    
    private var myCheckedCount: Int {
        savedMealsService.shoppingListItems.filter { $0.isChecked }.count
    }
    
    private var progressPercentage: CGFloat {
        guard !savedMealsService.shoppingListItems.isEmpty else { return 0 }
        return CGFloat(myCheckedCount) / CGFloat(savedMealsService.shoppingListItems.count)
    }
    
    private func shareMyList() {
        var listText = "🛒 My Shopping List\n\n"
        
        let groupedByMeal = Dictionary(grouping: savedMealsService.shoppingListItems) { 
            $0.fromRecipe ?? "Other Items" 
        }
        
        for (meal, items) in groupedByMeal.sorted(by: { $0.key < $1.key }) {
            listText += "🍽️ \(meal)\n"
            for item in items {
                let checkbox = item.isChecked ? "✅" : "⬜️"
                listText += "   \(checkbox) \(item.name.capitalized) - \(item.formattedAmount)\n"
            }
            listText += "\n"
        }
        
        let activityVC = UIActivityViewController(
            activityItems: [listText],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
}

// MARK: - Shopping Meal Section (Expandable)
struct ShoppingMealSection: View {
    let mealName: String
    let items: [ShoppingListItem]
    
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var savedMealsService = SavedMealsService.shared
    @State private var isExpanded = false // Collapsed by default - tap to show ingredients
    
    private var checkedCount: Int {
        items.filter { $0.isChecked }.count
    }
    
    private var allChecked: Bool {
        items.allSatisfy { $0.isChecked }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Meal Header
            Button(action: { withAnimation(.spring(response: 0.3)) { isExpanded.toggle() } }) {
                HStack(spacing: 12) {
                    // Meal icon with completion indicator
                    ZStack {
                        Circle()
                            .fill(
                                allChecked 
                                    ? LinearGradient(colors: [.green, .mint], startPoint: .topLeading, endPoint: .bottomTrailing)
                                    : LinearGradient(colors: [.orange, .red], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .frame(width: 44, height: 44)
                        
                        if allChecked {
                            Image(systemName: "checkmark")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                        } else {
                            Image(systemName: "fork.knife")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(mealName)
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(allChecked ? .secondary : .primary)
                            .strikethrough(allChecked)
                            .lineLimit(2)
                        
                        Text("\(checkedCount)/\(items.count) ingredients")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // Chevron
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.trailing, 4)
                }
                .padding(14)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Ingredients (expandable)
            if isExpanded {
                Divider()
                    .padding(.horizontal)
                
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        ShoppingIngredientRow(item: item)
                        
                        if item.id != items.last?.id {
                            Divider()
                                .padding(.leading, 56)
                        }
                    }
                }
                .padding(.vertical, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(white: 0.12) : Color.white)
                .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        )
        .padding(.horizontal)
    }
}

// MARK: - Shopping Ingredient Row
struct ShoppingIngredientRow: View {
    let item: ShoppingListItem
    
    @ObservedObject private var savedMealsService = SavedMealsService.shared
    
    var body: some View {
        HStack(spacing: 12) {
            // Checkbox
            Button(action: {
                withAnimation(.spring(response: 0.2)) {
                    savedMealsService.toggleShoppingItemChecked(id: item.id)
                }
            }) {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(item.isChecked ? .green : .secondary)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Ingredient name and amount
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name.capitalized)
                    .font(.subheadline)
                    .foregroundColor(item.isChecked ? .secondary : .primary)
                    .strikethrough(item.isChecked)
                
                if let aisle = item.aisle, !aisle.isEmpty {
                    Text(aisle)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Amount
            Text(item.formattedAmount)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            // Delete button
            Button(action: {
                withAnimation {
                    savedMealsService.removeFromShoppingList(id: item.id)
                }
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.subheadline)
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// MARK: - Preview
#Preview {
    ShoppingListSheet()
}
