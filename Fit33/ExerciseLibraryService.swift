import Foundation
import CoreData

struct ExerciseData: Codable {
    let name: String
    let category: String
    let muscleGroups: [String]
    let equipment: String
    let instructions: String
    let primaryBodyRegion: String
    let primaryMuscle: String
    let secondaryMuscles: [String]
    let sources: [String]
    var videoFilename: String? = nil  // For direct video lookup (not in JSON)
    
    enum CodingKeys: String, CodingKey {
        case name, category, muscleGroups, equipment, instructions
        case primaryBodyRegion, primaryMuscle, secondaryMuscles, sources
        // videoFilename is excluded from JSON — it's set at runtime
    }
}

class ExerciseLibraryService: ObservableObject {
    static let shared = ExerciseLibraryService()
    
    private let viewContext = PersistenceController.shared.container.viewContext
    
    // ⚡️ PERF: Loads from exercises.json via ExerciseDataProvider (lazy, cached).
    // Previously loaded from ComprehensiveExerciseDatabase.swift (7800 lines of hardcoded Swift).
    private var defaultExercises: [ExerciseData] { ExerciseDataProvider.shared.exercises }
    
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
        let count = (try? viewContext.count(for: Exercise.fetchRequest())) ?? 0
        if count > 100 {
            isExercisesReady = true
            AppLogger.debug("✅ [ExerciseLibrary] Exercises ready at init: \(count) in Core Data", category: .data)
        }
        preWarmCache()
    }
    
    /// Pre-warm the exercise cache, doing the Core Data fetch on a background context
    /// to avoid blocking the main thread at startup
    func preWarmCache() {
        guard !isPreWarming && cachedExercisesByName == nil else { return }
        isPreWarming = true
        
        let bgContext = PersistenceController.shared.container.newBackgroundContext()
        bgContext.automaticallyMergesChangesFromParent = true
        
        Task.detached(priority: .userInitiated) { [weak self] in
            await MainActor.run { StartupWaterfall.shared.mark("ExerciseLibrary.preWarmCache") }
            let startTime = CFAbsoluteTimeGetCurrent()
            
            // Fetch exercise names on background context (avoids blocking main thread)
            let nameList: [String] = await bgContext.perform {
                let request: NSFetchRequest<Exercise> = Exercise.fetchRequest()
                request.sortDescriptors = [NSSortDescriptor(keyPath: \Exercise.name, ascending: true)]
                request.propertiesToFetch = ["name"]
                let exercises = (try? bgContext.fetch(request)) ?? []
                return exercises.compactMap { $0.name }
            }
            
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            
            // Now do the lightweight main-thread work: build cache using viewContext
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                AppLogger.debug("🔥 [ExerciseLibrary] Cache pre-warmed: \(elapsed)ms", category: .data)
                StartupWaterfall.shared.end("ExerciseLibrary.preWarmCache")
                self.isPreWarming = false
                
                if nameList.count > 100 {
                    self.isExercisesReady = true
                    AppLogger.debug("✅ [ExerciseLibrary] Exercises ready: \(nameList.count) valid exercises", category: .data)
                    
                    // Trigger filter cache precomputation (also runs mostly in background)
                    let allExercises = self.getAllExercises()
                    let filterCache = ExerciseLibraryFilterCache.shared
                    if !filterCache.isReady {
                        filterCache.precomputeRecommendedList(allExercises: allExercises)
                    }
                } else {
                    AppLogger.warning("⚠️ [ExerciseLibrary] Only \(nameList.count) valid exercises - waiting for sync", category: .network)
                }
            }
        }
    }
    
    /// Get exercise by name - O(1) lookup using cached dictionary (case-insensitive)
    func getExercise(byName name: String) -> Exercise? {
        // Build cache if needed (with lowercase keys for case-insensitive matching)
        if cachedExercisesByName == nil || !isCacheValid {
            #if DEBUG
            AppLogger.debug("📦 [ExerciseLibrary] Cache miss for '\(name)' - rebuilding...", category: .data)
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
            AppLogger.warning("⚠️ [ExerciseLibrary] Exercise not found: '\(name)' (cache size: \(cachedExercisesByName?.count ?? 0))", category: .data)
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
        AppLogger.debug("📦 Exercise cache invalidated", category: .data)
        #endif
        
        // Refresh the context to ensure it sees all changes after batch operations
        viewContext.refreshAllObjects()
        
        // SYNCHRONOUSLY rebuild the cache so it's immediately available
        // (Don't use preWarmCache which runs async)
        let startTime = CFAbsoluteTimeGetCurrent()
        _ = getAllExercises()
        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        #if DEBUG
        AppLogger.debug("🔥 [ExerciseLibrary] Cache rebuilt synchronously: \(elapsed)ms, \(cachedExercises?.count ?? 0) exercises", category: .data)
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
                AppLogger.warning("🔧 [ExerciseLibrary] Found \(orphanedExercises.count) WorkoutExercises with nil relationships", category: .data)
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
                    AppLogger.debug("✅ [ExerciseLibrary] Repaired \(repaired) exercise relationships", category: .data)
                    #endif
                }
            } catch {
                #if DEBUG
                AppLogger.error("❌ [ExerciseLibrary] Error repairing relationships: \(error)", category: .data)
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
            AppLogger.warning("⚠️ [SYNC] Skipping exercise sync - workout is active", category: .network)
            return
        }
        
        // 🔒 Prevent concurrent syncs
        syncLock.lock()
        if isSyncing {
            syncLock.unlock()
            AppLogger.warning("⚠️ [SYNC] Skipping - sync already in progress", category: .network)
            return
        }
        isSyncing = true
        syncLock.unlock()
        
        defer {
            syncLock.lock()
            isSyncing = false
            syncLock.unlock()
        }
        
        AppLogger.debug("🔄 Syncing \(cloudExercises.count) exercises from audit to local database...", category: .network)
        await performSync(with: cloudExercises)
    }
    
    /// Force sync exercises - clears old data and pulls fresh from cloud
    func forceSyncExercises() async {
        AppLogger.debug("🔄 FORCE SYNC: Clearing old exercise data...", category: .network)
        
        // ⚠️ Mark as not ready FIRST so UI shows loading state
        // and onChange(isExercisesReady) fires when sync completes
        await MainActor.run {
            isExercisesReady = false
        }
        
        await MainActor.run {
            let viewContext = PersistenceController.shared.container.viewContext
            let fetchRequest: NSFetchRequest<NSFetchRequestResult> = Exercise.fetchRequest()
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
            
            do {
                try viewContext.execute(deleteRequest)
                try viewContext.save()
                invalidateCache()
                AppLogger.debug("✅ Cleared existing exercises from Core Data", category: .data)
            } catch {
                AppLogger.error("❌ Error clearing exercises: \(error)", category: .data)
            }
        }
        
        // Now sync fresh data
        await syncExercisesFromCloud()
        
        // Mark as synced with latest data
        UserDefaults.standard.set(Date(), forKey: "lastExerciseDataUpdate")
        AppLogger.debug("✅ FORCE SYNC complete - fresh data loaded!", category: .network)
    }
    
    /// How often exercises should be fully re-synced from cloud.
    /// Exercises rarely change — a 6-hour window is plenty.
    private static let exerciseSyncInterval: TimeInterval = 6 * 60 * 60 // 6 hours
    
    func syncExercisesFromCloud() async {
        // 🛡️ CRITICAL: Never sync exercises during an active workout!
        if WorkoutManager.shared.isWorkoutActive {
            AppLogger.warning("⚠️ [SYNC] Skipping exercise sync - workout is active", category: .network)
            return
        }
        
        // ⚡️ PERFORMANCE: Skip full exercise re-sync if Core Data is fresh.
        // The exercise database rarely changes (new exercises added weekly at most).
        // A full re-sync downloads 6500+ exercises, deletes Core Data, and re-inserts — VERY expensive.
        // Only re-sync if cache is stale (>6 hours) or explicitly forced.
        let lastSync = UserDefaults.standard.object(forKey: "lastExerciseCloudSync") as? Date
        let cacheAge = lastSync.map { Date().timeIntervalSince($0) } ?? .infinity
        
        // Check if we have a reasonable number of exercises cached
        let cachedCount = await MainActor.run { () -> Int in
            let req: NSFetchRequest<Exercise> = Exercise.fetchRequest()
            return (try? PersistenceController.shared.container.viewContext.count(for: req)) ?? 0
        }
        
        if cachedCount > 1000 && cacheAge < Self.exerciseSyncInterval {
            let hoursAgo = String(format: "%.1f", cacheAge / 3600)
            AppLogger.warning("⚡️ [SYNC] Skipping exercise sync — \(cachedCount) exercises cached, synced \(hoursAgo)h ago", category: .network)
            
            // Still mark exercises as ready if they aren't
            if !isExercisesReady {
                await preloadAll()
            }
            return
        }
        
        // 🔒 Prevent concurrent syncs (causes duplicate entries)
        syncLock.lock()
        if isSyncing {
            syncLock.unlock()
            AppLogger.warning("⚠️ [SYNC] Skipping - sync already in progress", category: .network)
            return
        }
        isSyncing = true
        syncLock.unlock()
        
        defer {
            syncLock.lock()
            isSyncing = false
            syncLock.unlock()
        }
        
        // Fetch exercises from Supabase with retry on timeout, then sync to Core Data
        AppLogger.debug("🔄 Starting exercise sync from cloud...", category: .network)
        do {
            var cloudExercises: [ExerciseDTO]?
            var lastError: Error?
            for attempt in 0...2 {
                do {
                    cloudExercises = try await SupabaseManager.shared.fetchAllExercises()
                    break
                } catch {
                    lastError = error
                    let nsError = error as NSError
                    if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorTimedOut && attempt < 2 {
                        let delay = UInt64(pow(2.0, Double(attempt))) * 2_000_000_000
                        AppLogger.warning("Exercise cloud sync timed out (attempt \(attempt + 1)/3) — retrying in \(delay / 1_000_000_000)s...", category: .network)
                        try? await Task.sleep(nanoseconds: delay)
                        continue
                    }
                    throw error
                }
            }
            guard let exercises = cloudExercises else {
                throw lastError ?? NSError(domain: "ExerciseLibraryService", code: -1)
            }
            AppLogger.debug("✅ Fetched \(exercises.count) exercises from cloud", category: .network)
            await performSync(with: exercises)
            
            UserDefaults.standard.set(Date(), forKey: "lastExerciseCloudSync")
        } catch {
            AppLogger.error("❌ Failed to fetch exercises from cloud: \(error)", category: .network)
        }
    }
    
    private func performSync(with cloudExercises: [ExerciseDTO]) async {
        AppLogger.debug("✅ Processing \(cloudExercises.count) exercises for sync", category: .network)
        
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
                AppLogger.debug("🗑️ Cleared existing exercises from Core Data", category: .data)
            } catch {
                AppLogger.error("⚠️ Error clearing exercises: \(error)", category: .data)
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
                    AppLogger.debug("📊 Syncing workout_type: '\(cloudExercise.workoutType ?? "nil")' for '\(cloudExercise.name)'", category: .network)
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
                AppLogger.debug("✅ Synced \(syncedCount) exercises to Core Data", category: .network)
                
                // CRITICAL: Invalidate cache AFTER save completes
                // This will synchronously rebuild the cache
                invalidateCache()
                
                // Verify exercises are accessible
                let verifyCount = getAllExercises().count
                AppLogger.debug("✅ [VERIFY] Cache now has \(verifyCount) exercises", category: .data)
                
                // ✅ Mark exercises as ready now that sync is complete
                if verifyCount > 100 {
                    isExercisesReady = true
                    AppLogger.debug("✅ [SYNC] Exercises ready: \(verifyCount) exercises available", category: .network)
                }
            } catch {
                AppLogger.error("❌ Error saving exercises to Core Data: \(error)", category: .data)
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
                AppLogger.debug("🔄 [DEFAULT] No cloud data available, initializing with \(defaultExercises.count) default exercises...", category: .network)
                
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
                AppLogger.debug("✅ [DEFAULT] Initialized \(successCount) default exercises", category: .data)
                #endif
            } else {
                #if DEBUG
                AppLogger.warning("📦 [DEFAULT] Skipping - already have \(existingExercises.count) exercises from cloud", category: .network)
                #endif
            }
        } catch {
            AppLogger.error("❌ [DEFAULT] Error: \(error)", category: .data)
        }
    }
    
    /// Seed Core Data from bundle JSON for true cold starts (empty database).
    /// Safe to call multiple times -- exits early if exercises already exist.
    func seedFromBundle() {
        let count = (try? viewContext.count(for: Exercise.fetchRequest())) ?? 0
        guard count < 100 else { return }
        
        let bundleExercises = ExerciseDataProvider.shared.exercises
        guard !bundleExercises.isEmpty else { return }
        
        AppLogger.debug("🌱 [ExerciseLibrary] Seeding \(bundleExercises.count) exercises from bundle...", category: .data)
        var inserted = 0
        for data in bundleExercises {
            guard !data.name.isEmpty, !data.category.isEmpty else { continue }
            let exercise = Exercise(context: viewContext)
            exercise.id = UUID()
            exercise.name = data.name
            exercise.category = data.category
            exercise.muscleGroups = data.muscleGroups as NSObject
            exercise.equipment = data.equipment
            exercise.instructions = data.instructions
            exercise.isFavorite = false
            inserted += 1
        }
        
        do {
            try viewContext.save()
            invalidateCache()
            isExercisesReady = true
            AppLogger.debug("✅ [ExerciseLibrary] Seeded \(inserted) exercises from bundle", category: .data)
        } catch {
            AppLogger.error("❌ [ExerciseLibrary] Bundle seed failed: \(error)", category: .data)
        }
    }
    
    func getAllExercises() -> [Exercise] {
        // Return cached exercises if valid
        if isCacheValid, let cached = cachedExercises {
            #if DEBUG
            AppLogger.debug("📦 [ExerciseLibrary] Returning \(cached.count) cached exercises", category: .data)
            #endif
            return cached
        }
        
        #if DEBUG
        AppLogger.debug("📦 [ExerciseLibrary] Fetching exercises from Core Data...", category: .network)
        #endif
        
        let request: NSFetchRequest<Exercise> = Exercise.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Exercise.name, ascending: true)]
        // ⚡️ MEMORY FIX: Use faults (true = default). The old `false` setting forced all 7000+
        // exercises to load ALL properties into memory at once (~50-100MB). Core Data faulting
        // loads properties on demand, which is far more memory efficient.
        // request.returnsObjectsAsFaults = false  // REMOVED — was forcing full materialization
        
        do {
            let exercises = try viewContext.fetch(request)
            
            #if DEBUG
            AppLogger.debug("📦 [ExerciseLibrary] Fetched \(exercises.count) exercises from Core Data", category: .network)
            if exercises.count > 0 {
                AppLogger.debug("📦 [ExerciseLibrary] Sample: \(exercises.prefix(3).compactMap { $0.name })", category: .data)
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
            AppLogger.debug("📦 [ExerciseLibrary] Built name cache with \(cachedExercisesByName?.count ?? 0) entries", category: .data)
            #endif
            
            // ✅ Update exercises ready state based on valid entries
            let validCount = cachedExercisesByName?.count ?? 0
            if validCount > 100 && !isExercisesReady {
                isExercisesReady = true
                AppLogger.debug("✅ [ExerciseLibrary] Exercises now ready: \(validCount) valid", category: .data)
            }
            
            return exercises
        } catch {
            AppLogger.error("❌ Error fetching exercises: \(error)", category: .network)
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
            AppLogger.error("Error fetching exercises by equipment: \(error)", category: .network)
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
            AppLogger.error("Error fetching exercises by category: \(error)", category: .network)
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
            AppLogger.error("Error searching exercises: \(error)", category: .data)
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
