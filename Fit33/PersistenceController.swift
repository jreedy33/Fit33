import CoreData
import Foundation

struct PersistenceController {
    static let shared = PersistenceController()
    
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
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
        
        return result
    }()
    
    let container: NSPersistentContainer
    
    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "DataModel")
        
        // Use persistent storage for meals data (even in DEBUG)
        let useInMemory = inMemory // Respect the parameter, don't force in-memory
        
        if useInMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
            print("🧪 Using in-memory Core Data (DEBUG mode)")
        }
        
        // Configure store description with migration options
        guard let description = container.persistentStoreDescriptions.first else {
            fatalError("Failed to retrieve a persistent store description")
        }
        
        // Enable automatic migration
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        
        var loadError: NSError?
        var storeURL: URL?
        
        container.loadPersistentStores { storeDescription, error in
            if let error = error as NSError? {
                print("⚠️ Core Data load failed: \(error)")
                print("Error code: \(error.code)")
                loadError = error
                storeURL = storeDescription.url
            } else {
                print("✅ Core Data loaded successfully")
            }
        }
        
        // Handle migration failures by resetting the store
        if let error = loadError, let url = storeURL {
            print("🔄 Attempting automatic Core Data reset...")
            print("Error details: \(error.localizedDescription)")
            
            // Delete all store files
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: url.path) {
                // Delete main store file
                try? fileManager.removeItem(at: url)
                
                // Delete associated files (-shm, -wal)
                let shmURL = URL(fileURLWithPath: url.path + "-shm")
                let walURL = URL(fileURLWithPath: url.path + "-wal")
                try? fileManager.removeItem(at: shmURL)
                try? fileManager.removeItem(at: walURL)
                
                print("🗑️ Deleted old Core Data store files")
            }
            
            // Try loading again with fresh store
            var retrySuccess = false
            container.loadPersistentStores { _, retryError in
                if let retryError = retryError as NSError? {
                    print("❌ Retry failed: \(retryError.localizedDescription)")
                } else {
                    print("✅ Core Data successfully reset and loaded")
                    retrySuccess = true
                }
            }
            
            // If retry failed, this is a critical error
            if !retrySuccess {
                print("⚠️ WARNING: Could not load Core Data even after reset. App may not function correctly.")
            }
        }
        
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }
    
    func save() {
        let context = container.viewContext
        
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                let nsError = error as NSError
                print("Core Data save error: \(nsError), \(nsError.userInfo)")
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
                print("Error deleting \(entity): \(error)")
            }
        }
        
        save()
        print("🗑️ All Core Data entities deleted")
    }
    
    /// Clears all user data for sign-out security
    /// This ensures no data from one user is visible to another
    func clearAllUserData() {
        print("🔐 Clearing all local user data for sign-out/deletion...")
        
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
        
        print("🗑️ UserDefaults cleared")
        
        // 3. Reset the view context
        container.viewContext.reset()
        print("🔄 Core Data context reset")
        
        // 4. Clear profile photo cache - critical for multi-user scenarios
        ProfilePhotoCache.shared.clearCache()
        print("🗑️ Profile photo cache cleared")
        
        // 5. Clear singleton service in-memory state
        // This is critical - clearing UserDefaults alone won't reset @Published properties
        // Use DispatchQueue.main.async since some services are @MainActor isolated
        DispatchQueue.main.async {
            SmartProgramEngine.shared.clearAllData()
            GeneratedProgramService.shared.clearAllPrograms()
            CloudProgramService.shared.clearActiveProgramCache()
            UserManager.shared.resetForSignOut()
            print("🔄 Singleton services reset")
        }
        
        print("✅ All local user data cleared successfully")
    }
}
