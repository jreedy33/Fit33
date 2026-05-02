-- =============================================================================
-- Strava API Agreement compliance — `delete_my_strava_data` RPC
-- =============================================================================
-- Lands the iOS-side leg of the three hard violations the production-access
-- audit surfaced (see PRODUCT_ENGINEER_AGENT.md invariant 14r):
--
--   1. The 48-hour activity-deletion rule (Strava API Agreement §"Permitted
--      Use"): "deletions must be reflected in your Developer Application
--      expeditiously but in all cases, within 48 hours."
--   2. Athlete deauthorization (Strava API Agreement §"Privacy"): "if a
--      user revokes the authorization previously granted for your Developer
--      Applications to access to their Strava account, you must ensure that
--      all Personal Data pertaining to that user is deleted from your
--      Developer Applications and related networks, systems and servers."
--   3. The in-app Disconnect button must purge — not retain — the user's
--      imported Strava activities.
--
-- This migration ships the iOS path (#3). The webhook path (#1, #2) is
-- handled in `supabase/functions/strava-webhook/index.ts` via direct
-- DELETEs on `cardio_workouts` + `user_strava_tokens` using the function's
-- service-role client (RLS bypass is intentional — webhook callers have no
-- `auth.uid()` and Strava signs nothing).
--
-- Contract:
--   • RPC name: `public.delete_my_strava_data()`
--   • Args: none (IDOR-safe per Infra Security invariant 9 — `auth.uid()`
--     is the only user binding; never accepts `p_user_id`).
--   • Returns: INT — count of `cardio_workouts` rows removed (the
--     `user_strava_tokens` row, if any, is also deleted but is at most 1
--     and isn't reflected in the return value).
--   • Permissions: GRANT EXECUTE TO authenticated. anon / service_role
--     don't need this entrypoint — service_role hits the tables directly
--     and anon users have no Strava data to delete.
--   • Idempotent: re-running on a user with no Strava rows returns 0.
--
-- Why an RPC rather than two `DELETE` calls from the iOS client:
--   • A single transaction guarantees the activity rows + the tokens row
--     either both go or neither does (no partial-revoke window where
--     activities are gone but a stale token is still in keychain mirror).
--   • Server-side enforcement of the `auth.uid()` filter — clients can
--     only delete THEIR OWN rows, never another user's, regardless of
--     what the iOS code does.
--
-- Idempotent / safe to re-deploy. Wrapped in BEGIN; / COMMIT;.
-- =============================================================================

BEGIN;

-- Drop ALL prior overloads before CREATE OR REPLACE (Supabase invariant #38 —
-- the canonical pg_proc-loop pattern). No-args has historically been the
-- only signature, but the loop pattern is cheap insurance against future
-- drift.
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT n.nspname AS schema_name,
               p.proname  AS func_name,
               pg_get_function_identity_arguments(p.oid) AS args
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname = 'delete_my_strava_data'
    LOOP
        EXECUTE format(
            'DROP FUNCTION IF EXISTS %I.%I(%s) CASCADE',
            r.schema_name, r.func_name, r.args
        );
    END LOOP;
END
$$;

CREATE OR REPLACE FUNCTION public.delete_my_strava_data()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_caller_id      UUID := auth.uid();
    v_deleted_count  INT  := 0;
BEGIN
    -- Authentication — anonymous callers have nothing to delete.
    IF v_caller_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
    END IF;

    -- 1. Purge imported Strava activities. RLS would already pin to the
    --    caller (cardio_workouts_delete_own from migration 20260511), but
    --    `SECURITY DEFINER` bypasses RLS so we add an explicit `user_id`
    --    filter. Belt + suspenders on a row-deletion path.
    DELETE FROM public.cardio_workouts
    WHERE user_id = v_caller_id
      AND source  = 'strava';

    GET DIAGNOSTICS v_deleted_count = ROW_COUNT;

    -- 2. Purge tokens. The webhook function's `get_user_id_for_strava_athlete`
    --    lookup will return NULL for this user post-purge, so any in-flight
    --    Strava activity events for this athlete will short-circuit cleanly
    --    instead of re-importing rows we just deleted.
    DELETE FROM public.user_strava_tokens
    WHERE user_id = v_caller_id;

    RAISE NOTICE '[strava-compliance] Purged % Strava cardio_workouts + token row for user %',
        v_deleted_count, v_caller_id;

    RETURN v_deleted_count;
END;
$$;

REVOKE ALL ON FUNCTION public.delete_my_strava_data() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_my_strava_data() TO authenticated;

-- Audit guard: confirm exactly one definition exists (Supabase invariant 28).
DO $$
DECLARE
    v_count INT;
BEGIN
    SELECT COUNT(*) INTO v_count
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'delete_my_strava_data';

    IF v_count <> 1 THEN
        RAISE EXCEPTION
            'delete_my_strava_data overload audit failed: expected 1 def, found %',
            v_count;
    END IF;

    RAISE NOTICE '[strava-compliance] delete_my_strava_data overload audit OK (1 def)';
END;
$$;

COMMIT;
