import SwiftUI
import Combine

struct FoodSearchView: View {
    let mealType: MealType
    let onAdd: (FoodEntry) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var userManager: UserManager
    
    @StateObject private var foodService = USDAFoodService.shared
    @State private var searchText = ""
    @State private var selectedFood: ProcessedFoodItem?
    @State private var searchDebouncer: Timer?
    @State private var showingQuickAccess = true
    @State private var showingNutritionScanner = false
    @State private var showingRestaurantSearch = false
    @State private var showingScanChoice = false      // Action sheet — barcode vs nutrition label
    @State private var showingBarcodeScanner = false  // Open Food Facts barcode scanner (2026-04-30)
    @State private var isWaitingForSearch = false  // Track debounce state to prevent flash
    
    var body: some View {
        ZStack {
            AnimatedOrbBackground.meals(colorScheme: colorScheme)
                .ignoresSafeArea(.all, edges: .all)
            
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
                            AppLogger.debug("💾 [SEARCH VIEW] Saving scanned nutrition: \(foodEntry.name)", category: .nutrition)
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
        .sheet(isPresented: $showingRestaurantSearch) {
            RestaurantSearchSheet()
                .environmentObject(userManager)
        }
        .confirmationDialog("Scan", isPresented: $showingScanChoice, titleVisibility: .visible) {
            Button {
                AppLogger.debug("📸 [SEARCH VIEW] User chose: Scan Barcode", category: .nutrition)
                showingBarcodeScanner = true
            } label: {
                Label("Scan Barcode (UPC/EAN)", systemImage: "barcode.viewfinder")
            }
            Button {
                AppLogger.debug("📸 [SEARCH VIEW] User chose: Scan Nutrition Label", category: .nutrition)
                showingNutritionScanner = true
            } label: {
                Label("Scan Nutrition Label", systemImage: "doc.text.viewfinder")
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Barcode = packaged product\nNutrition Label = restaurant menu / hand-written")
        }
        .fullScreenCover(isPresented: $showingBarcodeScanner) {
            // Camera needs full screen — sheet would clip the preview layer
            // and AVCapture orientation handling gets weird inside a half-sheet.
            BarcodeScannerView(
                onScan: { food in
                    // Hit: route through the existing FoodDetailsView path
                    // (NavigationLink hidden in `.background` above) so the
                    // serving-size picker + onAdd closure all work unchanged.
                    selectedFood = food
                },
                onSearchFallback: { code in
                    // Miss: prefill the search bar so the user can find a
                    // similar product by name. Keeps the scanner from being
                    // a dead-end UX when OFF doesn't have the item.
                    searchText = code
                }
            )
        }
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
                            .font(.ds_heading3).fontWeight(.semibold)
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
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .fill(colorScheme == .dark ? Color(white: 0.15) : .white)
                    .shadow(color: mealTypeColor.opacity(0.15), radius: 8, x: 0, y: 4)
            )
            .padding(.horizontal)
            .padding(.top, 8)
            
            // Modern Search Bar with glow effect
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.ds_heading3)
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
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.ds_heading3)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, Spacing.md)
            .background(
                ZStack {
                    // Bottom shadow layer - subtle color glow
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(mealTypeColor.opacity(colorScheme == .dark ? 0.1 : 0.06))
                        .offset(y: 6)
                        .blur(radius: 4)
                    
                    // Middle shadow layer
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.black.opacity(colorScheme == .dark ? 0.15 : 0.03))
                        .offset(y: 3)
                    
                    // Main card background
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: colorScheme == .dark 
                                    ? [Color(white: 0.14), Color(white: 0.09)]
                                    : [Color.white, Color.white.opacity(0.95)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    
                    // Inner highlight (top edge glow)
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: colorScheme == .dark
                                    ? [Color.white.opacity(0.08), Color.white.opacity(0.02), Color.clear]
                                    : [Color.white, Color.white.opacity(0.4), Color.clear],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1.5
                        )
                    
                    // Subtle accent border
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [mealTypeColor.opacity(colorScheme == .dark ? 0.25 : 0.2), mealTypeColor.opacity(colorScheme == .dark ? 0.15 : 0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.06), radius: 10, x: 0, y: 5)
            .shadow(color: mealTypeColor.opacity(colorScheme == .dark ? 0.15 : 0.08), radius: 14, x: 0, y: 7)
            .padding(.horizontal)
            
            // Action Tiles - Search, Scan, Eat Out (below search bar)
            HStack(spacing: 12) {
                // Search Tile (active by default)
                AddFoodActionTile(
                    icon: "magnifyingglass",
                    title: "Search",
                    gradient: [.blue, .cyan],
                    isActive: true,
                    action: { /* Already showing search */ }
                )
                
                // Scan Tile — opens an action sheet with two scanning paths
                // (added Open Food Facts barcode lookup 2026-04-30):
                //   - "Scan Barcode" → BarcodeScannerView → searchByBarcode
                //   - "Scan Nutrition Label" → NutritionScannerView (existing OCR)
                // We keep a single Scan tile rather than splitting into two so
                // the action row stays at 3 tiles (4 doesn't fit comfortably
                // on iPhone SE width — verified via DEVICE_COMPATIBILITY_AGENT
                // adaptive-layout invariant). Confirmation dialog is the
                // cheapest disambiguator.
                AddFoodActionTile(
                    icon: "camera.fill",
                    title: "Scan",
                    gradient: [.purple, .pink],
                    isActive: false,
                    action: {
                        AppLogger.debug("📸 [SEARCH VIEW] Scan tile tapped", category: .nutrition)
                        showingScanChoice = true
                    }
                )
                
                // Eat Out Tile
                AddFoodActionTile(
                    icon: "fork.knife",
                    title: "Eat Out",
                    gradient: [.orange, .yellow],
                    isActive: false,
                    action: {
                        AppLogger.debug("🍔 [SEARCH VIEW] Eat Out tile tapped", category: .nutrition)
                        showingRestaurantSearch = true
                    }
                )
            }
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
                    .padding(.horizontal, Spacing.xl)
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
                
                ForEach(sampleSearchesWithEmojis, id: \.name) { item in
                    Button(action: { searchText = item.name }) {
                        HStack {
                            Text(item.emoji)
                                .font(.title3)
                            Text(item.name)
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
    
    private var quickAccessView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Frequently Used Foods Section (TOP PRIORITY - Quick Add)
                if !foodService.frequentFoods.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "bolt.fill")
                                .foregroundColor(.green)
                            Text("Your Quick Add")
                                .font(.headline)
                                .fontWeight(.bold)
                            
                            Spacer()
                            
                            Text("\(foodService.frequentFoods.count) foods")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, Spacing.xs)
                                .padding(.vertical, Spacing.xxs)
                                .background(
                                    Capsule()
                                        .fill(Color.green)
                                )
                        }
                        .padding(.horizontal)
                        
                        Text("Based on your meal history")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                        
                        ForEach(foodService.frequentFoods.prefix(8)) { food in
                            QuickAccessFoodRow(food: food, badge: nil) {
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
                
                // Popular Foods Section (Global - all users)
                if !foodService.popularFoods.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "flame.fill")
                                .foregroundColor(.orange)
                            Text("Trending Foods")
                                .font(.headline)
                                .fontWeight(.bold)
                            
                            Spacer()
                            
                            Text("All Users")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(Color.orange.opacity(0.15))
                                )
                        }
                        .padding(.horizontal)
                        
                        Text("Most logged across the community")
                            .font(.caption)
                            .foregroundColor(.secondary)
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
                    .padding(.horizontal, Spacing.xl)
            }
            
            VStack(spacing: 8) {
                Text("Suggestions:")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                ForEach([("🥚", "Eggs"), ("🍗", "Chicken breast"), ("🍚", "Brown rice"), ("🍌", "Banana")], id: \.1) { emoji, suggestion in
                    Button(action: { searchText = suggestion }) {
                        HStack {
                            Text(emoji)
                                .font(.title3)
                            Text(suggestion)
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.left")
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.md)
                                .fill(colorScheme == .dark ? Color(white: 0.15) : .white)
                                .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
                        )
                    }
                }
            }
            .padding(.horizontal, Spacing.xl)
            
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
    
    private var sampleSearchesWithEmojis: [(emoji: String, name: String)] {
        [
            ("🥚", "Eggs"),
            ("🍗", "Chicken breast"),
            ("🍚", "Brown rice"),
            ("🍌", "Banana"),
            ("🥛", "Greek yogurt"),
            ("🐟", "Salmon")
        ]
    }
}

// MARK: - Food Search Result Row

struct FoodSearchResultRow: View {
    let food: ProcessedFoodItem
    let onTap: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var foodService = USDAFoodService.shared
    @State private var isFavorite: Bool = false
    
    var body: some View {
        HStack(spacing: 12) {
            // OFF rows (`food.imageUrl != nil`) render the real product photo on a
            // white chip; USDA / local rows fall back to the original category
            // gradient + emoji circle. Bumped from 40 → 52 so the photo is
            // recognizable (and a Pringles can looks like a Pringles can) without
            // dominating the row.
            FoodThumbnailView(
                imageUrl: food.imageUrl,
                gradient: categoryGradient,
                emoji: getFoodEmoji(for: food),
                size: 52
            )

            // Food details
            VStack(alignment: .leading, spacing: 2) {
                // USDA-branded + Open Food Facts items frequently exceed one line
                // (e.g. "Kellogg's Frosted Mini-Wheats Touch of Brown Sugar Bite-Size
                // Cereal"). Match the canonical USDAFoodResultRow pattern so picks
                // aren't clipped to "…" before the user can tell them apart.
                Text(food.displayName)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                HStack(spacing: 8) {
                    if let category = food.category {
                        Text(category)
                            .font(.caption)
                            .foregroundColor(categoryColor)
                            .fontWeight(.medium)
                    }
                    
                    Text("•")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text("\(Int(food.nutrition.calories)) cal")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                }
            }
            
            Spacer()
            
            // Favorite star indicator
            if isFavorite {
                Image(systemName: "star.fill")
                    .font(.ds_bodySmall).fontWeight(.medium)
                    .foregroundColor(.yellow)
            }
            
            // Chevron inside the card
            Image(systemName: "chevron.right")
                .font(.ds_bodySmall).fontWeight(.medium)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(
            ZStack {
                // Bottom shadow layer (deepest) - category colored (subtle)
                RoundedRectangle(cornerRadius: 28)
                    .fill(categoryGradient[0].opacity(colorScheme == .dark ? 0.06 : 0.03))
                    .offset(y: 4)
                    .blur(radius: 2)
                
                // Middle shadow layer (subtle)
                RoundedRectangle(cornerRadius: 26)
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.08 : 0.02))
                    .offset(y: 2)
                
                // Main card background
                RoundedRectangle(cornerRadius: 25)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark 
                                ? [Color(white: 0.15), Color.cardBackground]
                                : [Color.white, Color.white.opacity(0.98)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                // Inner highlight (top edge glow)
                RoundedRectangle(cornerRadius: 25)
                    .stroke(
                        LinearGradient(
                            colors: colorScheme == .dark 
                                ? [Color.white.opacity(0.08), Color.clear]
                                : [Color.white, Color.white.opacity(0.3), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                
                // Subtle accent border
                RoundedRectangle(cornerRadius: 25)
                    .stroke(
                        LinearGradient(
                            colors: [
                                categoryGradient[0].opacity(colorScheme == .dark ? 0.2 : 0.12),
                                categoryGradient[1].opacity(colorScheme == .dark ? 0.1 : 0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.12 : 0.05), radius: 6, x: 0, y: 3)
        .shadow(color: categoryGradient[0].opacity(colorScheme == .dark ? 0.08 : 0.04), radius: 8, x: 0, y: 4)
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
    
    private var categoryColor: Color {
        guard let category = food.category?.lowercased() else { return .gray }
        
        if category.contains("dairy") || category.contains("milk") {
            return .blue
        } else if category.contains("meat") || category.contains("poultry") || category.contains("beef") {
            return .red
        } else if category.contains("fish") || category.contains("seafood") {
            return .cyan
        } else if category.contains("fruit") {
            return .pink
        } else if category.contains("vegetable") {
            return .green
        } else if category.contains("grain") || category.contains("cereal") || category.contains("bread") {
            return .orange
        } else if category.contains("nut") || category.contains("seed") || category.contains("legume") {
            return .brown
        } else if category.contains("beverage") {
            return .teal
        } else {
            return .gray
        }
    }
    
    private var categoryGradient: [Color] {
        guard let category = food.category?.lowercased() else {
            return [Color.green, Color.teal]
        }
        
        if category.contains("dairy") || category.contains("milk") {
            return [Color.blue, Color.cyan]
        } else if category.contains("meat") || category.contains("poultry") || category.contains("beef") || category.contains("pork") {
            return [Color.red, Color.orange]
        } else if category.contains("fish") || category.contains("seafood") {
            return [Color.cyan, Color.blue]
        } else if category.contains("fruit") {
            return [Color.pink, Color.red]
        } else if category.contains("vegetable") {
            return [Color.green, Color.teal]
        } else if category.contains("grain") || category.contains("cereal") || category.contains("bread") {
            return [Color.orange, Color.yellow]
        } else if category.contains("nut") || category.contains("seed") || category.contains("legume") {
            return [Color.brown, Color.orange]
        } else if category.contains("beverage") {
            return [Color.teal, Color.blue]
        } else {
            return [Color.green, Color.teal]
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
    
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var foodService = USDAFoodService.shared
    @State private var isFavorite: Bool = false
    
    var body: some View {
        HStack(spacing: 12) {
            // OFF rows (`food.imageUrl != nil`) render the real product photo;
            // USDA / local rows show the category-gradient + emoji fallback.
            // Mirrors the canonical FoodSearchResultRow icon treatment so a row
            // that appears in both Search and Quick Add looks identical.
            FoodThumbnailView(
                imageUrl: food.imageUrl,
                gradient: categoryGradient,
                emoji: getFoodEmoji(for: food),
                size: 52
            )

            // Food details
            VStack(alignment: .leading, spacing: 2) {
                // Frequent / quick-access foods carry the same long-name risk as
                // search results — match the lineLimit(2) canonical pattern so
                // long restaurant + branded items are legible at a glance.
                Text(food.displayName)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                HStack(spacing: 8) {
                    if let category = food.category {
                        Text(category)
                            .font(.caption)
                            .foregroundColor(categoryColor)
                            .fontWeight(.medium)
                    }
                    
                    Text("•")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text("\(Int(food.nutrition.calories)) cal")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                }
            }
            
            Spacer()
            
            // Favorite star indicator
            if isFavorite {
                Image(systemName: "star.fill")
                    .font(.ds_bodySmall).fontWeight(.medium)
                    .foregroundColor(.yellow)
            }
            
            // Chevron inside the card
            Image(systemName: "chevron.right")
                .font(.ds_bodySmall).fontWeight(.medium)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(
            ZStack {
                // Bottom shadow layer (deepest) - category colored (subtle)
                RoundedRectangle(cornerRadius: 28)
                    .fill(categoryGradient[0].opacity(colorScheme == .dark ? 0.06 : 0.03))
                    .offset(y: 4)
                    .blur(radius: 2)
                
                // Middle shadow layer (subtle)
                RoundedRectangle(cornerRadius: 26)
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.08 : 0.02))
                    .offset(y: 2)
                
                // Main card background
                RoundedRectangle(cornerRadius: 25)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark 
                                ? [Color(white: 0.15), Color.cardBackground]
                                : [Color.white, Color.white.opacity(0.98)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                // Inner highlight (top edge glow)
                RoundedRectangle(cornerRadius: 25)
                    .stroke(
                        LinearGradient(
                            colors: colorScheme == .dark 
                                ? [Color.white.opacity(0.08), Color.clear]
                                : [Color.white, Color.white.opacity(0.3), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                
                // Subtle accent border
                RoundedRectangle(cornerRadius: 25)
                    .stroke(
                        LinearGradient(
                            colors: [
                                categoryGradient[0].opacity(colorScheme == .dark ? 0.2 : 0.12),
                                categoryGradient[1].opacity(colorScheme == .dark ? 0.1 : 0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.12 : 0.05), radius: 6, x: 0, y: 3)
        .shadow(color: categoryGradient[0].opacity(colorScheme == .dark ? 0.08 : 0.04), radius: 8, x: 0, y: 4)
        .padding(.horizontal)
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
    
    private var categoryColor: Color {
        guard let category = food.category?.lowercased() else { return .gray }
        
        if category.contains("dairy") || category.contains("milk") {
            return .blue
        } else if category.contains("meat") || category.contains("poultry") || category.contains("beef") {
            return .red
        } else if category.contains("fish") || category.contains("seafood") {
            return .cyan
        } else if category.contains("fruit") {
            return .pink
        } else if category.contains("vegetable") {
            return .green
        } else if category.contains("grain") || category.contains("cereal") || category.contains("bread") {
            return .orange
        } else if category.contains("nut") || category.contains("seed") || category.contains("legume") {
            return .brown
        } else if category.contains("beverage") {
            return .teal
        } else {
            return .gray
        }
    }
    
    private var categoryGradient: [Color] {
        guard let category = food.category?.lowercased() else {
            return [Color.green, Color.teal]
        }
        
        if category.contains("dairy") || category.contains("milk") {
            return [Color.blue, Color.cyan]
        } else if category.contains("meat") || category.contains("poultry") || category.contains("beef") || category.contains("pork") {
            return [Color.red, Color.orange]
        } else if category.contains("fish") || category.contains("seafood") {
            return [Color.cyan, Color.blue]
        } else if category.contains("fruit") {
            return [Color.pink, Color.red]
        } else if category.contains("vegetable") {
            return [Color.green, Color.teal]
        } else if category.contains("grain") || category.contains("cereal") || category.contains("bread") {
            return [Color.orange, Color.yellow]
        } else if category.contains("nut") || category.contains("seed") || category.contains("legume") {
            return [Color.brown, Color.orange]
        } else if category.contains("beverage") {
            return [Color.teal, Color.blue]
        } else {
            return [Color.green, Color.teal]
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

// MARK: - Food Thumbnail (OFF product photo with emoji fallback)

/// Renders a leading thumbnail for a `ProcessedFoodItem`.
///
/// When the row originated from Open Food Facts (`food.imageUrl != nil`) we
/// show the real product photo on a white rounded-square chip — OFF crops are
/// rectangular product shots so a circle clips the label. While loading or on
/// failure we fall back to the existing category-gradient + emoji circle so
/// USDA / local rows look identical to before and OFF rows degrade cleanly
/// when the CDN is unreachable.
struct FoodThumbnailView: View {
    let imageUrl: String?
    let gradient: [Color]
    let emoji: String
    let size: CGFloat

    var body: some View {
        if let urlString = imageUrl,
           !urlString.isEmpty,
           let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(size * 0.08)
                        .frame(width: size, height: size)
                        .background(
                            RoundedRectangle(cornerRadius: size * 0.22)
                                .fill(Color.white)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: size * 0.22)
                                .stroke(
                                    (gradient.first ?? Color.gray).opacity(0.25),
                                    lineWidth: 1
                                )
                        )
                        .shadow(
                            color: (gradient.first ?? Color.black).opacity(0.18),
                            radius: 4, x: 0, y: 2
                        )
                default:
                    fallback
                }
            }
        } else {
            fallback
        }
    }

    private var fallback: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: gradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .shadow(
                    color: (gradient.first ?? Color.black).opacity(0.25),
                    radius: 4, x: 0, y: 2
                )

            Text(emoji)
                .font(.system(size: size * 0.5))
        }
    }
}

// MARK: - Food Emoji Helper

/// Returns a food emoji based on the food name and category
/// Comprehensive mapping of foods to their corresponding emojis
func getFoodEmoji(for food: ProcessedFoodItem) -> String {
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

// MARK: - Add Food Action Tile

struct AddFoodActionTile: View {
    let icon: String
    let title: String
    let gradient: [Color]
    let isActive: Bool
    let action: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: gradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                        .shadow(color: gradient[0].opacity(0.5), radius: 8, x: 0, y: 4)
                    
                    Image(systemName: icon)
                        .font(.ds_heading3)
                        .foregroundColor(.white)
                }
                
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 100)
            .background(
                ZStack {
                    // Bottom shadow layer (deepest) - color glow
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(gradient[0].opacity(colorScheme == .dark ? 0.15 : 0.08))
                        .offset(y: 6)
                        .blur(radius: 4)
                    
                    // Middle shadow layer
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                        .offset(y: 3)
                    
                    // Main card background with gradient
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            Color.cardBackground
                        )
                    
                    // Inner highlight (top edge glow)
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: colorScheme == .dark
                                    ? [Color.white.opacity(0.1), Color.white.opacity(0.02), Color.clear]
                                    : [Color.white, Color.white.opacity(0.5), Color.clear],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1.5
                        )
                    
                    // Colored accent border
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [gradient[0].opacity(colorScheme == .dark ? 0.4 : 0.3), gradient[1].opacity(colorScheme == .dark ? 0.3 : 0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 10, x: 0, y: 5)
            .shadow(color: gradient[0].opacity(colorScheme == .dark ? 0.2 : 0.12), radius: 16, x: 0, y: 8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    FoodSearchView(mealType: .breakfast) { _ in }
        .environmentObject(UserManager.shared)
}
