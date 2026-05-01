//
//  ChallengeLeaguePointsTests.swift
//  Fit33Tests
//
//  Unit tests for the Challenge League Points Expansion ("Daily Duels,
//  Final Bell", 2026-04-30). Guards the client-side plumbing the server
//  relies on:
//
//    1. DTO decoding parity with the new RPC shapes
//         (`get_challenge_details.daily_league_awards`,
//          `get_league_member_breakdown`,
//          `get_or_join_weekly_league` promotion floor fields).
//    2. BattleLogRow / ChallengeDetails computed-property correctness
//         (aggregation per day, primary-reason selection).
//    3. LeaguePointSource extension coverage (new .challengeDaily /
//       .challengeFinalBell cases decode, roundtrip, and stay 0-point
//       client-side since they're server-authoritative).
//    4. Promotion LP floor progress math (nil when floor=0, capped at 1.0).
//    5. Push-routing allowlist includes `challenge_lp_awarded`.
//
//  These are pure-logic tests — no HealthKit, no Supabase. They run in the
//  app's default Testing framework sim scheme.
//

import XCTest
import Foundation
@testable import Fit33

final class ChallengeLeaguePointsTests: XCTestCase {

    private let decoder = JSONDecoder()

    // MARK: - ChallengeLeagueAward DTO

    func testChallengeLeagueAwardDecodesDailyRow() throws {
        let json = Data("""
        {
            "day": "2026-05-03",
            "award_kind": "day_winner",
            "base_points": 15,
            "multiplier": 2.0,
            "points": 20,
            "note": "Day winner (1v1) — 2x"
        }
        """.utf8)
        let award = try decoder.decode(ChallengeLeagueAward.self, from: json)
        XCTAssertEqual(award.day, "2026-05-03")
        XCTAssertEqual(award.awardKind, "day_winner")
        XCTAssertEqual(award.points, 20)
        XCTAssertEqual(award.multiplier, 2.0, accuracy: 0.001)
        XCTAssertEqual(award.displayReason, "Day winner (1v1) — 2x")
    }

    func testChallengeLeagueAwardDecodesFinalBellNullDay() throws {
        let json = Data("""
        {
            "day": null,
            "award_kind": "final_bell",
            "base_points": 66,
            "multiplier": 1.5,
            "points": 99,
            "note": "Winner — full pot + Unbroken Chain 1.5x"
        }
        """.utf8)
        let award = try decoder.decode(ChallengeLeagueAward.self, from: json)
        XCTAssertNil(award.day)
        XCTAssertEqual(award.awardKind, "final_bell")
        XCTAssertEqual(award.points, 99)
    }

    func testChallengeLeagueAwardDisplayReasonFallsBackByKind() {
        let award = ChallengeLeagueAward(
            day: "2026-05-03",
            awardKind: "early_bird",
            basePoints: 10,
            multiplier: 1.0,
            points: 10,
            note: nil
        )
        XCTAssertEqual(award.displayReason, "Early Bird")
    }

    // MARK: - ChallengeDetails helpers

    /// Server response shape for `get_challenge_details` after migration #178.
    /// Validates the new `daily_league_awards` field decodes into the model.
    func testChallengeDetailsDecodesDailyLeagueAwardsArray() throws {
        let json = Data("""
        {
            "challenge_id": "11111111-1111-1111-1111-111111111111",
            "challenge_type": "steps",
            "title": "Test",
            "description": null,
            "daily_target": 10000,
            "total_target": null,
            "target_unit": "steps",
            "start_date": "2026-05-01",
            "end_date": "2026-05-07",
            "duration_days": 7,
            "status": "active",
            "created_at": "2026-05-01T00:00:00Z",
            "notify_on_opponent_complete": true,
            "participants": null,
            "daily_league_awards": [
                {"day":"2026-05-03","award_kind":"hit_target","base_points":10,"multiplier":1.0,"points":10,"note":"Hit target"},
                {"day":"2026-05-03","award_kind":"day_winner","base_points":15,"multiplier":2.0,"points":20,"note":"Day winner (1v1) — 2x"}
            ]
        }
        """.utf8)
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        let details = try d.decode(ChallengeDetails.self, from: json)

        XCTAssertEqual(details.dailyLeagueAwards?.count, 2)
    }

    /// `leaguePointsAwarded(on:)` must sum across the award-kind rows for
    /// the same calendar day (hit_target 10 + day_winner 20 = 30).
    func testLeaguePointsAggregatesSameDay() {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate]
        let day3 = iso.date(from: "2026-05-03")!

        let rows: [ChallengeLeagueAward] = [
            .init(day: "2026-05-03", awardKind: "hit_target", basePoints: 10, multiplier: 1.0, points: 10, note: "Hit target"),
            .init(day: "2026-05-03", awardKind: "day_winner", basePoints: 15, multiplier: 2.0, points: 20, note: "Day winner — 2x"),
            .init(day: "2026-05-04", awardKind: "hit_target", basePoints: 10, multiplier: 1.0, points: 10, note: "Hit target")
        ]
        let details = Self.makeDetailsStub(awards: rows)

        XCTAssertEqual(details.leaguePointsAwarded(on: day3), 30)
        XCTAssertEqual(details.primaryLeagueReason(on: day3), "Day winner — 2x")
    }

    /// A day with no awards should return 0 LP and a nil reason so
    /// BattleLogRow renders no chip.
    func testLeaguePointsReturnsZeroForDayWithoutAwards() {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate]
        let day9 = iso.date(from: "2026-05-09")!

        let details = Self.makeDetailsStub(awards: [
            .init(day: "2026-05-03", awardKind: "hit_target", basePoints: 10, multiplier: 1.0, points: 10, note: "Hit target")
        ])
        XCTAssertEqual(details.leaguePointsAwarded(on: day9), 0)
        XCTAssertNil(details.primaryLeagueReason(on: day9))
    }

    /// Final Bell lookup returns the single row whose day is nil.
    func testFinalBellAwardReturnsNullDayRow() {
        let details = Self.makeDetailsStub(awards: [
            .init(day: "2026-05-07", awardKind: "hit_target", basePoints: 10, multiplier: 1.0, points: 10, note: nil),
            .init(day: nil, awardKind: "final_bell", basePoints: 66, multiplier: 1.5, points: 99, note: "Winner — full pot + Unbroken Chain 1.5x")
        ])
        XCTAssertNotNil(details.finalBellAward)
        XCTAssertEqual(details.finalBellAward?.points, 99)
        XCTAssertEqual(details.finalBellAward?.awardKind, "final_bell")
    }

    // MARK: - LeagueMemberBreakdownEntry

    func testMemberBreakdownEntryDecoding() throws {
        let json = Data("""
        [
            {"source":"workout","award_count":3,"total_points":150},
            {"source":"challenge_daily","award_count":7,"total_points":210}
        ]
        """.utf8)
        let entries = try decoder.decode([LeagueMemberBreakdownEntry].self, from: json)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.first?.source, "workout")
        XCTAssertEqual(entries.first?.totalPoints, 150)
        XCTAssertEqual(entries.last?.awardCount, 7)
        XCTAssertEqual(entries.last?.displayName, "Daily Duel")
    }

    func testMemberBreakdownUnknownSourceDisplayName() {
        let entry = LeagueMemberBreakdownEntry(source: "some_future_kind", awardCount: 1, totalPoints: 5)
        XCTAssertEqual(entry.displayName, "Some Future Kind")
    }

    // MARK: - LeaguePointSource extensions

    func testNewChallengeSourcesAreEnumerable() {
        XCTAssertEqual(LeaguePointSource.challengeDaily.rawValue, "challenge_daily")
        XCTAssertEqual(LeaguePointSource.challengeFinalBell.rawValue, "challenge_final_bell")
    }

    /// Server is authoritative for points — these sources must expose 0 LP
    /// on the client so `shouldAwardPoints` can never accidentally credit.
    func testServerAuthoritativeSourcesReturnZeroClientPoints() {
        XCTAssertEqual(LeaguePointSource.challengeDaily.points, 0)
        XCTAssertEqual(LeaguePointSource.challengeFinalBell.points, 0)
    }

    func testServerAuthoritativeSourceDisplayNames() {
        XCTAssertEqual(LeaguePointSource.challengeDaily.displayName, "Daily Duel")
        XCTAssertEqual(LeaguePointSource.challengeFinalBell.displayName, "Final Bell")
    }

    // MARK: - LeagueStanding promotion floor progress

    /// Floor of 0 (e.g. Verified — no promotion) returns nil for both
    /// `meetsPromotionLpFloor` and `promotionLpFloorProgress`.
    func testPromotionLpFloorZeroReturnsNilHelpers() {
        let standing = Self.makeStandingStub(
            myPoints: 500,
            promotionLpFloor: 0,
            peakDayMultiplier: 5,
            requiresCrownToPromote: false
        )
        XCTAssertNil(standing.meetsPromotionLpFloor)
        XCTAssertNil(standing.promotionLpFloorProgress)
    }

    /// Floor of 900 with myPoints 540 = 0.6 progress, not met.
    func testPromotionLpFloorPartialProgress() {
        let standing = Self.makeStandingStub(
            myPoints: 540,
            promotionLpFloor: 900,
            peakDayMultiplier: 4,
            requiresCrownToPromote: false
        )
        XCTAssertEqual(standing.meetsPromotionLpFloor, false)
        XCTAssertEqual(standing.promotionLpFloorProgress ?? -1, 0.6, accuracy: 0.001)
    }

    /// Exceeding the floor still caps progress at 1.0.
    func testPromotionLpFloorOverachievementCapsAtOne() {
        let standing = Self.makeStandingStub(
            myPoints: 5000,
            promotionLpFloor: 1200,
            peakDayMultiplier: 4,
            requiresCrownToPromote: true
        )
        XCTAssertEqual(standing.meetsPromotionLpFloor, true)
        XCTAssertEqual(standing.promotionLpFloorProgress ?? -1, 1.0, accuracy: 0.001)
    }

    // MARK: - Push allowlist

    func testChallengeLpAwardedIsInKnownNotificationTypes() {
        XCTAssertTrue(NotificationManager.knownNotificationTypes.contains("challenge_lp_awarded"),
                       "challenge_lp_awarded must be in knownNotificationTypes or taps log false-positive unknown-type errors")
    }

    // MARK: - Helpers

    /// Build a `ChallengeDetails` directly without round-tripping JSON. We
    /// bypass the private `start_date`/`end_date` string fields via
    /// decoding a canonical minimal payload + splicing the awards array.
    private static func makeDetailsStub(awards: [ChallengeLeagueAward]) -> ChallengeDetails {
        let awardsJSON = (try? JSONEncoder().encode(awards)).flatMap {
            String(data: $0, encoding: .utf8)
        } ?? "[]"
        let json = """
        {
            "challenge_id": "11111111-1111-1111-1111-111111111111",
            "challenge_type": "steps",
            "title": "Stub",
            "description": null,
            "daily_target": 10000,
            "total_target": null,
            "target_unit": "steps",
            "start_date": "2026-05-01",
            "end_date": "2026-05-07",
            "duration_days": 7,
            "status": "active",
            "created_at": "2026-05-01T00:00:00Z",
            "notify_on_opponent_complete": true,
            "participants": null,
            "daily_league_awards": \(awardsJSON)
        }
        """
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        guard let data = json.data(using: .utf8),
              let details = try? d.decode(ChallengeDetails.self, from: data) else {
            fatalError("ChallengeLeaguePointsTests.makeDetailsStub — decoder failed")
        }
        return details
    }

    /// Build a `LeagueStanding` with the new Sprint 4 fields set. We bypass
    /// the full leaderboard array for brevity; tests above only touch
    /// computed helpers that read `myPoints` + the three new optionals.
    private static func makeStandingStub(
        myPoints: Int,
        promotionLpFloor: Int,
        peakDayMultiplier: Int,
        requiresCrownToPromote: Bool
    ) -> LeagueStanding {
        let json = """
        {
            "group_id": "22222222-2222-2222-2222-222222222222",
            "tier_rank": 5,
            "tier_name": "Diamond",
            "tier_emoji": "💠",
            "tier_color": "#00BFFF",
            "promotion_count": 3,
            "relegation_count": 6,
            "week_start": "2026-04-27",
            "days_remaining": 3,
            "my_points": \(myPoints),
            "my_rank": 2,
            "group_size": 25,
            "leaderboard": [],
            "pending_league_points": 0,
            "shield_available": false,
            "top3_streak": 1,
            "crown_until": null,
            "peak_day": 3,
            "promotion_lp_floor": \(promotionLpFloor),
            "peak_day_multiplier": \(peakDayMultiplier),
            "requires_crown_to_promote": \(requiresCrownToPromote)
        }
        """
        guard let data = json.data(using: .utf8),
              let standing = try? JSONDecoder().decode(LeagueStanding.self, from: data) else {
            fatalError("ChallengeLeaguePointsTests.makeStandingStub — decoder failed")
        }
        return standing
    }
}
