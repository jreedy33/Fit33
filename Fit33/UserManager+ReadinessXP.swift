//
//  UserManager+ReadinessXP.swift
//  Fit33
//
//  Wearable Personalization Platform — Phase 4 (XP Multipliers)
//
//  XP bonus logic for completed workouts based on the user's
//  readiness band + whether the workout was recovery-style:
//
//    Green day + any workout  →  +20% XP (trained while primed)
//    Red day   + recovery     →  +15% XP (Smart Rest bonus)
//    Red day   + heavy        →  base XP (no penalty — don't punish)
//    Yellow / no wearable     →  base XP
//
//  Feature-flagged via `AppConfig.FeatureFlags.readinessXpBonus` so
//  we don't silently change the XP economy before users see the new
//  banner / toast copy.
//

import Foundation

extension UserManager {

    /// Apply a readiness-band XP bonus on top of the base XP award.
    ///
    /// Never returns below `baseXP` — bonuses are always additive so
    /// we never penalize training on a red day.
    ///
    /// Nonisolated on purpose — callers (`completeWorkout`) pass the
    /// snapshot they already read from `ReadinessService.shared` on
    /// the main actor. Avoids making the whole UserManager main-actor
    /// just to read one published value.
    func applyReadinessXPMultiplier(
        baseXP: Int32,
        snapshot: DailyReadinessSnapshot,
        isRecoveryWorkout: Bool
    ) -> Int32 {
        guard AppConfig.FeatureFlags.readinessXpBonus else { return baseXP }
        guard snapshot.hasWearableSignal else { return baseXP }

        switch snapshot.band {
        case .green:
            // +20% (rounded) for training on a green day.
            let bonus = Int32((Double(baseXP) * 0.20).rounded())
            AppLogger.info(
                "[Readiness] +\(bonus) XP bonus (green day multiplier)",
                category: .general
            )
            return baseXP + bonus

        case .red where isRecoveryWorkout:
            // +15% "Smart Rest" — respect red recovery pays off.
            let bonus = Int32((Double(baseXP) * 0.15).rounded())
            AppLogger.info(
                "[Readiness] +\(bonus) XP Smart Rest bonus (red day recovery)",
                category: .general
            )
            return baseXP + bonus

        case .red, .yellow:
            return baseXP
        }
    }

    /// True when the completed workout looks like a recovery session —
    /// all exercises are tagged Stretch / Yoga / mobility. Used to
    /// gate the Smart Rest XP bonus on red days.
    static func isRecoveryStyleWorkout(_ workout: Workout) -> Bool {
        guard let exercises = workout.exercises?.allObjects as? [WorkoutExercise],
              !exercises.isEmpty else {
            return false
        }
        // Every exercise in the session must look like a recovery
        // movement — a single heavy compound defeats the "smart rest"
        // claim. Keeps the bonus from being gameable.
        return exercises.allSatisfy { workoutExercise in
            let name = (workoutExercise.safeDisplayName).lowercased()
            // `Exercise` rel on WorkoutExercise exposes `.exercise`;
            // fall back to name match when the relation is nil
            // (shouldn't happen in prod, defensive).
            if let exercise = workoutExercise.value(forKey: "exercise") as? Exercise {
                let wt = (exercise.workoutType ?? "").lowercased()
                let cat = (exercise.category ?? "").lowercased()
                if wt.contains("stretch") { return true }
                if cat.contains("stretch") { return true }
            }
            return name.contains("stretch")
                || name.contains("yoga")
                || name.contains("mobility")
                || name.contains("foam roll")
        }
    }
}
