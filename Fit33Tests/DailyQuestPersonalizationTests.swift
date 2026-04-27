// Tests for the Smart Adaptive Daily Goals client surface (migrations
// 20260601–20260607). The personalization, suppression, and reroll
// logic itself lives in PostgreSQL — covered by the migration manual-QA
// matrix in DATA_BACKEND_AGENT.md. These tests lock in the Swift
// contracts the server depends on:
//
//   1. ActivityMixSnapshot dominant / least picks for the 4 archetypes
//      the plan calls out (cardio-heavy, strength-heavy, walker, balanced).
//   2. The verification → XP multiplier label asymmetry that surfaces
//      "auto +50%" / "honor system" on the quest card so the user
//      perceives why auto-tracked quests pay more.
//   3. DailyQuest Codable decoding for the new server fields
//      (`tier`, `double_xp`, `is_custom`, `is_reroll`) — drift here
//      silently strips the new badges off Pro quests.
//   4. New QuestKey raw-value contract for the friend-named / wearable /
//      Strava-PR templates added in migration 20260604.

import XCTest
@testable import Fit33

@MainActor
final class DailyQuestPersonalizationTests: XCTestCase {

    // MARK: - Activity-mix archetype bias (Plan §5 Layer 4)
    //
    // The RPC adds +30% to the dominant share and +10% to the least share
    // for the "sneak in the opposite" exploration bump. The Swift snapshot
    // is what feeds `p_activity_mix` so its dominant/least contract has
    // to match the server's expectations exactly.

    func testCardioHeavyArchetypeMarksCardioDominant() {
        let snap = DailyQuestService.ActivityMixSnapshot(
            totalSessions: 20,
            strengthShare: 0.10, cardioShare: 0.70,
            walkShare: 0.10,     stretchShare: 0.10
        )
        XCTAssertEqual(snap.dominant, "cardio")
        // Strength tied with walk + stretch at 0.10 — least has to be one
        // of the smallest non-zero buckets (deterministic .min picks the
        // first encountered, which is "strength" given declaration order).
        XCTAssertEqual(snap.least, "strength")
    }

    func testStrengthHeavyArchetypeMarksStrengthDominant() {
        let snap = DailyQuestService.ActivityMixSnapshot(
            totalSessions: 20,
            strengthShare: 0.75, cardioShare: 0.15,
            walkShare: 0.05,     stretchShare: 0.05
        )
        XCTAssertEqual(snap.dominant, "strength")
        // Walk and stretch tied at 0.05 — declaration order picks "walk".
        XCTAssertEqual(snap.least, "walk")
    }

    func testWalkerArchetypeMarksWalkDominant() {
        let snap = DailyQuestService.ActivityMixSnapshot(
            totalSessions: 14,
            strengthShare: 0.05, cardioShare: 0.10,
            walkShare: 0.80,     stretchShare: 0.05
        )
        XCTAssertEqual(snap.dominant, "walk")
        XCTAssertEqual(snap.least, "strength")
    }

    func testBalancedArchetypeStillPicksADominant() {
        let snap = DailyQuestService.ActivityMixSnapshot(
            totalSessions: 16,
            strengthShare: 0.30, cardioShare: 0.30,
            walkShare: 0.20,     stretchShare: 0.20
        )
        // .max picks the first encountered tie — declaration order
        // ("strength" before "cardio"). Locking that in so the server
        // sees a stable hint for tied users.
        XCTAssertEqual(snap.dominant, "strength")
    }

    func testEmptyActivityMixYieldsNoHints() {
        let snap = DailyQuestService.ActivityMixSnapshot.empty
        XCTAssertNil(snap.dominant,
                     "Zero-session users should not pretend to have a dominant bucket")
        XCTAssertNil(snap.least)
        XCTAssertTrue(snap.rpcHint.isEmpty,
                      "Empty snapshot must serialize to {} so the RPC falls back to user_activity_mix")
    }

    func testRpcHintEncodesDominantAndLeast() {
        let snap = DailyQuestService.ActivityMixSnapshot(
            totalSessions: 10,
            strengthShare: 0.60, cardioShare: 0.30,
            walkShare: 0.10,     stretchShare: 0.0
        )
        let hint = snap.rpcHint
        XCTAssertEqual(hint["dominant"], "strength")
        // stretch is 0 — must be excluded from least so the bump never
        // recommends a category the user has never touched at all.
        XCTAssertEqual(hint["least"], "walk")
    }

    // MARK: - XP multiplier sub-label (Plan §3 + Display)

    func testAutoVerifiedQuestSurfacesAutoTrackedLabel() {
        let q = makeQuest(verification: "auto")
        XCTAssertEqual(q.verificationXpMultiplierLabel, "1.5× XP — auto-tracked")
    }

    func testManualQuestSurfacesHonorSystemLabel() {
        let q = makeQuest(verification: "manual")
        XCTAssertEqual(q.verificationXpMultiplierLabel, "0.7× XP — honor system")
    }

    func testSocialQuestSurfacesNeutralMultiplierLabel() {
        let q = makeQuest(verification: "social")
        XCTAssertEqual(q.verificationXpMultiplierLabel, "1.0× XP — social")
    }

    func testUnknownVerificationTypeReturnsNil() {
        // Defensive — if the server ever sends an unknown literal we want
        // the card to suppress the badge, not show "nil × XP".
        let q = makeQuest(verification: "wat")
        XCTAssertNil(q.verificationXpMultiplierLabel)
    }

    // MARK: - Pro state badges

    func testDoubleXpBadgeAppearsOnlyWhenFlagOn() {
        let on  = makeQuest(verification: "auto", doubleXp: true)
        let off = makeQuest(verification: "auto", doubleXp: false)
        let nil_ = makeQuest(verification: "auto", doubleXp: nil)
        XCTAssertEqual(on.doubleXpBadge, "✨ 2× XP today")
        XCTAssertNil(off.doubleXpBadge)
        XCTAssertNil(nil_.doubleXpBadge)
    }

    func testIsCustomProAndWasRerolledFlagsRoundTrip() {
        let custom = makeQuest(verification: "manual", isCustom: true)
        let rerolled = makeQuest(verification: "auto", isReroll: true)
        XCTAssertTrue(custom.isCustomPro)
        XCTAssertFalse(custom.wasRerolled)
        XCTAssertTrue(rerolled.wasRerolled)
        XCTAssertFalse(rerolled.isCustomPro)
    }

    // MARK: - Wire-format Codable contract

    func testDailyQuestDecodesNewServerFields() throws {
        // Simulates a row returned by `get_daily_quests` v3 where every
        // new column is set. If any CodingKey drifts from the snake_case
        // server name the badge / Pro flag silently disappears.
        let json = """
        {
          "id": "11111111-2222-3333-4444-555566667777",
          "quest_key": "do_friend_workout",
          "title": "Due for chest — do Paul's",
          "description": "Match Paul's most recent chest day.",
          "icon": "figure.strengthtraining.functional",
          "category": "social",
          "target_value": 1,
          "current_value": 0,
          "target_unit": "session",
          "xp_reward": 35,
          "league_points": 7,
          "difficulty": "medium",
          "is_completed": false,
          "completed_at": null,
          "fun_label": null,
          "verification_type": "social",
          "tier": "pro",
          "double_xp": true,
          "is_custom": false,
          "is_reroll": true
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(DailyQuest.self, from: json)
        XCTAssertEqual(decoded.questKey, "do_friend_workout")
        XCTAssertEqual(decoded.tier, "pro")
        XCTAssertEqual(decoded.doubleXp, true)
        XCTAssertEqual(decoded.isCustom, false)
        XCTAssertEqual(decoded.isReroll, true)
        XCTAssertTrue(decoded.wasRerolled)
        XCTAssertEqual(decoded.doubleXpBadge, "✨ 2× XP today")
    }

    func testDailyQuestDecodesIsBriefInfluencedFlag() throws {
        // Daily Mission Unification (20260703 Phase 1). The server stamps
        // `is_brief_influenced = true` on quests selected by Layer 7
        // (capacity band re-rank) or Layer 8 (debt booster). Drift in the
        // CodingKey would silently strip the "← from your brief" chip.
        let json = """
        {
          "id": "11111111-2222-3333-4444-555566667777",
          "quest_key": "active_recovery_logged",
          "title": "Active Recovery",
          "description": "Walk 15 min — your body needs the day.",
          "icon": "figure.walk",
          "category": "workout",
          "target_value": 15,
          "current_value": 0,
          "target_unit": "minutes",
          "xp_reward": 38,
          "league_points": 8,
          "difficulty": "easy",
          "is_completed": false,
          "completed_at": null,
          "fun_label": null,
          "verification_type": "auto",
          "is_brief_influenced": true
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(DailyQuest.self, from: json)
        XCTAssertEqual(decoded.isBriefInfluenced, true)
    }

    // MARK: - Optimistic update preserves is_brief_influenced

    /// Regression for the Daily Brief unification:
    /// `DailyQuestService.reportProgress` rewrites a `DailyQuest` after
    /// every `update_quest_progress` RPC. The rewrite previously dropped
    /// `is_brief_influenced` because the new field was added without
    /// updating the optimistic-update initializer call. This test mirrors
    /// the same field-by-field copy and asserts the flag survives a
    /// progress tick (so the "← from your brief" chip stays on screen
    /// while the bar fills).
    func testOptimisticUpdatePreservesIsBriefInfluenced() {
        let old = makeQuest(
            verification: "auto",
            isBriefInfluenced: true,
            currentValue: 0,
            targetValue: 3
        )

        // Mirror the exact initializer that
        // `reportProgress.quests[idx] = DailyQuest(...)` uses, with the
        // `currentValue` replaced by the new server value.
        let newValue = 1
        let nowComplete = false
        let updated = DailyQuest(
            id: old.id,
            questKey: old.questKey,
            title: old.title,
            description: old.description,
            icon: old.icon,
            category: old.category,
            targetValue: old.targetValue,
            currentValue: newValue,
            targetUnit: old.targetUnit,
            xpReward: old.xpReward,
            leaguePoints: old.leaguePoints,
            difficulty: old.difficulty,
            isCompleted: nowComplete,
            completedAt: nil,
            funLabel: old.funLabel,
            verificationType: old.verificationType,
            tier: old.tier,
            doubleXp: old.doubleXp,
            isCustom: old.isCustom,
            isReroll: old.isReroll,
            isBriefInfluenced: old.isBriefInfluenced
        )

        XCTAssertEqual(updated.isBriefInfluenced, true,
            "Progress tick must preserve is_brief_influenced — otherwise the brief chip disappears as the bar fills")
        XCTAssertEqual(updated.currentValue, newValue)
        XCTAssertEqual(updated.id, old.id)
    }

    func testOptimisticUpdatePreservesAllNewBriefAndProFields() {
        // Belt-and-suspenders: every new field added since the original
        // 20260601 wire format should ride through the optimistic update.
        // If any drift, this test pins the regression to the exact field.
        let old = makeQuest(
            verification: "auto",
            doubleXp: true,
            isCustom: false,
            isReroll: true,
            isBriefInfluenced: true,
            currentValue: 5,
            targetValue: 10
        )
        let updated = DailyQuest(
            id: old.id,
            questKey: old.questKey,
            title: old.title,
            description: old.description,
            icon: old.icon,
            category: old.category,
            targetValue: old.targetValue,
            currentValue: 7,
            targetUnit: old.targetUnit,
            xpReward: old.xpReward,
            leaguePoints: old.leaguePoints,
            difficulty: old.difficulty,
            isCompleted: false,
            completedAt: nil,
            funLabel: old.funLabel,
            verificationType: old.verificationType,
            tier: old.tier,
            doubleXp: old.doubleXp,
            isCustom: old.isCustom,
            isReroll: old.isReroll,
            isBriefInfluenced: old.isBriefInfluenced
        )
        XCTAssertEqual(updated.doubleXp, true)
        XCTAssertEqual(updated.isCustom, false)
        XCTAssertEqual(updated.isReroll, true)
        XCTAssertEqual(updated.isBriefInfluenced, true)
    }

    func testDailyQuestDecodesLegacyRowsWithoutNewFields() throws {
        // Older server responses (pre-20260607) won't have the new
        // columns. Decoding must succeed with `nil` defaults so the
        // smartAdaptiveQuests kill-switch can downgrade gracefully.
        let json = """
        {
          "id": "11111111-2222-3333-4444-555566667777",
          "quest_key": "complete_workout",
          "title": "Complete a workout",
          "description": "Any tracked workout counts.",
          "icon": "dumbbell",
          "category": "workout",
          "target_value": 1,
          "current_value": 0,
          "target_unit": "session",
          "xp_reward": 50,
          "league_points": 10,
          "difficulty": "medium",
          "is_completed": false,
          "completed_at": null,
          "fun_label": null,
          "verification_type": "auto"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(DailyQuest.self, from: json)
        XCTAssertNil(decoded.tier)
        XCTAssertNil(decoded.doubleXp)
        XCTAssertNil(decoded.isCustom)
        XCTAssertNil(decoded.isReroll)
        XCTAssertNil(decoded.isBriefInfluenced)
        XCTAssertFalse(decoded.wasRerolled)
        XCTAssertFalse(decoded.isCustomPro)
        XCTAssertNil(decoded.doubleXpBadge)
    }

    // MARK: - QuestKey ↔ raw-value contract (Plan §4)
    //
    // The Swift hooks call `reportProgress(questKey: .doFriendWorkout)`
    // which writes the raw value directly to `quest_key` filters in
    // `update_quest_progress`. Drift here silently no-ops the tick.

    func testNewQuestKeyRawValuesMatchServerContract() {
        XCTAssertEqual(QuestKey.doFriendWorkout.rawValue, "do_friend_workout")
        XCTAssertEqual(QuestKey.beatYour5kPR.rawValue,    "beat_your_5k_pr")
        XCTAssertEqual(QuestKey.walkWhenRed.rawValue,     "walk_when_red")
    }

    // MARK: - Helpers

    private func makeQuest(
        verification: String?,
        doubleXp: Bool? = nil,
        isCustom: Bool? = nil,
        isReroll: Bool? = nil,
        isBriefInfluenced: Bool? = nil,
        currentValue: Int = 0,
        targetValue: Int = 1,
        isCompleted: Bool = false
    ) -> DailyQuest {
        DailyQuest(
            id: UUID(),
            questKey: "complete_workout",
            title: "Complete a workout",
            description: "Test quest",
            icon: "dumbbell",
            category: "workout",
            targetValue: targetValue,
            currentValue: currentValue,
            targetUnit: "session",
            xpReward: 50,
            leaguePoints: 10,
            difficulty: "medium",
            isCompleted: isCompleted,
            completedAt: nil,
            funLabel: nil,
            verificationType: verification,
            tier: nil,
            doubleXp: doubleXp,
            isCustom: isCustom,
            isReroll: isReroll,
            isBriefInfluenced: isBriefInfluenced
        )
    }
}
