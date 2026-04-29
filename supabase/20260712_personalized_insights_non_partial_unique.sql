-- 20260712_personalized_insights_non_partial_unique.sql
-- Hotfix — drains bug-intel cluster `4922971b` / `8fb2f8b3`:
-- "there is no unique or exclusion constraint matching the ON CONFLICT
--  specification" on `user_personalized_insights`.
--
-- ROOT CAUSE
-- ----------
-- `20260507_personalized_insights_wearable.sql` introduced a PARTIAL
-- unique index:
--
--     CREATE UNIQUE INDEX idx_personalized_insights_user_key
--         ON public.user_personalized_insights (user_id, insight_key)
--         WHERE insight_key IS NOT NULL;
--
-- Three call sites upsert with `onConflict: "user_id,insight_key"`:
--   1. `Fit33/PersonalizedInsightsService.swift` (on-device generator)
--   2. `supabase/functions/compute-readiness-insights/index.ts`
--   3. `supabase/functions/compute-strava-insights/index.ts`
--
-- PostgREST's `onConflict` parameter does NOT support partial indexes.
-- It generates `ON CONFLICT (user_id, insight_key)` with NO `WHERE`
-- predicate, so PostgreSQL can't match a partial index that has one.
-- The upsert errors out (PG 42P10) every time. Same shape as the
-- already-fixed `cardio_workouts` constraint
-- (`supabase/fix_cardio_workouts_constraint.sql`).
--
-- FIX
-- ---
-- Replace the partial index with a NON-partial one that PostgREST can
-- match. PostgreSQL's default `NULLS DISTINCT` semantics on unique
-- indexes mean rows where `insight_key IS NULL` (legacy on-device
-- insights) still won't conflict with each other — multiple
-- (user_id, NULL) rows coexist exactly as they did under the partial
-- index. The only behavior change is that PostgREST upserts now
-- succeed.
--
-- Defensive dedup: legacy data should already satisfy the constraint
-- (the partial index enforced uniqueness on `insight_key IS NOT NULL`),
-- but if any backfill or manual write slipped past it we keep the
-- newest row per (user_id, insight_key) pair before creating the new
-- index. Identical pattern to the cardio_workouts fix.
--
-- INVARIANTS
-- ----------
--   * Idempotent — wrapped in BEGIN/COMMIT, all DDL is `IF EXISTS` /
--     `IF NOT EXISTS`. Safe to re-run.
--   * No call-site changes required — the three upserts already pass
--     `onConflict: "user_id,insight_key"`.
--   * `v_user_wearable_insights` view is unaffected (it doesn't touch
--     the index, only the columns).

BEGIN;

-- 1. Drop the legacy PARTIAL index. PostgREST can't use it for
--    `onConflict (user_id, insight_key)`.
DROP INDEX IF EXISTS public.idx_personalized_insights_user_key;

-- 2. Defensive dedup. Keep the newest row (greatest `id`) per
--    (user_id, insight_key) when both are non-null. Rows where
--    `insight_key IS NULL` (legacy on-device insights) are NOT
--    deduped — they're append-only by design and remain distinct
--    under NULLS DISTINCT semantics.
WITH ranked AS (
    SELECT id,
           ROW_NUMBER() OVER (
               PARTITION BY user_id, insight_key
               ORDER BY id DESC
           ) AS rn
      FROM public.user_personalized_insights
     WHERE insight_key IS NOT NULL
)
DELETE FROM public.user_personalized_insights
 WHERE id IN (SELECT id FROM ranked WHERE rn > 1);

-- 3. Create the non-partial unique index. PostgREST's
--    `onConflict (user_id, insight_key)` will match this directly.
--    NULLS DISTINCT (PG default) means legacy rows with
--    `insight_key IS NULL` continue to coexist for the same user.
CREATE UNIQUE INDEX IF NOT EXISTS idx_personalized_insights_user_key
    ON public.user_personalized_insights (user_id, insight_key);

-- 4. Audit — surface the result. Fails loud if the new index is
--    missing or somehow still partial (predicate present means
--    PostgREST can't use it).
DO $$
DECLARE
    v_predicate TEXT;
BEGIN
    SELECT pg_get_expr(indpred, indrelid)
      INTO v_predicate
      FROM pg_index
     WHERE indexrelid = 'public.idx_personalized_insights_user_key'::regclass;

    IF v_predicate IS NOT NULL THEN
        RAISE EXCEPTION
            'idx_personalized_insights_user_key is still partial (predicate: %) — PostgREST upserts will fail',
            v_predicate;
    END IF;

    RAISE NOTICE
        '✅ user_personalized_insights: non-partial unique index in place — onConflict "user_id,insight_key" will now match';
END $$;

COMMIT;

-- ─── Verification queries (safe to re-run) ─────────────────────────────
-- -- Confirm the index is non-partial:
-- SELECT indexname, indexdef
--   FROM pg_indexes
--  WHERE schemaname = 'public'
--    AND tablename = 'user_personalized_insights'
--    AND indexname = 'idx_personalized_insights_user_key';
-- -- Expect: indexdef WITHOUT a "WHERE" clause.
--
-- -- Smoke-test the upsert path (run as an authenticated user):
-- INSERT INTO public.user_personalized_insights
--     (user_id, insight_key, insight_type, insight_category, title, message)
-- VALUES
--     (auth.uid(), 'insight_smoke_test', 'wearable', 'recovery', 'smoke', 'smoke')
-- ON CONFLICT (user_id, insight_key) DO UPDATE SET message = EXCLUDED.message;
-- DELETE FROM public.user_personalized_insights
--  WHERE user_id = auth.uid() AND insight_key = 'insight_smoke_test';
