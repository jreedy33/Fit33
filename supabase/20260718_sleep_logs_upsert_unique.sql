-- 20260718_sleep_logs_upsert_unique.sql
-- Hotfix — drains bug-intel clusters `9e02b91e` (HIGH, 36 occ) +
-- `b38bcdf9` (MEDIUM, 15 occ): pg:42P10 "there is no unique or exclusion
-- constraint matching the ON CONFLICT specification" on sleep_logs.
--
-- ROOT CAUSE
-- ----------
-- `Fit33/HealthDataService.swift::saveSleepFromHealthKit` upserts via:
--
--     .upsert(insert, onConflict: "user_id,date_of_sleep,source")
--
-- but the canonical `sleep_logs` table only has a (user_id) FK index +
-- the dashboard-applied RLS from 20260511_health_rls_audit.sql. There
-- is no unique index on (user_id, date_of_sleep, source), so PostgREST's
-- generated `INSERT … ON CONFLICT (user_id, date_of_sleep, source)` has
-- nothing to match and Postgres rejects with 42P10 on every HealthKit
-- sync — silently corrupting the user's sleep history. WHOOP and Oura
-- sync paths target the same table with their own `source` discriminator
-- and would hit the same wall once they're routed through upsert.
--
-- FIX
-- ---
-- 1. Defensive dedup of any pre-existing duplicate (user_id, date_of_sleep,
--    source) rows — keep the newest. Without this step the new index
--    creation would fail on existing dupes.
-- 2. Create a NON-partial unique index on (user_id, date_of_sleep, source)
--    so PostgREST `onConflict` matches exactly. NULLS DISTINCT (PG default)
--    keeps legacy rows where any column is NULL coexisting — no behavior
--    change for old data.
-- 3. Backfill `source = 'manual'` for any null-source rows so the upsert
--    contract matches schema-side. Future writes always pass source.
-- 4. Audit block fails loud if the index is somehow still partial
--    (predicate present means PostgREST can't use it).
--
-- INVARIANTS
-- ----------
--   * Idempotent — wrapped in BEGIN/COMMIT, all DDL is `IF NOT EXISTS` /
--     `IF EXISTS`. Safe to re-run.
--   * No call-site changes required — the upsert at HealthDataService.swift:1292
--     already passes `onConflict: "user_id,date_of_sleep,source"`.
--   * RLS unchanged (already audited by 20260511_health_rls_audit.sql).
--   * Mirrors the canonical recipe from
--     20260712_personalized_insights_non_partial_unique.sql (same root cause).
-- Resolves: 9e02b91ecc1f52efd70af7150a80584d, b38bcdf9b3b02089918d5beb1bd618fa

BEGIN;

DO $$
BEGIN
    IF to_regclass('public.sleep_logs') IS NULL THEN
        RAISE NOTICE '[20260718] sleep_logs not present in this env — skipping.';
        RETURN;
    END IF;

    -- 1. Backfill any rows where `source` is NULL so the partial-index
    --    edge case (NULL source) is impossible going forward.
    EXECUTE $sql$
        UPDATE public.sleep_logs
           SET source = 'manual'
         WHERE source IS NULL
    $sql$;

    -- 2. Defensive dedup — keep the newest row per (user_id, date_of_sleep,
    --    source). `created_at DESC, id DESC` for stable ordering.
    EXECUTE $sql$
        WITH ranked AS (
            SELECT id,
                   ROW_NUMBER() OVER (
                       PARTITION BY user_id, date_of_sleep, source
                       ORDER BY COALESCE(created_at, to_timestamp(0)) DESC,
                                id DESC
                   ) AS rn
              FROM public.sleep_logs
             WHERE user_id IS NOT NULL
               AND date_of_sleep IS NOT NULL
               AND source IS NOT NULL
        )
        DELETE FROM public.sleep_logs
         WHERE id IN (SELECT id FROM ranked WHERE rn > 1)
    $sql$;

    -- 3. Drop any pre-existing partial / mismatched indexes on the same
    --    columns so we can re-create the canonical non-partial one.
    EXECUTE 'DROP INDEX IF EXISTS public.idx_sleep_logs_user_date_source';

    -- 4. Create the non-partial unique index. PostgREST's
    --    onConflict (user_id, date_of_sleep, source) will match this directly.
    EXECUTE $sql$
        CREATE UNIQUE INDEX IF NOT EXISTS idx_sleep_logs_user_date_source
            ON public.sleep_logs (user_id, date_of_sleep, source)
    $sql$;

    -- 5. Convenience read index for the v_sleep_recovery_correlation view
    --    and dashboard sleep timeline queries (user_id + date range scan).
    EXECUTE $sql$
        CREATE INDEX IF NOT EXISTS idx_sleep_logs_user_date
            ON public.sleep_logs (user_id, date_of_sleep DESC)
    $sql$;

    RAISE NOTICE '[20260718] sleep_logs unique index created.';
END $$;

-- 6. Audit — surface the result. Fails loud if the new index is missing
--    or somehow still partial.
DO $$
DECLARE
    v_predicate TEXT;
    v_dupes INTEGER;
BEGIN
    IF to_regclass('public.sleep_logs') IS NULL THEN
        RAISE NOTICE '[20260718] sleep_logs not present — audit skipped.';
        RETURN;
    END IF;

    SELECT pg_get_expr(indpred, indrelid)
      INTO v_predicate
      FROM pg_index
     WHERE indexrelid = 'public.idx_sleep_logs_user_date_source'::regclass;

    IF v_predicate IS NOT NULL THEN
        RAISE EXCEPTION
            'idx_sleep_logs_user_date_source is still partial (predicate: %) — PostgREST upserts will fail',
            v_predicate;
    END IF;

    SELECT COUNT(*) INTO v_dupes
      FROM (
          SELECT user_id, date_of_sleep, source, COUNT(*) AS c
            FROM public.sleep_logs
           WHERE user_id IS NOT NULL
             AND date_of_sleep IS NOT NULL
             AND source IS NOT NULL
           GROUP BY 1, 2, 3
          HAVING COUNT(*) > 1
      ) AS dupes;

    IF v_dupes > 0 THEN
        RAISE EXCEPTION
            '[20260718] sleep_logs still has % duplicate (user_id, date_of_sleep, source) groups — dedup did not converge',
            v_dupes;
    END IF;

    RAISE NOTICE
        '✅ sleep_logs: non-partial unique index in place — onConflict "user_id,date_of_sleep,source" will now match';
END $$;

COMMIT;
