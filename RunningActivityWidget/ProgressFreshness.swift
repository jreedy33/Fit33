// ProgressFreshness.swift (widget mirror)
// Realtime Widget Server Pull, Phase 6a (2026-04-26)
//
// IMPORTANT: this is a byte-for-byte mirror of
// `Fit33/ProgressFreshness.swift`. The widget extension uses
// Xcode's synchronized-folder feature for `RunningActivityWidget/`,
// so it can't easily share files with the main `Fit33` target.
// Duplicating the small pure-Foundation utility avoids cross-target
// module dances. If you edit one file, edit the other; the bridge
// header / interface stays identical (`ProgressFreshness` enum +
// `ProgressFreshnessKit` namespace).

import Foundation

/// Coarse buckets used to drive UI styling.
enum ProgressFreshness: Equatable {
    case fresh
    case recent
    case stale
    case unknown
}

enum ProgressFreshnessKit {

    static func freshness(
        for lastProgressAt: Date?,
        now: Date = Date()
    ) -> ProgressFreshness {
        guard let lastProgressAt else { return .unknown }
        let delta = now.timeIntervalSince(lastProgressAt)
        if delta < 0 { return .fresh }
        switch delta {
        case ..<(30 * 60):                return .fresh
        case (30 * 60)..<(2 * 60 * 60):   return .recent
        case (2 * 60 * 60)..<(24 * 60 * 60): return .stale
        default:                          return .unknown
        }
    }

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
