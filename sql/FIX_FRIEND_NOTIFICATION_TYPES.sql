-- Fix app_notifications constraint to include ALL notification types
-- This allows friend request, friend accepted, challenge, and workout notifications

DO $$
DECLARE
    constraint_name TEXT;
BEGIN
    -- Get the name of the existing check constraint
    SELECT conname INTO constraint_name
    FROM pg_constraint
    WHERE conrelid = 'public.app_notifications'::regclass
    AND contype = 'c'
    AND conname LIKE '%notification_type_check%';

    IF constraint_name IS NOT NULL THEN
        -- Drop the old constraint
        EXECUTE 'ALTER TABLE public.app_notifications DROP CONSTRAINT ' || constraint_name;
        RAISE NOTICE 'Dropped constraint %', constraint_name;
    END IF;

    -- Add the new constraint with ALL notification types
    EXECUTE 'ALTER TABLE public.app_notifications ADD CONSTRAINT app_notifications_notification_type_check CHECK ((notification_type = ANY (ARRAY[
        ''friend_request''::text, 
        ''friend_request_received''::text, 
        ''friend_accepted''::text, 
        ''friend_request_accepted''::text,
        ''workout_received''::text, 
        ''workout_started''::text, 
        ''workout_completed''::text, 
        ''challenge_invite''::text, 
        ''challenge_accepted''::text, 
        ''challenge_declined''::text, 
        ''challenge_cancelled''::text,
        ''shared_workout''::text
    ])))';
    
    RAISE NOTICE 'Created new constraint app_notifications_notification_type_check with ALL notification types';
    
END;
$$ LANGUAGE plpgsql;

-- Verify the constraint
SELECT 
    conname AS constraint_name,
    pg_get_constraintdef(oid) AS constraint_definition
FROM pg_constraint
WHERE conrelid = 'public.app_notifications'::regclass
AND contype = 'c'
AND conname LIKE '%notification_type_check%';
