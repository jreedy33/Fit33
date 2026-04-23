-- 20260508_adaptive_goal_proposals.sql
-- Wearable Personalization Platform — Phase 3 (Adaptive Goals)
--
-- Stores weekly goal proposals computed by the nightly server job
-- (extension of `compute-readiness-insights` in Phase 2a or a
-- standalone `compute-adaptive-goals` function). The iOS client
-- surfaces these as a "tune this week's goals?" card on the
-- Dashboard; user acceptance writes the accepted values back to
-- `user_profiles` / `User` Core Data.
--
-- Never auto-applied (per plan) — the `applied_at` column is set
-- only when the user taps Accept in the UI. Server-side nightly
-- job only WRITES proposals; application is always a user action.
--
-- Schema:
--   metric TEXT — one of: 'calorie_goal', 'sleep_goal', 'step_goal',
--                         'weight_pace', 'protein_goal'
--   current_value NUMERIC — user's goal at the time we computed.
--   proposed_value NUMERIC — our recommended goal.
--   rationale TEXT — short copy for the UI ("You burned more than we
--                    estimated — bump your calorie target").
--   week_of DATE — start-of-week (Monday) the proposal applies to.
--   accepted BOOLEAN — did the user accept? (NULL = pending)
--   applied_at TIMESTAMPTZ — when the Accept tap landed.
--
-- Invariants:
--   * FK → user_profiles ON DELETE CASCADE (SUPABASE_AGENT §1).
--   * RLS: auth.uid() = user_id on every op.
--   * UNIQUE(user_id, metric, week_of) — one proposal per metric per
--     week; nightly reruns upsert.
--   * View `v_user_pending_goal_proposals` with `security_invoker = on`
--     returns only pending proposals for the current week, so
--     Dashboard doesn't need date math on the client.

BEGIN;

CREATE TABLE IF NOT EXISTS public.user_adaptive_goal_proposals (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
    metric TEXT NOT NULL CHECK (metric IN (
        'calorie_goal',
        'sleep_goal',
        'step_goal',
        'weight_pace',
        'protein_goal'
    )),
    current_value NUMERIC,
    proposed_value NUMERIC NOT NULL,
    rationale TEXT NOT NULL,
    week_of DATE NOT NULL,
    accepted BOOLEAN,
    applied_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, metric, week_of)
);

CREATE INDEX IF NOT EXISTS idx_adaptive_goal_user_week
    ON public.user_adaptive_goal_proposals (user_id, week_of DESC);

CREATE INDEX IF NOT EXISTS idx_adaptive_goal_pending
    ON public.user_adaptive_goal_proposals (user_id)
    WHERE accepted IS NULL;

ALTER TABLE public.user_adaptive_goal_proposals ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "agp_select_own" ON public.user_adaptive_goal_proposals;
CREATE POLICY "agp_select_own"
    ON public.user_adaptive_goal_proposals
    FOR SELECT
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "agp_insert_own" ON public.user_adaptive_goal_proposals;
CREATE POLICY "agp_insert_own"
    ON public.user_adaptive_goal_proposals
    FOR INSERT
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "agp_update_own" ON public.user_adaptive_goal_proposals;
CREATE POLICY "agp_update_own"
    ON public.user_adaptive_goal_proposals
    FOR UPDATE
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "agp_delete_own" ON public.user_adaptive_goal_proposals;
CREATE POLICY "agp_delete_own"
    ON public.user_adaptive_goal_proposals
    FOR DELETE
    USING (auth.uid() = user_id);

-- updated_at touch trigger ---------------------------------------------
CREATE OR REPLACE FUNCTION public.tg_adaptive_goal_touch_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tg_adaptive_goal_updated_at
    ON public.user_adaptive_goal_proposals;

CREATE TRIGGER tg_adaptive_goal_updated_at
    BEFORE UPDATE ON public.user_adaptive_goal_proposals
    FOR EACH ROW
    EXECUTE FUNCTION public.tg_adaptive_goal_touch_updated_at();

-- Dashboard-friendly view: pending proposals for the current week -----
DROP VIEW IF EXISTS public.v_user_pending_goal_proposals;
CREATE VIEW public.v_user_pending_goal_proposals
    WITH (security_invoker = on) AS
SELECT
    id,
    user_id,
    metric,
    current_value,
    proposed_value,
    rationale,
    week_of,
    created_at,
    updated_at
FROM public.user_adaptive_goal_proposals
WHERE
    accepted IS NULL
    AND week_of >= (date_trunc('week', CURRENT_DATE)::date)
ORDER BY user_id, created_at DESC;

COMMENT ON VIEW public.v_user_pending_goal_proposals IS
'Current-week pending adaptive goal proposals for the signed-in user.
 Feeds the Dashboard "tune your goals" nudge card. Auto-clears once
 the user accepts/declines (accepted column flips non-NULL).';

COMMIT;

-- ─── Verification ──────────────────────────────────────────────────────
-- SELECT 1 FROM information_schema.tables
--  WHERE table_schema = 'public' AND table_name = 'user_adaptive_goal_proposals';
-- SELECT 1 FROM pg_views WHERE schemaname = 'public'
--   AND viewname = 'v_user_pending_goal_proposals';
