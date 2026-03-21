-- ============================================================================
-- FOOD SEARCH INTEGRITY MIGRATION
-- Date: 2026-03-21
-- Source: USDA Integration Audit recommendations
-- ============================================================================
-- Changes:
--   1a. Add created_at TTL column to food_search_cache (30-day expiry)
--   1b. Create get_user_frequent_foods() RPC (server-side aggregation)
--   1c. Composite index on user_food_history(user_id, logged_at DESC)
--   1d. UNIQUE constraint on user_favorite_foods(user_id, food_item_id)
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1a. Cache TTL for food_search_cache
-- ============================================================================
-- USDA updates quarterly; 30-day TTL balances freshness with cache hit rate.
-- The edge function checks created_at before serving cached results.

ALTER TABLE food_search_cache
  ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT now();

-- Backfill existing rows: use last_searched_at if available, otherwise now()
UPDATE food_search_cache
SET created_at = COALESCE(last_searched_at, now())
WHERE created_at IS NULL;

-- Cleanup function to purge stale cache entries (>30 days)
CREATE OR REPLACE FUNCTION cleanup_expired_food_cache()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  deleted_count INTEGER;
BEGIN
  DELETE FROM food_search_cache
  WHERE created_at < now() - INTERVAL '30 days';

  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  RETURN deleted_count;
END;
$$;

GRANT EXECUTE ON FUNCTION cleanup_expired_food_cache() TO service_role;

-- Index to speed up TTL-based cache lookups
CREATE INDEX IF NOT EXISTS idx_food_search_cache_created_at
  ON food_search_cache(created_at);

-- ============================================================================
-- 1b. Server-side frequent foods RPC
-- ============================================================================
-- Replaces client-side aggregation that fetches ALL user_food_history rows.
-- Returns top N foods grouped by fdc_id/food_name with usage counts.

CREATE OR REPLACE FUNCTION get_user_frequent_foods(
  p_limit INT DEFAULT 20
)
RETURNS TABLE (
  fdc_id INT,
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
AS $$
BEGIN
  RETURN QUERY
  SELECT
    ufh.fdc_id,
    ufh.food_name,
    MAX(ufh.calories)::NUMERIC     AS calories,
    MAX(ufh.protein)::NUMERIC      AS protein,
    MAX(ufh.carbs)::NUMERIC        AS carbs,
    MAX(ufh.fat)::NUMERIC          AS fat,
    COUNT(*)                        AS usage_count,
    MAX(ufh.quantity)::NUMERIC     AS quantity,
    MAX(ufh.serving_unit)           AS serving_unit
  FROM user_food_history ufh
  WHERE ufh.user_id = auth.uid()
  GROUP BY ufh.fdc_id, ufh.food_name
  ORDER BY usage_count DESC
  LIMIT p_limit;
END;
$$;

GRANT EXECUTE ON FUNCTION get_user_frequent_foods(INT) TO authenticated;

-- ============================================================================
-- 1c. Composite index on user_food_history
-- ============================================================================
-- Speeds up loadRecentFoods() which orders by logged_at DESC

CREATE INDEX IF NOT EXISTS idx_user_food_history_user_logged
  ON user_food_history(user_id, logged_at DESC);

-- ============================================================================
-- 1d. UNIQUE constraint on user_favorite_foods
-- ============================================================================
-- Prevents duplicate favorites from race conditions.
-- First, deduplicate any existing rows (keep the earliest-inserted row per pair).
-- Uses ctid because the id column is UUID (MIN/MAX not supported).

DELETE FROM user_favorite_foods a
USING user_favorite_foods b
WHERE a.user_id = b.user_id
  AND a.food_item_id = b.food_item_id
  AND a.ctid > b.ctid;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'uq_user_favorite_foods'
  ) THEN
    ALTER TABLE user_favorite_foods
      ADD CONSTRAINT uq_user_favorite_foods UNIQUE (user_id, food_item_id);
  END IF;
END $$;

COMMIT;
