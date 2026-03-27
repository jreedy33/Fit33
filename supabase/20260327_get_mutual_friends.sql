-- Get mutual friends between the current user and a target user
-- Returns the list of friends they have in common (name, username, photo)

CREATE OR REPLACE FUNCTION get_mutual_friends(p_target_user_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_current_user UUID;
    v_result JSON;
BEGIN
    v_current_user := auth.uid();
    IF v_current_user IS NULL THEN
        RETURN '[]'::JSON;
    END IF;

    WITH my_friends AS (
        SELECT CASE WHEN requester_id = v_current_user THEN addressee_id ELSE requester_id END AS fid
        FROM friendships
        WHERE status = 'accepted'
          AND (requester_id = v_current_user OR addressee_id = v_current_user)
    ),
    their_friends AS (
        SELECT CASE WHEN requester_id = p_target_user_id THEN addressee_id ELSE requester_id END AS fid
        FROM friendships
        WHERE status = 'accepted'
          AND (requester_id = p_target_user_id OR addressee_id = p_target_user_id)
    ),
    mutuals AS (
        SELECT mf.fid
        FROM my_friends mf
        INNER JOIN their_friends tf ON tf.fid = mf.fid
    )
    SELECT COALESCE(json_agg(row_to_json(sub)), '[]'::JSON)
    INTO v_result
    FROM (
        SELECT
            up.id AS user_id,
            up.name,
            up.username,
            up.profile_photo_url
        FROM mutuals m
        INNER JOIN user_profiles up ON up.id = m.fid
        ORDER BY up.name ASC
        LIMIT 50
    ) sub;

    RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION get_mutual_friends(UUID) TO authenticated;
