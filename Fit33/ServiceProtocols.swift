import Foundation
import SwiftUI
import CoreData

// MARK: - Service Protocols for Dependency Injection
// These protocols define the contracts for major services.
// Conformance will be added incrementally as services are refactored.
// Tests can create mock implementations of these protocols.

// MARK: - User Management

protocol UserManaging: ObservableObject {
    var currentUser: NSManagedObject? { get }
    var isLoggedIn: Bool { get }
    func getMaxAllowedRestDays() -> Int
}

// MARK: - Challenge Coordination

protocol ChallengeManaging: ObservableObject {
    var isLoading: Bool { get }
    func refreshChallenges() async
}

// MARK: - Workout Generation

protocol WorkoutGenerating {
    func generateWorkout(for user: NSManagedObject, splitType: String?, muscleGroups: [String]?) async throws
}

// MARK: - Meal Logging

protocol MealLogging: ObservableObject {
    func logMeal(name: String, calories: Int, protein: Double, carbs: Double, fat: Double) async throws
}

// MARK: - Health Data

protocol HealthDataProviding: ObservableObject {
    var todaySteps: Int { get }
    var todayCalories: Double { get }
    func requestAuthorization() async throws
    func syncTodayStats() async
}

// MARK: - Friend Management

protocol FriendManaging: ObservableObject {
    func sendFriendRequest(to userId: String) async throws
    func acceptFriendRequest(_ requestId: String) async throws
    func fetchFriends() async
}

// MARK: - Video Playback

protocol VideoPlaying: ObservableObject {
    func clearAllCaches()
}

// MARK: - Crash Reporting

protocol CrashReportable {
    func addBreadcrumb(_ message: String, category: String)
}

// MARK: - Notification Management

protocol NotificationManaging: ObservableObject {
    func requestPermission() async -> Bool
}

// MARK: - Store/Purchase Management

protocol StoreManaging: ObservableObject {
    var isPremium: Bool { get }
    func restorePurchases() async throws
}

// MARK: - Exercise Data

protocol ExerciseDataProviding {
    func getPopularityScore(for exerciseName: String) -> Int
    func isTopTierExercise(_ exerciseName: String) -> Bool
    func getPopularityBoost(for exerciseName: String) -> Int
}

extension ExercisePopularityService: ExerciseDataProviding {}
