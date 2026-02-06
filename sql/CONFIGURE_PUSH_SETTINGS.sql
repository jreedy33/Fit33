-- =====================================================
-- CONFIGURE PUSH NOTIFICATION SETTINGS
-- =====================================================
-- Run this AFTER running FIX_PUSH_NOTIFICATIONS_RELIABLE.sql
-- 
-- Replace the values below with your actual Supabase project info:
-- - YOUR_PROJECT_REF: Your Supabase project reference (e.g., ehooeghabzefgoqzugrc)
-- - YOUR_SERVICE_ROLE_KEY: Your service role key from Supabase Dashboard > Settings > API
-- =====================================================

-- OPTION 1: Set as database configuration (recommended)
-- Replace 'ehooeghabzefgoqzugrc' with your actual project ref
-- Replace 'YOUR_SERVICE_ROLE_KEY' with your actual service role key

ALTER DATABASE postgres 
SET app.settings.edge_function_url = 'https://ehooeghabzefgoqzugrc.supabase.co/functions/v1/send-push-notification';

-- ⚠️ IMPORTANT: Replace this with your actual service role key
-- You can find it in: Supabase Dashboard > Settings > API > service_role key
-- ALTER DATABASE postgres SET app.settings.service_role_key = 'YOUR_SERVICE_ROLE_KEY';

-- =====================================================
-- VERIFICATION
-- =====================================================

-- Check if settings are configured
SELECT 
    current_setting('app.settings.edge_function_url', true) as edge_function_url,
    CASE 
        WHEN current_setting('app.settings.service_role_key', true) IS NOT NULL 
        AND current_setting('app.settings.service_role_key', true) != ''
        THEN '✅ CONFIGURED (hidden for security)'
        ELSE '❌ NOT CONFIGURED'
    END as service_role_key_status;

-- =====================================================
-- ALTERNATIVE: Set via Supabase Dashboard
-- =====================================================
/*
If you prefer not to put the service role key in SQL:

1. Go to Supabase Dashboard
2. Navigate to: Settings > Database > Configuration Parameters
3. Add these parameters:
   - app.settings.edge_function_url = https://YOUR_PROJECT.supabase.co/functions/v1/send-push-notification
   - app.settings.service_role_key = YOUR_SERVICE_ROLE_KEY

This is more secure as the key won't be in your SQL files.
*/

SELECT 'Configuration complete! Make sure to set your service_role_key.' AS status;
