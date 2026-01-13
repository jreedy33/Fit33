import Foundation
import CoreData

struct ExerciseData {
    let name: String
    let category: String
    let muscleGroups: [String]
    let equipment: String
    let instructions: String
    let primaryBodyRegion: String
    let primaryMuscle: String
    let secondaryMuscles: [String]
    let sources: [String]
    var videoFilename: String? = nil  // For direct video lookup
}

class ExerciseLibraryService: ObservableObject {
    static let shared = ExerciseLibraryService()
    
    private let viewContext = PersistenceController.shared.container.viewContext
    
    private let defaultExercises: [ExerciseData] = ComprehensiveExerciseDatabase.exercises
    
    // MARK: - Loading State (for UI to know when exercises are ready)
    @Published var isExercisesReady: Bool = false
    
    // MARK: - Caching
    private var cachedExercises: [Exercise]?
    private var cachedExercisesByName: [String: Exercise]? // For O(1) name lookups
    private var cacheTimestamp: Date?
    
    // MARK: - Sync Protection
    private var isSyncing = false
    private let syncLock = NSLock()
    private let cacheValidityDuration: TimeInterval = 300 // 5 minutes
    private var isPreWarming = false
    
    private init() {
        // Pre-warm cache at startup for instant workout starts
        preWarmCache()
    }
    
    /// Pre-warm the exercise cache in background
    /// Call this early (e.g., at app startup) so lookups are instant later
    func preWarmCache() {
        guard !isPreWarming && cachedExercisesByName == nil else { return }
        isPreWarming = true
        
        // Run on main thread (Core Data requirement) but async so it doesn't block
        DispatchQueue.main.async { [weak self] in
            let startTime = CFAbsoluteTimeGetCurrent()
            let exercises = self?.getAllExercises() ?? []
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            print("🔥 [ExerciseLibrary] Cache pre-warmed: \(elapsed)ms")
            self?.isPreWarming = false
            
            // Mark as ready if we have valid exercises (with names)
            let validCount = exercises.filter { $0.name != nil && !$0.name!.isEmpty }.count
            if validCount > 100 {
                self?.isExercisesReady = true
                print("✅ [ExerciseLibrary] Exercises ready: \(validCount) valid exercises")
            } else {
                print("⚠️ [ExerciseLibrary] Only \(validCount) valid exercises - waiting for sync")
            }
        }
    }
    
    /// Get exercise by name - O(1) lookup using cached dictionary (case-insensitive)
    func getExercise(byName name: String) -> Exercise? {
        // Build cache if needed (with lowercase keys for case-insensitive matching)
        if cachedExercisesByName == nil || !isCacheValid {
            #if DEBUG
            print("📦 [ExerciseLibrary] Cache miss for '\(name)' - rebuilding...")
            #endif
            let allExercises = getAllExercises()
            cachedExercisesByName = Dictionary(
                allExercises.compactMap { exercise -> (String, Exercise)? in
                    guard let name = exercise.name, !exercise.isDeleted else { return nil }
                    return (name.lowercased(), exercise)
                },
                uniquingKeysWith: { first, _ in first }
            )
        }
        let result = cachedExercisesByName?[name.lowercased()]
        #if DEBUG
        if result == nil {
            print("⚠️ [ExerciseLibrary] Exercise not found: '\(name)' (cache size: \(cachedExercisesByName?.count ?? 0))")
        }
        #endif
        return result
    }
    
    /// Get multiple exercises by name - O(n) where n is names count
    func getExercises(byNames names: [String]) -> [Exercise] {
        return names.compactMap { getExercise(byName: $0) }
    }
    
    /// Invalidate the exercise cache (call after sync or modifications)
    func invalidateCache() {
        cachedExercises = nil
        cachedExercisesByName = nil
        cacheTimestamp = nil
        #if DEBUG
        print("📦 Exercise cache invalidated")
        #endif
        
        // Refresh the context to ensure it sees all changes after batch operations
        viewContext.refreshAllObjects()
        
        // SYNCHRONOUSLY rebuild the cache so it's immediately available
        // (Don't use preWarmCache which runs async)
        let startTime = CFAbsoluteTimeGetCurrent()
        _ = getAllExercises()
        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        #if DEBUG
        print("🔥 [ExerciseLibrary] Cache rebuilt synchronously: \(elapsed)ms, \(cachedExercises?.count ?? 0) exercises")
        #endif
        
        // ⚡️ Repair nil exercise relationships in workouts
        repairNilExerciseRelationships()
    }
    
    /// Repairs WorkoutExercise objects that have nil exercise relationships
    /// This happens when workouts sync before exercises are available
    private func repairNilExerciseRelationships() {
        guard isExercisesReady else { return }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let context = PersistenceController.shared.container.viewContext
            
            // Find WorkoutExercises with nil exercise relationship
            let fetchRequest: NSFetchRequest<WorkoutExercise> = WorkoutExercise.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "exercise == nil")
            
            do {
                let orphanedExercises = try context.fetch(fetchRequest)
                
                if orphanedExercises.isEmpty { return }
                
                #if DEBUG
                print("🔧 [ExerciseLibrary] Found \(orphanedExercises.count) WorkoutExercises with nil relationships")
                #endif
                
                var repaired = 0
                
                for workoutExercise in orphanedExercises {
                    // Try to get the cached name
                    guard let id = workoutExercise.id?.uuidString,
                          let cachedName = ExerciseNameCache.shared.getName(forWorkoutExerciseId: id) else {
                        continue
                    }
                    
                    // Try to find the exercise by name
                    if let exercise = self.getExercise(byName: cachedName) {
                        workoutExercise.exercise = exercise
                        repaired += 1
                    }
                }
                
                if repaired > 0 {
                    try context.save()
                    #if DEBUG
                    print("✅ [ExerciseLibrary] Repaired \(repaired) exercise relationships")
                    #endif
                }
            } catch {
                #if DEBUG
                print("❌ [ExerciseLibrary] Error repairing relationships: \(error)")
                #endif
            }
        }
    }
    
    private var isCacheValid: Bool {
        guard let timestamp = cacheTimestamp else { return false }
        return Date().timeIntervalSince(timestamp) < cacheValidityDuration
    }
    
    /// Sync exercises from pre-fetched cloud data (for audit tool)
    func syncExercisesFromCloud(_ cloudExercises: [ExerciseDTO]) async {
        // 🛡️ CRITICAL: Never sync exercises during an active workout!
        if WorkoutManager.shared.isWorkoutActive {
            print("⚠️ [SYNC] Skipping exercise sync - workout is active")
            return
        }
        
        // 🔒 Prevent concurrent syncs
        syncLock.lock()
        if isSyncing {
            syncLock.unlock()
            print("⚠️ [SYNC] Skipping - sync already in progress")
            return
        }
        isSyncing = true
        syncLock.unlock()
        
        defer {
            syncLock.lock()
            isSyncing = false
            syncLock.unlock()
        }
        
        print("🔄 Syncing \(cloudExercises.count) exercises from audit to local database...")
        await performSync(with: cloudExercises)
    }
    
    /// Force sync exercises - clears old data and pulls fresh from cloud
    func forceSyncExercises() async {
        print("🔄 FORCE SYNC: Clearing old exercise data...")
        await MainActor.run {
            let viewContext = PersistenceController.shared.container.viewContext
            let fetchRequest: NSFetchRequest<NSFetchRequestResult> = Exercise.fetchRequest()
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
            
            do {
                try viewContext.execute(deleteRequest)
                try viewContext.save()
                invalidateCache()
                print("✅ Cleared existing exercises from Core Data")
            } catch {
                print("❌ Error clearing exercises: \(error)")
            }
        }
        
        // Now sync fresh data
        await syncExercisesFromCloud()
        
        // Mark as synced with latest data
        UserDefaults.standard.set(Date(), forKey: "lastExerciseDataUpdate")
        print("✅ FORCE SYNC complete - fresh data loaded!")
    }
    
    func syncExercisesFromCloud() async {
        // 🛡️ CRITICAL: Never sync exercises during an active workout!
        // This would delete the exercise objects the workout is referencing,
        // causing exercise cards to show "Exercise" and lose all data.
        if WorkoutManager.shared.isWorkoutActive {
            print("⚠️ [SYNC] Skipping exercise sync - workout is active")
            return
        }
        
        // 🔒 Prevent concurrent syncs (causes duplicate entries)
        syncLock.lock()
        if isSyncing {
            syncLock.unlock()
            print("⚠️ [SYNC] Skipping - sync already in progress")
            return
        }
        isSyncing = true
        syncLock.unlock()
        
        defer {
            syncLock.lock()
            isSyncing = false
            syncLock.unlock()
        }
        
        // Fetch exercises from Supabase and sync to Core Data
        print("🔄 Starting exercise sync from cloud...")
        do {
            let cloudExercises = try await SupabaseManager.shared.fetchAllExercises()
            print("✅ Fetched \(cloudExercises.count) exercises from cloud")
            await performSync(with: cloudExercises)
        } catch {
            print("❌ Failed to fetch exercises from cloud: \(error)")
        }
    }
    
    private func performSync(with cloudExercises: [ExerciseDTO]) async {
        print("✅ Processing \(cloudExercises.count) exercises for sync")
        
        // ⚠️ Mark exercises as not ready during sync (UI will show loading)
        await MainActor.run {
            isExercisesReady = false
        }
        
        await MainActor.run {
            ExerciseIntelligenceService.shared.resetProfiles()
        }
        var intelligenceProfiles: [ExerciseIntelligenceProfile] = []
        
        // Use batch delete for safety and performance
        await MainActor.run {
            let fetchRequest: NSFetchRequest<NSFetchRequestResult> = Exercise.fetchRequest()
            let batchDeleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
            batchDeleteRequest.resultType = .resultTypeObjectIDs
            
            do {
                // Execute batch delete
                let result = try viewContext.execute(batchDeleteRequest) as? NSBatchDeleteResult
                let objectIDArray = result?.result as? [NSManagedObjectID]
                let changes = [NSDeletedObjectsKey: objectIDArray ?? []]
                NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [viewContext])
                print("🗑️ Cleared existing exercises from Core Data")
            } catch {
                print("⚠️ Error clearing exercises: \(error)")
            }
        }
        
        // Add cloud exercises to Core Data (deduplicate by name)
        // The database may have multiple entries per exercise (one per gender for videos)
        // We only need one exercise entry - video service handles gender-specific videos
        var syncedCount = 0
        var seenExerciseNames = Set<String>()
        
        await MainActor.run {
            for cloudExercise in cloudExercises {
                // Skip exercises with empty names
                guard !cloudExercise.name.isEmpty else {
                    continue
                }
                
                // Deduplicate by exercise name (case-insensitive)
                let normalizedName = cloudExercise.name.lowercased().trimmingCharacters(in: .whitespaces)
                guard !seenExerciseNames.contains(normalizedName) else {
                    continue // Skip duplicate
                }
                seenExerciseNames.insert(normalizedName)
                
                let exercise = Exercise(context: viewContext)
                // Generate new UUID for Core Data (cloud uses different ID system)
                exercise.id = UUID()
                exercise.name = cloudExercise.name
                exercise.category = cloudExercise.category.isEmpty ? "General" : cloudExercise.category
                
                // Parse comma-separated muscles string into array (new schema uses String, not [String])
                let muscleArray = cloudExercise.primaryMusclesArray
                let muscleGroups = muscleArray.isEmpty ? ["General"] : muscleArray
                exercise.muscleGroups = muscleGroups as NSObject
                
                // Also sync secondary muscles for workout generation filtering
                let secondaryArray = cloudExercise.secondaryMusclesArray
                exercise.secondaryMuscles = secondaryArray as NSObject
                
                exercise.equipment = cloudExercise.equipment?.isEmpty == false ? cloudExercise.equipment! : "Bodyweight"
                exercise.instructions = cloudExercise.instructions ?? "No instructions available"
                exercise.exerciseDescription = cloudExercise.description
                exercise.stepsToPerform = cloudExercise.stepsToPerform
                exercise.workoutType = cloudExercise.workoutType  // Strength, Cardio, Stretch, Plyometrics
                exercise.isFavorite = false
                
                // Enhanced metadata fields
                exercise.movementPattern = cloudExercise.movementPattern
                exercise.forceType = cloudExercise.forceType
                exercise.movementType = cloudExercise.movementType
                exercise.laterality = cloudExercise.laterality
                exercise.planeOfMotion = cloudExercise.planeOfMotion
                exercise.difficultyLevel = Int16(cloudExercise.difficultyLevel ?? 0)
                exercise.complexityScore = Int16(cloudExercise.complexityScore ?? 0)
                exercise.strengthRating = Int16(cloudExercise.strengthRating ?? 0)
                exercise.hypertrophyRating = Int16(cloudExercise.hypertrophyRating ?? 0)
                exercise.powerRating = Int16(cloudExercise.powerRating ?? 0)
                exercise.enduranceRating = Int16(cloudExercise.enduranceRating ?? 0)
                exercise.bodyPosition = cloudExercise.bodyPosition
                exercise.benchAngle = cloudExercise.benchAngle
                exercise.gripType = cloudExercise.gripType
                exercise.gripWidth = cloudExercise.gripWidth
                exercise.optimalRepRangeMin = Int16(cloudExercise.optimalRepRangeMin ?? 0)
                exercise.optimalRepRangeMax = Int16(cloudExercise.optimalRepRangeMax ?? 0)
                exercise.placementInWorkout = cloudExercise.placementInWorkout
                exercise.fatigability = Int16(cloudExercise.fatigability ?? 0)
                exercise.popularityScore = Int16(cloudExercise.popularityScore ?? 0)
                exercise.homeGymFriendly = cloudExercise.homeGymFriendly ?? false
                exercise.practicalityScore = Int16(cloudExercise.practicalityScore ?? 50)  // Default 50 if not set
                
                // Goal-based classification fields (4 key columns)
                exercise.fatLossRating = Int16(cloudExercise.fatLossRating ?? 5)
                exercise.generalFitnessRating = Int16(cloudExercise.generalFitnessRating ?? 5)
                exercise.isCompound = cloudExercise.isCompound ?? false
                exercise.supersetable = cloudExercise.supersetable ?? true
                
                // Exercise family & swap system fields
                exercise.setValue(cloudExercise.exerciseFamily, forKey: "exerciseFamily")
                exercise.setValue(cloudExercise.baseExerciseName, forKey: "baseExerciseName")
                exercise.setValue(cloudExercise.complementaryFamilies, forKey: "complementaryFamilies")
                exercise.setValue(cloudExercise.isEquipmentPrimary ?? false, forKey: "isEquipmentPrimary")
                exercise.setValue(cloudExercise.equipmentCategory, forKey: "equipmentCategory")
                exercise.setValue(cloudExercise.durationBased ?? false, forKey: "durationBased")
                exercise.setValue(Int16(cloudExercise.recommendedSets ?? 3), forKey: "recommendedSets")
                exercise.setValue(Int16(cloudExercise.restSeconds ?? 60), forKey: "restSeconds")
                exercise.setValue(Int16(cloudExercise.musclesWorkedCount ?? 2), forKey: "musclesWorkedCount")
                exercise.setValue(Int16(cloudExercise.priorityBuildMuscle ?? 70), forKey: "priorityBuildMuscle")
                exercise.setValue(Int16(cloudExercise.priorityGetLean ?? 70), forKey: "priorityGetLean")
                exercise.setValue(Int16(cloudExercise.priorityHome ?? 50), forKey: "priorityHome")
                exercise.setValue(Int16(cloudExercise.priorityGym ?? 70), forKey: "priorityGym")
                
                // Video filename for direct video lookup
                exercise.videoFilename = cloudExercise.videoFilename
                
                syncedCount += 1
                
                // Debug: Log workout types being synced (first 10)
                if syncedCount <= 10 && cloudExercise.workoutType != nil {
                    print("📊 Syncing workout_type: '\(cloudExercise.workoutType ?? "nil")' for '\(cloudExercise.name)'")
                }
                
                // Create intelligence profile with defaults for optional fields
                let profile = ExerciseIntelligenceProfile(
                    exerciseName: cloudExercise.name,
                    primaryMuscles: cloudExercise.primaryMusclesArray,
                    secondaryMuscles: cloudExercise.secondaryMusclesArray,
                    movementPattern: cloudExercise.movementPattern ?? "compound",
                    forceVector: cloudExercise.forceType ?? "push",
                    planeOfMotion: cloudExercise.planeOfMotion ?? "sagittal",
                    movementType: cloudExercise.movementType ?? "dynamic",
                    laterality: cloudExercise.laterality ?? "bilateral",
                    difficultyLevel: cloudExercise.difficultyLevel ?? 5,
                    complexityScore: cloudExercise.complexityScore ?? 5,
                    strengthRating: cloudExercise.strengthRating ?? 5,
                    hypertrophyRating: cloudExercise.hypertrophyRating ?? 5,
                    powerRating: cloudExercise.powerRating ?? 3,
                    enduranceRating: cloudExercise.enduranceRating ?? 3,
                    bodyPosition: cloudExercise.bodyPosition ?? "standing",
                    benchAngle: {
                        // Convert bench angle string to Int (if it's a number)
                        guard let angleStr = cloudExercise.benchAngle else { return nil }
                        // Try to parse number from string (e.g., "45" or "45 degrees")
                        let numericPart = angleStr.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
                        return Int(numericPart)
                    }(),
                    gripType: cloudExercise.gripType,
                    gripWidth: cloudExercise.gripWidth,
                    optimalRepRange: (cloudExercise.optimalRepRangeMin ?? 8)...(cloudExercise.optimalRepRangeMax ?? 12),
                    placementInWorkout: cloudExercise.placementInWorkout ?? "main",
                    fatigability: {
                        // Convert numeric fatigability to string
                        if let numFatigability = cloudExercise.fatigability {
                            switch numFatigability {
                            case 1...3: return "low"
                            case 4...6: return "moderate"
                            case 7...10: return "high"
                            default: return "moderate"
                            }
                        }
                        return "moderate"
                    }(),
                    popularityScore: cloudExercise.popularityScore ?? 50,
                    homeGymFriendly: cloudExercise.homeGymFriendly ?? true
                )
                intelligenceProfiles.append(profile)
            }
            
            do {
                try viewContext.save()
                print("✅ Synced \(syncedCount) exercises to Core Data")
                
                // CRITICAL: Invalidate cache AFTER save completes
                // This will synchronously rebuild the cache
                invalidateCache()
                
                // Verify exercises are accessible
                let verifyCount = getAllExercises().count
                print("✅ [VERIFY] Cache now has \(verifyCount) exercises")
                
                // ✅ Mark exercises as ready now that sync is complete
                if verifyCount > 100 {
                    isExercisesReady = true
                    print("✅ [SYNC] Exercises ready: \(verifyCount) exercises available")
                }
            } catch {
                print("❌ Error saving exercises to Core Data: \(error)")
            }
        }
        
        await MainActor.run {
            ExerciseIntelligenceService.shared.updateProfiles(intelligenceProfiles)
        }
        
        // Don't block on supplemental data - do it in background
        Task.detached(priority: .background) {
            await ExerciseIntelligenceService.shared.refreshSupplementalData()
        }
    }
    
    func initializeDefaultExercises() {
        // Check if exercises already exist
        let request: NSFetchRequest<Exercise> = Exercise.fetchRequest()
        
        do {
            let existingExercises = try viewContext.fetch(request)
            
            // Only initialize if database is essentially empty (< 100 exercises)
            // This prevents adding duplicates when cloud sync has already populated the database
            // Cloud sync should be the primary source - this is only a fallback for offline/first launch
            if existingExercises.count < 100 {
                print("🔄 [DEFAULT] No cloud data available, initializing with \(defaultExercises.count) default exercises...")
                
                // Delete any existing exercises first
                let deleteRequest = NSBatchDeleteRequest(fetchRequest: Exercise.fetchRequest())
                try viewContext.execute(deleteRequest)
                try viewContext.save()
                
                // Add default exercise database
                var successCount = 0
                for exerciseData in defaultExercises {
                    guard !exerciseData.name.isEmpty,
                          !exerciseData.category.isEmpty else {
                        continue
                    }
                    
                    let exercise = Exercise(context: viewContext)
                    exercise.id = UUID()
                    exercise.name = exerciseData.name
                    exercise.category = exerciseData.category
                    exercise.muscleGroups = exerciseData.muscleGroups as NSObject
                    exercise.equipment = exerciseData.equipment
                    exercise.instructions = exerciseData.instructions
                    exercise.isFavorite = false
                    successCount += 1
                }
                
                try viewContext.save()
                invalidateCache()
                #if DEBUG
                print("✅ [DEFAULT] Initialized \(successCount) default exercises")
                #endif
            } else {
                #if DEBUG
                print("📦 [DEFAULT] Skipping - already have \(existingExercises.count) exercises from cloud")
                #endif
            }
        } catch {
            print("❌ [DEFAULT] Error: \(error)")
        }
    }
    
    func getAllExercises() -> [Exercise] {
        // Return cached exercises if valid
        if isCacheValid, let cached = cachedExercises {
            #if DEBUG
            print("📦 [ExerciseLibrary] Returning \(cached.count) cached exercises")
            #endif
            return cached
        }
        
        #if DEBUG
        print("📦 [ExerciseLibrary] Fetching exercises from Core Data...")
        #endif
        
        let request: NSFetchRequest<Exercise> = Exercise.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Exercise.name, ascending: true)]
        request.returnsObjectsAsFaults = false
        
        do {
            let exercises = try viewContext.fetch(request)
            
            #if DEBUG
            print("📦 [ExerciseLibrary] Fetched \(exercises.count) exercises from Core Data")
            if exercises.count > 0 {
                print("📦 [ExerciseLibrary] Sample: \(exercises.prefix(3).compactMap { $0.name })")
            }
            #endif
            
            cachedExercises = exercises
            cacheTimestamp = Date()
            
            // Build name dictionary for quick lookups (lowercase keys for case-insensitive matching)
            cachedExercisesByName = Dictionary(
                exercises.compactMap { exercise -> (String, Exercise)? in
                    guard let name = exercise.name, !exercise.isDeleted else { return nil }
                    return (name.lowercased(), exercise)
                },
                uniquingKeysWith: { first, _ in first }
            )
            
            #if DEBUG
            print("📦 [ExerciseLibrary] Built name cache with \(cachedExercisesByName?.count ?? 0) entries")
            #endif
            
            // ✅ Update exercises ready state based on valid entries
            let validCount = cachedExercisesByName?.count ?? 0
            if validCount > 100 && !isExercisesReady {
                isExercisesReady = true
                print("✅ [ExerciseLibrary] Exercises now ready: \(validCount) valid")
            }
            
            return exercises
        } catch {
            print("❌ Error fetching exercises: \(error)")
            return []
        }
    }
    
    func getExercisesByEquipment(_ equipment: [String]) -> [Exercise] {
        let request: NSFetchRequest<Exercise> = Exercise.fetchRequest()
        request.predicate = NSPredicate(format: "equipment IN %@", equipment)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Exercise.name, ascending: true)]
        
        do {
            return try viewContext.fetch(request)
        } catch {
            print("Error fetching exercises by equipment: \(error)")
            return []
        }
    }
    
    func getExercisesByCategory(_ category: String) -> [Exercise] {
        let request: NSFetchRequest<Exercise> = Exercise.fetchRequest()
        request.predicate = NSPredicate(format: "category == %@", category)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Exercise.name, ascending: true)]
        
        do {
            return try viewContext.fetch(request)
        } catch {
            print("Error fetching exercises by category: \(error)")
            return []
        }
    }
    
    func searchExercises(_ searchText: String) -> [Exercise] {
        let request: NSFetchRequest<Exercise> = Exercise.fetchRequest()
        
        if searchText.isEmpty {
            request.sortDescriptors = [NSSortDescriptor(keyPath: \Exercise.name, ascending: true)]
        } else {
            request.predicate = NSPredicate(format: "name CONTAINS[cd] %@ OR category CONTAINS[cd] %@", searchText, searchText)
            request.sortDescriptors = [NSSortDescriptor(keyPath: \Exercise.name, ascending: true)]
        }
        
        do {
            return try viewContext.fetch(request)
        } catch {
            print("Error searching exercises: \(error)")
            return []
        }
    }
    
    func getMuscleGroups() -> [String] {
        return Array(Set(defaultExercises.flatMap { $0.muscleGroups })).sorted()
    }
    
    func getCategories() -> [String] {
        return Array(Set(defaultExercises.map { $0.category })).sorted()
    }
    
    func getEquipmentTypes() -> [String] {
        return Array(Set(defaultExercises.map { $0.equipment })).sorted()
    }
    
    func getSuggestedExercises(for equipment: [String], goal: String, experience: String, recentMuscleGroups: [String: Int] = [:], workoutLocation: String? = nil) -> [Exercise] {
        let allExercises = getAllExercises()
        
        // Determine if user has gym equipment
        let gymEquipment = ["Barbell", "Cables", "Cable", "Machines", "Machine"]
        let hasGymEquipment = equipment.contains { equip in
            gymEquipment.contains { equip.lowercased().contains($0.lowercased()) }
        } || workoutLocation == "Gym"
        
        // Gym equipment priority for gym users
        let gymEquipmentPriority = ["Barbell", "Dumbbells", "Dumbbell", "Cables", "Cable", "Machines", "Machine", "Kettlebell"]
        
        // Keywords for exercises to avoid for gym users
        let lyingBodyweightKeywords = ["lying", "floor", "dead bug", "bird dog", "superman", "prone"]
        let plyometricKeywords = ["jump", "hop", "bound", "plyo", "explosive"]
        
        // Determine focus based on goal and recent activity
        var focusAreas: [String] = []
        let allMuscleGroups = ["Chest", "Back", "Legs", "Shoulders", "Arms", "Core"]
        
        // Find least trained muscle groups
        let sortedByActivity = allMuscleGroups.sorted { muscle1, muscle2 in
            let count1 = recentMuscleGroups[muscle1] ?? 0
            let count2 = recentMuscleGroups[muscle2] ?? 0
            return count1 < count2
        }
        
        switch goal.lowercased() {
        case let g where g.contains("strength") || g.contains("strong"):
            focusAreas = ["Legs", "Back", "Chest"] // Compound movements
        case let g where g.contains("bulk") || g.contains("muscle"):
            focusAreas = Array(sortedByActivity.prefix(4)) // Balance all groups
        case let g where g.contains("cut") || g.contains("weight") || g.contains("fat"):
            focusAreas = ["Legs", "Core", "Back", "Chest"] // Higher calorie burn
        case let g where g.contains("tone"):
            focusAreas = Array(sortedByActivity.prefix(3)) // Balanced approach
        default:
            focusAreas = Array(sortedByActivity.prefix(3)) // General fitness
        }
        
        // Score and filter exercises
        var scoredExercises: [(exercise: Exercise, score: Int)] = []
        
        for exercise in allExercises {
            var score = 100
            
            let exerciseName = (exercise.name ?? "").lowercased()
            let exerciseEquipment = (exercise.equipment ?? "").lowercased()
            let exerciseMuscles = (exercise.getMuscleGroups() ?? []).map { $0.lowercased() }
            let category = (exercise.category ?? "").lowercased()
            let workoutType = (exercise.workoutType ?? "").lowercased()
            
            // Check equipment match
            let normalizedUserEquipment = equipment.map { $0.lowercased() }
            let equipmentMatch = normalizedUserEquipment.isEmpty || normalizedUserEquipment.contains { equip in
                exerciseEquipment.contains(equip) || 
                (equip == "bodyweight" && exerciseEquipment.isEmpty)
            }
            
            guard equipmentMatch else { continue }
            
            // Check muscle/focus match
            let muscleMatch = focusAreas.contains { focus in
                exerciseMuscles.contains { $0.contains(focus.lowercased()) } ||
                category.contains(focus.lowercased())
            }
            
            if !muscleMatch { score -= 50 }
            
            // Exclude stretching
            let isStretch = workoutType == "stretch" || workoutType == "stretching"
            guard !isStretch else { continue }
            
            // ═══════════════════════════════════════════════════════════════
            // GYM USER SCORING
            // ═══════════════════════════════════════════════════════════════
            if hasGymEquipment {
                // BOOST: Gym equipment
                if let priorityIndex = gymEquipmentPriority.firstIndex(where: { exerciseEquipment.contains($0.lowercased()) }) {
                    score += (gymEquipmentPriority.count - priorityIndex) * 12
                }
                
                // PENALIZE: Lying bodyweight for gym users
                let isLyingBodyweight = lyingBodyweightKeywords.contains { exerciseName.contains($0) } && 
                                       (exerciseEquipment == "bodyweight" || exerciseEquipment.isEmpty)
                if isLyingBodyweight {
                    score -= 70
                }
                
                // PENALIZE: Pure bodyweight for gym users
                if exerciseEquipment == "bodyweight" || exerciseEquipment.isEmpty {
                    score -= 25
                }
                
                // PENALIZE: Plyometrics for gym sessions
                let isPlyometric = plyometricKeywords.contains { exerciseName.contains($0) }
                if isPlyometric {
                    score -= 35
                }
            }
            
            // BOOST: Compound movements
            let compoundKeywords = ["press", "squat", "deadlift", "row", "pull-up", "chin-up", "lunge", "dip"]
            if compoundKeywords.contains(where: { exerciseName.contains($0) }) {
                score += 15
            }
            
            // Experience level adjustments
            switch experience.lowercased() {
            case "beginner":
                if exerciseEquipment == "barbell" { score -= 20 }
                if exerciseName.contains("olympic") || exerciseName.contains("snatch") { score -= 50 }
            case "advanced":
                if compoundKeywords.contains(where: { exerciseName.contains($0) }) { score += 10 }
            default:
                break
            }
            
            // Penalize recently used muscles (encourage variety)
            for muscle in exerciseMuscles {
                if let recentCount = recentMuscleGroups.first(where: { muscle.contains($0.key.lowercased()) })?.value {
                    score -= recentCount * 5
                }
            }
            
            scoredExercises.append((exercise, score))
        }
        
        // Sort by score and select top exercises
        scoredExercises.sort { $0.score > $1.score }
        
        var selectedExercises: [Exercise] = []
        var selectedNames: Set<String> = []
        var plyoCount = 0
        let maxPlyos = hasGymEquipment ? 1 : 2
        
        for (exercise, _) in scoredExercises {
            guard selectedExercises.count < 6 else { break }
            
            let name = (exercise.name ?? "").lowercased()
            
            // Skip duplicates
            guard !selectedNames.contains(name) else { continue }
            
            // Limit plyometrics
            let isPlyometric = plyometricKeywords.contains { name.contains($0) }
            if isPlyometric {
                if plyoCount >= maxPlyos { continue }
                plyoCount += 1
            }
            
            selectedExercises.append(exercise)
            selectedNames.insert(name)
        }
        
        return selectedExercises
    }
}
