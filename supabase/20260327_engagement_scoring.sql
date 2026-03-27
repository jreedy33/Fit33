-- ============================================================================
-- Engagement Scoring & Retention Cohorts
-- ============================================================================
-- Materialized views refreshed daily via pg_cron.
-- ============================================================================

-- 1. User engagement scores (0-100)
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_user_engagement_scores AS
WITH workout_stats AS (
  SELECT
    user_id,
    count(*) FILTER (WHERE date > NOW() - INTERVAL '7 days') AS workouts_7d,
    count(*) FILTER (WHERE date > NOW() - INTERVAL '30 days') AS workouts_30d,
    MAX(date) AS last_workout
  FROM workouts
  GROUP BY user_id
),
social_stats AS (
  SELECT
    u.id AS user_id,
    (SELECT count(*) FROM friendships f WHERE (f.requester_id = u.id OR f.addressee_id = u.id) AND f.status = 'accepted') AS friend_count,
    (SELECT count(*) FROM challenge_participants cp WHERE cp.user_id = u.id) AS challenges_joined,
    (SELECT count(*) FROM shared_workouts sw WHERE sw.sender_id = u.id) AS workouts_shared
  FROM user_profiles u
),
feature_stats AS (
  SELECT
    u.id AS user_id,
    EXISTS (SELECT 1 FROM user_active_programs uap WHERE uap.user_id = u.id) AS uses_programs,
    EXISTS (SELECT 1 FROM meal_logs ml WHERE ml.user_id = u.id AND ml.date > NOW() - INTERVAL '30 days') AS uses_nutrition,
    EXISTS (SELECT 1 FROM cardio_workouts cw WHERE cw.user_id = u.id AND cw.started_at > NOW() - INTERVAL '30 days') AS uses_cardio,
    EXISTS (SELECT 1 FROM step_tracking st WHERE st.user_id = u.id AND st.date > NOW() - INTERVAL '7 days') AS uses_steps
  FROM user_profiles u
)
SELECT
  u.id AS user_id,
  u.name,
  u.username,
  u.email,
  u.created_at,
  u.last_workout_date,
  u.current_streak,
  u.total_workouts,
  COALESCE(ws.workouts_7d, 0) AS workouts_7d,
  COALESCE(ws.workouts_30d, 0) AS workouts_30d,
  COALESCE(ss.friend_count, 0) AS friend_count,
  COALESCE(ss.challenges_joined, 0) AS challenges_joined,
  LEAST(100, (
    -- Recency (0-30): based on days since last workout
    CASE
      WHEN ws.last_workout IS NOT NULL AND ws.last_workout > NOW() - INTERVAL '1 day' THEN 30
      WHEN ws.last_workout IS NOT NULL AND ws.last_workout > NOW() - INTERVAL '3 days' THEN 25
      WHEN ws.last_workout IS NOT NULL AND ws.last_workout > NOW() - INTERVAL '7 days' THEN 18
      WHEN ws.last_workout IS NOT NULL AND ws.last_workout > NOW() - INTERVAL '14 days' THEN 10
      WHEN ws.last_workout IS NOT NULL AND ws.last_workout > NOW() - INTERVAL '30 days' THEN 5
      ELSE 0
    END
    -- Frequency (0-30): workouts per week in last 30d
    + LEAST(30, COALESCE(ws.workouts_30d, 0) * 7)
    -- Streak (0-15)
    + LEAST(15, COALESCE(u.current_streak, 0) * 3)
    -- Social (0-15)
    + LEAST(5, COALESCE(ss.friend_count, 0))
    + LEAST(5, COALESCE(ss.challenges_joined, 0) * 2)
    + LEAST(5, COALESCE(ss.workouts_shared, 0) * 2)
    -- Feature adoption (0-10)
    + (CASE WHEN COALESCE(fs.uses_programs, false) THEN 3 ELSE 0 END)
    + (CASE WHEN COALESCE(fs.uses_nutrition, false) THEN 3 ELSE 0 END)
    + (CASE WHEN COALESCE(fs.uses_cardio, false) THEN 2 ELSE 0 END)
    + (CASE WHEN COALESCE(fs.uses_steps, false) THEN 2 ELSE 0 END)
  )) AS engagement_score,
  CASE
    WHEN LEAST(100, (
      CASE WHEN ws.last_workout IS NOT NULL AND ws.last_workout > NOW() - INTERVAL '1 day' THEN 30
           WHEN ws.last_workout IS NOT NULL AND ws.last_workout > NOW() - INTERVAL '3 days' THEN 25
           WHEN ws.last_workout IS NOT NULL AND ws.last_workout > NOW() - INTERVAL '7 days' THEN 18
           WHEN ws.last_workout IS NOT NULL AND ws.last_workout > NOW() - INTERVAL '14 days' THEN 10
           WHEN ws.last_workout IS NOT NULL AND ws.last_workout > NOW() - INTERVAL '30 days' THEN 5
           ELSE 0 END
      + LEAST(30, COALESCE(ws.workouts_30d, 0) * 7)
      + LEAST(15, COALESCE(u.current_streak, 0) * 3)
      + LEAST(5, COALESCE(ss.friend_count, 0))
      + LEAST(5, COALESCE(ss.challenges_joined, 0) * 2)
      + LEAST(5, COALESCE(ss.workouts_shared, 0) * 2)
      + (CASE WHEN COALESCE(fs.uses_programs, false) THEN 3 ELSE 0 END)
      + (CASE WHEN COALESCE(fs.uses_nutrition, false) THEN 3 ELSE 0 END)
      + (CASE WHEN COALESCE(fs.uses_cardio, false) THEN 2 ELSE 0 END)
      + (CASE WHEN COALESCE(fs.uses_steps, false) THEN 2 ELSE 0 END)
    )) >= 80 THEN 'power_user'
    WHEN LEAST(100, (
      CASE WHEN ws.last_workout IS NOT NULL AND ws.last_workout > NOW() - INTERVAL '1 day' THEN 30
           WHEN ws.last_workout IS NOT NULL AND ws.last_workout > NOW() - INTERVAL '3 days' THEN 25
           WHEN ws.last_workout IS NOT NULL AND ws.last_workout > NOW() - INTERVAL '7 days' THEN 18
           WHEN ws.last_workout IS NOT NULL AND ws.last_workout > NOW() - INTERVAL '14 days' THEN 10
           WHEN ws.last_workout IS NOT NULL AND ws.last_workout > NOW() - INTERVAL '30 days' THEN 5
           ELSE 0 END
      + LEAST(30, COALESCE(ws.workouts_30d, 0) * 7)
      + LEAST(15, COALESCE(u.current_streak, 0) * 3)
      + LEAST(5, COALESCE(ss.friend_count, 0))
      + LEAST(5, COALESCE(ss.challenges_joined, 0) * 2)
      + LEAST(5, COALESCE(ss.workouts_shared, 0) * 2)
      + (CASE WHEN COALESCE(fs.uses_programs, false) THEN 3 ELSE 0 END)
      + (CASE WHEN COALESCE(fs.uses_nutrition, false) THEN 3 ELSE 0 END)
      + (CASE WHEN COALESCE(fs.uses_cardio, false) THEN 2 ELSE 0 END)
      + (CASE WHEN COALESCE(fs.uses_steps, false) THEN 2 ELSE 0 END)
    )) >= 50 THEN 'engaged'
    WHEN LEAST(100, (
      CASE WHEN ws.last_workout IS NOT NULL AND ws.last_workout > NOW() - INTERVAL '1 day' THEN 30
           WHEN ws.last_workout IS NOT NULL AND ws.last_workout > NOW() - INTERVAL '3 days' THEN 25
           WHEN ws.last_workout IS NOT NULL AND ws.last_workout > NOW() - INTERVAL '7 days' THEN 18
           WHEN ws.last_workout IS NOT NULL AND ws.last_workout > NOW() - INTERVAL '14 days' THEN 10
           WHEN ws.last_workout IS NOT NULL AND ws.last_workout > NOW() - INTERVAL '30 days' THEN 5
           ELSE 0 END
      + LEAST(30, COALESCE(ws.workouts_30d, 0) * 7)
      + LEAST(15, COALESCE(u.current_streak, 0) * 3)
      + LEAST(5, COALESCE(ss.friend_count, 0))
      + LEAST(5, COALESCE(ss.challenges_joined, 0) * 2)
      + LEAST(5, COALESCE(ss.workouts_shared, 0) * 2)
      + (CASE WHEN COALESCE(fs.uses_programs, false) THEN 3 ELSE 0 END)
      + (CASE WHEN COALESCE(fs.uses_nutrition, false) THEN 3 ELSE 0 END)
      + (CASE WHEN COALESCE(fs.uses_cardio, false) THEN 2 ELSE 0 END)
      + (CASE WHEN COALESCE(fs.uses_steps, false) THEN 2 ELSE 0 END)
    )) >= 25 THEN 'casual'
    WHEN LEAST(100, (
      CASE WHEN ws.last_workout IS NOT NULL AND ws.last_workout > NOW() - INTERVAL '1 day' THEN 30
           WHEN ws.last_workout IS NOT NULL AND ws.last_workout > NOW() - INTERVAL '3 days' THEN 25
           WHEN ws.last_workout IS NOT NULL AND ws.last_workout > NOW() - INTERVAL '7 days' THEN 18
           WHEN ws.last_workout IS NOT NULL AND ws.last_workout > NOW() - INTERVAL '14 days' THEN 10
           WHEN ws.last_workout IS NOT NULL AND ws.last_workout > NOW() - INTERVAL '30 days' THEN 5
           ELSE 0 END
      + LEAST(30, COALESCE(ws.workouts_30d, 0) * 7)
      + LEAST(15, COALESCE(u.current_streak, 0) * 3)
      + LEAST(5, COALESCE(ss.friend_count, 0))
      + LEAST(5, COALESCE(ss.challenges_joined, 0) * 2)
      + LEAST(5, COALESCE(ss.workouts_shared, 0) * 2)
      + (CASE WHEN COALESCE(fs.uses_programs, false) THEN 3 ELSE 0 END)
      + (CASE WHEN COALESCE(fs.uses_nutrition, false) THEN 3 ELSE 0 END)
      + (CASE WHEN COALESCE(fs.uses_cardio, false) THEN 2 ELSE 0 END)
      + (CASE WHEN COALESCE(fs.uses_steps, false) THEN 2 ELSE 0 END)
    )) >= 10 THEN 'at_risk'
    ELSE 'churned'
  END AS engagement_bucket
FROM user_profiles u
LEFT JOIN workout_stats ws ON ws.user_id = u.id
LEFT JOIN social_stats ss ON ss.user_id = u.id
LEFT JOIN feature_stats fs ON fs.user_id = u.id
WHERE u.has_completed_onboarding = true;

CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_engagement_user ON mv_user_engagement_scores (user_id);
CREATE INDEX IF NOT EXISTS idx_mv_engagement_bucket ON mv_user_engagement_scores (engagement_bucket);
CREATE INDEX IF NOT EXISTS idx_mv_engagement_score ON mv_user_engagement_scores (engagement_score DESC);

-- 2. Retention cohorts (weekly)
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_retention_cohorts AS
WITH cohorts AS (
  SELECT
    id AS user_id,
    date_trunc('week', created_at)::DATE AS cohort_week,
    created_at
  FROM user_profiles
  WHERE has_completed_onboarding = true
),
activity AS (
  SELECT DISTINCT user_id, date_trunc('week', date)::DATE AS active_week
  FROM workouts
)
SELECT
  c.cohort_week,
  count(DISTINCT c.user_id) AS cohort_size,
  count(DISTINCT a1.user_id) FILTER (WHERE a1.active_week = c.cohort_week + INTERVAL '1 week') AS retained_w1,
  count(DISTINCT a2.user_id) FILTER (WHERE a2.active_week = c.cohort_week + INTERVAL '2 weeks') AS retained_w2,
  count(DISTINCT a4.user_id) FILTER (WHERE a4.active_week = c.cohort_week + INTERVAL '4 weeks') AS retained_w4,
  count(DISTINCT a8.user_id) FILTER (WHERE a8.active_week = c.cohort_week + INTERVAL '8 weeks') AS retained_w8,
  count(DISTINCT a12.user_id) FILTER (WHERE a12.active_week = c.cohort_week + INTERVAL '12 weeks') AS retained_w12
FROM cohorts c
LEFT JOIN activity a1 ON a1.user_id = c.user_id AND a1.active_week = c.cohort_week + INTERVAL '1 week'
LEFT JOIN activity a2 ON a2.user_id = c.user_id AND a2.active_week = c.cohort_week + INTERVAL '2 weeks'
LEFT JOIN activity a4 ON a4.user_id = c.user_id AND a4.active_week = c.cohort_week + INTERVAL '4 weeks'
LEFT JOIN activity a8 ON a8.user_id = c.user_id AND a8.active_week = c.cohort_week + INTERVAL '8 weeks'
LEFT JOIN activity a12 ON a12.user_id = c.user_id AND a12.active_week = c.cohort_week + INTERVAL '12 weeks'
GROUP BY c.cohort_week
ORDER BY c.cohort_week DESC;

CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_cohorts_week ON mv_retention_cohorts (cohort_week);

-- 3. Onboarding funnel
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_onboarding_funnel AS
SELECT
  count(*) AS total_signups,
  count(*) FILTER (WHERE has_completed_onboarding = true) AS completed_onboarding,
  count(*) FILTER (WHERE total_workouts >= 1) AS first_workout,
  count(*) FILTER (WHERE total_workouts >= 3) AS third_workout,
  count(*) FILTER (WHERE total_workouts >= 5) AS fifth_workout,
  count(*) FILTER (WHERE last_workout_date > created_at + INTERVAL '7 days') AS active_week_1,
  count(*) FILTER (WHERE last_workout_date > created_at + INTERVAL '30 days') AS active_month_1
FROM user_profiles;

-- 4. Refresh function + cron job
CREATE OR REPLACE FUNCTION refresh_engagement_data()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  REFRESH MATERIALIZED VIEW CONCURRENTLY mv_user_engagement_scores;
  REFRESH MATERIALIZED VIEW CONCURRENTLY mv_retention_cohorts;
  REFRESH MATERIALIZED VIEW mv_onboarding_funnel;
  RAISE NOTICE 'Engagement data refreshed at %', NOW();
END;
$$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'refresh-engagement-data') THEN
    PERFORM cron.unschedule('refresh-engagement-data');
  END IF;
END $$;

SELECT cron.schedule(
  'refresh-engagement-data',
  '0 4 * * *',
  $$SELECT refresh_engagement_data();$$
);

DO $$ BEGIN
  RAISE NOTICE 'Engagement scoring system created (3 materialized views + daily refresh)';
END $$;
