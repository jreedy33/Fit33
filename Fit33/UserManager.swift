import Foundation
import CoreData
import SwiftUI

class UserManager: ObservableObject {
    @Published var currentUser: User?
    @Published var hasCompletedOnboarding: Bool = false
    @Published var showLevelUpCelebration: Bool = false
    @Published var newLevelReached: Int = 0
    @Published var isVerified: Bool = false
    @Published var isGoldVerified: Bool = false
    
    private let viewContext = PersistenceController.shared.container.viewContext
    private let supabaseManager = SupabaseManager.shared
    
    // MARK: - Cloud Sync Debouncing
    private var pendingCloudSync = false
    private var lastCloudSync: Date?
    private let cloudSyncDebounceInterval: TimeInterval = 5.0 // 5 seconds minimum between syncs
    
    static let shared = UserManager()
    
    init() {
        loadCurrentUser()
    }
    
    /// Reloads user state from Core Data - call after cloud sync
    func reloadCurrentUser() {
        loadCurrentUser()
        AppLogger.debug("UserManager reloaded - hasCompletedOnboarding: \(hasCompletedOnboarding)", category: .auth)
    }
    
    private func loadCurrentUser() {
        // DEBUG: Skip onboarding in debug builds ONLY if explicitly enabled
        #if DEBUG
        // To skip onboarding: Set environment variable SKIP_ONBOARDING = "YES"
        let shouldSkipOnboarding = ProcessInfo.processInfo.environment["SKIP_ONBOARDING"] == "YES"
        if shouldSkipOnboarding {
            AppLogger.debug("DEBUG: Skipping onboarding, creating test user", category: .auth)
            createDebugUserIfNeeded()
            return
        }
        // Not misleading: this runs on every launch in DEBUG when SKIP_ONBOARDING is unset — actual UI is ContentView + cached user state.
        AppLogger.debug("[DEBUG] UserManager: loading user from Core Data (SKIP_ONBOARDING not set)", category: .auth)
        #endif
        
        let request: NSFetchRequest<User> = User.fetchRequest()
        request.fetchLimit = 1
        
        do {
            let users = try viewContext.fetch(request)
            if let user = users.first {
                // Validate that the user data is not corrupted
                do {
                    // Try to access equipment to ensure it's not corrupted
                    _ = user.getEquipment()
                    self.currentUser = user
                    self.hasCompletedOnboarding = user.hasCompletedOnboarding
                } catch {
                    AppLogger.warning("User data corrupted, deleting and requiring re-onboarding", category: .general)
                    viewContext.delete(user)
                    try? viewContext.save()
                    self.currentUser = nil
                    self.hasCompletedOnboarding = false
                }
            }
        } catch {
            AppLogger.error("Error fetching user: \(error.localizedDescription)", category: .general)
            // If fetch fails completely, reset Core Data
            AppLogger.warning("Core Data fetch failed, attempting cleanup...", category: .general)
            PersistenceController.shared.deleteAll()
        }
    }
    
    #if DEBUG
    // 🔑 CONSISTENT DEBUG USER ID - Ensures workout history persists across rebuilds
    // This MUST match the user ID in Supabase for cloud sync to work
    private static let debugUserID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    
    private func createDebugUserIfNeeded() {
        let request: NSFetchRequest<User> = User.fetchRequest()
        request.fetchLimit = 1
        
        do {
            let users = try viewContext.fetch(request)
            if users.isEmpty {
                // Create a test user with CONSISTENT ID (for cloud sync)
                let testUser = User(context: viewContext)
                testUser.id = Self.debugUserID  // Use consistent ID, not random UUID()
                testUser.name = "Test User"
                testUser.birthday = "01/15/1999"  // Test birthday
                testUser.age = 25
                testUser.gender = "Male"
                testUser.email = "test@test.com"
                testUser.height = 175 // 175 cm
                testUser.heightInches = 69  // 5'9" = 69 inches
                testUser.weight = 75  // 75 kg
                testUser.weightLbs = 165.0  // ~165 lbs
                testUser.fitnessGoal = "Build Muscle"
                testUser.experienceLevel = "Intermediate"
                testUser.equipment = ["Dumbbells", "Barbell", "Bench"] as NSObject
                testUser.availableDays = 5
                testUser.hasCompletedOnboarding = true
                testUser.createdAt = Date()
                testUser.currentStreak = 0
                testUser.longestStreak = 0
                testUser.totalWorkouts = 0
                testUser.xp = 0
                
                // Save to UserDefaults for backwards compatibility
                UserDefaults.standard.set(75, forKey: "userWeight")
                UserDefaults.standard.set(175, forKey: "userHeight")
                UserDefaults.standard.set("Male", forKey: "userGender")
                
                try viewContext.save()
                self.currentUser = testUser
                self.hasCompletedOnboarding = true
                AppLogger.info("Created debug test user (175cm/69in, 75kg/165lbs)", category: .auth)
                
                // Initialize exercises and sync to cloud
                Task {
                    ExerciseLibraryService.shared.initializeDefaultExercises()
                    
                    // Sync debug user to cloud if authenticated
                    if SupabaseManager.shared.isAuthenticated {
                        AppLogger.debug("[DEBUG] Syncing debug user profile to cloud...", category: .auth)
                        try? await syncProfileToCloud()
                    }
                }
            } else {
                let existingUser = users.first!
                self.currentUser = existingUser
                self.hasCompletedOnboarding = true
                
                // Backfill missing fields for existing debug users
                var needsSave = false
                if existingUser.heightInches == 0 && existingUser.height > 0 {
                    existingUser.heightInches = Int16(Double(existingUser.height) / 2.54)
                    AppLogger.debug("[DEBUG] Backfilled heightInches: \(existingUser.heightInches)", category: .general)
                    needsSave = true
                }
                if existingUser.weightLbs == 0 && existingUser.weight > 0 {
                    existingUser.weightLbs = Double(existingUser.weight) * 2.20462
                    AppLogger.debug("[DEBUG] Backfilled weightLbs: \(existingUser.weightLbs)", category: .general)
                    needsSave = true
                }
                if existingUser.birthday == nil || existingUser.birthday?.isEmpty == true {
                    existingUser.birthday = "01/15/1999"
                    AppLogger.debug("[DEBUG] Backfilled birthday: \(existingUser.birthday ?? "")", category: .general)
                    needsSave = true
                }
                
                if needsSave {
                    try? viewContext.save()
                }
                
                // Sync existing user to cloud (in case local data was updated)
                Task {
                    if SupabaseManager.shared.isAuthenticated {
                        AppLogger.debug("[DEBUG] Syncing existing user profile to cloud...", category: .auth)
                        try? await syncProfileToCloud()
                    }
                }
            }
        } catch {
            AppLogger.error("Error creating debug user: \(error.localizedDescription)", category: .auth)
        }
    }
    #endif
    
    func createUser(name: String, age: Int16, gender: String?, email: String?, height: Int16, weight: Int16, fitnessGoal: String, experienceLevel: String, equipment: [String], availableDays: Int16, strengthLevel: String? = nil, workoutEnvironment: String? = nil, birthday: String? = nil, weightLbs: Double? = nil, heightInches: Int16? = nil, phoneNumber: String? = nil) {
        // Input validation - return early on invalid data
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, trimmedName.count <= 100 else {
            AppLogger.error("[ONBOARDING] Validation failed: name must be 1-100 characters", category: .auth)
            return
        }
        guard (13...120).contains(age) else {
            AppLogger.error("[ONBOARDING] Validation failed: age must be 13-120", category: .auth)
            return
        }
        guard (1...300).contains(height) else {
            AppLogger.error("[ONBOARDING] Validation failed: height must be 1-300 cm", category: .auth)
            return
        }
        guard (1...1000).contains(weight) else {
            AppLogger.error("[ONBOARDING] Validation failed: weight must be 1-1000 kg", category: .auth)
            return
        }
        let validationInches = heightInches ?? Int16(Double(height) / 2.54)
        guard (1...120).contains(validationInches) else {
            AppLogger.error("[ONBOARDING] Validation failed: height must be 1-120 inches", category: .auth)
            return
        }
        let lbs = weightLbs ?? Double(weight) * 2.20462
        guard (1...1000).contains(lbs) else {
            AppLogger.error("[ONBOARDING] Validation failed: weight must be 1-1000 lbs", category: .auth)
            return
        }

        let newUser = User(context: viewContext)
        newUser.id = UUID()
        newUser.name = trimmedName
        newUser.age = age
        newUser.gender = gender
        newUser.email = email
        newUser.phoneNumber = phoneNumber  // For 2FA / account security (private)
        newUser.height = height
        newUser.weight = weight
        newUser.fitnessGoal = fitnessGoal
        newUser.experienceLevel = experienceLevel
        newUser.equipment = equipment as NSObject
        newUser.availableDays = availableDays
        newUser.strengthLevel = strengthLevel
        newUser.workoutEnvironment = workoutEnvironment
        newUser.hasCompletedOnboarding = true
        newUser.createdAt = Date()
        newUser.currentStreak = 0
        newUser.longestStreak = 0
        newUser.totalWorkouts = 0
        newUser.xp = 0
        
        // Store original input values for display and sync
        newUser.birthday = birthday
        newUser.weightLbs = weightLbs ?? Double(weight) * 2.20462  // Convert kg to lbs if not provided
        // Calculate total inches from cm if not provided: cm / 2.54 = inches
        newUser.heightInches = heightInches ?? Int16(Double(height) / 2.54)
        
        // Cached in UserDefaults for backwards compatibility. Authoritative weight is in WeightTrackingService.
        UserDefaults.standard.set(Int(weight), forKey: "userWeight")
        UserDefaults.standard.set(Int(height), forKey: "userHeight")
        UserDefaults.standard.set(gender ?? "Prefer not to say", forKey: "userGender")
        
        let totalInches = heightInches ?? Int16(Double(height) / 2.54)
        let ft = totalInches / 12
        let inches = totalInches % 12
        AppLogger.info("[ONBOARDING] Created user: Birthday: \(birthday ?? "not set"), Age: \(age), Height: \(ft)'\(inches)\" = \(totalInches) inches (\(height)cm), Weight: \(weightLbs ?? 0) lbs (\(weight)kg)", category: .auth)
        
        do {
            try viewContext.save()
            self.currentUser = newUser
            self.hasCompletedOnboarding = true
            AppLogger.info("[ONBOARDING] User saved to Core Data", category: .auth)
            
            // ALWAYS sync profile to cloud after creation
            Task {
                // Sync exercises from cloud if authenticated
                if SupabaseManager.shared.isAuthenticated {
                    await ExerciseLibraryService.shared.syncExercisesFromCloud()
                    
                    // Sync full profile to cloud immediately after onboarding
                    AppLogger.debug("[ONBOARDING] Syncing full profile to cloud...", category: .auth)
                    do {
                        try await syncProfileToCloud()
                        AppLogger.info("[ONBOARDING] Profile synced to cloud successfully", category: .auth)
                    } catch {
                        AppLogger.error("[ONBOARDING] Failed to sync profile to cloud: \(error.localizedDescription)", category: .auth)
                        AppLogger.error("[ONBOARDING] Will retry sync on next app launch", category: .auth)
                    }
                    
                    // Mark onboarding as complete in cloud (important for social sign-in users)
                    do {
                        try await SupabaseManager.shared.markOnboardingComplete()
                        AppLogger.info("[ONBOARDING] Onboarding status synced to cloud", category: .auth)
                    } catch {
                        AppLogger.error("[ONBOARDING] Failed to mark onboarding complete: \(error.localizedDescription)", category: .auth)
                    }
                } else {
                    AppLogger.warning("[ONBOARDING] User not authenticated after signup - this is unexpected!", category: .auth)
                    // Fall back to local exercises if not authenticated
                    await MainActor.run {
                        ExerciseLibraryService.shared.initializeDefaultExercises()
                    }
                }
            }
        } catch {
            AppLogger.error("Error saving user: \(error.localizedDescription)", category: .auth)
        }
    }
    
    // MARK: - Cloud Sync
    
    func syncProfileToCloud() async throws {
        guard let user = currentUser else { return }
        guard supabaseManager.isAuthenticated else {
            #if DEBUG
            AppLogger.info("User not authenticated, skipping cloud sync", category: .auth)
            #endif
            return
        }
        
        try await supabaseManager.syncCoreDataProfile(from: user)
        lastCloudSync = Date()
    }
    
    /// Debounced cloud sync - batches multiple sync requests into one
    private func scheduleDebouncedCloudSync() {
        // Skip if sync already pending
        guard !pendingCloudSync else { return }
        
        // Skip if synced recently
        if let lastSync = lastCloudSync,
           Date().timeIntervalSince(lastSync) < cloudSyncDebounceInterval {
            return
        }
        
        pendingCloudSync = true
        
        Task {
            // Wait a short time for additional changes to batch
            try? await Task.sleep(nanoseconds: UInt64(cloudSyncDebounceInterval * 1_000_000_000))
            pendingCloudSync = false
            try? await syncProfileToCloud()
        }
    }
    
    /// Resets user state for sign-out
    /// Called when user signs out to ensure clean state for next user
    func resetForSignOut() {
        AppLogger.info("UserManager: Resetting state for sign-out...", category: .auth)
        currentUser = nil
        hasCompletedOnboarding = false
        AppLogger.info("UserManager: State reset complete", category: .auth)
    }
    
    // ═══════════════════════════════════════════════════════════════════════════
    // SMART STREAK LOGIC
    // ═══════════════════════════════════════════════════════════════════════════
    // Rest days are part of training! A realistic streak system should:
    // 1. Allow rest days between workouts (based on user's schedule)
    // 2. Not punish users for following healthy recovery practices
    // 3. Only break if user is truly inactive (3+ days without workout)
    //
    // Logic:
    // - User works out X days/week (e.g., 4 days = avg 1.75 days between workouts)
    // - Max allowed gap = 7 / availableDays + 1 (rounded up)
    //   • 6 days/week = max 2 day gap (1 rest day)
    //   • 5 days/week = max 2 day gap (1-2 rest days)
    //   • 4 days/week = max 3 day gap (1-2 rest days)
    //   • 3 days/week = max 3 day gap (2 rest days between)
    //   • 2 days/week = max 4 day gap (flexible schedule)
    // ═══════════════════════════════════════════════════════════════════════════
    func updateStreak() {
        guard let user = currentUser else { return }
        
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let lastWorkoutDate = user.lastWorkoutDate ?? Date.distantPast
        let daysSinceLastWorkout = calendar.dateComponents([.day], from: calendar.startOfDay(for: lastWorkoutDate), to: today).day ?? 0
        
        // Calculate max allowed gap based on user's workout frequency
        let availableDays = max(2, Int(user.availableDays))  // Minimum 2 days/week
        let maxAllowedGap = calculateMaxAllowedGap(daysPerWeek: availableDays)
        
        #if DEBUG
        AppLogger.debug("[STREAK] Checking streak: days since last=\(daysSinceLastWorkout), available days/week=\(availableDays), max gap=\(maxAllowedGap), current streak=\(user.currentStreak)", category: .general)
        #endif
        
        if daysSinceLastWorkout == 0 {
            // Already worked out today - no change to streak
            #if DEBUG
            AppLogger.debug("[STREAK] Already worked out today, no streak change", category: .general)
            #endif
            return
        } else if daysSinceLastWorkout <= maxAllowedGap {
            // Within acceptable rest period - INCREMENT streak!
            user.currentStreak += 1
            if user.currentStreak > user.longestStreak {
                user.longestStreak = user.currentStreak
            }
            #if DEBUG
            AppLogger.info("[STREAK] Within rest window (\(daysSinceLastWorkout) ≤ \(maxAllowedGap)) - streak now: \(user.currentStreak)", category: .general)
            #endif
        } else {
            // Too many days off - streak broken
            let oldStreak = user.currentStreak
            user.currentStreak = 1
            #if DEBUG
            AppLogger.warning("[STREAK] Streak broken! (\(daysSinceLastWorkout) > \(maxAllowedGap)) - was \(oldStreak), now 1", category: .general)
            #endif
            
            // Log for analytics
            SessionLogManager.shared.logStreakBroken(
                previousStreak: Int(oldStreak),
                streakType: "workout",
                daysMissed: daysSinceLastWorkout
            )
        }
        
        user.lastWorkoutDate = today
        
        do {
            try viewContext.save()
            checkForAchievements()
            
            // Auto-sync streaks to cloud (debounced)
            scheduleDebouncedCloudSync()
            
            // Log streak milestone if applicable
            if user.currentStreak % 7 == 0 && user.currentStreak > 0 {
                SessionLogManager.shared.logStreakMilestone(
                    streakDays: Int(user.currentStreak),
                    streakType: "workout"
                )
            }
        } catch {
            #if DEBUG
            AppLogger.error("Error updating streak: \(error.localizedDescription)", category: .general)
            #endif
        }
    }
    
    /// Calculate max allowed gap between workouts based on user's schedule
    /// - Parameter daysPerWeek: How many days per week user plans to work out
    /// - Returns: Maximum days allowed between workouts before streak breaks
    private func calculateMaxAllowedGap(daysPerWeek: Int) -> Int {
        // Logic: More frequent workouts = stricter gap, less frequent = more lenient
        switch daysPerWeek {
        case 6...7:
            return 2  // 1 rest day allowed (working out almost daily)
        case 5:
            return 2  // 1-2 rest days (5 day split)
        case 4:
            return 3  // 2 rest days (4 day split like PPL)
        case 3:
            return 3  // 2 rest days between workouts (3 day full body)
        case 2:
            return 4  // 3 rest days (flexible schedule)
        default:
            return 3  // Default: 2 rest days allowed
        }
    }
    
    // MARK: - Streak Status (for UI)
    
    /// Returns streak status for UI display
    /// - Returns: Tuple with (isAtRisk, daysRemaining, message)
    func getStreakStatus() -> (isAtRisk: Bool, daysRemaining: Int, message: String) {
        guard let user = currentUser else {
            return (false, 0, "Start your first workout!")
        }
        
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let lastWorkoutDate = user.lastWorkoutDate ?? Date.distantPast
        let daysSinceLastWorkout = calendar.dateComponents([.day], from: calendar.startOfDay(for: lastWorkoutDate), to: today).day ?? 0
        
        let availableDays = max(2, Int(user.availableDays))
        let maxAllowedGap = calculateMaxAllowedGap(daysPerWeek: availableDays)
        let daysRemaining = maxAllowedGap - daysSinceLastWorkout
        
        if user.currentStreak == 0 {
            return (false, maxAllowedGap, "Start your streak today!")
        } else if daysSinceLastWorkout == 0 {
            return (false, maxAllowedGap, "Great job! See you next workout 💪")
        } else if daysRemaining <= 0 {
            return (true, 0, "Workout today to save your streak! 🔥")
        } else if daysRemaining == 1 {
            return (true, 1, "Last day to keep your streak! 🔥")
        } else {
            return (false, daysRemaining, "\(daysRemaining) rest days remaining")
        }
    }
    
    /// Get the max allowed gap for the current user (public accessor)
    func getMaxAllowedRestDays() -> Int {
        guard let user = currentUser else { return 3 }
        let availableDays = max(2, Int(user.availableDays))
        return calculateMaxAllowedGap(daysPerWeek: availableDays) - 1  // -1 because gap includes workout day
    }
    
    /// Check if streak should be broken due to inactivity (called by DailyResetService)
    /// Unlike updateStreak(), this does NOT increment the streak or update lastWorkoutDate.
    /// It only checks if the user has been inactive too long and breaks the streak if so.
    func checkAndBreakStreakIfNeeded() {
        guard let user = currentUser else { return }

        guard user.currentStreak > 0 else { return }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let lastWorkoutDate = user.lastWorkoutDate ?? Date.distantPast
        
        // If a streak shield was used after the last workout, treat the shield date
        // as the effective reference point (extends the allowed gap window).
        let effectiveDate: Date
        if let shieldDate = StreakShieldService.shared.lastShieldUsedDate,
           shieldDate > lastWorkoutDate {
            effectiveDate = shieldDate
        } else {
            effectiveDate = lastWorkoutDate
        }
        
        let daysSinceEffective = calendar.dateComponents([.day], from: calendar.startOfDay(for: effectiveDate), to: today).day ?? 0

        let availableDays = max(2, Int(user.availableDays))
        let maxAllowedGap = calculateMaxAllowedGap(daysPerWeek: availableDays)

        #if DEBUG
        let daysSinceLastWorkout = calendar.dateComponents([.day], from: calendar.startOfDay(for: lastWorkoutDate), to: today).day ?? 0
        AppLogger.debug("[STREAK CHECK] Daily check: days since workout=\(daysSinceLastWorkout), days since effective=\(daysSinceEffective) (shield: \(effectiveDate != lastWorkoutDate)), max gap=\(maxAllowedGap), streak=\(user.currentStreak)", category: .general)
        #endif

        if daysSinceEffective > maxAllowedGap {
            if StreakShieldService.shared.canUseShield,
               StreakShieldService.shared.useShield() {
                #if DEBUG
                AppLogger.debug("[STREAK CHECK] Shield auto-used, streak preserved at \(user.currentStreak)", category: .general)
                #endif
                return
            }

            let oldStreak = user.currentStreak
            user.currentStreak = 0

            #if DEBUG
            AppLogger.warning("[STREAK CHECK] Streak broken! (\(daysSinceEffective) > \(maxAllowedGap)) - was \(oldStreak), now 0", category: .general)
            #endif

            SessionLogManager.shared.logStreakBroken(
                previousStreak: Int(oldStreak),
                streakType: "workout",
                daysMissed: daysSinceEffective
            )

            do {
                try viewContext.save()
                scheduleDebouncedCloudSync()
            } catch {
                #if DEBUG
                AppLogger.error("Error saving streak break: \(error.localizedDescription)", category: .general)
                #endif
            }
        } else {
            #if DEBUG
            AppLogger.debug("[STREAK CHECK] Streak safe (\(daysSinceEffective) ≤ \(maxAllowedGap))", category: .general)
            #endif
        }
    }

    func addXP(_ points: Int32) {
        guard let user = currentUser else { return }
        let oldLevel = getLevel()
        user.xp += points
        let newLevel = getLevel()
        
        do {
            try viewContext.save()
            
            // Trigger level-up celebration
            if newLevel > oldLevel {
                newLevelReached = newLevel
                showLevelUpCelebration = true
                HapticManager.notification(.success)
                awardAchievement(type: "level_\(newLevel)")
            }
            
            // Auto-sync XP and level to cloud (debounced)
            scheduleDebouncedCloudSync()
        } catch {
            #if DEBUG
            AppLogger.error("Error adding XP: \(error.localizedDescription)", category: .general)
            #endif
        }
    }
    
    func getLevel() -> Int {
        guard let user = currentUser else { return 1 }
        return Int(user.xp / 100) + 1
    }
    
    func getXPForNextLevel() -> Int32 {
        guard let user = currentUser else { return 100 }
        let currentLevel = getLevel()
        return Int32(currentLevel * 100) - user.xp
    }
    
    func getXPProgress() -> Double {
        guard let user = currentUser else { return 0 }
        let currentLevel = getLevel()
        let xpInCurrentLevel = user.xp - Int32((currentLevel - 1) * 100)
        return Double(xpInCurrentLevel) / 100.0
    }
    
    func getLevelTitle() -> String {
        let level = getLevel()
        if level <= 5 { return "Novice \(level)" }
        else if level <= 10 { return "Beginner \(level)" }
        else if level <= 20 { return "Intermediate \(level)" }
        else if level <= 30 { return "Advanced \(level)" }
        else if level <= 40 { return "Expert \(level)" }
        else if level <= 50 { return "Master \(level)" }
        else { return "Legendary Master \(level)" }
    }
    
    func getLevelIcon() -> String {
        let level = getLevel()
        if level <= 10 { return "bolt.fill" }
        else if level <= 20 { return "star.fill" }
        else if level <= 30 { return "crown.fill" }
        else if level <= 40 { return "diamond.fill" }
        else if level <= 50 { return "sparkles" }
        else { return "infinity" }
    }
    
    func getLevelColor() -> Color {
        let level = getLevel()
        if level <= 10 { return .cyan }
        else if level <= 20 { return .blue }
        else if level <= 30 { return .purple }
        else if level <= 40 { return .pink }
        else if level <= 50 { return .yellow }
        else { return .orange }
    }
    
    func completeWorkout(_ workout: Workout) {
        guard let user = currentUser else { return }
        
        workout.isCompleted = true
        workout.xpEarned = calculateWorkoutXP(workout)
        user.totalWorkouts += 1
        
        addXP(workout.xpEarned)
        updateStreak()
        
        do {
            try viewContext.save()
            checkForAchievements()
            
            // Sync workout completion to cloud (debounced)
            scheduleDebouncedCloudSync()
            
            // Award league points for workout completion (+50 pts)
            Task {
                await WeeklyLeagueService.shared.addPoints(source: .workout)
                
                // Update daily quest progress for workout completion
                let exercises = workout.exercises?.allObjects as? [WorkoutExercise] ?? []
                let totalSets = exercises.reduce(0) { total, ex in
                    total + ((ex.sets?.allObjects as? [WorkoutSet])?.filter(\.isCompleted).count ?? 0)
                }
                let durationSeconds = Int(workout.duration)
                await DailyQuestService.shared.onWorkoutCompleted(durationSeconds: durationSeconds, totalSets: totalSets)
                
                // Post to friend activity feed (skip if user opted out)
                let muscleGroups = exercises.compactMap { $0.safeMuscleGroups.first?.lowercased() }
                let uniqueMuscles = Array(Set(muscleGroups))
                guard !PrivacySettingsManager.shared.hideFriendActivity else {
                    AppLogger.debug("[PRIVACY] Skipping activity feed post — user has friend activity hidden", category: .social)
                    // Still check achievements below
                    await BadgeService.shared.onWorkoutCompleted(totalWorkouts: Int(user.totalWorkouts))
                    await BadgeService.shared.onStreakUpdated(streak: Int(user.currentStreak))
                    StreakShieldService.shared.checkAndAwardShield(totalWorkouts: Int(user.totalWorkouts))
                    return
                }
                let exerciseDetails: [[String: Any]] = exercises.enumerated().map { index, ex in
                    let completedSets = (ex.sets?.allObjects as? [WorkoutSet])?.filter(\.isCompleted) ?? []
                    let maxWeight = completedSets.map(\.weight).max() ?? 0
                    let maxReps = completedSets.map { Int($0.reps) }.max() ?? 0
                    return [
                        "name": ex.safeDisplayName,
                        "sets": completedSets.count,
                        "max_weight": maxWeight,
                        "max_reps": maxReps
                    ] as [String: Any]
                }
                
                await ActivityFeedService.shared.postWorkoutActivity(
                    workoutId: workout.objectID.uriRepresentation().lastPathComponent,
                    name: workout.name ?? "Workout",
                    duration: durationSeconds,
                    exercises: exercises.count,
                    sets: totalSets,
                    xp: Int(workout.xpEarned),
                    muscles: uniqueMuscles,
                    exerciseDetails: exerciseDetails
                )
                
                // Check workout achievements
                await BadgeService.shared.onWorkoutCompleted(totalWorkouts: Int(user.totalWorkouts))
                await BadgeService.shared.onStreakUpdated(streak: Int(user.currentStreak))
                
                // Award streak shield for workout milestones (every 10 workouts)
                StreakShieldService.shared.checkAndAwardShield(totalWorkouts: Int(user.totalWorkouts))
            }
        } catch {
            #if DEBUG
            AppLogger.error("Error completing workout: \(error.localizedDescription)", category: .general)
            #endif
        }
    }
    
    private func calculateWorkoutXP(_ workout: Workout) -> Int32 {
        guard let exercises = workout.exercises?.allObjects as? [WorkoutExercise] else { return 25 }
        
        let baseXP: Int32 = 25
        let exerciseBonus = Int32(exercises.count * 5)
        let durationBonus = workout.duration > 1800 ? Int32(15) : Int32(0) // 30+ minutes
        
        return baseXP + exerciseBonus + durationBonus
    }

    // MARK: - Cardio gamification (Sprint 2 Q2-5)

    /// Sprint 2 Q2-5 — cardio parity with strength. Mirrors `completeWorkout`
    /// for cardio sessions: awards XP, updates streak, posts to the friend
    /// activity feed, progresses daily quests + league points + badges, and
    /// forwards to challenge progress. Called from `CardioActiveWorkoutView`
    /// after the cardio row is persisted in Supabase.
    ///
    /// XP curve (fitness-expert signoff): deliberately weighted below strength
    /// to keep XP-per-minute roughly equal to strength's 40–80 XP band.
    ///   • base 20
    ///   • +10 per 15 minutes of duration, capped at +40 (60+ min workout)
    ///   • +10 if distance ≥ 3 km (road / bike / run milestone)
    ///   • +10 if calories ≥ 300 (sustained effort)
    /// Typical 30 min run ≈ 40 XP; 45 min bike with 10 km ≈ 60 XP.
    func completeCardioWorkout(
        workoutId: String,
        activityType: String,
        durationSeconds: Int,
        distanceMeters: Double,
        caloriesBurned: Int,
        averageHeartRate: Int?
    ) {
        guard let user = currentUser else { return }

        let xp = calculateCardioXP(
            durationSeconds: durationSeconds,
            distanceMeters: distanceMeters,
            caloriesBurned: caloriesBurned
        )

        user.totalWorkouts += 1
        addXP(xp)
        updateStreak()

        do {
            try viewContext.save()
            checkForAchievements()
            scheduleDebouncedCloudSync()
        } catch {
            #if DEBUG
            AppLogger.error("Error completing cardio workout: \(error.localizedDescription)", category: .workout)
            #endif
        }

        let totalWorkouts = Int(user.totalWorkouts)
        let currentStreak = Int(user.currentStreak)

        Task {
            // League points (+50) — parity with strength workouts.
            await WeeklyLeagueService.shared.addPoints(source: .workout)

            // Daily quest progression. Cardio has no sets, so pass 0.
            await DailyQuestService.shared.onWorkoutCompleted(
                durationSeconds: durationSeconds,
                totalSets: 0
            )

            // Challenge progression — reuse the Strava pipeline since it already
            // gates on workoutType + distance/duration + handles run/walk/
            // active_minutes/workout_streak.
            await ChallengeService.shared.checkStravaWorkoutForChallenges(
                workoutType: activityType,
                distanceMeters: distanceMeters,
                durationSeconds: durationSeconds,
                source: "cardio"
            )

            // Badges (total workouts + streak milestones).
            await BadgeService.shared.onWorkoutCompleted(totalWorkouts: totalWorkouts)
            await BadgeService.shared.onStreakUpdated(streak: currentStreak)
            StreakShieldService.shared.checkAndAwardShield(totalWorkouts: totalWorkouts)

            // Friend activity feed — respect the same privacy opt-out as
            // `completeWorkout`.
            guard !PrivacySettingsManager.shared.hideFriendActivity else {
                AppLogger.debug("[PRIVACY] Skipping cardio activity feed post — friend activity hidden", category: .social)
                return
            }
            await ActivityFeedService.shared.postCardioActivity(
                workoutId: workoutId,
                activityType: activityType,
                durationSeconds: durationSeconds,
                distanceMeters: distanceMeters,
                caloriesBurned: caloriesBurned,
                averageHeartRate: averageHeartRate,
                xpEarned: Int(xp)
            )
        }
    }

    private func calculateCardioXP(
        durationSeconds: Int,
        distanceMeters: Double,
        caloriesBurned: Int
    ) -> Int32 {
        let base: Int32 = 20
        let fifteenMinChunks = Int32(durationSeconds / (15 * 60))
        let durationBonus = min(Int32(40), fifteenMinChunks * 10)
        let distanceBonus: Int32 = distanceMeters >= 3000 ? 10 : 0
        let calorieBonus: Int32 = caloriesBurned >= 300 ? 10 : 0
        return base + durationBonus + distanceBonus + calorieBonus
    }
    
    private func checkForAchievements() {
        guard let user = currentUser else { return }
        
        // Check various achievement conditions
        if user.currentStreak >= 7 && !hasAchievement(type: "streak_7") {
            awardAchievement(type: "streak_7")
        }
        
        if user.currentStreak >= 30 && !hasAchievement(type: "streak_30") {
            awardAchievement(type: "streak_30")
        }
        
        if user.totalWorkouts >= 10 && !hasAchievement(type: "workouts_10") {
            awardAchievement(type: "workouts_10")
        }
        
        if user.totalWorkouts >= 50 && !hasAchievement(type: "workouts_50") {
            awardAchievement(type: "workouts_50")
        }
        
        if user.totalWorkouts >= 100 && !hasAchievement(type: "workouts_100") {
            awardAchievement(type: "workouts_100")
        }
    }
    
    private func hasAchievement(type: String) -> Bool {
        guard let user = currentUser,
              let achievements = user.achievements?.allObjects as? [UserAchievement] else { return false }
        
        return achievements.contains { $0.achievementType == type }
    }
    
    private func awardAchievement(type: String) {
        guard let user = currentUser else { return }
        
        let achievement = UserAchievement(context: viewContext)
        achievement.id = UUID()
        achievement.achievementType = type
        achievement.dateEarned = Date()
        achievement.user = user
        
        do {
            try viewContext.save()
        } catch {
            AppLogger.error("Error awarding achievement: \(error.localizedDescription)", category: .general)
        }
    }
    
    func getRecentMuscleGroups(days: Int = 7) -> [String: Int] {
        guard let user = currentUser else { return [:] }
        
        let calendar = Calendar.current
        let startDate = calendar.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        
        let request: NSFetchRequest<Workout> = Workout.fetchRequest()
        request.predicate = NSPredicate(format: "user == %@ AND date >= %@ AND isCompleted == YES", user, startDate as NSDate)
        
        var muscleGroupCounts: [String: Int] = [:]
        
        do {
            let workouts = try viewContext.fetch(request)
            for workout in workouts {
                if let exercises = workout.exercises?.allObjects as? [WorkoutExercise] {
                    for workoutExercise in exercises {
                        // Use safeMuscleGroups for nil-safety
                        for muscle in workoutExercise.safeMuscleGroups {
                            muscleGroupCounts[muscle, default: 0] += 1
                        }
                    }
                }
            }
        } catch {
            AppLogger.error("Error fetching recent muscle groups: \(error.localizedDescription)", category: .general)
        }
        
        return muscleGroupCounts
    }
    
    func getAchievements() -> [UserAchievement] {
        guard let user = currentUser,
              let achievements = user.achievements?.allObjects as? [UserAchievement] else { return [] }
        
        return achievements.sorted { $0.dateEarned ?? Date.distantPast > $1.dateEarned ?? Date.distantPast }
    }
}

// MARK: - Premium Manager
class PremiumManager: ObservableObject {
    static let shared = PremiumManager()
    
    @Published var isPremiumUser: Bool = true {
        didSet {
            UserDefaults.standard.set(isPremiumUser, forKey: "isPremiumUser")
        }
    }
    
    private init() {
        // Always start as premium — all features available.
        // The Settings "Free User Mode" toggle can temporarily switch to free for testing,
        // but every fresh launch resets to premium.
        self.isPremiumUser = true
        UserDefaults.standard.set(true, forKey: "isPremiumUser")
    }
    
    /// Called by StoreKitManager when entitlement status changes.
    /// Currently a no-op: app always runs as premium.
    /// Re-enable when subscription billing goes live.
    func updateFromStoreKit(hasSubscription: Bool) {
        // No-op: premium is always true until billing is live
    }
    
    // MARK: - Premium Feature Checks
    
    /// Check if user has access to premium workouts
    var hasPremiumWorkouts: Bool {
        return isPremiumUser
    }
    
    /// Check if user has access to advanced analytics
    var hasAdvancedAnalytics: Bool {
        return isPremiumUser
    }
    
    /// Check if user has access to custom meal plans
    var hasCustomMealPlans: Bool {
        return isPremiumUser
    }
    
    /// Check if user has access to AI workout generation
    var hasAIWorkoutGeneration: Bool {
        return isPremiumUser
    }
    
    /// Check if user has access to unlimited workout history
    var hasUnlimitedHistory: Bool {
        return isPremiumUser
    }
    
    /// Check if user has access to premium exercises
    var hasPremiumExercises: Bool {
        return isPremiumUser
    }
    
    /// Check if user has access to advanced progress tracking
    var hasAdvancedProgress: Bool {
        return isPremiumUser
    }
    
    /// Check if user has access to nutrition insights
    var hasNutritionInsights: Bool {
        return isPremiumUser
    }
    
    // MARK: - Development Helpers
    
    /// Toggle premium status (for development only)
    func togglePremiumStatus() {
        isPremiumUser.toggle()
        AppLogger.debug("Premium status changed to: \(isPremiumUser ? "Premium" : "Free")", category: .general)
    }
    
    /// Force set premium status (for development only)
    func setPremiumStatus(_ premium: Bool) {
        isPremiumUser = premium
        AppLogger.debug("Premium status set to: \(isPremiumUser ? "Premium" : "Free")", category: .general)
    }
    
    // MARK: - Feature Descriptions
    
    /// Get description of what premium unlocks
    var premiumFeatures: [String] {
        return [
            "🏋️ Unlimited AI Workout Generation",
            "📊 Advanced Analytics & Progress Tracking", 
            "🍽️ Custom Meal Plans & Nutrition Insights",
            "💪 Premium Exercise Library (500+ exercises)",
            "📈 Unlimited Workout History",
            "🎯 Personalized Recommendations",
            "🔥 Advanced Achievement System",
            "⚡ Priority Support"
        ]
    }
    
    /// Get current status description
    var statusDescription: String {
        return isPremiumUser ? "Premium User" : "Free User"
    }
    
    /// Get current status color
    var statusColor: Color {
        return isPremiumUser ? .green : .orange
    }
    
    /// Get current status icon
    var statusIcon: String {
        return isPremiumUser ? "crown.fill" : "person.fill"
    }
}

// MARK: - Premium Feature View Modifier
struct PremiumFeatureModifier: ViewModifier {
    @ObservedObject var premiumManager = PremiumManager.shared
    let feature: String
    let premiumRequired: Bool
    
    func body(content: Content) -> some View {
        if premiumRequired && !premiumManager.isPremiumUser {
            ZStack {
                content
                    .blur(radius: 2)
                    .disabled(true)
                
                VStack(spacing: 8) {
                    Image(systemName: "crown.fill")
                        .font(.title)
                        .foregroundColor(.yellow)
                    
                    Text("Premium Feature")
                        .font(.headline)
                        .fontWeight(.bold)
                    
                    Text(feature)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .background(.ultraThinMaterial)
                .cornerRadius(CornerRadius.md)
            }
        } else {
            content
        }
    }
}

// MARK: - View Extension
extension View {
    /// Apply premium feature restriction
    func premiumFeature(_ feature: String, required: Bool = true) -> some View {
        self.modifier(PremiumFeatureModifier(feature: feature, premiumRequired: required))
    }
    
    /// Check if premium feature is available
    func isPremiumAvailable() -> Bool {
        return PremiumManager.shared.isPremiumUser
    }
}
