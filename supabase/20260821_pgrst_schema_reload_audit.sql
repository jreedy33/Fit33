-- =============================================================================
-- Migration #188 — Defensive PostgREST schema-cache reload + post-deploy audit
-- =============================================================================
-- Date:    2026-08-21
-- Author:  Bug Intelligence (drains clusters from
--          `bug-intelligence-new-2026-05-02T14-44-02.md`).
--
-- WHY THIS EXISTS
-- ---------------
-- Migration #164 (`20260802_exercise_performance_id_match.sql`, deployed
-- 2026-04-29) added `exercise_performance_history.exercise_id UUID` and
-- `exercise_set_history.exercise_id UUID`, but did NOT broadcast a schema
-- reload to PostgREST. Until PostgREST's periodic background refresh
-- caught up (default = 10 min on Supabase Cloud), every iOS write that
-- referenced `exercise_id` came back as:
--
--   PostgrestError(code: "PGRST204",
--                  message: "Could not find the 'exercise_id' column of
--                  'exercise_set_history' in the schema cache.")
--
-- and the iOS catch block (`ExerciseHistoryService.swift::saveExerciseSets`,
-- `ActiveWorkoutView+Persistence.swift::cacheCompletedExercise`) surfaced
-- it as `AppLogger.error` — generating bug-intel fingerprints
-- `f5e63f1c…`, `c3edd3a3…`, `e7e58303…`, `91e7baa9…`, `0e92e6a9…`,
-- `2eb2f0d6…` (Cluster A in the 2026-05-02 rollup, 6 reports).
--
-- Same root cause for migration #168
-- (`20260801_notification_categories_and_caps.sql`, status: 🆕 Ready —
-- not yet deployed at report time): once that ships, the
-- `get_my_notification_preferences()` RPC will exist physically but
-- PostgREST's cache will return PGRST202 ("Could not find the function
-- public.get_my_notification_preferences without parameters in the
-- schema cache") for ~10 min — generating `Bug-intel Reports 10 + 22`.
--
-- WHAT THIS MIGRATION DOES
-- ------------------------
-- 1. Audits the on-prod schema state for the columns / functions that
--    have already shipped (ie. exercise_id columns from #164). RAISE
--    EXCEPTION if absent — fails loud rather than silently masking a
--    failed prior deploy.
-- 2. Issues `NOTIFY pgrst, 'reload schema';` so the API node's cache
--    invalidates immediately instead of waiting for the periodic refresh.
-- 3. Pure no-op for data — no DML, no DDL, no RLS changes. Safe to
--    re-run as many times as needed; idempotent by definition.
-- 4. Establishes the canonical recipe for "what to ship after every
--    schema-altering migration so iOS doesn't see PGRST20x for 10 min."
--    Going forward, any migration that ALTERs a column or
--    CREATEs/DROPs a function MUST end with a `NOTIFY pgrst,
--    'reload schema';` (new SUPABASE_AGENT invariant 30).
--
-- WHAT THIS MIGRATION DOES NOT DO
-- -------------------------------
--   * Does NOT modify any column, function, RPC return type, or RLS
--     policy. iOS sync paths see ZERO behavior change.
--   * Does NOT drop or recreate any RPC (so no overload-collapse risk
--     per Supabase invariant 28).
--   * Does NOT touch the in-progress Cardio Redesign Phase 1 schema
--     (#184 — #187). Independent fix, separate concern.
--
-- TESTING / VERIFICATION
-- ----------------------
--   * The trailing audit DO block prints NOTICE lines for every column
--     / function it inspects so the SQL Editor output makes the
--     post-state obvious.
--   * `psql -c "SELECT 1 FROM pg_notify('pgrst', 'reload schema')"`
--     produces the same effect — proven harmless in past hot-reload
--     runs (eg. mid-day Supabase rolling restarts).
--
-- RESOLVES
-- --------
-- Bug-intel fingerprints (Cluster A — schema-cache class):
--   f5e63f1c, c3edd3a3, e7e58303, 91e7baa9, 0e92e6a9, 2eb2f0d6
-- Defensively pre-empts (Cluster B — will fire on #168 deploy without it):
--   2c81c50f (get_my_notification_preferences PGRST202)
-- =============================================================================

BEGIN;

-- ── 1. Audit the columns added by migration #164 ─────────────────────────
--
-- Fail loud if either column is missing. If we get here and one of these
-- raises, it means migration #164 was NOT applied on prod (or was rolled
-- back) and the iOS code that depends on `exercise_id` will keep failing
-- regardless of whether the schema cache is fresh — needs operator
-- intervention before NOTIFY pgrst can help.

DO $audit$
DECLARE
    v_exists BOOLEAN;
BEGIN
    -- exercise_set_history.exercise_id (UUID, FK → exercises.id)
    SELECT EXISTS (
        SELECT 1
          FROM information_schema.columns
         WHERE table_schema = 'public'
           AND table_name   = 'exercise_set_history'
           AND column_name  = 'exercise_id'
    ) INTO v_exists;

    IF NOT v_exists THEN
        RAISE EXCEPTION
            '[#188] exercise_set_history.exercise_id is MISSING — migration #164 (20260802_exercise_performance_id_match.sql) was not applied. Re-run #164 before this migration can help.';
    END IF;
    RAISE NOTICE '[#188] ✅ exercise_set_history.exercise_id present';

    -- exercise_performance_history.exercise_id (UUID, FK → exercises.id)
    SELECT EXISTS (
        SELECT 1
          FROM information_schema.columns
         WHERE table_schema = 'public'
           AND table_name   = 'exercise_performance_history'
           AND column_name  = 'exercise_id'
    ) INTO v_exists;

    IF NOT v_exists THEN
        RAISE EXCEPTION
            '[#188] exercise_performance_history.exercise_id is MISSING — migration #164 was not applied. Re-run #164 before this migration can help.';
    END IF;
    RAISE NOTICE '[#188] ✅ exercise_performance_history.exercise_id present';
END
$audit$;

-- ── 2. Audit Cluster B's RPC surface (best-effort) ───────────────────────
--
-- If migration #168 (`20260801_notification_categories_and_caps.sql`) has
-- ALSO been deployed by this point, confirm the no-arg overload of
-- `get_my_notification_preferences()` is present so the schema reload
-- below makes it visible to PostgREST. If #168 has NOT shipped yet,
-- this is fine — the NOTIFY in step 3 still ensures that whenever #168
-- DOES land, the SQL Editor's automatic post-deploy reload will be
-- belt-and-suspenders'd.

DO $rpc_audit$
DECLARE
    v_exists BOOLEAN;
BEGIN
    SELECT EXISTS (
        SELECT 1
          FROM pg_proc p
          JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public'
           AND p.proname = 'get_my_notification_preferences'
           AND p.pronargs = 0
    ) INTO v_exists;

    IF v_exists THEN
        RAISE NOTICE '[#188] ✅ get_my_notification_preferences() (0-arg) present — schema reload below will surface it to PostgREST cache.';
    ELSE
        RAISE NOTICE '[#188] ℹ️  get_my_notification_preferences() (0-arg) not yet deployed — migration #168 still pending. The NOTIFY below remains useful for the columns inspected above.';
    END IF;
END
$rpc_audit$;

-- ── 3. Reload the PostgREST schema cache ────────────────────────────────
--
-- This is the entire point of the migration. PostgREST listens on the
-- `pgrst` channel and reloads its in-memory schema cache when it
-- receives any payload (the canonical payload string is
-- `'reload schema'`). The reload is online — no API downtime, no
-- connection drops. Effect on iOS clients: the very next request
-- that would have returned PGRST204 / PGRST202 succeeds.
--
-- Supabase Cloud's automatic post-deploy reload normally handles this,
-- but only when the migration file completes via the SQL Editor's
-- standard path. Several #164-class incidents have shown the auto-
-- reload sometimes lags by 5 — 12 minutes (likely tied to multi-region
-- failover propagation). Issuing it ourselves makes that lag impossible.

NOTIFY pgrst, 'reload schema';

-- ── 4. Final NOTICE so the SQL Editor output is unambiguous ─────────────

DO $$
BEGIN
    RAISE NOTICE '[#188] ✅ Migration #188 complete — PostgREST schema cache reload requested. iOS clients should stop seeing PGRST204 (exercise_set_history.exercise_id) immediately.';
END $$;

COMMIT;
