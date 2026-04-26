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

enum DailyGoalsWidgetSnapshot {
    static let appGroupID = "group.com.fit33.app"
    static let goalsKey = "fit33.widget.dailyGoals.v1"
    static let updatedAtKey = "fit33.widget.dailyGoals.updatedAt"
    static let bonusXpKey = "fit33.widget.dailyGoals.bonusXp"
    static let allCompleteKey = "fit33.widget.dailyGoals.allComplete"

    struct WidgetDailyGoal: Codable, Hashable {
        let title: String
        let icon: String
        let category: String
        let currentValue: Int
        let targetValue: Int
        let targetUnit: String
        let isCompleted: Bool
        let funLabel: String?

        var progress: Double {
            guard targetValue > 0 else { return isCompleted ? 1 : 0 }
            return min(Double(currentValue) / Double(targetValue), 1.0)
        }

        /// Short progress label e.g. "3,200 / 5,000 steps", "1/1", "✓".
        var progressLabel: String {
            if isCompleted { return "Done" }
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            let current = formatter.string(from: NSNumber(value: currentValue)) ?? "\(currentValue)"
            let target = formatter.string(from: NSNumber(value: targetValue)) ?? "\(targetValue)"
            if targetValue <= 1 {
                return "Tap in app"
            }
            return "\(current) / \(target)"
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
                    funLabel: "💪 Just show up"
                ),
                WidgetDailyGoal(
                    title: "Halfway There",
                    icon: "figure.walk.motion",
                    category: "steps",
                    currentValue: 0, targetValue: 5000,
                    targetUnit: "steps",
                    isCompleted: false,
                    funLabel: "👟 Solid effort"
                ),
                WidgetDailyGoal(
                    title: "Breakfast Check-in",
                    icon: "sunrise.fill",
                    category: "nutrition",
                    currentValue: 0, targetValue: 1,
                    targetUnit: "meal",
                    isCompleted: false,
                    funLabel: "🌅 Morning fuel"
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
