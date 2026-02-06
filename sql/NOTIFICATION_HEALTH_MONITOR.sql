-- =====================================================================
-- 🏥 NOTIFICATION HEALTH MONITORING SYSTEM
-- =====================================================================
-- This creates functions to monitor notification health that can be 
-- called from the Swift app or admin dashboard.
-- =====================================================================

-- =====================================================================
-- FUNCTION 1: Get notification system health status
-- Returns a single row with all health metrics
-- =====================================================================

CREATE OR REPLACE FUNCTION get_notification_health()
RETURNS TABLE (
    overall_status TEXT,
    pending_count INTEGER,
    failed_24h INTEGER,
    sent_24h INTEGER,
    success_rate_24h NUMERIC,
    valid_tokens INTEGER,
    stale_tokens INTEGER,
    cron_job_active BOOLEAN,
    last_cron_run TIMESTAMPTZ,
    oldest_pending TIMESTAMPTZ,
    recommendations TEXT[]
) AS $$
DECLARE
    v_pending INTEGER;
    v_failed INTEGER;
    v_sent INTEGER;
    v_valid_tokens INTEGER;
    v_stale_tokens INTEGER;
    v_cron_active BOOLEAN;
    v_last_cron TIMESTAMPTZ;
    v_oldest_pending TIMESTAMPTZ;
    v_recommendations TEXT[] := ARRAY[]::TEXT[];
    v_status TEXT := '🟢 HEALTHY';
BEGIN
    -- Count pending notifications
    SELECT COUNT(*) INTO v_pending
    FROM push_notification_queue 
    WHERE status = 'pending';
    
    -- Count failed in last 24h
    SELECT COUNT(*) INTO v_failed
    FROM push_notification_queue 
    WHERE status = 'failed' 
    AND created_at > NOW() - INTERVAL '24 hours';
    
    -- Count sent in last 24h
    SELECT COUNT(*) INTO v_sent
    FROM push_notification_queue 
    WHERE status = 'sent' 
    AND created_at > NOW() - INTERVAL '24 hours';
    
    -- Count valid tokens
    SELECT COUNT(*) INTO v_valid_tokens
    FROM user_push_tokens 
    WHERE is_valid = true;
    
    -- Count stale tokens (not updated in 30 days)
    SELECT COUNT(*) INTO v_stale_tokens
    FROM user_push_tokens 
    WHERE updated_at < NOW() - INTERVAL '30 days';
    
    -- Check cron job
    SELECT active, 
           (SELECT MAX(end_time) FROM cron.job_run_details WHERE jobid = cron.job.jobid)
    INTO v_cron_active, v_last_cron
    FROM cron.job 
    WHERE jobname = 'process-push-notifications';
    
    -- Get oldest pending notification
    SELECT MIN(created_at) INTO v_oldest_pending
    FROM push_notification_queue 
    WHERE status = 'pending';
    
    -- Determine status and recommendations
    IF v_pending > 100 THEN
        v_status := '🔴 CRITICAL';
        v_recommendations := array_append(v_recommendations, 'Queue backup: ' || v_pending || ' pending notifications');
    ELSIF v_pending > 50 THEN
        v_status := '🟡 WARNING';
        v_recommendations := array_append(v_recommendations, 'Queue growing: ' || v_pending || ' pending');
    END IF;
    
    IF v_failed > 10 THEN
        v_status := CASE WHEN v_status = '🟢 HEALTHY' THEN '🟡 WARNING' ELSE v_status END;
        v_recommendations := array_append(v_recommendations, 'High failure rate: ' || v_failed || ' failed in 24h');
    END IF;
    
    IF NOT COALESCE(v_cron_active, false) THEN
        v_status := '🔴 CRITICAL';
        v_recommendations := array_append(v_recommendations, 'Cron job not active - notifications will not be sent');
    END IF;
    
    IF v_last_cron IS NOT NULL AND v_last_cron < NOW() - INTERVAL '5 minutes' THEN
        v_status := CASE WHEN v_status = '🟢 HEALTHY' THEN '🟡 WARNING' ELSE v_status END;
        v_recommendations := array_append(v_recommendations, 'Cron job last ran ' || EXTRACT(EPOCH FROM (NOW() - v_last_cron))::INTEGER || ' seconds ago');
    END IF;
    
    IF v_valid_tokens = 0 THEN
        v_status := '🔴 CRITICAL';
        v_recommendations := array_append(v_recommendations, 'No valid device tokens - no one can receive push notifications');
    END IF;
    
    IF v_oldest_pending IS NOT NULL AND v_oldest_pending < NOW() - INTERVAL '10 minutes' THEN
        v_status := CASE WHEN v_status = '🟢 HEALTHY' THEN '🟡 WARNING' ELSE v_status END;
        v_recommendations := array_append(v_recommendations, 'Oldest pending notification is ' || EXTRACT(EPOCH FROM (NOW() - v_oldest_pending))::INTEGER || ' seconds old');
    END IF;
    
    IF array_length(v_recommendations, 1) IS NULL THEN
        v_recommendations := ARRAY['System operating normally']::TEXT[];
    END IF;
    
    RETURN QUERY SELECT 
        v_status,
        v_pending,
        v_failed,
        v_sent,
        CASE WHEN (v_sent + v_failed) > 0 
             THEN ROUND(100.0 * v_sent / (v_sent + v_failed), 1) 
             ELSE 100.0 
        END,
        v_valid_tokens,
        v_stale_tokens,
        COALESCE(v_cron_active, false),
        v_last_cron,
        v_oldest_pending,
        v_recommendations;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_notification_health() TO authenticated;

-- =====================================================================
-- FUNCTION 2: Get failed notifications for a user
-- For debugging why a specific user isn't receiving notifications
-- =====================================================================

CREATE OR REPLACE FUNCTION get_user_notification_status(target_user_id UUID)
RETURNS TABLE (
    has_valid_token BOOLEAN,
    token_updated_at TIMESTAMPTZ,
    recent_notifications INTEGER,
    recent_sent INTEGER,
    recent_failed INTEGER,
    recent_pending INTEGER,
    last_sent_at TIMESTAMPTZ,
    last_failure_reason TEXT,
    recommendations TEXT[]
) AS $$
DECLARE
    v_has_token BOOLEAN;
    v_token_updated TIMESTAMPTZ;
    v_recent INTEGER;
    v_sent INTEGER;
    v_failed INTEGER;
    v_pending INTEGER;
    v_last_sent TIMESTAMPTZ;
    v_last_error TEXT;
    v_recommendations TEXT[] := ARRAY[]::TEXT[];
BEGIN
    -- Check for valid token
    SELECT is_valid, updated_at 
    INTO v_has_token, v_token_updated
    FROM user_push_tokens 
    WHERE user_id = target_user_id;
    
    IF NOT FOUND THEN
        v_has_token := false;
        v_recommendations := array_append(v_recommendations, '❌ No device token registered - user has never enabled push notifications');
    ELSIF NOT v_has_token THEN
        v_recommendations := array_append(v_recommendations, '❌ Device token is marked invalid - token may be expired or device unregistered');
    ELSIF v_token_updated < NOW() - INTERVAL '30 days' THEN
        v_recommendations := array_append(v_recommendations, '⚠️ Device token is stale (' || EXTRACT(DAY FROM (NOW() - v_token_updated))::INTEGER || ' days old) - user should open app to refresh');
    END IF;
    
    -- Count recent notifications
    SELECT 
        COUNT(*),
        SUM(CASE WHEN status = 'sent' THEN 1 ELSE 0 END),
        SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END),
        SUM(CASE WHEN status = 'pending' THEN 1 ELSE 0 END)
    INTO v_recent, v_sent, v_failed, v_pending
    FROM push_notification_queue
    WHERE recipient_user_id = target_user_id
    AND created_at > NOW() - INTERVAL '7 days';
    
    -- Get last sent time
    SELECT MAX(sent_at) INTO v_last_sent
    FROM push_notification_queue
    WHERE recipient_user_id = target_user_id
    AND status = 'sent';
    
    -- Get last failure reason
    SELECT error_message INTO v_last_error
    FROM push_notification_queue
    WHERE recipient_user_id = target_user_id
    AND status = 'failed'
    ORDER BY created_at DESC
    LIMIT 1;
    
    IF v_last_error IS NOT NULL THEN
        IF v_last_error LIKE '%BadDeviceToken%' THEN
            v_recommendations := array_append(v_recommendations, '❌ APNs rejected token - device may have been reset or app reinstalled');
        ELSIF v_last_error LIKE '%Unregistered%' THEN
            v_recommendations := array_append(v_recommendations, '❌ Device unregistered from APNs - user may have disabled notifications in iOS Settings');
        ELSIF v_last_error LIKE '%Network%' THEN
            v_recommendations := array_append(v_recommendations, '⚠️ Network errors - transient issue, should retry automatically');
        ELSE
            v_recommendations := array_append(v_recommendations, '⚠️ Last error: ' || v_last_error);
        END IF;
    END IF;
    
    IF v_pending > 10 THEN
        v_recommendations := array_append(v_recommendations, '⚠️ ' || v_pending || ' notifications pending - processing may be backed up');
    END IF;
    
    IF array_length(v_recommendations, 1) IS NULL THEN
        v_recommendations := ARRAY['✅ User notification setup looks healthy']::TEXT[];
    END IF;
    
    RETURN QUERY SELECT 
        COALESCE(v_has_token, false),
        v_token_updated,
        COALESCE(v_recent, 0),
        COALESCE(v_sent, 0),
        COALESCE(v_failed, 0),
        COALESCE(v_pending, 0),
        v_last_sent,
        v_last_error,
        v_recommendations;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_user_notification_status(UUID) TO authenticated;

-- =====================================================================
-- FUNCTION 3: Force retry failed notifications
-- Useful for admin to retry failed notifications after fixing issues
-- =====================================================================

CREATE OR REPLACE FUNCTION retry_failed_notifications(max_age_hours INTEGER DEFAULT 24)
RETURNS INTEGER AS $$
DECLARE
    v_count INTEGER;
BEGIN
    UPDATE push_notification_queue
    SET 
        status = 'pending',
        retry_count = COALESCE(retry_count, 0) + 1,
        error_message = 'Manual retry at ' || NOW()::TEXT,
        next_retry_at = NULL
    WHERE status = 'failed'
    AND created_at > NOW() - (max_age_hours || ' hours')::INTERVAL
    AND retry_count < 5;  -- Don't retry forever
    
    GET DIAGNOSTICS v_count = ROW_COUNT;
    
    RETURN v_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION retry_failed_notifications(INTEGER) TO service_role;

-- =====================================================================
-- FUNCTION 4: Clean up old notifications
-- Should be called by cron job daily
-- =====================================================================

CREATE OR REPLACE FUNCTION cleanup_old_notifications()
RETURNS INTEGER AS $$
DECLARE
    v_count INTEGER;
BEGIN
    -- Delete sent notifications older than 7 days
    DELETE FROM push_notification_queue
    WHERE status = 'sent' 
    AND sent_at < NOW() - INTERVAL '7 days';
    
    GET DIAGNOSTICS v_count = ROW_COUNT;
    
    -- Delete failed notifications older than 30 days
    DELETE FROM push_notification_queue
    WHERE status = 'failed' 
    AND created_at < NOW() - INTERVAL '30 days';
    
    -- Delete old app notifications
    DELETE FROM app_notifications
    WHERE created_at < NOW() - INTERVAL '90 days'
    AND is_read = true;
    
    RETURN v_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================================================
-- VERIFICATION
-- =====================================================================

SELECT '═══════════════════════════════════════════════════════════════' AS separator;
SELECT '✅ NOTIFICATION HEALTH MONITORING SYSTEM INSTALLED' AS status;
SELECT '═══════════════════════════════════════════════════════════════' AS separator;

-- Test the health function
SELECT * FROM get_notification_health();

-- Example: Check a specific user's notification status
-- SELECT * FROM get_user_notification_status('e31f9d3b-a43e-44a8-a31f-6826e9d17e1a');
