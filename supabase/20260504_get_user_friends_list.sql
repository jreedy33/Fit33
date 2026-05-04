-- ============================================================================
-- Migration #196 — get_user_friends_list (Instagram-style friend list)
-- Date: 2026-05-04
--
-- Powers the new "See friends >" CTA on a non-friend user's profile
-- (Fit33/FriendProfileView.swift → UserFriendsListView). Returns the target
-- user's accepted-friend list with per-row social signals (is_my_friend,
-- has_outgoing_request, has_incoming_request) so the iOS UI can render the
-- correct CTA per row ("Friends" badge, "Add", "Pending", "Accept").
--
-- Mirrors the established `get_mutual_friends(p_target_user_id)` pattern
-- (#20260327): SECURITY DEFINER, takes the *other* user's id (not the caller's
-- — see supabase-rules §22 carve-out for `p_target_user_id`-style params),
-- returns JSON. Friend-list visibility today is open (parity with Instagram /
-- with the existing search + mutuals + PYMK flows that already expose
-- name/username/photo). When `profile_visibility` lands later, gate this RPC
-- behind the same setting.
--
-- Sort order: my-friends first (so the rendering surface naturally clusters
-- the people I know), then others, both alphabetical by name.
-- Defaults: LIMIT 200 (full list for typical users; UI can paginate later).
-- ============================================================================

BEGIN;

-- Drop every overload before CREATE OR REPLACE per supabase-rules §32.
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT format('DROP FUNCTION IF EXISTS %I.%I(%s);',
                      n.nspname, p.proname,
                      pg_get_function_identity_arguments(p.oid)) AS cmd
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname = 'get_user_friends_list'
    LOOP
        EXECUTE r.cmd;
    END LOOP;
END $$;

CREATE OR REPLACE FUNCTION get_user_friends_list(
    p_target_user_id UUID,
    p_limit INT DEFAULT 200
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_current_user UUID;
    v_result JSON;
BEGIN
    v_current_user := auth.uid();
    IF v_current_user IS NULL THEN
        RETURN '[]'::JSON;
    END IF;

    IF p_target_user_id IS NULL THEN
        RETURN '[]'::JSON;
    END IF;

    -- Defensive cap: p_limit ∈ [1, 500] so we never return the whole table.
    IF p_limit IS NULL OR p_limit < 1 THEN
        p_limit := 200;
    ELSIF p_limit > 500 THEN
        p_limit := 500;
    END IF;

    WITH their_friends AS (
        -- Every accepted friend of the target user (the "other side" of each
        -- friendship row). Excludes the caller themselves so they don't see
        -- "you" listed as a friend of the target.
        SELECT
            CASE
                WHEN f.requester_id = p_target_user_id THEN f.addressee_id
                ELSE f.requester_id
            END AS friend_id
        FROM friendships f
        WHERE f.status = 'accepted'
          AND (f.requester_id = p_target_user_id OR f.addressee_id = p_target_user_id)
          AND CASE
              WHEN f.requester_id = p_target_user_id THEN f.addressee_id
              ELSE f.requester_id
          END <> v_current_user
    ),
    my_friend_ids AS (
        -- Caller's own friends — used to compute is_my_friend per row.
        SELECT
            CASE
                WHEN f.requester_id = v_current_user THEN f.addressee_id
                ELSE f.requester_id
            END AS friend_id
        FROM friendships f
        WHERE f.status = 'accepted'
          AND (f.requester_id = v_current_user OR f.addressee_id = v_current_user)
    ),
    pending_to_them AS (
        -- Friend requests the caller has SENT (still pending) → "Pending" pill.
        SELECT addressee_id AS other_user_id
        FROM friendships
        WHERE requester_id = v_current_user AND status = 'pending'
    ),
    pending_from_them AS (
        -- Friend requests the caller has RECEIVED (still pending) → "Accept".
        SELECT requester_id AS other_user_id
        FROM friendships
        WHERE addressee_id = v_current_user AND status = 'pending'
    ),
    blocked AS (
        -- Hide users who blocked the caller OR who the caller blocked, in
        -- either direction. Schema lives in `20260418_blocking_and_reporting.sql`
        -- (`user_blocks` table, `blocker_id` / `blocked_id`).
        SELECT blocked_id AS uid FROM user_blocks WHERE blocker_id = v_current_user
        UNION
        SELECT blocker_id AS uid FROM user_blocks WHERE blocked_id = v_current_user
    )
    SELECT COALESCE(json_agg(row_to_json(sub) ORDER BY sub.is_my_friend DESC, lower(COALESCE(sub.name, sub.username, ''))), '[]'::JSON)
    INTO v_result
    FROM (
        SELECT
            up.id AS user_id,
            up.name,
            up.username,
            up.profile_photo_url,
            up.is_verified,
            up.is_gold_verified,
            EXISTS(SELECT 1 FROM my_friend_ids mf WHERE mf.friend_id = up.id) AS is_my_friend,
            EXISTS(SELECT 1 FROM pending_to_them pt WHERE pt.other_user_id = up.id) AS has_outgoing_request,
            EXISTS(SELECT 1 FROM pending_from_them pf WHERE pf.other_user_id = up.id) AS has_incoming_request
        FROM their_friends tf
        INNER JOIN user_profiles up ON up.id = tf.friend_id
        WHERE NOT EXISTS (SELECT 1 FROM blocked b WHERE b.uid = up.id)
        ORDER BY
            -- Caller's own friends bubble to the top (so the surface clusters
            -- the people they actually know first), then everyone else
            -- alphabetically by display name.
            EXISTS(SELECT 1 FROM my_friend_ids mf WHERE mf.friend_id = up.id) DESC,
            lower(COALESCE(up.name, up.username, '')) ASC
        LIMIT p_limit
    ) sub;

    RETURN COALESCE(v_result, '[]'::JSON);
END;
$$;

GRANT EXECUTE ON FUNCTION get_user_friends_list(UUID, INT) TO authenticated;

-- Schema cache reload so iOS clients can call the new RPC immediately
-- (per supabase-rules §44 — without this, PostgREST may serve PGRST202 for
-- 5–12 min until the periodic background refresh fires).
NOTIFY pgrst, 'reload schema';

COMMIT;
