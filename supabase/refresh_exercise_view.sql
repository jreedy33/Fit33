-- ============================================================================
-- REFRESH MATERIALIZED VIEW + FIX CATEGORY DATA
-- Run this AFTER update_exercises_from_csv.sql
-- ============================================================================

-- Fix 2 exercises that have "Biceps" as category (not a standard app category)
-- These should be categorized properly for the UI color/icon mapping
UPDATE exercises SET category = 'Arms' WHERE id = '88783bbf-6352-4f6d-ba6a-31b76ac77602'; -- Romanian Deadlift Bicep Curl Kickback
UPDATE exercises SET category = 'Arms' WHERE id = 'fc9a7bfc-2dc6-4888-84cb-9faeefa9df9b'; -- Rear Lunge Bicep Curl

-- Refresh the materialized view so the app gets the updated data
-- The app fetches from mv_public_exercises first for performance
REFRESH MATERIALIZED VIEW IF EXISTS mv_public_exercises;

-- Verify the refresh worked
DO $$
DECLARE
    view_count INT;
    table_count INT;
BEGIN
    -- Check if materialized view exists
    IF EXISTS (SELECT 1 FROM pg_matviews WHERE matviewname = 'mv_public_exercises') THEN
        SELECT COUNT(*) INTO view_count FROM mv_public_exercises;
        SELECT COUNT(*) INTO table_count FROM exercises WHERE is_custom = false;
        RAISE NOTICE '✅ Materialized view refreshed: % exercises (table has %)', view_count, table_count;
    ELSE
        RAISE NOTICE 'ℹ️ No materialized view found — app will use exercises table directly';
    END IF;
END $$;
