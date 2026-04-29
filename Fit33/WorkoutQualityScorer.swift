//
//  WorkoutQualityScorer.swift
//  Fit33
//
//  Pure-local quality scorer used at workout-finish time to label a workout
//  HIGH / MEDIUM / LOW for the auto-gen training corpus and to feed the
//  same fields into `workout_history` server-side.
//
//  WHY THIS FILE EXISTS:
//  - `Fit33/CollaborativeLearningEngine.swift::recordWorkoutCompletion` only
//    pushes workouts with score >= 70 into `collaborative_workout_data`
//    (Wave 2 wires this).
//  - We want instant UI feedback at workout-finish (no round-trip) AND we
//    want the score attached to the Core Data `Workout` BEFORE first sync.
//
//  WHY IT MUST STAY IN SYNC WITH THE SQL RPC:
//  - `supabase/20260723_quality_workout_corpus.sql` exposes
//    `score_workout_quality(p_workout_id UUID)` doing the SAME math.
//  - Server is the canonical authority — every check, threshold, and weight
//    here MUST mirror that RPC. If you change the rubric, change BOTH.
//
//  Public surface (intentionally narrow):
//    - `WorkoutQualityBand`
//    - `WorkoutQualityResult`
//    - `WorkoutQualityScorer.score(...)`
//    - `WorkoutQualityScorer.isObviouslyJunk(...)`
//

import Foundation
import CoreData

// MARK: - Band

enum WorkoutQualityBand: String, Codable {
    case high   // 70+
    case medium // 40–69
    case low    // <40

    static func band(for score: Int) -> WorkoutQualityBand {
        if score >= 70 { return .high }
        if score >= 40 { return .medium }
        return .low
    }
}

// MARK: - Result

struct WorkoutQualityResult: Codable {
    let score: Int                 // 0–100
    let band: WorkoutQualityBand
    /// Canonical reason keys (must match SQL RPC):
    /// durationOK, completionOK, exerciseCountOK, setsOK,
    /// weightDistributionOK, paceOK, balanceOK
    let reasons: [String: Bool]
    let qualifiesForCorpus: Bool   // score >= 70

    /// JSON-friendly dictionary used as `quality_reasons` JSONB on
    /// `workout_history`. `[String: Any]` because PostgREST encodes
    /// JSONB as a free-form object; values here are all booleans.
    var reasonsJSON: [String: Any] {
        var out: [String: Any] = [:]
        for (k, v) in reasons { out[k] = v }
        return out
    }
}

// MARK: - Scorer

@MainActor
struct WorkoutQualityScorer {

    // MARK: Rubric weights (mirror SQL RPC exactly)
    private static let pointsDuration: Int             = 20  // duration >= 25 min
    private static let pointsCompletion: Int           = 25  // completed/planned >= 0.80
    private static let pointsExerciseCount: Int        = 15  // >= 3 catalog exercises
    private static let pointsSets: Int                 = 15  // >= 12 working sets (non-warmup)
    private static let pointsWeightDistribution: Int   = 10  // >= 50% of weight-eligible sets have weight > 0
    private static let pointsPace: Int                 = 10  // duration / completedSets >= 20s
    private static let pointsBalance: Int              = 5   // FE invariants (lenient bonus)

    private static let thresholdDurationSec: TimeInterval = 1500.0
    private static let thresholdCompletionRate: Double    = 0.80
    private static let thresholdExerciseCount: Int        = 3
    private static let thresholdWorkingSets: Int          = 12
    private static let thresholdWeightCoverage: Double    = 0.50
    private static let thresholdPaceSec: Double           = 20.0

    // MARK: Public API

    static func score(
        workout: Workout,
        exercises: [Exercise],
        exerciseSets: [String: [WorkoutSetData]],
        workoutDuration: TimeInterval
    ) -> WorkoutQualityResult {
        let plannedSets = totalPlannedSets(exerciseSets: exerciseSets)
        let completedAll = completedSets(exerciseSets: exerciseSets, includingWarmup: true)
        let completedWorking = completedSets(exerciseSets: exerciseSets, includingWarmup: false)

        let catalogExerciseCount = exercises.filter { $0.id != nil }.count

        // 1. Duration
        let durationOK = workoutDuration >= thresholdDurationSec

        // 2. Completion rate (uses ALL completed sets vs ALL planned sets, matching RPC)
        let completionRate = Double(completedAll) / Double(max(1, plannedSets))
        let completionOK = completionRate >= thresholdCompletionRate

        // 3. Distinct catalog exercises
        let exerciseCountOK = catalogExerciseCount >= thresholdExerciseCount

        // 4. Working sets (excluding warmup)
        let setsOK = completedWorking >= thresholdWorkingSets

        // 5. Weight distribution (skip bodyweight + duration-based exercises)
        let weightDistributionOK = passesWeightDistribution(
            exercises: exercises,
            exerciseSets: exerciseSets
        )

        // 6. Pace proxy
        let paceOK = (workoutDuration / Double(max(1, completedAll))) >= thresholdPaceSec

        // 7. FE balance heuristic (lenient bonus)
        let balanceOK = passesBalanceHeuristic(exercises: exercises)

        var total = 0
        if durationOK            { total += pointsDuration }
        if completionOK          { total += pointsCompletion }
        if exerciseCountOK       { total += pointsExerciseCount }
        if setsOK                { total += pointsSets }
        if weightDistributionOK  { total += pointsWeightDistribution }
        if paceOK                { total += pointsPace }
        if balanceOK             { total += pointsBalance }

        let reasons: [String: Bool] = [
            "durationOK":            durationOK,
            "completionOK":          completionOK,
            "exerciseCountOK":       exerciseCountOK,
            "setsOK":                setsOK,
            "weightDistributionOK":  weightDistributionOK,
            "paceOK":                paceOK,
            "balanceOK":             balanceOK
        ]

        let result = WorkoutQualityResult(
            score: total,
            band: WorkoutQualityBand.band(for: total),
            reasons: reasons,
            qualifiesForCorpus: total >= 70
        )

        #if DEBUG
        let failed = reasons.filter { !$0.value }.map { $0.key }.sorted()
        AppLogger.debug(
            "WorkoutQualityScorer: score=\(total) band=\(result.band.rawValue) failed=[\(failed.joined(separator: ","))]",
            category: .workout
        )
        #endif

        return result
    }

    static func isObviouslyJunk(
        workout: Workout,
        exercises: [Exercise],
        exerciseSets: [String: [WorkoutSetData]],
        workoutDuration: TimeInterval
    ) -> Bool {
        if workoutDuration < 12 * 60 { return true }
        if exercises.count < 2 { return true }
        if completedSets(exerciseSets: exerciseSets, includingWarmup: true) < 6 { return true }
        return false
    }

    // MARK: Helpers

    private static func totalPlannedSets(exerciseSets: [String: [WorkoutSetData]]) -> Int {
        exerciseSets.values.reduce(0) { $0 + $1.count }
    }

    private static func completedSets(
        exerciseSets: [String: [WorkoutSetData]],
        includingWarmup: Bool
    ) -> Int {
        var count = 0
        for sets in exerciseSets.values {
            for set in sets where set.isCompleted {
                if !includingWarmup && set.setType == .warmup { continue }
                count += 1
            }
        }
        return count
    }

    /// Bodyweight + duration-based exercises auto-pass (no weight expected).
    /// Among the remaining "weight-eligible" completed working sets, at
    /// least 50% must have `weight > 0`.
    private static func passesWeightDistribution(
        exercises: [Exercise],
        exerciseSets: [String: [WorkoutSetData]]
    ) -> Bool {
        var eligible = 0
        var withWeight = 0

        for ex in exercises {
            if isBodyweight(ex) || isDurationBased(ex) { continue }
            guard let idStr = ex.id?.uuidString, let sets = exerciseSets[idStr] else { continue }
            for set in sets where set.isCompleted && set.setType != .warmup {
                eligible += 1
                if set.weight > 0 { withWeight += 1 }
            }
        }

        if eligible == 0 { return true } // pure bodyweight / duration-based workout — lenient pass
        return Double(withWeight) / Double(eligible) >= thresholdWeightCoverage
    }

    private static func isBodyweight(_ ex: Exercise) -> Bool {
        let cat = (ex.value(forKey: "equipmentCategory") as? String)?.lowercased()
        if cat == "bodyweight" { return true }
        return ex.equipment?.lowercased() == "bodyweight"
    }

    private static func isDurationBased(_ ex: Exercise) -> Bool {
        (ex.value(forKey: "durationBased") as? Bool) ?? false
    }

    /// Lenient FE-invariants proxy. Rewards rough push/pull balance and
    /// penalizes long runs of consecutive press/bench/push tokens.
    private static func passesBalanceHeuristic(exercises: [Exercise]) -> Bool {
        let pushTokens: Set<String> = ["press", "bench", "push"]
        let pullTokens: Set<String> = ["row", "pull", "curl"]

        var pushCount = 0
        var pullCount = 0
        var maxPushRun = 0
        var currentPushRun = 0

        for ex in exercises {
            let name = (ex.name ?? "").lowercased()
            let isPush = pushTokens.contains(where: { name.contains($0) })
            let isPull = pullTokens.contains(where: { name.contains($0) })
            if isPush { pushCount += 1 }
            if isPull { pullCount += 1 }

            if isPush {
                currentPushRun += 1
                if currentPushRun > maxPushRun { maxPushRun = currentPushRun }
            } else {
                currentPushRun = 0
            }
        }

        if pushCount > 2 * pullCount { return false }
        if pullCount > 2 * pushCount { return false }
        if maxPushRun > 2 { return false }
        return true
    }
}
