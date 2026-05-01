//
//  ChallengeActivityType.swift
//  Fit33
//
//  Extracted 2026-08-11 from `ChallengeCreationFlow.swift` (now deleted).
//
//  Three small types used by the active challenge-creation flows
//  (`ChallengeFlowStartView`, `PrivateChallengeCreationFlow`,
//   `CommunityCreateChallengeView`):
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
