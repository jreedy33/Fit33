import SwiftUI
import AVKit

// MARK: - Exercise Substitution View
// Beautiful, cohesive exercise swap interface matching app design

struct ExerciseSubstitutionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    let currentExercise: Exercise
    let onSelectReplacement: (Exercise) -> Void
    
    @State private var substitutes: [SubstituteExercise] = []
    @State private var isLoading = true
    @State private var selectedExercise: Exercise?
    @State private var filterType: FilterType = .all
    @State private var searchText = ""
    
    enum FilterType: String, CaseIterable {
        case all = "All"
        case sameEquipment = "Same Equipment"
        case bodyweight = "Bodyweight"
        case easier = "Easier"
        case harder = "Harder"
        
        var icon: String {
            switch self {
            case .all: return "square.grid.2x2"
            case .sameEquipment: return "dumbbell"
            case .bodyweight: return "figure.walk"
            case .easier: return "arrow.down.circle"
            case .harder: return "arrow.up.circle"
            }
        }
    }
    
    // Model for substitute with match info
    struct SubstituteExercise: Identifiable {
        let id = UUID()
        let exercise: Exercise
        let matchReason: MatchReason
        let matchScore: Int // 0-100
        
        enum MatchReason: String {
            case sameMuscle = "Same Muscles"
            case sameEquipment = "Same Equipment"
            case samePattern = "Same Movement"
            case easier = "Easier Variation"
            case harder = "Harder Variation"
            case popular = "Popular Alternative"
            case noEquipment = "No Equipment Needed"
            
            var icon: String {
                switch self {
                case .sameMuscle: return "figure.strengthtraining.traditional"
                case .sameEquipment: return "dumbbell.fill"
                case .samePattern: return "arrow.triangle.2.circlepath"
                case .easier: return "leaf.fill"
                case .harder: return "flame.fill"
                case .popular: return "star.fill"
                case .noEquipment: return "hand.raised.fill"
                }
            }
            
            var color: Color {
                switch self {
                case .sameMuscle: return .blue
                case .sameEquipment: return .green
                case .samePattern: return .purple
                case .easier: return .mint
                case .harder: return .orange
                case .popular: return .yellow
                case .noEquipment: return .cyan
                }
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Animated blue/cyan orb background
                AnimatedOrbBackground.exercises(colorScheme: colorScheme)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Current exercise header
                    currentExerciseHeader
                    
                    // Filter pills
                    filterPills
                    
                    // Search bar
                    searchBar
                    
                    // Substitutes list
                    if isLoading {
                        loadingView
                    } else if filteredSubstitutes.isEmpty {
                        emptyStateView
                    } else {
                        substitutesList
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.ds_labelMedium)
                            .foregroundColor(.primary)
                            .frame(width: 32, height: 32)
                            .background(
                                Circle()
                                    .fill(Color.cardBackground)
                            )
                    }
                }
                
                ToolbarItem(placement: .principal) {
                    Text("Swap Exercise")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if selectedExercise != nil {
                        Button("Swap") {
                            if let selected = selectedExercise {
                                onSelectReplacement(selected)
                                dismiss()
                            }
                        }
                        .font(.headline)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .onAppear {
            loadSubstitutes()
        }
    }
    
    // MARK: - Current Exercise Header
    
    private var currentExerciseHeader: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                // Video thumbnail
                ZStack {
                    RoundedRectangle(cornerRadius: CornerRadius.md)
                        .fill(categoryColor.opacity(0.2))
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: categoryIcon)
                        .font(.ds_heading1)
                        .foregroundColor(categoryColor)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Current Exercise")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(currentExercise.name ?? "Exercise")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    
                    HStack(spacing: 8) {
                        // Category badge
                        if let category = currentExercise.category {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(categoryColor)
                                    .frame(width: 6, height: 6)
                                Text(category)
                                    .font(.caption2)
                            }
                            .foregroundColor(categoryColor)
                            .padding(.horizontal, Spacing.xs)
                            .padding(.vertical, Spacing.xxs)
                            .background(
                                Capsule()
                                    .fill(categoryColor.opacity(0.15))
                            )
                        }
                        
                        // Equipment badge
                        if let equipment = currentExercise.equipment {
                            HStack(spacing: 4) {
                                Image(systemName: "dumbbell.fill")
                                    .font(.system(size: 8))
                                Text(equipment)
                                    .font(.caption2)
                            }
                            .foregroundColor(.secondary)
                            .padding(.horizontal, Spacing.xs)
                            .padding(.vertical, Spacing.xxs)
                            .background(
                                Capsule()
                                    .fill(Color.cardBackground)
                            )
                        }
                    }
                }
                
                Spacer()
            }
            .padding(Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .fill(Color.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.lg)
                            .stroke(
                                LinearGradient(
                                    colors: [categoryColor.opacity(0.3), Color.clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
            .padding(.horizontal, Spacing.md)
            .padding(.top, 8)
            
            // Arrow indicator
            Image(systemName: "arrow.down.circle.fill")
                .font(.title2)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }
    
    // MARK: - Filter Pills
    
    private var filterPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(FilterType.allCases, id: \.self) { filter in
                    FilterPill(
                        title: filter.rawValue,
                        icon: filter.icon,
                        isSelected: filterType == filter
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            filterType = filter
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
        }
    }
    
    // MARK: - Search Bar
    
    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("Search exercises...", text: $searchText)
                .font(.body)
            
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color(.systemGray6))
        )
        .padding(.horizontal, Spacing.md)
        .padding(.bottom, 8)
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            
            Text("Finding smart substitutes...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No substitutes found")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text("Try adjusting your filters")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Substitutes List
    
    private var substitutesList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(filteredSubstitutes) { substitute in
                    SubstituteExerciseCard(
                        substitute: substitute,
                        isSelected: selectedExercise?.id == substitute.exercise.id,
                        categoryColor: getCategoryColor(for: substitute.exercise.category)
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if selectedExercise?.id == substitute.exercise.id {
                                selectedExercise = nil
                            } else {
                                selectedExercise = substitute.exercise
                                // Haptic feedback
                                let generator = UIImpactFeedbackGenerator(style: .light)
                                generator.impactOccurred()
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, 100)
        }
    }
    
    // MARK: - Filtered Substitutes
    
    private var filteredSubstitutes: [SubstituteExercise] {
        var result = substitutes
        
        // Apply filter type
        switch filterType {
        case .all:
            break
        case .sameEquipment:
            result = result.filter { $0.exercise.equipment == currentExercise.equipment }
        case .bodyweight:
            result = result.filter { 
                $0.exercise.equipment?.lowercased() == "bodyweight" || 
                $0.matchReason == .noEquipment 
            }
        case .easier:
            result = result.filter { $0.matchReason == .easier }
        case .harder:
            result = result.filter { $0.matchReason == .harder }
        }
        
        // Apply search
        if !searchText.isEmpty {
            result = result.filter { 
                $0.exercise.name?.localizedCaseInsensitiveContains(searchText) ?? false
            }
        }
        
        return result
    }
    
    // MARK: - Load Substitutes
    
    private func loadSubstitutes() {
        Task {
            await MainActor.run {
                // Use the new ExerciseSwapService for database-powered suggestions
                let sections = ExerciseSwapService.shared.getSwapSuggestions(
                    for: currentExercise,
                    userGoal: "Build Muscle",  // Could be passed in
                    userLocation: "gym",        // Could be passed in
                    userEquipment: [],          // Show all, filter in UI
                    excludeIds: []
                )
                
                // Flatten sections into substitutes list
                var allSubstitutes: [SubstituteExercise] = []
                
                for section in sections {
                    for suggestion in section.suggestions {
                        let reason: SubstituteExercise.MatchReason = {
                            switch suggestion.swapType {
                            case .equipmentVariant: return .sameEquipment
                            case .complementary: return .samePattern
                            case .similar: return .popular
                            }
                        }()
                        
                        allSubstitutes.append(SubstituteExercise(
                            exercise: suggestion.exercise,
                            matchReason: reason,
                            matchScore: suggestion.priorityScore
                        ))
                    }
                }
                
                // If no database results, fall back to algorithmic matching
                if allSubstitutes.isEmpty {
                    let pairings = SmartExercisePairingEngine.shared.findSubstitutes(
                        for: currentExercise,
                        limit: 25,
                        userEquipment: nil
                    )
                    
                    allSubstitutes = pairings.map { pairing in
                        let primaryReason = mapMatchReason(pairing.matchReasons.first)
                        return SubstituteExercise(
                            exercise: pairing.exercise,
                            matchReason: primaryReason,
                            matchScore: pairing.matchScore
                        )
                    }
                }
                
                substitutes = allSubstitutes
                isLoading = false
                
                #if DEBUG
                print("🔄 [SUBSTITUTION] Found \(substitutes.count) substitutes for \(currentExercise.name ?? "exercise")")
                for sub in substitutes.prefix(5) {
                    print("   • \(sub.exercise.name ?? "") - \(sub.matchScore)% (\(sub.matchReason.rawValue))")
                }
                #endif
            }
        }
    }
    
    /// Maps SmartExercisePairingEngine match reasons to our UI match reasons
    private func mapMatchReason(_ engineReason: SmartExercisePairingEngine.ExercisePairing.MatchReason?) -> SubstituteExercise.MatchReason {
        guard let reason = engineReason else { return .samePattern }
        
        switch reason {
        case .sameMovementPattern:
            return .samePattern
        case .samePrimaryMuscle:
            return .sameMuscle
        case .sameSecondaryMuscles:
            return .sameMuscle
        case .equipmentAlternative:
            return .sameEquipment
        case .sameGripType, .samePlaneOfMotion, .sameForceVector, .sameBodyPosition:
            return .samePattern
        case .similarDifficulty:
            return .popular
        case .compoundToIsolation, .isolationToCompound:
            return .samePattern
        }
    }
    
    // MARK: - Helpers
    
    private var categoryColor: Color {
        getCategoryColor(for: currentExercise.category)
    }
    
    private var categoryIcon: String {
        switch currentExercise.category?.lowercased() {
        case "chest": return "heart.fill"
        case "back": return "figure.strengthtraining.traditional"
        case "legs": return "figure.walk"
        case "shoulders": return "figure.arms.open"
        case "arms": return "hand.raised.fill"
        case "core": return "circle.circle"
        default: return "figure.strengthtraining.traditional"
        }
    }
    
    private func getCategoryColor(for category: String?) -> Color {
        switch category?.lowercased() {
        case "chest": return .red
        case "back": return .blue
        case "legs": return .green
        case "shoulders": return .orange
        case "arms": return .purple
        case "core": return .pink
        case "full body": return .cyan
        case "cardio": return Color(red: 1.0, green: 0.4, blue: 0.4)
        default: return .cyan
        }
    }
}

// MARK: - Filter Pill Component

struct FilterPill: View {
    @Environment(\.colorScheme) var colorScheme
    
    let title: String
    let icon: String
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.ds_bodySmall)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .foregroundColor(isSelected ? .white : .primary)
            .padding(.horizontal, 14)
            .padding(.vertical, Spacing.xs)
            .background(
                Capsule()
                    .fill(
                        isSelected
                            ? LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)
                            : LinearGradient(colors: [Color.cardBackground, Color.cardBackground], startPoint: .leading, endPoint: .trailing)
                    )
            )
            .overlay(
                Capsule()
                    .stroke(
                        isSelected ? Color.clear : Color.primary.opacity(0.1),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Substitute Exercise Card

struct SubstituteExerciseCard: View {
    @Environment(\.colorScheme) var colorScheme
    
    let substitute: ExerciseSubstitutionView.SubstituteExercise
    let isSelected: Bool
    let categoryColor: Color
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Exercise icon
                ZStack {
                    RoundedRectangle(cornerRadius: CornerRadius.md)
                        .fill(
                            isSelected
                                ? LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LinearGradient(colors: [categoryColor.opacity(0.15), categoryColor.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 56, height: 56)
                    
                    Image(systemName: substitute.matchReason.icon)
                        .font(.ds_heading2)
                        .foregroundColor(isSelected ? .white : categoryColor)
                }
                
                // Exercise info
                VStack(alignment: .leading, spacing: 6) {
                    Text(substitute.exercise.displayName)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    HStack(spacing: 8) {
                        // Match reason badge
                        HStack(spacing: 4) {
                            Image(systemName: substitute.matchReason.icon)
                                .font(.ds_caption)
                            Text(substitute.matchReason.rawValue)
                                .font(.caption2)
                        }
                        .foregroundColor(substitute.matchReason.color)
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, Spacing.xxs)
                        .background(
                            Capsule()
                                .fill(substitute.matchReason.color.opacity(0.15))
                        )
                        
                        // Equipment badge
                        if let equipment = substitute.exercise.equipment {
                            Text(equipment)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, Spacing.xs)
                                .padding(.vertical, Spacing.xxs)
                                .background(
                                    Capsule()
                                        .fill(Color.cardBackground)
                                )
                        }
                    }
                }
                
                Spacer()
                
                // Match score or selection indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                } else {
                    // Match percentage
                    VStack(spacing: 2) {
                        Text("\(substitute.matchScore)%")
                            .font(.ds_bodySmall).fontWeight(.bold).fontDesign(.rounded)
                            .foregroundColor(.primary)
                        Text("match")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .fill(Color.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.lg)
                            .stroke(
                                isSelected
                                    ? LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)
                                    : LinearGradient(colors: [Color.primary.opacity(0.08), Color.primary.opacity(0.04)], startPoint: .top, endPoint: .bottom),
                                lineWidth: isSelected ? 2 : 1
                            )
                    )
                    .shadow(
                        color: isSelected ? Color.blue.opacity(0.2) : Color.black.opacity(colorScheme == .dark ? 0.3 : 0.08),
                        radius: isSelected ? 12 : 6,
                        x: 0,
                        y: isSelected ? 6 : 3
                    )
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview

#Preview {
    ExerciseSubstitutionView(
        currentExercise: Exercise(),
        onSelectReplacement: { _ in }
    )
    .preferredColorScheme(.dark)
}

