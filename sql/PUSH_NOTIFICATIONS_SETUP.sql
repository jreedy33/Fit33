-- ============================================================================
-- PUSH NOTIFICATIONS SETUP FOR SHARED WORKOUTS
-- ============================================================================
-- This SQL sets up:
-- 1. Table to store user device tokens
-- 2. Database trigger to notify when a workout is shared
-- 3. Edge function to send the actual push notification
-- ============================================================================

-- ============================================================================
-- STEP 1: Create table to store user device tokens
-- ============================================================================

CREATE TABLE IF NOT EXISTS user_push_tokens (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    device_token TEXT NOT NULL,
    platform TEXT NOT NULL DEFAULT 'ios', -- 'ios' or 'android'
    app_version TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id) -- One token per user (most recent device)
);

-- Enable RLS
ALTER TABLE user_push_tokens ENABLE ROW LEVEL SECURITY;

-- Users can only manage their own tokens
CREATE POLICY "Users can insert their own token" ON user_push_tokens
    FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own token" ON user_push_tokens
    FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own token" ON user_push_tokens
    FOR DELETE USING (auth.uid() = user_id);

-- Service role can read all tokens (for sending notifications)
CREATE POLICY "Service can read all tokens" ON user_push_tokens
    FOR SELECT USING (true);

-- Index for fast lookups
CREATE INDEX IF NOT EXISTS idx_push_tokens_user_id ON user_push_tokens(user_id);

-- ============================================================================
-- STEP 2: Create a queue table for pending push notifications
-- ============================================================================

CREATE TABLE IF NOT EXISTS push_notification_queue (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    recipient_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    notification_type TEXT NOT NULL, -- 'shared_workout', 'friend_request', etc.
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    data JSONB DEFAULT '{}', -- Additional data like workout_id
    status TEXT DEFAULT 'pending', -- 'pending', 'sent', 'failed'
    created_at TIMESTAMPTZ DEFAULT NOW(),
    sent_at TIMESTAMPTZ,
    error_message TEXT
);

-- Enable RLS
ALTER TABLE push_notification_queue ENABLE ROW LEVEL SECURITY;

-- Only service role should access this table
CREATE POLICY "Service role only" ON push_notification_queue
    FOR ALL USING (auth.role() = 'service_role');

-- Index for processing pending notifications
CREATE INDEX IF NOT EXISTS idx_push_queue_status ON push_notification_queue(status) WHERE status = 'pending';

-- ============================================================================
-- STEP 3: Create function to queue a notification when workout is shared
-- ============================================================================

CREATE OR REPLACE FUNCTION queue_shared_workout_notification()
RETURNS TRIGGER AS $$
DECLARE
    sender_name TEXT;
    workout_name TEXT;
BEGIN
    -- Get sender name from user_profiles (cast both sides to text for safe comparison)
    SELECT COALESCE(name, 'Someone') INTO sender_name
    FROM user_profiles
    WHERE id::text = NEW.sender_id::text;
    
    -- Get workout name
    workout_name := COALESCE(NEW.workout_name, 'a workout');
    
    -- Insert into notification queue
    INSERT INTO push_notification_queue (
        recipient_user_id,
        notification_type,
        title,
        body,
        data
    ) VALUES (
        NEW.recipient_id,
        'shared_workout',
        sender_name || ' sent you a workout! 💪',
        'Tap to check out "' || workout_name || '" and start training.',
        jsonb_build_object(
            'workout_id', NEW.id::text,
            'sender_name', sender_name,
            'workout_name', workout_name
        )
    );
    
    -- Trigger the edge function via pg_notify (Supabase will pick this up)
    PERFORM pg_notify('push_notification', json_build_object(
        'queue_id', (SELECT id FROM push_notification_queue ORDER BY created_at DESC LIMIT 1)::text
    )::text);
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- STEP 4: Create trigger on shared_workouts table
-- ============================================================================

DROP TRIGGER IF EXISTS on_workout_shared ON shared_workouts;

CREATE TRIGGER on_workout_shared
    AFTER INSERT ON shared_workouts
    FOR EACH ROW
    EXECUTE FUNCTION queue_shared_workout_notification();

-- ============================================================================
-- STEP 5: Grant necessary permissions
-- ============================================================================

GRANT USAGE ON SCHEMA public TO authenticated;
GRANT ALL ON user_push_tokens TO authenticated;
GRANT SELECT ON push_notification_queue TO service_role;
GRANT INSERT, UPDATE ON push_notification_queue TO service_role;

-- ============================================================================
-- VERIFICATION: Check the setup
-- ============================================================================

-- Run this to verify tables exist:
-- SELECT table_name FROM information_schema.tables WHERE table_name IN ('user_push_tokens', 'push_notification_queue');

-- ============================================================================
-- EDGE FUNCTION SETUP (Deploy separately in Supabase Dashboard)
-- ============================================================================
-- 
-- Create a new Edge Function called "send-push-notification" with this code:
--
-- import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
-- import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
-- 
-- const APNS_KEY_ID = Deno.env.get('APNS_KEY_ID')!
-- const APNS_TEAM_ID = Deno.env.get('APNS_TEAM_ID')!
-- const APNS_PRIVATE_KEY = Deno.env.get('APNS_PRIVATE_KEY')!
-- const APNS_BUNDLE_ID = Deno.env.get('APNS_BUNDLE_ID')! // e.g., "com.yourapp.fit33"
-- 
-- serve(async (req) => {
--   const supabase = createClient(
--     Deno.env.get('SUPABASE_URL')!,
--     Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
--   )
-- 
--   // Get pending notifications
--   const { data: pendingNotifications, error: fetchError } = await supabase
--     .from('push_notification_queue')
--     .select(`
--       id,
--       recipient_user_id,
--       title,
--       body,
--       data,
--       user_push_tokens!inner(device_token)
--     `)
--     .eq('status', 'pending')
--     .limit(100)
-- 
--   if (fetchError) {
--     return new Response(JSON.stringify({ error: fetchError.message }), { status: 500 })
--   }
-- 
--   // Process each notification
--   for (const notification of pendingNotifications || []) {
--     try {
--       const deviceToken = notification.user_push_tokens?.device_token
--       if (!deviceToken) continue
-- 
--       // Send to APNs
--       const apnsResponse = await sendAPNS(deviceToken, {
--         title: notification.title,
--         body: notification.body,
--         data: notification.data
--       })
-- 
--       // Update status
--       await supabase
--         .from('push_notification_queue')
--         .update({ status: 'sent', sent_at: new Date().toISOString() })
--         .eq('id', notification.id)
-- 
--     } catch (error) {
--       await supabase
--         .from('push_notification_queue')
--         .update({ status: 'failed', error_message: error.message })
--         .eq('id', notification.id)
--     }
--   }
-- 
--   return new Response(JSON.stringify({ processed: pendingNotifications?.length || 0 }))
-- })
-- 
-- async function sendAPNS(deviceToken: string, payload: any) {
--   // Generate JWT for APNs authentication
--   const jwt = await generateAPNSJWT()
--   
--   const response = await fetch(
--     `https://api.push.apple.com/3/device/${deviceToken}`,
--     {
--       method: 'POST',
--       headers: {
--         'authorization': `bearer ${jwt}`,
--         'apns-topic': APNS_BUNDLE_ID,
--         'apns-push-type': 'alert',
--         'apns-priority': '10',
--       },
--       body: JSON.stringify({
--         aps: {
--           alert: {
--             title: payload.title,
--             body: payload.body,
--           },
--           sound: 'default',
--           badge: 1,
--         },
--         ...payload.data
--       })
--     }
--   )
--   
--   if (!response.ok) {
--     throw new Error(`APNs error: ${response.status}`)
--   }
--   
--   return response
-- }
-- 
-- ============================================================================
-- ALTERNATIVE: Use Supabase Realtime to trigger from client
-- ============================================================================
-- If Edge Functions are complex, you can use Supabase Realtime on the client
-- to listen for new shared_workouts and show local notifications.
-- This is simpler but only works when the app is running.
-- ============================================================================
