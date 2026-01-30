import SwiftUI
import Combine

struct FoodSearchView: View {
    let mealType: MealType
    let onAdd: (FoodEntry) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    @StateObject private var foodService = USDAFoodService.shared
    @State private var searchText = ""
    @State private var selectedFood: ProcessedFoodItem?
    @State private var searchDebouncer: Timer?
    @State private var showingQuickAccess = true
    @State private var showingNutritionScanner = false
    @State private var isWaitingForSearch = false  // Track debounce state to prevent flash
    
    var body: some View {
        ZStack {
            // Background gradient matching the app aesthetic
            LinearGradient(
                gradient: Gradient(colors: colorScheme == .dark ? [
                    Color(white: 0.08),
                    Color(white: 0.05),
                    Color.black
                ] : [
                    Color(red: 0.85, green: 0.92, blue: 1.0),
                    Color(red: 0.95, green: 0.97, blue: 1.0),
                    Color.white
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Search Header
                searchHeader
                
                // Search Results
                if foodService.isSearching || isWaitingForSearch {
                    // Show loading while searching OR waiting for debounce
                    if foodService.searchResults.isEmpty {
                        loadingView
                    } else {
                        // Show previous results while searching for new ones
                        searchResultsList
                    }
                } else if let error = foodService.searchError {
                    errorView(error)
                } else if searchText.isEmpty {
                    // Show quick access when no search
                    quickAccessView
                } else if foodService.searchResults.isEmpty {
                    // Only show no results after search has completed (not during debounce)
                    noResultsView
                } else {
                    searchResultsList
                }
            }
        }
        .navigationTitle("Add Food")
        .navigationBarTitleDisplayMode(.inline)
        .background(
            ZStack {
                // Food details navigation
                NavigationLink(
                    destination: Group {
                        if let food = selectedFood {
                            FoodDetailsView(
                                food: food,
                                mealType: mealType,
                                onAdd: onAdd,
                                onDismiss: { 
                                    selectedFood = nil
                                    dismiss()
                                }
                            )
                        }
                    },
                    isActive: Binding(
                        get: { selectedFood != nil },
                        set: { if !$0 { selectedFood = nil } }
                    )
                ) {
                    EmptyView()
                }
                .hidden()
                
                // Nutrition scanner navigation
                NavigationLink(
                    destination: NutritionScannerView(
                        mealType: mealType,
                        onSave: { foodEntry in
                            print("💾 [SEARCH VIEW] Saving scanned nutrition: \(foodEntry.name)")
                            onAdd(foodEntry)
                            showingNutritionScanner = false
                            dismiss()
                        }
                    ),
                    isActive: $showingNutritionScanner
                ) {
                    EmptyView()
                }
                .hidden()
            }
        )
        .scrollDismissesKeyboard(.immediately)
        .onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .onAppear {
            SessionLogManager.shared.logScreen(.foodSearch, metadata: [
                "meal_type": mealType.rawValue
            ])
            // Refresh quick access foods when view appears
            foodService.refreshQuickAccessFoods()
        }
    }
    
    // MARK: - View Components
    
    private var searchHeader: some View {
        VStack(spacing: 16) {
            // Meal Type Badge with modern card design
            HStack(spacing: 12) {
                Circle()
                    .fill(mealTypeColor.opacity(0.15))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: mealTypeIcon)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(mealTypeColor)
                    )
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Adding to")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(mealType.displayName)
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                }
                
                Spacer()
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(colorScheme == .dark ? Color(white: 0.15) : .white)
                    .shadow(color: mealTypeColor.opacity(0.15), radius: 8, x: 0, y: 4)
            )
            .padding(.horizontal)
            .padding(.top, 8)
            
            // Modern Search Bar
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(mealTypeColor)
                
                TextField("Search USDA database...", text: $searchText)
                    .font(.body)
                    .textFieldStyle(PlainTextFieldStyle())
                    .onChange(of: searchText) { newValue in
                        searchDebouncer?.invalidate()
                        
                        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty {
                            // Clear search state when text is empty
                            isWaitingForSearch = false
                        } else {
                            // Mark as waiting for search during debounce
                            isWaitingForSearch = true
                            // Reduced debounce from 500ms to 300ms for snappier feel
                            searchDebouncer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
                                isWaitingForSearch = false  // Search is starting now
                                foodService.searchFoods(query: newValue)
                                
                                // Track food search for recipe recommendations
                                Task { @MainActor in
                                    RecipePreferenceService.shared.trackFoodSearch(query: newValue)
                                }
                            }
                        }
                    }
                
                // Camera button
                Button(action: {
                    print("📸 [SEARCH VIEW] Camera button tapped")
                    showingNutritionScanner = true
                }) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(mealTypeColor)
                        .padding(8)
                        .background(
                            Circle()
                                .fill(mealTypeColor.opacity(0.15))
                        )
                }
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(colorScheme == .dark ? Color(white: 0.15) : .white)
                    .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
            )
            .padding(.horizontal)
        }
        .padding(.bottom, 16)
    }
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            // Modern loading indicator with circle background
            ZStack {
                Circle()
                    .fill(mealTypeColor.opacity(0.1))
                    .frame(width: 100, height: 100)
                
                ProgressView()
                    .scaleEffect(1.5)
                    .progressViewStyle(CircularProgressViewStyle(tint: mealTypeColor))
            }
            
            VStack(spacing: 8) {
                Text("Searching Database")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text("Finding the best results for you...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
    }
    
    private func errorView(_ error: String) -> some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Modern error icon with circle background
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.1))
                    .frame(width: 100, height: 100)
                
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundColor(.orange)
            }
            
            VStack(spacing: 12) {
                Text("Search Error")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text(error)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            Button(action: {
                if !searchText.isEmpty {
                    foodService.searchFoods(query: searchText)
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                    Text("Try Again")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: 200)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(mealTypeColor)
                )
            }
            
            Spacer()
        }
        .padding()
    }
    
    private var emptySearchView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "magnifyingglass.circle")
                .font(.system(size: 64))
                .foregroundColor(.green)
            
            VStack(spacing: 12) {
                Text("Search for Foods")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Enter a food name to search the USDA database with over 400,000 foods")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Try searching for:")
                    .font(.headline)
                    .fontWeight(.medium)
                
                ForEach(sampleSearches, id: \.self) { search in
                    Button(action: { searchText = search }) {
                        HStack {
                            Text(search)
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.left")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.systemGray6))
                        )
                    }
                }
            }
            .padding(.horizontal)
            
            Spacer()
        }
    }
    
    private var quickAccessView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Frequently Used Foods Section (TOP PRIORITY)
                if !foodService.frequentFoods.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Frequently Logged")
                                .font(.headline)
                                .fontWeight(.bold)
                            Spacer()
                            Text("Quick Add")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                        
                        ForEach(foodService.frequentFoods.prefix(6)) { food in
                            QuickAccessFoodRow(food: food, badge: nil) {
                                selectedFood = food
                            }
                        }
                    }
                }
                
                // Recent Foods Section
                if !foodService.recentFoods.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "clock.fill")
                                .foregroundColor(.blue)
                            Text("Recent Foods")
                                .font(.headline)
                                .fontWeight(.bold)
                            Spacer()
                        }
                        .padding(.horizontal)
                        
                        ForEach(foodService.recentFoods.prefix(5)) { food in
                            QuickAccessFoodRow(food: food, badge: "RECENT") {
                                selectedFood = food
                            }
                        }
                    }
                }
                
                // Favorite Foods Section
                if !foodService.favoriteFoods.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "star.fill")
                                .foregroundColor(.yellow)
                            Text("Favorites")
                                .font(.headline)
                                .fontWeight(.bold)
                            Spacer()
                        }
                        .padding(.horizontal)
                        
                        ForEach(foodService.favoriteFoods.prefix(5)) { food in
                            QuickAccessFoodRow(food: food, badge: "FAVORITE") {
                                selectedFood = food
                            }
                        }
                    }
                }
                
                // Popular Foods Section
                if !foodService.popularFoods.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "flame.fill")
                                .foregroundColor(.orange)
                            Text("Popular Foods")
                                .font(.headline)
                                .fontWeight(.bold)
                            Spacer()
                        }
                        .padding(.horizontal)
                        
                        ForEach(foodService.popularFoods.prefix(10)) { food in
                            QuickAccessFoodRow(food: food, badge: nil) {
                                selectedFood = food
                            }
                        }
                    }
                }
                
            }
            .padding(.vertical)
        }
        .scrollDismissesKeyboard(.immediately)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
        )
        .onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }
    
    private var noResultsView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Modern empty state icon with circle background
            ZStack {
                Circle()
                    .fill(Color.gray.opacity(0.1))
                    .frame(width: 100, height: 100)
                
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            
            VStack(spacing: 12) {
                Text("No Results Found")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text("Try a different search term or check your spelling")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            VStack(spacing: 8) {
                Text("Suggestions:")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                ForEach(["Eggs", "Chicken breast", "Brown rice", "Banana"], id: \.self) { suggestion in
                    Button(action: { searchText = suggestion }) {
                        HStack {
                            Text(suggestion)
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.left")
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(colorScheme == .dark ? Color(white: 0.15) : .white)
                                .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
                        )
                    }
                }
            }
            .padding(.horizontal, 32)
            
            Spacer()
        }
        .padding()
    }
    
    private var searchResultsList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(foodService.searchResults) { food in
                    FoodSearchResultRow(food: food) {
                        selectedFood = food
                    }
                }
            }
            .padding()
        }
        .scrollDismissesKeyboard(.immediately)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
        )
        .onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }
    
    // MARK: - Computed Properties
    
    private var mealTypeIcon: String {
        switch mealType {
        case .breakfast: return "sunrise"
        case .lunch: return "sun.max"
        case .dinner: return "sunset"
        case .snacks: return "leaf"
        }
    }
    
    private var mealTypeColor: Color {
        switch mealType {
        case .breakfast: return .orange
        case .lunch: return .yellow
        case .dinner: return .purple
        case .snacks: return .green
        }
    }
    
    private var sampleSearches: [String] {
        ["Eggs", "Chicken breast", "Brown rice", "Banana", "Greek yogurt", "Salmon"]
    }
}

// MARK: - Food Search Result Row

struct FoodSearchResultRow: View {
    let food: ProcessedFoodItem
    let onTap: () -> Void
    
    @StateObject private var foodService = USDAFoodService.shared
    @State private var isFavorite: Bool = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Food Icon
            Image(systemName: foodIcon)
                .font(.title2)
                .foregroundColor(.green)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                // Food Name with star if favorited
                HStack(spacing: 4) {
                    Text(food.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    if isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundColor(.yellow)
                    }
                }
                
                // Brand and Category
                if let category = food.category {
                    Text(category)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                // Serving Info
                Text("Per \(formatServingSize(food.servingSize)) \(food.servingUnit)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Favorite star button
            Button(action: toggleFavorite) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.system(size: 18))
                    .foregroundColor(isFavorite ? .yellow : .gray.opacity(0.5))
            }
            .buttonStyle(PlainButtonStyle())
            
            // Nutrition Preview
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(food.nutrition.calories)) cal")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text("\(Int(food.nutrition.protein))p • \(Int(food.nutrition.carbohydrates))c • \(Int(food.nutrition.totalFat))f")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            // Tap to view details
            Button(action: onTap) {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
        .onTapGesture {
            onTap()
        }
        .onAppear {
            isFavorite = foodService.isFavorite(foodItemId: food.id)
        }
    }
    
    private func toggleFavorite() {
        Task {
            await foodService.toggleFavorite(fdcId: food.id, foodItemId: food.id)
            await MainActor.run {
                isFavorite.toggle()
            }
        }
    }
    
    private var foodIcon: String {
        guard let category = food.category?.lowercased() else { return "leaf" }
        
        if category.contains("dairy") || category.contains("milk") {
            return "drop"
        } else if category.contains("meat") || category.contains("poultry") || category.contains("beef") || category.contains("chicken") {
            return "flame"
        } else if category.contains("fish") || category.contains("seafood") {
            return "fish"
        } else if category.contains("fruit") {
            return "apple"
        } else if category.contains("vegetable") {
            return "carrot"
        } else if category.contains("grain") || category.contains("cereal") || category.contains("bread") {
            return "wheat"
        } else if category.contains("nut") || category.contains("seed") {
            return "circle.hexagongrid"
        } else {
            return "leaf"
        }
    }
    
    private func formatServingSize(_ size: Double) -> String {
        if size == floor(size) {
            return String(Int(size))
        } else {
            return String(format: "%.1f", size)
        }
    }
}

// MARK: - Quick Access Food Row

struct QuickAccessFoodRow: View {
    let food: ProcessedFoodItem
    let badge: String?
    let onTap: () -> Void
    
    @StateObject private var foodService = USDAFoodService.shared
    @State private var isFavorite: Bool = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Food Icon
            Image(systemName: foodIcon)
                .font(.title2)
                .foregroundColor(.green)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                // Food Name
                HStack(spacing: 6) {
                    Text(food.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    
                    if isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundColor(.yellow)
                    }
                    
                    if let badge = badge {
                        Text(badge)
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(badgeColor(for: badge))
                            )
                    }
                }
                
                // Serving Info
                Text("Per \(formatServingSize(food.servingSize)) \(food.servingUnit)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Favorite star button
            Button(action: toggleFavorite) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.system(size: 18))
                    .foregroundColor(isFavorite ? .yellow : .gray.opacity(0.5))
            }
            .buttonStyle(PlainButtonStyle())
            
            // Nutrition Preview
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(food.nutrition.calories)) cal")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text("\(Int(food.nutrition.protein))p • \(Int(food.nutrition.carbohydrates))c • \(Int(food.nutrition.totalFat))f")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            // Quick add button
            Button(action: onTap) {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundColor(.green)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
        .padding(.horizontal)
        .onAppear {
            isFavorite = foodService.isFavorite(foodItemId: food.id)
        }
    }
    
    private func toggleFavorite() {
        Task {
            await foodService.toggleFavorite(fdcId: food.id, foodItemId: food.id)
            await MainActor.run {
                isFavorite.toggle()
            }
        }
    }
    
    private var foodIcon: String {
        guard let category = food.category?.lowercased() else { return "leaf" }
        
        if category.contains("dairy") || category.contains("milk") {
            return "drop.fill"
        } else if category.contains("meat") || category.contains("poultry") || category.contains("beef") || category.contains("chicken") {
            return "flame.fill"
        } else if category.contains("fish") || category.contains("seafood") {
            return "fish.fill"
        } else if category.contains("fruit") {
            return "apple"
        } else if category.contains("vegetable") {
            return "carrot.fill"
        } else if category.contains("grain") || category.contains("cereal") || category.contains("bread") {
            return "wheat"
        } else if category.contains("nut") || category.contains("seed") {
            return "circle.hexagongrid.fill"
        } else {
            return "leaf.fill"
        }
    }
    
    private func badgeColor(for badge: String) -> Color {
        switch badge {
        case "RECENT": return .blue
        case "FAVORITE": return .yellow
        case "FREQUENT": return .orange
        default: return .gray
        }
    }
    
    private func formatServingSize(_ size: Double) -> String {
        if size == floor(size) {
            return String(Int(size))
        } else {
            return String(format: "%.1f", size)
        }
    }
}

#Preview {
    FoodSearchView(mealType: .breakfast) { _ in }
}
