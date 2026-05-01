-- ============================================================================
-- 20260801 — food_items: Open Food Facts integration
-- ============================================================================
-- Adds the schema needed for the OFF expansion of the food search system
-- (paired with `supabase/functions/_shared/openFoodFacts.ts` and the new
-- `case "barcode"` action in `supabase/functions/usda-food-search/index.ts`).
--
-- Why these columns:
--   barcode       — UNIQUE lookup index for camera-scan flow. Indexed PARTIAL
--                   so USDA-only rows (the existing 99% of `food_items`) cost
--                   zero index space.
--   source        — 'usda' | 'off'. Drives the iOS attribution badge AND the
--                   ranker's data-type tier (`OFF` vs `Foundation` vs
--                   `Branded` — see `calculateFoodScore()` in the edge fn).
--                   ODbL license requires we attribute OFF data on render
--                   (`FoodDetailsView` shows "Data: Open Food Facts" footer
--                   when source = 'off').
--   image_url     — OFF product photo. USDA doesn't ship product images, so
--                   only OFF rows populate this. Helps users confirm "this is
--                   the bag I'm holding" on the scanner result screen.
--
-- Why fdc_id stays the upsert key (not a separate UNIQUE on barcode):
--   OFF products get a SYNTHETIC NEGATIVE fdcId derived from the numeric
--   barcode (`syntheticFdcIdForBarcode()`). USDA fdcIds are positive int32;
--   OFF synthetics are negative bigints — by construction collision-free.
--   This lets the existing `onConflict: "fdc_id"` upsert path in
--   `cacheUSDAFoods()` stay unchanged. The barcode UNIQUE INDEX is for the
--   READ path (`SELECT * FROM food_items WHERE barcode = $1`).
--
-- Why fdc_id MUST be widened to BIGINT — and the cascade that comes with it:
--   13-digit EAN max = 9_999_999_999_999. Negated = -9_999_999_999_999. INT4
--   max abs is ~2.1B — too small. BIGINT (INT8) max abs is ~9.2 * 10^18 — fits.
--   ALTER COLUMN TYPE on a column under a UNIQUE INDEX rebuilds the index;
--   acceptable cost on `food_items` (~10K rows in prod 2026-04-30).
--
--   CASCADE — anything that depends on the OLD type must be dropped FIRST,
--   then recreated AFTER the alter:
--   (a) `popular_foods_view` — uses `food_items.*` so the `fdc_id` column is
--       referenced. Postgres errors `cannot alter type of a column used by
--       a view or rule` on the ALTER unless we drop+recreate the view.
--       Original definition lives in `supabase/global_food_popularity.sql`.
--   (b) `get_global_food_popularity()` RPC — `RETURNS TABLE(fdc_id INTEGER, …)`.
--       Reads from `user_food_history.fdc_id`, not `food_items.fdc_id`, but
--       the RETURN signature still names INTEGER. Drop + recreate as BIGINT
--       so the PG executor doesn't fight the implicit cast on calls.
--   (c) `get_user_frequent_foods()` RPC — same story (RETURNS TABLE includes
--       `fdc_id INT`). Drop + recreate as BIGINT.
--   (d) `increment_food_log_count(fdc_id_param INTEGER)` RPC — iOS calls
--       this with the negated bigint when the user logs an OFF meal; the
--       INTEGER param will overflow on values like `-1234567890123`. Drop
--       all overloads (Supabase invariant 12) + recreate with BIGINT.
--   (e) `user_food_history.fdc_id` — iOS will write the synthetic negative
--       bigint to this column on meal-log of an OFF food. Widen to BIGINT
--       in the same pass so the second crash doesn't surface days later.
--       Defensive `IF EXISTS` because the column may already be BIGINT in
--       some envs that ran an earlier hotfix.
--
-- Idempotency: every block uses IF NOT EXISTS / DO NOTHING / safe DROP IF
-- EXISTS so re-running this migration on an already-deployed DB is a no-op
-- (Data invariant #20). If a partial run already widened `food_items.fdc_id`
-- before erroring on the view, the second run skips the type change and
-- still recreates the view + RPCs cleanly.
--
-- Reads: handled by edge function via service-role; no RLS policy changes
-- required (food_items already has read-for-authenticated, write-via-service).
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 0a. Snapshot + drop ALL views that depend on food_items / user_food_history
-- ----------------------------------------------------------------------------
-- The 2026-04-30 first deploy attempt failed twice: first on
-- `popular_foods_view`, then on `popular_foods_30d` (which only exists in
-- prod — was created directly in the SQL Editor, not source-controlled).
-- Hardcoding view names is whack-a-mole. This block discovers every view +
-- materialized view in `public` whose definition transitively references
-- `food_items` or `user_food_history`, snapshots its CREATE statement +
-- security_invoker setting into a TEMP table, then drops with CASCADE so
-- the ALTER COLUMN below can run. Section 6 restores them verbatim from
-- the snapshot AFTER the column type has been widened.
--
-- Why the snapshot is captured BEFORE we drop overloads / change types:
-- `pg_get_viewdef` returns the rewritten parsed query, which references
-- the source columns by NAME. After ALTER COLUMN, the recreated view picks
-- up the new BIGINT type automatically. If a view had pinned the old type
-- (e.g. `CAST(fdc_id AS INT4)`), `pg_get_viewdef` reproduces the cast
-- verbatim and the view rebuilds with the cast intact — still safe, since
-- the underlying value still fits int4 for USDA rows (positive < 2.1B); OFF
-- rows wouldn't reach a view that explicitly downcasts to int4 because
-- `WHERE fdc_id > 0` is the canonical OFF-exclusion guard (used by
-- `get_global_food_popularity`).
CREATE TEMP TABLE _food_view_snapshot AS
SELECT
    n.nspname                                  AS schema_name,
    c.relname                                  AS view_name,
    c.relkind                                  AS rel_kind,        -- 'v' = view, 'm' = matview
    pg_get_viewdef(c.oid, true)                AS view_def,
    -- security_invoker reloption is the canonical Supabase view hardening
    -- (see `supabase-rules.mdc`). Restore it on recreate so the rebuilt
    -- view doesn't silently downgrade from `security_invoker = on` to the
    -- default `security_invoker = off` (which would let a regular auth'd
    -- caller see ALL rows the view's owner can see — RLS bypass).
    EXISTS (
        SELECT 1
        FROM unnest(c.reloptions) AS opt
        WHERE opt = 'security_invoker=on' OR opt = 'security_invoker=true'
    )                                          AS uses_security_invoker
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind IN ('v', 'm')
  AND n.nspname = 'public'
  AND EXISTS (
    SELECT 1
    FROM pg_rewrite r
    JOIN pg_depend d ON d.objid = r.oid
    JOIN pg_class t ON t.oid = d.refobjid
    JOIN pg_namespace tn ON tn.oid = t.relnamespace
    WHERE r.ev_class = c.oid
      AND tn.nspname = 'public'
      AND t.relname IN ('food_items', 'user_food_history')
  );

-- Drop discovered views with CASCADE so any unknown view-of-a-view (not
-- captured in the snapshot) is also cleaned. The unsnapshotted ones won't
-- be restored — by definition they're not source-controlled and the user
-- needs to re-create them manually if they're still needed. This is the
-- correct behavior for ad-hoc SQL Editor-created views: the migration
-- shouldn't pretend it knows what they were for.
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN SELECT schema_name, view_name, rel_kind FROM _food_view_snapshot LOOP
    IF r.rel_kind = 'm' THEN
      EXECUTE format('DROP MATERIALIZED VIEW IF EXISTS %I.%I CASCADE', r.schema_name, r.view_name);
    ELSE
      EXECUTE format('DROP VIEW IF EXISTS %I.%I CASCADE', r.schema_name, r.view_name);
    END IF;
  END LOOP;
END $$;

-- ----------------------------------------------------------------------------
-- 0b. Drop ALL overloads of the affected RPCs via the Supabase-invariant-12
-- pg_proc loop, so the recreate-as-BIGINT below doesn't trip
-- `cannot change return type of existing function`. Loop catches every
-- signature regardless of historical drift (e.g. an older `(INTEGER, TEXT)`
-- variant would still get cleaned up).
DO $$
DECLARE
  func_name TEXT;
  func_oid OID;
BEGIN
  FOREACH func_name IN ARRAY ARRAY[
    'increment_food_log_count',
    'get_global_food_popularity',
    'get_user_frequent_foods'
  ]
  LOOP
    FOR func_oid IN
      SELECT p.oid
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname = 'public' AND p.proname = func_name
    LOOP
      EXECUTE format('DROP FUNCTION IF EXISTS public.%I(%s) CASCADE',
        func_name,
        pg_get_function_identity_arguments(func_oid));
    END LOOP;
  END LOOP;
END $$;

-- ----------------------------------------------------------------------------
-- 1. Widen `food_items.fdc_id` INT4 → BIGINT (idempotent: noop if already bigint)
-- ----------------------------------------------------------------------------
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'food_items'
          AND column_name = 'fdc_id'
          AND data_type = 'integer'
    ) THEN
        ALTER TABLE public.food_items
            ALTER COLUMN fdc_id TYPE BIGINT USING fdc_id::BIGINT;
    END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 1b. Widen `user_food_history.fdc_id` INT4 → BIGINT (defensive — column may
--     not exist in all envs; the table itself is pre-`YYYYMMDD_` era)
-- ----------------------------------------------------------------------------
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'user_food_history'
          AND column_name = 'fdc_id'
          AND data_type = 'integer'
    ) THEN
        ALTER TABLE public.user_food_history
            ALTER COLUMN fdc_id TYPE BIGINT USING fdc_id::BIGINT;
    END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 2. Drop NOT NULL on fdc_id (defensive — OFF rows always populate it via
--    syntheticFdcIdForBarcode, but if the iOS-side `cache_food` path is ever
--    fed a payload missing fdcId we want NULL > a poison-pill 0).
-- ----------------------------------------------------------------------------
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'food_items'
          AND column_name = 'fdc_id'
          AND is_nullable = 'NO'
    ) THEN
        ALTER TABLE public.food_items ALTER COLUMN fdc_id DROP NOT NULL;
    END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 3. Add new columns (idempotent)
-- ----------------------------------------------------------------------------
ALTER TABLE public.food_items
    ADD COLUMN IF NOT EXISTS barcode TEXT,
    ADD COLUMN IF NOT EXISTS source TEXT NOT NULL DEFAULT 'usda',
    ADD COLUMN IF NOT EXISTS image_url TEXT;

-- ----------------------------------------------------------------------------
-- 4. Constrain `source` to known values so a future typo doesn't silently
--    create a third bucket the ranker can't score.
-- ----------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'food_items_source_check'
    ) THEN
        ALTER TABLE public.food_items
            ADD CONSTRAINT food_items_source_check
            CHECK (source IN ('usda', 'off'));
    END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 5. PARTIAL UNIQUE INDEX on barcode (only for OFF rows)
--    - Partial: zero index cost for the existing 99% USDA rows.
--    - UNIQUE: lookup is `WHERE barcode = $1` and we never want two rows for
--      the same scan code.
--    - Where source = 'off': USDA never has a barcode. If a future ingestion
--      ever populates it for a USDA Branded row, that row still won't be
--      reachable from the scanner UI (which routes through the `barcode`
--      action specifically), so gating on source = 'off' is the safer index.
-- ----------------------------------------------------------------------------
CREATE UNIQUE INDEX IF NOT EXISTS food_items_barcode_off_uidx
    ON public.food_items (barcode)
    WHERE barcode IS NOT NULL AND source = 'off';

-- Plain index for general source-based filtering (e.g. CMS analytics
-- breakdowns by source).
CREATE INDEX IF NOT EXISTS food_items_source_idx
    ON public.food_items (source);

-- ----------------------------------------------------------------------------
-- 6. Recreate ALL snapshotted views from the section 0a temp table
-- ----------------------------------------------------------------------------
-- Each view is restored verbatim from `pg_get_viewdef`'s parsed-SQL output,
-- with its `security_invoker` reloption re-applied if the original had it.
-- Order doesn't matter here — `pg_get_viewdef` doesn't emit cross-view
-- references (each view's body inlines whatever it reads), so a recreate-
-- in-snapshot-order pass is sufficient. If a view-of-a-view existed but
-- only the leaf was snapshotted, the dependent would have been
-- CASCADE-dropped in section 0a and stays gone (deliberate — see comment
-- there). Manual recreate post-migration is the recovery path.
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN SELECT schema_name, view_name, rel_kind, view_def, uses_security_invoker
           FROM _food_view_snapshot LOOP
    IF r.rel_kind = 'm' THEN
      EXECUTE format('CREATE MATERIALIZED VIEW %I.%I AS %s',
        r.schema_name, r.view_name, r.view_def);
    ELSE
      EXECUTE format('CREATE OR REPLACE VIEW %I.%I AS %s',
        r.schema_name, r.view_name, r.view_def);
    END IF;
    -- security_invoker is a regular-view-only reloption (matviews don't
    -- support it; they always run as their owner). Skip on rel_kind = 'm'.
    IF r.uses_security_invoker AND r.rel_kind = 'v' THEN
      EXECUTE format('ALTER VIEW %I.%I SET (security_invoker = on)',
        r.schema_name, r.view_name);
    END IF;
  END LOOP;
END $$;

-- TEMP table is auto-dropped at COMMIT, but be explicit for re-run safety
-- in case someone runs this script outside a session boundary.
DROP TABLE IF EXISTS _food_view_snapshot;

-- ----------------------------------------------------------------------------
-- 7. Recreate the three RPCs with BIGINT signatures
-- ----------------------------------------------------------------------------
-- 7a. increment_food_log_count(fdc_id_param BIGINT)
--     iOS calls this from `FoodDatabaseService.logFoodAccess(...)` whenever a
--     food is added to a meal — must accept the synthetic negative bigint
--     fdcId for OFF rows or the meal-add silently no-ops on log_count update.
CREATE OR REPLACE FUNCTION public.increment_food_log_count(fdc_id_param BIGINT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    UPDATE public.food_items
       SET log_count = COALESCE(log_count, 0) + 1,
           last_logged_at = NOW()
     WHERE fdc_id = fdc_id_param;
END;
$$;

-- 7b. get_global_food_popularity(limit_count INTEGER)
--     Reads from `user_food_history` — which we widened to BIGINT in step 1b.
--     RETURNS TABLE matches the new column type.
CREATE OR REPLACE FUNCTION public.get_global_food_popularity(limit_count INTEGER DEFAULT 30)
RETURNS TABLE(
    fdc_id BIGINT,
    food_name TEXT,
    total_logs BIGINT,
    unique_users BIGINT,
    avg_calories NUMERIC,
    avg_protein NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT
        ufh.fdc_id,
        ufh.food_name,
        COUNT(*)::BIGINT AS total_logs,
        COUNT(DISTINCT ufh.user_id)::BIGINT AS unique_users,
        AVG(ufh.calories)::NUMERIC AS avg_calories,
        AVG(ufh.protein)::NUMERIC AS avg_protein
    FROM public.user_food_history ufh
    WHERE ufh.fdc_id > 0  -- USDA rows only; OFF rows have negative fdcId
    GROUP BY ufh.fdc_id, ufh.food_name
    ORDER BY total_logs DESC
    LIMIT limit_count;
END;
$$;

-- 7c. get_user_frequent_foods(p_limit INTEGER)
--     Per-user aggregation over user_food_history. Same widening rationale.
CREATE OR REPLACE FUNCTION public.get_user_frequent_foods(
  p_limit INTEGER DEFAULT 20
)
RETURNS TABLE(
  fdc_id BIGINT,
  food_name TEXT,
  calories NUMERIC,
  protein NUMERIC,
  carbs NUMERIC,
  fat NUMERIC,
  usage_count BIGINT,
  quantity NUMERIC,
  serving_unit TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    ufh.fdc_id,
    ufh.food_name,
    MAX(ufh.calories)::NUMERIC AS calories,
    MAX(ufh.protein)::NUMERIC AS protein,
    MAX(ufh.carbs)::NUMERIC AS carbs,
    MAX(ufh.fat)::NUMERIC AS fat,
    COUNT(*) AS usage_count,
    MAX(ufh.quantity)::NUMERIC AS quantity,
    MAX(ufh.serving_unit) AS serving_unit
  FROM public.user_food_history ufh
  WHERE ufh.user_id = auth.uid()
  GROUP BY ufh.fdc_id, ufh.food_name
  ORDER BY usage_count DESC
  LIMIT p_limit;
END;
$$;

-- ----------------------------------------------------------------------------
-- 8. Helper RPC: increment search_count by id (used by handleBarcode cache hit)
--    - We already have `increment_food_search_count(query_text)` for the
--      query-cache path. Barcode hits go through `food_items.id` directly so
--      they need a different RPC. Best-effort, non-critical — failure is
--      swallowed in the edge function with try/catch.
--    - SECURITY DEFINER + SET search_path so service-role calls work even
--      under RLS-tightened public roles. No user-id parameter (Data invariant
--      #7 doesn't apply — this only mutates aggregate counters, no IDOR
--      surface).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.increment_food_search_count_by_id(p_food_id BIGINT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    UPDATE public.food_items
       SET search_count = COALESCE(search_count, 0) + 1
     WHERE id = p_food_id;
END;
$$;

-- ----------------------------------------------------------------------------
-- 9. Permissions — preserve the original GRANTs from global_food_popularity.sql
-- ----------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.increment_food_log_count(BIGINT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.increment_food_log_count(BIGINT) TO authenticated, anon;

REVOKE ALL ON FUNCTION public.get_global_food_popularity(INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_global_food_popularity(INTEGER) TO authenticated, anon;

REVOKE ALL ON FUNCTION public.get_user_frequent_foods(INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_user_frequent_foods(INTEGER) TO authenticated;

REVOKE ALL ON FUNCTION public.increment_food_search_count_by_id(BIGINT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.increment_food_search_count_by_id(BIGINT) TO authenticated, service_role;

COMMIT;
