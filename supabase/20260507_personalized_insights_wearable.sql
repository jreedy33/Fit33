-- 20260507_personalized_insights_wearable.sql
-- Wearable Personalization Platform — Phase 2a (Server-side insights pipeline)
--
-- Extends `user_personalized_insights` with the correlation-shape
-- fields the nightly `compute-readiness-insights` edge function needs
-- to write, and wires the pg_cron schedule that invokes it at
-- 03:30 UTC for active users. The Swift `PersonalizedInsightsService`
-- then reads these rows on demand (no schema change required on the
-- Swift side — new fields are additive).
--
-- Correlations we compute (one row per (user_id, insight_key)):
--   sleep_hours_vs_pr_rate    — does sleep ≥ 7h predict PR success?
--   hrv_delta_vs_pr_success   — does HRV-above-baseline predict PRs?
--   readiness_band_vs_adherence — does band influence attendance?
--   strain_avg_vs_rhr_trend   — overtraining early-warning signal.
--   protein_x_sleep_vs_recovery — compound factor for recovery speed.
--
-- Invariants:
--   * `security_invoker = on` on the new view (SUPABASE_AGENT §6).
--   * Cron wrapper reads secrets from `internal_config` — same pattern
--     as `trigger_challenge_opponent_wake()` / `trigger_triage_bugs()`.
--   * No IDOR surface — the edge function authenticates via
--     `x-cron-key` (service_role); users cannot invoke it directly.

BEGIN;

-- 1. Extend user_personalized_insights ---------------------------------
-- All columns NULLABLE so historical insights (pre-Phase 2) keep
-- working. Future rows written by the edge function populate all
-- correlation fields.
--
-- `insight_key` didn't exist prior to this migration — the legacy
-- `PersonalizedInsightsService.generateInsight(...)` just inserts rows
-- without a stable upsert key. We add it here so the nightly edge
-- function's per-user correlation cards don't duplicate on rerun.
-- Existing rows stay with NULL `insight_key` and keep behaving as
-- append-only legacy insights. DO blocks (instead of inline ADD
-- CONSTRAINT ... ADD CHECK) keep the migration idempotent without
-- worrying about duplicate constraint names from a partial prior run.
ALTER TABLE public.user_personalized_insights
    ADD COLUMN IF NOT EXISTS insight_key TEXT,
    ADD COLUMN IF NOT EXISTS correlation_type TEXT,
    ADD COLUMN IF NOT EXISTS r_squared NUMERIC,
    ADD COLUMN IF NOT EXISTS p_value NUMERIC,
    ADD COLUMN IF NOT EXISTS sample_size INTEGER,
    ADD COLUMN IF NOT EXISTS wearable_source TEXT;

-- Re-add CHECK constraints idempotently. Named so re-runs don't
-- create duplicates.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
         WHERE conname = 'user_personalized_insights_r_squared_range'
    ) THEN
        ALTER TABLE public.user_personalized_insights
            ADD CONSTRAINT user_personalized_insights_r_squared_range
            CHECK (r_squared IS NULL OR (r_squared >= 0 AND r_squared <= 1));
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
         WHERE conname = 'user_personalized_insights_p_value_range'
    ) THEN
        ALTER TABLE public.user_personalized_insights
            ADD CONSTRAINT user_personalized_insights_p_value_range
            CHECK (p_value IS NULL OR (p_value >= 0 AND p_value <= 1));
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
         WHERE conname = 'user_personalized_insights_sample_size_nonneg'
    ) THEN
        ALTER TABLE public.user_personalized_insights
            ADD CONSTRAINT user_personalized_insights_sample_size_nonneg
            CHECK (sample_size IS NULL OR sample_size >= 0);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
         WHERE conname = 'user_personalized_insights_wearable_source_enum'
    ) THEN
        ALTER TABLE public.user_personalized_insights
            ADD CONSTRAINT user_personalized_insights_wearable_source_enum
            CHECK (
                wearable_source IS NULL
                OR wearable_source IN ('whoop', 'oura', 'fitbit', 'healthkit', 'derived')
            );
    END IF;
END $$;

COMMENT ON COLUMN public.user_personalized_insights.insight_key IS
'Wearable Personalization Phase 2 — stable machine key (e.g.
 "insight_sleep_pr", "insight_hrv_pr") used by the nightly edge
 function to upsert correlations without duplicating rows. NULL for
 legacy append-only insights written by the on-device
 PersonalizedInsightsService.';

COMMENT ON COLUMN public.user_personalized_insights.correlation_type IS
'Wearable Personalization Phase 2 — machine key for correlation:
 sleep_hours_vs_pr_rate | hrv_delta_vs_pr_success |
 readiness_band_vs_adherence | strain_avg_vs_rhr_trend |
 protein_x_sleep_vs_recovery. NULL for legacy on-device insights.';

COMMENT ON COLUMN public.user_personalized_insights.r_squared IS
'Coefficient of determination 0-1. NULL when the insight is rule-based
 (e.g. "drink more water on heavy days") not statistical.';

COMMENT ON COLUMN public.user_personalized_insights.p_value IS
'Two-tailed p-value 0-1. Edge function filters correlations with
 p > 0.15 out before writing so the UI never shows noise.';

COMMENT ON COLUMN public.user_personalized_insights.sample_size IS
'Number of observations (paired days) that backed this correlation.
 UI hides insights with sample_size < 10.';

-- 2. insight_key uniqueness per user -----------------------------------
-- Edge function upserts by (user_id, insight_key) so nightly reruns
-- don't duplicate cards. Partial unique index: scoped to rows where
-- `insight_key IS NOT NULL` so the legacy rows (which never populated
-- insight_key) continue to coexist without violating uniqueness.
CREATE UNIQUE INDEX IF NOT EXISTS idx_personalized_insights_user_key
    ON public.user_personalized_insights (user_id, insight_key)
    WHERE insight_key IS NOT NULL;

-- 3. Dashboard-facing view ---------------------------------------------
-- Only rows from the last 14 days, meeting the significance gate
-- (p_value <= 0.15, sample_size >= 10, OR legacy on-device insight
-- with no correlation metadata). `security_invoker = on` so RLS
-- applies to the caller. Columns reflect the canonical
-- user_personalized_insights schema (`insight_type` + `insight_category`,
-- `priority` + `icon` + `accent_color` — no `severity`/`action_label`).
DROP VIEW IF EXISTS public.v_user_wearable_insights;

CREATE VIEW public.v_user_wearable_insights
    WITH (security_invoker = on) AS
SELECT
    id,
    user_id,
    insight_key,
    insight_type,
    insight_category,
    title,
    message,
    detail_message,
    priority,
    icon,
    accent_color,
    correlation_type,
    r_squared,
    p_value,
    sample_size,
    wearable_source,
    created_at,
    updated_at
FROM public.user_personalized_insights
WHERE
    created_at >= (now() - INTERVAL '14 days')
    AND COALESCE(is_dismissed, FALSE) = FALSE
    AND (
        correlation_type IS NULL  -- legacy rule-based insights pass through
        OR (
            correlation_type IS NOT NULL
            AND COALESCE(sample_size, 0) >= 10
            AND COALESCE(p_value, 1) <= 0.15
        )
    )
ORDER BY
    user_id,
    COALESCE(priority, 0) DESC,
    created_at DESC;

COMMENT ON VIEW public.v_user_wearable_insights IS
'Fresh (<=14d) correlation-backed wearable insights surfaced by the
 Dashboard Smart Welcome + HealthInsightsView. Filters noise via
 sample_size >= 10 AND p_value <= 0.15. Legacy on-device insights
 (correlation_type IS NULL) pass through unchanged.';

-- 4. trigger_compute_readiness_insights — pg_cron wrapper --------------
-- Follows the canonical `internal_config` + `x-cron-key` pattern
-- (SUPABASE_AGENT invariant #25 / supabase-rules #7). Fires nightly
-- at 03:30 UTC — offset from other cron sweeps (03:10, 03:45) to
-- stagger edge-function cold starts.
CREATE OR REPLACE FUNCTION public.trigger_compute_readiness_insights()
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
        RAISE WARNING 'compute_readiness_insights: internal_config missing required keys — skipping';
        RETURN;
    END IF;

    PERFORM net.http_post(
        url     := v_url || '/functions/v1/compute-readiness-insights',
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

REVOKE ALL ON FUNCTION public.trigger_compute_readiness_insights() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.trigger_compute_readiness_insights() TO service_role;

-- 5. pg_cron schedule --------------------------------------------------
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'compute-readiness-insights-nightly') THEN
        PERFORM cron.unschedule('compute-readiness-insights-nightly');
    END IF;
END $$;

SELECT cron.schedule(
    'compute-readiness-insights-nightly',
    '30 3 * * *',
    $$SELECT public.trigger_compute_readiness_insights()$$
);

DO $$ BEGIN
    RAISE NOTICE '✅ user_personalized_insights extended + compute-readiness-insights cron scheduled (03:30 UTC nightly)';
END $$;

COMMIT;

-- ─── Verification queries (safe to re-run) ─────────────────────────────
-- SELECT column_name FROM information_schema.columns
--  WHERE table_schema = 'public' AND table_name = 'user_personalized_insights'
--    AND column_name IN ('correlation_type','r_squared','p_value','sample_size','wearable_source');
-- SELECT jobname, schedule, active FROM cron.job
--  WHERE jobname = 'compute-readiness-insights-nightly';
-- SELECT 1 FROM pg_views WHERE schemaname = 'public'
--   AND viewname = 'v_user_wearable_insights';
