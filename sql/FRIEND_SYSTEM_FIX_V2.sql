-- =====================================================
-- FRIEND SYSTEM FIX V2 - Complete rebuild
-- Run this in Supabase SQL Editor
-- =====================================================

-- Step 1: Drop ALL versions of send_workout_to_friend
DROP FUNCTION IF EXISTS send_workout_to_friend(text, text, text, text, text, integer, text);
DROP FUNCTION IF EXISTS send_workout_to_friend(uuid, text, jsonb, text, text, integer, text);
DROP FUNCTION IF EXISTS send_workout_to_friend(text, text, jsonb, text, text, integer, text);

-- Step 2: Drop get_received_workouts function
DROP FUNCTION IF EXISTS get_received_workouts();

-- Step 3: Drop the existing shared_workouts table completely and recreate
DROP TABLE IF EXISTS shared_workouts CASCADE;

CREATE TABLE shared_workouts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sender_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    recipient_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    workout_name TEXT NOT NULL,
    workout_description TEXT,
    exercises JSONB NOT NULL DEFAULT '[]'::jsonb,
    message TEXT,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'declined', 'started', 'completed')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    viewed_at TIMESTAMPTZ,
    responded_at TIMESTAMPTZ,
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    saved_to_favorites BOOLEAN DEFAULT FALSE,
    estimated_duration INTEGER,
    difficulty_level TEXT
);

-- Step 4: Enable RLS
ALTER TABLE shared_workouts ENABLE ROW LEVEL SECURITY;

-- Step 5: Create RLS policies
CREATE POLICY "Users can view their sent or received workouts" ON shared_workouts
    FOR SELECT USING (auth.uid() = sender_id OR auth.uid() = recipient_id);

CREATE POLICY "Users can insert workouts they send" ON shared_workouts
    FOR INSERT WITH CHECK (auth.uid() = sender_id);

CREATE POLICY "Users can update their workouts" ON shared_workouts
    FOR UPDATE USING (auth.uid() = recipient_id OR auth.uid() = sender_id);

-- Step 6: Create indexes
CREATE INDEX IF NOT EXISTS idx_shared_workouts_sender ON shared_workouts(sender_id);
CREATE INDEX IF NOT EXISTS idx_shared_workouts_recipient ON shared_workouts(recipient_id);
CREATE INDEX IF NOT EXISTS idx_shared_workouts_status ON shared_workouts(status);

-- Step 7: Create the send_workout_to_friend function (single version with TEXT params)
CREATE OR REPLACE FUNCTION send_workout_to_friend(
    target_user_id TEXT,
    p_workout_name TEXT,
    p_exercises TEXT,
    p_description TEXT DEFAULT NULL,
    p_message TEXT DEFAULT NULL,
    p_duration INTEGER DEFAULT NULL,
    p_difficulty TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    current_user_id UUID := auth.uid();
    target_uuid UUID;
    new_workout_id UUID;
    exercises_jsonb JSONB;
    friendship_exists BOOLEAN;
BEGIN
    -- Convert target_user_id to UUID
    target_uuid := target_user_id::UUID;
    
    -- Check if they are friends
    SELECT EXISTS (
        SELECT 1 FROM friendships
        WHERE status = 'accepted'
        AND ((requester_id = current_user_id AND addressee_id = target_uuid)
             OR (requester_id = target_uuid AND addressee_id = current_user_id))
    ) INTO friendship_exists;
    
    IF NOT friendship_exists THEN
        RAISE EXCEPTION 'You can only send workouts to friends';
    END IF;
    
    -- Parse exercises JSON string to JSONB
    BEGIN
        exercises_jsonb := p_exercises::JSONB;
    EXCEPTION WHEN OTHERS THEN
        exercises_jsonb := '[]'::JSONB;
    END;
    
    -- Insert the shared workout
    INSERT INTO shared_workouts (
        sender_id,
        recipient_id,
        workout_name,
        workout_description,
        exercises,
        message,
        estimated_duration,
        difficulty_level,
        status
    ) VALUES (
        current_user_id,
        target_uuid,
        p_workout_name,
        p_description,
        exercises_jsonb,
        p_message,
        p_duration,
        p_difficulty,
        'pending'
    )
    RETURNING id INTO new_workout_id;
    
    -- Create notification for recipient (if app_notifications table exists)
    BEGIN
        INSERT INTO app_notifications (
            user_id,
            notification_type,
            reference_id,
            from_user_id,
            title,
            body
        ) VALUES (
            target_uuid,
            'shared_workout',
            new_workout_id,
            current_user_id,
            'New Workout Received',
            (SELECT COALESCE(name, email) FROM user_profiles WHERE id = current_user_id::TEXT) || ' sent you a workout: ' || p_workout_name
        );
    EXCEPTION WHEN OTHERS THEN
        -- Notification table might not exist, continue anyway
        NULL;
    END;
    
    RETURN new_workout_id;
END;
$$;

-- Step 8: Create get_received_workouts function
CREATE OR REPLACE FUNCTION get_received_workouts()
RETURNS TABLE (
    workout_id UUID,
    sender_id UUID,
    sender_name TEXT,
    sender_username TEXT,
    workout_name TEXT,
    workout_description TEXT,
    exercises JSONB,
    message TEXT,
    status TEXT,
    created_at TIMESTAMPTZ,
    viewed_at TIMESTAMPTZ,
    saved_to_favorites BOOLEAN,
    estimated_duration INTEGER,
    difficulty_level TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    current_user_id UUID := auth.uid();
BEGIN
    RETURN QUERY
    SELECT 
        sw.id AS workout_id,
        sw.sender_id,
        COALESCE(u.name, u.email::TEXT) AS sender_name,
        u.username AS sender_username,
        sw.workout_name,
        sw.workout_description,
        sw.exercises,
        sw.message,
        sw.status,
        sw.created_at,
        sw.viewed_at,
        sw.saved_to_favorites,
        sw.estimated_duration,
        sw.difficulty_level
    FROM shared_workouts sw
    JOIN user_profiles u ON u.id = sw.sender_id::TEXT
    WHERE sw.recipient_id = current_user_id
    ORDER BY sw.created_at DESC;
END;
$$;

-- Step 9: Ensure app_notifications table exists
CREATE TABLE IF NOT EXISTS app_notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    notification_type TEXT NOT NULL,
    reference_id UUID,
    from_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    title TEXT NOT NULL,
    body TEXT,
    is_read BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE app_notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view their own notifications" ON app_notifications;
DROP POLICY IF EXISTS "Users can update their own notifications" ON app_notifications;

CREATE POLICY "Users can view their own notifications" ON app_notifications
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can update their own notifications" ON app_notifications
    FOR UPDATE USING (auth.uid() = user_id);

-- Step 10: Grant execute permissions
GRANT EXECUTE ON FUNCTION send_workout_to_friend(TEXT, TEXT, TEXT, TEXT, TEXT, INTEGER, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION get_received_workouts() TO authenticated;

-- Verify the fix
SELECT 'Fix V2 applied successfully!' AS status;
SELECT 
    routine_name, 
    data_type as return_type
FROM information_schema.routines 
WHERE routine_name = 'send_workout_to_friend' 
AND routine_schema = 'public';
