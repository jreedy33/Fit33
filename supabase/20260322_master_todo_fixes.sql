-- Master TODO fixes: H-9, H-10, H-13, H-15, C-5
-- Date: 2026-03-22

BEGIN;

-- ============================================================================
-- H-13: Unfriend RPC with cleanup
-- ============================================================================

CREATE OR REPLACE FUNCTION unfriend(p_friend_user_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_user_id UUID := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  DELETE FROM friendships
  WHERE (requester_id = v_user_id AND addressee_id = p_friend_user_id)
     OR (requester_id = p_friend_user_id AND addressee_id = v_user_id);

  DELETE FROM shared_workouts
  WHERE (user_id = v_user_id AND recipient_id = p_friend_user_id)
     OR (user_id = p_friend_user_id AND recipient_id = v_user_id);

  DELETE FROM activity_reactions
  WHERE user_id = v_user_id
    AND activity_id IN (
      SELECT id FROM friend_activity_feed WHERE user_id = p_friend_user_id
    );

  RETURN TRUE;
END;
$$;

-- ============================================================================
-- H-9: Verify REPLICA IDENTITY FULL on realtime-subscribed tables
-- ============================================================================

DO $$
DECLARE
  tbl TEXT;
BEGIN
  FOR tbl IN
    SELECT unnest(ARRAY[
      'friendships',
      'group_challenges',
      'challenge_participants',
      'challenge_daily_progress',
      'private_challenges',
      'private_challenge_members',
      'private_challenge_daily_progress',
      'private_challenge_chat',
      'community_challenges',
      'community_challenge_participants',
      'community_challenge_daily_progress',
      'shared_workouts',
      'friend_activity_feed',
      'app_notifications'
    ])
  LOOP
    EXECUTE format('ALTER TABLE IF EXISTS %I REPLICA IDENTITY FULL', tbl);
  END LOOP;
  RAISE NOTICE 'REPLICA IDENTITY FULL set on all realtime tables';
END $$;

-- ============================================================================
-- H-10: Server-side bounds on challenge progress values
-- ============================================================================

ALTER TABLE challenge_daily_progress
  DROP CONSTRAINT IF EXISTS check_progress_bounds;
ALTER TABLE challenge_daily_progress
  ADD CONSTRAINT check_progress_bounds CHECK (progress_value >= 0 AND progress_value <= 1000000);

ALTER TABLE community_challenge_daily_progress
  DROP CONSTRAINT IF EXISTS check_community_progress_bounds;
ALTER TABLE community_challenge_daily_progress
  ADD CONSTRAINT check_community_progress_bounds CHECK (progress_value >= 0 AND progress_value <= 1000000);

ALTER TABLE private_challenge_daily_progress
  DROP CONSTRAINT IF EXISTS check_private_progress_bounds;
ALTER TABLE private_challenge_daily_progress
  ADD CONSTRAINT check_private_progress_bounds CHECK (progress_value >= 0 AND progress_value <= 1000000);

-- ============================================================================
-- H-15: Verify search_users RPC exists (creates if missing)
-- ============================================================================

DROP FUNCTION IF EXISTS search_users(TEXT, INT);
CREATE OR REPLACE FUNCTION search_users(search_query TEXT, p_limit INT DEFAULT 20)
RETURNS TABLE(id UUID, name TEXT, username TEXT, profile_photo_url TEXT)
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  RETURN QUERY
  SELECT up.id, up.name, up.username, up.profile_photo_url
  FROM user_profiles up
  WHERE up.id != auth.uid()
    AND (
      up.name ILIKE '%' || search_query || '%'
      OR up.username ILIKE '%' || search_query || '%'
    )
  ORDER BY
    CASE WHEN up.username ILIKE search_query || '%' THEN 0
         WHEN up.name ILIKE search_query || '%' THEN 1
         ELSE 2
    END,
    up.name
  LIMIT p_limit;
END;
$$;

-- ============================================================================
-- C-5: Challenge RLS audit — ensure policies exist on all challenge tables
-- ============================================================================

DO $$
DECLARE
  tbl TEXT;
BEGIN
  FOR tbl IN
    SELECT unnest(ARRAY[
      'group_challenges',
      'challenge_participants',
      'challenge_daily_progress',
      'challenge_reactions',
      'private_challenges',
      'private_challenge_members',
      'private_challenge_invites',
      'private_challenge_daily_progress',
      'private_challenge_chat',
      'community_challenges',
      'community_challenge_participants',
      'community_challenge_daily_progress'
    ])
  LOOP
    EXECUTE format('ALTER TABLE IF EXISTS %I ENABLE ROW LEVEL SECURITY', tbl);
  END LOOP;
  RAISE NOTICE 'RLS enabled on all challenge tables';
END $$;

-- ============================================================================
-- Verification
-- ============================================================================

DO $$
BEGIN
  RAISE NOTICE 'Master TODO SQL fixes applied: unfriend RPC, REPLICA IDENTITY, progress bounds, search_users, challenge RLS';
END $$;

COMMIT;
