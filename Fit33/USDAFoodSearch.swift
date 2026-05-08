import SwiftUI

// MARK: - USDA Food Search View (Real API Integration)

struct USDAFoodSearchView: View {
    let mealType: MealType
    let onAdd: (FoodEntry) -> Void
    @Environment(\.dismiss) private var dismiss
    
    @ObservedObject private var foodService = USDAFoodService.shared
    @State private var searchText = ""
    @State private var searchDebouncer: Timer?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search Header
                searchHeader
                
                // Search Results
                if foodService.isSearching {
                    loadingView
                } else if let error = foodService.searchError {
                    errorView(error)
                } else if searchText.isEmpty {
                    emptySearchView
                } else if foodService.searchResults.isEmpty && !searchText.isEmpty {
                    noResultsView
                } else {
                    searchResultsList
                }
            }
            .navigationTitle("Add to \(mealType.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onDisappear {
                searchDebouncer?.invalidate()
                searchDebouncer = nil
            }
        }
    }
    
    // MARK: - View Components
    
    private var searchHeader: some View {
        VStack(spacing: 16) {
            // Meal Type Badge
            HStack {
                Image(systemName: mealTypeIcon)
                    .foregroundColor(mealTypeColor)
                Text("Adding to \(mealType.displayName)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(mealTypeColor)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 8)
            
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search USDA database (e.g., eggs, chicken)", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .onChange(of: searchText) { newValue in
                        AppLogger.debug("[CONTENTVIEW] Search text changed to: '\(newValue)'", category: .ui)
                        searchDebouncer?.invalidate()
                        searchDebouncer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
                            AppLogger.debug("[CONTENTVIEW] Debounce timer fired for: '\(newValue)'", category: .ui)
                            if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                AppLogger.debug("[CONTENTVIEW] Calling foodService.searchFoods() for: '\(newValue)'", category: .ui)
                                foodService.searchFoods(query: newValue)
                            } else {
                                AppLogger.warning("[CONTENTVIEW] Query empty, clearing results", category: .ui)
                                foodService.searchResults = []
                            }
                        }
                    }
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .fill(Color(.systemGray6))
            )
            .padding(.horizontal)
        }
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
            Text("Searching USDA database...")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("400,000+ foods")
                .font(.caption)
                .foregroundColor(.green)
                .fontWeight(.medium)
            Spacer()
        }
    }
    
    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            Text("Search Error")
                .font(.headline)
                .fontWeight(.bold)
            Text(error)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Try Again") {
                if !searchText.isEmpty {
                    foodService.searchFoods(query: searchText)
                }
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
    }
    
    private var emptySearchView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "magnifyingglass.circle")
                .font(.system(size: 64))
                .foregroundColor(.green)
            
            VStack(spacing: 12) {
                Text("Search USDA Database")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Search over 400,000 foods from the U.S. Department of Agriculture database")
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
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xs)
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.sm)
                                .fill(Color(.systemGray6))
                        )
                    }
                }
            }
            .padding(.horizontal)
            
            Spacer()
        }
    }
    
    private var noResultsView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No Results Found")
                .font(.headline)
                .fontWeight(.bold)
            Text("Try a different search term or check your spelling")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
    }
    
    private var searchResultsList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(foodService.searchResults) { food in
                    USDAFoodResultRow(food: food) {
                        addFood(food)
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
        .background(Color(.systemGroupedBackground))
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
        ["eggs", "chicken breast", "brown rice", "banana", "greek yogurt", "salmon"]
    }
    
    private func addFood(_ food: ProcessedFoodItem) {
        let foodEntry = FoodEntry(
            name: food.displayName,
            quantity: 1.0,
            unit: food.servingUnit,
            calories: Int(food.nutrition.calories),
            protein: Int(food.nutrition.protein),
            carbs: Int(food.nutrition.carbohydrates),
            fat: Int(food.nutrition.totalFat),
            fdcId: food.id,
            foodItemId: nil,
            // Carry source from the underlying ProcessedFoodItem so OFF
            // attribution survives this (legacy / dead) entry path.
            source: food.source,
            barcode: food.barcode
        )
        
        onAdd(foodEntry)
        dismiss()
    }
}

// MARK: - USDA Food Result Row

struct USDAFoodResultRow: View {
    let food: ProcessedFoodItem
    let onTap: () -> Void
    
    var body: some View {
        Button(action: { HapticManager.selectionChanged(); onTap() }) {
            HStack(spacing: 12) {
                // OFF rows render the real product photo; USDA / local rows fall
                // back to a green-tint emoji circle. Reuses the canonical
                // FoodThumbnailView from FoodSearchView so this legacy result row
                // stays visually aligned with the modern search UI if it's ever
                // re-enabled. Bumped from 32 → 48 so the photo is recognizable.
                FoodThumbnailView(
                    imageUrl: food.imageUrl,
                    gradient: [Color.green, Color.mint],
                    emoji: getFoodEmoji(for: food),
                    size: 48
                )

                VStack(alignment: .leading, spacing: 4) {
                    // Food Name
                    Text(food.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
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
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(Color(.systemBackground))
            .cornerRadius(CornerRadius.md)
            .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func formatServingSize(_ size: Double) -> String {
        if size == floor(size) {
            return String(Int(size))
        } else {
            return String(format: "%.1f", size)
        }
    }
}
