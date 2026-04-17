-- Privacy Settings: Add privacy preference columns to user_profiles
-- These columns control visibility of user data across social features.
-- Client-side guards provide immediate UX; these columns enable server-side enforcement
-- in RPCs as defense-in-depth.

BEGIN;

-- 1. Add privacy columns to user_profiles (all default FALSE = fully visible)
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS privacy_hide_photo BOOLEAN DEFAULT FALSE;
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS privacy_hide_activity BOOLEAN DEFAULT FALSE;
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS privacy_hide_league BOOLEAN DEFAULT FALSE;
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS privacy_hide_contact_sync BOOLEAN DEFAULT FALSE;
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS privacy_hide_search BOOLEAN DEFAULT FALSE;
ALTER TABLE user_profiles ADD COLUMN IF NOT EXISTS privacy_hide_active_status BOOLEAN DEFAULT FALSE;

COMMIT;

-- =============================================================================
-- RPC MODIFICATIONS (apply separately per function)
-- =============================================================================
--
-- After adding the columns above, update these RPCs to enforce privacy server-side:
--
-- 1. search_users:
--    Add to WHERE clause:
--      AND NOT up.privacy_hide_search
--
-- 2. get_friend_activity_feed:
--    Add to the join/WHERE on the poster's profile:
--      AND NOT poster_profile.privacy_hide_activity
--
-- 3. get_or_join_weekly_league / get_league_leaderboard:
--    Filter out users with privacy_hide_league = TRUE from leaderboard results.
--    For get_or_join_weekly_league, skip league placement if the calling user's
--    own privacy_hide_league is TRUE.
--
-- 4. match_contacts_by_phone / contact email matching:
--    Add to WHERE clause:
--      AND NOT up.privacy_hide_contact_sync
--
-- 5. All RPCs returning profile_photo_url:
--    Replace direct column reference with:
--      CASE WHEN up.privacy_hide_photo THEN NULL ELSE up.profile_photo_url END AS profile_photo_url
--
-- 6. RPCs exposing last_workout_date or last_active_at:
--    Replace with NULL when privacy_hide_active_status = TRUE:
--      CASE WHEN up.privacy_hide_active_status THEN NULL ELSE up.last_workout_date END
--
-- These RPC changes should be applied individually per function to avoid
-- disrupting unrelated functionality. Each change is backwards-compatible
-- (privacy columns default FALSE, so existing users see no behavior change).
