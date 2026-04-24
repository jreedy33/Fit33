-- ============================================================================
-- Challenge Progress Fanout — cross-table consistency for shared metrics
-- ============================================================================
-- PROBLEM (2026-04-24, post bug-intel 6be18e3a fix):
--   A user's "steps today" is ONE number, but Fit33 stores it in three
--   independent tables (challenge_daily_progress for 1v1/group,
--   private_challenge_daily_progress, community_challenge_daily_progress).
--   Each table is populated by its own iOS service (`ChallengeService`,
--   `PrivateChallengeService`, `CommunityChallengeService`) that reads a
--   shared HealthKit value and pushes independently.
--
--   If any one service bails early (`guard !myChallenges.isEmpty`,
--   uninitialized on cold wake, throttled), its table gets no write and the
--   leaderboards on that surface show stale or missing data while the other
--   two surfaces show current data — e.g. Paul at 15,718 in Private
--   "Olean Squad 10k" but "—" in Community "10K Steps Daily" on the exact
--   same morning.
--
-- FIX:
--   AFTER INSERT/UPDATE trigger on each of the three daily-progress tables
--   for cumulative shared metrics (`steps`, `active_minutes`, `calories`).
--   When any one of them gets a write for (user_id, progress_date, type), the
--   trigger UPSERTs the same `progress_value` into the OTHER two tables for
--   every challenge of the same type that the user is an active member of.
--   GREATEST() semantics preserved — stale lower values never overwrite a
--   higher cumulative value. Recursion is blocked via `pg_trigger_depth()`.
--
-- NOT FIXED BY THIS MIGRATION (on purpose):
--   Correctness of the pushed VALUE is a client concern (HealthKit
--   `@Published` cache freshness). See `DATA_BACKEND_AGENT.md` invariants
--   #46 (HK force-refresh before push) and #47 (`steps` / `active_minutes`
--   always `allowDecrease=true`), which ship in the 2026-04-24 client build
--   alongside `20260520_challenge_daily_reset_caller_tz.sql`. Fanout makes
--   the LEADERBOARDS agree; the client guards make the VALUE correct.
--
-- PERFORMANCE:
--   The fanout UPSERTs are bounded to the user's own membership rows for
--   the challenge_type in question. For a typical user with ~5 step
--   challenges across the three tables, one write triggers 2 small
--   UPSERTs. Indexes `(challenge_id, user_id)` on all three participant
--   tables already exist (see community_challenges_migration + private
--   migration + challenge_participants index).
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. Helper: compute target_hit for a given challenge_type + user + value
-- ============================================================================
-- Each table has its own parent with its own `daily_target`. We look up the
-- target per challenge_id in the fanout target table, not via this helper —
-- this is just documentation that target_hit is per-challenge, not per-user.
-- ============================================================================

-- ============================================================================
-- 2. Fanout trigger function (parameterized via TG_TABLE_NAME)
-- ============================================================================
CREATE OR REPLACE FUNCTION fanout_challenge_progress()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_challenge_type TEXT;
    v_source TEXT := 'fanout:' || TG_TABLE_NAME;
BEGIN
    -- Block recursion: if we're already inside a trigger chain, don't re-fanout.
    IF pg_trigger_depth() > 1 THEN
        RETURN NEW;
    END IF;

    -- Resolve the parent challenge's `challenge_type`. Each table has a
    -- different parent (group_challenges / private_challenges /
    -- community_challenges), so dispatch on TG_TABLE_NAME.
    IF TG_TABLE_NAME = 'challenge_daily_progress' THEN
        SELECT challenge_type INTO v_challenge_type
        FROM group_challenges WHERE id = NEW.challenge_id;
    ELSIF TG_TABLE_NAME = 'private_challenge_daily_progress' THEN
        SELECT challenge_type INTO v_challenge_type
        FROM private_challenges WHERE id = NEW.challenge_id;
    ELSIF TG_TABLE_NAME = 'community_challenge_daily_progress' THEN
        SELECT challenge_type INTO v_challenge_type
        FROM community_challenges WHERE id = NEW.challenge_id;
    ELSE
        RETURN NEW;
    END IF;

    -- Only fanout for cumulative HealthKit-derived metrics that share a
    -- single underlying source-of-truth per user per day. protein / hydrate
    -- are NOT fanned out — those are per-challenge-context meal logs /
    -- hydration that users may legitimately track differently per challenge.
    IF v_challenge_type IS NULL
       OR v_challenge_type NOT IN ('steps', 'active_minutes', 'calories') THEN
        RETURN NEW;
    END IF;

    -- Fanout to challenge_daily_progress (1v1 + group) when source is elsewhere.
    IF TG_TABLE_NAME != 'challenge_daily_progress' THEN
        INSERT INTO challenge_daily_progress (
            challenge_id, user_id, progress_date, progress_value,
            target_hit, source, updated_at
        )
        SELECT
            cp.challenge_id, NEW.user_id, NEW.progress_date, NEW.progress_value,
            (gc.daily_target IS NOT NULL AND NEW.progress_value >= gc.daily_target),
            v_source, NOW()
        FROM challenge_participants cp
        JOIN group_challenges gc ON gc.id = cp.challenge_id
        WHERE cp.user_id = NEW.user_id
          AND cp.status = 'accepted'
          AND gc.challenge_type = v_challenge_type
          AND gc.status IN ('active', 'pending')
        ON CONFLICT (challenge_id, user_id, progress_date) DO UPDATE SET
            progress_value = GREATEST(challenge_daily_progress.progress_value, EXCLUDED.progress_value),
            target_hit = CASE
                WHEN EXCLUDED.progress_value > challenge_daily_progress.progress_value
                THEN EXCLUDED.target_hit
                ELSE challenge_daily_progress.target_hit
            END,
            source = EXCLUDED.source,
            updated_at = NOW();
    END IF;

    -- Fanout to private_challenge_daily_progress.
    IF TG_TABLE_NAME != 'private_challenge_daily_progress' THEN
        INSERT INTO private_challenge_daily_progress (
            challenge_id, user_id, progress_date, progress_value,
            target_hit, source, updated_at
        )
        SELECT
            pcm.challenge_id, NEW.user_id, NEW.progress_date, NEW.progress_value,
            (pc.daily_target IS NOT NULL AND NEW.progress_value >= pc.daily_target),
            v_source, NOW()
        FROM private_challenge_members pcm
        JOIN private_challenges pc ON pc.id = pcm.challenge_id
        WHERE pcm.user_id = NEW.user_id
          AND pcm.is_active = TRUE
          AND pc.challenge_type = v_challenge_type
          AND pc.status = 'active'
        ON CONFLICT (challenge_id, user_id, progress_date) DO UPDATE SET
            progress_value = GREATEST(private_challenge_daily_progress.progress_value, EXCLUDED.progress_value),
            target_hit = CASE
                WHEN EXCLUDED.progress_value > private_challenge_daily_progress.progress_value
                THEN EXCLUDED.target_hit
                ELSE private_challenge_daily_progress.target_hit
            END,
            source = EXCLUDED.source,
            updated_at = NOW();
    END IF;

    -- Fanout to community_challenge_daily_progress.
    IF TG_TABLE_NAME != 'community_challenge_daily_progress' THEN
        INSERT INTO community_challenge_daily_progress (
            challenge_id, user_id, progress_date, progress_value,
            target_hit, source, updated_at
        )
        SELECT
            ccp.challenge_id, NEW.user_id, NEW.progress_date, NEW.progress_value,
            (cc.daily_target IS NOT NULL AND NEW.progress_value >= cc.daily_target),
            v_source, NOW()
        FROM community_challenge_participants ccp
        JOIN community_challenges cc ON cc.id = ccp.challenge_id
        WHERE ccp.user_id = NEW.user_id
          AND ccp.is_active = TRUE
          AND cc.challenge_type = v_challenge_type
          AND cc.status = 'active'
        ON CONFLICT (challenge_id, user_id, progress_date) DO UPDATE SET
            progress_value = GREATEST(community_challenge_daily_progress.progress_value, EXCLUDED.progress_value),
            target_hit = CASE
                WHEN EXCLUDED.progress_value > community_challenge_daily_progress.progress_value
                THEN EXCLUDED.target_hit
                ELSE community_challenge_daily_progress.target_hit
            END,
            source = EXCLUDED.source,
            updated_at = NOW();
    END IF;

    RETURN NEW;
END;
$$;

-- ============================================================================
-- 3. Attach the trigger to all three daily-progress tables
-- ============================================================================
DROP TRIGGER IF EXISTS trg_fanout_challenge_progress ON challenge_daily_progress;
CREATE TRIGGER trg_fanout_challenge_progress
    AFTER INSERT OR UPDATE OF progress_value ON challenge_daily_progress
    FOR EACH ROW
    EXECUTE FUNCTION fanout_challenge_progress();

DROP TRIGGER IF EXISTS trg_fanout_private_challenge_progress ON private_challenge_daily_progress;
CREATE TRIGGER trg_fanout_private_challenge_progress
    AFTER INSERT OR UPDATE OF progress_value ON private_challenge_daily_progress
    FOR EACH ROW
    EXECUTE FUNCTION fanout_challenge_progress();

DROP TRIGGER IF EXISTS trg_fanout_community_challenge_progress ON community_challenge_daily_progress;
CREATE TRIGGER trg_fanout_community_challenge_progress
    AFTER INSERT OR UPDATE OF progress_value ON community_challenge_daily_progress
    FOR EACH ROW
    EXECUTE FUNCTION fanout_challenge_progress();

-- ============================================================================
-- 4. One-time backfill: fanout every EXISTING row for (today, yesterday)
--    across the three tables so current leaderboards become consistent
--    without waiting for the next client push.
--
--    Strategy: iterate rows in the three tables for the last 2 days and
--    trigger a no-op UPDATE that bumps updated_at — the AFTER UPDATE trigger
--    then does the fanout. Bounded to 2 days so this stays fast even on
--    large tables.
-- ============================================================================

-- Touch every row from the last 2 days: the trigger takes care of the rest.
-- GREATEST() guarantees no value decreases during the sweep, so this is safe
-- to re-run and the order of rows doesn't matter.
--
-- IMPORTANT: the trigger is declared `AFTER UPDATE OF progress_value`, which
-- means Postgres only fires it when `progress_value` appears in the UPDATE's
-- SET list. A self-assignment (`progress_value = progress_value`) is enough
-- to satisfy that — a `SET updated_at = updated_at` bump would NOT fire it.
-- (See 20260522_fanout_backfill_fix.sql for the post-hoc correction on
-- environments where the original broken SET clause was already applied.)
UPDATE challenge_daily_progress
SET progress_value = progress_value   -- puts progress_value in SET list → trigger fires
WHERE progress_date >= (NOW() AT TIME ZONE 'UTC')::DATE - 1
  AND challenge_id IN (
      SELECT id FROM group_challenges
      WHERE challenge_type IN ('steps', 'active_minutes', 'calories')
  );

UPDATE private_challenge_daily_progress
SET progress_value = progress_value
WHERE progress_date >= (NOW() AT TIME ZONE 'UTC')::DATE - 1
  AND challenge_id IN (
      SELECT id FROM private_challenges
      WHERE challenge_type IN ('steps', 'active_minutes', 'calories')
  );

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
    v_trigger_count INT;
BEGIN
    SELECT COUNT(*) INTO v_trigger_count
    FROM pg_trigger
    WHERE tgname IN (
        'trg_fanout_challenge_progress',
        'trg_fanout_private_challenge_progress',
        'trg_fanout_community_challenge_progress'
    );

    IF v_trigger_count <> 3 THEN
        RAISE EXCEPTION 'Expected 3 fanout triggers, found %', v_trigger_count;
    END IF;

    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '✅ CHALLENGE PROGRESS FANOUT DEPLOYED';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '';
    RAISE NOTICE '📌 Triggers: % across the three daily-progress tables', v_trigger_count;
    RAISE NOTICE '🎯 Cumulative shared metrics now consistent in real-time:';
    RAISE NOTICE '   • steps / active_minutes / calories';
    RAISE NOTICE '';
    RAISE NOTICE '📝 Notes:';
    RAISE NOTICE '   • protein + hydrate intentionally NOT fanned out (per-challenge)';
    RAISE NOTICE '   • Recursion blocked via pg_trigger_depth() > 1';
    RAISE NOTICE '   • GREATEST() preserved — lower values never overwrite';
    RAISE NOTICE '   • Backfill swept last 2 days so existing rows converge';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
END $$;
