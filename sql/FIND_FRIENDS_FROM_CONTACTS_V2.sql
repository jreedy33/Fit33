-- =====================================================
-- FIND FRIENDS FROM CONTACTS V2
-- =====================================================
-- Enhanced function that searches by BOTH email AND phone number
-- Uses requester_id/addressee_id (correct column names for friendships table)
-- =====================================================

-- Drop existing function if it exists (to handle return type change)
DROP FUNCTION IF EXISTS find_friends_from_contacts_v2(text[], text[]);

-- Create the v2 function that searches by email AND phone
CREATE OR REPLACE FUNCTION find_friends_from_contacts_v2(
    contact_emails TEXT[],
    contact_phones TEXT[]
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
) AS $$
DECLARE
    v_current_user_id UUID := auth.uid();
BEGIN
    RETURN QUERY
    WITH 
    -- Normalize the contact phone numbers (just last 10 digits)
    normalized_phones AS (
        SELECT DISTINCT RIGHT(regexp_replace(phone, '[^0-9]', '', 'g'), 10) as phone
        FROM unnest(contact_phones) as phone
        WHERE LENGTH(regexp_replace(phone, '[^0-9]', '', 'g')) >= 10
    ),
    -- Find users matching by email OR phone
    matched_users AS (
        SELECT DISTINCT ON (up.id)
            up.id as matched_user_id,
            up.name,
            up.email,
            up.username,
            up.profile_photo_url,
            up.fitness_goal
        FROM user_profiles up
        WHERE 
            up.id != v_current_user_id
            AND up.has_completed_onboarding = true
            AND (
                -- Match by email (case-insensitive)
                LOWER(up.email) = ANY(SELECT LOWER(e) FROM unnest(contact_emails) e)
                -- OR match by phone number
                OR (
                    up.phone_number IS NOT NULL 
                    AND RIGHT(regexp_replace(up.phone_number, '[^0-9]', '', 'g'), 10) IN (SELECT phone FROM normalized_phones)
                )
            )
    ),
    -- Check existing friendships (accepted)
    accepted_friendships AS (
        SELECT 
            CASE 
                WHEN f.requester_id = v_current_user_id THEN f.addressee_id
                ELSE f.requester_id
            END as friend_id
        FROM friendships f
        WHERE (f.requester_id = v_current_user_id OR f.addressee_id = v_current_user_id)
        AND f.status = 'accepted'
    ),
    -- Check outgoing pending requests (I sent to them)
    outgoing_requests AS (
        SELECT f.addressee_id as other_user_id
        FROM friendships f
        WHERE f.requester_id = v_current_user_id
        AND f.status = 'pending'
    ),
    -- Check incoming pending requests (they sent to me)
    incoming_requests AS (
        SELECT f.requester_id as other_user_id
        FROM friendships f
        WHERE f.addressee_id = v_current_user_id
        AND f.status = 'pending'
    )
    SELECT 
        mu.matched_user_id as user_id,
        mu.name,
        mu.email,
        mu.username,
        mu.profile_photo_url,
        mu.fitness_goal,
        (mu.matched_user_id IN (SELECT friend_id FROM accepted_friendships)) as is_friend,
        (mu.matched_user_id IN (SELECT other_user_id FROM outgoing_requests)) as has_outgoing_request,
        (mu.matched_user_id IN (SELECT other_user_id FROM incoming_requests)) as has_incoming_request
    FROM matched_users mu
    WHERE mu.matched_user_id NOT IN (SELECT friend_id FROM accepted_friendships)
    ORDER BY mu.name ASC NULLS LAST;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION find_friends_from_contacts_v2(TEXT[], TEXT[]) TO authenticated;

-- Add phone_number column if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'user_profiles' 
        AND column_name = 'phone_number'
    ) THEN
        ALTER TABLE user_profiles ADD COLUMN phone_number TEXT;
        COMMENT ON COLUMN user_profiles.phone_number IS 'Phone number for contact matching';
    END IF;
END $$;
