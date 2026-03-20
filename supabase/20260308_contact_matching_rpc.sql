CREATE OR REPLACE FUNCTION match_contacts_by_phone(phone_hashes text[])
RETURNS TABLE(id uuid, name text, username text, profile_photo_url text)
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    RETURN QUERY
    SELECT up.id, up.name, up.username, up.profile_photo_url
    FROM user_profiles up
    WHERE md5(up.phone_number) = ANY(phone_hashes)
    AND up.phone_number IS NOT NULL;
END;
$$;
