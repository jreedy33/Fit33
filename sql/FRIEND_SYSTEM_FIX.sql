-- =====================================================
-- FRIEND SYSTEM FIX - Resolve duplicate functions and missing columns
-- Run this in Supabase SQL Editor
-- =====================================================

-- Step 1: Drop ALL versions of send_workout_to_friend to clear the conflict
DROP FUNCTION IF EXISTS send_workout_to_friend(text, text, text, text, text, integer, text);
DROP FUNCTION IF EXISTS send_workout_to_friend(uuid, text, jsonb, text, text, integer, text);
DROP FUNCTION IF EXISTS send_workout_to_friend(text, text, jsonb, text, text, integer, text);
DROP FUNCTION IF EXISTS public.send_workout_to_friend(text, text, text, text, text, integer, text);
DROP FUNCTION IF EXISTS public.send_workout_to_friend(uuid, text, jsonb, text, text, integer, text);

-- Step 2: Fix the shared_workouts table - remove NOT NULL from exercise_names if it exists
DO $$ 
BEGIN
    -- Make exercise_names nullable if it exists
    IF EXISTS (SELECT 1 FROM information_schema.columns 
               WHERE table_name = 'shared_workouts' AND column_name = 'exercise_names') THEN
        ALTER TABLE shared_workouts ALTER COLUMN exercise_names DROP NOT NULL;
    END IF;
END $$;

-- Step 3: Ensure shared_workouts table exists with ALL required columns
CREATE TABLE IF NOT EXISTS shared_workouts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sender_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    recipient_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    workout_name TEXT NOT NULL,
    workout_description TEXT,
    exercises JSONB DEFAULT '[]'::jsonb,
    exercise_names TEXT[],
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

-- Step 4: Add any missing columns to existing table and fix constraints
DO $$ 
BEGIN
    -- Add exercises column if missing
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'shared_workouts' AND column_name = 'exercises') THEN
        ALTER TABLE shared_workouts ADD COLUMN exercises JSONB DEFAULT '[]'::jsonb;
    END IF;
    
    -- Add exercise_names column if missing
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'shared_workouts' AND column_name = 'exercise_names') THEN
        ALTER TABLE shared_workouts ADD COLUMN exercise_names TEXT[];
    END IF;
    
    -- Add workout_description if missing
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'shared_workouts' AND column_name = 'workout_description') THEN
        ALTER TABLE shared_workouts ADD COLUMN workout_description TEXT;
    END IF;
    
    -- Add message if missing
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'shared_workouts' AND column_name = 'message') THEN
        ALTER TABLE shared_workouts ADD COLUMN message TEXT;
    END IF;
    
    -- Add viewed_at if missing
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'shared_workouts' AND column_name = 'viewed_at') THEN
        ALTER TABLE shared_workouts ADD COLUMN viewed_at TIMESTAMPTZ;
    END IF;
    
    -- Add saved_to_favorites if missing
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'shared_workouts' AND column_name = 'saved_to_favorites') THEN
        ALTER TABLE shared_workouts ADD COLUMN saved_to_favorites BOOLEAN DEFAULT FALSE;
    END IF;
    
    -- Add estimated_duration if missing
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'shared_workouts' AND column_name = 'estimated_duration') THEN
        ALTER TABLE shared_workouts ADD COLUMN estimated_duration INTEGER;
    END IF;
    
    -- Add difficulty_level if missing
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'shared_workouts' AND column_name = 'difficulty_level') THEN
        ALTER TABLE shared_workouts ADD COLUMN difficulty_level TEXT;
    END IF;
END $$;

-- Step 4: Enable RLS on shared_workouts
ALTER TABLE shared_workouts ENABLE ROW LEVEL SECURITY;

-- Step 5: Drop and recreate RLS policies for shared_workouts
DROP POLICY IF EXISTS "Users can view their sent or received workouts" ON shared_workouts;
DROP POLICY IF EXISTS "Users can insert workouts they send" ON shared_workouts;
DROP POLICY IF EXISTS "Recipients can update received workouts" ON shared_workouts;

CREATE POLICY "Users can view their sent or received workouts" ON shared_workouts
    FOR SELECT USING (auth.uid() = sender_id OR auth.uid() = recipient_id);

CREATE POLICY "Users can insert workouts they send" ON shared_workouts
    FOR INSERT WITH CHECK (auth.uid() = sender_id);

CREATE POLICY "Recipients can update received workouts" ON shared_workouts
    FOR UPDATE USING (auth.uid() = recipient_id OR auth.uid() = sender_id);

-- Step 6: Create the SINGLE correct send_workout_to_friend function
-- Using TEXT for target_user_id to match Swift client
CREATE OR REPLACE FUNCTION send_workout_to_friend(
    target_user_id TEXT,
    p_workout_name TEXT,
    p_exercises TEXT,  -- JSON string from Swift
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
    exercise_names_array TEXT[];
    friendship_exists BOOLEAN := FALSE;
BEGIN
    -- Convert target_user_id to UUID
    target_uuid := target_user_id::UUID;
    
    -- Check if they are friends (exact same logic as working get_friends function)
    -- Uses direct UUID comparison - requester_id and addressee_id are UUID columns
    SELECT EXISTS (
        SELECT 1 FROM friendships f
        WHERE f.status = 'accepted'
        AND (
            (f.requester_id = current_user_id AND f.addressee_id = target_uuid)
            OR (f.requester_id = target_uuid AND f.addressee_id = current_user_id)
        )
    ) INTO friendship_exists;
    
    IF NOT friendship_exists THEN
        RAISE EXCEPTION 'You can only send workouts to friends';
    END IF;
    
    -- Parse exercises JSON string to JSONB
    BEGIN
        exercises_jsonb := p_exercises::JSONB;
        -- Extract exercise names from the JSON array
        SELECT ARRAY_AGG(elem->>'name')
        INTO exercise_names_array
        FROM jsonb_array_elements(exercises_jsonb) AS elem
        WHERE elem->>'name' IS NOT NULL;
    EXCEPTION WHEN OTHERS THEN
        exercises_jsonb := '[]'::JSONB;
        exercise_names_array := ARRAY[]::TEXT[];
    END;
    
    -- Default to empty array if null
    IF exercise_names_array IS NULL THEN
        exercise_names_array := ARRAY[]::TEXT[];
    END IF;
    
    -- Insert the shared workout
    INSERT INTO shared_workouts (
        sender_id,
        recipient_id,
        workout_name,
        workout_description,
        exercises,
        exercise_names,
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
        exercise_names_array,
        p_message,
        p_duration,
        p_difficulty,
        'pending'
    )
    RETURNING id INTO new_workout_id;
    
    -- Create notification for recipient (skip user lookup to avoid type issues)
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
            'You received a new workout: ' || p_workout_name
        );
    EXCEPTION WHEN OTHERS THEN
        -- Notification failed, but workout was sent successfully - continue
        NULL;
    END;
    
    RETURN new_workout_id;
END;
$$;

-- Step 7: Fix get_received_workouts function to include exercises
DROP FUNCTION IF EXISTS get_received_workouts();

CREATE OR REPLACE FUNCTION get_received_workouts()
RETURNS TABLE (
    workout_id UUID,
    sender_id UUID,
    sender_name TEXT,
    sender_username TEXT,
    workout_name TEXT,
    workout_description TEXT,
    exercises JSONB,
    exercise_names TEXT[],
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
    current_user_uuid UUID := auth.uid();
BEGIN
    RETURN QUERY
    SELECT 
        sw.id AS workout_id,
        sw.sender_id,
        -- Get sender name via subquery - cast BOTH sides to TEXT for consistent comparison
        (SELECT COALESCE(up.name, up.email) FROM user_profiles up WHERE up.id::TEXT = sw.sender_id::TEXT LIMIT 1) AS sender_name,
        (SELECT up.username FROM user_profiles up WHERE up.id::TEXT = sw.sender_id::TEXT LIMIT 1) AS sender_username,
        sw.workout_name,
        sw.workout_description,
        COALESCE(sw.exercises, '[]'::JSONB) AS exercises,
        COALESCE(sw.exercise_names, ARRAY[]::TEXT[]) AS exercise_names,
        sw.message,
        sw.status,
        sw.created_at,
        sw.viewed_at,
        sw.saved_to_favorites,
        sw.estimated_duration,
        sw.difficulty_level
    FROM shared_workouts sw
    WHERE sw.recipient_id = current_user_uuid
    ORDER BY sw.created_at DESC;
END;
$$;

-- Step 8: Fix get_sent_workouts function
DROP FUNCTION IF EXISTS get_sent_workouts();

CREATE OR REPLACE FUNCTION get_sent_workouts()
RETURNS TABLE (
    workout_id UUID,
    to_user_id UUID,
    to_user_name TEXT,
    workout_name TEXT,
    status TEXT,
    created_at TIMESTAMPTZ,
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    current_user_uuid UUID := auth.uid();
BEGIN
    RETURN QUERY
    SELECT 
        sw.id AS workout_id,
        sw.recipient_id AS to_user_id,
        -- Get recipient name via subquery - cast BOTH sides to TEXT for consistent comparison
        (SELECT COALESCE(up.name, up.email) FROM user_profiles up WHERE up.id::TEXT = sw.recipient_id::TEXT LIMIT 1) AS to_user_name,
        sw.workout_name,
        sw.status,
        sw.created_at,
        sw.started_at,
        sw.completed_at
    FROM shared_workouts sw
    WHERE sw.sender_id = current_user_uuid
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

-- Enable RLS on app_notifications
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
GRANT EXECUTE ON FUNCTION get_sent_workouts() TO authenticated;

-- Done!
SELECT 'Friend system fix applied successfully!' AS status;

-- =====================================================
-- DIAGNOSTIC QUERIES - Run these separately to debug
-- Copy and paste each SELECT to see your data
-- =====================================================

-- 1. Show friendships table structure:
-- SELECT column_name, data_type FROM information_schema.columns 
-- WHERE table_schema = 'public' AND table_name = 'friendships';

-- 2. Show all friendships (first 10):
-- SELECT * FROM friendships LIMIT 10;

-- 3. Check if friend_requests table exists and has data:
-- SELECT * FROM friend_requests WHERE status = 'accepted' LIMIT 10;
