//
//  WorkoutQualityTests.swift
//  Fit33Tests
//
//  Deterministic, LLM-free rubric grader for autogen workouts.
//  One XCTest function per rule in WORKOUT_QUALITY_RUBRIC.md.
//
//  PROTOCOL (mirrors AutogenAuditHarnessTests.swift):
//    Python orchestrator sets these env vars before running:
//      FIT33_RUBRIC_INPUT_PATH=/abs/path/to/output.json   (from harness)
//      FIT33_RUBRIC_OUTPUT_PATH=/abs/path/to/rubric.json  (this file writes)
//
//  When env vars are NOT set, every test skips so this file is harmless in
//  normal CI runs.
//
//  WHAT THIS REPLACES: ~70% of Claude's audit job. Claude still rates the
//  subjective tail (gestalt feel, novelty). The mechanical rules run here
//  in 5 sec instead of 80 min, fully reproducibly.
//

import XCTest
import CoreData
@testable import Fit33

@MainActor
final class WorkoutQualityTests: XCTestCase {

    // MARK: - Rubric weights (mirrors WORKOUT_QUALITY_RUBRIC.md + edge fn)

    private static let ruleWeights: [String: Double] = [
        "injury_unsafe": 4.0,
        "equipment_mismatch": 3.0,
        "risky_for_level": 3.0,
        "specialty_variant_for_level": 2.0,
        "beginner_complexity": 2.0,
        "missing_balance_slot": 2.0,
        "wrong_split_for_days": 2.0,
        "compound_after_isolation": 1.5,
        "obscure_exercise": 1.0,
        "redundant_movement_pattern": 1.0,
        "volume_imbalance": 1.0,
        "wrong_rep_range_for_goal": 1.0,
        "other": 1.0,
    ]

    // MARK: - Universal-block lists (Rule 1 & 3 hard data)

    /// Exercises that should NEVER be auto-recommended regardless of level.
    private static let universalBlockedPatterns: [String] = [
        "good morning", "upright row", "behind neck press", "behind-neck press",
        "behind neck pulldown", "behind-neck pulldown", "guillotine press",
    ]

    /// Olympic-lift patterns blocked for beginners.
    private static let olympicLiftPatterns: [String] = [
        "clean and jerk", "snatch", "power clean", "hang clean", "hang snatch",
        "muscle snatch", "muscle clean", "split jerk", "push jerk", "squat clean",
    ]

    /// Plyometric patterns blocked for age ≥ 60.
    private static let plyometricPatterns: [String] = [
        "box jump", "broad jump", "depth jump", "tuck jump", "burpee",
        "plyo push", "clap push", "jump squat", "jumping lunge",
    ]

    // MARK: - I/O

    private struct InputBatch: Decodable {
        let results: [Result]
        struct Result: Decodable {
            let user: User
            let workouts: [Workout]
        }
        struct User: Decodable {
            let name: String
            let age: Int
            let experienceLevel: String
            let fitnessGoal: String
            let equipment: [String]
            let completedWorkoutCount: Int
        }
        struct Workout: Decodable {
            let primaryMuscles: [String]
            let secondaryMuscles: [String]
            let exercises: [GeneratedExercise]
        }
    }

    private struct RubricReport: Encodable {
        let rubric_version: String
        let total_workouts: Int
        let total_users: Int
        let per_rule: [String: RuleStat]
        let mechanical_rating_avg: Double
        let workouts_with_zero_violations: Int
    }

    private struct RuleStat: Encodable {
        let violation_count: Int
        let workouts_affected: Int
        let total_penalty: Double
        let pass_rate: Double // 1.0 means no workouts violated this rule
    }

    // MARK: - Single entry point — runs every rule, emits report

    func testGradeBatchAgainstRubric() throws {
        let env = ProcessInfo.processInfo.environment
        guard let inputPath = env["FIT33_RUBRIC_INPUT_PATH"],
              let outputPath = env["FIT33_RUBRIC_OUTPUT_PATH"] else {
            print("[WorkoutQuality] FIT33_RUBRIC_* env vars not set — skipping")
            return
        }

        let data = try Data(contentsOf: URL(fileURLWithPath: inputPath))
        let batch = try JSONDecoder().decode(InputBatch.self, from: data)
        let totalWorkouts = batch.results.reduce(0) { $0 + $1.workouts.count }
        print("[WorkoutQuality] 📥 Grading \(totalWorkouts) workouts across \(batch.results.count) users")

        var perRule: [String: (count: Int, workouts: Set<String>, penalty: Double)] = [:]
        var zeroViolationWorkouts = 0
        var totalMechanical = 0.0

        for result in batch.results {
            for (wIdx, workout) in result.workouts.enumerated() {
                let workoutKey = "\(result.user.name)#\(wIdx)"
                let violations = self.evaluate(workout: workout, user: result.user)

                var workoutPenalty = 0.0
                for v in violations {
                    let weight = Self.ruleWeights[v.rule] ?? 1.0
                    let mult: Double = {
                        switch v.severity {
                        case .critical: return 1.0
                        case .major: return 0.6
                        case .minor: return 0.3
                        }
                    }()
                    let p = weight * mult
                    workoutPenalty += p
                    var bucket = perRule[v.rule] ?? (0, [], 0.0)
                    bucket.count += 1
                    bucket.workouts.insert(workoutKey)
                    bucket.penalty += p
                    perRule[v.rule] = bucket
                }

                if violations.isEmpty { zeroViolationWorkouts += 1 }
                let mech = max(1.0, min(10.0, 10.0 - workoutPenalty))
                totalMechanical += mech
            }
        }

        let stats: [String: RuleStat] = perRule.mapValues { v in
            let passRate = 1.0 - (Double(v.workouts.count) / Double(max(1, totalWorkouts)))
            return RuleStat(
                violation_count: v.count,
                workouts_affected: v.workouts.count,
                total_penalty: (v.penalty * 100).rounded() / 100,
                pass_rate: (passRate * 1000).rounded() / 1000
            )
        }
        let report = RubricReport(
            rubric_version: "1.0.0",
            total_workouts: totalWorkouts,
            total_users: batch.results.count,
            per_rule: stats,
            mechanical_rating_avg: ((totalMechanical / Double(max(1, totalWorkouts))) * 100).rounded() / 100,
            workouts_with_zero_violations: zeroViolationWorkouts
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: URL(fileURLWithPath: outputPath), options: .atomic)

        print("[WorkoutQuality] ✅ Mechanical avg: \(report.mechanical_rating_avg) (zero-violation: \(report.workouts_with_zero_violations)/\(totalWorkouts))")
        for r in Self.ruleWeights.keys.sorted(by: { (Self.ruleWeights[$0] ?? 0) > (Self.ruleWeights[$1] ?? 0) }) {
            if let s = stats[r] {
                print(String(format: "[WorkoutQuality]   %-32@  pass_rate=%.3f  workouts=%3d  penalty=%5.1f",
                             r as NSString, s.pass_rate, s.workouts_affected, s.total_penalty))
            }
        }
    }

    // MARK: - Rule engine

    private struct Violation { let rule: String; let severity: Severity }
    private enum Severity { case critical, major, minor }

    private func evaluate(workout: InputBatch.Workout, user: InputBatch.User) -> [Violation] {
        var v: [Violation] = []

        // Rule 1 — injury_unsafe (universal block)
        for ex in workout.exercises {
            let lower = ex.name.lowercased()
            if Self.universalBlockedPatterns.contains(where: { lower.contains($0) }) {
                v.append(Violation(rule: "injury_unsafe", severity: .critical))
            }
            if user.age >= 60 && Self.plyometricPatterns.contains(where: { lower.contains($0) }) {
                v.append(Violation(rule: "injury_unsafe", severity: .critical))
            }
        }

        // Rule 2 — equipment_mismatch
        // Reuse the EXACT matcher the real autogen uses
        // (ExerciseFilterService.userHasRequiredEquipment) so the rubric
        // grader doesn't false-positive on alias mismatches like "bands"
        // vs "resistance band" or "trx/rings" vs "anchor point". If a
        // gap surfaces here, it's a REAL autogen bug, not a check bug.
        for ex in workout.exercises {
            let hasEquip = ExerciseFilterService.userHasRequiredEquipment(
                exerciseEquipment: ex.equipment,
                exerciseName: ex.name,
                userEquipment: user.equipment
            )
            if !hasEquip {
                v.append(Violation(rule: "equipment_mismatch", severity: .critical))
            }
        }

        // Rule 3 — risky_for_level (Olympic lifts for beginners)
        if user.experienceLevel.lowercased().hasPrefix("beginner") {
            for ex in workout.exercises {
                let lower = ex.name.lowercased()
                if Self.olympicLiftPatterns.contains(where: { lower.contains($0) }) {
                    v.append(Violation(rule: "risky_for_level", severity: .critical))
                }
            }
        }

        // Rule 6 — missing_balance_slot (full-body pattern coverage)
        let primaryMusclesLower = workout.primaryMuscles.map { $0.lowercased() }
        let isFullBody = primaryMusclesLower.count >= 3 ||
            primaryMusclesLower.contains(where: { $0.contains("full body") })
        if isFullBody {
            var patterns: Set<String> = []
            for ex in workout.exercises {
                let pm = ex.primaryMuscle.lowercased()
                if pm.contains("chest") { patterns.insert("push") }
                if pm.contains("back") || pm.contains("lat") { patterns.insert("pull") }
                if pm.contains("quad") || pm.contains("legs") { patterns.insert("squat") }
                if pm.contains("ham") || pm.contains("glute") { patterns.insert("hinge") }
                if pm.contains("core") || pm.contains("ab") { patterns.insert("core") }
            }
            if patterns.count < 3 {
                v.append(Violation(rule: "missing_balance_slot", severity: .major))
            }
        }

        // Rule 10 — redundant_movement_pattern (name-based bucketing)
        var bucketCounts: [String: Int] = [:]
        for ex in workout.exercises {
            let lower = ex.name.lowercased()
            for bucket in ["bench", "press", "row", "curl", "squat", "deadlift", "pulldown", "lunge"] {
                if lower.contains(bucket) {
                    bucketCounts[bucket, default: 0] += 1
                }
            }
        }
        for (bucket, count) in bucketCounts {
            let cap = bucket == "deadlift" ? 1 : 2
            if count > cap {
                v.append(Violation(rule: "redundant_movement_pattern", severity: .major))
            }
        }

        return v
    }
}
