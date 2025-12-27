-- ============================================================================
-- COLLABORATIVE LEARNING - MATERIALIZED VIEWS
-- ============================================================================
-- Run this AFTER creating the base tables.
-- These views aggregate data for faster recommendations.
-- They'll be empty at first - that's fine!
-- ============================================================================

-- ============================================================================
-- MATERIALIZED VIEW 1: Exercise Pairing Stats
-- Shows which exercises are frequently done together
-- ============================================================================
CREATE MATERIALIZED VIEW IF NOT EXISTS exercise_pairing_stats AS
SELECT 
    ex1,
    ex2,
    muscle1,
    muscle2,
    COUNT(*) as co_occurrence_count,
    COUNT(DISTINCT DATE(recorded_at)) as days_paired
FROM exercise_pairings
GROUP BY ex1, ex2, muscle1, muscle2
HAVING COUNT(*) >= 3
ORDER BY co_occurrence_count DESC;

-- Index for fast lookups
CREATE INDEX IF NOT EXISTS idx_pairing_stats_ex1 ON exercise_pairing_stats(ex1);
CREATE INDEX IF NOT EXISTS idx_pairing_stats_ex2 ON exercise_pairing_stats(ex2);

-- ============================================================================
-- MATERIALIZED VIEW 2: Exercise Global Stats
-- Shows overall popularity and success rates for each exercise
-- ============================================================================
CREATE MATERIALIZED VIEW IF NOT EXISTS exercise_global_stats AS
SELECT 
    UNNEST(exercises_completed) as exercise_name,
    COUNT(*) as completion_count,
    COUNT(DISTINCT user_id) as unique_users,
    AVG(duration_minutes) as avg_duration,
    1.0 as success_rate  -- Placeholder: all completed = 100% success
FROM collaborative_workout_data
GROUP BY exercise_name
HAVING COUNT(*) >= 5
ORDER BY completion_count DESC;

-- Index for fast lookups
CREATE INDEX IF NOT EXISTS idx_global_stats_name ON exercise_global_stats(exercise_name);

-- ============================================================================
-- MATERIALIZED VIEW 3: Program Success Stats
-- Shows which programs have the highest completion rates
-- ============================================================================
CREATE MATERIALIZED VIEW IF NOT EXISTS program_success_stats AS
SELECT 
    program_name,
    program_type,
    COUNT(*) as completion_count,
    AVG(completion_rate) as avg_completion_rate,
    AVG(completed_days) as avg_days_completed,
    ARRAY_AGG(DISTINCT user_id::text) as user_ids
FROM collaborative_program_completions
WHERE completion_rate >= 0.5  -- Only programs with 50%+ completion
GROUP BY program_name, program_type
HAVING COUNT(*) >= 3
ORDER BY avg_completion_rate DESC;

-- Index for fast lookups
CREATE INDEX IF NOT EXISTS idx_program_stats_name ON program_success_stats(program_name);

-- ============================================================================
-- REFRESH FUNCTION
-- Call this to update all materialized views with new data
-- ============================================================================
CREATE OR REPLACE FUNCTION refresh_collaborative_stats()
RETURNS TEXT AS $$
DECLARE
    result TEXT := '';
BEGIN
    -- Refresh exercise pairings
    BEGIN
        REFRESH MATERIALIZED VIEW CONCURRENTLY exercise_pairing_stats;
        result := result || 'Exercise pairings refreshed. ';
    EXCEPTION WHEN OTHERS THEN
        BEGIN
            REFRESH MATERIALIZED VIEW exercise_pairing_stats;
            result := result || 'Exercise pairings refreshed (non-concurrent). ';
        EXCEPTION WHEN OTHERS THEN
            result := result || 'Exercise pairings failed: ' || SQLERRM || '. ';
        END;
    END;
    
    -- Refresh exercise stats
    BEGIN
        REFRESH MATERIALIZED VIEW CONCURRENTLY exercise_global_stats;
        result := result || 'Exercise stats refreshed. ';
    EXCEPTION WHEN OTHERS THEN
        BEGIN
            REFRESH MATERIALIZED VIEW exercise_global_stats;
            result := result || 'Exercise stats refreshed (non-concurrent). ';
        EXCEPTION WHEN OTHERS THEN
            result := result || 'Exercise stats failed: ' || SQLERRM || '. ';
        END;
    END;
    
    -- Refresh program stats
    BEGIN
        REFRESH MATERIALIZED VIEW CONCURRENTLY program_success_stats;
        result := result || 'Program stats refreshed.';
    EXCEPTION WHEN OTHERS THEN
        BEGIN
            REFRESH MATERIALIZED VIEW program_success_stats;
            result := result || 'Program stats refreshed (non-concurrent).';
        EXCEPTION WHEN OTHERS THEN
            result := result || 'Program stats failed: ' || SQLERRM || '.';
        END;
    END;
    
    RETURN result;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- ✅ SETUP COMPLETE!
-- ============================================================================
-- The materialized views are created (they'll be empty until you have data).
-- 
-- After completing 10+ workouts, refresh them by running:
-- SELECT refresh_collaborative_stats();
-- 
-- Set up automatic refresh (optional):
-- Go to Database → Scheduled Jobs → Create new job:
-- Schedule: Every hour
-- SQL: SELECT refresh_collaborative_stats();
-- ============================================================================

