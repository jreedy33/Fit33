import Foundation
import Supabase
import SwiftUI
import Auth
import CoreData

// MARK: - Supabase Manager
// This class handles all communication with your cloud database

class SupabaseManager: ObservableObject {
    static let shared = SupabaseManager()
    
    // Your Supabase credentials
    private let supabaseURL = "https://ehooeghabzefgoqzugrc.supabase.co"  
    private let supabaseKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVob29lZ2hhYnplZmdvcXp1Z3JjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjM4NDc4NjQsImV4cCI6MjA3OTQyMzg2NH0.6-QWDr5B279hybtu9MbPVhmBKlyzFq1GK9P7zlDXuY0"     
    
    private var client: SupabaseClient!
    
    // Public getter for client (needed by FoodDatabaseService)
    var supabaseClient: SupabaseClient {
        return client
    }
    
    @Published var currentUser: Auth.User?
    @Published var isAuthenticated = false
    @Published var isLoading = false
    
    private init() {
        // Initialize Supabase client
        guard let url = URL(string: supabaseURL) else {
            print("❌ Invalid Supabase URL")
            return
        }
        
        client = SupabaseClient(supabaseURL: url, supabaseKey: supabaseKey)
        
        // Check for existing session
        Task {
            await checkAuth()
        }
    }
    
    // MARK: - Authentication
    
    func checkAuth() async {
        do {
            let session = try await client.auth.session
            
            // IMPORTANT: Verify the user actually exists in the database
            // This handles the case where user was deleted from Supabase but session still exists
            let userExists = await verifyUserExists(userId: session.user.id)
            
            if !userExists {
                print("⚠️ Session exists but user was deleted from database - forcing sign out")
                try? await client.auth.signOut()
                await MainActor.run {
                    currentUser = nil
                    isAuthenticated = false
                    // Clear all local data since user no longer exists
                    PersistenceController.shared.clearAllUserData()
                }
                return
            }
            
            await MainActor.run {
                currentUser = session.user
                isAuthenticated = true
            }
            print("✅ User already signed in: \(session.user.email ?? "unknown")")
            
            // Sync all data from cloud (skipped in fast startup mode for dev)
            #if DEBUG
            if !UserDefaults.standard.bool(forKey: "FAST_STARTUP_MODE") {
            await syncAllDataFromCloud()
            } else {
                print("⚡ [FAST STARTUP] Skipping cloud sync - using cached data")
            }
            #else
            await syncAllDataFromCloud()
            #endif
        } catch {
            await MainActor.run {
                isAuthenticated = false
                currentUser = nil
            }
            print("ℹ️ No active session")
        }
    }
    
    /// Verifies that a user actually exists in the database (not just has a session)
    private func verifyUserExists(userId: UUID) async -> Bool {
        do {
            let response: [UserProfileDTO] = try await client
                .from("user_profiles")
                .select("id")
                .eq("id", value: userId.uuidString)
                .execute()
                .value
            
            return !response.isEmpty
        } catch {
            print("⚠️ Error verifying user exists: \(error)")
            // If we can't verify, assume user exists to avoid accidental sign-outs
            return true
        }
    }
    
    func signUp(email: String, password: String, name: String) async throws {
        await MainActor.run { isLoading = true }
        SessionLogManager.shared.logAuthAttempt(method: "email_signup")

        do {
            let response = try await client.auth.signUp(email: email, password: password)
            
            let user = response.user
            // Create user profile
            try await createUserProfile(userId: user.id, name: name, email: email)
            
            await MainActor.run {
                currentUser = user
                isAuthenticated = true
                isLoading = false
                
                // Clear the manual sign-out flag since user is signing up
                UserDefaults.standard.removeObject(forKey: "user_manually_signed_out")
            }
            print("✅ Sign up successful: \(email)")
        } catch {
            await MainActor.run { isLoading = false }
            print("❌ Sign up error: \(error.localizedDescription)")
            throw error
        }
    }
    
    func signIn(email: String, password: String) async throws {
        await MainActor.run { isLoading = true }
        SessionLogManager.shared.logAuthAttempt(method: "email")

        do {
            let session = try await client.auth.signIn(email: email, password: password)
            SessionLogManager.shared.logAuthSuccess(method: "email", userId: session.user.id.uuidString)
            
            await MainActor.run {
                currentUser = session.user
                isAuthenticated = true
                isLoading = false
                
                // Clear the manual sign-out flag since user is logging back in
                UserDefaults.standard.removeObject(forKey: "user_manually_signed_out")
            }
            print("✅ Sign in successful: \(email)")
            
            // Sync all data from cloud
            await syncAllDataFromCloud()
        } catch {
            await MainActor.run { isLoading = false }
            SessionLogManager.shared.logAuthFailure(method: "email", error: error.localizedDescription)
            print("❌ Sign in error: \(error.localizedDescription)")
            throw error
        }
    }
    
    // MARK: - Auth Provider Detection
    
    /// Check what authentication provider an email is registered with
    /// Returns: "apple", "google", "email", "none", or comma-separated if multiple
    func checkAuthProvider(for email: String) async -> String {
        do {
            let response: String = try await client.rpc("check_auth_provider", params: ["email_to_check": email.lowercased()]).execute().value
            print("🔍 Auth provider for \(email): \(response)")
            return response
        } catch {
            print("⚠️ Could not check auth provider: \(error.localizedDescription)")
            return "unknown"
        }
    }
    
    /// Get a user-friendly message for the detected auth provider
    func getAuthProviderMessage(for provider: String) -> (message: String, shouldShowApple: Bool, shouldShowGoogle: Bool)? {
        switch provider.lowercased() {
        case "apple":
            return ("This email is linked to Sign in with Apple. Please use the Apple button below to sign in.", true, false)
        case "google":
            return ("This email is linked to Sign in with Google. Please use the Google button below to sign in.", false, true)
        case "apple,google", "google,apple":
            return ("This email is linked to Apple and Google. Please use either button below to sign in.", true, true)
        case "email":
            return nil // Normal email/password login is fine
        case "none":
            return nil // Email not registered, they can sign up
        default:
            return nil
        }
    }
    
    // MARK: - Social Sign-In (Apple & Google)
    
    /// Sign in with Apple using the identity token from ASAuthorizationAppleIDCredential
    /// Returns true if this is a NEW user who needs onboarding
    @discardableResult
    func signInWithApple(idToken: String, nonce: String) async throws -> Bool {
        await MainActor.run { isLoading = true }
        
        do {
            let session = try await client.auth.signInWithIdToken(
                credentials: .init(
                    provider: .apple,
                    idToken: idToken,
                    nonce: nonce
                )
            )
            
            // Check if this is a new user (no profile exists yet)
            let profileExists = await verifyUserExists(userId: session.user.id)
            var isNewUser = false
            
            if !profileExists {
                // Get email from Supabase session (Apple provides this to Supabase)
                let appleEmail = session.user.email ?? "apple_user_\(session.user.id.uuidString.prefix(8))@private.appleid.com"
                
                // Try to get name from various sources
                var appleName = "Apple User"
                if let fullName = session.user.userMetadata["full_name"] as? String, !fullName.isEmpty {
                    appleName = fullName
                } else if let name = session.user.userMetadata["name"] as? String, !name.isEmpty {
                    appleName = name
                } else if let email = session.user.email, !email.contains("privaterelay") {
                    // Use part of email as name if no name provided
                    appleName = email.components(separatedBy: "@").first ?? "Apple User"
                }
                
                print("📧 Apple Sign-In - Email: \(appleEmail), Name: \(appleName)")
                
                try await createUserProfile(userId: session.user.id, name: appleName, email: appleEmail, hasCompletedOnboarding: false)
                isNewUser = true
                print("👤 New Apple user - needs onboarding")
            }
            
            await MainActor.run {
                currentUser = session.user
                isAuthenticated = true
                isLoading = false
                UserDefaults.standard.removeObject(forKey: "user_manually_signed_out")
            }
            print("✅ Apple Sign-In successful: \(session.user.email ?? "private email")")
            
            // Only sync data for EXISTING users (not new users who need onboarding)
            if !isNewUser {
                await syncAllDataFromCloud()
            }
            
            return isNewUser
        } catch {
            await MainActor.run { isLoading = false }
            print("❌ Apple Sign-In error: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Handle OAuth callback URL (for Google Sign-In)
    func handleOAuthCallback(url: URL) async throws {
        await MainActor.run { isLoading = true }
        
        do {
            let session = try await client.auth.session(from: url)
            
            // Check if this is a new user (no profile exists yet)
            let profileExists = await verifyUserExists(userId: session.user.id)
            
            if !profileExists {
                // Create a new profile for this Google Sign-In user
                let googleEmail = session.user.email ?? "google_user_\(session.user.id.uuidString.prefix(8))@gmail.com"
                let googleName = session.user.userMetadata["full_name"] as? String 
                    ?? session.user.userMetadata["name"] as? String 
                    ?? "Google User"
                try await createUserProfile(userId: session.user.id, name: googleName, email: googleEmail)
            }
            
            await MainActor.run {
                currentUser = session.user
                isAuthenticated = true
                isLoading = false
                UserDefaults.standard.removeObject(forKey: "user_manually_signed_out")
            }
            print("✅ Google Sign-In successful: \(session.user.email ?? "unknown")")
            
            // Sync all data from cloud
            await syncAllDataFromCloud()
        } catch {
            await MainActor.run { isLoading = false }
            print("❌ Google OAuth callback error: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Get the OAuth URL for Google Sign-In
    func getGoogleOAuthURL() -> URL? {
        let redirectURL = "fit33://login-callback"
        
        var components = URLComponents(string: "\(supabaseURL)/auth/v1/authorize")
        components?.queryItems = [
            URLQueryItem(name: "provider", value: "google"),
            URLQueryItem(name: "redirect_to", value: redirectURL)
        ]
        
        return components?.url
    }
    
    func signOut() async throws {
        await MainActor.run { isLoading = true }
        SessionLogManager.shared.logLogout()
        
        do {
            try await client.auth.signOut()
            
            // Clear all local user data for security
            // This ensures no data from this user is visible to another user
            await MainActor.run {
                // Clear Core Data and UserDefaults
                PersistenceController.shared.clearAllUserData()
                
                // Mark that user manually signed out (for development mode)
                UserDefaults.standard.set(true, forKey: "user_manually_signed_out")
                
                // Reset authentication state
                currentUser = nil
                isAuthenticated = false
                isLoading = false
            }
            print("✅ Sign out successful - all local data cleared")
        } catch {
            await MainActor.run { isLoading = false }
            print("❌ Sign out error: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Delete the current user's account completely
    /// This uses a Supabase function to delete from auth.users (requires running supabase_delete_user_function.sql)
    func deleteAccount() async throws {
        guard let userId = currentUser?.id else {
            throw NSError(domain: "SupabaseManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "No user logged in"])
        }
        
        print("🗑️ Starting account deletion for user: \(userId.uuidString)")
        print("🔐 Current auth.uid from session: \(currentUser?.id.uuidString ?? "nil")")
        
        await MainActor.run { isLoading = true }
        
        do {
            // Call the database function that deletes the user from auth.users
            // This function also deletes from all related tables
            print("📡 Calling RPC delete_user_account...")
            let result: Bool = try await client
                .rpc("delete_user_account", params: ["user_id_to_delete": userId.uuidString])
                .execute()
                .value
            
            print("📡 RPC returned: \(result)")
            
            if result {
                print("✅ User deleted from database via RPC function")
            } else {
                print("⚠️ RPC function returned false - deletion may have failed")
                print("⚠️ This usually means auth.uid() != user_id in the function")
                // Try fallback deletion
                try await fallbackDeleteAccount(userId: userId)
            }
            
            // Sign out locally (the server-side user is already deleted)
            try? await client.auth.signOut()
            
            await MainActor.run {
                PersistenceController.shared.clearAllUserData()
                UserDefaults.standard.set(true, forKey: "user_manually_signed_out")
                currentUser = nil
                isAuthenticated = false
                isLoading = false
            }
            
            print("✅ Account deleted successfully - user can re-register with same email")
        } catch {
            await MainActor.run { isLoading = false }
            print("❌ Account deletion RPC error: \(error)")
            print("❌ Error details: \(error.localizedDescription)")
            
            // Fallback: If RPC fails, try manual deletion (won't delete from auth.users though)
            print("⚠️ Attempting fallback deletion...")
            try await fallbackDeleteAccount(userId: userId)
        }
    }
    
    /// Fallback deletion method if the RPC function isn't set up
    /// Note: This won't delete from auth.users - user won't be able to re-register with same email
    private func fallbackDeleteAccount(userId: UUID) async throws {
        // Delete from all user tables (comprehensive list)
        let tables = [
            // User profile and settings
            ("user_profiles", "id"),
            ("user_progress", "user_id"),
            
            // Workout data
            ("workout_history", "user_id"),
            ("workouts", "user_id"),
            ("exercise_usage_logs", "user_id"),
            
            // Program data
            ("user_active_programs", "user_id"),
            ("user_custom_programs", "user_id"),
            ("program_history", "user_id"),
            
            // Food/meal data
            ("meal_logs", "user_id"),
            ("user_food_history", "user_id"),
            ("user_food_frequency", "user_id"),
            
            // Favorites and custom content
            ("user_favorites", "user_id"),
            ("favorite_workouts", "user_id"),
            ("custom_exercises", "user_id"),
            
            // Other user data
            ("step_tracking", "user_id"),
            ("bug_reports", "user_id")
        ]
        
        for (table, column) in tables {
            do {
                try await client
                    .from(table)
                    .delete()
                    .eq(column, value: userId.uuidString)
                    .execute()
            } catch {
                print("⚠️ Could not delete from \(table): \(error.localizedDescription)")
            }
        }
        
        try? await client.auth.signOut()
        
        await MainActor.run {
            PersistenceController.shared.clearAllUserData()
            UserDefaults.standard.set(true, forKey: "user_manually_signed_out")
            currentUser = nil
            isAuthenticated = false
            isLoading = false
        }
        
        print("⚠️ Fallback deletion complete - Note: auth.users entry still exists")
        print("⚠️ Run supabase_delete_user_function.sql to enable full account deletion")
    }
    
    func resetPassword(email: String) async throws {
        await MainActor.run { isLoading = true }
        
        do {
            try await client.auth.resetPasswordForEmail(email)
            await MainActor.run { isLoading = false }
            print("✅ Password reset email sent to: \(email)")
        } catch {
            await MainActor.run { isLoading = false }
            print("❌ Password reset error: \(error.localizedDescription)")
            throw error
        }
    }
    
    // MARK: - User Profile
    
    private func createUserProfile(userId: UUID, name: String, email: String, hasCompletedOnboarding: Bool = false) async throws {
        struct ProfileInsert: Encodable {
            let id: String
            let name: String
            let email: String
            let has_completed_onboarding: Bool
        }
        
        let profile = ProfileInsert(
            id: userId.uuidString,
            name: name,
            email: email,
            has_completed_onboarding: hasCompletedOnboarding
        )
        
        try await client
            .from("user_profiles")
            .insert(profile)
            .execute()
        
        // Create initial progress record
        try await createUserProgress(userId: userId)
        
        print("✅ User profile created (onboarding: \(hasCompletedOnboarding ? "complete" : "pending"))")
    }
    
    func updateUserProfile(
        name: String?,
        heightCm: Double?,
        weightKg: Double?,
        fitnessGoal: String?,
        experienceLevel: String?,
        equipment: [String]? = nil,
        availableDays: Int? = nil,
        workoutEnvironment: String? = nil,
        age: Int? = nil,
        gender: String? = nil
    ) async throws {
        guard let userId = currentUser?.id else { return }
        
        struct ProfileUpdate: Encodable {
            let name: String?
            let height_cm: Double?
            let weight_kg: Double?
            let fitness_goal: String?
            let experience_level: String?
            let equipment: [String]?
            let available_days: Int?
            let workout_environment: String?
            let age: Int?
            let gender: String?
            let updated_at: String
        }
        
        let update = ProfileUpdate(
            name: name,
            height_cm: heightCm,
            weight_kg: weightKg,
            fitness_goal: fitnessGoal,
            experience_level: experienceLevel,
            equipment: equipment,
            available_days: availableDays,
            workout_environment: workoutEnvironment,
            age: age,
            gender: gender,
            updated_at: ISO8601DateFormatter().string(from: Date())
        )
        
        try await client
            .from("user_profiles")
            .update(update)
            .eq("id", value: userId.uuidString)
            .execute()
        
        print("✅ User profile updated - Equipment: \(equipment ?? []), Days: \(availableDays ?? 0)")
    }
    
    /// Mark onboarding as complete in the cloud
    func markOnboardingComplete() async throws {
        guard let userId = currentUser?.id else { return }
        
        struct OnboardingUpdate: Encodable {
            let has_completed_onboarding: Bool
            let updated_at: String
        }
        
        let update = OnboardingUpdate(
            has_completed_onboarding: true,
            updated_at: ISO8601DateFormatter().string(from: Date())
        )
        
        try await client
            .from("user_profiles")
            .update(update)
            .eq("id", value: userId.uuidString)
            .execute()
        
        print("✅ Onboarding marked as complete in cloud")
    }
    
    func fetchUserProfile() async throws -> UserProfileDTO? {
        guard let userId = currentUser?.id else { return nil }
        
        let response: [UserProfileDTO] = try await client
            .from("user_profiles")
            .select()
            .eq("id", value: userId.uuidString)
            .execute()
            .value
        
        return response.first
    }
    
    // MARK: - Profile Sync from Core Data
    
    func syncCoreDataProfile(from user: User) async throws {
        guard currentUser != nil else {
            print("⚠️ No authenticated user to sync profile")
            return
        }
        
        struct ProfileSync: Encodable {
            let name: String?
            let email: String?
            let birthday: String?
            let age: Int?
            let gender: String?
            let height_cm: Double?
            let height_inches: Int?
            let weight_kg: Double?
            let weight_lbs: Double?
            let fitness_goal: String?
            let experience_level: String?
            let strength_level: String?  // Smart recommendation strength assessment
            let workout_environment: String?  // Gym, Home, Outdoor, Hybrid
            let equipment: [String]?
            let available_days: Int?
            let current_streak: Int?
            let longest_streak: Int?
            let total_workouts: Int?
            let xp: Int?
            let last_workout_date: String?
            let updated_at: String
            // Unit preferences
            let weight_unit: String?
            let height_unit: String?
            let distance_unit: String?
            let week_start_day: String?
        }
        
        // Get equipment array from User
        let equipmentArray = user.getEquipment() ?? []
        
        // Get unit preferences from UnitSettingsManager
        let unitSettings = UnitSettingsManager.shared
        
        let profile = ProfileSync(
            name: user.name,
            email: user.email,
            birthday: user.birthday,
            age: Int(user.age),
            gender: user.gender,
            height_cm: Double(user.height),
            height_inches: Int(user.heightInches),
            weight_kg: Double(user.weight),
            weight_lbs: user.weightLbs,
            fitness_goal: user.fitnessGoal,
            experience_level: user.experienceLevel,
            strength_level: user.strengthLevel,  // For smart weight recommendations
            workout_environment: user.workoutEnvironment,  // Gym, Home, Outdoor, Hybrid
            equipment: equipmentArray.isEmpty ? nil : equipmentArray,
            available_days: Int(user.availableDays),
            current_streak: Int(user.currentStreak),
            longest_streak: Int(user.longestStreak),
            total_workouts: Int(user.totalWorkouts),
            xp: Int(user.xp),
            last_workout_date: user.lastWorkoutDate != nil ? ISO8601DateFormatter().string(from: user.lastWorkoutDate!) : nil,
            updated_at: ISO8601DateFormatter().string(from: Date()),
            weight_unit: unitSettings.weightUnit.rawValue,
            height_unit: unitSettings.heightUnit.rawValue,
            distance_unit: unitSettings.distanceUnit.rawValue,
            week_start_day: unitSettings.startWeekOn.rawValue
        )
        
        guard let userId = currentUser?.id else { return }
        
        do {
            try await client
                .from("user_profiles")
                .update(profile)
                .eq("id", value: userId.uuidString)
                .execute()
            let ft = user.heightInches / 12
            let inches = user.heightInches % 12
            print("✅ Full profile synced to cloud:")
            print("   Name: \(user.name ?? "nil"), Birthday: \(user.birthday ?? "nil"), Age: \(user.age)")
            print("   Gender: \(user.gender ?? "nil")")
            print("   Height: \(ft)'\(inches)\" (\(user.heightInches) in / \(user.height)cm)")
            print("   Weight: \(user.weightLbs) lbs (\(user.weight)kg)")
            print("   Goal: \(user.fitnessGoal ?? "nil"), Level: \(user.experienceLevel ?? "nil")")
            print("   Strength: \(user.strengthLevel ?? "nil"), Environment: \(user.workoutEnvironment ?? "nil")")
            print("   Equipment: \(equipmentArray), Days: \(user.availableDays)")
            print("   XP: \(user.xp), Streak: \(user.currentStreak), Workouts: \(user.totalWorkouts)")
        } catch {
            print("❌ Error syncing Core Data profile: \(error)")
            // Don't throw - we don't want to block the app if sync fails
        }
    }
    
    // MARK: - Custom Exercises
    
    func createCustomExercise(
        name: String,
        category: String,
        primaryMuscles: [String],
        secondaryMuscles: [String],
        equipment: String,
        instructions: String,
        iconName: String
    ) async throws {
        guard let userId = currentUser?.id else {
            throw NSError(domain: "SupabaseManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        struct CustomExerciseInsert: Encodable {
            let user_id: String
            let name: String
            let category: String
            let primary_muscles: [String]
            let secondary_muscles: [String]
            let equipment: String
            let instructions: String
            let icon_name: String
        }
        
        let exercise = CustomExerciseInsert(
            user_id: userId.uuidString,
            name: name,
            category: category,
            primary_muscles: primaryMuscles,
            secondary_muscles: secondaryMuscles,
            equipment: equipment,
            instructions: instructions,
            icon_name: iconName
        )
        
        try await client
            .from("custom_exercises")
            .insert(exercise)
            .execute()
        
        print("✅ Custom exercise created: \(name)")
    }
    
    // MARK: - Exercise Migration
    
    func uploadExercises<T: Encodable>(_ exercises: [T]) async throws {
        try await client
            .from("exercises")
            .insert(exercises)
            .execute()
    }
    
    func fetchAllExercises() async throws -> [ExerciseDTO] {
        // ⚡️ PERFORMANCE: Use materialized view for public exercises (60-90% faster)
        // Fetch ALL exercises from Supabase using pagination
        // Supabase default limit is 1000, so we need to paginate to get all ~7000 exercises
        var allExercises: [ExerciseDTO] = []
        let pageSize = 1000
        var offset = 0
        var hasMoreData = true
        
        print("📥 Starting paginated fetch of all exercises...")
        
        // Try materialized view first (much faster), fallback to regular table
        let tableName = "mv_public_exercises"
        let fallbackTable = "exercises"
        var usingMaterializedView = true
        
        while hasMoreData {
            do {
                // Attempt to use materialized view first
                let response: [ExerciseDTO] = try await client
                    .from(tableName)
                    .select()
                    .range(from: offset, to: offset + pageSize - 1)
                    .execute()
                    .value
                
                allExercises.append(contentsOf: response)
                if usingMaterializedView {
                    print("⚡️ Using cached view for faster performance")
                    usingMaterializedView = false // Only log once
                }
                print("✅ Fetched \(response.count) exercises (total: \(allExercises.count))")
                
                if response.count < pageSize {
                    hasMoreData = false
                } else {
                    offset += pageSize
                }
            } catch {
                // Fallback to regular table if materialized view doesn't exist
                print("ℹ️ Materialized view not available, using regular table")
                let response: [ExerciseDTO] = try await client
                    .from(fallbackTable)
                    .select()
                    .eq("is_custom", value: false)
                    .range(from: offset, to: offset + pageSize - 1)
                    .execute()
                    .value
                
                allExercises.append(contentsOf: response)
                print("✅ Fetched \(response.count) exercises (total: \(allExercises.count))")
                
                if response.count < pageSize {
                    hasMoreData = false
                } else {
                    offset += pageSize
                }
                
                // Don't retry materialized view if it failed once
                usingMaterializedView = false
            }
        }
        
        print("✅ Fetched ALL \(allExercises.count) exercises from cloud")
        return allExercises
    }
    
    /// Fetch all exercises for audit (raw DTOs without filtering)
    func fetchAllExercisesRaw() async throws -> [ExerciseDTO] {
        var allExercises: [ExerciseDTO] = []
        let pageSize = 1000
        var offset = 0
        var hasMoreData = true
        
        print("📥 [AUDIT] Fetching all exercises for audit...")
        
        while hasMoreData {
            let response: [ExerciseDTO] = try await client
                .from("exercises")
                .select()
                .range(from: offset, to: offset + pageSize - 1)
                .order("name", ascending: true)
                .execute()
                .value
            
            allExercises.append(contentsOf: response)
            
            if response.count < pageSize {
                hasMoreData = false
            } else {
                offset += pageSize
            }
        }
        
        print("✅ [AUDIT] Fetched \(allExercises.count) exercises for audit")
        return allExercises
    }
    
    /// Update an exercise in the database
    func updateExercise(_ exercise: ExerciseDTO) async throws {
        guard let exerciseId = exercise.id else {
            throw NSError(domain: "SupabaseManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Exercise ID is required"])
        }
        
        // FULL update payload with all editable fields
        struct FullExerciseUpdate: Encodable {
            // Basic info
            let name: String
            let category: String
            let equipment: ExplicitNull<String>
            let primary_muscles: ExplicitNull<[String]>
            let secondary_muscles: ExplicitNull<[String]>
            let description: ExplicitNull<String>
            let instructions: ExplicitNull<String>
            let workout_type: ExplicitNull<String>  // Strength, Cardio, Stretch, Plyometrics
            
            // Movement classification
            let movement_pattern: ExplicitNull<String>
            let force_type: ExplicitNull<String>
            let movement_type: ExplicitNull<String>
            let laterality: ExplicitNull<String>
            
            // Position & Grip
            let body_position: ExplicitNull<String>
            let grip_type: ExplicitNull<String>
            let grip_width: ExplicitNull<String>
            
            // Ratings
            let difficulty_level: ExplicitNull<Int>
            let home_gym_friendly: ExplicitNull<Bool>
        }
        
        // Wrapper that encodes nil as explicit JSON null (not omitted)
        enum ExplicitNull<T: Encodable>: Encodable {
            case value(T)
            case null
            
            init(_ value: T?) {
                if let v = value {
                    self = .value(v)
                } else {
                    self = .null
                }
            }
            
            func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                switch self {
                case .value(let v):
                    try container.encode(v)
                case .null:
                    try container.encodeNil()
                }
            }
        }
        
        // Get muscles as arrays
        let primaryMusclesArray: [String]?
        if let raw = exercise.primaryMusclesRaw {
            let arr = raw.asArray.filter { !$0.isEmpty }
            primaryMusclesArray = arr.isEmpty ? nil : arr
        } else {
            primaryMusclesArray = nil
        }
        
        let secondaryMusclesArray: [String]?
        if let raw = exercise.secondaryMusclesRaw {
            let arr = raw.asArray.filter { !$0.isEmpty }
            secondaryMusclesArray = arr.isEmpty ? nil : arr
        } else {
            secondaryMusclesArray = nil
        }
        
        // Helper to convert empty strings to nil (so they save as NULL in DB)
        func emptyToNil(_ str: String?) -> String? {
            guard let s = str, !s.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return s
        }
        
        let update = FullExerciseUpdate(
            name: exercise.name,
            category: exercise.category,
            equipment: ExplicitNull(emptyToNil(exercise.equipment)),
            primary_muscles: ExplicitNull(primaryMusclesArray?.isEmpty == true ? nil : primaryMusclesArray),
            secondary_muscles: ExplicitNull(secondaryMusclesArray?.isEmpty == true ? nil : secondaryMusclesArray),
            description: ExplicitNull(emptyToNil(exercise.description)),
            instructions: ExplicitNull(emptyToNil(exercise.instructions)),
            workout_type: ExplicitNull(emptyToNil(exercise.workoutType)),
            movement_pattern: ExplicitNull(emptyToNil(exercise.movementPattern)),
            force_type: ExplicitNull(emptyToNil(exercise.forceType)),
            movement_type: ExplicitNull(emptyToNil(exercise.movementType)),
            laterality: ExplicitNull(emptyToNil(exercise.laterality)),
            body_position: ExplicitNull(emptyToNil(exercise.bodyPosition)),
            grip_type: ExplicitNull(emptyToNil(exercise.gripType)),
            grip_width: ExplicitNull(emptyToNil(exercise.gripWidth)),
            difficulty_level: ExplicitNull(exercise.difficultyLevel),
            home_gym_friendly: ExplicitNull(exercise.homeGymFriendly)
        )
        
        print("📤 ═══════════════════════════════════════")
        print("📤 SENDING FULL UPDATE TO SUPABASE")
        print("📤 ID: \(exerciseId)")
        print("📤 Name: \(exercise.name)")
        print("📤 Category: \(exercise.category)")
        print("📤 Equipment: \(exercise.equipment ?? "nil")")
        print("📤 Primary Muscles: \(primaryMusclesArray ?? [])")
        print("📤 Secondary Muscles: \(secondaryMusclesArray ?? [])")
        print("📤 Movement Pattern: \(exercise.movementPattern ?? "nil")")
        print("📤 Force Type: \(exercise.forceType ?? "nil")")
        print("📤 Movement Type: \(exercise.movementType ?? "nil")")
        print("📤 Laterality: \(exercise.laterality ?? "nil")")
        print("📤 Body Position: \(exercise.bodyPosition ?? "nil")")
        print("📤 Grip Type: \(exercise.gripType ?? "nil")")
        print("📤 Grip Width: \(exercise.gripWidth ?? "nil")")
        print("📤 Difficulty: \(exercise.difficultyLevel ?? -1)")
        print("📤 Home Gym Friendly: \(exercise.homeGymFriendly ?? false)")
        print("📤 ═══════════════════════════════════════")
        
        do {
            let response = try await client
                .from("exercises")
                .update(update)
                .eq("id", value: exerciseId)
                .execute()
            
            print("✅ ═══════════════════════════════════════")
            print("✅ SUPABASE UPDATE SUCCESS!")
            print("✅ HTTP Status: \(response.status)")
            print("✅ Exercise: \(exercise.name)")
            print("✅ ID: \(exerciseId)")
            print("✅ ═══════════════════════════════════════")
        } catch {
            print("❌ ═══════════════════════════════════════")
            print("❌ SUPABASE UPDATE FAILED!")
            print("❌ Error: \(error)")
            print("❌ ID: \(exerciseId)")
            print("❌ ═══════════════════════════════════════")
            throw error
        }
    }
    
    /// Delete an exercise from the database
    func deleteExercise(id: String) async throws {
        try await client
            .from("exercises")
            .delete()
            .eq("id", value: id)
            .execute()
        
        print("🗑️ Deleted exercise ID: \(id)")
    }
    
    /// @deprecated - exercise_pairings table was replaced by exercises table
    /// Exercise pairing logic is now handled by SmartExercisePairingEngine locally
    func fetchExercisePairings() async throws -> [ExercisePairingDTO] {
        // Table deprecated - return empty array
        print("⚠️ exercise_pairings table deprecated, using local SmartExercisePairingEngine instead")
        return []
    }
    
    func fetchEquipmentSubstitutions() async throws -> [EquipmentSubstitutionDTO] {
        let response: [EquipmentSubstitutionDTO] = try await client
            .from("equipment_substitutions")
            .select()
            .order("quality_score", ascending: false)
            .execute()
            .value
        
        print("✅ Fetched \(response.count) equipment substitutions")
        return response
    }
    
    func fetchCustomExercises() async throws -> [CustomExerciseDTO] {
        guard let userId = currentUser?.id else { return [] }
        
        let response: [CustomExerciseDTO] = try await client
            .from("custom_exercises")
            .select()
            .eq("user_id", value: userId.uuidString)
            .execute()
            .value
        
        print("✅ Fetched \(response.count) custom exercises")
        return response
    }
    
    // MARK: - Workout History
    
    func saveWorkout(
        name: String,
        date: Date,
        durationSeconds: Int,
        xpEarned: Int,
        exercises: [(name: String, sets: Int)],
        programId: String? = nil,
        programDay: Int? = nil
    ) async throws {
        guard let userId = currentUser?.id else { return }
        
        struct WorkoutInsert: Encodable {
            let user_id: String
            let name: String
            let date: String
            let duration_seconds: Int
            let xp_earned: Int
            let program_id: String?
            let program_day: Int?
        }
        
        let workout = WorkoutInsert(
            user_id: userId.uuidString,
            name: name,
            date: ISO8601DateFormatter().string(from: date),
            duration_seconds: durationSeconds,
            xp_earned: xpEarned,
            program_id: programId,
            program_day: programDay
        )
        
        let response: [WorkoutDTO] = try await client
            .from("workouts")
            .insert(workout)
            .select()
            .execute()
            .value
        
        if let workoutId = response.first?.id {
            // Save exercise details
            for exercise in exercises {
                try await saveWorkoutExercise(
                    workoutId: workoutId,
                    exerciseName: exercise.name,
                    setsCompleted: exercise.sets
                )
            }
            
            // Update user progress
            try await updateUserProgress(xpEarned: xpEarned)
        }
        
        print("✅ Workout saved: \(name)")
    }
    
    private func saveWorkoutExercise(workoutId: String, exerciseName: String, setsCompleted: Int) async throws {
        struct WorkoutExerciseInsert: Encodable {
            let workout_id: String
            let exercise_name: String
            let sets_completed: Int
        }
        
        let exercise = WorkoutExerciseInsert(
            workout_id: workoutId,
            exercise_name: exerciseName,
            sets_completed: setsCompleted
        )
        
        try await client
            .from("workout_exercises")
            .insert(exercise)
            .execute()
    }
    
    func fetchRecentWorkouts(limit: Int = 10) async throws -> [WorkoutDTO] {
        guard let userId = currentUser?.id else { return [] }
        
        let response: [WorkoutDTO] = try await client
            .from("workouts")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("date", ascending: false)
            .limit(limit)
            .execute()
            .value
        
        print("✅ Fetched \(response.count) recent workouts")
        return response
    }
    
    // MARK: - Exercise Popularity Tracking
    
    func logExerciseUsage(
        exerciseName: String,
        exerciseId: String,
        setsCompleted: Int,
        totalReps: Int,
        totalWeightKg: Double,
        workoutType: String,
        programId: String? = nil,
        workoutId: String? = nil
    ) async throws {
        guard let userId = currentUser?.id else { return }
        
        struct ExerciseUsageLog: Encodable {
            let user_id: String
            let exercise_id: String
            let exercise_name: String
            let workout_id: String?
            let sets_completed: Int
            let total_reps: Int
            let total_weight_kg: Double
            let workout_type: String
            let program_id: String?
        }
        
        let log = ExerciseUsageLog(
            user_id: userId.uuidString,
            exercise_id: exerciseId,
            exercise_name: exerciseName,
            workout_id: workoutId,
            sets_completed: setsCompleted,
            total_reps: totalReps,
            total_weight_kg: totalWeightKg,
            workout_type: workoutType,
            program_id: programId
        )
        
        try await client
            .from("exercise_usage_logs")
            .insert(log)
            .execute()
    }
    
    func fetchPopularExercises(limit: Int = 50) async throws -> [PopularExerciseDTO] {
        let response: [PopularExerciseDTO] = try await client
            .from("exercise_popularity_stats")
            .select()
            .order("popularity_score", ascending: false)
            .limit(limit)
            .execute()
            .value
        
        return response
    }
    
    func fetchTrendingExercises(limit: Int = 50) async throws -> [PopularExerciseDTO] {
        let response: [PopularExerciseDTO] = try await client
            .from("exercise_popularity_stats")
            .select()
            .order("trending_score", ascending: false)
            .limit(limit)
            .execute()
            .value
        
        return response
    }
    
    func fetchMostFavoritedExercises(limit: Int = 50) async throws -> [PopularExerciseDTO] {
        let response: [PopularExerciseDTO] = try await client
            .from("exercise_popularity_stats")
            .select()
            .order("favorite_count", ascending: false)
            .limit(limit)
            .execute()
            .value
        
        // Filter out exercises with 0 favorites
        return response.filter { $0.favoriteCount > 0 }
    }
    
    // MARK: - User Progress
    
    private func createUserProgress(userId: UUID) async throws {
        struct ProgressInsert: Encodable {
            let user_id: String
            let date: String
            let xp: Int
            let current_level: Int
            let current_streak: Int
            let longest_streak: Int
            let total_workouts: Int
            let last_workout_date: String?
        }
        
        let progress = ProgressInsert(
            user_id: userId.uuidString,
            date: ISO8601DateFormatter().string(from: Date()),
            xp: 0,
            current_level: 1,
            current_streak: 0,
            longest_streak: 0,
            total_workouts: 0,
            last_workout_date: nil
        )
        
        try await client
            .from("user_progress")
            .insert(progress)
            .execute()
    }
    
    private func updateUserProgress(xpEarned: Int) async throws {
        guard let userId = currentUser?.id else { return }
        
        // Fetch current progress
        let response: [UserProgressDTO] = try await client
            .from("user_progress")
            .select()
            .eq("user_id", value: userId.uuidString)
            .execute()
            .value
        
        guard let current = response.first else { return }
        
        let newTotalXp = current.totalXp + xpEarned
        let newLevel = (newTotalXp / 1000) + 1  // Level up every 1000 XP
        
        struct ProgressUpdate: Encodable {
            let total_xp: Int
            let current_level: Int
            let total_workouts: Int
            let last_workout_date: String
            let updated_at: String
        }
        
        let update = ProgressUpdate(
            total_xp: newTotalXp,
            current_level: newLevel,
            total_workouts: current.totalWorkouts + 1,
            last_workout_date: ISO8601DateFormatter().string(from: Date()),
            updated_at: ISO8601DateFormatter().string(from: Date())
        )
        
        try await client
            .from("user_progress")
            .update(update)
            .eq("user_id", value: userId.uuidString)
            .execute()
        
        print("✅ User progress updated: +\(xpEarned) XP")
    }
    
    func fetchUserProgress() async throws -> UserProgressDTO? {
        guard let userId = currentUser?.id else { return nil }
        
        let response: [UserProgressDTO] = try await client
            .from("user_progress")
            .select()
            .eq("user_id", value: userId.uuidString)
            .execute()
            .value
        
        return response.first
    }
    
    // MARK: - Favorites
    
    /// Toggle favorite - now stores exercise NAME for reliable syncing
    /// (Exercise IDs change on each sync, but names are stable)
    func toggleFavorite(exerciseId: String, exerciseType: String = "default", exerciseName: String? = nil) async throws {
        guard let userId = currentUser?.id else { return }
        
        // Use exercise name for lookup if provided (more reliable)
        // Fall back to ID for backwards compatibility
        let lookupField = exerciseName != nil ? "exercise_name" : "exercise_id"
        let lookupValue = exerciseName ?? exerciseId
        
        // Check if already favorited
        let existing: [UserFavoriteDTO] = try await client
            .from("user_favorites")
            .select()
            .eq("user_id", value: userId.uuidString)
            .eq(lookupField, value: lookupValue)
            .execute()
            .value
        
        if existing.isEmpty {
            // Add favorite - include exercise name for reliable syncing
            struct FavoriteInsert: Encodable {
                let user_id: String
                let exercise_id: String
                let exercise_type: String
                let exercise_name: String?
            }
            
            let favorite = FavoriteInsert(
                user_id: userId.uuidString,
                exercise_id: exerciseId,
                exercise_type: exerciseType,
                exercise_name: exerciseName
            )
            
            try await client
                .from("user_favorites")
                .insert(favorite)
                .execute()
            
            print("✅ Added to favorites: \(exerciseName ?? exerciseId)")
        } else {
            // Remove favorite
            try await client
                .from("user_favorites")
                .delete()
                .eq("id", value: existing.first!.id)
                .execute()
            
            print("✅ Removed from favorites: \(exerciseName ?? exerciseId)")
        }
    }
    
    /// Fetch favorites - returns exercise NAMES for reliable Core Data matching
    func fetchFavorites() async throws -> [String] {
        guard let userId = currentUser?.id else { return [] }
        
        let response: [UserFavoriteDTO] = try await client
            .from("user_favorites")
            .select()
            .eq("user_id", value: userId.uuidString)
            .execute()
            .value
        
        // Return exercise names (preferred) or IDs (fallback for old data)
        return response.compactMap { $0.exerciseName ?? $0.exerciseId }
    }
    
    /// Fetch favorite exercise names only (for reliable Core Data syncing)
    func fetchFavoriteExerciseNames() async throws -> [String] {
        guard let userId = currentUser?.id else { return [] }
        
        let response: [UserFavoriteDTO] = try await client
            .from("user_favorites")
            .select()
            .eq("user_id", value: userId.uuidString)
            .execute()
            .value
        
        // Return only entries that have exercise names
        return response.compactMap { $0.exerciseName }
    }
    
    // MARK: - Favorite Workouts (Cloud Sync)
    
    /// Save a favorite workout template to cloud
    func saveFavoriteWorkout(
        workoutName: String,
        exerciseNames: [String],
        originalWorkoutId: String
    ) async throws {
        guard let userId = currentUser?.id else { return }
        
        struct FavoriteWorkoutInsert: Encodable {
            let user_id: String
            let workout_name: String
            let exercise_names: [String]
            let original_workout_id: String
            let created_at: String
        }
        
        let favoriteWorkout = FavoriteWorkoutInsert(
            user_id: userId.uuidString,
            workout_name: workoutName,
            exercise_names: exerciseNames,
            original_workout_id: originalWorkoutId,
            created_at: ISO8601DateFormatter().string(from: Date())
        )
        
        try await client
            .from("favorite_workouts")
            .insert(favoriteWorkout)
            .execute()
        
        print("✅ Favorite workout saved to cloud: \(workoutName)")
    }
    
    /// Remove a favorite workout from cloud
    func removeFavoriteWorkout(originalWorkoutId: String) async throws {
        guard let userId = currentUser?.id else { return }
        
        try await client
            .from("favorite_workouts")
            .delete()
            .eq("user_id", value: userId.uuidString)
            .eq("original_workout_id", value: originalWorkoutId)
            .execute()
        
        print("✅ Favorite workout removed from cloud")
    }
    
    /// Fetch all favorite workouts from cloud
    func fetchFavoriteWorkouts() async throws -> [FavoriteWorkoutDTO] {
        guard let userId = currentUser?.id else { return [] }
        
        let response: [FavoriteWorkoutDTO] = try await client
            .from("favorite_workouts")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("created_at", ascending: false)
            .execute()
            .value
        
        print("✅ Fetched \(response.count) favorite workouts from cloud")
        return response
    }
    
    // MARK: - Admin/Analytics Queries (All Users)
    
    /// Get aggregate workout statistics across all users
    func fetchWorkoutAnalytics() async throws -> WorkoutAnalyticsDTO {
        // Get total workouts
        let workoutCountResponse: [WorkoutCountDTO] = try await client
            .from("workouts")
            .select("id")
            .execute()
            .value
        
        // Get unique users who have worked out
        let uniqueUsersResponse: [UniqueUserDTO] = try await client
            .from("workouts")
            .select("user_id")
            .execute()
            .value
        
        let uniqueUsers = Set(uniqueUsersResponse.map { $0.userId }).count
        
        // Get workouts in last 7 days
        let sevenDaysAgo = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-7 * 24 * 60 * 60))
        let recentWorkouts: [WorkoutDTO] = try await client
            .from("workouts")
            .select()
            .gte("date", value: sevenDaysAgo)
            .execute()
            .value
        
        return WorkoutAnalyticsDTO(
            totalWorkouts: workoutCountResponse.count,
            uniqueUsers: uniqueUsers,
            workoutsLast7Days: recentWorkouts.count,
            avgWorkoutsPerUser: uniqueUsers > 0 ? Double(workoutCountResponse.count) / Double(uniqueUsers) : 0
        )
    }
    
    /// Get top completed workouts across all users
    func fetchTopWorkouts(limit: Int = 10) async throws -> [TopWorkoutDTO] {
        struct WorkoutAggregation: Codable {
            let name: String?
            let count: Int
            
            enum CodingKeys: String, CodingKey {
                case name
                case count
            }
        }
        
        // Use RPC call for aggregation
        let response: [WorkoutAggregation] = try await client
            .rpc("get_top_workouts", params: ["result_limit": limit])
            .execute()
            .value
        
        return response.compactMap { agg in
            guard let name = agg.name else { return nil }
            return TopWorkoutDTO(workoutName: name, completionCount: agg.count)
        }
    }
    
    /// Get user statistics
    func fetchUserStatistics() async throws -> UserStatisticsDTO {
        let profiles: [UserProfileDTO] = try await client
            .from("user_profiles")
            .select()
            .execute()
            .value
        
        let totalUsers = profiles.count
        
        // Count users with recent activity (last 30 days)
        let thirtyDaysAgo = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-30 * 24 * 60 * 60))
        let activeUsers: [UserProfileDTO] = try await client
            .from("user_profiles")
            .select()
            .gte("updated_at", value: thirtyDaysAgo)
            .execute()
            .value
        
        return UserStatisticsDTO(
            totalUsers: totalUsers,
            activeUsersLast30Days: activeUsers.count,
            avgStreakLength: profiles.compactMap { $0.currentStreak }.reduce(0, +) / max(totalUsers, 1),
            avgTotalWorkouts: profiles.compactMap { $0.totalWorkouts }.reduce(0, +) / max(totalUsers, 1)
        )
    }
    
    /// Get step tracking statistics across all users
    func fetchStepStatisticsAllUsers() async throws -> StepAnalyticsDTO {
        // Get all step records from last 7 days
        let sevenDaysAgo = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-7 * 24 * 60 * 60))
        
        let stepData: [StepDataDTO] = try await client
            .from("step_tracking")
            .select()
            .gte("date", value: sevenDaysAgo)
            .execute()
            .value
        
        let totalSteps = stepData.reduce(0) { $0 + $1.steps }
        let avgStepsPerDay = stepData.isEmpty ? 0 : totalSteps / stepData.count
        let uniqueUsers = Set(stepData.map { $0.userId }).count
        let goalsMetCount = stepData.filter { $0.steps >= $0.goal }.count
        let goalCompletionRate = stepData.isEmpty ? 0.0 : Double(goalsMetCount) / Double(stepData.count)
        
        return StepAnalyticsDTO(
            totalStepsAllUsers: totalSteps,
            avgStepsPerDay: avgStepsPerDay,
            usersTrackingSteps: uniqueUsers,
            goalCompletionRate: goalCompletionRate,
            daysTracked: stepData.count
        )
    }
    
    // MARK: - Step Tracking (Cloud-Based)
    
    /// Save daily step data to cloud
    func saveStepData(date: Date, steps: Int, goal: Int) async throws {
        guard let userId = currentUser?.id else { return }
        
        struct StepDataUpsert: Encodable {
            let user_id: String
            let date: String
            let steps: Int
            let goal: Int
            let synced_at: String
        }
        
        let dateString = ISO8601DateFormatter().string(from: date)
        
        let stepData = StepDataUpsert(
            user_id: userId.uuidString,
            date: dateString,
            steps: steps,
            goal: goal,
            synced_at: ISO8601DateFormatter().string(from: Date())
        )
        
        // Upsert (insert or update) to avoid duplicates
        // The unique constraint on (user_id, date) ensures one record per day
        try await client
            .from("step_tracking")
            .upsert(stepData, onConflict: "user_id,date")
            .execute()
    }
    
    /// Batch save multiple days of step data in a single database call
    /// ⚡️ PERFORMANCE: Reduces 100 individual queries to 1 batch query
    func batchSaveStepData(_ dailySteps: [HealthKitManager.DailySteps], goal: Int) async throws {
        guard let userId = currentUser?.id else { return }
        guard !dailySteps.isEmpty else { return }
        
        struct StepDataUpsert: Encodable {
            let user_id: String
            let date: String
            let steps: Int
            let goal: Int
            let synced_at: String
        }
        
        let formatter = ISO8601DateFormatter()
        let syncTime = formatter.string(from: Date())
        
        // Convert all daily steps to upsert records
        let stepDataBatch = dailySteps.map { dailyStep in
            StepDataUpsert(
                user_id: userId.uuidString,
                date: formatter.string(from: dailyStep.date),
                steps: dailyStep.steps,
                goal: goal,
                synced_at: syncTime
            )
        }
        
        // Single batch upsert for all records
        try await client
            .from("step_tracking")
            .upsert(stepDataBatch, onConflict: "user_id,date")
            .execute()
    }
    
    /// Fetch recent step data from cloud
    func fetchRecentSteps(days: Int = 30) async throws -> [StepDataDTO] {
        guard let userId = currentUser?.id else { return [] }
        
        let calendar = Calendar.current
        let startDate = calendar.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let startDateString = ISO8601DateFormatter().string(from: startDate)
        
        let response: [StepDataDTO] = try await client
            .from("step_tracking")
            .select()
            .eq("user_id", value: userId.uuidString)
            .gte("date", value: startDateString)
            .order("date", ascending: false)
            .execute()
            .value
        
        print("✅ Fetched \(response.count) days of step data from cloud")
        return response
    }
    
    /// Update user's daily step goal
    func updateStepGoal(_ goal: Int) async throws {
        guard let userId = currentUser?.id else { return }
        
        struct StepGoalUpdate: Encodable {
            let daily_step_goal: Int
            let updated_at: String
        }
        
        let update = StepGoalUpdate(
            daily_step_goal: goal,
            updated_at: ISO8601DateFormatter().string(from: Date())
        )
        
        try await client
            .from("user_profiles")
            .update(update)
            .eq("id", value: userId.uuidString)
            .execute()
        
        print("✅ Step goal updated to \(goal)")
    }
    
    /// Fetch user's step goal from cloud
    func fetchStepGoal() async throws -> Int? {
        guard let userId = currentUser?.id else { return nil }
        
        struct StepGoalResponse: Codable {
            let daily_step_goal: Int?
            
            enum CodingKeys: String, CodingKey {
                case daily_step_goal = "daily_step_goal"
            }
        }
        
        let response: [StepGoalResponse] = try await client
            .from("user_profiles")
            .select("daily_step_goal")
            .eq("id", value: userId.uuidString)
            .execute()
            .value
        
        return response.first?.daily_step_goal
    }
    
    /// Get step statistics for a date range
    func fetchStepStatistics(startDate: Date, endDate: Date) async throws -> StepStatisticsDTO? {
        guard let userId = currentUser?.id else { return nil }
        
        let startString = ISO8601DateFormatter().string(from: startDate)
        let endString = ISO8601DateFormatter().string(from: endDate)
        
        let response: [StepDataDTO] = try await client
            .from("step_tracking")
            .select()
            .eq("user_id", value: userId.uuidString)
            .gte("date", value: startString)
            .lte("date", value: endString)
            .execute()
            .value
        
        guard !response.isEmpty else { return nil }
        
        let totalSteps = response.reduce(0) { $0 + $1.steps }
        let averageSteps = totalSteps / response.count
        let maxSteps = response.map { $0.steps }.max() ?? 0
        let daysGoalMet = response.filter { $0.steps >= $0.goal }.count
        
        return StepStatisticsDTO(
            totalSteps: totalSteps,
            averageSteps: averageSteps,
            maxSteps: maxSteps,
            daysTracked: response.count,
            daysGoalMet: daysGoalMet,
            goalCompletionRate: Double(daysGoalMet) / Double(response.count)
        )
    }
    
    // MARK: - Comprehensive Data Sync
    
    /// Syncs all user data from cloud to Core Data
    func syncAllDataFromCloud() async {
        print("🔄 Starting comprehensive data sync from cloud...")
        
        do {
            // FIRST: Sync user profile from cloud to Core Data
            // This restores the user's profile when they log back in
            if let cloudProfile = try await fetchUserProfile() {
                await syncUserProfileToCoreData(profile: cloudProfile)
            }
            
            // 🛡️ Only sync exercises if no workout is active (prevents data loss!)
            if !WorkoutManager.shared.isWorkoutActive {
            await ExerciseLibraryService.shared.syncExercisesFromCloud()
            } else {
                print("⚠️ [SYNC] Skipping exercise sync during active workout")
            }
            
            // Sync exercise favorites (using names for reliable matching)
            let favoriteNames = try await fetchFavorites()
            await syncFavoritesToCoreData(favoriteNames: favoriteNames)
            
            // Sync custom exercises
            let customExercises = try await fetchCustomExercises()
            await syncCustomExercisesToCoreData(customExercises: customExercises)
            
            // Sync favorite workouts
            let favoriteWorkouts = try await fetchFavoriteWorkouts()
            await syncFavoriteWorkoutsToCoreData(favoriteWorkouts: favoriteWorkouts)
            
            // Sync workout history from cloud
            let workoutHistory = try await fetchWorkoutHistory()
            await syncWorkoutHistoryToCoreData(workouts: workoutHistory)
            
            // Sync meal logs from cloud
            let mealLogs = try await fetchMealLogs()
            await syncMealLogsToCoreData(meals: mealLogs)
            
            print("✅ Comprehensive data sync completed!")
        } catch {
            print("❌ Error during comprehensive sync: \(error)")
        }
    }
    
    /// Restores user profile from cloud to Core Data
    private func syncUserProfileToCoreData(profile: UserProfileDTO) async {
        let viewContext = PersistenceController.shared.container.viewContext
        
        await MainActor.run {
            // Check if user already exists
            let fetchRequest: NSFetchRequest<User> = User.fetchRequest()
            
            do {
                let existingUsers = try viewContext.fetch(fetchRequest)
                let user: User
                
                if let existingUser = existingUsers.first {
                    user = existingUser
                    print("📝 Updating existing user from cloud profile")
                } else {
                    user = User(context: viewContext)
                    user.id = UUID(uuidString: profile.id) ?? UUID()
                    user.createdAt = Date()
                    print("👤 Creating new user from cloud profile")
                }
                
                // Update ALL user fields from cloud
                user.name = profile.name
                user.email = profile.email
                user.fitnessGoal = profile.fitnessGoal
                user.experienceLevel = profile.experienceLevel
                
                // Use the cloud's onboarding status - new social users will have this as false
                // Only set to true if the cloud says so (meaning they completed onboarding before)
                user.hasCompletedOnboarding = profile.hasCompletedOnboarding ?? false
                
                // Sync all profile data
                if let birthday = profile.birthday {
                    user.birthday = birthday
                }
                if let age = profile.age {
                    user.age = Int16(age)
                }
                if let gender = profile.gender {
                    user.gender = gender
                }
                if let height = profile.heightCm {
                    user.height = Int16(height)
                    UserDefaults.standard.set(Int(height), forKey: "userHeight")
                }
                if let heightInches = profile.heightInches {
                    user.heightInches = Int16(heightInches)
                }
                if let weight = profile.weightKg {
                    user.weight = Int16(weight)
                    UserDefaults.standard.set(Int(weight), forKey: "userWeight")
                }
                if let weightLbs = profile.weightLbs {
                    user.weightLbs = weightLbs
                }
                if let equipment = profile.equipment {
                    user.equipment = equipment as NSObject
                }
                if let availableDays = profile.availableDays {
                    user.availableDays = Int16(availableDays)
                }
                
                // Sync progress data
                user.currentStreak = Int16(profile.currentStreak ?? 0)
                user.longestStreak = Int16(profile.longestStreak ?? 0)
                user.totalWorkouts = Int32(profile.totalWorkouts ?? 0)
                user.xp = Int32(profile.xp ?? 0)
                
                if let lastWorkoutDateStr = profile.lastWorkoutDate {
                    user.lastWorkoutDate = ISO8601DateFormatter().date(from: lastWorkoutDateStr)
                }
                
                // Sync gender to UserDefaults for nutrition calculations
                if let gender = profile.gender {
                    UserDefaults.standard.set(gender, forKey: "userGender")
                }
                
                // Restore unit preferences from cloud (using loadFromCloud to prevent sync loops)
                UnitSettingsManager.shared.loadFromCloud(
                    weightUnit: profile.weightUnit,
                    heightUnit: profile.heightUnit,
                    distanceUnit: profile.distanceUnit,
                    weekStartDay: profile.weekStartDay
                )
                
                try viewContext.save()
                print("✅ Full user profile synced from cloud:")
                print("   Name: \(profile.name ?? "nil"), Age: \(profile.age ?? 0)")
                print("   Height: \(profile.heightCm ?? 0)cm, Weight: \(profile.weightKg ?? 0)kg")
                print("   Goal: \(profile.fitnessGoal ?? "nil"), Level: \(profile.experienceLevel ?? "nil")")
                print("   Equipment: \(profile.equipment ?? []), Days: \(profile.availableDays ?? 0)")
                print("   XP: \(profile.xp ?? 0), Streak: \(profile.currentStreak ?? 0), Workouts: \(profile.totalWorkouts ?? 0)")
                print("   Units: Weight=\(profile.weightUnit ?? "default"), Height=\(profile.heightUnit ?? "default")")
                
                // CRITICAL: Notify UserManager to reload its state
                // This ensures hasCompletedOnboarding is updated after login sync
                UserManager.shared.reloadCurrentUser()
                
            } catch {
                print("❌ Error syncing user profile to Core Data: \(error)")
            }
        }
    }
    
    // MARK: - Workout History Cloud Sync
    
    /// Saves a completed workout to the cloud
    func saveWorkoutToCloud(workout: Workout) async throws {
        guard let userId = currentUser?.id,
              let workoutId = workout.id?.uuidString else { 
            print("⚠️ [WORKOUT SAVE] Cannot save - no user or workout ID")
            return 
        }
        
        print("💾 [WORKOUT SAVE] Saving workout '\(workout.name ?? "Unnamed")' for user \(userId.uuidString.prefix(8))...")
        
        // Build exercise data
        var exerciseDTOs: [WorkoutExerciseDTO] = []
        
        if let workoutExercises = workout.exercises?.allObjects as? [WorkoutExercise] {
            for we in workoutExercises.sorted(by: { $0.order < $1.order }) {
                var setDTOs: [WorkoutSetDTO] = []
                
                if let sets = we.sets?.allObjects as? [WorkoutSet] {
                    for set in sets.sorted(by: { $0.setNumber < $1.setNumber }) {
                        let setDTO = WorkoutSetDTO(
                            id: set.id?.uuidString ?? UUID().uuidString,
                            setNumber: Int(set.setNumber),
                            reps: Int(set.reps),
                            weight: set.weight,
                            isCompleted: set.isCompleted
                        )
                        setDTOs.append(setDTO)
                    }
                }
                
                let exerciseDTO = WorkoutExerciseDTO(
                    id: we.id?.uuidString ?? UUID().uuidString,
                    exerciseName: we.exercise?.name ?? "Unknown",
                    order: Int(we.order),
                    sets: setDTOs
                )
                exerciseDTOs.append(exerciseDTO)
            }
        }
        
        let workoutDTO = WorkoutHistoryDTO(
            id: workoutId,
            userId: userId.uuidString,
            name: workout.name ?? "Workout",
            date: ISO8601DateFormatter().string(from: workout.date ?? Date()),
            duration: Int(workout.duration),
            isCompleted: workout.isCompleted,
            xpEarned: Int(workout.xpEarned),
            notes: workout.notes,
            exercises: exerciseDTOs
        )
        
        try await client
            .from("workout_history")
            .upsert(workoutDTO)
            .execute()
        
        print("☁️ Workout saved to cloud: \(workout.name ?? "Workout")")
    }
    
    /// Fetches workout history from cloud
    func fetchWorkoutHistory() async throws -> [WorkoutHistoryDTO] {
        guard let userId = currentUser?.id else { 
            print("⚠️ [WORKOUT SYNC] No authenticated user - cannot fetch workout history")
            return [] 
        }
        
        print("🔍 [WORKOUT SYNC] Fetching workouts for user: \(userId.uuidString)")
        
        let response: [WorkoutHistoryDTO] = try await client
            .from("workout_history")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("date", ascending: false)
            .execute()
            .value
        
        print("📥 [WORKOUT SYNC] Fetched \(response.count) workouts from cloud for user \(userId.uuidString.prefix(8))...")
        return response
    }
    
    /// Syncs workout history from cloud to Core Data
    private func syncWorkoutHistoryToCoreData(workouts: [WorkoutHistoryDTO]) async {
        let viewContext = PersistenceController.shared.container.viewContext
        
        await MainActor.run {
            // Get or create user
            let userRequest: NSFetchRequest<User> = User.fetchRequest()
            userRequest.fetchLimit = 1
            
            guard let user = try? viewContext.fetch(userRequest).first else {
                print("⚠️ No user found for workout history sync")
                return
            }
            
            for workoutDTO in workouts {
                // Check if workout already exists
                let fetchRequest: NSFetchRequest<Workout> = Workout.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "id == %@", UUID(uuidString: workoutDTO.id) as CVarArg? ?? UUID() as CVarArg)
                
                do {
                    let existing = try viewContext.fetch(fetchRequest)
                    let workout: Workout
                    
                    if let existingWorkout = existing.first {
                        // Workout exists - check if exercises need to be synced
                        workout = existingWorkout
                        let existingExerciseCount = workout.exercises?.count ?? 0
                        let cloudExerciseCount = workoutDTO.exercises.count
                        
                        // Only sync exercises if they're missing (cloud has more than local)
                        if cloudExerciseCount > existingExerciseCount {
                            print("🔄 Syncing \(cloudExerciseCount) exercises for existing workout '\(workout.name ?? "")'")
                            
                            // Remove old exercises if any
                            if let oldExercises = workout.exercises?.allObjects as? [WorkoutExercise] {
                                for oldExercise in oldExercises {
                                    viewContext.delete(oldExercise)
                                }
                            }
                            
                            // Add exercises from cloud
                            for exerciseDTO in workoutDTO.exercises {
                                // Try to find the exercise by name FIRST
                                let exerciseRequest: NSFetchRequest<Exercise> = Exercise.fetchRequest()
                                exerciseRequest.predicate = NSPredicate(format: "name == %@", exerciseDTO.exerciseName)
                                
                                guard let exercise = try? viewContext.fetch(exerciseRequest).first else {
                                    // Skip this workout exercise if we can't find the exercise
                                    print("⚠️ [WORKOUT SYNC] Skipping exercise '\(exerciseDTO.exerciseName)' - not found in database")
                                    continue
                                }
                                
                                // Only create WorkoutExercise if we found the Exercise
                                let workoutExercise = WorkoutExercise(context: viewContext)
                                workoutExercise.id = UUID(uuidString: exerciseDTO.id) ?? UUID()
                                workoutExercise.order = Int16(exerciseDTO.order)
                                workoutExercise.workout = workout
                                workoutExercise.exercise = exercise
                                
                                // Create sets
                                for setDTO in exerciseDTO.sets {
                                    let workoutSet = WorkoutSet(context: viewContext)
                                    workoutSet.id = UUID(uuidString: setDTO.id) ?? UUID()
                                    workoutSet.setNumber = Int16(setDTO.setNumber)
                                    workoutSet.reps = Int16(setDTO.reps)
                                    workoutSet.weight = setDTO.weight
                                    workoutSet.isCompleted = setDTO.isCompleted
                                    workoutSet.workoutExercise = workoutExercise
                                }
                            }
                        }
                    } else {
                        // Create new workout
                        workout = Workout(context: viewContext)
                        workout.id = UUID(uuidString: workoutDTO.id) ?? UUID()
                        workout.name = workoutDTO.name
                        workout.date = ISO8601DateFormatter().date(from: workoutDTO.date)
                        workout.duration = Int32(workoutDTO.duration)
                        workout.isCompleted = workoutDTO.isCompleted
                        workout.xpEarned = Int32(workoutDTO.xpEarned)
                        workout.notes = workoutDTO.notes
                        workout.user = user
                        
                        // Create exercises and sets
                        for exerciseDTO in workoutDTO.exercises {
                            // Try to find the exercise by name FIRST
                            let exerciseRequest: NSFetchRequest<Exercise> = Exercise.fetchRequest()
                            exerciseRequest.predicate = NSPredicate(format: "name == %@", exerciseDTO.exerciseName)
                            
                            guard let exercise = try? viewContext.fetch(exerciseRequest).first else {
                                // Skip this workout exercise if we can't find the exercise
                                print("⚠️ [WORKOUT SYNC] Skipping exercise '\(exerciseDTO.exerciseName)' - not found in database")
                                continue
                            }
                            
                            // Only create WorkoutExercise if we found the Exercise
                            let workoutExercise = WorkoutExercise(context: viewContext)
                            workoutExercise.id = UUID(uuidString: exerciseDTO.id) ?? UUID()
                            workoutExercise.order = Int16(exerciseDTO.order)
                            workoutExercise.workout = workout
                            workoutExercise.exercise = exercise
                            
                            // Create sets
                            for setDTO in exerciseDTO.sets {
                                let workoutSet = WorkoutSet(context: viewContext)
                                workoutSet.id = UUID(uuidString: setDTO.id) ?? UUID()
                                workoutSet.setNumber = Int16(setDTO.setNumber)
                                workoutSet.reps = Int16(setDTO.reps)
                                workoutSet.weight = setDTO.weight
                                workoutSet.isCompleted = setDTO.isCompleted
                                workoutSet.workoutExercise = workoutExercise
                            }
                        }
                    }
                } catch {
                    print("❌ Error checking existing workout: \(error)")
                }
            }
            
            do {
                try viewContext.save()
                print("✅ Synced \(workouts.count) workouts from cloud")
            } catch {
                print("❌ Error saving workout history: \(error)")
            }
        }
    }
    
    // MARK: - Meal Logs Cloud Sync
    
    /// Saves a meal entry to the cloud
    func saveMealToCloud(meal: MealEntry) async throws {
        guard let userId = currentUser?.id,
              let mealId = meal.id?.uuidString else { return }
        
        let mealDTO = MealLogDTO(
            id: mealId,
            userId: userId.uuidString,
            date: ISO8601DateFormatter().string(from: meal.date ?? Date()),
            mealType: meal.mealType ?? "Other",
            foodName: meal.foodName ?? "Unknown",
            quantity: meal.quantity,
            unit: meal.unit,
            calories: Int(meal.calories),
            protein: Int(meal.protein),
            carbs: Int(meal.carbs),
            fat: Int(meal.fat),
            fdcId: meal.fdcId > 0 ? Int(meal.fdcId) : nil
        )
        
        try await client
            .from("meal_logs")
            .upsert(mealDTO)
            .execute()
        
        print("☁️ Meal saved to cloud: \(meal.foodName ?? "Unknown")")
    }
    
    /// Fetches meal logs from cloud
    func fetchMealLogs() async throws -> [MealLogDTO] {
        guard let userId = currentUser?.id else { return [] }
        
        let response: [MealLogDTO] = try await client
            .from("meal_logs")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("date", ascending: false)
            .execute()
            .value
        
        print("📥 Fetched \(response.count) meals from cloud")
        return response
    }
    
    /// Deletes a meal entry from the cloud
    func deleteMealFromCloud(mealId: UUID) async throws {
        guard let userId = currentUser?.id else { 
            print("⚠️ [CLOUD] No user - skipping cloud delete")
            return 
        }
        
        try await client
            .from("meal_logs")
            .delete()
            .eq("id", value: mealId.uuidString)
            .eq("user_id", value: userId.uuidString)
            .execute()
        
        print("🗑️ [CLOUD] Meal deleted from cloud: \(mealId)")
    }
    
    /// Syncs meal logs from cloud to Core Data
    private func syncMealLogsToCoreData(meals: [MealLogDTO]) async {
        let viewContext = PersistenceController.shared.container.viewContext
        
        await MainActor.run {
            // Get or create user
            let userRequest: NSFetchRequest<User> = User.fetchRequest()
            userRequest.fetchLimit = 1
            
            guard let user = try? viewContext.fetch(userRequest).first else {
                print("⚠️ No user found for meal logs sync")
                return
            }
            
            for mealDTO in meals {
                // Check if meal already exists
                let fetchRequest: NSFetchRequest<MealEntry> = MealEntry.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "id == %@", UUID(uuidString: mealDTO.id) as CVarArg? ?? UUID() as CVarArg)
                
                do {
                    let existing = try viewContext.fetch(fetchRequest)
                    if existing.isEmpty {
                        // Create new meal
                        let meal = MealEntry(context: viewContext)
                        meal.id = UUID(uuidString: mealDTO.id) ?? UUID()
                        meal.date = ISO8601DateFormatter().date(from: mealDTO.date)
                        meal.mealType = mealDTO.mealType
                        meal.foodName = mealDTO.foodName
                        meal.quantity = mealDTO.quantity
                        meal.unit = mealDTO.unit
                        meal.calories = Int32(mealDTO.calories)
                        meal.protein = Int32(mealDTO.protein)
                        meal.carbs = Int32(mealDTO.carbs)
                        meal.fat = Int32(mealDTO.fat)
                        meal.fdcId = Int32(mealDTO.fdcId ?? 0)
                        meal.user = user
                    }
                } catch {
                    print("❌ Error checking existing meal: \(error)")
                }
            }
            
            do {
                try viewContext.save()
                print("✅ Synced \(meals.count) meals from cloud")
            } catch {
                print("❌ Error saving meal logs: \(error)")
            }
        }
    }
    
    /// Sync favorites to Core Data - matches by exercise NAME (not ID, since IDs change on sync)
    private func syncFavoritesToCoreData(favoriteNames: [String]) async {
        let viewContext = PersistenceController.shared.container.viewContext
        
        // Normalize names for case-insensitive matching
        let normalizedFavoriteNames = Set(favoriteNames.map { $0.lowercased().trimmingCharacters(in: .whitespaces) })
        
        await MainActor.run {
            let fetchRequest: NSFetchRequest<Exercise> = Exercise.fetchRequest()
            
            do {
                let allExercises = try viewContext.fetch(fetchRequest)
                var matchedCount = 0
                
                for exercise in allExercises {
                    if let name = exercise.name {
                        let normalizedName = name.lowercased().trimmingCharacters(in: .whitespaces)
                        let isFavorite = normalizedFavoriteNames.contains(normalizedName)
                        if isFavorite {
                            matchedCount += 1
                        }
                        exercise.isFavorite = isFavorite
                    }
                }
                
                try viewContext.save()
                print("✅ Synced \(matchedCount)/\(favoriteNames.count) favorites to Core Data (matched by name)")
            } catch {
                print("❌ Error syncing favorites to Core Data: \(error)")
            }
        }
    }
    
    private func syncCustomExercisesToCoreData(customExercises: [CustomExerciseDTO]) async {
        let viewContext = PersistenceController.shared.container.viewContext
        
        await MainActor.run {
            for customExercise in customExercises {
                // Check if exercise already exists
                let fetchRequest: NSFetchRequest<Exercise> = Exercise.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "name == %@", customExercise.name)
                
                do {
                    let existing = try viewContext.fetch(fetchRequest)
                    if existing.isEmpty {
                        // Create new exercise
                        let exercise = Exercise(context: viewContext)
                        exercise.id = UUID(uuidString: customExercise.id) ?? UUID()
                        exercise.name = customExercise.name
                        exercise.category = customExercise.category
                        
                        // Combine primary and secondary muscles into muscleGroups
                        var allMuscles = customExercise.primaryMuscles ?? []
                        if let secondaryMuscles = customExercise.secondaryMuscles {
                            allMuscles.append(contentsOf: secondaryMuscles)
                        }
                        exercise.muscleGroups = allMuscles as NSObject
                        
                        exercise.equipment = customExercise.equipment
                        exercise.instructions = customExercise.instructions
                        // Store custom indicator in instructions with a special marker
                        let customMarker = "[CUSTOM_EXERCISE|ICON:\(customExercise.iconName ?? "figure.walk")]"
                        if let existingInstructions = customExercise.instructions {
                            exercise.instructions = "\(customMarker)\n\(existingInstructions)"
                        } else {
                            exercise.instructions = customMarker
                        }
                        
                        print("✅ Added custom exercise from cloud: \(customExercise.name)")
                    }
                } catch {
                    print("❌ Error syncing custom exercise: \(error)")
                }
            }
            
            do {
                try viewContext.save()
                print("✅ Synced \(customExercises.count) custom exercises to Core Data")
            } catch {
                print("❌ Error saving custom exercises to Core Data: \(error)")
            }
        }
    }
    
    private func syncFavoriteWorkoutsToCoreData(favoriteWorkouts: [FavoriteWorkoutDTO]) async {
        let viewContext = PersistenceController.shared.container.viewContext
        
        await MainActor.run {
            // Get all the original workout IDs from cloud favorites
            let cloudFavoriteIds = Set(favoriteWorkouts.map { $0.originalWorkoutId })
            
            // Fetch all completed workouts
            let fetchRequest: NSFetchRequest<Workout> = Workout.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "isCompleted == YES")
            
            do {
                let allWorkouts = try viewContext.fetch(fetchRequest)
                
                for workout in allWorkouts {
                    if let workoutId = workout.id?.uuidString {
                        // Mark as favorite if in cloud favorites, otherwise unfavorite
                        let shouldBeFavorite = cloudFavoriteIds.contains(workoutId)
                        if workout.isFavorite != shouldBeFavorite {
                            workout.isFavorite = shouldBeFavorite
                        }
                    }
                }
                
                try viewContext.save()
                print("✅ Synced \(favoriteWorkouts.count) favorite workouts to Core Data")
            } catch {
                print("❌ Error syncing favorite workouts to Core Data: \(error)")
            }
        }
    }
}

// MARK: - Data Transfer Objects (DTOs)

struct UserProfileDTO: Codable {
    let id: String
    let name: String?
    let email: String?
    let birthday: String?
    let age: Int?
    let gender: String?
    let heightCm: Double?
    let heightInches: Int?
    let weightKg: Double?
    let weightLbs: Double?
    let fitnessGoal: String?
    let experienceLevel: String?
    let strengthLevel: String?  // For smart weight recommendations
    let equipment: [String]?
    let availableDays: Int?
    let bmr: Double?
    let tdee: Double?
    let proteinGoalG: Double?
    let carbsGoalG: Double?
    let fatGoalG: Double?
    let dailyCalorieGoal: Int?
    let dailyProteinGoal: Int?
    let dailyCarbsGoal: Int?
    let dailyFatGoal: Int?
    let currentStreak: Int?
    let longestStreak: Int?
    let totalWorkouts: Int?
    let xp: Int?
    let lastWorkoutDate: String?
    let updatedAt: String?
    let hasCompletedOnboarding: Bool?
    // Unit preferences
    let weightUnit: String?
    let heightUnit: String?
    let distanceUnit: String?
    let weekStartDay: String?
    
    enum CodingKeys: String, CodingKey {
        case id, name, email, birthday, age, gender, bmr, tdee, equipment, xp
        case heightCm = "height_cm"
        case heightInches = "height_inches"
        case weightKg = "weight_kg"
        case weightLbs = "weight_lbs"
        case fitnessGoal = "fitness_goal"
        case experienceLevel = "experience_level"
        case strengthLevel = "strength_level"
        case availableDays = "available_days"
        case proteinGoalG = "protein_goal_g"
        case carbsGoalG = "carbs_goal_g"
        case fatGoalG = "fat_goal_g"
        case dailyCalorieGoal = "daily_calorie_goal"
        case dailyProteinGoal = "daily_protein_goal"
        case dailyCarbsGoal = "daily_carbs_goal"
        case dailyFatGoal = "daily_fat_goal"
        case currentStreak = "current_streak"
        case longestStreak = "longest_streak"
        case totalWorkouts = "total_workouts"
        case lastWorkoutDate = "last_workout_date"
        case updatedAt = "updated_at"
        case weightUnit = "weight_unit"
        case heightUnit = "height_unit"
        case distanceUnit = "distance_unit"
        case weekStartDay = "week_start_day"
        case hasCompletedOnboarding = "has_completed_onboarding"
    }
}

struct ExerciseDTO: Codable {
    let id: String?
    let name: String
    let category: String
    let equipment: String?
    let primaryMusclesRaw: MuscleField?   // Can be String or [String] in DB
    let secondaryMusclesRaw: MuscleField? // Can be String or [String] in DB
    let description: String?
    let videoCode: String?          // Unique identifier for the video
    let videoFilename: String?      // Filename for this gender's video (e.g., "44171201-Sumo-Squat.mp4")
    let gender: String?             // "Male" or "Female"
    let isCustom: Bool?
    
    // Enhanced metadata from improved CSV
    let movementPattern: String?
    let forceType: String?
    let movementType: String?
    let laterality: String?
    let planeOfMotion: String?
    let difficultyLevel: Int?
    let complexityScore: Int?
    let strengthRating: Int?
    let hypertrophyRating: Int?
    let powerRating: Int?
    let enduranceRating: Int?
    let bodyPosition: String?
    let benchAngle: String?
    let gripType: String?
    let gripWidth: String?
    let optimalRepRangeMin: Int?
    let optimalRepRangeMax: Int?
    let placementInWorkout: String?
    let fatigabilityRaw: FlexibleInt?
    var fatigability: Int? { fatigabilityRaw?.value }
    let popularityScore: Int?
    let homeGymFriendly: Bool?
    let workoutType: String?
    let practicalityScore: Int?  // 0-100 score for exercise practicality
    
    // Goal-based classification fields (from exercise_goal_classifications.csv)
    let fatLossRating: Int?           // 1-10: How good for Get Lean goal
    let generalFitnessRating: Int?    // 1-10: How good for General Fitness goal
    let isCompound: Bool?             // Multi-joint movement
    let supersetable: Bool?           // Can be done back-to-back
    
    // Exercise family & swap system fields
    let exerciseFamily: String?           // Movement family (e.g., "bicep_curl", "bench_press")
    let baseExerciseName: String?         // Canonical name without equipment
    let complementaryFamilies: String?    // Comma-separated related families
    let isEquipmentPrimary: Bool?         // Is this the gold standard variant?
    let equipmentCategory: String?        // Normalized: barbell, dumbbell, cable, etc.
    let durationBased: Bool?              // Track by time instead of reps?
    let recommendedSets: Int?             // Default sets for this exercise
    let restSeconds: Int?                 // Recommended rest between sets
    let musclesWorkedCount: Int?          // Number of muscle groups engaged
    let priorityBuildMuscle: Int?         // Sort priority for Build Muscle goal
    let priorityGetLean: Int?             // Sort priority for Get Lean goal
    let priorityHome: Int?                // Sort priority for home training
    let priorityGym: Int?                 // Sort priority for gym training
    
    // Helper to handle Int fields that might come as String from database
    struct FlexibleInt: Codable {
        let value: Int
        
        // Direct initializer for creating from Int
        init(_ value: Int) {
            self.value = value
        }
        
        // Optional initializer
        init?(_ value: Int?) {
            guard let v = value else { return nil }
            self.value = v
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let intValue = try? container.decode(Int.self) {
                self.value = intValue
            } else if let stringValue = try? container.decode(String.self), let parsed = Int(stringValue) {
                self.value = parsed
            } else {
                self.value = 0  // Default to 0 if can't parse
            }
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(value)
        }
    }
    
    // Helper enum to handle both String and [String] from database
    enum MuscleField: Codable {
        case string(String)
        case array([String])
        
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let stringValue = try? container.decode(String.self) {
                self = .string(stringValue)
            } else if let arrayValue = try? container.decode([String].self) {
                self = .array(arrayValue)
            } else {
                self = .string("")
            }
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let value):
                try container.encode(value)
            case .array(let value):
                try container.encode(value)
            }
        }
        
        var asArray: [String] {
            switch self {
            case .string(let str):
                return str.components(separatedBy: ", ").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            case .array(let arr):
                return arr.filter { !$0.isEmpty }
            }
        }
    }
    
    // Helper to get muscles as array (handles both String and [String] formats)
    var primaryMusclesArray: [String] {
        primaryMusclesRaw?.asArray ?? []
    }
    
    var secondaryMusclesArray: [String] {
        secondaryMusclesRaw?.asArray ?? []
    }
    
    // Helper fields (not directly from DB)
    let instructions: String?
    let stepsToPerform: String?  // How-to steps for the exercise
    
    enum CodingKeys: String, CodingKey {
        case id, name, category, equipment, description, instructions, gender
        case stepsToPerform = "steps_to_perform"
        case primaryMusclesRaw = "primary_muscles"
        case workoutType = "workout_type"
        case secondaryMusclesRaw = "secondary_muscles"
        case videoCode = "video_code"
        case videoFilename = "video_filename"
        case isCustom = "is_custom"
        case movementPattern = "movement_pattern"
        case forceType = "force_type"
        case planeOfMotion = "plane_of_motion"
        case movementType = "movement_type"
        case laterality
        case difficultyLevel = "difficulty_level"
        case complexityScore = "complexity_score"
        case strengthRating = "strength_rating"
        case hypertrophyRating = "hypertrophy_rating"
        case powerRating = "power_rating"
        case enduranceRating = "endurance_rating"
        case bodyPosition = "body_position"
        case benchAngle = "bench_angle"
        case gripType = "grip_type"
        case gripWidth = "grip_width"
        case optimalRepRangeMin = "optimal_rep_range_min"
        case optimalRepRangeMax = "optimal_rep_range_max"
        case placementInWorkout = "placement_in_workout"
        case fatigabilityRaw = "fatigability"
        case popularityScore = "popularity_score"
        case homeGymFriendly = "home_gym_friendly"
        case practicalityScore = "practicality_score"
        case fatLossRating = "fat_loss_rating"
        case generalFitnessRating = "general_fitness_rating"
        case isCompound = "is_compound"
        case supersetable
        case exerciseFamily = "exercise_family"
        case baseExerciseName = "base_exercise_name"
        case complementaryFamilies = "complementary_families"
        case isEquipmentPrimary = "is_equipment_primary"
        case equipmentCategory = "equipment_category"
        case durationBased = "duration_based"
        case recommendedSets = "recommended_sets"
        case restSeconds = "rest_seconds"
        case musclesWorkedCount = "muscles_worked_count"
        case priorityBuildMuscle = "priority_build_muscle"
        case priorityGetLean = "priority_get_lean"
        case priorityHome = "priority_home"
        case priorityGym = "priority_gym"
    }
}

struct CustomExerciseDTO: Codable {
    let id: String
    let userId: String
    let name: String
    let category: String?
    let primaryMuscles: [String]?
    let secondaryMuscles: [String]?
    let equipment: String?
    let instructions: String?
    let iconName: String?
    
    enum CodingKeys: String, CodingKey {
        case id, name, category, equipment, instructions
        case userId = "user_id"
        case primaryMuscles = "primary_muscles"
        case secondaryMuscles = "secondary_muscles"
        case iconName = "icon_name"
    }
}

struct ExercisePairingDTO: Codable {
    let primaryExercise: String
    let secondaryExercise: String
    let pairingFocus: [String]?
    let rationale: String?
    let intensityBalance: String?
    let recommendedTempos: [String]?
    let equipmentContext: [String: String]?
    let synergyScore: Double?
    
    enum CodingKeys: String, CodingKey {
        case primaryExercise = "primary_exercise"
        case secondaryExercise = "secondary_exercise"
        case pairingFocus = "pairing_focus"
        case rationale
        case intensityBalance = "intensity_balance"
        case recommendedTempos = "recommended_tempos"
        case equipmentContext = "equipment_context"
        case synergyScore = "synergy_score"
    }
}

struct EquipmentSubstitutionDTO: Codable {
    let sourceEquipment: String
    let substituteEquipment: String
    let qualityScore: Double?
    let cues: String?
    let notes: String?
    
    enum CodingKeys: String, CodingKey {
        case sourceEquipment = "source_equipment"
        case substituteEquipment = "substitute_equipment"
        case qualityScore = "quality_score"
        case cues, notes
    }
}

struct WorkoutDTO: Codable {
    let id: String
    let userId: String
    let name: String?
    let date: String
    let durationSeconds: Int
    let xpEarned: Int
    let programId: String?
    let programDay: Int?
    
    enum CodingKeys: String, CodingKey {
        case id, name, date
        case userId = "user_id"
        case durationSeconds = "duration_seconds"
        case xpEarned = "xp_earned"
        case programId = "program_id"
        case programDay = "program_day"
    }
}

struct UserProgressDTO: Codable {
    let id: String
    let userId: String
    let totalXp: Int
    let currentLevel: Int
    let workoutStreak: Int
    let lastWorkoutDate: String?
    let totalWorkouts: Int
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case totalXp = "total_xp"
        case currentLevel = "current_level"
        case workoutStreak = "workout_streak"
        case lastWorkoutDate = "last_workout_date"
        case totalWorkouts = "total_workouts"
    }
}

struct UserFavoriteDTO: Codable {
    let id: String
    let userId: String
    let exerciseId: String
    let exerciseType: String
    let exerciseName: String?  // Added for reliable syncing (IDs change, names don't)
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case exerciseId = "exercise_id"
        case exerciseType = "exercise_type"
        case exerciseName = "exercise_name"
    }
}

struct FavoriteWorkoutDTO: Codable {
    let id: String
    let userId: String
    let workoutName: String
    let exerciseNames: [String]
    let originalWorkoutId: String
    let createdAt: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case workoutName = "workout_name"
        case exerciseNames = "exercise_names"
        case originalWorkoutId = "original_workout_id"
        case createdAt = "created_at"
    }
}

struct PopularExerciseDTO: Codable {
    let exerciseId: String
    let exerciseName: String
    let totalUses: Int
    let uniqueUsers: Int
    let popularityScore: Double
    let trendingScore: Double
    let avgSetsPerUse: Double
    let completionRate: Double
    let usesLast7Days: Int
    let usesLast30Days: Int
    let favoriteCount: Int
    
    enum CodingKeys: String, CodingKey {
        case exerciseId = "exercise_id"
        case exerciseName = "exercise_name"
        case totalUses = "total_uses"
        case uniqueUsers = "unique_users"
        case popularityScore = "popularity_score"
        case trendingScore = "trending_score"
        case avgSetsPerUse = "avg_sets_per_use"
        case completionRate = "completion_rate"
        case usesLast7Days = "uses_last_7_days"
        case usesLast30Days = "uses_last_30_days"
        case favoriteCount = "favorite_count"
    }
}

// MARK: - Step Tracking DTOs

struct StepDataDTO: Codable {
    let id: String?
    let userId: String
    let date: String
    let steps: Int
    let goal: Int
    let syncedAt: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case date
        case steps
        case goal
        case syncedAt = "synced_at"
    }
}

struct StepStatisticsDTO: Codable {
    let totalSteps: Int
    let averageSteps: Int
    let maxSteps: Int
    let daysTracked: Int
    let daysGoalMet: Int
    let goalCompletionRate: Double
}

// MARK: - Admin Analytics DTOs

struct WorkoutAnalyticsDTO: Codable {
    let totalWorkouts: Int
    let uniqueUsers: Int
    let workoutsLast7Days: Int
    let avgWorkoutsPerUser: Double
}

struct TopWorkoutDTO: Codable {
    let workoutName: String
    let completionCount: Int
}

struct UserStatisticsDTO: Codable {
    let totalUsers: Int
    let activeUsersLast30Days: Int
    let avgStreakLength: Int
    let avgTotalWorkouts: Int
}

struct StepAnalyticsDTO: Codable {
    let totalStepsAllUsers: Int
    let avgStepsPerDay: Int
    let usersTrackingSteps: Int
    let goalCompletionRate: Double
    let daysTracked: Int
}

struct WorkoutCountDTO: Codable {
    let id: String
}

struct UniqueUserDTO: Codable {
    let userId: String
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
    }
}

// MARK: - Workout History DTOs
struct WorkoutHistoryDTO: Codable {
    let id: String
    let userId: String
    let name: String
    let date: String
    let duration: Int
    let isCompleted: Bool
    let xpEarned: Int
    let notes: String?
    let exercises: [WorkoutExerciseDTO]
    
    enum CodingKeys: String, CodingKey {
        case id, name, date, duration, notes, exercises
        case userId = "user_id"
        case isCompleted = "is_completed"
        case xpEarned = "xp_earned"
    }
}

struct WorkoutExerciseDTO: Codable {
    let id: String
    let exerciseName: String
    let order: Int
    let sets: [WorkoutSetDTO]
    
    enum CodingKeys: String, CodingKey {
        case id, order, sets
        case exerciseName = "exercise_name"
    }
}

struct WorkoutSetDTO: Codable {
    let id: String
    let setNumber: Int
    let reps: Int
    let weight: Double
    let isCompleted: Bool
    
    enum CodingKeys: String, CodingKey {
        case id, reps, weight
        case setNumber = "set_number"
        case isCompleted = "is_completed"
    }
}

// MARK: - Meal Log DTOs
struct MealLogDTO: Codable {
    let id: String
    let userId: String
    let date: String
    let mealType: String
    let foodName: String
    let quantity: Double
    let unit: String?
    let calories: Int
    let protein: Int
    let carbs: Int
    let fat: Int
    let fdcId: Int?
    
    enum CodingKeys: String, CodingKey {
        case id, date, quantity, unit, calories, protein, carbs, fat
        case userId = "user_id"
        case mealType = "meal_type"
        case foodName = "food_name"
        case fdcId = "fdc_id"
    }
}

