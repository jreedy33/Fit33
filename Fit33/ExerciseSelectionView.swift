import SwiftUI
import CoreData

struct ExerciseSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedExercises: [Exercise]
    
    @State private var searchText = ""
    @State private var selectedCategory = "All"
    @State private var selectedEquipment = "All"
    @State private var selectedMuscleGroup = "All"
    @State private var exercises: [Exercise] = []
    @State private var selectedExerciseForDetail: Exercise?
    
    // Updated categories for 7000+ exercise library
    private let categories = ExerciseFilterService.allCategories
    private let allMuscleGroups = ["All", "Biceps", "Triceps", "Forearms", "Quads", "Hamstrings", "Glutes", "Calves", "Lats", "Upper Back", "Traps", "Lower Back", "Front Delts", "Side Delts", "Rear Delts", "Abs", "Obliques", "Hip Flexors", "Adductors", "Rotator Cuff"]
    
    // Smart muscle groups based on selected category (uses centralized service)
    private var muscleGroups: [String] {
        ExerciseFilterService.muscleGroupsForCategory(selectedCategory)
    }
    
    // Updated equipment for 7000+ exercise library
    private let equipmentTypes = ExerciseFilterService.allEquipment
    
    var filteredExercises: [Exercise] {
        var filtered = exercises
        
        // Filter by category first (most restrictive)
        if selectedCategory != "All" {
            filtered = filtered.filter { exercise in
                let exerciseCategory = exercise.category?.lowercased() ?? ""
                let targetCategory = selectedCategory.lowercased()
                
                // Direct category match
                return exerciseCategory == targetCategory ||
                       exerciseCategory.contains(targetCategory) ||
                       targetCategory.contains(exerciseCategory)
            }
        }
        
        // Filter by equipment (with comprehensive normalization)
        if selectedEquipment != "All" {
            filtered = filtered.filter { exercise in
                exerciseMatchesEquipment(exercise, selectedEquipment: selectedEquipment)
            }
        }
        
        // Filter by muscle group (focus area within category)
        if selectedMuscleGroup != "All" {
            filtered = filtered.filter { exercise in
                isExerciseForMuscleGroup(exercise, muscleGroup: selectedMuscleGroup)
            }
        }
        
        // Apply smart search with filter context and personalization
        let userBehavior = UserBehaviorLearningEngine.shared.userPreferences
        let categoryForSearch = selectedCategory != "All" ? selectedCategory : nil
        let equipmentForSearch = selectedEquipment != "All" ? selectedEquipment : nil
        
        if !searchText.isEmpty {
            // Search with filter context
            filtered = SmartExerciseSearchService.shared.searchExercises(
                query: searchText,
                in: filtered,
                userBehavior: userBehavior,
                categoryFilter: categoryForSearch,
                equipmentFilter: equipmentForSearch
            )
        } else {
            // No search - rank by common exercises for filters
            filtered = SmartExerciseSearchService.shared.searchExercises(
                query: "",
                in: filtered,
                userBehavior: userBehavior,
                categoryFilter: categoryForSearch,
                equipmentFilter: equipmentForSearch
            )
        }
        
        return filtered
    }
    
    // MARK: - Muscle Group Matching
    /// Comprehensive muscle group matching - same logic as CustomWorkoutBuilderView
    private func isExerciseForMuscleGroup(_ exercise: Exercise, muscleGroup: String) -> Bool {
        let exerciseName = exercise.name?.lowercased() ?? ""
        let exerciseMuscleGroups = (exercise.muscleGroups as? [String])?.map { $0.lowercased() } ?? []
        let exerciseCategory = exercise.category?.lowercased() ?? ""
        
        // Helper to check if exercise is a fly/flye movement
        let isFlyMovement = exerciseName.contains("fly") || exerciseName.contains("flye") || 
                           exerciseName.contains("pec deck") || exerciseName.contains("crossover")
        
        switch muscleGroup {
        case "Upper Chest":
            let isIncline = exerciseName.contains("incline") && !exerciseName.contains("decline")
            let isLowToHigh = exerciseName.contains("low to high") || exerciseName.contains("low-to-high")
            if isFlyMovement && isIncline { return true }
            return isIncline || isLowToHigh ||
                   exerciseMuscleGroups.contains { $0.contains("upper") && ($0.contains("chest") || $0.contains("pec")) }
                   
        case "Lower Chest":
            let isDecline = exerciseName.contains("decline") && !exerciseName.contains("incline")
            let isDip = exerciseName.contains("dip") && !exerciseName.contains("hip")
            if isFlyMovement && isDecline { return true }
            return isDecline || isDip ||
                   exerciseMuscleGroups.contains { $0.contains("lower") && ($0.contains("chest") || $0.contains("pec")) }
                   
        case "Inner Chest":
            return exerciseName.contains("close grip") || exerciseName.contains("crossover") ||
                   exerciseName.contains("squeeze") ||
                   exerciseMuscleGroups.contains { $0.contains("inner") && $0.contains("chest") }
                   
        case "Outer Chest":
            return isFlyMovement ||
                   exerciseName.contains("wide grip") ||
                   exerciseMuscleGroups.contains { $0.contains("outer") && $0.contains("chest") }
                   
        case "Lats":
            return exerciseName.contains("pulldown") || exerciseName.contains("pull-down") ||
                   exerciseName.contains("lat ") || exerciseName.hasPrefix("lat") ||
                   exerciseName.contains("pull up") || exerciseName.contains("pull-up") ||
                   exerciseName.contains("chin up") || exerciseName.contains("chin-up") ||
                   exerciseMuscleGroups.contains { $0.contains("lat") }
                   
        case "Traps":
            return exerciseName.contains("shrug") || exerciseName.contains("upright row") ||
                   exerciseName.contains("trap") ||
                   exerciseMuscleGroups.contains { $0.contains("trap") }
                   
        case "Upper Back", "Rhomboids":
            return exerciseName.contains("row") || exerciseName.contains("face pull") ||
                   exerciseName.contains("reverse fly") ||
                   exerciseMuscleGroups.contains { $0.contains("rhomboid") || $0.contains("upper back") }
                   
        case "Lower Back":
            return exerciseName.contains("deadlift") || exerciseName.contains("hyperextension") ||
                   exerciseName.contains("good morning") || exerciseName.contains("superman") ||
                   exerciseMuscleGroups.contains { $0.contains("lower back") || $0.contains("erector") }
                   
        case "Front Delts":
            if exerciseName.contains("lateral") || exerciseName.contains("side") || 
               exerciseName.contains("rear") || exerciseName.contains("reverse") { return false }
            return exerciseName.contains("front raise") ||
                   (exerciseName.contains("press") && exerciseCategory == "shoulders") ||
                   exerciseMuscleGroups.contains { $0.contains("anterior") && $0.contains("delt") }
                   
        case "Side Delts", "Lateral Delts":
            return exerciseName.contains("lateral raise") || exerciseName.contains("side raise") ||
                   exerciseName.contains("upright row") ||
                   exerciseMuscleGroups.contains { ($0.contains("lateral") || $0.contains("medial")) && $0.contains("delt") }
                   
        case "Rear Delts":
            return exerciseName.contains("reverse fly") || exerciseName.contains("rear delt") ||
                   exerciseName.contains("face pull") ||
                   exerciseMuscleGroups.contains { ($0.contains("posterior") || $0.contains("rear")) && $0.contains("delt") }
                   
        case "Biceps":
            return exerciseName.contains("curl") || exerciseName.contains("chin up") ||
                   exerciseMuscleGroups.contains { $0.contains("bicep") }
                   
        case "Triceps":
            return exerciseName.contains("tricep") || exerciseName.contains("pushdown") ||
                   exerciseName.contains("extension") || exerciseName.contains("skull crusher") ||
                   exerciseMuscleGroups.contains { $0.contains("tricep") }
                   
        case "Forearms":
            return exerciseName.contains("wrist") || exerciseName.contains("forearm") ||
                   exerciseMuscleGroups.contains { $0.contains("forearm") }
                   
        case "Quads", "Quadriceps":
            return exerciseName.contains("squat") || exerciseName.contains("leg press") ||
                   exerciseName.contains("leg extension") || exerciseName.contains("lunge") ||
                   exerciseMuscleGroups.contains { $0.contains("quad") }
                   
        case "Hamstrings":
            return exerciseName.contains("leg curl") || exerciseName.contains("romanian") ||
                   exerciseName.contains("stiff leg") ||
                   exerciseMuscleGroups.contains { $0.contains("hamstring") }
                   
        case "Glutes":
            return exerciseName.contains("hip thrust") || exerciseName.contains("glute bridge") ||
                   exerciseName.contains("kickback") ||
                   exerciseMuscleGroups.contains { $0.contains("glute") }
                   
        case "Calves":
            return exerciseName.contains("calf raise") || exerciseName.contains("calf ") ||
                   exerciseMuscleGroups.contains { $0.contains("calf") || $0.contains("calve") }
                   
        case "Abs":
            return exerciseName.contains("crunch") || exerciseName.contains("sit up") ||
                   exerciseName.contains("plank") || exerciseName.contains("ab ") ||
                   exerciseMuscleGroups.contains { $0.contains("abs") || $0.contains("rectus") }
                   
        case "Obliques":
            return exerciseName.contains("oblique") || exerciseName.contains("twist") ||
                   exerciseName.contains("side bend") ||
                   exerciseMuscleGroups.contains { $0.contains("oblique") }
                   
        default:
            // Generic match
            let targetLower = muscleGroup.lowercased()
            return exerciseMuscleGroups.contains { $0.contains(targetLower) }
        }
    }
    
    // MARK: - Equipment Matching Helper
    /// Comprehensive equipment matching with normalization
    private func exerciseMatchesEquipment(_ exercise: Exercise, selectedEquipment: String) -> Bool {
        let exerciseEquipment = exercise.equipment?.lowercased() ?? ""
        let targetEquipment = selectedEquipment.lowercased()
        let exerciseName = exercise.name?.lowercased() ?? ""
        
        // Direct match
        if exerciseEquipment == targetEquipment { return true }
        
        // Normalize and compare
        let normalizedExercise = ExerciseFilterService.normalizeEquipment(exercise.equipment)
        if normalizedExercise == selectedEquipment { return true }
        
        // Handle compound equipment
        let equipmentParts = exerciseEquipment.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        
        switch targetEquipment {
        case "dumbbells":
            return exerciseEquipment.contains("dumbbell") || exerciseName.contains("dumbbell")
        case "barbell":
            let isBarbell = exerciseEquipment.contains("barbell") || exerciseName.contains("barbell") ||
                           exerciseEquipment.contains("ez bar") || exerciseEquipment.contains("trap bar")
            return isBarbell && !exerciseEquipment.contains("smith")
        case "cables":
            return exerciseEquipment.contains("cable") || exerciseName.contains("cable")
        case "machines":
            // IMPORTANT: Check cables and smith FIRST to exclude them
            let isCable = exerciseEquipment.contains("cable") || exerciseName.contains("cable")
            if isCable { return false }
            
            let isSmith = exerciseEquipment.contains("smith")
            if isSmith { return false }
            
            // Any machine or lever equipment
            return exerciseEquipment.contains("machine") || exerciseEquipment.contains("lever")
        case "bodyweight":
            return exerciseEquipment.isEmpty || exerciseEquipment.contains("bodyweight")
        case "kettlebell":
            return exerciseEquipment.contains("kettlebell") || exerciseName.contains("kettlebell")
        case "resistance bands", "bands":
            return exerciseEquipment.contains("band") || exerciseName.contains("band")
        case "smith machine":
            return exerciseEquipment.contains("smith") || exerciseName.contains("smith")
        default:
            return exerciseEquipment.contains(targetEquipment)
        }
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
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            
            // Compact search and filters
            compactFiltersView
            
            // Exercise list
            exerciseListView
        }
        .scrollDismissesKeyboard(.interactively) // Dismiss keyboard when interacting with scrollable content
        .onAppear {
            loadExercises()
        }
        .sheet(item: $selectedExerciseForDetail) { exercise in
            NavigationView {
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
            // Seamless search bar
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
                
                TextField("Search exercises...", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.body)
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
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
                    .padding(.horizontal, 16)
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
                        .padding(.horizontal, 16)
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
                    .padding(.horizontal, 16)
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
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .scrollDismissesKeyboard(.immediately)
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
        print("Loaded \(exercises.count) exercises")
    }
    
    private func toggleExerciseSelection(_ exercise: Exercise) {
        if let index = selectedExercises.firstIndex(where: { $0.id == exercise.id }) {
            selectedExercises.remove(at: index)
        } else {
            selectedExercises.append(exercise)
        }
    }
    
    // MARK: - 🚀 Smart Video Prefetching
    
    private func prefetchVisibleExercise(exercise: Exercise, index: Int) {
        guard let name = exercise.name else { return }
        
        var namesToPrefetch = [name]
        
        // Get next 2 exercises
        let exercises = filteredExercises
        if index + 1 < exercises.count, let nextName = exercises[index + 1].name {
            namesToPrefetch.append(nextName)
        }
        if index + 2 < exercises.count, let nextName2 = exercises[index + 2].name {
            namesToPrefetch.append(nextName2)
        }
        
        VideoPlaybackEngine.shared.prefetchVisible(exercises: namesToPrefetch)
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
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(isSelected ? .blue : Color(.systemGray4))
                
                // Exercise icon
                ZStack {
                    Circle()
                        .fill(categoryColor.opacity(0.12))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: categoryIcon)
                        .font(.system(size: 18, weight: .medium))
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
                                .font(.system(size: 18, weight: .medium))
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
                                .font(.system(size: 12, weight: .medium))
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
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
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
        case "back": return "figure.rowing"
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
                        .font(.system(size: 16, weight: .medium))
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
                                .font(.system(size: 16, weight: .medium))
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
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
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
        case "back": return "figure.rowing"
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
                .padding(.horizontal, 16)
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
                        .font(.system(size: 16, weight: .semibold))
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
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(6)
                        
                        Text(exercise.equipment ?? "")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
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
                RoundedRectangle(cornerRadius: 12)
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
                return "figure.squat"
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
        case "legs": return "figure.squat"
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
