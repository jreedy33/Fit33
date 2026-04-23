-- Bug-intel sweep Cluster F: resolve `post_workout_activity` function ambiguity.
--
-- Problem: `20260307_friend_activity_feed.sql` created a 7-argument
-- `post_workout_activity(TEXT, TEXT, INT, INT, INT, INT, TEXT[])`.
-- `20260330_activity_feed_exercises.sql` later added an 8-argument
-- version via `CREATE OR REPLACE FUNCTION post_workout_activity(..., TEXT)`
-- WITHOUT dropping the 7-arg overload first — this violates
-- supabase-rules §12 (all overloads must be dropped before CREATE OR
-- REPLACE so PostgREST can resolve the call unambiguously). Clients
-- sending 8 arguments (the current iOS call site) sometimes resolved to
-- the stale 7-arg version, silently discarding `p_exercises_json` and
-- producing empty exercise lists on friends' feeds — along with
-- PGRST202 "Could not find a function matching the expected signature"
-- noise in bug_intelligence_reports.
--
-- Fix: drop BOTH signatures explicitly, then recreate the canonical
-- 8-argument version (same body as 20260330 — verified byte-for-byte
-- equivalent). Idempotent, rollback-safe.

BEGIN;

-- =========================================================================
-- Drop all known overloads
-- =========================================================================

DROP FUNCTION IF EXISTS post_workout_activity(TEXT, TEXT, INT, INT, INT, INT, TEXT[]);
DROP FUNCTION IF EXISTS post_workout_activity(TEXT, TEXT, INT, INT, INT, INT, TEXT[], TEXT);

-- =========================================================================
-- Recreate canonical 8-arg version (matches iOS
-- FriendActivityFeedView.postWorkoutActivity call site)
-- =========================================================================

CREATE OR REPLACE FUNCTION post_workout_activity(
    p_workout_id TEXT,
    p_workout_name TEXT,
    p_duration_seconds INT,
    p_exercise_count INT,
    p_total_sets INT,
    p_xp_earned INT,
    p_muscle_groups TEXT[] DEFAULT '{}',
    p_exercises_json TEXT DEFAULT '[]'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID;
    new_activity_id UUID;
    v_exercises JSONB;
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    BEGIN
        v_exercises := p_exercises_json::jsonb;
    EXCEPTION WHEN OTHERS THEN
        v_exercises := '[]'::jsonb;
    END;

    INSERT INTO friend_activity_feed (user_id, activity_type, workout_id, metadata)
    VALUES (
        current_user_uuid,
        'workout_completed',
        p_workout_id,
        jsonb_build_object(
            'workout_name', p_workout_name,
            'duration_seconds', p_duration_seconds,
            'exercise_count', p_exercise_count,
            'total_sets', p_total_sets,
            'xp_earned', p_xp_earned,
            'muscle_groups', p_muscle_groups,
            'exercises', v_exercises
        )
    )
    RETURNING id INTO new_activity_id;

    RETURN new_activity_id;
END;
$$;

GRANT EXECUTE ON FUNCTION post_workout_activity(TEXT, TEXT, INT, INT, INT, INT, TEXT[], TEXT) TO authenticated;

-- =========================================================================
-- Sanity check — exactly one signature exists after this migration.
-- =========================================================================

DO $$
DECLARE
    overload_count INT;
BEGIN
    SELECT COUNT(*) INTO overload_count
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname = 'post_workout_activity';
    IF overload_count <> 1 THEN
        RAISE EXCEPTION '[20260513] Expected exactly 1 post_workout_activity overload, found %.', overload_count;
    END IF;
    RAISE NOTICE '[20260513] post_workout_activity overload collapse verified (1 signature).';
END $$;

COMMIT;
