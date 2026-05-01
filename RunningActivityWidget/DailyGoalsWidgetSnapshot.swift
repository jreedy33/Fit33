//
//  DailyGoalsWidgetSnapshot.swift
//  RunningActivityWidget
//
//  Widget-side mirror of `Fit33/DailyGoalsWidgetBridge.swift`. Reads the
//  slim payload the main app publishes to the shared App Group whenever
//  daily quests change, so the widget can render the user's current
//  three goals without reaching for the network.
//
//  Keep `WidgetDailyGoal` in sync with the main-app copy.
//

import Foundation
import SwiftUI

enum DailyGoalsWidgetSnapshot {
    static let appGroupID = "group.com.fit33.app"
    static let goalsKey = "fit33.widget.dailyGoals.v1"
    static let updatedAtKey = "fit33.widget.dailyGoals.updatedAt"
    static let bonusXpKey = "fit33.widget.dailyGoals.bonusXp"
    static let allCompleteKey = "fit33.widget.dailyGoals.allComplete"

    /// Slim widget-only model. New fields are Optional so a stale payload
    /// from an older app build still decodes cleanly into placeholder-ish
    /// values until the main app launches and re-publishes.
    struct WidgetDailyGoal: Codable, Hashable {
        let title: String
        let icon: String
        let category: String
        let currentValue: Int
        let targetValue: Int
        let targetUnit: String
        let isCompleted: Bool
        let funLabel: String?
        let description: String?
        let xpReward: Int?
        let difficulty: String?

        var progress: Double {
            guard targetValue > 0 else { return isCompleted ? 1 : 0 }
            return min(Double(currentValue) / Double(targetValue), 1.0)
        }

        /// Mirror of `DailyQuest.categoryEmoji` in the main app — delegates
        /// to `QuestEmojiResolver` so widget cards show the same smart,
        /// content-aware emoji as in-app cards (e.g. "Heart Health" → ❤️,
        /// "Strawberry Smoothie" → 🍓, "Drink 8 Glasses of Water" → 🚰).
        ///
        /// `quest_key` isn't part of the widget snapshot today (we'd have to
        /// bump the App Group payload version to add it). Until that ship,
        /// the resolver falls back to the keyword scan + funLabel/category
        /// path, which already covers the seeded server templates well.
        var categoryEmoji: String {
            QuestEmojiResolver.resolve(
                questKey: "",
                title: title,
                description: description ?? "",
                category: category,
                funLabel: funLabel
            )
        }

        /// Mirror of `DailyQuest.categoryColor` — drives the progress ring,
        /// progress bar, and card stroke gradient.
        var categoryColor: Color {
            switch category {
            case "workout":   return .blue
            case "nutrition": return .green
            case "social":    return .purple
            case "steps":     return .cyan
            case "tracking":  return .indigo
            case "wildcard":  return .orange
            case "reward":    return .yellow
            default:          return .cyan
            }
        }

        /// Live-progress label that mirrors `DailyQuestsWidget.liveProgressLabel`
        /// in the app — formats steps as "3.2k / 10K steps", workouts as
        /// "0/1 workout", glasses, sets, etc. Falls back to a generic
        /// "current/target unit" string for unknown units.
        var progressLabel: String {
            if isCompleted { return "Done" }
            switch targetUnit {
            case "steps":
                if targetValue >= 1000 {
                    let targetK = Double(targetValue) / 1000.0
                    if currentValue >= 1000 {
                        let currentK = Double(currentValue) / 1000.0
                        return String(format: "%.1fk / %.0fK steps", currentK, targetK)
                    }
                    return String(format: "%d / %.0fK steps", currentValue, targetK)
                }
                return "\(currentValue)/\(targetValue) steps"
            case "glasses":
                return "\(currentValue)/\(targetValue) glasses"
            case "sets":
                return "\(currentValue)/\(targetValue) sets"
            case "meals", "meal":
                return "\(currentValue)/\(targetValue) \(targetValue == 1 ? "meal" : "meals")"
            case "workouts", "workout":
                return "\(currentValue)/\(targetValue) \(targetValue == 1 ? "workout" : "workouts")"
            case "minutes":
                return "\(currentValue)/\(targetValue) min"
            case "goal":
                return currentValue >= targetValue ? "Goal hit!" : "Not yet"
            case "videos":
                return "\(currentValue)/\(targetValue) \(targetValue == 1 ? "video" : "videos")"
            default:
                if targetValue <= 1 {
                    return isCompleted ? "Done" : "Tap in app"
                }
                return "\(currentValue)/\(targetValue) \(targetUnit)"
            }
        }
    }

    struct Snapshot {
        let goals: [WidgetDailyGoal]
        let allComplete: Bool
        let bonusXp: Int
        let updatedAt: Date?

        static let placeholder = Snapshot(
            goals: [
                WidgetDailyGoal(
                    title: "Crush a Workout",
                    icon: "dumbbell.fill",
                    category: "workout",
                    currentValue: 0, targetValue: 1,
                    targetUnit: "workout",
                    isCompleted: false,
                    funLabel: "💪 Just show up",
                    description: "Finish any workout today",
                    xpReward: 30,
                    difficulty: "easy"
                ),
                WidgetDailyGoal(
                    title: "Halfway There",
                    icon: "figure.walk.motion",
                    category: "steps",
                    currentValue: 3200, targetValue: 5000,
                    targetUnit: "steps",
                    isCompleted: false,
                    funLabel: "👟 Solid effort",
                    description: "3.2K of 5K steps",
                    xpReward: 25,
                    difficulty: "easy"
                ),
                WidgetDailyGoal(
                    title: "Breakfast Check-in",
                    icon: "sunrise.fill",
                    category: "nutrition",
                    currentValue: 0, targetValue: 1,
                    targetUnit: "meal",
                    isCompleted: false,
                    funLabel: "🌅 Morning fuel",
                    description: "Log your breakfast",
                    xpReward: 20,
                    difficulty: "easy"
                )
            ],
            allComplete: false,
            bonusXp: 50,
            updatedAt: nil
        )
    }

    /// Reads the latest published snapshot from the App Group. Falls back
    /// to a sensible placeholder when the app group isn't configured or
    /// the user hasn't opened the app yet today.
    static func read() -> Snapshot {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: goalsKey),
              let goals = try? JSONDecoder().decode([WidgetDailyGoal].self, from: data),
              !goals.isEmpty else {
            return .placeholder
        }
        return Snapshot(
            goals: goals,
            allComplete: defaults.bool(forKey: allCompleteKey),
            bonusXp: defaults.integer(forKey: bonusXpKey),
            updatedAt: defaults.object(forKey: updatedAtKey) as? Date
        )
    }
}
