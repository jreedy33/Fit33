-- ============================================================================
-- EXERCISE NICKNAMES - User Custom Names for Exercises
-- ============================================================================
-- Run this script in your Supabase SQL Editor
-- This allows users to create their own names for exercises while keeping
-- data mapped to the official exercise name
-- ============================================================================

-- Table for storing user-specific exercise nicknames
CREATE TABLE IF NOT EXISTS user_exercise_nicknames (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    
    -- The official exercise name (what's stored in exercises table)
    official_name TEXT NOT NULL,
    
    -- The user's custom nickname for this exercise
    nickname TEXT NOT NULL,
    
    -- Optional: reference to exercise ID if you want stricter linking
    exercise_id UUID,
    
    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Unique constraint: one nickname per user per exercise
CREATE UNIQUE INDEX IF NOT EXISTS idx_nickname_unique 
    ON user_exercise_nicknames(user_id, official_name);

-- Index for quick lookups
CREATE INDEX IF NOT EXISTS idx_nickname_user ON user_exercise_nicknames(user_id);
CREATE INDEX IF NOT EXISTS idx_nickname_official ON user_exercise_nicknames(official_name);

-- Row Level Security
ALTER TABLE user_exercise_nicknames ENABLE ROW LEVEL SECURITY;

-- Users can only see their own nicknames
DROP POLICY IF EXISTS "Users can view own nicknames" ON user_exercise_nicknames;
CREATE POLICY "Users can view own nicknames" ON user_exercise_nicknames 
    FOR SELECT TO authenticated 
    USING (auth.uid() = user_id);

-- Users can only create nicknames for themselves
DROP POLICY IF EXISTS "Users can insert own nicknames" ON user_exercise_nicknames;
CREATE POLICY "Users can insert own nicknames" ON user_exercise_nicknames 
    FOR INSERT TO authenticated 
    WITH CHECK (auth.uid() = user_id);

-- Users can only update their own nicknames
DROP POLICY IF EXISTS "Users can update own nicknames" ON user_exercise_nicknames;
CREATE POLICY "Users can update own nicknames" ON user_exercise_nicknames 
    FOR UPDATE TO authenticated 
    USING (auth.uid() = user_id);

-- Users can only delete their own nicknames
DROP POLICY IF EXISTS "Users can delete own nicknames" ON user_exercise_nicknames;
CREATE POLICY "Users can delete own nicknames" ON user_exercise_nicknames 
    FOR DELETE TO authenticated 
    USING (auth.uid() = user_id);

-- ============================================================================
-- VERIFICATION
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '✅ Exercise nicknames table created successfully!';
    RAISE NOTICE 'Users can now create custom names for exercises.';
END $$;
