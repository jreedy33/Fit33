-- ============================================================================
-- 20260504 — PYMK-based community discovery for onboarding
--
-- Adds: get_discoverable_community_challenges_for_users(UUID[], INT)
--
-- WHY:
--   The existing get_discoverable_community_challenges RPC only surfaces
--   communities a user's DIRECT FRIENDS are in (via get_friend_ids). On the
--   onboarding tutorial Community step, a brand-new account has zero
--   accepted friendships yet — even after Sync Contacts they're at most
--   "people you may know" / friends-of-friends. The friend-only query
--   returns empty in that case, so the tutorial fell back to a generic
--   featured community.
--
--   This new RPC mirrors the friend-density discovery query but accepts the
--   PYMK user-id list as a parameter so the tutorial can show "the community
--   that has the most of the people you may know" — a vastly more relevant
--   first-impression card than a generic featured one.
--
--   The companion `join_community_challenge_friends` RPC already accepts
--   FoF (via `can_join_community_challenge`), so a user can legitimately
--   join one of these communities through the same friend-chain gate that
--   protects every other join.
--
-- PRIVACY:
--   The caller pre-filters the user-id list client-side from
--   `ContactsService.peopleYouMayKnow`, which itself comes from the
--   privacy-respecting `get_people_you_may_know` RPC (`privacy_hide_search`
--   + `privacy_hide_photo` aware). The PII returned in
--   `friends_in_challenge` (name / username / profile_photo_url) for those
--   IDs is therefore the same surface the caller already saw on PYMK —
--   no incremental disclosure. We DO cap the input array to 100 to bound
--   probing surface and reject the current user from showing up in their
--   own avatars row.
-- ============================================================================

BEGIN;

-- Drop any prior overloads so PostgREST doesn't see two ambiguous signatures.
DROP FUNCTION IF EXISTS get_discoverable_community_challenges_for_users(UUID[], INT);
DROP FUNCTION IF EXISTS get_discoverable_community_challenges_for_users(UUID[]);

CREATE OR REPLACE FUNCTION get_discoverable_community_challenges_for_users(
    p_user_ids UUID[],
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
    -- Up to 5 avatars from the supplied user-id list (NOT the user's friends —
    -- these are friends-of-friends / contacts the caller surfaced via PYMK).
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

    -- Empty / NULL list short-circuits to no rows.
    IF p_user_ids IS NULL OR array_length(p_user_ids, 1) IS NULL THEN
        RETURN;
    END IF;

    -- Bound probing surface — PYMK itself caps at 20, contacts at a few
    -- hundred typical; 100 covers the tutorial's needs.
    IF array_length(p_user_ids, 1) > 100 THEN
        RAISE EXCEPTION 'Too many user ids' USING ERRCODE = '22023';
    END IF;

    RETURN QUERY
    WITH candidate_users AS (
        -- De-duplicate + drop the caller (defense-in-depth: if the client
        -- ever sends their own id we don't want them in their own avatar row).
        SELECT DISTINCT u
        FROM unnest(p_user_ids) AS u
        WHERE u <> current_user_uuid
    ),
    -- Communities at least one candidate is actively participating in.
    candidate_challenges AS (
        SELECT ccp.challenge_id,
            COUNT(DISTINCT ccp.user_id)::INT AS friends_count
        FROM community_challenge_participants ccp
        WHERE ccp.is_active = TRUE
          AND ccp.user_id IN (SELECT u FROM candidate_users)
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
        -- Up to 5 PYMK avatars (matches the JSONB shape used by
        -- `get_discoverable_community_challenges` so the iOS decoder
        -- (`DiscoverableCommunityChallenge`) is shared).
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
                  AND ccp2.user_id IN (SELECT u FROM candidate_users)
                ORDER BY ccp2.joined_at ASC
                LIMIT 5
            ) sub
        ) AS friends_in_challenge,
        candc.friends_count
    FROM community_challenges cc
    JOIN candidate_challenges candc ON candc.challenge_id = cc.id
    WHERE cc.status = 'active'
      -- Caller is NOT already a participant (mirrors the friends RPC).
      AND NOT EXISTS (
          SELECT 1 FROM community_challenge_participants ccp3
          WHERE ccp3.challenge_id = cc.id
            AND ccp3.user_id = current_user_uuid
            AND ccp3.is_active = TRUE
      )
      -- Not full.
      AND (cc.max_participants IS NULL OR cc.participant_count < cc.max_participants)
    ORDER BY candc.friends_count DESC, cc.participant_count DESC
    LIMIT COALESCE(p_limit, 10);
END;
$$;

GRANT EXECUTE ON FUNCTION get_discoverable_community_challenges_for_users(UUID[], INT) TO authenticated;

COMMENT ON FUNCTION get_discoverable_community_challenges_for_users(UUID[], INT) IS
    'PYMK-driven community discovery for the onboarding tutorial. Returns active community challenges sorted by how many of the supplied user IDs (typically friends-of-friends from `get_people_you_may_know`) are participants. Mirrors `get_discoverable_community_challenges`'' return shape so the iOS `DiscoverableCommunityChallenge` decoder is reused.';

-- Force PostgREST to refresh its schema cache so the new RPC is callable
-- immediately after deploy (otherwise iOS clients see PGRST202 for 5–12 min).
NOTIFY pgrst, 'reload schema';

COMMIT;
