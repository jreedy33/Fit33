-- ============================================================================
-- PRIVATE CHALLENGES MIGRATION
-- ============================================================================
-- Adds the "Private Challenge" system — invite-only challenge communities.
-- The creator is the admin who can invite friends, manage members, and
-- configure the challenge. Members must be invited & accept before joining.
--
-- Think: Office step challenge, friend group fitness challenge, family wellness.
--
-- TABLES CREATED:
--   1. private_challenges           — the challenge definition + admin settings
--   2. private_challenge_members    — who is in the challenge + their role
--   3. private_challenge_invites    — pending invitations
--   4. private_challenge_daily_progress — daily progress per member
--   5. private_challenge_chat       — in-challenge group messaging
--
-- RPC FUNCTIONS CREATED:
--   1.  create_private_challenge           — admin creates a private challenge
--   2.  invite_to_private_challenge        — admin/co-admin invites users
--   3.  accept_private_challenge_invite    — invitee accepts invitation
--   4.  decline_private_challenge_invite   — invitee declines invitation
--   5.  leave_private_challenge            — member leaves voluntarily
--   6.  remove_from_private_challenge      — admin removes a member
--   7.  update_private_challenge           — admin updates settings/goal
--   8.  promote_to_admin                   — admin promotes member to co-admin
--   9.  demote_from_admin                  — admin demotes co-admin to member
--   10. log_private_challenge_progress     — daily progress upsert
--   11. get_my_private_challenges          — challenges I'm a member of
--   12. get_private_challenge_detail       — full detail + leaderboard
--   13. get_private_challenge_invites_for_me — pending invites I received
--   14. send_private_challenge_message     — send chat message
--   15. get_private_challenge_messages     — fetch chat messages
--   16. end_private_challenge              — admin ends the challenge
-- ============================================================================

-- ============================================================================
-- TABLE 1: private_challenges
-- ============================================================================
CREATE TABLE IF NOT EXISTS private_challenges (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    created_by      UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
    
    -- Challenge definition
    challenge_type  TEXT NOT NULL DEFAULT 'steps',  -- steps, walk, run, lift, hydrate, calories, protein, active_minutes, workout_streak, sleep
    title           TEXT NOT NULL,
    description     TEXT,
    emoji           TEXT DEFAULT '🔒',
    
    -- Targets
    daily_target    INT NOT NULL,
    target_unit     TEXT NOT NULL DEFAULT 'steps',
    
    -- Joining / sharing
    join_code       TEXT NOT NULL UNIQUE,            -- 6-char code for manual entry
    
    -- Timing
    is_recurring    BOOLEAN NOT NULL DEFAULT TRUE,   -- TRUE = ongoing (daily reset), FALSE = has end date
    start_date      DATE NOT NULL DEFAULT CURRENT_DATE,
    end_date        DATE,                            -- NULL = open-ended
    
    -- Limits
    max_members     INT DEFAULT 50,                  -- NULL = unlimited (premium unlock potential)
    
    -- Admin settings
    allow_member_invites BOOLEAN NOT NULL DEFAULT FALSE,  -- Can non-admin members invite others?
    show_leaderboard     BOOLEAN NOT NULL DEFAULT TRUE,   -- Show ranking or just progress?
    notifications_enabled BOOLEAN NOT NULL DEFAULT TRUE,  -- Send push notifications for milestones
    require_daily_checkin BOOLEAN NOT NULL DEFAULT FALSE,  -- Members must manually check in
    
    -- Stats (denormalized for fast queries)
    member_count    INT NOT NULL DEFAULT 0,
    total_completions INT NOT NULL DEFAULT 0,        -- total daily targets hit across all members
    
    -- Metadata
    status          TEXT NOT NULL DEFAULT 'active',  -- active, paused, ended, cancelled
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_private_challenges_join_code ON private_challenges(join_code);
CREATE INDEX IF NOT EXISTS idx_private_challenges_status ON private_challenges(status);
CREATE INDEX IF NOT EXISTS idx_private_challenges_created_by ON private_challenges(created_by);

-- ============================================================================
-- TABLE 2: private_challenge_members
-- ============================================================================
CREATE TABLE IF NOT EXISTS private_challenge_members (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    challenge_id    UUID NOT NULL REFERENCES private_challenges(id) ON DELETE CASCADE,
    user_id         UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
    
    -- Role: 'admin' (creator or promoted), 'member' (regular participant)
    role            TEXT NOT NULL DEFAULT 'member',  -- 'admin', 'member'
    
    -- Progress aggregates
    total_progress  INT NOT NULL DEFAULT 0,
    days_completed  INT NOT NULL DEFAULT 0,
    current_streak  INT NOT NULL DEFAULT 0,
    best_streak     INT NOT NULL DEFAULT 0,
    today_progress  INT NOT NULL DEFAULT 0,
    
    -- Participation metadata
    joined_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_active_at  TIMESTAMPTZ DEFAULT NOW(),
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    
    -- Who invited this member
    invited_by      UUID REFERENCES user_profiles(id),
    
    -- Notification preferences per-challenge
    mute_notifications BOOLEAN NOT NULL DEFAULT FALSE,
    
    UNIQUE(challenge_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_pcm_challenge_user ON private_challenge_members(challenge_id, user_id);
CREATE INDEX IF NOT EXISTS idx_pcm_challenge_active ON private_challenge_members(challenge_id, is_active);
CREATE INDEX IF NOT EXISTS idx_pcm_challenge_leaderboard ON private_challenge_members(challenge_id, today_progress DESC) WHERE is_active = TRUE;
CREATE INDEX IF NOT EXISTS idx_pcm_user_active ON private_challenge_members(user_id, is_active);
CREATE INDEX IF NOT EXISTS idx_pcm_role ON private_challenge_members(challenge_id, role) WHERE role = 'admin';

-- ============================================================================
-- TABLE 3: private_challenge_invites
-- ============================================================================
CREATE TABLE IF NOT EXISTS private_challenge_invites (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    challenge_id    UUID NOT NULL REFERENCES private_challenges(id) ON DELETE CASCADE,
    invited_user_id UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
    invited_by      UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
    
    status          TEXT NOT NULL DEFAULT 'pending',  -- 'pending', 'accepted', 'declined', 'expired'
    
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    responded_at    TIMESTAMPTZ,
    
    UNIQUE(challenge_id, invited_user_id)
);

CREATE INDEX IF NOT EXISTS idx_pci_invited_user ON private_challenge_invites(invited_user_id, status);
CREATE INDEX IF NOT EXISTS idx_pci_challenge ON private_challenge_invites(challenge_id, status);
CREATE INDEX IF NOT EXISTS idx_pci_invited_by ON private_challenge_invites(invited_by);

-- ============================================================================
-- TABLE 4: private_challenge_daily_progress
-- ============================================================================
CREATE TABLE IF NOT EXISTS private_challenge_daily_progress (
    challenge_id    UUID NOT NULL REFERENCES private_challenges(id) ON DELETE CASCADE,
    user_id         UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
    progress_date   DATE NOT NULL,
    progress_value  INT NOT NULL DEFAULT 0,
    target_hit      BOOLEAN NOT NULL DEFAULT FALSE,
    source          TEXT NOT NULL DEFAULT 'auto_sync',
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    PRIMARY KEY (challenge_id, user_id, progress_date)
);

CREATE INDEX IF NOT EXISTS idx_pcdp_date ON private_challenge_daily_progress(challenge_id, progress_date);
CREATE INDEX IF NOT EXISTS idx_pcdp_user ON private_challenge_daily_progress(user_id, progress_date);

-- ============================================================================
-- TABLE 5: private_challenge_chat
-- ============================================================================
CREATE TABLE IF NOT EXISTS private_challenge_chat (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    challenge_id    UUID NOT NULL REFERENCES private_challenges(id) ON DELETE CASCADE,
    sender_id       UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
    
    message_type    TEXT NOT NULL DEFAULT 'text',  -- 'text', 'milestone', 'system', 'reaction'
    content         TEXT NOT NULL,
    
    -- For milestone messages: "Mike just hit 10K steps! 🎉"
    metadata        JSONB,
    
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_pcc_challenge_date ON private_challenge_chat(challenge_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_pcc_sender ON private_challenge_chat(sender_id);

-- ============================================================================
-- RPC 1: create_private_challenge
-- ============================================================================
CREATE OR REPLACE FUNCTION create_private_challenge(
    p_challenge_type TEXT,
    p_title TEXT,
    p_description TEXT DEFAULT NULL,
    p_emoji TEXT DEFAULT '🔒',
    p_daily_target INT DEFAULT 10000,
    p_target_unit TEXT DEFAULT 'steps',
    p_is_recurring BOOLEAN DEFAULT TRUE,
    p_end_date TEXT DEFAULT NULL,
    p_max_members INT DEFAULT 50,
    p_allow_member_invites BOOLEAN DEFAULT FALSE,
    p_show_leaderboard BOOLEAN DEFAULT TRUE
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID;
    new_id UUID;
    v_join_code TEXT;
    v_end_date DATE;
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    -- Generate unique join code
    LOOP
        v_join_code := generate_join_code();
        EXIT WHEN NOT EXISTS (SELECT 1 FROM private_challenges WHERE join_code = v_join_code)
                  AND NOT EXISTS (SELECT 1 FROM community_challenges WHERE join_code = v_join_code);
    END LOOP;

    -- Parse end date
    IF p_end_date IS NOT NULL AND p_end_date != '' THEN
        v_end_date := p_end_date::DATE;
    ELSE
        v_end_date := NULL;
    END IF;

    -- Insert the private challenge
    INSERT INTO private_challenges (
        created_by, challenge_type, title, description, emoji,
        daily_target, target_unit, join_code,
        is_recurring, start_date, end_date, max_members,
        allow_member_invites, show_leaderboard,
        member_count, status
    ) VALUES (
        current_user_uuid, p_challenge_type, p_title, p_description, COALESCE(p_emoji, '🔒'),
        p_daily_target, p_target_unit, v_join_code,
        COALESCE(p_is_recurring, TRUE), CURRENT_DATE, v_end_date, p_max_members,
        COALESCE(p_allow_member_invites, FALSE), COALESCE(p_show_leaderboard, TRUE),
        1, 'active'
    )
    RETURNING id INTO new_id;

    -- Auto-join the creator as admin
    INSERT INTO private_challenge_members (
        challenge_id, user_id, role, is_active
    ) VALUES (
        new_id, current_user_uuid, 'admin', TRUE
    );

    -- Post system message
    INSERT INTO private_challenge_chat (
        challenge_id, sender_id, message_type, content
    ) VALUES (
        new_id, current_user_uuid, 'system', 'Challenge created! Invite your friends to join.'
    );

    RETURN new_id;
END;
$$;

GRANT EXECUTE ON FUNCTION create_private_challenge(TEXT, TEXT, TEXT, TEXT, INT, TEXT, BOOLEAN, TEXT, INT, BOOLEAN, BOOLEAN) TO authenticated;


-- ============================================================================
-- RPC 2: invite_to_private_challenge
-- ============================================================================
CREATE OR REPLACE FUNCTION invite_to_private_challenge(
    p_challenge_id TEXT,
    p_invited_user_id TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID;
    v_challenge_id UUID;
    v_invited_user_id UUID;
    v_role TEXT;
    v_allow_member_invites BOOLEAN;
    v_max_members INT;
    v_member_count INT;
    v_invite_id UUID;
    v_inviter_name TEXT;
    v_challenge_title TEXT;
BEGIN
    current_user_uuid := auth.uid();
    v_challenge_id := p_challenge_id::UUID;
    v_invited_user_id := p_invited_user_id::UUID;

    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    -- Check inviter is a member and get their role
    SELECT role INTO v_role
    FROM private_challenge_members
    WHERE challenge_id = v_challenge_id AND user_id = current_user_uuid AND is_active = TRUE;

    IF v_role IS NULL THEN
        RAISE EXCEPTION 'You are not a member of this challenge';
    END IF;

    -- Check if non-admin inviting is allowed
    SELECT allow_member_invites, max_members, member_count, title
    INTO v_allow_member_invites, v_max_members, v_member_count, v_challenge_title
    FROM private_challenges
    WHERE id = v_challenge_id AND status = 'active';

    IF v_role != 'admin' AND NOT v_allow_member_invites THEN
        RAISE EXCEPTION 'Only admins can invite members to this challenge';
    END IF;

    -- Check capacity
    IF v_max_members IS NOT NULL AND v_member_count >= v_max_members THEN
        RAISE EXCEPTION 'This challenge is full';
    END IF;

    -- Check if already a member
    IF EXISTS (
        SELECT 1 FROM private_challenge_members
        WHERE challenge_id = v_challenge_id AND user_id = v_invited_user_id AND is_active = TRUE
    ) THEN
        RAISE EXCEPTION 'User is already a member';
    END IF;

    -- Check if already invited (pending)
    IF EXISTS (
        SELECT 1 FROM private_challenge_invites
        WHERE challenge_id = v_challenge_id AND invited_user_id = v_invited_user_id AND status = 'pending'
    ) THEN
        RAISE EXCEPTION 'User already has a pending invite';
    END IF;

    -- Get inviter name for notifications
    SELECT name INTO v_inviter_name FROM user_profiles WHERE id = current_user_uuid;

    -- Create the invite (upsert: if previously declined, reset to pending)
    INSERT INTO private_challenge_invites (
        challenge_id, invited_user_id, invited_by, status, created_at, responded_at
    ) VALUES (
        v_challenge_id, v_invited_user_id, current_user_uuid, 'pending', NOW(), NULL
    )
    ON CONFLICT (challenge_id, invited_user_id) 
    DO UPDATE SET 
        status = 'pending',
        invited_by = current_user_uuid,
        created_at = NOW(),
        responded_at = NULL
    RETURNING id INTO v_invite_id;

    -- Insert notification record for the invited user
    INSERT INTO notifications (user_id, type, title, body, data, created_at)
    SELECT 
        v_invited_user_id,
        'private_challenge_invite',
        COALESCE(v_inviter_name, 'Someone') || ' invited you to join "' || v_challenge_title || '"',
        'Tap to view and accept the private challenge invite',
        jsonb_build_object(
            'challenge_id', v_challenge_id,
            'invite_id', v_invite_id,
            'inviter_id', current_user_uuid,
            'inviter_name', v_inviter_name,
            'challenge_title', v_challenge_title
        ),
        NOW()
    WHERE EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'notifications');

    RETURN v_invite_id;
END;
$$;

GRANT EXECUTE ON FUNCTION invite_to_private_challenge(TEXT, TEXT) TO authenticated;


-- ============================================================================
-- RPC 3: accept_private_challenge_invite
-- ============================================================================
CREATE OR REPLACE FUNCTION accept_private_challenge_invite(
    p_invite_id TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID;
    v_invite_id UUID;
    v_invite RECORD;
    v_user_name TEXT;
BEGIN
    current_user_uuid := auth.uid();
    v_invite_id := p_invite_id::UUID;

    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    -- Get invite details
    SELECT * INTO v_invite
    FROM private_challenge_invites
    WHERE id = v_invite_id AND invited_user_id = current_user_uuid AND status = 'pending';

    IF v_invite IS NULL THEN
        RAISE EXCEPTION 'Invite not found or already responded';
    END IF;

    -- Mark invite as accepted
    UPDATE private_challenge_invites
    SET status = 'accepted', responded_at = NOW()
    WHERE id = v_invite_id;

    -- Add member to challenge (upsert: reactivate if previously left)
    INSERT INTO private_challenge_members (
        challenge_id, user_id, role, is_active, invited_by, joined_at
    ) VALUES (
        v_invite.challenge_id, current_user_uuid, 'member', TRUE, v_invite.invited_by, NOW()
    )
    ON CONFLICT (challenge_id, user_id)
    DO UPDATE SET
        is_active = TRUE,
        joined_at = NOW(),
        invited_by = v_invite.invited_by,
        last_active_at = NOW();

    -- Update member count
    UPDATE private_challenges
    SET member_count = (
        SELECT COUNT(*) FROM private_challenge_members
        WHERE challenge_id = v_invite.challenge_id AND is_active = TRUE
    ),
    updated_at = NOW()
    WHERE id = v_invite.challenge_id;

    -- Get user name for system message
    SELECT name INTO v_user_name FROM user_profiles WHERE id = current_user_uuid;

    -- Post system message
    INSERT INTO private_challenge_chat (
        challenge_id, sender_id, message_type, content
    ) VALUES (
        v_invite.challenge_id, current_user_uuid, 'system',
        COALESCE(v_user_name, 'Someone') || ' joined the challenge!'
    );

    RETURN v_invite.challenge_id;
END;
$$;

GRANT EXECUTE ON FUNCTION accept_private_challenge_invite(TEXT) TO authenticated;


-- ============================================================================
-- RPC 4: decline_private_challenge_invite
-- ============================================================================
CREATE OR REPLACE FUNCTION decline_private_challenge_invite(
    p_invite_id TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID;
BEGIN
    current_user_uuid := auth.uid();

    UPDATE private_challenge_invites
    SET status = 'declined', responded_at = NOW()
    WHERE id = p_invite_id::UUID AND invited_user_id = current_user_uuid AND status = 'pending';

    RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION decline_private_challenge_invite(TEXT) TO authenticated;


-- ============================================================================
-- RPC 5: leave_private_challenge
-- ============================================================================
CREATE OR REPLACE FUNCTION leave_private_challenge(
    p_challenge_id TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID;
    v_challenge_id UUID;
    v_role TEXT;
    v_admin_count INT;
    v_user_name TEXT;
BEGIN
    current_user_uuid := auth.uid();
    v_challenge_id := p_challenge_id::UUID;

    -- Get member role
    SELECT role INTO v_role
    FROM private_challenge_members
    WHERE challenge_id = v_challenge_id AND user_id = current_user_uuid AND is_active = TRUE;

    -- If admin, check there's at least one other admin
    IF v_role = 'admin' THEN
        SELECT COUNT(*) INTO v_admin_count
        FROM private_challenge_members
        WHERE challenge_id = v_challenge_id AND role = 'admin' AND is_active = TRUE AND user_id != current_user_uuid;

        IF v_admin_count = 0 THEN
            -- Auto-promote the longest-serving member to admin
            UPDATE private_challenge_members
            SET role = 'admin'
            WHERE id = (
                SELECT id FROM private_challenge_members
                WHERE challenge_id = v_challenge_id AND is_active = TRUE AND user_id != current_user_uuid
                ORDER BY joined_at ASC
                LIMIT 1
            );
        END IF;
    END IF;

    -- Deactivate membership
    UPDATE private_challenge_members
    SET is_active = FALSE
    WHERE challenge_id = v_challenge_id AND user_id = current_user_uuid;

    -- Update member count
    UPDATE private_challenges
    SET member_count = GREATEST(0, member_count - 1), updated_at = NOW()
    WHERE id = v_challenge_id;

    -- Get user name for system message
    SELECT name INTO v_user_name FROM user_profiles WHERE id = current_user_uuid;

    -- Post system message
    INSERT INTO private_challenge_chat (
        challenge_id, sender_id, message_type, content
    ) VALUES (
        v_challenge_id, current_user_uuid, 'system',
        COALESCE(v_user_name, 'Someone') || ' left the challenge.'
    );

    RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION leave_private_challenge(TEXT) TO authenticated;


-- ============================================================================
-- RPC 6: remove_from_private_challenge
-- ============================================================================
CREATE OR REPLACE FUNCTION remove_from_private_challenge(
    p_challenge_id TEXT,
    p_user_id TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID;
    v_challenge_id UUID;
    v_target_user_id UUID;
    v_admin_role TEXT;
    v_removed_name TEXT;
BEGIN
    current_user_uuid := auth.uid();
    v_challenge_id := p_challenge_id::UUID;
    v_target_user_id := p_user_id::UUID;

    -- Check caller is admin
    SELECT role INTO v_admin_role
    FROM private_challenge_members
    WHERE challenge_id = v_challenge_id AND user_id = current_user_uuid AND is_active = TRUE;

    IF v_admin_role != 'admin' THEN
        RAISE EXCEPTION 'Only admins can remove members';
    END IF;

    -- Cannot remove yourself this way (use leave)
    IF current_user_uuid = v_target_user_id THEN
        RAISE EXCEPTION 'Use leave_private_challenge to leave';
    END IF;

    -- Deactivate membership
    UPDATE private_challenge_members
    SET is_active = FALSE
    WHERE challenge_id = v_challenge_id AND user_id = v_target_user_id;

    -- Revoke any pending invites
    UPDATE private_challenge_invites
    SET status = 'expired'
    WHERE challenge_id = v_challenge_id AND invited_user_id = v_target_user_id AND status = 'pending';

    -- Update member count
    UPDATE private_challenges
    SET member_count = GREATEST(0, member_count - 1), updated_at = NOW()
    WHERE id = v_challenge_id;

    -- System message
    SELECT name INTO v_removed_name FROM user_profiles WHERE id = v_target_user_id;
    INSERT INTO private_challenge_chat (challenge_id, sender_id, message_type, content)
    VALUES (v_challenge_id, current_user_uuid, 'system',
            COALESCE(v_removed_name, 'A member') || ' was removed from the challenge.');

    RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION remove_from_private_challenge(TEXT, TEXT) TO authenticated;


-- ============================================================================
-- RPC 7: update_private_challenge
-- ============================================================================
CREATE OR REPLACE FUNCTION update_private_challenge(
    p_challenge_id TEXT,
    p_title TEXT DEFAULT NULL,
    p_description TEXT DEFAULT NULL,
    p_emoji TEXT DEFAULT NULL,
    p_daily_target INT DEFAULT NULL,
    p_allow_member_invites BOOLEAN DEFAULT NULL,
    p_show_leaderboard BOOLEAN DEFAULT NULL,
    p_notifications_enabled BOOLEAN DEFAULT NULL,
    p_max_members INT DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID;
    v_challenge_id UUID;
    v_role TEXT;
    v_old_target INT;
BEGIN
    current_user_uuid := auth.uid();
    v_challenge_id := p_challenge_id::UUID;

    -- Check admin
    SELECT role INTO v_role
    FROM private_challenge_members
    WHERE challenge_id = v_challenge_id AND user_id = current_user_uuid AND is_active = TRUE;

    IF v_role != 'admin' THEN
        RAISE EXCEPTION 'Only admins can update this challenge';
    END IF;

    -- Get old target for change notification
    SELECT daily_target INTO v_old_target FROM private_challenges WHERE id = v_challenge_id;

    -- Update only non-null fields
    UPDATE private_challenges SET
        title = COALESCE(p_title, title),
        description = COALESCE(p_description, description),
        emoji = COALESCE(p_emoji, emoji),
        daily_target = COALESCE(p_daily_target, daily_target),
        allow_member_invites = COALESCE(p_allow_member_invites, allow_member_invites),
        show_leaderboard = COALESCE(p_show_leaderboard, show_leaderboard),
        notifications_enabled = COALESCE(p_notifications_enabled, notifications_enabled),
        max_members = COALESCE(p_max_members, max_members),
        updated_at = NOW()
    WHERE id = v_challenge_id;

    -- Post system message if target changed
    IF p_daily_target IS NOT NULL AND p_daily_target != v_old_target THEN
        INSERT INTO private_challenge_chat (challenge_id, sender_id, message_type, content)
        VALUES (v_challenge_id, current_user_uuid, 'system',
                'Daily target updated: ' || v_old_target || ' → ' || p_daily_target);
    END IF;

    RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION update_private_challenge(TEXT, TEXT, TEXT, TEXT, INT, BOOLEAN, BOOLEAN, BOOLEAN, INT) TO authenticated;


-- ============================================================================
-- RPC 8: promote_to_admin
-- ============================================================================
CREATE OR REPLACE FUNCTION promote_to_admin(
    p_challenge_id TEXT,
    p_user_id TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID;
    v_role TEXT;
    v_promoted_name TEXT;
BEGIN
    current_user_uuid := auth.uid();

    SELECT role INTO v_role
    FROM private_challenge_members
    WHERE challenge_id = p_challenge_id::UUID AND user_id = current_user_uuid AND is_active = TRUE;

    IF v_role != 'admin' THEN
        RAISE EXCEPTION 'Only admins can promote members';
    END IF;

    UPDATE private_challenge_members
    SET role = 'admin'
    WHERE challenge_id = p_challenge_id::UUID AND user_id = p_user_id::UUID AND is_active = TRUE;

    SELECT name INTO v_promoted_name FROM user_profiles WHERE id = p_user_id::UUID;
    INSERT INTO private_challenge_chat (challenge_id, sender_id, message_type, content)
    VALUES (p_challenge_id::UUID, current_user_uuid, 'system',
            COALESCE(v_promoted_name, 'A member') || ' is now a co-admin!');

    RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION promote_to_admin(TEXT, TEXT) TO authenticated;


-- ============================================================================
-- RPC 9: demote_from_admin
-- ============================================================================
CREATE OR REPLACE FUNCTION demote_from_admin(
    p_challenge_id TEXT,
    p_user_id TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID;
    v_role TEXT;
    v_challenge RECORD;
BEGIN
    current_user_uuid := auth.uid();

    -- Caller must be admin
    SELECT role INTO v_role
    FROM private_challenge_members
    WHERE challenge_id = p_challenge_id::UUID AND user_id = current_user_uuid AND is_active = TRUE;

    IF v_role != 'admin' THEN
        RAISE EXCEPTION 'Only admins can demote members';
    END IF;

    -- Can't demote the original creator
    SELECT * INTO v_challenge FROM private_challenges WHERE id = p_challenge_id::UUID;
    IF v_challenge.created_by = p_user_id::UUID THEN
        RAISE EXCEPTION 'Cannot demote the challenge creator';
    END IF;

    UPDATE private_challenge_members
    SET role = 'member'
    WHERE challenge_id = p_challenge_id::UUID AND user_id = p_user_id::UUID AND is_active = TRUE;

    RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION demote_from_admin(TEXT, TEXT) TO authenticated;


-- ============================================================================
-- RPC 10: log_private_challenge_progress
-- ============================================================================
CREATE OR REPLACE FUNCTION log_private_challenge_progress(
    p_challenge_id TEXT,
    p_progress INT,
    p_timezone TEXT DEFAULT 'UTC'
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID;
    v_challenge_id UUID;
    today_date DATE;
    v_daily_target INT;
    v_target_hit BOOLEAN;
    v_prev_target_hit BOOLEAN;
    v_user_name TEXT;
    v_challenge_title TEXT;
    v_notifications_enabled BOOLEAN;
BEGIN
    current_user_uuid := auth.uid();
    v_challenge_id := p_challenge_id::UUID;
    today_date := (NOW() AT TIME ZONE COALESCE(p_timezone, 'UTC'))::DATE;

    -- Get challenge info
    SELECT daily_target, title, notifications_enabled
    INTO v_daily_target, v_challenge_title, v_notifications_enabled
    FROM private_challenges WHERE id = v_challenge_id;

    v_target_hit := (v_daily_target IS NOT NULL AND p_progress >= v_daily_target);

    -- Check if target was already hit
    SELECT target_hit INTO v_prev_target_hit
    FROM private_challenge_daily_progress
    WHERE challenge_id = v_challenge_id AND user_id = current_user_uuid AND progress_date = today_date;

    -- Upsert daily progress
    INSERT INTO private_challenge_daily_progress (
        challenge_id, user_id, progress_date, progress_value, target_hit, source, updated_at
    ) VALUES (
        v_challenge_id, current_user_uuid, today_date, p_progress, v_target_hit, 'auto_sync', NOW()
    )
    ON CONFLICT (challenge_id, user_id, progress_date)
    DO UPDATE SET
        progress_value = GREATEST(private_challenge_daily_progress.progress_value, EXCLUDED.progress_value),
        target_hit = CASE 
            WHEN EXCLUDED.progress_value > private_challenge_daily_progress.progress_value 
            THEN EXCLUDED.target_hit
            ELSE private_challenge_daily_progress.target_hit
        END,
        updated_at = NOW()
    WHERE EXCLUDED.progress_value > private_challenge_daily_progress.progress_value;

    -- Update member aggregates
    UPDATE private_challenge_members
    SET 
        today_progress = p_progress,
        total_progress = (
            SELECT COALESCE(SUM(progress_value), 0)
            FROM private_challenge_daily_progress
            WHERE challenge_id = v_challenge_id AND user_id = current_user_uuid
        ),
        days_completed = (
            SELECT COUNT(*)
            FROM private_challenge_daily_progress
            WHERE challenge_id = v_challenge_id AND user_id = current_user_uuid AND target_hit = TRUE
        ),
        last_active_at = NOW()
    WHERE challenge_id = v_challenge_id AND user_id = current_user_uuid;

    -- If NEW completion, increment global and post milestone message
    IF v_target_hit AND (v_prev_target_hit IS NULL OR v_prev_target_hit = FALSE) THEN
        UPDATE private_challenges
        SET total_completions = total_completions + 1
        WHERE id = v_challenge_id;

        -- Post milestone message in chat
        SELECT name INTO v_user_name FROM user_profiles WHERE id = current_user_uuid;
        INSERT INTO private_challenge_chat (
            challenge_id, sender_id, message_type, content, metadata
        ) VALUES (
            v_challenge_id, current_user_uuid, 'milestone',
            COALESCE(v_user_name, 'Someone') || ' hit their daily goal! 🎉',
            jsonb_build_object('progress', p_progress, 'target', v_daily_target)
        );
    END IF;

    RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION log_private_challenge_progress(TEXT, INT, TEXT) TO authenticated;


-- ============================================================================
-- RPC 11: get_my_private_challenges
-- ============================================================================
CREATE OR REPLACE FUNCTION get_my_private_challenges(
    p_timezone TEXT DEFAULT 'UTC'
)
RETURNS TABLE (
    challenge_id UUID,
    title TEXT,
    description TEXT,
    emoji TEXT,
    challenge_type TEXT,
    daily_target INT,
    target_unit TEXT,
    member_count INT,
    max_members INT,
    join_code TEXT,
    is_recurring BOOLEAN,
    show_leaderboard BOOLEAN,
    allow_member_invites BOOLEAN,
    my_today_progress INT,
    my_days_completed INT,
    my_current_streak INT,
    my_role TEXT,
    my_rank INT,
    created_by UUID,
    creator_name TEXT,
    creator_username TEXT,
    status TEXT,
    -- Top 5 members for preview avatars
    top_members JSONB,
    -- Recent chat preview
    last_chat_message TEXT,
    last_chat_sender TEXT,
    last_chat_at TIMESTAMPTZ,
    unread_count INT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID;
    today_date DATE;
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    today_date := (NOW() AT TIME ZONE COALESCE(p_timezone, 'UTC'))::DATE;

    RETURN QUERY
    SELECT
        pc.id AS challenge_id,
        pc.title,
        pc.description,
        pc.emoji,
        pc.challenge_type,
        pc.daily_target,
        pc.target_unit,
        pc.member_count,
        pc.max_members,
        pc.join_code,
        pc.is_recurring,
        pc.show_leaderboard,
        pc.allow_member_invites,
        COALESCE(pcdp.progress_value, 0)::INT AS my_today_progress,
        pcm.days_completed::INT AS my_days_completed,
        pcm.current_streak::INT AS my_current_streak,
        pcm.role AS my_role,
        -- Rank
        (
            SELECT COUNT(*)::INT + 1
            FROM private_challenge_members other_pcm
            LEFT JOIN private_challenge_daily_progress other_pcdp
                ON other_pcdp.challenge_id = other_pcm.challenge_id
                AND other_pcdp.user_id = other_pcm.user_id
                AND other_pcdp.progress_date = today_date
            WHERE other_pcm.challenge_id = pc.id
            AND other_pcm.is_active = TRUE
            AND other_pcm.user_id != current_user_uuid
            AND COALESCE(other_pcdp.progress_value, 0) > COALESCE(pcdp.progress_value, 0)
        )::INT AS my_rank,
        pc.created_by,
        creator_up.name AS creator_name,
        creator_up.username AS creator_username,
        pc.status,
        -- Top 5 member avatars
        (
            SELECT jsonb_agg(member_info ORDER BY member_info->>'today_progress' DESC)
            FROM (
                SELECT jsonb_build_object(
                    'user_id', m.user_id,
                    'name', up2.name,
                    'username', up2.username,
                    'profile_photo_url', up2.profile_photo_url,
                    'role', m.role,
                    'today_progress', COALESCE(dp.progress_value, 0)
                ) AS member_info
                FROM private_challenge_members m
                JOIN user_profiles up2 ON up2.id = m.user_id
                LEFT JOIN private_challenge_daily_progress dp
                    ON dp.challenge_id = m.challenge_id AND dp.user_id = m.user_id AND dp.progress_date = today_date
                WHERE m.challenge_id = pc.id AND m.is_active = TRUE
                ORDER BY COALESCE(dp.progress_value, 0) DESC
                LIMIT 5
            ) sub
        ) AS top_members,
        -- Last chat message
        (SELECT pcc.content FROM private_challenge_chat pcc WHERE pcc.challenge_id = pc.id ORDER BY pcc.created_at DESC LIMIT 1) AS last_chat_message,
        (SELECT up3.name FROM private_challenge_chat pcc2 JOIN user_profiles up3 ON up3.id = pcc2.sender_id WHERE pcc2.challenge_id = pc.id ORDER BY pcc2.created_at DESC LIMIT 1) AS last_chat_sender,
        (SELECT pcc3.created_at FROM private_challenge_chat pcc3 WHERE pcc3.challenge_id = pc.id ORDER BY pcc3.created_at DESC LIMIT 1) AS last_chat_at,
        0::INT AS unread_count  -- Placeholder: implement with read receipts later
    FROM private_challenge_members pcm
    JOIN private_challenges pc ON pc.id = pcm.challenge_id
    JOIN user_profiles creator_up ON creator_up.id = pc.created_by
    LEFT JOIN private_challenge_daily_progress pcdp
        ON pcdp.challenge_id = pc.id AND pcdp.user_id = current_user_uuid AND pcdp.progress_date = today_date
    WHERE pcm.user_id = current_user_uuid
    AND pcm.is_active = TRUE
    AND pc.status = 'active'
    ORDER BY pcm.last_active_at DESC NULLS LAST;
END;
$$;

GRANT EXECUTE ON FUNCTION get_my_private_challenges(TEXT) TO authenticated;


-- ============================================================================
-- RPC 12: get_private_challenge_detail
-- ============================================================================
CREATE OR REPLACE FUNCTION get_private_challenge_detail(
    p_challenge_id TEXT,
    p_timezone TEXT DEFAULT 'UTC'
)
RETURNS TABLE (
    challenge_id UUID,
    title TEXT,
    description TEXT,
    emoji TEXT,
    challenge_type TEXT,
    daily_target INT,
    target_unit TEXT,
    member_count INT,
    max_members INT,
    join_code TEXT,
    is_recurring BOOLEAN,
    show_leaderboard BOOLEAN,
    allow_member_invites BOOLEAN,
    notifications_enabled BOOLEAN,
    total_completions INT,
    created_by UUID,
    status TEXT,
    created_at TIMESTAMPTZ,
    -- My stats
    my_today_progress INT,
    my_days_completed INT,
    my_current_streak INT,
    my_best_streak INT,
    my_total_progress INT,
    my_rank INT,
    my_role TEXT,
    -- Community stats
    avg_today_progress INT,
    top_today_progress INT,
    total_active_today INT,
    completion_rate_today DOUBLE PRECISION,
    -- Full leaderboard
    leaderboard JSONB,
    -- Pending invites count
    pending_invites_count INT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID;
    v_challenge_id UUID;
    today_date DATE;
BEGIN
    current_user_uuid := auth.uid();
    v_challenge_id := p_challenge_id::UUID;
    today_date := (NOW() AT TIME ZONE COALESCE(p_timezone, 'UTC'))::DATE;

    -- Verify user is a member
    IF NOT EXISTS (
        SELECT 1 FROM private_challenge_members
        WHERE challenge_id = v_challenge_id AND user_id = current_user_uuid AND is_active = TRUE
    ) THEN
        RAISE EXCEPTION 'You are not a member of this challenge';
    END IF;

    RETURN QUERY
    SELECT
        pc.id AS challenge_id,
        pc.title,
        pc.description,
        pc.emoji,
        pc.challenge_type,
        pc.daily_target,
        pc.target_unit,
        pc.member_count,
        pc.max_members,
        pc.join_code,
        pc.is_recurring,
        pc.show_leaderboard,
        pc.allow_member_invites,
        pc.notifications_enabled,
        pc.total_completions,
        pc.created_by,
        pc.status,
        pc.created_at,
        -- My stats
        COALESCE((SELECT dp.progress_value FROM private_challenge_daily_progress dp WHERE dp.challenge_id = v_challenge_id AND dp.user_id = current_user_uuid AND dp.progress_date = today_date), 0)::INT,
        COALESCE((SELECT m.days_completed FROM private_challenge_members m WHERE m.challenge_id = v_challenge_id AND m.user_id = current_user_uuid), 0)::INT,
        COALESCE((SELECT m.current_streak FROM private_challenge_members m WHERE m.challenge_id = v_challenge_id AND m.user_id = current_user_uuid), 0)::INT,
        COALESCE((SELECT m.best_streak FROM private_challenge_members m WHERE m.challenge_id = v_challenge_id AND m.user_id = current_user_uuid), 0)::INT,
        COALESCE((SELECT m.total_progress FROM private_challenge_members m WHERE m.challenge_id = v_challenge_id AND m.user_id = current_user_uuid), 0)::INT,
        (
            SELECT COUNT(*)::INT + 1
            FROM private_challenge_members other_m
            LEFT JOIN private_challenge_daily_progress other_dp
                ON other_dp.challenge_id = other_m.challenge_id AND other_dp.user_id = other_m.user_id AND other_dp.progress_date = today_date
            WHERE other_m.challenge_id = v_challenge_id AND other_m.is_active = TRUE AND other_m.user_id != current_user_uuid
            AND COALESCE(other_dp.progress_value, 0) > COALESCE(
                (SELECT dp2.progress_value FROM private_challenge_daily_progress dp2 WHERE dp2.challenge_id = v_challenge_id AND dp2.user_id = current_user_uuid AND dp2.progress_date = today_date), 0
            )
        )::INT,
        (SELECT m2.role FROM private_challenge_members m2 WHERE m2.challenge_id = v_challenge_id AND m2.user_id = current_user_uuid)::TEXT,
        -- Community stats
        COALESCE((SELECT AVG(COALESCE(dp3.progress_value, 0))::INT FROM private_challenge_members m3 LEFT JOIN private_challenge_daily_progress dp3 ON dp3.challenge_id = m3.challenge_id AND dp3.user_id = m3.user_id AND dp3.progress_date = today_date WHERE m3.challenge_id = v_challenge_id AND m3.is_active = TRUE), 0)::INT,
        COALESCE((SELECT MAX(COALESCE(dp4.progress_value, 0))::INT FROM private_challenge_members m4 LEFT JOIN private_challenge_daily_progress dp4 ON dp4.challenge_id = m4.challenge_id AND dp4.user_id = m4.user_id AND dp4.progress_date = today_date WHERE m4.challenge_id = v_challenge_id AND m4.is_active = TRUE), 0)::INT,
        (SELECT COUNT(*)::INT FROM private_challenge_daily_progress dp5 WHERE dp5.challenge_id = v_challenge_id AND dp5.progress_date = today_date AND dp5.progress_value > 0)::INT,
        CASE WHEN pc.member_count > 0 THEN
            (SELECT COUNT(*)::DOUBLE PRECISION / pc.member_count FROM private_challenge_daily_progress dp6 WHERE dp6.challenge_id = v_challenge_id AND dp6.progress_date = today_date AND dp6.target_hit = TRUE)
        ELSE 0 END,
        -- Full leaderboard
        (
            SELECT jsonb_agg(entry ORDER BY entry->>'rank')
            FROM (
                SELECT jsonb_build_object(
                    'rank', ROW_NUMBER() OVER (ORDER BY COALESCE(dp7.progress_value, 0) DESC, m5.days_completed DESC),
                    'user_id', m5.user_id,
                    'name', up5.name,
                    'username', up5.username,
                    'profile_photo_url', up5.profile_photo_url,
                    'role', m5.role,
                    'today_progress', COALESCE(dp7.progress_value, 0),
                    'days_completed', m5.days_completed,
                    'current_streak', m5.current_streak,
                    'best_streak', m5.best_streak,
                    'target_hit_today', COALESCE(dp7.target_hit, FALSE),
                    'is_current_user', (m5.user_id = current_user_uuid)
                ) AS entry
                FROM private_challenge_members m5
                JOIN user_profiles up5 ON up5.id = m5.user_id
                LEFT JOIN private_challenge_daily_progress dp7
                    ON dp7.challenge_id = m5.challenge_id AND dp7.user_id = m5.user_id AND dp7.progress_date = today_date
                WHERE m5.challenge_id = v_challenge_id AND m5.is_active = TRUE
                ORDER BY COALESCE(dp7.progress_value, 0) DESC, m5.days_completed DESC
            ) sub
        ) AS leaderboard,
        -- Pending invites count
        (SELECT COUNT(*)::INT FROM private_challenge_invites pci WHERE pci.challenge_id = v_challenge_id AND pci.status = 'pending')
    FROM private_challenges pc
    WHERE pc.id = v_challenge_id;
END;
$$;

GRANT EXECUTE ON FUNCTION get_private_challenge_detail(TEXT, TEXT) TO authenticated;


-- ============================================================================
-- RPC 13: get_private_challenge_invites_for_me
-- ============================================================================
CREATE OR REPLACE FUNCTION get_private_challenge_invites_for_me()
RETURNS TABLE (
    invite_id UUID,
    challenge_id UUID,
    challenge_title TEXT,
    challenge_emoji TEXT,
    challenge_type TEXT,
    daily_target INT,
    target_unit TEXT,
    member_count INT,
    inviter_id UUID,
    inviter_name TEXT,
    inviter_username TEXT,
    inviter_photo_url TEXT,
    created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID;
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    RETURN QUERY
    SELECT
        pci.id AS invite_id,
        pc.id AS challenge_id,
        pc.title AS challenge_title,
        pc.emoji AS challenge_emoji,
        pc.challenge_type,
        pc.daily_target,
        pc.target_unit,
        pc.member_count,
        pci.invited_by AS inviter_id,
        up.name AS inviter_name,
        up.username AS inviter_username,
        up.profile_photo_url AS inviter_photo_url,
        pci.created_at
    FROM private_challenge_invites pci
    JOIN private_challenges pc ON pc.id = pci.challenge_id
    JOIN user_profiles up ON up.id = pci.invited_by
    WHERE pci.invited_user_id = current_user_uuid
    AND pci.status = 'pending'
    AND pc.status = 'active'
    ORDER BY pci.created_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION get_private_challenge_invites_for_me() TO authenticated;


-- ============================================================================
-- RPC 14: send_private_challenge_message
-- ============================================================================
CREATE OR REPLACE FUNCTION send_private_challenge_message(
    p_challenge_id TEXT,
    p_content TEXT,
    p_message_type TEXT DEFAULT 'text'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID;
    v_message_id UUID;
BEGIN
    current_user_uuid := auth.uid();

    -- Verify membership
    IF NOT EXISTS (
        SELECT 1 FROM private_challenge_members
        WHERE challenge_id = p_challenge_id::UUID AND user_id = current_user_uuid AND is_active = TRUE
    ) THEN
        RAISE EXCEPTION 'You are not a member of this challenge';
    END IF;

    INSERT INTO private_challenge_chat (challenge_id, sender_id, message_type, content)
    VALUES (p_challenge_id::UUID, current_user_uuid, COALESCE(p_message_type, 'text'), p_content)
    RETURNING id INTO v_message_id;

    RETURN v_message_id;
END;
$$;

GRANT EXECUTE ON FUNCTION send_private_challenge_message(TEXT, TEXT, TEXT) TO authenticated;


-- ============================================================================
-- RPC 15: get_private_challenge_messages
-- ============================================================================
CREATE OR REPLACE FUNCTION get_private_challenge_messages(
    p_challenge_id TEXT,
    p_limit INT DEFAULT 50,
    p_before_id TEXT DEFAULT NULL
)
RETURNS TABLE (
    message_id UUID,
    sender_id UUID,
    sender_name TEXT,
    sender_username TEXT,
    sender_photo_url TEXT,
    message_type TEXT,
    content TEXT,
    metadata JSONB,
    created_at TIMESTAMPTZ,
    is_current_user BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID;
BEGIN
    current_user_uuid := auth.uid();

    -- Verify membership
    IF NOT EXISTS (
        SELECT 1 FROM private_challenge_members
        WHERE challenge_id = p_challenge_id::UUID AND user_id = current_user_uuid AND is_active = TRUE
    ) THEN
        RAISE EXCEPTION 'You are not a member of this challenge';
    END IF;

    RETURN QUERY
    SELECT
        pcc.id AS message_id,
        pcc.sender_id,
        up.name AS sender_name,
        up.username AS sender_username,
        up.profile_photo_url AS sender_photo_url,
        pcc.message_type,
        pcc.content,
        pcc.metadata,
        pcc.created_at,
        (pcc.sender_id = current_user_uuid) AS is_current_user
    FROM private_challenge_chat pcc
    JOIN user_profiles up ON up.id = pcc.sender_id
    WHERE pcc.challenge_id = p_challenge_id::UUID
    AND (p_before_id IS NULL OR pcc.id < p_before_id::UUID)
    ORDER BY pcc.created_at DESC
    LIMIT COALESCE(p_limit, 50);
END;
$$;

GRANT EXECUTE ON FUNCTION get_private_challenge_messages(TEXT, INT, TEXT) TO authenticated;


-- ============================================================================
-- RPC 16: end_private_challenge
-- ============================================================================
CREATE OR REPLACE FUNCTION end_private_challenge(
    p_challenge_id TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID;
    v_role TEXT;
BEGIN
    current_user_uuid := auth.uid();

    SELECT role INTO v_role
    FROM private_challenge_members
    WHERE challenge_id = p_challenge_id::UUID AND user_id = current_user_uuid AND is_active = TRUE;

    IF v_role != 'admin' THEN
        RAISE EXCEPTION 'Only admins can end this challenge';
    END IF;

    UPDATE private_challenges
    SET status = 'ended', end_date = CURRENT_DATE, updated_at = NOW()
    WHERE id = p_challenge_id::UUID;

    -- Post system message
    INSERT INTO private_challenge_chat (challenge_id, sender_id, message_type, content)
    VALUES (p_challenge_id::UUID, current_user_uuid, 'system', 'This challenge has ended. Great job everyone! 🏆');

    -- Expire all pending invites
    UPDATE private_challenge_invites
    SET status = 'expired'
    WHERE challenge_id = p_challenge_id::UUID AND status = 'pending';

    RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION end_private_challenge(TEXT) TO authenticated;


-- ============================================================================
-- RLS Policies
-- ============================================================================
ALTER TABLE private_challenges ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_challenge_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_challenge_invites ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_challenge_daily_progress ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_challenge_chat ENABLE ROW LEVEL SECURITY;

-- Private challenges: only members can view
CREATE POLICY "Members can view their private challenges"
    ON private_challenges FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM private_challenge_members pcm
            WHERE pcm.challenge_id = id AND pcm.user_id = auth.uid() AND pcm.is_active = TRUE
        )
    );

-- Also allow viewing if you have a pending invite
CREATE POLICY "Invited users can view challenge info"
    ON private_challenges FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM private_challenge_invites pci
            WHERE pci.challenge_id = id AND pci.invited_user_id = auth.uid() AND pci.status = 'pending'
        )
    );

-- Creator can update
CREATE POLICY "Admin can update their challenges"
    ON private_challenges FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM private_challenge_members pcm
            WHERE pcm.challenge_id = id AND pcm.user_id = auth.uid() AND pcm.role = 'admin' AND pcm.is_active = TRUE
        )
    );

-- Members can see other members
CREATE POLICY "Members can view other members"
    ON private_challenge_members FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM private_challenge_members my_pcm
            WHERE my_pcm.challenge_id = challenge_id AND my_pcm.user_id = auth.uid()
        )
    );

-- Invites: users can see their own invites
CREATE POLICY "Users can view their invites"
    ON private_challenge_invites FOR SELECT
    USING (invited_user_id = auth.uid() OR invited_by = auth.uid());

-- Members can also see challenge invites they sent
CREATE POLICY "Members can view challenge invites"
    ON private_challenge_invites FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM private_challenge_members pcm
            WHERE pcm.challenge_id = challenge_id AND pcm.user_id = auth.uid() AND pcm.role = 'admin'
        )
    );

-- Daily progress: members can see
CREATE POLICY "Members can view daily progress"
    ON private_challenge_daily_progress FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM private_challenge_members pcm
            WHERE pcm.challenge_id = challenge_id AND pcm.user_id = auth.uid()
        )
    );

-- Chat: members can view messages
CREATE POLICY "Members can view chat messages"
    ON private_challenge_chat FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM private_challenge_members pcm
            WHERE pcm.challenge_id = challenge_id AND pcm.user_id = auth.uid()
        )
    );

-- Enable realtime for instant updates
ALTER TABLE private_challenge_members REPLICA IDENTITY FULL;
ALTER TABLE private_challenge_invites REPLICA IDENTITY FULL;
ALTER TABLE private_challenge_daily_progress REPLICA IDENTITY FULL;
ALTER TABLE private_challenge_chat REPLICA IDENTITY FULL;


-- ============================================================================
-- SUMMARY
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '✅ PRIVATE CHALLENGES MIGRATION COMPLETE';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '';
    RAISE NOTICE '📌 Tables created:';
    RAISE NOTICE '   1. private_challenges';
    RAISE NOTICE '   2. private_challenge_members';
    RAISE NOTICE '   3. private_challenge_invites';
    RAISE NOTICE '   4. private_challenge_daily_progress';
    RAISE NOTICE '   5. private_challenge_chat';
    RAISE NOTICE '';
    RAISE NOTICE '📌 RPC Functions:';
    RAISE NOTICE '   1.  create_private_challenge';
    RAISE NOTICE '   2.  invite_to_private_challenge';
    RAISE NOTICE '   3.  accept_private_challenge_invite';
    RAISE NOTICE '   4.  decline_private_challenge_invite';
    RAISE NOTICE '   5.  leave_private_challenge';
    RAISE NOTICE '   6.  remove_from_private_challenge';
    RAISE NOTICE '   7.  update_private_challenge';
    RAISE NOTICE '   8.  promote_to_admin';
    RAISE NOTICE '   9.  demote_from_admin';
    RAISE NOTICE '   10. log_private_challenge_progress';
    RAISE NOTICE '   11. get_my_private_challenges';
    RAISE NOTICE '   12. get_private_challenge_detail';
    RAISE NOTICE '   13. get_private_challenge_invites_for_me';
    RAISE NOTICE '   14. send_private_challenge_message';
    RAISE NOTICE '   15. get_private_challenge_messages';
    RAISE NOTICE '   16. end_private_challenge';
    RAISE NOTICE '';
    RAISE NOTICE '🔒 RLS policies applied — private by default';
    RAISE NOTICE '📡 REPLICA IDENTITY FULL — real-time ready';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
END $$;
