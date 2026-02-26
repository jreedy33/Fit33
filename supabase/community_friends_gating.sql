-- ============================================================================
-- COMMUNITY CHALLENGES: FRIENDS-CHAIN GATING & REAL-TIME DISCOVERY
-- Version: 1.18.0
-- Date: 2026-02-25
--
-- Changes the community challenge model from "public/anyone" to
-- "friends-chain" growth. Communities grow organically through social
-- connections: friends → friends-of-friends → their friends, etc.
--
-- KEY RULES:
--   1. You can JOIN a community challenge only if a direct friend,
--      mutual, or friend-of-friend is already a participant.
--   2. The creator is automatically the first participant (seed).
--   3. Once you join, YOUR friends can now join too (chain growth).
--   4. Communities are capped at 200 participants.
--   5. The dashboard shows which friends are in each community.
--   6. Real-time updates via Supabase Realtime on participant tables.
--
-- NEW / MODIFIED RPC FUNCTIONS:
--   1. get_discoverable_community_challenges — challenges my friends are in
--   2. join_community_challenge_friends — friend-gated join
--   3. get_friends_in_community_challenge — friend avatars for a challenge
--   4. get_community_challenge_detail — enriched detail with stats/encouragement
-- ============================================================================


-- ============================================================================
-- 0. ENSURE max_participants defaults to 200 for new challenges
-- ============================================================================
ALTER TABLE community_challenges
    ALTER COLUMN max_participants SET DEFAULT 200;

-- Set existing NULL max_participants to 200 (friend-gated cap)
UPDATE community_challenges
SET max_participants = 200
WHERE max_participants IS NULL;


-- ============================================================================
-- 1. HELPER: Check if two users are friends (accepted friendship)
-- ============================================================================
CREATE OR REPLACE FUNCTION are_friends(user_a UUID, user_b UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1 FROM friendships
        WHERE status = 'accepted'
          AND (
              (requester_id = user_a AND addressee_id = user_b)
              OR (requester_id = user_b AND addressee_id = user_a)
          )
    );
$$;


-- ============================================================================
-- 2. HELPER: Get all direct friend IDs for a user
-- ============================================================================
CREATE OR REPLACE FUNCTION get_friend_ids(p_user_id UUID)
RETURNS TABLE (friend_id UUID)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT 
        CASE 
            WHEN requester_id = p_user_id THEN addressee_id
            ELSE requester_id
        END AS friend_id
    FROM friendships
    WHERE status = 'accepted'
      AND (requester_id = p_user_id OR addressee_id = p_user_id);
$$;


-- ============================================================================
-- 3. HELPER: Check if user can join a community challenge
--    Returns TRUE if any current participant is:
--      - A direct friend of the user, OR
--      - A friend-of-friend (FoF) of the user
-- ============================================================================
CREATE OR REPLACE FUNCTION can_join_community_challenge(
    p_user_id UUID,
    p_challenge_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_is_creator BOOLEAN;
    v_has_direct_friend BOOLEAN;
    v_has_fof BOOLEAN;
BEGIN
    -- Creator can always rejoin
    SELECT EXISTS (
        SELECT 1 FROM community_challenges
        WHERE id = p_challenge_id AND created_by = p_user_id
    ) INTO v_is_creator;
    
    IF v_is_creator THEN RETURN TRUE; END IF;

    -- Check: any active participant is a DIRECT friend
    SELECT EXISTS (
        SELECT 1
        FROM community_challenge_participants ccp
        WHERE ccp.challenge_id = p_challenge_id
          AND ccp.is_active = TRUE
          AND are_friends(p_user_id, ccp.user_id)
    ) INTO v_has_direct_friend;

    IF v_has_direct_friend THEN RETURN TRUE; END IF;

    -- Check: any active participant is a FRIEND-OF-FRIEND
    -- (participant is friends with someone who is friends with me)
    SELECT EXISTS (
        SELECT 1
        FROM community_challenge_participants ccp
        WHERE ccp.challenge_id = p_challenge_id
          AND ccp.is_active = TRUE
          AND EXISTS (
              -- Find a mutual: someone who is friends with BOTH me and the participant
              SELECT 1
              FROM friendships f1
              JOIN friendships f2 ON TRUE
              WHERE f1.status = 'accepted'
                AND f2.status = 'accepted'
                -- f1: me ↔ mutual
                AND (
                    (f1.requester_id = p_user_id AND f1.addressee_id != ccp.user_id)
                    OR (f1.addressee_id = p_user_id AND f1.requester_id != ccp.user_id)
                )
                -- f2: mutual ↔ participant
                AND (
                    (f2.requester_id = ccp.user_id AND f2.addressee_id = CASE WHEN f1.requester_id = p_user_id THEN f1.addressee_id ELSE f1.requester_id END)
                    OR (f2.addressee_id = ccp.user_id AND f2.requester_id = CASE WHEN f1.requester_id = p_user_id THEN f1.addressee_id ELSE f1.requester_id END)
                )
          )
    ) INTO v_has_fof;

    RETURN v_has_fof;
END;
$$;


-- ============================================================================
-- 4. RPC: get_discoverable_community_challenges
--    Returns community challenges that the user's friends (or FoF) are in,
--    but the user has NOT joined yet. This powers the "Communities your
--    friends are in" discovery widget on the dashboard.
-- ============================================================================
DROP FUNCTION IF EXISTS get_discoverable_community_challenges(TEXT, INT);

CREATE OR REPLACE FUNCTION get_discoverable_community_challenges(
    p_timezone TEXT DEFAULT 'UTC',
    p_limit INT DEFAULT 10
)
RETURNS TABLE (
    challenge_id UUID,
    title TEXT,
    description TEXT,
    emoji TEXT,
    challenge_type TEXT,
    daily_target INT,
    target_unit TEXT,
    participant_count INT,
    max_participants INT,
    join_code TEXT,
    invite_slug TEXT,
    is_recurring BOOLEAN,
    is_featured BOOLEAN,
    is_official BOOLEAN,
    created_by UUID,
    -- Friends in this challenge (up to 5 avatars)
    friends_in_challenge JSONB,
    friends_count INT
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
    WITH my_friends AS (
        SELECT friend_id FROM get_friend_ids(current_user_uuid)
    ),
    -- Challenges that at least one friend is actively in
    friend_challenges AS (
        SELECT DISTINCT ccp.challenge_id,
            COUNT(DISTINCT ccp.user_id) FILTER (WHERE ccp.user_id IN (SELECT friend_id FROM my_friends))::INT AS friends_count
        FROM community_challenge_participants ccp
        WHERE ccp.is_active = TRUE
          AND ccp.user_id IN (SELECT friend_id FROM my_friends)
        GROUP BY ccp.challenge_id
    )
    SELECT
        cc.id AS challenge_id,
        cc.title,
        cc.description,
        cc.emoji,
        cc.challenge_type,
        cc.daily_target,
        cc.target_unit,
        cc.participant_count,
        cc.max_participants,
        cc.join_code,
        cc.invite_slug,
        cc.is_recurring,
        cc.is_featured,
        cc.is_official,
        cc.created_by,
        -- Up to 5 friend avatars
        (
            SELECT COALESCE(jsonb_agg(friend_info), '[]'::JSONB)
            FROM (
                SELECT jsonb_build_object(
                    'user_id', ccp2.user_id,
                    'name', up2.name,
                    'username', up2.username,
                    'profile_photo_url', up2.profile_photo_url
                ) AS friend_info
                FROM community_challenge_participants ccp2
                JOIN user_profiles up2 ON up2.id = ccp2.user_id
                WHERE ccp2.challenge_id = cc.id
                  AND ccp2.is_active = TRUE
                  AND ccp2.user_id IN (SELECT friend_id FROM my_friends)
                ORDER BY ccp2.joined_at ASC
                LIMIT 5
            ) sub
        ) AS friends_in_challenge,
        fc.friends_count
    FROM community_challenges cc
    JOIN friend_challenges fc ON fc.challenge_id = cc.id
    WHERE cc.status = 'active'
      -- User is NOT already a participant
      AND NOT EXISTS (
          SELECT 1 FROM community_challenge_participants ccp3
          WHERE ccp3.challenge_id = cc.id
            AND ccp3.user_id = current_user_uuid
            AND ccp3.is_active = TRUE
      )
      -- Not full
      AND (cc.max_participants IS NULL OR cc.participant_count < cc.max_participants)
    ORDER BY fc.friends_count DESC, cc.participant_count DESC
    LIMIT COALESCE(p_limit, 10);
END;
$$;

GRANT EXECUTE ON FUNCTION get_discoverable_community_challenges(TEXT, INT) TO authenticated;


-- ============================================================================
-- 5. RPC: join_community_challenge_friends
--    Friend-gated join. Checks that user has a friend/FoF in the challenge
--    before allowing them to join. Enforces 200-member cap.
-- ============================================================================
DROP FUNCTION IF EXISTS join_community_challenge_friends(TEXT, TEXT);

CREATE OR REPLACE FUNCTION join_community_challenge_friends(
    p_challenge_id TEXT,
    p_referred_by TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID;
    v_challenge_id UUID;
    v_challenge RECORD;
    v_referred_by_uuid UUID;
    v_eligible BOOLEAN;
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    v_challenge_id := p_challenge_id::UUID;

    -- Get the challenge
    SELECT * INTO v_challenge
    FROM community_challenges
    WHERE id = v_challenge_id AND status = 'active';

    IF v_challenge IS NULL THEN
        RAISE EXCEPTION 'Challenge not found or no longer active';
    END IF;

    -- Check capacity (default 200)
    IF v_challenge.max_participants IS NOT NULL
       AND v_challenge.participant_count >= v_challenge.max_participants THEN
        RAISE EXCEPTION 'This community is full (max % members)', v_challenge.max_participants;
    END IF;

    -- Check if already joined (reactivate if left)
    IF EXISTS (
        SELECT 1 FROM community_challenge_participants
        WHERE challenge_id = v_challenge_id AND user_id = current_user_uuid
    ) THEN
        UPDATE community_challenge_participants
        SET is_active = TRUE, last_active_at = NOW()
        WHERE challenge_id = v_challenge_id
          AND user_id = current_user_uuid
          AND is_active = FALSE;

        RETURN v_challenge_id;
    END IF;

    -- FRIEND ELIGIBILITY CHECK
    -- For 'public' visibility, skip friend check (backward compat for official challenges)
    IF v_challenge.visibility != 'public' THEN
        v_eligible := can_join_community_challenge(current_user_uuid, v_challenge_id);
        IF NOT v_eligible THEN
            RAISE EXCEPTION 'You need a friend or friend-of-friend in this community to join';
        END IF;
    END IF;

    -- Parse referrer
    IF p_referred_by IS NOT NULL AND p_referred_by != '' THEN
        v_referred_by_uuid := p_referred_by::UUID;
    END IF;

    -- Join
    INSERT INTO community_challenge_participants (
        challenge_id, user_id, referred_by, is_active
    ) VALUES (
        v_challenge_id, current_user_uuid, v_referred_by_uuid, TRUE
    );

    -- Update count
    UPDATE community_challenges
    SET participant_count = participant_count + 1,
        updated_at = NOW()
    WHERE id = v_challenge_id;

    RETURN v_challenge_id;
END;
$$;

GRANT EXECUTE ON FUNCTION join_community_challenge_friends(TEXT, TEXT) TO authenticated;


-- ============================================================================
-- 6. RPC: get_friends_in_community_challenge
--    Returns which of my friends are in a specific community challenge.
--    Used for the friend avatar row on widgets and detail views.
-- ============================================================================
DROP FUNCTION IF EXISTS get_friends_in_community_challenge(TEXT, TEXT);

CREATE OR REPLACE FUNCTION get_friends_in_community_challenge(
    p_challenge_id TEXT,
    p_timezone TEXT DEFAULT 'UTC'
)
RETURNS TABLE (
    user_id UUID,
    name TEXT,
    username TEXT,
    profile_photo_url TEXT,
    today_progress INT,
    days_completed INT,
    current_streak INT,
    best_streak INT,
    rank INT,
    is_direct_friend BOOLEAN
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
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    v_challenge_id := p_challenge_id::UUID;
    today_date := (NOW() AT TIME ZONE COALESCE(p_timezone, 'UTC'))::DATE;

    RETURN QUERY
    WITH ranked_participants AS (
        SELECT
            ccp.user_id,
            COALESCE(cdp.progress_value, 0) AS today_prog,
            ccp.days_completed,
            ccp.current_streak,
            ccp.best_streak,
            ROW_NUMBER() OVER (
                ORDER BY COALESCE(cdp.progress_value, 0) DESC, ccp.days_completed DESC
            )::INT AS rank
        FROM community_challenge_participants ccp
        LEFT JOIN community_challenge_daily_progress cdp
            ON cdp.challenge_id = ccp.challenge_id
            AND cdp.user_id = ccp.user_id
            AND cdp.progress_date = today_date
        WHERE ccp.challenge_id = v_challenge_id
          AND ccp.is_active = TRUE
    )
    SELECT
        rp.user_id,
        up.name,
        up.username,
        up.profile_photo_url,
        rp.today_prog::INT AS today_progress,
        rp.days_completed::INT,
        rp.current_streak::INT,
        rp.best_streak::INT,
        rp.rank,
        are_friends(current_user_uuid, rp.user_id) AS is_direct_friend
    FROM ranked_participants rp
    JOIN user_profiles up ON up.id = rp.user_id
    WHERE are_friends(current_user_uuid, rp.user_id)
    ORDER BY rp.rank ASC;
END;
$$;

GRANT EXECUTE ON FUNCTION get_friends_in_community_challenge(TEXT, TEXT) TO authenticated;


-- ============================================================================
-- 7. RPC: get_community_challenge_detail
--    Enriched detail view for a community challenge.
--    Includes: leaderboard, friend highlights, community stats, encouragement.
-- ============================================================================
DROP FUNCTION IF EXISTS get_community_challenge_detail(TEXT, TEXT);

CREATE OR REPLACE FUNCTION get_community_challenge_detail(
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
    participant_count INT,
    max_participants INT,
    join_code TEXT,
    invite_slug TEXT,
    is_recurring BOOLEAN,
    total_completions INT,
    -- My stats
    my_today_progress INT,
    my_days_completed INT,
    my_current_streak INT,
    my_best_streak INT,
    my_rank INT,
    my_total_progress INT,
    -- Community stats
    avg_today_progress INT,
    top_today_progress INT,
    avg_streak NUMERIC,
    total_active_today INT,
    completion_rate_today NUMERIC,
    -- Friends in challenge (avatars)
    friends_in JSONB,
    friends_count INT,
    -- Full leaderboard (top 10)
    top_leaderboard JSONB,
    -- Encouragement message
    encouragement TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID;
    v_challenge_id UUID;
    today_date DATE;
    v_my_today INT;
    v_my_days INT;
    v_my_streak INT;
    v_my_best INT;
    v_my_rank INT;
    v_my_total INT;
    v_avg_today INT;
    v_top_today INT;
    v_avg_streak NUMERIC;
    v_active_today INT;
    v_completion_rate NUMERIC;
    v_encouragement TEXT;
    v_participant_count INT;
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    v_challenge_id := p_challenge_id::UUID;
    today_date := (NOW() AT TIME ZONE COALESCE(p_timezone, 'UTC'))::DATE;

    -- Get participant count for this challenge
    SELECT cc.participant_count INTO v_participant_count
    FROM community_challenges cc WHERE cc.id = v_challenge_id;

    -- My stats
    SELECT
        COALESCE(cdp.progress_value, 0),
        ccp.days_completed,
        ccp.current_streak,
        ccp.best_streak,
        ccp.total_progress
    INTO v_my_today, v_my_days, v_my_streak, v_my_best, v_my_total
    FROM community_challenge_participants ccp
    LEFT JOIN community_challenge_daily_progress cdp
        ON cdp.challenge_id = ccp.challenge_id
        AND cdp.user_id = ccp.user_id
        AND cdp.progress_date = today_date
    WHERE ccp.challenge_id = v_challenge_id
      AND ccp.user_id = current_user_uuid;

    -- My rank
    SELECT COUNT(*)::INT + 1 INTO v_my_rank
    FROM community_challenge_participants other_ccp
    LEFT JOIN community_challenge_daily_progress other_cdp
        ON other_cdp.challenge_id = other_ccp.challenge_id
        AND other_cdp.user_id = other_ccp.user_id
        AND other_cdp.progress_date = today_date
    WHERE other_ccp.challenge_id = v_challenge_id
      AND other_ccp.is_active = TRUE
      AND other_ccp.user_id != current_user_uuid
      AND COALESCE(other_cdp.progress_value, 0) > COALESCE(v_my_today, 0);

    -- Community stats
    SELECT
        COALESCE(AVG(COALESCE(cdp.progress_value, 0)), 0)::INT,
        COALESCE(MAX(COALESCE(cdp.progress_value, 0)), 0)::INT,
        COALESCE(AVG(ccp.current_streak), 0),
        COUNT(*) FILTER (WHERE COALESCE(cdp.progress_value, 0) > 0)::INT,
        CASE
            WHEN COUNT(*) > 0 THEN
                (COUNT(*) FILTER (WHERE COALESCE(cdp.target_hit, FALSE) = TRUE)::NUMERIC / COUNT(*)::NUMERIC * 100)
            ELSE 0
        END
    INTO v_avg_today, v_top_today, v_avg_streak, v_active_today, v_completion_rate
    FROM community_challenge_participants ccp
    LEFT JOIN community_challenge_daily_progress cdp
        ON cdp.challenge_id = ccp.challenge_id
        AND cdp.user_id = ccp.user_id
        AND cdp.progress_date = today_date
    WHERE ccp.challenge_id = v_challenge_id
      AND ccp.is_active = TRUE;

    -- Generate encouragement message
    v_encouragement := CASE
        WHEN v_my_today IS NULL THEN
            '💪 Join your friends in this community challenge!'
        WHEN v_my_rank = 1 THEN
            '🏆 You''re leading this community! Keep crushing it!'
        WHEN v_my_rank <= 3 THEN
            '🔥 Top 3! You''re on fire — just a bit more to take the crown!'
        WHEN v_my_rank <= 5 THEN
            '💪 Top 5! You''re outperforming most of the community!'
        WHEN v_my_streak > 0 AND v_my_streak >= v_avg_streak THEN
            '🔥 ' || v_my_streak || '-day streak! You''re more consistent than the average!'
        WHEN COALESCE(v_my_today, 0) >= v_avg_today AND v_avg_today > 0 THEN
            '📈 You''re above the community average today — keep pushing!'
        WHEN COALESCE(v_my_today, 0) > 0 THEN
            '👏 Great start today! A little more to match the community average.'
        ELSE
            '⚡ Your friends are active today — time to log some progress!'
    END;

    RETURN QUERY
    SELECT
        cc.id AS challenge_id,
        cc.title,
        cc.description,
        cc.emoji,
        cc.challenge_type,
        cc.daily_target,
        cc.target_unit,
        cc.participant_count,
        cc.max_participants,
        cc.join_code,
        cc.invite_slug,
        cc.is_recurring,
        cc.total_completions,
        COALESCE(v_my_today, 0)::INT,
        COALESCE(v_my_days, 0)::INT,
        COALESCE(v_my_streak, 0)::INT,
        COALESCE(v_my_best, 0)::INT,
        COALESCE(v_my_rank, 0)::INT,
        COALESCE(v_my_total, 0)::INT,
        v_avg_today,
        v_top_today,
        v_avg_streak,
        v_active_today,
        v_completion_rate,
        -- Friends in challenge
        (
            SELECT COALESCE(jsonb_agg(fi), '[]'::JSONB)
            FROM (
                SELECT jsonb_build_object(
                    'user_id', ccp2.user_id,
                    'name', up2.name,
                    'username', up2.username,
                    'profile_photo_url', up2.profile_photo_url,
                    'today_progress', COALESCE(cdp2.progress_value, 0),
                    'current_streak', ccp2.current_streak
                ) AS fi
                FROM community_challenge_participants ccp2
                JOIN user_profiles up2 ON up2.id = ccp2.user_id
                LEFT JOIN community_challenge_daily_progress cdp2
                    ON cdp2.challenge_id = ccp2.challenge_id
                    AND cdp2.user_id = ccp2.user_id
                    AND cdp2.progress_date = today_date
                WHERE ccp2.challenge_id = cc.id
                  AND ccp2.is_active = TRUE
                  AND are_friends(current_user_uuid, ccp2.user_id)
                ORDER BY COALESCE(cdp2.progress_value, 0) DESC
                LIMIT 10
            ) sub
        ) AS friends_in,
        (
            SELECT COUNT(*)::INT
            FROM community_challenge_participants ccp3
            WHERE ccp3.challenge_id = cc.id
              AND ccp3.is_active = TRUE
              AND are_friends(current_user_uuid, ccp3.user_id)
        ) AS friends_count,
        -- Top 10 leaderboard
        (
            SELECT COALESCE(jsonb_agg(entry ORDER BY (entry->>'rank')::INT), '[]'::JSONB)
            FROM (
                SELECT jsonb_build_object(
                    'rank', ROW_NUMBER() OVER (ORDER BY COALESCE(cdp4.progress_value, 0) DESC, ccp4.days_completed DESC),
                    'user_id', ccp4.user_id,
                    'name', up4.name,
                    'username', up4.username,
                    'profile_photo_url', up4.profile_photo_url,
                    'today_progress', COALESCE(cdp4.progress_value, 0),
                    'days_completed', ccp4.days_completed,
                    'current_streak', ccp4.current_streak,
                    'best_streak', ccp4.best_streak,
                    'target_hit_today', COALESCE(cdp4.target_hit, FALSE),
                    'is_current_user', (ccp4.user_id = current_user_uuid),
                    'is_friend', are_friends(current_user_uuid, ccp4.user_id)
                ) AS entry
                FROM community_challenge_participants ccp4
                JOIN user_profiles up4 ON up4.id = ccp4.user_id
                LEFT JOIN community_challenge_daily_progress cdp4
                    ON cdp4.challenge_id = ccp4.challenge_id
                    AND cdp4.user_id = ccp4.user_id
                    AND cdp4.progress_date = today_date
                WHERE ccp4.challenge_id = cc.id AND ccp4.is_active = TRUE
                ORDER BY COALESCE(cdp4.progress_value, 0) DESC, ccp4.days_completed DESC
                LIMIT 10
            ) sub
        ) AS top_leaderboard,
        v_encouragement AS encouragement
    FROM community_challenges cc
    WHERE cc.id = v_challenge_id;
END;
$$;

GRANT EXECUTE ON FUNCTION get_community_challenge_detail(TEXT, TEXT) TO authenticated;


-- ============================================================================
-- 8. UPDATE get_my_community_challenges to include friends_in_challenge
--    Adds a friends_in JSONB with avatars of friends in each challenge.
-- ============================================================================
DROP FUNCTION IF EXISTS get_my_community_challenges(TEXT);

CREATE OR REPLACE FUNCTION get_my_community_challenges(
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
    participant_count INT,
    max_participants INT,
    join_code TEXT,
    invite_slug TEXT,
    is_recurring BOOLEAN,
    is_featured BOOLEAN,
    is_official BOOLEAN,
    my_today_progress INT,
    my_days_completed INT,
    my_current_streak INT,
    my_best_streak INT,
    my_rank INT,
    created_by UUID,
    creator_name TEXT,
    creator_username TEXT,
    top_participants JSONB,
    friends_in JSONB,
    friends_count INT
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
        cc.id AS challenge_id,
        cc.title,
        cc.description,
        cc.emoji,
        cc.challenge_type,
        cc.daily_target,
        cc.target_unit,
        cc.participant_count,
        cc.max_participants,
        cc.join_code,
        cc.invite_slug,
        cc.is_recurring,
        cc.is_featured,
        cc.is_official,
        COALESCE(cdp.progress_value, 0)::INT AS my_today_progress,
        ccp.days_completed::INT AS my_days_completed,
        ccp.current_streak::INT AS my_current_streak,
        ccp.best_streak::INT AS my_best_streak,
        (
            SELECT COUNT(*)::INT + 1
            FROM community_challenge_participants other_ccp
            LEFT JOIN community_challenge_daily_progress other_cdp
                ON other_cdp.challenge_id = other_ccp.challenge_id
                AND other_cdp.user_id = other_ccp.user_id
                AND other_cdp.progress_date = today_date
            WHERE other_ccp.challenge_id = cc.id
            AND other_ccp.is_active = TRUE
            AND other_ccp.user_id != current_user_uuid
            AND COALESCE(other_cdp.progress_value, 0) > COALESCE(cdp.progress_value, 0)
        )::INT AS my_rank,
        cc.created_by,
        creator_up.name AS creator_name,
        creator_up.username AS creator_username,
        -- Top 5-10 leaderboard snippet
        (
            SELECT COALESCE(jsonb_agg(entry ORDER BY (entry->>'rank')::INT), '[]'::JSONB)
            FROM (
                SELECT jsonb_build_object(
                    'rank', ROW_NUMBER() OVER (ORDER BY COALESCE(sub_cdp.progress_value, 0) DESC, sub_ccp.days_completed DESC),
                    'user_id', sub_ccp.user_id,
                    'name', sub_up.name,
                    'username', sub_up.username,
                    'profile_photo_url', sub_up.profile_photo_url,
                    'today_progress', COALESCE(sub_cdp.progress_value, 0),
                    'days_completed', sub_ccp.days_completed,
                    'current_streak', sub_ccp.current_streak,
                    'best_streak', sub_ccp.best_streak,
                    'target_hit_today', COALESCE(sub_cdp.target_hit, FALSE),
                    'is_current_user', (sub_ccp.user_id = current_user_uuid),
                    'is_friend', are_friends(current_user_uuid, sub_ccp.user_id)
                ) AS entry
                FROM community_challenge_participants sub_ccp
                JOIN user_profiles sub_up ON sub_up.id = sub_ccp.user_id
                LEFT JOIN community_challenge_daily_progress sub_cdp
                    ON sub_cdp.challenge_id = sub_ccp.challenge_id
                    AND sub_cdp.user_id = sub_ccp.user_id
                    AND sub_cdp.progress_date = today_date
                WHERE sub_ccp.challenge_id = cc.id AND sub_ccp.is_active = TRUE
                ORDER BY COALESCE(sub_cdp.progress_value, 0) DESC, sub_ccp.days_completed DESC
                LIMIT LEAST(10, GREATEST(5, cc.participant_count / 10))
            ) sub
        ) AS top_participants,
        -- Friends in this challenge (up to 5 avatars)
        (
            SELECT COALESCE(jsonb_agg(fi), '[]'::JSONB)
            FROM (
                SELECT jsonb_build_object(
                    'user_id', f_ccp.user_id,
                    'name', f_up.name,
                    'username', f_up.username,
                    'profile_photo_url', f_up.profile_photo_url
                ) AS fi
                FROM community_challenge_participants f_ccp
                JOIN user_profiles f_up ON f_up.id = f_ccp.user_id
                WHERE f_ccp.challenge_id = cc.id
                  AND f_ccp.is_active = TRUE
                  AND are_friends(current_user_uuid, f_ccp.user_id)
                ORDER BY f_ccp.joined_at ASC
                LIMIT 5
            ) sub2
        ) AS friends_in,
        (
            SELECT COUNT(*)::INT
            FROM community_challenge_participants f_ccp2
            WHERE f_ccp2.challenge_id = cc.id
              AND f_ccp2.is_active = TRUE
              AND are_friends(current_user_uuid, f_ccp2.user_id)
        )::INT AS friends_count
    FROM community_challenge_participants ccp
    JOIN community_challenges cc ON cc.id = ccp.challenge_id
    JOIN user_profiles creator_up ON creator_up.id = cc.created_by
    LEFT JOIN community_challenge_daily_progress cdp
        ON cdp.challenge_id = cc.id
        AND cdp.user_id = current_user_uuid
        AND cdp.progress_date = today_date
    WHERE ccp.user_id = current_user_uuid
    AND ccp.is_active = TRUE
    AND cc.status = 'active'
    ORDER BY cc.is_official DESC, cc.participant_count DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION get_my_community_challenges(TEXT) TO authenticated;


-- ============================================================================
-- 9. UPDATE create_community_challenge
--    Default visibility to 'friends' (chain-gated), cap at 200
-- ============================================================================
DROP FUNCTION IF EXISTS create_community_challenge(TEXT, TEXT, TEXT, TEXT, INT, TEXT, BOOLEAN, TEXT, INT, TEXT, TEXT);

CREATE OR REPLACE FUNCTION create_community_challenge(
    p_challenge_type TEXT,
    p_title TEXT,
    p_description TEXT DEFAULT NULL,
    p_emoji TEXT DEFAULT '🌍',
    p_daily_target INT DEFAULT 10000,
    p_target_unit TEXT DEFAULT 'steps',
    p_is_recurring BOOLEAN DEFAULT TRUE,
    p_end_date TEXT DEFAULT NULL,
    p_max_participants INT DEFAULT 200,
    p_visibility TEXT DEFAULT 'friends',
    p_category TEXT DEFAULT 'fitness'
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
    v_slug TEXT;
    v_end_date DATE;
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    -- Generate unique join code
    LOOP
        v_join_code := generate_join_code();
        EXIT WHEN NOT EXISTS (SELECT 1 FROM community_challenges WHERE join_code = v_join_code);
    END LOOP;

    v_slug := generate_challenge_slug(p_title);

    IF p_end_date IS NOT NULL AND p_end_date != '' THEN
        v_end_date := p_end_date::DATE;
    ELSE
        v_end_date := NULL;
    END IF;

    -- Enforce max 200 cap
    INSERT INTO community_challenges (
        created_by, challenge_type, title, description, emoji,
        daily_target, target_unit, join_code, invite_slug,
        is_recurring, start_date, end_date,
        max_participants,
        visibility, category, participant_count, status
    ) VALUES (
        current_user_uuid, p_challenge_type, p_title, p_description, COALESCE(p_emoji, '🌍'),
        p_daily_target, p_target_unit, v_join_code, v_slug,
        COALESCE(p_is_recurring, TRUE), CURRENT_DATE, v_end_date,
        LEAST(COALESCE(p_max_participants, 200), 200),  -- Hard cap at 200
        COALESCE(p_visibility, 'friends'), COALESCE(p_category, 'fitness'), 1, 'active'
    )
    RETURNING id INTO new_id;

    -- Auto-join creator
    INSERT INTO community_challenge_participants (
        challenge_id, user_id, is_active
    ) VALUES (
        new_id, current_user_uuid, TRUE
    );

    RETURN new_id;
END;
$$;

GRANT EXECUTE ON FUNCTION create_community_challenge(TEXT, TEXT, TEXT, TEXT, INT, TEXT, BOOLEAN, TEXT, INT, TEXT, TEXT) TO authenticated;


-- ============================================================================
-- 10. ENABLE REALTIME on community challenge tables
--     This allows live widget updates for all participants.
-- ============================================================================

-- Enable realtime replica identity for change tracking
ALTER TABLE community_challenge_participants REPLICA IDENTITY FULL;
ALTER TABLE community_challenge_daily_progress REPLICA IDENTITY FULL;
ALTER TABLE community_challenges REPLICA IDENTITY FULL;

-- Add tables to realtime publication (if supabase_realtime publication exists)
DO $$
BEGIN
    -- Try to add to realtime publication
    BEGIN
        ALTER PUBLICATION supabase_realtime ADD TABLE community_challenge_participants;
    EXCEPTION WHEN duplicate_object THEN
        RAISE NOTICE 'community_challenge_participants already in realtime publication';
    END;

    BEGIN
        ALTER PUBLICATION supabase_realtime ADD TABLE community_challenge_daily_progress;
    EXCEPTION WHEN duplicate_object THEN
        RAISE NOTICE 'community_challenge_daily_progress already in realtime publication';
    END;

    BEGIN
        ALTER PUBLICATION supabase_realtime ADD TABLE community_challenges;
    EXCEPTION WHEN duplicate_object THEN
        RAISE NOTICE 'community_challenges already in realtime publication';
    END;
END $$;


-- ============================================================================
-- 11. INDEXES for friend-based queries (performance)
-- ============================================================================
CREATE INDEX IF NOT EXISTS idx_friendships_accepted_requester
    ON friendships(requester_id) WHERE status = 'accepted';
CREATE INDEX IF NOT EXISTS idx_friendships_accepted_addressee
    ON friendships(addressee_id) WHERE status = 'accepted';
CREATE INDEX IF NOT EXISTS idx_ccp_active_user
    ON community_challenge_participants(user_id, challenge_id) WHERE is_active = TRUE;


-- ============================================================================
-- SUMMARY
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '✅ COMMUNITY FRIENDS-CHAIN GATING MIGRATION COMPLETE';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '';
    RAISE NOTICE '📌 Helper functions:';
    RAISE NOTICE '   - are_friends(user_a, user_b)';
    RAISE NOTICE '   - get_friend_ids(user_id)';
    RAISE NOTICE '   - can_join_community_challenge(user_id, challenge_id)';
    RAISE NOTICE '';
    RAISE NOTICE '📌 New RPC functions:';
    RAISE NOTICE '   1. get_discoverable_community_challenges — find challenges friends are in';
    RAISE NOTICE '   2. join_community_challenge_friends — friend-gated join';
    RAISE NOTICE '   3. get_friends_in_community_challenge — friend avatars per challenge';
    RAISE NOTICE '   4. get_community_challenge_detail — enriched detail + encouragement';
    RAISE NOTICE '';
    RAISE NOTICE '📌 Updated:';
    RAISE NOTICE '   - get_my_community_challenges — now includes friends_in + friends_count';
    RAISE NOTICE '   - create_community_challenge — defaults to friends visibility, 200 cap';
    RAISE NOTICE '';
    RAISE NOTICE '📡 Realtime enabled on:';
    RAISE NOTICE '   - community_challenge_participants';
    RAISE NOTICE '   - community_challenge_daily_progress';
    RAISE NOTICE '   - community_challenges';
    RAISE NOTICE '';
    RAISE NOTICE '🔑 KEY BEHAVIOR:';
    RAISE NOTICE '   - Friends-only communities grow via chain: friends → FoF → their friends';
    RAISE NOTICE '   - Hard cap at 200 members per community';
    RAISE NOTICE '   - Official/public challenges bypass friend check';
    RAISE NOTICE '   - Widgets show which friends are in each community';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
END $$;
