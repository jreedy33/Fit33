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
    
    // MARK: - Cached Date Formatter (Performance Optimization)
    /// ISO8601DateFormatter is expensive to create - reuse this instance
    private let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    
    /// Convert Date to ISO8601 string for database storage
    @inline(__always)
    private func dateToISO(_ date: Date) -> String {
        iso8601Formatter.string(from: date)
    }
    
    /// Convert ISO8601 string to Date (nil if invalid)
    @inline(__always)
    private func isoToDate(_ string: String) -> Date? {
        ISO8601Parser.parse(string)
    }
    
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
    /// Check if a user profile exists AND has meaningful data (not just an empty row)
    /// Returns false if profile is missing OR if critical fields are null
    private func verifyUserExists(userId: UUID) async -> Bool {
        do {
            // Select critical fields to verify the profile has actual data
            let response: [UserProfileDTO] = try await client
                .from("user_profiles")
                .select("id, name, email, has_completed_onboarding")
                .eq("id", value: userId.uuidString)
                .execute()
                .value
            
            // Check if profile exists AND has meaningful data
            guard let profile = response.first else {
                print("📝 [VERIFY] No profile found for user \(userId.uuidString)")
                return false
            }
            
            // If name and email are both null/empty, treat as incomplete profile
            let hasName = profile.name != nil && !profile.name!.isEmpty
            let hasEmail = profile.email != nil && !profile.email!.isEmpty
            
            if !hasName && !hasEmail {
                print("⚠️ [VERIFY] Profile exists but has no name or email - treating as new user")
                return false
            }
            
            print("✅ [VERIFY] Valid profile found - Name: \(profile.name ?? "nil"), Email: \(profile.email ?? "nil")")
            return true
        } catch {
            print("⚠️ [VERIFY] Error checking user profile: \(error)")
            // IMPORTANT: If we can't verify, assume user is NEW so profile gets created
            // This is safer than assuming they exist and leaving them with null data
            return false
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
    /// - Parameters:
    ///   - idToken: The identity token from Apple
    ///   - nonce: The nonce used for the request
    ///   - appleProvidedName: The full name provided by Apple (only available on first sign-in)
    @discardableResult
    func signInWithApple(idToken: String, nonce: String, appleProvidedName: String? = nil) async throws -> Bool {
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
                
                // Priority for name:
                // 1. appleProvidedName (directly from Apple credentials - only first sign-in)
                // 2. Persisted name from previous sign-in (UserDefaults)
                // 3. Supabase user metadata
                // 4. Email prefix (if not private relay)
                // 5. Fallback "Apple User"
                var appleName: String
                
                if let providedName = appleProvidedName, !providedName.isEmpty, providedName != "Apple User" {
                    appleName = providedName
                    // Persist for future sign-ins (Apple only provides name once)
                    UserDefaults.standard.set(providedName, forKey: "apple_user_name_\(session.user.id.uuidString)")
                    print("💾 [APPLE] Persisted user name for future sign-ins: \(providedName)")
                } else if let persistedName = UserDefaults.standard.string(forKey: "apple_user_name_\(session.user.id.uuidString)"), !persistedName.isEmpty {
                    appleName = persistedName
                    print("📂 [APPLE] Using persisted name from previous sign-in: \(persistedName)")
                } else if let fullName = session.user.userMetadata["full_name"] as? String, !fullName.isEmpty {
                    appleName = fullName
                } else if let name = session.user.userMetadata["name"] as? String, !name.isEmpty {
                    appleName = name
                } else if let email = session.user.email, !email.contains("privaterelay") {
                    // Use part of email as name if no name provided
                    appleName = email.components(separatedBy: "@").first ?? "Apple User"
                } else {
                    appleName = "Apple User"
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
    
    /// Handle OAuth callback URL (for Google/Facebook Sign-In)
    func handleOAuthCallback(url: URL) async throws -> (isNewUser: Bool, socialUsername: String?) {
        await MainActor.run { isLoading = true }
        
        do {
            let session = try await client.auth.session(from: url)
            
            // Check if this is a new user (no profile exists yet)
            let profileExists = await verifyUserExists(userId: session.user.id)
            var isNewUser = false
            var socialUsername: String? = nil
            
            if !profileExists {
                // Determine provider from metadata
                let provider = session.user.appMetadata["provider"] as? String ?? "unknown"
                
                let userEmail: String
                let userName: String
                
                if provider == "facebook" {
                    // Facebook-specific data extraction
                    userEmail = session.user.email ?? "facebook_user_\(session.user.id.uuidString.prefix(8))@facebook.com"
                    userName = session.user.userMetadata["full_name"] as? String 
                        ?? session.user.userMetadata["name"] as? String 
                        ?? "Facebook User"
                    
                    // Extract username if available (could be Facebook or connected Instagram username)
                    socialUsername = session.user.userMetadata["user_name"] as? String 
                        ?? session.user.userMetadata["username"] as? String
                    
                    print("📘 Facebook Sign-In - Username: @\(socialUsername ?? "unknown"), Name: \(userName)")
                } else {
                    // Google or other OAuth provider
                    userEmail = session.user.email ?? "oauth_user_\(session.user.id.uuidString.prefix(8))@email.com"
                    userName = session.user.userMetadata["full_name"] as? String 
                        ?? session.user.userMetadata["name"] as? String 
                        ?? "User"
                    print("🔐 OAuth Sign-In - Provider: \(provider), Name: \(userName)")
                }
                
                try await createUserProfile(userId: session.user.id, name: userName, email: userEmail, hasCompletedOnboarding: false)
                isNewUser = true
            }
            
            await MainActor.run {
                currentUser = session.user
                isAuthenticated = true
                isLoading = false
                UserDefaults.standard.removeObject(forKey: "user_manually_signed_out")
            }
            print("✅ OAuth Sign-In successful: \(session.user.email ?? "unknown")")
            
            // Only sync for existing users
            if !isNewUser {
                await syncAllDataFromCloud()
            }
            
            return (isNewUser, socialUsername)
        } catch {
            await MainActor.run { isLoading = false }
            print("❌ OAuth callback error: \(error.localizedDescription)")
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
    
    /// Get the OAuth URL for Facebook Sign-In
    func getFacebookOAuthURL() -> URL? {
        let redirectURL = "fit33://login-callback"
        
        var components = URLComponents(string: "\(supabaseURL)/auth/v1/authorize")
        components?.queryItems = [
            URLQueryItem(name: "provider", value: "facebook"),
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
                
                // Clear profile photo cache - critical for multi-user scenarios
                ProfilePhotoCache.shared.clearCache()
                
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
            // Delete profile photo from Supabase Storage first
            await deleteProfilePhotoFromStorage(userId: userId)
            
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
                // Clear profile photo cache - critical for multi-user scenarios
                ProfilePhotoCache.shared.clearCache()
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
    
    /// Delete profile photo from Supabase Storage
    private func deleteProfilePhotoFromStorage(userId: UUID) async {
        do {
            let filePath = "profile_photos/\(userId.uuidString).jpg"
            try await client.storage
                .from("avatars")
                .remove(paths: [filePath])
            print("🗑️ Profile photo deleted from storage")
        } catch {
            // Photo might not exist, which is fine
            print("⚠️ Could not delete profile photo from storage: \(error.localizedDescription)")
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
        
        // Delete profile photo from storage
        await deleteProfilePhotoFromStorage(userId: userId)
        
        try? await client.auth.signOut()
        
        await MainActor.run {
            PersistenceController.shared.clearAllUserData()
            // Clear profile photo cache - critical for multi-user scenarios
            ProfilePhotoCache.shared.clearCache()
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
        
        // Use upsert to handle edge cases where profile might partially exist
        try await client
            .from("user_profiles")
            .upsert(profile, onConflict: "id")
            .execute()
        
        // Create initial progress record (also uses upsert)
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
            updated_at: dateToISO(Date())
        )
        
        try await client
            .from("user_profiles")
            .update(update)
            .eq("id", value: userId.uuidString)
            .execute()
        
        print("✅ User profile updated - Equipment: \(equipment ?? []), Days: \(availableDays ?? 0)")
    }
    
    // MARK: - Profile Photo
    
    /// Upload a profile photo and update the user profile with the URL
    func uploadProfilePhoto(imageData: Data) async throws -> String {
        guard let userId = currentUser?.id else {
            throw NSError(domain: "SupabaseManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "No user logged in"])
        }
        
        let fileName = "profile_photos/\(userId.uuidString).jpg"
        let bucket = "avatars"
        
        // Upload to Supabase Storage
        try await client.storage
            .from(bucket)
            .upload(
                path: fileName,
                file: imageData,
                options: FileOptions(
                    cacheControl: "3600",
                    contentType: "image/jpeg",
                    upsert: true
                )
            )
        
        // Get the public URL
        let publicUrl = try client.storage
            .from(bucket)
            .getPublicURL(path: fileName)
        
        // Update the user profile with the photo URL
        struct PhotoUpdate: Encodable {
            let profile_photo_url: String
            let updated_at: String
        }
        
        let update = PhotoUpdate(
            profile_photo_url: publicUrl.absoluteString,
            updated_at: dateToISO(Date())
        )
        
        try await client
            .from("user_profiles")
            .update(update)
            .eq("id", value: userId.uuidString)
            .execute()
        
        print("✅ Profile photo uploaded: \(publicUrl.absoluteString)")
        return publicUrl.absoluteString
    }
    
    /// Delete the current profile photo
    func deleteProfilePhoto() async throws {
        guard let userId = currentUser?.id else { return }
        
        let fileName = "profile_photos/\(userId.uuidString).jpg"
        let bucket = "avatars"
        
        // Delete from storage
        try await client.storage
            .from(bucket)
            .remove(paths: [fileName])
        
        // Update the user profile to remove the photo URL
        struct PhotoUpdate: Encodable {
            let profile_photo_url: String?
            let updated_at: String
        }
        
        let update = PhotoUpdate(
            profile_photo_url: nil,
            updated_at: dateToISO(Date())
        )
        
        try await client
            .from("user_profiles")
            .update(update)
            .eq("id", value: userId.uuidString)
            .execute()
        
        print("✅ Profile photo deleted")
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
            updated_at: dateToISO(Date())
        )
        
        try await client
            .from("user_profiles")
            .update(update)
            .eq("id", value: userId.uuidString)
            .execute()
        
        print("✅ Onboarding marked as complete in cloud")
    }
    
    // MARK: - Username Management
    
    /// Check if a username is available (case-insensitive)
    func isUsernameAvailable(_ username: String) async throws -> Bool {
        // Client-side validation first
        let cleanUsername = username.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard cleanUsername.count >= 3 else { return false }
        guard cleanUsername.count <= 30 else { return false }
        
        // Check alphanumeric + underscore only
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        guard cleanUsername.unicodeScalars.allSatisfy({ allowedCharacters.contains($0) }) else {
            return false
        }
        
        // Check with database
        let result: Bool = try await client
            .rpc("is_username_available", params: ["check_username": cleanUsername])
            .execute()
            .value
        
        return result
    }
    
    /// Set the username for the current user
    func setUsername(_ username: String) async throws {
        print("🔧 [USERNAME] ========== SET USERNAME START ==========")
        print("🔧 [USERNAME] Input username: '\(username)'")
        
        guard let user = currentUser else {
            print("❌ [USERNAME] Not authenticated - currentUser is nil")
            throw NSError(domain: "SupabaseManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        print("👤 [USERNAME] Current user ID: \(user.id.uuidString)")
        print("👤 [USERNAME] User email: \(user.email ?? "nil")")
        
        // Debug: Check profile state before setting username
        await debugProfileState()
        
        let cleanUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        print("🧹 [USERNAME] Cleaned username: '\(cleanUsername)'")
        
        // Validate on client side first
        guard cleanUsername.count >= 3 else {
            print("❌ [USERNAME] Username too short: \(cleanUsername.count) chars")
            throw NSError(domain: "SupabaseManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Username must be at least 3 characters"])
        }
        
        var rpcSucceeded = false
        
        // Try RPC first
        do {
            print("📡 [USERNAME] Trying Method 1: RPC set_username with: '\(cleanUsername)'")
            let success: Bool = try await client
                .rpc("set_username", params: ["new_username": cleanUsername])
                .execute()
                .value
            
            print("📡 [USERNAME] RPC returned: \(success)")
            
            if success {
                rpcSucceeded = true
                print("✅ [USERNAME] RPC success!")
            } else {
                print("⚠️ [USERNAME] RPC returned false, will try direct update")
            }
            
        } catch {
            print("⚠️ [USERNAME] RPC failed: \(error.localizedDescription)")
            print("⚠️ [USERNAME] Will try direct table update as fallback...")
        }
        
        // Fallback: Direct table update if RPC failed
        if !rpcSucceeded {
            do {
                print("📡 [USERNAME] Trying Method 2: Direct table update")
                
                try await client
                    .from("user_profiles")
                    .update(["username": cleanUsername])
                    .eq("id", value: user.id.uuidString)
                    .execute()
                
                print("✅ [USERNAME] Direct update executed")
                
            } catch {
                print("❌ [USERNAME] Direct update also failed: \(error.localizedDescription)")
                throw error
            }
        }
        
        // Verify the username was actually saved
        print("🔍 [USERNAME] Verifying save...")
        let savedUsername = try await getCurrentUsername()
        if savedUsername == cleanUsername {
            print("✅ [USERNAME] VERIFIED: Username saved as '@\(cleanUsername)'")
        } else if let saved = savedUsername {
            print("⚠️ [USERNAME] Mismatch! Expected '\(cleanUsername)' but got '\(saved)'")
        } else {
            print("❌ [USERNAME] FAILED: Username is still NULL after save attempt!")
            throw NSError(domain: "SupabaseManager", code: 4, userInfo: [NSLocalizedDescriptionKey: "Username failed to save to database"])
        }
        
        print("🔧 [USERNAME] ========== SET USERNAME END ==========")
    }
    
    /// Get the current user's username
    func getCurrentUsername() async throws -> String? {
        guard let userId = currentUser?.id else { return nil }
        
        struct UsernameResult: Decodable {
            let username: String?
        }
        
        let response: [UsernameResult] = try await client
            .from("user_profiles")
            .select("username")
            .eq("id", value: userId.uuidString)
            .execute()
            .value
        
        return response.first?.username
    }
    
    /// Debug: Check profile state and username
    func debugProfileState() async {
        print("🔍 [DEBUG] ============= PROFILE STATE CHECK =============")
        
        guard let user = currentUser else {
            print("❌ [DEBUG] No current user - not authenticated")
            return
        }
        
        print("✅ [DEBUG] Current User ID: \(user.id.uuidString)")
        print("✅ [DEBUG] User Email: \(user.email ?? "nil")")
        print("✅ [DEBUG] Is Authenticated: \(isAuthenticated)")
        
        // Check if profile exists
        do {
            struct ProfileCheck: Decodable {
                let id: String
                let username: String?
                let name: String?
                let email: String?
                let has_completed_onboarding: Bool?
            }
            
            let profiles: [ProfileCheck] = try await client
                .from("user_profiles")
                .select("id, username, name, email, has_completed_onboarding")
                .eq("id", value: user.id.uuidString)
                .execute()
                .value
            
            if let profile = profiles.first {
                print("✅ [DEBUG] Profile EXISTS in database:")
                print("   - ID: \(profile.id)")
                print("   - Username: \(profile.username ?? "NULL")")
                print("   - Name: \(profile.name ?? "NULL")")
                print("   - Email: \(profile.email ?? "NULL")")
                print("   - Onboarding Complete: \(profile.has_completed_onboarding ?? false)")
            } else {
                print("❌ [DEBUG] Profile NOT FOUND in user_profiles table!")
                print("   Searched for id = '\(user.id.uuidString)'")
            }
        } catch {
            print("❌ [DEBUG] Failed to query profile: \(error)")
        }
        
        print("🔍 [DEBUG] ============================================")
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
    
    /// Syncs the local Core Data user profile to Supabase cloud
    /// Uses UPSERT to ensure data is saved even if profile row is missing or empty
    func syncCoreDataProfile(from user: User) async throws {
        guard let authUser = currentUser else {
            print("⚠️ [SYNC] No authenticated Supabase user - cannot sync profile")
            return
        }
        
        print("☁️ [SYNC] Starting profile sync for user: \(authUser.id.uuidString)")
        print("☁️ [SYNC] Core Data user: name=\(user.name ?? "nil"), email=\(user.email ?? "nil")")
        
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
            last_workout_date: user.lastWorkoutDate != nil ? dateToISO( user.lastWorkoutDate!) : nil,
            updated_at: dateToISO(Date()),
            weight_unit: unitSettings.weightUnit.rawValue,
            height_unit: unitSettings.heightUnit.rawValue,
            distance_unit: unitSettings.distanceUnit.rawValue,
            week_start_day: unitSettings.startWeekOn.rawValue
        )
        
        guard let userId = currentUser?.id else { 
            print("❌ [SYNC] No authenticated user ID - cannot sync profile")
            return 
        }
        
        // Use UPSERT instead of UPDATE to ensure data is saved even if profile doesn't exist
        // This fixes the issue where UPDATE silently fails if no matching row exists
        struct ProfileUpsert: Encodable {
            let id: String
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
            let strength_level: String?
            let workout_environment: String?
            let equipment: [String]?
            let available_days: Int?
            let current_streak: Int?
            let longest_streak: Int?
            let total_workouts: Int?
            let xp: Int?
            let last_workout_date: String?
            let updated_at: String
            let weight_unit: String?
            let height_unit: String?
            let distance_unit: String?
            let week_start_day: String?
            let has_completed_onboarding: Bool
        }
        
        let upsertProfile = ProfileUpsert(
            id: userId.uuidString,
            name: profile.name,
            email: profile.email,
            birthday: profile.birthday,
            age: profile.age,
            gender: profile.gender,
            height_cm: profile.height_cm,
            height_inches: profile.height_inches,
            weight_kg: profile.weight_kg,
            weight_lbs: profile.weight_lbs,
            fitness_goal: profile.fitness_goal,
            experience_level: profile.experience_level,
            strength_level: profile.strength_level,
            workout_environment: profile.workout_environment,
            equipment: profile.equipment,
            available_days: profile.available_days,
            current_streak: profile.current_streak,
            longest_streak: profile.longest_streak,
            total_workouts: profile.total_workouts,
            xp: profile.xp,
            last_workout_date: profile.last_workout_date,
            updated_at: profile.updated_at,
            weight_unit: profile.weight_unit,
            height_unit: profile.height_unit,
            distance_unit: profile.distance_unit,
            week_start_day: profile.week_start_day,
            has_completed_onboarding: true
        )
        
        try await client
            .from("user_profiles")
            .upsert(upsertProfile, onConflict: "id")
            .execute()
        
        print("✅ [SYNC] Profile UPSERTED to cloud for user: \(userId.uuidString)")
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
    
    /// 🔒 Track in-flight exercise fetch to prevent duplicates
    private static var exerciseFetchTask: Task<[ExerciseDTO], Error>?
    private static var cachedExercises: [ExerciseDTO]?
    private static var cacheTimestamp: Date?
    private static let exerciseCacheTTL: TimeInterval = 60 // 60 second cache
    
    func fetchAllExercises() async throws -> [ExerciseDTO] {
        // ⚡️ PERFORMANCE: Check cache first
        if let cached = SupabaseManager.cachedExercises,
           let timestamp = SupabaseManager.cacheTimestamp,
           Date().timeIntervalSince(timestamp) < SupabaseManager.exerciseCacheTTL {
            print("⚡️ [EXERCISES] Returning \(cached.count) cached exercises")
            return cached
        }
        
        // ⚡️ PERFORMANCE: Reuse in-flight request if one exists
        if let existingTask = SupabaseManager.exerciseFetchTask {
            print("⚡️ [EXERCISES] Reusing in-flight fetch request")
            return try await existingTask.value
        }
        
        // Create new fetch task
        let task = Task<[ExerciseDTO], Error> {
            defer { SupabaseManager.exerciseFetchTask = nil }
            return try await self.performExerciseFetch()
        }
        
        SupabaseManager.exerciseFetchTask = task
        
        let result = try await task.value
        
        // Cache the result
        SupabaseManager.cachedExercises = result
        SupabaseManager.cacheTimestamp = Date()
        
        return result
    }
    
    /// Internal exercise fetch implementation
    private func performExerciseFetch() async throws -> [ExerciseDTO] {
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
            date: dateToISO( date),
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
            date: dateToISO(Date()),
            xp: 0,
            current_level: 1,
            current_streak: 0,
            longest_streak: 0,
            total_workouts: 0,
            last_workout_date: nil
        )
        
        // Use upsert to handle existing records (e.g., when user profile was deleted but progress remained)
        try await client
            .from("user_progress")
            .upsert(progress, onConflict: "user_id,date")
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
            last_workout_date: dateToISO(Date()),
            updated_at: dateToISO(Date())
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
            created_at: dateToISO(Date())
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
        let sevenDaysAgo = dateToISO( Date().addingTimeInterval(-7 * 24 * 60 * 60))
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
        let thirtyDaysAgo = dateToISO( Date().addingTimeInterval(-30 * 24 * 60 * 60))
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
        let sevenDaysAgo = dateToISO( Date().addingTimeInterval(-7 * 24 * 60 * 60))
        
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
        
        let dateString = dateToISO( date)
        
        let stepData = StepDataUpsert(
            user_id: userId.uuidString,
            date: dateString,
            steps: steps,
            goal: goal,
            synced_at: dateToISO(Date())
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
        let startDateString = dateToISO( startDate)
        
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
            updated_at: dateToISO(Date())
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
        
        let startString = dateToISO( startDate)
        let endString = dateToISO( endDate)
        
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
    
    // MARK: - Cardio Workout Tracking
    
    /// Save a completed cardio workout to the cloud
    func saveCardioWorkout(_ workout: CardioWorkoutData) async throws -> String? {
        guard let userId = currentUser?.id else {
            print("⚠️ [CARDIO] Cannot save - no user logged in")
            return nil
        }
        
        struct CardioWorkoutInsert: Encodable {
            let user_id: String
            let activity_type: String
            let workout_name: String?
            let goal_type: String
            let goal_value: Double?
            let goal_achieved: Bool
            let duration_seconds: Int
            let distance_meters: Double
            let calories_burned: Double
            let average_pace: Double?
            let best_pace: Double?
            let average_speed: Double?
            let max_speed: Double?
            let average_heart_rate: Int?
            let max_heart_rate: Int?
            let cadence: Int?
            let average_power: Int?
            let equipment_name: String?
            let equipment_type: String?
            let route_coordinates: String? // JSON string
            let splits: String? // JSON string
            let started_at: String
            let completed_at: String
        }
        
        let formatter = ISO8601DateFormatter()
        
        let insert = CardioWorkoutInsert(
            user_id: userId.uuidString,
            activity_type: workout.activityType,
            workout_name: workout.workoutName,
            goal_type: workout.goalType,
            goal_value: workout.goalValue,
            goal_achieved: workout.goalAchieved,
            duration_seconds: workout.durationSeconds,
            distance_meters: workout.distanceMeters,
            calories_burned: workout.caloriesBurned,
            average_pace: workout.averagePace,
            best_pace: workout.bestPace,
            average_speed: workout.averageSpeed,
            max_speed: workout.maxSpeed,
            average_heart_rate: workout.averageHeartRate,
            max_heart_rate: workout.maxHeartRate,
            cadence: workout.cadence,
            average_power: workout.averagePower,
            equipment_name: workout.equipmentName,
            equipment_type: workout.equipmentType,
            route_coordinates: workout.routeCoordinatesJSON,
            splits: workout.splitsJSON,
            started_at: formatter.string(from: workout.startedAt),
            completed_at: formatter.string(from: workout.completedAt)
        )
        
        struct CardioWorkoutResponse: Codable {
            let id: String
        }
        
        let response: [CardioWorkoutResponse] = try await client
            .from("cardio_workouts")
            .insert(insert)
            .select("id")
            .execute()
            .value
        
        let workoutId = response.first?.id
        print("✅ [CARDIO] Workout saved: \(workout.activityType) - \(workout.durationSeconds)s")
        
        // Check for PRs after saving workout
        if let id = workoutId {
            await checkAndSaveCardioPRs(workout: workout, workoutId: id)
        }
        
        return workoutId
    }
    
    /// Check for personal records and save any new PRs
    private func checkAndSaveCardioPRs(workout: CardioWorkoutData, workoutId: String) async {
        guard let userId = currentUser?.id else { return }
        
        // Fetch existing PRs for this activity type
        let existingPRs = await fetchCardioPRs(activityType: workout.activityType)
        
        var newPRs: [(type: String, category: String, value: Double, unit: String)] = []
        
        // Check distance PR (longest workout)
        if workout.distanceMeters > 0 {
            let existingDistancePR = existingPRs.first { $0.recordType == "longest_distance" }
            if existingDistancePR == nil || workout.distanceMeters > (existingDistancePR?.value ?? 0) {
                newPRs.append(("longest_distance", "distance", workout.distanceMeters, "meters"))
            }
        }
        
        // Check duration PR (longest duration)
        if workout.durationSeconds > 0 {
            let existingDurationPR = existingPRs.first { $0.recordType == "longest_duration" }
            if existingDurationPR == nil || Double(workout.durationSeconds) > (existingDurationPR?.value ?? 0) {
                newPRs.append(("longest_duration", "duration", Double(workout.durationSeconds), "seconds"))
            }
        }
        
        // Check calories PR (most calories)
        if workout.caloriesBurned > 0 {
            let existingCaloriesPR = existingPRs.first { $0.recordType == "most_calories" }
            if existingCaloriesPR == nil || workout.caloriesBurned > (existingCaloriesPR?.value ?? 0) {
                newPRs.append(("most_calories", "calories", workout.caloriesBurned, "calories"))
            }
        }
        
        // Check pace PR (fastest pace) - lower is better
        if let pace = workout.averagePace, pace > 0, workout.distanceMeters >= 1000 { // At least 1km
            let existingPacePR = existingPRs.first { $0.recordType == "fastest_pace" }
            if existingPacePR == nil || pace < (existingPacePR?.value ?? Double.infinity) {
                newPRs.append(("fastest_pace", "speed", pace, "min/km"))
            }
        }
        
        // Check specific distance PRs (5K, 10K, etc.)
        let distanceKm = workout.distanceMeters / 1000
        if distanceKm >= 5.0 {
            // Calculate 5K time
            let pacePerKm = Double(workout.durationSeconds) / distanceKm
            let time5K = pacePerKm * 5.0
            let existing5KPR = existingPRs.first { $0.recordType == "fastest_5k" }
            if existing5KPR == nil || time5K < (existing5KPR?.value ?? Double.infinity) {
                newPRs.append(("fastest_5k", "speed", time5K, "seconds"))
            }
        }
        
        if distanceKm >= 10.0 {
            let pacePerKm = Double(workout.durationSeconds) / distanceKm
            let time10K = pacePerKm * 10.0
            let existing10KPR = existingPRs.first { $0.recordType == "fastest_10k" }
            if existing10KPR == nil || time10K < (existing10KPR?.value ?? Double.infinity) {
                newPRs.append(("fastest_10k", "speed", time10K, "seconds"))
            }
        }
        
        // Save new PRs
        for pr in newPRs {
            do {
                try await saveCardioPR(
                    userId: userId.uuidString,
                    activityType: workout.activityType,
                    recordType: pr.type,
                    recordCategory: pr.category,
                    value: pr.value,
                    unit: pr.unit,
                    workoutId: workoutId,
                    previousValue: existingPRs.first { $0.recordType == pr.type }?.value
                )
                print("🏆 [CARDIO PR] New \(pr.type): \(pr.value) \(pr.unit)")
            } catch {
                print("⚠️ [CARDIO PR] Failed to save \(pr.type): \(error)")
            }
        }
    }
    
    /// Save a personal record
    private func saveCardioPR(
        userId: String,
        activityType: String,
        recordType: String,
        recordCategory: String,
        value: Double,
        unit: String,
        workoutId: String,
        previousValue: Double?
    ) async throws {
        struct CardioPRUpsert: Encodable {
            let user_id: String
            let activity_type: String
            let record_type: String
            let record_category: String
            let value: Double
            let unit: String
            let workout_id: String
            let previous_value: Double?
            let improvement_percentage: Double?
            let achieved_at: String
        }
        
        var improvement: Double? = nil
        if let prev = previousValue, prev > 0 {
            if recordCategory == "speed" {
                // For pace/time, lower is better
                improvement = ((prev - value) / prev) * 100
            } else {
                // For distance/calories/duration, higher is better
                improvement = ((value - prev) / prev) * 100
            }
        }
        
        let upsert = CardioPRUpsert(
            user_id: userId,
            activity_type: activityType,
            record_type: recordType,
            record_category: recordCategory,
            value: value,
            unit: unit,
            workout_id: workoutId,
            previous_value: previousValue,
            improvement_percentage: improvement,
            achieved_at: dateToISO(Date())
        )
        
        try await client
            .from("cardio_personal_records")
            .upsert(upsert, onConflict: "user_id,activity_type,record_type")
            .execute()
    }
    
    /// Fetch personal records for an activity type
    func fetchCardioPRs(activityType: String? = nil) async -> [CardioPRDTO] {
        guard let userId = currentUser?.id else { return [] }
        
        do {
            var query = client
                .from("cardio_personal_records")
                .select()
                .eq("user_id", value: userId.uuidString)
            
            if let activity = activityType {
                query = query.eq("activity_type", value: activity)
            }
            
            let response: [CardioPRDTO] = try await query
                .order("achieved_at", ascending: false)
                .execute()
                .value
            
            return response
        } catch {
            print("⚠️ [CARDIO] Failed to fetch PRs: \(error)")
            return []
        }
    }
    
    /// Fetch recent cardio workouts
    func fetchRecentCardioWorkouts(limit: Int = 20, activityType: String? = nil) async throws -> [CardioWorkoutDTO] {
        guard let userId = currentUser?.id else { return [] }
        
        var query = client
            .from("cardio_workouts")
            .select()
            .eq("user_id", value: userId.uuidString)
        
        if let activity = activityType {
            query = query.eq("activity_type", value: activity)
        }
        
        let response: [CardioWorkoutDTO] = try await query
            .order("completed_at", ascending: false)
            .limit(limit)
            .execute()
            .value
        
        print("✅ [CARDIO] Fetched \(response.count) workouts")
        return response
    }
    
    /// Fetch cardio statistics for a date range
    func fetchCardioStats(startDate: Date, endDate: Date) async throws -> CardioStatsDTO {
        guard let userId = currentUser?.id else {
            return CardioStatsDTO(totalWorkouts: 0, totalDuration: 0, totalDistance: 0, totalCalories: 0, workoutsByType: [:])
        }
        
        let formatter = ISO8601DateFormatter()
        let startString = formatter.string(from: startDate)
        let endString = formatter.string(from: endDate)
        
        let workouts: [CardioWorkoutDTO] = try await client
            .from("cardio_workouts")
            .select()
            .eq("user_id", value: userId.uuidString)
            .gte("completed_at", value: startString)
            .lte("completed_at", value: endString)
            .execute()
            .value
        
        let totalDuration = workouts.reduce(0) { $0 + $1.durationSeconds }
        let totalDistance = workouts.reduce(0.0) { $0 + $1.distanceMeters }
        let totalCalories = workouts.reduce(0.0) { $0 + $1.caloriesBurned }
        
        // Group by activity type
        var byType: [String: Int] = [:]
        for workout in workouts {
            byType[workout.activityType, default: 0] += 1
        }
        
        return CardioStatsDTO(
            totalWorkouts: workouts.count,
            totalDuration: totalDuration,
            totalDistance: totalDistance,
            totalCalories: totalCalories,
            workoutsByType: byType
        )
    }
    
    /// Fetch cardio streak information
    func fetchCardioStreak() async -> CardioStreakDTO? {
        guard let userId = currentUser?.id else { return nil }
        
        do {
            let response: [CardioStreakDTO] = try await client
                .from("cardio_streaks")
                .select()
                .eq("user_id", value: userId.uuidString)
                .eq("streak_type", value: "daily_cardio")
                .execute()
                .value
            
            return response.first
        } catch {
            print("⚠️ [CARDIO] Failed to fetch streak: \(error)")
            return nil
        }
    }
    
    /// Fetch weekly cardio summaries for trend analysis
    func fetchCardioWeeklySummaries(weeks: Int = 12) async throws -> [CardioWeeklySummaryDTO] {
        guard let userId = currentUser?.id else { return [] }
        
        let calendar = Calendar.current
        let startDate = calendar.date(byAdding: .weekOfYear, value: -weeks, to: Date()) ?? Date()
        let startString = dateToISO( startDate)
        
        let response: [CardioWeeklySummaryDTO] = try await client
            .from("cardio_weekly_summaries")
            .select()
            .eq("user_id", value: userId.uuidString)
            .gte("week_start", value: startString)
            .order("week_start", ascending: false)
            .execute()
            .value
        
        return response
    }
    
    // MARK: - Cardio Goals
    
    /// Create a new cardio goal
    func createCardioGoal(
        name: String,
        goalType: String,
        activityType: String?,
        targetValue: Double,
        unit: String,
        periodType: String,
        periodStart: Date,
        periodEnd: Date
    ) async throws {
        guard let userId = currentUser?.id else { return }
        
        struct CardioGoalInsert: Encodable {
            let user_id: String
            let goal_name: String
            let goal_type: String
            let activity_type: String?
            let target_value: Double
            let unit: String
            let period_type: String
            let period_start: String
            let period_end: String
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        let insert = CardioGoalInsert(
            user_id: userId.uuidString,
            goal_name: name,
            goal_type: goalType,
            activity_type: activityType,
            target_value: targetValue,
            unit: unit,
            period_type: periodType,
            period_start: dateFormatter.string(from: periodStart),
            period_end: dateFormatter.string(from: periodEnd)
        )
        
        try await client
            .from("cardio_goals")
            .insert(insert)
            .execute()
        
        print("✅ [CARDIO] Goal created: \(name)")
    }
    
    /// Fetch active cardio goals
    func fetchActiveCardioGoals() async throws -> [CardioGoalDTO] {
        guard let userId = currentUser?.id else { return [] }
        
        let today = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
        
        let response: [CardioGoalDTO] = try await client
            .from("cardio_goals")
            .select()
            .eq("user_id", value: userId.uuidString)
            .eq("is_active", value: true)
            .execute()
            .value
        
        return response
    }
    
    // MARK: - Exercise Nicknames
    
    /// Fetch all exercise nicknames for the current user
    func fetchExerciseNicknames() async throws -> [ExerciseNicknameDTO] {
        guard let userId = currentUser?.id else { return [] }
        
        let response: [ExerciseNicknameDTO] = try await client
            .from("user_exercise_nicknames")
            .select()
            .eq("user_id", value: userId.uuidString)
            .execute()
            .value
        
        print("✅ [NICKNAMES] Fetched \(response.count) exercise nicknames")
        return response
    }
    
    /// Save or update an exercise nickname
    func saveExerciseNickname(officialName: String, nickname: String, exerciseId: UUID? = nil) async throws {
        guard let userId = currentUser?.id else {
            print("⚠️ [NICKNAMES] Cannot save - no user logged in")
            return
        }
        
        struct NicknameUpsert: Encodable {
            let user_id: String
            let official_name: String
            let nickname: String
            let exercise_id: String?
            let updated_at: String
        }
        
        let upsert = NicknameUpsert(
            user_id: userId.uuidString,
            official_name: officialName,
            nickname: nickname,
            exercise_id: exerciseId?.uuidString,
            updated_at: dateToISO(Date())
        )
        
        try await client
            .from("user_exercise_nicknames")
            .upsert(upsert, onConflict: "user_id,official_name")
            .execute()
        
        print("✅ [NICKNAMES] Saved: '\(officialName)' -> '\(nickname)'")
    }
    
    /// Delete an exercise nickname (revert to official name)
    func deleteExerciseNickname(officialName: String) async throws {
        guard let userId = currentUser?.id else { return }
        
        try await client
            .from("user_exercise_nicknames")
            .delete()
            .eq("user_id", value: userId.uuidString)
            .eq("official_name", value: officialName)
            .execute()
        
        print("✅ [NICKNAMES] Deleted nickname for '\(officialName)'")
    }
    
    // MARK: - Comprehensive Data Sync
    
    /// 🔒 Sync state tracking to prevent duplicate syncs
    private static var isSyncInProgress = false
    private static var lastSyncTime: Date?
    private static let minSyncInterval: TimeInterval = 30 // Minimum 30 seconds between syncs
    
    /// Syncs all user data from cloud to Core Data
    /// ⚡️ PERFORMANCE: Now with deduplication, throttling, and heavy work signaling
    func syncAllDataFromCloud() async {
        // 🛡️ DEDUPLICATION: Prevent concurrent syncs
        guard !SupabaseManager.isSyncInProgress else {
            print("⚠️ [SYNC] Skipping - sync already in progress")
            return
        }
        
        // 🛡️ THROTTLING: Prevent too-frequent syncs
        if let lastSync = SupabaseManager.lastSyncTime,
           Date().timeIntervalSince(lastSync) < SupabaseManager.minSyncInterval {
            print("⚠️ [SYNC] Skipping - synced \(Int(Date().timeIntervalSince(lastSync)))s ago (min: \(Int(SupabaseManager.minSyncInterval))s)")
            return
        }
        
        SupabaseManager.isSyncInProgress = true
        
        // 🔴 Signal heavy work - pauses video prefetching to reduce CPU load
        HeavyWorkSentinel.shared.beginHeavyWork(reason: "Data sync from cloud")
        
        defer { 
            SupabaseManager.isSyncInProgress = false 
            SupabaseManager.lastSyncTime = Date()
            // 🟢 Signal heavy work complete - resumes video prefetching
            HeavyWorkSentinel.shared.endHeavyWork(reason: "Data sync from cloud")
        }
        
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
            
            // Sync exercise nicknames
            await ExerciseNicknameService.shared.loadNicknames()
            
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
                            isCompleted: set.isCompleted,
                            setType: set.setType  // Warmup, Dropset, Failure, AMRAP, etc.
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
            date: dateToISO( workout.date ?? Date()),
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
                                // Try to find the exercise by name
                                let exerciseRequest: NSFetchRequest<Exercise> = Exercise.fetchRequest()
                                exerciseRequest.predicate = NSPredicate(format: "name == %@", exerciseDTO.exerciseName)
                                let exercise = try? viewContext.fetch(exerciseRequest).first
                                
                                // Create WorkoutExercise even if exercise relationship is nil
                                // (we cache the name so the UI can still display it)
                                let workoutExercise = WorkoutExercise(context: viewContext)
                                let workoutExerciseId = UUID(uuidString: exerciseDTO.id) ?? UUID()
                                workoutExercise.id = workoutExerciseId
                                workoutExercise.order = Int16(exerciseDTO.order)
                                workoutExercise.workout = workout
                                workoutExercise.exercise = exercise // May be nil, that's OK
                                
                                // ⚡️ Cache exercise name for fallback display
                                ExerciseNameCache.shared.cacheName(
                                    exerciseDTO.exerciseName,
                                    forWorkoutExerciseId: workoutExerciseId.uuidString
                                )
                                
                                if exercise == nil {
                                    #if DEBUG
                                    print("⚠️ [WORKOUT SYNC] Exercise '\(exerciseDTO.exerciseName)' not in DB yet - will retry relationship later")
                                    #endif
                                }
                                
                                // Create sets
                                for setDTO in exerciseDTO.sets {
                                    let workoutSet = WorkoutSet(context: viewContext)
                                    workoutSet.id = UUID(uuidString: setDTO.id) ?? UUID()
                                    workoutSet.setNumber = Int16(setDTO.setNumber)
                                    workoutSet.reps = Int16(setDTO.reps)
                                    workoutSet.weight = setDTO.weight
                                    workoutSet.isCompleted = setDTO.isCompleted
                                    workoutSet.setType = setDTO.setType ?? "Normal"
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
                            // Try to find the exercise by name
                            let exerciseRequest: NSFetchRequest<Exercise> = Exercise.fetchRequest()
                            exerciseRequest.predicate = NSPredicate(format: "name == %@", exerciseDTO.exerciseName)
                            let exercise = try? viewContext.fetch(exerciseRequest).first
                            
                            // Create WorkoutExercise even if exercise relationship is nil
                            let workoutExercise = WorkoutExercise(context: viewContext)
                            let workoutExerciseId = UUID(uuidString: exerciseDTO.id) ?? UUID()
                            workoutExercise.id = workoutExerciseId
                            workoutExercise.order = Int16(exerciseDTO.order)
                            workoutExercise.workout = workout
                            workoutExercise.exercise = exercise // May be nil
                            
                            // ⚡️ Cache exercise name for fallback display
                            ExerciseNameCache.shared.cacheName(
                                exerciseDTO.exerciseName,
                                forWorkoutExerciseId: workoutExerciseId.uuidString
                            )
                            
                            if exercise == nil {
                                #if DEBUG
                                print("⚠️ [WORKOUT SYNC] Exercise '\(exerciseDTO.exerciseName)' not in DB yet - will retry later")
                                #endif
                            }
                            
                            // Create sets
                            for setDTO in exerciseDTO.sets {
                                let workoutSet = WorkoutSet(context: viewContext)
                                workoutSet.id = UUID(uuidString: setDTO.id) ?? UUID()
                                workoutSet.setNumber = Int16(setDTO.setNumber)
                                workoutSet.reps = Int16(setDTO.reps)
                                workoutSet.weight = setDTO.weight
                                workoutSet.isCompleted = setDTO.isCompleted
                                workoutSet.setType = setDTO.setType ?? "Normal"
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
            date: dateToISO( meal.date ?? Date()),
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
    let profilePhotoUrl: String?
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
        case profilePhotoUrl = "profile_photo_url"
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
    let setType: String?  // Warmup, Dropset, Failure, AMRAP, etc.
    
    enum CodingKeys: String, CodingKey {
        case id, reps, weight
        case setNumber = "set_number"
        case isCompleted = "is_completed"
        case setType = "set_type"
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

// MARK: - Cardio Workout DTOs

/// Data structure for creating a new cardio workout
struct CardioWorkoutData {
    let activityType: String
    let workoutName: String?
    let goalType: String
    let goalValue: Double?
    let goalAchieved: Bool
    let durationSeconds: Int
    let distanceMeters: Double
    let caloriesBurned: Double
    let averagePace: Double?
    let bestPace: Double?
    let averageSpeed: Double?
    let maxSpeed: Double?
    let averageHeartRate: Int?
    let maxHeartRate: Int?
    let cadence: Int?
    let averagePower: Int?
    let equipmentName: String?
    let equipmentType: String?
    let routeCoordinatesJSON: String?
    let splitsJSON: String?
    let startedAt: Date
    let completedAt: Date
    
    init(
        activityType: String,
        workoutName: String? = nil,
        goalType: String,
        goalValue: Double? = nil,
        goalAchieved: Bool,
        durationSeconds: Int,
        distanceMeters: Double,
        caloriesBurned: Double,
        averagePace: Double? = nil,
        bestPace: Double? = nil,
        averageSpeed: Double? = nil,
        maxSpeed: Double? = nil,
        averageHeartRate: Int? = nil,
        maxHeartRate: Int? = nil,
        cadence: Int? = nil,
        averagePower: Int? = nil,
        equipmentName: String? = nil,
        equipmentType: String? = nil,
        routeCoordinatesJSON: String? = nil,
        splitsJSON: String? = nil,
        startedAt: Date,
        completedAt: Date
    ) {
        self.activityType = activityType
        self.workoutName = workoutName
        self.goalType = goalType
        self.goalValue = goalValue
        self.goalAchieved = goalAchieved
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.caloriesBurned = caloriesBurned
        self.averagePace = averagePace
        self.bestPace = bestPace
        self.averageSpeed = averageSpeed
        self.maxSpeed = maxSpeed
        self.averageHeartRate = averageHeartRate
        self.maxHeartRate = maxHeartRate
        self.cadence = cadence
        self.averagePower = averagePower
        self.equipmentName = equipmentName
        self.equipmentType = equipmentType
        self.routeCoordinatesJSON = routeCoordinatesJSON
        self.splitsJSON = splitsJSON
        self.startedAt = startedAt
        self.completedAt = completedAt
    }
}

/// DTO for fetching cardio workouts from database
struct CardioWorkoutDTO: Codable {
    let id: String
    let activityType: String
    let workoutName: String?
    let goalType: String
    let goalValue: Double?
    let goalAchieved: Bool
    let durationSeconds: Int
    let distanceMeters: Double
    let caloriesBurned: Double
    let averagePace: Double?
    let bestPace: Double?
    let averageSpeed: Double?
    let maxSpeed: Double?
    let averageHeartRate: Int?
    let maxHeartRate: Int?
    let cadence: Int?
    let averagePower: Int?
    let equipmentName: String?
    let equipmentType: String?
    let startedAt: String
    let completedAt: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case activityType = "activity_type"
        case workoutName = "workout_name"
        case goalType = "goal_type"
        case goalValue = "goal_value"
        case goalAchieved = "goal_achieved"
        case durationSeconds = "duration_seconds"
        case distanceMeters = "distance_meters"
        case caloriesBurned = "calories_burned"
        case averagePace = "average_pace"
        case bestPace = "best_pace"
        case averageSpeed = "average_speed"
        case maxSpeed = "max_speed"
        case averageHeartRate = "average_heart_rate"
        case maxHeartRate = "max_heart_rate"
        case cadence
        case averagePower = "average_power"
        case equipmentName = "equipment_name"
        case equipmentType = "equipment_type"
        case startedAt = "started_at"
        case completedAt = "completed_at"
    }
}

/// DTO for personal records
struct CardioPRDTO: Codable {
    let id: String
    let activityType: String
    let recordType: String
    let recordCategory: String
    let value: Double
    let unit: String
    let workoutId: String?
    let previousValue: Double?
    let improvementPercentage: Double?
    let achievedAt: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case activityType = "activity_type"
        case recordType = "record_type"
        case recordCategory = "record_category"
        case value, unit
        case workoutId = "workout_id"
        case previousValue = "previous_value"
        case improvementPercentage = "improvement_percentage"
        case achievedAt = "achieved_at"
    }
}

/// DTO for cardio statistics
struct CardioStatsDTO {
    let totalWorkouts: Int
    let totalDuration: Int
    let totalDistance: Double
    let totalCalories: Double
    let workoutsByType: [String: Int]
}

/// DTO for cardio streak
struct CardioStreakDTO: Codable {
    let id: String
    let streakType: String
    let activityType: String?
    let currentStreak: Int
    let longestStreak: Int
    let lastActivityDate: String?
    let streakStartDate: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case streakType = "streak_type"
        case activityType = "activity_type"
        case currentStreak = "current_streak"
        case longestStreak = "longest_streak"
        case lastActivityDate = "last_activity_date"
        case streakStartDate = "streak_start_date"
    }
}

/// DTO for weekly summaries
struct CardioWeeklySummaryDTO: Codable {
    let id: String
    let weekStart: String
    let weekEnd: String
    let totalWorkouts: Int
    let totalDurationSeconds: Int
    let totalDistanceMeters: Double
    let totalCalories: Double
    let avgWorkoutDuration: Int?
    let avgPace: Double?
    let avgHeartRate: Int?
    let goalsCompleted: Int
    let prsAchieved: Int
    
    enum CodingKeys: String, CodingKey {
        case id
        case weekStart = "week_start"
        case weekEnd = "week_end"
        case totalWorkouts = "total_workouts"
        case totalDurationSeconds = "total_duration_seconds"
        case totalDistanceMeters = "total_distance_meters"
        case totalCalories = "total_calories"
        case avgWorkoutDuration = "avg_workout_duration"
        case avgPace = "avg_pace"
        case avgHeartRate = "avg_heart_rate"
        case goalsCompleted = "goals_completed"
        case prsAchieved = "prs_achieved"
    }
}

/// DTO for cardio goals
struct CardioGoalDTO: Codable {
    let id: String
    let goalName: String
    let goalType: String
    let activityType: String?
    let targetValue: Double
    let currentValue: Double
    let unit: String
    let periodType: String
    let periodStart: String
    let periodEnd: String
    let isActive: Bool
    let isCompleted: Bool
    let completedAt: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case goalName = "goal_name"
        case goalType = "goal_type"
        case activityType = "activity_type"
        case targetValue = "target_value"
        case currentValue = "current_value"
        case unit
        case periodType = "period_type"
        case periodStart = "period_start"
        case periodEnd = "period_end"
        case isActive = "is_active"
        case isCompleted = "is_completed"
        case completedAt = "completed_at"
    }
}
