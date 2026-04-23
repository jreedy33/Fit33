import CoreData
import Foundation

// MARK: - Core Data Recovery Notifications
extension Notification.Name {
    /// Posted when Core Data fails to load even after a reset attempt.
    /// Observers should show a critical error screen to the user.
    static let coreDataLoadFailed = Notification.Name("coreDataLoadFailed")
}

struct PersistenceController {
    static let shared = PersistenceController()
    
    // MARK: - Store Recovery State
    /// True if the store was reset (deleted & recreated) due to migration failure.
    /// The existing syncAllDataFromCloud() in checkAuth() will auto-restore all data.
    /// After restore, Fit33App silently cleans up the backup — user never sees anything.
    static var storeWasReset = false
    
    /// True if Core Data could not be loaded even after a reset attempt.
    /// The app should show a critical error screen when this is true.
    static var storeLoadFailed = false
    
    /// The migration error that caused the store reset, if any.
    static var migrationError: NSError?
    
    /// URL where the backup of the corrupted store was saved (if backup succeeded).
    static var storeBackupURL: URL?
    
    static var preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext
        
        // Create sample user for previews
        let sampleUser = User(context: viewContext)
        sampleUser.id = UUID()
        sampleUser.name = "John Doe"
        sampleUser.email = "john@example.com"
        sampleUser.hasCompletedOnboarding = true
        sampleUser.currentStreak = 7
        sampleUser.longestStreak = 14
        sampleUser.totalWorkouts = 25
        sampleUser.xp = 1250
        sampleUser.fitnessGoal = "Strength"
        sampleUser.experienceLevel = "Intermediate"
        sampleUser.equipment = ["Dumbbells", "Barbell", "Bodyweight"] as NSObject
        sampleUser.availableDays = 4
        sampleUser.createdAt = Date()
        sampleUser.lastWorkoutDate = Calendar.current.date(byAdding: .day, value: -1, to: Date())
        
        // Create sample exercises
        let exercises = [
            ("Push-ups", "Chest", ["Chest", "Shoulders", "Triceps"], "Bodyweight"),
            ("Squats", "Legs", ["Quadriceps", "Glutes", "Hamstrings"], "Bodyweight"),
            ("Dumbbell Rows", "Back", ["Lats", "Rhomboids", "Biceps"], "Dumbbells"),
            ("Plank", "Core", ["Core", "Shoulders"], "Bodyweight"),
            ("Deadlifts", "Back", ["Hamstrings", "Glutes", "Lats", "Traps"], "Barbell")
        ]
        
        for (name, category, muscleGroups, equipment) in exercises {
            let exercise = Exercise(context: viewContext)
            exercise.id = UUID()
            exercise.name = name
            exercise.category = category
            exercise.muscleGroups = muscleGroups as NSObject
            exercise.equipment = equipment
            exercise.instructions = "Perform with proper form and controlled movement."
        }
        
        // Create sample workout
        let sampleWorkout = Workout(context: viewContext)
        sampleWorkout.id = UUID()
        sampleWorkout.name = "Upper Body Strength"
        sampleWorkout.date = Date()
        sampleWorkout.duration = 3600 // 60 minutes
        sampleWorkout.isCompleted = true
        sampleWorkout.xpEarned = 50
        sampleWorkout.user = sampleUser
        
        do {
            try viewContext.save()
        } catch {
            AppLogger.warning("⚠️ [PREVIEW] Failed to save preview data: \(error)", category: .general)
        }
        
        return result
    }()
    
    let container: NSPersistentContainer
    
    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "DataModel")
        
        // Use persistent storage for meals data (even in DEBUG)
        let useInMemory = inMemory // Respect the parameter, don't force in-memory
        
        if useInMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
            AppLogger.debug("🧪 Using in-memory Core Data (DEBUG mode)", category: .general)
        }
        
        // Configure store description with migration options
        if let description = container.persistentStoreDescriptions.first {
            // Enable automatic migration
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
        } else {
            AppLogger.warning("⚠️ [CORE DATA] No persistent store description found — migration options skipped", category: .general)
        }
        
        var loadError: NSError?
        var storeURL: URL?
        
        container.loadPersistentStores { storeDescription, error in
            if let error = error as NSError? {
                AppLogger.warning("⚠️ Core Data load failed: \(error)", category: .general)
                AppLogger.error("Error code: \(error.code)", category: .general)
                loadError = error
                storeURL = storeDescription.url
            } else {
                AppLogger.info("✅ Core Data loaded successfully", category: .general)
            }
        }
        
        // Handle migration failures by resetting the store
        if let error = loadError, let url = storeURL {
            AppLogger.debug("🔄 Attempting automatic Core Data reset...", category: .general)
            AppLogger.error("Error details: \(error.localizedDescription)", category: .general)
            
            PersistenceController.migrationError = error
            
            // 🛡️ Log the migration failure to crash reporting with full context
            CrashReportingService.shared.reportError(
                message: "Core Data migration failed — store will be reset",
                domain: "CoreData",
                code: "MIGRATION_FAILURE_\(error.code)",
                error: error,
                severity: .critical,
                additionalContext: [
                    "store_url": url.absoluteString,
                    "error_domain": error.domain,
                    "error_code": "\(error.code)",
                    "error_user_info": "\(error.userInfo)",
                    "migration_auto_enabled": "true",
                    "infer_mapping_auto_enabled": "true"
                ]
            )
            
            let fileManager = FileManager.default
            
            // 🛡️ STEP 1: Backup the corrupted store before deleting
            if fileManager.fileExists(atPath: url.path) {
                let backupDir = fileManager.temporaryDirectory
                    .appendingPathComponent("CoreDataBackup_\(Int(Date().timeIntervalSince1970))")
                
                do {
                    try fileManager.createDirectory(at: backupDir, withIntermediateDirectories: true)
                    
                    let mainBackup = backupDir.appendingPathComponent(url.lastPathComponent)
                    try fileManager.copyItem(at: url, to: mainBackup)
                    
                    // Also backup -shm and -wal if they exist
                    let shmURL = URL(fileURLWithPath: url.path + "-shm")
                    let walURL = URL(fileURLWithPath: url.path + "-wal")
                    if fileManager.fileExists(atPath: shmURL.path) {
                        try fileManager.copyItem(at: shmURL, to: backupDir.appendingPathComponent(shmURL.lastPathComponent))
                    }
                    if fileManager.fileExists(atPath: walURL.path) {
                        try fileManager.copyItem(at: walURL, to: backupDir.appendingPathComponent(walURL.lastPathComponent))
                    }
                    
                    PersistenceController.storeBackupURL = backupDir
                    AppLogger.debug("💾 Core Data store backed up to: \(backupDir.path)", category: .general)
                } catch {
                    AppLogger.warning("⚠️ Failed to backup Core Data store: \(error.localizedDescription)", category: .general)
                    CrashReportingService.shared.reportError(
                        message: "Failed to backup Core Data store before reset",
                        domain: "CoreData",
                        code: "BACKUP_FAILURE",
                        error: error,
                        severity: .high
                    )
                }
                
                // STEP 2: Delete the corrupted store files
                try? fileManager.removeItem(at: url)
                
                let shmURL = URL(fileURLWithPath: url.path + "-shm")
                let walURL = URL(fileURLWithPath: url.path + "-wal")
                try? fileManager.removeItem(at: shmURL)
                try? fileManager.removeItem(at: walURL)
                
                AppLogger.debug("🗑️ Deleted old Core Data store files", category: .general)
            }
            
            // STEP 3: Try loading again with fresh store
            var retrySuccess = false
            container.loadPersistentStores { _, retryError in
                if let retryError = retryError as NSError? {
                    AppLogger.error("❌ Retry failed: \(retryError.localizedDescription)", category: .general)
                } else {
                    AppLogger.info("✅ Core Data successfully reset and loaded", category: .general)
                    retrySuccess = true
                }
            }
            
            if retrySuccess {
                // STEP 4: Store was reset — auto-restore will happen via syncAllDataFromCloud()
                // which runs inside checkAuth() on every authenticated app launch.
                // The user never sees anything — their data reappears seamlessly.
                PersistenceController.storeWasReset = true
                
                CrashReportingService.shared.reportError(
                    message: "Core Data store was reset successfully — auto-restore pending via cloud sync",
                    domain: "CoreData",
                    code: "STORE_RESET_SUCCESS",
                    severity: .high,
                    additionalContext: [
                        "backup_location": PersistenceController.storeBackupURL?.path ?? "none",
                        "original_error_code": "\(loadError?.code ?? 0)"
                    ]
                )
            } else {
                // STEP 5: Critical failure — Core Data cannot load at all
                PersistenceController.storeLoadFailed = true
                
                CrashReportingService.shared.reportError(
                    message: "Core Data CRITICAL FAILURE — store cannot load even after reset",
                    domain: "CoreData",
                    code: "STORE_LOAD_FATAL",
                    severity: .critical,
                    additionalContext: [
                        "original_error": loadError?.localizedDescription ?? "unknown",
                        "original_error_code": "\(loadError?.code ?? 0)",
                        "backup_location": PersistenceController.storeBackupURL?.path ?? "none"
                    ]
                )
                
                // Post notification so UI can show a critical error screen
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .coreDataLoadFailed, object: nil)
                }
                
                AppLogger.error("❌ CRITICAL: Could not load Core Data even after reset. App will not function correctly.", category: .general)
            }
        }
        
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        // Cluster E — SIGSEGV root-cause audit.
        //
        // Core Data Transformable attributes that use the default (deprecated)
        // NSKeyedUnarchiveFromData transformer or no transformer at all can
        // SIGSEGV on iOS 17+ when decoding. Every release we've seen with a
        // fresh SIGSEGV in bug_intelligence_reports traced back to a
        // Transformable attribute added without a secure transformer.
        // Run a DEBUG-only scan so regressions are caught at dev time.
        #if DEBUG
        scanUnsafeTransformableAttributes()
        #endif
    }

    /// DEBUG-only audit — logs `.error` for every Transformable attribute
    /// in the Core Data model that lacks `NSSecureUnarchiveFromData` (or a
    /// custom secure transformer) + a `customClassName`. Both are required
    /// for iOS 17+ crash-safe decoding. Runs inside `init` so regressions
    /// surface during the first app launch after a model change.
    private func scanUnsafeTransformableAttributes() {
        for (entityName, entity) in container.managedObjectModel.entitiesByName {
            for (attrName, attr) in entity.attributesByName
                where attr.attributeType == .transformableAttributeType {
                let transformer = attr.valueTransformerName
                let hasClassName = attr.userInfo?["customClassName"] != nil
                let unsafe =
                    transformer == nil ||
                    transformer == "NSKeyedUnarchiveFromData" ||
                    transformer == "NSKeyedUnarchiveFromDataTransformerName"

                if unsafe {
                    AppLogger.error(
                        "UNSAFE transformable attribute: \(entityName).\(attrName) transformer=\(transformer ?? "nil")",
                        category: .data,
                        context: DiagnosticContext(
                            op: "coredata.transformable_scan",
                            endpoint: "\(entityName).\(attrName)"
                        )
                    )
                } else if !hasClassName {
                    AppLogger.warning(
                        "Transformable attribute missing customClassName: \(entityName).\(attrName) transformer=\(transformer ?? "?")",
                        category: .data,
                        context: DiagnosticContext(
                            op: "coredata.transformable_scan",
                            endpoint: "\(entityName).\(attrName)"
                        )
                    )
                }
            }
        }
    }

    func save() {
        let context = container.viewContext
        
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                let nsError = error as NSError
                AppLogger.error("Core Data save error: \(nsError), \(nsError.userInfo)", category: .general)
            }
        }
    }
    
    func deleteAll() {
        // These are the actual entity names from the Core Data model
        let entities = ["User", "Workout", "WorkoutExercise", "WorkoutSet", "Exercise", "UserAchievement", "MealEntry"]
        
        for entity in entities {
            let request = NSFetchRequest<NSFetchRequestResult>(entityName: entity)
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
            
            do {
                try container.viewContext.execute(deleteRequest)
            } catch {
                AppLogger.error("Error deleting \(entity): \(error)", category: .general)
            }
        }
        
        save()
        AppLogger.debug("🗑️ All Core Data entities deleted", category: .general)
    }
    
    /// Clears all user data for sign-out security
    /// This ensures no data from one user is visible to another
    func clearAllUserData() {
        AppLogger.debug("🔐 Clearing all local user data for sign-out/deletion...", category: .general)
        
        // 1. Delete all Core Data entities
        deleteAll()
        
        // 2. Clear UserDefaults (comprehensive list - except essential app settings)
        let keysToRemove = [
            // User profile data
            "userWeight", "userHeight", "userGender", "userAge",
            "userName", "userEmail", "userFitnessGoal", "userExperienceLevel",
            "userEquipment", "userAvailableDays", "hasCompletedOnboarding",
            
            // User stats and progress
            "currentStreak", "longestStreak", "totalWorkouts", "userXP",
            "lastWorkoutDate", "isPremiumUser",
            
            // Nutrition goals
            "dailyCalorieGoal", "dailyProteinGoal", "dailyCarbsGoal", "dailyFatGoal",
            
            // Program data - ALL program services
            "activeProgram", "activeProgramId", "programStartDate", "programCompletedDays",
            "cachedProgram", "cachedProgram_active",
            
            // GeneratedProgramService keys
            "generatedPrograms",
            "activeGeneratedProgram",
            "activeGeneratedProgram_currentDay",
            
            // CloudProgramService keys
            "cached_active_program",
            "cached_active_program_active",
            
            // SmartProgramEngine keys
            "smart_user_programs",
            
            // Cached data
            "lastSyncDate", "cachedWorkoutHistory", "cachedUserProfile", "cachedMeals",
            
            // Notifications and reminders
            "last_comeback_reminder",
            
            // Auth state (keep user_manually_signed_out for proper flow)
            // "user_manually_signed_out" - intentionally NOT removed here
        ]
        
        for key in keysToRemove {
            UserDefaults.standard.removeObject(forKey: key)
        }
        
        // Also clear any keys with dynamic prefixes
        let allKeys = UserDefaults.standard.dictionaryRepresentation().keys
        for key in allKeys {
            // BUG FIX: Added parentheses — without them, && binds tighter than ||,
            // causing "user_manually_signed_out" to be incorrectly deleted
            if key.hasPrefix("cached") || 
               key.hasPrefix("program_") || 
               key.hasPrefix("workout_") ||
               key.hasPrefix("smart_") ||
               key.hasPrefix("generated") ||
               key.hasPrefix("active") ||
               (key.hasPrefix("user_") && key != "user_manually_signed_out") {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        
        AppLogger.debug("🗑️ UserDefaults cleared", category: .general)
        
        // 3. Reset the view context
        container.viewContext.reset()
        AppLogger.debug("🔄 Core Data context reset", category: .general)
        
        // 4. Clear profile photo cache - critical for multi-user scenarios
        ProfilePhotoCache.shared.clearCache()
        AppLogger.debug("🗑️ Profile photo cache cleared", category: .general)
        
        // 5. Clear singleton service in-memory state
        // This is critical - clearing UserDefaults alone won't reset @Published properties
        // Use DispatchQueue.main.async since some services are @MainActor isolated
        DispatchQueue.main.async {
            SmartProgramEngine.shared.clearAllData()
            GeneratedProgramService.shared.clearAllPrograms()
            CloudProgramService.shared.clearActiveProgramCache()
            UserManager.shared.resetForSignOut()
            AppLogger.debug("🔄 Singleton services reset", category: .general)
        }
        
        AppLogger.info("✅ All local user data cleared successfully", category: .general)
    }
    
    // MARK: - Cloud Restore After Store Reset
    
    /// Restores all user data from Supabase after a Core Data store reset.
    /// Called automatically — the user never needs to know a reset happened.
    func attemptCloudRestore() async -> Bool {
        guard SupabaseManager.shared.isAuthenticated else {
            AppLogger.warning("⚠️ [RESTORE] Cannot restore from cloud — user not authenticated", category: .general)
            return false
        }
        
        AppLogger.debug("☁️ [RESTORE] Starting full cloud data restore...", category: .general)
        
        CrashReportingService.shared.addBreadcrumb("Cloud restore started after Core Data reset")
        
        // Use the existing comprehensive sync which restores:
        // - User profile
        // - Workout history
        // - Favorite workouts
        // - Meal logs
        // - Exercise nicknames
        await SupabaseManager.shared.syncAllDataFromCloud()
        
        AppLogger.info("✅ [RESTORE] Cloud data restore completed", category: .general)
        
        CrashReportingService.shared.addBreadcrumb("Cloud restore completed successfully")
        
        // Clear the reset flag now that data is restored
        PersistenceController.storeWasReset = false
        
        return true
    }
    
    /// Cleans up the backup of the corrupted store (call after successful restore or if user declines)
    func cleanupStoreBackup() {
        guard let backupURL = PersistenceController.storeBackupURL else { return }
        
        do {
            try FileManager.default.removeItem(at: backupURL)
            PersistenceController.storeBackupURL = nil
            AppLogger.debug("🗑️ Cleaned up Core Data backup at \(backupURL.path)", category: .general)
        } catch {
            AppLogger.warning("⚠️ Failed to clean up Core Data backup: \(error.localizedDescription)", category: .general)
        }
    }
}

// MARK: - DEBUG Context Safety

#if DEBUG
extension NSManagedObject {
    /// Assert that this object belongs to the expected context before setting relationships.
    /// Call this before assigning cross-object relationships in bgContext.perform blocks.
    /// Only runs in DEBUG builds — zero overhead in production.
    func assertContext(_ expectedContext: NSManagedObjectContext, file: StaticString = #file, line: UInt = #line) {
        guard let myContext = self.managedObjectContext else {
            assertionFailure(
                "[CONTEXT GUARD] \(entity.name ?? "Unknown") has nil context — was it deleted? (\(file):\(line))",
                file: file, line: line
            )
            return
        }
        assert(
            myContext === expectedContext,
            "[CONTEXT GUARD] \(entity.name ?? "Unknown") is on wrong context. Expected \(expectedContext.description), got \(myContext.description). Fetch from the correct context before assigning relationships. (\(file):\(line))"
        )
    }
}
#endif
