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
    @Published var shouldShowWorkoutGenerator: Bool = false
    @Published var shouldNavigateToAutoGen: Bool = false  // 🔧 Redirect Home→Workout auto-gen flow
    @Published var shouldNavigateToPrograms: Bool = false  // 🔧 Redirect Home→Workout programs
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
    
    // Active program tracking (persisted to UserDefaults)
    @Published var activeProgram: WorkoutProgram? = nil {
        didSet {
            print("🔔 [PROGRAM] activeProgram changed: \(oldValue?.name ?? "nil") -> \(activeProgram?.name ?? "nil")")
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
    
    // Rest timer settings (adjusted based on workout duration)
    @Published var restTimeBetweenSets: Int = 60 // Default 60 seconds
    @Published var targetWorkoutDuration: Int = 45 // Default 45 minutes
    
    // Persistent storage for exercise sets data (survives view rebuilds during ads)
    // Key is exercise ID (String), value is array of WorkoutSetData
    // This is @Published so UI updates when sets are added/removed
    // The WorkoutSetData objects themselves have stable UUIDs and persist across view rebuilds
    @Published var exerciseSetsData: [String: [WorkoutSetData]] = [:]
    
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
    // UPDATED: Now creates 3 sets by default instead of 1
    func initializeSetsForExercise(id: String) {
        if exerciseSetsData[id] == nil || exerciseSetsData[id]?.isEmpty == true {
            // Create 3 empty sets ready to go
            let set1 = WorkoutSetData()
            let set2 = WorkoutSetData()
            let set3 = WorkoutSetData()
            exerciseSetsData[id] = [set1, set2, set3]
            #if DEBUG
            print("📦 Initialized 3 sets for exercise \(id.prefix(8))")
            #endif
        }
    }
    
    // Ensure all exercises have initialized sets (call on workout start)
    // OPTIMIZED: Batch all updates to trigger only ONE SwiftUI re-render
    // UPDATED: Now creates 3 sets by default instead of 1
    func initializeSetsForExercises(_ exercises: [Exercise]) {
        #if DEBUG
        let startTime = CFAbsoluteTimeGetCurrent()
        #endif
        
        // Build updates locally first (no @Published triggers)
        var updates: [String: [WorkoutSetData]] = [:]
        
        for exercise in exercises {
            if let exerciseId = exercise.id?.uuidString {
                if exerciseSetsData[exerciseId] == nil || exerciseSetsData[exerciseId]?.isEmpty == true {
                    // Create 3 empty sets ready to go
                    let set1 = WorkoutSetData()
                    let set2 = WorkoutSetData()
                    let set3 = WorkoutSetData()
                    updates[exerciseId] = [set1, set2, set3]
                    #if DEBUG
                    print("📦 Initialized 3 sets for exercise \(exerciseId.prefix(8))")
                    #endif
                }
            }
        }
        
        #if DEBUG
        let buildTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        print("📦 Built \(updates.count * 3) sets (3 per exercise) in \(String(format: "%.2f", buildTime))ms")
        let mergeStart = CFAbsoluteTimeGetCurrent()
        #endif
        
        // Apply all updates at once (single @Published trigger)
        if !updates.isEmpty {
            exerciseSetsData.merge(updates) { _, new in new }
        }
        
        #if DEBUG
        let mergeTime = (CFAbsoluteTimeGetCurrent() - mergeStart) * 1000
        print("📦 Merge completed in \(String(format: "%.2f", mergeTime))ms")
        print("📦 Initialized 3 sets for \(exercises.count) exercises (total: \(String(format: "%.2f", (CFAbsoluteTimeGetCurrent() - startTime) * 1000))ms)")
        #endif
    }
    
    // Update sets for an exercise (replaces entire array)
    func updateSetsForExercise(id: String, sets: [WorkoutSetData]) {
        exerciseSetsData[id] = sets
    }
    
    // Add a set to an exercise
    func addSetToExercise(id: String, set: WorkoutSetData) {
        if exerciseSetsData[id] != nil {
            exerciseSetsData[id]?.append(set)
        } else {
            exerciseSetsData[id] = [set]
        }
    }
    
    // Clear all sets data (when workout ends)
    func clearAllSetsData() {
        exerciseSetsData.removeAll()
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
        print("🎯 [PROGRAM] startProgram called for: \(program.name)")
        print("🎯 [PROGRAM] activeProgram BEFORE: \(activeProgram?.name ?? "nil")")
        activeProgram = program
        programStartDate = Date()
        programCompletedDays = []
        print("🎯 [PROGRAM] activeProgram AFTER: \(activeProgram?.name ?? "nil")")
        print("🎯 [PROGRAM] Started program: \(program.name)")
    }
    
    func startProgramWorkout(day: Int, context: NSManagedObjectContext) {
        guard let program = activeProgram,
              let programDay = program.schedule[day] else {
            print("❌ No program day found for day \(day)")
            return
        }
        
        print("🏋️ Starting program day \(day): \(programDay.name)")
        print("   Focus: \(programDay.focus.joined(separator: ", "))")
        
        // Generate fresh workout using intelligent generator with day's focus
        let (workout, exercises) = WorkoutProgramEngine.shared.generateWorkoutFromProgramDay(
            programDay,
            context: context
        )
        
        // Start the workout
        startWorkout(workout: workout, exercises: exercises, insights: nil)
        
        // Mark this day as started (could add completion tracking)
        print("✅ Started fresh workout for Day \(day) with \(exercises.count) exercises")
    }
    
    func startPreviewWorkout(context: NSManagedObjectContext) {
        guard let program = previewProgram,
              let day = previewDay,
              let programDay = program.schedule[day] else {
            print("❌ No preview workout data available")
            return
        }
        
        print("🚀 Starting workout from preview screen")
        
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
        
        print("   Starting with \(exercises.count) exercises")
        
        // Start the workout with program day info
        startWorkout(
            workout: workout,
            exercises: exercises,
            insights: nil,
            programDay: day,
            programDayFocus: programDay.name
        )
        
        print("✅ Preview workout started successfully")
    }
    
    func markProgramDayComplete(_ day: Int) {
        programCompletedDays.insert(day)
        print("✅ Marked program day \(day) complete. Total: \(programCompletedDays.count)")
    }
    
    func cancelProgram() {
        activeProgram = nil
        programStartDate = nil
        programCompletedDays = []
        clearProgramStorage()
        print("❌ Program cancelled")
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
    
    // Maximum time (in seconds) before auto-ending a workout (6 hours)
    private let maxWorkoutDuration: TimeInterval = 6 * 60 * 60
    
    private init() {
        // Load saved program on init
        loadActiveProgramFromStorage()
        
        // ⚡️ PERSISTENCE: Load any saved active workout
        loadActiveWorkoutFromStorage()
        
        // Start timer when workout becomes active
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
                print("💾 [PROGRAM] Saved active program: \(program.name)")
            }
        } else {
            UserDefaults.standard.removeObject(forKey: activeProgramKey)
            print("💾 [PROGRAM] Cleared active program from storage")
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
            print("📂 [PROGRAM] Loaded active program: \(program.name)")
        }
        
        // Load start date
        if let date = UserDefaults.standard.object(forKey: programStartDateKey) as? Date {
            self.programStartDate = date
            print("📂 [PROGRAM] Loaded start date: \(date)")
        }
        
        // Load completed days
        if let daysArray = UserDefaults.standard.array(forKey: programCompletedDaysKey) as? [Int] {
            self.programCompletedDays = Set(daysArray)
            print("📂 [PROGRAM] Loaded completed days: \(daysArray)")
        }
    }
    
    private func clearProgramStorage() {
        UserDefaults.standard.removeObject(forKey: activeProgramKey)
        UserDefaults.standard.removeObject(forKey: programStartDateKey)
        UserDefaults.standard.removeObject(forKey: programCompletedDaysKey)
        print("🗑️ [PROGRAM] Cleared all program storage")
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
        let isFailure: Bool
        let isDropset: Bool
        let restTime: TimeInterval
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
        
        let exerciseIds = currentExercises.compactMap { $0.id?.uuidString }
        
        let state = ActiveWorkoutState(
            workoutId: workoutId,
            exerciseIds: exerciseIds,
            startTime: workoutStartTime ?? Date(),
            programDayNumber: currentProgramDayNumber,
            programDayFocus: currentProgramDayFocus,
            smartProgramId: currentSmartProgramId
        )
        
        // Save workout state
        if let encoded = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(encoded, forKey: activeWorkoutKey)
            print("💾 [WORKOUT] Saved active workout state")
        }
        
        // Save sets data
        var persistedSets: [String: [PersistedSetData]] = [:]
        for (exerciseId, sets) in exerciseSetsData {
            persistedSets[exerciseId] = sets.map { set in
                PersistedSetData(
                    id: set.id.uuidString,
                    weight: set.weight,
                    reps: set.reps,
                    isCompleted: set.isCompleted,
                    isFailure: set.isFailure,
                    isDropset: set.isDropset,
                    restTime: set.restTime
                )
            }
        }
        
        if let setsEncoded = try? JSONEncoder().encode(persistedSets) {
            UserDefaults.standard.set(setsEncoded, forKey: workoutSetsDataKey)
            print("💾 [WORKOUT] Saved \(exerciseSetsData.count) exercise sets")
        }
    }
    
    /// Load active workout state from UserDefaults (call on app launch)
    private func loadActiveWorkoutFromStorage() {
        guard let data = UserDefaults.standard.data(forKey: activeWorkoutKey),
              let state = try? JSONDecoder().decode(ActiveWorkoutState.self, from: data) else {
            print("📂 [WORKOUT] No saved active workout found")
            return
        }
        
        // Check if workout is too old (auto-timeout after 6 hours)
        let elapsedTime = Date().timeIntervalSince(state.startTime)
        if elapsedTime > maxWorkoutDuration {
            print("⏰ [WORKOUT] Active workout expired (\(Int(elapsedTime / 3600)) hours old) - auto-ending")
            clearActiveWorkoutStorage()
            return
        }
        
        print("📂 [WORKOUT] Found saved active workout (started \(Int(elapsedTime / 60)) minutes ago)")
        
        // Fetch the workout and exercises from Core Data
        let context = PersistenceController.shared.container.viewContext
        
        // Fetch workout
        let workoutFetch: NSFetchRequest<Workout> = Workout.fetchRequest()
        workoutFetch.predicate = NSPredicate(format: "id == %@", state.workoutId)
        workoutFetch.fetchLimit = 1
        
        guard let workout = try? context.fetch(workoutFetch).first else {
            print("⚠️ [WORKOUT] Could not find saved workout in Core Data - clearing")
            clearActiveWorkoutStorage()
            return
        }
        
        // Fetch exercises
        let exerciseFetch: NSFetchRequest<Exercise> = Exercise.fetchRequest()
        exerciseFetch.predicate = NSPredicate(format: "id IN %@", state.exerciseIds.compactMap { UUID(uuidString: $0) })
        
        guard let exercises = try? context.fetch(exerciseFetch), !exercises.isEmpty else {
            print("⚠️ [WORKOUT] Could not find saved exercises in Core Data - clearing")
            clearActiveWorkoutStorage()
            return
        }
        
        // Sort exercises to match original order
        let orderedExercises = state.exerciseIds.compactMap { id -> Exercise? in
            exercises.first { $0.id?.uuidString == id }
        }
        
        // Load sets data
        if let setsData = UserDefaults.standard.data(forKey: workoutSetsDataKey),
           let persistedSets = try? JSONDecoder().decode([String: [PersistedSetData]].self, from: setsData) {
            
            for (exerciseId, sets) in persistedSets {
                exerciseSetsData[exerciseId] = sets.map { persisted in
                    let setData = WorkoutSetData()
                    setData.weight = persisted.weight
                    setData.reps = persisted.reps
                    setData.isCompleted = persisted.isCompleted
                    setData.isFailure = persisted.isFailure
                    setData.isDropset = persisted.isDropset
                    setData.restTime = persisted.restTime
                    return setData
                }
            }
            print("📂 [WORKOUT] Restored \(persistedSets.count) exercise sets")
        }
        
        // Restore workout state
        currentWorkout = workout
        currentExercises = orderedExercises
        workoutStartTime = state.startTime
        currentProgramDayNumber = state.programDayNumber
        currentProgramDayFocus = state.programDayFocus
        currentSmartProgramId = state.smartProgramId
        isWorkoutActive = true
        
        print("✅ [WORKOUT] Restored active workout with \(orderedExercises.count) exercises")
        
        // Navigate to workout tab
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.shouldNavigateToWorkoutTab = true
        }
    }
    
    /// Clear active workout storage (call when workout finishes/cancels)
    private func clearActiveWorkoutStorage() {
        UserDefaults.standard.removeObject(forKey: activeWorkoutKey)
        UserDefaults.standard.removeObject(forKey: workoutSetsDataKey)
        print("🗑️ [WORKOUT] Cleared active workout storage")
    }
    
    /// Called when app enters background - save workout state
    func saveWorkoutStateOnBackground() {
        if isWorkoutActive {
            saveActiveWorkoutToStorage()
            print("📱 [WORKOUT] Saved state before entering background")
        }
    }
    
    /// Called when app returns to foreground - check for expired workout
    func checkWorkoutStateOnForeground() {
        guard isWorkoutActive, let startTime = workoutStartTime else { return }
        
        let elapsedTime = Date().timeIntervalSince(startTime)
        if elapsedTime > maxWorkoutDuration {
            print("⏰ [WORKOUT] Workout has been active for \(Int(elapsedTime / 3600)) hours - auto-ending")
            
            // Auto-end the workout
            cancelWorkout()
            
            // Show alert to user
            NotificationCenter.default.post(
                name: NSNotification.Name("WorkoutAutoEnded"),
                object: nil,
                userInfo: ["reason": "Your workout was automatically ended after 6 hours of inactivity."]
            )
        } else {
            print("✅ [WORKOUT] Workout still valid (\(Int(elapsedTime / 60)) minutes elapsed)")
        }
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    // Counter for periodic saves (save every 30 seconds during workout)
    private var saveCounter: Int = 0
    
    private func startTimer() {
        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] time in
                self?.currentTime = time
                
                // ⚡️ PERSISTENCE: Auto-save workout state every 30 seconds
                self?.saveCounter += 1
                if self?.saveCounter ?? 0 >= 30 {
                    self?.saveCounter = 0
                    self?.saveActiveWorkoutToStorage()
                }
            }
    }
    
    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }
    
    func startWorkout(workout: Workout, exercises: [Exercise], insights: WorkoutInsights? = nil, programDay: Int? = nil, programDayFocus: String? = nil, smartProgramId: String? = nil) {
        #if DEBUG
        let totalStartTime = CFAbsoluteTimeGetCurrent()
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🏋️ [PERF] startWorkout() BEGIN")
        print("   Exercises: \(exercises.count)")
        print("   Thread: \(Thread.isMainThread ? "Main ✅" : "Background ⚠️")")
        #endif
        
        // 📺 Prepare ads for workout (initializes SDK + preloads ad)
        AdManager.shared.prepareForWorkout()
        
        // Ensure we're on the main thread for @Published property changes
        guard Thread.isMainThread else {
            #if DEBUG
            print("⚠️ [PERF] Redirecting to main thread...")
            #endif
            DispatchQueue.main.async {
                self.startWorkout(workout: workout, exercises: exercises, insights: insights, programDay: programDay, programDayFocus: programDayFocus, smartProgramId: smartProgramId)
            }
            return
        }
        
        // Prevent double-start
        guard !isWorkoutActive else {
            #if DEBUG
            print("⏭️ [PERF] Workout already active, skipping")
            #endif
            return
        }
        
        #if DEBUG
        var checkpoint = CFAbsoluteTimeGetCurrent()
        #endif
        
        // Set workout state
        currentWorkout = workout
        currentExercises = exercises
        workoutStartTime = Date()
        workoutInsights = insights
        currentProgramDayNumber = programDay
        currentProgramDayFocus = programDayFocus
        currentSmartProgramId = smartProgramId
        
        // Record workout context (temporal data)
        Task {
            await recordWorkoutContext()
        }
        
        #if DEBUG
        print("   State assignment: \(String(format: "%.2f", (CFAbsoluteTimeGetCurrent() - checkpoint) * 1000))ms")
        checkpoint = CFAbsoluteTimeGetCurrent()
        #endif
        
        // ⚡ CRITICAL: Initialize sets BEFORE triggering navigation
        // This prevents SwiftUI from fighting with data changes during render
        initializeSetsForExercises(exercises)
        
        #if DEBUG
        print("   Initialize sets: \(String(format: "%.2f", (CFAbsoluteTimeGetCurrent() - checkpoint) * 1000))ms")
        checkpoint = CFAbsoluteTimeGetCurrent()
        #endif
        
        // NOW set navigation flags (data is ready)
        // Stagger state changes to prevent AttributeGraph cycles
        
        print("🎯 [WORKOUT MANAGER] Starting workout transition...")
        
        // Step 1: Clear navigation path (shows gradient overlay)
        shouldClearWorkoutTabNav = true
        
        // Step 2: Switch tab
        shouldNavigateToWorkoutTab = true
        
        // Step 3: After 100ms, activate workout (gradient hides the transition)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [self] in
            isWorkoutActive = true
            shouldClearWorkoutTabNav = false
            print("🎯 [WORKOUT MANAGER] Workout ACTIVE")
        }
        
        #if DEBUG
        print("   Navigation flags: \(String(format: "%.2f", (CFAbsoluteTimeGetCurrent() - checkpoint) * 1000))ms")
        let totalTime = (CFAbsoluteTimeGetCurrent() - totalStartTime) * 1000
        print("🏋️ [PERF] startWorkout() COMPLETE in \(String(format: "%.2f", totalTime))ms")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        #endif
        
        // DO NOT prepare ads here - AdMob WebView processes block UI for 4-6 seconds
        // Ads will be prepared lazily when shouldShowAd() is first called
        
        // ⚡️ PERSISTENCE: Save workout state so it survives app close
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.saveActiveWorkoutToStorage()
        }
    }
    
    func finishWorkout() {
        #if DEBUG
        print("🏁 WorkoutManager: Finishing current workout")
        #endif
        
        // Calculate workout stats for program tracking
        let totalVolume = calculateTotalVolume()
        let actualDuration = calculateWorkoutDuration()
        
        // If this is a SmartProgram workout, complete the day
        if let smartProgramId = currentSmartProgramId, let dayNumber = currentProgramDayNumber {
            #if DEBUG
            print("✅ Completing SmartProgram day: Program=\(smartProgramId), Day=\(dayNumber)")
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
            print("✅ Program Day \(dayNumber) marked as complete")
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
                print("🧠 UserBehaviorLearningEngine: Updated preferences from completed workout")
                #endif
            }
        }
        
        // ═══════════════════════════════════════════════════════════════════════
        // UPDATE COLLABORATIVE LEARNING ENGINE (Cross-User Intelligence)
        // This records the workout for global pattern analysis - learning what
        // exercises/combinations work well across similar users
        // ═══════════════════════════════════════════════════════════════════════
        if let workout = currentWorkout, let user = UserManager.shared.currentUser {
            Task { @MainActor in
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
                    userId: user.id?.uuidString ?? "",
                    userProfile: userProfile,
                    exercises: completedExercises,
                    workoutType: workoutType,
                    programId: currentSmartProgramId,
                    wasSuccessful: completedExercises.count >= 3  // Consider successful if 3+ exercises done
                )
                
                #if DEBUG
                print("🌐 CollaborativeLearningEngine: Recorded \(completedExercises.count) exercises for global analysis")
                #endif
            }
        }
        
        // ═══════════════════════════════════════════════════════════════════════
        // QUICK WINS: Record performance history, context, and proficiency
        // ═══════════════════════════════════════════════════════════════════
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
        }
        
        isWorkoutActive = false
        currentWorkout = nil
        currentExercises = []
        workoutStartTime = nil
        workoutInsights = nil
        currentProgramDayNumber = nil
        currentProgramDayFocus = nil
        currentSmartProgramId = nil
        shouldNavigateToWorkoutTab = false
        clearAllSetsData() // Clear persistent sets data
        
        // ⚡️ PERSISTENCE: Clear saved workout state
        clearActiveWorkoutStorage()
        
        #if DEBUG
        print("✅ WorkoutManager: Workout finished successfully")
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
        print("❌ WorkoutManager: Cancelling current workout")
        #endif
        
        isWorkoutActive = false
        currentWorkout = nil
        currentExercises = []
        workoutStartTime = nil
        workoutInsights = nil
        currentProgramDayNumber = nil
        currentProgramDayFocus = nil
        currentSmartProgramId = nil
        shouldNavigateToWorkoutTab = false
        clearAllSetsData() // Clear persistent sets data
        
        // ⚡️ PERSISTENCE: Clear saved workout state
        clearActiveWorkoutStorage()
        
        #if DEBUG
        print("✅ WorkoutManager: Workout cancelled successfully")
        #endif
    }
    
    /// Replace an exercise in the current workout with a new one
    func replaceExercise(_ oldExercise: Exercise, with newExercise: Exercise) {
        guard let index = currentExercises.firstIndex(where: { $0.id == oldExercise.id }) else {
            #if DEBUG
            print("⚠️ WorkoutManager: Could not find exercise to replace: \(oldExercise.name ?? "?")")
            #endif
            return
        }
        
        #if DEBUG
        print("🔄 WorkoutManager: Replacing '\(oldExercise.name ?? "?")' with '\(newExercise.name ?? "?")'")
        #endif
        
        // Get the old exercise ID for sets data
        let oldExerciseId = oldExercise.id?.uuidString ?? ""
        let newExerciseId = newExercise.id?.uuidString ?? UUID().uuidString
        
        // Replace the exercise in the array
        currentExercises[index] = newExercise
        
        // Transfer sets data from old exercise to new one
        if let existingSets = exerciseSetsData[oldExerciseId] {
            // Copy the sets to the new exercise (preserving any progress)
            exerciseSetsData[newExerciseId] = existingSets
            // Remove old exercise sets
            exerciseSetsData.removeValue(forKey: oldExerciseId)
        } else {
            // Initialize with default 3 sets if no existing data
            initializeSetsForExercise(id: newExerciseId)
        }
        
        // Save updated state
        saveActiveWorkoutToStorage()
        
        // Trigger UI update
        objectWillChange.send()
        
        #if DEBUG
        print("✅ WorkoutManager: Exercise replaced successfully")
        #endif
    }
    
    func showWorkoutGenerator() {
        #if DEBUG
        print("🧠 WorkoutManager: Navigating to workout generator")
        #endif
        shouldNavigateToWorkoutTab = true
        shouldShowWorkoutGenerator = true
    }
    
    func navigateToHomeTab() {
        #if DEBUG
        print("🏠 WorkoutManager: Navigating to home tab")
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
        print("🔐 WorkoutManager: Resetting state for sign-out...")
        
        isWorkoutActive = false
        currentWorkout = nil
        currentExercises = []
        workoutStartTime = nil
        shouldNavigateToWorkoutTab = false
        shouldNavigateToHomeTab = false
        shouldNavigateToHomeTabInstant = false
        shouldPopToRootHome = false
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
        
        print("✅ WorkoutManager state reset")
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
            print("✅ Recorded context: \(dayNames[dayOfWeek - 1]) at \(timeString)")
            #endif
        } catch {
            print("❌ Error recording context: \(error)")
        }
    }
    
    /// Record exercise performance history for progressive overload
    private func recordExercisePerformance() async {
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
                print("✅ Recorded performance: \(exerciseName) - \(bestSet.weight)lbs x \(bestSet.reps) (1RM: \(String(format: "%.1f", oneRM))lbs)")
                #endif
            } catch {
                print("❌ Error recording performance for \(exerciseName): \(error)")
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
                print("✅ Updated proficiency: \(equipment)")
                #endif
            } catch {
                print("❌ Error updating proficiency for \(equipment): \(error)")
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
            print("✅ Saved workout stats: \(String(format: "%.0f", totalVolume))lbs volume, \(totalReps) reps, \(totalSets) sets")
            #endif
        } catch {
            print("❌ Error saving workout stats: \(error)")
        }
    }
}
