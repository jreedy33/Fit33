-- ============================================================================
-- CONTACTS-BASED FRIEND SUGGESTIONS
-- 
-- Finds app users that match the user's phone contacts (by email)
-- This enables "People you may know" / friend suggestions feature
-- ============================================================================

-- Function to find app users from contact emails
CREATE OR REPLACE FUNCTION find_friends_from_contacts(
    contact_emails TEXT[]
)
RETURNS TABLE (
    user_id UUID,
    name TEXT,
    email TEXT,
    username TEXT,
    profile_photo_url TEXT,
    fitness_goal TEXT,
    is_friend BOOLEAN,
    has_outgoing_request BOOLEAN,
    has_incoming_request BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    current_user_uuid UUID := auth.uid();
BEGIN
    RETURN QUERY
    SELECT 
        u.id as user_id,
        up.name,
        u.email::TEXT,
        up.username,
        up.profile_photo_url,
        up.fitness_goal,
        -- Is already a friend
        EXISTS (
            SELECT 1 FROM friendships f 
            WHERE f.status = 'accepted'
            AND ((f.requester_id = current_user_uuid AND f.addressee_id = u.id)
                 OR (f.requester_id = u.id AND f.addressee_id = current_user_uuid))
        ) as is_friend,
        -- Has outgoing request (I sent them)
        EXISTS (
            SELECT 1 FROM friendships f 
            WHERE f.status = 'pending'
            AND f.requester_id = current_user_uuid 
            AND f.addressee_id = u.id
        ) as has_outgoing_request,
        -- Has incoming request (they sent me)
        EXISTS (
            SELECT 1 FROM friendships f 
            WHERE f.status = 'pending'
            AND f.requester_id = u.id 
            AND f.addressee_id = current_user_uuid
        ) as has_incoming_request
    FROM auth.users u
    LEFT JOIN user_profiles up ON up.id::TEXT = u.id::TEXT
    WHERE u.id != current_user_uuid
    -- Match by email (case insensitive)
    AND LOWER(u.email) = ANY(SELECT LOWER(unnest(contact_emails)))
    -- Exclude users that are already friends
    AND NOT EXISTS (
        SELECT 1 FROM friendships f 
        WHERE f.status = 'accepted'
        AND ((f.requester_id = current_user_uuid AND f.addressee_id = u.id)
             OR (f.requester_id = u.id AND f.addressee_id = current_user_uuid))
    )
    -- Exclude users with pending outgoing requests (already sent)
    AND NOT EXISTS (
        SELECT 1 FROM friendships f 
        WHERE f.status = 'pending'
        AND f.requester_id = current_user_uuid 
        AND f.addressee_id = u.id
    )
    ORDER BY up.name ASC
    LIMIT 50;  -- Limit suggestions
END;
$$;

GRANT EXECUTE ON FUNCTION find_friends_from_contacts(TEXT[]) TO authenticated;

-- Done!
SELECT 'Contacts friend suggestions function created!' AS status;
SELECT 'Call find_friends_from_contacts with array of contact emails to get suggestions' AS info;
