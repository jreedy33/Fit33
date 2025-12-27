-- ================================================
-- ADMIN ANALYTICS FUNCTIONS
-- For comprehensive cross-user analytics
-- ================================================

-- Function to get top workouts across all users
CREATE OR REPLACE FUNCTION get_top_workouts(result_limit INTEGER DEFAULT 10)
RETURNS TABLE (
    name TEXT,
    count BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        w.name::TEXT,
        COUNT(*)::BIGINT as count
    FROM workouts w
    WHERE w.name IS NOT NULL
    GROUP BY w.name
    ORDER BY count DESC
    LIMIT result_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to get user activity summary
CREATE OR REPLACE FUNCTION get_user_activity_summary()
RETURNS TABLE (
    total_users BIGINT,
    active_last_7_days BIGINT,
    active_last_30_days BIGINT,
    total_workouts BIGINT,
    avg_workouts_per_user NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        COUNT(DISTINCT up.id)::BIGINT as total_users,
        COUNT(DISTINCT CASE 
            WHEN up.updated_at >= NOW() - INTERVAL '7 days' 
            THEN up.id 
        END)::BIGINT as active_last_7_days,
        COUNT(DISTINCT CASE 
            WHEN up.updated_at >= NOW() - INTERVAL '30 days' 
            THEN up.id 
        END)::BIGINT as active_last_30_days,
        (SELECT COUNT(*)::BIGINT FROM workouts) as total_workouts,
        CASE 
            WHEN COUNT(DISTINCT up.id) > 0 
            THEN (SELECT COUNT(*)::NUMERIC FROM workouts) / COUNT(DISTINCT up.id)::NUMERIC 
            ELSE 0 
        END as avg_workouts_per_user
    FROM user_profiles up;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to get step tracking analytics
CREATE OR REPLACE FUNCTION get_step_analytics()
RETURNS TABLE (
    total_users_tracking BIGINT,
    total_steps_7_days BIGINT,
    avg_steps_per_day NUMERIC,
    goal_completion_rate NUMERIC,
    days_tracked BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        COUNT(DISTINCT st.user_id)::BIGINT as total_users_tracking,
        SUM(st.steps)::BIGINT as total_steps_7_days,
        CASE 
            WHEN COUNT(*) > 0 
            THEN ROUND(AVG(st.steps), 0) 
            ELSE 0 
        END as avg_steps_per_day,
        CASE 
            WHEN COUNT(*) > 0 
            THEN ROUND((SUM(CASE WHEN st.steps >= st.goal THEN 1 ELSE 0 END)::NUMERIC / COUNT(*)::NUMERIC) * 100, 1)
            ELSE 0 
        END as goal_completion_rate,
        COUNT(*)::BIGINT as days_tracked
    FROM step_tracking st
    WHERE st.date >= CURRENT_DATE - INTERVAL '7 days';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to get exercise completion stats
CREATE OR REPLACE FUNCTION get_exercise_completion_stats()
RETURNS TABLE (
    total_exercise_completions BIGINT,
    unique_exercises_used BIGINT,
    avg_sets_per_exercise NUMERIC,
    total_reps_completed BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        COUNT(*)::BIGINT as total_exercise_completions,
        COUNT(DISTINCT exercise_name)::BIGINT as unique_exercises_used,
        ROUND(AVG(sets_completed), 1) as avg_sets_per_exercise,
        SUM(total_reps)::BIGINT as total_reps_completed
    FROM workout_exercises;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ================================================
-- EXERCISE POPULARITY STATS VIEW
-- Aggregates exercise usage and favorites across all users
-- ================================================

-- First, drop the table if it exists (it might be a table from before)
DROP TABLE IF EXISTS exercise_popularity_stats CASCADE;

-- Then drop the view if it exists
DROP VIEW IF EXISTS exercise_popularity_stats CASCADE;

-- Create comprehensive exercise popularity view
CREATE OR REPLACE VIEW exercise_popularity_stats AS
WITH exercise_usage AS (
    SELECT 
        we.exercise_name,
        COUNT(*) as total_uses,
        COUNT(DISTINCT w.user_id) as unique_users,
        COALESCE(ROUND(AVG(we.sets_completed), 2), 0) as avg_sets_per_use,
        0 as completion_rate,
        COUNT(CASE WHEN we.created_at >= NOW() - INTERVAL '7 days' THEN 1 END) as uses_last_7_days,
        COUNT(CASE WHEN we.created_at >= NOW() - INTERVAL '30 days' THEN 1 END) as uses_last_30_days
    FROM workout_exercises we
    JOIN workouts w ON we.workout_id = w.id::TEXT
    WHERE we.exercise_name IS NOT NULL
    GROUP BY we.exercise_name
),
exercise_favorites AS (
    SELECT 
        uf.exercise_id as exercise_name,
        COUNT(*) as favorite_count
    FROM user_favorites uf
    GROUP BY uf.exercise_id
)
SELECT 
    eu.exercise_name as exercise_id,
    eu.exercise_name,
    eu.total_uses,
    eu.unique_users,
    -- Popularity score: combines usage and unique users
    ROUND((eu.total_uses::NUMERIC * 0.6) + (eu.unique_users::NUMERIC * 2.0), 2) as popularity_score,
    -- Trending score: heavily weights recent activity
    ROUND((eu.uses_last_7_days::NUMERIC * 3.0) + (eu.uses_last_30_days::NUMERIC * 0.5), 2) as trending_score,
    eu.avg_sets_per_use,
    eu.completion_rate,
    eu.uses_last_7_days,
    eu.uses_last_30_days,
    COALESCE(ef.favorite_count, 0)::INTEGER as favorite_count
FROM exercise_usage eu
LEFT JOIN exercise_favorites ef ON eu.exercise_name = ef.exercise_name
WHERE eu.exercise_name IS NOT NULL;

-- Grant select permission on the view
GRANT SELECT ON exercise_popularity_stats TO authenticated;

-- ================================================
-- Grant execute permissions
-- ================================================
GRANT EXECUTE ON FUNCTION get_top_workouts(INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION get_user_activity_summary() TO authenticated;
GRANT EXECUTE ON FUNCTION get_step_analytics() TO authenticated;
GRANT EXECUTE ON FUNCTION get_exercise_completion_stats() TO authenticated;

-- ================================================
-- DEPLOYMENT INSTRUCTIONS
-- ================================================
-- 1. Run this SQL in your Supabase SQL Editor
-- 2. These functions enable admin analytics queries
-- 3. They aggregate data across ALL users securely
-- ================================================

SELECT '✅ Admin analytics functions created successfully!' as status;

