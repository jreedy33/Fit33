//
//  OnboardingTestHelper.swift
//  Fit33
//
//  Created for debugging onboarding flow issues
//  ⚠️ DEBUG ONLY - This entire file is excluded from production builds
//

#if DEBUG

import Foundation

/// Helper class to test the full onboarding flow with real database writes
/// Run from Settings screen with the debug button or from console
class OnboardingTestHelper {
    
    static let shared = OnboardingTestHelper()
    
    private init() {}
    
    /// Creates a test user and runs through the full onboarding flow
    /// This creates REAL data in the database
    func runFullOnboardingTest() async -> OnboardingTestResult {
        print("🧪 ============================================")
        print("🧪 ONBOARDING TEST STARTING")
        print("🧪 ============================================")
        
        let testId = Int.random(in: 1000...9999)
        let testEmail = "test_user_\(testId)@fit33test.com"
        let testPassword = "TestPassword123!"
        let testName = "Test User \(testId)"
        let testUsername = "testuser\(testId)"
        
        var result = OnboardingTestResult()
        result.testEmail = testEmail
        result.testUsername = testUsername
        
        let supabase = SupabaseManager.shared
        
        // Step 1: Sign Up
        print("📝 Step 1: Creating account...")
        print("   Email: \(testEmail)")
        print("   Username: @\(testUsername)")
        
        do {
            try await supabase.signUp(email: testEmail, password: testPassword, name: testName)
            result.signupSuccess = true
            print("✅ Step 1: Account created successfully")
            print("   User ID: \(supabase.currentUser?.id.uuidString ?? "nil")")
        } catch {
            result.errors.append("Signup failed: \(error.localizedDescription)")
            print("❌ Step 1 FAILED: \(error)")
            return result
        }
        
        // Step 2: Check authentication state
        print("\n📝 Step 2: Verifying authentication...")
        if supabase.isAuthenticated {
            result.authenticationVerified = true
            print("✅ Step 2: User is authenticated")
        } else {
            result.errors.append("User not authenticated after signup")
            print("❌ Step 2 FAILED: Not authenticated")
            return result
        }
        
        // Step 3: Wait a moment for profile creation to complete
        print("\n📝 Step 3: Waiting for profile sync (1 second)...")
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        print("✅ Step 3: Wait complete")
        
        // Step 4: Debug profile state before setting username
        print("\n📝 Step 4: Checking profile state before username...")
        await supabase.debugProfileState()
        
        // Step 5: Set username
        print("\n📝 Step 5: Setting username to @\(testUsername)...")
        do {
            try await supabase.setUsername(testUsername)
            result.usernameSetSuccess = true
            print("✅ Step 5: Username set successfully")
        } catch {
            result.errors.append("Set username failed: \(error.localizedDescription)")
            print("❌ Step 5 FAILED: \(error)")
            // Continue anyway to see if profile was created
        }
        
        // Step 6: Verify username was saved
        print("\n📝 Step 6: Verifying username in database...")
        do {
            if let savedUsername = try await supabase.getCurrentUsername() {
                if savedUsername == testUsername {
                    result.usernameVerified = true
                    print("✅ Step 6: Username verified: @\(savedUsername)")
                } else {
                    result.errors.append("Username mismatch: expected '\(testUsername)' got '\(savedUsername)'")
                    print("❌ Step 6 FAILED: Mismatch - expected '\(testUsername)' got '\(savedUsername)'")
                }
            } else {
                result.errors.append("Username is NULL in database")
                print("❌ Step 6 FAILED: Username is NULL")
            }
        } catch {
            result.errors.append("Verify username failed: \(error.localizedDescription)")
            print("❌ Step 6 FAILED: \(error)")
        }
        
        // Step 7: Complete profile update (simulating rest of onboarding)
        print("\n📝 Step 7: Simulating profile update with onboarding data...")
        do {
            try await supabase.updateUserProfile(
                name: testName,
                heightCm: 175.0,
                weightKg: 75.0,
                fitnessGoal: "Build Muscle",
                experienceLevel: "Intermediate",
                equipment: ["Dumbbells", "Barbell", "Cables"],
                availableDays: 4,
                workoutEnvironment: "gym",
                age: 30,
                gender: "Male"
            )
            result.profileUpdateSuccess = true
            print("✅ Step 7: Profile updated successfully")
        } catch {
            result.errors.append("Profile update failed: \(error.localizedDescription)")
            print("❌ Step 7 FAILED: \(error)")
        }
        
        // Step 8: Final verification
        print("\n📝 Step 8: Final database verification...")
        await supabase.debugProfileState()
        
        // Step 9: Clean up - sign out (optional, comment out to keep logged in)
        print("\n📝 Step 9: Signing out test user...")
        do {
            try await supabase.signOut()
            result.cleanupSuccess = true
            print("✅ Step 9: Signed out successfully")
        } catch {
            print("⚠️ Step 9: Sign out failed (non-critical): \(error)")
        }
        
        // Final summary
        print("\n🧪 ============================================")
        print("🧪 ONBOARDING TEST COMPLETE")
        print("🧪 ============================================")
        print("   Test Email: \(testEmail)")
        print("   Test Username: @\(testUsername)")
        print("   Results:")
        print("   ✓ Signup: \(result.signupSuccess ? "✅" : "❌")")
        print("   ✓ Auth: \(result.authenticationVerified ? "✅" : "❌")")
        print("   ✓ Username Set: \(result.usernameSetSuccess ? "✅" : "❌")")
        print("   ✓ Username Verified: \(result.usernameVerified ? "✅" : "❌")")
        print("   ✓ Profile Update: \(result.profileUpdateSuccess ? "✅" : "❌")")
        print("   ✓ Cleanup: \(result.cleanupSuccess ? "✅" : "❌")")
        
        if !result.errors.isEmpty {
            print("\n   ❌ ERRORS:")
            for error in result.errors {
                print("      - \(error)")
            }
        }
        
        print("\n   📊 Overall: \(result.isSuccess ? "SUCCESS ✅" : "FAILED ❌")")
        print("🧪 ============================================\n")
        
        return result
    }
    
    /// Quick test just for username functionality
    func testUsernameOnly() async {
        print("🧪 Testing username functionality for current user...")
        
        let supabase = SupabaseManager.shared
        
        guard supabase.isAuthenticated else {
            print("❌ Not authenticated - sign in first")
            return
        }
        
        await supabase.debugProfileState()
        
        let testUsername = "debug_\(Int.random(in: 100...999))"
        print("📝 Setting test username: @\(testUsername)")
        
        do {
            try await supabase.setUsername(testUsername)
            print("✅ Username set!")
        } catch {
            print("❌ Failed: \(error)")
        }
        
        // Verify
        do {
            let saved = try await supabase.getCurrentUsername()
            print("📝 Saved username: \(saved ?? "NULL")")
        } catch {
            print("❌ Verify failed: \(error)")
        }
    }
}

/// Result of the onboarding test
struct OnboardingTestResult {
    var testEmail: String = ""
    var testUsername: String = ""
    
    var signupSuccess: Bool = false
    var authenticationVerified: Bool = false
    var usernameSetSuccess: Bool = false
    var usernameVerified: Bool = false
    var profileUpdateSuccess: Bool = false
    var cleanupSuccess: Bool = false
    
    var errors: [String] = []
    
    var isSuccess: Bool {
        return signupSuccess && authenticationVerified && usernameSetSuccess && usernameVerified && profileUpdateSuccess
    }
}

#endif
