-- ============================================================
-- GROUP CHALLENGES - Multi-person challenge support (up to 3)
-- ============================================================

-- 1. Group Challenges table
CREATE TABLE IF NOT EXISTS group_challenges (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    description TEXT,
    challenge_type TEXT NOT NULL,
    mode TEXT NOT NULL DEFAULT 'competition',
    daily_target INTEGER,
    total_target INTEGER,
    target_unit TEXT NOT NULL DEFAULT 'count',
    start_date DATE NOT NULL DEFAULT CURRENT_DATE,
    end_date DATE NOT NULL,
    duration_days INTEGER NOT NULL DEFAULT 7,
    status TEXT NOT NULL DEFAULT 'pending', -- pending, active, completed, cancelled
    created_by UUID NOT NULL REFERENCES auth.users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2. Group Challenge Members table
CREATE TABLE IF NOT EXISTS group_challenge_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    group_challenge_id UUID NOT NULL REFERENCES group_challenges(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id),
    status TEXT NOT NULL DEFAULT 'pending', -- pending, accepted, declined
    total_progress INTEGER NOT NULL DEFAULT 0,
    today_progress INTEGER NOT NULL DEFAULT 0,
    days_completed INTEGER NOT NULL DEFAULT 0,
    current_streak INTEGER NOT NULL DEFAULT 0,
    joined_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(group_challenge_id, user_id)
);

-- 3. Enable RLS
ALTER TABLE group_challenges ENABLE ROW LEVEL SECURITY;
ALTER TABLE group_challenge_members ENABLE ROW LEVEL SECURITY;

-- 4. RLS Policies
CREATE POLICY "Users can view their group challenges"
    ON group_challenges FOR SELECT
    USING (id IN (SELECT group_challenge_id FROM group_challenge_members WHERE user_id = auth.uid()));

CREATE POLICY "Users can create group challenges"
    ON group_challenges FOR INSERT
    WITH CHECK (created_by = auth.uid());

CREATE POLICY "Creator can update group challenges"
    ON group_challenges FOR UPDATE
    USING (created_by = auth.uid());

CREATE POLICY "Users can view members of their group challenges"
    ON group_challenge_members FOR SELECT
    USING (group_challenge_id IN (
        SELECT group_challenge_id FROM group_challenge_members WHERE user_id = auth.uid()
    ));

CREATE POLICY "Creator can add members"
    ON group_challenge_members FOR INSERT
    WITH CHECK (
        group_challenge_id IN (SELECT id FROM group_challenges WHERE created_by = auth.uid())
        OR user_id = auth.uid()
    );

CREATE POLICY "Users can update their own membership"
    ON group_challenge_members FOR UPDATE
    USING (user_id = auth.uid());

-- 5. Create Group Challenge RPC
CREATE OR REPLACE FUNCTION create_group_challenge(
    p_member_ids UUID[],
    p_challenge_type TEXT,
    p_title TEXT,
    p_description TEXT DEFAULT NULL,
    p_mode TEXT DEFAULT 'competition',
    p_daily_target INTEGER DEFAULT NULL,
    p_total_target INTEGER DEFAULT NULL,
    p_target_unit TEXT DEFAULT 'count',
    p_start_date DATE DEFAULT CURRENT_DATE,
    p_duration_days INTEGER DEFAULT 7
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
    v_challenge_id UUID;
    v_end_date DATE;
    v_member_id UUID;
BEGIN
    v_end_date := p_start_date + p_duration_days;

    -- Create the group challenge
    INSERT INTO group_challenges (
        title, description, challenge_type, mode,
        daily_target, total_target, target_unit,
        start_date, end_date, duration_days, status, created_by
    ) VALUES (
        p_title, p_description, p_challenge_type, p_mode,
        p_daily_target, p_total_target, p_target_unit,
        p_start_date, v_end_date, p_duration_days, 'pending', auth.uid()
    ) RETURNING id INTO v_challenge_id;

    -- Add creator as accepted member
    INSERT INTO group_challenge_members (group_challenge_id, user_id, status, joined_at)
    VALUES (v_challenge_id, auth.uid(), 'accepted', now());

    -- Add other members as pending
    FOREACH v_member_id IN ARRAY p_member_ids
    LOOP
        IF v_member_id != auth.uid() THEN
            INSERT INTO group_challenge_members (group_challenge_id, user_id, status)
            VALUES (v_challenge_id, v_member_id, 'pending');
        END IF;
    END LOOP;

    RETURN v_challenge_id;
END;
$$;

-- 6. Accept Group Challenge RPC
CREATE OR REPLACE FUNCTION accept_group_challenge(p_challenge_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
    v_all_accepted BOOLEAN;
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

    -- If all accepted, activate the challenge
    IF v_all_accepted THEN
        UPDATE group_challenges
        SET status = 'active', start_date = CURRENT_DATE, end_date = CURRENT_DATE + duration_days
        WHERE id = p_challenge_id;
    END IF;

    RETURN v_all_accepted;
END;
$$;

-- 7. Decline Group Challenge RPC
CREATE OR REPLACE FUNCTION decline_group_challenge(p_challenge_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
AS $$
BEGIN
    UPDATE group_challenge_members
    SET status = 'declined'
    WHERE group_challenge_id = p_challenge_id AND user_id = auth.uid();
END;
$$;

-- 8. Log Group Challenge Progress RPC
CREATE OR REPLACE FUNCTION log_group_challenge_progress(
    p_challenge_id UUID,
    p_progress INTEGER,
    p_date DATE DEFAULT CURRENT_DATE
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
AS $$
BEGIN
    UPDATE group_challenge_members
    SET today_progress = p_progress,
        total_progress = total_progress + p_progress,
        days_completed = CASE WHEN p_progress >= (
            SELECT daily_target FROM group_challenges WHERE id = p_challenge_id
        ) THEN days_completed + 1 ELSE days_completed END,
        current_streak = CASE WHEN p_progress >= (
            SELECT daily_target FROM group_challenges WHERE id = p_challenge_id
        ) THEN current_streak + 1 ELSE 0 END
    WHERE group_challenge_id = p_challenge_id AND user_id = auth.uid();
END;
$$;

-- 9. Get Active Group Challenges RPC
CREATE OR REPLACE FUNCTION get_active_group_challenges()
RETURNS TABLE (
    challenge_id UUID,
    title TEXT,
    description TEXT,
    challenge_type TEXT,
    mode TEXT,
    daily_target INTEGER,
    total_target INTEGER,
    target_unit TEXT,
    start_date DATE,
    end_date DATE,
    duration_days INTEGER,
    days_elapsed INTEGER,
    days_remaining INTEGER,
    status TEXT,
    created_by UUID,
    member_count INTEGER,
    members JSONB
)
LANGUAGE plpgsql SECURITY DEFINER STABLE
AS $$
BEGIN
    RETURN QUERY
    SELECT
        gc.id AS challenge_id,
        gc.title,
        gc.description,
        gc.challenge_type,
        gc.mode,
        gc.daily_target,
        gc.total_target,
        gc.target_unit,
        gc.start_date,
        gc.end_date,
        gc.duration_days,
        GREATEST(0, (CURRENT_DATE - gc.start_date)::INTEGER) AS days_elapsed,
        GREATEST(0, (gc.end_date - CURRENT_DATE)::INTEGER) AS days_remaining,
        gc.status,
        gc.created_by,
        (SELECT COUNT(*)::INTEGER FROM group_challenge_members WHERE group_challenge_id = gc.id) AS member_count,
        (
            SELECT jsonb_agg(jsonb_build_object(
                'user_id', m.user_id,
                'status', m.status,
                'total_progress', m.total_progress,
                'today_progress', m.today_progress,
                'days_completed', m.days_completed,
                'current_streak', m.current_streak,
                'name', COALESCE(p.name, p.username, p.email),
                'username', p.username,
                'profile_photo_url', p.profile_photo_url
            ) ORDER BY m.total_progress DESC)
            FROM group_challenge_members m
            JOIN user_profiles p ON p.id = m.user_id
            WHERE m.group_challenge_id = gc.id
        ) AS members
    FROM group_challenges gc
    WHERE gc.id IN (
        SELECT group_challenge_id FROM group_challenge_members WHERE user_id = auth.uid()
    )
    AND gc.status IN ('pending', 'active')
    ORDER BY gc.created_at DESC;
END;
$$;
