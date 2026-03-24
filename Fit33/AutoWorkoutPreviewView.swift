import SwiftUI
import CoreData

struct AutoWorkoutPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var workoutManager: WorkoutManager
    @EnvironmentObject var userManager: UserManager
    @StateObject private var generatorService = WorkoutGeneratorService.shared
    
    let primaryMuscles: [String]
    let secondaryMuscles: [String]
    let equipment: [String]
    let targetDurationMinutes: Int
    let restBetweenSets: Int
    
    @State private var exercises: [GeneratedExercise]
    @State private var isAddingExercise = false
    @State private var swappingExerciseId: String?
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingExerciseSwap = false
    @State private var selectedExerciseIndex: Int? = nil
    @State private var selectedCoreDataExercise: Exercise? = nil
    @State private var selectedGeneratedExercise: GeneratedExercise? = nil  // 🆕 Fallback for non-Core Data
    @State private var isRegenerating = false
    @State private var showingExerciseDetail = false
    @State private var showingFallbackDetail = false  // 🆕 For fallback detail view
    @State private var isSyncingExercises = false  // 🆕 For sync loading state
    @State private var isPreparingWorkout = false  // ⚡️ For warmup-pending state
    
    // Haptic feedback generators (UX Audit)
    private let selectionFeedback = UISelectionFeedbackGenerator()
    private let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
    
    // ⚡️ Warmup service for instant "Go!" transitions
    @StateObject private var warmupService = PreviewWarmupService.shared
    
    private let themeColor: Color = .blue
    
    init(primaryMuscles: [String], secondaryMuscles: [String], equipment: [String], initialExercises: [GeneratedExercise], targetDurationMinutes: Int = 45, restBetweenSets: Int = 60) {
        self.primaryMuscles = primaryMuscles
        self.secondaryMuscles = secondaryMuscles
        self.equipment = equipment
        self.targetDurationMinutes = targetDurationMinutes
        self.restBetweenSets = restBetweenSets
        self._exercises = State(initialValue: initialExercises)
    }
    
    var body: some View {
        ZStack {
            // Background gradient matching program day view style
            LinearGradient(
                gradient: Gradient(colors: colorScheme == .dark 
                    ? [themeColor.opacity(0.2), themeColor.opacity(0.05), Color(red: 0.05, green: 0.05, blue: 0.07)]
                    : [themeColor.opacity(0.3), themeColor.opacity(0.1), Color.white]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            if exercises.isEmpty {
                emptyStateView
            } else {
                exerciseListView
            }
            
            // 🆕 Loading overlay for exercise sync
            if isSyncingExercises {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                    Text("Loading exercise data...")
                        .font(.headline)
                        .foregroundColor(.white)
                }
                .padding(30)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.black.opacity(0.7))
                )
            }
            
            // ⚡️ Loading overlay when waiting for warmup to complete
            if isPreparingWorkout {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                    Text("Preparing workout...")
                        .font(.headline)
                        .foregroundColor(.white)
                }
                .padding(30)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.black.opacity(0.7))
                )
                .transition(.opacity)
            }
        }
        .navigationTitle("Your Workout")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.ds_labelLarge)
                        .foregroundColor(.primary)
                }
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .sheet(isPresented: $showingExerciseSwap) {
            if let index = selectedExerciseIndex, index < exercises.count {
                AutoExerciseSwapView(
                    currentExercise: exercises[index],
                    themeColor: themeColor,
                    primaryMuscles: primaryMuscles,
                    secondaryMuscles: secondaryMuscles,
                    equipment: equipment,
                    existingExercises: exercises
                ) { newExercise in
                    exercises[index] = newExercise
                }
            }
        }
        .sheet(isPresented: $showingExerciseDetail) {
            if let exercise = selectedCoreDataExercise {
                NavigationStack {
                    ExerciseDetailView(exercise: exercise)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Done") {
                                    showingExerciseDetail = false
                                }
                            }
                        }
                }
            }
        }
        .sheet(isPresented: $showingFallbackDetail) {
            // 🆕 Fallback detail view when Core Data not available
            if let exercise = selectedGeneratedExercise {
                NavigationStack {
                    GeneratedExerciseDetailView(exercise: exercise, themeColor: themeColor)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Done") {
                                    showingFallbackDetail = false
                                }
                            }
                        }
                }
            }
        }
        .onAppear {
            // Log screen transition
            SessionLogManager.shared.logScreen(.workoutPreview, metadata: [
                "exercise_count": exercises.count,
                "theme": themeColor.description
            ])
            
            AppLogger.debug("📱 [AutoWorkout] View appeared with \(exercises.count) exercises", category: .workout)
            if !exercises.isEmpty {
                GoButtonState.shared.show(
                    primaryColor: themeColor,
                    secondaryColor: .blue,
                    source: "AutoWorkoutPreview"
                ) {
                    // Haptic feedback on GO! (UX Audit)
                    let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
                    heavyImpact.impactOccurred()
                    startWorkout()
                }
                
                // 🚀 PREFETCH: Start loading exercise history NOW (before GO! is tapped)
                // This eliminates the N network calls when workout starts
                let exerciseNames = exercises.map { $0.name }
                Task {
                    let startTime = CFAbsoluteTimeGetCurrent()
                    AppLogger.debug("🔮 [PREFETCH] Pre-loading exercise history for \(exerciseNames.count) exercises...", category: .workout)
                    _ = await ExerciseHistoryService.shared.fetchPreviousSetsForExercises(exerciseNames)
                    AppLogger.debug("🔮 [PREFETCH] Complete in \(String(format: "%.0f", (CFAbsoluteTimeGetCurrent() - startTime) * 1000))ms", category: .workout)
                }
            }
        }
        .onDisappear {
            AppLogger.debug("📱 [AutoWorkout] View disappeared", category: .workout)
            GoButtonState.shared.hide(reason: "AutoWorkoutPreview_disappeared")
        }
    }
    
    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.orange)
            
            Text("No exercises generated")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text("Please go back and try again")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
    }
    
    // MARK: - Exercise List View
    private var exerciseListView: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header card
                workoutHeader
                
                // Exercise list section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Today's Exercises")
                            .font(.headline)
                            .fontWeight(.bold)
                        
                        Spacer()
                        
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.swap")
                                .font(.caption2)
                            Text("to swap")
                                .font(.caption)
                        }
                        .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, Spacing.xxs)
                    
                    VStack(spacing: 10) {
                        ForEach(Array(exercises.enumerated()), id: \.element.id) { index, exercise in
                            AutoExerciseCard(
                                number: index + 1,
                                exercise: exercise,
                                themeColor: themeColor,
                                isSwapping: swappingExerciseId == exercise.id,
                                onTapCard: {
                                    // Find matching Exercise from Core Data for full detail view with user stats
                                    if let coreDataExercise = ExerciseLibraryService.shared.getExercise(byName: exercise.name) {
                                        selectedCoreDataExercise = coreDataExercise
                                        showingExerciseDetail = true
                                    } else {
                                        // 🆕 Fallback: Show detail with GeneratedExercise data (no Core Data)
                                        #if DEBUG
                                        AppLogger.warning("⚠️ [AUTO-WORKOUT] Core Data exercise not found, using fallback for: \(exercise.name)", category: .workout)
                                        #endif
                                        selectedGeneratedExercise = exercise
                                        showingFallbackDetail = true
                                    }
                                },
                                onTapSwap: {
                                    selectedExerciseIndex = index
                                    showingExerciseSwap = true
                                }
                            )
                        }
                    }
                    
                    // Add more exercise button
                    if !isAddingExercise {
                        Button(action: {
                            selectionFeedback.selectionChanged()
                            addMoreExercise()
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.ds_heading3)
                                Text("Add Exercise")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(themeColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 25)
                                    .stroke(themeColor.opacity(0.3), lineWidth: 2)
                                    .background(RoundedRectangle(cornerRadius: 25).fill(Color.cardBackground))
                            )
                        }
                        .padding(.top, 8)
                    } else {
                        HStack {
                            Spacer()
                            ProgressView()
                                .tint(themeColor)
                            Text("Adding exercise...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.vertical, 14)
                    }
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, 8)
            .padding(.bottom, 120)
        }
        .onAppear {
            // 🚀 PERF: Fallback prefetch (primary prefetch happens in generator before navigation)
            // ⚡️ MEMORY FIX: Disabled video prefetching — videos load on-demand in detail view.
            // Was prefetching all exercises at once, creating multiple AVPlayers.
            
            // ⚡️ WARMUP: Pre-load all data for ActiveWorkoutView while user browses preview
            // This ensures instant "Go!" transitions with no lag
            warmupService.warmUp(
                exercises: exercises,
                context: PersistenceController.shared.container.viewContext
            )
        }
        .onDisappear {
            // Reset warmup if user backs out (they might change exercises)
            if !workoutManager.isWorkoutActive {
                warmupService.reset()
            }
        }
    }
    
    // MARK: - Workout Header
    private var workoutHeader: some View {
        HStack(spacing: 14) {
            // Workout badge
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [themeColor, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 46, height: 46)
                
                Image(systemName: "bolt.fill")
                    .font(.ds_heading2)
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(generateWorkoutTitle())
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                HStack(spacing: 8) {
                    Label("\(exercises.count) exercises", systemImage: "figure.strengthtraining.traditional")
                    Label("\(targetDurationMinutes) min", systemImage: "clock.fill")
                    Label("\(restBetweenSets)s rest", systemImage: "timer")
                }
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            
            Spacer()
            
            // Regenerate button
            Button(action: {
                selectionFeedback.selectionChanged()
                regenerateWorkout()
            }) {
                ZStack {
                    Circle()
                        .fill(themeColor.opacity(0.1))
                        .frame(width: 40, height: 40)
                    
                    if isRegenerating {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(themeColor)
                    } else {
                        Image(systemName: "shuffle")
                            .font(.ds_labelLarge)
                            .foregroundColor(themeColor)
                    }
                }
            }
            .disabled(isRegenerating)
        }
        .padding(14)
        .sleekCard(cornerRadius: 24, accentColor: themeColor)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
    
    // MARK: - Helper Functions
    private func generateWorkoutTitle() -> String {
        // Use sorted array to ensure consistent ordering
        let muscles = Array(Set(exercises.map { $0.primaryBodyRegion.capitalized })).sorted()
        if muscles.count == 1 {
            return "\(muscles[0]) Workout"
        } else if muscles.count == 2 {
            return "\(muscles[0]) & \(muscles[1])"
        } else {
            return "Full Body Workout"
        }
    }
    
    // MARK: - Actions
    private func addMoreExercise() {
        isAddingExercise = true
        
        Task {
            do {
                let newExercise = try await generatorService.addMoreExercises(
                    to: exercises,
                    primaryMuscles: primaryMuscles,
                    secondaryMuscles: secondaryMuscles,
                    equipment: equipment
                )
                
                await MainActor.run {
                    withAnimation {
                        exercises.append(newExercise)
                    }
                    isAddingExercise = false
                }
                
            } catch {
                await MainActor.run {
                    errorMessage = "Could not add more exercises. Try different filters."
                    showingError = true
                    isAddingExercise = false
                }
            }
        }
    }
    
    private func startWorkout() {
        #if DEBUG
        let totalStartTime = CFAbsoluteTimeGetCurrent()
        AppLogger.debug("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", category: .workout)
        AppLogger.debug("🎯 [AUTO-WORKOUT] startWorkout() BEGIN", category: .workout)
        AppLogger.debug("   └─ Warmup ready: \(warmupService.isWarmedUp)", category: .workout)
        #endif
        
        // Early validation
        guard !exercises.isEmpty else {
            #if DEBUG
            AppLogger.warning("⚠️ [AUTO-WORKOUT] No exercises, aborting", category: .workout)
            #endif
            return
        }
        guard !workoutManager.isWorkoutActive else {
            #if DEBUG
            AppLogger.warning("⚠️ [AUTO-WORKOUT] Workout already active, aborting", category: .workout)
            #endif
            return
        }
        
        // ⚡️ If warmup hasn't completed, show brief loading and wait
        if !warmupService.isWarmedUp && warmupService.warmupProgress < 1.0 {
            #if DEBUG
            AppLogger.debug("⏳ [AUTO-WORKOUT] Waiting for warmup to complete (progress: \(warmupService.warmupProgress * 100)%)", category: .workout)
            #endif
            isPreparingWorkout = true
            
            // Wait for warmup with timeout
            Task {
                let maxWait: TimeInterval = 2.0  // Max 2 seconds
                let startWait = Date()
                
                while !warmupService.isWarmedUp && Date().timeIntervalSince(startWait) < maxWait {
                    try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
                }
                
                await MainActor.run {
                    isPreparingWorkout = false
                    proceedWithStartWorkout()
                }
            }
            return
        }
        
        proceedWithStartWorkout()
    }
    
    private func proceedWithStartWorkout() {
        #if DEBUG
        var checkpoint = CFAbsoluteTimeGetCurrent()
        #endif
        
        let workoutTitle = generateWorkoutTitle()
        
        // Set WorkoutManager properties
        workoutManager.restTimeBetweenSets = restBetweenSets
        workoutManager.targetWorkoutDuration = targetDurationMinutes
        
        #if DEBUG
        AppLogger.debug("   Properties set: \(String(format: "%.2f", (CFAbsoluteTimeGetCurrent() - checkpoint) * 1000))ms", category: .workout)
        checkpoint = CFAbsoluteTimeGetCurrent()
        #endif
        
        // Lookup Core Data exercises by name first
        let exerciseNames = exercises.map { $0.name }
        var coreDataExercises = ExerciseLibraryService.shared.getExercises(byNames: exerciseNames)
        
        #if DEBUG
        AppLogger.debug("   Exercise lookup: \(String(format: "%.2f", (CFAbsoluteTimeGetCurrent() - checkpoint) * 1000))ms (\(coreDataExercises.count) found)", category: .workout)
        AppLogger.debug("   Looking for: \(exerciseNames.prefix(3))...", category: .workout)
        let totalInCoreData = ExerciseLibraryService.shared.getAllExercises().count
        AppLogger.debug("   Total exercises in Core Data: \(totalInCoreData)", category: .workout)
        checkpoint = CFAbsoluteTimeGetCurrent()
        #endif
        
        // 🆕 If name lookup failed, try to find by ID or create exercises in Core Data
        if coreDataExercises.count < exercises.count {
            #if DEBUG
            AppLogger.warning("⚠️ [AUTO-WORKOUT] Only found \(coreDataExercises.count)/\(exercises.count) exercises by name", category: .workout)
            AppLogger.debug("   🔧 Attempting to create missing exercises in Core Data...", category: .workout)
            #endif
            
            let context = PersistenceController.shared.container.viewContext
            var createdExercises: [Exercise] = []
            
            for generatedExercise in exercises {
                // First check if we already found this one
                if let existing = coreDataExercises.first(where: { $0.name?.lowercased() == generatedExercise.name.lowercased() }) {
                    continue // Already have it
                }
                
                // Try to find by ID if it looks like a UUID
                if let uuid = UUID(uuidString: generatedExercise.id) {
                    if let foundById = ExerciseLibraryService.shared.getAllExercises().first(where: { $0.id == uuid }) {
                        createdExercises.append(foundById)
                        #if DEBUG
                        AppLogger.info("   ✅ Found '\(generatedExercise.name)' by ID", category: .workout)
                        #endif
                        continue
                    }
                }
                
                // Create the exercise in Core Data from GeneratedExercise data
                let newExercise = Exercise(context: context)
                newExercise.id = UUID()
                newExercise.name = generatedExercise.name
                newExercise.category = generatedExercise.category
                newExercise.equipment = generatedExercise.equipment
                newExercise.instructions = generatedExercise.instructions ?? ""
                
                // Set muscle groups
                var muscleGroups = [generatedExercise.primaryMuscle]
                muscleGroups.append(contentsOf: generatedExercise.secondaryMuscles)
                newExercise.muscleGroups = muscleGroups as NSArray
                
                createdExercises.append(newExercise)
                #if DEBUG
                AppLogger.debug("   ✨ Created '\(generatedExercise.name)' in Core Data", category: .workout)
                #endif
            }
            
            // Save the new exercises to Core Data
            if !createdExercises.isEmpty {
                do {
                    try context.save()
                    // Invalidate the cache so the new exercises are available
                    ExerciseLibraryService.shared.invalidateCache()
                    #if DEBUG
                    AppLogger.debug("   💾 Saved \(createdExercises.count) new exercises to Core Data", category: .workout)
                    #endif
                } catch {
                    #if DEBUG
                    AppLogger.error("   ❌ Failed to save exercises: \(error)", category: .workout)
                    #endif
                }
            }
            
            // Combine found and created exercises in the correct order
            coreDataExercises = exercises.compactMap { generated -> Exercise? in
                // Try name match first
                if let found = coreDataExercises.first(where: { $0.name?.lowercased() == generated.name.lowercased() }) {
                    return found
                }
                // Try created exercises
                if let created = createdExercises.first(where: { $0.name?.lowercased() == generated.name.lowercased() }) {
                    return created
                }
                return nil
            }
            
            #if DEBUG
            AppLogger.debug("   📊 Final exercise count: \(coreDataExercises.count)/\(exercises.count)", category: .workout)
            #endif
        }
        
        // Still couldn't resolve exercises - show error
        if coreDataExercises.isEmpty {
            #if DEBUG
            AppLogger.error("❌ [AUTO-WORKOUT] Failed to resolve any exercises!", category: .workout)
            #endif
            errorMessage = "Unable to load exercise data. Please try regenerating the workout."
            showingError = true
            return
        }
        
        // Proceed with workout if we have exercises
        proceedWithWorkout(title: workoutTitle, coreDataExercises: coreDataExercises)
        
        #if DEBUG
        AppLogger.debug("🎯 [AUTO-WORKOUT] proceedWithStartWorkout() COMPLETE", category: .workout)
        AppLogger.debug("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", category: .workout)
        #endif
    }
    
    /// Helper function to proceed with workout after Core Data exercises are confirmed
    private func proceedWithWorkout(title: String, coreDataExercises: [Exercise]) {
        // Validate exercise IDs
        let exercisesWithValidIds = coreDataExercises.filter { $0.id != nil }
        guard exercisesWithValidIds.count == coreDataExercises.count else {
            #if DEBUG
            AppLogger.error("❌ [AUTO-WORKOUT] Some exercises missing IDs!", category: .workout)
            #endif
            errorMessage = "Some exercises are missing data. Please regenerate the workout."
            showingError = true
            return
        }
        
        // Create Workout entity
        let context = PersistenceController.shared.container.viewContext
        let workout = Workout(context: context)
        workout.id = UUID()
        workout.name = title
        workout.date = Date()
        workout.duration = 0
        workout.isCompleted = false
        
        #if DEBUG
        AppLogger.debug("   Validation complete", category: .workout)
        AppLogger.debug("🎯 [AUTO-WORKOUT] Calling workoutManager.startWorkout()...", category: .workout)
        #endif
        
        // Start workout via WorkoutManager (uses tab navigation)
        workoutManager.startWorkout(
            workout: workout,
            exercises: coreDataExercises,
            insights: nil,
            programDay: nil,
            programDayFocus: title
        )
    }
    
    private func regenerateWorkout() {
        isRegenerating = true
        
        // Hide GO button while regenerating
        GoButtonState.shared.hide()
        
        Task {
            do {
                // Generate new exercises with the same parameters
                let newExercises = try await generatorService.generateWorkout(
                    primaryMuscles: primaryMuscles,
                    secondaryMuscles: secondaryMuscles,
                    equipment: equipment,
                    count: exercises.count, // Keep the same number of exercises
                    excludeExerciseIds: [] // Fresh set of exercises
                )
                
                await MainActor.run {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        exercises = newExercises
                    }
                    isRegenerating = false
                    
                    // Show GO button again
                    GoButtonState.shared.show(
                        primaryColor: themeColor,
                        secondaryColor: .blue
                    ) {
                        startWorkout()
                    }
                }
                
                AppLogger.debug("🔄 Regenerated workout with \(newExercises.count) exercises", category: .workout)
                
            } catch {
                await MainActor.run {
                    errorMessage = "Could not regenerate workout. Please try again."
                    showingError = true
                    isRegenerating = false
                    
                    // Show GO button again even on error
                    GoButtonState.shared.show(
                        primaryColor: themeColor,
                        secondaryColor: .blue
                    ) {
                        startWorkout()
                    }
                }
            }
        }
    }
}

// MARK: - Auto Exercise Card
struct AutoExerciseCard: View {
    let number: Int
    let exercise: GeneratedExercise
    let themeColor: Color
    let isSwapping: Bool
    let onTapCard: () -> Void
    let onTapSwap: () -> Void
    
    private var categoryColor: Color {
        switch exercise.category.lowercased() {
        case "chest": return .red
        case "back": return .blue
        case "legs": return .green
        case "shoulders": return .orange
        case "arms": return .purple
        case "core": return .yellow
        default: return .cyan
        }
    }
    
    private var categoryIcon: String {
        switch exercise.category.lowercased() {
        case "chest": return "figure.strengthtraining.traditional"
        case "back": return "figure.rower"
        case "legs": return "figure.run"
        case "shoulders": return "figure.arms.open"
        case "arms": return "dumbbell.fill"
        case "core": return "figure.core.training"
        default: return "dumbbell.fill"
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Tappable card area (opens detail sheet)
            Button(action: onTapCard) {
                HStack(spacing: 12) {
                    // Category icon (matching exercise library style)
                    ZStack {
                        Circle()
                            .fill(categoryColor.opacity(0.15))
                            .frame(width: 36, height: 36)
                        
                        Image(systemName: categoryIcon)
                            .font(.ds_labelMedium)
                            .foregroundColor(categoryColor)
                    }
                    
                    // Exercise details
                    VStack(alignment: .leading, spacing: 2) {
                        Text(exercise.name)
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        HStack(spacing: 8) {
                            Text(exercise.category)
                                .font(.caption)
                                .foregroundColor(categoryColor)
                                .fontWeight(.medium)
                            
                            Text("•")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            Text(exercise.equipment)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    // Info icon
                    Image(systemName: "info.circle")
                        .font(.ds_bodyRegular).fontWeight(.medium)
                        .foregroundColor(.secondary.opacity(0.5))
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            // Swap button (separate action)
            Button(action: onTapSwap) {
                if isSwapping {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 32, height: 32)
                } else {
                    Image(systemName: "arrow.triangle.swap")
                        .font(.ds_bodyRegular).fontWeight(.medium)
                        .foregroundColor(categoryColor)
                        .padding(Spacing.xs)
                        .background(
                            Circle()
                                .fill(categoryColor.opacity(0.1))
                        )
                }
            }
            .disabled(isSwapping)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .sleekCard(cornerRadius: 20, accentColor: categoryColor)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// MARK: - Auto Exercise Swap View
struct AutoExerciseSwapView: View {
    @Environment(\.dismiss) private var dismiss
    let currentExercise: GeneratedExercise
    let themeColor: Color
    let primaryMuscles: [String]
    let secondaryMuscles: [String]
    let equipment: [String]
    let existingExercises: [GeneratedExercise]
    let onSwap: (GeneratedExercise) -> Void
    
    @State private var searchText = ""
    @State private var selectedCategory: String? = nil
    
    private var allExercises: [ExerciseData] {
        ExerciseDataProvider.shared.exercises
    }
    
    private var filteredExercises: [ExerciseData] {
        var filtered = allExercises
        
        // Exclude already selected exercises
        let existingNames = Set(existingExercises.map { $0.name })
        filtered = filtered.filter { !existingNames.contains($0.name) }
        
        // Filter by search
        if !searchText.isEmpty {
            filtered = filtered.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        
        // Filter by category
        if let category = selectedCategory {
            filtered = filtered.filter { $0.category == category }
        }
        
        return filtered
    }
    
    private var categories: [String] {
        Array(Set(allExercises.map { $0.category })).sorted()
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    
                    TextField("Search exercises...", text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                }
                .padding(Spacing.sm)
                .background(Color(.systemGray6))
                .cornerRadius(CornerRadius.md)
                .padding(.horizontal)
                .padding(.top)
                
                // Category filter
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        CategoryChip(
                            title: "All",
                            isSelected: selectedCategory == nil,
                            color: themeColor
                        ) {
                            selectedCategory = nil
                        }
                        
                        ForEach(categories, id: \.self) { category in
                            CategoryChip(
                                title: category,
                                isSelected: selectedCategory == category,
                                color: themeColor
                            ) {
                                selectedCategory = category
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, Spacing.sm)
                }
                
                // Exercise list
                List(filteredExercises, id: \.name) { exercise in
                    Button {
                        selectExercise(exercise)
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(exercise.name)
                                    .font(.body)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                                
                                HStack(spacing: 8) {
                                    Text(exercise.category)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    Text("•")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    
                                    Text(exercise.equipment)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Spacer()
                            
                            Image(systemName: "arrow.right.circle.fill")
                                .foregroundColor(themeColor)
                        }
                        .padding(.vertical, Spacing.xxs)
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Swap Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func selectExercise(_ exercise: ExerciseData) {
        let newExercise = GeneratedExercise(from: exercise)
        onSwap(newExercise)
        dismiss()
    }
}

// MARK: - Category Chip
struct CategoryChip: View {
    let title: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.xs)
                .background(
                    Capsule()
                        .fill(isSelected ? color : Color(.systemGray5))
                )
        }
    }
}

// MARK: - Exercise Data Detail View (Full Page Navigation)
struct ExerciseDataDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    let exerciseData: ExerciseData
    
    private var categoryColor: Color {
        switch exerciseData.category.lowercased() {
        case "chest": return .red
        case "back": return .blue
        case "legs": return .green
        case "shoulders": return .orange
        case "arms": return .purple
        case "core": return .pink
        case "neck": return .indigo
        default: return .cyan
        }
    }
    
    private var categoryIcon: String {
        switch exerciseData.category.lowercased() {
        case "chest": return "figure.strengthtraining.traditional"
        case "back": return "figure.rower"
        case "legs": return "figure.run"
        case "shoulders": return "figure.arms.open"
        case "arms": return "dumbbell.fill"
        case "core": return "figure.core.training"
        case "neck": return "person.bust"
        default: return "figure.walk"
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Video Section - using streaming service
                videoSection
                
                // Content Section
                VStack(alignment: .leading, spacing: 20) {
                    // Exercise Name & Category Badge
                    VStack(alignment: .leading, spacing: 12) {
                        Text(exerciseData.name)
                            .font(.ds_heading1)
                            .foregroundColor(.primary)
                        
                        HStack(spacing: 12) {
                            // Category Badge
                            HStack(spacing: 6) {
                                Image(systemName: categoryIcon)
                                    .font(.ds_labelMedium)
                                Text(exerciseData.category)
                                    .font(.ds_labelMedium)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, 6)
                            .background(
                                LinearGradient(
                                    colors: [categoryColor, categoryColor.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(20)
                            
                            // Equipment Badge
                            HStack(spacing: 6) {
                                Image(systemName: "dumbbell.fill")
                                    .font(.ds_bodySmall)
                                Text(exerciseData.equipment)
                                    .font(.ds_bodySmall)
                            }
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, 6)
                            .background(Color(.systemGray5))
                            .cornerRadius(20)
                        }
                    }
                    .padding(.top, 16)
                    
                    // Primary Muscle
                    sectionCard(title: "Primary Muscle", icon: "figure.strengthtraining.traditional") {
                        muscleTag(exerciseData.primaryMuscle, isPrimary: true)
                    }
                    
                    // Secondary Muscles
                    if !exerciseData.secondaryMuscles.isEmpty {
                        sectionCard(title: "Secondary Muscles", icon: "figure.arms.open") {
                            FlowLayout(spacing: 8) {
                                ForEach(exerciseData.secondaryMuscles, id: \.self) { muscle in
                                    muscleTag(muscle, isPrimary: false)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    
                    // How to Perform
                    if let steps = extractSteps(from: exerciseData.instructions) {
                        sectionCard(title: "How to Perform", icon: "list.number") {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                                    stepRow(number: index + 1, text: step)
                                }
                            }
                        }
                    } else if !exerciseData.instructions.isEmpty {
                        sectionCard(title: "Instructions", icon: "text.alignleft") {
                            Text(exerciseData.instructions)
                                .font(.ds_bodyMedium)
                                .foregroundColor(.secondary)
                                .lineSpacing(4)
                        }
                    }
                    
                    Spacer(minLength: 100)
                }
                .padding(.horizontal, 20)
            }
        }
        .background(Color(.systemBackground))
        .navigationTitle("Exercise Details")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.ds_labelLarge)
                        .foregroundColor(.primary)
                }
            }
        }
        .onAppear {
            // ⚡️ MEMORY FIX: Disabled — video loads on-demand via RemoteVideoPlayerView
        }
    }
    
    // MARK: - Video Section with Streaming
    private var videoSection: some View {
        RemoteVideoPlayerView(
            exerciseName: exerciseData.name,
            categoryColor: categoryColor,
            videoFilename: exerciseData.videoFilename
        )
            .aspectRatio(16/9, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [categoryColor.opacity(0.3), categoryColor.opacity(0.1)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }
    
    // MARK: - Section Card
    private func sectionCard<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.ds_labelMedium)
                    .foregroundColor(categoryColor)
                
                Text(title)
                    .font(.ds_labelLarge)
                    .foregroundColor(.primary)
            }
            
            content()
        }
        .padding(Spacing.md)
        .sleekCard(cornerRadius: 20, accentColor: categoryColor)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
    
    // MARK: - Muscle Tag
    private func muscleTag(_ muscle: String, isPrimary: Bool) -> some View {
        Text(muscle)
            .font(.system(size: 14, weight: isPrimary ? .semibold : .medium))
            .foregroundColor(isPrimary ? .white : .primary)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isPrimary ? categoryColor : Color(.systemGray5))
            )
    }
    
    // MARK: - Step Row
    private func stepRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.ds_bodySmall).fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(categoryColor)
                )
            
            Text(text)
                .font(.ds_bodyMedium)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    // MARK: - Extract Steps from Instructions
    private func extractSteps(from instructions: String) -> [String]? {
        // Try to parse numbered steps (1. Step one, 2. Step two, etc.)
        let pattern = #"^\d+[\.\)]\s*"#
        let lines = instructions.components(separatedBy: "\n")
        var steps: [String] = []
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let range = trimmed.range(of: pattern, options: .regularExpression) {
                let step = String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                if !step.isEmpty {
                    steps.append(step)
                }
            }
        }
        
        return steps.count >= 2 ? steps : nil
    }
}

// MARK: - Generated Exercise Detail View (Fallback when Core Data not available)
struct GeneratedExerciseDetailView: View {
    let exercise: GeneratedExercise
    let themeColor: Color
    @Environment(\.colorScheme) var colorScheme
    
    private var categoryColor: Color {
        switch exercise.category.lowercased() {
        case "chest": return .red
        case "back": return .blue
        case "legs": return .green
        case "shoulders": return .orange
        case "arms": return .purple
        case "core": return .yellow
        default: return themeColor
        }
    }
    
    private var categoryIcon: String {
        switch exercise.category.lowercased() {
        case "chest": return "figure.strengthtraining.traditional"
        case "back": return "figure.rower"
        case "legs": return "figure.run"
        case "shoulders": return "figure.arms.open"
        case "arms": return "dumbbell.fill"
        case "core": return "figure.core.training"
        default: return "dumbbell.fill"
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Video Section
                RemoteVideoPlayerView(
                    exerciseName: exercise.name,
                    categoryColor: categoryColor,
                    videoFilename: nil  // Will use cache lookup
                )
                .aspectRatio(16/9, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .background(
                    LinearGradient(
                        colors: [categoryColor.opacity(0.3), categoryColor.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                
                // Content Section
                VStack(alignment: .leading, spacing: 20) {
                    // Exercise Name & Category Badge
                    VStack(alignment: .leading, spacing: 12) {
                        Text(exercise.name)
                            .font(.ds_heading1)
                            .foregroundColor(.primary)
                        
                        HStack(spacing: 12) {
                            // Category Badge
                            HStack(spacing: 6) {
                                Image(systemName: categoryIcon)
                                    .font(.ds_labelMedium)
                                Text(exercise.category)
                                    .font(.ds_labelMedium)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, 6)
                            .background(
                                LinearGradient(
                                    colors: [categoryColor, categoryColor.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(20)
                            
                            // Equipment Badge
                            HStack(spacing: 6) {
                                Image(systemName: "dumbbell.fill")
                                    .font(.ds_bodySmall)
                                Text(exercise.equipment)
                                    .font(.ds_bodySmall)
                            }
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, 6)
                            .background(Color(.systemGray5))
                            .cornerRadius(20)
                        }
                    }
                    .padding(.top, 16)
                    
                    // Primary Muscle
                    sectionCard(title: "Primary Muscle", icon: "figure.strengthtraining.traditional") {
                        Text(exercise.primaryMuscle)
                            .font(.ds_labelMedium)
                            .foregroundColor(.white)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(categoryColor)
                            )
                    }
                    
                    // Secondary Muscles
                    if !exercise.secondaryMuscles.isEmpty {
                        sectionCard(title: "Secondary Muscles", icon: "figure.arms.open") {
                            FlowLayout(spacing: 8) {
                                ForEach(exercise.secondaryMuscles, id: \.self) { muscle in
                                    Text(muscle)
                                        .font(.ds_bodySmall).fontWeight(.medium)
                                        .foregroundColor(.primary)
                                        .padding(.horizontal, Spacing.sm)
                                        .padding(.vertical, 6)
                                        .background(
                                            Capsule()
                                                .fill(Color(.systemGray5))
                                        )
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    
                    // Instructions
                    if let instructions = exercise.instructions, !instructions.isEmpty {
                        sectionCard(title: "Instructions", icon: "text.alignleft") {
                            Text(instructions)
                                .font(.ds_bodyMedium)
                                .foregroundColor(.secondary)
                                .lineSpacing(4)
                        }
                    }
                    
                    Spacer(minLength: 100)
                }
                .padding(.horizontal, 20)
            }
        }
        .background(Color(.systemBackground))
        .navigationTitle("Exercise Details")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // ⚡️ MEMORY FIX: Disabled — video loads on-demand via RemoteVideoPlayerView
        }
    }
    
    // MARK: - Section Card
    private func sectionCard<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.ds_labelMedium)
                    .foregroundColor(categoryColor)
                
                Text(title)
                    .font(.ds_labelLarge)
                    .foregroundColor(.primary)
            }
            
            content()
        }
        .padding(Spacing.md)
        .sleekCard(cornerRadius: 20, accentColor: categoryColor)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
