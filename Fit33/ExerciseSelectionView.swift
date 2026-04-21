import SwiftUI
import CoreData

/// Sprint 5 M-25 (partial) — planned unification: new entry points should use
/// `CustomWorkoutBuilderView(mode: .build)` which already owns the richer
/// picker (filters, pinning, favorites, live exercise count, strength-level
/// personalization). `ExerciseSelectionView` only survives because it is
/// embedded inline inside `WorkoutCreationView.customWorkoutView` with a
/// dedicated "Start Workout" CTA below it — migrating that flow requires
/// changing `CustomWorkoutBuilderView` to expose a `@Binding` instead of a
/// dismissing sheet, which is tracked as a follow-up. Do NOT add new callers
/// of `ExerciseSelectionView` — use `CustomWorkoutBuilderView` instead.
struct ExerciseSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedExercises: [Exercise]
    
    @State private var searchText = ""
    @State private var selectedCategory = "All"
    @State private var selectedEquipment = "All"
    @State private var selectedMuscleGroup = "All"
    @State private var exercises: [Exercise] = []
    @State private var selectedExerciseForDetail: Exercise?
    
    // ⚡️ SNAPPY SEARCH: Focus state for instant keyboard dismiss
    @FocusState private var isSearchFocused: Bool
    
    // ⚡️ HIGH-PERFORMANCE: Cached results - no recomputation on every render
    @State private var cachedFilteredExercises: [Exercise] = []
    @State private var preFilteredExercises: [Exercise] = []
    @State private var lastFilterKey: String = ""
    @State private var searchCache: [String: [Exercise]] = [:]
    @State private var searchDebounceTask: Task<Void, Never>?
    
    // Updated categories for 7000+ exercise library
    private let categories = ExerciseFilterService.allCategories
    private let allMuscleGroups = ["All", "Biceps", "Triceps", "Forearms", "Quads", "Hamstrings", "Glutes", "Calves", "Lats", "Upper Back", "Traps", "Lower Back", "Front Delts", "Side Delts", "Rear Delts", "Abs", "Obliques", "Hip Flexors", "Adductors", "Rotator Cuff"]
    
    // Smart muscle groups based on selected category (uses centralized service)
    private var muscleGroups: [String] {
        ExerciseFilterService.muscleGroupsForCategory(selectedCategory)
    }
    
    // Updated equipment for 7000+ exercise library
    private let equipmentTypes = ExerciseFilterService.allEquipment
    
    // ⚡️ HIGH-PERFORMANCE: Use cached results, not computed
    var filteredExercises: [Exercise] {
        cachedFilteredExercises
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // ⚡️ HIGH-PERFORMANCE SEARCH ENGINE
    // ═══════════════════════════════════════════════════════════════════════
    
    private func updateFilteredExercises() {
        let filterKey = "\(selectedCategory)|\(selectedEquipment)|\(selectedMuscleGroup)"
        
        // Rebuild filter cache if filters changed
        if filterKey != lastFilterKey {
            lastFilterKey = filterKey
            searchCache.removeAll()
            SmartExerciseSearchService.shared.invalidateCache()
            preFilteredExercises = applyFiltersOnly(to: exercises)
        }
        
        // Apply search to pre-filtered results
        if !searchText.isEmpty {
            let searchKey = searchText.lowercased()
            if let cached = searchCache[searchKey] {
                cachedFilteredExercises = cached
                return
            }
            let results = SmartExerciseSearchService.shared.searchExercisesUltraFast(
                query: searchKey, in: preFilteredExercises
            )
            searchCache[searchKey] = results
            cachedFilteredExercises = results
        } else {
            cachedFilteredExercises = preFilteredExercises
        }
    }
    
    private func applyFiltersOnly(to exercises: [Exercise]) -> [Exercise] {
        var filtered = exercises
        
        if selectedCategory != "All" {
            let categoryLower = selectedCategory.lowercased()
            filtered = filtered.filter { exercise in
                let exerciseCategory = (exercise.category ?? "").lowercased()
                return exerciseCategory == categoryLower || exerciseCategory.contains(categoryLower)
            }
        }
        
        if selectedEquipment != "All" {
            filtered = filtered.filter { exercise in
                ExerciseFilterService.exerciseMatchesEquipment(exercise, selectedEquipment: selectedEquipment)
            }
        }
        
        if selectedMuscleGroup != "All" {
            filtered = filtered.filter { exercise in
                ExerciseFilterService.isExerciseForMuscleGroup(exercise, muscleGroup: selectedMuscleGroup)
            }
        }
        
        return filtered
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Clean top navigation bar
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .font(.body)
                .foregroundColor(.blue)
                
                Spacer()
                
                Button("Done") {
                    dismiss()
                }
                .font(.body)
                .fontWeight(.semibold)
                .foregroundColor(.blue)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, Spacing.sm)
            .background(.ultraThinMaterial)
            
            // Compact search and filters
            compactFiltersView
            
            // Exercise list
            exerciseListView
        }
        .scrollDismissesKeyboard(.interactively) // Dismiss keyboard when interacting with scrollable content
        .onAppear {
            loadExercises()
            updateFilteredExercises()
        }
        .onChange(of: searchText) { _, _ in
            searchDebounceTask?.cancel()
            if searchText.isEmpty {
                updateFilteredExercises()
            } else {
                searchDebounceTask = Task {
                    try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                    guard !Task.isCancelled else { return }
                    updateFilteredExercises()
                }
            }
        }
        .onChange(of: selectedCategory) { _, _ in 
            lastFilterKey = ""
            updateFilteredExercises() 
        }
        .onChange(of: selectedEquipment) { _, _ in 
            lastFilterKey = ""
            updateFilteredExercises() 
        }
        .onChange(of: selectedMuscleGroup) { _, _ in 
            lastFilterKey = ""
            updateFilteredExercises() 
        }
        .onChange(of: exercises) { _, _ in 
            lastFilterKey = ""
            updateFilteredExercises() 
        }
        .sheet(item: $selectedExerciseForDetail) { exercise in
            NavigationStack {
                ExerciseDetailView(exercise: exercise)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") {
                                selectedExerciseForDetail = nil
                            }
                        }
                    }
            }
        }
    }
    
    private var compactFiltersView: some View {
        VStack(spacing: 16) {
            // ⚡️ SNAPPY SEARCH: Instant response search bar
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.ds_bodyRegular).fontWeight(.medium)
                    .foregroundColor(.secondary)
                
                TextField("Search exercises...", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.body)
                    .focused($isSearchFocused)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.done)
                    .onSubmit {
                        // ⚡️ INSTANT keyboard dismiss on return
                        isSearchFocused = false
                    }
                
                if !searchText.isEmpty {
                    Button(action: { 
                        searchText = ""
                        isSearchFocused = false // Also dismiss keyboard when clearing
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.ds_bodyRegular)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .fill(Color(.systemGray6).opacity(0.6))
            )
            
            // Seamless filter chips in single flow
            VStack(spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(categories, id: \.self) { category in
                            SelectionFilterChip(
                                text: category,
                                isSelected: selectedCategory == category,
                                onTap: { 
                                    selectedCategory = category
                                    selectedMuscleGroup = "All"
                                }
                            )
                        }
                    }
                    .padding(.horizontal, Spacing.md)
                }
                
                if selectedCategory != "All" {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(muscleGroups, id: \.self) { muscle in
                                SelectionFilterChip(
                                    text: muscle,
                                    isSelected: selectedMuscleGroup == muscle,
                                    color: .green,
                                    onTap: { selectedMuscleGroup = muscle }
                                )
                            }
                        }
                        .padding(.horizontal, Spacing.md)
                    }
                }
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(equipmentTypes, id: \.self) { equipment in
                            SelectionFilterChip(
                                text: equipment,
                                isSelected: selectedEquipment == equipment,
                                color: .gray,
                                onTap: { selectedEquipment = equipment }
                            )
                        }
                    }
                    .padding(.horizontal, Spacing.md)
                }
            }
        }
        .padding(.vertical, 20)
    }
    
    private var exerciseListView: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(Array(filteredExercises.enumerated()), id: \.element.objectID) { index, exercise in
                    SeamlessExerciseSelectionRow(
                        exercise: exercise,
                        isSelected: selectedExercises.contains { $0.id == exercise.id },
                        onToggle: {
                            toggleExerciseSelection(exercise)
                        },
                        onInfoTap: {
                            selectedExerciseForDetail = exercise
                            // 🚀 Priority prefetch when user taps info
                            if let name = exercise.name {
                                VideoPlaybackEngine.shared.priorityPrefetch(exerciseName: name)
                            }
                        }
                    )
                    // 🚀 Prefetch when exercise appears in viewport
                    .onAppear {
                        prefetchVisibleExercise(exercise: exercise, index: index)
                    }
                }
                
                if filteredExercises.isEmpty {
                    emptyStateView
                        .padding(.top, 40)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, 8)
        }
        .scrollDismissesKeyboard(.immediately)
        // ⚡️ SNAPPY SEARCH: Dismiss keyboard instantly when scrolling
        .simultaneousGesture(
            DragGesture().onChanged { _ in
                isSearchFocused = false
            }
        )
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 50))
                .foregroundColor(.gray)
            
            Text("No exercises found")
                .font(.headline)
                .fontWeight(.semibold)
            
            Text("Try adjusting your search or filters")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
    
    private func loadExercises() {
        // Load exercises from cache/Core Data (don't re-initialize, that causes duplicates)
        exercises = ExerciseLibraryService.shared.getAllExercises()
        AppLogger.info("Loaded \(exercises.count) exercises", category: .workout)
    }
    
    private func toggleExerciseSelection(_ exercise: Exercise) {
        if let index = selectedExercises.firstIndex(where: { $0.id == exercise.id }) {
            selectedExercises.remove(at: index)
        } else {
            selectedExercises.append(exercise)
        }
    }
    
    // MARK: - 🚀 Smart Video Prefetching
    
    /// ⚡️ MEMORY FIX: DISABLED — scroll prefetching was creating AVPlayers for every visible row,
    /// causing 600MB+ memory from XPC video process leaks. Videos load on-demand in detail view.
    private func prefetchVisibleExercise(exercise: Exercise, index: Int) {
        // NO-OP: Disabled to prevent memory pressure
    }
}

// MARK: - Seamless Components

struct SeamlessExerciseSelectionRow: View {
    let exercise: Exercise
    let isSelected: Bool
    let onToggle: () -> Void
    let onInfoTap: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 16) {
                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.ds_heading2)
                    .foregroundColor(isSelected ? .blue : Color(.systemGray4))
                
                // Exercise icon
                ZStack {
                    Circle()
                        .fill(categoryColor.opacity(0.12))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: categoryIcon)
                        .font(.ds_heading3)
                        .foregroundColor(categoryColor)
                }
                
                // Exercise details
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(exercise.displayName)
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        Button(action: onInfoTap) {
                            Image(systemName: "info.circle")
                                .font(.ds_heading3)
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    HStack(spacing: 6) {
                        if let category = exercise.category {
                            Text(category)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundColor(categoryColor)
                        }
                        
                        if let equipment = exercise.equipment {
                            Text("•")
                                .font(.ds_bodySmall).fontWeight(.medium)
                                .foregroundColor(Color(.systemGray3))
                            
                            Text(equipment)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundColor(Color(.systemGray))
                        }
                        
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
    
    private var categoryColor: Color {
        switch exercise.category?.lowercased() {
        case "chest": return .red
        case "back": return .blue
        case "legs": return .green
        case "shoulders": return .orange
        case "arms": return .purple
        case "core": return .yellow
        case "full body": return .pink
        default: return .gray
        }
    }
    
    private var categoryIcon: String {
        // First, check for specific exercise patterns
        if let exerciseName = exercise.name?.lowercased() {
            
            // Dumbbell exercises
            if exerciseName.contains("dumbbell") {
                return "dumbbell.fill"
            }
            
            // Barbell exercises
            if exerciseName.contains("barbell") {
                return "figure.strengthtraining.traditional"
            }
            
            // Bodyweight exercises
            if exerciseName.contains("push") || exerciseName.contains("pull") || exerciseName.contains("squat") {
                return "figure.strengthtraining.functional"
            }
            
            // Cable exercises
            if exerciseName.contains("cable") {
                return "cable.connector"
            }
        }
        
        // Fallback to category-based icons
        switch exercise.category?.lowercased() {
        case "chest": return "figure.strengthtraining.traditional"
        case "back": return "figure.rower"
        case "legs": return "figure.run"
        case "shoulders": return "figure.strengthtraining.functional"
        case "arms": return "dumbbell.fill"
        case "core": return "figure.core.training"
        case "full body": return "figure.mixed.cardio"
        default: return "dumbbell"
        }
    }
}

struct CompactExerciseSelectionRow: View {
    let exercise: Exercise
    let isSelected: Bool
    let onToggle: () -> Void
    let onInfoTap: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                // Selection indicator (matching the selected state)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(isSelected ? .blue : .gray)
                
                // Exercise icon
                ZStack {
                    Circle()
                        .fill(categoryColor.opacity(0.15))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: categoryIcon)
                        .font(.ds_bodyRegular).fontWeight(.medium)
                        .foregroundColor(categoryColor)
                }
                
                // Exercise details
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(exercise.displayName)
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        Button(action: onInfoTap) {
                            Image(systemName: "info.circle")
                                .font(.ds_bodyRegular).fontWeight(.medium)
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    HStack(spacing: 8) {
                        if let category = exercise.category {
                            Text(category)
                                .font(.caption)
                                .foregroundColor(categoryColor)
                                .fontWeight(.medium)
                        }
                        
                        if let equipment = exercise.equipment {
                            Text("•")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            Text(equipment)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: CornerRadius.sm))
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var categoryColor: Color {
        switch exercise.category?.lowercased() {
        case "chest": return .red
        case "back": return .blue
        case "legs": return .green
        case "shoulders": return .orange
        case "arms": return .purple
        case "core": return .yellow
        case "full body": return .pink
        default: return .gray
        }
    }
    
    private var categoryIcon: String {
        // First, check for specific exercise patterns
        if let exerciseName = exercise.name?.lowercased() {
            
            // Dumbbell exercises
            if exerciseName.contains("dumbbell") {
                return "dumbbell.fill"
            }
            
            // Barbell exercises
            if exerciseName.contains("barbell") {
                return "figure.strengthtraining.traditional"
            }
            
            // Bodyweight exercises
            if exerciseName.contains("push") || exerciseName.contains("pull") || exerciseName.contains("squat") {
                return "figure.strengthtraining.functional"
            }
            
            // Cable exercises
            if exerciseName.contains("cable") {
                return "cable.connector"
            }
        }
        
        // Fallback to category-based icons
        switch exercise.category?.lowercased() {
        case "chest": return "figure.strengthtraining.traditional"
        case "back": return "figure.rower"
        case "legs": return "figure.run"
        case "shoulders": return "figure.strengthtraining.functional"
        case "arms": return "dumbbell.fill"
        case "core": return "figure.core.training"
        case "full body": return "figure.mixed.cardio"
        default: return "dumbbell"
        }
    }
}



struct SelectionFilterChip: View {
    let text: String
    let isSelected: Bool
    var color: Color = .blue
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            Text(text)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(
                            isSelected ? 
                            LinearGradient(
                                gradient: Gradient(colors: [color, color.opacity(0.8)]),
                                startPoint: .leading,
                                endPoint: .trailing
                            ) :
                            LinearGradient(
                                gradient: Gradient(colors: [Color(.systemGray5), Color(.systemGray6)]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .shadow(color: isSelected ? .blue.opacity(0.3) : .clear, radius: 4, x: 0, y: 2)
                )
        }
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

struct ExerciseSelectionCard: View {
    let exercise: Exercise
    let isSelected: Bool
    let onToggle: () -> Void
    let onInfoTap: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(isSelected ? .blue : .gray)
                
                // Exercise icon
                ZStack {
                    Circle()
                        .fill(categoryColor.opacity(0.15))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: categoryIcon)
                        .font(.ds_labelLarge)
                        .foregroundColor(categoryColor)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.displayName)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    HStack {
                        Text(exercise.category ?? "")
                            .font(.caption)
                            .padding(.horizontal, Spacing.xs)
                            .padding(.vertical, Spacing.xxs)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(6)
                        
                        Text(exercise.equipment ?? "")
                            .font(.caption)
                            .padding(.horizontal, Spacing.xs)
                            .padding(.vertical, Spacing.xxs)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(6)
                    }
                    
                    if let muscleGroups = exercise.muscleGroups as? [String], !muscleGroups.isEmpty {
                        Text(muscleGroups.joined(separator: ", "))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                Button(action: onInfoTap) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                        .font(.subheadline)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .fill(isSelected ? Color.blue.opacity(0.1) : Color.white)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                    .shadow(color: .gray.opacity(0.2), radius: 2, x: 0, y: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var categoryColor: Color {
        switch exercise.category?.lowercased() {
        case "chest": return .red
        case "back": return .blue
        case "legs": return .green
        case "shoulders": return .orange
        case "arms": return .purple
        case "core": return .yellow
        case "full body": return .pink
        default: return .gray
        }
    }
    
    private var categoryIcon: String {
        // First, check for specific exercise patterns
        if let exerciseName = exercise.name?.lowercased() {
            
            // Dumbbell exercises
            if exerciseName.contains("dumbbell") {
                return "dumbbell.fill"
            }
            
            // Barbell exercises  
            else if exerciseName.contains("barbell") {
                return "figure.strengthtraining.traditional"
            }
            
            // Cable exercises
            else if exerciseName.contains("cable") {
                return "dot.radiowaves.left.and.right"
            }
            
            // Push-up variations
            else if exerciseName.contains("push") && exerciseName.contains("up") {
                return "figure.strengthtraining.traditional"
            }
            
            // Pull-up variations  
            else if exerciseName.contains("pull") && (exerciseName.contains("up") || exerciseName.contains("chin")) {
                return "figure.climbing"
            }
            
            // Squat variations
            else if exerciseName.contains("squat") {
                return "figure.strengthtraining.traditional"
            }
            
            // Lunge variations
            else if exerciseName.contains("lunge") {
                return "figure.walk"
            }
            
            // Hip thrust variations
            else if exerciseName.contains("thrust") || exerciseName.contains("bridge") {
                return "figure.strengthtraining.functional"
            }
            
            // Deadlift variations
            else if exerciseName.contains("deadlift") {
                return "figure.strengthtraining.functional"
            }
            
            // Curl variations (bicep/tricep)
            else if exerciseName.contains("curl") {
                return "figure.arms.open"
            }
            
            // Press variations (shoulder/chest)
            else if exerciseName.contains("press") && !exerciseName.contains("leg") {
                return "arrow.up.circle.fill"
            }
            
            // Row variations
            else if exerciseName.contains("row") {
                return "arrow.left.and.right.circle.fill"
            }
            
            // Fly variations
            else if exerciseName.contains("fly") || exerciseName.contains("flye") {
                return "arrow.up.left.and.arrow.down.right.circle.fill"
            }
            
            // Raise variations (lateral, front)
            else if exerciseName.contains("raise") {
                return "arrow.up.circle"
            }
            
            // Shrug variations
            else if exerciseName.contains("shrug") {
                return "arrow.up.and.down.circle.fill"
            }
            
            // Plank variations
            else if exerciseName.contains("plank") {
                return "figure.core.training"
            }
            
            // Running/cardio
            else if exerciseName.contains("run") || exerciseName.contains("jog") {
                return "figure.run"
            }
            
            // Jump exercises
            else if exerciseName.contains("jump") {
                return "figure.jumprope"
            }
        }
        
        // Fallback to equipment-based icons
        if let equipment = exercise.equipment?.lowercased() {
            switch equipment {
            case "dumbbells":
                return "dumbbell.fill"
            case "barbell":
                return "figure.strengthtraining.traditional"
            case "cables":
                return "dot.radiowaves.left.and.right"
            case "machines":
                return "gearshape.fill"
            case "bodyweight":
                return "figure.strengthtraining.traditional"
            default:
                break
            }
        }
        
        // Final fallback to category icons
        switch exercise.category?.lowercased() {
        case "chest": return "figure.strengthtraining.traditional"
        case "back": return "figure.climbing"
        case "legs": return "figure.strengthtraining.traditional"
        case "shoulders": return "arrow.up.circle.fill"
        case "arms": return "dumbbell.fill"
        case "core": return "figure.core.training"
        case "full body": return "figure.mixed.cardio"
        default: return "dumbbell.fill"
        }
    }
}

#Preview {
    ExerciseSelectionView(selectedExercises: .constant([]))
}
