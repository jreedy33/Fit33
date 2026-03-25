-- Fix: unfriend RPC references wrong column names
-- shared_workouts uses sender_id (not user_id)
-- activity_reactions uses sender_id (not user_id)

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
  WHERE (sender_id = v_user_id AND recipient_id = p_friend_user_id)
     OR (sender_id = p_friend_user_id AND recipient_id = v_user_id);

  DELETE FROM activity_reactions
  WHERE sender_id = v_user_id
    AND activity_id IN (
      SELECT id FROM friend_activity_feed WHERE user_id = p_friend_user_id
    );

  RETURN TRUE;
END;
$$;
