-- ============================================
-- UPDATE EXERCISES TABLE SCHEMA
-- Run this in Supabase SQL Editor
-- ============================================

-- Add all columns we need (IF NOT EXISTS prevents errors if they already exist)
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS video_code TEXT;
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS video_filename TEXT;
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS gender TEXT DEFAULT 'male';
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS description TEXT;
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS primary_muscles TEXT[];
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS secondary_muscles TEXT[];
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS is_custom BOOLEAN DEFAULT false;

-- Create index for gender filtering (fast lookups)
CREATE INDEX IF NOT EXISTS idx_exercises_gender ON exercises(gender);
CREATE INDEX IF NOT EXISTS idx_exercises_video_code ON exercises(video_code);
CREATE INDEX IF NOT EXISTS idx_exercises_name ON exercises(name);
CREATE INDEX IF NOT EXISTS idx_exercises_category ON exercises(category);

-- Verify columns exist
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'exercises'
ORDER BY ordinal_position;

