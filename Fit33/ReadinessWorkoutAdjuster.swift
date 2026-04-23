//
//  ReadinessWorkoutAdjuster.swift
//  Fit33
//
//  Wearable Personalization Platform — Phase 1 (Recovery-aware auto-gen)
//
//  Implements FITNESS_EXPERT_AGENT.md invariant #23:
//    Red    (0-33)   → override to recovery day; skip heavy compounds.
//    Yellow (34-66)  → normal programming with 0.9× volume cap.
//    Green  (67-100) → encourage PRs; +10% volume ceiling + RIR-1 allowed.
//
//  Keeps the intervention surface tiny: all adjustment math lives here
//  (`adjustedCount(...)`, `adjustment(for:)`, `buildRecoveryDayExercises(...)`)
//  so we never touch the 3,500-line WorkoutGeneratorService's core
//  selection logic. Callers apply this as a wrapper:
//
//      let adjustment = ReadinessWorkoutAdjuster.adjustment(
//          for: ReadinessService.shared.todayReadiness,
//          requestedCount: count
//      )
//      if adjustment.replaceWithRecoveryDay {
//          return ReadinessWorkoutAdjuster.buildRecoveryDayExercises(count: adjustment.adjustedCount)
//      }
//      // else generate normally, using adjustment.adjustedCount
//
//  Gated by `AppConfig.FeatureFlags.readinessAdaptiveAutoGen` at the
//  call site so Phase-0 ships dark.
//

import Foundation
import CoreData

/// One-shot description of the adjustment that should be applied to
/// today's generated workout given the current readiness band.
struct ReadinessAdjustment: Equatable {
    /// True ⇔ band is `.red` AND the user has a real wearable signal.
    /// When true, callers should bypass normal selection and return
    /// `buildRecoveryDayExercises(count:)`.
    let replaceWithRecoveryDay: Bool

    /// Adjusted target exercise count. For yellow days this is
    /// `max(3, ceil(requested × 0.9))` — never below the Fitness
    /// Expert invariant #17 minimum (3 sets / ≥3 exercises).
    let adjustedCount: Int

    /// True ⇔ band is `.green` — UI may show a "PR attempt day" flag
    /// and generator may allow the first compound's RIR to drop to 1.
    let allowsPrAttempt: Bool

    /// Human readable short banner line ("Recovery day — mobility +
    /// walk today"). Used by `ReadinessAdjustmentBanner`.
    let bannerHeadline: String

    /// Source band that produced this adjustment. Repeated so the
    /// banner can color on band rather than parsing the headline.
    let band: ReadinessBand

    /// Primary wearable source (for the banner caption — "from WHOOP").
    let source: ReadinessSource
}

enum ReadinessWorkoutAdjuster {

    // MARK: - Public API

    /// Compute the adjustment for a requested workout count.
    ///
    /// Always returns a non-nil adjustment (callers don't need to
    /// branch on presence). When the snapshot has no real wearable
    /// signal, returns a pass-through adjustment — identical to
    /// "no feature flag, no adjustment".
    static func adjustment(
        for snapshot: DailyReadinessSnapshot,
        requestedCount: Int
    ) -> ReadinessAdjustment {
        // No wearable connected = no adjustment. `.yellow` placeholder
        // snapshot would otherwise silently cap yellow-pass-through
        // users' volume on day 1, which is a surprising UX.
        guard snapshot.hasWearableSignal else {
            return ReadinessAdjustment(
                replaceWithRecoveryDay: false,
                adjustedCount: requestedCount,
                allowsPrAttempt: false,
                bannerHeadline: "",
                band: snapshot.band,
                source: snapshot.primarySource
            )
        }

        switch snapshot.band {
        case .red:
            // Fitness Expert #23: nervous-system recovery wins over
            // muscle recovery. Fewer items on purpose (3-4 stretches,
            // not a full session) — the day is "mobility + walk".
            let target = max(3, min(4, requestedCount))
            return ReadinessAdjustment(
                replaceWithRecoveryDay: true,
                adjustedCount: target,
                allowsPrAttempt: false,
                bannerHeadline: "Recovery day — mobility + walk today",
                band: .red,
                source: snapshot.primarySource
            )

        case .yellow:
            // 0.9× volume cap, never below the minimum 3 exercises
            // (Fitness Expert invariant #17).
            let capped = Int(ceil(Double(requestedCount) * 0.9))
            let adjusted = max(3, capped)
            return ReadinessAdjustment(
                replaceWithRecoveryDay: false,
                adjustedCount: adjusted,
                allowsPrAttempt: false,
                bannerHeadline: "Listen to your body — keep the last rep in the tank",
                band: .yellow,
                source: snapshot.primarySource
            )

        case .green:
            // No count change at the top (Fitness Expert safety: we
            // don't let the engine blast beyond user's selected count).
            // The +10% ceiling is applied per-exercise inside selection
            // later; here we just flag PR intent.
            return ReadinessAdjustment(
                replaceWithRecoveryDay: false,
                adjustedCount: requestedCount,
                allowsPrAttempt: true,
                bannerHeadline: "Primed for a PR attempt today",
                band: .green,
                source: snapshot.primarySource
            )
        }
    }

    // MARK: - Recovery day builder

    /// Pull up to `count` stretches / yoga / mobility exercises from
    /// the local library. Matches the Fitness Expert invariant #23
    /// "stretching / mobility / walking / yoga" rule — we filter
    /// `Exercise.workoutType` for `stretch` variants (same contract
    /// as `StretchModeView`).
    ///
    /// Returns an empty array only when the library is cold (pre-warm
    /// still running). Callers MUST fall back to normal generation
    /// in that case to avoid showing a blank workout.
    static func buildRecoveryDayExercises(count: Int) -> [Exercise] {
        let all = ExerciseLibraryService.shared.getAllExercises()
        guard !all.isEmpty else { return [] }

        let stretches = all.filter { exercise in
            let workoutType = (exercise.workoutType ?? "").lowercased()
            let category = (exercise.category ?? "").lowercased()
            let name = (exercise.name ?? "").lowercased()
            // Primary signal: workoutType = "Stretch" / "Stretching".
            // Secondary signals: category or name contains "stretch" /
            // "yoga" / "mobility" so we catch exercises that haven't
            // had workoutType populated yet (same fallback
            // StretchModeView uses in its client-side path).
            return workoutType.contains("stretch")
                || category.contains("stretch")
                || name.contains("stretch")
                || name.contains("yoga")
                || name.contains("mobility")
                || name.contains("foam roll")
        }

        guard !stretches.isEmpty else { return [] }

        // Bucket by muscle region so the recovery session hits the
        // whole body (not 4 variations of the same stretch). Core
        // Data `Exercise` stores muscles in the `muscleGroups`
        // transformable array (not a scalar `primaryMuscle`) — first
        // entry is the primary.
        var buckets: [String: [Exercise]] = [:]
        for exercise in stretches {
            let muscles = (exercise.muscleGroups as? [String]) ?? []
            let primary = (muscles.first ?? exercise.category ?? "general").lowercased()
            buckets[primary, default: []].append(exercise)
        }

        var selected: [Exercise] = []
        let targetCount = max(3, min(4, count))
        // Round-robin across buckets for variety.
        var bucketKeys = Array(buckets.keys).shuffled()
        while selected.count < targetCount, !bucketKeys.isEmpty {
            let key = bucketKeys.removeFirst()
            if let pick = buckets[key]?.shuffled().first {
                selected.append(pick)
            }
        }

        // Top-up from the full stretches pool if we didn't hit the
        // target (small libraries / bucket starvation).
        if selected.count < targetCount {
            let remainingPool = stretches.filter { candidate in
                !selected.contains(where: { $0.objectID == candidate.objectID })
            }.shuffled()
            for candidate in remainingPool {
                selected.append(candidate)
                if selected.count >= targetCount { break }
            }
        }

        AppLogger.info(
            "[Readiness] Built recovery day with \(selected.count) mobility/stretch exercises",
            category: .workout
        )
        return selected
    }
}
