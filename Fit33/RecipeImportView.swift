import SwiftUI

// MARK: - Recipe Import Sheet
/// Import recipes from any URL — premium redesign
struct RecipeImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var advancedService = SpoonacularAdvancedService.shared
    
    @State private var urlText: String = ""
    @State private var isExtracting = false
    @State private var extractedRecipe: ExtractedRecipe?
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showingRecipeDetail = false
    @State private var showRecipeContent = false // For animated reveal
    
    private var cardBg: Color {
        colorScheme == .dark ? Color(white: 0.12) : Color.white
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Premium gradient background
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [Color(red: 0.06, green: 0.08, blue: 0.16), Color(red: 0.04, green: 0.04, blue: 0.08)]
                        : [Color(red: 0.95, green: 0.97, blue: 1.0), Color(.systemGroupedBackground)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        // Header
                        headerSection
                        
                        // URL Input
                        urlInputSection
                        
                        // Extract Button
                        extractButton
                        
                        // Full recipe results
                        if let recipe = extractedRecipe, showRecipeContent {
                            recipeResultsView(recipe)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.secondary)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .fullScreenCover(isPresented: $showingRecipeDetail) {
                if let recipe = extractedRecipe {
                    ImportedRecipeDetailView(recipe: recipe, sourceURL: urlText)
                }
            }
        }
    }
    
    // MARK: - Header
    private var headerSection: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                    .shadow(color: .blue.opacity(0.3), radius: 8, x: 0, y: 4)
                
                Image(systemName: "link.badge.plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Import Recipe")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                
                Text("Paste any recipe URL to get started")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.top, 8)
    }
    
    // MARK: - URL Input
    private var urlInputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "link")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.blue)
                    .frame(width: 24)
                
                TextField("https://example.com/recipe", text: $urlText)
                    .autocapitalization(.none)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .font(.subheadline)
                
                if !urlText.isEmpty {
                    Button(action: { urlText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(colorScheme == .dark ? Color(white: 0.15) : Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(
                                LinearGradient(
                                    colors: urlText.isEmpty ? [Color.gray.opacity(0.2)] : [.blue.opacity(0.5), .cyan.opacity(0.3)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                lineWidth: 1.5
                            )
                    )
            )
            .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
            
            HStack(spacing: 4) {
                Image(systemName: "info.circle")
                    .font(.system(size: 10))
                Text("AllRecipes, Food Network, BBC Good Food, and more")
                    .font(.caption2)
            }
            .foregroundColor(.secondary)
            .padding(.leading, 4)
        }
    }
    
    // MARK: - Extract Button
    private var extractButton: some View {
        Button(action: extractRecipe) {
            HStack(spacing: 10) {
                if isExtracting {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 16, weight: .semibold))
                }
                Text(isExtracting ? "Extracting Recipe..." : "Extract Recipe")
                    .font(.headline)
                    .fontWeight(.bold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: urlText.isEmpty ? [.gray.opacity(0.5)] : [.blue, .cyan],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: urlText.isEmpty ? .clear : .blue.opacity(0.4), radius: 10, x: 0, y: 5)
        }
        .disabled(urlText.isEmpty || isExtracting)
        .scaleEffect(isExtracting ? 0.98 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isExtracting)
    }
    
    // MARK: - Full Recipe Results
    private func recipeResultsView(_ recipe: ExtractedRecipe) -> some View {
        VStack(spacing: 16) {
            // Hero Image
            recipeHeroImage(recipe)
            
            // Title + Meta
            recipeTitleCard(recipe)
            
            // Nutrition
            recipeNutritionCard(recipe)
            
            // Banner Ad for free users
            if !PremiumManager.shared.isPremiumUser && AdManager.shared.adsEnabled {
                BannerAdView()
            }
            
            // Ingredients
            recipeIngredientsCard(recipe)
            
            // Instructions / Steps
            if let instructions = recipe.instructions, !instructions.isEmpty {
                recipeStepsCard(instructions)
            }
            
            // View Full Details button
            viewDetailsButton
        }
    }
    
    // MARK: - Hero Image
    private func recipeHeroImage(_ recipe: ExtractedRecipe) -> some View {
        ZStack(alignment: .topTrailing) {
            if let imageURL = recipe.image, let url = URL(string: imageURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .empty:
                        imagePlaceholder
                            .overlay(ProgressView().tint(.white))
                    case .failure:
                        imagePlaceholder
                    @unknown default:
                        imagePlaceholder
                    }
                }
            } else {
                imagePlaceholder
            }
            
            // Success badge
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .bold))
                Text("Extracted")
                    .font(.caption2)
                    .fontWeight(.bold)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.green.gradient))
            .shadow(color: .green.opacity(0.4), radius: 4, x: 0, y: 2)
            .padding(12)
        }
        .frame(height: 220)
        .frame(maxWidth: .infinity)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            VStack {
                Spacer()
                LinearGradient(
                    colors: [.clear, .black.opacity(0.5)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 70)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20))
        )
        .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 6)
    }
    
    private var imagePlaceholder: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [Color.blue.opacity(0.25), Color.cyan.opacity(0.15)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                VStack(spacing: 8) {
                    Image(systemName: "fork.knife")
                        .font(.system(size: 36))
                    Text("No image available")
                        .font(.caption)
                }
                .foregroundColor(.white.opacity(0.5))
            )
    }
    
    // MARK: - Title + Meta Card
    private func recipeTitleCard(_ recipe: ExtractedRecipe) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(recipe.title)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
            
            HStack(spacing: 14) {
                if let source = recipe.sourceName {
                    Label(source, systemImage: "globe")
                }
                if let time = recipe.readyInMinutes {
                    Label("\(time) min", systemImage: "clock.fill")
                }
                if let servings = recipe.servings {
                    Label("\(servings) servings", systemImage: "person.2.fill")
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(cardBg)
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
        )
    }
    
    // MARK: - Nutrition Card
    private func recipeNutritionCard(_ recipe: ExtractedRecipe) -> some View {
        VStack(spacing: 10) {
            Text("Nutrition")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 8) {
                NutritionPill(label: "Cal", value: "\(recipe.calories)", color: .orange)
                NutritionPill(label: "Protein", value: "\(recipe.protein)g", color: .blue)
                NutritionPill(label: "Carbs", value: "\(recipe.carbs)g", color: .green)
                NutritionPill(label: "Fat", value: "\(recipe.fat)g", color: .purple)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(cardBg)
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
        )
    }
    
    // MARK: - Ingredients Card
    private func recipeIngredientsCard(_ recipe: ExtractedRecipe) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Section header
            HStack {
                Image(systemName: "leaf.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 14))
                Text("Ingredients")
                    .font(.headline)
                    .fontWeight(.bold)
                
                Spacer()
                
                if let count = recipe.extendedIngredients?.count {
                    Text("\(count)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.green.opacity(0.15)))
                }
            }
            
            if let ingredients = recipe.extendedIngredients, !ingredients.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(ingredients.enumerated()), id: \.element.id) { index, ingredient in
                        HStack(spacing: 12) {
                            // Ingredient image
                            AsyncImage(url: ingredient.imageURL) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                case .failure, .empty:
                                    Circle()
                                        .fill(Color.green.opacity(0.1))
                                        .overlay(
                                            Image(systemName: "leaf.fill")
                                                .font(.system(size: 10))
                                                .foregroundColor(.green)
                                        )
                                @unknown default:
                                    Circle().fill(Color.gray.opacity(0.2))
                                }
                            }
                            .frame(width: 34, height: 34)
                            .clipShape(Circle())
                            
                            Text(ingredient.name.capitalized)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            
                            Spacer()
                            
                            Text("\(ingredient.formattedAmount) \(ingredient.unit ?? "")")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 8)
                        
                        if index < ingredients.count - 1 {
                            Divider()
                                .padding(.leading, 46)
                        }
                    }
                }
            } else {
                Text("No ingredients available")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(cardBg)
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
        )
    }
    
    // MARK: - Steps Card
    private func recipeStepsCard(_ instructions: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Section header
            HStack {
                Image(systemName: "list.number")
                    .foregroundColor(.blue)
                    .font(.system(size: 14))
                Text("Steps")
                    .font(.headline)
                    .fontWeight(.bold)
                
                Spacer()
            }
            
            let steps = parseInstructionSteps(instructions)
            
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 12) {
                    // Step number circle
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.blue, .cyan],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 28, height: 28)
                        
                        Text("\(index + 1)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                    
                    Text(step)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 2)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(cardBg)
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
        )
    }
    
    /// Parse raw instruction text into individual steps
    private func parseInstructionSteps(_ raw: String) -> [String] {
        // Clean HTML
        let cleaned = raw
            .replacingOccurrences(of: "<[^>]+>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Try splitting by numbered patterns like "1." or "1)" or newlines
        let byNewlines = cleaned
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { $0.replacingOccurrences(of: #"^\d+[\.\)]\s*"#, with: "", options: .regularExpression) }
            .filter { !$0.isEmpty && $0.count > 5 }
        
        if byNewlines.count > 1 {
            return byNewlines
        }
        
        // Fall back to splitting by sentences (period followed by space + capital)
        let bySentence = cleaned
            .components(separatedBy: ". ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count > 10 }
            .map { $0.hasSuffix(".") ? $0 : $0 + "." }
        
        if bySentence.count > 1 {
            return bySentence
        }
        
        // Single block
        return [cleaned]
    }
    
    // MARK: - View Details Button
    private var viewDetailsButton: some View {
        Button {
            HapticManager.tap()
            showingRecipeDetail = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "eye.fill")
                    .font(.system(size: 16, weight: .semibold))
                Text("View Full Details")
                    .font(.headline)
                    .fontWeight(.bold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [.blue, .cyan],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .blue.opacity(0.4), radius: 10, x: 0, y: 5)
        }
    }
    
    // MARK: - Extract Recipe
    private func extractRecipe() {
        guard !urlText.isEmpty else { return }
        
        isExtracting = true
        showRecipeContent = false
        HapticManager.tap()
        
        Task {
            let recipe = await advancedService.extractRecipeFromURL(urlString: urlText)
            
            await MainActor.run {
                if let recipe = recipe {
                    extractedRecipe = recipe
                    // Animate the recipe content in
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        showRecipeContent = true
                    }
                    HapticManager.success()
                } else {
                    errorMessage = "Could not extract recipe from this URL. Please try a different recipe page."
                    showError = true
                }
                isExtracting = false
            }
        }
    }
}

// MARK: - Nutrition Pill
struct NutritionPill: View {
    let label: String
    let value: String
    let color: Color
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(color)
            
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(color.opacity(colorScheme == .dark ? 0.15 : 0.1))
        )
    }
}

// MARK: - Restaurant Search Sheet
struct RestaurantSearchSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var userManager: UserManager
    @StateObject private var advancedService = SpoonacularAdvancedService.shared
    
    @State private var searchQuery: String = ""
    @State private var isSearching = false
    @State private var menuItems: [MenuItem] = []
    @State private var selectedMenuItem: MenuItem?
    @State private var menuItemDetail: MenuItemDetail?
    @State private var showingMealPicker = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                (colorScheme == .dark ? Color.black : Color(white: 0.95))
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Search bar
                    searchBar
                    
                    // Results
                    if isSearching {
                        ProgressView("Searching...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if menuItems.isEmpty && !searchQuery.isEmpty {
                        emptyState
                    } else {
                        resultsList
                    }
                }
            }
            .navigationTitle("Restaurant Foods")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showingMealPicker) {
                if let detail = menuItemDetail {
                    MenuItemAddSheet(menuItem: detail)
                }
            }
        }
    }
    
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("Search restaurant foods...", text: $searchQuery)
                .onSubmit { searchMenuItems() }
            
            if !searchQuery.isEmpty {
                Button(action: { searchQuery = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color(white: 0.12) : Color.white)
        )
        .padding()
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "fork.knife.circle")
                .font(.system(size: 50))
                .foregroundColor(.orange.opacity(0.5))
            
            Text("No results found")
                .font(.headline)
            
            Text("Try searching for a restaurant or menu item")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(menuItems) { item in
                    MenuItemRow(item: item) {
                        selectMenuItem(item)
                    }
                }
            }
            .padding()
        }
    }
    
    private func searchMenuItems() {
        guard !searchQuery.isEmpty else { return }
        
        isSearching = true
        
        Task {
            let results = await advancedService.searchMenuItems(query: searchQuery, number: 20)
            
            await MainActor.run {
                menuItems = results
                isSearching = false
            }
        }
    }
    
    private func selectMenuItem(_ item: MenuItem) {
        Task {
            if let detail = await advancedService.getMenuItemDetails(menuItemId: item.id) {
                await MainActor.run {
                    menuItemDetail = detail
                    showingMealPicker = true
                }
            }
        }
    }
}

// MARK: - Menu Item Row
struct MenuItemRow: View {
    let item: MenuItem
    let onSelect: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 14) {
                // Image
                AsyncImage(url: item.imageURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    ZStack {
                        Color.orange.opacity(0.2)
                        Image(systemName: "fork.knife")
                            .foregroundColor(.orange)
                    }
                }
                .frame(width: 60, height: 60)
                .cornerRadius(10)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    
                    if let restaurant = item.restaurantChain {
                        Text(restaurant)
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    
                    if let serving = item.servingSize {
                        Text(serving)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundColor(.orange)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(colorScheme == .dark ? Color(white: 0.12) : Color.white)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Menu Item Add Sheet
struct MenuItemAddSheet: View {
    let menuItem: MenuItemDetail
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var userManager: UserManager
    @State private var selectedMealType: MealType = .lunch
    @State private var servings: Int = 1
    
    var body: some View {
        NavigationStack {
            ZStack {
                (colorScheme == .dark ? Color.black : Color(white: 0.95))
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Food info
                        VStack(alignment: .leading, spacing: 12) {
                            Text(menuItem.title)
                                .font(.title3)
                                .fontWeight(.bold)
                            
                            if let restaurant = menuItem.restaurantChain {
                                HStack {
                                    Image(systemName: "building.2")
                                        .foregroundColor(.orange)
                                    Text(restaurant)
                                        .foregroundColor(.secondary)
                                }
                                .font(.subheadline)
                            }
                            
                            // Nutrition
                            HStack(spacing: 16) {
                                NutritionPill(label: "Cal", value: "\(menuItem.calories * servings)", color: .orange)
                                NutritionPill(label: "Protein", value: "\(Int(menuItem.protein * Double(servings)))g", color: .blue)
                                NutritionPill(label: "Carbs", value: "\(Int(menuItem.carbs * Double(servings)))g", color: .green)
                                NutritionPill(label: "Fat", value: "\(Int(menuItem.fat * Double(servings)))g", color: .purple)
                            }
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(colorScheme == .dark ? Color(white: 0.12) : Color.white)
                        )
                        
                        // Servings
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Servings")
                                .font(.headline)
                            
                            HStack {
                                Button(action: { if servings > 1 { servings -= 1 } }) {
                                    Image(systemName: "minus.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(servings > 1 ? .orange : .gray)
                                }
                                .disabled(servings <= 1)
                                
                                Text("\(servings)")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .frame(minWidth: 50)
                                
                                Button(action: { servings += 1 }) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(.orange)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(colorScheme == .dark ? Color(white: 0.12) : Color.white)
                        )
                        
                        // Meal type
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Add to Meal")
                                .font(.headline)
                            
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                ForEach(MealType.allCases, id: \.self) { meal in
                                    MealTypeButton(
                                        mealType: meal,
                                        isSelected: selectedMealType == meal,
                                        action: { selectedMealType = meal }
                                    )
                                }
                            }
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(colorScheme == .dark ? Color(white: 0.12) : Color.white)
                        )
                        
                        // Add button
                        Button(action: addToMeal) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text("Add to \(selectedMealType.displayName)")
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(colors: [.orange, .red.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
                            )
                            .cornerRadius(14)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Add to Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
    
    private func addToMeal() {
        guard let user = userManager.currentUser else { return }
        
        let foodEntry = FoodEntry(
            name: menuItem.title,
            quantity: servings,
            unit: "serving",
            calories: menuItem.calories * servings,
            protein: Int(menuItem.protein * Double(servings)),
            carbs: Int(menuItem.carbs * Double(servings)),
            fat: Int(menuItem.fat * Double(servings)),
            fdcId: menuItem.id,
            foodItemId: menuItem.id
        )
        
        MealService.shared.addMealEntry(foodEntry, mealType: selectedMealType, user: user)
        HapticManager.success()
        dismiss()
    }
}

// MARK: - Preview
#Preview {
    RecipeImportSheet()
}
