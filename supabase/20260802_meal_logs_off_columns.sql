-- ============================================================================
-- Migration #166 — Widen meal_logs.fdc_id to BIGINT + add OFF/detailed columns
-- ============================================================================
--
-- WHY:
--   The 2026-04-30 nutrition pipeline audit found three silent data losses:
--
--     1. `meal_logs.fdc_id` is INTEGER (INT4). OFF (Open Food Facts) synthetic
--        ids are NEGATIVE bigints derived from the EAN/UPC barcode (e.g.
--        barcode 3017620422003 → fdcId -3017620422003). INT4 truncates these,
--        meaning every OFF meal logged round-tripped to NULL on save → no
--        provenance, no favoriting, no barcode-cache hits across devices.
--
--     2. fiber / sugar / sodium are computed by FoodDetailsView and shown to
--        the user, but never persisted. They were dropped at `MealEntry`
--        save time and recomputed (incorrectly, often as 0) every render.
--        Dashboard fiber goal / sodium-limit quests are impossible without
--        these columns.
--
--     3. `source` (usda / off / ocr / spoonacular) and `barcode` were
--        carried as far as `ProcessedFoodItem` and then dropped. Without
--        these columns we can't:
--          - render the ODbL "Data: Open Food Facts" attribution footer
--            for previously-saved OFF meals (license requirement),
--          - de-duplicate barcode-scanned items across devices,
--          - run analytics breakdowns by data source in the CMS.
--
-- COMPATIBILITY:
--   - All new columns are NULLABLE with no default, so pre-existing rows
--     remain valid (NULL = "we don't know" — correct semantic vs a forced 0).
--   - `fdc_id BIGINT` is a widening cast — every existing INT4 value fits
--     unchanged.
--   - **Dynamic dependency handling** (lesson learned from migration #165):
--     `meal_logs.fdc_id` IS referenced by views (e.g. `user_food_history_v`
--     joins meal_logs → food_items via fdc_id). We snapshot every dependent
--     view's `pg_get_viewdef`, drop them with CASCADE, alter the column,
--     then recreate from the snapshot. Idempotent + handles unknown views.
--
-- COORDINATES WITH:
--   - supabase/20260801_food_items_off_barcode.sql — widened
--     `food_items.fdc_id` and `user_food_history.fdc_id` to BIGINT.
--   - Fit33/SupabaseDTOs.swift::MealLogDTO — adds fiber/sugar/sodium/source/barcode.
--   - Fit33/SupabaseManager.swift — saveMealToCloud / syncMealLogsToCoreData
--     plumb the new columns; the legacy `fdcId > 0` filter (which dropped
--     OFF rows) was changed to `fdcId != 0`.
-- ============================================================================

BEGIN;

-- ────────────────────────────────────────────────────────────────────────────
-- 1. Discover + snapshot every (materialized) view that depends on
--    meal_logs.fdc_id, then CASCADE-drop them. We'll recreate at step 5.
--
--    pg_depend → pg_rewrite → pg_class chain finds rules that reference
--    a specific column on a specific relation. We catch BOTH regular views
--    (`relkind = 'v'`) and materialized views (`relkind = 'm'`).
-- ────────────────────────────────────────────────────────────────────────────
CREATE TEMP TABLE _meal_log_view_snapshot (
    view_schema TEXT,
    view_name   TEXT,
    relkind     CHAR,            -- 'v' = view, 'm' = matview
    is_security_invoker BOOLEAN, -- recreate with same setting
    view_def    TEXT
) ON COMMIT DROP;

DO $$
DECLARE
    r RECORD;
    v_def TEXT;
    v_security_invoker BOOLEAN;
BEGIN
    FOR r IN
        SELECT DISTINCT n.nspname AS view_schema,
                        c.relname AS view_name,
                        c.relkind,
                        c.oid    AS view_oid
        FROM pg_depend d
        JOIN pg_rewrite rw ON d.objid = rw.oid
        JOIN pg_class   c  ON rw.ev_class = c.oid
        JOIN pg_namespace n ON c.relnamespace = n.oid
        JOIN pg_attribute a ON a.attrelid = d.refobjid
                            AND a.attnum  = d.refobjsubid
        WHERE d.refobjid = 'public.meal_logs'::regclass
          AND a.attname  = 'fdc_id'
          AND c.relkind  IN ('v', 'm')
          AND n.nspname  = 'public'
    LOOP
        v_def := pg_get_viewdef(format('%I.%I', r.view_schema, r.view_name)::regclass, true);

        -- Detect security_invoker setting on regular views so we can re-apply
        -- it on recreate. (Materialized views don't have this option.)
        IF r.relkind = 'v' THEN
            SELECT COALESCE(
                (SELECT (option_name = 'security_invoker' AND option_value::boolean) IS TRUE
                   FROM (
                       SELECT split_part(opt, '=', 1) AS option_name,
                              split_part(opt, '=', 2) AS option_value
                       FROM unnest(c.reloptions) AS opt
                   ) opts
                  WHERE option_name = 'security_invoker'
                  LIMIT 1),
                false
            )
            INTO v_security_invoker
            FROM pg_class c
            WHERE c.oid = r.view_oid;
        ELSE
            v_security_invoker := false;
        END IF;

        INSERT INTO _meal_log_view_snapshot
            (view_schema, view_name, relkind, is_security_invoker, view_def)
        VALUES (r.view_schema, r.view_name, r.relkind, v_security_invoker, v_def);

        RAISE NOTICE 'Snapshotted % %.% (security_invoker=%)',
            CASE WHEN r.relkind = 'm' THEN 'matview' ELSE 'view' END,
            r.view_schema, r.view_name, v_security_invoker;
    END LOOP;
END $$;

-- 2. Drop all snapshotted views. CASCADE because some may depend on each other.
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN SELECT view_schema, view_name, relkind FROM _meal_log_view_snapshot
    LOOP
        EXECUTE format(
            'DROP %s IF EXISTS %I.%I CASCADE',
            CASE WHEN r.relkind = 'm' THEN 'MATERIALIZED VIEW' ELSE 'VIEW' END,
            r.view_schema, r.view_name
        );
        RAISE NOTICE 'Dropped %.%', r.view_schema, r.view_name;
    END LOOP;
END $$;

-- ────────────────────────────────────────────────────────────────────────────
-- 3. Now safe to widen fdc_id and add the new columns.
-- ────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.meal_logs
    ALTER COLUMN fdc_id TYPE BIGINT USING fdc_id::BIGINT;

ALTER TABLE public.meal_logs
    ADD COLUMN IF NOT EXISTS fiber  DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS sugar  DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS sodium DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS source  TEXT,
    ADD COLUMN IF NOT EXISTS barcode TEXT;

ALTER TABLE public.meal_logs
    DROP CONSTRAINT IF EXISTS meal_logs_source_check;
ALTER TABLE public.meal_logs
    ADD CONSTRAINT meal_logs_source_check
        CHECK (source IS NULL OR source IN ('usda','off','ocr','spoonacular','manual'));

CREATE INDEX IF NOT EXISTS meal_logs_source_idx
    ON public.meal_logs (source)
    WHERE source IS NOT NULL;

CREATE INDEX IF NOT EXISTS meal_logs_barcode_idx
    ON public.meal_logs (user_id, barcode)
    WHERE barcode IS NOT NULL;

-- ────────────────────────────────────────────────────────────────────────────
-- 4. Recreate every dropped (mat)view from its snapshotted definition.
--    Order doesn't matter for regular views (they're independent of each
--    other once meal_logs is altered); matviews follow the same pattern.
--
--    We re-apply security_invoker = on for views that had it (this is the
--    Supabase RLS-respecting pattern from supabase-rules.mdc).
-- ────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN SELECT * FROM _meal_log_view_snapshot
    LOOP
        IF r.relkind = 'm' THEN
            EXECUTE format(
                'CREATE MATERIALIZED VIEW %I.%I AS %s',
                r.view_schema, r.view_name, r.view_def
            );
        ELSE
            -- Recreate with security_invoker = on if it was set originally,
            -- otherwise plain view. Trailing semicolon is in r.view_def.
            IF r.is_security_invoker THEN
                EXECUTE format(
                    'CREATE VIEW %I.%I WITH (security_invoker = on) AS %s',
                    r.view_schema, r.view_name, r.view_def
                );
            ELSE
                EXECUTE format(
                    'CREATE VIEW %I.%I AS %s',
                    r.view_schema, r.view_name, r.view_def
                );
            END IF;
        END IF;
        RAISE NOTICE 'Recreated %.% (security_invoker=%)',
            r.view_schema, r.view_name, r.is_security_invoker;
    END LOOP;
END $$;

COMMIT;

-- ============================================================================
-- Verify (run manually in psql; Supabase SQL Editor will show NOTICE output)
-- ============================================================================
--   SELECT column_name, data_type, is_nullable
--     FROM information_schema.columns
--    WHERE table_name = 'meal_logs'
--      AND column_name IN ('fdc_id','fiber','sugar','sodium','source','barcode')
--    ORDER BY column_name;
--
-- Expected:
--   barcode | text             | YES
--   fdc_id  | bigint           | YES
--   fiber   | double precision | YES
--   sodium  | double precision | YES
--   source  | text             | YES
--   sugar   | double precision | YES
--
-- And confirm the dependent view came back:
--   SELECT viewname FROM pg_views
--    WHERE schemaname = 'public' AND viewname = 'user_food_history_v';
-- ============================================================================
