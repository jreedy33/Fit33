// ProgressFreshness.swift
// Realtime Widget Server Pull, Phase 6a (2026-04-26)
//
// Pure-Foundation freshness helpers for opponent / participant
// progress timestamps coming back from `get_active_challenges`'s
// new `my_last_progress_at` / `opponent_last_progress_at` columns.
//
// Used by the widget timeline and the in-app challenge UI to
// decide:
//   1. Whether a participant's progress value should be rendered
//      as-is (e.g. "8,432 steps") or as a stale-data placeholder
//      (e.g. "— · 4h ago").
//   2. What short relative-age label to show ("just now", "8m ago",
//      "yesterday").
//
// IMPORTANT: this file lives in `Fit33/` and is added to the main
// `Fit33` target via project.pbxproj. A byte-for-byte mirror lives
// at `RunningActivityWidget/ProgressFreshness.swift` so the widget
// extension (which uses Xcode's synchronized folder feature) can
// link the same logic without sharing module boundaries. If you
// edit this file, edit the mirror; the duplication is intentional
// per `codingrules.mdc` "no dependency surprises across targets".

import Foundation

/// Coarse buckets used to drive UI styling. Keep this enum in sync
/// with the widget mirror — render code matches on cases and any
/// drift will silently fall through to `.unknown` styling.
enum ProgressFreshness: Equatable {
    /// `< 30 minutes`. Treat as live. Show the raw value, no
    /// staleness indicator. This matches the widget pull cadence
    /// (~20-min timeline ticks) so any value the server has is
    /// guaranteed to be at least this fresh after one tick.
    case fresh

    /// `30 minutes – 2 hours`. Show the value but annotate with a
    /// subtle relative-age suffix ("8,432 · 47m"). The user is
    /// likely walking around; data should still be useful.
    case recent

    /// `2 hours – 24 hours`. Still TODAY's data — the value is the
    /// known total for today even if the opponent's phone hasn't
    /// uploaded a fresh sample in a couple hours. We show the raw
    /// value alongside a prominent age suffix ("4,674 · 2h ago")
    /// so the user knows it's a trailing number, not a hidden one.
    /// Hiding `2h-old today data` behind `—` was actively misleading
    /// — Abbie at 667 from 2h ago is NOT the "0 steps for a stepper"
    /// bug; that bug is `value == 0 && lastProgressAt is nil/old`.
    case stale

    /// `> 24 hours` OR `nil`. The last update is from a previous
    /// day (or we have no record at all). Render as `—` plus a
    /// "1d+ ago" / "yesterday" suffix and let `Phase 7` engagement
    /// nudges handle the "poke them" side. `nil` collapses here so
    /// a user who has NEVER logged progress in this challenge looks
    /// the same as one who's been gone for days — both warrant the
    /// "we genuinely don't know today's number" treatment.
    case unknown
}

/// Single source of truth for the freshness math + label
/// formatting. Pure function — no side effects, no logging — so
/// it's safe to call from a SwiftUI body or a TimelineProvider
/// without performance concerns.
enum ProgressFreshnessKit {

    /// Categorise a server-side progress timestamp into a
    /// `ProgressFreshness` bucket.
    ///
    /// - Parameters:
    ///   - lastProgressAt: the `my_last_progress_at` /
    ///     `opponent_last_progress_at` value from the RPC. May be
    ///     `nil` if the user has never logged progress for this
    ///     challenge — collapses to `.unknown`.
    ///   - now: injected wall clock for testability. Defaults to
    ///     `Date()`.
    /// - Returns: the bucket. Negative deltas (clock skew, server
    ///   timestamp slightly ahead of device clock) are treated as
    ///   `.fresh` rather than `.unknown`.
    static func freshness(
        for lastProgressAt: Date?,
        now: Date = Date()
    ) -> ProgressFreshness {
        guard let lastProgressAt else { return .unknown }
        let delta = now.timeIntervalSince(lastProgressAt)
        // Future timestamps from server clock skew are treated
        // as live — clamping to .fresh avoids a confusing "in 2s"
        // age label.
        if delta < 0 { return .fresh }
        switch delta {
        case ..<(30 * 60):                return .fresh
        case (30 * 60)..<(2 * 60 * 60):   return .recent
        case (2 * 60 * 60)..<(24 * 60 * 60): return .stale
        default:                          return .unknown
        }
    }

    /// Compact age label suitable for widget headers and inline
    /// challenge cards. Optimised for ≤6 characters so it fits in
    /// the small-widget width budget.
    ///
    ///   delta < 60s          → "just now"
    ///   delta < 60m          → "12m ago"
    ///   delta < 24h          → "4h ago"
    ///   delta < 48h          → "yesterday"
    ///   delta < 7d           → "3d ago"
    ///   else                 → "1w+ ago"
    ///
    /// Returns `nil` when `lastProgressAt` is `nil` so callers can
    /// branch on "never logged" cleanly. Keep this allocation-free
    /// where possible — called once per render frame per
    /// participant.
    static func ageLabel(
        for lastProgressAt: Date?,
        now: Date = Date()
    ) -> String? {
        guard let lastProgressAt else { return nil }
        let delta = max(0, now.timeIntervalSince(lastProgressAt))
        if delta < 60 { return "just now" }
        if delta < 60 * 60 {
            let minutes = Int(delta / 60)
            return "\(minutes)m ago"
        }
        if delta < 24 * 60 * 60 {
            let hours = Int(delta / 3600)
            return "\(hours)h ago"
        }
        if delta < 48 * 60 * 60 { return "yesterday" }
        if delta < 7 * 24 * 60 * 60 {
            let days = Int(delta / (24 * 3600))
            return "\(days)d ago"
        }
        return "1w+ ago"
    }

    /// Convenience: should the caller render the raw progress
    /// value, or substitute the `—` placeholder? Centralised so
    /// the widget and the in-app card never disagree.
    ///
    /// Rule (rev 2026-04-26): a non-`nil` `lastProgressAt` within the
    /// last 24 hours means the server's `today` value is genuinely
    /// today's known total — show it. A 2h-old `4,674` is real today
    /// progress, just trailing reality by a couple of hours; the age
    /// label gives the user the freshness context they need.
    /// Only `.unknown` (≥24h or never logged) collapses to `—`,
    /// because at that point the value is yesterday's residue or
    /// missing entirely.
    static func shouldShowRawValue(
        for lastProgressAt: Date?,
        now: Date = Date()
    ) -> Bool {
        switch freshness(for: lastProgressAt, now: now) {
        case .fresh, .recent, .stale: return true
        case .unknown: return false
        }
    }
}
