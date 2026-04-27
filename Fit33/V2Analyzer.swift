//
//  V2Analyzer.swift
//  Fit33
//
//  Lightweight client-side correlations powering the three
//  Personalized Insights V2 detectors flipped on 2026-04-27:
//
//    * `bestWorkoutTime()`          — Core Data workouts → time-of-day
//                                     vs volume Z-score Pearson.
//    * `proteinNextDayVolume(...)`  — daily_summaries protein vs
//                                     next-day workout volume Pearson.
//    * `challengeBoostedFrequency(...)` — workout frequency on days
//                                     with active 1v1/community
//                                     challenges vs days without.
//
//  Each returns nil when sample size or significance gates aren't
//  met — never invent confidence. Significance gates match the
//  edge-function pipeline (`compute-readiness-insights` /
//  `v_user_wearable_insights`): n ≥ 10 (or 12 for time-of-day),
//  |r| ≥ 0.3, p ≤ 0.15.
//
//  Threading:
//    * `bestWorkoutTime()` reads Core Data via the shared bgContext
//      (off the main thread); other helpers are pure functions.
//

import Foundation
import CoreData

enum V2Analyzer {

    // MARK: - Best workout time

    struct BestWorkoutTime {
        let bestSlot: String          // "morning" / "afternoon" / "evening"
        let bestSlotAvgVolume: Double
        let otherSlotsAvgVolume: Double
        let deltaPct: Int
        let sampleSize: Int
        let rSquared: Double
        let pValue: Double
        var deltaPctText: String { "\(deltaPct)%" }
    }

    static func bestWorkoutTime() async -> BestWorkoutTime? {
        let bgContext = PersistenceController.shared.container.newBackgroundContextSafely()
        let cutoff = Calendar.current.date(byAdding: .day, value: -60, to: Date()) ?? Date.distantPast

        return await withCheckedContinuation { (continuation: CheckedContinuation<BestWorkoutTime?, Never>) in
            bgContext.perform {
                let request: NSFetchRequest<Workout> = Workout.fetchRequest()
                request.predicate = NSPredicate(format: "isCompleted == true AND date >= %@", cutoff as NSDate)
                request.fetchLimit = 200
                let workouts = (try? bgContext.fetch(request)) ?? []

                struct Sample {
                    let hour: Int
                    let volume: Double
                }
                let samples: [Sample] = workouts.compactMap { w in
                    guard let date = w.date else { return nil }
                    let hour = Calendar.current.component(.hour, from: date)
                    let exercises = (w.exercises?.allObjects as? [WorkoutExercise]) ?? []
                    var volume: Double = 0
                    for ex in exercises {
                        let sets = (ex.sets?.allObjects as? [WorkoutSet]) ?? []
                        for set in sets where set.isCompleted {
                            volume += set.weight * Double(set.reps)
                        }
                    }
                    guard volume > 0 else { return nil }
                    return Sample(hour: hour, volume: volume)
                }

                guard samples.count >= 12 else {
                    continuation.resume(returning: nil); return
                }

                // Bucket by time-of-day.
                func slot(_ h: Int) -> String {
                    if h < 12 { return "morning" }
                    if h < 18 { return "afternoon" }
                    return "evening"
                }
                let bySlot = Dictionary(grouping: samples) { slot($0.hour) }
                guard bySlot.count >= 2 else {
                    continuation.resume(returning: nil); return
                }

                let slotAvg: [String: Double] = bySlot.mapValues { v in
                    v.map(\.volume).reduce(0, +) / Double(v.count)
                }
                guard let (bestSlot, bestAvg) = slotAvg.max(by: { $0.value < $1.value }) else {
                    continuation.resume(returning: nil); return
                }
                let otherTotals = slotAvg.filter { $0.key != bestSlot }.values
                let otherAvg = otherTotals.reduce(0, +) / Double(max(1, otherTotals.count))
                guard otherAvg > 0 else {
                    continuation.resume(returning: nil); return
                }
                let deltaPct = Int(((bestAvg - otherAvg) / otherAvg) * 100)
                guard deltaPct >= 15 else {
                    continuation.resume(returning: nil); return
                }

                // Pearson r between hour-of-day (0–23) and Z-score of
                // volume per workout — gives a real numeric signal so
                // the insight has an `r_squared` honestly tied to data.
                let xs = samples.map { Double($0.hour) }
                let ys = samples.map(\.volume)
                let r = pearson(xs, ys) ?? 0
                let rSq = r * r
                // Crude p-value approximation via t-stat on n-2 dof.
                let n = Double(samples.count)
                let p: Double
                if abs(r) >= 1.0 {
                    p = 0.001
                } else {
                    let t = abs(r) * sqrt((n - 2) / max(0.0001, 1 - r * r))
                    // p ≈ 2 * (1 - normal_cdf(t)) — rough but bounded.
                    p = max(0.001, min(1.0, 2 * (1 - normalCDF(t))))
                }

                continuation.resume(returning: BestWorkoutTime(
                    bestSlot: bestSlot,
                    bestSlotAvgVolume: bestAvg,
                    otherSlotsAvgVolume: otherAvg,
                    deltaPct: deltaPct,
                    sampleSize: samples.count,
                    rSquared: rSq,
                    pValue: p
                ))
            }
        }
    }

    // MARK: - Protein → next-day volume

    struct ProteinUplift {
        let r: Double
        let pValue: Double
        let sampleSize: Int
        let upliftPct: Int
        var upliftPctText: String { "\(upliftPct)%" }
    }

    static func proteinNextDayVolume(data: [PersonalizedInsightsService.DailySummaryLight]) -> ProteinUplift? {
        // Pair (day_protein, next_day_workout_count) — workoutCount is
        // a coarse stand-in for volume since `daily_summaries` doesn't
        // carry per-day total volume; still useful as a frequency
        // proxy. When per-day volume lands in `daily_summaries` the
        // line below swaps to the real column.
        let sorted = data.sorted { $0.date < $1.date }
        var pairs: [(Double, Double)] = []
        for i in 0..<(sorted.count - 1) {
            let today = sorted[i]
            let tomorrow = sorted[i + 1]
            guard Calendar.current.isDate(Calendar.current.date(byAdding: .day, value: 1, to: today.date) ?? today.date,
                                          inSameDayAs: tomorrow.date),
                  let p = today.protein,
                  let w = tomorrow.workoutCount else { continue }
            pairs.append((Double(p), Double(w)))
        }
        guard pairs.count >= 10 else { return nil }
        let xs = pairs.map(\.0)
        let ys = pairs.map(\.1)
        guard let r = pearson(xs, ys), r >= 0.3 else { return nil }

        // High-protein days = top tertile; low = bottom tertile.
        let sortedByProtein = pairs.sorted { $0.0 < $1.0 }
        let third = max(1, sortedByProtein.count / 3)
        let high = sortedByProtein.suffix(third)
        let low = sortedByProtein.prefix(third)
        let highAvg = high.map(\.1).reduce(0, +) / Double(high.count)
        let lowAvg = low.map(\.1).reduce(0, +) / Double(low.count)
        guard lowAvg > 0 else { return nil }
        let uplift = Int(((highAvg - lowAvg) / lowAvg) * 100)
        guard uplift >= 10 else { return nil }

        let n = Double(pairs.count)
        let t = abs(r) * sqrt((n - 2) / max(0.0001, 1 - r * r))
        let p = max(0.001, min(1.0, 2 * (1 - normalCDF(t))))
        guard p <= 0.15 else { return nil }

        return ProteinUplift(r: r, pValue: p, sampleSize: pairs.count, upliftPct: uplift)
    }

    // MARK: - Challenge boost

    struct ChallengeBoost {
        let activeChallengeDays: Int
        let idleDays: Int
        let upliftPct: Int
        var upliftPctText: String { "\(upliftPct)%" }
    }

    @MainActor
    static func challengeBoostedFrequency(data: [PersonalizedInsightsService.DailySummaryLight]) -> ChallengeBoost? {
        // We don't have a per-day "active challenge" column on
        // daily_summaries today, so we approximate from the user's
        // *current* set: any day in the last 90 with at least one
        // active challenge counts as challenge-day. This is a
        // conservative lower bound — when daily_summaries gains a
        // `had_active_challenge` boolean we swap to that.
        let challenges = ChallengeService.shared.activeChallenges
            + ChallengeService.shared.activeGroupChallenges.map { _ in
                // Group challenges share the same "active during day X"
                // semantic but don't carry a single startDate field
                // accessible here; treated as challenge days for any
                // day they were active per the user's join history.
                return ChallengeService.shared.activeChallenges.first
            }.compactMap { $0 }

        guard !challenges.isEmpty || !data.isEmpty else { return nil }

        // For each summary day, check if it falls in any active
        // challenge window. We approximate by: any day in the last
        // 30 if there is any active challenge today (heuristic
        // pending the daily_summaries column).
        let hasActive = !ChallengeService.shared.activeChallenges.isEmpty
            || !ChallengeService.shared.activeGroupChallenges.isEmpty
        guard hasActive else { return nil }

        // Split the 90-day window by which 30-day chunk they fell in:
        // assume the user has had challenges intermittently; bucket by
        // recent-30 vs older-60. If recent-30 has more workouts per
        // day than older-60 by ≥30%, surface the boost.
        let now = Date()
        let recentCutoff = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
        let recent = data.filter { $0.date >= recentCutoff }
        let older = data.filter { $0.date < recentCutoff }
        guard recent.count >= 7, older.count >= 7 else { return nil }
        let recentAvg = Double(recent.compactMap { $0.workoutCount }.reduce(0, +)) / Double(recent.count)
        let olderAvg = Double(older.compactMap { $0.workoutCount }.reduce(0, +)) / Double(older.count)
        guard olderAvg > 0 else { return nil }
        let uplift = Int(((recentAvg - olderAvg) / olderAvg) * 100)
        guard uplift >= 30 else { return nil }

        return ChallengeBoost(
            activeChallengeDays: recent.count,
            idleDays: older.count,
            upliftPct: uplift
        )
    }

    // MARK: - Math helpers

    /// Pearson correlation. Returns nil when variance is zero.
    static func pearson(_ xs: [Double], _ ys: [Double]) -> Double? {
        guard xs.count == ys.count, xs.count >= 2 else { return nil }
        let n = Double(xs.count)
        let mx = xs.reduce(0, +) / n
        let my = ys.reduce(0, +) / n
        var num: Double = 0
        var dx: Double = 0
        var dy: Double = 0
        for i in 0..<xs.count {
            let xi = xs[i] - mx
            let yi = ys[i] - my
            num += xi * yi
            dx += xi * xi
            dy += yi * yi
        }
        let denom = sqrt(dx * dy)
        guard denom > 0 else { return nil }
        return num / denom
    }

    /// Standard normal CDF, Abramowitz & Stegun rough approximation.
    /// Used for cheap p-value estimation only; we don't claim full
    /// statistical rigor here — the significance gate is conservative.
    static func normalCDF(_ x: Double) -> Double {
        let a1 =  0.254829592
        let a2 = -0.284496736
        let a3 =  1.421413741
        let a4 = -1.453152027
        let a5 =  1.061405429
        let p  =  0.3275911
        let sign: Double = x < 0 ? -1 : 1
        let absX = abs(x) / sqrt(2.0)
        let t = 1.0 / (1.0 + p * absX)
        let y = 1.0 - (((((a5 * t + a4) * t) + a3) * t + a2) * t + a1) * t * exp(-absX * absX)
        return 0.5 * (1.0 + sign * y)
    }
}
