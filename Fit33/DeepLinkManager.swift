import Foundation
import SwiftUI

/// Manages deep link navigation throughout the app
@MainActor
class DeepLinkManager: ObservableObject {
    static let shared = DeepLinkManager()
    
    enum Destination: Equatable {
        case running
        case workout
        case dashboard
        case sharedWorkout(workoutId: String)
    }
    
    @Published var pendingDestination: Destination?
    @Published var showSharedWorkoutSheet = false
    @Published var pendingSharedWorkoutId: String?
    
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
            
        default:
            return false
        }
    }
    
    /// Clear all pending navigation state
    func clearPendingNavigation() {
        pendingDestination = nil
        pendingSharedWorkoutId = nil
        showSharedWorkoutSheet = false
    }
}

