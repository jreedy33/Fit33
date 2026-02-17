import Foundation
import SwiftUI

/// Manages deep link navigation throughout the app
@MainActor
class DeepLinkManager: ObservableObject {
    static let shared = DeepLinkManager()
    
    enum Destination: Equatable {
        // Tab Navigation
        case running
        case workout
        case dashboard
        case mealsTab           // Navigate to Meals tab (tab 3)
        case statsTab           // Navigate to Stats tab (tab 4)
        
        // Social / Friends
        case friends
        case friendRequests     // Direct to friend requests tab
        case sharedWorkout(workoutId: String)
        case receivedWorkout(workoutId: String)
        case receivedWorkouts
        
        // Challenges
        case challenges         // List of active challenges
        case challengeInvite(challengeId: String)
        case challengeDetail(challengeId: String)
        
        // Community Challenges
        case communityChallenge(slug: String)    // Join/view a community challenge
        case communityChallengeBrowse            // Browse/discover community challenges
        
        // Dashboard Widgets (navigate to Home + scroll to widget)
        case hydration          // Home tab > Hydration widget
        case stepTracker        // Home tab > Step tracker widget
        case weightTracker      // Home tab > Weight tracker widget
        case workoutHistory     // Home tab > Recent workouts section
        
        // Achievements/Progress
        case personalRecord     // Stats tab > achievements
        case streakInfo         // Home tab > streak popup
    }
    
    @Published var pendingDestination: Destination?
    @Published var showSharedWorkoutSheet = false
    @Published var pendingSharedWorkoutId: String?
    @Published var pendingReceivedWorkoutId: String?
    @Published var pendingCommunitySlug: String?          // Community challenge to join on open
    @Published var showCommunityJoinSheet = false
    
    private init() {}
    
    /// Consume and clear the pending destination
    func consumeDestination() -> Destination? {
        let destination = pendingDestination
        pendingDestination = nil
        return destination
    }
    
    /// Handle incoming URL and route appropriately
    func handleURL(_ url: URL) -> Bool {
        print("🔗 [DEEPLINK] Handling URL: \(url.absoluteString)")
        
        guard let scheme = url.scheme?.lowercased() else { return false }
        
        // Handle our custom scheme (fit33://)
        if scheme == "fit33" {
            return handleCustomScheme(url)
        }
        
        // Handle universal links (https://fit33.app/...)
        if scheme == "https" && url.host?.contains("fit33") == true {
            return handleUniversalLink(url)
        }
        
        return false
    }
    
    /// Handle custom URL scheme (fit33://...)
    private func handleCustomScheme(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        
        switch host {
        case "running":
            pendingDestination = .running
            return true
            
        case "workout":
            // Format: fit33://workout/{workoutId}
            let path = url.path
            let workoutId = path.hasPrefix("/") ? String(path.dropFirst()) : path
            
            if !workoutId.isEmpty {
                pendingSharedWorkoutId = workoutId
                pendingDestination = .sharedWorkout(workoutId: workoutId)
                showSharedWorkoutSheet = true
                
                // Also notify the sharing service
                _ = WorkoutSharingService.shared.handleSharedWorkoutURL(url)
                return true
            }
            return false
            
        case "dashboard":
            pendingDestination = .dashboard
            return true
            
        case "share":
            // Format: fit33://share/workout/{workoutId}
            let pathComponents = url.pathComponents.filter { $0 != "/" }
            if pathComponents.count >= 2 && pathComponents[0] == "workout" {
                let workoutId = pathComponents[1]
                pendingSharedWorkoutId = workoutId
                pendingDestination = .sharedWorkout(workoutId: workoutId)
                showSharedWorkoutSheet = true
                return true
            }
            return false
            
        case "strava":
            // Handle Strava OAuth callback
            // Format: fit33://strava?code=xxx&scope=xxx
            print("🏃 [DEEPLINK] Strava OAuth callback received - forwarding to StravaService")
            // The callback is handled via .onOpenURL in StravaAuthSheet
            // Post notification for any listening views
            NotificationCenter.default.post(name: Notification.Name("StravaCallback"), object: url)
            return true
            
        case "inbody":
            // Handle InBody OAuth callback
            // Format: fit33://inbody/callback?code=xxx
            print("📊 [DEEPLINK] InBody OAuth callback received - forwarding to InBodyService")
            // The callback is handled via .onOpenURL in InBodyAuthSheet
            // Post notification for any listening views
            NotificationCenter.default.post(name: Notification.Name("InBodyCallback"), object: url)
            return true
            
        case "fitbit":
            // Handle Fitbit OAuth callback
            // Format: fit33://fitbit?code=xxx
            print("⌚ [DEEPLINK] Fitbit OAuth callback received - forwarding to FitbitService")
            // Post notification for any listening views
            NotificationCenter.default.post(name: Notification.Name("FitbitCallback"), object: url)
            return true
            
        case "login-callback":
            // Handle OAuth callback (Google, Facebook, etc.)
            // Format: fit33://login-callback#access_token=xxx&...
            print("🔐 [DEEPLINK] OAuth login callback received")
            // Post notification for authentication handling
            NotificationCenter.default.post(name: Notification.Name("OAuthCallback"), object: url)
            return true
            
        case "friendrequests", "friend-requests":
            // Format: fit33://friendrequests
            pendingDestination = .friendRequests
            print("👥 [DEEPLINK] Navigating to friend requests")
            return true
            
        case "friends":
            // Format: fit33://friends
            pendingDestination = .friends
            print("👥 [DEEPLINK] Navigating to friends list")
            return true
            
        case "meals", "nutrition", "food":
            // Format: fit33://meals
            pendingDestination = .mealsTab
            print("🍎 [DEEPLINK] Navigating to meals tab")
            return true
            
        case "stats", "progress", "achievements":
            // Format: fit33://stats
            pendingDestination = .statsTab
            print("📊 [DEEPLINK] Navigating to stats tab")
            return true
            
        case "water", "hydration":
            // Format: fit33://hydration
            pendingDestination = .hydration
            print("💧 [DEEPLINK] Navigating to hydration widget")
            return true
            
        case "steps", "steptracker":
            // Format: fit33://steps
            pendingDestination = .stepTracker
            print("👟 [DEEPLINK] Navigating to step tracker")
            return true
            
        case "weight", "weighttracker":
            // Format: fit33://weight
            pendingDestination = .weightTracker
            print("⚖️ [DEEPLINK] Navigating to weight tracker")
            return true
            
        case "history", "workouthistory":
            // Format: fit33://history
            pendingDestination = .workoutHistory
            print("📜 [DEEPLINK] Navigating to workout history")
            return true
            
        case "streak":
            // Format: fit33://streak
            pendingDestination = .streakInfo
            print("🔥 [DEEPLINK] Navigating to streak info")
            return true
            
        case "personalrecord", "pr":
            // Format: fit33://personalrecord
            pendingDestination = .personalRecord
            print("🏆 [DEEPLINK] Navigating to personal records")
            return true
            
        case "challenge", "challenges":
            // Format: fit33://challenge/{challengeId} or fit33://challenges
            let path = url.path
            let challengeId = path.hasPrefix("/") ? String(path.dropFirst()) : path
            
            if !challengeId.isEmpty {
                pendingDestination = .challengeDetail(challengeId: challengeId)
                print("🏆 [DEEPLINK] Navigating to challenge: \(challengeId)")
            } else {
                pendingDestination = .challenges
                print("🏆 [DEEPLINK] Navigating to challenges list")
            }
            return true
            
        case "community-challenge", "community":
            // Format: fit33://community-challenge/{slug} or fit33://community
            let path = url.path
            let slug = path.hasPrefix("/") ? String(path.dropFirst()) : path
            
            if !slug.isEmpty {
                pendingCommunitySlug = slug
                pendingDestination = .communityChallenge(slug: slug)
                showCommunityJoinSheet = true
                print("🌍 [DEEPLINK] Navigating to community challenge: \(slug)")
            } else {
                pendingDestination = .communityChallengeBrowse
                print("🌍 [DEEPLINK] Navigating to community challenges browse")
            }
            return true
            
        case "join":
            // Format: fit33://join/{code} — shorthand for joining a community challenge
            let path = url.path
            let code = path.hasPrefix("/") ? String(path.dropFirst()) : path
            
            if !code.isEmpty {
                pendingCommunitySlug = code
                pendingDestination = .communityChallenge(slug: code)
                showCommunityJoinSheet = true
                print("🌍 [DEEPLINK] Join community challenge via code: \(code)")
            }
            return true
            
        default:
            return false
        }
    }
    
    /// Handle universal links (https://fit33.app/...)
    private func handleUniversalLink(_ url: URL) -> Bool {
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        
        guard !pathComponents.isEmpty else { return false }
        
        switch pathComponents[0].lowercased() {
        case "workout":
            // Format: https://fit33.app/workout/{workoutId}
            if pathComponents.count >= 2 {
                let workoutId = pathComponents[1]
                pendingSharedWorkoutId = workoutId
                pendingDestination = .sharedWorkout(workoutId: workoutId)
                showSharedWorkoutSheet = true
                return true
            }
            return false
            
        case "download":
            // Just downloading the app - navigate to home
            pendingDestination = .dashboard
            return true
            
        case "c", "challenge", "community":
            // Format: https://fit33.app/c/{slug}
            // This is the shareable community challenge URL
            if pathComponents.count >= 2 {
                let slug = pathComponents[1]
                pendingCommunitySlug = slug
                pendingDestination = .communityChallenge(slug: slug)
                showCommunityJoinSheet = true
                print("🌍 [DEEPLINK] Universal link to community challenge: \(slug)")
                return true
            }
            return false
            
        case "join":
            // Format: https://fit33.app/join/{code}
            if pathComponents.count >= 2 {
                let code = pathComponents[1]
                pendingCommunitySlug = code
                pendingDestination = .communityChallenge(slug: code)
                showCommunityJoinSheet = true
                print("🌍 [DEEPLINK] Universal link join: \(code)")
                return true
            }
            return false
            
        default:
            return false
        }
    }
    
    /// Clear all pending navigation state
    func clearPendingNavigation() {
        pendingDestination = nil
        pendingSharedWorkoutId = nil
        showSharedWorkoutSheet = false
        pendingCommunitySlug = nil
        showCommunityJoinSheet = false
    }
}

