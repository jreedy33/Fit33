-- Add cover_image_url to private challenge RPCs
-- The column exists on private_challenges but was stripped from RPCs during the 2026-03-29 revert.
-- Re-adding it so challenge icon uploads display correctly.

-- ============================================================
-- 1. get_my_private_challenges — add cover_image_url after emoji
-- ============================================================
DROP FUNCTION IF EXISTS get_my_private_challenges(TEXT);

CREATE OR REPLACE FUNCTION get_my_private_challenges(p_timezone TEXT DEFAULT 'UTC')
RETURNS TABLE (
    challenge_id UUID,
    title TEXT,
    description TEXT,
    emoji TEXT,
    cover_image_url TEXT,
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
    top_members JSONB,
    last_chat_message TEXT,
    last_chat_sender TEXT,
    last_chat_at TIMESTAMPTZ,
    unread_count INT
)
LANGUAGE plpgsql SECURITY DEFINER AS $$
#variable_conflict use_column
DECLARE current_user_uuid UUID; today_date DATE;
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
    today_date := (NOW() AT TIME ZONE COALESCE(p_timezone, 'UTC'))::DATE;
    RETURN QUERY
    SELECT pc.id, pc.title, pc.description, pc.emoji, pc.cover_image_url, pc.challenge_type,
        pc.daily_target, pc.target_unit, pc.member_count, pc.max_members, pc.join_code,
        pc.is_recurring, pc.show_leaderboard, pc.allow_member_invites,
        COALESCE(pcdp.progress_value, 0)::INT, pcm.days_completed::INT,
        pcm.current_streak::INT, pcm.role,
        (SELECT COUNT(*)::INT + 1 FROM private_challenge_members other_pcm
            LEFT JOIN private_challenge_daily_progress other_pcdp ON other_pcdp.challenge_id = other_pcm.challenge_id
                AND other_pcdp.user_id = other_pcm.user_id AND other_pcdp.progress_date = today_date
            WHERE other_pcm.challenge_id = pc.id AND other_pcm.is_active = TRUE AND other_pcm.user_id != current_user_uuid
            AND COALESCE(other_pcdp.progress_value, 0) > COALESCE(pcdp.progress_value, 0))::INT,
        pc.created_by, creator_up.name, creator_up.username, pc.status,
        (SELECT jsonb_agg(member_info ORDER BY member_info->>'today_progress' DESC) FROM (
            SELECT jsonb_build_object(
                'user_id', m.user_id, 'name', up2.name, 'username', up2.username,
                'profile_photo_url', CASE WHEN COALESCE(up2.privacy_hide_photo, FALSE) THEN NULL ELSE up2.profile_photo_url END, 'role', m.role,
                'today_progress', COALESCE(dp.progress_value, 0),
                'is_verified', COALESCE(up2.is_verified, FALSE),
                'is_gold_verified', COALESCE(up2.is_gold_verified, FALSE)
            ) AS member_info
            FROM private_challenge_members m
            JOIN user_profiles up2 ON up2.id = m.user_id
            LEFT JOIN private_challenge_daily_progress dp ON dp.challenge_id = m.challenge_id AND dp.user_id = m.user_id AND dp.progress_date = today_date
            WHERE m.challenge_id = pc.id AND m.is_active = TRUE
            ORDER BY COALESCE(dp.progress_value, 0) DESC LIMIT 5
        ) sub),
        (SELECT pcc.content FROM private_challenge_chat pcc WHERE pcc.challenge_id = pc.id ORDER BY pcc.created_at DESC LIMIT 1),
        (SELECT up3.name FROM private_challenge_chat pcc2 JOIN user_profiles up3 ON up3.id = pcc2.sender_id WHERE pcc2.challenge_id = pc.id ORDER BY pcc2.created_at DESC LIMIT 1),
        (SELECT pcc3.created_at FROM private_challenge_chat pcc3 WHERE pcc3.challenge_id = pc.id ORDER BY pcc3.created_at DESC LIMIT 1),
        0::INT
    FROM private_challenge_members pcm
    JOIN private_challenges pc ON pc.id = pcm.challenge_id
    JOIN user_profiles creator_up ON creator_up.id = pc.created_by
    LEFT JOIN private_challenge_daily_progress pcdp ON pcdp.challenge_id = pc.id AND pcdp.user_id = current_user_uuid AND pcdp.progress_date = today_date
    WHERE pcm.user_id = current_user_uuid AND pcm.is_active = TRUE AND pc.status = 'active'
    ORDER BY pcm.last_active_at DESC NULLS LAST;
END;
$$;

-- ============================================================
-- 2. get_private_challenge_detail — add cover_image_url after emoji
-- ============================================================
DROP FUNCTION IF EXISTS get_private_challenge_detail(TEXT, TEXT);

CREATE OR REPLACE FUNCTION get_private_challenge_detail(p_challenge_id TEXT, p_timezone TEXT DEFAULT 'UTC')
RETURNS TABLE (
    challenge_id UUID,
    title TEXT,
    description TEXT,
    emoji TEXT,
    cover_image_url TEXT,
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
    my_today_progress INT,
    my_days_completed INT,
    my_current_streak INT,
    my_best_streak INT,
    my_total_progress INT,
    my_rank INT,
    my_role TEXT,
    avg_today_progress INT,
    top_today_progress INT,
    total_active_today INT,
    completion_rate_today DOUBLE PRECISION,
    leaderboard JSONB,
    pending_invites_count INT
)
LANGUAGE plpgsql SECURITY DEFINER AS $$
#variable_conflict use_column
DECLARE current_user_uuid UUID; v_challenge_id UUID; today_date DATE;
BEGIN
    current_user_uuid := auth.uid();
    v_challenge_id := p_challenge_id::UUID;
    today_date := (NOW() AT TIME ZONE COALESCE(p_timezone, 'UTC'))::DATE;
    IF NOT EXISTS (SELECT 1 FROM private_challenge_members pcm_check
        WHERE pcm_check.challenge_id = v_challenge_id AND pcm_check.user_id = current_user_uuid AND pcm_check.is_active = TRUE
    ) THEN RAISE EXCEPTION 'You are not a member of this challenge'; END IF;
    RETURN QUERY
    SELECT pc.id, pc.title, pc.description, pc.emoji, pc.cover_image_url, pc.challenge_type,
        pc.daily_target, pc.target_unit, pc.member_count, pc.max_members, pc.join_code,
        pc.is_recurring, pc.show_leaderboard, pc.allow_member_invites, pc.notifications_enabled,
        pc.total_completions, pc.created_by, pc.status, pc.created_at,
        COALESCE((SELECT dp.progress_value FROM private_challenge_daily_progress dp WHERE dp.challenge_id = v_challenge_id AND dp.user_id = current_user_uuid AND dp.progress_date = today_date), 0)::INT,
        COALESCE((SELECT m.days_completed FROM private_challenge_members m WHERE m.challenge_id = v_challenge_id AND m.user_id = current_user_uuid), 0)::INT,
        COALESCE((SELECT m.current_streak FROM private_challenge_members m WHERE m.challenge_id = v_challenge_id AND m.user_id = current_user_uuid), 0)::INT,
        COALESCE((SELECT m.best_streak FROM private_challenge_members m WHERE m.challenge_id = v_challenge_id AND m.user_id = current_user_uuid), 0)::INT,
        COALESCE((SELECT m.total_progress FROM private_challenge_members m WHERE m.challenge_id = v_challenge_id AND m.user_id = current_user_uuid), 0)::INT,
        (SELECT COUNT(*)::INT + 1 FROM private_challenge_members other_m
            LEFT JOIN private_challenge_daily_progress other_dp ON other_dp.challenge_id = other_m.challenge_id AND other_dp.user_id = other_m.user_id AND other_dp.progress_date = today_date
            WHERE other_m.challenge_id = v_challenge_id AND other_m.is_active = TRUE AND other_m.user_id != current_user_uuid
            AND COALESCE(other_dp.progress_value, 0) > COALESCE(
                (SELECT dp2.progress_value FROM private_challenge_daily_progress dp2 WHERE dp2.challenge_id = v_challenge_id AND dp2.user_id = current_user_uuid AND dp2.progress_date = today_date), 0
            ))::INT,
        (SELECT m2.role FROM private_challenge_members m2 WHERE m2.challenge_id = v_challenge_id AND m2.user_id = current_user_uuid)::TEXT,
        COALESCE((SELECT AVG(COALESCE(dp3.progress_value, 0))::INT FROM private_challenge_members m3 LEFT JOIN private_challenge_daily_progress dp3 ON dp3.challenge_id = m3.challenge_id AND dp3.user_id = m3.user_id AND dp3.progress_date = today_date WHERE m3.challenge_id = v_challenge_id AND m3.is_active = TRUE), 0)::INT,
        COALESCE((SELECT MAX(COALESCE(dp4.progress_value, 0))::INT FROM private_challenge_members m4 LEFT JOIN private_challenge_daily_progress dp4 ON dp4.challenge_id = m4.challenge_id AND dp4.user_id = m4.user_id AND dp4.progress_date = today_date WHERE m4.challenge_id = v_challenge_id AND m4.is_active = TRUE), 0)::INT,
        (SELECT COUNT(*)::INT FROM private_challenge_daily_progress dp5 WHERE dp5.challenge_id = v_challenge_id AND dp5.progress_date = today_date AND dp5.progress_value > 0)::INT,
        CASE WHEN pc.member_count > 0 THEN
            (SELECT COUNT(*)::DOUBLE PRECISION / pc.member_count FROM private_challenge_daily_progress dp6 WHERE dp6.challenge_id = v_challenge_id AND dp6.progress_date = today_date AND dp6.target_hit = TRUE)
        ELSE 0 END,
        (SELECT jsonb_agg(entry ORDER BY entry->>'rank') FROM (
            SELECT jsonb_build_object(
                'rank', ROW_NUMBER() OVER (ORDER BY COALESCE(dp7.progress_value, 0) DESC, m5.days_completed DESC),
                'user_id', m5.user_id, 'name', up5.name, 'username', up5.username,
                'profile_photo_url', CASE WHEN COALESCE(up5.privacy_hide_photo, FALSE) THEN NULL ELSE up5.profile_photo_url END, 'role', m5.role,
                'today_progress', COALESCE(dp7.progress_value, 0),
                'days_completed', m5.days_completed, 'current_streak', m5.current_streak,
                'best_streak', m5.best_streak,
                'target_hit_today', COALESCE(dp7.target_hit, FALSE),
                'is_current_user', (m5.user_id = current_user_uuid),
                'is_verified', COALESCE(up5.is_verified, FALSE),
                'is_gold_verified', COALESCE(up5.is_gold_verified, FALSE)
            ) AS entry
            FROM private_challenge_members m5
            JOIN user_profiles up5 ON up5.id = m5.user_id
            LEFT JOIN private_challenge_daily_progress dp7 ON dp7.challenge_id = m5.challenge_id AND dp7.user_id = m5.user_id AND dp7.progress_date = today_date
            WHERE m5.challenge_id = v_challenge_id AND m5.is_active = TRUE
            ORDER BY COALESCE(dp7.progress_value, 0) DESC, m5.days_completed DESC
        ) sub),
        (SELECT COUNT(*)::INT FROM private_challenge_invites pci WHERE pci.challenge_id = v_challenge_id AND pci.status = 'pending')
    FROM private_challenges pc WHERE pc.id = v_challenge_id;
END;
$$;
