//
//  ExerciseHistoryService.swift
//  BuiltSimple
//
//  Service for tracking exercise performance history, PRs, and metrics
//

import Foundation
import Supabase

// MARK: - Data Models

struct ExercisePerformanceHistory: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let exerciseName: String
    let exerciseCategory: String?
    let workoutId: UUID?
    let workoutDate: Date
    let totalSets: Int
    let totalReps: Int
    let totalVolume: Double
    let maxWeight: Double
    let maxReps: Int
    let avgWeight: Double?
    let avgReps: Double?
    let workoutDurationSeconds: Int?
    let restTimeTotalSeconds: Int?
    let hadFailureSet: Bool
    let hadDropset: Bool
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case exerciseName = "exercise_name"
        case exerciseCategory = "exercise_category"
        case workoutId = "workout_id"
        case workoutDate = "workout_date"
        case totalSets = "total_sets"
        case totalReps = "total_reps"
        case totalVolume = "total_volume"
        case maxWeight = "max_weight"
        case maxReps = "max_reps"
        case avgWeight = "avg_weight"
        case avgReps = "avg_reps"
        case workoutDurationSeconds = "workout_duration_seconds"
        case restTimeTotalSeconds = "rest_time_total_seconds"
        case hadFailureSet = "had_failure_set"
        case hadDropset = "had_dropset"
    }
}

struct ExerciseSetHistory: Codable, Identifiable {
    let id: UUID
    let performanceId: UUID
    let userId: UUID
    let exerciseName: String
    let setNumber: Int
    let weight: Double
    let reps: Int
    let isCompleted: Bool
    let isFailure: Bool
    let isDropset: Bool
    let restTimeSeconds: Int
    
    enum CodingKeys: String, CodingKey {
        case id
        case performanceId = "performance_id"
        case userId = "user_id"
        case exerciseName = "exercise_name"
        case setNumber = "set_number"
        case weight
        case reps
        case isCompleted = "is_completed"
        case isFailure = "is_failure"
        case isDropset = "is_dropset"
        case restTimeSeconds = "rest_time_seconds"
    }
}

struct ExercisePersonalRecord: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let exerciseName: String
    
    // PRs
    var maxWeight: Double
    var maxWeightDate: Date?
    var maxReps: Int
    var maxRepsDate: Date?
    var maxVolumeSingleSet: Double
    var maxVolumeSingleSetDate: Date?
    var maxVolumeSession: Double
    var maxVolumeSessionDate: Date?
    var maxSetsSession: Int
    var maxSetsSessionDate: Date?
    
    // Estimated 1RM
    var estimated1rm: Double
    var estimated1rmDate: Date?
    var estimated1rmWeight: Double?
    var estimated1rmReps: Int?
    
    // Lifetime stats
    var totalTimesPerformed: Int
    var totalSetsEver: Int
    var totalRepsEver: Int
    var totalVolumeEver: Double
    var firstPerformedDate: Date?
    var lastPerformedDate: Date?
    
    // Streaks
    var currentStreak: Int
    var longestStreak: Int
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case exerciseName = "exercise_name"
        case maxWeight = "max_weight"
        case maxWeightDate = "max_weight_date"
        case maxReps = "max_reps"
        case maxRepsDate = "max_reps_date"
        case maxVolumeSingleSet = "max_volume_single_set"
        case maxVolumeSingleSetDate = "max_volume_single_set_date"
        case maxVolumeSession = "max_volume_session"
        case maxVolumeSessionDate = "max_volume_session_date"
        case maxSetsSession = "max_sets_session"
        case maxSetsSessionDate = "max_sets_session_date"
        case estimated1rm = "estimated_1rm"
        case estimated1rmDate = "estimated_1rm_date"
        case estimated1rmWeight = "estimated_1rm_weight"
        case estimated1rmReps = "estimated_1rm_reps"
        case totalTimesPerformed = "total_times_performed"
        case totalSetsEver = "total_sets_ever"
        case totalRepsEver = "total_reps_ever"
        case totalVolumeEver = "total_volume_ever"
        case firstPerformedDate = "first_performed_date"
        case lastPerformedDate = "last_performed_date"
        case currentStreak = "current_streak"
        case longestStreak = "longest_streak"
    }
}

// Simple struct for previous set display
struct PreviousSetInfo: Codable {
    let setNumber: Int
    let weight: Double
    let reps: Int
    var isFailure: Bool = false
    var isDropset: Bool = false
    
    enum CodingKeys: String, CodingKey {
        case setNumber = "set_number"
        case weight
        case reps
        case isFailure = "is_failure"
        case isDropset = "is_dropset"
    }
    
    // Custom decoder to handle missing fields
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        setNumber = try container.decode(Int.self, forKey: .setNumber)
        weight = try container.decode(Double.self, forKey: .weight)
        reps = try container.decode(Int.self, forKey: .reps)
        isFailure = try container.decodeIfPresent(Bool.self, forKey: .isFailure) ?? false
        isDropset = try container.decodeIfPresent(Bool.self, forKey: .isDropset) ?? false
    }
    
    // Manual initializer for creating instances in code
    init(setNumber: Int, weight: Double, reps: Int, isFailure: Bool = false, isDropset: Bool = false) {
        self.setNumber = setNumber
        self.weight = weight
        self.reps = reps
        self.isFailure = isFailure
        self.isDropset = isDropset
    }
    
    var displayString: String {
        if weight > 0 && reps > 0 {
            // Preserve decimals when needed (e.g., 180.5 → "180.5", 180.0 → "180")
            let weightStr = weight.truncatingRemainder(dividingBy: 1) == 0 
                ? "\(Int(weight))" 
                : String(format: "%.1f", weight)
            return "\(weightStr)×\(reps)"
        }
        return "-"
    }
}

// MARK: - Service

class ExerciseHistoryService: ObservableObject {
    static let shared = ExerciseHistoryService()
    
    private var supabase: SupabaseClient {
        SupabaseManager.shared.supabaseClient
    }
    
    @Published var previousSetsCache: [String: [PreviousSetInfo]] = [:]
    @Published var personalRecordsCache: [String: ExercisePersonalRecord] = [:]
    
    private init() {}
    
    // MARK: - Fetch Previous Sets
    
    /// Fetch the previous workout's sets for a specific exercise
    func fetchPreviousSets(for exerciseName: String) async -> [PreviousSetInfo] {
        // Check cache first - INSTANT return if cached
        if let cached = previousSetsCache[exerciseName] {
            #if DEBUG
            print("⚡ [ExerciseHistory] CACHE HIT for '\(exerciseName)' (\(cached.count) sets)")
            #endif
            return cached
        }
        
        guard let userId = SupabaseManager.shared.currentUser?.id else {
            print("⚠️ [ExerciseHistory] No authenticated user")
            return []
        }
        
        #if DEBUG
        let startTime = CFAbsoluteTimeGetCurrent()
        print("🔍 [ExerciseHistory] Fetching previous sets for '\(exerciseName)' user: \(userId.uuidString)")
        #endif
        
        do {
            // Query exercise_performance_history first to get the most recent workout for this exercise
            // This table has workout_date which we can sort by
            struct PerformanceRow: Decodable {
                let id: String
                let workout_date: String?
            }
            
            print("🔍 [ExerciseHistory] Querying exercise_performance_history for '\(exerciseName)'...")
            
            let recentPerformance: [PerformanceRow] = try await supabase
                .from("exercise_performance_history")
                .select("id, workout_date")
                .eq("user_id", value: userId.uuidString)
                .eq("exercise_name", value: exerciseName)
                .order("workout_date", ascending: false)
                .limit(1)
                .execute()
                .value
            
            guard let performanceId = recentPerformance.first?.id else {
                print("📭 [ExerciseHistory] No previous performance found for '\(exerciseName)'")
                // Cache empty result to avoid repeated lookups
                await MainActor.run {
                    self.previousSetsCache[exerciseName] = []
                }
                return []
            }
            
            print("🔍 [ExerciseHistory] Found performance_id: \(performanceId), fetching sets...")
            
            // Now get all sets from that workout
            struct SetHistoryRow: Decodable {
                let set_number: Int
                let weight: Double
                let reps: Int
            }
            
            let setRows: [SetHistoryRow] = try await supabase
                .from("exercise_set_history")
                .select("set_number, weight, reps")
                .eq("performance_id", value: performanceId)
                .order("set_number", ascending: true)
                .execute()
                .value
            
            print("🔍 [ExerciseHistory] Found \(setRows.count) set rows for performance_id: \(performanceId)")
            
            let response = setRows.map { row in
                PreviousSetInfo(
                    setNumber: row.set_number,
                    weight: row.weight,
                    reps: row.reps
                )
            }
            
            // Cache the result
            await MainActor.run {
                self.previousSetsCache[exerciseName] = response
            }
            
            #if DEBUG
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            print("✅ [ExerciseHistory] Found \(response.count) previous sets for '\(exerciseName)' in \(String(format: "%.0f", elapsed))ms")
            for set in response {
                print("   Set \(set.setNumber): \(Int(set.weight))lbs × \(set.reps) reps")
            }
            #endif
            return response
            
        } catch {
            print("❌ [ExerciseHistory] Error fetching previous sets for '\(exerciseName)': \(error)")
            print("❌ [ExerciseHistory] Full error details: \(String(describing: error))")
            return []
        }
    }
    
    /// Fetch previous sets for multiple exercises at once (batch load)
    func fetchPreviousSetsForExercises(_ exerciseNames: [String]) async -> [String: [PreviousSetInfo]] {
        #if DEBUG
        let startTime = CFAbsoluteTimeGetCurrent()
        var cacheHits = 0
        var networkFetches = 0
        #endif
        
        var results: [String: [PreviousSetInfo]] = [:]
        var namesToFetch: [String] = []
        
        // First, collect cached results and identify what needs network fetch
        for name in exerciseNames {
            if let cached = previousSetsCache[name] {
                results[name] = cached
                #if DEBUG
                cacheHits += 1
                #endif
            } else {
                namesToFetch.append(name)
            }
        }
        
        #if DEBUG
        print("📦 [ExerciseHistory] Batch: \(cacheHits) cache hits, \(namesToFetch.count) need fetch")
        #endif
        
        // Fetch remaining in parallel (only if needed)
        if !namesToFetch.isEmpty {
            await withTaskGroup(of: (String, [PreviousSetInfo]).self) { group in
                for name in namesToFetch {
                    group.addTask {
                        let sets = await self.fetchPreviousSets(for: name)
                        return (name, sets)
                    }
                }
                
                for await (name, sets) in group {
                    results[name] = sets
                    #if DEBUG
                    networkFetches += 1
                    #endif
                }
            }
        }
        
        #if DEBUG
        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        print("📦 [ExerciseHistory] Batch complete: \(results.count) exercises in \(String(format: "%.0f", elapsed))ms")
        #endif
        
        return results
    }
    
    // MARK: - Save Exercise Performance
    
    /// Save exercise performance after a workout is completed
    func saveExercisePerformance(
        exerciseName: String,
        exerciseCategory: String?,
        workoutId: UUID?,
        sets: [WorkoutSetData],
        workoutDurationSeconds: Int? = nil
    ) async throws {
        print("💾 [ExerciseHistory] saveExercisePerformance called for '\(exerciseName)'")
        print("💾 [ExerciseHistory] Input sets count: \(sets.count)")
        
        guard let userId = SupabaseManager.shared.currentUser?.id else {
            print("❌ [ExerciseHistory] No authenticated user - cannot save")
            throw ExerciseHistoryError.notAuthenticated
        }
        
        print("💾 [ExerciseHistory] User ID: \(userId.uuidString)")
        
        // Filter to only completed sets with actual data
        let completedSets = sets.filter { $0.isCompleted && ($0.weight > 0 || $0.reps > 0) }
        
        print("💾 [ExerciseHistory] Completed sets with data: \(completedSets.count)")
        
        guard !completedSets.isEmpty else {
            print("⚠️ [ExerciseHistory] No completed sets to save for '\(exerciseName)'")
            return
        }
        
        // Calculate aggregate metrics
        let totalSets = completedSets.count
        let totalReps = completedSets.reduce(0) { $0 + $1.reps }
        let totalVolume = completedSets.reduce(0.0) { $0 + ($1.weight * Double($1.reps)) }
        let maxWeight = completedSets.map { $0.weight }.max() ?? 0
        let maxReps = completedSets.map { $0.reps }.max() ?? 0
        let avgWeight = completedSets.isEmpty ? 0 : completedSets.reduce(0.0) { $0 + $1.weight } / Double(completedSets.count)
        let avgReps = completedSets.isEmpty ? 0 : Double(totalReps) / Double(completedSets.count)
        let totalRestTime = Int(completedSets.reduce(0.0) { $0 + $1.restTime })
        let hadFailure = completedSets.contains { $0.isFailure }
        let hadDropset = completedSets.contains { $0.isDropset }
        
        // Create performance record
        let performanceId = UUID()
        let performanceData: [String: AnyJSON] = [
            "id": .string(performanceId.uuidString),
            "user_id": .string(userId.uuidString),
            "exercise_name": .string(exerciseName),
            "exercise_category": exerciseCategory.map { .string($0) } ?? .null,
            "workout_id": workoutId.map { .string($0.uuidString) } ?? .null,
            "workout_date": .string(ISO8601DateFormatter().string(from: Date())),
            "total_sets": .integer(totalSets),
            "total_reps": .integer(totalReps),
            "total_volume": .double(totalVolume),
            "max_weight": .double(maxWeight),
            "max_reps": .integer(maxReps),
            "avg_weight": .double(avgWeight),
            "avg_reps": .double(avgReps),
            "workout_duration_seconds": workoutDurationSeconds.map { .integer($0) } ?? .null,
            "rest_time_total_seconds": .integer(totalRestTime),
            "had_failure_set": .bool(hadFailure),
            "had_dropset": .bool(hadDropset)
        ]
        
        // Insert performance record
        print("💾 [ExerciseHistory] Inserting into exercise_performance_history...")
        do {
            try await supabase
                .from("exercise_performance_history")
                .insert(performanceData)
                .execute()
            print("✅ [ExerciseHistory] Saved performance for '\(exerciseName)' - \(totalSets) sets, \(totalReps) reps, \(Int(totalVolume)) volume")
        } catch {
            print("❌ [ExerciseHistory] FAILED to insert performance: \(error)")
            throw error
        }
        
        // Insert individual set records
        print("💾 [ExerciseHistory] Inserting \(completedSets.count) sets into exercise_set_history...")
        for (index, set) in completedSets.enumerated() {
            let setData: [String: AnyJSON] = [
                "performance_id": .string(performanceId.uuidString),
                "user_id": .string(userId.uuidString),
                "exercise_name": .string(exerciseName),
                "set_number": .integer(index + 1),
                "weight": .double(set.weight),
                "reps": .integer(set.reps),
                "is_completed": .bool(true),
                "is_failure": .bool(set.isFailure),
                "is_dropset": .bool(set.isDropset),
                "rest_time_seconds": .integer(Int(set.restTime))
            ]
            
            do {
                try await supabase
                    .from("exercise_set_history")
                    .insert(setData)
                    .execute()
                print("   ✅ Set \(index + 1) saved")
            } catch {
                print("   ❌ Set \(index + 1) FAILED: \(error)")
                throw error
            }
        }
        
        print("✅ [ExerciseHistory] Saved \(completedSets.count) set records for '\(exerciseName)'")
        
        // Update personal records
        try await updatePersonalRecords(
            exerciseName: exerciseName,
            userId: userId,
            sets: completedSets,
            totalSets: totalSets,
            totalReps: totalReps,
            totalVolume: totalVolume,
            maxWeight: maxWeight,
            maxReps: maxReps
        )
        
        // Clear cache for this exercise so next fetch gets fresh data
        await MainActor.run {
            self.previousSetsCache.removeValue(forKey: exerciseName)
        }
    }
    
    // MARK: - Update Personal Records
    
    private func updatePersonalRecords(
        exerciseName: String,
        userId: UUID,
        sets: [WorkoutSetData],
        totalSets: Int,
        totalReps: Int,
        totalVolume: Double,
        maxWeight: Double,
        maxReps: Int
    ) async throws {
        let now = Date()
        let isoNow = ISO8601DateFormatter().string(from: now)
        
        // Calculate max volume for a single set
        let maxVolumeSingleSet = sets.map { $0.weight * Double($0.reps) }.max() ?? 0
        
        // Calculate estimated 1RM using Epley formula
        // 1RM = weight × (1 + reps/30)
        var best1rm: Double = 0
        var best1rmWeight: Double = 0
        var best1rmReps: Int = 0
        
        for set in sets where set.weight > 0 && set.reps > 0 {
            let estimated = set.weight * (1 + Double(set.reps) / 30.0)
            if estimated > best1rm {
                best1rm = estimated
                best1rmWeight = set.weight
                best1rmReps = set.reps
            }
        }
        
        // Try to get existing PR record
        let existingRecords: [ExercisePersonalRecord] = try await supabase
            .from("exercise_personal_records")
            .select()
            .eq("user_id", value: userId.uuidString)
            .eq("exercise_name", value: exerciseName)
            .execute()
            .value
        
        if let existing = existingRecords.first {
            // Update existing record
            var updates: [String: AnyJSON] = [
                "total_times_performed": .integer(existing.totalTimesPerformed + 1),
                "total_sets_ever": .integer(existing.totalSetsEver + totalSets),
                "total_reps_ever": .integer(existing.totalRepsEver + totalReps),
                "total_volume_ever": .double(existing.totalVolumeEver + totalVolume),
                "last_performed_date": .string(isoNow),
                "updated_at": .string(isoNow)
            ]
            
            // Check for new PRs
            if maxWeight > existing.maxWeight {
                updates["max_weight"] = .double(maxWeight)
                updates["max_weight_date"] = .string(isoNow)
                print("🏆 [ExerciseHistory] NEW PR! Max weight for '\(exerciseName)': \(Int(maxWeight)) lbs")
            }
            
            if maxReps > existing.maxReps {
                updates["max_reps"] = .integer(maxReps)
                updates["max_reps_date"] = .string(isoNow)
                print("🏆 [ExerciseHistory] NEW PR! Max reps for '\(exerciseName)': \(maxReps)")
            }
            
            if maxVolumeSingleSet > existing.maxVolumeSingleSet {
                updates["max_volume_single_set"] = .double(maxVolumeSingleSet)
                updates["max_volume_single_set_date"] = .string(isoNow)
                print("🏆 [ExerciseHistory] NEW PR! Max volume single set for '\(exerciseName)': \(Int(maxVolumeSingleSet))")
            }
            
            if totalVolume > existing.maxVolumeSession {
                updates["max_volume_session"] = .double(totalVolume)
                updates["max_volume_session_date"] = .string(isoNow)
                print("🏆 [ExerciseHistory] NEW PR! Max volume session for '\(exerciseName)': \(Int(totalVolume))")
            }
            
            if totalSets > existing.maxSetsSession {
                updates["max_sets_session"] = .integer(totalSets)
                updates["max_sets_session_date"] = .string(isoNow)
            }
            
            if best1rm > existing.estimated1rm {
                updates["estimated_1rm"] = .double(best1rm)
                updates["estimated_1rm_date"] = .string(isoNow)
                updates["estimated_1rm_weight"] = .double(best1rmWeight)
                updates["estimated_1rm_reps"] = .integer(best1rmReps)
                print("🏆 [ExerciseHistory] NEW PR! Estimated 1RM for '\(exerciseName)': \(Int(best1rm)) lbs")
            }
            
            try await supabase
                .from("exercise_personal_records")
                .update(updates)
                .eq("id", value: existing.id.uuidString)
                .execute()
            
        } else {
            // Create new PR record
            let newRecord: [String: AnyJSON] = [
                "user_id": .string(userId.uuidString),
                "exercise_name": .string(exerciseName),
                "max_weight": .double(maxWeight),
                "max_weight_date": .string(isoNow),
                "max_reps": .integer(maxReps),
                "max_reps_date": .string(isoNow),
                "max_volume_single_set": .double(maxVolumeSingleSet),
                "max_volume_single_set_date": .string(isoNow),
                "max_volume_session": .double(totalVolume),
                "max_volume_session_date": .string(isoNow),
                "max_sets_session": .integer(totalSets),
                "max_sets_session_date": .string(isoNow),
                "estimated_1rm": .double(best1rm),
                "estimated_1rm_date": .string(isoNow),
                "estimated_1rm_weight": .double(best1rmWeight),
                "estimated_1rm_reps": .integer(best1rmReps),
                "total_times_performed": .integer(1),
                "total_sets_ever": .integer(totalSets),
                "total_reps_ever": .integer(totalReps),
                "total_volume_ever": .double(totalVolume),
                "first_performed_date": .string(isoNow),
                "last_performed_date": .string(isoNow),
                "current_streak": .integer(1),
                "longest_streak": .integer(1)
            ]
            
            try await supabase
                .from("exercise_personal_records")
                .insert(newRecord)
                .execute()
            
            print("✅ [ExerciseHistory] Created new PR record for '\(exerciseName)'")
        }
    }
    
    // MARK: - Fetch Personal Records
    
    func fetchPersonalRecord(for exerciseName: String) async -> ExercisePersonalRecord? {
        // Check cache first
        if let cached = personalRecordsCache[exerciseName] {
            return cached
        }
        
        guard let userId = SupabaseManager.shared.currentUser?.id else {
            return nil
        }
        
        do {
            let records: [ExercisePersonalRecord] = try await supabase
                .from("exercise_personal_records")
                .select()
                .eq("user_id", value: userId.uuidString)
                .eq("exercise_name", value: exerciseName)
                .execute()
                .value
            
            if let record = records.first {
                await MainActor.run {
                    self.personalRecordsCache[exerciseName] = record
                }
                return record
            }
            
        } catch {
            print("❌ [ExerciseHistory] Error fetching PR: \(error)")
        }
        
        return nil
    }
    
    /// Fetch all personal records for a user
    func fetchAllPersonalRecords() async -> [ExercisePersonalRecord] {
        guard let userId = SupabaseManager.shared.currentUser?.id else {
            return []
        }
        
        do {
            let records: [ExercisePersonalRecord] = try await supabase
                .from("exercise_personal_records")
                .select()
                .eq("user_id", value: userId.uuidString)
                .order("last_performed_date", ascending: false)
                .execute()
                .value
            
            // Update cache
            await MainActor.run {
                for record in records {
                    self.personalRecordsCache[record.exerciseName] = record
                }
            }
            
            return records
            
        } catch {
            print("❌ [ExerciseHistory] Error fetching all PRs: \(error)")
            return []
        }
    }
    
    // MARK: - Clear Cache
    
    func clearCache() {
        previousSetsCache.removeAll()
        personalRecordsCache.removeAll()
    }
}

// MARK: - Errors

enum ExerciseHistoryError: Error, LocalizedError {
    case notAuthenticated
    case saveFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "User must be authenticated to track exercise history"
        case .saveFailed(let reason):
            return "Failed to save exercise history: \(reason)"
        }
    }
}

