-- ============================================================================
-- Migration #206 — Backend hygiene batch + shared rate-limit store
-- Date: 2026-07-30
-- Owner: Supabase Expert + Infra & Security
-- Resolves: MASTER_TODO PR-31 residuals (group_challenge_members SELECT,
--           interpolate_template re-revoke, push-flush rate limit backing
--           store) + #147 service_role grant gap (CMS Revenue / ASSN RPCs).
--
-- Deploy AFTER #203–#205. Idempotent; safe to re-run.
-- ============================================================================

BEGIN;

-- ────────────────────────────────────────────────────────────────────────────
-- 1. Shared rate-limit store (backs send-push-notification per-user flush
--    limit AND the Admin CMS login/admin-route limiters — replaces the
--    per-instance in-memory Maps that don't survive Vercel multi-instance).
--    Pattern precedent: 20260417_phone_verification_rate_limit.sql.
-- ────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.rate_limit_events (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    scope      TEXT        NOT NULL,   -- e.g. 'push_flush', 'cms_login', 'cms_admin_write'
    key        TEXT        NOT NULL,   -- user UUID, IP address, etc.
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_rate_limit_events_scope_key_time
    ON public.rate_limit_events (scope, key, created_at DESC);

-- Service-role-only table: RLS on with ZERO policies (same posture as
-- silent_push_wake_log). Clients must never read or write this.
ALTER TABLE public.rate_limit_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.rate_limit_events FROM authenticated;
REVOKE ALL ON public.rate_limit_events FROM anon;

COMMENT ON TABLE public.rate_limit_events IS
    'Shared sliding-window rate-limit store (migration #206). Written only '
    'via check_rate_limit() from service-role callers (edge functions + '
    'Admin CMS). RLS enabled with no client policies.';

-- Sliding-window check-and-record. Returns TRUE when the call is allowed
-- (and records it), FALSE when the caller is over the limit.
DROP FUNCTION IF EXISTS public.check_rate_limit(TEXT, TEXT, INT, INT);

CREATE OR REPLACE FUNCTION public.check_rate_limit(
    p_scope          TEXT,
    p_key            TEXT,
    p_max            INT,
    p_window_seconds INT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_count INT;
BEGIN
    IF p_scope IS NULL OR p_key IS NULL OR p_max IS NULL OR p_window_seconds IS NULL
       OR p_max <= 0 OR p_window_seconds <= 0 THEN
        RAISE EXCEPTION 'check_rate_limit: invalid arguments' USING ERRCODE = '22023';
    END IF;

    -- Opportunistic cleanup of expired events for this scope/key so the
    -- table stays small without needing a cron. WHERE clause satisfies the
    -- safe_updates guard.
    DELETE FROM public.rate_limit_events
    WHERE scope = p_scope
      AND key = p_key
      AND created_at < now() - make_interval(secs => p_window_seconds);

    SELECT COUNT(*) INTO v_count
    FROM public.rate_limit_events
    WHERE scope = p_scope
      AND key = p_key
      AND created_at >= now() - make_interval(secs => p_window_seconds);

    IF v_count >= p_max THEN
        RETURN FALSE;
    END IF;

    INSERT INTO public.rate_limit_events (scope, key) VALUES (p_scope, p_key);
    RETURN TRUE;
END;
$$;

-- Service-role-only execution. Never grant to authenticated — clients could
-- otherwise burn other users' budgets (key is caller-supplied).
REVOKE ALL ON FUNCTION public.check_rate_limit(TEXT, TEXT, INT, INT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.check_rate_limit(TEXT, TEXT, INT, INT) FROM authenticated;
REVOKE ALL ON FUNCTION public.check_rate_limit(TEXT, TEXT, INT, INT) FROM anon;
GRANT EXECUTE ON FUNCTION public.check_rate_limit(TEXT, TEXT, INT, INT) TO service_role;

COMMENT ON FUNCTION public.check_rate_limit(TEXT, TEXT, INT, INT) IS
    'Sliding-window rate limit: allowed? -> record + TRUE, else FALSE. '
    'Service-role only (edge functions + Admin CMS server routes).';

-- ────────────────────────────────────────────────────────────────────────────
-- 2. group_challenge_members — revoke residual SELECT (PR-31a).
--    Writes were revoked by 20260418 (Q2-15); no Swift code reads the table
--    directly (live surface is challenge_participants + RPCs). RLS stays on;
--    with the grant gone the client policies are inert defense-in-depth.
-- ────────────────────────────────────────────────────────────────────────────

DO $$
BEGIN
    IF EXISTS (SELECT FROM information_schema.tables
               WHERE table_schema = 'public' AND table_name = 'group_challenge_members') THEN
        -- REVOKE ALL (not just SELECT): first prod run (2026-07-31) tripped the
        -- trailing audit because the live DB still carried residual non-SELECT
        -- grants to authenticated — the 20260418 (Q2-15) write-revoke never
        -- fully landed. ALL matches the audit's zero-client-grants contract.
        REVOKE ALL ON public.group_challenge_members FROM authenticated;
        REVOKE ALL ON public.group_challenge_members FROM anon;
        COMMENT ON TABLE public.group_challenge_members IS
            'Legacy group-challenge membership. Fully client-revoked as of '
            'migration #206 (writes revoked 20260418 Q2-15, SELECT revoked '
            '2026-07-30). Server-side access only (RPCs + service role).';
    END IF;
END $$;

-- ────────────────────────────────────────────────────────────────────────────
-- 3. interpolate_template — re-revoke authenticated EXECUTE (PR-31c).
--    #171 (20260807_notification_template_variants.sql) originally granted
--    authenticated + service_role; the repo file is corrected, but databases
--    that ran the earlier revision AFTER #204's revoke would have regressed.
--    This re-revoke is idempotent and ordering-proof.
-- ────────────────────────────────────────────────────────────────────────────

DO $$
BEGIN
    IF EXISTS (SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
               WHERE n.nspname = 'public' AND p.proname = 'interpolate_template') THEN
        REVOKE ALL ON FUNCTION public.interpolate_template(TEXT, JSONB) FROM authenticated;
        REVOKE ALL ON FUNCTION public.interpolate_template(TEXT, JSONB) FROM anon;
        GRANT EXECUTE ON FUNCTION public.interpolate_template(TEXT, JSONB) TO service_role;
    END IF;
END $$;

-- ────────────────────────────────────────────────────────────────────────────
-- 4. #147 grant gap — monetization RPCs revoked PUBLIC but never granted
--    service_role. Function owner (postgres) keeps EXECUTE, but the CMS
--    (createAdminClient) and assn-webhook call these AS service_role via
--    PostgREST → permission denied once #147 is live. Grant explicitly.
-- ────────────────────────────────────────────────────────────────────────────

DO $$
DECLARE
    v_sig TEXT;
BEGIN
    FOREACH v_sig IN ARRAY ARRAY[
        'public.record_iap_event(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, JSONB, JSONB, JSONB, BOOLEAN)',
        'public.grant_premium_to_user(UUID, TEXT, TIMESTAMPTZ, UUID, TEXT)',
        'public.revoke_premium_from_user(UUID, TEXT, UUID, TEXT)',
        'public.extend_trial(UUID, INT, TEXT, UUID, TEXT)',
        'public.mark_refund_acknowledged(UUID, TEXT, TEXT, UUID, TEXT)',
        'public.get_revenue_overview(INT)',
        'public.compute_revenue_rollup()'
    ]
    LOOP
        BEGIN
            EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', v_sig);
        EXCEPTION WHEN undefined_function THEN
            RAISE NOTICE 'check: % not deployed yet (deploy #147 first) — skipping grant', v_sig;
        END;
    END LOOP;
END $$;

-- ────────────────────────────────────────────────────────────────────────────
-- 5. Trailing audit — fail loud if the hygiene state didn't take.
-- ────────────────────────────────────────────────────────────────────────────

DO $$
BEGIN
    -- rate_limit_events must be RLS-on with no client grants
    IF NOT EXISTS (SELECT FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                   WHERE n.nspname = 'public' AND c.relname = 'rate_limit_events'
                     AND c.relrowsecurity) THEN
        RAISE EXCEPTION 'AUDIT FAIL: rate_limit_events missing or RLS disabled';
    END IF;

    IF EXISTS (SELECT FROM information_schema.role_table_grants
               WHERE table_schema = 'public' AND table_name = 'rate_limit_events'
                 AND grantee IN ('authenticated', 'anon')) THEN
        RAISE EXCEPTION 'AUDIT FAIL: rate_limit_events has client grants';
    END IF;

    -- group_challenge_members must have no client SELECT grant
    IF EXISTS (SELECT FROM information_schema.role_table_grants
               WHERE table_schema = 'public' AND table_name = 'group_challenge_members'
                 AND grantee IN ('authenticated', 'anon')) THEN
        RAISE EXCEPTION 'AUDIT FAIL: group_challenge_members still has client grants';
    END IF;

    RAISE NOTICE '✅ migration #206 hygiene state verified';
END $$;

-- PostgREST schema-cache reload (supabase-rules.mdc — mandatory after
-- CREATE OR REPLACE FUNCTION; fires only on successful commit).
NOTIFY pgrst, 'reload schema';

COMMIT;
