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
        case addFood(mealType: String)  // Navigate to Meals tab + open Add Food for specific meal
        case statsTab           // Navigate to Stats tab (tab 4)
        
        // Social / Friends
        case friends
        case friendRequests     // Direct to friend requests tab
        case friendSearch       // Direct to friend search tab
        case sharedWorkout(workoutId: String)
        case receivedWorkout(workoutId: String)
        case receivedWorkouts
        
        // Challenges
        case challenges         // List of active challenges
        case challengeCreation  // Open challenge creation flow (same as "Challenge a Friend" widget)
        case challengeInvite(challengeId: String)
        case challengeDetail(challengeId: String)
        
        // Community Challenges
        case communityChallenge(slug: String)    // Join/view a community challenge
        case communityChallengeBrowse            // Browse/discover community challenges
        
        // Private Challenges
        case privateChallengeDetail(challengeId: String)   // View a private challenge
        case privateChallengeInvite(challengeId: String)   // Accept/view an invite
        case privateChallengeJoinByCode(code: String)      // Preview + join a private challenge by code
        
        // Dashboard Widgets (navigate to Home + scroll to widget)
        case hydration          // Home tab > Hydration widget
        case stepTracker        // Home tab > Step tracker widget
        case weightTracker      // Home tab > Weight tracker widget
        case workoutHistory     // Home tab > Recent workouts section
        
        // Achievements/Progress
        case personalRecord     // Stats tab > achievements
        case streakInfo         // Home tab > streak popup
        case programs           // Workout tab > program schedule
    }
    
    @Published var pendingDestination: Destination?
    @Published var showSharedWorkoutSheet = false
    @Published var pendingSharedWorkoutId: String?
    @Published var pendingReceivedWorkoutId: String?
    @Published var pendingCommunitySlug: String?          // Community challenge to join on open
    @Published var showCommunityJoinSheet = false
    @Published var pendingPrivateChallengeId: String?     // Private challenge to view on open
    @Published var showPrivateChallengeSheet = false
    @Published var pendingPrivateJoinCode: String?         // Private challenge code to preview + join
    @Published var showPrivateJoinSheet = false
    
    // Tab-specific pending routes for deep navigation after tab switch
    @Published var pendingFriendsRoute: String?           // Route to push on FriendsTabView's NavigationStack
    @Published var pendingDashboardRoute: String?         // Route to push on DashboardView's NavigationStack
    @Published var pendingMealType: String?              // Meal type to auto-open Add Food (breakfast/lunch/dinner/snacks)
    
    private init() {}
    
    /// Consume and clear the pending destination
    func consumeDestination() -> Destination? {
        let destination = pendingDestination
        pendingDestination = nil
        return destination
    }
    
    /// Handle incoming URL and route appropriately
    func handleURL(_ url: URL) -> Bool {
        AppLogger.debug("🔗 [DEEPLINK] Handling URL: \(url.absoluteString)", category: .network)
        
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
            AppLogger.debug("🏃 [DEEPLINK] Strava OAuth callback received - forwarding to StravaService", category: .network)
            // The callback is handled via .onOpenURL in StravaAuthSheet
            // Post notification for any listening views
            NotificationCenter.default.post(name: Notification.Name("StravaCallback"), object: url)
            return true
            
        case "inbody":
            // Handle InBody OAuth callback
            // Format: fit33://inbody/callback?code=xxx
            AppLogger.debug("📊 [DEEPLINK] InBody OAuth callback received - forwarding to InBodyService", category: .network)
            // The callback is handled via .onOpenURL in InBodyAuthSheet
            // Post notification for any listening views
            NotificationCenter.default.post(name: Notification.Name("InBodyCallback"), object: url)
            return true
            
        case "fitbit":
            // Handle Fitbit OAuth callback
            // Format: fit33://fitbit?code=xxx
            AppLogger.debug("[DEEPLINK] Fitbit OAuth callback received - forwarding to FitbitService", category: .network)
            NotificationCenter.default.post(name: Notification.Name("FitbitCallback"), object: url)
            return true
            
        case "whoop":
            // Handle WHOOP OAuth callback
            // Format: fit33://whoop?code=xxx
            AppLogger.debug("[DEEPLINK] WHOOP OAuth callback received - forwarding to WhoopService", category: .network)
            NotificationCenter.default.post(name: Notification.Name("WhoopCallback"), object: url)
            return true
            
        case "login-callback":
            // Handle OAuth callback (Google, Facebook, etc.)
            // Format: fit33://login-callback#access_token=xxx&...
            AppLogger.debug("🔐 [DEEPLINK] OAuth login callback received", category: .network)
            // Post notification for authentication handling
            NotificationCenter.default.post(name: Notification.Name("OAuthCallback"), object: url)
            return true
            
        case "friendrequests", "friend-requests":
            // Format: fit33://friendrequests
            pendingDestination = .friendRequests
            AppLogger.debug("👥 [DEEPLINK] Navigating to friend requests", category: .network)
            return true
            
        case "friends":
            // Format: fit33://friends
            pendingDestination = .friends
            AppLogger.debug("👥 [DEEPLINK] Navigating to friends list", category: .network)
            return true
            
        case "meals", "nutrition", "food":
            // Format: fit33://meals
            pendingDestination = .mealsTab
            AppLogger.debug("🍎 [DEEPLINK] Navigating to meals tab", category: .network)
            return true
            
        case "stats", "progress", "achievements":
            // Format: fit33://stats
            pendingDestination = .statsTab
            AppLogger.debug("📊 [DEEPLINK] Navigating to stats tab", category: .network)
            return true
            
        case "water", "hydration":
            // Format: fit33://hydration
            pendingDestination = .hydration
            AppLogger.debug("💧 [DEEPLINK] Navigating to hydration widget", category: .network)
            return true
            
        case "steps", "steptracker":
            // Format: fit33://steps
            pendingDestination = .stepTracker
            AppLogger.debug("👟 [DEEPLINK] Navigating to step tracker", category: .network)
            return true
            
        case "weight", "weighttracker":
            // Format: fit33://weight
            pendingDestination = .weightTracker
            AppLogger.debug("⚖️ [DEEPLINK] Navigating to weight tracker", category: .network)
            return true
            
        case "history", "workouthistory":
            // Format: fit33://history
            pendingDestination = .workoutHistory
            AppLogger.debug("📜 [DEEPLINK] Navigating to workout history", category: .network)
            return true
            
        case "streak":
            // Format: fit33://streak
            pendingDestination = .streakInfo
            AppLogger.debug("🔥 [DEEPLINK] Navigating to streak info", category: .network)
            return true
            
        case "personalrecord", "pr":
            // Format: fit33://personalrecord
            pendingDestination = .personalRecord
            AppLogger.debug("🏆 [DEEPLINK] Navigating to personal records", category: .network)
            return true
            
        case "challenge", "challenges":
            // Format: fit33://challenge/{challengeId} or fit33://challenges
            let path = url.path
            let challengeId = path.hasPrefix("/") ? String(path.dropFirst()) : path
            
            if !challengeId.isEmpty {
                pendingDestination = .challengeDetail(challengeId: challengeId)
                AppLogger.debug("🏆 [DEEPLINK] Navigating to challenge: \(challengeId)", category: .network)
            } else {
                pendingDestination = .challenges
                AppLogger.debug("🏆 [DEEPLINK] Navigating to challenges list", category: .network)
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
                AppLogger.debug("🌍 [DEEPLINK] Navigating to community challenge: \(slug)", category: .network)
            } else {
                pendingDestination = .communityChallengeBrowse
                AppLogger.debug("🌍 [DEEPLINK] Navigating to community challenges browse", category: .network)
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
                AppLogger.debug("🌍 [DEEPLINK] Join community challenge via code: \(code)", category: .network)
            }
            return true
            
        case "private-challenge", "private":
            // Format: fit33://private-challenge/{challengeId}
            let path = url.path
            let challengeId = path.hasPrefix("/") ? String(path.dropFirst()) : path
            
            if !challengeId.isEmpty {
                pendingPrivateChallengeId = challengeId
                pendingDestination = .privateChallengeDetail(challengeId: challengeId)
                showPrivateChallengeSheet = true
                AppLogger.debug("🔒 [DEEPLINK] Navigating to private challenge: \(challengeId)", category: .network)
            } else {
                pendingDestination = .dashboard
                AppLogger.debug("🔒 [DEEPLINK] Navigating to dashboard for private challenges", category: .network)
            }
            return true
            
        case "private-invite":
            // Format: fit33://private-invite/{challengeId}
            let path = url.path
            let challengeId = path.hasPrefix("/") ? String(path.dropFirst()) : path
            
            if !challengeId.isEmpty {
                pendingPrivateChallengeId = challengeId
                pendingDestination = .privateChallengeInvite(challengeId: challengeId)
                showPrivateChallengeSheet = true
                AppLogger.debug("🔒 [DEEPLINK] Navigating to private challenge invite: \(challengeId)", category: .network)
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
                AppLogger.debug("🌍 [DEEPLINK] Universal link to community challenge: \(slug)", category: .network)
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
                AppLogger.debug("🌍 [DEEPLINK] Universal link join: \(code)", category: .network)
                return true
            }
            return false
            
        case "p", "private":
            // Format: https://fit33.app/p/{challengeId}
            if pathComponents.count >= 2 {
                let challengeId = pathComponents[1]
                pendingPrivateChallengeId = challengeId
                pendingDestination = .privateChallengeDetail(challengeId: challengeId)
                showPrivateChallengeSheet = true
                AppLogger.debug("🔒 [DEEPLINK] Universal link to private challenge: \(challengeId)", category: .network)
                return true
            }
            return false
            
        case "pc":
            // Format: https://fit33.app/pc/{joinCode} — show private challenge preview + join
            if pathComponents.count >= 2 {
                let joinCode = pathComponents[1]
                pendingPrivateJoinCode = joinCode
                pendingDestination = .privateChallengeJoinByCode(code: joinCode)
                showPrivateJoinSheet = true
                AppLogger.debug("🔒 [DEEPLINK] Universal link to private challenge join preview: \(joinCode)", category: .network)
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
        pendingPrivateChallengeId = nil
        showPrivateChallengeSheet = false
        pendingPrivateJoinCode = nil
        showPrivateJoinSheet = false
        pendingFriendsRoute = nil
        pendingDashboardRoute = nil
    }
}

