-- ============================================================================
-- Push Campaign Management
-- ============================================================================
-- Supports draft/scheduled/sent campaigns with segment targeting.
-- ============================================================================

CREATE TABLE IF NOT EXISTS push_campaigns (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  notification_type TEXT NOT NULL DEFAULT 'campaign',
  segment TEXT NOT NULL CHECK (segment IN ('all', 'at_risk', 'inactive_7d', 'inactive_30d', 'new_users', 'power_users', 'custom')),
  custom_filter JSONB,
  data JSONB DEFAULT '{}',
  scheduled_at TIMESTAMPTZ,
  status TEXT NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft', 'scheduled', 'sending', 'sent', 'cancelled')),
  sent_count INT NOT NULL DEFAULT 0,
  failed_count INT NOT NULL DEFAULT 0,
  created_by TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  sent_at TIMESTAMPTZ
);

ALTER TABLE push_campaigns ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_push_campaigns_status ON push_campaigns (status, created_at DESC);

-- Execute a campaign: resolve segment → insert into push_notification_queue
CREATE OR REPLACE FUNCTION execute_push_campaign(p_campaign_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_campaign RECORD;
  v_count INT := 0;
  v_user RECORD;
BEGIN
  SELECT * INTO v_campaign FROM push_campaigns WHERE id = p_campaign_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Campaign not found');
  END IF;

  IF v_campaign.status != 'draft' AND v_campaign.status != 'scheduled' THEN
    RETURN jsonb_build_object('error', 'Campaign already sent or cancelled');
  END IF;

  UPDATE push_campaigns SET status = 'sending' WHERE id = p_campaign_id;

  FOR v_user IN
    SELECT up.id AS user_id
    FROM user_profiles up
    WHERE up.has_completed_onboarding = true
      AND EXISTS (SELECT 1 FROM user_push_tokens upt WHERE upt.user_id = up.id AND upt.is_valid = true)
      AND CASE v_campaign.segment
        WHEN 'all' THEN true
        WHEN 'inactive_7d' THEN up.last_workout_date < NOW() - INTERVAL '7 days' OR up.last_workout_date IS NULL
        WHEN 'inactive_30d' THEN up.last_workout_date < NOW() - INTERVAL '30 days' OR up.last_workout_date IS NULL
        WHEN 'new_users' THEN up.created_at > NOW() - INTERVAL '7 days'
        WHEN 'power_users' THEN up.total_workouts >= 50
        WHEN 'at_risk' THEN up.last_workout_date < NOW() - INTERVAL '14 days' AND up.total_workouts > 3
        ELSE true
      END
  LOOP
    INSERT INTO push_notification_queue (recipient_user_id, notification_type, title, body, data, status, created_at)
    VALUES (v_user.user_id, v_campaign.notification_type, v_campaign.title, v_campaign.body, v_campaign.data, 'pending', NOW());
    v_count := v_count + 1;
  END LOOP;

  UPDATE push_campaigns
  SET status = 'sent', sent_count = v_count, sent_at = NOW()
  WHERE id = p_campaign_id;

  RETURN jsonb_build_object('success', true, 'sent_count', v_count);
END;
$$;

-- Estimate campaign reach
CREATE OR REPLACE FUNCTION estimate_campaign_reach(p_segment TEXT)
RETURNS INT
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  SELECT count(*)::INT
  FROM user_profiles up
  WHERE up.has_completed_onboarding = true
    AND EXISTS (SELECT 1 FROM user_push_tokens upt WHERE upt.user_id = up.id AND upt.is_valid = true)
    AND CASE p_segment
      WHEN 'all' THEN true
      WHEN 'inactive_7d' THEN up.last_workout_date < NOW() - INTERVAL '7 days' OR up.last_workout_date IS NULL
      WHEN 'inactive_30d' THEN up.last_workout_date < NOW() - INTERVAL '30 days' OR up.last_workout_date IS NULL
      WHEN 'new_users' THEN up.created_at > NOW() - INTERVAL '7 days'
      WHEN 'power_users' THEN up.total_workouts >= 50
      WHEN 'at_risk' THEN up.last_workout_date < NOW() - INTERVAL '14 days' AND up.total_workouts > 3
      ELSE true
    END;
$$;

DO $$ BEGIN
  RAISE NOTICE 'Push campaign system created (push_campaigns table, execute + estimate RPCs)';
END $$;
