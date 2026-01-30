import SwiftUI

// MARK: - Healthy Recipes Carousel
/// A beautiful horizontal scrolling carousel showcasing healthy recipes from Spoonacular
struct HealthyRecipesCarousel: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var spoonacularService = SpoonacularService.shared
    @StateObject private var preferenceService = RecipePreferenceService.shared
    @ObservedObject private var premiumManager = PremiumManager.shared
    @State private var selectedRecipe: SpoonacularRecipe?
    @State private var showingRecipeDetail = false
    @State private var showingRecipeBrowser = false
    @State private var showingPremiumUpgrade = false
    @State private var displayedRecipes: [SpoonacularRecipe] = []
    @State private var isPersonalized = false
    @State private var refreshTimer: Timer?
    @State private var viewedRecipeCount = 0
    
    // Free users can only view 1 recipe
    private let freeRecipeLimit = 1
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "fork.knife.circle.fill")
                            .font(.title2)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.orange, .red],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        Text(isPersonalized ? "Recommended for You" : "Healthy Recipes")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                    }
                    
                    Text(subtitleText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // See All button
                Button {
                    showingRecipeBrowser = true
                } label: {
                    HStack(spacing: 4) {
                        Text("See all")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                    }
                    .foregroundColor(.orange)
                }
            }
            .padding(.horizontal, 4)
            
            // Content
            if (spoonacularService.isLoading || preferenceService.isLoadingRecommendations) && displayedRecipes.isEmpty {
                loadingView
            } else if let error = spoonacularService.errorMessage {
                errorView(error)
            } else if displayedRecipes.isEmpty {
                emptyStateView
            } else {
                recipeCarousel
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 16)
        .background(carouselBackground)
        .onAppear {
            loadRecipes()
            startRefreshTimer()
        }
        .onDisappear {
            stopRefreshTimer()
        }
        .background(
            Group {
                // Recipe Detail Navigation
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
                
                // Recipe Browser Navigation (See All)
                NavigationLink(
                    destination: RecipeBrowserView(),
                    isActive: $showingRecipeBrowser
                ) {
                    EmptyView()
                }
            }
            .hidden()
        )
        .fullScreenCover(isPresented: $showingPremiumUpgrade) {
            PremiumUpgradeView(
                triggeringFeature: .recipes,
                onUpgrade: { plan in
                    // Handle upgrade flow - this would connect to your payment system
                    print("User selected plan: \(plan.rawValue)")
                    showingPremiumUpgrade = false
                },
                onRestore: {
                    // Handle restore purchases
                    showingPremiumUpgrade = false
                }
            )
        }
    }
    
    // MARK: - Recipe Carousel
    private var recipeCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(Array(displayedRecipes.prefix(8).enumerated()), id: \.element.id) { index, recipe in
                    // First recipe is always free, rest require premium
                    let isLocked = !premiumManager.isPremiumUser && index >= freeRecipeLimit
                    
                    PremiumRecipeCard(
                        recipe: recipe,
                        isLocked: isLocked,
                        onTap: {
                            if isLocked {
                                // Show premium upgrade
                                showingPremiumUpgrade = true
                            } else {
                                selectedRecipe = recipe
                                showingRecipeDetail = true
                                viewedRecipeCount += 1
                                // Track view interaction
                                preferenceService.trackRecipeView(recipe: recipe)
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Subtitle Text
    private var subtitleText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        
        if isPersonalized {
            return "Based on your preferences"
        }
        
        switch hour {
        case 5..<11:
            return "Healthy breakfast ideas"
        case 11..<15:
            return "Nutritious lunch options"
        case 15..<18:
            return "Protein-packed snacks"
        default:
            return "Delicious dinner recipes"
        }
    }
    
    // MARK: - Load Recipes
    private func loadRecipes() {
        Task {
            // Check if we should refresh or use cached
            if preferenceService.shouldRefreshCarousel() {
                // Try to get personalized recommendations
                let personalized = await preferenceService.getRotatedCarouselRecipes(count: 10)
                
                if !personalized.isEmpty {
                    displayedRecipes = personalized
                    isPersonalized = true
                } else {
                    // Fall back to time-based suggestions
                    let timeBased = await preferenceService.getMealSuggestionsForCurrentTime(count: 10)
                    
                    if !timeBased.isEmpty {
                        displayedRecipes = timeBased
                        isPersonalized = false
                    } else {
                        // Fall back to default healthy recipes
                        await spoonacularService.fetchHealthyRecipes()
                        displayedRecipes = spoonacularService.healthyRecipes
                        isPersonalized = false
                    }
                }
            } else if displayedRecipes.isEmpty {
                // First load - get default recipes
                await spoonacularService.fetchHealthyRecipes()
                displayedRecipes = spoonacularService.healthyRecipes
            }
        }
    }
    
    // MARK: - Refresh Timer (rotates recipes every 4 hours)
    private func startRefreshTimer() {
        // Check every 30 minutes if we should refresh
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { _ in
            if preferenceService.shouldRefreshCarousel() {
                loadRecipes()
            }
        }
    }
    
    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    // MARK: - Loading View
    private var loadingView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(0..<4, id: \.self) { _ in
                    RecipeCardSkeleton()
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Error View
    private func errorView(_ error: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title)
                .foregroundColor(.orange)
            
            Text(error)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button {
                Task {
                    await spoonacularService.fetchHealthyRecipes()
                }
            } label: {
                Label("Try Again", systemImage: "arrow.clockwise")
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.orange)
                    .cornerRadius(8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
    
    // MARK: - Empty State View
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "fork.knife")
                .font(.title)
                .foregroundColor(.secondary)
            
            Text("No recipes available")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Button {
                Task {
                    await spoonacularService.fetchHealthyRecipes()
                }
            } label: {
                Label("Load Recipes", systemImage: "arrow.down.circle")
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.mint)
                    .cornerRadius(8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
    
    // MARK: - Background
    private var carouselBackground: some View {
        ZStack {
            // Bottom shadow layer
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.orange.opacity(colorScheme == .dark ? 0.12 : 0.06))
                .offset(y: 8)
                .blur(radius: 4)
            
            // Middle shadow
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                .offset(y: 4)
            
            // Main background
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color(white: 0.13), Color(white: 0.10)]
                            : [Color.white, Color.white.opacity(0.95)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            
            // Inner highlight
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color.white.opacity(0.08), Color.clear]
                            : [Color.white, Color.white.opacity(0.5)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            
            // Accent border
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.orange.opacity(colorScheme == .dark ? 0.3 : 0.2),
                            Color.red.opacity(colorScheme == .dark ? 0.2 : 0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 12, x: 0, y: 6)
    }
}

// MARK: - Premium Recipe Card
/// Recipe card with premium lock overlay for non-premium users
struct PremiumRecipeCard: View {
    let recipe: SpoonacularRecipe
    let isLocked: Bool
    let onTap: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var isPressed = false
    @State private var lockGlowRotation: Double = 0
    
    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Base recipe card
                recipeCardContent
                
                // Lock overlay for premium content
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
    
    private var recipeCardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Image Section
            ZStack(alignment: .bottomLeading) {
                // Recipe Image
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
                            .overlay(
                                ProgressView()
                                    .tint(.white)
                            )
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
                                    .font(.title)
                                    .foregroundColor(.white.opacity(0.6))
                            )
                    @unknown default:
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                    }
                }
                .frame(width: 180, height: 120)
                .clipped()
                
                // Gradient overlay for text readability
                LinearGradient(
                    colors: [.clear, .black.opacity(0.6)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                
                // Calorie badge
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.caption2)
                    Text("\(recipe.calories) cal")
                        .font(.caption2)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.5))
                        .background(
                            Capsule()
                                .fill(.ultraThinMaterial)
                        )
                )
                .padding(8)
            }
            .frame(width: 180, height: 120)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 14,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 14
                )
            )
            
            // Info Section
            VStack(alignment: .leading, spacing: 8) {
                // Title
                Text(recipe.displayTitle)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(height: 40, alignment: .topLeading)
                
                // Macros Row
                HStack(spacing: 12) {
                    RecipeMacroBadge(value: recipe.protein, label: "P", color: .blue)
                    RecipeMacroBadge(value: recipe.carbs, label: "C", color: .orange)
                    RecipeMacroBadge(value: recipe.fat, label: "F", color: .purple)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(width: 180, alignment: .leading)
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(colorScheme == .dark ? Color(white: 0.15) : .white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    colorScheme == .dark
                        ? Color.white.opacity(0.1)
                        : Color.black.opacity(0.05),
                    lineWidth: 1
                )
        )
        .shadow(
            color: .black.opacity(colorScheme == .dark ? 0.4 : 0.12),
            radius: isPressed ? 4 : 8,
            x: 0,
            y: isPressed ? 2 : 4
        )
        .blur(radius: isLocked ? 2 : 0)
    }
    
    private var lockOverlay: some View {
        ZStack {
            // Dark overlay
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(0.5))
            
            // Lock content
            VStack(spacing: 10) {
                // Crown with animated glow
                ZStack {
                    // Rotating glow
                    Circle()
                        .stroke(
                            AngularGradient(
                                colors: [
                                    .purple.opacity(0.8),
                                    .blue.opacity(0.4),
                                    .purple.opacity(0.1),
                                    .clear,
                                    .purple.opacity(0.1),
                                    .blue.opacity(0.4),
                                    .purple.opacity(0.8)
                                ],
                                center: .center,
                                startAngle: .degrees(lockGlowRotation),
                                endAngle: .degrees(lockGlowRotation + 360)
                            ),
                            lineWidth: 2
                        )
                        .frame(width: 52, height: 52)
                        .blur(radius: 3)
                    
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(white: 0.18), Color(white: 0.1)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 46, height: 46)
                    
                    Image(systemName: "crown.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.yellow, .orange],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                
                // Premium badge
                HStack(spacing: 4) {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                    Text("PRO")
                        .font(.caption)
                        .fontWeight(.bold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
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
                .shadow(color: .purple.opacity(0.4), radius: 6, x: 0, y: 3)
                
                Text("Tap to unlock")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }
}

// MARK: - Recipe Card (Legacy - kept for compatibility)
struct RecipeCard: View {
    let recipe: SpoonacularRecipe
    let onTap: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var isPressed = false
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                // Image Section
                ZStack(alignment: .bottomLeading) {
                    // Recipe Image
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
                                .overlay(
                                    ProgressView()
                                        .tint(.white)
                                )
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
                                        .font(.title)
                                        .foregroundColor(.white.opacity(0.6))
                                )
                        @unknown default:
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                        }
                    }
                    .frame(width: 180, height: 120)
                    .clipped()
                    
                    // Gradient overlay for text readability
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.6)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    
                    // Calorie badge
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .font(.caption2)
                        Text("\(recipe.calories) cal")
                            .font(.caption2)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.5))
                            .background(
                                Capsule()
                                    .fill(.ultraThinMaterial)
                            )
                    )
                    .padding(8)
                }
                .frame(width: 180, height: 120)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 14,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 14
                    )
                )
                
                // Info Section
                VStack(alignment: .leading, spacing: 8) {
                    // Title
                    Text(recipe.displayTitle)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(height: 40, alignment: .topLeading)
                    
                    // Macros Row
                    HStack(spacing: 12) {
                        RecipeMacroBadge(value: recipe.protein, label: "P", color: .blue)
                        RecipeMacroBadge(value: recipe.carbs, label: "C", color: .orange)
                        RecipeMacroBadge(value: recipe.fat, label: "F", color: .purple)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(width: 180, alignment: .leading)
            }
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(colorScheme == .dark ? Color(white: 0.15) : .white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        colorScheme == .dark
                            ? Color.white.opacity(0.1)
                            : Color.black.opacity(0.05),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: .black.opacity(colorScheme == .dark ? 0.4 : 0.12),
                radius: isPressed ? 4 : 8,
                x: 0,
                y: isPressed ? 2 : 4
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

// MARK: - Recipe Macro Badge
struct RecipeMacroBadge: View {
    let value: Int
    let label: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 2) {
            Text("\(value)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Recipe Card Skeleton
struct RecipeCardSkeleton: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var isAnimating = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Image placeholder
            Rectangle()
                .fill(shimmerGradient)
                .frame(width: 180, height: 120)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 14,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 14
                    )
                )
            
            VStack(alignment: .leading, spacing: 8) {
                // Title placeholder
                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(shimmerGradient)
                        .frame(width: 150, height: 14)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(shimmerGradient)
                        .frame(width: 100, height: 14)
                }
                .frame(height: 40, alignment: .topLeading)
                
                // Macro placeholders
                HStack(spacing: 12) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(shimmerGradient)
                            .frame(width: 35, height: 16)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(width: 180)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(colorScheme == .dark ? Color(white: 0.15) : .white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    colorScheme == .dark
                        ? Color.white.opacity(0.1)
                        : Color.black.opacity(0.05),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false)) {
                isAnimating = true
            }
        }
    }
    
    private var shimmerGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.gray.opacity(0.2),
                Color.gray.opacity(0.3),
                Color.gray.opacity(0.2)
            ],
            startPoint: isAnimating ? .leading : .trailing,
            endPoint: isAnimating ? .trailing : .leading
        )
    }
}

// MARK: - Preview
#Preview {
    ScrollView {
        HealthyRecipesCarousel()
            .padding()
    }
    .background(Color(.systemGroupedBackground))
}
