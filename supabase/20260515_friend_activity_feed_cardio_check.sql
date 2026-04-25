-- ============================================================================
-- 20260515_friend_activity_feed_cardio_check.sql
-- ============================================================================
-- Q2-97 Bug-Intel Sweep Cluster B — 2026-04-23 follow-up
--
-- Resolves: e3388d0313f3684927989494c3c72464 — Social activity feed constraint violation (Report 18 / 04-25 audit)
-- Resolves: b66f6c070ced888a9dc85867ec79ed1b — Social cardio activity violates constraint, log variant (Report 26 / 04-25 audit)
--
-- Fixes the 23514 CHECK constraint violation surfaced by Bug Intelligence
-- report `b66f6c07` ("Social cardio activity violates constraint"):
--
--   PostgrestError code 23514: new row for relation "friend_activity_feed"
--   violates check constraint "friend_activity_feed_activity_type_check"
--
-- Root cause: migration 20260418_post_cardio_activity.sql introduced the
-- `post_cardio_activity` RPC, which inserts rows with
-- `activity_type = 'cardio_completed'`. But the original CHECK constraint
-- from 20260307_friend_activity_feed.sql only allowed:
--   'workout_completed', 'streak_milestone', 'level_up',
--   'achievement_unlocked', 'challenge_won'
--
-- Every cardio session posted to the friend feed has been failing since
-- the `post_cardio_activity` RPC shipped.
--
-- This migration:
--   1. Drops the stale CHECK constraint (if present) idempotently.
--   2. Re-adds it with the full set of activity_type values the app writes,
--      including 'cardio_completed'.
--   3. Ends with a fail-loud DO $$ block that verifies the constraint is
--      present and names every allowed value — future additions to the
--      enum should bump this migration.
--
-- Paired Swift: `Fit33/FriendActivityFeedView.swift` postCardioActivity
-- catch block is upgraded to NetworkErrorClassifier.log with op +
-- endpoint + startedAt + userId so a residual 23514 lands with pg_code in
-- the bug_intelligence payload (not collapsed into "Failed to post cardio
-- activity").
-- ============================================================================

BEGIN;

-- Guard against missing table on staging / fresh clones.
DO $$
BEGIN
    IF to_regclass('public.friend_activity_feed') IS NULL THEN
        RAISE NOTICE '[20260515] friend_activity_feed table not present — skipping';
        RETURN;
    END IF;

    -- Drop any legacy CHECK constraint by name. 20260307_friend_activity_feed
    -- used the auto-generated name "friend_activity_feed_activity_type_check".
    IF EXISTS (
        SELECT 1
          FROM pg_constraint
         WHERE conname = 'friend_activity_feed_activity_type_check'
           AND conrelid = 'public.friend_activity_feed'::regclass
    ) THEN
        ALTER TABLE friend_activity_feed
            DROP CONSTRAINT friend_activity_feed_activity_type_check;
        RAISE NOTICE '[20260515] Dropped stale friend_activity_feed_activity_type_check';
    END IF;

    -- Re-add the constraint with the full allowed set.
    ALTER TABLE friend_activity_feed
        ADD CONSTRAINT friend_activity_feed_activity_type_check
        CHECK (activity_type IN (
            'workout_completed',
            'cardio_completed',
            'streak_milestone',
            'level_up',
            'achievement_unlocked',
            'challenge_won'
        ));

    RAISE NOTICE '[20260515] friend_activity_feed_activity_type_check rebuilt with cardio_completed';
END $$;

-- =========================================================================
-- Fail-loud audit — verify the constraint ended up in the expected shape.
-- SUPABASE_AGENT invariant #29: audit migrations end with a DO $$ that
-- RAISE EXCEPTIONs on regression so the signal isn't lost.
-- =========================================================================

DO $$
DECLARE
    constraint_src TEXT;
    required_values TEXT[] := ARRAY[
        'workout_completed',
        'cardio_completed',
        'streak_milestone',
        'level_up',
        'achievement_unlocked',
        'challenge_won'
    ];
    missing_value TEXT;
BEGIN
    IF to_regclass('public.friend_activity_feed') IS NULL THEN
        RETURN;
    END IF;

    SELECT pg_get_constraintdef(oid)
      INTO constraint_src
      FROM pg_constraint
     WHERE conname = 'friend_activity_feed_activity_type_check'
       AND conrelid = 'public.friend_activity_feed'::regclass;

    IF constraint_src IS NULL THEN
        RAISE EXCEPTION '[20260515] friend_activity_feed_activity_type_check missing after migration';
    END IF;

    FOREACH missing_value IN ARRAY required_values LOOP
        IF position(quote_literal(missing_value) IN constraint_src) = 0 THEN
            RAISE EXCEPTION '[20260515] friend_activity_feed_activity_type_check missing value %', missing_value;
        END IF;
    END LOOP;

    RAISE NOTICE '[20260515] friend_activity_feed_activity_type_check verified — % allowed values', array_length(required_values, 1);
END $$;

COMMIT;
