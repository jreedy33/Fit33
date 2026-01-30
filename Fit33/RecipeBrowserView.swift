import SwiftUI

// MARK: - Recipe Browser View
/// Full-screen recipe browser with search and ingredient filtering
struct RecipeBrowserView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel = RecipeBrowserViewModel()
    @ObservedObject private var premiumManager = PremiumManager.shared
    @State private var selectedRecipe: SpoonacularRecipe?
    @State private var showingRecipeDetail = false
    @State private var showingPremiumUpgrade = false
    
    // Free users can only view 1 recipe
    private let freeRecipeLimit = 1
    @State private var viewedRecipeIds: Set<Int> = []
    
    var body: some View {
        ZStack {
            // Background
            backgroundGradient
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Search Header
                searchHeader
                
                // Filter Chips
                filterChipsSection
                
                // Content
                if viewModel.isLoading && viewModel.recipes.isEmpty {
                    loadingView
                } else if let error = viewModel.errorMessage {
                    errorView(error)
                } else if viewModel.recipes.isEmpty {
                    emptyStateView
                } else {
                    recipeGrid
                }
            }
        }
        .navigationTitle("Healthy Recipes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    // Sort options
                    Section("Sort By") {
                        Button {
                            viewModel.sortOption = .healthiness
                            Task { await viewModel.searchRecipes() }
                        } label: {
                            Label("Healthiness", systemImage: viewModel.sortOption == .healthiness ? "checkmark" : "")
                        }
                        
                        Button {
                            viewModel.sortOption = .protein
                            Task { await viewModel.searchRecipes() }
                        } label: {
                            Label("Protein", systemImage: viewModel.sortOption == .protein ? "checkmark" : "")
                        }
                        
                        Button {
                            viewModel.sortOption = .calories
                            Task { await viewModel.searchRecipes() }
                        } label: {
                            Label("Calories", systemImage: viewModel.sortOption == .calories ? "checkmark" : "")
                        }
                        
                        Button {
                            viewModel.sortOption = .time
                            Task { await viewModel.searchRecipes() }
                        } label: {
                            Label("Cook Time", systemImage: viewModel.sortOption == .time ? "checkmark" : "")
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down.circle")
                        .font(.body)
                }
            }
        }
        .task {
            await viewModel.searchRecipes()
        }
        .background(
            NavigationLink(
                destination: Group {
                    if let recipe = selectedRecipe {
                        RecipeDetailView(recipeId: recipe.id, initialRecipe: recipe)
                    }
                },
                isActive: $showingRecipeDetail
            ) {
                EmptyView()
            }
            .hidden()
        )
        .fullScreenCover(isPresented: $showingPremiumUpgrade) {
            PremiumUpgradeView(
                triggeringFeature: .recipes,
                onUpgrade: { plan in
                    print("User selected plan: \(plan.rawValue)")
                    showingPremiumUpgrade = false
                },
                onRestore: {
                    showingPremiumUpgrade = false
                }
            )
        }
    }
    
    // MARK: - Search Header
    private var searchHeader: some View {
        VStack(spacing: 12) {
            // Search bar
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.body)
                    .foregroundColor(.secondary)
                
                TextField("Search recipes...", text: $viewModel.searchQuery)
                    .textFieldStyle(PlainTextFieldStyle())
                    .submitLabel(.search)
                    .onSubmit {
                        Task { await viewModel.searchRecipes() }
                    }
                
                if !viewModel.searchQuery.isEmpty {
                    Button {
                        viewModel.searchQuery = ""
                        Task { await viewModel.searchRecipes() }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? Color(white: 0.15) : .white)
                    .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
            )
            
            // Ingredient input
            HStack(spacing: 12) {
                Image(systemName: "leaf.fill")
                    .font(.body)
                    .foregroundColor(.green)
                
                TextField("Filter by ingredients (comma separated)...", text: $viewModel.ingredientsQuery)
                    .textFieldStyle(PlainTextFieldStyle())
                    .submitLabel(.search)
                    .onSubmit {
                        Task { await viewModel.searchByIngredients() }
                    }
                
                if !viewModel.ingredientsQuery.isEmpty {
                    Button {
                        Task { await viewModel.searchByIngredients() }
                    } label: {
                        Text("Find")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.green)
                            .cornerRadius(8)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? Color(white: 0.15) : .white)
                    .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    // MARK: - Filter Chips
    private var filterChipsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                // Diet filters
                ForEach(DietFilter.allCases, id: \.self) { diet in
                    RecipeFilterChip(
                        title: diet.displayName,
                        isSelected: viewModel.selectedDiet == diet,
                        color: diet.color
                    ) {
                        if viewModel.selectedDiet == diet {
                            viewModel.selectedDiet = nil
                        } else {
                            viewModel.selectedDiet = diet
                        }
                        Task { await viewModel.searchRecipes() }
                    }
                }
                
                Divider()
                    .frame(height: 24)
                
                // Quick filters
                ForEach(QuickFilter.allCases, id: \.self) { filter in
                    RecipeFilterChip(
                        title: filter.displayName,
                        isSelected: viewModel.selectedQuickFilter == filter,
                        color: filter.color
                    ) {
                        if viewModel.selectedQuickFilter == filter {
                            viewModel.selectedQuickFilter = nil
                        } else {
                            viewModel.selectedQuickFilter = filter
                        }
                        Task { await viewModel.searchRecipes() }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 8)
    }
    
    // MARK: - Recipe Grid
    private var recipeGrid: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16)
            ], spacing: 16) {
                ForEach(Array(viewModel.recipes.enumerated()), id: \.element.id) { index, recipe in
                    // First recipe is always free, rest require premium
                    let isLocked = !premiumManager.isPremiumUser && index >= freeRecipeLimit
                    
                    PremiumRecipeGridCard(recipe: recipe, isLocked: isLocked) {
                        if isLocked {
                            showingPremiumUpgrade = true
                        } else {
                            selectedRecipe = recipe
                            showingRecipeDetail = true
                            viewedRecipeIds.insert(recipe.id)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            // Load more button
            if viewModel.hasMoreResults {
                Button {
                    Task { await viewModel.loadMore() }
                } label: {
                    if viewModel.isLoadingMore {
                        ProgressView()
                            .tint(.orange)
                    } else {
                        Text("Load More")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.orange)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
        }
        .refreshable {
            await viewModel.searchRecipes()
        }
    }
    
    // MARK: - Loading View
    private var loadingView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            ProgressView()
                .scaleEffect(1.5)
                .tint(.orange)
            
            Text("Finding delicious recipes...")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
        }
    }
    
    // MARK: - Error View
    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            
            Text("Something went wrong")
                .font(.headline)
            
            Text(error)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button {
                Task { await viewModel.searchRecipes() }
            } label: {
                Label("Try Again", systemImage: "arrow.clockwise")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.orange)
                    .cornerRadius(12)
            }
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "fork.knife")
                .font(.system(size: 56))
                .foregroundColor(.secondary)
            
            Text("No recipes found")
                .font(.headline)
            
            Text("Try adjusting your search or filters")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Button {
                viewModel.clearFilters()
                Task { await viewModel.searchRecipes() }
            } label: {
                Label("Clear Filters", systemImage: "xmark.circle")
                    .font(.subheadline)
                    .foregroundColor(.orange)
            }
            
            Spacer()
        }
    }
    
    // MARK: - Background
    private var backgroundGradient: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color(white: 0.08), Color(white: 0.05)]
                : [Color(red: 0.98, green: 0.96, blue: 0.94), .white],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Recipe Browser ViewModel
@MainActor
class RecipeBrowserViewModel: ObservableObject {
    @Published var recipes: [SpoonacularRecipe] = []
    @Published var searchQuery = ""
    @Published var ingredientsQuery = ""
    @Published var selectedDiet: DietFilter?
    @Published var selectedQuickFilter: QuickFilter?
    @Published var sortOption: SortOption = .healthiness
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var errorMessage: String?
    @Published var hasMoreResults = true
    
    private var currentOffset = 0
    private let pageSize = 20
    private let apiKey = "69f4b06727ac448d88841e2ce717a228"
    private let baseURL = "https://api.spoonacular.com"
    
    enum SortOption: String {
        case healthiness = "healthiness"
        case protein = "protein"
        case calories = "calories"
        case time = "time"
    }
    
    func searchRecipes() async {
        isLoading = true
        errorMessage = nil
        currentOffset = 0
        
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "apiKey", value: apiKey),
            URLQueryItem(name: "number", value: String(pageSize)),
            URLQueryItem(name: "offset", value: "0"),
            URLQueryItem(name: "addRecipeNutrition", value: "true"),
            URLQueryItem(name: "sort", value: sortOption.rawValue),
            URLQueryItem(name: "sortDirection", value: sortOption == .calories ? "asc" : "desc")
        ]
        
        // Add search query
        if !searchQuery.isEmpty {
            queryItems.append(URLQueryItem(name: "query", value: searchQuery))
        } else {
            queryItems.append(URLQueryItem(name: "query", value: "healthy"))
        }
        
        // Add diet filter
        if let diet = selectedDiet {
            queryItems.append(URLQueryItem(name: "diet", value: diet.apiValue))
        }
        
        // Add quick filter constraints
        if let quickFilter = selectedQuickFilter {
            switch quickFilter {
            case .highProtein:
                queryItems.append(URLQueryItem(name: "minProtein", value: "30"))
            case .lowCarb:
                queryItems.append(URLQueryItem(name: "maxCarbs", value: "20"))
            case .lowCalorie:
                queryItems.append(URLQueryItem(name: "maxCalories", value: "400"))
            case .quickMeals:
                queryItems.append(URLQueryItem(name: "maxReadyTime", value: "30"))
            }
        }
        
        var urlComponents = URLComponents(string: "\(baseURL)/recipes/complexSearch")!
        urlComponents.queryItems = queryItems
        
        guard let url = urlComponents.url else {
            errorMessage = "Invalid URL"
            isLoading = false
            return
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            
            let decoder = JSONDecoder()
            let searchResponse = try decoder.decode(RecipeSearchResponse.self, from: data)
            
            recipes = searchResponse.results
            hasMoreResults = searchResponse.totalResults > pageSize
            currentOffset = pageSize
            
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func searchByIngredients() async {
        guard !ingredientsQuery.isEmpty else {
            await searchRecipes()
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        let ingredients = ingredientsQuery
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: ",+")
        
        let url = URL(string: "\(baseURL)/recipes/findByIngredients?apiKey=\(apiKey)&ingredients=\(ingredients)&number=\(pageSize)&ranking=1&ignorePantry=true")!
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            
            let decoder = JSONDecoder()
            let ingredientRecipes = try decoder.decode([IngredientSearchRecipe].self, from: data)
            
            // Convert to SpoonacularRecipe format
            recipes = ingredientRecipes.map { recipe in
                SpoonacularRecipe(
                    id: recipe.id,
                    title: recipe.title,
                    image: recipe.image,
                    imageType: recipe.imageType,
                    nutrition: nil
                )
            }
            hasMoreResults = false
            
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func loadMore() async {
        guard !isLoadingMore && hasMoreResults else { return }
        
        isLoadingMore = true
        
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "apiKey", value: apiKey),
            URLQueryItem(name: "number", value: String(pageSize)),
            URLQueryItem(name: "offset", value: String(currentOffset)),
            URLQueryItem(name: "addRecipeNutrition", value: "true"),
            URLQueryItem(name: "sort", value: sortOption.rawValue),
            URLQueryItem(name: "sortDirection", value: sortOption == .calories ? "asc" : "desc")
        ]
        
        if !searchQuery.isEmpty {
            queryItems.append(URLQueryItem(name: "query", value: searchQuery))
        } else {
            queryItems.append(URLQueryItem(name: "query", value: "healthy"))
        }
        
        if let diet = selectedDiet {
            queryItems.append(URLQueryItem(name: "diet", value: diet.apiValue))
        }
        
        var urlComponents = URLComponents(string: "\(baseURL)/recipes/complexSearch")!
        urlComponents.queryItems = queryItems
        
        guard let url = urlComponents.url else {
            isLoadingMore = false
            return
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            
            let decoder = JSONDecoder()
            let searchResponse = try decoder.decode(RecipeSearchResponse.self, from: data)
            
            recipes.append(contentsOf: searchResponse.results)
            hasMoreResults = currentOffset + pageSize < searchResponse.totalResults
            currentOffset += pageSize
            
        } catch {
            print("Error loading more: \(error)")
        }
        
        isLoadingMore = false
    }
    
    func clearFilters() {
        searchQuery = ""
        ingredientsQuery = ""
        selectedDiet = nil
        selectedQuickFilter = nil
        sortOption = .healthiness
    }
}

// MARK: - Supporting Types

enum DietFilter: String, CaseIterable {
    case vegetarian
    case vegan
    case glutenFree
    case ketogenic
    case paleo
    
    var displayName: String {
        switch self {
        case .vegetarian: return "Vegetarian"
        case .vegan: return "Vegan"
        case .glutenFree: return "Gluten-Free"
        case .ketogenic: return "Keto"
        case .paleo: return "Paleo"
        }
    }
    
    var apiValue: String {
        switch self {
        case .vegetarian: return "vegetarian"
        case .vegan: return "vegan"
        case .glutenFree: return "gluten free"
        case .ketogenic: return "ketogenic"
        case .paleo: return "paleo"
        }
    }
    
    var color: Color {
        switch self {
        case .vegetarian: return .green
        case .vegan: return .mint
        case .glutenFree: return .orange
        case .ketogenic: return .purple
        case .paleo: return .brown
        }
    }
}

enum QuickFilter: String, CaseIterable {
    case highProtein
    case lowCarb
    case lowCalorie
    case quickMeals
    
    var displayName: String {
        switch self {
        case .highProtein: return "High Protein"
        case .lowCarb: return "Low Carb"
        case .lowCalorie: return "Low Calorie"
        case .quickMeals: return "Quick (<30min)"
        }
    }
    
    var color: Color {
        switch self {
        case .highProtein: return .blue
        case .lowCarb: return .indigo
        case .lowCalorie: return .pink
        case .quickMeals: return .cyan
        }
    }
}

// MARK: - Ingredient Search Response
struct IngredientSearchRecipe: Codable, Identifiable {
    let id: Int
    let title: String
    let image: String?
    let imageType: String?
    let usedIngredientCount: Int?
    let missedIngredientCount: Int?
    let likes: Int?
}

// MARK: - Recipe Filter Chip
struct RecipeFilterChip: View {
    let title: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(isSelected ? .white : color)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isSelected ? color : color.opacity(0.15))
                )
                .overlay(
                    Capsule()
                        .stroke(color.opacity(isSelected ? 0 : 0.3), lineWidth: 1)
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Premium Recipe Grid Card
/// Grid card with premium lock overlay for non-premium users
struct PremiumRecipeGridCard: View {
    let recipe: SpoonacularRecipe
    let isLocked: Bool
    let onTap: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var isPressed = false
    @State private var lockGlowRotation: Double = 0
    
    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Base card content
                cardContent
                
                // Lock overlay
                if isLocked {
                    lockOverlay
                }
            }
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
        }
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
        .onAppear {
            if isLocked {
                withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                    lockGlowRotation = 360
                }
            }
        }
    }
    
    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Image
            ZStack(alignment: .bottomTrailing) {
                AsyncImage(url: recipe.imageURL) { phase in
                    switch phase {
                    case .empty:
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [.orange.opacity(0.3), .red.opacity(0.2)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(ProgressView().tint(.white))
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [.orange.opacity(0.3), .red.opacity(0.2)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(
                                Image(systemName: "photo")
                                    .foregroundColor(.white.opacity(0.5))
                            )
                    @unknown default:
                        Rectangle().fill(Color.gray.opacity(0.3))
                    }
                }
                .frame(height: 120)
                .clipped()
                
                // Calorie badge
                if recipe.calories > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "flame.fill")
                            .font(.caption2)
                        Text("\(recipe.calories)")
                            .font(.caption2)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.6))
                    )
                    .padding(8)
                }
            }
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 12,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 12
                )
            )
            
            // Info
            VStack(alignment: .leading, spacing: 6) {
                Text(recipe.displayTitle)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(height: 40, alignment: .topLeading)
                
                // Macros
                if recipe.protein > 0 || recipe.carbs > 0 {
                    HStack(spacing: 8) {
                        MacroLabel(value: recipe.protein, label: "P", color: .blue)
                        MacroLabel(value: recipe.carbs, label: "C", color: .orange)
                        MacroLabel(value: recipe.fat, label: "F", color: .purple)
                    }
                }
            }
            .padding(12)
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color(white: 0.12) : .white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .shadow(
            color: .black.opacity(colorScheme == .dark ? 0.3 : 0.1),
            radius: isPressed ? 2 : 6,
            x: 0,
            y: isPressed ? 1 : 3
        )
        .blur(radius: isLocked ? 1.5 : 0)
    }
    
    private var lockOverlay: some View {
        ZStack {
            // Semi-transparent overlay
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.45))
            
            // Lock content
            VStack(spacing: 8) {
                // Crown with glow
                ZStack {
                    // Rotating glow
                    Circle()
                        .stroke(
                            AngularGradient(
                                colors: [
                                    .purple.opacity(0.7),
                                    .blue.opacity(0.3),
                                    .purple.opacity(0.1),
                                    .clear,
                                    .purple.opacity(0.1),
                                    .blue.opacity(0.3),
                                    .purple.opacity(0.7)
                                ],
                                center: .center,
                                startAngle: .degrees(lockGlowRotation),
                                endAngle: .degrees(lockGlowRotation + 360)
                            ),
                            lineWidth: 2
                        )
                        .frame(width: 44, height: 44)
                        .blur(radius: 2)
                    
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(white: 0.16), Color(white: 0.08)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 38, height: 38)
                    
                    Image(systemName: "crown.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.yellow, .orange],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                
                // PRO badge
                HStack(spacing: 3) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9))
                    Text("PRO")
                        .font(.caption2)
                        .fontWeight(.bold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.purple, .blue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
                .shadow(color: .purple.opacity(0.4), radius: 4, x: 0, y: 2)
            }
        }
    }
}

// MARK: - Recipe Grid Card (Legacy)
struct RecipeGridCard: View {
    let recipe: SpoonacularRecipe
    let onTap: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var isPressed = false
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                // Image
                ZStack(alignment: .bottomTrailing) {
                    AsyncImage(url: recipe.imageURL) { phase in
                        switch phase {
                        case .empty:
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: [.orange.opacity(0.3), .red.opacity(0.2)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .overlay(ProgressView().tint(.white))
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        case .failure:
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: [.orange.opacity(0.3), .red.opacity(0.2)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .overlay(
                                    Image(systemName: "photo")
                                        .foregroundColor(.white.opacity(0.5))
                                )
                        @unknown default:
                            Rectangle().fill(Color.gray.opacity(0.3))
                        }
                    }
                    .frame(height: 120)
                    .clipped()
                    
                    // Calorie badge
                    if recipe.calories > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "flame.fill")
                                .font(.caption2)
                            Text("\(recipe.calories)")
                                .font(.caption2)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(0.6))
                        )
                        .padding(8)
                    }
                }
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 12,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 12
                    )
                )
                
                // Info
                VStack(alignment: .leading, spacing: 6) {
                    Text(recipe.displayTitle)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(height: 40, alignment: .topLeading)
                    
                    // Macros
                    if recipe.protein > 0 || recipe.carbs > 0 {
                        HStack(spacing: 8) {
                            MacroLabel(value: recipe.protein, label: "P", color: .blue)
                            MacroLabel(value: recipe.carbs, label: "C", color: .orange)
                            MacroLabel(value: recipe.fat, label: "F", color: .purple)
                        }
                    }
                }
                .padding(12)
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? Color(white: 0.12) : .white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
            .shadow(
                color: .black.opacity(colorScheme == .dark ? 0.3 : 0.1),
                radius: isPressed ? 2 : 6,
                x: 0,
                y: isPressed ? 1 : 3
            )
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
        }
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }
}

struct MacroLabel: View {
    let value: Int
    let label: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 2) {
            Text("\(value)")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Preview
#Preview {
    NavigationView {
        RecipeBrowserView()
    }
}
