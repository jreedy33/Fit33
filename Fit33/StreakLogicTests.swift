//
//  StreakLogicTests.swift
//  Fit33
//
//  Unit tests for streak calculation, update, and break logic.
//  Exercises UserManager's streak methods with real Core Data state,
//  saving and restoring user values to remain non-destructive.
//
//  ⚠️ DEBUG ONLY — excluded from production builds.
//

#if DEBUG

import Foundation
import CoreData

@MainActor
enum StreakLogicTests {

    struct TestResult {
        let name: String
        let passed: Bool
        let detail: String
    }

    // MARK: - Snapshot / Restore

    private struct UserSnapshot {
        let currentStreak: Int32
        let longestStreak: Int32
        let lastWorkoutDate: Date?
        let availableDays: Int16
    }

    private static func snapshot(_ user: NSManagedObject) -> UserSnapshot {
        UserSnapshot(
            currentStreak: (user.value(forKey: "currentStreak") as? Int32) ?? 0,
            longestStreak: (user.value(forKey: "longestStreak") as? Int32) ?? 0,
            lastWorkoutDate: user.value(forKey: "lastWorkoutDate") as? Date,
            availableDays: (user.value(forKey: "availableDays") as? Int16) ?? 5
        )
    }

    private static func restore(_ snap: UserSnapshot, to user: NSManagedObject) {
        user.setValue(snap.currentStreak, forKey: "currentStreak")
        user.setValue(snap.longestStreak, forKey: "longestStreak")
        user.setValue(snap.lastWorkoutDate, forKey: "lastWorkoutDate")
        user.setValue(snap.availableDays, forKey: "availableDays")
        try? user.managedObjectContext?.save()
    }

    // MARK: - Public Entry Point

    static func runAll() -> [TestResult] {
        var results: [TestResult] = []

        results.append(testMaxAllowedRestDays())
        results.append(testStreakStatusMessages())
        results.append(testUpdateStreakIncrements())
        results.append(testUpdateStreakSameDayNoDouble())
        results.append(testCheckAndBreakStreakSafe())
        results.append(testCheckAndBreakStreakBreaks())
        results.append(testCheckAndBreakStreakZeroNoop())
        results.append(testLongestStreakTracking())
        results.append(testGapBoundaryExact())
        results.append(testFirstWorkoutSetsStreakToOne())

        return results
    }

    // MARK: - T1: Max Allowed Rest Days

    static func testMaxAllowedRestDays() -> TestResult {
        let name = "Max Allowed Rest Days"
        let um = UserManager.shared
        guard let user = um.currentUser else {
            return TestResult(name: name, passed: false, detail: "No current user")
        }

        let snap = snapshot(user)
        defer { restore(snap, to: user) }

        // Expected mapping: availableDays → rest days (gap - 1)
        let expected: [(days: Int16, rest: Int)] = [
            (7, 1), (6, 1), (5, 1), (4, 2), (3, 2), (2, 3)
        ]

        for pair in expected {
            user.setValue(pair.days, forKey: "availableDays")
            let rest = um.getMaxAllowedRestDays()
            if rest != pair.rest {
                return TestResult(name: name, passed: false,
                    detail: "availableDays=\(pair.days): expected rest \(pair.rest), got \(rest)")
            }
        }

        return TestResult(name: name, passed: true, detail: "All 6 frequency→rest-day mappings correct")
    }

    // MARK: - T2: Streak Status Messages

    static func testStreakStatusMessages() -> TestResult {
        let name = "Streak Status Messages"
        let um = UserManager.shared
        guard let user = um.currentUser else {
            return TestResult(name: name, passed: false, detail: "No current user")
        }

        let snap = snapshot(user)
        defer { restore(snap, to: user) }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Case 1: currentStreak == 0 → "Start your streak today!"
        user.setValue(Int32(0), forKey: "currentStreak")
        user.setValue(today, forKey: "lastWorkoutDate")
        let s1 = um.getStreakStatus()
        guard s1.message == "Start your streak today!" else {
            return TestResult(name: name, passed: false,
                detail: "streak=0 message wrong: \(s1.message)")
        }

        // Case 2: daysSinceLastWorkout == 0 → "Great job!" message
        user.setValue(Int32(5), forKey: "currentStreak")
        user.setValue(today, forKey: "lastWorkoutDate")
        let s2 = um.getStreakStatus()
        guard s2.message.hasPrefix("Great job!") else {
            return TestResult(name: name, passed: false,
                detail: "same-day message wrong: \(s2.message)")
        }
        guard !s2.isAtRisk else {
            return TestResult(name: name, passed: false, detail: "same-day should not be at risk")
        }

        // Case 3: daysRemaining <= 0 → at risk
        user.setValue(Int32(3), forKey: "currentStreak")
        user.setValue(Int16(5), forKey: "availableDays")
        let farPast = calendar.date(byAdding: .day, value: -10, to: today)!
        user.setValue(farPast, forKey: "lastWorkoutDate")
        let s3 = um.getStreakStatus()
        guard s3.isAtRisk else {
            return TestResult(name: name, passed: false,
                detail: "10 days gap should be at risk")
        }

        // Case 4: daysRemaining == 1 → at risk
        user.setValue(Int32(3), forKey: "currentStreak")
        user.setValue(Int16(5), forKey: "availableDays") // gap=2
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        user.setValue(yesterday, forKey: "lastWorkoutDate")
        let s4 = um.getStreakStatus()
        guard s4.isAtRisk && s4.daysRemaining == 1 else {
            return TestResult(name: name, passed: false,
                detail: "1 day remaining should be at risk, got isAtRisk=\(s4.isAtRisk) remaining=\(s4.daysRemaining)")
        }

        return TestResult(name: name, passed: true, detail: "All 4 status message scenarios correct")
    }

    // MARK: - T3: Update Streak Increments

    static func testUpdateStreakIncrements() -> TestResult {
        let name = "Update Streak Increments"
        let um = UserManager.shared
        guard let user = um.currentUser else {
            return TestResult(name: name, passed: false, detail: "No current user")
        }

        let snap = snapshot(user)
        defer { restore(snap, to: user) }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

        user.setValue(Int32(5), forKey: "currentStreak")
        user.setValue(Int32(10), forKey: "longestStreak")
        user.setValue(yesterday, forKey: "lastWorkoutDate")
        user.setValue(Int16(5), forKey: "availableDays")

        um.updateStreak()

        let newStreak = (user.value(forKey: "currentStreak") as? Int32) ?? 0
        guard newStreak == 6 else {
            return TestResult(name: name, passed: false,
                detail: "Expected streak 6, got \(newStreak)")
        }

        return TestResult(name: name, passed: true, detail: "Streak incremented 5→6 after 1-day gap")
    }

    // MARK: - T4: Same-Day No Double Count

    static func testUpdateStreakSameDayNoDouble() -> TestResult {
        let name = "Same-Day No Double Count"
        let um = UserManager.shared
        guard let user = um.currentUser else {
            return TestResult(name: name, passed: false, detail: "No current user")
        }

        let snap = snapshot(user)
        defer { restore(snap, to: user) }

        let today = Calendar.current.startOfDay(for: Date())
        user.setValue(Int32(3), forKey: "currentStreak")
        user.setValue(Int32(10), forKey: "longestStreak")
        user.setValue(today, forKey: "lastWorkoutDate")
        user.setValue(Int16(5), forKey: "availableDays")

        um.updateStreak()

        let streak = (user.value(forKey: "currentStreak") as? Int32) ?? 0
        guard streak == 3 else {
            return TestResult(name: name, passed: false,
                detail: "Expected streak to stay 3, got \(streak)")
        }

        return TestResult(name: name, passed: true, detail: "Same-day call left streak at 3")
    }

    // MARK: - T5: Check And Break – Safe

    static func testCheckAndBreakStreakSafe() -> TestResult {
        let name = "Break Check Safe"
        let um = UserManager.shared
        guard let user = um.currentUser else {
            return TestResult(name: name, passed: false, detail: "No current user")
        }

        let snap = snapshot(user)
        defer { restore(snap, to: user) }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

        user.setValue(Int32(7), forKey: "currentStreak")
        user.setValue(yesterday, forKey: "lastWorkoutDate")
        user.setValue(Int16(5), forKey: "availableDays") // gap=2, 1 day is within

        um.checkAndBreakStreakIfNeeded()

        let streak = (user.value(forKey: "currentStreak") as? Int32) ?? 0
        guard streak == 7 else {
            return TestResult(name: name, passed: false,
                detail: "Streak should stay 7, got \(streak)")
        }

        return TestResult(name: name, passed: true, detail: "Streak 7 preserved (1 day gap, max 2)")
    }

    // MARK: - T6: Check And Break – Breaks

    static func testCheckAndBreakStreakBreaks() -> TestResult {
        let name = "Break Check Breaks"
        let um = UserManager.shared
        guard let user = um.currentUser else {
            return TestResult(name: name, passed: false, detail: "No current user")
        }

        let snap = snapshot(user)
        defer { restore(snap, to: user) }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let fiveDaysAgo = calendar.date(byAdding: .day, value: -5, to: today)!

        user.setValue(Int32(10), forKey: "currentStreak")
        user.setValue(fiveDaysAgo, forKey: "lastWorkoutDate")
        user.setValue(Int16(5), forKey: "availableDays") // gap=2, 5 days exceeds

        um.checkAndBreakStreakIfNeeded()

        let streak = (user.value(forKey: "currentStreak") as? Int32) ?? 0
        guard streak == 0 else {
            return TestResult(name: name, passed: false,
                detail: "Streak should be 0 after 5-day gap, got \(streak)")
        }

        return TestResult(name: name, passed: true, detail: "Streak reset to 0 (5-day gap > max 2)")
    }

    // MARK: - T7: Check And Break – Zero No-op

    static func testCheckAndBreakStreakZeroNoop() -> TestResult {
        let name = "Break Check Zero No-op"
        let um = UserManager.shared
        guard let user = um.currentUser else {
            return TestResult(name: name, passed: false, detail: "No current user")
        }

        let snap = snapshot(user)
        defer { restore(snap, to: user) }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tenDaysAgo = calendar.date(byAdding: .day, value: -10, to: today)!

        user.setValue(Int32(0), forKey: "currentStreak")
        user.setValue(tenDaysAgo, forKey: "lastWorkoutDate")
        user.setValue(Int16(5), forKey: "availableDays")

        um.checkAndBreakStreakIfNeeded()

        let streak = (user.value(forKey: "currentStreak") as? Int32) ?? 0
        guard streak == 0 else {
            return TestResult(name: name, passed: false,
                detail: "Streak should remain 0, got \(streak)")
        }

        return TestResult(name: name, passed: true, detail: "No-op when streak already 0")
    }

    // MARK: - T8: Longest Streak Tracking

    static func testLongestStreakTracking() -> TestResult {
        let name = "Longest Streak Tracking"
        let um = UserManager.shared
        guard let user = um.currentUser else {
            return TestResult(name: name, passed: false, detail: "No current user")
        }

        let snap = snapshot(user)
        defer { restore(snap, to: user) }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

        user.setValue(Int32(9), forKey: "currentStreak")
        user.setValue(Int32(9), forKey: "longestStreak")
        user.setValue(yesterday, forKey: "lastWorkoutDate")
        user.setValue(Int16(5), forKey: "availableDays")

        um.updateStreak()

        let longest = (user.value(forKey: "longestStreak") as? Int32) ?? 0
        let current = (user.value(forKey: "currentStreak") as? Int32) ?? 0
        guard current == 10 && longest == 10 else {
            return TestResult(name: name, passed: false,
                detail: "Expected current=10, longest=10; got current=\(current), longest=\(longest)")
        }

        return TestResult(name: name, passed: true, detail: "longestStreak updated 9→10 with currentStreak")
    }

    // MARK: - T9: Gap Boundary Exact

    static func testGapBoundaryExact() -> TestResult {
        let name = "Gap Boundary Exact"
        let um = UserManager.shared
        guard let user = um.currentUser else {
            return TestResult(name: name, passed: false, detail: "No current user")
        }

        let snap = snapshot(user)
        defer { restore(snap, to: user) }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // With availableDays=5, maxAllowedGap=2
        user.setValue(Int16(5), forKey: "availableDays")

        // Exactly at boundary (2 days ago) → should continue streak
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: today)!
        user.setValue(Int32(4), forKey: "currentStreak")
        user.setValue(Int32(10), forKey: "longestStreak")
        user.setValue(twoDaysAgo, forKey: "lastWorkoutDate")

        um.updateStreak()

        let streakAfterExact = (user.value(forKey: "currentStreak") as? Int32) ?? 0
        guard streakAfterExact == 5 else {
            return TestResult(name: name, passed: false,
                detail: "At exact boundary (2d), expected 5 got \(streakAfterExact)")
        }

        // One past boundary (3 days ago) → should reset to 1
        let threeDaysAgo = calendar.date(byAdding: .day, value: -3, to: today)!
        user.setValue(Int32(4), forKey: "currentStreak")
        user.setValue(Int32(10), forKey: "longestStreak")
        user.setValue(threeDaysAgo, forKey: "lastWorkoutDate")

        um.updateStreak()

        let streakAfterOver = (user.value(forKey: "currentStreak") as? Int32) ?? 0
        guard streakAfterOver == 1 else {
            return TestResult(name: name, passed: false,
                detail: "Past boundary (3d), expected 1 got \(streakAfterOver)")
        }

        return TestResult(name: name, passed: true,
            detail: "gap==max continues (4→5), gap>max resets to 1")
    }

    // MARK: - T10: First Workout Sets Streak To One

    static func testFirstWorkoutSetsStreakToOne() -> TestResult {
        let name = "First Workout Streak=1"
        let um = UserManager.shared
        guard let user = um.currentUser else {
            return TestResult(name: name, passed: false, detail: "No current user")
        }

        let snap = snapshot(user)
        defer { restore(snap, to: user) }

        // Simulate never having worked out: nil date, distant past triggers gap > max
        user.setValue(Int32(0), forKey: "currentStreak")
        user.setValue(Int32(0), forKey: "longestStreak")
        user.setValue(nil, forKey: "lastWorkoutDate")
        user.setValue(Int16(5), forKey: "availableDays")

        um.updateStreak()

        let streak = (user.value(forKey: "currentStreak") as? Int32) ?? 0
        guard streak == 1 else {
            return TestResult(name: name, passed: false,
                detail: "Expected streak 1 after first workout, got \(streak)")
        }

        let lastDate = user.value(forKey: "lastWorkoutDate") as? Date
        guard lastDate != nil else {
            return TestResult(name: name, passed: false,
                detail: "lastWorkoutDate should be set after first workout")
        }

        return TestResult(name: name, passed: true,
            detail: "nil lastWorkoutDate → streak=1, date set to today")
    }
}

#endif
