//
//  TabHeaderInsightProvider.swift
//  Fit33
//
//  Per-tab one-line "sub-brief" copy that sits under the page title on the
//  Exercises, Nutrition, and Friends tabs. Mirrors the Workout tab's
//  `headerSubBriefCopy` pattern (`WorkoutTabView.headerSubBriefCopy`) so
//  every main tab shares the same alive-feeling rhythm.
//
//  The helpers are pure & synchronous — they read from already-loaded state
//  (Core Data fetch results, `MealService.shared.todaysMeals`,
//  `FriendService.shared`, `ActivityFeedService.shared.activities`) and never
//  fire network requests. Callers re-evaluate the computed string on every
//  render; copy is stable within a state context but rotates as the user's
//  data evolves through the day (last workout, meals logged, friend activity).
//

import Foundation
import CoreData

@MainActor
enum TabHeaderInsightProvider {

    // MARK: - Exercises tab

    /// Sub-brief for the Exercises (library) tab. Rotates on:
    /// - days since last workout (idle nudge)
    /// - last completed workout's `name` keyword (suggests the next muscle
    ///   group so the user feels guided through a balanced rotation)
    /// - new-user empty state.
    static func exercisesSubBrief(recentWorkouts: [Workout]) -> String {
        let calendar = Calendar.current
        let now = Date()

        guard let last = recentWorkouts.first(where: { $0.isCompleted }),
              let lastDate = last.date else {
            return rotate([
                "Browse the library and pick your first lift.",
                "Start with the basics — compound lifts.",
                "Find an exercise that fits your goal."
            ])
        }

        let daysSince = calendar.dateComponents([.day],
                                                from: calendar.startOfDay(for: lastDate),
                                                to: calendar.startOfDay(for: now)).day ?? 0

        if daysSince >= 4 {
            return "It's been \(daysSince) days — let's break the slump."
        }
        if daysSince == 3 {
            return "3 days off — pick something quick today."
        }

        let recentName = (last.name ?? "").lowercased()

        // Suggest the opposite/next muscle group so the rotation stays balanced.
        if recentName.contains("leg") || recentName.contains("quad") ||
           recentName.contains("glute") || recentName.contains("lower") {
            return rotate([
                "You're due for upper body — grab some pulls.",
                "Rotate to chest and back today.",
                "Upper body's calling — bench or row."
            ])
        }
        if recentName.contains("push") || recentName.contains("chest") {
            return rotate([
                "You're due for back — keep that posture strong.",
                "Pull day next — rows and lat work.",
                "Hit your pulls to balance yesterday's push."
            ])
        }
        if recentName.contains("pull") || recentName.contains("back") {
            return rotate([
                "Push day's up — chest, shoulders, triceps.",
                "Time to push — bench and overhead press.",
                "Balance the pull with some pressing."
            ])
        }
        if recentName.contains("upper") {
            return "You're due for leg day."
        }
        if recentName.contains("arm") || recentName.contains("bicep") || recentName.contains("tricep") {
            return rotate([
                "Hit a compound today — squat, bench, or row.",
                "Big lifts next — give the arms a rest.",
                "Compound day — focus on the basics."
            ])
        }
        if recentName.contains("shoulder") || recentName.contains("delt") {
            return "Lock in legs or back to balance the volume."
        }

        // Generic post-workout state — yesterday counted, what's next?
        if daysSince == 0 {
            return rotate([
                "Solid lift today. Browse for tomorrow's session.",
                "Plan tomorrow's workout while it's fresh.",
                "Save a favorite for next time."
            ])
        }
        return rotate([
            "Yesterday was solid — keep the rhythm going.",
            "Browse a new variation to keep things fresh.",
            "Try a finisher to round out the week.",
            "Pick something new — no two weeks the same."
        ])
    }

    // MARK: - Nutrition tab

    /// Sub-brief for the Nutrition (meals) tab. Rotates on:
    /// - meals logged so far today (empty → "log breakfast")
    /// - protein gap vs goal (low protein → grilled chicken nudge)
    /// - calorie pacing (under/over)
    /// - hour-of-day fallbacks
    static func nutritionSubBrief(
        consumedProtein: Int,
        proteinGoal: Int,
        consumedCalories: Int,
        calorieGoal: Int,
        mealCount: Int
    ) -> String {
        let hour = Calendar.current.component(.hour, from: Date())

        if mealCount == 0 {
            if hour < 11 { return "Log breakfast — start the day fueled." }
            if hour < 14 { return "Lunch time — log it before you forget." }
            if hour < 18 { return "Snack or dinner? Log it to stay on track." }
            return "End the day strong — log dinner."
        }

        let proteinPct = proteinGoal > 0 ? Double(consumedProtein) / Double(proteinGoal) : 0
        let proteinRemaining = max(0, proteinGoal - consumedProtein)

        if proteinPct < 0.4 && hour >= 13 {
            return rotate([
                "Protein is low — grab some grilled chicken.",
                "Need protein — Greek yogurt or eggs.",
                "Boost protein with a quick shake."
            ])
        }
        if proteinPct < 0.7 && hour >= 18 && proteinRemaining > 0 {
            return "Need \(proteinRemaining)g more protein — try a shake or yogurt."
        }
        if proteinPct >= 1.0 {
            return rotate([
                "Protein goal hit — stay hydrated.",
                "Macros locked in. Now hit the water.",
                "Crushing it today. Don't forget veggies."
            ])
        }

        let caloriesPct = calorieGoal > 0 ? Double(consumedCalories) / Double(calorieGoal) : 0
        if caloriesPct > 1.15 {
            return "Calories over target — keep it lighter tonight."
        }
        if caloriesPct < 0.4 && hour >= 16 {
            return "You've barely eaten — fuel up for recovery."
        }

        return rotate([
            "Steady macros — keep building the habit.",
            "Halfway there — finish strong.",
            "Hydrate and lean into protein next.",
            "On pace — pick a clean snack next."
        ])
    }

    // MARK: - Friends tab

    /// Sub-brief for the Friends tab. Priority order:
    /// 1. No friends → onboarding nudge
    /// 2. Pending requests → action nudge
    /// 3. Recent friend activity (last 24h) → personalized challenge prompt
    /// 4. Quiet feed → outreach rotation
    static func friendsSubBrief(
        friendsCount: Int,
        pendingRequestCount: Int,
        recentActivities: [FriendActivity]
    ) -> String {
        if friendsCount == 0 {
            return rotate([
                "No friends yet — find your training partner.",
                "Add a friend to unlock head-to-head challenges.",
                "Training is better with a teammate — invite one."
            ])
        }

        if pendingRequestCount == 1 {
            return "You have a friend request — accept it!"
        }
        if pendingRequestCount > 1 {
            return "\(pendingRequestCount) friend requests waiting."
        }

        let now = Date()
        let recent = recentActivities.first { activity in
            guard let date = ISO8601Parser.parse(activity.createdAt) else { return false }
            return now.timeIntervalSince(date) < 86_400
        }

        if let activity = recent {
            let name = activity.firstName
            switch activity.activityType {
            case "workout_completed":
                let muscle = activity.metadata.muscleGroups?
                    .first?
                    .lowercased() ?? "workout"
                return "\(name) completed a \(muscle) workout — send a challenge."
            case "personal_record", "pr":
                return "\(name) just hit a PR — give 'em props."
            case "challenge_completed", "challenge_won":
                return "\(name) crushed a challenge. Your turn?"
            case "streak_milestone":
                return "\(name) is on a streak — match it."
            case "level_up":
                return "\(name) just leveled up — react to celebrate."
            default:
                return "\(name) is grinding — react to their post."
            }
        }

        return rotate([
            "Quiet feed — challenge a friend to wake it up.",
            "Start a head-to-head this week.",
            "Send a message — accountability beats willpower.",
            "Check on a friend's progress."
        ])
    }

    // MARK: - Helpers

    /// Deterministic daily-seeded rotation. Same option list + same calendar
    /// day → same pick (so the message is stable across re-renders within
    /// the day), but the variant rotates on different days so the header
    /// feels alive without flipping every frame.
    private static func rotate(_ options: [String]) -> String {
        guard !options.isEmpty else { return "" }
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        return options[day % options.count]
    }
}
