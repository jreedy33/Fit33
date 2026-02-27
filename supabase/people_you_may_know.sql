-- People You May Know (Friends-of-Friends) Discovery
-- Returns users who are friends with your friends but not yet your friends
-- Prioritized by mutual friend count and profile completeness

DROP FUNCTION IF EXISTS get_people_you_may_know(INT);

CREATE OR REPLACE FUNCTION get_people_you_may_know(
    result_limit INT DEFAULT 20
)
RETURNS TABLE (
    user_id UUID,
    name TEXT,
    email TEXT,
    username TEXT,
    profile_photo_url TEXT,
    phone_number TEXT,
    fitness_goal TEXT,
    is_friend BOOLEAN,
    has_outgoing_request BOOLEAN,
    has_incoming_request BOOLEAN,
    mutual_friend_count INT
)
LANGUAGE plpgsql
SECURITY DEFINER
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
        -- Get all accepted friend IDs (friendships table uses requester_id/addressee_id)
        SELECT CASE 
            WHEN requester_id = current_user_uuid THEN addressee_id
            ELSE requester_id
        END AS friend_id
        FROM friendships
        WHERE (requester_id = current_user_uuid OR addressee_id = current_user_uuid)
          AND status = 'accepted'
    ),
    friends_of_friends AS (
        -- Find friends-of-my-friends who are NOT already my friends
        SELECT 
            CASE 
                WHEN f.requester_id = mf.friend_id THEN f.addressee_id
                ELSE f.requester_id
            END AS suggested_user_id,
            COUNT(DISTINCT mf.friend_id) AS mutual_count
        FROM friendships f
        INNER JOIN my_friends mf ON (f.requester_id = mf.friend_id OR f.addressee_id = mf.friend_id)
        WHERE f.status = 'accepted'
        GROUP BY suggested_user_id
        -- Exclude self
        HAVING CASE 
            WHEN f.requester_id = mf.friend_id THEN f.addressee_id
            ELSE f.requester_id
        END != current_user_uuid
        -- Exclude existing friends
        AND CASE 
            WHEN f.requester_id = mf.friend_id THEN f.addressee_id
            ELSE f.requester_id
        END NOT IN (SELECT friend_id FROM my_friends)
    ),
    pending_to_them AS (
        -- Outgoing requests from me
        SELECT addressee_id AS other_user_id
        FROM friendships
        WHERE requester_id = current_user_uuid AND status = 'pending'
    ),
    pending_from_them AS (
        -- Incoming requests to me
        SELECT requester_id AS other_user_id
        FROM friendships
        WHERE addressee_id = current_user_uuid AND status = 'pending'
    )
    SELECT 
        up.id AS user_id,
        up.name,
        up.email,
        up.username,
        up.profile_photo_url,
        up.phone_number,
        up.fitness_goal,
        FALSE AS is_friend,
        EXISTS(SELECT 1 FROM pending_to_them pt WHERE pt.other_user_id = up.id) AS has_outgoing_request,
        EXISTS(SELECT 1 FROM pending_from_them pf WHERE pf.other_user_id = up.id) AS has_incoming_request,
        fof.mutual_count::INT AS mutual_friend_count
    FROM friends_of_friends fof
    INNER JOIN user_profiles up ON up.id = fof.suggested_user_id
    -- Exclude users who already have pending requests (either direction)
    WHERE NOT EXISTS(SELECT 1 FROM pending_to_them pt WHERE pt.other_user_id = up.id)
      AND NOT EXISTS(SELECT 1 FROM pending_from_them pf WHERE pf.other_user_id = up.id)
    ORDER BY 
        -- Prioritize: has photo + high mutual count
        (up.profile_photo_url IS NOT NULL AND up.profile_photo_url != '') DESC,
        fof.mutual_count DESC,
        up.name ASC
    LIMIT result_limit;
END;
$$;

COMMENT ON FUNCTION get_people_you_may_know(INT) IS 
  'Returns friends-of-friends ("People You May Know") with mutual friend counts. '
  'Used in the Friends tab suggestion bar to help users discover and add new friends.';

GRANT EXECUTE ON FUNCTION get_people_you_may_know(INT) TO authenticated;
