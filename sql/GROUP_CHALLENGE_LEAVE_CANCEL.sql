-- ============================================================
-- GROUP CHALLENGE: Notifications, Leave & Cancel Support
-- ============================================================

-- ============================================================
-- FIX: Update app_notifications CHECK constraint to allow
-- group_challenge_invite and group_challenge_started types
-- Without this, the INSERT into app_notifications silently fails!
-- ============================================================

DO $$
DECLARE
    constraint_name TEXT;
BEGIN
    -- Find and drop the existing notification_type check constraint
    SELECT conname INTO constraint_name
    FROM pg_constraint
    WHERE conrelid = 'public.app_notifications'::regclass
    AND contype = 'c'
    AND conname LIKE '%notification_type%';

    IF constraint_name IS NOT NULL THEN
        EXECUTE 'ALTER TABLE public.app_notifications DROP CONSTRAINT ' || constraint_name;
        RAISE NOTICE 'Dropped constraint: %', constraint_name;
    END IF;

    -- Recreate with ALL notification types including group challenge types
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
        ''shared_workout''::text,
        ''contact_joined''::text,
        ''group_challenge_invite''::text,
        ''group_challenge_started''::text
    ])))';

    RAISE NOTICE 'Updated constraint with group_challenge_invite and group_challenge_started types';
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- Helper: Format challenge title for push notifications
-- Strips mode/activity emojis, formats thousands as K
-- ============================================================

CREATE OR REPLACE FUNCTION format_challenge_title(p_title TEXT)
RETURNS TEXT
LANGUAGE plpgsql IMMUTABLE
AS $$
DECLARE
    t TEXT := p_title;
BEGIN
    -- Strip common leading emojis (mode + activity)
    t := regexp_replace(t, '^\s*[^\x20-\x7E]+\s*', '', 'g');
    -- If still has leading non-ASCII after first pass, strip again
    t := regexp_replace(t, '^\s*[^\x20-\x7E]+\s*', '', 'g');
    -- Format thousands as K (e.g. 10000 → 10K, 2000 → 2K)
    t := regexp_replace(t, '(\d+)000\b', '\1K', 'g');
    RETURN trim(t);
END;
$$;

-- ============================================================
-- 0. Push Notification Trigger for Group Challenge Invites
-- When a member is added to a group challenge with status='pending',
-- send them a real-time push notification via app_notifications
-- (the existing trigger on app_notifications queues push automatically)
-- ============================================================

CREATE OR REPLACE FUNCTION notify_group_challenge_invite()
RETURNS TRIGGER AS $$
DECLARE
    v_creator_id UUID;
    v_creator_name TEXT;
    v_challenge_title TEXT;
BEGIN
    -- Only trigger for new pending invites (not the creator's auto-accepted entry)
    IF NEW.status != 'pending' THEN
        RETURN NEW;
    END IF;

    -- Get the group challenge creator and title
    SELECT gc.created_by, gc.title, COALESCE(up.name, up.username, 'Someone')
    INTO v_creator_id, v_challenge_title, v_creator_name
    FROM group_challenges gc
    JOIN user_profiles up ON up.id = gc.created_by
    WHERE gc.id = NEW.group_challenge_id;

    -- Insert app notification (this triggers push notification automatically)
    INSERT INTO app_notifications (
        user_id,
        notification_type,
        reference_id,
        from_user_id,
        title,
        body,
        is_read
    ) VALUES (
        NEW.user_id,
        'group_challenge_invite',
        NEW.group_challenge_id,
        v_creator_id,
        v_creator_name || ' invited you to a group challenge! 🏆',
        'Tap to check out "' || format_challenge_title(COALESCE(v_challenge_title, 'Group Challenge')) || '" and join the crew.',
        false
    );

    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    -- Don't fail the member insert if notification fails
    RAISE WARNING 'Group challenge invite notification failed: %', SQLERRM;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger on group_challenge_members
DROP TRIGGER IF EXISTS on_group_challenge_invite ON group_challenge_members;
CREATE TRIGGER on_group_challenge_invite
    AFTER INSERT ON group_challenge_members
    FOR EACH ROW
    EXECUTE FUNCTION notify_group_challenge_invite();

-- ============================================================
-- 1. Updated accept_group_challenge
-- When the LAST member accepts:
--   - Activate the challenge
--   - Send "Challenge Started" push notification to ALL members
-- ============================================================

CREATE OR REPLACE FUNCTION accept_group_challenge(p_challenge_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
    v_all_accepted BOOLEAN;
    v_challenge_title TEXT;
    v_accepter_name TEXT;
    v_member RECORD;
BEGIN
    -- Update member status
    UPDATE group_challenge_members
    SET status = 'accepted', joined_at = now()
    WHERE group_challenge_id = p_challenge_id AND user_id = auth.uid();

    -- Check if all members have accepted
    SELECT NOT EXISTS (
        SELECT 1 FROM group_challenge_members
        WHERE group_challenge_id = p_challenge_id AND status = 'pending'
    ) INTO v_all_accepted;

    -- Get accepter name and challenge title (used for both paths)
    SELECT COALESCE(up.name, up.username, 'Someone') INTO v_accepter_name
    FROM user_profiles up WHERE up.id = auth.uid();

    SELECT title INTO v_challenge_title
    FROM group_challenges WHERE id = p_challenge_id;

    -- If NOT all accepted yet, notify OTHER members that this person accepted (real-time update)
    IF NOT v_all_accepted THEN
        FOR v_member IN
            SELECT user_id FROM group_challenge_members
            WHERE group_challenge_id = p_challenge_id
            AND user_id != auth.uid()
            AND status IN ('accepted', 'pending')
        LOOP
            INSERT INTO app_notifications (user_id, notification_type, reference_id, from_user_id, title, body, is_read)
            VALUES (
                v_member.user_id, 'group_challenge_invite', p_challenge_id, auth.uid(),
                v_accepter_name || ' joined the challenge! ✅',
                'Waiting for everyone to accept "' || format_challenge_title(COALESCE(v_challenge_title, 'Group Challenge')) || '"',
                false
            );
        END LOOP;
    END IF;

    -- If all accepted, activate the challenge and notify everyone
    IF v_all_accepted THEN
        UPDATE group_challenges
        SET status = 'active', start_date = CURRENT_DATE, end_date = CURRENT_DATE + duration_days
        WHERE id = p_challenge_id;

        -- Send "Challenge Started" notification to ALL accepted members
        FOR v_member IN
            SELECT user_id FROM group_challenge_members
            WHERE group_challenge_id = p_challenge_id AND status = 'accepted'
        LOOP
            INSERT INTO app_notifications (
                user_id,
                notification_type,
                reference_id,
                from_user_id,
                title,
                body,
                is_read
            ) VALUES (
                v_member.user_id,
                'group_challenge_started',
                p_challenge_id,
                auth.uid(),
                'Group Challenge Started! 🔥',
                'Everyone''s in! "' || format_challenge_title(COALESCE(v_challenge_title, 'Group Challenge')) || '" is now active. Let''s go!',
                false
            );
        END LOOP;
    END IF;

    RETURN v_all_accepted;
END;
$$;

-- ============================================================

-- 2. Leave Group Challenge
-- When a member leaves:
--   - If 3+ members remain → just remove the member
--   - If exactly 2 accepted members remain → convert to a 1v1 challenge
--     (creates a friend_challenges entry, copies progress, cancels group)
--   - If <2 remain → cancel the group entirely
-- ============================================================

CREATE OR REPLACE FUNCTION leave_group_challenge(p_challenge_id UUID)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
    v_user_id UUID;
    v_remaining_accepted INTEGER;
    v_member1 RECORD;
    v_member2 RECORD;
    v_new_challenge_id UUID;
    v_gc RECORD;
BEGIN
    v_user_id := auth.uid();

    -- Mark the current user as 'left'
    UPDATE group_challenge_members
    SET status = 'left'
    WHERE group_challenge_id = p_challenge_id AND user_id = v_user_id;

    -- Count remaining accepted members
    SELECT COUNT(*) INTO v_remaining_accepted
    FROM group_challenge_members
    WHERE group_challenge_id = p_challenge_id AND status = 'accepted';

    IF v_remaining_accepted < 2 THEN
        -- Not enough members, cancel the group
        UPDATE group_challenges SET status = 'cancelled' WHERE id = p_challenge_id;
        RETURN 'cancelled';

    ELSIF v_remaining_accepted = 2 THEN
        -- Exactly 2 remain → convert to a 1v1 challenge
        -- Get the group challenge details
        SELECT * INTO v_gc FROM group_challenges WHERE id = p_challenge_id;

        -- Get the two remaining members (ordered so first is "creator")
        SELECT user_id, total_progress, days_completed, current_streak
        INTO v_member1
        FROM group_challenge_members
        WHERE group_challenge_id = p_challenge_id AND status = 'accepted'
        ORDER BY created_at ASC
        LIMIT 1;

        SELECT user_id, total_progress, days_completed, current_streak
        INTO v_member2
        FROM group_challenge_members
        WHERE group_challenge_id = p_challenge_id AND status = 'accepted'
        AND user_id != v_member1.user_id
        LIMIT 1;

        -- Create a new 1v1 friend_challenges entry
        INSERT INTO friend_challenges (
            creator_id, challenge_type, title, description,
            daily_target, total_target, target_unit,
            start_date, end_date, status
        ) VALUES (
            v_member1.user_id,
            v_gc.challenge_type,
            v_gc.title,
            v_gc.description,
            v_gc.daily_target,
            v_gc.total_target,
            v_gc.target_unit,
            v_gc.start_date,
            v_gc.end_date,
            'active'
        ) RETURNING id INTO v_new_challenge_id;

        -- Add both members as accepted participants with their progress
        INSERT INTO challenge_participants (challenge_id, user_id, status, total_progress, days_completed, current_streak, responded_at, joined_at)
        VALUES (v_new_challenge_id, v_member1.user_id, 'accepted', v_member1.total_progress, v_member1.days_completed, v_member1.current_streak, now(), now());

        INSERT INTO challenge_participants (challenge_id, user_id, status, total_progress, days_completed, current_streak, responded_at, joined_at)
        VALUES (v_new_challenge_id, v_member2.user_id, 'accepted', v_member2.total_progress, v_member2.days_completed, v_member2.current_streak, now(), now());

        -- Cancel the group challenge
        UPDATE group_challenges SET status = 'cancelled' WHERE id = p_challenge_id;

        RETURN 'converted';

    ELSE
        -- 3+ remain, group continues without this member
        RETURN 'left';
    END IF;
END;
$$;

-- 3. Updated decline_group_challenge
-- Smart decline: marks user as declined, then checks remaining non-declined members.
-- If only 2 accepted/pending remain → convert to 1v1 (if both accepted) or stay group
-- If <2 remain → cancel the group entirely
-- Notifies remaining members about the decline
-- ============================================================

CREATE OR REPLACE FUNCTION decline_group_challenge(p_challenge_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
    v_user_id UUID;
    v_decliner_name TEXT;
    v_remaining_count INTEGER;
    v_accepted_count INTEGER;
    v_gc RECORD;
    v_member1 RECORD;
    v_member2 RECORD;
    v_new_challenge_id UUID;
    v_member RECORD;
    v_challenge_title TEXT;
BEGIN
    v_user_id := auth.uid();

    -- Mark user as declined
    UPDATE group_challenge_members
    SET status = 'declined'
    WHERE group_challenge_id = p_challenge_id AND user_id = v_user_id;

    -- Get decliner name and challenge title
    SELECT COALESCE(up.name, up.username, 'Someone') INTO v_decliner_name
    FROM user_profiles up WHERE up.id = v_user_id;

    SELECT title INTO v_challenge_title
    FROM group_challenges WHERE id = p_challenge_id;

    -- Count remaining non-declined/non-left members
    SELECT COUNT(*) INTO v_remaining_count
    FROM group_challenge_members
    WHERE group_challenge_id = p_challenge_id AND status IN ('accepted', 'pending');

    -- Count accepted members
    SELECT COUNT(*) INTO v_accepted_count
    FROM group_challenge_members
    WHERE group_challenge_id = p_challenge_id AND status = 'accepted';

    IF v_remaining_count < 2 THEN
        -- Not enough members remain, cancel the group
        UPDATE group_challenges SET status = 'cancelled' WHERE id = p_challenge_id;

    ELSIF v_remaining_count = 2 AND v_accepted_count = 2 THEN
        -- Exactly 2 accepted members remain with no pending → convert to 1v1
        SELECT * INTO v_gc FROM group_challenges WHERE id = p_challenge_id;

        SELECT user_id, total_progress, days_completed, current_streak
        INTO v_member1
        FROM group_challenge_members
        WHERE group_challenge_id = p_challenge_id AND status = 'accepted'
        ORDER BY created_at ASC LIMIT 1;

        SELECT user_id, total_progress, days_completed, current_streak
        INTO v_member2
        FROM group_challenge_members
        WHERE group_challenge_id = p_challenge_id AND status = 'accepted'
        AND user_id != v_member1.user_id LIMIT 1;

        -- Create a 1v1 challenge
        INSERT INTO friend_challenges (
            creator_id, challenge_type, title, description,
            daily_target, total_target, target_unit,
            start_date, end_date, status
        ) VALUES (
            v_member1.user_id, v_gc.challenge_type, v_gc.title, v_gc.description,
            v_gc.daily_target, v_gc.total_target, v_gc.target_unit,
            v_gc.start_date, v_gc.end_date, 'active'
        ) RETURNING id INTO v_new_challenge_id;

        INSERT INTO challenge_participants (challenge_id, user_id, status, total_progress, days_completed, current_streak, responded_at, joined_at)
        VALUES (v_new_challenge_id, v_member1.user_id, 'accepted', v_member1.total_progress, v_member1.days_completed, v_member1.current_streak, now(), now());

        INSERT INTO challenge_participants (challenge_id, user_id, status, total_progress, days_completed, current_streak, responded_at, joined_at)
        VALUES (v_new_challenge_id, v_member2.user_id, 'accepted', v_member2.total_progress, v_member2.days_completed, v_member2.current_streak, now(), now());

        -- Cancel the group challenge
        UPDATE group_challenges SET status = 'cancelled' WHERE id = p_challenge_id;

        -- Notify the 2 remaining members that it converted to 1v1
        FOR v_member IN
            SELECT user_id FROM group_challenge_members
            WHERE group_challenge_id = p_challenge_id AND status = 'accepted'
        LOOP
            INSERT INTO app_notifications (user_id, notification_type, reference_id, from_user_id, title, body, is_read)
            VALUES (
                v_member.user_id, 'challenge_accepted', v_new_challenge_id, v_user_id,
                v_decliner_name || ' left — now it''s a 1v1! ⚔️',
                '"' || format_challenge_title(COALESCE(v_challenge_title, 'Challenge')) || '" continues between you two.',
                false
            );
        END LOOP;
    END IF;
    -- If v_remaining_count > 2, the group continues with remaining members (no special action needed)
END;
$$;

-- ============================================================

-- 4. Cancel Group Challenge (creator/anyone can cancel the whole thing)
-- Sets the group status to cancelled — everyone is removed
-- ============================================================

CREATE OR REPLACE FUNCTION cancel_group_challenge(p_challenge_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
    v_canceller_name TEXT;
    v_challenge_title TEXT;
    v_member RECORD;
BEGIN
    -- Verify the user is a member of this challenge
    IF NOT EXISTS (
        SELECT 1 FROM group_challenge_members
        WHERE group_challenge_id = p_challenge_id AND user_id = auth.uid()
    ) THEN
        RAISE EXCEPTION 'You are not a member of this challenge';
    END IF;

    -- Get canceller name and challenge title
    SELECT COALESCE(up.name, up.username, 'Someone') INTO v_canceller_name
    FROM user_profiles up WHERE up.id = auth.uid();

    SELECT title INTO v_challenge_title
    FROM group_challenges WHERE id = p_challenge_id;

    -- Cancel the group challenge
    UPDATE group_challenges
    SET status = 'cancelled'
    WHERE id = p_challenge_id;

    -- Notify ALL other members that the challenge was cancelled
    FOR v_member IN
        SELECT user_id FROM group_challenge_members
        WHERE group_challenge_id = p_challenge_id
        AND user_id != auth.uid()
        AND status IN ('accepted', 'pending')
    LOOP
        INSERT INTO app_notifications (user_id, notification_type, reference_id, from_user_id, title, body, is_read)
        VALUES (
            v_member.user_id,
            'challenge_cancelled',
            p_challenge_id,
            auth.uid(),
            v_canceller_name || ' cancelled the challenge 😔',
            '"' || format_challenge_title(COALESCE(v_challenge_title, 'Group Challenge')) || '" has been cancelled.',
            false
        );
    END LOOP;

    RETURN TRUE;
END;
$$;

-- ============================================================
-- 5. Nudge a pending group challenge member (one-time per sender/recipient pair)
-- Sends a push notification to the pending member
-- Returns false if already nudged
-- ============================================================

CREATE TABLE IF NOT EXISTS group_challenge_nudges (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    group_challenge_id UUID NOT NULL REFERENCES group_challenges(id) ON DELETE CASCADE,
    sender_id UUID NOT NULL REFERENCES auth.users(id),
    recipient_id UUID NOT NULL REFERENCES auth.users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(group_challenge_id, sender_id, recipient_id)
);

ALTER TABLE group_challenge_nudges ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Members can view nudges for their challenges" ON group_challenge_nudges;
CREATE POLICY "Members can view nudges for their challenges" ON group_challenge_nudges
    FOR SELECT USING (
        group_challenge_id IN (
            SELECT group_challenge_id FROM group_challenge_members WHERE user_id = auth.uid()
        )
    );

DROP POLICY IF EXISTS "Members can insert nudges" ON group_challenge_nudges;
CREATE POLICY "Members can insert nudges" ON group_challenge_nudges
    FOR INSERT WITH CHECK (sender_id = auth.uid());

CREATE OR REPLACE FUNCTION nudge_group_challenge_member(
    p_challenge_id UUID,
    p_recipient_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
    v_sender_name TEXT;
    v_challenge_title TEXT;
BEGIN
    -- Check if already nudged
    IF EXISTS (
        SELECT 1 FROM group_challenge_nudges
        WHERE group_challenge_id = p_challenge_id
        AND sender_id = auth.uid()
        AND recipient_id = p_recipient_id
    ) THEN
        RETURN FALSE;
    END IF;

    -- Record the nudge
    INSERT INTO group_challenge_nudges (group_challenge_id, sender_id, recipient_id)
    VALUES (p_challenge_id, auth.uid(), p_recipient_id);

    -- Get sender name and challenge title
    SELECT COALESCE(up.name, up.username, 'Someone') INTO v_sender_name
    FROM user_profiles up WHERE up.id = auth.uid();

    SELECT title INTO v_challenge_title
    FROM group_challenges WHERE id = p_challenge_id;

    -- Send push notification to the pending member
    INSERT INTO app_notifications (user_id, notification_type, reference_id, from_user_id, title, body, is_read)
    VALUES (
        p_recipient_id,
        'group_challenge_invite',
        p_challenge_id,
        auth.uid(),
        'Friends are waiting for you! 👋',
        v_sender_name || ' nudged you to join "' || format_challenge_title(COALESCE(v_challenge_title, 'Group Challenge')) || '"',
        false
    );

    RETURN TRUE;
END;
$$;
