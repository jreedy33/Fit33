-- ============================================================================
-- FIX: Challenge Progress Notification Flood
-- ============================================================================
-- DISCOVERED BY: Social System Simulator (Feb 25, 2026)
--
-- PROBLEM: Every time challenge_daily_progress is updated with target_hit=true,
-- a trigger fires a push notification to the opponent. When multiple challenges
-- update in quick succession (HealthKit sync, simulation, etc.), this creates
-- hundreds of duplicate "Dave completed their daily challenge! 🔥" notifications.
--
-- FIX: Add a cooldown/debounce to the notification trigger:
--   - Max 1 progress notification per opponent per challenge per 5 minutes
--   - Check push_notification_queue before inserting a new notification
--
-- This fix also benefits REAL users — if HealthKit syncs steps multiple times
-- in a short window, the opponent won't get spammed.
-- ============================================================================

-- Step 1: Find and list current triggers on challenge_daily_progress
DO $$
DECLARE
    trig_rec RECORD;
BEGIN
    RAISE NOTICE 'Current triggers on challenge_daily_progress:';
    FOR trig_rec IN
        SELECT trigger_name, event_manipulation, action_statement
        FROM information_schema.triggers
        WHERE event_object_table = 'challenge_daily_progress'
        AND trigger_schema = 'public'
    LOOP
        RAISE NOTICE '  Trigger: % (on %)', trig_rec.trigger_name, trig_rec.event_manipulation;
        RAISE NOTICE '  Action: %', LEFT(trig_rec.action_statement, 200);
    END LOOP;
END $$;

-- Step 2: Create or replace the notification function WITH cooldown
-- This replaces whatever function the trigger calls, adding a 5-minute debounce
CREATE OR REPLACE FUNCTION notify_challenge_progress()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_opponent_id UUID;
    v_challenge_title TEXT;
    v_user_name TEXT;
    v_recent_notification_exists BOOLEAN;
    v_opponent_wants_notification BOOLEAN;
BEGIN
    -- Only fire when target is newly hit (not on every upsert)
    -- Check: target_hit must be TRUE, and either it's a new row or target_hit changed from false to true
    IF NEW.target_hit IS NOT TRUE THEN
        RETURN NEW;
    END IF;

    -- If this is an UPDATE and target was already hit, skip (prevents duplicate on re-upsert)
    IF TG_OP = 'UPDATE' AND OLD.target_hit = TRUE THEN
        RETURN NEW;
    END IF;

    -- Get the user's name
    SELECT name INTO v_user_name
    FROM user_profiles
    WHERE id = NEW.user_id;

    -- Get challenge title
    SELECT title INTO v_challenge_title
    FROM group_challenges
    WHERE id = NEW.challenge_id;

    -- Find the opponent(s) in this challenge
    -- For each opponent, check cooldown and notification preference
    FOR v_opponent_id IN
        SELECT user_id FROM challenge_participants
        WHERE challenge_id = NEW.challenge_id
        AND user_id != NEW.user_id
        AND status = 'accepted'
    LOOP
        -- Check if opponent wants these notifications
        SELECT COALESCE(notify_on_opponent_complete, true) INTO v_opponent_wants_notification
        FROM challenge_participants
        WHERE challenge_id = NEW.challenge_id AND user_id = v_opponent_id;

        IF NOT v_opponent_wants_notification THEN
            CONTINUE;
        END IF;

        -- DEBOUNCE: Check if we already sent a progress notification for this
        -- challenge to this opponent in the last 5 minutes
        SELECT EXISTS (
            SELECT 1 FROM push_notification_queue
            WHERE recipient_user_id = v_opponent_id
            AND notification_type = 'challenge_progress'
            AND data->>'challenge_id' = NEW.challenge_id::TEXT
            AND created_at > NOW() - INTERVAL '5 minutes'
        ) INTO v_recent_notification_exists;

        IF v_recent_notification_exists THEN
            -- Skip — we already notified this opponent about this challenge recently
            CONTINUE;
        END IF;

        -- Queue the push notification (with cooldown passed)
        INSERT INTO push_notification_queue (
            recipient_user_id,
            notification_type,
            title,
            body,
            data,
            status
        ) VALUES (
            v_opponent_id,
            'challenge_progress',
            COALESCE(v_user_name, 'Your opponent') || ' completed their daily challenge! 🔥',
            'Keep up in "' || COALESCE(v_challenge_title, 'your challenge') || '"!',
            jsonb_build_object(
                'type', 'challenge_progress',
                'challenge_id', NEW.challenge_id::TEXT,
                'from_user_id', NEW.user_id::TEXT,
                'opponent_name', COALESCE(v_user_name, 'Opponent')
            ),
            'pending'
        );

    END LOOP;

    RETURN NEW;
END;
$$;

-- Step 3: Drop existing trigger(s) and re-create with the debounced function
-- First drop any existing triggers on this table that fire our function
DO $$
DECLARE
    trig_name TEXT;
BEGIN
    FOR trig_name IN
        SELECT trigger_name
        FROM information_schema.triggers
        WHERE event_object_table = 'challenge_daily_progress'
        AND trigger_schema = 'public'
    LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS %I ON challenge_daily_progress', trig_name);
        RAISE NOTICE 'Dropped trigger: %', trig_name;
    END LOOP;
END $$;

-- Re-create trigger with the debounced function
CREATE TRIGGER challenge_progress_notify
    AFTER INSERT OR UPDATE ON challenge_daily_progress
    FOR EACH ROW
    EXECUTE FUNCTION notify_challenge_progress();

-- ============================================================================
-- VERIFICATION
-- ============================================================================
DO $$
DECLARE
    trig_count INT;
BEGIN
    SELECT COUNT(*) INTO trig_count
    FROM information_schema.triggers
    WHERE event_object_table = 'challenge_daily_progress'
    AND trigger_schema = 'public';
    
    RAISE NOTICE '✅ challenge_daily_progress now has % trigger(s)', trig_count;
    RAISE NOTICE '   Notification debounce: 5 minutes per opponent per challenge';
    RAISE NOTICE '   Skips: target_hit=false, re-upsert of already-hit target, recent notification exists';
END $$;
