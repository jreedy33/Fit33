-- =============================================================================
-- 20260730_rls_league_point_source_caps.sql  (Migration #161)
--
-- HOTFIX — Enables Row Level Security on `league_point_source_caps`.
--
-- WHY
-- ---
-- The Supabase platform linter (2026-04-29) flagged `public.league_point_source_caps`
-- as CRITICAL because RLS was never enabled on it when the table was created
-- in `20260717_league_sprint3_caps_peak_day.sql` (#148). Tables in the public
-- schema are exposed to PostgREST — without RLS, the `anon` and `authenticated`
-- REST roles can SELECT every row directly. This violates the universal
-- supabase-rules.mdc invariant: "RLS is MANDATORY: Every new table MUST have
-- ALTER TABLE ... ENABLE ROW LEVEL SECURITY."
--
-- WHY THIS WON'T BREAK ANYTHING
-- -----------------------------
-- The only reader of this table inside the codebase is the
-- `add_league_points(UUID, INTEGER, TEXT, TEXT)` SECURITY DEFINER RPC
-- (line 180 of #148). SECURITY DEFINER functions execute as the function
-- owner (`postgres` for migration-created functions), and the `postgres`
-- role has BYPASSRLS by default in Supabase — so enabling RLS on the table
-- does not change behavior inside the RPC at all. No client-side code path
-- (Swift, edge functions, admin CMS) reads this table directly today, so
-- the linter warning is the only observable effect — and that goes green
-- after this migration.
--
-- POLICY CHOICE
-- -------------
-- The cap policy is non-sensitive global configuration data (the same caps
-- ship in the iOS `LeaguePointSource` enum). We add a single permissive
-- SELECT policy for `authenticated` so the column can be surfaced in the
-- app UI later (e.g. "5 kudos/day max" badge). NO INSERT / UPDATE / DELETE
-- policies — cap edits go through migrations only, exactly per the table's
-- existing comment ("Edit cap values via new migrations — never UPDATE rows
-- directly in production."). `service_role` keeps full access through its
-- BYPASSRLS attribute. `anon` gets nothing.
--
-- IDEMPOTENT
-- ----------
-- `ALTER TABLE ... ENABLE ROW LEVEL SECURITY` is a no-op when already
-- enabled. `DROP POLICY IF EXISTS` precedes `CREATE POLICY`. Re-runnable.
-- =============================================================================

BEGIN;

-- 1. Enable RLS. No-op if already on.
ALTER TABLE public.league_point_source_caps ENABLE ROW LEVEL SECURITY;

-- 2. Read-only access for any authenticated user. Cap policy is the same
--    data shipped in the Swift `LeaguePointSource` enum — exposing it to
--    the client is harmless and lets future UI render "5/day" hints.
DROP POLICY IF EXISTS "lpsc_select_authenticated" ON public.league_point_source_caps;
CREATE POLICY "lpsc_select_authenticated" ON public.league_point_source_caps
    FOR SELECT
    TO authenticated
    USING (TRUE);

-- 3. NO write policies. Inserts / updates / deletes are migration-only.
--    SECURITY DEFINER RPCs owned by `postgres` (BYPASSRLS) and the
--    `service_role` (BYPASSRLS) are unaffected.

-- 4. Fail-loud audit — confirms RLS landed and the RPC reader path still works.
DO $$
DECLARE
    v_rls_enabled BOOLEAN;
    v_policy_count INTEGER;
    v_cap_count INTEGER;
BEGIN
    SELECT relrowsecurity INTO v_rls_enabled
      FROM pg_class
     WHERE oid = 'public.league_point_source_caps'::regclass;

    IF NOT COALESCE(v_rls_enabled, FALSE) THEN
        RAISE EXCEPTION 'RLS audit failed: league_point_source_caps still has RLS disabled';
    END IF;

    SELECT COUNT(*) INTO v_policy_count
      FROM pg_policies
     WHERE schemaname = 'public'
       AND tablename = 'league_point_source_caps'
       AND policyname = 'lpsc_select_authenticated';

    IF v_policy_count <> 1 THEN
        RAISE EXCEPTION 'RLS audit failed: expected 1 lpsc_select_authenticated policy, got %', v_policy_count;
    END IF;

    -- Sanity check the seeded policy data is still intact (the RPC depends
    -- on this — empty table = no caps enforced, same as pre-RLS).
    SELECT COUNT(*) INTO v_cap_count FROM public.league_point_source_caps;
    IF v_cap_count = 0 THEN
        RAISE EXCEPTION 'RLS audit failed: league_point_source_caps is empty — cap enforcement would silently no-op';
    END IF;

    RAISE NOTICE '✅ Migration #161: RLS enabled on league_point_source_caps (% rows, 1 SELECT policy).', v_cap_count;
END $$;

COMMIT;
