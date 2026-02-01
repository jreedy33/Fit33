-- ============================================================================
-- CONTACT JOINED NOTIFICATIONS
-- When a new user joins Fit33 and their email matches a synced contact,
-- notify the contact owner so they can add them as a friend
-- ============================================================================

-- ============================================================================
-- 1. TABLE: Store synced contact emails per user
-- ============================================================================

CREATE TABLE IF NOT EXISTS user_synced_contacts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    contact_email TEXT NOT NULL,
    contact_name TEXT, -- Optional: store name for display
    synced_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- One entry per user/email combo
    UNIQUE(user_id, contact_email)
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_synced_contacts_user ON user_synced_contacts(user_id);
CREATE INDEX IF NOT EXISTS idx_synced_contacts_email ON user_synced_contacts(contact_email);

-- RLS
ALTER TABLE user_synced_contacts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own synced contacts" ON user_synced_contacts;
DROP POLICY IF EXISTS "Users can insert own synced contacts" ON user_synced_contacts;
DROP POLICY IF EXISTS "Users can delete own synced contacts" ON user_synced_contacts;

CREATE POLICY "Users can view own synced contacts" ON user_synced_contacts
    FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "Users can insert own synced contacts" ON user_synced_contacts
    FOR INSERT WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can delete own synced contacts" ON user_synced_contacts
    FOR DELETE USING (user_id = auth.uid());

-- ============================================================================
-- 2. TABLE: Contact joined notifications (queue for push notifications)
-- ============================================================================

CREATE TABLE IF NOT EXISTS contact_joined_notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    recipient_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    new_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    new_user_name TEXT,
    new_user_email TEXT,
    notification_sent BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    sent_at TIMESTAMPTZ,
    
    -- Only one notification per recipient/new_user combo
    UNIQUE(recipient_id, new_user_id)
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_contact_joined_recipient ON contact_joined_notifications(recipient_id);
CREATE INDEX IF NOT EXISTS idx_contact_joined_pending ON contact_joined_notifications(notification_sent) WHERE notification_sent = false;

-- RLS
ALTER TABLE contact_joined_notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own contact notifications" ON contact_joined_notifications;
DROP POLICY IF EXISTS "Users can update own contact notifications" ON contact_joined_notifications;

CREATE POLICY "Users can view own contact notifications" ON contact_joined_notifications
    FOR SELECT USING (recipient_id = auth.uid());

CREATE POLICY "Users can update own contact notifications" ON contact_joined_notifications
    FOR UPDATE USING (recipient_id = auth.uid());

-- ============================================================================
-- 3. FUNCTION: Sync contacts from client
-- ============================================================================

CREATE OR REPLACE FUNCTION sync_user_contacts(
    p_contact_emails TEXT[],
    p_contact_names TEXT[] DEFAULT NULL
)
RETURNS INTEGER AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_count INTEGER := 0;
    v_email TEXT;
    v_name TEXT;
    v_idx INTEGER := 1;
BEGIN
    -- Clear existing synced contacts for this user (full refresh)
    DELETE FROM user_synced_contacts WHERE user_id = v_user_id;
    
    -- Insert new contacts
    FOREACH v_email IN ARRAY p_contact_emails
    LOOP
        -- Get corresponding name if provided
        v_name := NULL;
        IF p_contact_names IS NOT NULL AND array_length(p_contact_names, 1) >= v_idx THEN
            v_name := p_contact_names[v_idx];
        END IF;
        
        -- Insert contact (normalized email)
        INSERT INTO user_synced_contacts (user_id, contact_email, contact_name)
        VALUES (v_user_id, LOWER(TRIM(v_email)), v_name)
        ON CONFLICT (user_id, contact_email) DO UPDATE SET
            contact_name = EXCLUDED.contact_name,
            synced_at = NOW();
        
        v_count := v_count + 1;
        v_idx := v_idx + 1;
    END LOOP;
    
    RETURN v_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION sync_user_contacts(TEXT[], TEXT[]) TO authenticated;

-- ============================================================================
-- 4. FUNCTION: Check for new user and create notifications
-- Called when user completes profile setup or on new signup
-- ============================================================================

CREATE OR REPLACE FUNCTION notify_contacts_of_new_user(p_new_user_id UUID DEFAULT NULL)
RETURNS INTEGER AS $$
DECLARE
    v_new_user_id UUID;
    v_new_user_email TEXT;
    v_new_user_name TEXT;
    v_count INTEGER := 0;
    v_contact_owner RECORD;
BEGIN
    -- Use provided ID or current user
    v_new_user_id := COALESCE(p_new_user_id, auth.uid());
    
    -- Get new user's email and name
    SELECT u.email, up.name
    INTO v_new_user_email, v_new_user_name
    FROM auth.users u
    LEFT JOIN user_profiles up ON up.id::TEXT = u.id::TEXT
    WHERE u.id = v_new_user_id;
    
    IF v_new_user_email IS NULL THEN
        RETURN 0;
    END IF;
    
    -- Find all users who have this email in their synced contacts
    FOR v_contact_owner IN
        SELECT DISTINCT usc.user_id
        FROM user_synced_contacts usc
        WHERE LOWER(usc.contact_email) = LOWER(v_new_user_email)
        AND usc.user_id != v_new_user_id -- Don't notify yourself
        -- Don't notify if already friends
        AND NOT EXISTS (
            SELECT 1 FROM friendships f
            WHERE f.status = 'accepted'
            AND ((f.requester_id = usc.user_id AND f.addressee_id = v_new_user_id)
                 OR (f.requester_id = v_new_user_id AND f.addressee_id = usc.user_id))
        )
        -- Don't notify if there's already a pending request
        AND NOT EXISTS (
            SELECT 1 FROM friendships f
            WHERE f.status = 'pending'
            AND ((f.requester_id = usc.user_id AND f.addressee_id = v_new_user_id)
                 OR (f.requester_id = v_new_user_id AND f.addressee_id = usc.user_id))
        )
    LOOP
        -- Create notification record
        INSERT INTO contact_joined_notifications (
            recipient_id, new_user_id, new_user_name, new_user_email
        ) VALUES (
            v_contact_owner.user_id, v_new_user_id, v_new_user_name, v_new_user_email
        )
        ON CONFLICT (recipient_id, new_user_id) DO NOTHING;
        
        v_count := v_count + 1;
    END LOOP;
    
    RETURN v_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION notify_contacts_of_new_user(UUID) TO authenticated;

-- ============================================================================
-- 5. FUNCTION: Get pending contact joined notifications
-- ============================================================================

CREATE OR REPLACE FUNCTION get_pending_contact_notifications()
RETURNS TABLE (
    notification_id UUID,
    new_user_id UUID,
    new_user_name TEXT,
    new_user_email TEXT,
    new_user_username TEXT,
    new_user_photo_url TEXT,
    created_at TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        cjn.id as notification_id,
        cjn.new_user_id,
        COALESCE(up.name, cjn.new_user_name) as new_user_name,
        cjn.new_user_email,
        up.username as new_user_username,
        up.profile_photo_url as new_user_photo_url,
        cjn.created_at
    FROM contact_joined_notifications cjn
    LEFT JOIN user_profiles up ON up.id::TEXT = cjn.new_user_id::TEXT
    WHERE cjn.recipient_id = auth.uid()
    AND cjn.notification_sent = false
    ORDER BY cjn.created_at DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_pending_contact_notifications() TO authenticated;

-- ============================================================================
-- 6. FUNCTION: Mark notification as sent
-- ============================================================================

CREATE OR REPLACE FUNCTION mark_contact_notification_sent(p_notification_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    UPDATE contact_joined_notifications
    SET notification_sent = true, sent_at = NOW()
    WHERE id = p_notification_id
    AND recipient_id = auth.uid();
    
    RETURN FOUND;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION mark_contact_notification_sent(UUID) TO authenticated;

-- ============================================================================
-- 7. TRIGGER: Auto-notify when user_profiles is created/updated with name
-- This fires when a new user completes their profile
-- ============================================================================

CREATE OR REPLACE FUNCTION trigger_notify_contacts_on_profile()
RETURNS TRIGGER AS $$
BEGIN
    -- When a user profile is created or name is set for first time
    IF TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND OLD.name IS NULL AND NEW.name IS NOT NULL) THEN
        PERFORM notify_contacts_of_new_user(NEW.id);
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trigger_contact_notification ON user_profiles;
CREATE TRIGGER trigger_contact_notification
    AFTER INSERT OR UPDATE ON user_profiles
    FOR EACH ROW
    EXECUTE FUNCTION trigger_notify_contacts_on_profile();

-- ============================================================================
-- DONE!
-- ============================================================================

SELECT 'Contact Joined Notifications system created!' AS status;
SELECT 'Tables: user_synced_contacts, contact_joined_notifications' AS tables;
SELECT 'Functions:' AS functions;
SELECT '- sync_user_contacts(emails[], names[]) - Sync contacts from client' AS func1;
SELECT '- notify_contacts_of_new_user(user_id) - Create notification records' AS func2;
SELECT '- get_pending_contact_notifications() - Get unsent notifications' AS func3;
SELECT '- mark_contact_notification_sent(id) - Mark as sent' AS func4;
