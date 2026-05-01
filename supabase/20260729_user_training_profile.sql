-- ═══════════════════════════════════════════════════════════════════════════
-- 20260729_user_training_profile.sql  (Migration #160)
--
-- Wires up the rolling per-user training-style profile (#156 schema, never
-- populated). Adds `refresh_user_training_profile(user_id)` SECURITY
-- DEFINER RPC that aggregates the user's last 8 quality workouts and
-- writes/updates a `user_training_profile` row. The edge function calls
-- this fire-and-forget after every successful Claude report write.
--
-- WHAT GETS COMPUTED (from last 8 quality workouts)
-- -------------------------------------------------
--   inferred_intent      — from rep distribution across all working sets
--                          - strength      → ≥50% of sets in 1–5 rep range
--                          - hypertrophy   → ≥50% of sets in 6–12 rep range
--                          - endurance     → ≥30% of sets at 13+ reps
--                          - mixed         → none of the above dominate
--                          (warmups excluded)
--   median_rest_sec      — median inter-set gap from exercise_set_history
--                          .completed_at deltas, EXCLUDING gaps > 600s
--                          (treated as exercise-transition or pause).
--                          NULL when not enough timestamped sets exist.
--   preferred_equipment  — top 5 equipment_category values by frequency.
--   strong_movement_patterns — primary muscle groups appearing in ≥3
--                          workouts AND with completion rate ≥ 0.90.
--   weak_movement_patterns   — primary muscle groups appearing in ≥3
--                          workouts AND with completion rate < 0.70.
--   avg_session_duration_min, avg_working_sets_per_session — straight
--                          arithmetic mean over the same 8 workouts.
--   profile_jsonb        — extensible bag with totals + the refresh
--                          window for debugging and future fields.
--
-- REFRESH CADENCE
-- ---------------
-- The edge function MUST call this at the end of every successful
-- Claude report write (fire-and-forget). The RPC itself is a no-op when
-- the user has < 4 completed reports — so the first 3 quality workouts
-- contribute data but don't trigger a profile yet (need 4 for a
-- meaningful baseline). After that, every quality workout refreshes the
-- profile in-place.
--
-- IDEMPOTENCY
-- -----------
-- Refresh is upsert (INSERT ... ON CONFLICT ON CONSTRAINT
-- user_training_profile_pkey DO UPDATE). Re-running on the same workout
-- row produces an identical result — `quality_workouts_at_refresh`
-- captures the count at the time of the refresh.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

DROP FUNCTION IF EXISTS refresh_user_training_profile(UUID);

CREATE OR REPLACE FUNCTION refresh_user_training_profile(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_workout_count    INTEGER;
    v_window           INTEGER := 8;
    v_workout_ids      UUID[];
    v_inferred_intent  TEXT;
    v_median_rest      INTEGER;
    v_preferred        TEXT[];
    v_strong           TEXT[];
    v_weak             TEXT[];
    v_avg_duration_min INTEGER;
    v_avg_working_sets INTEGER;
    v_total_sets       INTEGER;
    v_strength_pct     NUMERIC;
    v_hypertrophy_pct  NUMERIC;
    v_endurance_pct    NUMERIC;
    v_profile_jsonb    JSONB;
BEGIN
    IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_id THEN
        RAISE EXCEPTION 'Forbidden: cannot refresh another user''s profile'
            USING ERRCODE = '42501';
    END IF;

    -- 1. Need at least 4 completed reports (= 4 quality workouts) to
    --    compute a meaningful profile.
    SELECT count(*) INTO v_workout_count
      FROM ai_workout_reports
     WHERE user_id = p_user_id
       AND status = 'complete';

    IF v_workout_count < 4 THEN
        RETURN jsonb_build_object(
            'refreshed', FALSE,
            'reason', 'insufficient_data',
            'workout_count', v_workout_count
        );
    END IF;

    -- 2. Pick the most recent v_window quality workouts.
    SELECT array_agg(workout_id)
      INTO v_workout_ids
      FROM (
          SELECT workout_id
            FROM ai_workout_reports
           WHERE user_id = p_user_id
             AND status = 'complete'
           ORDER BY analyzed_at DESC NULLS LAST, enqueued_at DESC
           LIMIT v_window
      ) s;

    -- 3. Inferred intent — rep distribution across all working sets in
    --    these workouts. Warmups excluded.
    SELECT
        COUNT(*) FILTER (WHERE reps BETWEEN 1 AND 5)::NUMERIC
            / NULLIF(COUNT(*), 0)::NUMERIC,
        COUNT(*) FILTER (WHERE reps BETWEEN 6 AND 12)::NUMERIC
            / NULLIF(COUNT(*), 0)::NUMERIC,
        COUNT(*) FILTER (WHERE reps >= 13)::NUMERIC
            / NULLIF(COUNT(*), 0)::NUMERIC,
        COUNT(*)
      INTO v_strength_pct, v_hypertrophy_pct, v_endurance_pct, v_total_sets
      FROM exercise_set_history esh
      JOIN exercise_performance_history eph
        ON eph.id = esh.performance_id
     WHERE eph.workout_id = ANY(v_workout_ids)
       AND esh.is_completed = TRUE
       AND esh.set_type IS DISTINCT FROM 'Warmup'
       AND esh.reps IS NOT NULL
       AND esh.reps > 0;

    v_inferred_intent := CASE
        WHEN v_total_sets IS NULL OR v_total_sets = 0 THEN 'unknown'
        WHEN COALESCE(v_strength_pct, 0)    >= 0.5 THEN 'strength'
        WHEN COALESCE(v_hypertrophy_pct, 0) >= 0.5 THEN 'hypertrophy'
        WHEN COALESCE(v_endurance_pct, 0)   >= 0.3 THEN 'endurance'
        ELSE 'mixed'
    END;

    -- 4. Median rest sec — set-to-set deltas grouped by performance_id,
    --    capped at 600s to exclude exercise-transition gaps.
    WITH set_deltas AS (
        SELECT
            EXTRACT(EPOCH FROM (
                esh.completed_at - LAG(esh.completed_at) OVER (
                    PARTITION BY esh.performance_id
                    ORDER BY esh.set_number
                )
            )) AS delta_sec
          FROM exercise_set_history esh
          JOIN exercise_performance_history eph ON eph.id = esh.performance_id
         WHERE eph.workout_id = ANY(v_workout_ids)
           AND esh.is_completed = TRUE
           AND esh.completed_at IS NOT NULL
    )
    SELECT (PERCENTILE_CONT(0.5) WITHIN GROUP (
        ORDER BY delta_sec
    ))::INTEGER
      INTO v_median_rest
      FROM set_deltas
     WHERE delta_sec IS NOT NULL
       AND delta_sec BETWEEN 10 AND 600;

    -- 5. Preferred equipment — top 5 equipment_category by frequency.
    --    Join on EXERCISE NAME (eph.exercise_id is NULL in production —
    --    iOS only writes exercise_name).
    SELECT array_agg(eq) INTO v_preferred FROM (
        SELECT e.equipment_category AS eq
          FROM exercise_performance_history eph
          JOIN exercises e ON e.name = eph.exercise_name
         WHERE eph.workout_id = ANY(v_workout_ids)
           AND e.equipment_category IS NOT NULL
           AND e.equipment_category <> ''
         GROUP BY e.equipment_category
         ORDER BY COUNT(*) DESC
         LIMIT 5
    ) s;

    -- 6. Strong / weak movement patterns — by primary muscle group.
    --    Strong: appears in ≥3 workouts AND completion rate ≥ 0.90.
    --    Weak:   appears in ≥3 workouts AND completion rate < 0.70.
    --    Same name-based join as preferred_equipment above.
    WITH muscle_stats AS (
        SELECT
            unnest(e.primary_muscles) AS muscle,
            COUNT(DISTINCT eph.workout_id) AS workouts,
            SUM(esh.is_completed::INT)::NUMERIC
                / NULLIF(COUNT(esh.id), 0)::NUMERIC AS completion_rate
          FROM exercise_performance_history eph
          JOIN exercises e ON e.name = eph.exercise_name
          JOIN exercise_set_history esh ON esh.performance_id = eph.id
         WHERE eph.workout_id = ANY(v_workout_ids)
           AND esh.set_type IS DISTINCT FROM 'Warmup'
         GROUP BY 1
    )
    SELECT
        ARRAY(
            SELECT muscle FROM muscle_stats
             WHERE workouts >= 3 AND completion_rate >= 0.90
             ORDER BY completion_rate DESC, workouts DESC
        ),
        ARRAY(
            SELECT muscle FROM muscle_stats
             WHERE workouts >= 3 AND completion_rate < 0.70
             ORDER BY completion_rate ASC, workouts DESC
        )
      INTO v_strong, v_weak;

    -- 7. Session-level averages.
    SELECT
        (AVG(NULLIF(duration, 0)) / 60)::INTEGER,
        AVG(NULLIF(total_sets_completed, 0))::INTEGER
      INTO v_avg_duration_min, v_avg_working_sets
      FROM workout_history
     WHERE id = ANY(v_workout_ids);

    -- 8. Extensible profile JSONB.
    v_profile_jsonb := jsonb_build_object(
        'window_size', v_window,
        'workout_count_total', v_workout_count,
        'workout_ids_in_window', v_workout_ids,
        'rep_distribution', jsonb_build_object(
            'strength_pct',    v_strength_pct,
            'hypertrophy_pct', v_hypertrophy_pct,
            'endurance_pct',   v_endurance_pct,
            'total_working_sets', v_total_sets
        )
    );

    -- 9. Upsert profile.
    INSERT INTO user_training_profile (
        user_id, inferred_intent, median_rest_sec, preferred_equipment,
        weak_movement_patterns, strong_movement_patterns,
        avg_session_duration_min, avg_working_sets_per_session,
        profile_jsonb, quality_workouts_at_refresh, refreshed_at
    )
    VALUES (
        p_user_id, v_inferred_intent, v_median_rest, v_preferred,
        v_weak, v_strong,
        v_avg_duration_min, v_avg_working_sets,
        v_profile_jsonb, v_workout_count, NOW()
    )
    ON CONFLICT (user_id) DO UPDATE SET
        inferred_intent              = EXCLUDED.inferred_intent,
        median_rest_sec              = EXCLUDED.median_rest_sec,
        preferred_equipment          = EXCLUDED.preferred_equipment,
        weak_movement_patterns       = EXCLUDED.weak_movement_patterns,
        strong_movement_patterns     = EXCLUDED.strong_movement_patterns,
        avg_session_duration_min     = EXCLUDED.avg_session_duration_min,
        avg_working_sets_per_session = EXCLUDED.avg_working_sets_per_session,
        profile_jsonb                = EXCLUDED.profile_jsonb,
        quality_workouts_at_refresh  = EXCLUDED.quality_workouts_at_refresh,
        refreshed_at                 = EXCLUDED.refreshed_at;

    RETURN jsonb_build_object(
        'refreshed', TRUE,
        'user_id', p_user_id,
        'workout_count', v_workout_count,
        'window_size', v_window,
        'inferred_intent', v_inferred_intent,
        'median_rest_sec', v_median_rest,
        'preferred_equipment', v_preferred,
        'strong_movement_patterns', v_strong,
        'weak_movement_patterns', v_weak,
        'avg_session_duration_min', v_avg_duration_min,
        'avg_working_sets_per_session', v_avg_working_sets
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION refresh_user_training_profile(UUID) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION refresh_user_training_profile(UUID) TO authenticated, service_role;

COMMENT ON FUNCTION refresh_user_training_profile(UUID) IS
    'Aggregates the user''s last 8 quality workouts into user_training_profile. Called fire-and-forget by the edge function after every successful Claude report write. No-op when the user has <4 completed reports.';

-- One-shot backfill for any user with ≥4 completed reports already.
DO $$
DECLARE
    r RECORD;
    v_result JSONB;
    v_count INTEGER := 0;
BEGIN
    FOR r IN
        SELECT user_id
          FROM ai_workout_reports
         WHERE status = 'complete'
         GROUP BY user_id
        HAVING count(*) >= 4
    LOOP
        SELECT refresh_user_training_profile(r.user_id) INTO v_result;
        v_count := v_count + 1;
        RAISE NOTICE 'Backfilled profile for %: %', r.user_id, v_result;
    END LOOP;
    RAISE NOTICE '✅ Migration #160: refresh_user_training_profile RPC + backfilled % users.', v_count;
END $$;

COMMIT;
