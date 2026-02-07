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
    
    internal var client: SupabaseClient!
    
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
    
    /// Convert birthday from display format (MM/DD/YYYY or DD/MM/YYYY) to ISO format (YYYY-MM-DD)
    /// Handles both US (MM/DD/YYYY) and international (DD/MM/YYYY) formats
    /// Returns nil if the input is nil, empty, or invalid
    /// If already in ISO format (YYYY-MM-DD), returns as-is
    private func birthdayToISO(_ birthday: String?) -> String? {
        guard let birthday = birthday, !birthday.isEmpty else { return nil }
        
        // If already in ISO format (YYYY-MM-DD), return as-is
        if birthday.contains("-") && birthday.count == 10 {
            return birthday
        }
        
        // Parse from slash format (MM/DD/YYYY or DD/MM/YYYY)
        let parts = birthday.split(separator: "/")
        guard parts.count == 3 else { return nil }
        
        guard let part1 = Int(parts[0]),
              let part2 = Int(parts[1]),
              let year = Int(parts[2]) else { return nil }
        
        let month: Int
        let day: Int
        
        // Determine format based on values
        // If first part > 12, it must be a day (DD/MM/YYYY format)
        // If second part > 12, it must be a day (MM/DD/YYYY format)
        // Otherwise, use locale preference
        if part1 > 12 {
            // First part is day (DD/MM/YYYY - international format)
            day = part1
            month = part2
        } else if part2 > 12 {
            // Second part is day (MM/DD/YYYY - US format)
            month = part1
            day = part2
        } else {
            // Ambiguous - check device locale
            let usesMonthFirst = Locale.current.identifier.hasPrefix("en_US") ||
                                 Locale.current.identifier.hasPrefix("en_PH") ||
                                 Locale.current.region?.identifier == "US"
            if usesMonthFirst {
                month = part1
                day = part2
            } else {
                day = part1
                month = part2
            }
        }
        
        // Validate and format
        guard month >= 1 && month <= 12,
              day >= 1 && day <= 31,
              year >= 1900 && year <= 2100 else { return nil }
        
        return String(format: "%04d-%02d-%02d", year, month, day)
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
        
        let startTime = Date()
        print("🔐 [SUPABASE] Starting signup request for: \(email)")
        print("🔐 [SUPABASE] Timestamp: \(startTime)")

        do {
            print("🔐 [SUPABASE] Calling client.auth.signUp...")
            let response = try await client.auth.signUp(email: email, password: password)
            
            let duration = Date().timeIntervalSince(startTime)
            print("🔐 [SUPABASE] signUp response received in \(String(format: "%.2f", duration))s")
            
            let user = response.user
            print("🔐 [SUPABASE] User ID: \(user.id)")
            
            // Create user profile
            print("🔐 [SUPABASE] Creating user profile...")
            try await createUserProfile(userId: user.id, name: name, email: email)
            print("🔐 [SUPABASE] Profile created successfully")
            
            await MainActor.run {
                currentUser = user
                isAuthenticated = true
                isLoading = false
                
                // Clear the manual sign-out flag since user is signing up
                UserDefaults.standard.removeObject(forKey: "user_manually_signed_out")
            }
            
            let totalDuration = Date().timeIntervalSince(startTime)
            print("✅ Sign up successful: \(email) (total: \(String(format: "%.2f", totalDuration))s)")
            SessionLogManager.shared.logAuthSuccess(method: "email_signup", userId: user.id.uuidString)
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            await MainActor.run { isLoading = false }
            print("❌ Sign up error after \(String(format: "%.2f", duration))s: \(error.localizedDescription)")
            print("❌ Sign up error details: \(error)")
            SessionLogManager.shared.logAuthFailure(method: "email_signup", error: "\(error.localizedDescription) | Duration: \(String(format: "%.2f", duration))s")
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
            SessionLogManager.shared.log(.info, category: .auth, message: "🔐 Sign in successful", metadata: [
                "email": email,
                "user_id": String(currentUser?.id.uuidString.prefix(8) ?? "?")
            ])
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
                
                // Priority for FULL NAME (first + last):
                // 1. appleProvidedName (FULL NAME directly from Apple credentials - only first sign-in)
                // 2. Persisted full name from previous sign-in (UserDefaults - per user)
                // 3. Global Apple name cache (survives account deletion)
                // 4. Supabase user metadata (full_name or name)
                // 5. Email prefix (if not private relay and looks like a real name)
                // 6. Don't store anything (let user enter their name)
                var appleFullName: String?
                
                print("🔍 [APPLE] Starting name resolution for user: \(session.user.id.uuidString.prefix(8))...")
                print("🔍 [APPLE] appleProvidedName: \(appleProvidedName ?? "nil")")
                
                if let providedName = appleProvidedName, !providedName.isEmpty, providedName != "Apple User" {
                    appleFullName = providedName
                    // Persist for future sign-ins (Apple only provides name once)
                    // Store both per-user AND globally (global survives account deletion)
                    UserDefaults.standard.set(providedName, forKey: "apple_user_name_\(session.user.id.uuidString)")
                    UserDefaults.standard.set(providedName, forKey: "apple_global_name")
                    print("💾 [APPLE] Persisted user FULL NAME for future sign-ins: \(providedName)")
                    print("💾 [APPLE] Also stored globally as fallback")
                } else {
                    // Check per-user persisted name
                    let persistedKey = "apple_user_name_\(session.user.id.uuidString)"
                    let persistedFullName = UserDefaults.standard.string(forKey: persistedKey)
                    print("🔍 [APPLE] Checking UserDefaults[\(persistedKey)]: \(persistedFullName ?? "nil")")
                    
                    if let persistedFullName = persistedFullName, 
                       !persistedFullName.isEmpty,
                       persistedFullName != "Apple User" {
                        appleFullName = persistedFullName
                        print("📂 [APPLE] Using persisted FULL NAME from previous sign-in: \(persistedFullName)")
                    } else {
                        // Check global name cache (survives account deletion)
                        let globalName = UserDefaults.standard.string(forKey: "apple_global_name")
                        print("🔍 [APPLE] Checking global cache [apple_global_name]: \(globalName ?? "nil")")
                        
                        if let globalName = globalName, !globalName.isEmpty, globalName != "Apple User" {
                            appleFullName = globalName
                            // Restore to per-user cache
                            UserDefaults.standard.set(globalName, forKey: "apple_user_name_\(session.user.id.uuidString)")
                            print("📂 [APPLE] Using GLOBAL cached name (restored from previous session): \(globalName)")
                        } else if let fullName = session.user.userMetadata["full_name"] as? String, !fullName.isEmpty {
                            print("🔍 [APPLE] Checking metadata full_name: \(fullName)")
                            if fullName != "Apple User" {
                                appleFullName = fullName
                            }
                        } else if let name = session.user.userMetadata["name"] as? String, !name.isEmpty {
                            print("🔍 [APPLE] Checking metadata name: \(name)")
                            if name != "Apple User" {
                                appleFullName = name
                            }
                        } else if let email = session.user.email, !email.contains("privaterelay"), !email.contains("@icloud") {
                            // Only use email prefix if it looks like a real name (not private relay or iCloud)
                            let emailPrefix = email.components(separatedBy: "@").first ?? ""
                            // Check if email prefix looks like a real name (contains letters, not too many numbers)
                            let letterCount = emailPrefix.filter { $0.isLetter }.count
                            print("🔍 [APPLE] Checking email prefix: \(emailPrefix) (letters: \(letterCount))")
                            if letterCount > 2 && emailPrefix.count > 2 {
                                appleFullName = emailPrefix.capitalized
                            }
                        }
                    }
                }
                
                print("📧 Apple Sign-In - Email: \(appleEmail), Full Name: \(appleFullName ?? "(none - user will enter)")")
                
                // ⚠️ IMPORTANT: Do NOT create profile here!
                // The profile should only be created when user taps "Create Account" at end of onboarding.
                // This prevents "zombie" accounts with null data if user abandons onboarding.
                // Store the Apple FULL NAME temporarily ONLY if we have a valid one - profile will be created in completeOnboarding()
                if let fullName = appleFullName, !fullName.isEmpty {
                    UserDefaults.standard.set(fullName, forKey: "pending_oauth_name")
                    print("🔐 [APPLE] Stored pending full name: \(fullName)")
                } else {
                    // Don't store anything - user will be prompted to enter their name
                    UserDefaults.standard.removeObject(forKey: "pending_oauth_name")
                    print("🔐 [APPLE] ⚠️ No valid name available - user will be prompted to enter name")
                    print("🔐 [APPLE] ℹ️ To fix: Sign out of Apple ID in Settings > [Your Name] > Sign In & Security > Apps Using Your Apple ID > Fit33 > Stop Using Apple ID")
                    print("🔐 [APPLE] ℹ️ Then sign in again - Apple will provide your name on the FIRST sign-in with a new connection")
                }
                UserDefaults.standard.set(appleEmail, forKey: "pending_oauth_email")
                UserDefaults.standard.synchronize()
                
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
    /// This handles the implicit flow response where tokens are in the URL fragment
    func handleOAuthCallback(url: URL) async throws -> (isNewUser: Bool, socialUsername: String?) {
        await MainActor.run { isLoading = true }
        
        do {
            // First, try the standard PKCE session flow
            // If that fails (implicit flow), parse tokens from URL fragment manually
            let session: Session
            var jwtUserMetadata: [String: Any]? = nil  // Store metadata from JWT for implicit flow
            
            do {
                session = try await client.auth.session(from: url)
            } catch {
                // PKCE failed - try parsing implicit flow tokens from URL fragment
                print("🔐 [OAUTH] PKCE failed, trying implicit flow token parsing...")
                
                guard let fragment = url.fragment else {
                    throw error
                }
                
                // Parse the fragment as query parameters
                var params: [String: String] = [:]
                for pair in fragment.components(separatedBy: "&") {
                    let parts = pair.components(separatedBy: "=")
                    if parts.count == 2 {
                        params[parts[0]] = parts[1].removingPercentEncoding ?? parts[1]
                    }
                }
                
                guard let accessToken = params["access_token"],
                      let refreshToken = params["refresh_token"] else {
                    print("❌ [OAUTH] Missing tokens in URL fragment")
                    throw error
                }
                
                // Decode the JWT to extract user metadata (it's in the payload)
                jwtUserMetadata = decodeJWTPayload(accessToken)
                if let metadata = jwtUserMetadata?["user_metadata"] as? [String: Any] {
                    print("🔐 [OAUTH] Decoded user metadata from JWT: \(metadata)")
                    jwtUserMetadata = metadata
                }
                
                print("🔐 [OAUTH] Found tokens in URL fragment, setting session...")
                
                // Set the session using the tokens
                session = try await client.auth.setSession(accessToken: accessToken, refreshToken: refreshToken)
                print("✅ [OAUTH] Session set from implicit flow tokens")
            }
            
            // Check if this is a new user (no profile exists yet)
            let profileExists = await verifyUserExists(userId: session.user.id)
            var isNewUser = false
            var socialUsername: String? = nil
            
            if !profileExists {
                // Determine provider from metadata - check both session and JWT-decoded metadata
                let provider = session.user.appMetadata["provider"] as? String 
                    ?? jwtUserMetadata?["iss"] as? String ?? "unknown"
                
                let userEmail: String
                let userName: String
                let avatarUrl: String?
                
                // Try to get name from session first, then from JWT-decoded metadata
                let sessionFullName = session.user.userMetadata["full_name"] as? String
                let sessionName = session.user.userMetadata["name"] as? String
                let jwtFullName = jwtUserMetadata?["full_name"] as? String
                let jwtName = jwtUserMetadata?["name"] as? String
                avatarUrl = session.user.userMetadata["avatar_url"] as? String 
                    ?? session.user.userMetadata["picture"] as? String
                    ?? jwtUserMetadata?["avatar_url"] as? String
                    ?? jwtUserMetadata?["picture"] as? String
                
                if provider == "facebook" || provider.contains("facebook") {
                    // Facebook-specific data extraction
                    userEmail = session.user.email ?? "facebook_user_\(session.user.id.uuidString.prefix(8))@facebook.com"
                    userName = sessionFullName ?? sessionName ?? jwtFullName ?? jwtName ?? "Facebook User"
                    
                    // Extract username if available
                    socialUsername = session.user.userMetadata["user_name"] as? String 
                        ?? session.user.userMetadata["username"] as? String
                    
                    print("📘 Facebook Sign-In - Username: @\(socialUsername ?? "unknown"), Name: \(userName)")
                } else {
                    // Google or other OAuth provider
                    userEmail = session.user.email ?? "oauth_user_\(session.user.id.uuidString.prefix(8))@email.com"
                    userName = sessionFullName ?? sessionName ?? jwtFullName ?? jwtName ?? "User"
                    print("🔐 OAuth Sign-In - Provider: \(provider), Name: \(userName)")
                    print("🔐 OAuth Sign-In - Session metadata: \(session.user.userMetadata)")
                    print("🔐 OAuth Sign-In - JWT metadata: \(jwtUserMetadata ?? [:])")
                }
                
                // ⚠️ IMPORTANT: Do NOT create profile here!
                // The profile should only be created when user taps "Create Account" at end of onboarding.
                // This prevents "zombie" accounts with null data if user abandons onboarding.
                // Store the OAuth data temporarily - profile will be created in completeOnboarding()
                await MainActor.run {
                    UserDefaults.standard.set(userName, forKey: "pending_oauth_name")
                    UserDefaults.standard.set(userEmail, forKey: "pending_oauth_email")
                    if let avatar = avatarUrl {
                        UserDefaults.standard.set(avatar, forKey: "pending_oauth_avatar")
                    }
                    UserDefaults.standard.synchronize()
                    print("🔐 [OAUTH] Stored pending profile data (will create on onboarding completion)")
                    print("🔐 [OAUTH] Pending name: \(userName), email: \(userEmail)")
                }
                
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
            print("❌ OAuth callback error: \(error)")
            throw error
        }
    }
    
    /// Decode a JWT payload to extract user metadata
    private func decodeJWTPayload(_ jwt: String) -> [String: Any]? {
        let parts = jwt.components(separatedBy: ".")
        guard parts.count == 3 else { return nil }
        
        var payload = parts[1]
        // Add padding if needed for base64 decoding
        let remainder = payload.count % 4
        if remainder > 0 {
            payload = payload.padding(toLength: payload.count + 4 - remainder, withPad: "=", startingAt: 0)
        }
        
        // Convert base64url to base64
        payload = payload
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        
        return json
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
                
                // Clear challenge cache - ensures no challenge data leaks between users
                ChallengeService.shared.clearCache()
                
                // Mark that user manually signed out (for development mode)
                UserDefaults.standard.set(true, forKey: "user_manually_signed_out")
                
                // Reset authentication state
                currentUser = nil
                isAuthenticated = false
                isLoading = false
            }
            SessionLogManager.shared.log(.info, category: .auth, message: "🔐 Sign out complete")
            print("✅ Sign out successful - all local data cleared")
        } catch {
            await MainActor.run { isLoading = false }
            print("❌ Sign out error: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Delete the current user's account completely
    /// This uses a Supabase function to delete from auth.users (requires running DELETE_USER_ACCOUNT.sql)
    func deleteAccount() async throws {
        guard let userId = currentUser?.id else {
            throw NSError(domain: "SupabaseManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "No user logged in"])
        }
        
        print("🗑️ ════════════════════════════════════════")
        print("🗑️ STARTING ACCOUNT DELETION")
        print("🗑️ User ID: \(userId.uuidString)")
        print("🗑️ ════════════════════════════════════════")
        
        await MainActor.run { isLoading = true }
        
        // STEP 1: Always delete all user data from tables first (this always works)
        print("🗑️ Step 1: Deleting all user data from tables...")
        await deleteAllUserDataFromTables(userId: userId)
        
        // STEP 2: Delete profile photo from storage
        print("🗑️ Step 2: Deleting profile photo...")
        await deleteProfilePhotoFromStorage(userId: userId)
        
        // STEP 3: Try to delete from auth.users via RPC (requires DELETE_USER_ACCOUNT.sql)
        print("🗑️ Step 3: Attempting to delete from auth.users via RPC...")
        var authUserDeleted = false
        do {
            let result: Bool = try await client
                .rpc("delete_user_account", params: ["user_id_to_delete": userId.uuidString])
                .execute()
                .value
            
            authUserDeleted = result
            if result {
                print("✅ User deleted from auth.users via RPC")
            } else {
                print("⚠️ RPC returned false - auth.users entry may still exist")
            }
        } catch {
            print("⚠️ RPC delete_user_account failed: \(error.localizedDescription)")
            print("⚠️ Run DELETE_USER_ACCOUNT.sql in Supabase to enable full deletion")
            // Continue anyway - profile data is already deleted
        }
        
        // STEP 4: Sign out and clear local data
        print("🗑️ Step 4: Signing out and clearing local data...")
        try? await client.auth.signOut()
        
        await MainActor.run {
            PersistenceController.shared.clearAllUserData()
            ProfilePhotoCache.shared.clearCache()
            ChallengeService.shared.clearCache()
            ChallengeService.shared.activeChallenges = []
            ChallengeService.shared.pendingInvites = []
            UserDefaults.standard.set(true, forKey: "user_manually_signed_out")
            currentUser = nil
            isAuthenticated = false
            isLoading = false
        }
        
        print("🗑️ ════════════════════════════════════════")
        if authUserDeleted {
            print("✅ ACCOUNT FULLY DELETED - user can re-register with same email")
        } else {
            print("⚠️ PROFILE DATA DELETED but auth.users entry may remain")
            print("⚠️ User may need to use a different email or run DELETE_USER_ACCOUNT.sql")
        }
        print("🗑️ ════════════════════════════════════════")
    }
    
    /// Delete all user data from all tables (comprehensive cleanup)
    private func deleteAllUserDataFromTables(userId: UUID) async {
        // Order matters due to foreign key constraints - delete child tables first
        let deletions: [(table: String, column: String)] = [
            // Challenge data (delete daily progress first)
            ("challenge_daily_progress", "user_id"),
            ("challenge_participants", "user_id"),
            
            // Friend/social data — friendships uses requester_id/addressee_id, NOT user_id/friend_id
            ("friendships", "requester_id"),
            ("friendships", "addressee_id"),
            // Shared workouts — table is shared_workouts, NOT sent_workouts
            ("shared_workouts", "sender_id"),
            ("shared_workouts", "recipient_id"),
            
            // Contact sync data
            ("user_synced_contacts", "user_id"),
            ("contact_joined_notifications", "notified_user_id"),
            
            // Push notifications
            ("user_push_tokens", "user_id"),
            ("push_notification_queue", "recipient_user_id"),
            
            // Workout data
            ("workout_history", "user_id"),
            ("workout_exercises", "user_id"),
            ("workout_context", "user_id"),
            ("workouts", "user_id"),
            ("exercise_usage_logs", "user_id"),
            ("exercise_performance_history", "user_id"),
            
            // Program data
            ("user_active_programs", "user_id"),
            ("user_custom_programs", "user_id"),
            ("program_history", "user_id"),
            
            // Food/meal data
            ("meal_logs", "user_id"),
            ("user_food_history", "user_id"),
            ("user_food_frequency", "user_id"),
            ("user_ingredient_preferences", "user_id"),
            ("user_cuisine_preferences", "user_id"),
            ("user_favorite_foods", "user_id"),
            
            // Favorites and custom content
            ("user_favorites", "user_id"),
            ("favorite_workouts", "user_id"),
            ("custom_exercises", "user_id"),
            ("user_exercise_nicknames", "user_id"),
            
            // Health data
            ("step_tracking", "user_id"),
            ("weight_logs", "user_id"),
            ("weight_goals", "user_id"),
            ("weight_statistics", "user_id"),
            ("hydration_logs", "user_id"),
            ("daily_activity_summary", "user_id"),
            ("daily_summaries", "user_id"),
            ("sleep_logs", "user_id"),
            ("heart_rate_daily", "user_id"),
            ("body_composition_logs", "user_id"),
            ("inbody_connections", "user_id"),
            
            // Cardio data
            ("cardio_personal_records", "user_id"),
            ("cardio_streaks", "user_id"),
            ("cardio_weekly_summaries", "user_id"),
            ("cardio_goals", "user_id"),
            ("cardio_workouts", "user_id"),
            
            // Intelligence/insights data
            ("user_personalized_insights", "user_id"),
            ("user_streak_tracking", "user_id"),
            ("user_metric_correlations", "user_id"),
            ("user_behavior_patterns", "user_id"),
            ("user_performance_windows", "user_id"),
            
            // Strava integration
            ("user_strava_tokens", "user_id"),
            ("strava_activities", "user_id"),
            
            // Notifications
            ("app_notifications", "user_id"),
            
            // Other user data
            ("bug_reports", "user_id"),
            ("user_progress", "user_id")
        ]
        
        for (table, column) in deletions {
            do {
                try await client
                    .from(table)
                    .delete()
                    .eq(column, value: userId.uuidString)
                    .execute()
                print("  ✓ Deleted from \(table)")
            } catch {
                // Table might not exist or no data - continue
                print("  ⚠️ \(table): \(error.localizedDescription)")
            }
        }
        
        // Delete challenges created by this user (table is group_challenges, NOT friend_challenges)
        do {
            try await client
                .from("group_challenges")
                .delete()
                .eq("created_by", value: userId.uuidString)
                .execute()
            print("  ✓ Deleted created challenges")
        } catch {
            print("  ⚠️ group_challenges (created_by): \(error.localizedDescription)")
        }
        
        // Finally delete the user profile
        do {
            try await client
                .from("user_profiles")
                .delete()
                .eq("id", value: userId.uuidString)
                .execute()
            print("  ✓ Deleted user_profiles")
        } catch {
            print("  ⚠️ user_profiles: \(error.localizedDescription)")
        }
        
        print("🗑️ All user data deletion complete")
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
    
    
    func resetPassword(email: String) async throws {
        await MainActor.run { isLoading = true }
        
        do {
            // Configure redirect URL for password reset
            // This URL will be used in the email link that user receives
            let redirectURL = "fit33://reset-password"  // Deep link to app
            
            try await client.auth.resetPasswordForEmail(
                email,
                redirectTo: URL(string: redirectURL)
            )
            await MainActor.run { isLoading = false }
            print("✅ Password reset email sent to: \(email)")
        } catch {
            await MainActor.run { isLoading = false }
            print("❌ Password reset error: \(error.localizedDescription)")
            print("❌ Full error: \(error)")
            throw error
        }
    }
    
    // MARK: - Onboarding Logging
    
    /// Log an onboarding event to the database for debugging
    func logOnboardingEvent(
        eventType: String,
        stepName: String? = nil,
        eventData: [String: Any]? = nil,
        errorMessage: String? = nil,
        sessionId: String? = nil
    ) async {
        do {
            // Get device info
            let deviceInfo: [String: Any] = [
                "device_model": getDeviceModel(),
                "os_version": UIDevice.current.systemVersion,
                "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
                "build_number": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
                "locale": Locale.current.identifier,
                "timezone": TimeZone.current.identifier,
                "language": Locale.preferredLanguages.first ?? "unknown",
                "region": Locale.current.region?.identifier ?? "unknown"
            ]
            
            // Build params
            var params: [String: Any] = [
                "p_event_type": eventType,
                "p_device_info": deviceInfo
            ]
            
            if let userId = currentUser?.id {
                params["p_user_id"] = userId.uuidString
            }
            
            if let sessionId = sessionId ?? OnboardingSessionManager.shared.currentSessionId {
                params["p_session_id"] = sessionId
            }
            
            if let stepName = stepName {
                params["p_step_name"] = stepName
            }
            
            if let eventData = eventData {
                params["p_event_data"] = eventData
            }
            
            if let errorMessage = errorMessage {
                params["p_error_message"] = errorMessage
            }
            
            // Call the RPC function (convert to Encodable for Supabase)
            try await client.rpc("log_onboarding_event", params: params.toEncodable()).execute()
            
            print("📝 [ONBOARDING LOG] \(eventType) - \(stepName ?? "N/A")")
        } catch {
            // Don't throw - logging should never break the app
            print("⚠️ [ONBOARDING LOG] Failed to log event: \(error.localizedDescription)")
        }
    }
    
    /// Get the device model name
    private func getDeviceModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return identifier
    }
    
    /// Log an individual field's value at a specific stage (collected, sent_to_db, verified_in_db)
    func logOnboardingField(
        fieldName: String,
        stage: String, // "collected", "sent_to_db", "verified_in_db"
        value: Any?,
        rawInput: String? = nil,
        convertedValue: String? = nil,
        sessionId: String? = nil
    ) async {
        do {
            // Determine field type and string value
            let (fieldValue, fieldType) = stringifyValue(value)
            
            // Get device info
            let deviceInfo: [String: Any] = [
                "device_model": getDeviceModel(),
                "os_version": UIDevice.current.systemVersion,
                "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
                "locale": Locale.current.identifier,
                "timezone": TimeZone.current.identifier,
                "region": Locale.current.region?.identifier ?? "unknown"
            ]
            
            var params: [String: Any] = [
                "p_field_name": fieldName,
                "p_stage": stage,
                "p_field_type": fieldType,
                "p_device_info": deviceInfo
            ]
            
            if let userId = currentUser?.id {
                params["p_user_id"] = userId.uuidString
            }
            
            if let sessionId = sessionId ?? OnboardingSessionManager.shared.currentSessionId {
                params["p_session_id"] = sessionId
            }
            
            if let fieldValue = fieldValue {
                params["p_field_value"] = fieldValue
            }
            
            if let rawInput = rawInput {
                params["p_raw_input"] = rawInput
            }
            
            if let convertedValue = convertedValue {
                params["p_converted_value"] = convertedValue
            }
            
            try await client.rpc("log_onboarding_field", params: params.toEncodable()).execute()
            
            let valueDesc = fieldValue ?? "NULL"
            print("📊 [FIELD LOG] \(fieldName) @ \(stage): \(valueDesc)")
        } catch {
            print("⚠️ [FIELD LOG] Failed: \(error.localizedDescription)")
        }
    }
    
    /// Convert any value to a string representation for logging
    private func stringifyValue(_ value: Any?) -> (String?, String) {
        guard let value = value else {
            return (nil, "null")
        }
        
        if let str = value as? String {
            return (str.isEmpty ? nil : str, "string")
        } else if let num = value as? Int {
            return (String(num), "number")
        } else if let num = value as? Int16 {
            return (String(num), "number")
        } else if let num = value as? Double {
            return (String(num), "number")
        } else if let arr = value as? [String] {
            return (arr.isEmpty ? nil : arr.joined(separator: ", "), "array")
        } else if let bool = value as? Bool {
            return (String(bool), "boolean")
        } else {
            return (String(describing: value), "unknown")
        }
    }
    
    /// Verify what's actually saved in the database and log it
    func verifyAndLogSavedProfile() async {
        guard let userId = currentUser?.id else { return }
        
        do {
            struct ProfileRow: Decodable {
                let name: String?
                let email: String?
                let username: String?
                let age: Int?
                let gender: String?
                let height_cm: Double?
                let weight_kg: Double?
                let fitness_goal: String?
                let experience_level: String?
                let equipment: [String]?
                let available_days: Int?
                let workout_environment: String?
                let birthday: String?
            }
            
            let response: ProfileRow = try await client
                .from("user_profiles")
                .select("name, email, username, age, gender, height_cm, weight_kg, fitness_goal, experience_level, equipment, available_days, workout_environment, birthday")
                .eq("id", value: userId.uuidString)
                .single()
                .execute()
                .value
            
            // Log each field as verified in DB
            let fieldsToVerify: [(String, Any?)] = [
                ("name", response.name),
                ("email", response.email),
                ("username", response.username),
                ("age", response.age),
                ("gender", response.gender),
                ("height_cm", response.height_cm),
                ("weight_kg", response.weight_kg),
                ("fitness_goal", response.fitness_goal),
                ("experience_level", response.experience_level),
                ("equipment", response.equipment),
                ("available_days", response.available_days),
                ("workout_environment", response.workout_environment),
                ("birthday", response.birthday)
            ]
            
            for (fieldName, fieldValue) in fieldsToVerify {
                await logOnboardingField(
                    fieldName: fieldName,
                    stage: "verified_in_db",
                    value: fieldValue
                )
            }
            
            print("✅ [VERIFY] Logged all verified field values from database")
            
        } catch {
            print("❌ [VERIFY] Failed to verify saved profile: \(error.localizedDescription)")
            await logOnboardingEvent(
                eventType: "error",
                stepName: "verify_profile",
                errorMessage: "Failed to read back profile: \(error.localizedDescription)"
            )
        }
    }
    
    // MARK: - User Profile
    
    private func createUserProfile(userId: UUID, name: String, email: String, hasCompletedOnboarding: Bool = false) async throws {
        // Use SECURITY DEFINER function to bypass RLS during signup
        // This fixes the "database error saving new user" issue
        struct CreateProfileParams: Encodable {
            let user_id: String
            let user_name: String
            let user_email: String
        }
        
        let params = CreateProfileParams(
            user_id: userId.uuidString,
            user_name: name,
            user_email: email
        )
        
        do {
            // Try using the secure RPC function first
            try await client.rpc("create_user_profile", params: params).execute()
            print("✅ User profile created via RPC function")
        } catch {
            // Fallback to direct insert if RPC function doesn't exist
            print("⚠️ RPC function not available, trying direct insert: \(error.localizedDescription)")
            
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
        }
        
        // Create initial progress record (also uses upsert)
        try await createUserProgress(userId: userId)
        
        print("✅ User profile created (onboarding: \(hasCompletedOnboarding ? "complete" : "pending"))")
    }
    
    // MARK: - Activity & Integration Tracking
    
    /// Update last login timestamp - call when app opens
    func updateLastLogin() async {
        guard let userId = currentUser?.id else { return }
        
        do {
            try await client.rpc("update_last_login", params: ["p_user_id": userId.uuidString]).execute()
            print("✅ [ACTIVITY] Updated last login timestamp")
        } catch {
            // Fallback to direct update if RPC doesn't exist
            do {
                struct LastLoginUpdate: Encodable {
                    let last_login_at: String
                }
                
                let update = LastLoginUpdate(last_login_at: ISO8601DateFormatter().string(from: Date()))
                
                try await client
                    .from("user_profiles")
                    .update(update)
                    .eq("id", value: userId.uuidString)
                    .execute()
                print("✅ [ACTIVITY] Updated last login timestamp (direct)")
            } catch {
                print("⚠️ [ACTIVITY] Failed to update last login: \(error.localizedDescription)")
            }
        }
    }
    
    /// Update integration connection status
    func updateIntegrationStatus(integration: String, isConnected: Bool) async {
        guard let userId = currentUser?.id else { return }
        
        // Use direct update (simpler and more reliable than RPC for this use case)
        do {
            let columnName: String
            switch integration {
            case "strava": columnName = "is_strava_connected"
            case "fitbit": columnName = "is_fitbit_connected"
            case "apple_health": columnName = "is_apple_health_connected"
            case "inbody": columnName = "is_inbody_connected"
            default:
                print("⚠️ [INTEGRATIONS] Unknown integration: \(integration)")
                return
            }
            
            // Create typed update struct for each integration
            struct IntegrationUpdate: Encodable {
                let is_strava_connected: Bool?
                let is_fitbit_connected: Bool?
                let is_apple_health_connected: Bool?
                let is_inbody_connected: Bool?
            }
            
            let update = IntegrationUpdate(
                is_strava_connected: integration == "strava" ? isConnected : nil,
                is_fitbit_connected: integration == "fitbit" ? isConnected : nil,
                is_apple_health_connected: integration == "apple_health" ? isConnected : nil,
                is_inbody_connected: integration == "inbody" ? isConnected : nil
            )
            
            try await client
                .from("user_profiles")
                .update(update)
                .eq("id", value: userId.uuidString)
                .execute()
            print("✅ [INTEGRATIONS] Updated \(integration) status to \(isConnected)")
        } catch {
            print("⚠️ [INTEGRATIONS] Failed to update \(integration) status: \(error.localizedDescription)")
        }
    }
    
    /// Update all integration statuses at once (called on app launch)
    func syncAllIntegrationStatuses() async {
        guard currentUser != nil else { return }
        
        // Check each integration's current connection status (MainActor isolated)
        let (stravaConnected, fitbitConnected, appleHealthConnected, inbodyConnected) = await MainActor.run {
            (
                StravaService.shared.isConnected,
                FitbitService.shared.isConnected,
                HealthKitManager.shared.isAuthorized,
                InBodyService.shared.isConnected
            )
        }
        
        // Update each status
        await updateIntegrationStatus(integration: "strava", isConnected: stravaConnected)
        await updateIntegrationStatus(integration: "fitbit", isConnected: fitbitConnected)
        await updateIntegrationStatus(integration: "apple_health", isConnected: appleHealthConnected)
        await updateIntegrationStatus(integration: "inbody", isConnected: inbodyConnected)
        
        print("✅ [INTEGRATIONS] Synced all integration statuses - Strava: \(stravaConnected), Fitbit: \(fitbitConnected), Apple Health: \(appleHealthConnected), InBody: \(inbodyConnected)")
    }
    
    /// Public function to create user profile for OAuth users when they complete onboarding
    /// This should be called when the user taps "Create Account" at the end of onboarding
    /// Only creates the profile if the user is authenticated via OAuth but doesn't have a profile yet
    func createProfileForOAuthUser(
        name: String,
        email: String,
        username: String?,
        birthday: String?,  // Added: birthday string (e.g., "26/10/1996")
        age: Int?,
        gender: String?,
        heightCm: Double?,
        weightKg: Double?,
        fitnessGoal: String?,
        experienceLevel: String?,
        equipment: [String]?,
        availableDays: Int?,
        workoutEnvironment: String?,
        phoneNumber: String? = nil  // For 2FA / account security (private)
    ) async throws {
        guard let userId = currentUser?.id else {
            print("❌ [PROFILE] Cannot create profile - no authenticated user")
            throw NSError(domain: "SupabaseManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        // Check if profile already exists (safety check)
        let profileExists = await verifyUserExists(userId: userId)
        if profileExists {
            print("⚠️ [PROFILE] Profile already exists for user \(userId), updating instead")
            try await updateUserProfile(
                name: name,
                heightCm: heightCm,
                weightKg: weightKg,
                fitnessGoal: fitnessGoal,
                experienceLevel: experienceLevel,
                equipment: equipment,
                availableDays: availableDays,
                workoutEnvironment: workoutEnvironment,
                birthday: birthday,  // Include birthday in update
                age: age,
                gender: gender
            )
            // Also set username if provided
            if let username = username {
                try await setUsername(username)
            }
            // Mark onboarding as complete
            try await client
                .from("user_profiles")
                .update(["has_completed_onboarding": true])
                .eq("id", value: userId.uuidString)
                .execute()
            return
        }
        
        print("🔐 [PROFILE] Creating profile for OAuth user at end of onboarding...")
        print("🔐 [PROFILE] User ID: \(userId), Name: \(name), Email: \(email)")
        
        // Create the full profile with all onboarding data
        struct OAuthProfileInsert: Encodable {
            let id: String
            let name: String
            let email: String
            let phone_number: String?  // For 2FA / account security (private)
            let phone_verified: Bool  // Whether phone was verified during onboarding
            let username: String?
            let birthday: String?  // Birthday string (e.g., "26/10/1996" or "1996-10-26")
            let age: Int?
            let gender: String?
            let height_cm: Double?
            let weight_kg: Double?
            let fitness_goal: String?
            let experience_level: String?
            let equipment: [String]?
            let available_days: Int?
            let workout_environment: String?
            let has_completed_onboarding: Bool
        }
        
        let profile = OAuthProfileInsert(
            id: userId.uuidString,
            name: name,
            email: email,
            phone_number: phoneNumber,  // 2FA phone number (private)
            phone_verified: phoneNumber != nil,  // true if phone provided = verified during onboarding
            username: username,
            birthday: birthday,  // Birthday string from onboarding
            age: age,
            gender: gender,
            height_cm: heightCm,
            weight_kg: weightKg,
            fitness_goal: fitnessGoal,
            experience_level: experienceLevel,
            equipment: equipment,
            available_days: availableDays,
            workout_environment: workoutEnvironment,
            has_completed_onboarding: true  // Profile created at end of onboarding = complete
        )
        
        // Log the upsert attempt with all data for debugging
        print("🔐 [PROFILE] Attempting upsert with data:")
        print("   - id: \(userId.uuidString)")
        print("   - name: \(name)")
        print("   - email: \(email)")
        print("   - phone_number: \(phoneNumber ?? "nil")")
        print("   - phone_verified: \(phoneNumber != nil)")
        print("   - username: \(username ?? "nil")")
        print("   - birthday: \(birthday ?? "nil")")
        print("   - age: \(age ?? 0)")
        print("   - gender: \(gender ?? "nil")")
        print("   - height_cm: \(heightCm ?? 0)")
        print("   - weight_kg: \(weightKg ?? 0)")
        print("   - fitness_goal: \(fitnessGoal ?? "nil")")
        print("   - experience_level: \(experienceLevel ?? "nil")")
        print("   - equipment: \(equipment ?? [])")
        print("   - available_days: \(availableDays ?? 0)")
        print("   - workout_environment: \(workoutEnvironment ?? "nil")")
        
        do {
            try await client
                .from("user_profiles")
                .upsert(profile, onConflict: "id")
                .execute()
            print("✅ [PROFILE] Upsert to user_profiles succeeded")
        } catch {
            print("❌ [PROFILE] Upsert FAILED: \(error)")
            print("❌ [PROFILE] Error details: \(error.localizedDescription)")
            
            // Log the error to the onboarding_logs table
            await logOnboardingEvent(
                eventType: "profile_update_error",
                stepName: "createProfileForOAuthUser",
                eventData: [
                    "user_id": userId.uuidString,
                    "name": name,
                    "email": email,
                    "attempted_action": "upsert"
                ],
                errorMessage: error.localizedDescription
            )
            
            throw error
        }
        
        // Create initial progress record
        do {
            try await createUserProgress(userId: userId)
            print("✅ [PROFILE] User progress record created")
        } catch {
            print("⚠️ [PROFILE] Failed to create user progress (non-fatal): \(error.localizedDescription)")
            // Don't throw - profile was created successfully
        }
        
        // Clear the pending OAuth data from UserDefaults
        await MainActor.run {
            UserDefaults.standard.removeObject(forKey: "pending_oauth_name")
            UserDefaults.standard.removeObject(forKey: "pending_oauth_email")
            UserDefaults.standard.removeObject(forKey: "pending_oauth_avatar")
        }
        
        print("✅ [PROFILE] OAuth user profile created successfully with all onboarding data!")
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
        birthday: String? = nil,  // Added: birthday string
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
            let birthday: String?
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
            birthday: birthday,
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
    
    // MARK: - Phone Number
    
    /// Update phone number for existing user (used for contact matching & 2FA)
    /// Sets phone_verified = true in database after successful verification
    func updatePhoneNumber(_ phoneNumber: String) async throws {
        guard let userId = currentUser?.id else {
            print("❌ [PHONE] Cannot update phone - no authenticated user")
            throw NSError(domain: "SupabaseManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        
        struct PhoneUpdate: Encodable {
            let phone_number: String
            let phone_verified: Bool
            let updated_at: String
        }
        
        let update = PhoneUpdate(
            phone_number: phoneNumber,
            phone_verified: true,  // Mark as verified since this is called after successful verification
            updated_at: dateToISO(Date())
        )
        
        try await client
            .from("user_profiles")
            .update(update)
            .eq("id", value: userId.uuidString)
            .execute()
        
        print("✅ [PHONE] Phone number updated and marked as verified for user: \(phoneNumber)")
    }
    
    /// Check if current user has a phone number saved
    func getUserPhoneNumber() async -> String? {
        guard let userId = currentUser?.id else { return nil }
        
        do {
            let result: [PhoneResult] = try await client
                .from("user_profiles")
                .select("phone_number")
                .eq("id", value: userId.uuidString)
                .execute()
                .value
            
            return result.first?.phone_number
        } catch {
            print("⚠️ [PHONE] Error fetching phone number: \(error)")
            return nil
        }
    }
    
    private struct PhoneResult: Decodable {
        let phone_number: String?
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
        
        // Update the user profile with the photo URL using RPC (handles UUID casting)
        do {
            let success: Bool = try await client
                .rpc("set_profile_photo_for_user", params: [
                    "p_user_id": userId.uuidString,
                    "p_photo_url": publicUrl.absoluteString
                ])
                .execute()
                .value
            
            if success {
                print("✅ Profile photo uploaded via RPC: \(publicUrl.absoluteString)")
            } else {
                print("⚠️ RPC returned false, trying direct update...")
                throw NSError(domain: "SupabaseManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "RPC returned false"])
            }
        } catch {
            // Fallback to direct update
            print("⚠️ Profile photo RPC failed: \(error.localizedDescription), trying direct update...")
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
            
            print("✅ Profile photo uploaded via direct update: \(publicUrl.absoluteString)")
        }
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
        
        // Try RPC with user_id parameter (handles UUID casting internally)
        do {
            print("📡 [USERNAME] Trying Method 1: RPC set_username_for_user with user_id: '\(user.id.uuidString)', username: '\(cleanUsername)'")
            let success: Bool = try await client
                .rpc("set_username_for_user", params: [
                    "p_user_id": user.id.uuidString,
                    "p_username": cleanUsername
                ])
                .execute()
                .value
            
            print("📡 [USERNAME] RPC returned: \(success)")
            
            if success {
                rpcSucceeded = true
                print("✅ [USERNAME] RPC success!")
            } else {
                print("⚠️ [USERNAME] RPC returned false, will try fallback...")
            }
            
        } catch {
            print("⚠️ [USERNAME] RPC set_username_for_user failed: \(error.localizedDescription)")
            
            // Try the original set_username as fallback
            do {
                print("📡 [USERNAME] Trying Method 2: RPC set_username (auth.uid based)")
                let success: Bool = try await client
                    .rpc("set_username", params: ["new_username": cleanUsername])
                    .execute()
                    .value
                
                if success {
                    rpcSucceeded = true
                    print("✅ [USERNAME] Fallback RPC success!")
                }
            } catch {
                print("⚠️ [USERNAME] Fallback RPC also failed: \(error.localizedDescription)")
            }
        }
        
        // Fallback: Direct table update if RPC failed
        if !rpcSucceeded {
            do {
                print("📡 [USERNAME] Trying Method 3: Direct table update")
                
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
            let phone_number: String?  // For 2FA / account security (private, not displayed)
            let phone_verified: Bool  // Whether phone was verified
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
            phone_number: user.phoneNumber,  // 2FA phone number (private)
            phone_verified: user.phoneNumber != nil && !(user.phoneNumber?.isEmpty ?? true),  // true if phone exists and not empty
            birthday: birthdayToISO(user.birthday),  // Convert to ISO format for database
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
            let phone_number: String?  // For 2FA / account security (private)
            let phone_verified: Bool  // Whether phone was verified
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
            phone_number: profile.phone_number,  // 2FA phone number (private)
            phone_verified: profile.phone_verified,  // Pass through from ProfileSync
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
        
        do {
            try await client
                .from("user_profiles")
                .upsert(upsertProfile, onConflict: "id")
                .execute()
            
            print("✅ [SYNC] Profile UPSERTED to cloud for user: \(userId.uuidString)")
        } catch {
            print("❌ [SYNC] UPSERT FAILED: \(error)")
            print("❌ [SYNC] Error details: \(error.localizedDescription)")
            print("❌ [SYNC] User can try Settings > Sync Profile to force retry")
            throw error  // Propagate error so caller knows sync failed
        }
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
    
    /// Force sync profile from Core Data to cloud - call this if sync seems broken
    /// This is a public method that can be called from Settings to manually trigger a sync
    func forceSyncProfileToCloud() async throws {
        guard let user = await MainActor.run(body: { UserManager.shared.currentUser }) else {
            print("❌ [FORCE SYNC] No local user to sync")
            throw NSError(domain: "SupabaseManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "No local user found"])
        }
        
        guard let userId = currentUser?.id else {
            print("❌ [FORCE SYNC] Not authenticated")
            throw NSError(domain: "SupabaseManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        print("🔄 [FORCE SYNC] Starting forced profile sync...")
        print("🔄 [FORCE SYNC] User: \(user.name ?? "unknown"), Age: \(user.age), Gender: \(user.gender ?? "nil")")
        
        // Build complete profile update with ALL fields
        struct FullProfileUpdate: Encodable {
            let name: String?
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
            let has_completed_onboarding: Bool
            let updated_at: String
        }
        
        let equipmentArray = user.getEquipment() ?? []
        
        let fullUpdate = FullProfileUpdate(
            name: user.name,
            birthday: birthdayToISO(user.birthday),  // Convert to ISO format for database
            age: user.age > 0 ? Int(user.age) : nil,
            gender: user.gender,
            height_cm: user.height > 0 ? Double(user.height) : nil,
            height_inches: user.heightInches > 0 ? Int(user.heightInches) : nil,
            weight_kg: user.weight > 0 ? Double(user.weight) : nil,
            weight_lbs: user.weightLbs > 0 ? user.weightLbs : nil,
            fitness_goal: user.fitnessGoal,
            experience_level: user.experienceLevel,
            strength_level: user.strengthLevel,
            workout_environment: user.workoutEnvironment,
            equipment: equipmentArray.isEmpty ? nil : equipmentArray,
            available_days: user.availableDays > 0 ? Int(user.availableDays) : nil,
            has_completed_onboarding: true,
            updated_at: dateToISO(Date())
        )
        
        try await client
            .from("user_profiles")
            .update(fullUpdate)
            .eq("id", value: userId.uuidString)
            .execute()
        
        print("✅ [FORCE SYNC] Profile force synced successfully!")
        print("   Name: \(user.name ?? "nil"), Birthday: \(user.birthday ?? "nil")")
        print("   Age: \(user.age), Gender: \(user.gender ?? "nil")")
        print("   Height: \(user.height)cm / \(user.heightInches)in")
        print("   Weight: \(user.weight)kg / \(user.weightLbs)lbs")
        print("   Goal: \(user.fitnessGoal ?? "nil"), Level: \(user.experienceLevel ?? "nil")")
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
        // Try using the secure RPC function first (bypasses RLS during signup)
        struct CreateProgressParams: Encodable {
            let user_id: String
        }
        
        do {
            try await client.rpc("create_user_progress", params: CreateProgressParams(user_id: userId.uuidString)).execute()
            print("✅ User progress created via RPC function")
        } catch {
            // Fallback to direct insert if RPC function doesn't exist
            print("⚠️ RPC function not available for progress, trying direct insert: \(error.localizedDescription)")
            
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
        
        // 🔥 Update user streak (cardio workouts count as workout sessions!)
        await MainActor.run {
            UserManager.shared.updateStreak()
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
    
    // Source tracking (for Strava, Apple Health, etc.)
    let source: String?
    let externalId: String?
    let externalUrl: String?
    let totalElevationGain: Double?
    
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
        case source
        case externalId = "external_id"
        case externalUrl = "external_url"
        case totalElevationGain = "total_elevation_gain"
    }
    
    /// Whether this workout was synced from Strava
    var isFromStrava: Bool {
        source == "strava"
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
