import SwiftUI
import CoreData
import Combine
import Supabase
import PostgREST

// Notification for forcing immediate tab switch (bypasses SwiftUI state delays)
extension Notification.Name {
    static let forceWorkoutTabSwitch = Notification.Name("forceWorkoutTabSwitch")
}

struct WorkoutInsights {
    let userSelections: [String]
    let appliedPairings: [String]
    let pairingDescriptions: [String]
    let exerciseCount: Int
}

class WorkoutManager: ObservableObject {
    @Published var isWorkoutActive: Bool = false
    @Published var currentWorkout: Workout?
    @Published var currentExercises: [Exercise] = []
    @Published var workoutStartTime: Date?
    @Published var shouldNavigateToWorkoutTab: Bool = false
    @Published var shouldNavigateToHomeTab: Bool = false
    @Published var shouldPopToRootHome: Bool = false
    @Published var shouldDismissCardioFlow: Bool = false  // Dismiss entire cardio workout flow
    @Published var shouldShowWorkoutGenerator: Bool = false
    @Published var shouldNavigateToAutoGen: Bool = false  // 🔧 Redirect Home→Workout auto-gen flow
    @Published var shouldNavigateToPrograms: Bool = false  // 🔧 Redirect Home→Workout programs
    @Published var shouldNavigateToFindFriends: Bool = false  // 🔧 Redirect Home→Workout friends (for challenges)
    @Published var shouldNavigateToProfileFriends: Bool = false  // 🔧 Redirect Home→Profile friends (Challenge a Friend)
    @Published var autoGenCameFromHomeTab: Bool = false   // 🔧 Track if auto-gen was started from Home tab
    @Published var shouldNavigateToHomeTabInstant: Bool = false  // 🔧 Instant tab switch (no animation)
    
    // 🔧 Navigate to program views on Workout tab (from Dashboard)
    @Published var shouldNavigateToProgramOverview: Bool = false
    @Published var shouldNavigateToProgramDay: Bool = false
    @Published var navigateProgramData: SmartActiveProgram? = nil
    @Published var navigateProgramTemplate: SmartProgramTemplate? = nil
    @Published var navigateProgramDay: SmartProgramDay? = nil
    @Published var isTransitioningBackToHome: Bool = false  // 🔧 Cover back navigation transition
    @Published var shouldClearWorkoutTabNav: Bool = false  // 🔧 Clear nav path before workout starts
    @Published var currentTime: Date = Date()
    @Published var workoutInsights: WorkoutInsights? = nil
    
    // Workout generator selections state
    @Published var generatorSelections: (bodyParts: Set<String>, equipment: Set<String>, surpriseMe: Bool)? = nil
    @Published var shouldTriggerWorkoutGeneration: Bool = false
    @Published var shouldStartPreviewWorkout: Bool = false
    @Published var isOnGeneratorScreen: Bool = false
    @Published var isOnWorkoutPreviewScreen: Bool = false
    
    // Custom workout builder state
    @Published var isOnCustomWorkoutBuilder: Bool = false
    @Published var selectedCustomWorkoutExercises: [Exercise] = []
    @Published var shouldStartCustomWorkout: Bool = false
    @Published var exerciseToAddToCustomWorkout: Exercise? = nil  // Pre-select exercise when opening builder
    @Published var shouldNavigateToCustomWorkoutBuilder: Bool = false  // Trigger navigation to builder
    
    // Active program tracking (persisted to UserDefaults)
    @Published var activeProgram: WorkoutProgram? = nil {
        didSet {
            AppLogger.debug("🔔 [PROGRAM] activeProgram changed: \(oldValue?.name ?? "nil") -> \(activeProgram?.name ?? "nil")", category: .workout)
            saveActiveProgramToStorage()
        }
    }
    @Published var programStartDate: Date? = nil {
        didSet {
            saveProgramStartDateToStorage()
        }
    }
    @Published var programCompletedDays: Set<Int> = [] {
        didSet {
            saveProgramCompletedDaysToStorage()
        }
    }
    
    // Workout preview data (for starting from preview screen)
    @Published var previewProgram: WorkoutProgram? = nil
    @Published var previewDay: Int? = nil
    @Published var previewExercises: [ExerciseData] = []
    @Published var currentProgramDayNumber: Int? = nil
    @Published var currentProgramDayFocus: String? = nil
    @Published var currentSmartProgramId: String? = nil
    @Published var currentProgramWeek: Int? = nil
    
    // Rest timer settings (adjusted based on workout duration)
    @Published var restTimeBetweenSets: Int = 60 // Default 60 seconds
    @Published var targetWorkoutDuration: Int = 45 // Default 45 minutes
    
    // Persistent storage for exercise sets data (survives view rebuilds during ads)
    // Key is exercise ID (String), value is array of WorkoutSetData
    // This is @Published so UI updates when sets are added/removed
    // The WorkoutSetData objects themselves have stable UUIDs and persist across view rebuilds
    @Published var exerciseSetsData: [String: [WorkoutSetData]] = [:]
    
    static var userDefaultSetCount: Int {
        let stored = UserDefaults.standard.integer(forKey: "defaultSetCount")
        return stored > 0 ? stored : 3
    }
    
    @MainActor func padAllExercisesToSetCount(_ targetCount: Int) {
        var didUpdate = false
        for (exerciseId, sets) in exerciseSetsData {
            if sets.count < targetCount {
                var updated = sets
                for _ in sets.count..<targetCount {
                    updated.append(WorkoutSetData())
                }
                exerciseSetsData[exerciseId] = updated
                didUpdate = true
            }
        }
        if didUpdate { throttledSave() }
    }
    
    // Get sets for an exercise ID (read-only, does NOT create if missing)
    func getSetsForExercise(id: String) -> [WorkoutSetData] {
        if let existingSets = exerciseSetsData[id], !existingSets.isEmpty {
            return existingSets
        } else {
            // Return empty array - initialization should happen in initializeSetsForExercise
            return []
        }
    }
    
    // Initialize sets for an exercise if not already present (call this BEFORE rendering)
    // Row count = max(previous workout's set count, user's default set count).
    // Sets are always empty WorkoutSetData — previous values render as grey TextField
    // placeholders (see SetRowView.weightPlaceholder / reps placeholder), never as
    // pre-filled values. Tapping the checkmark without typing still falls back to the
    // previous-set values in SetRowView's completion handler.
    @MainActor func initializeSetsForExercise(id: String, exerciseName: String = "") {
        if exerciseSetsData[id] == nil || exerciseSetsData[id]?.isEmpty == true {
            let defaultCount = Self.userDefaultSetCount
            let previousCount = Self.previousSetCount(forExerciseId: id, exerciseName: exerciseName)
            let rowCount = max(previousCount, defaultCount)
            let sets = (0..<rowCount).map { _ in WorkoutSetData() }
            exerciseSetsData[id] = sets
            #if DEBUG
            AppLogger.debug("📦 Initialized \(sets.count) empty sets for exercise \(id.prefix(8)) (prev: \(previousCount), default: \(defaultCount))", category: .data)
            #endif
        }
    }

    /// Look up how many working sets the user performed last time for this exercise.
    /// Checks the pre-warmed cache first, then the Supabase history cache. Safe to call
    /// with an empty `exerciseName` (returns 0). Runs on main actor because both caches
    /// are @MainActor-isolated.
    @MainActor static func previousSetCount(forExerciseId id: String, exerciseName: String) -> Int {
        guard !exerciseName.isEmpty else { return 0 }
        if let preWarmed = PreviewWarmupService.shared.getPreviousSets(forExerciseId: id, exerciseName: exerciseName),
           !preWarmed.isEmpty {
            return preWarmed.count
        }
        if let cached = ExerciseHistoryService.shared.previousSetsCache[exerciseName],
           !cached.isEmpty {
            return cached.count
        }
        return 0
    }
    
    // ⚡️ CRITICAL PERFORMANCE: Pre-fetch all Core Data properties BEFORE navigation
    // This forces Core Data to materialize exercise data from disk immediately,
    // so SwiftUI doesn't have to wait for lazy fetching during render
    func prefetchExerciseData(_ exercises: [Exercise]) {
        #if DEBUG
        let startTime = CFAbsoluteTimeGetCurrent()
        AppLogger.debug("⚡️ [PREFETCH] Pre-warming \(exercises.count) exercises...", category: .performance)
        #endif
        
        // Force Core Data to fetch all properties we'll need during rendering
        // by accessing them now (while user sees transition animation)
        for exercise in exercises {
            // Access all properties that will be read during view render
            // This triggers Core Data to load from disk NOW, not during SwiftUI layout
            _ = exercise.id
            _ = exercise.name
            _ = exercise.category
            _ = exercise.equipment
            _ = exercise.muscleGroups
            _ = exercise.isFavorite
            _ = exercise.displayName // This also pre-warms nickname lookup
        }
        
        #if DEBUG
        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        AppLogger.debug("⚡️ [PREFETCH] Pre-warmed \(exercises.count) exercises in \(String(format: "%.2f", elapsed))ms", category: .performance)
        #endif
    }
    
    // Ensure all exercises have initialized sets (call on workout start)
    // OPTIMIZED: Batch all updates to trigger only ONE SwiftUI re-render
    // SMART: Row count = max(previous workout's set count, user's default set count).
    // Sets are always empty — previous values render as grey placeholders in the UI
    // (see SetRowView.weightPlaceholder). This matches the user's "repeat exercise"
    // expectation: never pre-fill values, always show last workout's numbers as hints.
    @MainActor func initializeSetsForExercises(_ exercises: [Exercise]) {
        #if DEBUG
        let startTime = CFAbsoluteTimeGetCurrent()
        #endif

        // Build updates locally first (no @Published triggers)
        var updates: [String: [WorkoutSetData]] = [:]
        var totalSets = 0

        for exercise in exercises {
            if let exerciseId = exercise.id?.uuidString {
                if exerciseSetsData[exerciseId] == nil || exerciseSetsData[exerciseId]?.isEmpty == true {
                    let exerciseName = exercise.name ?? ""
                    let defaultCount = Self.userDefaultSetCount
                    let previousCount = Self.previousSetCount(forExerciseId: exerciseId, exerciseName: exerciseName)
                    let rowCount = max(previousCount, defaultCount)
                    let sets = (0..<rowCount).map { _ in WorkoutSetData() }

                    updates[exerciseId] = sets
                    totalSets += sets.count
                    #if DEBUG
                    AppLogger.debug("📦 Initialized \(sets.count) empty sets for '\(exerciseName)' \(exerciseId.prefix(8)) (prev: \(previousCount), default: \(defaultCount))", category: .data)
                    #endif
                }
            }
        }

        #if DEBUG
        let buildTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        AppLogger.debug("📦 Built \(totalSets) sets in \(String(format: "%.2f", buildTime))ms", category: .data)
        let mergeStart = CFAbsoluteTimeGetCurrent()
        #endif

        // Apply all updates at once (single @Published trigger)
        if !updates.isEmpty {
            exerciseSetsData.merge(updates) { _, new in new }
        }

        #if DEBUG
        let mergeTime = (CFAbsoluteTimeGetCurrent() - mergeStart) * 1000
        AppLogger.debug("📦 Merge completed in \(String(format: "%.2f", mergeTime))ms", category: .data)
        AppLogger.debug("📦 Initialized sets for \(exercises.count) exercises (total: \(String(format: "%.2f", (CFAbsoluteTimeGetCurrent() - startTime) * 1000))ms)", category: .performance)
        #endif
    }
    
    // Update sets for an exercise (replaces entire array)
    func updateSetsForExercise(id: String, sets: [WorkoutSetData]) {
        exerciseSetsData[id] = sets
        
        // ⚡️ PERSISTENCE: Save immediately when sets are updated
        // (Debounced via throttle to avoid excessive saves)
        throttledSave()
    }
    
    // Add a set to an exercise
    func addSetToExercise(id: String, set: WorkoutSetData) {
        if exerciseSetsData[id] != nil {
            exerciseSetsData[id]?.append(set)
        } else {
            exerciseSetsData[id] = [set]
        }
        
        // ⚡️ PERSISTENCE: Save immediately when set is added
        throttledSave()
    }
    
    // Throttle saves to at most once per 5 seconds for performance
    private var lastSaveTime: Date = .distantPast
    private func throttledSave() {
        let now = Date()
        guard now.timeIntervalSince(lastSaveTime) > 5 else { return }
        lastSaveTime = now
        saveActiveWorkoutToStorage()
    }
    
    // Clear all sets data (when workout ends)
    func clearAllSetsData() {
        exerciseSetsData.removeAll()
        Task { @MainActor in
            ExerciseSwapService.shared.clearSwapCache()
        }
        // Similar-exercise suggestions are cached by exercise name for the current
        // workout. Drop them when the workout ends so the next workout picks up any
        // fresh history the user just created (e.g. they did Barbell Curl today, so
        // tomorrow's Dumbbell Curl suggestion should reflect it).
        StrengthProfileRecommendationEngine.shared.clearSimilarExerciseCache()
    }
    
    var canGenerateWorkout: Bool {
        guard let selections = generatorSelections else { return false }
        return (!selections.bodyParts.isEmpty || selections.surpriseMe) && !selections.equipment.isEmpty
    }
    
    var programProgress: Double {
        guard let program = activeProgram else { return 0 }
        return Double(programCompletedDays.count) / Double(program.duration)
    }
    
    var currentProgramDay: Int {
        guard let startDate = programStartDate else { return 0 }
        let daysPassed = Calendar.current.dateComponents([.day], from: startDate, to: Date()).day ?? 0
        return min(daysPassed + 1, activeProgram?.duration ?? 0)
    }
    
    func startProgram(_ program: WorkoutProgram) {
        AppLogger.debug("🎯 [PROGRAM] startProgram called for: \(program.name)", category: .workout)
        AppLogger.debug("🎯 [PROGRAM] activeProgram BEFORE: \(activeProgram?.name ?? "nil")", category: .workout)
        activeProgram = program
        programStartDate = Date()
        programCompletedDays = []
        AppLogger.debug("🎯 [PROGRAM] activeProgram AFTER: \(activeProgram?.name ?? "nil")", category: .workout)
        AppLogger.debug("🎯 [PROGRAM] Started program: \(program.name)", category: .workout)
    }
    
    @MainActor func startProgramWorkout(day: Int, context: NSManagedObjectContext) {
        guard let program = activeProgram,
              let programDay = program.schedule[day] else {
            AppLogger.error("❌ No program day found for day \(day)", category: .workout)
            return
        }
        
        AppLogger.debug("🏋️ Starting program day \(day): \(programDay.name)", category: .workout)
        AppLogger.debug("   Focus: \(programDay.focus.joined(separator: ", "))", category: .data)
        
        // Generate fresh workout using intelligent generator with day's focus
        let (workout, exercises) = WorkoutProgramEngine.shared.generateWorkoutFromProgramDay(
            programDay,
            context: context
        )
        
        // Start the workout
        startWorkout(workout: workout, exercises: exercises, insights: nil)
        
        // Mark this day as started (could add completion tracking)
        AppLogger.debug("✅ Started fresh workout for Day \(day) with \(exercises.count) exercises", category: .data)
    }
    
    @MainActor func startPreviewWorkout(context: NSManagedObjectContext) {
        guard let program = previewProgram,
              let day = previewDay,
              let programDay = program.schedule[day] else {
            AppLogger.error("❌ No preview workout data available", category: .workout)
            return
        }
        
        AppLogger.debug("🚀 Starting workout from preview screen", category: .data)
        
        // Create workout
        let workout = Workout(context: context)
        workout.id = UUID()
        workout.name = programDay.name
        workout.date = Date()
        workout.duration = 0
        workout.isCompleted = false
        
        // Convert generated ExerciseData to Core Data Exercise objects
        let allExercises = ExerciseLibraryService.shared.getAllExercises()
        let exercises = previewExercises.compactMap { exerciseData in
            allExercises.first { $0.name == exerciseData.name }
        }
        
        AppLogger.debug("   Starting with \(exercises.count) exercises", category: .data)
        
        // Start the workout with program day info
        startWorkout(
            workout: workout,
            exercises: exercises,
            insights: nil,
            programDay: day,
            programDayFocus: programDay.name
        )
        
        AppLogger.debug("✅ Preview workout started successfully", category: .workout)
    }
    
    func markProgramDayComplete(_ day: Int) {
        programCompletedDays.insert(day)
        AppLogger.debug("✅ Marked program day \(day) complete. Total: \(programCompletedDays.count)", category: .workout)
    }
    
    func cancelProgram() {
        activeProgram = nil
        programStartDate = nil
        programCompletedDays = []
        clearProgramStorage()
        AppLogger.error("❌ Program cancelled", category: .workout)
    }
    
    static let shared = WorkoutManager()
    
    private var timer: AnyCancellable?
    
    // MARK: - Program Persistence Keys
    private let activeProgramKey = "activeProgram"
    private let programStartDateKey = "programStartDate"
    private let programCompletedDaysKey = "programCompletedDays"
    
    // MARK: - Active Workout Persistence Keys
    private let activeWorkoutKey = "activeWorkoutState"
    private let workoutSetsDataKey = "workoutSetsData"
    
    // Maximum time (in seconds) before auto-ending a workout (4 hours)
    private let maxWorkoutDuration: TimeInterval = 4 * 60 * 60
    
    private init() {
        loadActiveProgramFromStorage()
        
        // Defer Core Data work to background — sync fetch in init() blocks the main thread
        Task { [weak self] in
            await self?.loadActiveWorkoutFromStorage()
        }
        
        $isWorkoutActive
            .sink { [weak self] isActive in
                if isActive {
                    self?.startTimer()
                } else {
                    self?.stopTimer()
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Program Persistence
    private func saveActiveProgramToStorage() {
        if let program = activeProgram {
            if let encoded = try? JSONEncoder().encode(program) {
                UserDefaults.standard.set(encoded, forKey: activeProgramKey)
                AppLogger.debug("💾 [PROGRAM] Saved active program: \(program.name)", category: .workout)
            }
        } else {
            UserDefaults.standard.removeObject(forKey: activeProgramKey)
            AppLogger.debug("💾 [PROGRAM] Cleared active program from storage", category: .workout)
        }
    }
    
    private func saveProgramStartDateToStorage() {
        if let date = programStartDate {
            UserDefaults.standard.set(date, forKey: programStartDateKey)
        } else {
            UserDefaults.standard.removeObject(forKey: programStartDateKey)
        }
    }
    
    private func saveProgramCompletedDaysToStorage() {
        let daysArray = Array(programCompletedDays)
        UserDefaults.standard.set(daysArray, forKey: programCompletedDaysKey)
    }
    
    private func loadActiveProgramFromStorage() {
        // Load active program
        if let data = UserDefaults.standard.data(forKey: activeProgramKey),
           let program = try? JSONDecoder().decode(WorkoutProgram.self, from: data) {
            // Set without triggering didSet to avoid re-saving
            self.activeProgram = program
            AppLogger.debug("📂 [PROGRAM] Loaded active program: \(program.name)", category: .workout)
        }
        
        // Load start date
        if let date = UserDefaults.standard.object(forKey: programStartDateKey) as? Date {
            self.programStartDate = date
            AppLogger.debug("📂 [PROGRAM] Loaded start date: \(date)", category: .workout)
        }
        
        // Load completed days
        if let daysArray = UserDefaults.standard.array(forKey: programCompletedDaysKey) as? [Int] {
            self.programCompletedDays = Set(daysArray)
            AppLogger.debug("📂 [PROGRAM] Loaded completed days: \(daysArray)", category: .workout)
        }
    }
    
    private func clearProgramStorage() {
        UserDefaults.standard.removeObject(forKey: activeProgramKey)
        UserDefaults.standard.removeObject(forKey: programStartDateKey)
        UserDefaults.standard.removeObject(forKey: programCompletedDaysKey)
        AppLogger.debug("🗑️ [PROGRAM] Cleared all program storage", category: .workout)
    }
    
    // MARK: - Active Workout Persistence
    
    /// Structure to persist active workout state
    private struct ActiveWorkoutState: Codable {
        let workoutId: String
        let exerciseIds: [String]
        let startTime: Date
        let programDayNumber: Int?
        let programDayFocus: String?
        let smartProgramId: String?
    }
    
    /// Persisted set data (Codable version of WorkoutSetData)
    private struct PersistedSetData: Codable {
        let id: String
        let weight: Double
        let reps: Int
        let isCompleted: Bool
        let setType: String  // Using string for Codable compatibility
        let restTime: TimeInterval
        
        // Legacy support - decode old format
        let isFailure: Bool?
        let isDropset: Bool?
    }
    
    /// Save active workout state to UserDefaults (call on workout start and state changes)
    func saveActiveWorkoutToStorage() {
        guard isWorkoutActive,
              let workout = currentWorkout,
              let workoutId = workout.id?.uuidString else {
            // No active workout - clear storage
            clearActiveWorkoutStorage()
            return
        }
        
        // ⚠️ SAFETY: Verify exercises are valid before saving
        // This prevents saving corrupted state that can't be restored
        guard !currentExercises.isEmpty else {
            #if DEBUG
            AppLogger.error("⚠️ [WORKOUT] Cannot save workout state with empty exercises - potential data corruption", category: .data)
            #endif
            // Don't clear storage yet - this might be a temporary state
            return
        }
        
        let exerciseIds = currentExercises.compactMap { $0.id?.uuidString }
        
        // Additional safety check - ensure we got valid IDs
        guard exerciseIds.count == currentExercises.count else {
            #if DEBUG
            AppLogger.error("⚠️ [WORKOUT] Some exercises have nil IDs - cannot save workout state safely", category: .data)
            #endif
            return
        }
        
        let state = ActiveWorkoutState(
            workoutId: workoutId,
            exerciseIds: exerciseIds,
            startTime: workoutStartTime ?? Date(),
            programDayNumber: currentProgramDayNumber,
            programDayFocus: currentProgramDayFocus,
            smartProgramId: currentSmartProgramId
        )
        
        if let encoded = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(encoded, forKey: activeWorkoutKey)
        }
        
        var persistedSets: [String: [PersistedSetData]] = [:]
        for (exerciseId, sets) in exerciseSetsData {
            persistedSets[exerciseId] = sets.map { set in
                PersistedSetData(
                    id: set.id.uuidString,
                    weight: set.weight,
                    reps: set.reps,
                    isCompleted: set.isCompleted,
                    setType: set.setType.rawValue,
                    restTime: set.restTime,
                    isFailure: nil,
                    isDropset: nil
                )
            }
        }
        
        if let setsEncoded = try? JSONEncoder().encode(persistedSets) {
            UserDefaults.standard.set(setsEncoded, forKey: workoutSetsDataKey)
        }
    }
    
    /// Load active workout state from UserDefaults (call on app launch).
    /// Uses the main-queue viewContext but runs inside an async Task so init() returns instantly.
    @MainActor
    private func loadActiveWorkoutFromStorage() async {
        AppLogger.debug("📂 [WORKOUT] Checking for saved active workout...", category: .data)
        
        guard let data = UserDefaults.standard.data(forKey: activeWorkoutKey) else {
            AppLogger.debug("📂 [WORKOUT] No saved active workout data found", category: .data)
            return
        }
        
        guard let state = try? JSONDecoder().decode(ActiveWorkoutState.self, from: data) else {
            AppLogger.error("⚠️ [WORKOUT] Could not decode saved workout state", category: .data)
            return
        }
        
        let elapsedTime = Date().timeIntervalSince(state.startTime)
        let hoursElapsed = elapsedTime / 3600
        let minutesElapsed = Int(elapsedTime / 60)
        
        if elapsedTime > maxWorkoutDuration {
            AppLogger.warning("⏰ [WORKOUT] Active workout expired (\(String(format: "%.1f", hoursElapsed)) hours old, limit is 4 hours) - auto-ending", category: .performance)
            clearActiveWorkoutStorage()
            return
        }
        
        AppLogger.debug("📂 [WORKOUT] Found saved active workout (started \(minutesElapsed) minutes ago)", category: .performance)
        AppLogger.debug("📂 [WORKOUT] Workout ID: \(state.workoutId)", category: .data)
        AppLogger.debug("📂 [WORKOUT] Exercise IDs: \(state.exerciseIds.count) exercises", category: .data)
        
        let context = PersistenceController.shared.container.viewContext
        let exerciseUUIDs = state.exerciseIds.compactMap { UUID(uuidString: $0) }
        AppLogger.debug("📂 [WORKOUT] Looking for exercises with IDs: \(exerciseUUIDs.map { $0.uuidString.prefix(8) })", category: .data)
        
        // Run Core Data fetches inside context.perform to yield the main thread between frames
        let (workout, exercises): (Workout?, [Exercise]) = await withCheckedContinuation { continuation in
            context.perform {
                let workoutFetch: NSFetchRequest<Workout> = Workout.fetchRequest()
                workoutFetch.predicate = NSPredicate(format: "id == %@", state.workoutId)
                workoutFetch.fetchLimit = 1
                let fetchedWorkout = try? context.fetch(workoutFetch).first
                
                let exerciseFetch: NSFetchRequest<Exercise> = Exercise.fetchRequest()
                exerciseFetch.predicate = NSPredicate(format: "id IN %@", exerciseUUIDs)
                let fetchedExercises = (try? context.fetch(exerciseFetch)) ?? []
                
                continuation.resume(returning: (fetchedWorkout, fetchedExercises))
            }
        }
        
        var resolvedWorkout = workout
        
        if resolvedWorkout == nil {
            AppLogger.warning("⚠️ [WORKOUT] Could not find saved workout in Core Data — creating placeholder...", category: .data)
            let newWorkout = Workout(context: context)
            newWorkout.id = UUID(uuidString: state.workoutId) ?? UUID()
            newWorkout.name = "Workout"
            newWorkout.date = state.startTime
            newWorkout.isCompleted = false
            resolvedWorkout = newWorkout
            do {
                try context.save()
            } catch {
                AppLogger.error("❌ [WORKOUT] Failed to create placeholder workout: \(error)", category: .data)
                clearActiveWorkoutStorage()
                return
            }
        }
        
        guard let finalWorkout = resolvedWorkout else {
            clearActiveWorkoutStorage()
            return
        }
        
        if finalWorkout.isCompleted {
            AppLogger.warning("⚠️ [WORKOUT] Restored workout was marked as completed - resetting", category: .data)
            finalWorkout.isCompleted = false
            try? context.save()
        }
        
        AppLogger.debug("📂 [WORKOUT] Found \(exercises.count) exercises in Core Data", category: .data)
        
        if exercises.isEmpty {
            AppLogger.error("⚠️ [WORKOUT] Could not find any saved exercises in Core Data", category: .data)
            AppLogger.error("⚠️ [WORKOUT] This means the workout data is corrupted - clearing to prevent crash loop", category: .data)
            clearActiveWorkoutStorage()
            
            // Show notification to user that workout was lost
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: NSNotification.Name("WorkoutDataCorrupted"),
                    object: nil,
                    userInfo: ["message": "Your previous workout could not be restored. This can happen if the app was interrupted unexpectedly."]
                )
            }
            return
        }
        
        // Sort exercises to match original order
        let orderedExercises = state.exerciseIds.compactMap { id -> Exercise? in
            exercises.first { $0.id?.uuidString == id }
        }
        
        // Final safety check - ensure we have exercises after ordering
        if orderedExercises.isEmpty {
            AppLogger.error("⚠️ [WORKOUT] No exercises after ordering - clearing to prevent crash loop", category: .data)
            clearActiveWorkoutStorage()
            return
        }
        
        // Load sets data (this is the most important data to preserve!)
        if let setsData = UserDefaults.standard.data(forKey: workoutSetsDataKey),
           let persistedSets = try? JSONDecoder().decode([String: [PersistedSetData]].self, from: setsData) {
            
            for (exerciseId, sets) in persistedSets {
                exerciseSetsData[exerciseId] = sets.map { persisted in
                    let setData = WorkoutSetData()
                    setData.weight = persisted.weight
                    setData.reps = persisted.reps
                    setData.isCompleted = persisted.isCompleted
                    setData.restTime = persisted.restTime
                    
                    // Restore setType - handle legacy data migration
                    if let setTypeValue = SetType(rawValue: persisted.setType) {
                        setData.setType = setTypeValue
                    } else if persisted.isFailure == true {
                        setData.setType = .failure
                    } else if persisted.isDropset == true {
                        setData.setType = .dropset
                    } else {
                        setData.setType = .normal
                    }
                    
                    return setData
                }
            }
            
            // Count completed sets
            var completedSets = 0
            for (_, sets) in exerciseSetsData {
                completedSets += sets.filter { $0.isCompleted }.count
            }
            AppLogger.debug("📂 [WORKOUT] Restored \(persistedSets.count) exercises with \(completedSets) completed sets", category: .data)
        }
        
        // Restore workout state
        currentWorkout = resolvedWorkout
        currentExercises = orderedExercises
        workoutStartTime = state.startTime
        currentProgramDayNumber = state.programDayNumber
        currentProgramDayFocus = state.programDayFocus
        currentSmartProgramId = state.smartProgramId
        isWorkoutActive = true
        
        AppLogger.debug("✅ [WORKOUT] Successfully restored active workout with \(orderedExercises.count) exercises", category: .data)
        AppLogger.debug("✅ [WORKOUT] Workout has been active for \(minutesElapsed) minutes (\(String(format: "%.1f", hoursElapsed)) hours)", category: .performance)
        
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(0.5))
            guard !Task.isCancelled else { return }
            self?.shouldNavigateToWorkoutTab = true
        }
    }
    
    /// Clear active workout storage (call when workout finishes/cancels)
    private func clearActiveWorkoutStorage() {
        UserDefaults.standard.removeObject(forKey: activeWorkoutKey)
        UserDefaults.standard.removeObject(forKey: workoutSetsDataKey)
        AppLogger.debug("🗑️ [WORKOUT] Cleared active workout storage", category: .data)
    }
    
    /// Force clear ALL workout state - use when stuck in bad state
    /// This is a nuclear option for debugging/recovery
    func forceResetWorkoutState() {
        AppLogger.debug("🔴 [WORKOUT] FORCE RESET - Clearing all workout state", category: .data)
        
        // Clear published state
        isWorkoutActive = false
        currentWorkout = nil
        currentExercises = []
        workoutStartTime = nil
        workoutInsights = nil
        currentProgramDayNumber = nil
        currentProgramDayFocus = nil
        currentSmartProgramId = nil
        currentProgramWeek = nil
        shouldNavigateToWorkoutTab = false
        shouldNavigateToHomeTab = false
        
        // Clear all sets data
        exerciseSetsData.removeAll()
        
        // Clear persisted state
        UserDefaults.standard.removeObject(forKey: activeWorkoutKey)
        UserDefaults.standard.removeObject(forKey: workoutSetsDataKey)
        
        // Force UI update
        objectWillChange.send()
        
        AppLogger.debug("✅ [WORKOUT] Force reset complete - all state cleared", category: .data)
    }
    
    /// Called when app enters background - save workout state
    func saveWorkoutStateOnBackground() {
        if isWorkoutActive {
            saveActiveWorkoutToStorage()
            AppLogger.debug("📱 [WORKOUT] Saved state before entering background", category: .data)
        }
    }
    
    /// Called when app returns to foreground - check for expired workout
    func checkWorkoutStateOnForeground() {
        guard isWorkoutActive, let startTime = workoutStartTime else {
            AppLogger.debug("📱 [WORKOUT] App foregrounded - no active workout", category: .data)
            return
        }
        
        let elapsedTime = Date().timeIntervalSince(startTime)
        let hoursElapsed = elapsedTime / 3600
        let minutesElapsed = Int(elapsedTime / 60)
        
        if elapsedTime > maxWorkoutDuration {
            AppLogger.debug("⏰ [WORKOUT] Workout has been active for \(String(format: "%.1f", hoursElapsed)) hours - exceeds 4 hour limit", category: .performance)
            
            // Auto-end the workout
            cancelWorkout()
            
            // Show alert to user
            NotificationCenter.default.post(
                name: NSNotification.Name("WorkoutAutoEnded"),
                object: nil,
                userInfo: ["reason": "Your workout was automatically ended after 4 hours. Tap FINISH next time to save your progress!"]
            )
        } else {
            AppLogger.debug("✅ [WORKOUT] App foregrounded - workout still active (\(minutesElapsed) min / \(String(format: "%.1f", hoursElapsed)) hrs)", category: .performance)
            
            // Re-save state to ensure it's fresh
            saveActiveWorkoutToStorage()
        }
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    // Counter for periodic saves (save every 15 seconds during workout for better persistence)
    private var saveCounter: Int = 0
    
    private func startTimer() {
        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] time in
                self?.currentTime = time
                
                self?.saveCounter += 1
                if self?.saveCounter ?? 0 >= 15 {
                    self?.saveCounter = 0
                    self?.saveActiveWorkoutToStorage()
                    #if DEBUG
                    AppLogger.debug("💾 [WORKOUT] Auto-saved (\(self?.exerciseSetsData.count ?? 0) exercises, periodic)", category: .data)
                    #endif
                }
            }
    }
    
    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }
    
    @MainActor func startWorkout(workout: Workout, exercises: [Exercise], insights: WorkoutInsights? = nil, programDay: Int? = nil, programDayFocus: String? = nil, smartProgramId: String? = nil, programWeek: Int? = nil) {
        #if DEBUG
        let totalStartTime = CFAbsoluteTimeGetCurrent()
        AppLogger.debug("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", category: .data)
        AppLogger.debug("🏋️ [PERF] startWorkout() BEGIN", category: .performance)
        AppLogger.debug("   Exercises: \(exercises.count)", category: .data)
        AppLogger.warning("   Thread: \(Thread.isMainThread ? "Main ✅" : "Background ⚠️")", category: .data)
        #endif
        
        // Ensure we're on the main thread for @Published property changes
        guard Thread.isMainThread else {
            #if DEBUG
            AppLogger.warning("⚠️ [PERF] Redirecting to main thread...", category: .performance)
            #endif
            DispatchQueue.main.async {
                self.startWorkout(workout: workout, exercises: exercises, insights: insights, programDay: programDay, programDayFocus: programDayFocus, smartProgramId: smartProgramId, programWeek: programWeek)
            }
            return
        }
        
        // Prevent double-start
        guard !isWorkoutActive else {
            #if DEBUG
            AppLogger.warning("⏭️ [PERF] Workout already active, skipping", category: .performance)
            #endif
            return
        }
        
        #if DEBUG
        var checkpoint = CFAbsoluteTimeGetCurrent()
        #endif
        
        // ⚡️ CRITICAL FIRST: Pre-fetch all Core Data properties IMMEDIATELY
        // This forces Core Data to materialize from disk NOW (not during SwiftUI render)
        // Result: Exercise names appear INSTANTLY when ActiveWorkoutView loads
        prefetchExerciseData(exercises)
        
        #if DEBUG
        AppLogger.debug("   Prefetch data: \(String(format: "%.2f", (CFAbsoluteTimeGetCurrent() - checkpoint) * 1000))ms", category: .performance)
        checkpoint = CFAbsoluteTimeGetCurrent()
        #endif
        
        // ⚡ CRITICAL: Initialize sets BEFORE setting state
        // This prevents SwiftUI from fighting with data changes during render
        initializeSetsForExercises(exercises)
        
        #if DEBUG
        AppLogger.debug("   Initialize sets: \(String(format: "%.2f", (CFAbsoluteTimeGetCurrent() - checkpoint) * 1000))ms", category: .data)
        checkpoint = CFAbsoluteTimeGetCurrent()
        #endif
        
        let exercisesForCache = exercises
        let userGoal = UserManager.shared.currentUser?.fitnessGoal ?? "Build Muscle"
        let userEquipment = UserManager.shared.currentUser?.getEquipment() ?? []
        Task.detached(priority: .utility) {
            await ExerciseSwapService.shared.precomputeSwapGraph(
                for: exercisesForCache,
                userGoal: userGoal,
                userEquipment: userEquipment
            )
        }
        
        #if DEBUG
        AppLogger.debug("   Swap graph: \(String(format: "%.2f", (CFAbsoluteTimeGetCurrent() - checkpoint) * 1000))ms", category: .data)
        checkpoint = CFAbsoluteTimeGetCurrent()
        #endif
        
        // ⚡️ INSTANT TRANSITION: Set ALL state synchronously in one batch
        // This ensures the ActiveWorkoutView has everything it needs IMMEDIATELY
        // No delays, no staggering - just instant activation
        currentWorkout = workout
        currentExercises = exercises
        workoutStartTime = Date()
        workoutInsights = insights
        currentProgramDayNumber = programDay
        currentProgramDayFocus = programDayFocus
        currentSmartProgramId = smartProgramId
        currentProgramWeek = programWeek
        
        // Clear navigation and switch tab
        shouldClearWorkoutTabNav = true
        shouldNavigateToWorkoutTab = true
        
        // ⚡️ INSTANT: Activate workout NOW - no delay!
        // The workout view will appear immediately with all data ready
        isWorkoutActive = true
        shouldClearWorkoutTabNav = false
        
        #if DEBUG
        AppLogger.debug("   State + Navigation: \(String(format: "%.2f", (CFAbsoluteTimeGetCurrent() - checkpoint) * 1000))ms", category: .data)
        let totalTime = (CFAbsoluteTimeGetCurrent() - totalStartTime) * 1000
        AppLogger.debug("🏋️ [PERF] startWorkout() COMPLETE in \(String(format: "%.2f", totalTime))ms", category: .performance)
        AppLogger.debug("🎯 [WORKOUT MANAGER] Workout ACTIVE - INSTANT!", category: .data)
        AppLogger.debug("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", category: .data)
        #endif
        
        // 📺 Prepare ads ASYNC after workout starts (non-blocking)
        Task.detached(priority: .background) {
            await MainActor.run {
                AdManager.shared.prepareForWorkout()
            }
        }
        
        // Record workout context ASYNC (non-blocking)
        Task {
            await recordWorkoutContext()
        }
        
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(0.3))
            guard !Task.isCancelled else { return }
            self?.saveActiveWorkoutToStorage()
        }
    }
    
    func finishWorkout() {
        #if DEBUG
        AppLogger.debug("🏁 WorkoutManager: Finishing current workout", category: .data)
        #endif
        
        // Calculate workout stats for program tracking
        let totalVolume = calculateTotalVolume()
        let actualDuration = calculateWorkoutDuration()
        
        // If this is a SmartProgram workout, complete the day
        if let smartProgramId = currentSmartProgramId, let dayNumber = currentProgramDayNumber {
            #if DEBUG
            AppLogger.debug("✅ Completing SmartProgram day: Program=\(smartProgramId), Day=\(dayNumber)", category: .workout)
            #endif
            SmartProgramEngine.shared.completeDay(
                programId: smartProgramId,
                dayNumber: dayNumber,
                actualDuration: actualDuration,
                totalVolume: totalVolume
            )
        }
        // If this is an old-style program workout, mark the day as complete
        else if let dayNumber = currentProgramDayNumber, activeProgram != nil {
            markProgramDayComplete(dayNumber)
            #if DEBUG
            AppLogger.debug("✅ Program Day \(dayNumber) marked as complete", category: .workout)
            #endif
        }
        
        // ═══════════════════════════════════════════════════════════════════════
        // UPDATE USER BEHAVIOR LEARNING ENGINE
        // This learns from the workout the user just completed to improve
        // future exercise recommendations (what they like, what equipment, etc.)
        // ═══════════════════════════════════════════════════════════════════════
        if let workout = currentWorkout {
            Task { @MainActor in
                let context = PersistenceController.shared.container.viewContext
                await UserBehaviorLearningEngine.shared.refreshAfterWorkout(workout, context: context)
                #if DEBUG
                AppLogger.debug("🧠 UserBehaviorLearningEngine: Updated preferences from completed workout", category: .data)
                #endif
            }
        }
        
        // ═══════════════════════════════════════════════════════════════════════
        // UPDATE COLLABORATIVE LEARNING ENGINE (Cross-User Intelligence)
        // This records the workout for global pattern analysis - learning what
        // exercises/combinations work well across similar users
        // ═══════════════════════════════════════════════════════════════════════
        if let workout = currentWorkout, let user = UserManager.shared.currentUser, let userId = user.id {
            Task { @MainActor in
                let userIdString = userId.uuidString
                
                // Build user profile snapshot
                let userProfile = UserProfileSnapshot(from: user)
                
                // Extract completed exercises
                var completedExercises: [CompletedExercise] = []
                if let workoutExercises = workout.exercises as? Set<WorkoutExercise> {
                    for workoutExercise in workoutExercises {
                        if let exercise = workoutExercise.exercise,
                           let name = exercise.name {
                            let sets = (workoutExercise.sets as? Set<WorkoutSet>) ?? []
                            let completedSets = sets.filter { $0.isCompleted }
                            let totalReps = completedSets.reduce(0) { $0 + Int($1.reps) }
                            let muscleGroups = (exercise.muscleGroups as? [String])?.first ?? "Unknown"
                            
                            completedExercises.append(CompletedExercise(
                                name: name,
                                equipment: exercise.equipment ?? "Bodyweight",
                                muscleGroup: muscleGroups,
                                setsCompleted: completedSets.count,
                                totalReps: totalReps
                            ))
                        }
                    }
                }
                
                // Determine workout type
                let workoutType: String
                if currentSmartProgramId != nil {
                    workoutType = "program"
                } else if workout.name?.contains("Auto") == true || workout.name?.contains("Quick") == true {
                    workoutType = "auto-gen"
                } else {
                    workoutType = "custom"
                }
                
                // Record to collaborative engine
                await CollaborativeLearningEngine.shared.recordWorkoutCompletion(
                    userId: userIdString,
                    userProfile: userProfile,
                    exercises: completedExercises,
                    workoutType: workoutType,
                    programId: currentSmartProgramId,
                    wasSuccessful: completedExercises.count >= 3  // Consider successful if 3+ exercises done
                )
                
                #if DEBUG
                AppLogger.debug("🌐 CollaborativeLearningEngine: Recorded \(completedExercises.count) exercises for global analysis", category: .data)
                #endif
            }
        }
        
        // ═══════════════════════════════════════════════════════════════════════
        // ADVANCED SESSION LOGGER: Full workout snapshot for AI analysis
        // ═══════════════════════════════════════════════════════════════════
        if AdvancedSessionLogger.isActive, let workout = currentWorkout, let user = UserManager.shared.currentUser {
            let userName = user.name ?? "unknown"
            let userGoal = user.fitnessGoal ?? "unknown"
            let userExp = user.experienceLevel ?? "unknown"
            let userWeight = user.weightLbs
            let userWorkouts = user.totalWorkouts
            let userStreak = user.currentStreak
            let userXP = user.xp
            let workoutName = workout.name ?? "Workout"
            let duration = actualDuration
            let volume = totalVolume
            
            var exerciseDetails: [[String: Any]] = []
            for (exerciseId, sets) in exerciseSetsData {
                let completedSets = sets.filter { $0.isCompleted }
                if !completedSets.isEmpty {
                    let name = currentExercises.first(where: { $0.id?.uuidString == exerciseId })?.name ?? "Unknown"
                    exerciseDetails.append([
                        "name": name,
                        "sets": completedSets.count,
                        "reps": completedSets.map { $0.reps }.reduce(0, +),
                        "weight": completedSets.first?.weight ?? 0,
                    ])
                }
            }
            let setsCount = exerciseDetails.reduce(0) { $0 + ($1["sets"] as? Int ?? 0) }
            let repsCount = exerciseDetails.reduce(0) { $0 + ($1["reps"] as? Int ?? 0) }
            
            Task { @MainActor in
                let limitations = LimitationsService.shared.userLimitations
                let limitSummary = limitations.map { "\($0.limitationType.rawValue): \($0.affectedArea.rawValue) (\($0.severity.rawValue))" }.joined(separator: ", ")
                
                let profile: [String: Any] = [
                    "name": userName, "goal": userGoal, "experience": userExp,
                    "weight_lbs": userWeight, "total_workouts": userWorkouts,
                    "current_streak": userStreak, "xp": userXP,
                    "injuries_limitations": limitSummary.isEmpty ? "none" : limitSummary,
                ]
                AdvancedSessionLogger.shared.logWorkoutCompleted(
                    userProfile: profile,
                    workoutName: workoutName,
                    durationMinutes: duration,
                    exercises: exerciseDetails,
                    totalSets: setsCount,
                    totalReps: repsCount,
                    totalVolume: volume,
                    caloriesBurned: 0,
                    personalRecords: []
                )
            }
        }
        
        // ═══════════════════════════════════════════════════════════════════════
        // QUICK WINS: Record performance history, context, and proficiency
        // ═══════════════════════════════════════════════════════════════════════
        if let workout = currentWorkout {
            // Save enhanced workout stats to Core Data first (synchronous)
            saveEnhancedWorkoutStats()
            
            // Then record performance data async (non-blocking)
            Task {
                await recordExercisePerformance()
                await updateEquipmentProficiency()
            }
        }
        
        // ═══════════════════════════════════════════════════════════════════════
        // NOTIFY COMPLETION - Cancel today's workout reminders
        // ═══════════════════════════════════════════════════════════════════════
        Task { @MainActor in
            NotificationManager.shared.workoutCompleted()
            
            // Sync workout completion to active challenges (lift/workout_streak)
            await ChallengeService.shared.syncFit33WorkoutToChallenge(workoutType: "strength")
        }
        
        isWorkoutActive = false
        currentWorkout = nil
        currentExercises = []
        workoutStartTime = nil
        workoutInsights = nil
        currentProgramDayNumber = nil
        currentProgramDayFocus = nil
        currentSmartProgramId = nil
        currentProgramWeek = nil
        shouldNavigateToWorkoutTab = false
        clearAllSetsData() // Clear persistent sets data
        
        // ⚡️ PERSISTENCE: Clear saved workout state
        clearActiveWorkoutStorage()
        
        #if DEBUG
        AppLogger.debug("✅ WorkoutManager: Workout finished successfully", category: .data)
        #endif
    }
    
    private func calculateTotalVolume() -> Double {
        var total = 0.0
        for (_, sets) in exerciseSetsData {
            for set in sets where set.isCompleted {
                total += Double(set.weight) * Double(set.reps)
            }
        }
        return total
    }
    
    private func calculateWorkoutDuration() -> Int {
        guard let startTime = workoutStartTime else { return 0 }
        return Int(Date().timeIntervalSince(startTime) / 60) // minutes
    }
    
    func cancelWorkout() {
        #if DEBUG
        AppLogger.error("❌ WorkoutManager: Cancelling current workout", category: .data)
        #endif
        
        isWorkoutActive = false
        currentWorkout = nil
        currentExercises = []
        workoutStartTime = nil
        workoutInsights = nil
        currentProgramDayNumber = nil
        currentProgramDayFocus = nil
        currentSmartProgramId = nil
        currentProgramWeek = nil
        shouldNavigateToWorkoutTab = false
        clearAllSetsData() // Clear persistent sets data
        
        // ⚡️ PERSISTENCE: Clear saved workout state
        clearActiveWorkoutStorage()
        
        #if DEBUG
        AppLogger.debug("✅ WorkoutManager: Workout cancelled successfully", category: .data)
        #endif
    }
    
    /// Replace an exercise in the current workout with a new one
    @MainActor func replaceExercise(_ oldExercise: Exercise, with newExercise: Exercise) {
        guard let index = currentExercises.firstIndex(where: { $0.id == oldExercise.id }) else {
            #if DEBUG
            AppLogger.error("⚠️ WorkoutManager: Could not find exercise to replace: \(oldExercise.name ?? "?")", category: .data)
            #endif
            return
        }
        
        #if DEBUG
        AppLogger.debug("🔄 WorkoutManager: Replacing '\(oldExercise.name ?? "?")' with '\(newExercise.name ?? "?")'", category: .data)
        #endif
        
        let oldExerciseId = oldExercise.id?.uuidString ?? ""
        let newExerciseId = newExercise.id?.uuidString ?? UUID().uuidString
        
        currentExercises[index] = newExercise
        
        // Preserve set structure: keep the same number of sets so completed
        // progress isn't lost. Transfer completed set count but clear the
        // exercise-specific weight/rep data since the new exercise may differ.
        let oldSets = exerciseSetsData[oldExerciseId] ?? []
        let preservedSetCount = max(oldSets.count, 3)
        
        var newSets: [WorkoutSetData] = []
        for i in 0..<preservedSetCount {
            let setData = WorkoutSetData()
            if i < oldSets.count && oldSets[i].isCompleted {
                setData.isCompleted = true
                setData.reps = oldSets[i].reps
                setData.weight = oldSets[i].weight
            }
            newSets.append(setData)
        }
        
        exerciseSetsData.removeValue(forKey: oldExerciseId)
        exerciseSetsData[newExerciseId] = newSets
        
        // Save updated state
        saveActiveWorkoutToStorage()
        
        // Trigger UI update
        objectWillChange.send()
        
        #if DEBUG
        AppLogger.debug("✅ WorkoutManager: Exercise replaced successfully", category: .data)
        #endif
    }
    
    func showWorkoutGenerator() {
        #if DEBUG
        AppLogger.debug("🧠 WorkoutManager: Navigating to workout generator", category: .data)
        #endif
        shouldNavigateToWorkoutTab = true
        shouldShowWorkoutGenerator = true
    }
    
    func navigateToHomeTab() {
        #if DEBUG
        AppLogger.debug("🏠 WorkoutManager: Navigating to home tab", category: .data)
        #endif
        // 🔧 Set synchronously to prevent race conditions with user actions
        shouldPopToRootHome = true
        shouldNavigateToHomeTab = true
    }
    
    var workoutDuration: TimeInterval {
        guard let startTime = workoutStartTime else { return 0 }
        return Date().timeIntervalSince(startTime)
    }
    
    var formattedDuration: String {
        let duration = workoutDuration
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    /// Resets all workout state for sign-out
    /// Called when user signs out to ensure clean state for next user
    func resetForSignOut() {
        AppLogger.debug("🔐 WorkoutManager: Resetting state for sign-out...", category: .auth)
        
        isWorkoutActive = false
        currentWorkout = nil
        currentExercises = []
        workoutStartTime = nil
        shouldNavigateToWorkoutTab = false
        shouldNavigateToHomeTab = false
        shouldNavigateToHomeTabInstant = false
        shouldPopToRootHome = false
        shouldDismissCardioFlow = false
        shouldShowWorkoutGenerator = false
        shouldClearWorkoutTabNav = false
        shouldNavigateToAutoGen = false
        autoGenCameFromHomeTab = false
        isTransitioningBackToHome = false
        workoutInsights = nil
        
        // Reset generator state
        generatorSelections = nil
        shouldTriggerWorkoutGeneration = false
        shouldStartPreviewWorkout = false
        isOnGeneratorScreen = false
        isOnWorkoutPreviewScreen = false
        
        // Reset custom workout builder state
        isOnCustomWorkoutBuilder = false
        selectedCustomWorkoutExercises = []
        shouldStartCustomWorkout = false
        
        // Reset program state
        activeProgram = nil
        programStartDate = nil
        programCompletedDays = []
        
        // Reset preview data
        previewProgram = nil
        previewDay = nil
        previewExercises = []
        currentProgramDayNumber = nil
        currentProgramDayFocus = nil
        
        // Clear exercise sets data
        exerciseSetsData = [:]
        
        AppLogger.debug("✅ WorkoutManager state reset", category: .data)
    }
    
    // MARK: - Quick Wins: Performance Tracking
    
    /// Record workout context (when workout started)
    private func recordWorkoutContext() async {
        guard let workout = currentWorkout,
              let userId = UserManager.shared.currentUser?.id,
              let workoutDate = workout.date else {
            return
        }
        
        let calendar = Calendar.current
        let dayOfWeek = calendar.component(.weekday, from: workoutDate)
        let dayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss"
        let timeString = timeFormatter.string(from: workoutDate)
        
        let dto: [String: AnyJSON] = [
            "user_id": .string(userId.uuidString),
            "workout_id": workout.id.map { .string($0.uuidString) } ?? .null,
            "workout_date": .string(ISO8601DateFormatter().string(from: workoutDate)),
            "workout_time": .string(timeString),
            "day_of_week": .string(dayNames[dayOfWeek - 1])
        ]
        
        do {
            try await SupabaseManager.shared.supabaseClient
                .from("workout_context")
                .insert(dto)
                .execute()
            #if DEBUG
            AppLogger.debug("✅ Recorded context: \(dayNames[dayOfWeek - 1]) at \(timeString)", category: .data)
            #endif
        } catch {
            AppLogger.error("❌ Error recording context: \(error)", category: .data)
        }
    }
    
    /// Record exercise performance history for progressive overload
    private func recordExercisePerformance() async {
        guard SupabaseManager.shared.isAuthenticated else {
            AppLogger.warning("[PERF HISTORY] Skipping — not authenticated", category: .auth)
            return
        }
        guard let workout = currentWorkout,
              let userId = UserManager.shared.currentUser?.id,
              let exercises = workout.exercises as? Set<WorkoutExercise> else {
            return
        }
        
        for workoutExercise in exercises {
            guard let exercise = workoutExercise.exercise,
                  let exerciseName = exercise.name,
                  let sets = workoutExercise.sets as? Set<WorkoutSet> else {
                continue
            }
            
            let completedSets = sets.filter { $0.isCompleted }.sorted { $0.setNumber < $1.setNumber }
            guard !completedSets.isEmpty else { continue }
            
            // Find best set
            guard let bestSet = completedSets.max(by: { 
                ($0.weight * Double($0.reps)) < ($1.weight * Double($1.reps)) 
            }) else { continue }
            
            // Calculate totals
            let totalVolume = completedSets.reduce(0.0) { $0 + ($1.weight * Double($1.reps)) }
            
            // Calculate 1RM using Epley formula
            let oneRM: Double
            if bestSet.reps == 1 {
                oneRM = bestSet.weight
            } else if bestSet.reps > 12 {
                oneRM = bestSet.weight * (1 + 0.033 * 12)
            } else {
                oneRM = bestSet.weight * (1 + 0.033 * Double(bestSet.reps))
            }
            
            // Save to Supabase
            let dto: [String: AnyJSON] = [
                "user_id": .string(userId.uuidString),
                "workout_id": workout.id.map { .string($0.uuidString) } ?? .null,
                "exercise_name": .string(exerciseName),
                "workout_date": .string(ISO8601DateFormatter().string(from: workout.date ?? Date())),
                "best_set_weight": .double(bestSet.weight),
                "best_set_reps": .integer(Int(bestSet.reps)),
                "total_sets": .integer(completedSets.count),
                "total_volume": .double(totalVolume),
                "one_rep_max_estimate": .double(oneRM),
                "equipment_used": .string(exercise.equipment ?? "Bodyweight")
            ]
            
            do {
                try await SupabaseManager.shared.supabaseClient
                    .from("exercise_performance_history")
                    .insert(dto)
                    .execute()
                #if DEBUG
                AppLogger.debug("✅ Recorded performance: \(exerciseName) - \(bestSet.weight)lbs x \(bestSet.reps) (1RM: \(String(format: "%.1f", oneRM))lbs)", category: .data)
                #endif
            } catch {
                AppLogger.error("❌ Error recording performance for \(exerciseName): \(error)", category: .data)
            }
        }
    }
    
    /// Update equipment proficiency based on workout
    private func updateEquipmentProficiency() async {
        guard let workout = currentWorkout,
              let userId = UserManager.shared.currentUser?.id,
              let exercises = workout.exercises as? Set<WorkoutExercise> else {
            return
        }
        
        // Collect all equipment used
        var equipmentUsed = Set<String>()
        for workoutExercise in exercises {
            if let equipment = workoutExercise.exercise?.equipment, !equipment.isEmpty {
                equipmentUsed.insert(equipment)
            }
        }
        
        // Update proficiency for each equipment type
        for equipment in equipmentUsed {
            do {
                try await SupabaseManager.shared.supabaseClient
                    .rpc("increment_equipment_usage", params: [
                        "p_user_id": userId.uuidString,
                        "p_equipment_type": equipment
                    ])
                    .execute()
                #if DEBUG
                AppLogger.debug("✅ Updated proficiency: \(equipment)", category: .data)
                #endif
            } catch {
                AppLogger.error("❌ Error updating proficiency for \(equipment): \(error)", category: .data)
            }
        }
    }
    
    /// Save enhanced workout stats to Core Data
    private func saveEnhancedWorkoutStats() {
        guard let workout = currentWorkout,
              let exercises = workout.exercises as? Set<WorkoutExercise> else {
            return
        }
        
        var totalVolume: Double = 0
        var totalReps: Int32 = 0
        var totalSets: Int16 = 0
        var completedExercises = 0
        
        for workoutExercise in exercises {
            if let sets = workoutExercise.sets as? Set<WorkoutSet> {
                let completed = sets.filter { $0.isCompleted }
                if !completed.isEmpty {
                    completedExercises += 1
                }
                totalSets += Int16(completed.count)
                totalReps += Int32(completed.reduce(0) { $0 + Int($1.reps) })
                totalVolume += completed.reduce(0.0) { $0 + ($1.weight * Double($1.reps)) }
            }
        }
        
        // Set workout type
        if currentSmartProgramId != nil {
            workout.workoutType = "program"
        } else if workout.name?.contains("Auto") == true || workout.name?.contains("Quick") == true {
            workout.workoutType = "auto-gen"
        } else {
            workout.workoutType = "custom"
        }
        
        // Save stats
        workout.totalVolume = totalVolume
        workout.totalReps = totalReps
        workout.totalSets = totalSets
        workout.completionPercentage = Double(completedExercises) / Double(max(exercises.count, 1))
        
        do {
            try PersistenceController.shared.container.viewContext.save()
            #if DEBUG
            AppLogger.debug("✅ Saved workout stats: \(String(format: "%.0f", totalVolume))lbs volume, \(totalReps) reps, \(totalSets) sets", category: .data)
            #endif
        } catch {
            AppLogger.error("❌ Error saving workout stats: \(error)", category: .data)
        }
    }
}
