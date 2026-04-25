-- Strava daily-quest templates + detection helper
--
-- Phase 3 of Strava Integration Upgrade. Adds three outdoor-cardio quest
-- templates that key off cardio_workouts rows where source = 'strava'
-- (or origin_app = 'strava' / 'runna') and a helper RPC that the daily
-- quest service can call to determine completion.
--
-- Idempotent / safe to re-run. RLS not applicable to quest_templates
-- (admin-managed, public read).

BEGIN;

-- 1. Quest templates -------------------------------------------------------
INSERT INTO quest_templates (
    quest_key, title, description, icon, category,
    target_value, target_unit, xp_reward, league_points,
    difficulty, weight, requires_context, fun_label,
    verification_type, min_workouts
) VALUES
    ('run_outside_3km',     'Out the Door',         'Run 3km outside today',                    'figure.run',         'workout', 3000,  'meters', 30, 15, 'easy',   8, NULL, '🏃 Fresh air run',         'auto', 0),
    ('run_outside_5km',     '5K Sweat',             'Run 5km outside today',                    'figure.run',         'workout', 5000,  'meters', 45, 25, 'medium', 6, NULL, '🏃 Hit the pavement',      'auto', 6),
    ('cycle_outside_15km',  'Spin Outside',         'Cycle 15km outside today',                 'figure.outdoor.cycle','workout', 15000, 'meters', 40, 20, 'medium', 6, NULL, '🚴 Roll the miles',        'auto', 6)
ON CONFLICT (quest_key) DO UPDATE SET
    title             = EXCLUDED.title,
    description       = EXCLUDED.description,
    icon              = EXCLUDED.icon,
    category          = EXCLUDED.category,
    target_value      = EXCLUDED.target_value,
    target_unit       = EXCLUDED.target_unit,
    xp_reward         = EXCLUDED.xp_reward,
    league_points     = EXCLUDED.league_points,
    difficulty        = EXCLUDED.difficulty,
    weight            = EXCLUDED.weight,
    requires_context  = EXCLUDED.requires_context,
    fun_label         = EXCLUDED.fun_label,
    verification_type = EXCLUDED.verification_type,
    min_workouts      = EXCLUDED.min_workouts;

-- 2. Detection helper ------------------------------------------------------
-- Drop all overloads (Supabase invariant) before recreating.
DROP FUNCTION IF EXISTS public.is_strava_quest_completed(UUID, TEXT, TEXT);

CREATE OR REPLACE FUNCTION public.is_strava_quest_completed(
    p_user_id UUID,
    p_quest_key TEXT,
    p_timezone TEXT DEFAULT 'UTC'
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_caller_id UUID := auth.uid();
    v_today     DATE := (now() AT TIME ZONE p_timezone)::DATE;
    v_required_meters INT;
    v_required_types TEXT[];
    v_count INT;
BEGIN
    -- IDOR guard (Data invariant #7): SECURITY DEFINER never trusts p_user_id;
    -- always pin to auth.uid(). p_user_id is accepted only for compat with
    -- callers that pass it explicitly.
    IF v_caller_id IS NULL OR v_caller_id <> p_user_id THEN
        RETURN FALSE;
    END IF;

    -- activity_type values match StravaService.mapStravaActivityType output
    -- (outdoor_run, outdoor_cycle, treadmill, etc.). For "outside" quests
    -- we explicitly exclude treadmill / indoor_cycle.
    CASE p_quest_key
        WHEN 'run_outside_3km' THEN
            v_required_meters := 3000;
            v_required_types  := ARRAY['outdoor_run'];
        WHEN 'run_outside_5km' THEN
            v_required_meters := 5000;
            v_required_types  := ARRAY['outdoor_run'];
        WHEN 'cycle_outside_15km' THEN
            v_required_meters := 15000;
            v_required_types  := ARRAY['outdoor_cycle'];
        ELSE
            RETURN FALSE;
    END CASE;

    SELECT COUNT(*) INTO v_count
    FROM public.cardio_workouts cw
    WHERE cw.user_id = v_caller_id
      AND cw.source IN ('strava')
      AND COALESCE(cw.activity_type, '') = ANY (v_required_types)
      AND COALESCE(cw.distance_meters, 0) >= v_required_meters
      AND (cw.started_at AT TIME ZONE p_timezone)::DATE = v_today;

    RETURN v_count > 0;
END;
$$;

GRANT EXECUTE ON FUNCTION public.is_strava_quest_completed(UUID, TEXT, TEXT) TO authenticated;

COMMENT ON FUNCTION public.is_strava_quest_completed(UUID, TEXT, TEXT) IS
    'Phase 3 Strava integration: returns TRUE when the caller has logged a qualifying outdoor Strava activity today. Used by daily-quest verification.';

COMMIT;
