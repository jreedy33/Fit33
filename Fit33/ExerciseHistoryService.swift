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
    var isWarmup: Bool = false
    
    enum CodingKeys: String, CodingKey {
        case setNumber = "set_number"
        case weight
        case reps
        case isFailure = "is_failure"
        case isDropset = "is_dropset"
        case setType = "set_type"
    }
    
    // Custom decoder to handle missing fields
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        setNumber = try container.decode(Int.self, forKey: .setNumber)
        weight = try container.decode(Double.self, forKey: .weight)
        reps = try container.decode(Int.self, forKey: .reps)
        isFailure = try container.decodeIfPresent(Bool.self, forKey: .isFailure) ?? false
        isDropset = try container.decodeIfPresent(Bool.self, forKey: .isDropset) ?? false
        let setType = try container.decodeIfPresent(String.self, forKey: .setType) ?? "Normal"
        isWarmup = setType == "Warmup"
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(setNumber, forKey: .setNumber)
        try container.encode(weight, forKey: .weight)
        try container.encode(reps, forKey: .reps)
        try container.encode(isFailure, forKey: .isFailure)
        try container.encode(isDropset, forKey: .isDropset)
        try container.encode(isWarmup ? "Warmup" : "Normal", forKey: .setType)
    }
    
    // Manual initializer for creating instances in code
    init(setNumber: Int, weight: Double, reps: Int, isFailure: Bool = false, isDropset: Bool = false, isWarmup: Bool = false) {
        self.setNumber = setNumber
        self.weight = weight
        self.reps = reps
        self.isFailure = isFailure
        self.isDropset = isDropset
        self.isWarmup = isWarmup
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

// Condensed session summary for "last N times you did this exercise" tiles.
// Sourced from `exercise_performance_history` (one row per workout per exercise).
struct ExerciseSessionSummary: Codable, Hashable, Identifiable {
    let workoutDate: Date
    let avgWeight: Double      // lbs (matches storage unit)
    let totalSets: Int
    let totalReps: Int
    let maxWeight: Double      // lbs

    var id: Date { workoutDate }
}

// MARK: - Service

class ExerciseHistoryService: ObservableObject {
    static let shared = ExerciseHistoryService()
    
    private var supabase: SupabaseClient {
        SupabaseManager.shared.supabaseClient
    }
    
    @Published var previousSetsCache: [String: [PreviousSetInfo]] = [:]
    @Published var personalRecordsCache: [String: ExercisePersonalRecord] = [:]

    // Cache for the "last N sessions" tile row in ExerciseCard. Keyed by exercise name,
    // value is sorted desc by date. Empty arrays are cached too (avoid re-fetch on
    // first-time exercises). Cleared on `clearCache()` and after `saveExercisePerformance`.
    private var recentSessionsCache: [String: [ExerciseSessionSummary]] = [:]
    private var inFlightSessionTasks: [String: Task<[ExerciseSessionSummary], Never>] = [:]

    // ⚡️ PERF: Deduplicate concurrent batch fetches (warmup + preview fire simultaneously)
    private var inFlightBatchTask: Task<[String: [PreviousSetInfo]], Never>?
    private var inFlightBatchKey: Set<String>?

    private init() {}
    
    // MARK: - Fetch Previous Sets
    
    /// Fetch the previous workout's sets for a specific exercise
    func fetchPreviousSets(for exerciseName: String) async -> [PreviousSetInfo] {
        // Check cache first - INSTANT return if cached
        if let cached = previousSetsCache[exerciseName] {
            #if DEBUG
            AppLogger.debug("⚡ [ExerciseHistory] CACHE HIT for '\(exerciseName)' (\(cached.count) sets)", category: .workout)
            #endif
            return cached
        }
        
        guard let userId = SupabaseManager.shared.currentUser?.id else {
            AppLogger.warning("⚠️ [ExerciseHistory] No authenticated user", category: .workout)
            return []
        }
        
        #if DEBUG
        let startTime = CFAbsoluteTimeGetCurrent()
        AppLogger.debug("🔍 [ExerciseHistory] Fetching previous sets for '\(exerciseName)' user: \(userId.uuidString)", category: .workout)
        #endif
        
        do {
            // Query exercise_performance_history first to get the most recent workout for this exercise
            // This table has workout_date which we can sort by
            struct PerformanceRow: Decodable {
                let id: String
                let workout_date: String?
            }
            
            AppLogger.debug("🔍 [ExerciseHistory] Querying exercise_performance_history for '\(exerciseName)'...", category: .workout)
            
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
                AppLogger.debug("📭 [ExerciseHistory] No previous performance found for '\(exerciseName)'", category: .workout)
                // Cache empty result to avoid repeated lookups
                await MainActor.run {
                    self.previousSetsCache[exerciseName] = []
                }
                return []
            }
            
            AppLogger.debug("🔍 [ExerciseHistory] Found performance_id: \(performanceId), fetching sets...", category: .workout)
            
            // Now get all sets from that workout (excluding warmup sets)
            struct SetHistoryRow: Decodable {
                let set_number: Int
                let weight: Double
                let reps: Int
                let set_type: String?
            }
            
            let setRows: [SetHistoryRow] = try await supabase
                .from("exercise_set_history")
                .select("set_number, weight, reps, set_type")
                .eq("performance_id", value: performanceId)
                .neq("set_type", value: "Warmup")
                .order("set_number", ascending: true)
                .execute()
                .value
            
            AppLogger.debug("🔍 [ExerciseHistory] Found \(setRows.count) working set rows for performance_id: \(performanceId)", category: .workout)
            
            let response = setRows.enumerated().map { index, row in
                PreviousSetInfo(
                    setNumber: index + 1,
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
            AppLogger.info("✅ [ExerciseHistory] Found \(response.count) previous sets for '\(exerciseName)' in \(String(format: "%.0f", elapsed))ms", category: .workout)
            for set in response {
                AppLogger.debug("   Set \(set.setNumber): \(Int(set.weight))lbs × \(set.reps) reps", category: .workout)
            }
            #endif
            return response
            
        } catch {
            AppLogger.error("❌ [ExerciseHistory] Error fetching previous sets for '\(exerciseName)': \(error)", category: .workout)
            AppLogger.error("❌ [ExerciseHistory] Full error details: \(String(describing: error))", category: .workout)
            return []
        }
    }
    
    /// Fetch previous sets for multiple exercises at once (batch load)
    /// Deduplicates concurrent calls for the same exercise set (warmup + preview fire simultaneously)
    func fetchPreviousSetsForExercises(_ exerciseNames: [String]) async -> [String: [PreviousSetInfo]] {
        let requestedSet = Set(exerciseNames)
        
        // If an identical batch is already in flight, reuse it
        if let existingTask = inFlightBatchTask, let existingKey = inFlightBatchKey, existingKey == requestedSet {
            AppLogger.debug("📦 [ExerciseHistory] Reusing in-flight batch for \(exerciseNames.count) exercises", category: .workout)
            return await existingTask.value
        }
        
        let task = Task<[String: [PreviousSetInfo]], Never> { [weak self] in
            guard let self = self else { return [:] }
            
            #if DEBUG
            let startTime = CFAbsoluteTimeGetCurrent()
            var cacheHits = 0
            #endif

            var results: [String: [PreviousSetInfo]] = [:]
            var namesToFetch: [String] = []

            for name in exerciseNames {
                if let cached = self.previousSetsCache[name] {
                    results[name] = cached
                    #if DEBUG
                    cacheHits += 1
                    #endif
                } else {
                    namesToFetch.append(name)
                }
            }
            
            #if DEBUG
            AppLogger.debug("📦 [ExerciseHistory] Batch: \(cacheHits) cache hits, \(namesToFetch.count) need fetch", category: .workout)
            #endif
            
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
                    }
                }
            }
            
            #if DEBUG
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            AppLogger.debug("📦 [ExerciseHistory] Batch complete: \(results.count) exercises in \(String(format: "%.0f", elapsed))ms", category: .workout)
            #endif
            
            return results
        }
        
        inFlightBatchTask = task
        inFlightBatchKey = requestedSet
        
        let result = await task.value
        
        inFlightBatchTask = nil
        inFlightBatchKey = nil
        
        return result
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
        AppLogger.debug("💾 [ExerciseHistory] saveExercisePerformance called for '\(exerciseName)'", category: .workout)
        AppLogger.debug("💾 [ExerciseHistory] Input sets count: \(sets.count)", category: .workout)
        
        guard let userId = SupabaseManager.shared.currentUser?.id else {
            AppLogger.error("❌ [ExerciseHistory] No authenticated user - cannot save", category: .workout)
            throw ExerciseHistoryError.notAuthenticated
        }
        
        AppLogger.debug("💾 [ExerciseHistory] User ID: \(userId.uuidString)", category: .workout)
        
        // Filter to only completed sets with actual data
        let completedSets = sets.filter { $0.isCompleted && ($0.weight > 0 || $0.reps > 0) }
        
        AppLogger.debug("💾 [ExerciseHistory] Completed sets with data: \(completedSets.count)", category: .workout)
        
        guard !completedSets.isEmpty else {
            AppLogger.warning("⚠️ [ExerciseHistory] No completed sets to save for '\(exerciseName)'", category: .workout)
            return
        }
        
        // Calculate aggregate metrics (exclude warmup sets from aggregates)
        let workingSets = completedSets.filter { !$0.isWarmup }
        let setsForMetrics = workingSets.isEmpty ? completedSets : workingSets
        let totalSets = setsForMetrics.count
        let totalReps = setsForMetrics.reduce(0) { $0 + $1.reps }
        let totalVolume = setsForMetrics.reduce(0.0) { $0 + ($1.weight * Double($1.reps)) }
        let maxWeight = setsForMetrics.map { $0.weight }.max() ?? 0
        let maxReps = setsForMetrics.map { $0.reps }.max() ?? 0
        let avgWeight = setsForMetrics.isEmpty ? 0 : setsForMetrics.reduce(0.0) { $0 + $1.weight } / Double(setsForMetrics.count)
        let avgReps = setsForMetrics.isEmpty ? 0 : Double(totalReps) / Double(setsForMetrics.count)
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
        AppLogger.debug("💾 [ExerciseHistory] Inserting into exercise_performance_history...", category: .workout)
        do {
            try await supabase
                .from("exercise_performance_history")
                .insert(performanceData)
                .execute()
            AppLogger.info("✅ [ExerciseHistory] Saved performance for '\(exerciseName)' - \(totalSets) sets, \(totalReps) reps, \(Int(totalVolume)) volume", category: .workout)
        } catch {
            AppLogger.error("❌ [ExerciseHistory] FAILED to insert performance: \(error)", category: .workout)
            throw error
        }
        
        // Insert individual set records
        AppLogger.debug("💾 [ExerciseHistory] Inserting \(completedSets.count) sets into exercise_set_history...", category: .workout)
        for (index, set) in completedSets.enumerated() {
            let weightKg = (set.weight * 0.453592 * 10).rounded() / 10
            let setData: [String: AnyJSON] = [
                "performance_id": .string(performanceId.uuidString),
                "user_id": .string(userId.uuidString),
                "exercise_name": .string(exerciseName),
                "set_number": .integer(index + 1),
                "weight": .double(set.weight),
                "weight_kg": .double(weightKg),
                "reps": .integer(set.reps),
                "is_completed": .bool(true),
                "is_failure": .bool(set.isFailure),
                "is_dropset": .bool(set.isDropset),
                "set_type": .string(set.setType.rawValue),
                "rest_time_seconds": .integer(Int(set.restTime))
            ]
            
            do {
                try await supabase
                    .from("exercise_set_history")
                    .insert(setData)
                    .execute()
                AppLogger.info("   ✅ Set \(index + 1) saved", category: .workout)
            } catch {
                AppLogger.error("   ❌ Set \(index + 1) FAILED: \(error)", category: .workout)
                throw error
            }
        }
        
        AppLogger.info("✅ [ExerciseHistory] Saved \(completedSets.count) set records for '\(exerciseName)'", category: .workout)
        
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
            self.recentSessionsCache.removeValue(forKey: exerciseName)
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
                AppLogger.debug("🏆 [ExerciseHistory] NEW PR! Max weight for '\(exerciseName)': \(Int(maxWeight)) lbs", category: .workout)
            }
            
            if maxReps > existing.maxReps {
                updates["max_reps"] = .integer(maxReps)
                updates["max_reps_date"] = .string(isoNow)
                AppLogger.debug("🏆 [ExerciseHistory] NEW PR! Max reps for '\(exerciseName)': \(maxReps)", category: .workout)
            }
            
            if maxVolumeSingleSet > existing.maxVolumeSingleSet {
                updates["max_volume_single_set"] = .double(maxVolumeSingleSet)
                updates["max_volume_single_set_date"] = .string(isoNow)
                AppLogger.debug("🏆 [ExerciseHistory] NEW PR! Max volume single set for '\(exerciseName)': \(Int(maxVolumeSingleSet))", category: .workout)
            }
            
            if totalVolume > existing.maxVolumeSession {
                updates["max_volume_session"] = .double(totalVolume)
                updates["max_volume_session_date"] = .string(isoNow)
                AppLogger.debug("🏆 [ExerciseHistory] NEW PR! Max volume session for '\(exerciseName)': \(Int(totalVolume))", category: .workout)
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
                AppLogger.debug("🏆 [ExerciseHistory] NEW PR! Estimated 1RM for '\(exerciseName)': \(Int(best1rm)) lbs", category: .workout)
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
            
            AppLogger.info("✅ [ExerciseHistory] Created new PR record for '\(exerciseName)'", category: .workout)
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
            AppLogger.error("❌ [ExerciseHistory] Error fetching PR: \(error)", category: .workout)
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
            AppLogger.error("❌ [ExerciseHistory] Error fetching all PRs: \(error)", category: .workout)
            return []
        }
    }
    
    // MARK: - Recent Session Summaries (last-N-sessions tile row)

    /// Fetch up to `limit` most-recent session summaries for an exercise.
    /// Used by ExerciseCard tile row. Cached by exercise name (deduplicates
    /// concurrent calls). Returns [] for first-time exercises and caches the
    /// empty result to avoid hammering Supabase.
    func fetchRecentSessions(for exerciseName: String, limit: Int = 2) async -> [ExerciseSessionSummary] {
        if let cached = recentSessionsCache[exerciseName] {
            return Array(cached.prefix(limit))
        }
        if let inFlight = inFlightSessionTasks[exerciseName] {
            return Array((await inFlight.value).prefix(limit))
        }
        guard let userId = SupabaseManager.shared.currentUser?.id else {
            AppLogger.warning("⚠️ [ExerciseHistory] No authenticated user for recent sessions", category: .workout)
            return []
        }

        let task = Task<[ExerciseSessionSummary], Never> { [weak self] in
            guard let self = self else { return [] }
            struct Row: Decodable {
                let workout_date: String?
                let avg_weight: Double?
                let max_weight: Double?
                let total_sets: Int?
                let total_reps: Int?
            }
            do {
                let rows: [Row] = try await self.supabase
                    .from("exercise_performance_history")
                    .select("workout_date, avg_weight, max_weight, total_sets, total_reps")
                    .eq("user_id", value: userId.uuidString)
                    .eq("exercise_name", value: exerciseName)
                    .order("workout_date", ascending: false)
                    .limit(limit)
                    .execute()
                    .value

                let iso = ISO8601DateFormatter()
                iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let isoFallback = ISO8601DateFormatter()
                let dateOnly = DateFormatter()
                dateOnly.dateFormat = "yyyy-MM-dd"
                dateOnly.timeZone = TimeZone(identifier: "UTC")

                let summaries: [ExerciseSessionSummary] = rows.compactMap { row in
                    guard let raw = row.workout_date else { return nil }
                    let date = iso.date(from: raw)
                        ?? isoFallback.date(from: raw)
                        ?? dateOnly.date(from: raw)
                    guard let parsed = date else { return nil }
                    let avg = row.avg_weight ?? 0
                    let maxW = row.max_weight ?? 0
                    return ExerciseSessionSummary(
                        workoutDate: parsed,
                        avgWeight: avg,
                        totalSets: row.total_sets ?? 0,
                        totalReps: row.total_reps ?? 0,
                        maxWeight: maxW
                    )
                }

                await MainActor.run {
                    self.recentSessionsCache[exerciseName] = summaries
                    self.inFlightSessionTasks[exerciseName] = nil
                }
                return summaries
            } catch {
                AppLogger.error("❌ [ExerciseHistory] Recent sessions fetch failed for '\(exerciseName)': \(error)", category: .workout)
                await MainActor.run {
                    self.inFlightSessionTasks[exerciseName] = nil
                }
                return []
            }
        }
        await MainActor.run {
            self.inFlightSessionTasks[exerciseName] = task
        }
        return Array((await task.value).prefix(limit))
    }

    // MARK: - Clear Cache
    
    func clearCache() {
        previousSetsCache.removeAll()
        personalRecordsCache.removeAll()
        recentSessionsCache.removeAll()
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

