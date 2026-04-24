-- ============================================================================
-- Fanout Backfill Correction — re-sweeps last 2 days on environments where
-- the original `20260521_challenge_progress_fanout.sql` ran before it was
-- patched.
-- ============================================================================
-- BUG IN ORIGINAL MIGRATION (2026-04-24):
--   The three triggers (`trg_fanout_*_challenge_progress`) are declared
--     AFTER INSERT OR UPDATE OF progress_value
--   Postgres only fires an `UPDATE OF col` trigger when `col` is in the
--   UPDATE's SET list. The original backfill used
--     SET updated_at = updated_at
--   which never puts `progress_value` in the SET list, so the backfill was
--   a silent no-op: existing rows from before the trigger was installed
--   stayed out of sync, which is why Paul showed 16k steps on the private
--   challenge leaderboard but a stale value (or "—") on the community
--   "10K Steps Daily" leaderboard on the morning of 2026-04-24.
--
-- FIX:
--   Self-assign `progress_value = progress_value` on every row from the
--   last 2 days. That DOES put `progress_value` in the SET list, the
--   trigger fires, and fanout executes. The trigger's `GREATEST()` semantic
--   guarantees no value decreases during the sweep, so this is safe to run
--   multiple times and order-independent.
--
-- ENVIRONMENTS IMPACTED:
--   Any environment where 20260521_challenge_progress_fanout.sql was
--   applied between its initial landing and the SET-clause patch. Running
--   this migration is a safe no-op on environments that picked up the
--   fixed version — rows just converge to their current (already-correct)
--   value via GREATEST().
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. Re-sweep group challenges (1v1 + squad)
-- ============================================================================
UPDATE challenge_daily_progress
SET progress_value = progress_value
WHERE progress_date >= (NOW() AT TIME ZONE 'UTC')::DATE - 1
  AND challenge_id IN (
      SELECT id FROM group_challenges
      WHERE challenge_type IN ('steps', 'active_minutes', 'calories')
  );

-- ============================================================================
-- 2. Re-sweep private challenges
-- ============================================================================
UPDATE private_challenge_daily_progress
SET progress_value = progress_value
WHERE progress_date >= (NOW() AT TIME ZONE 'UTC')::DATE - 1
  AND challenge_id IN (
      SELECT id FROM private_challenges
      WHERE challenge_type IN ('steps', 'active_minutes', 'calories')
  );

-- ============================================================================
-- 3. Re-sweep community challenges
-- ============================================================================
UPDATE community_challenge_daily_progress
SET progress_value = progress_value
WHERE progress_date >= (NOW() AT TIME ZONE 'UTC')::DATE - 1
  AND challenge_id IN (
      SELECT id FROM community_challenges
      WHERE challenge_type IN ('steps', 'active_minutes', 'calories')
  );

COMMIT;

-- ============================================================================
-- VERIFICATION
-- ============================================================================
DO $$
DECLARE
    v_group_rows      INT;
    v_private_rows    INT;
    v_community_rows  INT;
BEGIN
    -- Count rows in-scope for each surface so we know the sweep covered
    -- something on every surface. These are just informational totals —
    -- GREATEST() makes the value convergence the real success signal.
    SELECT COUNT(*) INTO v_group_rows
    FROM challenge_daily_progress cdp
    JOIN group_challenges gc ON gc.id = cdp.challenge_id
    WHERE cdp.progress_date >= (NOW() AT TIME ZONE 'UTC')::DATE - 1
      AND gc.challenge_type IN ('steps', 'active_minutes', 'calories');

    SELECT COUNT(*) INTO v_private_rows
    FROM private_challenge_daily_progress pcdp
    JOIN private_challenges pc ON pc.id = pcdp.challenge_id
    WHERE pcdp.progress_date >= (NOW() AT TIME ZONE 'UTC')::DATE - 1
      AND pc.challenge_type IN ('steps', 'active_minutes', 'calories');

    SELECT COUNT(*) INTO v_community_rows
    FROM community_challenge_daily_progress ccdp
    JOIN community_challenges cc ON cc.id = ccdp.challenge_id
    WHERE ccdp.progress_date >= (NOW() AT TIME ZONE 'UTC')::DATE - 1
      AND cc.challenge_type IN ('steps', 'active_minutes', 'calories');

    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '✅ FANOUT BACKFILL CORRECTION APPLIED';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '';
    RAISE NOTICE '📌 Rows touched (last 2 days, shared metrics):';
    RAISE NOTICE '   • group / 1v1 (challenge_daily_progress):          %', v_group_rows;
    RAISE NOTICE '   • private     (private_challenge_daily_progress):  %', v_private_rows;
    RAISE NOTICE '   • community   (community_challenge_daily_progress):%', v_community_rows;
    RAISE NOTICE '';
    RAISE NOTICE '🎯 Expected state:';
    RAISE NOTICE '   For every (user, date) with at least one write across';
    RAISE NOTICE '   the three tables, the value in all three tables for';
    RAISE NOTICE '   that user/date is now MAX(all observed values).';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
END $$;
