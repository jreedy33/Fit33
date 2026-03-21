-- ============================================================================
-- SMART INSIGHTS ENHANCEMENT: Phase 1 Schema Changes
-- ============================================================================
-- Adds new columns and tables to capture data for smarter insights:
--   1.1 Workout completion rate tracking
--   1.2 Skip reason already exists (swap_reason in exercise_swap_analytics)
--   1.3 Push notification engagement tracking
--   1.4 Referral source tracking
--   1.5 Subscription events table
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1.1 Workout Completion Rate
-- ============================================================================

ALTER TABLE workout_history
  ADD COLUMN IF NOT EXISTS completion_rate NUMERIC DEFAULT 1.0,
  ADD COLUMN IF NOT EXISTS total_sets_planned INT DEFAULT 0,
  ADD COLUMN IF NOT EXISTS total_sets_completed INT DEFAULT 0;

DO $$ BEGIN
  RAISE NOTICE '✅ 1.1 Added completion_rate, total_sets_planned, total_sets_completed to workout_history';
END $$;

-- ============================================================================
-- 1.3 Push Notification Engagement
-- ============================================================================

ALTER TABLE push_notification_queue
  ADD COLUMN IF NOT EXISTS opened_at TIMESTAMPTZ;

DO $$ BEGIN
  RAISE NOTICE '✅ 1.3 Added opened_at to push_notification_queue';
END $$;

-- ============================================================================
-- 1.4 Referral Source Tracking
-- ============================================================================

ALTER TABLE user_profiles
  ADD COLUMN IF NOT EXISTS referral_source TEXT;

DO $$ BEGIN
  RAISE NOTICE '✅ 1.4 Added referral_source to user_profiles';
END $$;

-- ============================================================================
-- 1.5 Subscription Events
-- ============================================================================

CREATE TABLE IF NOT EXISTS subscription_events (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  event_type TEXT NOT NULL,
  product_id TEXT,
  price_cents INT,
  currency TEXT DEFAULT 'USD',
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_subscription_events_user_id ON subscription_events(user_id);
CREATE INDEX IF NOT EXISTS idx_subscription_events_event_type ON subscription_events(event_type);
CREATE INDEX IF NOT EXISTS idx_subscription_events_created_at ON subscription_events(created_at);

ALTER TABLE subscription_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own subscription events" ON subscription_events;
CREATE POLICY "Users can view own subscription events"
  ON subscription_events FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own subscription events" ON subscription_events;
CREATE POLICY "Users can insert own subscription events"
  ON subscription_events FOR INSERT
  WITH CHECK (auth.uid() = user_id);

DO $$ BEGIN
  RAISE NOTICE '✅ 1.5 Created subscription_events table with RLS and indexes';
END $$;

-- ============================================================================
-- SUMMARY
-- ============================================================================

DO $$ BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
  RAISE NOTICE 'SMART INSIGHTS SCHEMA CHANGES COMPLETE';
  RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
  RAISE NOTICE '  1.1 workout_history: +completion_rate, +total_sets_planned, +total_sets_completed';
  RAISE NOTICE '  1.2 exercise_swap_analytics: swap_reason already exists';
  RAISE NOTICE '  1.3 push_notification_queue: +opened_at';
  RAISE NOTICE '  1.4 user_profiles: +referral_source';
  RAISE NOTICE '  1.5 subscription_events: new table with RLS';
  RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
END $$;

COMMIT;
