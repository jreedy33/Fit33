-- ============================================================================
-- 20260508 — Community challenge user-id-filtered leaderboard
--
-- Adds: get_community_challenge_user_leaderboard(UUID, UUID[], TEXT, INT)
--
-- WHY:
--   The onboarding tutorial Community step now renders the full
--   `CommunityLeaderboardWidget` BEFORE the user joins (previously this
--   widget only showed post-join). The user wants the leaderboard rows
--   inside that preview to be populated with their synced contacts /
--   PYMK members showing REAL scores ("contacts and people they know"),
--   not random global top scorers.
--
--   `get_community_challenge_detail` already returns a top-10 leaderboard,
--   but it's globally-sorted by today's progress and not filterable to a
--   user-id list. Filtering client-side would just hide non-contact rows
--   without surfacing contacts who scored too low to make the top 10.
--
--   This RPC takes a `p_user_ids UUID[]` (the caller's PYMK + contacts
--   list, already privacy-cleared by `get_people_you_may_know` /
--   `ContactsService.suggestedFriends`) and returns the leaderboard rows
--   for ONLY those user IDs in the given community, with their real
--   today-progress / streak / target-hit data.
--
-- PRIVACY POSTURE:
--   - `p_user_ids` is caller-supplied; same trust model as
--     `get_discoverable_community_challenges_for_users` (#197). The PII
--     surfaced (name / username / profile_photo_url) is the same surface
--     the caller already saw via PYMK / contacts-on-Fit33.
--   - `today_progress` for a community participant is NOT incremental
--     disclosure — `get_community_challenge_detail` already returns the
--     global top-10 with today-progress to any authenticated caller
--     without requiring participation. We're just providing a filter
--     onto that already-public surface.
--   - `p_user_ids` capped at 100 to bound probing surface.
--   - Caller's own UUID is filtered out defense-in-depth so they don't
--     show up in their own preview leaderboard.
--
-- IDEMPOTENT — safe to re-run.
-- ============================================================================

BEGIN;

-- Drop any prior overloads so PostgREST doesn't see two ambiguous signatures.
DROP FUNCTION IF EXISTS get_community_challenge_user_leaderboard(UUID, UUID[], TEXT, INT);
DROP FUNCTION IF EXISTS get_community_challenge_user_leaderboard(UUID, UUID[], TEXT);
DROP FUNCTION IF EXISTS get_community_challenge_user_leaderboard(UUID, UUID[]);

CREATE OR REPLACE FUNCTION get_community_challenge_user_leaderboard(
    p_challenge_id UUID,
    p_user_ids UUID[],
    p_timezone TEXT DEFAULT 'UTC',
    p_limit INT DEFAULT 10
)
RETURNS TABLE (
    rank INT,
    user_id UUID,
    name TEXT,
    username TEXT,
    profile_photo_url TEXT,
    today_progress INT,
    days_completed INT,
    current_streak INT,
    best_streak INT,
    target_hit_today BOOLEAN,
    is_current_user BOOLEAN
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

    -- Empty / NULL list short-circuits to no rows.
    IF p_user_ids IS NULL OR array_length(p_user_ids, 1) IS NULL THEN
        RETURN;
    END IF;

    -- Bound probing surface — PYMK caps at 20, contacts at a few hundred
    -- typical; 100 covers the tutorial's needs. Mirrors #197.
    IF array_length(p_user_ids, 1) > 100 THEN
        RAISE EXCEPTION 'Too many user ids' USING ERRCODE = '22023';
    END IF;

    today_date := (NOW() AT TIME ZONE COALESCE(NULLIF(p_timezone, ''), 'UTC'))::DATE;

    RETURN QUERY
    SELECT
        ROW_NUMBER() OVER (
            ORDER BY COALESCE(cdp.progress_value, 0) DESC, ccp.days_completed DESC
        )::INT AS rank,
        ccp.user_id,
        up.name,
        up.username,
        up.profile_photo_url,
        COALESCE(cdp.progress_value, 0)::INT AS today_progress,
        ccp.days_completed::INT AS days_completed,
        ccp.current_streak::INT AS current_streak,
        ccp.best_streak::INT AS best_streak,
        COALESCE(cdp.target_hit, FALSE) AS target_hit_today,
        FALSE AS is_current_user
    FROM community_challenge_participants ccp
    JOIN user_profiles up ON up.id = ccp.user_id
    LEFT JOIN community_challenge_daily_progress cdp
        ON cdp.challenge_id = ccp.challenge_id
        AND cdp.user_id = ccp.user_id
        AND cdp.progress_date = today_date
    WHERE ccp.challenge_id = p_challenge_id
      AND ccp.is_active = TRUE
      AND ccp.user_id = ANY(p_user_ids)
      AND ccp.user_id <> current_user_uuid
    ORDER BY COALESCE(cdp.progress_value, 0) DESC, ccp.days_completed DESC
    LIMIT GREATEST(1, COALESCE(p_limit, 10));
END;
$$;

GRANT EXECUTE ON FUNCTION get_community_challenge_user_leaderboard(UUID, UUID[], TEXT, INT) TO authenticated;

COMMENT ON FUNCTION get_community_challenge_user_leaderboard(UUID, UUID[], TEXT, INT) IS
    'Returns the leaderboard rows for a community challenge filtered to a caller-supplied user-id list (PYMK / contacts), with each user''s real today-progress / streak / target-hit data. Powers the onboarding tutorial preview widget where the leaderboard surfaces the new user''s synced contacts (not just global top scorers). Privacy posture mirrors #197: caller-supplied IDs already privacy-cleared by `get_people_you_may_know`; today_progress is not incremental disclosure (already exposed by `get_community_challenge_detail` global top-10).';

-- Force PostgREST to refresh its schema cache so the new RPC is callable
-- immediately after deploy (otherwise iOS clients see PGRST202 for 5–12 min).
NOTIFY pgrst, 'reload schema';

COMMIT;
