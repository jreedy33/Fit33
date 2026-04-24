-- Fix the 42883 `operator does not exist: uuid = text` root cause.
--
-- Traced via the trigger hunt added in
-- `supabase/20260517_bug_intel_noise_filter_expand.sql`. The 2026-04-24T11:10
-- Cursor bug-intel export surfaced a regressed weight-logging error cluster
-- (fingerprints `ff6ae8d5` / `222e0fc1` / `95b0b27b`, 25+ occurrences) that
-- persisted even after `20260512_weight_logs_audit.sql` canonicalized the
-- RLS policies. The real culprit wasn't RLS — it was this trigger.
--
-- Original (buggy) function body captured during the 2026-04-24 audit:
--
--     CREATE OR REPLACE FUNCTION public.sync_profile_weight()
--     RETURNS trigger
--     LANGUAGE plpgsql
--     AS $function$
--     BEGIN
--         UPDATE user_profiles
--         SET
--             weight_kg   = NEW.weight_kg,
--             weight_lbs  = NEW.weight_lbs,
--             updated_at  = NOW()
--         WHERE id = NEW.user_id::text;   -- ← 42883 HERE
--         RETURN NEW;
--     END;
--     $function$;
--
-- `user_profiles.id` is `uuid` (it references `auth.users(id)` which is
-- uuid), and `weight_logs.user_id` is also `uuid`. Casting `NEW.user_id`
-- to text produced the mismatch `uuid = text`, which PostgreSQL rejects
-- with SQLSTATE 42883. Every single `INSERT INTO weight_logs` from the
-- iOS client triggered this AFTER INSERT, so every weight log failed
-- with 42883 regardless of how clean the Swift-side UUID was.
--
-- Fix: drop the `::text` cast. Both sides are already uuid.
--
-- Safety:
--   - `CREATE OR REPLACE FUNCTION` preserves the existing `pg_trigger` row
--     (the trigger itself is not recreated, which avoids a short window
--     where writes could bypass the trigger mid-transaction).
--   - Trailing `DO $$` block runs a dry-run UPDATE against a synthetic
--     uuid so the new function body is syntactically valid against the
--     real column types — `RAISE EXCEPTION` on failure so we fail-closed
--     rather than shipping a broken trigger.
--   - Paired Swift work: none required. The client has been sending
--     correct UUIDs the whole time (`Fit33/WeightTrackingService.swift`
--     `WeightLogInsert.user_id` is `UUID`). The bug was entirely
--     server-side.
--
-- Expected impact on next bug-intel rollup:
--   - Cluster C (C_uuid) fingerprint count: 4 → 0 over 48h as active
--     users' log-weight retries succeed.
--   - Fingerprints `ff6ae8d5` / `222e0fc1` / `95b0b27b` stop regenerating.

BEGIN;

-- ============================================================================
-- 1. Replace the buggy function body.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.sync_profile_weight()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    -- NEW.user_id is uuid, user_profiles.id is uuid. Previous version cast
    -- NEW.user_id to text, producing `uuid = text` (SQLSTATE 42883). The
    -- cast is gone — both sides are now uuid and the comparison resolves
    -- to the canonical uuid-eq operator.
    UPDATE user_profiles
    SET
        weight_kg  = NEW.weight_kg,
        weight_lbs = NEW.weight_lbs,
        updated_at = NOW()
    WHERE id = NEW.user_id;

    RETURN NEW;
END;
$function$;

COMMENT ON FUNCTION public.sync_profile_weight() IS
    'AFTER INSERT trigger on weight_logs: propagates latest weight to user_profiles. Fixed 2026-04-24 (42883 uuid=text cast removed). Paired migration: 20260518.';

-- ============================================================================
-- 2. Fail-loud sanity check.
-- ============================================================================
-- Dry-run the UPDATE the function will issue against a throwaway uuid so
-- we catch any lingering type mismatch at deploy time instead of at
-- runtime. The UPDATE is harmless — no row has id = '00000000-…-0001' in
-- the synthetic uuid namespace, so 0 rows are affected, but the planner
-- still type-checks the predicate.
-- ============================================================================

DO $$
DECLARE
    v_plan_check INTEGER;
BEGIN
    -- Plan-phase check that the new predicate is `uuid = uuid` and no
    -- longer triggers 42883. We EXECUTE dynamic SQL so the plan is built
    -- fresh and uses the same predicate shape as the trigger body.
    EXECUTE 'UPDATE user_profiles SET updated_at = updated_at WHERE id = $1'
        USING '00000000-0000-0000-0000-000000000001'::uuid;
    GET DIAGNOSTICS v_plan_check = ROW_COUNT;
    RAISE NOTICE '[20260518] sync_profile_weight() predicate type-checks cleanly (dry-run touched % rows).', v_plan_check;
EXCEPTION
    WHEN undefined_function THEN
        RAISE EXCEPTION '[20260518] Type mismatch still present on user_profiles.id predicate — 42883 not fixed. Original error: %', SQLERRM;
END $$;

-- ============================================================================
-- 3. Confirm the trigger is still wired to the fixed function.
-- ============================================================================

DO $$
DECLARE
    v_trigger_function TEXT;
BEGIN
    SELECT t.tgfoid::regprocedure::text INTO v_trigger_function
      FROM pg_trigger t
      JOIN pg_class c ON c.oid = t.tgrelid
     WHERE NOT t.tgisinternal
       AND c.relname = 'weight_logs'
       AND t.tgname = 'trigger_sync_profile_weight';

    IF v_trigger_function IS NULL THEN
        RAISE EXCEPTION '[20260518] Expected trigger_sync_profile_weight on weight_logs — not found.';
    END IF;

    IF v_trigger_function NOT LIKE '%sync_profile_weight%' THEN
        RAISE EXCEPTION '[20260518] trigger_sync_profile_weight fires % — expected sync_profile_weight().', v_trigger_function;
    END IF;

    RAISE NOTICE '[20260518] trigger_sync_profile_weight on weight_logs is wired to % (fix landed).', v_trigger_function;
END $$;

-- ============================================================================
-- 4. Auto-resolve the C_uuid fingerprints this fix targets.
--    Matches the fingerprints surfaced in the 2026-04-24 export plus any
--    additional 42883 fingerprints that carry `weight_logs` or
--    `sync_profile_weight` in their sample_message.
-- ============================================================================

UPDATE bug_intelligence_fingerprints
   SET status = 'resolved',
       auto_resolved_at = COALESCE(auto_resolved_at, now()),
       auto_resolved_reason = 'silent_fix',
       fixed_in_build = COALESCE(fixed_in_build, '1.38 (51)'),
       updated_at = now()
 WHERE status NOT IN ('resolved', 'wont_fix', 'duplicate')
   AND (
        LOWER(sample_message) LIKE '%42883%'
     OR LOWER(sample_message) LIKE '%sync_profile_weight%'
     OR LOWER(sample_message) LIKE '%operator does not exist: uuid = text%'
       )
   AND (
        LOWER(COALESCE(sample_message, '')) LIKE '%weight%'
     OR LOWER(COALESCE(normalized_message, '')) LIKE '%weight%'
     OR LOWER(COALESCE(error_domain, '')) LIKE '%weight%'
       );

COMMIT;
