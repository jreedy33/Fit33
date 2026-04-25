-- ════════════════════════════════════════════════════════════════════
-- BUNDLE: B — Strava integration (4 files; pairs with the 2 deployed edge functions)
-- Concatenated 2026-04-25 14:34 EDT from individual migrations
-- on disk under supabase/. Each source file keeps its own
-- BEGIN; ... COMMIT; — paste this whole file into the SQL editor
-- and Postgres will run them serially as separate transactions.
-- All idempotent: safe to re-run.
-- ════════════════════════════════════════════════════════════════════


-- ════════════════════════════════════════════════════════════════════
-- SOURCE: supabase/20260530_cardio_workouts_strava_detail.sql
-- ════════════════════════════════════════════════════════════════════

-- =============================================================================
-- cardio_workouts: Strava detail + streams enrichment columns
-- =============================================================================
-- Phase 2 of the Strava Integration Upgrade. The current Strava sync only
-- writes the fields available in `GET /athlete/activities` (the list
-- endpoint). Strava exposes much richer data via:
--   * `GET /activities/{id}`        — splits, segment efforts, gear, kudos,
--                                     suffer score, polyline summary, etc.
--   * `GET /activities/{id}/streams`— full HR / pace / cadence / power /
--                                     altitude time-series for the activity.
--
-- We persist the fields we want to show in the Dashboard recap, segment PR
-- insights, and HR-zone analytics directly as columns; everything else lands
-- in `streams_json` / `splits_json` / `segment_efforts_json` so the recap
-- sheet can render arbitrary cuts without a follow-up API call.
--
-- Idempotent — uses `IF NOT EXISTS` so re-running this migration on an
-- already-enriched DB is a no-op (Data invariant #20).
-- =============================================================================

BEGIN;

ALTER TABLE public.cardio_workouts
    ADD COLUMN IF NOT EXISTS suffer_score          INT,
    ADD COLUMN IF NOT EXISTS kudos_count           INT,
    ADD COLUMN IF NOT EXISTS achievement_count     INT,
    ADD COLUMN IF NOT EXISTS polyline_summary      TEXT,
    ADD COLUMN IF NOT EXISTS splits_json           JSONB,
    ADD COLUMN IF NOT EXISTS segment_efforts_json  JSONB,
    ADD COLUMN IF NOT EXISTS streams_json          JSONB,
    ADD COLUMN IF NOT EXISTS gear_name             TEXT,
    ADD COLUMN IF NOT EXISTS detail_synced_at      TIMESTAMPTZ;

COMMENT ON COLUMN public.cardio_workouts.suffer_score IS
    'Strava Relative Effort score (formerly "Suffer Score"). NULL when the source did not provide one.';
COMMENT ON COLUMN public.cardio_workouts.kudos_count IS
    'Strava kudos count at the time the activity detail was synced; refreshed on next enrichment pass.';
COMMENT ON COLUMN public.cardio_workouts.achievement_count IS
    'Strava achievement count (PRs / KOMs detected on the activity).';
COMMENT ON COLUMN public.cardio_workouts.polyline_summary IS
    'Encoded summary polyline from Strava `map.summary_polyline` — used for the dashboard mini-map preview.';
COMMENT ON COLUMN public.cardio_workouts.splits_json IS
    'Strava `splits_metric` array (per-km splits with pace, elevation, HR).';
COMMENT ON COLUMN public.cardio_workouts.segment_efforts_json IS
    'Strava `segment_efforts` array (filtered to PR-eligible / leaderboard segments).';
COMMENT ON COLUMN public.cardio_workouts.streams_json IS
    'Strava streams (heartrate, cadence, watts, velocity_smooth, altitude) keyed by stream type. Used for HR zone + pace charts in the recap sheet.';
COMMENT ON COLUMN public.cardio_workouts.gear_name IS
    'Strava gear (shoe / bike) name attached to the activity.';
COMMENT ON COLUMN public.cardio_workouts.detail_synced_at IS
    'Timestamp of the last successful detail+streams enrichment for this row. NULL = list-only (raw sync).';

-- Useful for the nightly insights computer to find activities that need
-- enrichment (or are due for a kudos refresh).
CREATE INDEX IF NOT EXISTS idx_cardio_workouts_strava_pending_enrichment
    ON public.cardio_workouts (user_id, started_at DESC)
    WHERE source = 'strava' AND detail_synced_at IS NULL;

COMMIT;


-- ════════════════════════════════════════════════════════════════════
-- SOURCE: supabase/20260531_strava_quest_templates.sql
-- ════════════════════════════════════════════════════════════════════

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


-- ════════════════════════════════════════════════════════════════════
-- SOURCE: supabase/20260532_strava_insights_cron.sql
-- ════════════════════════════════════════════════════════════════════

-- Strava insights cron — Phase 3 of Strava Integration Upgrade.
--
-- Wires the new `compute-strava-insights` edge function to pg_cron.
-- Mirrors the `trigger_compute_readiness_insights` pattern from
-- 20260507_personalized_insights_wearable.sql (canonical
-- `internal_config` + `x-cron-key` invariant — SUPABASE_AGENT #25,
-- supabase-rules #7).
--
-- The edge function itself reads `cardio_workouts` (Strava rows) and
-- `daily_readiness_history`, then upserts five strava_* insight cards
-- into `user_personalized_insights` using `onConflict:user_id,insight_key`.
--
-- Idempotent. Wrapped BEGIN/COMMIT.

BEGIN;

CREATE OR REPLACE FUNCTION public.trigger_compute_strava_insights()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_url  TEXT;
    v_key  TEXT;
    v_anon TEXT;
BEGIN
    SELECT value INTO v_url  FROM internal_config WHERE key = 'supabase_url';
    SELECT value INTO v_key  FROM internal_config WHERE key = 'service_role_key';
    SELECT value INTO v_anon FROM internal_config WHERE key = 'anon_key';

    IF v_url IS NULL OR v_key IS NULL OR v_anon IS NULL THEN
        RAISE WARNING 'compute_strava_insights: internal_config missing required keys — skipping';
        RETURN;
    END IF;

    PERFORM net.http_post(
        url     := v_url || '/functions/v1/compute-strava-insights',
        headers := jsonb_build_object(
            'Authorization', 'Bearer ' || v_anon,
            'apikey',        v_anon,
            'x-cron-key',    v_key,
            'Content-Type',  'application/json'
        ),
        body    := '{"source": "cron"}'::jsonb
    );
END;
$$;

REVOKE ALL ON FUNCTION public.trigger_compute_strava_insights() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.trigger_compute_strava_insights() TO service_role;

COMMENT ON FUNCTION public.trigger_compute_strava_insights() IS
    'Phase 3 Strava integration: pg_cron entrypoint that POSTs to the compute-strava-insights edge function. Auth via x-cron-key + service_role bearer.';

-- Schedule nightly at 03:40 UTC — offset from compute-readiness-insights
-- (03:30) and bug-intel sweeps (03:45 / 04:30) so cold-starts stagger.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'compute-strava-insights-nightly') THEN
            PERFORM cron.unschedule('compute-strava-insights-nightly');
        END IF;

        PERFORM cron.schedule(
            'compute-strava-insights-nightly',
            '40 3 * * *',
            $cron$ SELECT public.trigger_compute_strava_insights() $cron$
        );
        RAISE NOTICE '✅ Scheduled compute-strava-insights-nightly (03:40 UTC daily)';
    ELSE
        RAISE NOTICE 'pg_cron not installed — trigger_compute_strava_insights() must be invoked manually';
    END IF;
END $$;

COMMIT;


-- ════════════════════════════════════════════════════════════════════
-- SOURCE: supabase/20260533_strava_webhook_tokens.sql
-- ════════════════════════════════════════════════════════════════════

-- 20260533_strava_webhook_tokens.sql
-- Phase 5 of Strava Integration Upgrade — server-side token store so the
-- Strava webhook edge function can fetch activity detail + write to
-- cardio_workouts without an iOS device being awake.
--
-- iOS still owns the keychain copy (primary) — this table is a
-- write-mirror used only by the webhook function. Refresh-token rotation
-- (Strava rotates the refresh token on every refresh) is handled by
-- whichever side refreshed last; both sides trust the latest expires_at.
--
-- Invariants:
--   * RLS on every user-data table (codingrules / SUPABASE_AGENT §2).
--   * SECURITY DEFINER RPC never accepts user_id (Data invariant #7) —
--     pinned to auth.uid().
--   * Drop all overloads before CREATE OR REPLACE (Data invariant #38).
--   * Idempotent. Wrapped BEGIN/COMMIT.

BEGIN;

-- 1. Table -----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.user_strava_tokens (
    user_id        UUID PRIMARY KEY REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    access_token   TEXT NOT NULL,
    refresh_token  TEXT NOT NULL,
    expires_at     TIMESTAMPTZ NOT NULL,
    athlete_id     BIGINT,
    last_rotated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.user_strava_tokens IS
    'Server-side mirror of Strava OAuth tokens. Written by the iOS client (dual-write with keychain) and by the strava-webhook edge function on refresh. Used by webhook function to fetch activity detail when the iOS app is offline.';

CREATE INDEX IF NOT EXISTS idx_user_strava_tokens_athlete_id
    ON public.user_strava_tokens (athlete_id)
    WHERE athlete_id IS NOT NULL;

-- 2. RLS -------------------------------------------------------------------
ALTER TABLE public.user_strava_tokens ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can read own strava tokens"   ON public.user_strava_tokens;
DROP POLICY IF EXISTS "Users can update own strava tokens" ON public.user_strava_tokens;
DROP POLICY IF EXISTS "Users can delete own strava tokens" ON public.user_strava_tokens;

-- SELECT / UPDATE / DELETE only by the owning user. INSERT goes through
-- the SECURITY DEFINER RPC below — never directly.
CREATE POLICY "Users can read own strava tokens"
    ON public.user_strava_tokens
    FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can update own strava tokens"
    ON public.user_strava_tokens
    FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete own strava tokens"
    ON public.user_strava_tokens
    FOR DELETE
    USING (auth.uid() = user_id);

-- 3. Upsert RPC ------------------------------------------------------------
-- Drop all overloads first per Data invariant #38.
DROP FUNCTION IF EXISTS public.upsert_strava_tokens(TEXT, TEXT, TIMESTAMPTZ, BIGINT);
DROP FUNCTION IF EXISTS public.upsert_strava_tokens(TEXT, TEXT, TIMESTAMPTZ);

CREATE OR REPLACE FUNCTION public.upsert_strava_tokens(
    p_access     TEXT,
    p_refresh    TEXT,
    p_expires_at TIMESTAMPTZ,
    p_athlete_id BIGINT DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := auth.uid();
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'upsert_strava_tokens: not authenticated';
    END IF;

    INSERT INTO public.user_strava_tokens (
        user_id, access_token, refresh_token, expires_at, athlete_id, last_rotated_at, updated_at
    ) VALUES (
        v_user_id, p_access, p_refresh, p_expires_at, p_athlete_id, now(), now()
    )
    ON CONFLICT (user_id) DO UPDATE SET
        access_token    = EXCLUDED.access_token,
        refresh_token   = EXCLUDED.refresh_token,
        expires_at      = EXCLUDED.expires_at,
        athlete_id      = COALESCE(EXCLUDED.athlete_id, public.user_strava_tokens.athlete_id),
        last_rotated_at = now(),
        updated_at      = now();
END;
$$;

REVOKE ALL ON FUNCTION public.upsert_strava_tokens(TEXT, TEXT, TIMESTAMPTZ, BIGINT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.upsert_strava_tokens(TEXT, TEXT, TIMESTAMPTZ, BIGINT) TO authenticated;

COMMENT ON FUNCTION public.upsert_strava_tokens(TEXT, TEXT, TIMESTAMPTZ, BIGINT) IS
    'SECURITY DEFINER upsert — caller user pinned to auth.uid() (Data invariant #7). Used by Fit33/StravaService.swift dual-write after OAuth exchange and after every refresh rotation.';

-- 4. Service-role helper (used by strava-webhook to find a user from
--    Strava athlete_id) ------------------------------------------------------
DROP FUNCTION IF EXISTS public.get_user_id_for_strava_athlete(BIGINT);

CREATE OR REPLACE FUNCTION public.get_user_id_for_strava_athlete(p_athlete_id BIGINT)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID;
BEGIN
    SELECT user_id INTO v_user_id
    FROM public.user_strava_tokens
    WHERE athlete_id = p_athlete_id
    LIMIT 1;
    RETURN v_user_id;
END;
$$;

REVOKE ALL ON FUNCTION public.get_user_id_for_strava_athlete(BIGINT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_user_id_for_strava_athlete(BIGINT) TO service_role;

COMMENT ON FUNCTION public.get_user_id_for_strava_athlete(BIGINT) IS
    'Service-role-only lookup for the strava-webhook edge function — maps Strava owner_id → app user_id without exposing the tokens table to anon.';

-- 5. updated_at trigger ----------------------------------------------------
CREATE OR REPLACE FUNCTION public._user_strava_tokens_set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_user_strava_tokens_updated_at ON public.user_strava_tokens;
CREATE TRIGGER trg_user_strava_tokens_updated_at
BEFORE UPDATE ON public.user_strava_tokens
FOR EACH ROW
EXECUTE FUNCTION public._user_strava_tokens_set_updated_at();

DO $$ BEGIN
    RAISE NOTICE '✅ user_strava_tokens table + RLS + upsert RPC + service-role lookup created';
END $$;

COMMIT;

