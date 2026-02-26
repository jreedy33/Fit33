-- ============================================================================
-- UPGRADE: Community Challenge Leaderboard Widgets
-- Version: 1.17.0
-- Date: 2026-02-25
--
-- Upgrades get_my_community_challenges to include a top-N leaderboard snippet
-- per challenge, so the client can render mini-leaderboard widgets without
-- making separate RPC calls for each challenge.
--
-- Also upgrades get_community_challenge_leaderboard to include best_streak
-- and completion_rate in each leaderboard entry.
-- ============================================================================

-- ============================================================================
-- 1. UPGRADED get_my_community_challenges
--    Now returns `top_participants` JSONB array (top 5) per challenge
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
    top_participants JSONB
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
        -- Top 5 leaderboard snippet
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
                    'is_current_user', (sub_ccp.user_id = current_user_uuid)
                ) AS entry
                FROM community_challenge_participants sub_ccp
                JOIN user_profiles sub_up ON sub_up.id = sub_ccp.user_id
                LEFT JOIN community_challenge_daily_progress sub_cdp 
                    ON sub_cdp.challenge_id = sub_ccp.challenge_id 
                    AND sub_cdp.user_id = sub_ccp.user_id 
                    AND sub_cdp.progress_date = today_date
                WHERE sub_ccp.challenge_id = cc.id AND sub_ccp.is_active = TRUE
                ORDER BY COALESCE(sub_cdp.progress_value, 0) DESC, sub_ccp.days_completed DESC
                LIMIT LEAST(
                    10,
                    GREATEST(5, cc.participant_count / 10)
                )
            ) sub
        ) AS top_participants
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
-- 2. UPGRADED get_community_challenge_leaderboard
--    Now includes best_streak and completion_rate in each leaderboard entry
-- ============================================================================
DROP FUNCTION IF EXISTS get_community_challenge_leaderboard(TEXT, INT, TEXT);

CREATE OR REPLACE FUNCTION get_community_challenge_leaderboard(
    p_challenge_id TEXT,
    p_limit INT DEFAULT 50,
    p_timezone TEXT DEFAULT 'UTC'
)
RETURNS TABLE (
    challenge_id UUID,
    challenge_title TEXT,
    challenge_emoji TEXT,
    challenge_type TEXT,
    daily_target INT,
    target_unit TEXT,
    participant_count INT,
    join_code TEXT,
    invite_slug TEXT,
    leaderboard JSONB,
    my_rank INT,
    my_today_progress INT,
    my_days_completed INT,
    my_current_streak INT,
    my_best_streak INT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID;
    v_challenge_id UUID;
    today_date DATE;
    v_my_rank INT;
    v_my_today INT;
    v_my_days INT;
    v_my_streak INT;
    v_my_best INT;
BEGIN
    current_user_uuid := auth.uid();
    v_challenge_id := p_challenge_id::UUID;
    today_date := (NOW() AT TIME ZONE COALESCE(p_timezone, 'UTC'))::DATE;

    -- Calculate my rank
    SELECT ranked.rank, ranked.today_progress, ranked.days_completed, ranked.current_streak, ranked.best_streak
    INTO v_my_rank, v_my_today, v_my_days, v_my_streak, v_my_best
    FROM (
        SELECT 
            ccp.user_id,
            COALESCE(cdp.progress_value, 0) AS today_progress,
            ccp.days_completed,
            ccp.current_streak,
            ccp.best_streak,
            ROW_NUMBER() OVER (ORDER BY COALESCE(cdp.progress_value, 0) DESC, ccp.days_completed DESC) AS rank
        FROM community_challenge_participants ccp
        LEFT JOIN community_challenge_daily_progress cdp 
            ON cdp.challenge_id = ccp.challenge_id 
            AND cdp.user_id = ccp.user_id 
            AND cdp.progress_date = today_date
        WHERE ccp.challenge_id = v_challenge_id AND ccp.is_active = TRUE
    ) ranked
    WHERE ranked.user_id = current_user_uuid;

    RETURN QUERY
    SELECT
        cc.id AS challenge_id,
        cc.title AS challenge_title,
        cc.emoji AS challenge_emoji,
        cc.challenge_type,
        cc.daily_target,
        cc.target_unit,
        cc.participant_count,
        cc.join_code,
        cc.invite_slug,
        -- Top N leaderboard with enriched data
        (
            SELECT COALESCE(jsonb_agg(entry ORDER BY (entry->>'rank')::INT), '[]'::JSONB)
            FROM (
                SELECT jsonb_build_object(
                    'rank', ROW_NUMBER() OVER (ORDER BY COALESCE(cdp.progress_value, 0) DESC, ccp.days_completed DESC),
                    'user_id', ccp.user_id,
                    'name', up.name,
                    'username', up.username,
                    'profile_photo_url', up.profile_photo_url,
                    'today_progress', COALESCE(cdp.progress_value, 0),
                    'days_completed', ccp.days_completed,
                    'current_streak', ccp.current_streak,
                    'best_streak', ccp.best_streak,
                    'target_hit_today', COALESCE(cdp.target_hit, FALSE),
                    'total_progress', ccp.total_progress,
                    'is_current_user', (ccp.user_id = current_user_uuid)
                ) AS entry
                FROM community_challenge_participants ccp
                JOIN user_profiles up ON up.id = ccp.user_id
                LEFT JOIN community_challenge_daily_progress cdp 
                    ON cdp.challenge_id = ccp.challenge_id 
                    AND cdp.user_id = ccp.user_id 
                    AND cdp.progress_date = today_date
                WHERE ccp.challenge_id = v_challenge_id AND ccp.is_active = TRUE
                ORDER BY COALESCE(cdp.progress_value, 0) DESC, ccp.days_completed DESC
                LIMIT p_limit
            ) sub
        ) AS leaderboard,
        COALESCE(v_my_rank, 0)::INT AS my_rank,
        COALESCE(v_my_today, 0)::INT AS my_today_progress,
        COALESCE(v_my_days, 0)::INT AS my_days_completed,
        COALESCE(v_my_streak, 0)::INT AS my_current_streak,
        COALESCE(v_my_best, 0)::INT AS my_best_streak
    FROM community_challenges cc
    WHERE cc.id = v_challenge_id;
END;
$$;

GRANT EXECUTE ON FUNCTION get_community_challenge_leaderboard(TEXT, INT, TEXT) TO authenticated;
