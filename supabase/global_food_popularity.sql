-- ============================================================================
-- GLOBAL FOOD POPULARITY TRACKING
-- Tracks how popular foods are across ALL users for smart search ranking
-- ============================================================================

-- 1. Add log_count and search_count columns to food_items if they don't exist
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'food_items' AND column_name = 'log_count') THEN
        ALTER TABLE food_items ADD COLUMN log_count INTEGER DEFAULT 0;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'food_items' AND column_name = 'search_count') THEN
        ALTER TABLE food_items ADD COLUMN search_count INTEGER DEFAULT 0;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'food_items' AND column_name = 'last_logged_at') THEN
        ALTER TABLE food_items ADD COLUMN last_logged_at TIMESTAMPTZ;
    END IF;
END $$;

-- 2. Create index for fast popularity queries
CREATE INDEX IF NOT EXISTS idx_food_items_log_count ON food_items(log_count DESC);
CREATE INDEX IF NOT EXISTS idx_food_items_search_count ON food_items(search_count DESC);

-- 3. RPC function to increment food log count (called when any user logs a food)
CREATE OR REPLACE FUNCTION increment_food_log_count(fdc_id_param INTEGER)
RETURNS void AS $$
BEGIN
    UPDATE food_items 
    SET log_count = COALESCE(log_count, 0) + 1,
        last_logged_at = NOW()
    WHERE fdc_id = fdc_id_param;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. RPC function to increment food search count (called when search cache is hit)
CREATE OR REPLACE FUNCTION increment_food_search_count(query_text TEXT)
RETURNS void AS $$
BEGIN
    UPDATE food_search_cache 
    SET search_count = COALESCE(search_count, 0) + 1,
        last_searched_at = NOW()
    WHERE normalized_query = query_text;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. View for top globally popular foods (used by the app's "Trending" section)
CREATE OR REPLACE VIEW popular_foods_view AS
SELECT 
    fi.*,
    COALESCE(fi.log_count, 0) as popularity_score
FROM food_items fi
WHERE COALESCE(fi.log_count, 0) > 0
ORDER BY fi.log_count DESC NULLS LAST, fi.search_count DESC NULLS LAST
LIMIT 50;

-- 6. Function to get aggregated food popularity from user_food_history
-- This provides a more accurate count by counting actual log entries
CREATE OR REPLACE FUNCTION get_global_food_popularity(limit_count INTEGER DEFAULT 30)
RETURNS TABLE(
    fdc_id INTEGER,
    food_name TEXT,
    total_logs BIGINT,
    unique_users BIGINT,
    avg_calories NUMERIC,
    avg_protein NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        ufh.fdc_id,
        ufh.food_name,
        COUNT(*)::BIGINT as total_logs,
        COUNT(DISTINCT ufh.user_id)::BIGINT as unique_users,
        AVG(ufh.calories)::NUMERIC as avg_calories,
        AVG(ufh.protein)::NUMERIC as avg_protein
    FROM user_food_history ufh
    WHERE ufh.fdc_id > 0
    GROUP BY ufh.fdc_id, ufh.food_name
    ORDER BY total_logs DESC
    LIMIT limit_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 7. Grant execute permissions
GRANT EXECUTE ON FUNCTION increment_food_log_count(INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION increment_food_log_count(INTEGER) TO anon;
GRANT EXECUTE ON FUNCTION increment_food_search_count(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION increment_food_search_count(TEXT) TO anon;
GRANT EXECUTE ON FUNCTION get_global_food_popularity(INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION get_global_food_popularity(INTEGER) TO anon;
