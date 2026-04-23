//
//  AdaptiveGoalService.swift
//  Fit33
//
//  Wearable Personalization Platform — Phase 3 (Adaptive Goals)
//
//  Reads pending weekly goal proposals from Supabase (written by the
//  nightly server job backed by `user_adaptive_goal_proposals`) and
//  exposes them to the Dashboard nudge card. Also provides local
//  computation helpers — a user can still see "proposed" values on
//  day 1 before the server rollup has run by computing them
//  client-side from the existing 28-day wearable cache.
//
//  Never auto-applies. Accept / decline is always an explicit user
//  action that writes back to the row.
//
//  Feature-flagged via `AppConfig.FeatureFlags.adaptiveGoals` —
//  service boots without touching network when the flag is off.
//

import Foundation
import Combine

// MARK: - Value types

/// One metric the service can propose a new value for.
enum AdaptiveGoalMetric: String, Codable, CaseIterable, Identifiable {
    case calorieGoal = "calorie_goal"
    case sleepGoal = "sleep_goal"
    case stepGoal = "step_goal"
    case weightPace = "weight_pace"
    case proteinGoal = "protein_goal"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .calorieGoal: return "Calories"
        case .sleepGoal: return "Sleep"
        case .stepGoal: return "Steps"
        case .weightPace: return "Weight pace"
        case .proteinGoal: return "Protein"
        }
    }

    var unitLabel: String {
        switch self {
        case .calorieGoal, .proteinGoal: return ""
        case .sleepGoal: return "h"
        case .stepGoal: return "steps"
        case .weightPace: return "lb / wk"
        }
    }

    var sfSymbol: String {
        switch self {
        case .calorieGoal: return "flame.fill"
        case .sleepGoal: return "bed.double.fill"
        case .stepGoal: return "figure.walk"
        case .weightPace: return "scalemass.fill"
        case .proteinGoal: return "leaf.fill"
        }
    }
}

/// Single proposal row. Mirrors `user_adaptive_goal_proposals` but
/// with the Swift-native enum. Local proposals (computed client-side
/// when the server hasn't run yet) share this shape and use
/// `id = UUID()` — no server round-trip.
struct AdaptiveGoalProposal: Codable, Equatable, Identifiable, Hashable {
    let id: UUID
    let metric: AdaptiveGoalMetric
    let currentValue: Double?
    let proposedValue: Double
    let rationale: String
    let weekOf: Date
    var accepted: Bool?

    /// Percent change relative to current (for the arrow badge).
    var percentChange: Double? {
        guard let current = currentValue, current != 0 else { return nil }
        return ((proposedValue - current) / current) * 100.0
    }

    /// Formatted proposed value for the card row.
    func formattedValue() -> String {
        switch metric {
        case .calorieGoal, .stepGoal, .proteinGoal:
            return "\(Int(proposedValue.rounded()))"
        case .sleepGoal:
            return String(format: "%.1f", proposedValue)
        case .weightPace:
            return String(format: "%.2f", proposedValue)
        }
    }
}

// MARK: - Service

@MainActor
final class AdaptiveGoalService: ObservableObject {
    static let shared = AdaptiveGoalService()

    @Published var pendingProposals: [AdaptiveGoalProposal] = []
    @Published var isLoading: Bool = false

    /// Last time we refreshed from server. Used to throttle.
    @Published var lastLoadedAt: Date?

    private static let loadThrottleInterval: TimeInterval = 300

    private init() {}

    // MARK: - Public API

    /// Refresh pending proposals from Supabase. No-op when the feature
    /// flag is off so the service adds zero network pressure in
    /// dark-ship mode.
    func refreshPendingProposals() async {
        guard AppConfig.FeatureFlags.adaptiveGoals else { return }
        guard SupabaseManager.shared.isAuthenticated else { return }

        if let last = lastLoadedAt,
           Date().timeIntervalSince(last) < Self.loadThrottleInterval {
            return
        }

        isLoading = true
        defer { isLoading = false }

        let rows = await SupabaseManager.shared.fetchPendingGoalProposals()
        pendingProposals = rows.compactMap { $0.toProposal() }
        lastLoadedAt = Date()
    }

    /// Persist the user's accept/decline decision for a proposal.
    /// Writes `accepted = true/false` and (for accept) `applied_at = now()`.
    /// On accept, the caller is responsible for propagating the new
    /// value into Core Data / user_profiles (UserManager.updateGoal(...)).
    func resolveProposal(_ proposal: AdaptiveGoalProposal, accepted: Bool) async {
        guard AppConfig.FeatureFlags.adaptiveGoals else { return }
        await SupabaseManager.shared.resolveGoalProposal(id: proposal.id, accepted: accepted)

        // Optimistic local removal — the view can refresh later.
        pendingProposals.removeAll { $0.id == proposal.id }
    }

    // MARK: - Local computation helpers
    //
    // Used by on-device UIs that want to show a "projected" proposal
    // before the server rollup has run. The nightly edge function
    // should perform the authoritative computation; these mirror the
    // formulas so copy stays consistent between the two sides.

    /// Step goal = 28-day p70 of delivered daily steps.
    static func proposeStepGoal(recentStepsPerDay: [Int]) -> Double? {
        guard recentStepsPerDay.count >= 10 else { return nil }
        let sorted = recentStepsPerDay.sorted()
        let idx = min(sorted.count - 1, Int(Double(sorted.count) * 0.70))
        return Double(sorted[idx])
    }

    /// Calorie goal = BMR × activityMultiplier, where activityMultiplier
    /// comes from the average daily active+resting calories burned by
    /// the wearable divided by BMR. Never drops below BMR × 1.2.
    static func proposeCalorieGoal(bmr: Double, avgDailyBurned: Double) -> Double {
        guard bmr > 0, avgDailyBurned > 0 else { return bmr * 1.4 }
        let multiplier = max(1.2, avgDailyBurned / bmr)
        return (bmr * multiplier).rounded()
    }

    /// Sleep goal = median sleep hours on days that preceded a PR / good
    /// workout. Caller supplies the "good-day" sleep samples.
    static func proposeSleepGoal(goodDaySleepHours: [Double]) -> Double? {
        guard goodDaySleepHours.count >= 5 else { return nil }
        let sorted = goodDaySleepHours.sorted()
        return sorted[sorted.count / 2]  // median
    }
}

// MARK: - SupabaseManager bridge (readiness + goals live in their extension files)

extension SupabaseManager {

    /// Fetch pending adaptive goal proposals for the signed-in user.
    /// Reads the `v_user_pending_goal_proposals` view (current week +
    /// accepted IS NULL).
    func fetchPendingGoalProposals() async -> [AdaptiveGoalRowEnvelope] {
        guard isAuthenticated, let userId = currentUser?.id else { return [] }

        do {
            let rows: [AdaptiveGoalRowEnvelope] = try await client
                .from("v_user_pending_goal_proposals")
                .select()
                .eq("user_id", value: userId.uuidString)
                .order("created_at", ascending: false)
                .limit(10)
                .execute()
                .value
            return rows
        } catch {
            NetworkErrorClassifier.log(
                error,
                context: "Failed to fetch adaptive goal proposals",
                category: .network,
                transientLevel: .debug
            )
            return []
        }
    }

    /// Mark a single proposal accepted/declined. `applied_at` only set
    /// when `accepted == true`.
    func resolveGoalProposal(id: UUID, accepted: Bool) async {
        guard isAuthenticated else { return }

        struct Patch: Encodable {
            let accepted: Bool
            let applied_at: String?
        }
        let patch = Patch(
            accepted: accepted,
            applied_at: accepted ? ISO8601DateFormatter().string(from: Date()) : nil
        )

        do {
            try await client
                .from("user_adaptive_goal_proposals")
                .update(patch)
                .eq("id", value: id.uuidString)
                .execute()
            AppLogger.debug("[AdaptiveGoal] Resolved proposal \(id) accepted=\(accepted)", category: .network)
        } catch {
            NetworkErrorClassifier.log(
                error,
                context: "Failed to resolve goal proposal",
                category: .network,
                transientLevel: .debug
            )
        }
    }
}

// MARK: - Supabase row envelope

/// Codable row shape — shared between `SupabaseManager` extension and
/// the service. Kept at file scope (not nested inside the service)
/// so the extension method can reference it without an access-level
/// dance.
struct AdaptiveGoalRowEnvelope: Codable {
    let id: UUID
    let metric: String
    let currentValue: Double?
    let proposedValue: Double
    let rationale: String
    let weekOf: String
    let accepted: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case metric
        case currentValue = "current_value"
        case proposedValue = "proposed_value"
        case rationale
        case weekOf = "week_of"
        case accepted
    }

    func toProposal() -> AdaptiveGoalProposal? {
        guard let metric = AdaptiveGoalMetric(rawValue: metric) else { return nil }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        f.locale = Locale(identifier: "en_US_POSIX")
        let week = f.date(from: weekOf) ?? Date()
        return AdaptiveGoalProposal(
            id: id,
            metric: metric,
            currentValue: currentValue,
            proposedValue: proposedValue,
            rationale: rationale,
            weekOf: week,
            accepted: accepted
        )
    }
}
