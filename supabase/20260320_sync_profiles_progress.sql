-- ============================================================================
-- PHASE 4: SYNC TRIGGER FOR user_profiles <-> user_progress
-- ============================================================================
-- Problem: 6 fields are duplicated between user_profiles and user_progress
-- with NO sync mechanism. Data drifts silently.
--
-- Column mapping (names may differ between tables):
--   user_profiles.current_streak  <-> user_progress.current_streak
--   user_profiles.longest_streak  <-> user_progress.longest_streak
--   user_profiles.total_workouts  <-> user_progress.total_workouts
--   user_profiles.last_workout_date <-> user_progress.last_workout_date
--   user_profiles.xp              <-> user_progress.xp (or total_xp)
--   user_profiles.weight_lbs      <-> user_progress.weight_lbs
--
-- The IS DISTINCT FROM check prevents infinite trigger recursion:
-- if the target row already has the same values, no UPDATE fires,
-- so the other trigger is never invoked.
-- ============================================================================

-- ============================================================================
-- STEP 1: One-time reconciliation of existing drift
-- ============================================================================
-- Source of truth:
--   user_progress owns: total_workouts, current_streak, longest_streak,
--                       last_workout_date (workout completion writes here)
--   user_profiles owns: weight_lbs, xp (profile edits write here)
-- ============================================================================

DO $$
DECLARE
  v_synced INT := 0;
  v_has_xp_in_progress BOOLEAN;
  v_has_weight_in_progress BOOLEAN;
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
  RAISE NOTICE 'PHASE 4: SYNC user_profiles <-> user_progress';
  RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
  RAISE NOTICE '';

  -- Check which columns exist in user_progress
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='user_progress' AND column_name='xp'
  ) INTO v_has_xp_in_progress;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='user_progress' AND column_name='weight_lbs'
  ) INTO v_has_weight_in_progress;

  RAISE NOTICE '  user_progress has xp column: %', v_has_xp_in_progress;
  RAISE NOTICE '  user_progress has weight_lbs column: %', v_has_weight_in_progress;

  -- Sync shared fields from user_progress -> user_profiles
  -- (user_progress is source of truth for workout stats)
  UPDATE user_profiles p SET
    current_streak = COALESCE(pr.current_streak, p.current_streak),
    longest_streak = COALESCE(pr.longest_streak, p.longest_streak),
    total_workouts = COALESCE(pr.total_workouts, p.total_workouts),
    last_workout_date = COALESCE(pr.last_workout_date, p.last_workout_date)
  FROM user_progress pr
  WHERE p.id = pr.user_id
    AND (p.current_streak IS DISTINCT FROM pr.current_streak
      OR p.longest_streak IS DISTINCT FROM pr.longest_streak
      OR p.total_workouts IS DISTINCT FROM pr.total_workouts
      OR p.last_workout_date IS DISTINCT FROM pr.last_workout_date);
  GET DIAGNOSTICS v_synced = ROW_COUNT;
  IF v_synced > 0 THEN
    RAISE NOTICE '  🔄 Synced workout stats (progress → profiles) for % users', v_synced;
  ELSE
    RAISE NOTICE '  ✅ Workout stats already in sync';
  END IF;

  -- Sync weight from user_profiles -> user_progress (if column exists)
  IF v_has_weight_in_progress THEN
    EXECUTE '
      UPDATE user_progress pr SET
        weight_lbs = p.weight_lbs
      FROM user_profiles p
      WHERE pr.user_id = p.id
        AND pr.weight_lbs IS DISTINCT FROM p.weight_lbs';
    GET DIAGNOSTICS v_synced = ROW_COUNT;
    IF v_synced > 0 THEN
      RAISE NOTICE '  🔄 Synced weight_lbs (profiles → progress) for % users', v_synced;
    ELSE
      RAISE NOTICE '  ✅ weight_lbs already in sync';
    END IF;
  END IF;

  -- Sync XP from user_profiles -> user_progress (if xp column exists)
  IF v_has_xp_in_progress THEN
    EXECUTE '
      UPDATE user_progress pr SET
        xp = p.xp
      FROM user_profiles p
      WHERE pr.user_id = p.id
        AND pr.xp IS DISTINCT FROM p.xp';
    GET DIAGNOSTICS v_synced = ROW_COUNT;
    IF v_synced > 0 THEN
      RAISE NOTICE '  🔄 Synced xp (profiles → progress) for % users', v_synced;
    ELSE
      RAISE NOTICE '  ✅ xp already in sync';
    END IF;
  END IF;

  RAISE NOTICE '';
  RAISE NOTICE '  ✅ One-time reconciliation complete';
END $$;

-- ============================================================================
-- STEP 2: Create the bidirectional sync trigger function
-- ============================================================================

CREATE OR REPLACE FUNCTION sync_profiles_progress()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF TG_TABLE_NAME = 'user_profiles' THEN
    -- user_profiles was updated -> push shared fields to user_progress
    UPDATE user_progress SET
      current_streak = NEW.current_streak,
      longest_streak = NEW.longest_streak,
      total_workouts = NEW.total_workouts,
      last_workout_date = NEW.last_workout_date
    WHERE user_id = NEW.id
      AND (current_streak IS DISTINCT FROM NEW.current_streak
        OR longest_streak IS DISTINCT FROM NEW.longest_streak
        OR total_workouts IS DISTINCT FROM NEW.total_workouts
        OR last_workout_date IS DISTINCT FROM NEW.last_workout_date);

  ELSIF TG_TABLE_NAME = 'user_progress' THEN
    -- user_progress was updated -> push shared fields to user_profiles
    UPDATE user_profiles SET
      current_streak = NEW.current_streak,
      longest_streak = NEW.longest_streak,
      total_workouts = NEW.total_workouts,
      last_workout_date = NEW.last_workout_date
    WHERE id = NEW.user_id
      AND (current_streak IS DISTINCT FROM NEW.current_streak
        OR longest_streak IS DISTINCT FROM NEW.longest_streak
        OR total_workouts IS DISTINCT FROM NEW.total_workouts
        OR last_workout_date IS DISTINCT FROM NEW.last_workout_date);
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION sync_profiles_progress() IS
  'Bidirectional sync of shared fields between user_profiles and user_progress. '
  'Uses IS DISTINCT FROM to prevent infinite trigger recursion.';

-- ============================================================================
-- STEP 3: Attach triggers to both tables
-- ============================================================================

DROP TRIGGER IF EXISTS trg_sync_profiles_to_progress ON user_profiles;
CREATE TRIGGER trg_sync_profiles_to_progress
  AFTER UPDATE OF current_streak, longest_streak, total_workouts, last_workout_date
  ON user_profiles
  FOR EACH ROW
  EXECUTE FUNCTION sync_profiles_progress();

DROP TRIGGER IF EXISTS trg_sync_progress_to_profiles ON user_progress;
CREATE TRIGGER trg_sync_progress_to_profiles
  AFTER UPDATE OF current_streak, longest_streak, total_workouts, last_workout_date
  ON user_progress
  FOR EACH ROW
  EXECUTE FUNCTION sync_profiles_progress();

DO $$ BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '  ✅ Triggers installed:';
  RAISE NOTICE '     trg_sync_profiles_to_progress (on user_profiles)';
  RAISE NOTICE '     trg_sync_progress_to_profiles (on user_progress)';
  RAISE NOTICE '';
  RAISE NOTICE '  Fields synced: current_streak, longest_streak, total_workouts, last_workout_date';
  RAISE NOTICE '  Recursion prevention: IS DISTINCT FROM check';
  RAISE NOTICE '';
END $$;
