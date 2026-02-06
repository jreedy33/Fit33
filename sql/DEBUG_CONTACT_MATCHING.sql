-- =====================================================
-- DEBUG CONTACT MATCHING
-- Run these queries to diagnose friend suggestion issues
-- =====================================================

-- 1. Check if find_friends_from_contacts_v2 function exists
SELECT routine_name, routine_type 
FROM information_schema.routines 
WHERE routine_name LIKE '%find_friends%';

-- 2. Check Wayne's profile - does he have phone/email that might match?
SELECT id, name, username, email, phone_number, has_completed_onboarding
FROM user_profiles 
WHERE LOWER(name) LIKE '%wayne%' OR LOWER(username) LIKE '%wayne%';

-- 3. Check Abbie's profile - is her phone number synced?
SELECT id, name, username, email, phone_number, has_completed_onboarding
FROM user_profiles 
WHERE LOWER(name) LIKE '%abbie%' OR LOWER(name) LIKE '%macwilliams%';

-- 4. Check Nicholas Reed's profile
SELECT id, name, username, email, phone_number
FROM user_profiles 
WHERE LOWER(name) LIKE '%nicholas%' OR LOWER(name) LIKE '%nick%';

-- 5. List ALL users to see who could be showing (for debugging)
SELECT id, name, username, email, 
       CASE WHEN phone_number IS NOT NULL THEN 'Yes' ELSE 'No' END as has_phone,
       has_completed_onboarding
FROM user_profiles 
WHERE has_completed_onboarding = true
ORDER BY name;

-- 6. If you have Nick's user ID, test the function directly:
-- Replace 'NICKS_USER_ID' with actual UUID
-- SELECT * FROM find_friends_from_contacts_v2(
--     ARRAY['test@email.com']::TEXT[],  -- contact_emails from Nick's phone
--     ARRAY['1234567890']::TEXT[]       -- contact_phones from Nick's phone
-- );

-- =====================================================
-- POTENTIAL FIX: Ensure the function excludes users
-- not in contacts (double-check the WHERE clause)
-- =====================================================

-- This version adds explicit logging about WHY each user matched
CREATE OR REPLACE FUNCTION find_friends_from_contacts_v2_debug(
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
    has_incoming_request BOOLEAN,
    matched_by TEXT  -- NEW: shows WHY this user matched (email or phone)
) AS $$
DECLARE
    v_current_user_id UUID := auth.uid();
BEGIN
    -- Debug: Log what we received
    RAISE NOTICE 'find_friends_from_contacts_v2_debug called';
    RAISE NOTICE 'contact_emails count: %', array_length(contact_emails, 1);
    RAISE NOTICE 'contact_phones count: %', array_length(contact_phones, 1);
    RAISE NOTICE 'current_user_id: %', v_current_user_id;
    
    RETURN QUERY
    WITH 
    -- Normalize the contact phone numbers (just last 10 digits)
    normalized_phones AS (
        SELECT DISTINCT RIGHT(regexp_replace(phone, '[^0-9]', '', 'g'), 10) as phone
        FROM unnest(contact_phones) as phone
        WHERE LENGTH(regexp_replace(phone, '[^0-9]', '', 'g')) >= 10
    ),
    -- Find users matching by email
    email_matches AS (
        SELECT up.id as matched_user_id, 'email' as match_type
        FROM user_profiles up
        WHERE up.id != v_current_user_id
        AND up.has_completed_onboarding = true
        AND LOWER(up.email) = ANY(SELECT LOWER(e) FROM unnest(contact_emails) e)
    ),
    -- Find users matching by phone
    phone_matches AS (
        SELECT up.id as matched_user_id, 'phone' as match_type
        FROM user_profiles up
        WHERE up.id != v_current_user_id
        AND up.has_completed_onboarding = true
        AND up.phone_number IS NOT NULL 
        AND RIGHT(regexp_replace(up.phone_number, '[^0-9]', '', 'g'), 10) IN (SELECT phone FROM normalized_phones)
    ),
    -- Combine all matches
    all_matches AS (
        SELECT * FROM email_matches
        UNION ALL
        SELECT * FROM phone_matches
    ),
    -- Deduplicate and determine match type
    matched_users AS (
        SELECT DISTINCT ON (am.matched_user_id)
            am.matched_user_id,
            up.name,
            up.email,
            up.username,
            up.profile_photo_url,
            up.fitness_goal,
            string_agg(DISTINCT am.match_type, ', ') as matched_by
        FROM all_matches am
        JOIN user_profiles up ON up.id = am.matched_user_id
        GROUP BY am.matched_user_id, up.name, up.email, up.username, up.profile_photo_url, up.fitness_goal
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
    -- Check outgoing pending requests
    outgoing_requests AS (
        SELECT f.addressee_id as other_user_id
        FROM friendships f
        WHERE f.requester_id = v_current_user_id
        AND f.status = 'pending'
    ),
    -- Check incoming pending requests
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
        (mu.matched_user_id IN (SELECT other_user_id FROM incoming_requests)) as has_incoming_request,
        mu.matched_by
    FROM matched_users mu
    WHERE mu.matched_user_id NOT IN (SELECT friend_id FROM accepted_friendships)
    ORDER BY mu.name ASC NULLS LAST;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION find_friends_from_contacts_v2_debug(TEXT[], TEXT[]) TO authenticated;
