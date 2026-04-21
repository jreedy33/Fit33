//
//  WorkoutWearableMerger.swift
//  Fit33
//
//  Cross-source dedup + enrichment for the workout history UI.
//
//  Problem: when the user wears a WHOOP (or Apple Watch / Oura / Fitbit /
//  Garmin) during a Fit33 strength session, the wearable writes its own
//  "Strength Training" workout to HealthKit. `HealthDataService.syncTodayHealthKitData()`
//  imports that into `cardio_workouts` with `origin_app = <wearable>`. The
//  Fit33 session itself lives in Core Data (`Workout` entity) because it
//  carries the exercises/sets/reps. The history UI concatenates both lists,
//  so the user sees the same session twice — once with rich Fit33 data, once
//  as a bare-metrics wearable row.
//
//  Fix: match each Fit33 strength `Workout` to any wearable-origin strength
//  cardio row that time-overlaps it (>=50% shorter-side overlap — same math
//  as the canonical WHOOP overlap dedup in `supabase-rules.mdc`). The
//  wearable row is dropped from the visible cardio list and exposed via
//  `enrichmentByWorkoutID` so the Fit33 card / detail view can surface the
//  wearable's avg HR / calories / origin badge. Storage is untouched — the
//  cardio row stays in `cardio_workouts` for WHOOP widgets + analytics.
//
//  Used by:
//    - `DashboardWorkoutHistory.WorkoutHistoryFullView.groupedItems`
//    - `DashboardView.rebuildCombinedWorkouts`
//    - `WorkoutHistoryDetailView` (detail-view wearable card)
//

import Foundation
import CoreData

enum WorkoutWearableMerger {
    // MARK: - Configuration

    /// Origins we collapse onto a Fit33 strength `Workout`. These are the
    /// wearables that commonly auto-track a strength session when worn
    /// alongside Fit33 (either via first-party OAuth or via HealthKit).
    private static let wearableOrigins: Set<WorkoutOrigin> = [
        .whoop, .oura, .fitbit, .appleWatch, .garmin
    ]

    /// Lowercased activity types treated as "strength-like" and therefore
    /// candidates to merge onto a Fit33 strength workout. Matches the
    /// strings emitted by `HealthDataService.saveHealthKitWorkout` for
    /// HKWorkoutActivityType traditional/functional strength + adjacent
    /// training types that wearables frequently tag during lifting.
    private static let strengthActivityTypes: Set<String> = [
        "strength training",
        "functional strength training",
        "traditional strength training",
        "hiit",
        "cross training",
        "core training"
    ]

    /// Minimum fraction of overlap required to treat two workouts as the
    /// same session. Uses shorter-side denominator (matches the canonical
    /// `cardio_workouts` WHOOP dedup: `supabase-rules.mdc` → "WHOOP Overlap
    /// Dedup"). 0.5 tolerates a minute of clock skew between the watch and
    /// the user tapping "Finish".
    private static let overlapThreshold: Double = 0.5

    // MARK: - Result

    struct Result {
        /// Cardio rows with wearable-strength duplicates removed.
        let filteredCardio: [CardioWorkoutDTO]
        /// Fit33 `Workout.id` → matched wearable cardio row. Lookup key for
        /// UI enrichment (avg HR chip, origin badge, detail-view card).
        let enrichmentByWorkoutID: [UUID: CardioWorkoutDTO]
    }

    // MARK: - API

    /// Merge wearable-origin strength cardio rows into Fit33 strength
    /// workouts. Pure function — safe to call from any thread as long as the
    /// passed Core Data `Workout` objects are accessed from their own
    /// managed object context (callers read `.id` / `.date` / `.duration` on
    /// the context they came from, which is the view-context case for every
    /// caller today).
    static func merge(strength: [Workout], cardio: [CardioWorkoutDTO]) -> Result {
        guard !strength.isEmpty, !cardio.isEmpty else {
            return Result(filteredCardio: cardio, enrichmentByWorkoutID: [:])
        }

        var consumedCardioIDs: Set<String> = []
        var enrichment: [UUID: CardioWorkoutDTO] = [:]

        for workout in strength {
            guard let workoutID = workout.id,
                  let start = workout.date else { continue }
            // `Workout.duration` is seconds (see `ActiveWorkoutView+Persistence` → `Int32(elapsedTime)`).
            let durationSec = max(Int(workout.duration), 1)
            let end = start.addingTimeInterval(TimeInterval(durationSec))

            var bestMatch: (dto: CardioWorkoutDTO, score: Double)?
            for dto in cardio where !consumedCardioIDs.contains(dto.id) {
                guard wearableOrigins.contains(dto.resolvedOrigin) else { continue }
                guard strengthActivityTypes.contains(dto.activityType.lowercased()) else { continue }

                let dtoStart = ISO8601Parser.parse(dto.startedAt, fallback: Date.distantPast)
                let dtoEnd = ISO8601Parser.parse(dto.completedAt, fallback: Date.distantPast)
                guard dtoStart > Date.distantPast, dtoEnd > dtoStart else { continue }

                let overlap = overlapFraction(aStart: start, aEnd: end, bStart: dtoStart, bEnd: dtoEnd)
                guard overlap >= overlapThreshold else { continue }

                if overlap > (bestMatch?.score ?? 0) {
                    bestMatch = (dto, overlap)
                }
            }

            if let match = bestMatch {
                consumedCardioIDs.insert(match.dto.id)
                enrichment[workoutID] = match.dto
                AppLogger.info(
                    "[WEARABLE-MERGE] Merged \(match.dto.resolvedOrigin.displayName) \(match.dto.activityType) into Fit33 workout \(workout.name ?? "Untitled") (overlap=\(Int(match.score * 100))%)",
                    category: .workout
                )
            }
        }

        let filtered = cardio.filter { !consumedCardioIDs.contains($0.id) }
        return Result(filteredCardio: filtered, enrichmentByWorkoutID: enrichment)
    }

    /// Lookup helper for views that already have a `Workout` and want just
    /// the wearable enrichment (e.g. `WorkoutHistoryDetailView`). Returns
    /// the first wearable cardio row that overlaps `workout`.
    static func wearableEnrichment(for workout: Workout, in cardio: [CardioWorkoutDTO]) -> CardioWorkoutDTO? {
        merge(strength: [workout], cardio: cardio).enrichmentByWorkoutID[workout.id ?? UUID()]
    }

    // MARK: - Effective calories (wearable priority)

    /// Preferred calorie count for a Fit33 strength workout. When a wearable
    /// (WHOOP / Apple Watch / Oura / Fitbit / Garmin) recorded an
    /// overlapping session and reported `caloriesBurned > 0`, that
    /// sensor-measured value wins over the Fit33 MET-based formula estimate
    /// stored in `Workout.caloriesBurned`. Otherwise the Fit33 stored value
    /// is returned. Returns `0` only when neither source has a value.
    ///
    /// Why: the Fit33 formula assumes an average MET-per-exercise curve and
    /// is accurate to roughly ±25% for typical lifters. A wearable with
    /// optical HR (WHOOP / Apple Watch) or a calibrated IR PPG (Oura)
    /// measures actual caloric cost from HR + motion and is substantially
    /// more accurate — especially for users who train harder or lighter
    /// than the formula's baseline assumes. We never overwrite the stored
    /// Core Data value (so historical analytics remain stable and offline
    /// devices don't lose data) — the override is display-only at every
    /// call site.
    static func effectiveCalories(workout: Workout, wearable: CardioWorkoutDTO?) -> Double {
        if let wearable, wearable.caloriesBurned > 0 {
            return wearable.caloriesBurned
        }
        return workout.caloriesBurned
    }

    /// True when `effectiveCalories` would return a wearable-measured value.
    /// UI uses this to show a subtle "Measured by <brand>" tag so users know
    /// the number came from their device, not the formula.
    static func caloriesAreWearableMeasured(workout: Workout, wearable: CardioWorkoutDTO?) -> Bool {
        guard let wearable, wearable.caloriesBurned > 0 else { return false }
        _ = workout // silence unused-parameter warning; signature kept symmetric with `effectiveCalories`.
        return true
    }

    // MARK: - Private

    /// Overlap fraction using shorter-side denominator. Mirrors the
    /// `cardio_workouts` canonical overlap math in `supabase-rules.mdc`.
    private static func overlapFraction(aStart: Date, aEnd: Date, bStart: Date, bEnd: Date) -> Double {
        let start = max(aStart, bStart)
        let end = min(aEnd, bEnd)
        let overlap = end.timeIntervalSince(start)
        guard overlap > 0 else { return 0 }

        let aDuration = aEnd.timeIntervalSince(aStart)
        let bDuration = bEnd.timeIntervalSince(bStart)
        let denom = min(aDuration, bDuration)
        guard denom > 0 else { return 0 }
        return overlap / denom
    }
}
