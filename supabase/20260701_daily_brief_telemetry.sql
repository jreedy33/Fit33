-- ============================================================================
-- 20260701 — Daily Brief telemetry (impression + tap log)
--
-- Sister to the new client-side `DailyBriefEngine` shipping on
-- 2026-04-27. Replaces the welcome card's single-line subtitle with
-- a fused multi-source brief; we want to learn which (capacity_band
-- × debt × goal) compositions actually drive the user to take the
-- prescribed action so the templates table can iterate.
--
-- TABLE: daily_brief_impressions
--   One row per surfaced brief. Inserted by the iOS client whenever
--   `WelcomeBriefRow` first paints a non-cached brief on the
--   dashboard. Keyed by `(user_id, surfaced_at)` — same user opening
--   the dashboard twice within a few seconds produces a second
--   impression because the brief's underlying state may have shifted
--   between the two paints (quest completion, fresh sync, etc.).
--
-- TABLE: daily_brief_taps
--   One row per tap. FK to `daily_brief_impressions(id)`. The client
--   stamps `completed_action_at` if/when the routed CTA was actually
--   followed through (workout started + completed, water logged,
--   meal saved, challenge opened) within 30 minutes of the tap. Lets
--   us compute "tap → completion" funnels per template family.
--
-- RLS: every read/write scoped to `auth.uid()`. service_role retains
-- full access for nightly aggregation jobs.
--
-- This is metrics-only; nothing in the app's hot path depends on the
-- table. The client's `BriefTelemetryUploader` falls back to silent
-- no-op when offline (Data invariant 26) so a stale auth session
-- never surfaces.
--
-- Idempotent. Re-running the migration is a no-op on existing
-- deployments.
-- ============================================================================

BEGIN;

-- ─── Impressions ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.daily_brief_impressions (
    id              UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID         NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    -- Composition trace — what the engine fused into THIS brief.
    capacity_band   TEXT         NOT NULL CHECK (capacity_band IN ('green','yellow','red','unknown')),
    capacity_source TEXT         NOT NULL,    -- "WHOOP" / "Oura" / "Fitbit" / "Apple Health" / "No wearable"
    debt_kind       TEXT         NOT NULL,    -- e.g. "muscleGroup" / "proteinDeficit" / "noWorkoutYet" / "allClear"
    goal_family     TEXT         NOT NULL,    -- buildMuscle / loseFat / endurance / generalFitness
    has_booster     BOOLEAN      NOT NULL DEFAULT FALSE,
    cta_code        TEXT         NOT NULL,    -- "auto" / "recovery" / "meal" / "water" / "challenge" / "readiness" / "weight" / "none"
    -- Free-form trace string the engine produced, for debugging stalls.
    source_trace    TEXT,
    surfaced_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    -- Client tz so we can window per local-day in analytics without
    -- having to look up `user_profiles.timezone` every query.
    client_timezone TEXT
);

CREATE INDEX IF NOT EXISTS idx_daily_brief_impressions_user_date
    ON public.daily_brief_impressions (user_id, surfaced_at DESC);

CREATE INDEX IF NOT EXISTS idx_daily_brief_impressions_template
    ON public.daily_brief_impressions (capacity_band, debt_kind, goal_family);

-- ─── Taps ───────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.daily_brief_taps (
    id                    UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    impression_id         UUID         NOT NULL REFERENCES public.daily_brief_impressions(id) ON DELETE CASCADE,
    user_id               UUID         NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    tapped_at             TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    -- Stamped by the client when the action was actually completed
    -- (workout finished / meal logged / challenge opened) within
    -- 30 minutes of the tap. Null = tapped but didn't follow through.
    completed_action_at   TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_daily_brief_taps_user_date
    ON public.daily_brief_taps (user_id, tapped_at DESC);

CREATE INDEX IF NOT EXISTS idx_daily_brief_taps_impression
    ON public.daily_brief_taps (impression_id);

-- ─── RLS ────────────────────────────────────────────────────────────────────
ALTER TABLE public.daily_brief_impressions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.daily_brief_taps        ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "daily_brief_impressions_self_select" ON public.daily_brief_impressions;
CREATE POLICY "daily_brief_impressions_self_select"
    ON public.daily_brief_impressions
    FOR SELECT
    USING (user_id = auth.uid());

DROP POLICY IF EXISTS "daily_brief_impressions_self_insert" ON public.daily_brief_impressions;
CREATE POLICY "daily_brief_impressions_self_insert"
    ON public.daily_brief_impressions
    FOR INSERT
    WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "daily_brief_taps_self_select" ON public.daily_brief_taps;
CREATE POLICY "daily_brief_taps_self_select"
    ON public.daily_brief_taps
    FOR SELECT
    USING (user_id = auth.uid());

DROP POLICY IF EXISTS "daily_brief_taps_self_insert" ON public.daily_brief_taps;
CREATE POLICY "daily_brief_taps_self_insert"
    ON public.daily_brief_taps
    FOR INSERT
    WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "daily_brief_taps_self_update" ON public.daily_brief_taps;
CREATE POLICY "daily_brief_taps_self_update"
    ON public.daily_brief_taps
    FOR UPDATE
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());

-- service_role bypass is granted by default via Postgres role
-- inheritance — nightly aggregation jobs read the full table.

COMMIT;

-- ─── Verification ───────────────────────────────────────────────────────────
-- Spot-check one inserted row after the iOS client lands the first
-- brief in TestFlight:
--
-- SELECT capacity_band, debt_kind, goal_family, cta_code, surfaced_at
--   FROM daily_brief_impressions
--  WHERE user_id = auth.uid()
--  ORDER BY surfaced_at DESC
--  LIMIT 5;
--
-- Tap-through funnel (CTAs that actually got completed within 30 min):
--
-- SELECT i.capacity_band, i.debt_kind, i.cta_code,
--        COUNT(*) FILTER (WHERE t.completed_action_at IS NOT NULL) AS completed,
--        COUNT(t.id) AS taps,
--        COUNT(*) FILTER (WHERE t.id IS NULL) AS impressions_only
--   FROM daily_brief_impressions i
--   LEFT JOIN daily_brief_taps t ON t.impression_id = i.id
--  WHERE i.surfaced_at > NOW() - INTERVAL '14 days'
--  GROUP BY 1,2,3
--  ORDER BY taps DESC;
