-- ============================================================================
-- group_challenge_members — Invariant Hardening (Sprint 2, 2026-04-18)
-- Q2-15 closure.
--
-- CONTEXT:
--   * Table is LEGACY. No Swift client code queries it (verified 2026-04-18).
--   * The live app uses `challenge_participants` for all group-challenge
--     membership logic.
--   * 20260324_security_fixes.sql re-enabled RLS with "user_id = auth.uid()"
--     policies for SELECT/INSERT/UPDATE/DELETE, which technically allows a
--     client to self-insert into a table that should be write-isolated.
--
-- INVARIANT (enforce at grant layer as defense in depth):
--   * No direct client-side INSERT / UPDATE / DELETE on group_challenge_members.
--   * Any future server-side mutation must go through a SECURITY DEFINER RPC
--     that explicitly gates on `auth.uid()`.
--   * SELECT remains policy-gated (users can read their own rows only) in case
--     any admin / debug view ever queries the table.
--
-- This migration:
--   1. REVOKEs INSERT / UPDATE / DELETE from `authenticated` so the existing
--      RLS policies become moot for writes (grant layer denies first).
--   2. REVOKEs ALL from `anon` (belt-and-suspenders — anon has no business
--      touching this table).
--   3. Leaves the `service_role` bypass intact for the cascade-delete trigger
--      and any future admin tooling.
--   4. Adds COMMENT ON TABLE recording the invariant so future engineers can
--      grep for the rule and see the reason.
-- ============================================================================

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = 'group_challenge_members'
    ) THEN
        RAISE NOTICE 'group_challenge_members does not exist in this environment — skipping invariant hardening';
        RETURN;
    END IF;

    -- Confirm RLS is on. If it was ever toggled off in an emergency, flip it back.
    EXECUTE 'ALTER TABLE public.group_challenge_members ENABLE ROW LEVEL SECURITY';

    -- Defense in depth: deny direct writes at the grant layer.
    REVOKE INSERT, UPDATE, DELETE ON public.group_challenge_members FROM authenticated;
    REVOKE ALL ON public.group_challenge_members FROM anon;

    -- Read access for the user's own row stays via the existing RLS policy.
    GRANT SELECT ON public.group_challenge_members TO authenticated;

    COMMENT ON TABLE public.group_challenge_members IS
      'LEGACY. Live app uses challenge_participants. Sprint 2 invariant: '
      'direct INSERT/UPDATE/DELETE by `authenticated` is REVOKED. Any future '
      'mutation must go through a SECURITY DEFINER RPC that gates on auth.uid(). '
      'service_role still has full access for cascade-delete triggers. See '
      'INFRA_SECURITY_AGENT.md.';
END
$$;
