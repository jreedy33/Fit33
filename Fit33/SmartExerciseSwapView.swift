//
//  SmartExerciseSwapView.swift
//  GoFit
//
//  Intelligent exercise swap interface using database-powered recommendations
//  Shows equipment variants + complementary exercises in organized sections
//

import SwiftUI

struct SmartExerciseSwapView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var swapService = ExerciseSwapService.shared
    
    let currentExercise: Exercise
    let userGoal: String
    let userLocation: String
    let userEquipment: [String]
    let excludeIds: Set<UUID>
    let onSelectReplacement: (Exercise) -> Void
    
    @State private var sections: [SwapSection] = []
    @State private var isLoading = true
    @State private var selectedExercise: Exercise?
    @State private var searchText = ""
    @State private var showAllExercises = false
    
    // Track swaps for learning
    @State private var swapCount: Int = 0
    
    init(
        currentExercise: Exercise,
        userGoal: String = "Build Muscle",
        userLocation: String = "gym",
        userEquipment: [String] = [],
        excludeIds: Set<UUID> = [],
        swapCount: Int = 0,
        onSelectReplacement: @escaping (Exercise) -> Void
    ) {
        self.currentExercise = currentExercise
        self.userGoal = userGoal
        self.userLocation = userLocation
        self.userEquipment = userEquipment
        self.excludeIds = excludeIds
        self._swapCount = State(initialValue: swapCount)
        self.onSelectReplacement = onSelectReplacement
    }
    
    private var categoryColor: Color {
        switch currentExercise.category?.lowercased() {
        case "chest": return .red
        case "back": return .blue
        case "legs": return .green
        case "shoulders": return .orange
        case "arms": return .purple
        case "core": return .pink
        default: return .cyan
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                backgroundGradient
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Current exercise header
                    currentExerciseHeader
                    
                    // Content
                    if isLoading {
                        loadingView
                    } else if sections.isEmpty && !showAllExercises {
                        emptyStateView
                    } else {
                        swapContent
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
                            .background(Circle().fill(Color.cardBackground))
                    }
                }
                
                ToolbarItem(placement: .principal) {
                    Text("Swap Exercise")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if let selected = selectedExercise {
                        Button("Swap") {
                            // Record the swap for learning
                            UserBehaviorLearningEngine.shared.recordExerciseSwap(
                                from: currentExercise.name ?? "",
                                to: selected.name ?? ""
                            )
                            onSelectReplacement(selected)
                            dismiss()
                        }
                        .font(.headline)
                        .foregroundStyle(LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                    }
                }
            }
        }
        .onAppear {
            SessionLogManager.shared.logSheetPresent(.exerciseSwap)
            SessionLogManager.shared.logScreen(.exerciseSwap, metadata: [
                "original_exercise": currentExercise.name
            ])
            loadSuggestions()
        }
    }
    
    // MARK: - Views
    
    private var backgroundGradient: some View {
        LinearGradient(
            gradient: Gradient(colors: colorScheme == .dark
                ? [categoryColor.opacity(0.15), Color(red: 0.05, green: 0.05, blue: 0.07)]
                : [categoryColor.opacity(0.1), Color.white]),
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    private var currentExerciseHeader: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: CornerRadius.md)
                        .fill(categoryColor.opacity(0.2))
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: "dumbbell.fill")
                        .font(.ds_heading2)
                        .foregroundColor(categoryColor)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Swapping")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(currentExercise.name ?? "Exercise")
                        .font(.title3)
                        .fontWeight(.bold)
                        .lineLimit(2)
                    
                    HStack(spacing: 8) {
                        if let family = currentExercise.value(forKey: "exerciseFamily") as? String {
                            Text(family.replacingOccurrences(of: "_", with: " ").capitalized)
                                .font(.caption2)
                                .foregroundColor(categoryColor)
                                .padding(.horizontal, Spacing.xs)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(categoryColor.opacity(0.15)))
                        }
                        
                        if let equipment = currentExercise.equipment {
                            Text(equipment)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
            }
            .padding(Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .fill(Color.cardBackground)
                    .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
            )
            .padding(.horizontal, Spacing.md)
            .padding(.top, 8)
            
            // Arrow
            Image(systemName: "arrow.down.circle.fill")
                .font(.title2)
                .foregroundStyle(LinearGradient(
                    colors: [.blue, .purple],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Finding smart alternatives...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No alternatives found")
                .font(.headline)
            
            Button("Browse All Exercises") {
                showAllExercises = true
            }
            .font(.subheadline)
            .foregroundColor(.blue)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var swapContent: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                ForEach(sections) { section in
                    swapSectionView(section)
                }
                
                // "Browse All" button at bottom
                if !showAllExercises {
                    Button(action: { showAllExercises = true }) {
                        HStack {
                            Image(systemName: "square.grid.2x2")
                            Text("Browse All Exercises")
                        }
                        .font(.subheadline)
                        .foregroundColor(.blue)
                        .padding(.vertical, Spacing.sm)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.md)
                                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .padding(.horizontal, Spacing.md)
                }
            }
            .padding(.vertical, Spacing.md)
            .padding(.bottom, 80)
        }
    }
    
    private func swapSectionView(_ section: SwapSection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack(spacing: 8) {
                Image(systemName: section.icon)
                    .font(.ds_labelMedium)
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(section.title)
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text(section.subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text("\(section.suggestions.count)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, Spacing.xxs)
                    .background(Capsule().fill(Color.secondary.opacity(0.1)))
            }
            .padding(.horizontal, Spacing.md)
            
            // Suggestions
            VStack(spacing: 10) {
                ForEach(section.suggestions) { suggestion in
                    swapSuggestionCard(suggestion)
                }
            }
            .padding(.horizontal, Spacing.md)
        }
    }
    
    private func swapSuggestionCard(_ suggestion: SwapSuggestion) -> some View {
        let isSelected = selectedExercise?.id == suggestion.exercise.id
        let typeColor: Color = {
            switch suggestion.swapType {
            case .equipmentVariant: return .blue
            case .complementary: return .purple
            case .similar: return .gray
            }
        }()
        
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                if isSelected {
                    selectedExercise = nil
                } else {
                    selectedExercise = suggestion.exercise
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
        }) {
            HStack(spacing: 14) {
                // Type indicator
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isSelected
                            ? LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [typeColor.opacity(0.15), typeColor.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: suggestion.swapType.icon)
                        .font(.ds_heading3)
                        .foregroundColor(isSelected ? .white : typeColor)
                }
                
                // Exercise info
                VStack(alignment: .leading, spacing: 4) {
                    Text(suggestion.exercise.displayName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    HStack(spacing: 6) {
                        // Swap type badge
                        Text(suggestion.swapType.rawValue)
                            .font(.caption2)
                            .foregroundColor(typeColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(typeColor.opacity(0.1)))
                        
                        // Equipment
                        if let equip = (suggestion.exercise.value(forKey: "equipmentCategory") as? String) ?? suggestion.exercise.equipment {
                            Text(equip.capitalized)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                // Selection indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                } else {
                    Text("\(suggestion.priorityScore)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                }
            }
            .padding(Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(
                                isSelected
                                    ? LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)
                                    : LinearGradient(colors: [Color.clear], startPoint: .leading, endPoint: .trailing),
                                lineWidth: 2
                            )
                    )
                    .shadow(color: isSelected ? .blue.opacity(0.2) : .black.opacity(0.05), radius: isSelected ? 8 : 4, y: 2)
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Data Loading
    
    private func loadSuggestions() {
        Task {
            // Small delay for smooth animation
            try? await Task.sleep(nanoseconds: 200_000_000)
            
            await MainActor.run {
                let loadedSections = swapService.getSwapSuggestions(
                    for: currentExercise,
                    userGoal: userGoal,
                    userLocation: userLocation,
                    userEquipment: userEquipment,
                    excludeIds: excludeIds
                )
                
                withAnimation(.easeOut(duration: 0.3)) {
                    sections = loadedSections
                    isLoading = false
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    SmartExerciseSwapView(
        currentExercise: Exercise(),
        onSelectReplacement: { _ in }
    )
    .preferredColorScheme(.dark)
}
