-- =====================================================
-- FIX: Add DELETE policy for shared_workouts table
-- This allows users to delete workouts they sent OR received
-- =====================================================

-- Drop existing delete policy if any
DROP POLICY IF EXISTS "Users can delete own shared workouts" ON shared_workouts;
DROP POLICY IF EXISTS "Users can delete shared workouts" ON shared_workouts;

-- Create DELETE policy - users can delete workouts they sent OR received
-- Uses sender_id and recipient_id (the current column names in the table)
CREATE POLICY "Users can delete shared workouts" ON shared_workouts 
    FOR DELETE USING (
        auth.uid() = sender_id OR auth.uid() = recipient_id
    );

-- Verify the policy was created
SELECT 
    policyname, 
    cmd,
    qual
FROM pg_policies 
WHERE tablename = 'shared_workouts' 
AND policyname LIKE '%delete%';

-- Grant necessary permissions
GRANT DELETE ON shared_workouts TO authenticated;

-- Test message
SELECT 'DELETE policy for shared_workouts added successfully!' AS status;
