import Foundation
import SwiftUI
import CoreData

// MARK: - Cloud Program Data Models

/// Represents a workout program from the cloud
struct CloudProgram: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
    let preview: String
    let durationDays: Int
    let difficulty: String
    let programType: String
    let targetGoals: [String]
    let requiredExperience: String
    let requiredEquipment: [String]
    let minDaysPerWeek: Int
    let maxDaysPerWeek: Int
    let workoutsPerWeek: Int
    let avgWorkoutDurationMin: Int
    let restDays: [Int]
    let icon: String
    let color: String
    let benefits: [String]
    let equipment: [String]
    let popularityScore: Int
    let ratingAvg: Double?
    let ratingCount: Int
    let isFeatured: Bool
    
    // Computed for compatibility with existing UI
    var duration: Int { durationDays }
    
    enum CodingKeys: String, CodingKey {
        case id, name, description, preview, difficulty, icon, color, benefits, equipment
        case durationDays = "duration_days"
        case programType = "program_type"
        case targetGoals = "target_goals"
        case requiredExperience = "required_experience"
        case requiredEquipment = "required_equipment"
        case minDaysPerWeek = "min_days_per_week"
        case maxDaysPerWeek = "max_days_per_week"
        case workoutsPerWeek = "workouts_per_week"
        case avgWorkoutDurationMin = "avg_workout_duration_min"
        case restDays = "rest_days"
        case popularityScore = "popularity_score"
        case ratingAvg = "rating_avg"
        case ratingCount = "rating_count"
        case isFeatured = "is_featured"
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: CloudProgram, rhs: CloudProgram) -> Bool {
        lhs.id == rhs.id
    }
}

/// Represents a day within a program
struct CloudProgramDay: Codable, Identifiable {
    let id: String
    let programId: String
    let dayNumber: Int
    let name: String
    let description: String?
    let focusAreas: [String]
    let isRestDay: Bool
    let exerciseCount: Int
    let intensity: String
    let estimatedDurationMin: Int
    let requiredEquipment: [String]
    let workoutOrder: String
    
    enum CodingKeys: String, CodingKey {
        case id, name, description, intensity
        case programId = "program_id"
        case dayNumber = "day_number"
        case focusAreas = "focus_areas"
        case isRestDay = "is_rest_day"
        case exerciseCount = "exercise_count"
        case estimatedDurationMin = "estimated_duration_min"
        case requiredEquipment = "required_equipment"
        case workoutOrder = "workout_order"
    }
}

/// Represents an exercise within a program day
struct CloudProgramExercise: Codable, Identifiable {
    let id: String
    let programDayId: String
    let exerciseName: String
    let exerciseId: String?
    let exerciseOrder: Int
    let supersetGroup: Int?
    let sets: Int
    let repsMin: Int
    let repsMax: Int
    let repsType: String
    let restSeconds: Int
    let tempo: String?
    let notes: String?
    let isWarmup: Bool
    let isOptional: Bool
    let targetRpe: Int?
    
    enum CodingKeys: String, CodingKey {
        case id, sets, tempo, notes
        case programDayId = "program_day_id"
        case exerciseName = "exercise_name"
        case exerciseId = "exercise_id"
        case exerciseOrder = "exercise_order"
        case supersetGroup = "superset_group"
        case repsMin = "reps_min"
        case repsMax = "reps_max"
        case repsType = "reps_type"
        case restSeconds = "rest_seconds"
        case isWarmup = "is_warmup"
        case isOptional = "is_optional"
        case targetRpe = "target_rpe"
    }
    
    var repRange: String {
        if repsMin == repsMax {
            return "\(repsMin)"
        }
        return "\(repsMin)-\(repsMax)"
    }
}

/// Represents a substitute exercise
struct CloudExerciseSubstitute: Codable, Identifiable {
    let id: String
    let programDayExerciseId: String
    let substituteExerciseName: String
    let substituteExerciseId: String?
    let priority: Int
    let substituteReason: String
    let notes: String?
    
    enum CodingKeys: String, CodingKey {
        case id, priority, notes
        case programDayExerciseId = "program_day_exercise_id"
        case substituteExerciseName = "substitute_exercise_name"
        case substituteExerciseId = "substitute_exercise_id"
        case substituteReason = "substitute_reason"
    }
}

/// User's active program with progress
struct UserActiveProgram: Codable, Identifiable {
    let id: String
    let userId: String
    let programId: String
    let startDate: String
    var currentDay: Int
    var completedDays: [Int]
    var daySwaps: [String: Int]  // Original day -> Swapped day
    var exerciseSwaps: [String: String]  // Day exercise ID -> Substitute exercise name
    let status: String
    var totalWorkoutsCompleted: Int
    var totalXpEarned: Int
    
    enum CodingKeys: String, CodingKey {
        case id, status
        case userId = "user_id"
        case programId = "program_id"
        case startDate = "start_date"
        case currentDay = "current_day"
        case completedDays = "completed_days"
        case daySwaps = "day_swaps"
        case exerciseSwaps = "exercise_swaps"
        case totalWorkoutsCompleted = "total_workouts_completed"
        case totalXpEarned = "total_xp_earned"
    }
}

/// Recommended program with match score
struct RecommendedProgram: Codable, Identifiable {
    let programId: String
    let name: String
    let description: String
    let preview: String
    let durationDays: Int
    let difficulty: String
    let programType: String
    let workoutsPerWeek: Int
    let avgWorkoutDurationMin: Int
    let icon: String
    let color: String
    let benefits: [String]
    let equipment: [String]
    let ratingAvg: Double?
    let ratingCount: Int
    let matchScore: Double
    
    var id: String { programId }
    
    enum CodingKeys: String, CodingKey {
        case programId = "program_id"
        case name = "program_name"
        case description = "program_description"
        case preview = "program_preview"
        case durationDays = "duration_days"
        case difficulty = "difficulty_level"
        case programType = "program_type"
        case workoutsPerWeek = "workouts_per_week"
        case avgWorkoutDurationMin = "avg_workout_duration_min"
        case icon = "program_icon"
        case color = "program_color"
        case benefits = "program_benefits"
        case equipment = "program_equipment"
        case ratingAvg = "rating_avg"
        case ratingCount = "rating_count"
        case matchScore = "match_score"
    }
}

/// Full program with all days and exercises (for caching)
struct FullCloudProgram: Codable {
    let program: CloudProgram
    let days: [FullProgramDay]
}

struct FullProgramDay: Codable {
    let day: CloudProgramDay
    let exercises: [FullProgramExercise]
}

struct FullProgramExercise: Codable {
    let exercise: CloudProgramExercise
    let substitutes: [CloudExerciseSubstitute]?
}

// MARK: - Cloud Program Service

@MainActor
class CloudProgramService: ObservableObject {
    static let shared = CloudProgramService()
    
    private let supabase = SupabaseManager.shared
    private let cacheKey = "cached_active_program"
    
    // Published state
    @Published var allPrograms: [CloudProgram] = []
    @Published var recommendedPrograms: [RecommendedProgram] = []
    @Published var activeProgram: UserActiveProgram?
    @Published var activeProgramDetails: FullCloudProgram?
    @Published var isLoading = false
    @Published var error: String?
    
    // Local cache for offline access
    private var cachedFullProgram: FullCloudProgram?
    
    // Cache for generated exercises by day number - prevents regeneration
    private var generatedExercisesCache: [Int: [ExerciseData]] = [:]
    
    private init() {
        loadCachedProgram()
    }
    
    // MARK: - Exercise Cache Management
    
    /// Get cached exercises for a day (returns nil if not cached)
    func getCachedExercises(for dayNumber: Int) -> [ExerciseData]? {
        return generatedExercisesCache[dayNumber]
    }
    
    /// Cache exercises for a day
    func cacheExercises(_ exercises: [ExerciseData], for dayNumber: Int) {
        generatedExercisesCache[dayNumber] = exercises
        #if DEBUG
        print("💾 Cached \(exercises.count) exercises for day \(dayNumber)")
        #endif
    }
    
    /// Update a single exercise in the cache (for swaps)
    func updateCachedExercise(at index: Int, with newExercise: ExerciseData, for dayNumber: Int) {
        guard var exercises = generatedExercisesCache[dayNumber], index < exercises.count else { return }
        exercises[index] = newExercise
        generatedExercisesCache[dayNumber] = exercises
        #if DEBUG
        print("🔄 Updated exercise at index \(index) for day \(dayNumber)")
        #endif
    }
    
    /// Clear exercise cache (call when program ends or changes)
    func clearExerciseCache() {
        generatedExercisesCache.removeAll()
        #if DEBUG
        print("🗑️ Cleared exercise cache")
        #endif
    }
    
    // MARK: - Public Cache Management
    
    /// Force clear all caches and refresh - call this to fix stale data issues
    func forceRefreshAllData() async {
        #if DEBUG
        print("🔄 Force refreshing all program data...")
        #endif
        
        // Clear all caches
        clearCache()
        cachedFullProgram = nil
        activeProgram = nil
        activeProgramDetails = nil
        allPrograms = []
        recommendedPrograms = []
        
        // Reload from Supabase
        await fetchAllPrograms()
        await loadActiveProgram()
        
        #if DEBUG
        print("✅ Force refresh complete")
        #endif
    }
    
    /// Clear just the active program cache (for when starting a new program)
    func clearActiveProgramCache() {
        cachedFullProgram = nil
        activeProgramDetails = nil
        clearCache()
        #if DEBUG
        print("🗑️ Active program cache cleared")
        #endif
    }
    
    // MARK: - Fetch Programs
    
    /// Fetch all available programs
    func fetchAllPrograms() async {
        isLoading = true
        error = nil
        
        do {
            let response: [CloudProgram] = try await supabase.supabaseClient
                .from("programs")
                .select()
                .eq("is_active", value: true)
                .order("popularity_score", ascending: false)
                .execute()
                .value
            
            allPrograms = response
            #if DEBUG
            print("✅ Fetched \(response.count) programs from cloud")
            #endif
        } catch {
            self.error = "Failed to load programs: \(error.localizedDescription)"
            #if DEBUG
            print("❌ Error fetching programs: \(error)")
            #endif
            
            // Fall back to local programs if cloud fails
            loadLocalFallbackPrograms()
        }
        
        isLoading = false
    }
    
    /// Get recommended programs for current user
    func fetchRecommendedPrograms() async {
        guard let userId = supabase.currentUser?.id else {
            print("⚠️ No authenticated user for recommendations")
            return
        }
        
        isLoading = true
        error = nil
        
        // Get user profile for recommendation parameters
        guard let userProfile = try? await supabase.fetchUserProfile() else {
            print("⚠️ Could not fetch user profile for recommendations")
            isLoading = false
            return
        }
        
        // Map goal to lowercase for matching
        let fitnessGoal = mapGoalToCloudFormat(userProfile.fitnessGoal ?? "general_fitness")
        let experienceLevel = (userProfile.experienceLevel ?? "intermediate").lowercased()
        
        // Get user's equipment from Core Data (since it's not in cloud profile)
        let userEquipment = getUserEquipment()
        
        // Get available days per week from Core Data
        let availableDays = getUserAvailableDays()
        
        do {
            struct RecommendationParams: Encodable {
                let p_user_id: String
                let p_experience_level: String
                let p_fitness_goal: String
                let p_available_equipment: [String]
                let p_days_per_week: Int
                let p_user_age: Int?
                let p_limit: Int
            }
            
            let params = RecommendationParams(
                p_user_id: userId.uuidString,
                p_experience_level: experienceLevel,
                p_fitness_goal: fitnessGoal,
                p_available_equipment: userEquipment,
                p_days_per_week: availableDays,
                p_user_age: nil,
                p_limit: 10
            )
            
            let response: [RecommendedProgram] = try await supabase.supabaseClient
                .rpc("get_recommended_programs", params: params)
                .execute()
                .value
            
            recommendedPrograms = response
            print("✅ Fetched \(response.count) recommended programs")
        } catch {
            self.error = "Failed to get recommendations: \(error.localizedDescription)"
            print("❌ Error fetching recommendations: \(error)")
        }
        
        isLoading = false
    }
    
    // MARK: - Active Program Management
    
    /// Start a new program
    func startProgram(_ programId: String) async -> Bool {
        guard let userId = supabase.currentUser?.id else {
            print("⚠️ No authenticated user to start program")
            return false
        }
        
        isLoading = true
        
        // Clear old cache first to ensure fresh data
        clearActiveProgramCache()
        clearExerciseCache() // Clear exercise cache when starting new program
        
        do {
            // First, cancel any existing active program
            try await supabase.supabaseClient
                .from("user_active_programs")
                .update(["status": "cancelled"])
                .eq("user_id", value: userId.uuidString)
                .eq("status", value: "active")
                .execute()
            
            // Create new active program
            struct NewActiveProgram: Encodable {
                let user_id: String
                let program_id: String
                let current_day: Int
                let completed_days: [Int]
                let day_swaps: [String: Int]
                let exercise_swaps: [String: String]
                let status: String
            }
            
            let newProgram = NewActiveProgram(
                user_id: userId.uuidString,
                program_id: programId,
                current_day: 1,
                completed_days: [],
                day_swaps: [:],
                exercise_swaps: [:],
                status: "active"
            )
            
            let response: [UserActiveProgram] = try await supabase.supabaseClient
                .from("user_active_programs")
                .insert(newProgram)
                .select()
                .execute()
                .value
            
            if let active = response.first {
                activeProgram = active
                
                // Fetch and cache the full program details
                await fetchAndCacheFullProgram(programId: programId)
                
                // 🚀 Smart prefetch: Preload videos for first few days of new program
                if let programDetails = activeProgramDetails {
                    VideoStreamingService.shared.prefetchActiveProgramVideos(
                        program: programDetails,
                        currentDay: 1
                    )
                }
                
                print("✅ Started program: \(programId)")
                isLoading = false
                return true
            }
        } catch {
            self.error = "Failed to start program: \(error.localizedDescription)"
            print("❌ Error starting program: \(error)")
        }
        
        isLoading = false
        return false
    }
    
    /// Load user's active program
    func loadActiveProgram() async {
        guard let userId = supabase.currentUser?.id else {
            print("⚠️ No authenticated user")
            return
        }
        
        do {
            let response: [UserActiveProgram] = try await supabase.supabaseClient
                .from("user_active_programs")
                .select()
                .eq("user_id", value: userId.uuidString)
                .eq("status", value: "active")
                .limit(1)
                .execute()
                .value
            
            if let active = response.first {
                activeProgram = active
                print("✅ Found active program: \(active.programId)")
                
                // Check if cache is valid (has days)
                let cacheIsValid = cachedFullProgram != nil && 
                                   cachedFullProgram?.program.id == active.programId &&
                                   (cachedFullProgram?.days.count ?? 0) > 0
                
                if cacheIsValid {
                    activeProgramDetails = cachedFullProgram
                    print("📦 Using cached program details (\(cachedFullProgram?.days.count ?? 0) days)")
                } else {
                    // Cache is invalid or empty - fetch fresh
                    if cachedFullProgram != nil && (cachedFullProgram?.days.count ?? 0) == 0 {
                        print("⚠️ Cache has 0 days - clearing and re-fetching")
                        clearCache()
                        cachedFullProgram = nil
                    }
                    print("📥 Fetching full program details...")
                    await fetchAndCacheFullProgram(programId: active.programId)
                }
                
                print("✅ Loaded active program")
                print("   activeProgramDetails: \(activeProgramDetails != nil ? "✅ loaded" : "❌ nil")")
                print("   days count: \(activeProgramDetails?.days.count ?? 0)")
                
                // 🚀 Smart prefetch: Preload videos for today + next 2 days
                if let programDetails = activeProgramDetails {
                    VideoStreamingService.shared.prefetchActiveProgramVideos(
                        program: programDetails,
                        currentDay: active.currentDay
                    )
                }
            } else {
                activeProgram = nil
                activeProgramDetails = nil
                print("⚠️ No active program found for user")
            }
        } catch {
            print("❌ Error loading active program: \(error)")
            
            // Try to use cached data
            if let cached = cachedFullProgram {
                activeProgramDetails = cached
                print("📦 Using cached program data")
            }
        }
    }
    
    /// Complete a workout day
    @MainActor
    func completeDay(_ dayNumber: Int, xpEarned: Int = 0) async {
        guard var active = activeProgram else { 
            print("⚠️ No active program to complete day for")
            return 
        }
        
        print("📅 Completing day \(dayNumber) for program...")
        
        // Update local state
        if !active.completedDays.contains(dayNumber) {
            active.completedDays.append(dayNumber)
        }
        active.totalWorkoutsCompleted += 1
        active.totalXpEarned += xpEarned
        
        // Advance to next day
        if let details = activeProgramDetails {
            let nextDay = dayNumber + 1
            if nextDay <= details.program.durationDays {
                active.currentDay = nextDay
            }
        }
        
        // Update published property on main thread (triggers UI update)
        self.activeProgram = active
        print("✅ Local state updated - completed days: \(active.completedDays)")
        
        // Sync to cloud
        do {
            struct DayCompletionUpdate: Encodable {
                let completed_days: [Int]
                let current_day: Int
                let total_workouts_completed: Int
                let total_xp_earned: Int
            }
            
            let update = DayCompletionUpdate(
                completed_days: active.completedDays,
                current_day: active.currentDay,
                total_workouts_completed: active.totalWorkoutsCompleted,
                total_xp_earned: active.totalXpEarned
            )
            
            try await supabase.supabaseClient
                .from("user_active_programs")
                .update(update)
                .eq("id", value: active.id)
                .execute()
            
            print("☁️ Day \(dayNumber) synced to cloud")
        } catch {
            print("❌ Error syncing day completion: \(error)")
        }
        
        // Update cache
        saveProgramToCache()
        print("💾 Program cache updated")
        
        // Check if program is complete
        await checkProgramCompletion()
    }
    
    /// Swap two days in the program
    func swapDays(originalDay: Int, newDay: Int) async {
        guard var active = activeProgram else { return }
        
        // Update swaps
        active.daySwaps["\(originalDay)"] = newDay
        active.daySwaps["\(newDay)"] = originalDay
        
        activeProgram = active
        
        // Clear exercise cache for both days so exercises regenerate with correct focus
        generatedExercisesCache.removeValue(forKey: originalDay)
        generatedExercisesCache.removeValue(forKey: newDay)
        print("🗑️ Cleared exercise cache for days \(originalDay) and \(newDay)")
        
        // Sync to cloud
        do {
            struct DaySwapUpdate: Encodable {
                let day_swaps: [String: Int]
            }
            
            try await supabase.supabaseClient
                .from("user_active_programs")
                .update(DaySwapUpdate(day_swaps: active.daySwaps))
                .eq("id", value: active.id)
                .execute()
            
            print("✅ Swapped days \(originalDay) and \(newDay)")
        } catch {
            print("❌ Error syncing day swap: \(error)")
        }
        
        saveProgramToCache()
    }
    
    /// Swap an exercise for a substitute
    func swapExercise(exerciseId: String, substituteExerciseName: String) async {
        guard var active = activeProgram else { return }
        
        active.exerciseSwaps[exerciseId] = substituteExerciseName
        activeProgram = active
        
        // Sync to cloud
        do {
            struct ExerciseSwapUpdate: Encodable {
                let exercise_swaps: [String: String]
            }
            
            try await supabase.supabaseClient
                .from("user_active_programs")
                .update(ExerciseSwapUpdate(exercise_swaps: active.exerciseSwaps))
                .eq("id", value: active.id)
                .execute()
            
            print("✅ Swapped exercise \(exerciseId) for \(substituteExerciseName)")
        } catch {
            print("❌ Error syncing exercise swap: \(error)")
        }
        
        saveProgramToCache()
    }
    
    /// Cancel the active program and save progress history
    func cancelProgram() async {
        guard let active = activeProgram else { return }
        
        do {
            // Save program history before cancelling
            await saveProgramHistory(active, status: "cancelled")
            
            try await supabase.supabaseClient
                .from("user_active_programs")
                .update(["status": "cancelled"])
                .eq("id", value: active.id)
                .execute()
            
            // Clear all local data
            activeProgram = nil
            activeProgramDetails = nil
            cachedFullProgram = nil
            clearCache()
            clearExerciseCache()
            
            print("✅ Program cancelled and history saved")
        } catch {
            print("❌ Error cancelling program: \(error)")
        }
    }
    
    /// Complete the active program and save full history
    func completeProgram() async {
        guard let active = activeProgram else { return }
        
        do {
            // Save program history with completed status
            await saveProgramHistory(active, status: "completed")
            
            try await supabase.supabaseClient
                .from("user_active_programs")
                .update(["status": "completed"])
                .eq("id", value: active.id)
                .execute()
            
            // Clear all local data - program no longer needs to be stored locally
            activeProgram = nil
            activeProgramDetails = nil
            cachedFullProgram = nil
            clearCache()
            clearExerciseCache()
            
            print("✅ Program completed and history saved")
        } catch {
            print("❌ Error completing program: \(error)")
        }
    }
    
    /// Save program progress history to user's cloud profile
    private func saveProgramHistory(_ program: UserActiveProgram, status: String) async {
        guard let userId = supabase.currentUser?.id else { return }
        
        // Calculate statistics
        let completionPercentage: Double
        if let details = activeProgramDetails {
            let totalWorkoutDays = details.days.filter { !$0.day.isRestDay }.count
            completionPercentage = totalWorkoutDays > 0 ? Double(program.completedDays.count) / Double(totalWorkoutDays) * 100 : 0
        } else {
            completionPercentage = 0
        }
        
        do {
            struct ProgramHistoryEntry: Encodable {
                let user_id: String
                let program_id: String
                let program_name: String
                let start_date: String
                let end_date: String
                let status: String
                let days_completed: Int
                let total_workouts: Int
                let total_xp_earned: Int
                let completion_percentage: Double
            }
            
            let entry = ProgramHistoryEntry(
                user_id: userId.uuidString,
                program_id: program.programId,
                program_name: activeProgramDetails?.program.name ?? "Unknown Program",
                start_date: program.startDate,
                end_date: ISO8601DateFormatter().string(from: Date()),
                status: status,
                days_completed: program.completedDays.count,
                total_workouts: program.totalWorkoutsCompleted,
                total_xp_earned: program.totalXpEarned,
                completion_percentage: completionPercentage
            )
            
            try await supabase.supabaseClient
                .from("program_history")
                .insert(entry)
                .execute()
            
            print("📊 Program history saved: \(program.completedDays.count) days, \(Int(completionPercentage))% complete")
        } catch {
            print("⚠️ Could not save program history: \(error)")
            // Don't fail the entire operation if history save fails
        }
    }
    
    /// Check if program is complete (all workout days done)
    func checkProgramCompletion() async {
        guard let active = activeProgram,
              let details = activeProgramDetails else { return }
        
        let totalWorkoutDays = details.days.filter { !$0.day.isRestDay }.count
        let completedWorkoutDays = active.completedDays.count
        
        if completedWorkoutDays >= totalWorkoutDays {
            print("🎉 Program complete! All \(totalWorkoutDays) workout days finished!")
            await completeProgram()
        }
    }
    
    // MARK: - Full Program Fetch & Cache
    
    /// Fetch complete program details and cache locally
    private func fetchAndCacheFullProgram(programId: String) async {
        print("🔄 fetchAndCacheFullProgram started for: \(programId)")
        
        do {
            // Fetch program
            print("   Fetching program from database...")
            let programs: [CloudProgram] = try await supabase.supabaseClient
                .from("programs")
                .select()
                .eq("id", value: programId)
                .limit(1)
                .execute()
                .value
            
            print("   Found \(programs.count) programs")
            
            guard let program = programs.first else {
                print("❌ Program not found: \(programId)")
                return
            }
            
            print("   ✅ Program: \(program.name), type: \(program.programType), duration: \(program.durationDays) days")
            
            // Fetch days
            print("   Fetching days from database...")
            var days: [CloudProgramDay] = try await supabase.supabaseClient
                .from("program_days")
                .select()
                .eq("program_id", value: programId)
                .order("day_number", ascending: true)
                .execute()
                .value
            
            print("   Found \(days.count) days in database")
            
            // If no days found in database, generate them dynamically
            if days.isEmpty {
                print("⚠️ No days found in database for \(programId), generating dynamically")
                days = generateDynamicDays(for: program)
                print("   Generated \(days.count) dynamic days")
            }
            
            // Fetch exercises for all days
            var fullDays: [FullProgramDay] = []
            
            for day in days {
                var fullExercises: [FullProgramExercise] = []
                
                // Only fetch from database if day has a real ID (not generated)
                if !day.id.starts(with: "generated_") {
                    let exercises: [CloudProgramExercise] = try await supabase.supabaseClient
                        .from("program_day_exercises")
                        .select()
                        .eq("program_day_id", value: day.id)
                        .order("exercise_order", ascending: true)
                        .execute()
                        .value
                    
                    // Fetch substitutes for each exercise
                    for exercise in exercises {
                        let substitutes: [CloudExerciseSubstitute] = try await supabase.supabaseClient
                            .from("program_exercise_substitutes")
                            .select()
                            .eq("program_day_exercise_id", value: exercise.id)
                            .order("priority", ascending: true)
                            .execute()
                            .value
                        
                        fullExercises.append(FullProgramExercise(
                            exercise: exercise,
                            substitutes: substitutes.isEmpty ? nil : substitutes
                        ))
                    }
                }
                
                fullDays.append(FullProgramDay(day: day, exercises: fullExercises))
            }
            
            let fullProgram = FullCloudProgram(program: program, days: fullDays)
            cachedFullProgram = fullProgram
            activeProgramDetails = fullProgram
            
            // Save to disk for offline access
            saveProgramToCache()
            
            print("✅ Fetched and cached full program: \(program.name)")
            print("   - \(days.count) days")
            print("   - \(fullDays.flatMap { $0.exercises }.count) predefined exercises")
            
        } catch {
            print("❌ Error fetching full program: \(error)")
        }
    }
    
    /// Generate days dynamically based on program settings
    private func generateDynamicDays(for program: CloudProgram) -> [CloudProgramDay] {
        var days: [CloudProgramDay] = []
        let restDays = Set(program.restDays)
        
        // Analyze program to determine focus
        let programFocus = analyzeProgramFocus(program)
        print("📊 Program analysis for '\(program.name)':")
        print("   Focus type: \(programFocus.type)")
        print("   Primary muscles: \(programFocus.primaryMuscles)")
        
        // Get workout patterns that match the program's focus
        let workoutPatterns = getSmartWorkoutPatterns(for: program, focus: programFocus)
        
        for dayNum in 1...program.durationDays {
            let isRest = restDays.contains(dayNum)
            let patternIndex = (dayNum - 1) % workoutPatterns.count
            let pattern = isRest ? ("Rest Day", ["full body"], "light") : workoutPatterns[patternIndex]
            
            let day = CloudProgramDay(
                id: "generated_\(program.id)_day_\(dayNum)",
                programId: program.id,
                dayNumber: dayNum,
                name: pattern.0,
                description: isRest ? "Recovery and rest" : "Day \(dayNum) - \(pattern.0)",
                focusAreas: pattern.1,
                isRestDay: isRest,
                exerciseCount: isRest ? 0 : (program.difficulty == "advanced" ? 7 : (program.difficulty == "intermediate" ? 6 : 5)),
                intensity: pattern.2,
                estimatedDurationMin: isRest ? 0 : program.avgWorkoutDurationMin,
                requiredEquipment: program.equipment,
                workoutOrder: "standard"
            )
            days.append(day)
        }
        
        return days
    }
    
    /// Program focus analysis result
    private struct ProgramFocus {
        let type: ProgramFocusType
        let primaryMuscles: [String]
        let secondaryMuscles: [String]
    }
    
    private enum ProgramFocusType {
        case upperLower      // Upper/Lower split
        case pushPullLegs    // PPL split
        case fullBody        // Full body workouts
        case pushPull        // Push/Pull split
        case fatLoss         // Fat loss / cardio focused
        case strength        // Strength / powerlifting
        case muscle          // Hypertrophy / bodybuilding
        case athletic        // Athletic / functional
        case maintenance     // Maintenance / recovery
    }
    
    /// Analyze program name, type, and goals to determine focus
    /// NOTE: We use BALANCED splits, not single-muscle programs (bad for recovery)
    private func analyzeProgramFocus(_ program: CloudProgram) -> ProgramFocus {
        let name = program.name.lowercased()
        let type = program.programType.lowercased()
        let goals = program.targetGoals.map { $0.lowercased() }
        
        // UPPER/LOWER SPLIT - most versatile and recovery-friendly
        if name.contains("upper") && name.contains("lower") || type.contains("upper_lower") {
            return ProgramFocus(
                type: .upperLower,
                primaryMuscles: ["chest", "back", "shoulders", "legs", "glutes"],
                secondaryMuscles: ["arms", "core"]
            )
        }
        
        // PUSH/PULL/LEGS - classic bodybuilding split
        if name.contains("ppl") || (name.contains("push") && name.contains("pull") && name.contains("leg")) || type.contains("push_pull_legs") {
            return ProgramFocus(
                type: .pushPullLegs,
                primaryMuscles: ["chest", "back", "legs", "shoulders"],
                secondaryMuscles: ["arms", "core"]
            )
        }
        
        // PUSH/PULL split (no dedicated leg day)
        if (name.contains("push") && name.contains("pull")) || type.contains("push_pull") {
            return ProgramFocus(
                type: .pushPull,
                primaryMuscles: ["chest", "back", "shoulders"],
                secondaryMuscles: ["arms", "legs", "core"]
            )
        }
        
        // FULL BODY - great for beginners and busy schedules
        if name.contains("full body") || name.contains("full-body") || name.contains("fullbody") || 
           name.contains("total body") || type.contains("full_body") {
            return ProgramFocus(
                type: .fullBody,
                primaryMuscles: ["chest", "back", "legs", "shoulders"],
                secondaryMuscles: ["arms", "core"]
            )
        }
        
        // FAT LOSS / CARDIO focused
        if type.contains("fat") || type.contains("cut") || type.contains("shred") || 
           name.contains("fat") || name.contains("burn") || name.contains("shred") || 
           name.contains("lean") || name.contains("cut") || name.contains("metcon") || name.contains("hiit") {
            return ProgramFocus(
                type: .fatLoss,
                primaryMuscles: ["full body"],
                secondaryMuscles: ["core"]
            )
        }
        
        // STRENGTH / POWERLIFTING focused
        if type.contains("strength") || type.contains("power") || 
           name.contains("strength") || name.contains("power") || name.contains("strong") {
            return ProgramFocus(
                type: .strength,
                primaryMuscles: ["chest", "back", "legs"],
                secondaryMuscles: ["shoulders", "arms", "core"]
            )
        }
        
        // MUSCLE / HYPERTROPHY focused
        if type.contains("bulk") || type.contains("muscle") || type.contains("hypertrophy") ||
           name.contains("muscle") || name.contains("mass") || name.contains("hypertrophy") || 
           name.contains("bulk") || name.contains("size") || name.contains("build") {
            return ProgramFocus(
                type: .muscle,
                primaryMuscles: ["chest", "back", "legs", "shoulders"],
                secondaryMuscles: ["arms", "core"]
            )
        }
        
        // ATHLETIC / FUNCTIONAL
        if type.contains("athletic") || type.contains("functional") || type.contains("sport") ||
           name.contains("athletic") || name.contains("functional") || name.contains("sport") ||
           name.contains("performance") || name.contains("agility") {
            return ProgramFocus(
                type: .athletic,
                primaryMuscles: ["full body", "legs", "core"],
                secondaryMuscles: ["shoulders", "back"]
            )
        }
        
        // MAINTENANCE / RECOVERY / DELOAD
        if type.contains("maintenance") || type.contains("deload") || type.contains("recovery") ||
           name.contains("maintain") || name.contains("deload") || name.contains("recovery") ||
           name.contains("easy") || name.contains("light") {
            return ProgramFocus(
                type: .maintenance,
                primaryMuscles: ["full body"],
                secondaryMuscles: ["core"]
            )
        }
        
        // DEFAULT: Full body for beginners (safest, most balanced)
        if program.difficulty == "beginner" {
            return ProgramFocus(
                type: .fullBody,
                primaryMuscles: ["chest", "back", "legs", "shoulders"],
                secondaryMuscles: ["arms", "core"]
            )
        }
        
        // DEFAULT: Upper/Lower for intermediate+ (good balance of volume and recovery)
        return ProgramFocus(
            type: .upperLower,
            primaryMuscles: ["chest", "back", "shoulders", "legs", "glutes"],
            secondaryMuscles: ["arms", "core"]
        )
    }
    
    /// Get workout patterns that match the program's analyzed focus
    /// All patterns are BALANCED - no single-muscle-group days that would cause overtraining
    private func getSmartWorkoutPatterns(for program: CloudProgram, focus: ProgramFocus) -> [(String, [String], String)] {
        // Returns: (dayName, focusAreas, intensity)
        
        switch focus.type {
        case .upperLower:
            // Classic Upper/Lower - train each area 2x per week
            return [
                ("Upper Body Push", ["chest", "shoulders", "triceps"], "heavy"),
                ("Lower Body Strength", ["legs", "glutes", "hamstrings"], "heavy"),
                ("Upper Body Pull", ["back", "biceps", "rear delts"], "heavy"),
                ("Lower Body Power", ["legs", "glutes", "calves"], "moderate"),
                ("Upper Body Volume", ["chest", "back", "shoulders"], "moderate"),
                ("Lower Body Volume", ["legs", "glutes", "core"], "moderate")
            ]
            
        case .pushPullLegs:
            // PPL - each muscle group hit with optimal frequency
            return [
                ("Push Day", ["chest", "shoulders", "triceps"], "heavy"),
                ("Pull Day", ["back", "biceps", "rear delts"], "heavy"),
                ("Leg Day", ["legs", "glutes", "hamstrings", "calves"], "heavy"),
                ("Push Volume", ["chest", "shoulders", "triceps"], "moderate"),
                ("Pull Volume", ["back", "biceps"], "moderate"),
                ("Legs & Core", ["legs", "glutes", "core"], "moderate")
            ]
            
        case .pushPull:
            // Push/Pull with legs included in each day
            return [
                ("Push + Quads", ["chest", "shoulders", "triceps", "quadriceps"], "heavy"),
                ("Pull + Hamstrings", ["back", "biceps", "hamstrings", "glutes"], "heavy"),
                ("Push Hypertrophy", ["chest", "shoulders", "triceps"], "moderate"),
                ("Pull Hypertrophy", ["back", "biceps", "rear delts"], "moderate"),
                ("Push Power", ["chest", "shoulders", "legs"], "heavy"),
                ("Pull Power", ["back", "biceps", "glutes"], "heavy")
            ]
            
        case .fullBody:
            // Full body - perfect for beginners, 3-4x per week
            return [
                ("Full Body Strength", ["chest", "back", "legs", "shoulders"], "heavy"),
                ("Full Body Hypertrophy", ["chest", "back", "legs", "arms"], "moderate"),
                ("Full Body Power", ["legs", "back", "shoulders", "core"], "heavy"),
                ("Full Body Conditioning", ["full body", "core"], "moderate"),
                ("Full Body Balance", ["chest", "back", "legs", "shoulders"], "moderate"),
                ("Full Body Finisher", ["full body", "arms", "core"], "moderate")
            ]
            
        case .fatLoss:
            // Fat loss - metabolic training with full body movements
            return [
                ("Metabolic Full Body", ["full body", "core"], "moderate"),
                ("Lower Body Burn", ["legs", "glutes", "core"], "moderate"),
                ("Upper Body Torch", ["chest", "back", "shoulders", "arms"], "moderate"),
                ("HIIT Circuit", ["full body"], "heavy"),
                ("Core & Cardio", ["core", "abs", "full body"], "moderate"),
                ("Total Body Blast", ["legs", "chest", "back", "shoulders"], "heavy")
            ]
            
        case .strength:
            // Strength focus - compound lifts, lower rep ranges
            return [
                ("Squat Focus", ["legs", "glutes", "core"], "heavy"),
                ("Bench & Press", ["chest", "shoulders", "triceps"], "heavy"),
                ("Deadlift & Rows", ["back", "hamstrings", "biceps"], "heavy"),
                ("Overhead Strength", ["shoulders", "triceps", "core"], "heavy"),
                ("Lower Body Power", ["legs", "glutes", "hamstrings"], "heavy"),
                ("Upper Body Power", ["chest", "back", "shoulders"], "heavy")
            ]
            
        case .muscle:
            // Hypertrophy focus - moderate reps, higher volume
            return [
                ("Chest & Back", ["chest", "back"], "heavy"),
                ("Legs & Glutes", ["legs", "glutes", "hamstrings"], "heavy"),
                ("Shoulders & Arms", ["shoulders", "biceps", "triceps"], "moderate"),
                ("Back & Biceps", ["back", "biceps", "rear delts"], "heavy"),
                ("Chest & Triceps", ["chest", "triceps", "shoulders"], "moderate"),
                ("Legs & Core", ["legs", "glutes", "core", "calves"], "moderate")
            ]
            
        case .athletic:
            // Athletic/functional - power, agility, conditioning
            return [
                ("Power Day", ["legs", "back", "shoulders"], "heavy"),
                ("Conditioning", ["full body", "core"], "moderate"),
                ("Upper Body Athleticism", ["chest", "back", "shoulders", "core"], "moderate"),
                ("Lower Body Explosiveness", ["legs", "glutes", "core"], "heavy"),
                ("Full Body Functional", ["full body"], "moderate"),
                ("Sport Performance", ["legs", "core", "shoulders"], "heavy")
            ]
            
        case .maintenance:
            // Maintenance/deload - lower intensity, maintain gains
            return [
                ("Easy Full Body", ["chest", "back", "legs", "shoulders"], "light"),
                ("Light Upper", ["chest", "back", "shoulders"], "light"),
                ("Light Lower", ["legs", "glutes", "core"], "light"),
                ("Active Recovery", ["full body"], "light"),
                ("Mobility & Core", ["core", "full body"], "light"),
                ("Maintenance Full Body", ["chest", "back", "legs"], "moderate")
            ]
        }
    }
    
    // MARK: - Local Caching
    
    private func saveProgramToCache() {
        guard let program = cachedFullProgram else { return }
        
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(program)
            UserDefaults.standard.set(data, forKey: cacheKey)
            
            // Also save active program state
            if let active = activeProgram {
                let activeData = try encoder.encode(active)
                UserDefaults.standard.set(activeData, forKey: "\(cacheKey)_active")
            }
            
            print("💾 Program cached locally")
        } catch {
            print("❌ Error caching program: \(error)")
        }
    }
    
    private func loadCachedProgram() {
        if let data = UserDefaults.standard.data(forKey: cacheKey) {
            do {
                let decoder = JSONDecoder()
                let cached = try decoder.decode(FullCloudProgram.self, from: data)
                
                // Validate cache - must have days
                if cached.days.isEmpty {
                    print("⚠️ Cached program has 0 days - discarding invalid cache")
                    clearCache()
                    return
                }
                
                cachedFullProgram = cached
                activeProgramDetails = cached
                print("📦 Loaded cached program: \(cached.program.name) with \(cached.days.count) days")
            } catch {
                print("❌ Error loading cached program: \(error)")
                clearCache()
            }
        }
        
        if let activeData = UserDefaults.standard.data(forKey: "\(cacheKey)_active") {
            do {
                let decoder = JSONDecoder()
                activeProgram = try decoder.decode(UserActiveProgram.self, from: activeData)
                print("📦 Loaded cached active program state")
            } catch {
                print("❌ Error loading cached active program: \(error)")
            }
        }
    }
    
    private func clearCache() {
        UserDefaults.standard.removeObject(forKey: cacheKey)
        UserDefaults.standard.removeObject(forKey: "\(cacheKey)_active")
        print("🗑️ Program cache cleared")
    }
    
    // MARK: - Helper Methods
    
    /// Get the actual day to show (accounting for swaps)
    func getActualDay(_ dayNumber: Int) -> Int {
        guard let active = activeProgram else { return dayNumber }
        return active.daySwaps["\(dayNumber)"] ?? dayNumber
    }
    
    /// Get the day details for a given day number
    /// OPTIMIZED: Reduced logging to prevent console spam during rapid view updates
    func getDayDetails(for dayNumber: Int) -> FullProgramDay? {
        let actualDay = getActualDay(dayNumber)
        return activeProgramDetails?.days.first { $0.day.dayNumber == actualDay }
    }
    
    /// Debug version with full logging (call only when debugging)
    func getDayDetailsDebug(for dayNumber: Int) -> FullProgramDay? {
        let actualDay = getActualDay(dayNumber)
        print("🔍 getDayDetails called for day \(dayNumber) (actual: \(actualDay))")
        print("   activeProgramDetails: \(activeProgramDetails != nil ? "exists" : "nil")")
        print("   days count: \(activeProgramDetails?.days.count ?? 0)")
        if let details = activeProgramDetails {
            print("   available days: \(details.days.map { $0.day.dayNumber })")
        }
        let result = activeProgramDetails?.days.first { $0.day.dayNumber == actualDay }
        print("   result: \(result != nil ? "found" : "nil")")
        return result
    }
    
    /// Get exercise name (accounting for swaps)
    func getExerciseName(for exercise: CloudProgramExercise) -> String {
        guard let active = activeProgram else { return exercise.exerciseName }
        return active.exerciseSwaps[exercise.id] ?? exercise.exerciseName
    }
    
    /// Map onboarding goal to cloud format
    private func mapGoalToCloudFormat(_ goal: String) -> String {
        switch goal.lowercased() {
        case "strength": return "strength"
        case "bulk", "build muscle": return "bulk"
        case "cut", "lose fat", "lose weight": return "cut"
        case "tone": return "tone"
        case "cardio", "endurance": return "cardio"
        default: return "general_fitness"
        }
    }
    
    /// Get user equipment from Core Data
    private func getUserEquipment() -> [String] {
        let viewContext = PersistenceController.shared.container.viewContext
        let request: NSFetchRequest<User> = User.fetchRequest()
        request.fetchLimit = 1
        
        do {
            let users = try viewContext.fetch(request)
            if let user = users.first, let equipment = user.equipment as? [String] {
                return equipment.map { $0.lowercased() }
            }
        } catch {
            print("❌ Error fetching user equipment: \(error)")
        }
        
        return ["bodyweight"]
    }
    
    /// Get user's available days per week from Core Data
    private func getUserAvailableDays() -> Int {
        let viewContext = PersistenceController.shared.container.viewContext
        let request: NSFetchRequest<User> = User.fetchRequest()
        request.fetchLimit = 1
        
        do {
            let users = try viewContext.fetch(request)
            if let user = users.first {
                return Int(user.availableDays)
            }
        } catch {
            print("❌ Error fetching user available days: \(error)")
        }
        
        return 3
    }
    
    /// Load local fallback programs when cloud is unavailable
    private func loadLocalFallbackPrograms() {
        // Convert existing WorkoutProgramEngine programs to CloudProgram format
        let localPrograms = WorkoutProgramEngine.shared.getAllPrograms()
        allPrograms = localPrograms.map { program in
            CloudProgram(
                id: program.id,
                name: program.name,
                description: program.description,
                preview: program.preview,
                durationDays: program.duration,
                difficulty: program.difficulty.rawValue.lowercased(),
                programType: program.focus.rawValue.lowercased().replacingOccurrences(of: " ", with: "_"),
                targetGoals: ["general_fitness"],
                requiredExperience: program.difficulty.rawValue.lowercased(),
                requiredEquipment: program.equipment.map { $0.lowercased() },
                minDaysPerWeek: program.workoutsPerWeek - 1,
                maxDaysPerWeek: program.workoutsPerWeek + 1,
                workoutsPerWeek: program.workoutsPerWeek,
                avgWorkoutDurationMin: program.estimatedTimePerWorkout,
                restDays: Array(program.restDays),
                icon: program.icon,
                color: program.color,
                benefits: program.benefits,
                equipment: program.equipment,
                popularityScore: 50,
                ratingAvg: nil,
                ratingCount: 0,
                isFeatured: false
            )
        }
        print("📦 Loaded \(allPrograms.count) local fallback programs")
    }
    
    // MARK: - Generate Exercises for Day
    
    /// Generate exercises for a program day - ALWAYS returns exercises, never empty
    /// Uses SMART distribution to ensure exercises match the day's focus
    func generateExercisesForDay(_ day: FullProgramDay) -> [ExerciseData] {
        print("🏋️ Smart generating exercises for: \(day.day.name)")
        print("   Focus areas: \(day.day.focusAreas)")
        print("   Equipment: \(day.day.requiredEquipment)")
        
        // Skip rest days
        if day.day.isRestDay {
            print("   📅 Rest day - no exercises needed")
            return []
        }
        
        let targetCount = max(day.day.exerciseCount, 5) // Minimum 5 exercises
        let allExercises = ComprehensiveExerciseDatabase.exercises
        let mappedEquipment = Set(mapEquipment(day.day.requiredEquipment))
        
        // If day has predefined exercises, find them in the database
        if !day.exercises.isEmpty {
            let exercises = day.exercises.compactMap { fullExercise -> ExerciseData? in
                let exerciseName = getExerciseName(for: fullExercise.exercise)
                if let match = allExercises.first(where: { $0.name.lowercased() == exerciseName.lowercased() }) {
                    return match
                }
                if let match = allExercises.first(where: { $0.name.lowercased().contains(exerciseName.lowercased()) }) {
                    return match
                }
                return nil
            }
            
            if !exercises.isEmpty {
                print("   ✅ Found \(exercises.count) predefined exercises")
                return exercises
            }
        }
        
        // SMART GENERATION: Analyze day name and focus to create balanced workout
        let dayType = analyzeDayType(dayName: day.day.name, focusAreas: day.day.focusAreas)
        print("   📊 Day type analysis: \(dayType.name)")
        print("   📊 Muscle distribution: \(dayType.muscleDistribution)")
        
        // Generate exercises with BALANCED distribution across muscle groups
        var selectedExercises: [ExerciseData] = []
        var usedExerciseNames: Set<String> = []
        
        for (muscleGroup, count) in dayType.muscleDistribution {
            let exercisesForMuscle = selectExercisesForMuscle(
                muscleGroup: muscleGroup,
                count: count,
                equipment: mappedEquipment,
                allExercises: allExercises,
                usedNames: usedExerciseNames
            )
            selectedExercises.append(contentsOf: exercisesForMuscle)
            exercisesForMuscle.forEach { usedExerciseNames.insert($0.name) }
        }
        
        // If we don't have enough, fill with exercises matching any focus area
        let focusMuscles = Set(dayType.muscleDistribution.map { $0.0 })
        while selectedExercises.count < targetCount {
            if let exercise = allExercises.shuffled().first(where: { ex in
                !usedExerciseNames.contains(ex.name) &&
                (focusMuscles.contains(ex.category.lowercased()) ||
                 focusMuscles.contains(ex.primaryMuscle.lowercased()) ||
                 focusMuscles.contains(where: { muscle in
                     ex.primaryBodyRegion.lowercased().contains(muscle) ||
                     ex.secondaryMuscles.contains(where: { $0.lowercased().contains(muscle) })
                 }))
            }) {
                selectedExercises.append(exercise)
                usedExerciseNames.insert(exercise.name)
            } else {
                break
            }
        }
        
        // Emergency fallback - still try to match the day type
        if selectedExercises.isEmpty {
            print("   🆘 Emergency fallback - matching day type: \(dayType.name)")
            let targetCategories = focusMuscles
            let emergencyExercises = allExercises.filter { ex in
                targetCategories.contains(ex.category.lowercased()) ||
                targetCategories.contains(ex.primaryMuscle.lowercased())
            }.shuffled()
            
            if !emergencyExercises.isEmpty {
                selectedExercises = Array(emergencyExercises.prefix(targetCount))
            } else {
                // Absolute last resort
                selectedExercises = Array(allExercises.shuffled().prefix(targetCount))
            }
        }
        
        print("   ✅ Generated \(selectedExercises.count) exercises with smart distribution")
        for ex in selectedExercises {
            print("      - \(ex.name) (\(ex.category))")
        }
        
        return selectedExercises
    }
    
    /// Analyze day type based on name and focus areas
    private struct DayTypeAnalysis {
        let name: String
        let muscleDistribution: [(String, Int)] // (muscle group, number of exercises)
    }
    
    private func analyzeDayType(dayName: String, focusAreas: [String]) -> DayTypeAnalysis {
        let name = dayName.lowercased()
        let focus = focusAreas.map { $0.lowercased() }
        
        // FULL BODY - distribute evenly across all major groups with compound exercises first
        if name.contains("full body") || focus.contains("full body") {
            return DayTypeAnalysis(name: "Full Body", muscleDistribution: [
                ("compound", 2),   // Prioritize compound exercises like deadlifts, squats, burpees
                ("chest", 1),
                ("back", 1),
                ("legs", 1),
                ("shoulders", 1),
                ("arms", 1),
                ("core", 1)
            ])
        }
        
        // PUSH DAY - chest, shoulders, triceps
        if name.contains("push") {
            return DayTypeAnalysis(name: "Push", muscleDistribution: [
                ("chest", 2),
                ("shoulders", 2),
                ("arms", 1)  // triceps
            ])
        }
        
        // PULL DAY - back, biceps
        if name.contains("pull") {
            return DayTypeAnalysis(name: "Pull", muscleDistribution: [
                ("back", 3),
                ("arms", 2)  // biceps
            ])
        }
        
        // LEG DAY
        if name.contains("leg") || name.contains("lower") || focus.contains("legs") {
            return DayTypeAnalysis(name: "Legs", muscleDistribution: [
                ("legs", 3),  // quads/general
                ("legs", 2)   // hamstrings/glutes (will get different exercises due to variety)
            ])
        }
        
        // UPPER BODY
        if name.contains("upper") {
            return DayTypeAnalysis(name: "Upper Body", muscleDistribution: [
                ("chest", 2),
                ("back", 2),
                ("shoulders", 1)
            ])
        }
        
        // CHEST focused
        if name.contains("chest") || focus.contains("chest") {
            return DayTypeAnalysis(name: "Chest", muscleDistribution: [
                ("chest", 3),
                ("arms", 1),  // triceps support
                ("shoulders", 1)
            ])
        }
        
        // BACK focused
        if name.contains("back") || focus.contains("back") {
            return DayTypeAnalysis(name: "Back", muscleDistribution: [
                ("back", 3),
                ("arms", 1),  // biceps support
                ("shoulders", 1)  // rear delts
            ])
        }
        
        // SHOULDERS focused
        if name.contains("shoulder") || focus.contains("shoulders") {
            return DayTypeAnalysis(name: "Shoulders", muscleDistribution: [
                ("shoulders", 3),
                ("arms", 1),
                ("chest", 1)
            ])
        }
        
        // ARMS focused
        if name.contains("arm") || focus.contains("arms") || focus.contains("biceps") || focus.contains("triceps") {
            return DayTypeAnalysis(name: "Arms", muscleDistribution: [
                ("arms", 4),
                ("shoulders", 1)
            ])
        }
        
        // CORE focused
        if name.contains("core") || focus.contains("core") || focus.contains("abs") {
            return DayTypeAnalysis(name: "Core", muscleDistribution: [
                ("core", 5)
            ])
        }
        
        // STRENGTH / POWER - compound focused
        if name.contains("strength") || name.contains("power") {
            return DayTypeAnalysis(name: "Strength", muscleDistribution: [
                ("legs", 2),
                ("chest", 1),
                ("back", 1),
                ("shoulders", 1)
            ])
        }
        
        // HYPERTROPHY
        if name.contains("hypertrophy") || name.contains("volume") {
            return DayTypeAnalysis(name: "Hypertrophy", muscleDistribution: [
                ("chest", 1),
                ("back", 1),
                ("legs", 1),
                ("shoulders", 1),
                ("arms", 1)
            ])
        }
        
        // Default: analyze focus areas directly
        if !focus.isEmpty {
            var distribution: [(String, Int)] = []
            let exercisesPerGroup = max(1, 5 / focus.count)
            for area in focus {
                let mappedMuscle = mapSingleFocusToMuscle(area)
                distribution.append((mappedMuscle, exercisesPerGroup))
            }
            return DayTypeAnalysis(name: "Custom", muscleDistribution: distribution)
        }
        
        // Ultimate fallback - full body with compound exercises
        return DayTypeAnalysis(name: "Default Full Body", muscleDistribution: [
            ("compound", 2),
            ("chest", 1),
            ("back", 1),
            ("legs", 1),
            ("shoulders", 1),
            ("arms", 1),
            ("core", 1)
        ])
    }
    
    private func mapSingleFocusToMuscle(_ focus: String) -> String {
        let lower = focus.lowercased()
        switch lower {
        case "chest", "pec", "pectorals": return "chest"
        case "back", "lats", "lat": return "back"
        case "legs", "quads", "quadriceps", "hamstrings", "glutes": return "legs"
        case "shoulders", "delts", "deltoids": return "shoulders"
        case "arms", "biceps", "triceps": return "arms"
        case "core", "abs", "abdominals": return "core"
        default: return lower
        }
    }
    
    /// Select exercises for a specific muscle group
    private func selectExercisesForMuscle(
        muscleGroup: String,
        count: Int,
        equipment: Set<String>,
        allExercises: [ExerciseData],
        usedNames: Set<String>
    ) -> [ExerciseData] {
        
        let targetMuscle = muscleGroup.lowercased()
        
        // COMPOUND EXERCISES - prioritize multi-joint, full body movements
        if targetMuscle == "compound" {
            return selectCompoundExercises(
                count: count,
                equipment: equipment,
                allExercises: allExercises,
                usedNames: usedNames
            )
        }
        
        // Map common muscle group names to actual categories in database
        // Database categories: Arms, Legs, Back, Chest, Core, Shoulders, Full_Body, Neck
        let categoryMappings: [String: [String]] = [
            "chest": ["chest"],
            "back": ["back"],
            "legs": ["legs"],
            "shoulders": ["shoulders"],
            "arms": ["arms"],
            "core": ["core"],
            "full body": ["full_body", "legs", "back", "chest"]  // full body matches multiple
        ]
        
        let targetCategories = categoryMappings[targetMuscle] ?? [targetMuscle]
        
        // Filter exercises that match this muscle group
        let matchingExercises = allExercises.filter { exercise in
            guard !usedNames.contains(exercise.name) else { return false }
            
            let category = exercise.category.lowercased()
            let primaryMuscle = exercise.primaryMuscle.lowercased()
            let primaryRegion = exercise.primaryBodyRegion.lowercased()
            let secondaryMuscles = exercise.secondaryMuscles.map { $0.lowercased() }
            let exerciseEquip = exercise.equipment.lowercased()
            
            // Check equipment match (or allow if equipment set is broad)
            let equipmentMatch = equipment.isEmpty || 
                                 equipment.contains("all") ||
                                 equipment.contains("bodyweight") && exerciseEquip.contains("bodyweight") ||
                                 equipment.contains(where: { equip in
                                     exerciseEquip.contains(equip) || equip.contains(exerciseEquip)
                                 })
            
            // Check muscle match - STRICT matching
            let muscleMatch = targetCategories.contains(where: { target in
                category == target ||
                primaryMuscle.contains(target) || target.contains(primaryMuscle) ||
                primaryRegion.contains(target) || target.contains(primaryRegion)
            })
            
            // Also check secondary muscles as backup
            let secondaryMatch = targetCategories.contains(where: { target in
                secondaryMuscles.contains(where: { $0.contains(target) || target.contains($0) })
            })
            
            return equipmentMatch && (muscleMatch || secondaryMatch)
        }
        
        print("      🎯 Finding \(count) \(targetMuscle) exercises - found \(matchingExercises.count) candidates")
        
        // Shuffle and take requested count
        return Array(matchingExercises.shuffled().prefix(count))
    }
    
    /// Select compound/multi-joint exercises for full body workouts
    private func selectCompoundExercises(
        count: Int,
        equipment: Set<String>,
        allExercises: [ExerciseData],
        usedNames: Set<String>
    ) -> [ExerciseData] {
        
        // Priority compound exercise keywords - these work multiple muscle groups
        let compoundKeywords = [
            "deadlift", "squat", "burpee", "thruster", "clean", "snatch", "press",
            "lunge", "row", "pull up", "push up", "dip", "turkish get up",
            "farmer", "carry", "swing", "jerk", "high pull", "good morning",
            "hip thrust", "step up", "box jump", "mountain climber", "plank"
        ]
        
        // First priority: exercises with "compound" or multiple secondary muscles
        let compoundExercises = allExercises.filter { exercise in
            guard !usedNames.contains(exercise.name) else { return false }
            
            let nameLower = exercise.name.lowercased()
            let exerciseEquip = exercise.equipment.lowercased()
            
            // Check equipment match
            let equipmentMatch = equipment.isEmpty || 
                                 equipment.contains("all") ||
                                 equipment.contains("bodyweight") && exerciseEquip.contains("bodyweight") ||
                                 equipment.contains(where: { equip in
                                     exerciseEquip.contains(equip) || equip.contains(exerciseEquip)
                                 })
            
            guard equipmentMatch else { return false }
            
            // Check if exercise name contains compound movement keywords
            let isCompoundByName = compoundKeywords.contains(where: { keyword in
                nameLower.contains(keyword)
            })
            
            // Check if exercise works multiple muscle groups (has 2+ secondary muscles)
            let hasMultipleMuscles = exercise.secondaryMuscles.count >= 2
            
            // Check if it's in the Full_Body category
            let isFullBodyCategory = exercise.category.lowercased() == "full_body"
            
            return isCompoundByName || hasMultipleMuscles || isFullBodyCategory
        }
        
        // Sort by number of muscles worked (more is better for compound)
        let sortedCompound = compoundExercises.sorted { a, b in
            (a.secondaryMuscles.count + 1) > (b.secondaryMuscles.count + 1)
        }
        
        print("      💪 Finding \(count) compound exercises - found \(sortedCompound.count) candidates")
        
        // Take top compound exercises, shuffle among the best ones for variety
        let topCandidates = Array(sortedCompound.prefix(count * 3))
        return Array(topCandidates.shuffled().prefix(count))
    }
    
    /// Map database focus areas to muscle groups the generator understands
    private func mapFocusAreasToMuscleGroups(_ focusAreas: [String]) -> [String] {
        var muscles: [String] = []
        
        for area in focusAreas {
            let lower = area.lowercased()
            
            // Direct mappings
            switch lower {
            case "full body":
                muscles.append(contentsOf: ["chest", "back", "legs", "shoulders", "core"])
            case "upper body":
                muscles.append(contentsOf: ["chest", "back", "shoulders", "arms"])
            case "lower body":
                muscles.append(contentsOf: ["legs", "glutes", "hamstrings", "calves"])
            case "push":
                muscles.append(contentsOf: ["chest", "shoulders", "triceps"])
            case "pull":
                muscles.append(contentsOf: ["back", "biceps"])
            case "legs":
                muscles.append(contentsOf: ["quadriceps", "hamstrings", "glutes", "calves"])
            case "arms":
                muscles.append(contentsOf: ["biceps", "triceps", "forearms"])
            case "core", "abs":
                muscles.append(contentsOf: ["abs", "obliques", "core"])
            case "stability":
                muscles.append(contentsOf: ["core", "abs"])
            case "rear delts":
                muscles.append("shoulders")
            default:
                // Direct muscle name
                muscles.append(lower)
            }
        }
        
        // Remove duplicates while preserving order
        var seen = Set<String>()
        return muscles.filter { seen.insert($0).inserted }
    }
    
    /// Map equipment names to what the generator understands
    private func mapEquipment(_ equipment: [String]) -> [String] {
        var mapped: [String] = []
        
        for equip in equipment {
            let lower = equip.lowercased()
            switch lower {
            case "bodyweight", "body weight", "none":
                mapped.append("bodyweight")
            case "dumbbells", "dumbbell":
                mapped.append("dumbbell")
            case "barbell", "barbells":
                mapped.append("barbell")
            case "cables", "cable":
                mapped.append("cable")
            case "machines", "machine":
                mapped.append("machine")
            case "kettlebell", "kettlebells":
                mapped.append("kettlebell")
            case "bands", "band", "resistance bands":
                mapped.append("band")
            default:
                mapped.append(lower)
            }
        }
        
        // If no equipment specified, allow all
        if mapped.isEmpty {
            mapped = ["bodyweight", "dumbbell"]
        }
        
        return mapped
    }
    
    /// Fallback exercise generation when intelligent generator fails
    private func generateFallbackExercises(for day: FullProgramDay) -> [ExerciseData] {
        let allExercises = ComprehensiveExerciseDatabase.exercises
        let focusAreas = Set(day.day.focusAreas.map { $0.lowercased() })
        let equipment = Set(day.day.requiredEquipment.map { $0.lowercased() })
        
        // Filter exercises that match any focus area
        var matching = allExercises.filter { exercise in
            let category = exercise.category.lowercased()
            let muscleGroups = (exercise.muscleGroups as? [String])?.map { $0.lowercased() } ?? []
            
            // Check if category or muscles match focus areas
            return focusAreas.isEmpty || focusAreas.contains(where: { focus in
                category.contains(focus) || 
                focus.contains(category) ||
                muscleGroups.contains(where: { $0.contains(focus) || focus.contains($0) }) ||
                focus == "full body"
            })
        }
        
        // Filter by equipment if specified
        if !equipment.isEmpty && !equipment.contains("all") {
            matching = matching.filter { exercise in
                let exerciseEquip = exercise.equipment.lowercased()
                return equipment.contains(where: { equip in
                    exerciseEquip.contains(equip) || equip.contains(exerciseEquip) || equip == "bodyweight"
                })
            }
        }
        
        // Shuffle and take desired count
        let count = max(day.day.exerciseCount, 5)
        return Array(matching.shuffled().prefix(count))
    }
}

// MARK: - Program Difficulty Extension

extension CloudProgram {
    var difficultyLevel: ProgramDifficulty {
        switch difficulty.lowercased() {
        case "beginner": return .beginner
        case "advanced": return .advanced
        default: return .intermediate
        }
    }
    
    var programColor: Color {
        switch color {
        case "blue": return .blue
        case "purple": return .purple
        case "orange": return .orange
        case "red": return .red
        case "green": return .green
        case "cyan": return .cyan
        case "indigo": return .indigo
        case "pink": return .pink
        default: return .blue
        }
    }
}

