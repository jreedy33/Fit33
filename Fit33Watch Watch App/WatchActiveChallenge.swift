//
//  WatchActiveChallenge.swift
//  Fit33Watch
//
//  Watch UI Phase 1 (2026-04-26).
//
//  Slim Codable mirror of the subset of `get_active_challenges` RPC
//  columns the watch UI consumes. We deliberately decode only the
//  fields rendered by `WatchTodayView` and friends — the RPC returns
//  ~28 columns and decoding all of them on every refresh wastes
//  watch-extension CPU. Forward-compatible: extra columns ignored,
//  missing columns surface as decode errors.
//
//  Lives next to `WatchChallengeConfig` (the WCSession config-push
//  shape). Distinct types because the config push is the iPhone
//  telling us "these are the IDs to write to" while this is the
//  watch pulling Supabase directly to display progress.
//

import Foundation

/// Display shape the watch Today screen renders. Wire-format mirror
/// of the relevant `get_active_challenges` row columns.
struct WatchActiveChallenge: Identifiable, Equatable, Codable, Sendable {
    let id: String
    let title: String
    let challengeType: String
    let dailyTarget: Int?
    let targetUnit: String
    let daysRemaining: Int
    let myTodayProgress: Int
    let myCurrentStreak: Int
    let opponentName: String?
    let opponentTodayProgress: Int
    let amWinningToday: Bool
    let myLastProgressAt: Date?
    let opponentLastProgressAt: Date?

    /// Strip leading mode prefix + activity emoji so the watch shows
    /// "10K Steps" rather than "🤝 🚶 10000 Steps". Matches the
    /// iPhone/widget formatter so the same challenge looks the same
    /// everywhere.
    var displayTitle: String {
        var t = title
        for prefix in ["🤝 ", "⚔️ "] where t.hasPrefix(prefix) {
            t = String(t.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        while let first = t.unicodeScalars.first,
              first.properties.isEmoji && first.value > 0x238C {
            t = String(t.dropFirst()).trimmingCharacters(in: .whitespaces)
            if let next = t.unicodeScalars.first, next.value == 0xFE0F {
                t = String(t.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
        }
        return t.replacingOccurrences(
            of: #"\b(\d{1,})(000)\b"#,
            with: "$1K",
            options: .regularExpression
        )
    }
}
