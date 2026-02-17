-- ============================================================================
-- FIX: Refresh materialized view for exercise data
-- The app fetches from mv_public_exercises (cached view) first.
-- If this view is stale, exercises show as blank "Exercise" cards.
-- ============================================================================

-- Step 1: Check if the materialized view exists and refresh it
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_matviews WHERE matviewname = 'mv_public_exercises'
    ) THEN
        RAISE NOTICE '🔄 Refreshing materialized view mv_public_exercises...';
        EXECUTE 'REFRESH MATERIALIZED VIEW mv_public_exercises';
        RAISE NOTICE '✅ Materialized view refreshed!';
    ELSE
        RAISE NOTICE 'ℹ️ Materialized view mv_public_exercises does not exist.';
        RAISE NOTICE '   Creating it now...';
        
        -- Create the materialized view with all exercise columns
        EXECUTE '
            CREATE MATERIALIZED VIEW mv_public_exercises AS
            SELECT *
            FROM exercises
            WHERE is_custom = false
        ';
        
        -- Create index for faster lookups
        EXECUTE '
            CREATE INDEX IF NOT EXISTS idx_mv_exercises_name 
            ON mv_public_exercises(name)
        ';
        
        RAISE NOTICE '✅ Materialized view created!';
    END IF;
END $$;

-- Step 2: Verify the data looks correct
DO $$
DECLARE
    total_count INT;
    named_count INT;
    null_name_count INT;
BEGIN
    -- Check exercises table
    SELECT COUNT(*) INTO total_count FROM exercises WHERE is_custom = false;
    SELECT COUNT(*) INTO named_count FROM exercises WHERE is_custom = false AND name IS NOT NULL AND name != '';
    SELECT COUNT(*) INTO null_name_count FROM exercises WHERE is_custom = false AND (name IS NULL OR name = '');
    
    RAISE NOTICE '';
    RAISE NOTICE '📊 EXERCISES TABLE VERIFICATION:';
    RAISE NOTICE '   Total non-custom exercises: %', total_count;
    RAISE NOTICE '   With valid names: %', named_count;
    RAISE NOTICE '   With NULL/empty names: %', null_name_count;
    
    -- Check materialized view if it exists
    IF EXISTS (SELECT 1 FROM pg_matviews WHERE matviewname = 'mv_public_exercises') THEN
        SELECT COUNT(*) INTO total_count FROM mv_public_exercises;
        SELECT COUNT(*) INTO named_count FROM mv_public_exercises WHERE name IS NOT NULL AND name != '';
        
        RAISE NOTICE '';
        RAISE NOTICE '📊 MATERIALIZED VIEW VERIFICATION:';
        RAISE NOTICE '   Total exercises in view: %', total_count;
        RAISE NOTICE '   With valid names: %', named_count;
    END IF;
    
    RAISE NOTICE '';
    RAISE NOTICE '✅ Verification complete!';
    RAISE NOTICE '   After running this, force-close and reopen the app.';
    RAISE NOTICE '   Or use the Force Refresh Exercises button in Settings.';
END $$;
