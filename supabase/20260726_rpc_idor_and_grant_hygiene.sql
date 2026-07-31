-- ============================================================================
-- Security hygiene: remaining IDOR guards + grant/RLS cleanup
-- (2026-07-26 production-readiness audit — MASTER_TODO PR-3 + PR-31)
-- ============================================================================
-- 1. get_league_history(p_user_id)  — SECURITY DEFINER, callable by any
--    authenticated user, returned ANY user's league history. Add the
--    standard IDOR guard (Swift only ever calls it with the caller's own id
--    — WeeklyLeagueService.swift:1057 — so this is behavior-preserving).
-- 2. get_quest_history(p_user_id, p_days) — same class of hole; guarded the
--    same way (currently no client callers, guarded for defense in depth).
-- 3. test_account_deletion(user_id_to_check) — leaks per-user friendship /
--    workout counts to any authenticated caller. Revoked from authenticated;
--    service_role (admin tooling) keeps access.
-- 4. calc_league_zone_count / interpolate_template — pure helpers with no
--    client callers; EXECUTE revoked from authenticated (attack-surface
--    hygiene).
-- 5. challenge_award_tiers — reference/config table with RLS disabled and
--    SELECT granted to authenticated (scoring config was readable /
--    gameable). RLS enabled, client SELECT revoked; SECURITY DEFINER RPCs
--    and the service-role CMS are unaffected.
-- ============================================================================

BEGIN;

-- ────────────────────────────────────────────────────────────────────────────
-- 1. get_league_history — IDOR guard
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION get_league_history(p_user_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER STABLE
SET search_path = public
AS $$
BEGIN
    -- IDOR guard: real users may only read their own history.
    -- service_role / pg_cron contexts (auth.uid() IS NULL) unrestricted.
    IF auth.uid() IS NOT NULL AND p_user_id <> auth.uid() THEN
        RAISE EXCEPTION 'get_league_history: caller % may not read history for %',
            auth.uid(), p_user_id
            USING ERRCODE = '42501';
    END IF;

    RETURN COALESCE((
        SELECT json_agg(json_build_object(
            'week_start', week_start,
            'tier_name', tier_name,
            'tier_rank', tier_rank,
            'final_rank', final_rank,
            'final_points', final_points,
            'group_size', group_size,
            'was_promoted', was_promoted,
            'was_relegated', was_relegated
        ) ORDER BY week_start DESC)
        FROM league_history
        WHERE user_id = p_user_id
    ), '[]'::json);
END;
$$;

REVOKE ALL ON FUNCTION get_league_history(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_league_history(UUID) TO authenticated, service_role;

-- ────────────────────────────────────────────────────────────────────────────
-- 2. get_quest_history — close the IDOR by revoking client EXECUTE.
--    (Original DEFINER body in daily_quests_migration.sql takes p_user_id
--    with no guard. No client callers exist today — grep of Fit33/ on
--    2026-07-26 found none — so revoking is behavior-preserving. If a client
--    surface ever needs quest history, re-grant WITH an in-body auth.uid()
--    guard.)
-- ────────────────────────────────────────────────────────────────────────────
REVOKE EXECUTE ON FUNCTION get_quest_history(TEXT, INT) FROM authenticated;
REVOKE ALL ON FUNCTION get_quest_history(TEXT, INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_quest_history(TEXT, INT) TO service_role;

-- ────────────────────────────────────────────────────────────────────────────
-- 3. test_account_deletion — admin/service tooling only
-- ────────────────────────────────────────────────────────────────────────────
REVOKE EXECUTE ON FUNCTION test_account_deletion(UUID) FROM authenticated;
REVOKE ALL ON FUNCTION test_account_deletion(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION test_account_deletion(UUID) TO service_role;

-- ────────────────────────────────────────────────────────────────────────────
-- 4. Dead-surface helper revokes (no client callers as of 2026-07-26)
-- ────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
    BEGIN
        REVOKE EXECUTE ON FUNCTION calc_league_zone_count(INTEGER, NUMERIC) FROM authenticated;
    EXCEPTION WHEN undefined_function THEN
        RAISE NOTICE 'calc_league_zone_count not present — skipping revoke';
    END;
    BEGIN
        REVOKE EXECUTE ON FUNCTION interpolate_template(TEXT, JSONB) FROM authenticated;
    EXCEPTION WHEN undefined_function THEN
        RAISE NOTICE 'interpolate_template not present — skipping revoke';
    END;
END $$;

-- ────────────────────────────────────────────────────────────────────────────
-- 5. challenge_award_tiers — enable RLS, revoke client SELECT
-- ────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'challenge_award_tiers') THEN
        ALTER TABLE public.challenge_award_tiers ENABLE ROW LEVEL SECURITY;
        REVOKE SELECT ON public.challenge_award_tiers FROM authenticated;
        REVOKE ALL ON public.challenge_award_tiers FROM anon;
        COMMENT ON TABLE public.challenge_award_tiers IS
            'Award scoring config. RLS enabled with no client policies (2026-07-26): '
            'reads happen inside SECURITY DEFINER RPCs and the service-role CMS only. '
            'Do not re-grant client SELECT — scoring thresholds are gameable.';
        RAISE NOTICE '✅ challenge_award_tiers locked down';
    ELSE
        RAISE NOTICE 'challenge_award_tiers not present — skipping';
    END IF;
END $$;

-- ────────────────────────────────────────────────────────────────────────────
-- Trailing audit — fail loud if the league-history guard is missing
-- ────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
    v_def TEXT;
BEGIN
    SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'get_league_history';

    IF v_def IS NULL OR position('p_user_id <> auth.uid()' IN v_def) = 0 THEN
        RAISE EXCEPTION 'AUDIT FAIL: get_league_history is missing the IDOR guard';
    END IF;
    RAISE NOTICE '✅ get_league_history guard verified';
END $$;

-- PostgREST schema-cache reload (supabase-rules.mdc — mandatory after
-- CREATE OR REPLACE FUNCTION; fires only on successful commit).
NOTIFY pgrst, 'reload schema';

COMMIT;
