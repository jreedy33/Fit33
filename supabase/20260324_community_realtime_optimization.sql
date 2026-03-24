-- ============================================================================
-- COMMUNITY REALTIME STATS OPTIMIZATION
-- Date: 2026-03-24
--
-- Improvements for community leaderboard real-time visibility:
-- 1. Composite index on updated_at for efficient "what changed since X?" queries
-- 2. Trigger to auto-update community_challenges.updated_at on any progress event
-- 3. Lightweight RPC to fetch leaderboard snippet for a single challenge
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. INDEX: Enable efficient "what changed since?" queries
-- ============================================================================
CREATE INDEX IF NOT EXISTS idx_ccdp_updated_at
ON community_challenge_daily_progress (updated_at DESC);

-- ============================================================================
-- 2. TRIGGER: Auto-update community_challenges.updated_at on progress events
--    When any participant logs progress, the parent challenge row is touched.
--    This allows "get challenges updated since X" queries to check one table
--    instead of joining daily_progress.
-- ============================================================================
CREATE OR REPLACE FUNCTION update_community_challenge_activity()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE community_challenges
    SET updated_at = NOW()
    WHERE id = NEW.challenge_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_community_progress_activity ON community_challenge_daily_progress;
CREATE TRIGGER trg_community_progress_activity
AFTER INSERT OR UPDATE ON community_challenge_daily_progress
FOR EACH ROW EXECUTE FUNCTION update_community_challenge_activity();

-- ============================================================================
-- 3. RPC: Lightweight single-challenge leaderboard snippet
--    Returns top N participants + caller's rank for ONE challenge.
--    Used for targeted refresh after realtime events instead of re-fetching
--    all challenges. Should be <50ms even for 200-member communities.
-- ============================================================================
DROP FUNCTION IF EXISTS get_single_community_leaderboard_snippet(TEXT, INT, TEXT);

CREATE OR REPLACE FUNCTION get_single_community_leaderboard_snippet(
    p_challenge_id TEXT,
    p_limit INT DEFAULT 10,
    p_timezone TEXT DEFAULT 'America/New_York'
)
RETURNS TABLE (
    challenge_id UUID,
    my_today_progress INT,
    my_rank INT,
    my_current_streak INT,
    my_best_streak INT,
    participant_count INT,
    top_participants JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID := auth.uid();
    today_date DATE := (NOW() AT TIME ZONE p_timezone)::DATE;
    v_challenge_id UUID := p_challenge_id::UUID;
BEGIN
    RETURN QUERY
    SELECT
        cc.id AS challenge_id,
        COALESCE(cdp.progress_value, 0)::INT AS my_today_progress,
        (
            SELECT COUNT(*)::INT + 1
            FROM community_challenge_participants other_ccp
            LEFT JOIN community_challenge_daily_progress other_cdp
                ON other_cdp.challenge_id = other_ccp.challenge_id
                AND other_cdp.user_id = other_ccp.user_id
                AND other_cdp.progress_date = today_date
            WHERE other_ccp.challenge_id = v_challenge_id
            AND other_ccp.is_active = TRUE
            AND other_ccp.user_id != current_user_uuid
            AND COALESCE(other_cdp.progress_value, 0) > COALESCE(cdp.progress_value, 0)
        )::INT AS my_rank,
        ccp.current_streak::INT AS my_current_streak,
        ccp.best_streak::INT AS my_best_streak,
        cc.participant_count::INT AS participant_count,
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
                WHERE sub_ccp.challenge_id = v_challenge_id AND sub_ccp.is_active = TRUE
                ORDER BY COALESCE(sub_cdp.progress_value, 0) DESC, sub_ccp.days_completed DESC
                LIMIT p_limit
            ) sub
        ) AS top_participants
    FROM community_challenges cc
    JOIN community_challenge_participants ccp
        ON ccp.challenge_id = cc.id AND ccp.user_id = current_user_uuid AND ccp.is_active = TRUE
    LEFT JOIN community_challenge_daily_progress cdp
        ON cdp.challenge_id = cc.id
        AND cdp.user_id = current_user_uuid
        AND cdp.progress_date = today_date
    WHERE cc.id = v_challenge_id;
END;
$$;

GRANT EXECUTE ON FUNCTION get_single_community_leaderboard_snippet(TEXT, INT, TEXT) TO authenticated;

COMMIT;
