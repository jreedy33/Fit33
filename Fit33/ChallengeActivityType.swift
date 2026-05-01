//
//  ChallengeActivityType.swift
//  Fit33
//
//  Extracted 2026-08-11 from `ChallengeCreationFlow.swift` (now deleted).
//
//  Four small types used by the active challenge-creation flows
//  (`ChallengeFlowStartView`, `PrivateChallengeCreationFlow`,
//   `CommunityCreateChallengeView`) and read across the dashboard /
//   widget / reactions surfaces:
//
//    • `ChallengeMode` — Accountability ("we're in this together",
//      🤝 prefix) vs Competition ("only one can win", ⚔️ prefix). Mode
//      is encoded in the challenge TITLE PREFIX (no DB column) — every
//      reader uses `ChallengeMode.from(title:)` to detect it. This is
//      the contract that lets the iOS widget extension read mode
//      without a DB schema dependency (see `WidgetSupabaseFetcher`).
//      Adding a new mode = (a) new emoji prefix, (b) update `from(title:)`
//      detection, (c) update every existing title-emitter
//      (`ChallengeService.create…`, private + community equivalents).
//
//    • `ChallengeActivityType` — the activity-tile choice in the picker
//      (Walk / Run / Lift / Steps / Hydrate / Calories / Protein /
//       Active Minutes / Workout Streak / Sleep). NOT the same as
//      `ChallengeType` — the latter is the wire-format string raw value
//      stored on `group_challenges.challenge_type`. The two enums are
//      mapped 1:1 inside the `submitChallenge` flows. When adding a new
//      `ChallengeType` case (cycling / swim / stairs / totalVolume /
//       mindBody), surface it here ONLY when you also extend the picker
//      UI in ChallengeFlowStartView.
//
//    • `ChallengeOption` — a preset target row inside the activity step
//      ("10K Steps Daily" / "Custom"). Identifiable by a composite key
//      so multiple "10K"-named presets across activities don't collide.
//
//    • `HydrationUnit` — ml / oz toggle for the hydration challenge step.
//
//  Why a standalone file: `ChallengeCreationFlow.swift` was a 1,378-line
//  legacy view that's no longer routed in the dashboard (replaced by
//  `ChallengeFlowStartView`). Deleting it would have removed three types
//  still referenced by three live views. Extracting them here lets us
//  delete the dead view without breaking the live ones.

import SwiftUI

// MARK: - Challenge Mode
//
// Encoded in the challenge TITLE PREFIX (no DB column). Every reader
// — dashboard, widget extension, reactions composer, friends tab —
// uses `ChallengeMode.from(title:)` to detect mode at render time.
// Adding a new mode requires updating both `titlePrefix` (the writer)
// and `from(title:)` (the reader) in the same edit.
enum ChallengeMode: String, CaseIterable {
    case accountability = "Accountability"
    case competition = "Competition"

    var title: String {
        switch self {
        case .accountability: return "Accountability Buddy"
        case .competition: return "Head-to-Head Battle"
        }
    }

    var subtitle: String {
        switch self {
        case .accountability: return "We're in this together"
        case .competition: return "Only one can win"
        }
    }

    var description: String {
        switch self {
        case .accountability:
            return "Same goal. Same grind. You both commit to hitting the target every day — and keep each other honest. No scores, no losers. Just a shared streak you build together."
        case .competition:
            return "Go head-to-head. Every step, rep, and drop counts. One scoreboard, one winner, and permanent bragging rights."
        }
    }

    var emoji: String {
        switch self {
        case .accountability: return "🤝"
        case .competition: return "⚔️"
        }
    }

    /// Prefix embedded in challenge title so the widget can detect mode
    /// without a DB column round-trip (see `WidgetSupabaseFetcher`).
    var titlePrefix: String {
        switch self {
        case .accountability: return "🤝"
        case .competition: return "⚔️"
        }
    }

    var gradientColors: [Color] {
        switch self {
        case .accountability: return [.blue, .cyan]
        case .competition: return [.orange, .red]
        }
    }

    var accentColor: Color {
        switch self {
        case .accountability: return .cyan
        case .competition: return .orange
        }
    }

    /// Detect mode from a challenge title prefix. Legacy challenges
    /// (created before the prefix convention) default to competition —
    /// keeping the original behavior so old data still renders.
    static func from(title: String) -> ChallengeMode {
        if title.hasPrefix("🤝") { return .accountability }
        if title.hasPrefix("⚔️") { return .competition }
        return .competition
    }
}

// MARK: - Challenge Activity Type
enum ChallengeActivityType: String, CaseIterable {
    case walk = "Walk"
    case run = "Run"
    case lift = "Lift"
    case hydrate = "Hydrate"
    case steps = "Steps"
    case calories = "Calories"
    case protein = "Protein"
    case activeMinutes = "Active Minutes"
    case workoutStreak = "Workout Streak"
    case sleep = "Sleep"

    var emoji: String {
        switch self {
        case .walk: return "🚶"
        case .run: return "🏃"
        case .lift: return "💪"
        case .hydrate: return "💧"
        case .steps: return "👣"
        case .calories: return "🔥"
        case .protein: return "🥩"
        case .activeMinutes: return "⏱️"
        case .workoutStreak: return "🔥"
        case .sleep: return "😴"
        }
    }

    var gradientColors: [Color] {
        switch self {
        case .walk: return [.green, .mint]
        case .run: return [.orange, .yellow]
        case .lift: return [.red, .pink]
        case .hydrate: return [.blue, .cyan]
        case .steps: return [.purple, .blue]
        case .calories: return [.orange, .red]
        case .protein: return [.pink, .purple]
        case .activeMinutes: return [.cyan, .blue]
        case .workoutStreak: return [.red, .orange]
        case .sleep: return [.indigo, .purple]
        }
    }
}

// MARK: - Challenge Option
struct ChallengeOption: Identifiable {
    var id: String { "\(title)-\(dailyTarget)-\(unit)-\(isCustom)" }
    let title: String
    let description: String
    let dailyTarget: Int
    let unit: String
    let isPreset: Bool
    let isCustom: Bool
}

// MARK: - Hydration Unit
enum HydrationUnit: String, CaseIterable {
    case ml = "ml"
    case oz = "oz"

    var displayName: String {
        switch self {
        case .ml: return "Milliliters (ml)"
        case .oz: return "Ounces (oz)"
        }
    }

    func convert(value: Int, to targetUnit: HydrationUnit) -> Int {
        if self == targetUnit { return value }

        switch (self, targetUnit) {
        case (.ml, .oz): return Int(Double(value) / 29.5735)
        case (.oz, .ml): return Int(Double(value) * 29.5735)
        default: return value
        }
    }
}
