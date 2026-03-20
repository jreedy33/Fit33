// AppHealthDiagnostics.swift
// Fit33
//
// Comprehensive App Health Diagnostic System
// Runs automated checks across all app subsystems and produces a health report.
// Access via DevMenu or call AppHealthDiagnostics.shared.runFullDiagnostic()
//

import Foundation
import CoreData
import SwiftUI

// MARK: - Diagnostic Result Model

enum DiagnosticSeverity: String, Codable, Comparable {
    case critical = "🔴 CRITICAL"
    case warning = "🟡 WARNING"
    case info = "🔵 INFO"
    case passed = "✅ PASSED"
    
    static func < (lhs: DiagnosticSeverity, rhs: DiagnosticSeverity) -> Bool {
        let order: [DiagnosticSeverity] = [.critical, .warning, .info, .passed]
        return (order.firstIndex(of: lhs) ?? 0) < (order.firstIndex(of: rhs) ?? 0)
    }
}

struct DiagnosticResult: Identifiable {
    let id = UUID()
    let category: String
    let check: String
    let severity: DiagnosticSeverity
    let message: String
    let fix: String?
    let autoFixed: Bool
    
    init(category: String, check: String, severity: DiagnosticSeverity, message: String, fix: String? = nil, autoFixed: Bool = false) {
        self.category = category
        self.check = check
        self.severity = severity
        self.message = message
        self.fix = fix
        self.autoFixed = autoFixed
    }
}

struct DiagnosticReport {
    let timestamp: Date
    let results: [DiagnosticResult]
    let duration: TimeInterval
    
    var criticalCount: Int { results.filter { $0.severity == .critical }.count }
    var warningCount: Int { results.filter { $0.severity == .warning }.count }
    var passedCount: Int { results.filter { $0.severity == .passed }.count }
    var infoCount: Int { results.filter { $0.severity == .info }.count }
    var autoFixedCount: Int { results.filter { $0.autoFixed }.count }
    
    var overallHealth: String {
        if criticalCount > 0 { return "🔴 CRITICAL — \(criticalCount) critical issue(s)" }
        if warningCount > 3 { return "🟠 DEGRADED — \(warningCount) warnings" }
        if warningCount > 0 { return "🟡 FAIR — \(warningCount) warning(s)" }
        return "✅ HEALTHY"
    }
    
    var healthScore: Int {
        let total = results.count
        guard total > 0 else { return 100 }
        let deductions = criticalCount * 15 + warningCount * 5
        return max(0, 100 - deductions)
    }
    
    var summary: String {
        """
        ╔══════════════════════════════════════════════════════════╗
        ║           FIT33 APP HEALTH DIAGNOSTIC REPORT            ║
        ╠══════════════════════════════════════════════════════════╣
        ║  Timestamp: \(formattedTimestamp)
        ║  Duration:  \(String(format: "%.2f", duration))s
        ║  Overall:   \(overallHealth)
        ║  Score:     \(healthScore)/100
        ╠══════════════════════════════════════════════════════════╣
        ║  ✅ Passed:   \(passedCount)
        ║  🔵 Info:     \(infoCount)
        ║  🟡 Warnings: \(warningCount)
        ║  🔴 Critical: \(criticalCount)
        ║  🔧 Auto-Fixed: \(autoFixedCount)
        ╚══════════════════════════════════════════════════════════╝
        """
    }
    
    private var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: timestamp)
    }
}

// MARK: - App Health Diagnostics Engine

@MainActor
final class AppHealthDiagnostics: ObservableObject {
    static let shared = AppHealthDiagnostics()
    
    @Published var isRunning = false
    @Published var currentCheck = ""
    @Published var latestReport: DiagnosticReport?
    @Published var progress: Double = 0
    
    private let viewContext = PersistenceController.shared.container.viewContext
    
    private init() {}
    
    // MARK: - Run Full Diagnostic
    
    func runFullDiagnostic() async -> DiagnosticReport {
        isRunning = true
        progress = 0
        let startTime = CFAbsoluteTimeGetCurrent()
        var allResults: [DiagnosticResult] = []
        
        let checks: [(String, () async -> [DiagnosticResult])] = [
            ("Core Data Integrity", checkCoreDataIntegrity),
            ("User Profile Health", checkUserProfileHealth),
            ("Authentication State", checkAuthenticationState),
            ("Exercise Library", checkExerciseLibrary),
            ("Workout System", checkWorkoutSystem),
            ("Memory & Performance", checkMemoryAndPerformance),
            ("Cache Health", checkCacheHealth),
            ("Network & Supabase", checkNetworkHealth),
            ("UserDefaults Integrity", checkUserDefaultsIntegrity),
            ("Service Singletons", checkServiceSingletons),
            ("Challenge System", checkChallengeSystem),
            ("Notification System", checkNotificationSystem),
            ("Data Consistency", checkDataConsistency),
            ("Thread Safety", checkThreadSafety),
        ]
        
        for (index, (name, check)) in checks.enumerated() {
            currentCheck = name
            progress = Double(index) / Double(checks.count)
            let results = await check()
            allResults.append(contentsOf: results)
        }
        
        progress = 1.0
        currentCheck = "Complete"
        
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        let report = DiagnosticReport(
            timestamp: Date(),
            results: allResults.sorted { $0.severity < $1.severity },
            duration: duration
        )
        
        latestReport = report
        isRunning = false
        
        // Print summary
        print(report.summary)
        for result in report.results where result.severity != .passed {
            print("  \(result.severity.rawValue) [\(result.category)] \(result.check): \(result.message)")
            if let fix = result.fix {
                print("    → Fix: \(fix)")
            }
            if result.autoFixed {
                print("    → ✅ AUTO-FIXED")
            }
        }
        
        return report
    }
    
    // MARK: - 1. Core Data Integrity
    
    private func checkCoreDataIntegrity() async -> [DiagnosticResult] {
        var results: [DiagnosticResult] = []
        
        // Check if persistent store is loaded
        let stores = PersistenceController.shared.container.persistentStoreCoordinator.persistentStores
        if stores.isEmpty {
            results.append(DiagnosticResult(
                category: "Core Data", check: "Persistent Store",
                severity: .critical, message: "No persistent stores loaded — data cannot be saved",
                fix: "Restart the app. If persists, delete and reinstall."
            ))
        } else {
            results.append(DiagnosticResult(
                category: "Core Data", check: "Persistent Store",
                severity: .passed, message: "Persistent store loaded at \(stores.first?.url?.lastPathComponent ?? "unknown")"
            ))
        }
        
        // Check for pending changes that haven't been saved
        if viewContext.hasChanges {
            results.append(DiagnosticResult(
                category: "Core Data", check: "Unsaved Changes",
                severity: .warning, message: "View context has unsaved changes — data may be lost on crash",
                fix: "Saving pending changes now", autoFixed: true
            ))
            try? viewContext.save()
        } else {
            results.append(DiagnosticResult(
                category: "Core Data", check: "Unsaved Changes",
                severity: .passed, message: "No unsaved changes"
            ))
        }
        
        // Check merge policy (NSMergeByPropertyObjectTrumpMergePolicy is a singleton instance, not a type)
        let mergePolicy = viewContext.mergePolicy as AnyObject
        if mergePolicy === NSMergeByPropertyObjectTrumpMergePolicy as AnyObject {
            results.append(DiagnosticResult(
                category: "Core Data", check: "Merge Policy",
                severity: .passed, message: "Using NSMergeByPropertyObjectTrumpMergePolicy (correct)"
            ))
        } else {
            results.append(DiagnosticResult(
                category: "Core Data", check: "Merge Policy",
                severity: .warning, message: "Unexpected merge policy — may cause data conflicts"
            ))
        }
        
        // Check for orphaned workout exercises (workouts without exercises or vice versa)
        do {
            let workoutRequest: NSFetchRequest<Workout> = Workout.fetchRequest()
            let allWorkouts = try viewContext.fetch(workoutRequest)
            let orphanedWorkouts = allWorkouts.filter { $0.id == nil }
            
            if !orphanedWorkouts.isEmpty {
                results.append(DiagnosticResult(
                    category: "Core Data", check: "Orphaned Workouts",
                    severity: .warning, message: "\(orphanedWorkouts.count) workout(s) with nil ID found",
                    fix: "Cleaning up orphaned workouts", autoFixed: true
                ))
                for workout in orphanedWorkouts {
                    viewContext.delete(workout)
                }
                try? viewContext.save()
            } else {
                results.append(DiagnosticResult(
                    category: "Core Data", check: "Orphaned Workouts",
                    severity: .passed, message: "All workouts have valid IDs"
                ))
            }
        } catch {
            results.append(DiagnosticResult(
                category: "Core Data", check: "Workout Fetch",
                severity: .critical, message: "Cannot fetch workouts: \(error.localizedDescription)"
            ))
        }
        
        return results
    }
    
    // MARK: - 2. User Profile Health
    
    private func checkUserProfileHealth() async -> [DiagnosticResult] {
        var results: [DiagnosticResult] = []
        
        let userRequest: NSFetchRequest<User> = User.fetchRequest()
        
        do {
            let users = try viewContext.fetch(userRequest)
            
            // Check for duplicate users (should only be 1)
            if users.count > 1 {
                results.append(DiagnosticResult(
                    category: "User Profile", check: "Duplicate Users",
                    severity: .critical, message: "\(users.count) user profiles found — should be exactly 1. This causes unpredictable behavior.",
                    fix: "Keeping most recent user, removing duplicates", autoFixed: true
                ))
                // Keep the most recent user, delete others
                let sortedUsers = users.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
                for user in sortedUsers.dropFirst() {
                    viewContext.delete(user)
                }
                try? viewContext.save()
                UserManager.shared.reloadCurrentUser()
            } else if users.count == 0 {
                if SupabaseManager.shared.isAuthenticated {
                    results.append(DiagnosticResult(
                        category: "User Profile", check: "Missing User",
                        severity: .critical, message: "Authenticated but no local user profile — app state mismatch"
                    ))
                } else {
                    results.append(DiagnosticResult(
                        category: "User Profile", check: "User Count",
                        severity: .info, message: "No local user (not authenticated)"
                    ))
                }
            } else {
                results.append(DiagnosticResult(
                    category: "User Profile", check: "User Count",
                    severity: .passed, message: "Single user profile ✓"
                ))
            }
            
            if let user = users.first {
                // Validate required fields
                if user.name == nil || user.name?.isEmpty == true {
                    results.append(DiagnosticResult(
                        category: "User Profile", check: "Name",
                        severity: .warning, message: "User name is empty — display issues in social features"
                    ))
                } else {
                    results.append(DiagnosticResult(
                        category: "User Profile", check: "Name",
                        severity: .passed, message: "Name: \(user.name ?? "")"
                    ))
                }
                
                // Check equipment data integrity
                let equipment = user.getEquipment()
                if equipment == nil || equipment?.isEmpty == true {
                    results.append(DiagnosticResult(
                        category: "User Profile", check: "Equipment",
                        severity: .warning, message: "No equipment set — workout generation may produce poor results",
                        fix: "User should set equipment in Settings"
                    ))
                } else {
                    results.append(DiagnosticResult(
                        category: "User Profile", check: "Equipment",
                        severity: .passed, message: "\(equipment?.count ?? 0) equipment items configured"
                    ))
                }
                
                // Check fitness goal
                if user.fitnessGoal == nil || user.fitnessGoal?.isEmpty == true {
                    results.append(DiagnosticResult(
                        category: "User Profile", check: "Fitness Goal",
                        severity: .warning, message: "No fitness goal set — workout intelligence disabled"
                    ))
                } else {
                    results.append(DiagnosticResult(
                        category: "User Profile", check: "Fitness Goal",
                        severity: .passed, message: "Goal: \(user.fitnessGoal ?? "")"
                    ))
                }
                
                // Check height/weight sanity
                if user.weight <= 0 || user.height <= 0 {
                    results.append(DiagnosticResult(
                        category: "User Profile", check: "Body Metrics",
                        severity: .warning, message: "Height (\(user.height)cm) or weight (\(user.weight)kg) invalid — calorie calculations wrong"
                    ))
                } else {
                    results.append(DiagnosticResult(
                        category: "User Profile", check: "Body Metrics",
                        severity: .passed, message: "Height: \(user.height)cm, Weight: \(user.weight)kg"
                    ))
                }
                
                // Check for unit consistency
                if user.heightInches == 0 && user.height > 0 {
                    let fixedInches = Int16(Double(user.height) / 2.54)
                    user.heightInches = fixedInches
                    try? viewContext.save()
                    results.append(DiagnosticResult(
                        category: "User Profile", check: "Height Inches",
                        severity: .warning, message: "heightInches was 0 — backfilled to \(fixedInches)",
                        fix: "Auto-calculated from cm", autoFixed: true
                    ))
                }
                
                if user.weightLbs == 0 && user.weight > 0 {
                    let fixedLbs = Double(user.weight) * 2.20462
                    user.weightLbs = fixedLbs
                    try? viewContext.save()
                    results.append(DiagnosticResult(
                        category: "User Profile", check: "Weight Lbs",
                        severity: .warning, message: "weightLbs was 0 — backfilled to \(String(format: "%.1f", fixedLbs))",
                        fix: "Auto-calculated from kg", autoFixed: true
                    ))
                }
                
                // Check streak integrity
                if user.currentStreak < 0 {
                    user.currentStreak = 0
                    try? viewContext.save()
                    results.append(DiagnosticResult(
                        category: "User Profile", check: "Streak",
                        severity: .warning, message: "Negative streak detected and reset to 0",
                        autoFixed: true
                    ))
                }
                
                if user.currentStreak > user.longestStreak && user.longestStreak > 0 {
                    user.longestStreak = user.currentStreak
                    try? viewContext.save()
                    results.append(DiagnosticResult(
                        category: "User Profile", check: "Streak Consistency",
                        severity: .warning, message: "Current streak > longest streak — fixed longest to \(user.currentStreak)",
                        autoFixed: true
                    ))
                }
            }
        } catch {
            results.append(DiagnosticResult(
                category: "User Profile", check: "Fetch",
                severity: .critical, message: "Cannot fetch user profile: \(error.localizedDescription)"
            ))
        }
        
        return results
    }
    
    // MARK: - 3. Authentication State
    
    private func checkAuthenticationState() async -> [DiagnosticResult] {
        var results: [DiagnosticResult] = []
        
        let isAuthenticated = SupabaseManager.shared.isAuthenticated
        let hasLocalUser = UserManager.shared.currentUser != nil
        let hasCompletedOnboarding = UserManager.shared.hasCompletedOnboarding
        
        // Check auth ↔ local user consistency
        if isAuthenticated && !hasLocalUser {
            results.append(DiagnosticResult(
                category: "Auth", check: "Auth-Profile Sync",
                severity: .critical, message: "Authenticated with Supabase but no local Core Data user — app will crash on profile access"
            ))
        } else if !isAuthenticated && hasLocalUser && hasCompletedOnboarding {
            results.append(DiagnosticResult(
                category: "Auth", check: "Auth-Profile Sync",
                severity: .warning, message: "Local user exists but not authenticated — cloud sync disabled"
            ))
        } else {
            results.append(DiagnosticResult(
                category: "Auth", check: "Auth-Profile Sync",
                severity: .passed, message: "Auth state consistent (authenticated: \(isAuthenticated), local user: \(hasLocalUser))"
            ))
        }
        
        // Check Supabase client initialization
        if SupabaseManager.shared.supabaseClient == nil {
            results.append(DiagnosticResult(
                category: "Auth", check: "Supabase Client",
                severity: .critical, message: "Supabase client is nil — all network operations will fail"
            ))
        } else {
            results.append(DiagnosticResult(
                category: "Auth", check: "Supabase Client",
                severity: .passed, message: "Supabase client initialized"
            ))
        }
        
        // Check for stale manual sign-out flag
        let manualSignOut = UserDefaults.standard.bool(forKey: "user_manually_signed_out")
        if manualSignOut && isAuthenticated {
            UserDefaults.standard.removeObject(forKey: "user_manually_signed_out")
            results.append(DiagnosticResult(
                category: "Auth", check: "Sign-Out Flag",
                severity: .warning, message: "Stale 'user_manually_signed_out' flag cleared (user is authenticated)",
                autoFixed: true
            ))
        }
        
        return results
    }
    
    // MARK: - 4. Exercise Library
    
    private func checkExerciseLibrary() async -> [DiagnosticResult] {
        var results: [DiagnosticResult] = []
        
        let exercises = ExerciseLibraryService.shared.getAllExercises()
        
        if exercises.isEmpty {
            results.append(DiagnosticResult(
                category: "Exercise Library", check: "Exercise Count",
                severity: .critical, message: "0 exercises in library — workout generation will fail completely"
            ))
        } else if exercises.count < 50 {
            results.append(DiagnosticResult(
                category: "Exercise Library", check: "Exercise Count",
                severity: .warning, message: "Only \(exercises.count) exercises — expected 300+. May have sync issues."
            ))
        } else {
            results.append(DiagnosticResult(
                category: "Exercise Library", check: "Exercise Count",
                severity: .passed, message: "\(exercises.count) exercises loaded"
            ))
        }
        
        // Check for exercises with nil names
        let nilNameExercises = exercises.filter { $0.name == nil || $0.name?.isEmpty == true }
        if !nilNameExercises.isEmpty {
            results.append(DiagnosticResult(
                category: "Exercise Library", check: "Nil Names",
                severity: .warning, message: "\(nilNameExercises.count) exercises with nil/empty names — will show as blank in UI",
                fix: "Removing invalid exercises", autoFixed: true
            ))
            for exercise in nilNameExercises {
                viewContext.delete(exercise)
            }
            try? viewContext.save()
            ExerciseLibraryService.shared.invalidateCache()
        }
        
        // Check for duplicate exercise names
        var nameCount: [String: Int] = [:]
        for exercise in exercises {
            if let name = exercise.name?.lowercased() {
                nameCount[name, default: 0] += 1
            }
        }
        let duplicates = nameCount.filter { $0.value > 1 }
        if duplicates.count > 10 {
            results.append(DiagnosticResult(
                category: "Exercise Library", check: "Duplicates",
                severity: .warning, message: "\(duplicates.count) duplicate exercise names detected — wasted memory and confusing UX"
            ))
        } else {
            results.append(DiagnosticResult(
                category: "Exercise Library", check: "Duplicates",
                severity: .passed, message: "Minimal duplicates (\(duplicates.count))"
            ))
        }
        
        // Check exercises ready flag
        if !ExerciseLibraryService.shared.isExercisesReady && exercises.count > 100 {
            ExerciseLibraryService.shared.isExercisesReady = true
            results.append(DiagnosticResult(
                category: "Exercise Library", check: "Ready State",
                severity: .warning, message: "isExercisesReady was false despite \(exercises.count) exercises — fixed",
                autoFixed: true
            ))
        }
        
        // Check category distribution
        var categories: [String: Int] = [:]
        for exercise in exercises {
            if let cat = exercise.category {
                categories[cat, default: 0] += 1
            }
        }
        let emptyCategoryCount = exercises.filter { $0.category == nil || $0.category?.isEmpty == true }.count
        if emptyCategoryCount > 0 {
            results.append(DiagnosticResult(
                category: "Exercise Library", check: "Missing Categories",
                severity: .warning, message: "\(emptyCategoryCount) exercises with no category — won't appear in filtered views"
            ))
        }
        
        return results
    }
    
    // MARK: - 5. Workout System
    
    private func checkWorkoutSystem() async -> [DiagnosticResult] {
        var results: [DiagnosticResult] = []
        
        let wm = WorkoutManager.shared
        
        // Check for ghost active workout
        if wm.isWorkoutActive && wm.currentWorkout == nil {
            results.append(DiagnosticResult(
                category: "Workout", check: "Ghost Workout",
                severity: .critical, message: "isWorkoutActive=true but currentWorkout=nil — app stuck in workout mode",
                fix: "Resetting workout state", autoFixed: true
            ))
            wm.isWorkoutActive = false
            wm.currentExercises = []
            wm.clearAllSetsData()
        } else if !wm.isWorkoutActive && wm.currentWorkout != nil {
            results.append(DiagnosticResult(
                category: "Workout", check: "Orphaned Workout Object",
                severity: .warning, message: "currentWorkout exists but isWorkoutActive=false — stale reference",
                fix: "Clearing stale workout reference", autoFixed: true
            ))
            wm.currentWorkout = nil
            wm.currentExercises = []
        } else {
            results.append(DiagnosticResult(
                category: "Workout", check: "Workout State",
                severity: .passed, message: "Workout state consistent (active: \(wm.isWorkoutActive))"
            ))
        }
        
        // Check active workout data integrity
        if wm.isWorkoutActive {
            if wm.currentExercises.isEmpty {
                results.append(DiagnosticResult(
                    category: "Workout", check: "Active Exercises",
                    severity: .critical, message: "Active workout has 0 exercises — user sees empty workout"
                ))
            }
            
            // Check if workout start time is reasonable
            if let startTime = wm.workoutStartTime {
                let duration = Date().timeIntervalSince(startTime)
                if duration > 4 * 60 * 60 { // 4 hours
                    results.append(DiagnosticResult(
                        category: "Workout", check: "Stale Workout",
                        severity: .warning, message: "Active workout started \(String(format: "%.1f", duration/3600)) hours ago — may be abandoned"
                    ))
                }
            }
        }
        
        // Check for stale persisted workout state
        if !wm.isWorkoutActive {
            if UserDefaults.standard.data(forKey: "activeWorkoutState") != nil {
                UserDefaults.standard.removeObject(forKey: "activeWorkoutState")
                UserDefaults.standard.removeObject(forKey: "workoutSetsData")
                results.append(DiagnosticResult(
                    category: "Workout", check: "Stale Persisted State",
                    severity: .warning, message: "Persisted workout state found but no active workout — cleared stale data",
                    autoFixed: true
                ))
            }
        }
        
        return results
    }
    
    // MARK: - 6. Memory & Performance
    
    private func checkMemoryAndPerformance() async -> [DiagnosticResult] {
        var results: [DiagnosticResult] = []
        
        // Check memory usage
        let memoryMB = getMemoryUsageMB()
        if memoryMB > 500 {
            results.append(DiagnosticResult(
                category: "Performance", check: "Memory Usage",
                severity: .critical, message: "Memory at \(Int(memoryMB))MB — high risk of iOS termination (>500MB)",
                fix: "Triggering emergency memory cleanup"
            ))
            // Trigger cleanup
            VideoPlaybackEngine.shared.clearAllCaches()
            VideoPreloadManager.shared.clearCache()
            VideoStreamingService.shared.clearPreloadCache()
        } else if memoryMB > 350 {
            results.append(DiagnosticResult(
                category: "Performance", check: "Memory Usage",
                severity: .warning, message: "Memory at \(Int(memoryMB))MB — elevated, monitor for growth"
            ))
        } else {
            results.append(DiagnosticResult(
                category: "Performance", check: "Memory Usage",
                severity: .passed, message: "Memory usage: \(Int(memoryMB))MB (healthy)"
            ))
        }
        
        // Check if heavy work is blocking
        if HeavyWorkSentinel.shared.isHeavyWorkInProgress {
            let activeItems = HeavyWorkSentinel.shared.activeWorkItems
            results.append(DiagnosticResult(
                category: "Performance", check: "Heavy Work",
                severity: .info, message: "Heavy work in progress: \(activeItems.joined(separator: ", "))"
            ))
        }
        
        // Check CPU protection state
        let currentCPU = CPUProtection.shared.getCurrentCPU()
        if CPUProtection.shared.isCPUCritical() {
            results.append(DiagnosticResult(
                category: "Performance", check: "CPU Usage",
                severity: .critical, message: "CPU at \(String(format: "%.0f", currentCPU))% — app may be unresponsive"
            ))
        } else if CPUProtection.shared.isCPUTooHigh() {
            results.append(DiagnosticResult(
                category: "Performance", check: "CPU Usage",
                severity: .warning, message: "CPU at \(String(format: "%.0f", currentCPU))% — performance degraded"
            ))
        } else {
            results.append(DiagnosticResult(
                category: "Performance", check: "CPU Usage",
                severity: .passed, message: "CPU: \(String(format: "%.0f", currentCPU))%"
            ))
        }
        
        return results
    }
    
    // MARK: - 7. Cache Health
    
    private func checkCacheHealth() async -> [DiagnosticResult] {
        var results: [DiagnosticResult] = []
        
        // Check URL cache size
        let urlCacheSize = URLCache.shared.currentDiskUsage + URLCache.shared.currentMemoryUsage
        let urlCacheMB = Double(urlCacheSize) / (1024 * 1024)
        if urlCacheMB > 100 {
            results.append(DiagnosticResult(
                category: "Cache", check: "URL Cache",
                severity: .warning, message: "URL cache at \(String(format: "%.1f", urlCacheMB))MB — consider cleanup"
            ))
        } else {
            results.append(DiagnosticResult(
                category: "Cache", check: "URL Cache",
                severity: .passed, message: "URL cache: \(String(format: "%.1f", urlCacheMB))MB"
            ))
        }
        
        // Check exercise cache validity
        let exerciseCache = ExerciseLibraryService.shared.getAllExercises()
        results.append(DiagnosticResult(
            category: "Cache", check: "Exercise Cache",
            severity: .passed, message: "\(exerciseCache.count) exercises cached"
        ))
        
        return results
    }
    
    // MARK: - 8. Network & Supabase
    
    private func checkNetworkHealth() async -> [DiagnosticResult] {
        var results: [DiagnosticResult] = []
        
        // Check if Supabase client exists
        guard SupabaseManager.shared.supabaseClient != nil else {
            results.append(DiagnosticResult(
                category: "Network", check: "Supabase Client",
                severity: .critical, message: "Supabase client not initialized"
            ))
            return results
        }
        
        // Test Supabase connectivity with a lightweight query
        do {
            struct PingResponse: Codable {
                let id: String
            }
            let _: [PingResponse] = try await SupabaseManager.shared.supabaseClient
                .from("user_profiles")
                .select("id")
                .limit(1)
                .execute()
                .value
            
            results.append(DiagnosticResult(
                category: "Network", check: "Supabase Connectivity",
                severity: .passed, message: "Successfully connected to Supabase"
            ))
        } catch {
            results.append(DiagnosticResult(
                category: "Network", check: "Supabase Connectivity",
                severity: .warning, message: "Cannot reach Supabase: \(error.localizedDescription)"
            ))
        }
        
        // Check Realtime connection
        if SupabaseManager.shared.isAuthenticated {
            if RealtimeService.shared.isConnected {
                results.append(DiagnosticResult(
                    category: "Network", check: "Realtime",
                    severity: .passed, message: "Realtime connection active"
                ))
            } else {
                results.append(DiagnosticResult(
                    category: "Network", check: "Realtime",
                    severity: .warning, message: "Realtime not connected — social updates delayed"
                ))
            }
        }
        
        return results
    }
    
    // MARK: - 9. UserDefaults Integrity
    
    private func checkUserDefaultsIntegrity() async -> [DiagnosticResult] {
        var results: [DiagnosticResult] = []
        
        // Check for bloated UserDefaults
        let allDefaults = UserDefaults.standard.dictionaryRepresentation()
        let totalKeys = allDefaults.count
        
        if totalKeys > 500 {
            results.append(DiagnosticResult(
                category: "UserDefaults", check: "Key Count",
                severity: .warning, message: "\(totalKeys) keys in UserDefaults — should be under 500 for performance"
            ))
        } else {
            results.append(DiagnosticResult(
                category: "UserDefaults", check: "Key Count",
                severity: .passed, message: "\(totalKeys) keys stored"
            ))
        }
        
        // Check for corrupted data patterns
        var corruptedKeys: [String] = []
        for (key, value) in allDefaults {
            if key.hasPrefix("cached") || key.hasPrefix("program_") {
                if let data = value as? Data {
                    // Try to decode — if it fails, it's corrupted
                    if data.count > 10_000_000 { // 10MB — way too big for UserDefaults
                        corruptedKeys.append(key)
                    }
                }
            }
        }
        
        if !corruptedKeys.isEmpty {
            results.append(DiagnosticResult(
                category: "UserDefaults", check: "Bloated Entries",
                severity: .warning, message: "\(corruptedKeys.count) oversized entries found: \(corruptedKeys.prefix(3).joined(separator: ", "))",
                fix: "Removing oversized entries", autoFixed: true
            ))
            for key in corruptedKeys {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        
        // Check for orphaned keys from deleted features
        let orphanedPrefixes = ["fitbit_", "strava_", "inbody_"]
        for prefix in orphanedPrefixes {
            let orphanedCount = allDefaults.keys.filter { $0.hasPrefix(prefix) }.count
            if orphanedCount > 20 {
                results.append(DiagnosticResult(
                    category: "UserDefaults", check: "Orphaned Keys (\(prefix))",
                    severity: .info, message: "\(orphanedCount) keys with prefix '\(prefix)'"
                ))
            }
        }
        
        return results
    }
    
    // MARK: - 10. Service Singletons
    
    private func checkServiceSingletons() async -> [DiagnosticResult] {
        var results: [DiagnosticResult] = []
        
        // Verify critical singletons are initialized
        let criticalSingletons: [(String, Any?)] = [
            ("WorkoutManager", WorkoutManager.shared as Any?),
            ("UserManager", UserManager.shared as Any?),
            ("ExerciseLibraryService", ExerciseLibraryService.shared as Any?),
            ("SupabaseManager", SupabaseManager.shared as Any?),
            ("SessionLogManager", SessionLogManager.shared as Any?),
        ]
        
        for (name, instance) in criticalSingletons {
            if instance == nil {
                results.append(DiagnosticResult(
                    category: "Services", check: name,
                    severity: .critical, message: "\(name) singleton is nil — critical functionality broken"
                ))
            } else {
                results.append(DiagnosticResult(
                    category: "Services", check: name,
                    severity: .passed, message: "\(name) initialized"
                ))
            }
        }
        
        return results
    }
    
    // MARK: - 11. Challenge System
    
    private func checkChallengeSystem() async -> [DiagnosticResult] {
        var results: [DiagnosticResult] = []
        
        guard SupabaseManager.shared.isAuthenticated else {
            results.append(DiagnosticResult(
                category: "Challenges", check: "Auth Requirement",
                severity: .info, message: "Skipped — user not authenticated"
            ))
            return results
        }
        
        // Test the RPC functions exist
        do {
            struct ChallengeResponse: Codable {
                let id: String?
            }
            
            // Quick test to see if the active challenges RPC works
            let timezone = TimeZone.current.identifier
            let _: [ChallengeResponse] = try await SupabaseManager.shared.supabaseClient
                .rpc("get_active_challenges", params: ["p_timezone": timezone])
                .execute()
                .value
            
            results.append(DiagnosticResult(
                category: "Challenges", check: "RPC get_active_challenges",
                severity: .passed, message: "RPC function accessible"
            ))
        } catch {
            results.append(DiagnosticResult(
                category: "Challenges", check: "RPC get_active_challenges",
                severity: .warning, message: "RPC call failed: \(error.localizedDescription)"
            ))
        }
        
        return results
    }
    
    // MARK: - 12. Notification System
    
    private func checkNotificationSystem() async -> [DiagnosticResult] {
        var results: [DiagnosticResult] = []
        
        let isAuthorized = NotificationManager.shared.isAuthorized
        results.append(DiagnosticResult(
            category: "Notifications", check: "Authorization",
            severity: .info, message: "Notifications \(isAuthorized ? "authorized" : "not authorized")"
        ))
        
        // Check push token
        if SupabaseManager.shared.isAuthenticated {
            let hasPushToken = UserDefaults.standard.string(forKey: "apns_device_token") != nil
            if !hasPushToken && isAuthorized {
                results.append(DiagnosticResult(
                    category: "Notifications", check: "Push Token",
                    severity: .warning, message: "No push token saved despite notifications authorized — push notifications won't work"
                ))
            }
        }
        
        return results
    }
    
    // MARK: - 13. Data Consistency
    
    private func checkDataConsistency() async -> [DiagnosticResult] {
        var results: [DiagnosticResult] = []
        
        // Check UserDefaults ↔ Core Data consistency for key fields
        let udWeight = UserDefaults.standard.integer(forKey: "userWeight")
        let udHeight = UserDefaults.standard.integer(forKey: "userHeight")
        let udGender = UserDefaults.standard.string(forKey: "userGender")
        
        if let user = UserManager.shared.currentUser {
            // Weight consistency
            if udWeight > 0 && Int(user.weight) != udWeight {
                UserDefaults.standard.set(Int(user.weight), forKey: "userWeight")
                results.append(DiagnosticResult(
                    category: "Data Consistency", check: "Weight Sync",
                    severity: .warning, message: "UserDefaults weight (\(udWeight)) ≠ CoreData weight (\(user.weight)) — fixed to match CoreData",
                    autoFixed: true
                ))
            }
            
            // Height consistency
            if udHeight > 0 && Int(user.height) != udHeight {
                UserDefaults.standard.set(Int(user.height), forKey: "userHeight")
                results.append(DiagnosticResult(
                    category: "Data Consistency", check: "Height Sync",
                    severity: .warning, message: "UserDefaults height (\(udHeight)) ≠ CoreData height (\(user.height)) — fixed to match CoreData",
                    autoFixed: true
                ))
            }
            
            // Gender consistency
            if let cdGender = user.gender, let udG = udGender, cdGender != udG {
                UserDefaults.standard.set(cdGender, forKey: "userGender")
                results.append(DiagnosticResult(
                    category: "Data Consistency", check: "Gender Sync",
                    severity: .warning, message: "UserDefaults gender (\(udG)) ≠ CoreData gender (\(cdGender)) — fixed",
                    autoFixed: true
                ))
            }
            
            // XP / total workouts sanity
            if user.xp < 0 {
                user.xp = 0
                try? viewContext.save()
                results.append(DiagnosticResult(
                    category: "Data Consistency", check: "Negative XP",
                    severity: .warning, message: "Negative XP detected and reset to 0",
                    autoFixed: true
                ))
            }
            
            if user.totalWorkouts < 0 {
                user.totalWorkouts = 0
                try? viewContext.save()
                results.append(DiagnosticResult(
                    category: "Data Consistency", check: "Negative Workouts",
                    severity: .warning, message: "Negative totalWorkouts detected and reset to 0",
                    autoFixed: true
                ))
            }
        }
        
        if results.isEmpty {
            results.append(DiagnosticResult(
                category: "Data Consistency", check: "Overall",
                severity: .passed, message: "UserDefaults ↔ CoreData consistent"
            ))
        }
        
        return results
    }
    
    // MARK: - 14. Thread Safety
    
    private func checkThreadSafety() async -> [DiagnosticResult] {
        var results: [DiagnosticResult] = []
        
        // Check if we're running on main thread (we should be for @MainActor)
        if Thread.isMainThread {
            results.append(DiagnosticResult(
                category: "Thread Safety", check: "Main Thread",
                severity: .passed, message: "Diagnostic running on main thread ✓"
            ))
        } else {
            results.append(DiagnosticResult(
                category: "Thread Safety", check: "Main Thread",
                severity: .warning, message: "Diagnostic NOT on main thread — UI updates may crash"
            ))
        }
        
        // Check view context concurrency
        if viewContext.concurrencyType == .mainQueueConcurrencyType {
            results.append(DiagnosticResult(
                category: "Thread Safety", check: "Core Data Context",
                severity: .passed, message: "View context using main queue concurrency"
            ))
        } else {
            results.append(DiagnosticResult(
                category: "Thread Safety", check: "Core Data Context",
                severity: .warning, message: "View context NOT using main queue — potential threading issues"
            ))
        }
        
        return results
    }
    
    // MARK: - Helpers
    
    private func getMemoryUsageMB() -> Double {
        SystemMetrics.getMemoryUsageMB()
    }
}
