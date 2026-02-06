-- =====================================================
-- PHONE VERIFICATION SYSTEM
-- =====================================================
-- This sets up the database schema for phone verification
-- Works with Supabase Edge Functions + Twilio Verify
-- =====================================================

-- Table to track phone verification status
CREATE TABLE IF NOT EXISTS phone_verifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    phone_number TEXT NOT NULL,
    is_verified BOOLEAN DEFAULT FALSE,
    verified_at TIMESTAMPTZ,
    verification_attempts INT DEFAULT 0,
    last_attempt_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- Unique constraint: one verification per user
    UNIQUE(user_id)
);

-- Index for quick lookups
CREATE INDEX IF NOT EXISTS idx_phone_verifications_user_id ON phone_verifications(user_id);
CREATE INDEX IF NOT EXISTS idx_phone_verifications_phone ON phone_verifications(phone_number);

-- Enable RLS
ALTER TABLE phone_verifications ENABLE ROW LEVEL SECURITY;

-- Users can only see/update their own verification
CREATE POLICY "Users can view own verification" ON phone_verifications
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own verification" ON phone_verifications
    FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own verification" ON phone_verifications
    FOR UPDATE USING (auth.uid() = user_id);

-- =====================================================
-- Function to start phone verification
-- Called by Edge Function after Twilio sends code
-- =====================================================
CREATE OR REPLACE FUNCTION start_phone_verification(
    p_phone_number TEXT
)
RETURNS JSON AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_result JSON;
BEGIN
    -- Check rate limiting (max 5 attempts per hour)
    IF EXISTS (
        SELECT 1 FROM phone_verifications
        WHERE user_id = v_user_id
        AND verification_attempts >= 5
        AND last_attempt_at > NOW() - INTERVAL '1 hour'
    ) THEN
        RETURN json_build_object(
            'success', false,
            'error', 'Too many verification attempts. Please try again in an hour.'
        );
    END IF;

    -- Upsert verification record
    INSERT INTO phone_verifications (user_id, phone_number, verification_attempts, last_attempt_at)
    VALUES (v_user_id, p_phone_number, 1, NOW())
    ON CONFLICT (user_id) DO UPDATE SET
        phone_number = p_phone_number,
        verification_attempts = phone_verifications.verification_attempts + 1,
        last_attempt_at = NOW(),
        is_verified = FALSE,
        updated_at = NOW();

    RETURN json_build_object(
        'success', true,
        'message', 'Verification started'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================================
-- Function to confirm phone verification
-- Called by Edge Function after Twilio confirms code
-- =====================================================
CREATE OR REPLACE FUNCTION confirm_phone_verification(
    p_phone_number TEXT
)
RETURNS JSON AS $$
DECLARE
    v_user_id UUID := auth.uid();
BEGIN
    -- Mark as verified
    UPDATE phone_verifications
    SET is_verified = TRUE,
        verified_at = NOW(),
        verification_attempts = 0,
        updated_at = NOW()
    WHERE user_id = v_user_id
    AND phone_number = p_phone_number;

    -- Also update user_profiles with verified phone
    UPDATE user_profiles
    SET phone_number = p_phone_number,
        phone_verified = TRUE,
        updated_at = NOW()
    WHERE id = v_user_id::TEXT;

    RETURN json_build_object(
        'success', true,
        'message', 'Phone verified successfully'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================================
-- Add phone_verified column to user_profiles if missing
-- =====================================================
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'user_profiles' 
        AND column_name = 'phone_verified'
    ) THEN
        ALTER TABLE user_profiles ADD COLUMN phone_verified BOOLEAN DEFAULT FALSE;
        COMMENT ON COLUMN user_profiles.phone_verified IS 'Whether phone number has been verified via SMS';
        RAISE NOTICE 'Added phone_verified column to user_profiles';
    ELSE
        RAISE NOTICE 'phone_verified column already exists';
    END IF;
END $$;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION start_phone_verification(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION confirm_phone_verification(TEXT) TO authenticated;

-- Verify setup
SELECT 'Phone verification tables created!' as status;
SELECT 'Ready for Twilio Verify integration' as info;
