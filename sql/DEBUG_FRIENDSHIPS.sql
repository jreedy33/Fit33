-- =====================================================
-- DEBUG FRIENDSHIPS - Run this to see your friendship data
-- =====================================================

-- 1. Show friendships table columns and types
SELECT 
    column_name, 
    data_type,
    is_nullable
FROM information_schema.columns 
WHERE table_schema = 'public' AND table_name = 'friendships'
ORDER BY ordinal_position;

-- 2. Show ALL data in friendships table
SELECT * FROM friendships LIMIT 20;
