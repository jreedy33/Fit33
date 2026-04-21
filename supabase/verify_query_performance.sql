-- =====================================================================
-- Sprint 5 DB-5: Verify query-performance indexes applied in production.
-- =====================================================================
--
-- Context:
--   The "optimize_query_performance.sql" migration referenced historically
--   in MASTER_TODO.md never landed as a single file — the indexes ship
--   across several migrations (fix_data_relationships.sql,
--   create_friend_rpc_functions.sql, community_friends_gating.sql, the
--   dated 20260320+ schema fixes, etc.). This verifier asserts the hot
--   indexes are present on production so regressions show up as "MISSING"
--   rows instead of going silent.
--
-- Usage:
--   psql "$SUPABASE_DB_URL" -f supabase/verify_query_performance.sql
--
-- Output:
--   A single result set `verify_query_performance_report` with one row
--   per expected index. status = 'OK' or 'MISSING'.
--   Anything MISSING is an actionable ticket.
--
-- Notes:
--   - Idempotent + read-only. Safe to run any time, including against
--     read replicas.
--   - When new hot-path indexes are added in a future migration, append a
--     row to `expected_indexes` below.
-- =====================================================================

WITH expected_indexes(schema_name, table_name, index_name) AS (
    VALUES
        -- Challenge surfaces (fix_data_relationships.sql)
        ('public', 'challenge_participants',      'idx_challenge_participants_challenge_user'),
        ('public', 'challenge_participants',      'idx_challenge_participants_user_status'),
        ('public', 'challenge_daily_progress',    'idx_challenge_daily_progress_lookup'),
        ('public', 'group_challenges',            'idx_group_challenges_status'),
        ('public', 'group_challenges',            'idx_group_challenges_created_at'),

        -- Social / friendships (fix_data_relationships.sql, community_friends_gating.sql, create_friend_rpc_functions.sql)
        ('public', 'friendships',                 'idx_friendships_requester_status'),
        ('public', 'friendships',                 'idx_friendships_addressee_status'),
        ('public', 'friendships',                 'idx_friendships_status'),
        ('public', 'friendships',                 'idx_friendships_requester_accepted'),
        ('public', 'friendships',                 'idx_friendships_addressee_accepted'),
        ('public', 'friendships',                 'idx_friendships_accepted_requester'),
        ('public', 'friendships',                 'idx_friendships_accepted_addressee'),
        ('public', 'shared_workouts',             'idx_shared_workouts_recipient_status'),
        ('public', 'shared_workouts',             'idx_shared_workouts_recipient_id'),
        ('public', 'shared_workouts',             'idx_shared_workouts_sender_id'),
        ('public', 'shared_workouts',             'idx_shared_workouts_created_at'),
        ('public', 'shared_workouts',             'idx_shared_workouts_hidden'),

        -- Daily rollups (fix_data_relationships.sql)
        ('public', 'daily_activity_summary',      'idx_daily_activity_user_date'),
        ('public', 'daily_summaries',             'idx_daily_summaries_user_date'),
        ('public', 'weight_logs',                 'idx_weight_logs_user_date'),
        ('public', 'step_tracking',               'idx_step_tracking_user_date'),
        ('public', 'meal_logs',                   'idx_meal_logs_user_date'),
        ('public', 'cardio_workouts',             'idx_cardio_workouts_user_date'),

        -- Cardio origin filter (20260417_cardio_workouts_origin_app.sql)
        ('public', 'cardio_workouts',             'idx_cardio_workouts_user_origin_source'),

        -- Push / delivery (20260326_push_notification_reliability.sql)
        ('public', 'push_notification_queue',     'idx_push_queue_status'),
        ('public', 'push_notification_delivery_log', 'idx_delivery_log_user_created'),
        ('public', 'push_notification_delivery_log', 'idx_delivery_log_notification'),
        ('public', 'push_notification_delivery_log', 'idx_delivery_log_created'),

        -- Moderation (20260327_moderation_system.sql + 20260328_content_moderation.sql)
        ('public', 'user_reports',                'idx_user_reports_status'),
        ('public', 'user_reports',                'idx_user_reports_reported'),
        ('public', 'user_reports',                'idx_user_reports_reporter'),
        ('public', 'user_suspensions',            'idx_user_suspensions_user'),
        ('public', 'user_suspensions',            'idx_user_suspensions_active'),
        ('public', 'private_challenge_chat',      'idx_pcc_hidden'),
        ('public', 'challenge_reactions',         'idx_reactions_hidden'),
        ('public', 'friend_activity_feed',        'idx_activity_feed_hidden'),

        -- Workout history (20260324_workout_history_calories.sql)
        ('public', 'workout_history',             'idx_workout_history_calories'),

        -- Community realtime (20260324_community_realtime_optimization.sql)
        ('public', 'community_challenge_daily_progress', 'idx_ccdp_updated_at'),

        -- Insights + subscriptions (20260320_smart_insights_schema.sql)
        ('public', 'subscription_events',         'idx_subscription_events_user_id'),
        ('public', 'subscription_events',         'idx_subscription_events_event_type'),
        ('public', 'subscription_events',         'idx_subscription_events_created_at'),
        ('public', 'ai_insights',                 'idx_ai_insights_generated_at'),

        -- Oura integration (20260328_oura_integration.sql)
        ('public', 'oura_readiness_data',         'idx_oura_readiness_user_id'),
        ('public', 'oura_readiness_data',         'idx_oura_readiness_date'),

        -- Engagement MV (20260327_engagement_scoring.sql)
        ('public', 'mv_user_engagement_scores',   'idx_mv_engagement_bucket'),
        ('public', 'mv_user_engagement_scores',   'idx_mv_engagement_score'),

        -- Community friend gating (community_friends_gating.sql)
        ('public', 'community_challenge_participants', 'idx_ccp_active_user'),

        -- Admin audit (20260327_enhance_audit_log.sql)
        ('public', 'admin_audit_log',             'idx_audit_log_created'),

        -- Contacts (20260321_schema_fixes_2.sql)
        ('public', 'user_synced_contacts',        'idx_user_synced_contacts_matched'),

        -- Silent-push wake log (20260420_challenge_opponent_wake.sql)
        ('public', 'silent_push_wake_log',        'idx_silent_push_wake_log_user_sent')
),
present_indexes AS (
    SELECT schemaname AS schema_name,
           tablename  AS table_name,
           indexname  AS index_name
    FROM pg_indexes
),
report AS (
    SELECT e.schema_name,
           e.table_name,
           e.index_name,
           CASE
               WHEN p.index_name IS NOT NULL THEN 'OK'
               ELSE 'MISSING'
           END AS status
    FROM expected_indexes e
    LEFT JOIN present_indexes p
           ON p.schema_name = e.schema_name
          AND p.table_name  = e.table_name
          AND p.index_name  = e.index_name
)
SELECT schema_name,
       table_name,
       index_name,
       status
FROM report
ORDER BY status DESC,   -- MISSING sorts above OK alphabetically
         table_name,
         index_name;

-- End of file.
--
-- CI usage:
--   psql ... -f supabase/verify_query_performance.sql | grep MISSING
--   (If `grep` returns any rows → fail the deploy gate.)
