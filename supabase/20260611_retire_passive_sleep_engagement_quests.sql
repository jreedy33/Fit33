-- ============================================================================
-- 20260611 — Retire passive sleep / engagement quests, ship "Evening Wind Down"
--
-- Follow-up to 20260610. Three more quests fail the "actionable today, not
-- pre-determined by overnight sensor state" test (PE invariant 19d):
--
--   * sleep_8h_wearable   "Sleep 8 Hours"     (20260509 — wearable)
--   * sleep_7_hours       "Sleep Champion"    (20260324 — all users)
--   * log_readiness_am    "Morning Check-In"  (20260509 — wearable)
--
-- WHY:
--   - Both sleep quests tick via `DailyQuestService.onSleepLogged(hours:)`,
--     which fires when LAST NIGHT'S sleep syncs in (typically 6-9am). By the
--     time the user opens the app and sees today's slate, the quest is
--     already pass/fail-locked. Same anti-pattern as Green Recovery from
--     migration 20260610 — the user has zero levers today. (Joe initially
--     kept `sleep_8h_wearable` 2026-04-25 on the rationale that "the user
--     controls tonight's bedtime", but the quest is dated `today` and ticks
--     off LAST night, so the lever is off-by-one and the user-facing
--     experience is the same automatic loss.)
--   - `log_readiness_am` is BOTH the anti-pattern AND fully broken: there
--     is NO verification logic for this key anywhere in the codebase
--     (grepped supabase/*.sql + Fit33/*.swift on 2026-04-25 — zero hits
--     other than the template definition itself). It can never
--     auto-complete; users with this in their slate hit guaranteed 0/1.
--
-- WHAT THIS MIGRATION DOES:
--
--   1. SOFT-disables the three templates (`is_active = FALSE`). Templates
--      stay on disk so historical `user_daily_quests` rows still resolve
--      to a row for title/icon lookups. Never `DELETE` (PE invariant 19d).
--
--   2. CLEANS UP in-flight `log_readiness_am` user_daily_quests rows that
--      can never auto-complete. We DELETE only TODAY's open rows for that
--      key — historical (non-today) rows are preserved for streak audit.
--      This prevents users from staring at a permanently-stuck 0/1 quest
--      until the daily reset.
--
--   3. INSERTS one actionable replacement: `evening_wind_down`
--      "Evening Wind Down" — log a walk/yoga/stretch/mobility/foam-rolling
--      cardio session AFTER 6pm local time. Auto-verified from
--      `cardio_workouts.started_at AT TIME ZONE p_timezone` ≥ 18:00.
--      `requires_context = 'has_wearable'` because the verifier RPC is
--      `verify_wearable_quests_for_today` and only the wearable-recompute
--      path triggers it from iOS — non-wearable users use the existing
--      `stretch_session` quest (15+ min stretch, no time-of-day gate)
--      which is functionally similar.
--
--   4. EXTENDS `public.verify_wearable_quests_for_today(p_timezone TEXT)`
--      with one more ELSIF branch detecting `evening_wind_down`. Drops
--      every prior overload via the canonical `pg_proc` loop
--      (supabase-rules §12). Same SECURITY DEFINER + `auth.uid()`-pinned
--      shape from 20260606 / 20260610.
--
-- iOS notes:
--   * `Fit33/DailyQuestService.swift::onSleepLogged(hours:)` will become a
--     wasted RPC roundtrip once the templates are disabled (every sync
--     attempts `update_quest_progress` for `sleep_7_hours` / `sleep_8h_wearable`
--     against rows that no longer exist for any user). Paired iOS edit
--     (separate commit) short-circuits that hook to a no-op via a feature
--     flag check; functionally harmless to leave in place — the RPC just
--     returns "no matching quest" silently. Tracked as an iOS-cleanup
--     follow-up, not a blocker.
--   * No `QuestKey` enum case needed for `evening_wind_down` (string-keyed,
--     same as 20260610 replacements).
--   * `DailyQuestService.onReadinessRecomputed` already triggers
--     `verify_wearable_quests_for_today` after every readiness recompute,
--     so `evening_wind_down` rides that path with no Swift changes.
--
-- Idempotent: re-running is a no-op (UPDATE flips back to FALSE,
-- INSERT … ON CONFLICT DO UPDATE refreshes, DELETE … WHERE quest_key
-- = 'log_readiness_am' AND quest_date = current_date is harmless on
-- re-run, DROP FUNCTION + CREATE OR REPLACE for the verifier).
-- ============================================================================

BEGIN;

-- 1. Soft-disable the three passive quests --------------------------------
UPDATE quest_templates
   SET is_active = FALSE
 WHERE quest_key IN ('sleep_8h_wearable', 'sleep_7_hours', 'log_readiness_am');

-- 2. Clean up phantom in-flight log_readiness_am rows ---------------------
-- These can never auto-complete (no verifier exists). DELETE only today's
-- not-yet-completed rows so users don't see a permanently-stuck 0/1 quest.
-- Historical rows (older than today) are preserved for streak / audit
-- purposes — the daily reset cron drops them naturally.
--
-- Caveat: this DELETE walks every connected wearable user's today rows.
-- The number of rows is tiny (one per user with this template assigned —
-- max 1× per user for today), so no performance concern.
DELETE FROM user_daily_quests
 WHERE quest_key = 'log_readiness_am'
   AND quest_date = current_date
   AND is_completed = FALSE;

-- 3. Seed actionable replacement ------------------------------------------
-- `evening_wind_down` is wearable-gated (the verify hook only runs from
-- the wearable-recompute iOS path). XP rewards seeded post-rebalance
-- (auto × 1.5 from migration 20260603) so re-applying the multiplier is
-- a no-op:  base 25 XP / 10 LP × 1.5 = 38 XP / 15 LP.
INSERT INTO quest_templates (
    quest_key, title, description, icon, category, target_value, target_unit,
    xp_reward, league_points, difficulty, weight, requires_context, fun_label,
    verification_type, min_workouts, is_active, tier
) VALUES
    ('evening_wind_down',
        'Evening Wind Down',
        'Stretch, yoga, or walk after 6pm',
        'moon.stars.fill',
        'workout', 15, 'minutes',
        38, 15, 'easy', 8, 'has_wearable',
        '🌙 Set tonight up',
        'auto', 0, TRUE, 'free')
ON CONFLICT (quest_key) DO UPDATE SET
    title              = EXCLUDED.title,
    description        = EXCLUDED.description,
    icon               = EXCLUDED.icon,
    category           = EXCLUDED.category,
    target_value       = EXCLUDED.target_value,
    target_unit        = EXCLUDED.target_unit,
    xp_reward          = EXCLUDED.xp_reward,
    league_points      = EXCLUDED.league_points,
    difficulty         = EXCLUDED.difficulty,
    weight             = EXCLUDED.weight,
    requires_context   = EXCLUDED.requires_context,
    fun_label          = EXCLUDED.fun_label,
    verification_type  = EXCLUDED.verification_type,
    min_workouts       = EXCLUDED.min_workouts,
    is_active          = EXCLUDED.is_active,
    tier               = EXCLUDED.tier;

-- 4. Extend verify_wearable_quests_for_today ------------------------------
-- Drop every overload first (supabase-rules §12). Re-create with one
-- new ELSIF branch for evening_wind_down. All other branches are
-- byte-for-byte identical to 20260610.
DO $$
DECLARE
    v_sig TEXT;
BEGIN
    FOR v_sig IN
        SELECT oid::regprocedure::text
          FROM pg_proc
         WHERE proname = 'verify_wearable_quests_for_today'
           AND pronamespace = 'public'::regnamespace
    LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || v_sig || ' CASCADE';
    END LOOP;
END $$;

CREATE OR REPLACE FUNCTION public.verify_wearable_quests_for_today(
    p_timezone TEXT DEFAULT 'UTC'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_caller_id              UUID := auth.uid();
    v_today                  DATE;
    v_readiness              RECORD;
    v_quest                  RECORD;
    v_completed              TEXT[] := '{}';
    v_skipped                TEXT[] := '{}';
    v_walk_minutes_today     INT;
    v_active_recovery_minutes INT;
    v_zone2_minutes_today    INT;
    v_cardio_minutes_today   INT;
    v_evening_recovery_min   INT;
    v_recovery_workout_today BOOLEAN;
BEGIN
    IF v_caller_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required'
            USING ERRCODE = 'P0001';
    END IF;

    v_today := (now() AT TIME ZONE p_timezone)::DATE;

    SELECT band, score, sleep_hours, hrv_delta_pct, rhr_trend_bpm
      INTO v_readiness
      FROM daily_readiness_history
     WHERE user_id = v_caller_id
       AND date = v_today
     ORDER BY updated_at DESC
     LIMIT 1;

    FOR v_quest IN
        SELECT udq.id, udq.quest_key
          FROM user_daily_quests udq
         WHERE udq.user_id = v_caller_id
           AND udq.quest_date = v_today
           AND udq.is_completed = FALSE
           AND udq.quest_key IN (
               -- Soft-disabled but kept for in-flight assignments (will not
               -- be assigned by future get_daily_quests calls because their
               -- templates are is_active = FALSE).
               'sleep_8h_wearable','recovery_above_67','hrv_above_baseline',
               'rhr_in_healthy_range','respect_red_recovery',
               -- Actionable wearable quests
               'walk_when_red',
               -- 20260610 actionable replacements
               'active_recovery_logged','zone_2_minutes_20','cardio_minutes_20',
               -- 20260611 actionable replacement
               'evening_wind_down'
           )
    LOOP
        IF v_quest.quest_key = 'sleep_8h_wearable' THEN
            IF v_readiness IS NOT NULL AND COALESCE(v_readiness.sleep_hours, 0) >= 8 THEN
                PERFORM public.update_quest_progress(v_caller_id::TEXT, v_quest.quest_key, 1, p_timezone);
                v_completed := array_append(v_completed, v_quest.quest_key);
            ELSE
                v_skipped := array_append(v_skipped, v_quest.quest_key);
            END IF;

        ELSIF v_quest.quest_key = 'recovery_above_67' THEN
            IF v_readiness IS NOT NULL AND COALESCE(v_readiness.score, 0) >= 67 THEN
                PERFORM public.update_quest_progress(v_caller_id::TEXT, v_quest.quest_key, 1, p_timezone);
                v_completed := array_append(v_completed, v_quest.quest_key);
            ELSE
                v_skipped := array_append(v_skipped, v_quest.quest_key);
            END IF;

        ELSIF v_quest.quest_key = 'hrv_above_baseline' THEN
            IF v_readiness IS NOT NULL AND COALESCE(v_readiness.hrv_delta_pct, -1) > 0 THEN
                PERFORM public.update_quest_progress(v_caller_id::TEXT, v_quest.quest_key, 1, p_timezone);
                v_completed := array_append(v_completed, v_quest.quest_key);
            ELSE
                v_skipped := array_append(v_skipped, v_quest.quest_key);
            END IF;

        ELSIF v_quest.quest_key = 'rhr_in_healthy_range' THEN
            IF v_readiness IS NOT NULL AND COALESCE(v_readiness.rhr_trend_bpm, 1) <= 0 THEN
                PERFORM public.update_quest_progress(v_caller_id::TEXT, v_quest.quest_key, 1, p_timezone);
                v_completed := array_append(v_completed, v_quest.quest_key);
            ELSE
                v_skipped := array_append(v_skipped, v_quest.quest_key);
            END IF;

        ELSIF v_quest.quest_key = 'walk_when_red' THEN
            IF v_readiness IS NOT NULL AND v_readiness.band = 'red' THEN
                SELECT COALESCE(SUM(GREATEST(0, COALESCE(elapsed_seconds, 0)) / 60), 0)::INT
                  INTO v_walk_minutes_today
                  FROM cardio_workouts
                 WHERE user_id = v_caller_id
                   AND COALESCE(activity_type, '') IN ('walk', 'hike')
                   AND (started_at AT TIME ZONE p_timezone)::DATE = v_today;
                IF v_walk_minutes_today >= 20 THEN
                    PERFORM public.update_quest_progress(v_caller_id::TEXT, v_quest.quest_key, 1, p_timezone);
                    v_completed := array_append(v_completed, v_quest.quest_key);
                ELSE
                    v_skipped := array_append(v_skipped, v_quest.quest_key);
                END IF;
            ELSE
                v_skipped := array_append(v_skipped, v_quest.quest_key);
            END IF;

        ELSIF v_quest.quest_key = 'respect_red_recovery' THEN
            IF v_readiness IS NOT NULL AND v_readiness.band = 'red' THEN
                SELECT EXISTS (
                    SELECT 1 FROM cardio_workouts
                    WHERE user_id = v_caller_id
                      AND COALESCE(activity_type, '') IN ('walk','hike','yoga','stretch','mobility','foam_rolling')
                      AND (started_at AT TIME ZONE p_timezone)::DATE = v_today
                ) AND NOT EXISTS (
                    SELECT 1 FROM workouts
                    WHERE user_id = v_caller_id
                      AND date = v_today
                ) INTO v_recovery_workout_today;

                IF v_recovery_workout_today THEN
                    PERFORM public.update_quest_progress(v_caller_id::TEXT, v_quest.quest_key, 1, p_timezone);
                    v_completed := array_append(v_completed, v_quest.quest_key);
                ELSE
                    v_skipped := array_append(v_skipped, v_quest.quest_key);
                END IF;
            ELSE
                v_skipped := array_append(v_skipped, v_quest.quest_key);
            END IF;

        ELSIF v_quest.quest_key = 'active_recovery_logged' THEN
            SELECT COALESCE(SUM(GREATEST(0, COALESCE(elapsed_seconds, 0)) / 60), 0)::INT
              INTO v_active_recovery_minutes
              FROM cardio_workouts
             WHERE user_id = v_caller_id
               AND COALESCE(activity_type, '') IN ('walk','hike','yoga','stretch','mobility','foam_rolling')
               AND (started_at AT TIME ZONE p_timezone)::DATE = v_today;
            IF v_active_recovery_minutes >= 15 THEN
                PERFORM public.update_quest_progress(v_caller_id::TEXT, v_quest.quest_key, 1, p_timezone);
                v_completed := array_append(v_completed, v_quest.quest_key);
            ELSE
                v_skipped := array_append(v_skipped, v_quest.quest_key);
            END IF;

        ELSIF v_quest.quest_key = 'zone_2_minutes_20' THEN
            SELECT COALESCE(SUM(GREATEST(0, COALESCE(elapsed_seconds, 0)) / 60), 0)::INT
              INTO v_zone2_minutes_today
              FROM cardio_workouts
             WHERE user_id = v_caller_id
               AND (started_at AT TIME ZONE p_timezone)::DATE = v_today
               AND COALESCE(elapsed_seconds, 0) >= 300
               AND COALESCE(average_heart_rate, 0) BETWEEN 110 AND 150;
            IF v_zone2_minutes_today >= 20 THEN
                PERFORM public.update_quest_progress(v_caller_id::TEXT, v_quest.quest_key, 1, p_timezone);
                v_completed := array_append(v_completed, v_quest.quest_key);
            ELSE
                v_skipped := array_append(v_skipped, v_quest.quest_key);
            END IF;

        ELSIF v_quest.quest_key = 'cardio_minutes_20' THEN
            SELECT COALESCE(SUM(GREATEST(0, COALESCE(elapsed_seconds, 0)) / 60), 0)::INT
              INTO v_cardio_minutes_today
              FROM cardio_workouts
             WHERE user_id = v_caller_id
               AND (started_at AT TIME ZONE p_timezone)::DATE = v_today
               AND COALESCE(elapsed_seconds, 0) >= 60;
            IF v_cardio_minutes_today >= 20 THEN
                PERFORM public.update_quest_progress(v_caller_id::TEXT, v_quest.quest_key, 1, p_timezone);
                v_completed := array_append(v_completed, v_quest.quest_key);
            ELSE
                v_skipped := array_append(v_skipped, v_quest.quest_key);
            END IF;

        ELSIF v_quest.quest_key = 'evening_wind_down' THEN
            -- Sum minutes from any walk/hike/yoga/stretch/mobility/foam-rolling
            -- cardio session today whose started_at AT TIME ZONE p_timezone
            -- is at or after 18:00 (6pm). Threshold: 15 minutes.
            -- Multiple short evening sessions stack.
            SELECT COALESCE(SUM(GREATEST(0, COALESCE(elapsed_seconds, 0)) / 60), 0)::INT
              INTO v_evening_recovery_min
              FROM cardio_workouts
             WHERE user_id = v_caller_id
               AND (started_at AT TIME ZONE p_timezone)::DATE = v_today
               AND EXTRACT(HOUR FROM (started_at AT TIME ZONE p_timezone)) >= 18
               AND COALESCE(activity_type, '') IN ('walk','hike','yoga','stretch','mobility','foam_rolling');
            IF v_evening_recovery_min >= 15 THEN
                PERFORM public.update_quest_progress(v_caller_id::TEXT, v_quest.quest_key, 1, p_timezone);
                v_completed := array_append(v_completed, v_quest.quest_key);
            ELSE
                v_skipped := array_append(v_skipped, v_quest.quest_key);
            END IF;
        END IF;
    END LOOP;

    RETURN jsonb_build_object(
        'success', TRUE,
        'completed', v_completed,
        'skipped', v_skipped,
        'date', v_today,
        'band', COALESCE(v_readiness.band, 'unknown'),
        'score', COALESCE(v_readiness.score, 0)
    );
END;
$$;

REVOKE ALL ON FUNCTION public.verify_wearable_quests_for_today(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.verify_wearable_quests_for_today(TEXT) TO authenticated;

COMMENT ON FUNCTION public.verify_wearable_quests_for_today(TEXT) IS
    'Actionable Recovery Quests v2 (20260611): supersedes 20260610. Adds detection for evening_wind_down (recovery cardio after 6pm local). Legacy passive sensor-state quests (sleep_8h_wearable / recovery_above_67 / hrv_above_baseline / rhr_in_healthy_range / log_readiness_am) are soft-disabled at the template level but their detection branches stay for backwards-compat with in-flight assignments — log_readiness_am has no branch because it never had a verifier.';

COMMIT;

-- ─── Verification ─────────────────────────────────────────────────────────
-- SELECT quest_key, title, is_active, requires_context, xp_reward
--   FROM quest_templates
--  WHERE quest_key IN (
--      'sleep_8h_wearable', 'sleep_7_hours', 'log_readiness_am',
--      'evening_wind_down'
--  )
--  ORDER BY is_active DESC, quest_key;
--
-- Expected: evening_wind_down is_active=TRUE, three legacy rows is_active=FALSE.
--
-- SELECT COUNT(*) FROM user_daily_quests
--  WHERE quest_key = 'log_readiness_am' AND quest_date = current_date;
-- Expected: 0 (post-cleanup) for completed=FALSE rows.
