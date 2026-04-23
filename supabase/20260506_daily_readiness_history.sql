-- 20260506_daily_readiness_history.sql
-- Wearable Personalization Platform — Phase 0 (Foundation)
--
-- Persists the per-day unified "Daily Readiness Score" computed by
-- `ReadinessService` on-device from whichever wearable the user has
-- connected (WHOOP → Oura → Fitbit → HealthKit). Wearable-agnostic
-- contract: downstream systems (auto-gen, quests, challenges,
-- insights, adaptive goals) read `daily_readiness_history` or the
-- `v_user_readiness_30d` view and never touch raw WHOOP / Oura /
-- Fitbit tables directly.
--
-- Score / band contract (matches FITNESS_EXPERT_AGENT.md invariant
-- #23 and `ReadinessBand` enum in Swift):
--     0-33   → red    (override to recovery day)
--     34-66  → yellow (normal programming, "listen to body" note)
--     67-100 → green  (encourage PR / add volume)
--
-- Blend priority (first available wins as `primary_source`):
--   1. whoop      — `whoop_recovery_data.recovery_score`
--   2. oura       — `oura_readiness_data.readiness_score`
--   3. fitbit     — normalized RHR + sleep + active minutes
--   4. healthkit  — RHR + sleep hours + step delta
--
-- Server-side nightly rollup (edge function `compute-readiness-insights`,
-- Phase 2a) back-fills this table from raw wearable rows for historical
-- analysis; day-of writes land here from iOS via
-- `SupabaseManager.upsertReadinessSnapshot(...)`.
--
-- Invariants:
--   * RLS on every user-data table (codingrules.mdc #6 / SUPABASE_AGENT §2)
--   * FK → user_profiles(id) ON DELETE CASCADE (SUPABASE_AGENT §1) — this is
--     what makes `delete_user_account(…)` automatically drop this table's
--     rows without an explicit DELETE statement there.
--   * UNIQUE(user_id, date) so day-of and nightly-rollup upserts converge
--     on the same row (client uses `onConflict: "user_id,date"`).
--   * `security_invoker = on` on the dashboard-facing view
--     (SUPABASE_AGENT §6 / supabase-rules.mdc) so RLS still applies to
--     the caller, not the view owner.

BEGIN;

-- 1. daily_readiness_history --------------------------------------------
CREATE TABLE IF NOT EXISTS public.daily_readiness_history (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
    date DATE NOT NULL,
    -- Unified 0-100 score + banded equivalent. Kept denormalized so
    -- `.eq("band","green")` queries don't need a CASE expression.
    score INTEGER NOT NULL CHECK (score BETWEEN 0 AND 100),
    band TEXT NOT NULL CHECK (band IN ('red', 'yellow', 'green')),
    -- Which wearable the blend winner came from (`whoop`, `oura`,
    -- `fitbit`, `healthkit`, or `none` if no signals available but we
    -- still wrote a row for continuity — score = 50 in that case).
    primary_source TEXT NOT NULL DEFAULT 'none'
        CHECK (primary_source IN ('whoop', 'oura', 'fitbit', 'healthkit', 'none')),
    -- Delta of HRV vs the user's personal 28-day baseline, in percent.
    -- NULL when wearable didn't supply HRV.
    hrv_delta_pct NUMERIC,
    -- Sleep last night in hours (total sleep time, not time in bed).
    sleep_hours NUMERIC,
    -- Sleep debt in minutes (7h target − sleep_hours × 60, floored at 0).
    -- Client computes; server rollup may refine vs WHOOP/Oura native.
    sleep_debt_min INTEGER,
    -- Resting HR trend: today's RHR − 28-day baseline. Positive = higher
    -- than usual (concerning).
    rhr_trend_bpm NUMERIC,
    -- WHOOP strain from the prior day cycle (1 day lag relative to
    -- `date`). NULL when no WHOOP signal.
    strain_prev NUMERIC,
    -- Free-form signals blob for the UI drill-down ("why is today red?").
    -- Schema-in-schema: array of `{kind, label, value, severity}`.
    -- Kept JSONB so we can add new signal types without a migration.
    signals JSONB NOT NULL DEFAULT '[]'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, date)
);

-- Hot path: "give me this user's readiness for the last 30 days sorted
-- newest first" — dashboard chart + auto-gen prior-day lookup.
CREATE INDEX IF NOT EXISTS idx_daily_readiness_user_date
    ON public.daily_readiness_history (user_id, date DESC);

-- Admin analytics: "how many users had a green day today?"
CREATE INDEX IF NOT EXISTS idx_daily_readiness_band_date
    ON public.daily_readiness_history (date DESC, band);

-- 2. RLS ---------------------------------------------------------------
ALTER TABLE public.daily_readiness_history ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "readiness_select_own" ON public.daily_readiness_history;
CREATE POLICY "readiness_select_own"
    ON public.daily_readiness_history
    FOR SELECT
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "readiness_insert_own" ON public.daily_readiness_history;
CREATE POLICY "readiness_insert_own"
    ON public.daily_readiness_history
    FOR INSERT
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "readiness_update_own" ON public.daily_readiness_history;
CREATE POLICY "readiness_update_own"
    ON public.daily_readiness_history
    FOR UPDATE
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "readiness_delete_own" ON public.daily_readiness_history;
CREATE POLICY "readiness_delete_own"
    ON public.daily_readiness_history
    FOR DELETE
    USING (auth.uid() = user_id);

-- 3. updated_at trigger ------------------------------------------------
CREATE OR REPLACE FUNCTION public.tg_daily_readiness_touch_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tg_daily_readiness_updated_at
    ON public.daily_readiness_history;

CREATE TRIGGER tg_daily_readiness_updated_at
    BEFORE UPDATE ON public.daily_readiness_history
    FOR EACH ROW
    EXECUTE FUNCTION public.tg_daily_readiness_touch_updated_at();

-- 4. Dashboard-friendly 30-day view -----------------------------------
-- `security_invoker = on` — RLS still applies to the calling user, so
-- callers only see their own rows even though the view could aggregate
-- across the table.
DROP VIEW IF EXISTS public.v_user_readiness_30d;

CREATE VIEW public.v_user_readiness_30d
    WITH (security_invoker = on) AS
SELECT
    user_id,
    date,
    score,
    band,
    primary_source,
    hrv_delta_pct,
    sleep_hours,
    sleep_debt_min,
    rhr_trend_bpm,
    strain_prev,
    signals
FROM public.daily_readiness_history
WHERE date >= (CURRENT_DATE - INTERVAL '30 days')
ORDER BY user_id, date DESC;

COMMENT ON VIEW public.v_user_readiness_30d IS
'Last 30 days of unified readiness per user, feeding the HealthInsightsView
 readiness-history chart and the Dashboard Smart Welcome readiness slot.
 security_invoker = on (supabase-rules.mdc) so RLS applies to the caller.';

-- 5. Schema documentation ---------------------------------------------
COMMENT ON TABLE public.daily_readiness_history IS
'Wearable-agnostic unified Daily Readiness score (0-100 / red-yellow-green).
 Written by the iOS ReadinessService on sync and back-filled by the
 compute-readiness-insights edge function nightly. Score blend priority:
 WHOOP recovery > Oura readiness > Fitbit-derived > HealthKit-derived.
 Feeds auto-gen recovery-override (FITNESS_EXPERT_AGENT #23), adaptive
 goals, wearable quests, readiness-based challenges, and the
 Dashboard / HealthInsightsView readiness chart.';

COMMENT ON COLUMN public.daily_readiness_history.primary_source IS
'Wearable that supplied the winning signal for the blended score.
 ''none'' = no wearable connected yet a placeholder row was written
 (score=50) so downstream queries always find something.';

COMMENT ON COLUMN public.daily_readiness_history.signals IS
'JSONB array of free-form breakdown signals for UI drill-down. Each
 element is {kind, label, value, severity}. Not used for server
 aggregations — schema-less on purpose so new signals ship without
 migrations.';

COMMIT;

-- ─── Verification queries (safe to re-run) ─────────────────────────────
-- SELECT 1 FROM information_schema.tables
--  WHERE table_schema = 'public' AND table_name = 'daily_readiness_history';
-- SELECT 1 FROM pg_views
--  WHERE schemaname = 'public' AND viewname = 'v_user_readiness_30d';
-- SELECT 1 FROM pg_policies
--  WHERE schemaname = 'public' AND tablename = 'daily_readiness_history';
