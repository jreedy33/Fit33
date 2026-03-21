-- ============================================================================
-- NOTIFICATION PREFERENCES MIGRATION
-- Date: 2026-03-21
-- Source: Notification System Audit — server-side preference sync
-- ============================================================================
-- Allows the send-push-notification edge function to respect user toggles
-- and quiet hours before delivering push notifications.
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS user_notification_preferences (
    user_id UUID PRIMARY KEY REFERENCES user_profiles(id) ON DELETE CASCADE,
    master_enabled BOOLEAN NOT NULL DEFAULT true,
    disabled_types TEXT[] NOT NULL DEFAULT '{}',
    quiet_hours_enabled BOOLEAN NOT NULL DEFAULT false,
    quiet_hours_start TIME,
    quiet_hours_end TIME,
    timezone TEXT DEFAULT 'America/New_York',
    daily_cap INTEGER NOT NULL DEFAULT 8,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE user_notification_preferences ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own notification preferences"
    ON user_notification_preferences FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own notification preferences"
    ON user_notification_preferences FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own notification preferences"
    ON user_notification_preferences FOR UPDATE
    USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own notification preferences"
    ON user_notification_preferences FOR DELETE
    USING (auth.uid() = user_id);

COMMIT;
