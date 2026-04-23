import Foundation

// MARK: - Bug Report State Snapshot — Provider Conformances (Phase 7)
//
// Central home for SnapshotProvider conformances on the app's core
// singletons. Kept in a single file so adding a new service to the
// snapshot is one extension + one line in `registerAll()`.
//
// Design notes:
//   - `WeightTrackingService`'s conformance lives in-file with the
//     service itself, because it reads a `private` property. All
//     other services have their snapshot data accessible via
//     published or computed properties, so the extension lives here.
//   - Every `contributeSnapshot()` is @MainActor — the snapshotter
//     calls them from main. Services that publish from non-main
//     contexts are fine to read here because we only read after
//     the `@Published` setter has landed.
//   - PII audit: never include email / phone / auth token / contact
//     names / raw device IDs. Triage server-side already joins
//     user_profiles for us.

// MARK: - Central registration

extension BugReportSnapshotter {
    /// Touch every singleton that contributes a snapshot. Called once
    /// from `buildSnapshot()` (idempotent; re-registering is cheap).
    /// Keeping registration central avoids editing every service's
    /// init and makes it trivial to audit which services contribute.
    @MainActor
    func registerAll() {
        register(WeightTrackingService.shared)
        register(HydrationService.shared)
        register(MealService.shared)
        register(UserManager.shared)
        register(PremiumManager.shared)
        register(DailyQuestService.shared)
        register(WorkoutManager.shared)
        // Wearable Personalization Platform (Phase 6) — readiness +
        // wearable-connection states in every shake report so "my
        // dashboard pill is stuck on yellow" triage is one snapshot.
        register(ReadinessService.shared)
    }
}

// MARK: - HydrationService
//
// Hydration is the sibling widget to Weight on the Dashboard, and the
// same class of sync bug could land here. Capture today's total, goal,
// log count + age so Claude can spot "I added water but the widget
// didn't update" without reading source files.

extension HydrationService: SnapshotProvider {
    var snapshotKey: String { "HydrationService" }

    @MainActor
    func contributeSnapshot() -> [String: SnapshotValue] {
        var v: [String: SnapshotValue] = [
            "todayLogs.count": .int(todayLogs.count),
            "recommendedGoalMl": .int(recommendedGoalMl),
            "isLoading": .bool(isLoading),
        ]
        if let summary = todaySummary {
            // HydrationDailySummary fields vary by version — read what we
            // know exists via reflection-free published getters. Surface
            // totalMl + goalMl + date as the minimum divergence diagnostic.
            v["todaySummary.totalMl"] = .int(summary.totalMl)
            v["todaySummary.goalMl"] = .int(summary.goalMl)
            v["todaySummary.date"] = .string(summary.date)
            v["todaySummary.percentComplete"] = .double(
                summary.goalMl > 0
                    ? Double(summary.totalMl) / Double(summary.goalMl)
                    : 0
            )
        } else {
            v["todaySummary"] = .null
        }
        if let first = todayLogs.first {
            v["todayLogs.first.amountMl"] = .int(first.amountMl)
            v["todayLogs.first.ageSeconds"] = .double(
                Date().timeIntervalSince(first.loggedAt)
            )
        }
        return v
    }
}

// MARK: - MealService

extension MealService: SnapshotProvider {
    var snapshotKey: String { "MealService" }

    @MainActor
    func contributeSnapshot() -> [String: SnapshotValue] {
        var v: [String: SnapshotValue] = [
            "todaysMeals.count": .int(todaysMeals.count),
            "isLoading": .bool(isLoading),
        ]
        // Collapse calories / protein / carbs / fat across today's meals
        // so Claude can spot "nutrition shows 0 despite logged meal".
        let totalCalories = todaysMeals.reduce(0) { $0 + $1.calories }
        let totalProtein = todaysMeals.reduce(0) { $0 + $1.protein }
        v["todaysMeals.totalCalories"] = .int(totalCalories)
        v["todaysMeals.totalProtein"] = .int(totalProtein)
        if let latest = todaysMeals.last {
            v["todaysMeals.latest.mealType"] = .string(latest.mealType.rawValue)
            v["todaysMeals.latest.ageSeconds"] = .double(
                Date().timeIntervalSince(latest.date)
            )
        }
        return v
    }
}

// MARK: - UserManager
//
// Exposes the scalar flags the app branches on (onboarding, verified,
// premium). Deliberately omits currentUser's name/email — server-side
// enrichment already joins user_profiles for Claude.

extension UserManager: SnapshotProvider {
    var snapshotKey: String { "UserManager" }

    @MainActor
    func contributeSnapshot() -> [String: SnapshotValue] {
        var v: [String: SnapshotValue] = [
            "hasCompletedOnboarding": .bool(hasCompletedOnboarding),
            "isVerified": .bool(isVerified),
            "isGoldVerified": .bool(isGoldVerified),
            "showLevelUpCelebration": .bool(showLevelUpCelebration),
            "newLevelReached": .int(newLevelReached),
            "currentUser.isNil": .bool(currentUser == nil),
        ]
        if let u = currentUser {
            // Core Data `User` entity — pull only scalars that reveal
            // state mismatches (height/weight unit, experience, goal).
            // Never include user.name / user.email.
            v["currentUser.weight"] = .int(Int(u.weight))
            v["currentUser.weightLbs"] = .double(u.weightLbs)
            v["currentUser.height"] = .int(Int(u.height))
            v["currentUser.age"] = .int(Int(u.age))
            if let goal = u.fitnessGoal { v["currentUser.fitnessGoal"] = .string(goal) }
            if let level = u.experienceLevel { v["currentUser.experienceLevel"] = .string(level) }
        }
        return v
    }
}

// MARK: - PremiumManager
//
// A single bool that gates a huge chunk of the app. If a user reports
// "feature X is missing" and premium flips unexpectedly, this pins it.

extension PremiumManager: SnapshotProvider {
    var snapshotKey: String { "PremiumManager" }

    @MainActor
    func contributeSnapshot() -> [String: SnapshotValue] {
        [
            "isPremiumUser": .bool(isPremiumUser),
        ]
    }
}

// MARK: - DailyQuestService
//
// Quests are a common bug surface (slot logic, category diversity,
// challenge override). The published counts + current quest keys are
// enough to spot "quest completed but not checking off" divergences.

extension DailyQuestService: SnapshotProvider {
    var snapshotKey: String { "DailyQuestService" }

    @MainActor
    func contributeSnapshot() -> [String: SnapshotValue] {
        var v: [String: SnapshotValue] = [
            "quests.count": .int(quests.count),
            "allComplete": .bool(allComplete),
            "bonusXp": .int(bonusXp),
            "bonusLeaguePoints": .int(bonusLeaguePoints),
            "questStreak": .int(questStreak),
            "longestStreak": .int(longestStreak),
            "totalCompleted": .int(totalCompleted),
            "isLoading": .bool(isLoading),
        ]
        if let profile = difficultyProfile {
            v["difficultyProfile"] = .string(profile)
        }
        if let err = error {
            v["error"] = .string(err)
        }
        // Collapse quest IDs + completion state into a flat array so
        // Claude can see "3 of 3 completed" vs "claimed=false on 1".
        v["quests.ids"] = .strings(quests.map { $0.id.uuidString })
        v["quests.completedCount"] = .int(quests.filter { $0.isCompleted }.count)
        v["quests.keys"] = .strings(quests.map { $0.questKey })
        return v
    }
}

// MARK: - WorkoutManager
//
// Active workout state + navigation flags. Navigation flag drift is
// itself a frequent bug class — we surface all the shouldNavigate*
// bools in a compact array so mis-stuck flags jump out.

extension WorkoutManager: SnapshotProvider {
    var snapshotKey: String { "WorkoutManager" }

    @MainActor
    func contributeSnapshot() -> [String: SnapshotValue] {
        var v: [String: SnapshotValue] = [
            "isWorkoutActive": .bool(isWorkoutActive),
            "currentExercises.count": .int(currentExercises.count),
            "currentWorkout.isNil": .bool(currentWorkout == nil),
        ]
        if let start = workoutStartTime {
            v["workoutDurationSeconds"] = .double(Date().timeIntervalSince(start))
        }
        // Flatten all nav flags into a compact list of the ones
        // currently set to true. Empty array = no pending navigation.
        var stuckFlags: [String] = []
        if shouldNavigateToWorkoutTab { stuckFlags.append("toWorkoutTab") }
        if shouldNavigateToHomeTab { stuckFlags.append("toHomeTab") }
        if shouldPopToRootHome { stuckFlags.append("popToRootHome") }
        if shouldShowWorkoutGenerator { stuckFlags.append("showWorkoutGenerator") }
        if shouldNavigateToAutoGen { stuckFlags.append("toAutoGen") }
        if shouldNavigateToPrograms { stuckFlags.append("toPrograms") }
        if shouldNavigateToFindFriends { stuckFlags.append("toFindFriends") }
        if shouldNavigateToProfileFriends { stuckFlags.append("toProfileFriends") }
        if shouldNavigateToHomeTabInstant { stuckFlags.append("toHomeTabInstant") }
        if shouldNavigateToProgramOverview { stuckFlags.append("toProgramOverview") }
        if shouldNavigateToProgramDay { stuckFlags.append("toProgramDay") }
        v["pendingNavigationFlags"] = .strings(stuckFlags)
        return v
    }
}
