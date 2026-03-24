import SwiftUI
import CoreData

// MarqueeTicker removed — MarqueeText now uses TimelineView (pure SwiftUI, no CADisplayLink)

// MARK: - Add Exercise During Workout View
struct AddExerciseDuringWorkoutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.colorScheme) private var colorScheme
    @Binding var exercises: [Exercise]
    let onExercisesAdded: ([Exercise]) -> Void
    
    @State private var selectedExercises: [Exercise] = []
    @State private var searchText = ""
    @State private var selectedCategory = "All"
    @State private var selectedEquipment = "All"
    @State private var availableExercises: [Exercise] = []
    @State private var selectedExerciseForDetail: Exercise?
    
    // ⚡️ SNAPPY SEARCH: Focus state for instant keyboard dismiss
    @FocusState private var isSearchFocused: Bool
    
    // ⚡️ HIGH-PERFORMANCE: Cached results
    @State private var cachedFilteredExercises: [Exercise] = []
    @State private var preFilteredExercises: [Exercise] = []
    @State private var lastFilterKey: String = ""
    @State private var searchCache: [String: [Exercise]] = [:]
    
    private let categories = ["All", "Chest", "Back", "Legs", "Shoulders", "Arms", "Core"]
    private let equipmentTypes = ["All", "Bodyweight", "Dumbbells", "Barbell", "Cable", "Machine"]
    
    var filteredExercises: [Exercise] {
        cachedFilteredExercises
    }
    
    private func updateFilteredExercises() {
        let filterKey = "\(selectedCategory)|\(selectedEquipment)"
        
        if filterKey != lastFilterKey {
            lastFilterKey = filterKey
            searchCache.removeAll()
            preFilteredExercises = applyFiltersOnly(to: availableExercises)
        }
        
        if !searchText.isEmpty {
            let searchKey = searchText.lowercased()
            if let cached = searchCache[searchKey] {
                cachedFilteredExercises = cached
                return
            }
            let results = ultraFastSearch(query: searchKey, in: preFilteredExercises)
            searchCache[searchKey] = results
            cachedFilteredExercises = results
        } else {
            cachedFilteredExercises = preFilteredExercises
        }
    }
    
    private func ultraFastSearch(query: String, in exercises: [Exercise]) -> [Exercise] {
        guard !query.isEmpty else { return exercises }
        
        // Split query into words and correct typos for each
        let queryWords = query.split(separator: " ").map { correctCommonTypos(String($0)) }
        let isMultiWord = queryWords.count > 1
        let variations = isMultiWord ? [query] : getQuickVariations(query)
        
        // Build corrected query for direct substring matching
        let correctedQuery = queryWords.joined(separator: " ")
        
        // Priority buckets (highest to lowest):
        // 1. exactMatches: name equals query exactly
        // 2. startsWithPhraseMatches: name STARTS with the exact phrase (e.g., "front raise" → "Front Raise (Dumbbell)")
        // 3. containsPhraseMatches: name CONTAINS the exact phrase (e.g., "front raise" → "Seated Front Raise")
        // 4. allWordsMatches: all words found but not as contiguous phrase (e.g., "front raise" → "Front Lat Raise")
        var exactMatches: [Exercise] = []
        var startsWithPhraseMatches: [Exercise] = []
        var containsPhraseMatches: [Exercise] = []
        var allWordsMatches: [Exercise] = []
        
        for exercise in exercises {
            guard let name = exercise.name?.lowercased() else { continue }
            
            var matched = false
            
            // SINGLE-WORD: Use variations for typo tolerance
            if !isMultiWord {
                for variation in variations {
                    if name == variation { exactMatches.append(exercise); matched = true; break }
                    else if name.hasPrefix(variation) { startsWithPhraseMatches.append(exercise); matched = true; break }
                    else if name.contains(variation) { containsPhraseMatches.append(exercise); matched = true; break }
                }
            }
            
            // MULTI-WORD: Check for exact phrase match first (preserves word order)
            if !matched && isMultiWord {
                if name == correctedQuery {
                    exactMatches.append(exercise)
                    matched = true
                } else if name.hasPrefix(correctedQuery) {
                    // Name STARTS with the exact phrase - highest priority
                    startsWithPhraseMatches.append(exercise)
                    matched = true
                } else if name.contains(correctedQuery) {
                    // Name CONTAINS the exact phrase - second priority
                    containsPhraseMatches.append(exercise)
                    matched = true
                }
            }
            
            // MULTI-WORD: Word-order-independent matching (lowest priority)
            if !matched && isMultiWord {
                let allWordsFound = queryWords.allSatisfy { word in
                    let wordVariations = getQuickVariations(word)
                    return wordVariations.contains { variation in name.contains(variation) }
                }
                if allWordsFound {
                    allWordsMatches.append(exercise)
                }
            }
        }
        
        // Return in priority order: exact phrase ordering is prioritized
        return exactMatches + startsWithPhraseMatches + containsPhraseMatches + allWordsMatches
    }
    
    private func getQuickVariations(_ query: String) -> [String] {
        let corrected = correctCommonTypos(query)
        var variations = corrected == query ? [query] : [query, corrected]
        
        let baseWord = corrected
        switch baseWord {
        case "fly": variations += ["flye", "flyes", "flies"]
        case "flye": variations += ["fly", "flyes", "flies"]
        case "curl": variations += ["curls"]
        case "curls": variations += ["curl"]
        case "press": variations += ["presses"]
        case "presses": variations += ["press"]
        case "row": variations += ["rows"]
        case "rows": variations += ["row"]
        case "raise": variations += ["raises"]
        case "raises": variations += ["raise"]
        case "bicep": variations += ["biceps"]
        case "biceps": variations += ["bicep"]
        case "tricep": variations += ["triceps"]
        case "triceps": variations += ["tricep"]
        case "pulldown": variations += ["pull-down", "pull down", "pulldowns"]
        case "pushdown": variations += ["push-down", "push down", "pushdowns"]
        case "dumbbell": variations += ["dumbell", "dumbells", "dumbbells"]
        case "dumbbells": variations += ["dumbbell", "dumbell"]
        case "barbell": variations += ["barbel", "barbells"]
        case "extension": variations += ["extensions"]
        case "extensions": variations += ["extension"]
        case "squat": variations += ["squats"]
        case "squats": variations += ["squat"]
        case "lunge": variations += ["lunges"]
        case "lunges": variations += ["lunge"]
        default:
            if baseWord.hasSuffix("s") && baseWord.count > 3 { variations.append(String(baseWord.dropLast())) }
            else if !baseWord.hasSuffix("s") && baseWord.count > 2 { variations.append(baseWord + "s") }
        }
        return variations
    }
    
    private func correctCommonTypos(_ query: String) -> String {
        // Only do EXACT matches - no substring replacement which causes bugs
        // e.g., "decline" was becoming "declinee" because it contains "declin"
        let typoMap: [String: String] = [
            "dumbell": "dumbbell", "dumbel": "dumbbell", "dumble": "dumbbell",
            "dumbells": "dumbbells", "dumbels": "dumbbells",
            "barbel": "barbell", "barble": "barbell",
            "kettleball": "kettlebell", "kettlebel": "kettlebell",
            "cabel": "cable", "cabels": "cables",
            "machien": "machine", "mashine": "machine",
            "flye": "fly", "flyes": "flies",
            "pres": "press", "presss": "press", "curle": "curl",
            "rwo": "row", "sqaut": "squat", "sqat": "squat",
            "deadlif": "deadlift", "dedlift": "deadlift",
            "extention": "extension", "extenstion": "extension",
            "pullup": "pull up", "pushup": "push up", "chinup": "chin up",
            "bycep": "bicep", "byceps": "biceps", "bicept": "bicep",
            "trycep": "tricep", "tryceps": "triceps", "tricept": "tricep",
            "sholder": "shoulder", "sholders": "shoulders",
            "inclin": "incline", "inclien": "incline",
            "declin": "decline", "declien": "decline",
            "laterl": "lateral", "latral": "lateral",
            "revers": "reverse", "bensh": "bench", "banch": "bench", "benc": "bench"
        ]
        
        // Only return correction for EXACT match
        return typoMap[query] ?? query
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
            let equipmentLower = selectedEquipment.lowercased()
            filtered = filtered.filter { exercise in
                let exerciseEquipment = (exercise.equipment ?? "").lowercased()
                return exerciseEquipment.contains(equipmentLower) || equipmentLower.contains(exerciseEquipment)
            }
        }
        
        return filtered
    }
    
    private func categoryColor(for category: String?) -> Color {
        switch category?.lowercased() {
        case "chest": return .red
        case "back": return .blue
        case "legs": return .green
        case "shoulders": return .orange
        case "arms": return .purple
        case "core": return .yellow
        default: return .gray
        }
    }
    
    private func categoryIcon(for category: String?) -> String {
        switch category?.lowercased() {
        case "chest": return "heart.fill"
        case "back": return "person.fill"
        case "legs": return "figure.walk"
        case "shoulders": return "figure.arms.open"
        case "arms": return "hand.raised.fill"
        case "core": return "circle.circle.fill"
        default: return "dumbbell.fill"
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // Animated blue/cyan orb background
                AnimatedOrbBackground.workout(colorScheme: colorScheme)
                    .ignoresSafeArea(.all, edges: .all)
                
                VStack(spacing: 0) {
                    // Search & Filter Card
                    VStack(spacing: 12) {
                        // Search bar
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                            TextField("Search exercises...", text: $searchText)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .focused($isSearchFocused)
                                .submitLabel(.done)
                                .onSubmit {
                                    // ⚡️ INSTANT keyboard dismiss on return
                                    isSearchFocused = false
                                }
                        }
                        .padding(Spacing.sm)
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                        
                        // Categories row
                        HStack(spacing: 8) {
                            Text("Categories")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 70, alignment: .leading)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(categories, id: \.self) { category in
                                        AddExerciseFilterChip(
                                            text: category,
                                            isSelected: selectedCategory == category,
                                            color: .blue,
                                            onTap: { selectedCategory = category }
                                        )
                                    }
                                }
                            }
                        }
                        
                        // Equipment row
                        HStack(spacing: 8) {
                            Text("Equipment")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 70, alignment: .leading)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(equipmentTypes, id: \.self) { equipment in
                                        AddExerciseFilterChip(
                                            text: equipment,
                                            isSelected: selectedEquipment == equipment,
                                            color: .orange,
                                            onTap: { selectedEquipment = equipment }
                                        )
                                    }
                                }
                            }
                        }
                    }
                    .padding(Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.lg)
                            .fill(.ultraThinMaterial)
                            .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
                    )
                    .padding(.horizontal, Spacing.md)
                    .padding(.top, 8)
                    
                    // Exercise list
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(filteredExercises, id: \.id) { exercise in
                                let isSelected = selectedExercises.contains(where: { $0.id == exercise.id })
                                
                                HStack(spacing: 12) {
                                    // Selection circle
                                    Button(action: {
                                        if isSelected {
                                            selectedExercises.removeAll { $0.id == exercise.id }
                                        } else {
                                            selectedExercises.append(exercise)
                                        }
                                    }) {
                                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                            .font(.title2)
                                            .foregroundColor(isSelected ? .blue : .secondary.opacity(0.5))
                                    }
                                    
                                    // Category icon
                                    ZStack {
                                        Circle()
                                            .fill(categoryColor(for: exercise.category).opacity(0.15))
                                            .frame(width: 40, height: 40)
                                        
                                        Image(systemName: categoryIcon(for: exercise.category))
                                            .font(.ds_bodyLarge)
                                            .foregroundColor(categoryColor(for: exercise.category))
                                    }
                                    
                                    // Exercise info
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(exercise.displayName)
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                        
                                        HStack(spacing: 4) {
                                            Text(exercise.category ?? "")
                                                .font(.caption)
                                                .foregroundColor(categoryColor(for: exercise.category))
                                            
                                            Text("•")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                            
                                            Text(exercise.equipment ?? "")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    // Info button
                                    Button(action: {
                                        selectedExerciseForDetail = exercise
                                    }) {
                                        Image(systemName: "info.circle")
                                            .font(.title3)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.horizontal, Spacing.md)
                                .padding(.vertical, Spacing.sm)
                                .background(Color.cardBackground)
                                .cornerRadius(CornerRadius.md)
                                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                            }
                        }
                        .padding(.horizontal, Spacing.md)
                        .padding(.top, 12)
                        .padding(.bottom, 100)
                    }
                }
                
                // Bottom add button
                VStack {
                    Button(action: {
                        exercises.append(contentsOf: selectedExercises)
                        onExercisesAdded(selectedExercises)
                        
                        // 🧠 BEHAVIOR LEARNING: Track exercises user manually adds
                        for exercise in selectedExercises {
                            if let name = exercise.name {
                                UserBehaviorLearningEngine.shared.recordCustomWorkoutAddition(exerciseName: name)
                            }
                        }
                        
                        dismiss()
                    }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Add \(selectedExercises.count) Exercise\(selectedExercises.count == 1 ? "" : "s")")
                                .fontWeight(.bold)
                        }
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.md)
                        .background(Color.cardBackground)
                        .cornerRadius(14)
                        .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
                    }
                    .disabled(selectedExercises.isEmpty)
                    .opacity(selectedExercises.isEmpty ? 0.6 : 1.0)
                    .padding(.horizontal, Spacing.md)
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("Add Exercises")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.ds_labelLarge)
                            .foregroundColor(.primary)
                    }
                }
            }
            .sheet(item: $selectedExerciseForDetail) { exercise in
                ExerciseDetailView(exercise: exercise)
            }
        }
        .onAppear {
            loadExercises()
            updateFilteredExercises()
        }
        // ⚡️ HIGH-PERFORMANCE: Instant filter updates
        .onChange(of: searchText) { _, _ in updateFilteredExercises() }
        .onChange(of: selectedCategory) { _, _ in 
            lastFilterKey = ""
            updateFilteredExercises() 
        }
        .onChange(of: selectedEquipment) { _, _ in 
            lastFilterKey = ""
            updateFilteredExercises() 
        }
        .onChange(of: availableExercises) { _, _ in 
            lastFilterKey = ""
            updateFilteredExercises() 
        }
    }
    
    private func loadExercises() {
        availableExercises = ExerciseLibraryService.shared.getAllExercises()
    }
}

// MARK: - Add Exercise Filter Chip
struct AddExerciseFilterChip: View {
    let text: String
    let isSelected: Bool
    let color: Color
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            Text(text)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .medium)
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isSelected ? color : Color(.systemGray5))
                )
        }
    }
}
