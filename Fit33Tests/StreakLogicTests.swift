// Sprint 5 L-9/L-10: Streak timezone-change + midnight app-kill tests
//
// Exercises `Fit33StreakLogic.transition(...)` — the pure extraction of
// `UserManager.updateStreak()`. Uses fixed Dates + explicit Calendars so
// behavior is deterministic across CI environments and the developer's
// local time zone.
//
// Scenarios covered:
//  - L-9: User travels across time zones between workouts. The streak must
//         increment once and exactly once per calendar day in the traveler's
//         new local time zone, never break from a same-day workout, and never
//         go backwards when the wall clock shifts east.
//  - L-10: App is killed before midnight and reopened after midnight. The
//         streak math must treat the new calendar day as +1 day, not 0.

import XCTest
@testable import Fit33

final class StreakLogicTests: XCTestCase {

    // MARK: - Helpers

    private func calendar(timeZone identifier: String) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        guard let tz = TimeZone(identifier: identifier) else {
            XCTFail("Unknown timezone: \(identifier)")
            return cal
        }
        cal.timeZone = tz
        return cal
    }

    private func date(
        _ year: Int, _ month: Int, _ day: Int,
        _ hour: Int = 12, _ minute: Int = 0,
        timeZone: String = "America/New_York"
    ) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: timeZone) ?? TimeZone(identifier: "UTC")!
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = minute
        return cal.date(from: comps) ?? Date()
    }

    // MARK: - Baseline sanity

    func testFirstWorkoutEverStartsStreakAtOne() {
        let cal = calendar(timeZone: "America/New_York")
        let now = date(2026, 4, 20, 9, 0)

        let t = Fit33StreakLogic.transition(
            lastWorkoutDate: nil,
            now: now,
            currentStreak: 0,
            daysPerWeek: 4,
            calendar: cal
        )

        XCTAssertEqual(t.outcome, .incremented(newValue: 1))
        XCTAssertEqual(t.daysSinceLastWorkout, 0)
    }

    func testSameDayWorkoutDoesNotDoubleCount() {
        let cal = calendar(timeZone: "America/New_York")
        // Last workout at 7 AM, another at 7 PM same day.
        let last = date(2026, 4, 20, 7, 0)
        let now  = date(2026, 4, 20, 19, 0)

        let t = Fit33StreakLogic.transition(
            lastWorkoutDate: last,
            now: now,
            currentStreak: 5,
            daysPerWeek: 4,
            calendar: cal
        )

        XCTAssertEqual(t.outcome, .sameDay)
        XCTAssertEqual(t.daysSinceLastWorkout, 0)
    }

    func testConsecutiveDaysIncrement() {
        let cal = calendar(timeZone: "America/New_York")
        let last = date(2026, 4, 20, 9, 0)
        let now  = date(2026, 4, 21, 9, 0)

        let t = Fit33StreakLogic.transition(
            lastWorkoutDate: last,
            now: now,
            currentStreak: 5,
            daysPerWeek: 4,
            calendar: cal
        )

        XCTAssertEqual(t.outcome, .incremented(newValue: 6))
        XCTAssertEqual(t.daysSinceLastWorkout, 1)
    }

    func testGapBeyondToleranceBreaksStreak() {
        let cal = calendar(timeZone: "America/New_York")
        // 5 day gap for a 5 day/week trainee (max gap = 2) — should break.
        let last = date(2026, 4, 14, 9, 0)
        let now  = date(2026, 4, 19, 9, 0)

        let t = Fit33StreakLogic.transition(
            lastWorkoutDate: last,
            now: now,
            currentStreak: 12,
            daysPerWeek: 5,
            calendar: cal
        )

        XCTAssertEqual(t.outcome, .broken(previous: 12))
        XCTAssertEqual(t.daysSinceLastWorkout, 5)
        XCTAssertEqual(t.maxAllowedGap, 2)
    }

    func testGapAtTolerancePreservesStreak() {
        let cal = calendar(timeZone: "America/New_York")
        // 3-day gap for a 4 days/week trainee (max gap = 3) — should increment.
        let last = date(2026, 4, 17, 9, 0)
        let now  = date(2026, 4, 20, 9, 0)

        let t = Fit33StreakLogic.transition(
            lastWorkoutDate: last,
            now: now,
            currentStreak: 7,
            daysPerWeek: 4,
            calendar: cal
        )

        XCTAssertEqual(t.outcome, .incremented(newValue: 8))
        XCTAssertEqual(t.daysSinceLastWorkout, 3)
    }

    // MARK: - L-9: Timezone change

    /// User works out at 11:50 PM NYC time (UTC-4 DST), flies to Tokyo
    /// (UTC+9), lands, and works out the next local day at 9 AM. Same
    /// user-perceived calendar day in neither zone should break the streak;
    /// the streak should increment once.
    func testTimezoneChangeEastwardContinuesStreakExactlyOnce() {
        let nyc = calendar(timeZone: "America/New_York")
        let tokyo = calendar(timeZone: "Asia/Tokyo")

        // Wall-clock moments.
        let lastInNYC = date(2026, 4, 20, 23, 50, timeZone: "America/New_York")
        // Tokyo is ~13 hours ahead in April. Arriving next morning local.
        let nowInTokyo = date(2026, 4, 22, 9, 0, timeZone: "Asia/Tokyo")

        let t1 = Fit33StreakLogic.transition(
            lastWorkoutDate: lastInNYC,
            now: nowInTokyo,
            currentStreak: 10,
            daysPerWeek: 5,
            calendar: tokyo
        )
        XCTAssertEqual(t1.outcome, .incremented(newValue: 11),
                       "Flying east must still allow tomorrow's workout to extend the streak")
        XCTAssertLessThanOrEqual(t1.daysSinceLastWorkout, 2)
        XCTAssertGreaterThanOrEqual(t1.daysSinceLastWorkout, 1)

        // And evaluating from NYC (the user hasn't flipped their device's
        // timezone yet) yields the same "still increments" outcome.
        let t2 = Fit33StreakLogic.transition(
            lastWorkoutDate: lastInNYC,
            now: nowInTokyo,
            currentStreak: 10,
            daysPerWeek: 5,
            calendar: nyc
        )
        if case .incremented = t2.outcome {
            // pass
        } else {
            XCTFail("Eastward travel must never break the streak on day+1")
        }
    }

    /// User works out in Tokyo, flies westbound to LAX. Same real-time
    /// instant can be "yesterday" in LAX vs "today" in Tokyo. The streak
    /// must never decrement or go negative — reflected by the helper
    /// clamping negative day deltas to zero.
    func testTimezoneChangeWestwardNeverDecrements() {
        let la = calendar(timeZone: "America/Los_Angeles")

        let lastInTokyo = date(2026, 4, 20, 22, 0, timeZone: "Asia/Tokyo")
        // Earlier "today" in LAX because of the time zone rollback.
        let nowInLA = date(2026, 4, 20, 9, 0, timeZone: "America/Los_Angeles")

        let t = Fit33StreakLogic.transition(
            lastWorkoutDate: lastInTokyo,
            now: nowInLA,
            currentStreak: 3,
            daysPerWeek: 4,
            calendar: la
        )

        // Could be sameDay (clamp) or incremented depending on how the day
        // boundaries line up. The critical contract: never broken.
        switch t.outcome {
        case .broken:
            XCTFail("Westward travel must never break a live streak")
        default:
            XCTAssertGreaterThanOrEqual(t.daysSinceLastWorkout, 0)
        }
    }

    /// DST fall-back: same local calendar day straddling a 25-hour day
    /// should count as zero days, not one.
    func testDSTFallBackDoesNotDoubleCount() {
        let nyc = calendar(timeZone: "America/New_York")
        // DST "fall back" in US: Nov 2, 2025 at 2am → 1am.
        let last = date(2025, 11, 2, 0, 30, timeZone: "America/New_York")
        let now  = date(2025, 11, 2, 23, 30, timeZone: "America/New_York")

        let t = Fit33StreakLogic.transition(
            lastWorkoutDate: last,
            now: now,
            currentStreak: 4,
            daysPerWeek: 4,
            calendar: nyc
        )

        XCTAssertEqual(t.outcome, .sameDay)
        XCTAssertEqual(t.daysSinceLastWorkout, 0)
    }

    // MARK: - L-10: Midnight app-kill

    /// App was killed at 10 PM on day N. User reopens at 7 AM day N+1 and
    /// completes a workout. Streak should advance by exactly one.
    func testMidnightAppKillAdvancesStreakByOne() {
        let cal = calendar(timeZone: "America/New_York")
        let last = date(2026, 4, 20, 22, 0)       // 10 PM
        let now  = date(2026, 4, 21, 7, 0)        // next morning

        let t = Fit33StreakLogic.transition(
            lastWorkoutDate: last,
            now: now,
            currentStreak: 12,
            daysPerWeek: 5,
            calendar: cal
        )

        XCTAssertEqual(t.outcome, .incremented(newValue: 13))
        XCTAssertEqual(t.daysSinceLastWorkout, 1)
    }

    /// App killed at 11:58 PM. User reopens at 12:02 AM the next day. Even
    /// though only four minutes elapsed, it's a new calendar day → streak
    /// must increment by one (not zero).
    func testMidnightAppKillFourMinutesAfterMidnightCountsAsNewDay() {
        let cal = calendar(timeZone: "America/New_York")
        let last = date(2026, 4, 20, 23, 58)
        let now  = date(2026, 4, 21, 0, 2)

        let t = Fit33StreakLogic.transition(
            lastWorkoutDate: last,
            now: now,
            currentStreak: 6,
            daysPerWeek: 4,
            calendar: cal
        )

        XCTAssertEqual(t.outcome, .incremented(newValue: 7))
        XCTAssertEqual(t.daysSinceLastWorkout, 1)
    }

    /// User was killed right before midnight, woke up well past the
    /// tolerance window (e.g., was sick for a week). Streak should break
    /// with the correct "previous" value reported for analytics.
    func testMidnightAppKillWithLongAbsenceBreaksStreak() {
        let cal = calendar(timeZone: "America/New_York")
        let last = date(2026, 4, 13, 23, 59)      // ~a week ago
        let now  = date(2026, 4, 21, 8, 0)

        let t = Fit33StreakLogic.transition(
            lastWorkoutDate: last,
            now: now,
            currentStreak: 21,
            daysPerWeek: 5,
            calendar: cal
        )

        XCTAssertEqual(t.outcome, .broken(previous: 21))
        XCTAssertGreaterThan(t.daysSinceLastWorkout, t.maxAllowedGap)
    }

    // MARK: - Gap table

    func testMaxAllowedGapTableMatchesUserManager() {
        XCTAssertEqual(Fit33StreakLogic.maxAllowedGap(daysPerWeek: 7), 2)
        XCTAssertEqual(Fit33StreakLogic.maxAllowedGap(daysPerWeek: 6), 2)
        XCTAssertEqual(Fit33StreakLogic.maxAllowedGap(daysPerWeek: 5), 2)
        XCTAssertEqual(Fit33StreakLogic.maxAllowedGap(daysPerWeek: 4), 3)
        XCTAssertEqual(Fit33StreakLogic.maxAllowedGap(daysPerWeek: 3), 3)
        XCTAssertEqual(Fit33StreakLogic.maxAllowedGap(daysPerWeek: 2), 4)
    }
}
