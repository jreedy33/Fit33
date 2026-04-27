-- ============================================================================
-- 20260630 — Retire daily quests whose pass/fail depends on ANOTHER user
--
-- Follow-up to 20260610 + 20260611 (PE invariant 19d watch-list). Two more
-- quests fail the "actionable today, fully under the user's control" test:
--
--   * top_3_league       "Podium Finish"  (20260324_new_quest_templates.sql)
--   * beat_friend_steps  "Step Showdown"  (20260324_new_quest_templates.sql)
--
-- WHY (Joe, 2026-04-27 — Daily Goals dashboard screenshot):
--   "I don't like the podium finish goal — finishing top-3 seems out of your
--    control if the person ahead of you has higher XP daily goals, does more
--    workouts, etc. That's heavily based on what someone else does — I want
--    daily goals to be specific to the user."
--
--   Both quests gate completion on a SECOND user's behavior:
--
--     * `top_3_league` — verifies via `WeeklyLeagueService.standing.myRank`,
--       which is a function of every other league participant's XP for the
--       week. A user can have a perfect XP day and still drop a slot because
--       a rival posted higher. Same anti-pattern family as 20260610's
--       passive sensor-state quests (PE 19d): the user has zero levers
--       today that DETERMINISTICALLY moves the needle.
--
--     * `beat_friend_steps` — verifies by comparing the user's step count
--       to a friend's step count via the active steps challenge. Even when
--       the user blows past their own step goal, they can still "fail" the
--       quest if the friend walked more. The user-takeable lever is "walk
--       more steps", which is already covered by `walk_*_steps` /
--       `hit_step_goal` (every step quest target is a fixed number under
--       the user's sole control). Step-vs-friend competition lives in the
--       challenge surface itself; it shouldn't double-up as a daily quest.
--
-- WHAT THIS MIGRATION DOES:
--
--   1. SOFT-disables both templates (`is_active = FALSE`). Templates stay on
--      disk so historical `user_daily_quests` rows still resolve to a row
--      for title/icon lookups (PE invariant 19d: never DELETE templates).
--
--   2. CLEANS UP today's not-yet-completed `user_daily_quests` rows for both
--      keys so users staring at the bad quest right now (e.g. Joe in the
--      screenshot — "Podium Finish · Top 3 — you're #2 · Not yet") aren't
--      stuck with it until midnight. Following the 20260611 precedent for
--      log_readiness_am: only TODAY's incomplete rows; preserve historical
--      rows for streak/audit. Users will have 2 slots today instead of 3
--      (the dashboard handles a smaller slate gracefully) and a fresh 3-slot
--      slate tomorrow drawn from the post-disable pool.
--
--      We do NOT regenerate the slate today (`get_daily_quests` short-
--      circuits at `IF v_quest_count = 0`, so we'd have to wipe ALL three
--      rows for the day — that would torch any in-progress XP/streak credit
--      the user already earned on slot 1). 2-slot day is the lesser evil.
--
-- iOS notes:
--   * `Fit33/DailyQuestService.swift::QuestKey` cases `top3League` and
--     `beatFriendSteps` STAY (PE invariant 19d: backwards-compat for
--     historical rows). Same for the dynamic-description and
--     destination-routing branches in `Fit33/DailyQuestViews.swift`.
--   * No verifier removals — both quests had iOS-side state-driven
--     descriptions, not a server-side verifier RPC, so there's nothing
--     to drop from `verify_*_quests_for_today`.
--
-- DESIGN INVARIANT (extends PE 19d / FE 20a):
--   Daily quests must be 100% under the USER's own control today. Any quest
--   whose pass/fail is gated on a SECOND user's behavior (league rank,
--   beating a friend's count, finishing top-N of a leaderboard) is the
--   same anti-pattern as overnight-sensor passive quests — the user has
--   no deterministic lever, just hopes the other person under-performs.
--   Competition belongs on the challenge / league surfaces themselves,
--   not in the Daily Goals slate.
--
-- Idempotent: re-running flips `is_active` back to FALSE (no-op) and the
-- DELETE … WHERE is_completed = FALSE is harmless on re-run.
-- ============================================================================

BEGIN;

-- 1. Soft-disable both templates -----------------------------------------
UPDATE quest_templates
   SET is_active = FALSE
 WHERE quest_key IN ('top_3_league', 'beat_friend_steps');

-- 2. Clean up today's in-flight rows so users see a fresh slate ----------
-- Only DELETE incomplete rows; completed rows stay so XP/streak credit
-- (if somehow earned today) is preserved. Date filter uses UTC ±1 day to
-- cover every user timezone without a per-user lookup (same shape as the
-- 20260619 catch-up block).
DELETE FROM user_daily_quests
 WHERE quest_key IN ('top_3_league', 'beat_friend_steps')
   AND is_completed = FALSE
   AND quest_date >= ((now() AT TIME ZONE 'UTC')::DATE - INTERVAL '1 day')
   AND quest_date <= ((now() AT TIME ZONE 'UTC')::DATE + INTERVAL '1 day');

COMMIT;

-- ─── Verification ─────────────────────────────────────────────────────────
-- SELECT quest_key, title, is_active
--   FROM quest_templates
--  WHERE quest_key IN ('top_3_league', 'beat_friend_steps')
--  ORDER BY quest_key;
-- Expected: both rows present with is_active=FALSE.
--
-- SELECT COUNT(*) FROM user_daily_quests
--  WHERE quest_key IN ('top_3_league', 'beat_friend_steps')
--    AND quest_date = current_date
--    AND is_completed = FALSE;
-- Expected: 0 (post-cleanup).
