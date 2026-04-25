-- ============================================================================
-- 20260610 — Retire passive recovery quests, ship actionable replacements
--
-- User feedback (2026-04-25): "Green Recovery" (recovery_above_67) is a
-- pre-determined pass/fail — if you wake up red, the quest is already lost
-- before the user can take any action. Daily quests must be things the user
-- has agency over **today**, not summaries of overnight sensor state.
--
-- Three quests fail this test (introduced in 20260509_wearable_quests.sql):
--   * recovery_above_67     "Green Recovery"  — band ≥ 67 by wake-up
--   * hrv_above_baseline    "HRV Warrior"     — overnight HRV reading
--   * rhr_in_healthy_range  "Steady Heart"    — overnight RHR reading
--
-- This migration:
--   1. SOFT-disables the three passive templates (`is_active = FALSE`).
--      Templates are kept on disk so historical `user_daily_quests` rows
--      stay valid and the existing `verify_wearable_quests_for_today`
--      detection logic remains backwards-compatible for any in-flight
--      assignments that were issued before today (RPC will quietly
--      complete them if the user happens to satisfy the condition).
--
--   2. INSERTS three actionable replacements gated `requires_context =
--      'has_wearable'`, all auto-verifiable from `cardio_workouts`:
--
--      * active_recovery_logged "Active Recovery"
--          Log walk/yoga/stretch/mobility/foam-rolling ≥15 min today.
--          Replaces Green Recovery's spirit ("respect today's body")
--          with an action the user can take regardless of band color.
--
--      * zone_2_minutes_20 "Zone 2 Cardio"
--          Cardio session today with elapsed_seconds ≥ 1200 (20 min)
--          AND average_heart_rate in [110, 150] bpm. Replaces HRV
--          Warrior's spirit (zone-2 training is the canonical
--          HRV-positive intensity). HR range is age-agnostic and
--          captures Zone 2 for the typical adult max-HR (180-200 bpm
--          → 60-70% = ~108-140 bpm; we use 110-150 to allow some
--          slack for trained users with higher Z2 ceilings).
--
--      * cardio_minutes_20 "Heart Healthy"
--          Any cardio_workouts row today with elapsed_seconds ≥ 1200.
--          Replaces Steady Heart's spirit (cardiovascular health) with
--          a logged-cardio action. Distinct from `active_minutes_30`
--          (which is HealthKit ambient-active-minutes from any
--          movement) — this requires an actual logged session.
--
--   3. EXTENDS `public.verify_wearable_quests_for_today(p_timezone TEXT)`
--      to detect the three new quest_keys. The function already loops
--      over today's `user_daily_quests`; we widen the IN(...) filter and
--      add three ELSIF branches. Same `auth.uid()`-pinned SECURITY DEFINER
--      shape from 20260606. All queries use `(started_at AT TIME ZONE
--      p_timezone)::DATE = v_today` for timezone-correct windowing.
--
-- iOS notes:
--   * `Fit33/DailyQuestService.swift::onReadinessRecomputed` already
--     calls `verify_wearable_quests_for_today` after every
--     `ReadinessService.recompute()`; the new quest_keys ride that path.
--   * No `QuestKey` enum case is needed — `DailyQuest.questKey` is a
--     `String` and the icon / title / description come from
--     `quest_templates`, so new keys render via the generic path.
--   * The Swift `wearableKeys` set in `onReadinessRecomputed` does not
--     need updating; it's only used as an early-exit predicate, and a
--     superset (which it remains) is harmless.
--   * Cardio workout completion is also a natural verification trigger
--     for `active_recovery_logged` / `zone_2_minutes_20` /
--     `cardio_minutes_20`. Hooking those into
--     `HealthDataService` / `StravaService` cardio-import paths is a
--     paired iOS change tracked in DATA_BACKEND_AGENT.md (low-priority —
--     the readiness recompute path runs frequently enough that
--     verification will fire within minutes of a cardio workout import).
--
-- Idempotent: re-running is a no-op (UPDATE … WHERE is_active flips back
-- to FALSE, INSERT … ON CONFLICT DO UPDATE refreshes the new templates,
-- DROP FUNCTION … IF EXISTS + CREATE OR REPLACE for the verifier).
-- ============================================================================

BEGIN;

-- 1. Soft-disable the three passive sensor-state quests --------------------
UPDATE quest_templates
   SET is_active = FALSE
 WHERE quest_key IN ('recovery_above_67', 'hrv_above_baseline', 'rhr_in_healthy_range');

-- 2. Seed actionable replacements ------------------------------------------
-- XP rewards intentionally match the post-rebalance values the disabled
-- quests carried (see 20260603 — auto verification × 1.5). The 1.5×
-- multiplier was already applied to the original 25 / 30 / 20 base XP
-- numbers, yielding 38 / 45 / 30. We seed the post-multiplier numbers
-- directly so the 20260603 rebalance does NOT re-apply on re-run (the
-- migration is gated by an `internal_config` row).
INSERT INTO quest_templates (
    quest_key, title, description, icon, category, target_value, target_unit,
    xp_reward, league_points, difficulty, weight, requires_context, fun_label,
    verification_type, min_workouts, is_active, tier
) VALUES
    ('active_recovery_logged',
        'Active Recovery',
        'Log 15+ min of walk, yoga, or mobility',
        'figure.mind.and.body',
        'workout', 15, 'minutes',
        38, 23, 'easy', 9, 'has_wearable',
        '🧘 Move easy today',
        'auto', 0, TRUE, 'free'),

    ('zone_2_minutes_20',
        'Zone 2 Cardio',
        'Hit 20+ min cardio at HR 110–150',
        'heart.text.square.fill',
        'workout', 20, 'minutes',
        45, 30, 'medium', 8, 'has_wearable',
        '⚡ HRV-friendly pace',
        'auto', 0, TRUE, 'free'),

    ('cardio_minutes_20',
        'Heart Healthy',
        'Get 20+ min of cardio in today',
        'heart.fill',
        'workout', 20, 'minutes',
        30, 15, 'easy', 8, 'has_wearable',
        '❤️ Steady the engine',
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

-- 3. Extend verify_wearable_quests_for_today --------------------------------
-- Drop every overload first (supabase-rules §12). Then re-create with the
-- expanded IN(...) filter + three new ELSIF branches.
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
    v_recovery_workout_today BOOLEAN;
BEGIN
    IF v_caller_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required'
            USING ERRCODE = 'P0001';
    END IF;

    v_today := (now() AT TIME ZONE p_timezone)::DATE;

    -- Latest readiness row for today (band / score / sleep / hrv / rhr).
    -- Used by the legacy passive quests AND by `walk_when_red` /
    -- `respect_red_recovery` / `match_yesterday_strain` which gate on band.
    SELECT band, score, sleep_hours, hrv_delta_pct, rhr_trend_bpm
      INTO v_readiness
      FROM daily_readiness_history
     WHERE user_id = v_caller_id
       AND date = v_today
     ORDER BY updated_at DESC
     LIMIT 1;

    -- New actionable quests (active_recovery_logged / zone_2_minutes_20 /
    -- cardio_minutes_20) do NOT require a readiness row; they verify
    -- straight from `cardio_workouts`. So we no longer early-return when
    -- v_readiness IS NULL — instead, each branch handles its own
    -- precondition.

    FOR v_quest IN
        SELECT udq.id, udq.quest_key
          FROM user_daily_quests udq
         WHERE udq.user_id = v_caller_id
           AND udq.quest_date = v_today
           AND udq.is_completed = FALSE
           AND udq.quest_key IN (
               -- Legacy (kept for backwards-compat with already-assigned
               -- rows; templates are soft-disabled so no NEW assignments).
               'sleep_8h_wearable','recovery_above_67','hrv_above_baseline',
               'rhr_in_healthy_range','respect_red_recovery',
               -- Actionable wearable quests
               'walk_when_red',
               -- New actionable replacements (this migration)
               'active_recovery_logged','zone_2_minutes_20','cardio_minutes_20'
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
            -- Any walk/hike/yoga/stretch/mobility/foam-rolling cardio today
            -- summing to >= 15 minutes. No band gate — actionable on any day.
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
            -- Sum minutes from cardio_workouts today where the session's
            -- average_heart_rate fell in [110, 150] bpm AND the session
            -- itself ran >= 5 min (filters out garbage 30-second rows).
            -- Threshold: total >= 20 min. Multiple short Z2 sessions stack.
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
            -- Any cardio_workouts row today (any HR / type) summing to
            -- >= 20 minutes. Distinct from `active_minutes_30` which is
            -- HealthKit ambient-active-minutes (steps + low-intensity);
            -- this requires actual logged cardio sessions.
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
    'Actionable Recovery Quests (20260610): supersedes 20260606. Walks today user_daily_quests for the caller and ticks any wearable-detectable completion. Adds detection for active_recovery_logged / zone_2_minutes_20 / cardio_minutes_20 (all from cardio_workouts, no readiness-row gate). Legacy passive sensor-state quests (recovery_above_67 / hrv_above_baseline / rhr_in_healthy_range) are soft-disabled at the template level but their detection branches are retained for backwards-compat with in-flight assignments.';

COMMIT;

-- ─── Verification ─────────────────────────────────────────────────────────
-- SELECT quest_key, title, is_active, requires_context, xp_reward
--   FROM quest_templates
--  WHERE quest_key IN (
--      'recovery_above_67', 'hrv_above_baseline', 'rhr_in_healthy_range',
--      'active_recovery_logged', 'zone_2_minutes_20', 'cardio_minutes_20'
--  )
--  ORDER BY is_active DESC, quest_key;
--
-- Expected: three new rows is_active=TRUE, three legacy rows is_active=FALSE.
